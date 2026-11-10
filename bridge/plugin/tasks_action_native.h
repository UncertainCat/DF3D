#pragma once
#include "tasks_native.h"

namespace df3d_tasks {
enum class Action { Repeat, Suspend, RemoveWorker };
enum class Outcome { Unsupported, Rejected, Applied, Unknown };
// Caller owns epoch/save admission and receipt deduplication. Rebuild owned
// eligibility and compare displayed identities/state at the same safe point.
// Never replay Unknown: cancellation can retire a job and release its items.
inline Outcome apply(Action action,int32_t jobId,int32_t workerId,int32_t buildingId,bool expectedState) {
    const auto current=rows();if(!current)return Outcome::Unsupported;
    const Row* row=nullptr;
    for(const auto& value:*current)if(value.jobId==jobId){row=&value;break;}
    if(!row || row->unitId!=workerId || row->buildingId!=buildingId)return Outcome::Rejected;
    if(action==Action::Repeat && (!row->canRepeat || row->repeating!=expectedState))return Outcome::Rejected;
    if(action==Action::Suspend && (!row->canSuspend || row->suspended!=expectedState))return Outcome::Rejected;
    if(action==Action::RemoveWorker && !row->canRemoveWorker)return Outcome::Rejected;
    if(action!=Action::Repeat && action!=Action::Suspend && action!=Action::RemoveWorker)return Outcome::Rejected;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool pinned=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x397a53,0xbd,UINT64_C(0xa6abd76bfb819f41)},
            {0x57c760,0xa1,UINT64_C(0xebf853982f9617cd)},
            {0x1325080,0x33c3,UINT64_C(0xf84d63b3115de7d1)},
        };
        for(const auto& p:pins){uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<p.length;++i){h^=base[p.rva+i];h*=UINT64_C(1099511628211);}if(h!=p.hash)return false;}
        return true;
    }();
    if(!pinned)return Outcome::Unsupported;
    df::job* job=nullptr;
    for(auto* link=df::global::world->jobs.list.next;link;link=link->next)if(link->item->id==jobId){job=link->item;break;}
    auto* worker=workerId<0?nullptr:df::unit::find(workerId);
    auto* building=buildingId<0?nullptr:df::building::find(buildingId);
    if(!job || !building || (workerId>=0 && (!worker || worker->job.current_job!=job)))return Outcome::Rejected;
    try {
        if(action==Action::Repeat)job->flags.whole^=1;
        else if(action==Action::Suspend){
            job->flags.whole^=2;
            if(!expectedState && worker)
                reinterpret_cast<void (*)(df::unit*,bool,int32_t,bool,void*)>(base+0x1325080)(worker,false,0,false,nullptr);
        } else {
            // Native adds a 100-tick building claim suppression before releasing
            // this worker. Omitting it lets the same worker immediately reclaim.
            reinterpret_cast<void (*)(df::building*,df::unit*)>(base+0x57c760)(building,worker);
            reinterpret_cast<void (*)(df::unit*,bool,int32_t,bool,void*)>(base+0x1325080)(worker,false,0,false,nullptr);
        }
        return Outcome::Applied;
    } catch(...) {return Outcome::Unknown;}
}
}
