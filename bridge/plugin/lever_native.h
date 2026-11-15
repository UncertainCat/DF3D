#pragma once
#include "farm_native.h"
#include "df/building_trapst.h"
#include "df/item.h"
#include "df/item_trappartsst.h"
#include "modules/Maps.h"

namespace df3d_production {
// The initial Link selector is inline in DF's sheet input. Preserve its
// TRAPPARTS order/flag mask here; call DF for availability, effective position,
// walkability component and stock exclusion. Output IDs are independently owned.
inline std::optional<std::array<int32_t,2>> leverInitialMechanisms(df::building* building) {
    auto* lever=virtual_cast<df::building_trapst>(building);
    if(!farmFunctions() || !df::global::world || !lever || int(lever->trap_type)!=0 ||
       lever->getBuildStage()!=lever->getMaxBuildStage())return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool ready=[&] {
        struct Pin {size_t rva,length;uint64_t expected;};
        constexpr Pin pins[]={
            {0x1ad883,0x2b1,UINT64_C(0x6e32f372e3f3cf02)},
            {0xc93380,0x98,UINT64_C(0x9455ba082ba604c4)},
            {0xc93160,0x213,UINT64_C(0x07d957dea30ed105)},
            {0xc8baa0,0x11a,UINT64_C(0x2c62fce4a0555c66)},
            {0x10afe0,0xb9,UINT64_C(0xdd7dd1f9769e2f8a)}};
        for(const auto& pin:pins) {
            uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){h^=base[pin.rva+i];h*=UINT64_C(1099511628211);}
            if(h!=pin.expected)return false;
        }return true;
    }();
    auto& world=*df::global::world;
    auto& items=world.items.other.TRAPPARTS;
    if(!ready || reinterpret_cast<uint8_t*>(&world)!=base+0x23d14f0 ||
       reinterpret_cast<uint8_t*>(&items)!=base+0x23e5b88 || items.size()>1000000)return std::nullopt;
    using Check=bool (*)(df::item*);
    using Position=void (*)(df::item*,int16_t*,int16_t*,int16_t*);
    using Walk=int32_t (*)(df::world*,int16_t,int16_t,int16_t);
    auto walk=reinterpret_cast<Walk>(base+0x10afe0);
    std::array<int32_t,2> result{{-1,-1}};size_t count=0;
    for(auto* item:items) {
        if(!item || !reinterpret_cast<Check>(base+0xc93380)(item) ||
           (item->flags.whole & UINT64_C(0x800e90cb2)))continue;
        int16_t x=-30000,y=-30000,z=-30000;
        reinterpret_cast<Position>(base+0xc8baa0)(item,&x,&y,&z);
        if(!walk(&world,x,y,z))continue;
        const auto component=walk(&world,lever->centerx,lever->centery,lever->z);
        if(walk(&world,x,y,z)!=component || reinterpret_cast<Check>(base+0xc93160)(item))continue;
        result[count++]=item->id;if(count==2)break;
    }
    return result;
}
// Native1adb58..1adb8f: semantic job creation/attachment, with no menu input.
// fd580/d020c0 register the job and allocate its ID immediately. Call only at
// a safe point after validating the complete intent; never use as a preview.
inline bool leverPullNativeReady() {
    static const bool ready=[] {
        if(!farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        const auto hash=[&](size_t rva,size_t length) {
            uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<length;++i){h^=base[rva+i];h*=UINT64_C(1099511628211);}return h;
        };
        return hash(0xfd580,0x23)==UINT64_C(0x1f9646cb809a07ae) &&
            hash(0xd020c0,0x1f9)==UINT64_C(0xe6506fad7c779085) &&
            hash(0x54bcf0,0xce)==UINT64_C(0x7ceaff76902a0dea) &&
            hash(0xd09b70,0x130)==UINT64_C(0x1046a66c3f604a04) &&
            hash(0x1adb58,0x3c)==UINT64_C(0x63603996d93f2ca9);
    }();return ready;
}
inline df::job* pullLeverNative(df::building* building) {
    auto* lever=virtual_cast<df::building_trapst>(building);
    if(!leverPullNativeReady() || !df::global::world || !lever || int(lever->trap_type)!=0 ||
       lever->getBuildStage()!=lever->getMaxBuildStage() || lever->jobs.size()>=32767)return nullptr;
    auto* tile=DFHack::Maps::getTileDesignation(lever->centerx,lever->centery,lever->z);
    if(!tile || tile->bits.hidden)return nullptr;
    for(const auto* job:lever->jobs)if(!job || job->job_type==df::job_type::DestroyBuilding)return nullptr;
    static_assert(sizeof(df::job)==0x148 && offsetof(df::job,job_type)==0x14);
    using Create=df::job* (*)();
    using Attach=void (*)(df::building*,df::job*,bool);
    using Requirements=void (*)(df::job*);
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    auto* job=reinterpret_cast<Create>(base+0xfd580)();
    job->job_type=df::job_type::PullLever;
    job->pos=df::coord(lever->centerx,lever->centery,lever->z);
    reinterpret_cast<Attach>(base+0x54bcf0)(lever,job,false);
    reinterpret_cast<Requirements>(base+0xd09b70)(job);
    return job;
}
}
