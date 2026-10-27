#include "location_details_native.h"
#include "location_dance_native.h"
#include "location_value_native.h"
#include "modules/Maps.h"
#include "modules/Items.h"
#include "df/world.h"
#include "df/language_word_table.h"
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
#include <numeric>

namespace df3d_area {
std::optional<std::vector<LocationNameWord>> observeNativeLocationNameWords(uint8_t component,const std::string& queryCp437) {
  if(component>6 || !df::global::world || !DFHack::Maps::IsValid())return std::nullopt;
  // Native name-editor initialization calls this semantic selector builder,
  // passing all raw word IDs. It reads raw language words and writes only the
  // supplied vectors; its two callees are vector insertion/allocation helpers.
  // No name_creator object, menu, filter, cursor or cached choices are borrowed.
  static const bool compatible=[] {
    if(!locationRefreshFunction())return false;
    auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    const auto hash=[&](size_t rva,size_t size) {
      uint64_t h=UINT64_C(14695981039346656037);
      for(size_t i=0;i<size;++i){h^=base[rva+i];h*=UINT64_C(1099511628211);}return h;
    };
    return hash(0xd35530,0x9a4)==UINT64_C(0x77bd9190661f5681) &&
        hash(0xd2cb50,0xf0)==UINT64_C(0xf7ab8eceaadda09f) &&
        hash(0x52cee0,0x19e)==UINT64_C(0xc25c2d8a6eb9fcac) &&
        hash(0x1fc330,0x28c)==UINT64_C(0xc8d8335c19ae0818);
  }();
  if(!compatible)return std::nullopt;
  const auto& words=df::global::world->raws.language.words;
  if(words.size()>size_t(INT32_MAX) || std::any_of(words.begin(),words.end(),[](auto* v){return v==nullptr;}))return std::nullopt;
  std::vector<int32_t> ids(words.size());std::iota(ids.begin(),ids.end(),0);
  df::language_word_table table;
  static_assert(sizeof(table)==0x120);
  using Build=void(__fastcall*)(df::language_word_table*,std::vector<int32_t>*);
  const auto build=reinterpret_cast<Build>(reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr))+0xd35530);
  build(&table,&ids);
  const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
  using Form=void(__fastcall*)(void*,int32_t,std::string*,int32_t,int32_t);
  using Lower=void(__fastcall*)(std::string*);
  const auto form=reinterpret_cast<Form>(base+0xd2cb50);
  const auto lower=reinterpret_cast<Lower>(base+0x52cee0);
  std::string query=queryCp437;lower(&query);
  // Audited name component -> semantic selector table mapping at1fc387..1fc3b8.
  constexpr int slots[]={0,1,3,3,4,2,5};
  const auto slot=static_cast<df::language_word_table_index>(slots[component]);
  const auto& selected=table.words[slot];const auto& parts=table.parts[slot];
  if(selected.size()!=parts.size())return std::nullopt;
  std::vector<LocationNameWord> result;result.reserve(selected.size());
  for(size_t i=0;i<selected.size();++i) {
    if(selected[i]<0 || size_t(selected[i])>=words.size() || int(parts[i])<0 || int(parts[i])>8)return std::nullopt;
    std::string english;form(nullptr,selected[i],&english,0,int32_t(parts[i]));
    // Native1fc330 has no independent filter helper: it normalizes an owned
    // query with52cee0 and retains substring matches in native English forms.
    // Reproduce that audited string operation without a name_creator object.
    if(!query.empty() && english.find(query)==std::string::npos)continue;
    result.push_back({selected[i],int32_t(parts[i]),DF2UTF(english)});
  }
  return result;
}
std::optional<LocationNameWord> chooseNativeLocationNameWord(uint8_t displayedComponent,const std::string& queryCp437) {
  const auto choices=observeNativeLocationNameWords(displayedComponent,queryCp437);
  if(!choices || choices->empty())return std::nullopt;
  static const bool compatible=[] {
    auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    uint64_t h=UINT64_C(14695981039346656037);
    for(size_t i=0;i<0x163;++i){h^=base[0xd35ee0+i];h*=UINT64_C(1099511628211);}
    return h==UINT64_C(0xc1e4fe91eb73c848);
  }();
  if(!compatible)return std::nullopt;
  df::language_word_table table;
  const auto slot=static_cast<df::language_word_table_index>(0);
  for(const auto& choice:*choices) {
    table.words[slot].push_back(choice.word);
    table.parts[slot].push_back(static_cast<df::part_of_speech>(choice.partOfSpeech));
  }
  // Native nonempty selector uses the same eb68b0 RNG/bucket calculation as
  // name-editor Random1ff79c..1ff82b. Own both vectors and outputs; the helper's
  // empty-table fallback is intentionally unreachable. A singleton draws no RNG.
  using Choose=void(__fastcall*)(df::language_word_table*,int32_t*,int16_t*,int32_t);
  const auto choose=reinterpret_cast<Choose>(reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr))+0xd35ee0);
  int32_t word=-1;int16_t part=-1;choose(&table,&word,&part,0);
  const auto found=std::find_if(choices->begin(),choices->end(),[&](const auto& row) {
    return row.word==word && row.partOfSpeech==part;
  });
  if(found==choices->end())return std::nullopt;
  return *found;
}
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
LocationAccessOutcome editNativeLocationQuantity(int32_t siteId,int32_t id,
    uint64_t expectedRevision,uint8_t quantity,LocationQuantityEdit edit,int32_t value) {
  // Native writes are inline in the input handlers, not a callable semantic
  // routine. Pin those instructions; never call/borrow the global number editor.
  static const bool compatible=[] {
    if(!locationRefreshFunction())return false; // Supported PE/layout identity.
    auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    const auto hash=[&](size_t rva,size_t count) {
      uint64_t h=UINT64_C(14695981039346656037);
      for(size_t i=0;i<count;++i){h^=base[rva+i];h*=UINT64_C(1099511628211);}return h;
    };
    return hash(0x311c10,0x4d664)==UINT64_C(0x0bb5d255b4bd6863) &&
        hash(0x8baa33,0x121)==UINT64_C(0x0aff370e58e7681f);
  }();
  if(!compatible || !expectedRevision || expectedRevision>uint64_t(INT64_MAX) || quantity>10 ||
      static_cast<uint8_t>(edit)>2 || (edit==LocationQuantityEdit::Set ? value<0 || value>999 : value!=0))
    return LocationAccessOutcome::Rejected;
  const auto observed=observeNativeLocationDetailsCore(siteId,id);
  if(!observed)return LocationAccessOutcome::Rejected;
  const auto kind=observed->kind;
  const bool offered=(kind==1 && (quantity==0 || quantity==1)) || (kind==2 && quantity==1) ||
      (kind==3 && (quantity==2 || quantity==10)) || (kind==5 && quantity>=3 && quantity<=9);
  if(!offered)return LocationAccessOutcome::Rejected;
  if(locationDetailsRevision(*observed)!=expectedRevision)return LocationAccessOutcome::Stale;
  auto* site=df::world_site::find(siteId);
  if(!site)return LocationAccessOutcome::Rejected;
  const auto found=std::lower_bound(site->buildings.begin(),site->buildings.end(),id,
      [](const df::abstract_building* location,int32_t key){return location->id<key;});
  if(found==site->buildings.end() || (*found)->id!=id)return LocationAccessOutcome::Rejected;
  auto* c=(*found)->getContents();if(!c)return LocationAccessOutcome::Rejected;
  int32_t* fields[]={&c->desired_goblets,&c->desired_instruments,&c->desired_paper,&c->desired_splints,
      &c->desired_thread,&c->desired_cloth,&c->desired_crutches,&c->desired_powder,
      &c->desired_buckets,&c->desired_soap,&c->desired_copies};
  static_assert(offsetof(df::abstract_building_contents,desired_goblets)==8);
  static_assert(offsetof(df::abstract_building_contents,desired_copies)==48);
  const int32_t scale=quantity==4?15000:quantity==5?10000:(quantity==7 || quantity==9)?150:1;
  auto& target=*fields[quantity];
  // Native checks the bound BEFORE adding/subtracting one raw unit. Preserve
  // partial raw quantities, including a step across the bound; do not clamp.
  if(edit==LocationQuantityEdit::Set)target=value*scale;
  else if(edit==LocationQuantityEdit::Increase && target<999*scale)target+=scale;
  else if(edit==LocationQuantityEdit::Decrease && target>0)target-=scale;
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
