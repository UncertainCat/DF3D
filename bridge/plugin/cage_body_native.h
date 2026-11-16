#pragma once
#include "building_room_native.h"
#include "df/building_cagest.h"
#include "df/world.h"
namespace df3d_production {
inline bool cageBodyReady() {
    static const bool ready=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        const auto pin=[base](size_t at,size_t count,uint64_t expected) {
            uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<count;++i){h^=base[at+i];h*=UINT64_C(1099511628211);}
            return h==expected;
        };
        return pin(0x18e657,0x37,UINT64_C(0x9f43b94164e58c6c)) &&
            pin(0x18e790,0x3b,UINT64_C(0x1031f0379c115d68)) &&
            pin(0x1af003,0x22,UINT64_C(0x105436d3f8f15548)) &&
            pin(0x1af04f,0x1c,UINT64_C(0xb279a3dc3f20899a)) &&
            pin(0x1af0a2,8,UINT64_C(0x7110ccb69b8860ff)) &&
            pin(0x145bee0,0x5e,UINT64_C(0x6abc4e374e372eef));
    }();return ready;
}
inline std::optional<CageBody> cageBody(df::building* building) {
    if(!building || building->getType()!=df::building_type::Cage || !df::global::world || !cageBodyReady())return {};
    const auto room=cageRoomBody(*building);if(!room)return {};
    auto& cage=*static_cast<df::building_cagest*>(building);
    CageBody result;result.flags=cage.cage_flags.whole;result.materialType=cage.mat_type;result.materialIndex=cage.mat_index;
    result.justiceRestraint=cage.isJusticeRestraint();result.room=*room;
    using Flag=bool(*)(df::world*,int32_t,int16_t,int32_t);
    const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    result.glass=reinterpret_cast<Flag>(base+0x145bee0)(df::global::world,49,cage.mat_type,cage.mat_index);
    return result;
}
inline bool setCageAquarium(df::building* building,bool aquarium) {
    const auto before=cageBody(building);
    if(!before || before->justiceRestraint || !before->glass)return false;
    auto& cage=*static_cast<df::building_cagest*>(building);
    // Native input is inline: both choices set CHECKOCCUPANTS, even when the
    // requested WATER bit is unchanged. No native input/menu scratch is used.
    cage.cage_flags.whole=uint16_t((before->flags&~2U)|(aquarium?6U:4U));
    return true;
}
}
