#pragma once
#include "farm_native.h"
#include "df/unit.h"
#include "modules/Job.h"

namespace df3d_production {
enum class PriorityOutcome { Rejected, Applied, Unknown };
// Native1ad296..1ad3ff inlines this effect in the sheet's feed handler.
// Use simulation records only; never invoke the handler or its menu iterator.
inline PriorityOutcome setWorkshopPriority(int32_t buildingId,int32_t jobId,bool expected,bool desired) {
    if(expected==desired || !farmFunctions())return PriorityOutcome::Rejected;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool pinned=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        for(const auto& p:{Pin{0x1ad296,0x169,UINT64_C(0x20c8c67bd84fb457)},
                           Pin{0x1325080,0x33c3,UINT64_C(0xf84d63b3115de7d1)}}) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<p.length;++i){hash^=base[p.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=p.hash)return false;
        }
        return true;
    }();
    auto* building=df::building::find(buildingId);
    if(!pinned || !building || !df::global::world || building->jobs.size()>64)return PriorityOutcome::Rejected;
    auto found=std::find_if(building->jobs.begin(),building->jobs.end(),[jobId](auto* j){return j && j->id==jobId;});
    if(found==building->jobs.end())return PriorityOutcome::Rejected;
    auto* job=*found;
    if(DFHack::Job::getHolder(job)!=building || job->flags.bits.do_now!=expected)return PriorityOutcome::Rejected;
    size_t index=size_t(found-building->jobs.begin());
    try {
        job->flags.bits.do_now=desired;
        if(desired)while(building->jobs.size()>1 && index>0 && index<building->jobs.size()) {
            std::swap(building->jobs[index],building->jobs[index-1]);
            // Native cancellation can alter the queue. Recheck its bounds,
            // and do not retain a displaced job pointer across cancellation.
            for(size_t i=0;i<df::global::world->units.active.size();++i) {
                auto* unit=df::global::world->units.active[i];
                if(index>=building->jobs.size())return PriorityOutcome::Unknown;
                if(unit && !unit->flags1.bits.inactive && unit->job.current_job==building->jobs[index])
                    reinterpret_cast<void (*)(df::unit*,bool,int32_t,bool,void*)>(base+0x1325080)(unit,false,0,false,nullptr);
            }
            --index;
        }
        return PriorityOutcome::Applied;
    }catch(...){return PriorityOutcome::Unknown;}
}
}
