#pragma once
#include "places_native.h"

namespace df3d_places {
enum class ActionOutcome { Unsupported, Rejected, Applied, Unknown };
// Safe-point caller owns save/epoch admission and receipt deduplication. -1
// targets all current engines, collected privately rather than from the menu.
// Native has no separate setter: its feed writes action, then invokes the
// simulation job destructor for firing jobs when selecting action 0 or 1.
inline ActionOutcome siegeAction(int32_t buildingId,int32_t action) {
    if(buildingId < -1 || action<0 || action>4)return ActionOutcome::Rejected;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool pinned=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x39a2d0,0x1ce,UINT64_C(0x779b5b81609ed09c)},
            {0x39a554,0x116,UINT64_C(0x4a391436f17d0e33)},
            {0x39aad5,0xe5,UINT64_C(0x879c307e377d5110)},
            {0xa67820,0xcc,UINT64_C(0x506ce8a2c4eefca6)},
        };
        for(const auto& p:pins){uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<p.length;++i){h^=base[p.rva+i];h*=UINT64_C(1099511628211);}if(h!=p.hash)return false;}
        return true;
    }();
    if(!pinned)return ActionOutcome::Unsupported;
    const auto current=lists();if(!current)return ActionOutcome::Unsupported;
    std::vector<df::building_siegeenginest*> targets;
    for(auto id:(*current)[5])if(buildingId==-1 || id==buildingId){
        auto* engine=virtual_cast<df::building_siegeenginest>(df::building::find(id));
        if(!engine || engine->jobs.size()>1048576)return ActionOutcome::Rejected;
        for(auto* job:engine->jobs)if(!job)return ActionOutcome::Rejected;
        targets.push_back(engine);
    }
    if(buildingId!=-1 && targets.size()!=1)return ActionOutcome::Rejected;
    static_assert(offsetof(df::building_siegeenginest,action)==0x14c);
    try {
        for(auto* engine:targets){
            engine->action=static_cast<df::siegeengine_action>(action);
            if(action>1)continue;
            // Reload the vector after cancellation; the native destructor erases
            // the job. Reverse traversal preserves the remaining indices.
            for(size_t i=engine->jobs.size();i>0;--i){
                auto* job=engine->jobs[i-1];const int type=int(job->job_type);
                if(int(engine->type)==2 ? type==247 : type==137 || type==138)
                    reinterpret_cast<void(*)(df::job*)>(base+0xa67820)(job);
            }
        }
        return ActionOutcome::Applied;
    }catch(...){return ActionOutcome::Unknown;}
}
}
