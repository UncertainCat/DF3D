#pragma once
#include "df/global_objects.h"
#include "df/plotinfost.h"
#include "df/world.h"
#include "df/historical_entity.h"
#include "df/squad.h"
#include "df/squad_ammo_spec.h"
#include <windows.h>
#include <optional>

namespace df3d_production {
struct AmmunitionAllocation { int32_t kind=0,squadId=-1; };
// Shared item-sheet153daa and siege-sheet193096 allocation semantics. Native
// sorted membership and squad lookup consume only simulation-owned collections.
inline std::optional<AmmunitionAllocation> ammunitionAllocation(int32_t itemId) {
    if(itemId<0 || !df::global::plotinfo || !df::global::world)return {};
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    static const bool ready=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        for(const auto& p:{Pin{0xb9f70,0x25,UINT64_C(0xe6e732b038db044e)},
                          Pin{0x75500,0x6f,UINT64_C(0x223b74ce0823a28d)}}) {
            uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<p.length;++i){h^=base[p.rva+i];h*=UINT64_C(1099511628211);}
            if(h!=p.hash)return false;
        }return true;
    }();
    const auto& equipment=df::global::plotinfo->equipment;
    const auto* entity=df::global::plotinfo->main.fortress_entity;
    const auto at=[base](const void* ptr,size_t rva){return ptr==base+rva;};
    if(!ready || !at(&equipment.items_assigned,0x2398dc0) ||
       !at(&equipment.hunter_ammunition,0x2399890) ||
       !at(&df::global::plotinfo->main.fortress_entity,0x239a1e8) ||
       !at(&df::global::world->squads.all,0x24e37c0))return {};
    const auto contains=[base,itemId](const std::vector<int32_t>& ids) {
        return reinterpret_cast<int32_t(*)(int32_t,const std::vector<int32_t>*)>(base+0xb9f70)(itemId,&ids)!=-1;
    };
    const auto& assigned=equipment.items_assigned[int(df::item_type::AMMO)];
    if(assigned.size()>1000000 || equipment.hunter_ammunition.size()>10000)return {};
    if(!contains(assigned))return AmmunitionAllocation{};
    for(const auto* spec:equipment.hunter_ammunition) {
        if(!spec || spec->assigned.size()>1000000)return {};
        if(contains(spec->assigned))return AmmunitionAllocation{1,-1};
    }
    if(!entity || entity->squads.size()>10000 || df::global::world->squads.all.size()>1000000)return {};
    static_assert(offsetof(df::historical_entity,squads)==0x11c8);
    static_assert(offsetof(df::squad,ammo)==0x140);
    static_assert(offsetof(df::squad_ammo_spec,assigned)==0x18);
    using Find=df::squad* (*)(const std::vector<df::squad*>*,int32_t);
    for(auto id:entity->squads) {
        auto* squad=reinterpret_cast<Find>(base+0x75500)(&df::global::world->squads.all,id);
        if(!squad)continue;
        if(squad->ammo.ammunition.size()>10000)return {};
        for(const auto* spec:squad->ammo.ammunition) {
            if(!spec || spec->assigned.size()>1000000)return {};
            if(contains(spec->assigned))return AmmunitionAllocation{2,id};
        }
    }
    return AmmunitionAllocation{};
}
}
