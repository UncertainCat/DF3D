#pragma once
#include "zone_native.h"
#include "df/building_siegeenginest.h"
#include "df/job.h"
#include <windows.h>
#include <algorithm>
#include <optional>

namespace df3d_production {
inline bool siegeControlsReady() {
    if(!df3d_area::nativeZoneAnimalAssignmentReady())return false;
    static const bool ready=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x36b;++i){hash^=base[0x1af364+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0x03988b22a42720cd);
    }();return ready;
}
// Shared inline native mode semantics for Places and building sheets. Callers
// own safe-point admission and mark uncertainty before entry. Never replay.
inline bool applySiegeMode(df::building_siegeenginest& engine,int32_t action) {
    if(!siegeControlsReady() || action<0 || action>4 || int(engine.type)<0 || int(engine.type)>2 || engine.jobs.size()>4096)return false;
    for(auto* job:engine.jobs)if(!job || job->general_refs.size()>4096)return false;
    engine.action=static_cast<df::siegeengine_action>(action);
    if(action>1)return true;
    for(size_t i=engine.jobs.size();i-->0;) {
        auto* job=engine.jobs[i];const int type=int(job->job_type);
        if(int(engine.type)==2?type==247:type==137 || type==138) {
            if(!df3d_area::nativeRemoveBuildingJob(engine,*job))return false;
            i=std::min(i,engine.jobs.size());
        }
    }
    return true;
}
struct SiegeControls {
    int32_t id=-1,type=-1,action=-1,resting=-1,facing=-1;
    bool removing=false;
    uint64_t revision=0;
};
inline std::optional<SiegeControls> siegeControls(df::building* building) {
    if(!building || building->getType()!=df::building_type::SiegeEngine || !siegeControlsReady() ||
        building->getBuildStage()!=building->getMaxBuildStage())return {};
    auto& engine=*static_cast<df::building_siegeenginest*>(building);
    SiegeControls result;result.id=engine.id;result.type=int(engine.type);result.action=int(engine.action);
    result.resting=int(engine.resting_orientation);result.facing=int(engine.facing);
    if(result.id<0 || result.type<0 || result.type>2 || result.action<0 || result.action>4 || result.resting<0 || result.resting>7 || result.facing<0 || result.facing>7 || engine.jobs.size()>4096)return {};
    uint64_t hash=UINT64_C(14695981039346656037);
    const auto add=[&](uint64_t value){for(int i=0;i<8;++i){hash^=uint8_t(value);hash*=UINT64_C(1099511628211);value>>=8;}};
    add(result.id);add(result.type);add(result.action);add(result.resting);add(result.facing);
    add(engine.getBuildStage());add(engine.getMaxBuildStage());add(engine.centerx);add(engine.centery);add(engine.z);
    add(engine.jobs.size());
    for(auto* job:engine.jobs) {
        if(!job || job->general_refs.size()>4096)return {};
        add(job->id);add(int(job->job_type));add(job->flags.whole);
        if(job->job_type==df::job_type::DestroyBuilding)result.removing=true;
    }
    result.revision=(hash&INT64_MAX)|1;return result;
}
enum class SiegeOutcome:uint8_t { Rejected, Completed, Stale, Unknown };
struct SiegeEdit {
    SiegeOutcome outcome=SiegeOutcome::Rejected;
    bool effectsStarted=false;
    std::optional<SiegeControls> receipt;
};
inline SiegeEdit setSiegeControl(df::building* building,uint64_t expected,int32_t value,bool resting) {
    SiegeEdit result;
    try {
        const auto before=siegeControls(building);
        if(!before || !expected || expected>INT64_MAX || value<0 || value>(resting?7:4))return result;
        if(before->revision!=expected){result.outcome=SiegeOutcome::Stale;return result;}
        if(before->removing || (resting && before->type!=2))return result;
        auto& engine=*static_cast<df::building_siegeenginest*>(building);
        result.effectsStarted=true;result.outcome=SiegeOutcome::Unknown;
        if(resting)engine.resting_orientation=static_cast<df::siegeengine_orientation>(value);
        else if(!applySiegeMode(engine,value))return result;
        const auto after=siegeControls(building);
        if(!after || (resting?after->resting:after->action)!=value || after->facing!=before->facing ||
            (resting?after->action!=before->action:after->resting!=before->resting))return result;
        result.receipt=after;result.outcome=SiegeOutcome::Completed;
    }catch(...){}
    return result;
}
}
