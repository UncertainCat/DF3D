#pragma once
#include "df/building_civzonest.h"
#include "creature_labor_native.h"
#include "location_staff_order_native.h"
#include "workshop_job_native.h"

namespace df3d_production {
// Native3a54cc..3a5716 configures builtin skill weights inline in a widget.
// Retain that configuration in owned storage; never construct the widget.
inline std::optional<std::vector<std::pair<int32_t,int32_t>>> workshopWorkerSkills(df::building* building) {
    static const bool supported=[] {
        if(!farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x3a54cc,0x24a,UINT64_C(0x5f6df49bd46eff00)},
            {0x3a58c4,0x78,UINT64_C(0xdf4789b1f28508a8)},
            {0x5b0a00,0xc1,UINT64_C(0x7e97c2b621fe9d11)},
            {0xd082e0,0xa54,UINT64_C(0x0eada8cd99e75ec8)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();
    if(!supported || !building || !df::global::world)return std::nullopt;
    using Weights=std::vector<std::pair<int32_t,int32_t>>;
    static const Weights workshop[]={
        {{2,1}},{{16,1},{17,1},{18,1},{19,1},{107,1},{108,1},{115,1}},{{136,1}},
        {{31,1},{131,1},{132,1},{32,1},{36,1},{113,1}},{{29,1},{30,2}},
        {{26,3},{27,3},{28,2}},{{26,3},{27,3},{28,2}},{{48,1}},{{54,1}},
        {{46,1}},{{10,1}},{{35,1}},{{12,1}},{{15,1}},{{9,1},{7,1}},
        {{14,1}},{{13,1}},{{16,1}},{{11,1},{8,1}},{{20,1}},{{64,1},{66,1}},{{67,1}},{{16,1}}
    };
    static const Weights furnace[]={{{63,1}},{{24,1}},{{34,1}},{{109,1},{110,1}},{{24,1}},{{34,1}},{{109,1},{110,1}}};
    std::array<int32_t,149> weights{};
    const auto type=building->getType();const auto subtype=building->getSubtype();
    const Weights* builtin=nullptr;
    if(type==df::building_type::Workshop){if(subtype>=0 && subtype<23)builtin=&workshop[subtype];}
    else if(type==df::building_type::Furnace){if(subtype>=0 && subtype<7)builtin=&furnace[subtype];}
    else return std::nullopt;
    if(builtin)for(const auto& [id,weight]:*builtin)weights[id]=weight;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    using Matches=bool (*)(df::building*,df::reaction*,int32_t*);
    using Skill=int16_t (*)(int16_t,int32_t,int16_t,int32_t,int32_t,const std::string*);
    const auto& reactions=df::global::world->raws.reactions.reactions;
    for(size_t i=0;i<reactions.size();++i) {
        const auto allowed=workshopReactionAllowed(int32_t(i));if(!allowed)return std::nullopt;
        if(!*allowed)continue;
        auto* reaction=reactions[i];int32_t category=0;
        if(!reinterpret_cast<Matches>(base+0x5b0a00)(building,reaction,&category))continue;
        const std::string code=reaction->code;
        const int16_t skill=reinterpret_cast<Skill>(base+0xd082e0)(209,-1,-1,-1,0,&code);
        if(skill==-1)continue;
        if(skill<0 || size_t(skill)>=weights.size())return std::nullopt;
        if(weights[skill]==0)weights[skill]=1;
    }
    Weights result;for(size_t i=0;i<weights.size();++i)if(weights[i])result.emplace_back(int32_t(i),weights[i]);
    return result;
}
// Worker selector setup3a53b0 installs filter3d5f60. Its closure has no captured
// state: the second argument is an owned tagged unit reference. Only semantic
// unit/caste/occupation/fortress facts are read, never selector/widget storage.
inline std::optional<bool> workshopWorkerAllowed(df::unit* unit) {
    static const bool supported=[] {
        if(!farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        const auto hash=[&](size_t rva,size_t length) {
            uint64_t value=UINT64_C(14695981039346656037);
            for(size_t i=0;i<length;++i){value^=base[rva+i];value*=UINT64_C(1099511628211);}
            return value;
        };
        return hash(0x3d5f60,0x167)==UINT64_C(0x33702827971671a0) &&
               hash(0xb973c0,0x79)==UINT64_C(0xe30c0166fa2e4d2a);
    }();
    if(!supported)return std::nullopt;
    if(!unit)return false;
    bool allowed=false;
    // The filter contains all Labor's child/caste/office exclusions. Reuse its
    // native gate and restoration lifetime for unit/HF/office lookup caches.
    const auto labor=df3d_creature::laborEligible(unit,[&] {
        const df3d_area::StaffUnitReference reference{unit};
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        using Excluded=bool (*)(const void*,const df3d_area::StaffUnitReference*);
        allowed=!reinterpret_cast<Excluded>(base+0x3d5f60)(nullptr,&reference);
    });
    if(!labor)return std::nullopt;
    return *labor && allowed;
}

inline std::optional<std::vector<int32_t>> workshopWorkerCandidates(df::building* building) {
    if(!building || !df::global::world ||
       (building->getType()!=df::building_type::Workshop && building->getType()!=df::building_type::Furnace) ||
       !building->getWorkshopProfile())return std::nullopt;
    std::vector<int32_t> result;
    for(auto* unit:df::global::world->units.active) {
        const auto allowed=workshopWorkerAllowed(unit);if(!allowed)return std::nullopt;
        if(*allowed)result.push_back(unit->id);
    }
    return result; // Source order only; presentation sorting is a separate read.
}

struct WorkshopWorkerProfile {
    int32_t buildingId=-1;
    uint64_t revision=0;
    std::vector<int32_t> permittedWorkers;
};
// Caller owns a simulation safe point. This observes the simulation profile,
// not the selected native building or the worker selector's retained list.
inline std::optional<WorkshopWorkerProfile> workshopWorkerProfile(df::building* building) {
    if(!building || !df::global::world ||
       (building->getType()!=df::building_type::Workshop && building->getType()!=df::building_type::Furnace))return std::nullopt;
    auto* profile=building->getWorkshopProfile();
    const auto header=observeBuildingHeader(building);
    if(!profile || !header || header->removing || header->stage!=header->maxStage)return std::nullopt;
    WorkshopWorkerProfile value;value.buildingId=building->id;value.permittedWorkers=profile->permitted_workers;
    uint64_t hash=UINT64_C(14695981039346656037);
    const auto add=[&](uint64_t part) {
        for(unsigned shift=0;shift<64;shift+=8){hash^=(part>>shift)&255;hash*=UINT64_C(1099511628211);}
    };
    add(header->revision);add(building->getSubtype());add(building->getCustomType());
    add(value.permittedWorkers.size());for(const auto id:value.permittedWorkers)add(uint32_t(id));
    value.revision=(hash&INT64_MAX)?(hash&INT64_MAX):1;
    return value;
}
enum class WorkshopWorkerOutcome { Rejected, Stale, Applied, Unavailable, Unknown };
struct WorkshopWorkerResult {
    WorkshopWorkerOutcome outcome=WorkshopWorkerOutcome::Rejected;
    std::optional<WorkshopWorkerProfile> profile;
};
inline WorkshopWorkerResult selectWorkshopWorker(int32_t buildingId,int32_t unitId,uint64_t revision) {
    static const bool supported=[] {
        if(!farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x1bf;++i){hash^=base[0x3a8d90+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0x4b81af110a51f064);
    }();
    WorkshopWorkerResult result;
    if(!supported){result.outcome=WorkshopWorkerOutcome::Unavailable;return result;}
    auto* building=df::building::find(buildingId);
    const auto before=workshopWorkerProfile(building);if(!before)return result;
    if(!revision || before->revision!=revision){result.outcome=WorkshopWorkerOutcome::Stale;return result;}
    auto* unit=df::unit::find(unitId);
    if(!unit || std::find(df::global::world->units.active.begin(),df::global::world->units.active.end(),unit)==df::global::world->units.active.end())return result;
    const auto allowed=workshopWorkerAllowed(unit);
    if(!allowed){result.outcome=WorkshopWorkerOutcome::Unavailable;return result;}
    if(!*allowed)return result;
    // Native3a8d90 keeps this effect inline: remove the last matching entry,
    // otherwise replace the restriction with this worker (Workshop/Furnace).
    // Calling the whole handler would borrow selected-building/menu globals.
    // Prepare allocations before mutation; swapping commits only semantic data.
    auto desired=before->permittedWorkers;
    const auto existing=std::find(desired.rbegin(),desired.rend(),unitId);
    if(existing!=desired.rend())desired.erase(std::next(existing).base());
    else desired.assign(1,unitId);
    auto* profile=building->getWorkshopProfile();
    auto replacement=desired;
    profile->permitted_workers.swap(replacement);
    result.outcome=WorkshopWorkerOutcome::Unknown;
    try {
        auto after=workshopWorkerProfile(building);
        if(after && after->permittedWorkers==desired) {
            result.profile=std::move(after);result.outcome=WorkshopWorkerOutcome::Applied;
        }
    }catch(...) {} // Committed effects are never reported as safely retryable.
    return result;
}
}
