#pragma once
#include "building_header_transaction.h"
#include "df/building_doorst.h"
#include "df/world.h"
#include "df/global_objects.h"
#include "df/tile_occupancy.h"
#include "df/tile_designation.h"
#include "modules/Maps.h"
#include <windows.h>

namespace df3d_production {
struct DoorObservation {
    int32_t id=-1,x=-1,y=-1,z=-1;
    uint16_t flags=0;
    uint32_t occupancy=0;
    uint64_t revision=0;
};
inline bool doorNativeReady() {
    static const bool ready=[] {
        auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x1af741,0xcb,UINT64_C(0xe6e4fdfd305cfc1a)},
            {0x143c9a0,0x55,UINT64_C(0x9b4de3395f2625de)},
            {0x680a0,0x8d,UINT64_C(0xe88e74a561cb796a)},
            {0x143c830,0xad,UINT64_C(0x37c48d03b634ff66)},
            {0xa53370,0x117,UINT64_C(0x01d3a298f1911dba)},
            {0xa53490,0x79,UINT64_C(0x7406d58209ab6947)},
            {0x53af10,0xb72,UINT64_C(0x9655eb57f9886bfa)},
        };
        for(const auto& p:pins){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<p.length;++i){h^=base[p.rva+i];h*=UINT64_C(1099511628211);}if(h!=p.hash)return false;}
        return true;
    }();
    return ready;
}
inline std::optional<DoorObservation> observeDoor(df::building* building) {
    if(!doorNativeReady() || !df::global::world || !building || building->getType()!=df::building_type::Door ||
       building->getBuildStage()!=building->getMaxBuildStage())return {};
    auto* designation=DFHack::Maps::getTileDesignation(building->centerx,building->centery,building->z);
    auto* occupancy=DFHack::Maps::getTileOccupancy(building->x1,building->y1,building->z);
    if(!designation || designation->bits.hidden || !occupancy)return {};
    auto* door=static_cast<df::building_doorst*>(building);
    static_assert(offsetof(df::building_doorst,door_flags)==0x148);
    DoorObservation value;value.id=door->id;value.x=door->x1;value.y=door->y1;value.z=door->z;
    value.flags=door->door_flags.whole;value.occupancy=occupancy->whole;
    uint64_t hash=UINT64_C(14695981039346656037);
    for(uint64_t n:{uint64_t(value.id),uint64_t(value.x),uint64_t(value.y),uint64_t(value.z),uint64_t(value.flags),uint64_t(value.occupancy)})
        for(int i=0;i<8;++i){hash^=uint8_t(n);hash*=UINT64_C(1099511628211);n>>=8;}
    value.revision=(hash&INT64_MAX)?(hash&INT64_MAX):1;return value;
}
struct DoorEdit {
    BuildingHeaderOutcome outcome=BuildingHeaderOutcome::Rejected;
    bool mutated=false;
    std::optional<DoorObservation> receipt;
};
// Native1af741..1af807 keeps eligibility/bit writes inline. Its semantic
// occupancy leaf clears/replaces the occupancy kind and invalidates neighboring
// pathfinding data. Runtime never invokes the sheet handler or its scratch.
inline DoorEdit setDoorForbidden(df::building* building,uint64_t expected,bool forbidden) {
    DoorEdit result;const auto before=observeDoor(building);if(!before || !expected)return result;
    if(before->revision!=expected){result.outcome=BuildingHeaderOutcome::Stale;return result;}
    if(before->flags&0x2c)return result;
    if(bool(before->flags&1)==forbidden){result.outcome=BuildingHeaderOutcome::Completed;result.receipt=before;return result;}
    if(forbidden && !(before->flags&0x10))return result;
    result.mutated=true;result.outcome=BuildingHeaderOutcome::Unknown;
    try {
        auto* door=static_cast<df::building_doorst*>(building);
        door->door_flags.bits.forbidden=forbidden;
        const auto occupancy=forbidden?door->getImpassableOccupancy():door->getPassableOccupancy();
        auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
        using Update=void(*)(df::world*,int16_t,int16_t,int16_t,int32_t);
        reinterpret_cast<Update>(base+0x143c9a0)(df::global::world,int16_t(before->x),int16_t(before->y),int16_t(before->z),int32_t(occupancy));
        df::global::world->reindex_pathfinding=true;
        const auto after=observeDoor(building);
        const uint16_t flags=uint16_t((before->flags&~1u)|(forbidden?1u:0u));
        if(!after || after->flags!=flags || after->occupancy!=((before->occupancy&~7u)|uint32_t(occupancy)))return result;
        result.receipt=after;result.outcome=BuildingHeaderOutcome::Completed;
    }catch(...){}
    return result;
}
}
