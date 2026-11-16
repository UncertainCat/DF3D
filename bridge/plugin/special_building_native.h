#pragma once
#include "zone_native.h"
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace df { struct building; }
namespace df3d_production {
// Pointer-free, native CP437 descriptions. Read at a simulation safe point.
struct NestBoxBody {
    int32_t claimantId=-1;
    std::string status,name;
    std::optional<df3d_area::ZoneOwnerNameColor> nameColor;
};
struct AnimalTrapBody {
    enum class State:uint8_t { Blank,Empty,Baited,Occupied };
    State state=State::Blank;
    int16_t baitType=-1;
    int32_t itemId=-1;
    std::string status,name;
};
struct HiveBody {
    uint32_t flags=0;
    bool outdoorAccess=false;
    // 0: unrestricted, 1: restricted output, 2: no output.
    uint8_t crowding=0;
    int32_t colonyRace=-1,matchingColonies=0;
};
std::optional<NestBoxBody> nestBoxBody(df::building* building);
std::optional<AnimalTrapBody> animalTrapBody(df::building* building);
std::optional<HiveBody> hiveBody(df::building* building);
struct SpecialBuildingControls {
    struct Job {int32_t id,type,itemType;uint32_t flags;};
    int32_t id=-1,type=-1;
    uint64_t revision=0;
    bool removing=false;
    std::optional<AnimalTrapBody> trap;
    std::optional<HiveBody> hive;
    std::vector<Job> jobs;
};
enum class SpecialBuildingOutcome:uint8_t { Rejected,Completed,Stale,Unknown };
struct SpecialBuildingEdit {
    SpecialBuildingOutcome outcome=SpecialBuildingOutcome::Rejected;
    bool effectsStarted=false;
    std::optional<SpecialBuildingControls> receipt;
};
// Caller owns epoch/visibility validation at the same safe point. No native UI
// authority is consulted; revisions cover the actual target, contents and jobs.
std::optional<SpecialBuildingControls> specialBuildingControls(df::building* building);
SpecialBuildingEdit setAnimalTrapBait(df::building* building,uint64_t expected,int16_t bait);
SpecialBuildingEdit setHiveSetting(df::building* building,uint64_t expected,uint32_t mask,bool enabled);
}
