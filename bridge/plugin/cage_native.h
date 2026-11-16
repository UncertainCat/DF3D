#pragma once
#include "zone_native.h"
#include "df/building_cagest.h"
#include "df/world.h"
#include "df/unit.h"
#include "df/item.h"
#include "df/item_critter.h"
#include "df/building_civzonest.h"
#include "df/building_chainst.h"
#include "df/job.h"
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

struct CageSnapshot {
    int32_t buildingId=-1;
    uint64_t revision=0;
    bool removing=false,justiceRestraint=false;
    std::vector<df3d_area::ZoneAnimalCandidate> candidates;
};

// Recompute authority from semantic facts at the request's safe point. Include
// prior assignments that the native callback would retire, not just membership
// of the destination cage. The enclosing request owner supplies session/epoch.
inline std::optional<CageSnapshot> observeCage(df::building* building) {
    if(!building || building->getType()!=df::building_type::Cage)return {};
    auto& cage=*static_cast<df::building_cagest*>(building);
    auto candidates=cageCandidates(cage);if(!candidates)return {};
    CageSnapshot result;result.buildingId=cage.id;result.candidates=std::move(*candidates);
    uint64_t hash=UINT64_C(14695981039346656037);
    const auto add=[&](uint64_t value) {
        for(int i=0;i<8;++i){hash^=uint8_t(value);hash*=UINT64_C(1099511628211);value>>=8;}
    };
    result.justiceRestraint=cage.isJusticeRestraint();add(result.justiceRestraint);
    add(cage.id);add(cage.cage_flags.whole);add(cage.centerx);add(cage.centery);add(cage.z);
    for(auto* job:cage.jobs)if(job) {
        add(job->id);add(int32_t(job->job_type));
        if(job->job_type==df::job_type::DestroyBuilding)result.removing=true;
    }
    add(result.candidates.size());
    const auto contains=[](const auto& values,int32_t id) {
        return std::find(values.begin(),values.end(),id)!=values.end();
    };
    for(const auto& row:result.candidates) {
        add(row.id);add(row.item);add(row.assigned);
        if(row.item) {
            auto* item=df::item::find(row.id);if(!item)return {};
            add(item->flags.whole);add(item->getMaterial());add(item->getMaterialIndex());
        } else {
            auto* unit=df::unit::find(row.id);if(!unit)return {};
            add(unit->flags1.whole);add(unit->flags2.whole);
            add(unit->job.current_job?unit->job.current_job->id:-1);
        }
        add(1);
        for(auto* source:df::global::world->buildings.other.CAGE)
            if(source && contains(row.item?source->assigned_items:source->assigned_units,row.id))add(source->id);
        add(UINT64_MAX);
        for(auto* source:df::global::world->buildings.other.ANY_ZONE)
            if(source && contains(row.item?source->assigned_items:source->assigned_units,row.id))add(source->id);
        add(UINT64_MAX-1);
        if(!row.item)for(auto* chain:df::global::world->buildings.other.CHAIN) {
            if(!chain || !chain->assigned || chain->assigned->id!=row.id)continue;
            add(chain->id);
            for(auto* job:chain->jobs)if(job){add(job->id);add(int32_t(job->job_type));}
            add(UINT64_MAX-2);
        }
        add(UINT64_MAX-3);
    }
    result.revision=(hash&INT64_MAX)|1;
    return result;
}

enum class CageOutcome:uint8_t { Unavailable, Completed, Stale, Unknown };
struct CageEdit {
    CageOutcome outcome=CageOutcome::Unavailable;
    bool effectsStarted=false;
    std::optional<CageSnapshot> receipt;
};
inline CageEdit setCageAssignment(df::building* building,uint64_t expected,int32_t id,bool item,bool assigned) {
    CageEdit result;
    try {
        const auto before=observeCage(building);
        if(!before || !expected || expected>INT64_MAX || !cageAssignmentReady())return result;
        if(before->revision!=expected){result.outcome=CageOutcome::Stale;return result;}
        if(before->removing || before->justiceRestraint)return result;
        const auto found=std::find_if(before->candidates.begin(),before->candidates.end(),[&](const auto& row) {
            return row.id==id && row.item==item;
        });
        if(found==before->candidates.end())return result;
        if(found->assigned==assigned) {
            result.outcome=CageOutcome::Completed;result.receipt=before;return result;
        }
        result.effectsStarted=true;result.outcome=CageOutcome::Unknown;
        if(!cageAssign(*static_cast<df::building_cagest*>(building),id,item,assigned))return result;
        const auto after=observeCage(building);if(!after)return result;
        const auto current=std::find_if(after->candidates.begin(),after->candidates.end(),[&](const auto& row) {
            return row.id==id && row.item==item;
        });
        // An unassigned row may cease to be eligible. Absence is never success
        // for an assignment, and a still-assigned row is never successful removal.
        if(current==after->candidates.end()?assigned:current->assigned!=assigned)return result;
        result.receipt=after;result.outcome=CageOutcome::Completed;
    }catch(...){}
    return result;
}
}
