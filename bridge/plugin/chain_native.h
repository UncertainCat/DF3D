#pragma once
#include "zone_native.h"
#include "df/building_chainst.h"
#include "df/world.h"
#include "df/unit.h"
#include <windows.h>
#include <optional>
#include <vector>
namespace df3d_production {
inline bool chainCandidatesReady() {
    if(!df::global::world || !df3d_area::nativeZoneOwnerCandidatesReady())return false;
    static_assert(offsetof(df::building_chainst,assigned)==0x148);
    static const bool ready=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        const auto pin=[base](size_t at,size_t size,uint64_t expected) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<size;++i){hash^=base[at+i];hash*=UINT64_C(1099511628211);}
            return hash==expected;
        };
        return pin(0x3d5550,0x5a,UINT64_C(0xf7b598544fb03748)) &&
            pin(0x13673b0,0x78,UINT64_C(0x521808bb91dbc4fb));
    }();return ready;
}
inline std::optional<std::vector<df3d_area::ZoneAnimalCandidate>> chainCandidates(df::building_chainst& chain) {
    if(!chainCandidatesReady() || chain.getBuildStage()!=chain.getMaxBuildStage() || chain.isJusticeRestraint())return {};
    // The pinned exclusion predicate reads only the semantic chain and unit.
    // Supply its capture layout independently; no widget, filter or selection
    // storage is read or borrowed. Search and display ordering are separate.
    struct Context {void* unused;df::building_chainst* chain;};
    struct Entry {df::unit* unit;uint8_t item;uint8_t padding[7];};
    static_assert(sizeof(Context)==16 && sizeof(Entry)==16);
    Context context{nullptr,&chain};
    using Excluded=bool(*)(const Context*,const Entry*);
    const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    const auto excluded=reinterpret_cast<Excluded>(base+0x3d5550);
    std::vector<df3d_area::ZoneAnimalCandidate> result;
    for(auto* unit:df::global::world->units.active) {
        if(!unit)continue;
        Entry entry{unit,0,{}};
        if(excluded(&context,&entry))continue;
        if(result.size()>=4096)return {};
        result.push_back({unit->id,false,false});
    }
    return result;
}
}
