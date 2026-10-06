#include "location_catalog_native.h"
#include "modules/Maps.h"
#include "modules/Units.h"
#include "modules/Translation.h"
#include "MiscUtils.h"
#include "df/historical_entity.h"
#include "df/historical_figure.h"
#include "df/histfig_entity_link.h"
#include "df/histfig_hf_link.h"
#include "df/plotinfost.h"
#include "df/unit.h"
#include "df/world.h"
#include "df/world_site.h"
#include "df/abstract_building.h"
#include "df/abstract_building_contents.h"
#include "df/abstract_building_templest.h"
#include "df/entity_site_link.h"
#include "df/entity_focusst.h"
#include "df/historical_figure_info.h"
#include "df/metaphysical_profilest.h"

namespace df3d_area {
namespace {
std::string nativeName(const df::language_name* name) {
  auto text=DFHack::Translation::translateName(name,true);
  if(!text.empty())text[0]=toupper_cp437(text[0]);
  return DF2UTF(text);
}
std::optional<LocationDeity> observeDeity(int32_t id) {
  auto* figure=df::historical_figure::find(id);
  if(!figure)return std::nullopt;
  LocationDeity result;result.id=id;result.name=nativeName(&figure->name);
  if(figure->info && figure->info->metaphysical)
    for(auto sphere:figure->info->metaphysical->spheres)result.spheres.push_back(int32_t(sphere));
  return result;
}
int32_t guildProfessionLast(df::profession profession) {
  switch(profession) {
        case df::profession::WOODWORKER:return int32_t(df::profession::WOODCUTTER);
        case df::profession::STONEWORKER:return int32_t(df::profession::MASON);
        case df::profession::RANGER:return int32_t(df::profession::ANIMAL_DISSECTOR);
        case df::profession::METALSMITH:return int32_t(df::profession::METALCRAFTER);
        case df::profession::JEWELER:return int32_t(df::profession::GEM_SETTER);
        case df::profession::CRAFTSMAN:return int32_t(df::profession::STRAND_EXTRACTOR);
        case df::profession::FISHERY_WORKER:return int32_t(df::profession::FISH_CLEANER);
        case df::profession::FARMER:return int32_t(df::profession::BEEKEEPER);
        case df::profession::ENGINEER:return int32_t(df::profession::PUMP_OPERATOR);
        case df::profession::DOCTOR:return int32_t(df::profession::SURGEON);
        default:return int32_t(profession);
      }
}
bool existingLocation(df::abstract_building* location) {
  // Native095120: each ruin/deletion flag suppresses both indicators. Owner,
  // access, recognition and missing zone IDs do not suppress the indicator.
  return location && !location->flags.is_set(df::abstract_building_flags::DOES_NOT_EXIST) &&
      !location->flags.is_set(df::abstract_building_flags::WG_RUINED) &&
      !location->flags.is_set(df::abstract_building_flags::PWG_RUINED);
}
}
std::optional<std::vector<GuildWorkers>> observeNativeLocationGuilds() {
  if(!df::global::world || !df::global::plotinfo || !DFHack::Maps::IsValid())return std::nullopt;
  auto* site=df::world_site::find(df::global::plotinfo->site_id);
  if(!site)return std::nullopt;
  // Native085857/093440: these are the offered professions in native order.
  // Parent worker ranges include Stonecutter/Stone Carver even though neither
  // has its own choice. Generic enum parents wrongly include Papermaker/Bookbinder.
  std::vector<GuildProfessionRange> definitions;
  const auto append=[&](df::profession first,df::profession last) {
    for(int32_t profession=int32_t(first);profession<=int32_t(last);++profession) {
      int32_t end=profession;
      end=guildProfessionLast(df::profession(profession));
      definitions.push_back({profession,end});
    }
  };
  append(df::profession::MINER,df::profession::STONEWORKER);
  append(df::profession::ENGRAVER,df::profession::PUMP_OPERATOR);
  append(df::profession::DOCTOR,df::profession::SURGEON);
  std::vector<LocationUnitProfession> units;
  for(auto* unit:df::global::world->units.active) {
    if(!unit)continue;
    units.push_back({DFHack::Units::isActive(unit),DFHack::Units::isFortControlled(unit),int32_t(unit->profession)});
  }
  auto result=locationGuildWorkers(definitions,units);
  if(!result)return std::nullopt;
  // Native095759/100001: the current site's capital links supply guilds.
  // Link target/type/former flags do not replace capital/type/focus checks.
  for(auto* link:site->entity_links) {
    if(!link || !link->flags.bits.capital)continue;
    auto* guild=df::historical_entity::find(link->entity_id);
    if(!guild || guild->type!=df::historical_entity_type::Guild)continue;
    for(auto* focus:guild->guild_professions) {
      if(!focus || focus->type!=df::entity_focus_type::PROMOTE_PROFESSION_UNIT)continue;
      for(auto& row:*result)if(row.profession==int32_t(focus->profession)) {
        // Native101223: first eligible guild in site entity-link order wins,
        // including after swapping identities. Later matches do not replace it.
        if(row.guildId>=0)continue;
        row.guildId=guild->id;
        row.guildName=nativeName(&guild->name);
      }
    }
  }
  for(auto* unit:df::global::world->units.active) {
    if(!unit || !DFHack::Units::isActive(unit) || !DFHack::Units::isFortControlled(unit))continue;
    auto* figure=df::historical_figure::find(unit->hist_figure_id);
    if(!figure)continue;
    std::set<int32_t> membership;
    for(auto* link:figure->entity_links)
      if(link && link->getType()==df::histfig_entity_link_type::MEMBER)membership.insert(link->entity_id);
    for(auto& row:*result)if(row.guildId>=0 && membership.count(row.guildId))++row.members;
  }
  for(auto* location:site->buildings) {
    if(!existingLocation(location) || location->getType()!=df::abstract_building_type::GUILDHALL)continue;
    auto* contents=location->getContents();
    if(!contents)return std::nullopt;
    for(auto& row:*result)if(row.profession==int32_t(contents->profession))row.hasMeetingPlace=true;
  }
  return result;
}
std::optional<std::vector<ReligiousPractice>> observeNativeLocationReligions() {
  if(!df::global::world || !df::global::plotinfo || !DFHack::Maps::IsValid())
    return std::nullopt;
  auto* civ=df::historical_entity::find(df::global::plotinfo->civ_id);
  auto* site=df::world_site::find(df::global::plotinfo->site_id);
  if(!civ || !site)return std::nullopt;
  for(const auto id:civ->relations.deities)
    if(!df::historical_figure::find(id))return std::nullopt;
  std::vector<LocationUnitPractices> units;
  for(auto* unit:df::global::world->units.active) {
    if(!unit || !DFHack::Units::isActive(unit) || !DFHack::Units::isFortControlled(unit))continue;
    auto* figure=df::historical_figure::find(unit->hist_figure_id);
    if(!figure)continue;
    LocationUnitPractices observed;
    observed.active=true;observed.fortControlled=true;
    for(auto* link:figure->histfig_links) {
      if(!link || link->getType()!=df::histfig_hf_link_type::DEITY)continue;
      if(!df::historical_figure::find(link->target_hf))return std::nullopt;
      observed.deities.push_back(link->target_hf);
    }
    for(auto* link:figure->entity_links) {
      if(!link || link->getType()!=df::histfig_entity_link_type::MEMBER)continue;
      auto* entity=df::historical_entity::find(link->entity_id);
      if(entity && entity->type==df::historical_entity_type::Religion)
        observed.religions.push_back(entity->id);
    }
    units.push_back(std::move(observed));
  }
  auto result=locationReligiousPractices(civ->relations.deities,units);
  if(!result)return std::nullopt;
  for(auto& row:*result) {
    if(row.kind==ReligiousPracticeKind::None)continue; // presentation maps native sentinel copy
    if(row.kind==ReligiousPracticeKind::Deity) {
      auto deity=observeDeity(row.id);if(!deity)return std::nullopt;
      row.name=deity->name;row.deities.push_back(std::move(*deity));
    } else {
      auto* religion=df::historical_entity::find(row.id);if(!religion)return std::nullopt;
      row.name=nativeName(&religion->name);
      for(auto id:religion->relations.deities) {
        auto deity=observeDeity(id);if(!deity)return std::nullopt;
        row.deities.push_back(std::move(*deity));
      }
    }
  }
  for(auto* location:site->buildings) {
    if(!existingLocation(location) || location->getType()!=df::abstract_building_type::TEMPLE)continue;
    auto* temple=static_cast<df::abstract_building_templest*>(location);
    const auto kind=temple->deity_type==df::religious_practice_type::WORSHIP_HFID ? ReligiousPracticeKind::Deity :
        temple->deity_type==df::religious_practice_type::RELIGION_ENID ? ReligiousPracticeKind::Religion : ReligiousPracticeKind::None;
    for(auto& row:*result)if(row.kind==kind && row.id==temple->deity_data.practice_id)row.hasTemple=true;
  }
  return result;
}

std::optional<LocationAffiliation> observeNativeLocationAffiliation(int32_t siteId,int32_t locationId) {
  if(siteId<0 || locationId<0 || !df::global::world || !df::global::plotinfo ||
      !DFHack::Maps::IsValid() || siteId!=df::global::plotinfo->site_id)return std::nullopt;
  auto* site=df::world_site::find(siteId);if(!site)return std::nullopt;
  df::abstract_building* location=nullptr;
  for(auto* candidate:site->buildings)if(candidate && candidate->id==locationId){location=candidate;break;}
  if(!existingLocation(location))return std::nullopt;
  LocationAffiliation result;
  int32_t profession=-1,lastProfession=-1;
  if(location->getType()==df::abstract_building_type::TEMPLE) {
    auto* temple=static_cast<df::abstract_building_templest*>(location);
    if(temple->deity_type==df::religious_practice_type::NONE) {
      result.kind=1;return result;
    }
    result.id=temple->deity_data.practice_id;
    if(temple->deity_type==df::religious_practice_type::WORSHIP_HFID) {
      auto* deity=df::historical_figure::find(result.id);if(!deity)return std::nullopt;
      result.kind=2;result.name=nativeName(&deity->name);
    } else if(temple->deity_type==df::religious_practice_type::RELIGION_ENID) {
      auto* religion=df::historical_entity::find(result.id);
      if(!religion || religion->type!=df::historical_entity_type::Religion)return std::nullopt;
      result.kind=3;result.name=nativeName(&religion->name);
    } else return std::nullopt;
  } else if(location->getType()==df::abstract_building_type::GUILDHALL) {
    const auto* contents=location->getContents();if(!contents)return std::nullopt;
    result.kind=4;result.workers=0;
    profession=int32_t(contents->profession);lastProfession=guildProfessionLast(contents->profession);
    for(auto* link:site->entity_links) {
      if(!link || !link->flags.bits.capital)continue;
      auto* guild=df::historical_entity::find(link->entity_id);
      if(!guild || guild->type!=df::historical_entity_type::Guild)continue;
      bool matches=false;
      for(auto* focus:guild->guild_professions)
        if(focus && focus->type==df::entity_focus_type::PROMOTE_PROFESSION_UNIT &&
            focus->profession==contents->profession){matches=true;break;}
      if(matches){result.id=guild->id;result.name=nativeName(&guild->name);break;}
    }

  } else return std::nullopt;
  for(auto* unit:df::global::world->units.active) {
    if(!unit || !DFHack::Units::isActive(unit) || !DFHack::Units::isFortControlled(unit))continue;
    if(result.kind==4 && int32_t(unit->profession)>=profession && int32_t(unit->profession)<=lastProfession)++result.workers;
    if(result.id<0)continue;
    auto* figure=df::historical_figure::find(unit->hist_figure_id);if(!figure)continue;
    bool member=false;
    if(result.kind==2) {
      for(auto* link:figure->histfig_links)
        if(link && link->getType()==df::histfig_hf_link_type::DEITY && link->target_hf==result.id){member=true;break;}
    } else {
      for(auto* link:figure->entity_links)
        if(link && link->getType()==df::histfig_entity_link_type::MEMBER && link->entity_id==result.id){member=true;break;}
    }
    if(member)++result.count;
  }
  return result;
}
}
