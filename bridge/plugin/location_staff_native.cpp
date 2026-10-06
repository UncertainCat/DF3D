#include "location_staff_native.h"
#include "location_staff_order_native.h"
#include "location_staff_mutation_native.h"
#include "modules/Maps.h"
#include "modules/Units.h"
#include "modules/Translation.h"
#include "df/unit.h"
#include "df/unit_soul.h"
#include "df/unit_skill.h"
#include "df/caste_raw_flags.h"
#include "df/caste_raw.h"
#include "df/creature_raw.h"
#include "df/mood_type.h"
#include "df/historical_figure.h"
#include "MiscUtils.h"
#include "df/abstract_building.h"
#include "df/abstract_building_templest.h"
#include "df/religious_practice_type.h"
#include "df/historical_entity.h"
#include "df/entity_position.h"
#include "df/entity_position_assignment.h"
#include "df/occupation.h"
#include "df/occupation_type.h"
#include "df/plotinfost.h"
#include "df/world.h"
#include "df/world_site.h"
#include <algorithm>
#include <memory>
#include <exception>

namespace df3d_area {
namespace {
df::abstract_building* location(int32_t siteId,int32_t id) {
  if(siteId<0 || id<0 || !df::global::plotinfo || !DFHack::Maps::IsValid() ||
      siteId!=df::global::plotinfo->site_id)return nullptr;
  auto* site=df::world_site::find(siteId);if(!site)return nullptr;
  auto it=std::lower_bound(site->buildings.begin(),site->buildings.end(),id,
      [](const df::abstract_building* p,int32_t key){return p->id<key;});
  if(it==site->buildings.end() || (*it)->id!=id)return nullptr;
  auto* value=*it;
  if(value->flags.is_set(df::abstract_building_flags::DOES_NOT_EXIST) ||
      value->flags.is_set(df::abstract_building_flags::WG_RUINED) ||
      value->flags.is_set(df::abstract_building_flags::PWG_RUINED))return nullptr;
  switch(value->getType()) {
    case df::abstract_building_type::INN_TAVERN:case df::abstract_building_type::TEMPLE:
    case df::abstract_building_type::LIBRARY:case df::abstract_building_type::HOSPITAL:
    case df::abstract_building_type::GUILDHALL:return value;
    default:return nullptr;
  }
}
std::vector<int32_t> roles(df::abstract_building* value) {
  switch(value->getType()) {
    case df::abstract_building_type::INN_TAVERN:return {0,1};
    case df::abstract_building_type::TEMPLE:return {1};
    case df::abstract_building_type::LIBRARY:return {2,5};
    case df::abstract_building_type::HOSPITAL:return {7,8,9,10};
    default:return {};
  }
}
std::string readableStaffName(df::unit* unit) {
  auto result=DFHack::Units::getReadableName(unit,true);
  const auto profession=DFHack::Units::getProfession(unit);
  // Native selector survey20260930-011033: these two pinned DFHack enum
  // captions differ from the supported game's fallback profession labels.
  // Custom, noble, caste/raw and undead names are authored game data, not
  // fallback captions; never rewrite their spelling even when it matches.
  const char* previous=nullptr;const char* native=nullptr;
  if(profession==df::profession::DIAGNOSER) {previous="Diagnoser";native="Diagnostician";}
  else if(profession==df::profession::MASTER_SWORDSMAN) {previous="Swordsmaster";native="Swordmaster";}
  else return result;
  if(!unit->custom_profession.empty() || unit->enemy.undead)return result;
  std::vector<DFHack::Units::NoblePosition> positions;
  if(DFHack::Units::getNoblePositions(&positions,unit) && !positions.empty())return result;
  const auto* creature=df::creature_raw::find(unit->race);
  if(!creature || unit->caste<0 || size_t(unit->caste)>=creature->caste.size())return result;
  const auto* caste=creature->caste[unit->caste];
  if(!caste || !caste->caste_profession_name.singular[profession].empty() ||
      !creature->profession_name.singular[profession].empty())return result;
  const std::string suffix=previous;
  if(result.size()>=suffix.size() && result.compare(result.size()-suffix.size(),suffix.size(),suffix)==0)
    result.replace(result.size()-suffix.size(),suffix.size(),native);
  return result;
}
bool staffCandidateProfession(df::profession profession) {
  // Protected135-profession survey20260930-011033. Native excludes professions
  // that cannot receive labors, plus merchants, trained animals and thieves.
  // Citizenship/group membership alone does not exclude these special roles.
  if(!DFHack::is_valid_enum_item(profession) || profession==df::profession::NONE ||
      !ENUM_ATTR(profession,can_assign_labor,profession))return false;
  switch(profession) {
    case df::profession::MERCHANT:case df::profession::TRAINED_HUNTER:
    case df::profession::TRAINED_WAR:case df::profession::MASTER_THIEF:
    case df::profession::THIEF:return false;
    default:return true;
  }
}
LocationStaffNames names(int32_t unitId,int32_t histfigId) {
  LocationStaffNames result;
  // Native191420: a resolvable unit wins. Historical fallback has no profession.
  if(auto* unit=df::unit::find(unitId)) {
    result.holderKind=1;result.holderId=unit->id;
    result.holderName=DF2UTF(readableStaffName(unit));
  } else if(auto* figure=df::historical_figure::find(histfigId)) {
    result.holderKind=2;result.holderId=figure->id;
    result.holderName=DF2UTF(DFHack::Translation::translateName(&figure->name));
  }
  return result;
}
LocationStaffRow row(const df::occupation* value) {
  LocationStaffRow out;out.occupationId=value->id;out.role=int32_t(value->type);
  out.histfigId=value->histfig_id;out.unitId=value->unit_id;out.locationId=value->location_id;
  out.siteId=value->site_id;out.groupId=value->group_id;out.names=names(value->unit_id,value->histfig_id);return out;
}
}
std::optional<LocationStaffCandidates> observeNativeLocationStaffCandidates(
    int32_t siteId,int32_t locationId,int32_t occupationId) {
  auto* value=location(siteId,locationId);
  if(!value || !df::global::world)return std::nullopt;
  const df::occupation* selected=nullptr;
  for(const auto* occupation:value->occupations)
    if(occupation && occupation->id==occupationId) {selected=occupation;break;}
  if(!selected || selected->site_id!=siteId || selected->location_id!=locationId)return std::nullopt;
  const int32_t role=int32_t(selected->type);
  // Native233647 widget skill configuration; numbers are pinned job_skill IDs.
  std::vector<std::pair<int32_t,int32_t>> weights;
  switch(role) {
    case 0: weights={{70,1},{71,1},{72,1},{76,1},{77,1},{78,1},{79,1},{80,1},{81,1},{82,1}};break;
    case 1: weights={{92,2},{116,2},{117,2},{118,2},{119,1},{120,1},{121,1},{122,1}};break;
    case 2: weights={{54,1},{58,1},{87,1},{123,3},{124,2},{125,2},{126,2},{127,2},{128,2}};break;
    case 5: weights={{88,1},{91,1}};break;
    case 7: weights={{58,5},{59,4},{60,4}};break;
    case 8: weights={{58,1}};break;
    case 9: weights={{59,1}};break;
    case 10: weights={{60,1}};break;
    default:return std::nullopt;
  }
  // Native234933, 47 independent controls: use cached creature flags and
  // fortress membership. isCitizen/isFortControlled conflate checks whose
  // tame exceptions and raw-vs-cached behavior differ from this selector.
  constexpr uint32_t foreign1=df::unit_flags1::mask_marauder | df::unit_flags1::mask_active_invader |
      df::unit_flags1::mask_invader_origin | df::unit_flags1::mask_merchant |
      df::unit_flags1::mask_diplomat | df::unit_flags1::mask_forest;
  constexpr uint32_t foreign2=df::unit_flags2::mask_visitor | df::unit_flags2::mask_visitor_uninvited |
      df::unit_flags2::mask_resident | df::unit_flags2::mask_underworld;
  LocationStaffCandidates out;out.role=role;
  const auto bind=[&](int32_t owner,const df::occupation* held) {
    out.assignmentBindings.push_back({owner,held->id,int32_t(held->type),held->histfig_id,
      held->unit_id,held->location_id,held->site_id,held->group_id});
  };
  bind(-1,selected);
  if(auto* holder=df::unit::find(selected->unit_id)) {
    bind(holder->id,selected); // Bind resolved-holder presence even with no linked occupations.
    for(const auto* held:holder->occupations) {if(!held)return std::nullopt;bind(holder->id,held);}
  }
  const auto& order=staffOrderingFunctions();
  if(!order)return std::nullopt;
  for(auto* unit:df::global::world->units.active) {
    if(!unit || !staffCandidateProfession(unit->profession) ||
        !DFHack::Units::isActive(unit) || !DFHack::Units::isAdult(unit) ||
        !DFHack::Units::isOwnGroup(unit) || (unit->flags1.whole & foreign1) ||
        (!unit->flags1.bits.tame && ((unit->flags2.whole & foreign2) ||
                                   unit->civ_id!=df::global::plotinfo->civ_id ||
                                   unit->flags4.bits.agitated_wilderness_creature)) ||
        unit->mood==df::mood_type::Berserk || unit->flags3.bits.ghostly || unit->enemy.undead ||
        unit->enemy.caste_flags.is_set(df::caste_raw_flags::CRAZED) ||
        unit->enemy.caste_flags.is_set(df::caste_raw_flags::OPPOSED_TO_LIFE))continue;
    // Native234005 checks the worker's links, not the location/global vector or
    // the linked occupation's holder ID. Site is part of this identity.
    bool assigned=false;
    for(const auto* held:unit->occupations)
      if(held && held->site_id==siteId && held->location_id==locationId && int32_t(held->type)==role)
        {assigned=true;break;}
    if(assigned)continue;
    for(const auto* held:unit->occupations) {if(!held)return std::nullopt;bind(unit->id,held);}
    LocationStaffCandidate row;row.unitId=unit->id;row.histfigId=unit->hist_figure_id;
    row.sourceIndex=int32_t(out.rows.size());
    std::string nameKey,professionKey;
    order.name(unit,&nameKey,false);order.profession(unit,&professionKey,false);
    order.normalize(&nameKey);order.normalize(&professionKey);
    row.nameSortKey.assign(nameKey.begin(),nameKey.end());
    row.professionSortKey.assign(professionKey.begin(),professionKey.end());
    std::array<int32_t,2> category{};const StaffUnitReference reference{unit};
    order.category(&category,&reference);
    row.professionOrder=category[0];row.statusOrder=category[1];
    const auto baseName=DFHack::Translation::translateName(DFHack::Units::getVisibleName(unit));
    const auto readable=readableStaffName(unit);
    row.name=DF2UTF(readable);row.baseName=DF2UTF(baseName);
    if(baseName.empty())row.professionName=row.name;
    else if(readable==baseName)row.professionName.clear();
    else if(readable.compare(0,baseName.size()+2,baseName+", ")==0)
      row.professionName=DF2UTF(readable.substr(baseName.size()+2));
    else return std::nullopt; // Never invent a split for unrecognized native facts.
    row.professionColor=DFHack::Units::getProfessionColor(unit);
    if(const auto* soul=unit->status.current_soul)for(const auto* skill:soul->skills) {
      if(!skill)continue;
      // Name animation depends on every skill, not just this occupation's list.
      row.legendary=row.legendary || skill->rating>=15;
      for(const auto& weight:weights)if(int32_t(skill->id)==weight.first) {
        row.skills.push_back({weight.first,int32_t(skill->rating),skill->experience,weight.second});
        row.score+=weight.second*int32_t(skill->rating);break;
      }
    }
    out.rows.push_back(std::move(row));
  }
  std::stable_sort(out.rows.begin(),out.rows.end(),[](const auto& a,const auto& b){return a.score>b.score;});
  return out;
}
std::optional<LocationStaffSnapshot> observeNativeLocationStaff(int32_t siteId,int32_t id) {
  auto* value=location(siteId,id);if(!value)return std::nullopt;
  LocationStaffSnapshot out;
  // Native182358: religion assignments require current site and a resolvable
  // position. Location assignment and holder validity do not filter these rows.
  if(value->getType()==df::abstract_building_type::TEMPLE) {
    const auto* temple=static_cast<df::abstract_building_templest*>(value);
    if(temple->deity_type==df::religious_practice_type::RELIGION_ENID) {
      if(const auto* entity=df::historical_entity::find(temple->deity_data.Religion)) {
        for(const auto* assignment:entity->positions.assignments) {
          if(!assignment)return std::nullopt;
          if(assignment->st_id!=siteId)continue;
          const auto* position=binsearch_in_vector(entity->positions.own,assignment->position_id);
          if(!position)continue;
          LocationStaffRow r;r.source=LocationStaffSource::ReligiousPosition;
          r.entityId=entity->id;r.positionId=position->id;r.assignmentId=assignment->id;
          r.histfigId=assignment->histfig;r.siteId=siteId;r.locationId=id;
          const auto* holder=df::historical_figure::find(assignment->histfig);
          r.names=names(holder?holder->unit_id:-1,assignment->histfig);
          // Native190932: neutral position name, independent of holder sex.
          r.names->positionName=DF2UTF(DFHack::Translation::capitalize(position->name[0],true));
          out.rows.push_back(r);
        }
      }
    }
  }
  // Native182139: preserve assigned occurrence order; either holder sentinel
  // differing from -1 means assigned, even when its target no longer resolves.
  for(auto role:roles(value)) {
    const df::occupation* empty=nullptr;
    for(const auto* occupation:value->occupations) {
      if(!occupation)return std::nullopt;
      if(int32_t(occupation->type)!=role || occupation->site_id!=siteId || occupation->location_id!=id)continue;
      if(occupation->histfig_id==-1 && occupation->unit_id==-1) {
        if(!empty)empty=occupation;
      } else out.rows.push_back(row(occupation));
    }
    if(empty)out.rows.push_back(row(empty));else out.missingRoles.push_back(role);
  }
  return out;
}
bool prepareNativeLocationStaff(int32_t siteId,int32_t id) {
  const auto before=observeNativeLocationStaff(siteId,id);if(!before)return false;
  if(before->missingRoles.empty())return true;
  auto* value=location(siteId,id);
  if(!value || !df::global::world || !df::global::occupation_next_id)return false;
  const int64_t first=*df::global::occupation_next_id;
  if(first<0 || first+int64_t(before->missingRoles.size())>INT32_MAX)return false;
  auto& all=df::global::world->occupations.all;
  for(auto* occupation:all)if(!occupation)return false;
  try {
    auto nextAll=all;auto nextLocal=value->occupations;
    std::vector<std::unique_ptr<df::occupation>> pending;
    pending.reserve(before->missingRoles.size());
    for(auto role:before->missingRoles) {
      const int32_t nextId=int32_t(first+pending.size());
      const auto where=std::lower_bound(nextAll.begin(),nextAll.end(),nextId,
          [](const df::occupation* p,int32_t key){return p->id<key;});
      if(where!=nextAll.end() && (*where)->id==nextId)return false;
      std::unique_ptr<df::occupation> added(df::allocate<df::occupation>());
      if(!added)return false;
      added->id=nextId;added->type=df::occupation_type(role);
      added->histfig_id=-1;added->unit_id=-1;added->location_id=id;added->site_id=siteId;
      added->group_id=-1;added->next_service_order_id=0;added->wg_site=nullptr;added->wg_ab=nullptr;
      nextAll.insert(where,added.get());nextLocal.push_back(added.get());pending.push_back(std::move(added));
    }
    // Every allocation/vector edit succeeded before any game-owned publication.
    all.swap(nextAll);value->occupations.swap(nextLocal);
    *df::global::occupation_next_id=int32_t(first+pending.size());
    for(auto& added:pending)added.release();
    return true;
  } catch(const std::exception&) {return false;}
}
LocationStaffEditOutcome editNativeLocationStaff(int32_t siteId,int32_t locationId,
                                                int32_t occupationId,int32_t unitId) {
  const auto& native=staffMutationFunctions();
  if(!native)return LocationStaffEditOutcome::Unavailable;
  auto* place=location(siteId,locationId);
  if(!place || unitId< -1)return LocationStaffEditOutcome::Rejected;
  df::occupation* target=nullptr;
  for(auto* held:place->occupations)if(held && held->id==occupationId){target=held;break;}
  if(!target || target->site_id!=siteId || target->location_id!=locationId)return LocationStaffEditOutcome::Rejected;
  auto* chosen=unitId>=0?df::unit::find(unitId):nullptr;
  if(unitId>=0) {
    const auto eligible=observeNativeLocationStaffCandidates(siteId,locationId,occupationId);
    if(!chosen || !eligible || std::none_of(eligible->rows.begin(),eligible->rows.end(),
        [&](const auto& row){return row.unitId==unitId;}))return LocationStaffEditOutcome::Rejected;
    for(const auto* held:chosen->occupations)
      if(!held || df::occupation::find(held->id)!=held)return LocationStaffEditOutcome::Rejected;
    try {chosen->occupations.reserve(std::max<size_t>(1,chosen->occupations.size()));}
    catch(const std::exception&){return LocationStaffEditOutcome::Unavailable;}
  } else if(target->unit_id==-1 && target->histfig_id==-1)return LocationStaffEditOutcome::Rejected;
  const auto profession=[&](df::unit* unit) {
    // Native selection/removal deliberately suppress profession announcements.
    unit->flags2.bits.no_notify=true;
    native.profession(unit,false);
    unit->flags2.bits.no_notify=false;
  };
  try {
    if(auto* previous=df::unit::find(target->unit_id)) {
      auto& held=previous->occupations;
      held.erase(std::remove(held.begin(),held.end(),target),held.end());
      profession(previous);
      // Removal intentionally retains labors; replacing a holder recomputes them.
      if(chosen)native.labors(previous);
    }
    if(chosen) {
      for(auto* held:chosen->occupations){held->histfig_id=-1;held->unit_id=-1;}
      chosen->occupations.clear();chosen->occupations.push_back(target);
      profession(chosen);
      target->unit_id=chosen->id;target->histfig_id=chosen->hist_figure_id;
      native.labors(chosen);
      if(!prepareNativeLocationStaff(siteId,locationId))return LocationStaffEditOutcome::Unknown;
    } else {target->unit_id=-1;target->histfig_id=-1;}
    return LocationStaffEditOutcome::Applied;
  } catch(const std::exception&) {
    // Native allocation failure may follow published effects. Never replay.
    return LocationStaffEditOutcome::Unknown;
  }
}

}
