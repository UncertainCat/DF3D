#pragma once
#include <cstdint>
#include <optional>
#include <vector>
#include <string>
#include <tuple>

namespace df3d_area {
enum class LocationStaffSource : uint8_t { Occupation, ReligiousPosition };
struct LocationStaffNames {
  std::string positionName,holderName;
  uint8_t holderKind=0; // 0 unresolved/unassigned, 1 unit, 2 historical figure.
  int32_t holderId=-1;
};
struct LocationStaffRow {
  std::optional<LocationStaffNames> names;
  LocationStaffSource source=LocationStaffSource::Occupation;
  int32_t occupationId=-1,role=-1,histfigId=-1,unitId=-1,locationId=-1,siteId=-1,groupId=-1;
  int32_t entityId=-1,positionId=-1,assignmentId=-1;
};
struct LocationStaffSnapshot {
  std::vector<LocationStaffRow> rows;
  std::vector<int32_t> missingRoles;
};
struct LocationStaffSkill {
  int32_t id=-1,rating=0,experience=0,weight=0;
  bool operator==(const LocationStaffSkill& other) const {
    return std::tie(id,rating,experience,weight)==std::tie(other.id,other.rating,other.experience,other.weight);
  }
};
struct LocationStaffCandidate {
  int32_t unitId=-1,histfigId=-1,score=0;
  std::string name,baseName,professionName;
  int32_t professionColor=-1;
  bool legendary=false;
  int32_t sourceIndex=-1,professionOrder=-1,statusOrder=-1;
  std::vector<uint8_t> nameSortKey,professionSortKey;
  std::vector<LocationStaffSkill> skills;
  bool operator==(const LocationStaffCandidate& other) const {
    return std::tie(unitId,histfigId,score,name,baseName,professionName,professionColor,legendary,skills,sourceIndex,professionOrder,statusOrder,nameSortKey,professionSortKey)==
        std::tie(other.unitId,other.histfigId,other.score,other.name,other.baseName,other.professionName,other.professionColor,other.legendary,other.skills,other.sourceIndex,other.professionOrder,other.statusOrder,other.nameSortKey,other.professionSortKey);
  }
};
// Private receipt dependencies: assignment may clear occupations elsewhere even
// when displayed candidate facts are unchanged. Never serialized as UI state.
struct LocationStaffAssignmentBinding {
  int32_t ownerUnitId=-1,occupationId=-1,role=-1,histfigId=-1,unitId=-1;
  int32_t locationId=-1,siteId=-1,groupId=-1;
  bool operator==(const LocationStaffAssignmentBinding& other) const {
    return std::tie(ownerUnitId,occupationId,role,histfigId,unitId,locationId,siteId,groupId)==
      std::tie(other.ownerUnitId,other.occupationId,other.role,other.histfigId,other.unitId,other.locationId,other.siteId,other.groupId);
  }
};
struct LocationStaffCandidates {
  int32_t role=-1;
  std::vector<LocationStaffCandidate> rows;
  std::vector<LocationStaffAssignmentBinding> assignmentBindings;
};
// Ordinary occupation selector, default skill order. Semantic unit/occupation
// records only; native widget snapshots are independent test evidence.
std::optional<LocationStaffCandidates> observeNativeLocationStaffCandidates(
    int32_t siteId,int32_t locationId,int32_t occupationId);
// Caller owns a DF safe point. Current-site semantic records only; no UI inputs.
std::optional<LocationStaffSnapshot> observeNativeLocationStaff(int32_t siteId,int32_t id);
// Allocate missing empty roles as native Details entry does. Existing records and
// order are preserved. False means no publication; repeat entry reuses empty slots.
bool prepareNativeLocationStaff(int32_t siteId,int32_t id);
enum class LocationStaffEditOutcome : uint8_t { Unavailable, Rejected, Applied, Unknown, Stale };
// Caller validates current receipt/epoch at the same safe point. unitId==-1
// removes; otherwise native assignment replaces that unit's prior occupations.
LocationStaffEditOutcome editNativeLocationStaff(int32_t siteId,int32_t locationId,
                                                int32_t occupationId,int32_t unitId);

struct LocationReligiousStaffReceipt {
  int32_t siteId=-1,locationId=-1,entityId=-1,assignmentId=-1,positionId=-1,holderId=-1,unitId=-1;
  uint64_t revision=0;
  bool removable=false;
};
// Caller owns a safe point. Semantic identity and cleanup dependencies only;
// epoch ownership is supplied by transport, never native UI state.
std::optional<LocationReligiousStaffReceipt> observeNativeLocationReligiousStaff(
    int32_t siteId,int32_t locationId,int32_t entityId,int32_t assignmentId);
// Native candidate membership in source order; presentation sorting is separate.
std::optional<std::vector<int32_t>> observeNativeReligiousCandidateIds(
    int32_t siteId,int32_t locationId,int32_t entityId,int32_t assignmentId);
// Candidate facts and default skill order; role remains -1 for position targets.
std::optional<LocationStaffCandidates> observeNativeReligiousCandidates(
    int32_t siteId,int32_t locationId,int32_t entityId,int32_t assignmentId);
// Requires the exact observed revision at the same safe point as mutation.
LocationStaffEditOutcome removeNativeLocationReligiousStaff(int32_t siteId,int32_t locationId,
    int32_t entityId,int32_t assignmentId,int32_t expectedHolderId,uint64_t expectedRevision);
// Diagnostic primitive. Revalidates current candidate eligibility; transport
// must additionally bind the selected candidate's dependencies before exposure.
LocationStaffEditOutcome assignNativeLocationReligiousStaff(int32_t siteId,int32_t locationId,
    int32_t entityId,int32_t assignmentId,int32_t unitId,int32_t expectedHolderId,uint64_t expectedRevision);

}
