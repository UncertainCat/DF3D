#pragma once
#include <cstdint>
#include <string>
#include <vector>
namespace df3d_production {
struct BuildingRoomBody {
    int32_t buildingId=-1,roomId=-1,roomType=-1;
    std::vector<int32_t> relevantZones;
    std::vector<std::string> notices;
    std::string introduction,name;
};
struct CageBody {
    uint16_t flags=0;
    int16_t materialType=-1;int32_t materialIndex=-1;
    bool justiceRestraint=false,glass=false;
    BuildingRoomBody room;
};
}
