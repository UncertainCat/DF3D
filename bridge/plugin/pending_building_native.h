#pragma once
#include "building_header_transaction.h"
#include "df/building.h"
#include "df/job.h"
#include "df/job_type.h"
#include "df/unit.h"
#include "df/world.h"
#include "df/global_objects.h"
#include "modules/Maps.h"
#include <windows.h>

namespace df3d_production {
struct PendingBuildingObservation {
    int32_t id=-1,type=-1,stage=-1,maxStage=-1,jobId=-1;
    uint32_t jobFlags=0;
    bool removing=false;
    std::vector<int32_t> workers;
    uint64_t revision=0;
};
inline bool pendingBuildingNativeReady() {
    static const bool ready=[] {
        auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x1b00db,0xfc,UINT64_C(0x0c880dc02930d496)},
            {0x1b01ef,0x4e,UINT64_C(0xb616d79c06ae2817)},
            {0x1325080,0x33c3,UINT64_C(0xf84d63b3115de7d1)},
            {0x587d80,0xc98,UINT64_C(0x0f7410a976032a15)},
            {0x54c130,0xe6,UINT64_C(0xcab44276dbb81fae)},
        };
        for(const auto& p:pins){uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<p.length;++i){h^=base[p.rva+i];h*=UINT64_C(1099511628211);}if(h!=p.hash)return false;}
        return true;
    }();
    return ready;
}
inline std::optional<PendingBuildingObservation> observePendingBuilding(df::building* building) {
    auto* world=df::global::world;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    if(!pendingBuildingNativeReady() || !world || !building ||
       reinterpret_cast<uint8_t*>(&world->units.active)!=base+0x23e50c8 ||
       building->getType()==df::building_type::Stockpile || building->getType()==df::building_type::Civzone || building->jobs.size()>32767)return {};
    auto* designation=DFHack::Maps::getTileDesignation(building->centerx,building->centery,building->z);
    if(!designation || designation->bits.hidden)return {};
    PendingBuildingObservation value;value.id=building->id;value.type=int32_t(building->getType());
    value.stage=building->getBuildStage();value.maxStage=building->getMaxBuildStage();
    if(value.stage<0 || value.stage>=value.maxStage)return {};
    auto* first=building->jobs.empty()?nullptr:building->jobs.front();
    if(!building->jobs.empty() && (!first || (first->job_type!=df::job_type::ConstructBuilding && first->job_type!=df::job_type::DestroyBuilding)))return {};
    if(first){value.jobId=first->id;value.jobFlags=first->flags.whole;}
    uint64_t hash=UINT64_C(14695981039346656037);
    const auto number=[&](uint64_t n){for(int i=0;i<8;++i){hash^=uint8_t(n);hash*=UINT64_C(1099511628211);n>>=8;}};
    for(int32_t n:{value.id,value.type,value.stage,value.maxStage,building->centerx,building->centery,int32_t(building->z)})number(n);
    number(building->jobs.size());
    for(const auto* job:building->jobs){if(!job)return {};value.removing|=job->job_type==df::job_type::DestroyBuilding;number(job->id);number(int32_t(job->job_type));number(job->flags.whole);}
    // Native1b012a scans active units, not job references or a UI worker list.
    for(const auto* unit:world->units.active) {
        if(!unit)return {};
        if(first && !unit->flags1.bits.inactive && unit->job.current_job==first)value.workers.push_back(unit->id);
    }
    number(value.workers.size());for(auto id:value.workers)number(id);
    value.revision=(hash&INT64_MAX)?(hash&INT64_MAX):1;return value;
}
enum class PendingBuildingOperation { Resume, Suspend, Cancel, CancelRemoval };
struct PendingBuildingEdit {
    BuildingHeaderOutcome outcome=BuildingHeaderOutcome::Rejected;
    bool mutated=false,removed=false,removing=false;
    std::optional<PendingBuildingObservation> receipt;
};
// Safe-point caller owns epoch/save admission. Native leaves own job, item and
// worker cleanup. After cancellation, never dereference the original pointer.
inline PendingBuildingEdit editPendingBuilding(df::building* building,uint64_t expected,PendingBuildingOperation operation) {
    PendingBuildingEdit result;const auto before=observePendingBuilding(building);
    if(!before || !expected)return result;
    if(before->revision!=expected){result.outcome=BuildingHeaderOutcome::Stale;return result;}
    if(operation!=PendingBuildingOperation::Resume && operation!=PendingBuildingOperation::Suspend && operation!=PendingBuildingOperation::Cancel && operation!=PendingBuildingOperation::CancelRemoval)return result;
    const bool cancel=operation==PendingBuildingOperation::Cancel;
    const bool cancelRemoval=operation==PendingBuildingOperation::CancelRemoval;
    const bool suspend=operation==PendingBuildingOperation::Suspend;
    if(before->removing!=cancelRemoval || (!cancel && !cancelRemoval && before->jobId<0))return result;
    if(!cancel && !cancelRemoval && bool(before->jobFlags&2)==suspend){result.outcome=BuildingHeaderOutcome::Completed;result.receipt=before;return result;}
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    result.mutated=true;result.outcome=BuildingHeaderOutcome::Unknown;
    try {
        if(cancelRemoval) {
            reinterpret_cast<void (*)(df::building*)>(base+0x54c130)(building);
            const auto after=observePendingBuilding(df::building::find(before->id));
            if(!after || after->stage!=before->stage || after->maxStage!=before->maxStage || after->removing || after->jobId!=-1)return result;
            result.receipt=after;
        } else if(cancel) {
            if(before->stage==0)reinterpret_cast<void (*)(df::building*,bool,bool,bool)>(base+0x587d80)(building,false,false,false);
            else building->queueDestroy();
            auto* current=df::building::find(before->id);
            if(before->stage==0){if(current)return result;result.removed=true;}
            else {
                if(!current)return result;
                for(const auto* job:current->jobs)if(job && job->job_type==df::job_type::DestroyBuilding)result.removing=true;
                if(!result.removing)return result;
            }
        } else {
            building->jobs.front()->flags.bits.suspend=suspend;
            if(suspend)for(auto id:before->workers) {
                auto* worker=df::unit::find(id);
                if(!worker)return result;
                reinterpret_cast<void (*)(df::unit*,bool,int32_t,bool,void*)>(base+0x1325080)(worker,false,0,false,nullptr);
            }
            const auto after=observePendingBuilding(df::building::find(before->id));
            if(!after || after->jobId!=before->jobId || bool(after->jobFlags&2)!=suspend || (suspend && !after->workers.empty()))return result;
            result.receipt=after;
        }
        result.outcome=BuildingHeaderOutcome::Completed;
    }catch(...){}
    return result;
}
}
