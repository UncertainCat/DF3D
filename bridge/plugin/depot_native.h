#pragma once
#include "depot_body.h"
#include <windows.h>
#include <optional>
#include "modules/Maps.h"
#include "df/global_objects.h"
#include "df/plotinfost.h"
#include "df/world.h"
#include "df/job.h"
#include "df/job_type.h"
#include "df/building_tradedepotst.h"
#include "df/unit.h"
#include "df/historical_entity.h"
#include "df/historical_figure.h"
#include "df/entity_position_assignment.h"

namespace df3d_production {
// Native depot input1af983..1afac8. Owned setting intents call semantic leaves;
// no viewscreen, selected depot or native trade-menu scratch is an input.
inline bool depotNativeReady() {
    static const bool ready=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        if(!base)return false;
        const auto* dos=reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
        if(dos->e_magic!=IMAGE_DOS_SIGNATURE || dos->e_lfanew<=0 || dos->e_lfanew>0x1000)return false;
        const auto* pe=reinterpret_cast<const IMAGE_NT_HEADERS64*>(base+dos->e_lfanew);
        if(pe->Signature!=IMAGE_NT_SIGNATURE || pe->FileHeader.Machine!=IMAGE_FILE_MACHINE_AMD64 ||
           pe->FileHeader.TimeDateStamp!=0x6a70a6d9 || pe->OptionalHeader.SizeOfImage!=0x2711000)return false;
        const auto hash=[&](size_t rva,size_t length) {
            uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<length;++i){h^=base[rva+i];h*=UINT64_C(1099511628211);}return h;
        };
        return hash(0x54bcd0,0x15)==UINT64_C(0x23931f03386d1254) && hash(0x1af983,0x14a)==UINT64_C(0x970f77daf5b501fb) &&
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
struct DepotBrokerFacts {
    int32_t id=-1,jobId=-1;std::string name,activity;
    int16_t foreground=7,background=0;bool bright=false,accessible=false;
};
inline std::optional<DepotBrokerFacts> depotBrokerFacts(df::building* building) {
    auto* depot=virtual_cast<df::building_tradedepotst>(building);
    if(!depotNativeReady() || !df::global::plotinfo || !depot ||
       depot->getBuildStage()!=depot->getMaxBuildStage())return {};
    static const bool ready=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t expected;};
        constexpr Pin pins[]={
            {0x19799d,0xd9,UINT64_C(0x6f39c91775782bf3)},
            {0x13a4910,0x254,UINT64_C(0x24e41e31661f3ca6)},
            {0x1330c30,0x688,UINT64_C(0x0e165ee31decf426)},
            {0x138ffd0,0xd20,UINT64_C(0x904926737b452832)},
            {0xd03170,0x12b,UINT64_C(0x90da46373e49508e)},
            {0xd032b0,0x5024,UINT64_C(0xba755d2dfd15322d)},
        };
        for(const auto& pin:pins) {
            uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){h^=base[pin.rva+i];h*=UINT64_C(1099511628211);}
            if(h!=pin.expected)return false;
        }return true;
    }();
    if(!ready)return {};
    static_assert(offsetof(df::historical_entity,assignments_by_type)==0x1798);
    DepotBrokerFacts result;
    const auto* entity=df::global::plotinfo->main.fortress_entity;
    if(!entity)return {};
    const auto& assignments=entity->assignments_by_type[df::entity_position_responsibility::TRADE];
    // Native19799d resolves only the first assignment, not the last valid broker.
    if(assignments.empty())return result;
    if(!assignments.front())return {};
    auto* figure=df::historical_figure::find(assignments.front()->histfig);
    auto* unit=figure?df::unit::find(figure->unit_id):nullptr;
    if(!unit)return result;
    const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    result.id=unit->id;result.jobId=unit->job.current_job?unit->job.current_job->id:-1;
    reinterpret_cast<void (*)(df::unit*,std::string*,bool)>(base+0x1330c30)(unit,&result.name,false);
    if(unit->job.current_job && !unit->job.current_job->flags.bits.on_break) {
        reinterpret_cast<void (*)(df::job*,std::string*)>(base+0xd03170)(unit->job.current_job,&result.activity);
        result.foreground=3;result.bright=true;
    } else {
        // Semantic formatter underlying renderer1390cf0; never call the renderer.
        reinterpret_cast<void (*)(df::unit*,bool,bool,std::string*,int16_t*,int16_t*,bool*)>(base+0x138ffd0)
            (unit,true,false,&result.activity,&result.foreground,&result.background,&result.bright);
    }
    result.accessible=reinterpret_cast<bool (*)(df::unit*,int16_t,int16_t,int16_t,bool)>(base+0x13a4910)
        (unit,int16_t(depot->centerx),int16_t(depot->centery),int16_t(depot->z),true);
    if(result.name.size()>512 || result.activity.size()>512 || result.foreground<0 || result.foreground>7 ||
       result.background<0 || result.background>7)return {};
    return result;
}
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
inline std::optional<DepotBody> depotBody(df::building* building) {
    const auto facts=depotFacts(building);const auto broker=depotBrokerFacts(building);
    if(!facts || !broker)return {};
    DepotBody v;v.flags=facts->flags;v.goods=facts->goods;v.trade=facts->trade;v.workerId=facts->worker;
    v.brokerId=broker->id;v.brokerJobId=broker->jobId;v.brokerName=broker->name;v.activity=broker->activity;
    v.foreground=broker->foreground;v.background=broker->background;v.bright=broker->bright;v.accessible=broker->accessible;
    // Renderer196b53 counts hauling jobs, not item stack quantities.
    for(const auto* job:building->jobs){if(!job)return {};if(job->job_type==df::job_type::BringItemToDepot)++v.awaitingItems;}
    return validDepotBody(v)?std::optional<DepotBody>{std::move(v)}:std::nullopt;
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
