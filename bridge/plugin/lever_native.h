#pragma once
#include "farm_native.h"
#include "df/building_trapst.h"
#include "modules/Maps.h"

namespace df3d_production {
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
