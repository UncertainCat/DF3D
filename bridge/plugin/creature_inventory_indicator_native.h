#pragma once
#include "unit_description_native.h"
#include "df/artifact_claim.h"
#include "df/artifact_record.h"
#include "df/entity_position_assignment.h"
#include "df/historical_entity.h"
#include "df/historical_figure.h"
#include "df/histfig_entity_link.h"
#include "df/item.h"
#include "df/plotinfost.h"
#include "df/world.h"

namespace df3d_creature {
// Native16a014..16a4a1 is inline in the Items renderer. Preserve its branch
// order, calling its semantic lookups with owned cache scratch; never invoke
// the renderer or consume its menu/stack state. -1 none,0 squad,1 clothing,
// 2 work tool,3 position symbol. These are semantic assignments, not art IDs.
inline std::optional<int32_t> inventoryIndicator(df::unit* owned,df::item* item) {
    static const bool supported=[] {
        if(!inventoryDescriptionReady())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x16a014,0x48d,UINT64_C(0xb0f6b4e696675dd2)},
            {0xb9f70,0x25,UINT64_C(0xe6e732b038db044e)},
            {0xbabe0,0xab,UINT64_C(0x1bd318997a061458)},
            {0xcb1350,0x61,UINT64_C(0x6809c71079ec010d)},
            {0xcb1720,0x63,UINT64_C(0xb03bc00c14a2d687)},
            {0x13b3090,0x19,UINT64_C(0x901cd2f6d41c1657)},
            {0xb530b0,0xac,UINT64_C(0x7c6f66602bdab157)},
            {0x7daf0,0x25,UINT64_C(0xe08224475d4dff6a)},
            {0xba0a0,0xa8,UINT64_C(0xcf6b2a7b534d3331)},
            {0xb9dc0,0xa7,UINT64_C(0x4d8961b901732215)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();
    if(!supported||!owned||!item||!df::global::plotinfo||!df::global::world)return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    const auto& equipment=df::global::plotinfo->equipment;
    const auto type=static_cast<int32_t>(item->getType());
    if(type<0||size_t(type)>=equipment.items_assigned.size()||item->general_refs.size()>10000)return std::nullopt;
    for(auto* ref:item->general_refs)if(!ref)return std::nullopt;
    using Member=int32_t (*)(int32_t,const std::vector<int32_t>*);
    const auto member=reinterpret_cast<Member>(base+0xb9f70);
    if(member(item->id,&equipment.items_assigned[type])!=-1)return 0;
    if(member(item->id,&equipment.work_weapons)==-1) {
        using Owned=bool (*)(df::item*,int32_t,int32_t);
        return reinterpret_cast<Owned>(base+0xcb1350)(item,16,owned->id)?1:-1;
    }
    if(!item->flags.bits.artifact)return 2;
    using Figure=df::historical_figure* (*)(df::unit*);
    using Artifact=df::artifact_record* (*)(df::item*,int32_t);
    using Entity=df::historical_entity* (*)(const std::vector<df::historical_entity*>*,int32_t);
    using Assignment=df::entity_position_assignment* (*)(int32_t,const std::vector<df::entity_position_assignment*>*);
    const auto* figure=reinterpret_cast<Figure>(base+0x13b3090)(owned);
    const auto* artifact=reinterpret_cast<Artifact>(base+0xcb1720)(item,1);
    if(!figure||!artifact)return -1;
    if(figure->entity_links.size()>65536)return std::nullopt;
    for(auto* link:figure->entity_links) {
        if(!link)return std::nullopt;
        if(link->getType()!=df::histfig_entity_link_type::POSITION)continue;
        const auto* entity=reinterpret_cast<Entity>(base+0x7daf0)(&df::global::world->entities.all,link->entity_id);
        if(!entity)continue;
        if(entity->positions.assignments.size()>65536||entity->artifact_claims.size()>65536)return std::nullopt;
        const auto* assignment=reinterpret_cast<Assignment>(base+0xb9dc0)(link->getPosition(),&entity->positions.assignments);
        if(!assignment)continue;
        for(const auto* claim:entity->artifact_claims) {
            if(!claim)return std::nullopt;
            if(claim->renounce_event==-1&&static_cast<int32_t>(claim->claim_type)==0&&
               claim->artifact_id==artifact->id&&claim->symbol_claim_id==assignment->id)return 3;
        }
    }
    return -1;
}
} // namespace df3d_creature
