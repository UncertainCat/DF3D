#pragma once
#include "justice_native.h"
#include "df/historical_entity.h"
#include "df/entity_position_assignment.h"
#include "df/entity_position_responsibility.h"
#include "df/squad.h"
#include "df/squad_position.h"
#include "df/buildings_other_id.h"

namespace df3d_justice {
struct GuardOverview {
    int16_t available=0,desired=0;
    std::string caption;
    uint8_t color=12;
    // Native insertion order and judiciary rank, before presentation sorting.
    std::vector<CandidateFact> members;
};
// Counts are standalone native simulation readers. Roster construction is
// inline in4713a5..471a15: isolate its semantic inputs rather than invoking
// the widget builder or borrowing its unit list/rank map.
inline std::optional<GuardOverview> guardOverview() {
    auto* world=df::global::world;auto* plot=df::global::plotinfo;
    if(!world || !plot || !plot->main.fortress_entity)return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    const auto at=[base](const void* p,size_t rva){return p==base+rva;};
    if(!at(&world->units.all,0x23e50b0) || !at(&world->units.active,0x23e50c8) ||
       !at(&world->buildings.other[df::buildings_other_id::CHAIN],0x23eecc0) ||
       !at(&world->buildings.other[df::buildings_other_id::CAGE],0x23eecd8) ||
       !at(&world->squads.all,0x24e37c0) || !at(&world->history.figures,0x24f9d18) ||
       !at(&plot->main.fortress_entity,0x239a1e8))return std::nullopt;
    static_assert(offsetof(df::historical_entity,assignments_by_type)==0x1798);
    static_assert(offsetof(df::entity_position_assignment,histfig)==4 && offsetof(df::entity_position_assignment,squad_id)==0x28);
    static_assert(offsetof(df::squad,positions)==0xa0 && offsetof(df::squad_position,occupant)==0);
    static const bool pinned=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0xe52290,0xd7,UINT64_C(0x7ca80505821d2e88)},
            {0xe52370,0xc4,UINT64_C(0x7897231dfd93a180)},
            {0x57c120,0x3c,UINT64_C(0x7baf9dafd895963d)},
            {0x57c160,0x88,UINT64_C(0xae48daac70c4b05a)},
            {0x14add70,0x12f,UINT64_C(0x01f897b15772d540)},
            {0x138ed20,0xff,UINT64_C(0x430951f9f3e403c2)},
            {0x13cc4d0,0x139,UINT64_C(0xf660081358097d16)},
            {0x4713a5,0x670,UINT64_C(0xf2e58ef774921c1b)},
            {0x4701d1,0xea,UINT64_C(0x4cb5b07390f617a2)},
            {0x52c130,0xb3,UINT64_C(0xf2e358ad54df1c09)},
        };
        for(const auto& p:pins){uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<p.length;++i){hash^=base[p.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=p.hash)return false;}
        return *reinterpret_cast<uintptr_t*>(base+0x16531e0+0x1e0)==reinterpret_cast<uintptr_t>(base+0x57c160) &&
               *reinterpret_cast<uintptr_t*>(base+0x1654350+0x1e0)==reinterpret_cast<uintptr_t>(base+0x57c120);
    }();
    if(!pinned)return std::nullopt;
    GuardOverview result;
    result.desired=reinterpret_cast<int16_t(*)()>(base+0xe52290)();
    result.available=reinterpret_cast<int16_t(*)()>(base+0xe52370)();
    result.caption="Desired metal cages and chains in dungeons: ";
    auto number=reinterpret_cast<void(*)(int32_t,std::string*)>(base+0x52c130);
    number(result.available,&result.caption);result.caption+=" of ";number(result.desired,&result.caption);
    result.color=result.available<result.desired?12:10;
    std::unordered_map<int32_t,size_t> seen;
    using Resolve=df::unit*(*)(std::vector<df::unit*>*,int32_t);
    const auto resolve=reinterpret_cast<Resolve>(base+0x13cc4d0);
    const auto eligible=reinterpret_cast<bool(*)(df::unit*)>(base+0x138ed20);
    const auto add=[&](int32_t histfig,int32_t rank,int32_t leader=-1){
        if(histfig==-1)return;
        auto* unit=resolve(&world->units.all,histfig);
        if(!unit || unit->flags1.bits.inactive || !eligible(unit))return;
        auto found=seen.find(unit->id);
        if(found==seen.end()) {seen.emplace(unit->id,result.members.size());result.members.push_back({unit->id,rank+(leader!=-1 && unit->hist_figure_id==leader?1000:0),0});}
    };
    const auto& execution=plot->main.fortress_entity->assignments_by_type[df::entity_position_responsibility::EXECUTIONS];
    const auto& enforcement=plot->main.fortress_entity->assignments_by_type[df::entity_position_responsibility::LAW_ENFORCEMENT];
    if(execution.size()>65536 || enforcement.size()>65536)return std::nullopt;
    for(auto i=execution.rbegin();i!=execution.rend();++i){if(!*i)return std::nullopt;add((*i)->histfig,1000000);}
    size_t squadSlots=0;
    for(auto i=enforcement.rbegin();i!=enforcement.rend();++i){
        const auto* assignment=*i;if(!assignment)return std::nullopt;
        if(assignment->histfig==-1)continue;
        if(assignment->squad_id==-1){add(assignment->histfig,10000);continue;}
        const auto* squad=df::squad::find(assignment->squad_id);if(!squad)continue;
        if(squad->positions.size()>65536 || squad->positions.size()>1048576-squadSlots)return std::nullopt;
        squadSlots+=squad->positions.size();
        for(auto p=squad->positions.rbegin();p!=squad->positions.rend();++p){if(!*p)return std::nullopt;add((*p)->occupant,1000,assignment->histfig);}
    }
    return result;
}
}
