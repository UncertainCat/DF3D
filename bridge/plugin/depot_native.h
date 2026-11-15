#pragma once
#include "farm_native.h"
#include "df/building_tradedepotst.h"
#include "df/unit.h"

namespace df3d_production {
// Native depot input1af983..1afac8. Owned setting intents call semantic leaves;
// no viewscreen, selected depot or native trade-menu scratch is an input.
inline bool depotNativeReady() {
    static const bool ready=[] {
        if(!farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        const auto hash=[&](size_t rva,size_t length) {
            uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<length;++i){h^=base[rva+i];h*=UINT64_C(1099511628211);}return h;
        };
        return hash(0x1af983,0x14a)==UINT64_C(0x970f77daf5b501fb) &&
            hash(0xfd580,0x23)==UINT64_C(0x1f9646cb809a07ae) &&
            hash(0xd020c0,0x1f9)==UINT64_C(0xe6506fad7c779085) &&
            hash(0x54bcf0,0xce)==UINT64_C(0x7ceaff76902a0dea) &&
            hash(0xd09b70,0x130)==UINT64_C(0x1046a66c3f604a04) &&
            hash(0xe532f0,0x3b)==UINT64_C(0xfe4b29b6caf6e290) &&
            hash(0xe53330,0x36)==UINT64_C(0x8afaa9c1c0d5ef4d) &&
            hash(0x5ab090,0x1c3)==UINT64_C(0xadb127b9ef0064df);
    }();return ready;
}
struct DepotFacts {uint32_t flags=0;bool goods=false,trade=false;int32_t worker=-1;};
inline std::optional<DepotFacts> depotFacts(df::building* building) {
    auto* depot=virtual_cast<df::building_tradedepotst>(building);
    if(!depotNativeReady() || !df::global::plotinfo || !depot ||
       depot->getBuildStage()!=depot->getMaxBuildStage())return {};
    using Caravan=bool (*)(df::plotinfost*);
    using Worker=df::unit* (*)(df::building*);
    const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    auto* worker=reinterpret_cast<Worker>(base+0x5ab090)(depot);
    return DepotFacts{depot->trade_flags.whole,
        reinterpret_cast<Caravan>(base+0xe532f0)(df::global::plotinfo),
        reinterpret_cast<Caravan>(base+0xe53330)(df::global::plotinfo),worker?worker->id:-1};
}
enum class DepotSettingOutcome {Rejected,Applied,Unknown};
// mode0 Broker,1 Anyone,2 no trader. Dismissal preserves the previous Anyone bit.
// The caller must retire Unknown outcomes, never retry them automatically.
inline DepotSettingOutcome setDepotMode(df::building* building,uint32_t expectedFlags,int mode) {
    auto* depot=virtual_cast<df::building_tradedepotst>(building);
    if(!depotNativeReady() || !df::global::world || !depot || mode<0 || mode>2 ||
       depot->getBuildStage()!=depot->getMaxBuildStage() || depot->trade_flags.whole!=expectedFlags ||
       depot->jobs.size()>=32767)return DepotSettingOutcome::Rejected;
    auto* tile=DFHack::Maps::getTileDesignation(depot->centerx,depot->centery,depot->z);
    if(!tile || tile->bits.hidden)return DepotSettingOutcome::Rejected;
    for(const auto* job:depot->jobs)if(!job || job->job_type==df::job_type::DestroyBuilding)return DepotSettingOutcome::Rejected;
    const auto desired=mode==0?(expectedFlags|1U)&~2U:mode==1?expectedFlags|3U:expectedFlags&~1U;
    if(desired==expectedFlags)return DepotSettingOutcome::Applied;
    static_assert(offsetof(df::building_tradedepotst,trade_flags)==0x148);
    const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    depot->trade_flags.whole=desired;
    if((desired&1U) && !(expectedFlags&1U)) {
        using Create=df::job* (*)();using Attach=void (*)(df::building*,df::job*,bool);using Requirements=void (*)(df::job*);
        auto* job=reinterpret_cast<Create>(base+0xfd580)();
        if(!job)return DepotSettingOutcome::Unknown;
        job->job_type=df::job_type::TradeAtDepot;
        // Native leaves position unset; attachment supplies the building reference.
        reinterpret_cast<Attach>(base+0x54bcf0)(depot,job,false);
        reinterpret_cast<Requirements>(base+0xd09b70)(job);
    } else if(!(desired&1U) && (expectedFlags&1U)) {
        using Cancel=void (*)(df::building*,int32_t);
        for(int32_t i=int32_t(depot->jobs.size())-1;i>=0;--i)
            if(depot->jobs[size_t(i)]->job_type==df::job_type::TradeAtDepot)
                reinterpret_cast<Cancel>(base+0x54bcd0)(depot,i);
    }
    return depot->trade_flags.whole==desired?DepotSettingOutcome::Applied:DepotSettingOutcome::Unknown;
}
}
