#pragma once
#include <array>
#include "location_staff_native.h"
#include "location_catalog_native.h"
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace df3d_area {
enum class LocationAccess : uint8_t { Visitors, Residents, Citizens, Members };
struct LocationAccessFlags { bool visitors=false,residents=false,members=false; };
// Native160005: members overrides visitors, which overrides residents.
inline LocationAccess locationAccess(LocationAccessFlags flags) {
  return flags.members ? LocationAccess::Members : flags.visitors ? LocationAccess::Visitors :
      flags.residents ? LocationAccess::Residents : LocationAccess::Citizens;
}
// Native160005: selecting a mode replaces all three permission bits, including
// noncanonical starting combinations. Only temples/guildhalls offer Members.
inline std::optional<LocationAccessFlags> locationAccessSelection(uint8_t kind, LocationAccess mode) {
  if(kind<1 || kind>5)return std::nullopt;
  switch(mode) {
    case LocationAccess::Visitors:return LocationAccessFlags{true,true,false};
    case LocationAccess::Residents:return LocationAccessFlags{false,true,false};
    case LocationAccess::Citizens:return LocationAccessFlags{false,false,false};
    case LocationAccess::Members:
      if(kind==2 || kind==4)return LocationAccessFlags{false,false,true};
      return std::nullopt;
  }
  return std::nullopt;
}
enum class LocationAccessOutcome : uint8_t { Rejected, Completed, Stale };
enum class LocationSupply : uint8_t { Goblets, Instruments, Paper, Splints, Thread,
    Cloth, Crutches, Powder, Buckets, Soap };
struct LocationSupplyQuantity { int32_t stored=0,desired=0; };
// A partial semantic observation used to establish the Details contract. Does
// not claim complete native presentation or editing behavior.
struct LocationFacilities { int32_t chests=0,beds=0,tables=0,tractionBenches=0,bookcases=0,chairs=0,rooms=0,rentedRooms=0; };
struct LocationDetailsCore {
  int32_t siteId=-1,id=-1;
  uint8_t kind=0; // Existing semantic LocationCreate kinds1..5.
  std::string name;
  LocationAccessFlags accessFlags;
  LocationAccess access=LocationAccess::Citizens;
  int32_t profession=-1,tier=-1,value=-1,desiredCopies=0;
  int32_t appraisal=-2; // -2 unobserved, -1 no resolvable broker, otherwise effective skill.
  bool recognized=false;
  std::array<LocationSupplyQuantity,10> supplies{};
  std::vector<int32_t> zoneIds;
  LocationFacilities facilities;
  std::optional<LocationStaffSnapshot> staff;
  std::optional<LocationAffiliation> affiliation;
  int32_t danceFloorX=-1,danceFloorY=-1; // -1 unobserved, zero means no eligible rectangle.
  int32_t writtenObjects=-1; // -1 unobserved; native object count, not stack quantity.
};
// Caller owns a DF safe point. Current-site identities only, copied world facts;
// no retained native pointers and no viewscreen/widget/cursor inputs.
std::optional<LocationDetailsCore> observeNativeLocationDetailsCore(int32_t siteId,int32_t id);
// Native Details entry refreshes semantic caches; ordinary reads/renders do not.
// Caller owns a safe point. This does not populate staffing slots or open any UI.
// Returns false without writes for an invalid identity or unsupported executable.
bool refreshNativeLocationDetailsCaches(int32_t siteId,int32_t id);
// Safe-point mutation: validate the current Details receipt before any writes.
// Does not enter Details, refresh caches or create staffing slots.
LocationAccessOutcome setNativeLocationAccess(int32_t siteId,int32_t id,
    uint64_t expectedRevision,LocationAccess mode);
inline uint64_t locationDetailsRevision(const LocationDetailsCore& v) {
  uint64_t hash=14695981039346656037ULL;
  const auto number=[&](uint64_t value) {
    for(unsigned i=0;i<8;++i){hash^=value&255;hash*=1099511628211ULL;value>>=8;}
  };
  number(uint32_t(v.siteId));number(uint32_t(v.id));number(v.kind);number(v.name.size());
  for(unsigned char ch:v.name){hash^=ch;hash*=1099511628211ULL;}
  number(v.accessFlags.visitors);number(v.accessFlags.residents);number(v.accessFlags.members);
  number(uint8_t(v.access));number(uint32_t(v.profession));number(uint32_t(v.tier));number(uint32_t(v.value));
  number(uint32_t(v.desiredCopies));number(v.recognized);number(uint32_t(v.appraisal));
  for(const auto& supply:v.supplies){number(uint32_t(supply.stored));number(uint32_t(supply.desired));}
  number(v.zoneIds.size());for(auto id:v.zoneIds)number(uint32_t(id));
  for(auto count:{v.facilities.chests,v.facilities.beds,v.facilities.tables,v.facilities.tractionBenches,v.facilities.bookcases,v.facilities.chairs,v.facilities.rooms,v.facilities.rentedRooms})number(uint32_t(count));
  number(uint32_t(v.writtenObjects));number(uint32_t(v.danceFloorX));number(uint32_t(v.danceFloorY));
  number(bool(v.affiliation));
  if(v.affiliation) {
    const auto& a=*v.affiliation;number(a.kind);number(uint32_t(a.id));number(uint32_t(a.count));number(uint32_t(a.workers));
    number(a.name.size());for(unsigned char ch:a.name){hash^=ch;hash*=1099511628211ULL;}
  }
  number(bool(v.staff));
  if(v.staff) {
    number(v.staff->rows.size());
    for(const auto& row:v.staff->rows) {
      number(bool(row.names));
      if(row.names) {
        number(row.names->holderKind);number(uint32_t(row.names->holderId));
        for(const auto* text:{&row.names->positionName,&row.names->holderName}) {
          number(text->size());for(unsigned char ch:*text){hash^=ch;hash*=1099511628211ULL;}
        }
      }
      number(uint8_t(row.source));
      for(auto field:{row.occupationId,row.role,row.histfigId,row.unitId,row.locationId,row.siteId,row.groupId,row.entityId,row.positionId,row.assignmentId})number(uint32_t(field));
    }
    number(v.staff->missingRoles.size());for(auto role:v.staff->missingRoles)number(uint32_t(role));
  }
  hash&=0x7fffffffffffffffULL;return hash?hash:1;
}
}
