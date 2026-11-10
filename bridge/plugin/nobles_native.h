#pragma once
#include "unit_description_native.h"
#include "df/administrators_interfacest.h"
#include "df/noblelistst.h"
#include "df/appointment_candidatest.h"
#include "labor_eligibility_cache.h"
#include "df/nemesis_record.h"
#include "df/entity_position.h"
#include "df/entity_position_assignment.h"
#include "df/world.h"
#include "df/plotinfost.h"
#include <optional>
#include <vector>
namespace df3d_nobles {
struct Row {
    int32_t unitId=-1,nemesisId=-1,entityId=-1,positionId=-1,assignmentId=-1,value=0;
    std::string positionName;
    bool canAppoint=false;
};
// Native feed425539..425699 and renderer42712b..42726c inline the same
// appointment gate. No standalone helper exists at these call sites. Evaluate
// those semantic tests against the fresh owned list, never the native menu.
inline std::optional<bool> appointmentAvailable(const df::noblelistst& row,const std::vector<df::noblelistst*>& list) {
    if(!row.ep || !df::global::plotinfo)return std::nullopt;
    const auto& position=*row.ep;
    static_assert(offsetof(df::entity_position,appointed_by)==0x2e0);
    static_assert(offsetof(df::entity_position,appointed_by_civ)==0x2f8);
    static_assert(offsetof(df::entity_position,succession_by_position)==0x310);
    static_assert(offsetof(df::historical_figure,died_year)==0x30);
    if(position.appointed_by.size()!=position.appointed_by_civ.size() || position.appointed_by.size()>65536)return std::nullopt;
    bool allowed=row.enid==df::global::plotinfo->group_id && !position.flags.is_set(df::entity_position_flags::ELECTED);
    if((position.flags.is_set(df::entity_position_flags::SUCCESSION_BY_HEIR) || !position.succession_by_position.empty()) && row.epp && row.epp->histfig!=-1)allowed=false;
    if(allowed && !position.appointed_by_civ.empty()) {
        allowed=false;
        for(const auto* other:list) {
            if(!other || !other->ep)return std::nullopt;
            if(other==&row)continue;
            for(size_t i=0;i<position.appointed_by.size();++i) {
                if(position.appointed_by_civ[i]==other->enid && position.appointed_by[i]==other->ep->id && other->un)allowed=true;
            }
        }
    }
    if(!row.un && row.nem) {
        if(!row.nem->figure)return std::nullopt;
        if(row.nem->figure->died_year==-1)allowed=false;
    }
    return allowed;
}
// Native421f30 reads simulation entities, units, historical figures and positions.
// All overview rows, parallel identity vectors and location summaries belong to
// this private context. Never invoke the UI opener424280 or feed424330.
inline bool ready() {
    if(!df::global::world || !df::global::plotinfo)return false;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    // Bind observed RIP operands to semantic world storage, never menu aliases.
    const auto at=[base](const void* address,size_t rva){return address==base+rva;};
    if(!at(&df::global::world->history.figures,0x24f9d18) ||
       !at(&df::global::world->units.all,0x23e50b0) ||
       !at(&df::global::world->units.active,0x23e50c8) ||
       !at(&df::global::world->nemesis.all,0x23e5178) ||
       !at(&df::global::world->entities.all,0x23d17f8) ||
       !at(&df::global::plotinfo->main.fortress_entity,0x239a1e8))return false;
    if(df::global::world->units.all.size()>1048576 || df::global::world->history.figures.size()>1048576)return false;
    static_assert(sizeof(df::noblelistst)==0x30);
    static_assert(offsetof(df::noblelistst,upplist)==0x10);
    static_assert(offsetof(df::noblelistst,value)==0x2c);
    static_assert(offsetof(df::administrators_interfacest,spec_prof)==0x18);
    static_assert(offsetof(df::administrators_interfacest,candidate)==0x98);
    static const bool pinned=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
        {0x425539,0x162,UINT64_C(0x497589726e70534e)},
        {0x42712b,0x147,UINT64_C(0x1001eb9865cf74f3)},
        {0x423df0,0x483,UINT64_C(0x76d34506cc3f6746)},
        {0x421ea0,0x90,UINT64_C(0x66ce8e62615f3121)},
        {0x14219a0,0x1e,UINT64_C(0xbd7a0f718d1f235d)},
        {0x99a1f0,0x1c1,UINT64_C(0x29e6da03c674f048)},
        {0x13b1170,0xbd,UINT64_C(0x3e26062d73fefb84)},
        {0xb96d80,0x53e,UINT64_C(0x5249c96a7883418a)},
        {0xb530b0,0xac,UINT64_C(0x7c6f66602bdab157)},
        {0xbbef0,0x9a,UINT64_C(0xb674b3f5153bea03)},
        {0xbbd90,0xa8,UINT64_C(0xe0b2ddde58f5e3fc)},
        {0xbbe40,0xad,UINT64_C(0x062a266340f9bf38)},
        {0x421f30,0x87a,UINT64_C(0x24352b0e8bb5f0ba)},
        {0x421dc0,0xd9,UINT64_C(0x6e40e0a2cdabd7a8)},
        {0x1421960,0x39,UINT64_C(0x5678b62c0493d8f4)},
        {0x136ccc0,0xf00,UINT64_C(0x155550fa55ed7b99)},
        {0x136dbc0,0x5dd,UINT64_C(0x129278c5cfb8c58d)},
        {0x99a9f0,0x17f,UINT64_C(0xd528dde4d0fe9e7b)},
        };
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}if(hash!=pin.hash)return false;}
        return true;
    }();
    if(!pinned)return false;
    return true;
}
struct Context {
    df::administrators_interfacest value;
    uint8_t* base;
    explicit Context(uint8_t* address):base(address){}
    ~Context(){
        reinterpret_cast<void(*)(df::administrators_interfacest*)>(base+0x421ea0)(&value);
        reinterpret_cast<void(*)(df::administrators_interfacest*)>(base+0x421dc0)(&value);
    }
    Context(const Context&)=delete;
    Context& operator=(const Context&)=delete;
};
inline std::optional<std::vector<Row>> overview() {
    if(!ready())return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    // Unit location summaries can choose between equivalent locations using MT.
    df3d_creature::InventoryRandomRestore random(base);
    Context owned(base);
    reinterpret_cast<void(*)(df::administrators_interfacest*)>(base+0x421f30)(&owned.value);
    if(owned.value.noblelist.size()>65536)return std::nullopt;
    std::vector<Row> result;result.reserve(owned.value.noblelist.size());
    for(const auto* source:owned.value.noblelist) {
        if(!source || !source->ep)return std::nullopt;
        const auto available=appointmentAvailable(*source,owned.value.noblelist);if(!available)return std::nullopt;
        Row row;row.canAppoint=*available;row.unitId=source->un?source->un->id:-1;row.nemesisId=source->nem?source->nem->id:-1;
        row.entityId=source->enid;row.positionId=source->ep->id;row.assignmentId=source->epp?source->epp->id:-1;
        row.value=source->value;row.positionName=source->ep->name[0];result.push_back(std::move(row));
    }
    return result;
}
struct Candidate {int32_t unitId=-1,value=0;};
// Selection identity comes from a fresh owned overview; no menu index crosses
// this boundary. This only lists candidates, not permission to appoint them.
inline std::optional<std::vector<Candidate>> candidates(int32_t entityId,int32_t positionId,int32_t assignmentId) {
    if(!ready() || entityId<0 || positionId<0 || assignmentId< -1)return std::nullopt;
    static_assert(sizeof(df::appointment_candidatest)==0x10);
    static_assert(offsetof(df::appointment_candidatest,value)==8);
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    df3d_creature::InventoryRandomRestore random(base);
    df3d_creature::LaborEligibilityCacheRestore caches;
    if(df::global::world->units.active.size()>1048576)return std::nullopt;
    for(auto* unit:df::global::world->units.active)if(!caches.capture(unit,-1))return std::nullopt;
    Context owned(base);
    reinterpret_cast<void(*)(df::administrators_interfacest*)>(base+0x421f30)(&owned.value);
    if(owned.value.noblelist.size()>65536)return std::nullopt;
    df::noblelistst* target=nullptr;
    for(auto* row:owned.value.noblelist) {
        if(!row || !row->ep)return std::nullopt;
        if(row->enid==entityId && row->ep->id==positionId && (row->epp?row->epp->id:-1)==assignmentId) {
            if(target)return std::nullopt;
            target=row;
        }
    }
    if(!target)return std::nullopt;
    const auto available=appointmentAvailable(*target,owned.value.noblelist);
    if(!available || !*available)return std::nullopt;
    reinterpret_cast<void(*)(df::administrators_interfacest*,df::noblelistst*)>(base+0x423df0)(&owned.value,target);
    if(owned.value.candidate.size()>1048576)return std::nullopt;
    std::vector<Candidate> result;result.reserve(owned.value.candidate.size());
    for(const auto* row:owned.value.candidate) {
        if(!row)return std::nullopt;
        result.push_back({row->un?row->un->id:-1,row->value});
    }
    return result;
}
}
