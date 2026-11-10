#pragma once
#include "unit_description_native.h"
#include "df/administrators_interfacest.h"
#include "df/noblelistst.h"
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
};
// Native421f30 reads simulation entities, units, historical figures and positions.
// All overview rows, parallel identity vectors and location summaries belong to
// this private context. Never invoke the UI opener424280 or feed424330.
inline std::optional<std::vector<Row>> overview() {
    if(!df::global::world || !df::global::plotinfo)return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    // Bind observed RIP operands to semantic world storage, never menu aliases.
    const auto at=[base](const void* address,size_t rva){return address==base+rva;};
    if(!at(&df::global::world->history.figures,0x24f9d18) ||
       !at(&df::global::world->units.all,0x23e50b0) ||
       !at(&df::global::world->units.active,0x23e50c8) ||
       !at(&df::global::world->nemesis.all,0x23e5178) ||
       !at(&df::global::world->entities.all,0x23d17f8) ||
       !at(&df::global::plotinfo->main.fortress_entity,0x239a1e8))return std::nullopt;
    if(df::global::world->units.all.size()>1048576 || df::global::world->history.figures.size()>1048576)return std::nullopt;
    static_assert(sizeof(df::noblelistst)==0x30);
    static_assert(offsetof(df::noblelistst,upplist)==0x10);
    static_assert(offsetof(df::noblelistst,value)==0x2c);
    static_assert(offsetof(df::administrators_interfacest,spec_prof)==0x18);
    static_assert(offsetof(df::administrators_interfacest,candidate)==0x98);
    static const bool pinned=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
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
    if(!pinned)return std::nullopt;
    // Unit location summaries can choose between equivalent locations using MT.
    df3d_creature::InventoryRandomRestore random(base);
    struct Context {
        df::administrators_interfacest value;
        uint8_t* base;
        explicit Context(uint8_t* address):base(address){}
        ~Context(){reinterpret_cast<void(*)(df::administrators_interfacest*)>(base+0x421dc0)(&value);}
    } owned(base);
    reinterpret_cast<void(*)(df::administrators_interfacest*)>(base+0x421f30)(&owned.value);
    if(owned.value.noblelist.size()>65536)return std::nullopt;
    std::vector<Row> result;result.reserve(owned.value.noblelist.size());
    for(const auto* source:owned.value.noblelist) {
        if(!source || !source->ep)return std::nullopt;
        Row row;row.unitId=source->un?source->un->id:-1;row.nemesisId=source->nem?source->nem->id:-1;
        row.entityId=source->enid;row.positionId=source->ep->id;row.assignmentId=source->epp?source->epp->id:-1;
        row.value=source->value;row.positionName=source->ep->name[0];result.push_back(std::move(row));
    }
    return result;
}
}
