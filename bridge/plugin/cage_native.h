#pragma once
#include "zone_native.h"
#include "df/building_cagest.h"
#include "df/world.h"
#include "df/unit.h"
#include "df/item.h"
#include "df/item_critter.h"
#include <windows.h>
#include <algorithm>
#include <unordered_set>

namespace df3d_production {
// Safe-point semantic reads. The native widget producer is fingerprinted only
// to establish its iteration/admission contract; it is never called or read.
inline bool cageCandidatesReady() {
    if(!df::global::world || !df3d_area::nativeZoneOwnerCandidatesReady())return false;
    static_assert(offsetof(df::building_cagest,assigned_units)==0x148);
    static_assert(offsetof(df::building_cagest,assigned_items)==0x160);
    static_assert(offsetof(df::building_cagest,cage_flags)==0x178);
    static const bool ready=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        const auto pin=[&](size_t at,size_t count,uint64_t expected) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<count;++i){hash^=base[at+i];hash*=UINT64_C(1099511628211);}
            return hash==expected;
        };
        return pin(0x3a5940,0x4e9,UINT64_C(0x1723e1e18c2074af)) &&
            pin(0x576df0,0x155,UINT64_C(0xfaa0d2e7889c710a)) &&
            pin(0x576f50,0xe7,UINT64_C(0x33a236fc0d3e9e5e));
    }();
    return ready;
}

inline std::optional<std::vector<df3d_area::ZoneAnimalCandidate>> cageCandidates(df::building_cagest& cage) {
    if(!cageCandidatesReady() || cage.getBuildStage()!=cage.getMaxBuildStage())return {};
    if(cage.assigned_units.size()>4096 || cage.assigned_items.size()>4096-cage.assigned_units.size())return {};
    const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    using UnitEligible=bool(__fastcall*)(df::building_cagest*,df::unit*);
    using CritterEligible=bool(__fastcall*)(df::building_cagest*,int16_t,int16_t);
    std::vector<df3d_area::ZoneAnimalCandidate> result;
    std::unordered_set<int32_t> units(cage.assigned_units.begin(),cage.assigned_units.end());
    std::unordered_set<int32_t> items(cage.assigned_items.begin(),cage.assigned_items.end());
    const auto append=[&](int32_t id,bool item,bool assigned) {
        if(result.size()>=4096)return false;
        result.push_back({id,item,assigned});return true;
    };
    // Existing assignments are retained even when no longer eligible. Missing
    // IDs are omitted exactly as in native3a5a16..3a5c43.
    for(auto id:cage.assigned_units)if(df::unit::find(id) && !append(id,false,true))return {};
    for(auto id:cage.assigned_items)if(df::item::find(id) && !append(id,true,true))return {};
    for(auto* unit:df::global::world->units.active) {
        if(!unit || unit->flags1.bits.inactive || unit->flags2.bits.locked_in_for_trading)continue;
        if(!reinterpret_cast<UnitEligible>(base+0x576df0)(&cage,unit))continue;
        if(!units.count(unit->id) && !append(unit->id,false,false))return {};
    }
    for(auto* item:df::global::world->items.other.ANY_CRITTER) {
        if(!item || item->flags.bits.trader)continue;
        // For critter items these material getters return race/caste. Match
        // native's virtual slots2/3, including its signed16 narrowing.
        if(!reinterpret_cast<CritterEligible>(base+0x576f50)(&cage,item->getMaterial(),int16_t(item->getMaterialIndex())))continue;
        if(!items.count(item->id) && !append(item->id,true,false))return {};
    }
    return result;
}

inline bool cageAssignmentReady() {
    if(!cageCandidatesReady() || !df3d_area::nativeZoneAnimalAssignmentReady())return false;
    static const bool ready=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x232;++i){hash^=base[0x3cdd20+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0x9b8bbbda52deb6c3);
    }();
    return ready;
}

// Caller resolves the current cage and candidate at one safe point and owns
// epoch/revision checks. Native effects may partially complete; mark uncertainty
// before entry and never automatically retry. No UI callback object is borrowed.
inline bool cageAssign(df::building_cagest& cage,int32_t id,bool item,bool assign) {
    if(!cageAssignmentReady())return false;
    const auto candidates=cageCandidates(cage);if(!candidates)return false;
    const auto found=std::find_if(candidates->begin(),candidates->end(),[&](const auto& row) {
        return row.id==id && row.item==item;
    });
    if(found==candidates->end())return false;
    if(found->assigned==assign)return true;
    struct Entry { void* object; uint8_t kind; uint8_t padding[7]{}; };
    static_assert(sizeof(Entry)==16);
    Entry entry{};entry.kind=item?1:0;
    if(item)entry.object=df::item::find(id);
    else entry.object=df::unit::find(id);
    if(!entry.object)return false;
    // The native callback clears cage/chain assignment on both select and
    // deselect. Pre-detach chains semantically so its subsequent helper sees
    // no assigned chain and cannot enter native selection/cursor bookkeeping.
    if(!item && !df3d_area::nativeDetachAnimalRestraints(*static_cast<df::unit*>(entry.object)))return false;
    auto* context=&cage;
    const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    using Apply=bool(__fastcall*)(df::building_cagest**,Entry*,bool);
    return reinterpret_cast<Apply>(base+0x3cdd20)(&context,&entry,assign);
}
}
