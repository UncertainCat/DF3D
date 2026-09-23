#pragma once
// Native 53.16 ramp clearance: 0xdc1a10 -> 0x1447200 -> 0x534da0.
// Build the small dynamic-barrier index once per terrain scan or command, never
// scan the building lists for every pathfinding node. No native UI state.
#include "DataDefs.h"
#include "modules/Buildings.h"
#include "df/map_block.h"
#include "df/world.h"
#include "df/building_hatchst.h"
#include "df/building_grate_floorst.h"
#include "df/building_bars_floorst.h"
#include "df/building_grate_wallst.h"
#include "df/building_bars_verticalst.h"
#include <cstdint>
#include <unordered_set>

namespace df3d_track_terrain {
using ClearanceIndex = std::unordered_set<uint64_t>;
inline uint64_t key(int x,int y,int z) {
    return uint64_t(uint16_t(x)) | (uint64_t(uint16_t(y))<<16) | (uint64_t(uint16_t(z))<<32);
}
inline ClearanceIndex buildClearanceIndex() {
    ClearanceIndex blocked;
    auto* world=df::global::world;
    if(!world) return blocked;
    for(auto* b:world->buildings.other[df::buildings_other_id::HATCH]) {
        auto* hatch=DFHack::virtual_cast<df::building_hatchst>(b);
        if(!hatch || !hatch->door_flags.bits.forbidden || !hatch->door_flags.bits.closed ||
           hatch->getBuildStage()<hatch->getMaxBuildStage() || !hatch->isSettingOccupancy()) continue;
        for(int y=hatch->y1;y<=hatch->y2;++y) for(int x=hatch->x1;x<=hatch->x2;++x)
            if(DFHack::Buildings::containsTile(hatch,df::coord2d(x,y))) blocked.insert(key(x,y,hatch->z));
    }
    for(auto* b:world->buildings.other[df::buildings_other_id::GRATE_FLOOR]) {
        auto* gate=DFHack::virtual_cast<df::building_grate_floorst>(b);
        if(gate && gate->gate_flags.bits.closed) blocked.insert(key(gate->centerx,gate->centery,gate->z));
    }
    for(auto* b:world->buildings.other[df::buildings_other_id::BARS_FLOOR]) {
        auto* gate=DFHack::virtual_cast<df::building_bars_floorst>(b);
        if(gate && gate->gate_flags.bits.closed) blocked.insert(key(gate->centerx,gate->centery,gate->z));
    }
    return blocked;
}
inline bool clearanceBlocked(const df::map_block* block,int x,int y,const ClearanceIndex& dynamic) {
    if(!block) return true;
    const auto occupancy=block->occupancy[x][y].bits.building;
    if(occupancy==3 || occupancy==5 || occupancy==6) return true;
    return occupancy==7 && dynamic.count(key(block->map_pos.x+x,block->map_pos.y+y,block->map_pos.z))!=0;
}
inline ClearanceIndex buildHorizontalIndex() {
    ClearanceIndex blocked;
    auto* world=df::global::world;
    if(!world) return blocked;
    for(auto* b:world->buildings.other[df::buildings_other_id::GRATE_WALL]) {
        auto* gate=DFHack::virtual_cast<df::building_grate_wallst>(b);
        if(gate && gate->gate_flags.bits.closed) blocked.insert(key(gate->centerx,gate->centery,gate->z));
    }
    for(auto* b:world->buildings.other[df::buildings_other_id::BARS_VERTICAL]) {
        auto* gate=DFHack::virtual_cast<df::building_bars_verticalst>(b);
        if(gate && gate->gate_flags.bits.closed) blocked.insert(key(gate->centerx,gate->centery,gate->z));
    }
    return blocked;
}
inline bool horizontalBlocked(const df::map_block* block,int x,int y,const ClearanceIndex& dynamic) {
    if(!block) return true;
    const auto occupancy=block->occupancy[x][y].bits.building;
    return (occupancy>=3 && occupancy<=6) ||
        (occupancy==7 && dynamic.count(key(block->map_pos.x+x,block->map_pos.y+y,block->map_pos.z))!=0);
}
} // namespace df3d_track_terrain
