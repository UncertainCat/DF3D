#pragma once
#include <cstdint>
#include <optional>
#include <map>
#include <set>
#include <string>
#include <utility>
#include <vector>

namespace df3d_area {
// Semantic values match LocationCreate; native religious_practice_type uses
// different values and must be converted explicitly by the safe-point observer.
enum class ReligiousPracticeKind : int8_t { None=1, Deity=2, Religion=3 };
struct LocationDeity {
  int32_t id=-1;
  std::string name{};
  std::vector<int32_t> spheres{};
  bool operator==(const LocationDeity& other) const {
    return id==other.id && name==other.name && spheres==other.spheres;
  }
};
struct ReligiousPractice {
  ReligiousPracticeKind kind=ReligiousPracticeKind::None;
  int32_t id=-1;
  int32_t worshippers=0;
  bool hasTemple=false;
  std::string name{};
  std::vector<LocationDeity> deities{};
  bool operator==(const ReligiousPractice& other) const {
    return kind==other.kind && id==other.id && worshippers==other.worshippers && hasTemple==other.hasTemple &&
        name==other.name && deities==other.deities;
  }
};
struct LocationUnitPractices {
  // Native091417: all25 controlled cases match isActive && isFortControlled.
  // Do not substitute isAlive, isCitizen, isResident or own-civ checks.
  bool active=false,fortControlled=false;
  std::vector<int32_t> deities,religions;
};
struct GuildProfessionRange { int32_t profession=-1,last=-1; };
struct LocationUnitProfession { bool active=false,fortControlled=false; int32_t profession=-1; };
struct GuildWorkers {
  int32_t profession=-1,workers=0;
  bool hasMeetingPlace=false;
  int32_t guildId=-1,members=0;
  std::string guildName{};
  bool operator==(const GuildWorkers& other) const {
    return profession==other.profession && workers==other.workers && hasMeetingPlace==other.hasMeetingPlace &&
        guildId==other.guildId && members==other.members && guildName==other.guildName;
  }
};

inline std::optional<std::vector<GuildWorkers>> locationGuildWorkers(
    const std::vector<GuildProfessionRange>& definitions,
    const std::vector<LocationUnitProfession>& units) {
  std::vector<GuildWorkers> result;
  std::set<int32_t> seen;
  for(const auto& definition:definitions) {
    if(definition.profession<0 || definition.last<definition.profession ||
       !seen.insert(definition.profession).second)return std::nullopt;
    GuildWorkers row{definition.profession,0};
    for(const auto& unit:units)
      if(unit.active && unit.fortControlled && unit.profession>=definition.profession &&
         unit.profession<=definition.last)++row.workers;
    result.push_back(row);
  }
  return result;
}

// Inputs retain civilization deity order, active-unit order, and each historical
// figure's link order. Religions contain only MEMBER links to Religion entities.
// No viewscreen, native selector or staged location state is an input.
inline std::optional<std::vector<ReligiousPractice>> locationReligiousPractices(
    const std::vector<int32_t>& civilizationDeities,
    const std::vector<LocationUnitPractices>& units) {
  std::vector<ReligiousPractice> result{{ReligiousPracticeKind::None,-1}};
  std::map<std::pair<ReligiousPracticeKind,int32_t>,size_t> seen;
  const auto append=[&](ReligiousPracticeKind kind,const std::vector<int32_t>& ids) {
    for(const auto id:ids) {
      // Missing/invalid observations cannot become a plausible partial catalog.
      if(id<0)return false;
      if(seen.emplace(std::make_pair(kind,id),result.size()).second)result.push_back({kind,id});
    }
    return true;
  };
  if(!append(ReligiousPracticeKind::Deity,civilizationDeities))return std::nullopt;
  for(const auto& unit:units) {
    if(!unit.active || !unit.fortControlled)continue;
    if(!append(ReligiousPracticeKind::Deity,unit.deities) ||
       !append(ReligiousPracticeKind::Religion,unit.religions))return std::nullopt;
    // Native092518 baseline counts match eligible units with matching links.
    for(const auto id:std::set<int32_t>(unit.deities.begin(),unit.deities.end()))
      ++result[seen.at({ReligiousPracticeKind::Deity,id})].worshippers;
    for(const auto id:std::set<int32_t>(unit.religions.begin(),unit.religions.end()))
      ++result[seen.at({ReligiousPracticeKind::Religion,id})].worshippers;
  }
  return result;
}
} // namespace df3d_area
