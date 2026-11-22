#pragma once
#include "zone_native.h"
#include "df/building_chainst.h"
#include "df/world.h"
#include "df/unit.h"
#include "df/job.h"
#include "df/building_cagest.h"
#include "df/building_civzonest.h"
#include <unordered_set>
#include <algorithm>
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
// The native picker callback also reads active_sheet and mutates popup state.
// Never call it. Its semantic sequence is shared with the body-row action;
// the standalone zone detach performs the same reverse membership/ref removal.
inline bool chainAssignmentReady() {
    if(!chainCandidatesReady() || !df3d_area::nativeZoneAnimalAssignmentReady())return false;
    static const bool ready=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0xbb;++i){hash^=base[0x13adf80+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0xa24dfa60a95195ec);
    }();return ready;
}

// Safe-point primitive: the request owner must validate epoch/revision and mark
// Unknown before entry. False after entry can represent partial native effects;
// never replay automatically. A row toggle can select a chained-only occupant.
inline bool chainAssign(df::building_chainst& chain,int32_t id,bool toggleRow) {
    if(!chainAssignmentReady() || chain.getBuildStage()!=chain.getMaxBuildStage() ||
        chain.isJusticeRestraint())return false;
    for(auto* job:chain.jobs)
        if(job && job->job_type==df::job_type::DestroyBuilding)return false;
    auto* unit=df::unit::find(id);if(!unit)return false;
    if(toggleRow) {
        if(chain.assigned!=unit && chain.chained!=unit)return false;
    } else {
        const auto candidates=chainCandidates(chain);if(!candidates)return false;
        if(std::none_of(candidates->begin(),candidates->end(),[id](const auto& row){return row.id==id;}))return false;
    }
    auto* assigned=toggleRow && chain.assigned==unit?nullptr:unit;
    const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    reinterpret_cast<void (*)(df::unit*)>(base+0x8bfcf0)(unit);
    reinterpret_cast<void (*)(df::unit*)>(base+0x13adf80)(unit);
    if(!df3d_area::nativeDetachAnimalChains(*unit,&chain))return false;
    if(chain.chained==unit && assigned==unit &&
        !df3d_area::nativeRemoveAnimalChainJobs(chain,true))return false;
    chain.assigned=assigned;
    return true;
}

struct ChainSnapshot {
    int32_t buildingId=-1,assignedId=-1,chainedId=-1;
    uint64_t revision=0;
    bool removing=false;
    std::vector<df3d_area::ZoneAnimalCandidate> candidates;
};
// Revisions include memberships and jobs that a transfer would retire, not
// merely the destination. The enclosing owner still validates session/epoch.
inline std::optional<ChainSnapshot> observeChain(df::building* building) {
    if(!building || building->getType()!=df::building_type::Chain)return {};
    auto& chain=*static_cast<df::building_chainst*>(building);
    auto candidates=chainCandidates(chain);if(!candidates)return {};
    ChainSnapshot result;result.buildingId=chain.id;result.candidates=std::move(*candidates);
    result.assignedId=chain.assigned?chain.assigned->id:-1;
    result.chainedId=chain.chained?chain.chained->id:-1;
    uint64_t hash=UINT64_C(14695981039346656037);
    const auto add=[&](uint64_t value) {
        for(int i=0;i<8;++i){hash^=uint8_t(value);hash*=UINT64_C(1099511628211);value>>=8;}
    };
    const auto jobs=[&](df::building& source) {
        if(source.jobs.size()>4096)return false;
        add(source.jobs.size());
        for(auto* job:source.jobs) {
            if(!job || job->general_refs.size()>4096)return false;
            add(job->id);add(int32_t(job->job_type));add(job->flags.whole);
        }
        return true;
    };
    add(chain.id);add(chain.centerx);add(chain.centery);add(chain.z);
    add(chain.getBuildStage());add(chain.getMaxBuildStage());add(chain.chain_flags.whole);
    add(result.assignedId);add(result.chainedId);
    if(!jobs(chain))return {};
    for(auto* job:chain.jobs)if(job->job_type==df::job_type::DestroyBuilding)result.removing=true;
    std::vector<int32_t> ids;std::unordered_set<int32_t> seen;
    const auto append=[&](int32_t id){if(id>=0 && seen.insert(id).second)ids.push_back(id);};
    for(const auto& row:result.candidates)append(row.id);
    append(result.assignedId);append(result.chainedId);add(ids.size());
    const auto contains=[](const auto& values,int32_t id) {
        return std::find(values.begin(),values.end(),id)!=values.end();
    };
    for(auto id:ids) {
        auto* unit=df::unit::find(id);if(!unit)return {};
        add(id);add(unit->flags1.whole);add(unit->flags2.whole);
        add(unit->job.current_job?unit->job.current_job->id:-1);
        for(auto* source:df::global::world->buildings.other.CAGE) {
            if(!source || source->assigned_units.size()>4096)return {};
            if(contains(source->assigned_units,id))add(source->id);
        }
        add(UINT64_MAX);
        for(auto* source:df::global::world->buildings.other.ANY_ZONE) {
            if(!source || source->assigned_units.size()>4096)return {};
            if(contains(source->assigned_units,id))add(source->id);
        }
        add(UINT64_MAX-1);
        for(auto* source:df::global::world->buildings.other.CHAIN) {
            if(!source || source->assigned!=unit)continue;
            add(source->id);if(!jobs(*source))return {};
        }
        add(UINT64_MAX-2);
    }
    result.revision=(hash&INT64_MAX)|1;return result;
}
enum class ChainOutcome:uint8_t { Unavailable, Completed, Stale, Unknown };
struct ChainEdit {
    ChainOutcome outcome=ChainOutcome::Unavailable;
    bool effectsStarted=false;
    std::optional<ChainSnapshot> receipt;
};
inline ChainEdit setChainAssignment(df::building* building,uint64_t expected,int32_t id,bool toggleRow) {
    ChainEdit result;
    try {
        const auto before=observeChain(building);
        if(!before || id<0 || !expected || expected>INT64_MAX || !chainAssignmentReady())return result;
        if(before->revision!=expected){result.outcome=ChainOutcome::Stale;return result;}
        if(before->removing)return result;
        if(toggleRow) {
            if(before->assignedId!=id && before->chainedId!=id)return result;
        } else if(std::none_of(before->candidates.begin(),before->candidates.end(),
            [id](const auto& row){return row.id==id;}))return result;
        const auto desired=toggleRow && before->assignedId==id?-1:id;
        result.effectsStarted=true;result.outcome=ChainOutcome::Unknown;
        if(!chainAssign(*static_cast<df::building_chainst*>(building),id,toggleRow))return result;
        const auto after=observeChain(building);
        if(!after || after->assignedId!=desired || after->chainedId!=before->chainedId)return result;
        result.receipt=after;result.outcome=ChainOutcome::Completed;
    }catch(...){}
    return result;
}

}
