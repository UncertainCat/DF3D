#include "location_details_native.h"
#include "location_dance_native.h"
#include "location_value_native.h"
#include "modules/Maps.h"
#include "modules/Items.h"
#include "df/world.h"
#include "df/item.h"
#include "df/items_other_id.h"
#include "modules/Translation.h"
#include "modules/Units.h"
#include "df/historical_entity.h"
#include "df/historical_figure.h"
#include "df/entity_position_assignment.h"
#include "df/entity_position_responsibility.h"
#include "df/unit.h"
#include "df/job_skill.h"
#include "df/building.h"
#include "df/building_civzonest.h"
#include "df/building_type.h"
#include "df/civzone_type.h"
#include "MiscUtils.h"
#include "df/abstract_building.h"
#include "df/abstract_building_contents.h"
#include "df/plotinfost.h"
#include "df/world_site.h"
#include <algorithm>

namespace df3d_area {
std::optional<LocationDetailsCore> observeNativeLocationDetailsCore(int32_t siteId,int32_t id) {
  if(siteId<0 || id<0 || !df::global::plotinfo || !DFHack::Maps::IsValid() ||
      siteId!=df::global::plotinfo->site_id)return std::nullopt;
  auto* site=df::world_site::find(siteId);
  if(!site)return std::nullopt;
  auto found=std::lower_bound(site->buildings.begin(),site->buildings.end(),id,
      [](const df::abstract_building* location,int32_t key){return location->id<key;});
  if(found==site->buildings.end() || (*found)->id!=id)return std::nullopt;
  auto* location=*found;
  if(location->flags.is_set(df::abstract_building_flags::DOES_NOT_EXIST) ||
      location->flags.is_set(df::abstract_building_flags::WG_RUINED) ||
      location->flags.is_set(df::abstract_building_flags::PWG_RUINED))return std::nullopt;
  LocationDetailsCore result;result.siteId=siteId;result.id=id;
  switch(location->getType()) {
    case df::abstract_building_type::INN_TAVERN:result.kind=1;break;
    case df::abstract_building_type::TEMPLE:result.kind=2;break;
    case df::abstract_building_type::LIBRARY:result.kind=3;break;
    case df::abstract_building_type::GUILDHALL:result.kind=4;break;
    case df::abstract_building_type::HOSPITAL:result.kind=5;break;
    default:return std::nullopt;
  }
  const auto* contents=location->getContents();
  if(!contents)return std::nullopt;
  auto name=DFHack::Translation::translateName(location->getName(),true);
  if(!name.empty())name[0]=toupper_cp437(name[0]);
  result.name=DF2UTF(name);
  result.accessFlags={location->flags.is_set(df::abstract_building_flags::VISITORS_ALLOWED),
      location->flags.is_set(df::abstract_building_flags::NON_CITIZENS_ALLOWED),
      location->flags.is_set(df::abstract_building_flags::MEMBERS_ONLY)};
  result.access=locationAccess(result.accessFlags);
  result.profession=int32_t(contents->profession);result.tier=contents->location_tier;
  result.value=contents->location_value;result.desiredCopies=contents->desired_copies;
  result.recognized=contents->need_more.bits.entity_recognized;
  // Native165005 resolves TRADE assignments in reverse order, skipping missing
  // historical figures/units. No citizenship or activity filter in this lookup.
  result.appraisal=-1;
  if(const auto* entity=df::global::plotinfo->main.fortress_entity) {
    const auto& assignments=entity->assignments_by_type[df::entity_position_responsibility::TRADE];
    for(auto it=assignments.rbegin();it!=assignments.rend();++it) {
      if(!*it)continue;
      auto* figure=df::historical_figure::find((*it)->histfig);
      auto* unit=figure?df::unit::find(figure->unit_id):nullptr;
      if(!unit)continue;
      result.appraisal=std::max(0,DFHack::Units::getEffectiveSkill(unit,df::job_skill::APPRAISAL));
      break;
    }
  }
  // Preserve native internal units. Presentation conversion is separately
  // evidenced by155506; exposing raw value does not establish visibility.
  result.supplies={{{contents->count_goblets,contents->desired_goblets},
      {contents->count_instruments,contents->desired_instruments},
      {contents->count_paper,contents->desired_paper},
      {contents->count_splints,contents->desired_splints},
      {contents->count_thread,contents->desired_thread},
      {contents->count_cloth,contents->desired_cloth},
      {contents->count_crutches,contents->desired_crutches},
      {contents->count_powder,contents->desired_powder},
      {contents->count_buckets,contents->desired_buckets},
      {contents->count_soap,contents->desired_soap}}};
  result.zoneIds.assign(contents->building_ids.begin(),contents->building_ids.end());
  // Native170942: membership order/multiplicity is authoritative. Only Bedroom
  // zones are excluded from common furniture; stage/flags/ownership do not filter.
  int64_t counts[8]={};
  for(auto id:contents->building_ids) {
    auto* building=df::building::find(id);
    if(!building || building->getType()!=df::building_type::Civzone)continue;
    auto* zone=static_cast<df::building_civzonest*>(building);
    if(zone->type==df::civzone_type::Bedroom) {
      ++counts[6];if(zone->assigned_unit_id!=-1)++counts[7];continue;
    }
    for(auto* furniture:zone->contained_buildings) {
      if(!furniture)return std::nullopt; // No fabricated zero for a corrupt pointer.
      switch(furniture->getType()) {
        case df::building_type::Box:++counts[0];break;
        case df::building_type::Bed:++counts[1];break;
        case df::building_type::Table:++counts[2];break;
        case df::building_type::TractionBench:++counts[3];break;
        case df::building_type::Bookcase:++counts[4];break;
        case df::building_type::Chair:++counts[5];break;
        default:break;
      }
    }
  }
  for(auto count:counts)if(count>INT32_MAX)return std::nullopt;
  result.facilities={int32_t(counts[0]),int32_t(counts[1]),int32_t(counts[2]),int32_t(counts[3]),
      int32_t(counts[4]),int32_t(counts[5]),int32_t(counts[6]),int32_t(counts[7])};

  // Native173749: BOOK entries count even without writing; TOOL entries require
  // writing. Use effective item position (including carried/container contents),
  // non-Bedroom painted footprints, and count each vector occurrence once across
  // overlapping/repeated zones. Stack size and other item/zone flags do not filter.
  int64_t written=0;
  for(auto kind:{df::items_other_id::BOOK,df::items_other_id::TOOL}) {
    for(auto* item:df::global::world->items.other[kind]) {
      if(!item)return std::nullopt;
      if(kind==df::items_other_id::TOOL && !item->hasWriting())continue;
      const auto pos=DFHack::Items::getPosition(item);
      if(!pos.isValid())continue;
      for(auto id:contents->building_ids) {
        auto* building=df::building::find(id);
        if(!building || building->getType()!=df::building_type::Civzone)continue;
        const auto* zone=static_cast<df::building_civzonest*>(building);
        // Native175331: require room extents; building bounds are not inputs.
        if(zone->type==df::civzone_type::Bedroom || pos.z!=zone->z || !zone->room.extents)continue;
        const int64_t x=int64_t(pos.x)-zone->room.x,y=int64_t(pos.y)-zone->room.y;
        if(x<0 || y<0 || x>=zone->room.width || y>=zone->room.height ||
            !int(zone->room.extents[y*zone->room.width+x]))continue;
        ++written;break;
      }
    }
  }
  if(written>INT32_MAX)return std::nullopt;
  result.writtenObjects=int32_t(written);
  const auto dance=locationDanceFunction();
  if(!dance)return std::nullopt;
  result.danceFloorX=0;result.danceFloorY=0;
  int bestRank=-1;
  for(auto id:contents->building_ids) {
    auto* building=df::building::find(id);
    if(!building || building->getSubtype()==int(df::civzone_type::Bedroom) || !building->room.extents)continue;
    const auto& room=building->room;
    if(room.width<=0 || room.height<=0)continue;
    // Geometry/storage guard; never truncate a native footprint.
    if(int64_t(room.width)*room.height>32768)return std::nullopt;
    int32_t x=0,y=0;
    dance(room.extents,room.x,room.y,building->z,room.width,room.height,&x,&y);
    if(x<0 || y<0 || x>room.width || y>room.height)return std::nullopt;
    // Native3ad230 chooses tier first, then area; exact ties keep membership order.
    const int rank=std::clamp(std::min(x,y)-4,0,4);
    if(rank>bestRank || (rank==bestRank && int64_t(x)*y>int64_t(result.danceFloorX)*result.danceFloorY)) {
      bestRank=rank;result.danceFloorX=x;result.danceFloorY=y;
    }
  }
  if(result.kind==2 || result.kind==4) {
    result.affiliation=observeNativeLocationAffiliation(siteId,id);
    if(!result.affiliation)return std::nullopt;
  }
  result.staff=observeNativeLocationStaff(siteId,id);
  if(!result.staff)return std::nullopt;
  return result;
}
LocationAccessOutcome setNativeLocationAccess(int32_t siteId,int32_t id,
    uint64_t expectedRevision,LocationAccess mode) {
  if(!expectedRevision || expectedRevision>uint64_t(INT64_MAX))return LocationAccessOutcome::Rejected;
  const auto observed=observeNativeLocationDetailsCore(siteId,id);
  if(!observed)return LocationAccessOutcome::Rejected;
  const auto selected=locationAccessSelection(observed->kind,mode);
  if(!selected)return LocationAccessOutcome::Rejected;
  if(locationDetailsRevision(*observed)!=expectedRevision)return LocationAccessOutcome::Stale;
  auto* site=df::world_site::find(siteId);
  if(!site)return LocationAccessOutcome::Rejected;
  const auto found=std::lower_bound(site->buildings.begin(),site->buildings.end(),id,
      [](const df::abstract_building* location,int32_t key){return location->id<key;});
  if(found==site->buildings.end() || (*found)->id!=id)return LocationAccessOutcome::Rejected;
  auto& flags=(*found)->flags;
  flags.set(df::abstract_building_flags::VISITORS_ALLOWED,selected->visitors);
  flags.set(df::abstract_building_flags::NON_CITIZENS_ALLOWED,selected->residents);
  flags.set(df::abstract_building_flags::MEMBERS_ONLY,selected->members);
  return LocationAccessOutcome::Completed;
}
bool refreshNativeLocationDetailsCaches(int32_t siteId,int32_t id) {
  // Preflight all existing identity/availability/geometry guards before cache writes.
  // No pointers outlive this safe point; no native viewscreen state is involved.
  if(!observeNativeLocationDetailsCore(siteId,id))return false;
  const auto refresh=locationRefreshFunction();
  if(!refresh)return false;
  auto* site=df::world_site::find(siteId);
  if(!site)return false;
  const auto found=std::lower_bound(site->buildings.begin(),site->buildings.end(),id,
      [](const df::abstract_building* location,int32_t key){return location->id<key;});
  if(found==site->buildings.end() || (*found)->id!=id)return false;
  auto* contents=(*found)->getContents();
  if(!contents)return false;
  // Native181042: refresh on entry/reentry only, retaining requested quantities
  // and recognition. Native initializer resets these scheduler fields afterward.
  refresh(contents,id,true);
  contents->update_timer=100;contents->update_count=0;
  return true;
}

}
