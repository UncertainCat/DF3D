#pragma once
#include "creature_office_native.h"
#include "df/world.h"
#include "df/world_data.h"
#include "df/world_site.h"
#include "df/entity_site_link.h"
#include "df/diplomacy_statest.h"
#include "df/historical_figure_info.h"
#include "df/state_profilest.h"
#include "df/histfig_entity_link_positionst.h"

namespace df3d_creature {
// Header/input eligibility1b0916..1b097d, before family/office refusals.
// All three helpers read unit/caste semantics; no viewscreen or cursor input.
inline std::optional<bool> expelEligible(df::unit* unit) {
    static const bool supported=[] {
        if(!df3d_production::farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x1b0916,0x67,UINT64_C(0x21fc7f9d1fc0b2cd)},
            {0x138ed20,0xff,UINT64_C(0x430951f9f3e403c2)},
            {0x1376500,0xf0,UINT64_C(0x2c5ca25b0abc0a79)},
            {0x73760,0x4c,UINT64_C(0xd6e159fb1367c80e)},
            {0x1b9874,0xc,UINT64_C(0xb9431422bbe29198)},
            {0x1b9880,0x87,UINT64_C(0x19fd684bc16ee4b1)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();
    if(!supported)return std::nullopt;
    if(!unit)return false;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    if(!reinterpret_cast<bool (*)(df::unit*)>(base+0x138ed20)(unit) ||
       reinterpret_cast<bool (*)(int16_t,int16_t)>(base+0x1376500)(unit->race,unit->caste) ||
       !reinterpret_cast<bool (*)(df::unit*)>(base+0x73760)(unit))return false;
    // Native profession jump table: all0..134 except these six classes.
    const int profession=int(unit->profession);
    if(profession<0 || profession>134)return false;
    switch(unit->profession) {
    case df::profession::TRAINED_HUNTER:case df::profession::TRAINED_WAR:
    case df::profession::MASTER_THIEF:case df::profession::THIEF:
    case df::profession::CHILD:case df::profession::BABY:return false;
    default:return true;
    }
}
// Native1b0abd..1b0f02 builds refusal and departing IDs inline. This owns the
// result and mutable assignment lookup scratch. It does not read view_sheets.
// Destination selection and confirmation are separate, not implemented here.
struct ExpelGroup { int32_t reason=-1; std::vector<int32_t> units; };
inline std::optional<ExpelGroup> expelGroup(df::unit* unit) {
    static const bool supported=[] {
        if(!df3d_production::farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x1b0abd,0x445,UINT64_C(0x0ccc13c51a7ca18c)},
            {0x13b9c00,0x100,UINT64_C(0x38d9840d9bd4c8f3)},
            {0x99ab70,0x70,UINT64_C(0x65bcb7f764cab1d6)},
            {0xb9dc0,0xa7,UINT64_C(0x4d8961b901732215)},
            {0xbbe40,0xad,UINT64_C(0x062a266340f9bf38)},
            {0x13cc4d0,0x139,UINT64_C(0xf660081358097d16)},
            {0xb9e70,0xf8,UINT64_C(0x7dab880be6ec9cba)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();
    if(!supported || !unit || !df::global::world || !df::global::plotinfo)return std::nullopt;
    static_assert(offsetof(df::unit,relationship_ids)==0x3bc);
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    const auto* plot=df::global::plotinfo;
    using Responsibility=bool (*)(df::unit*,int16_t,int32_t,int32_t,int32_t);
    using FindAssignment=df::entity_position_assignment* (*)(int32_t,const std::vector<df::entity_position_assignment*>*);
    using Position=df::entity_position* (*)(df::historical_entity*,df::entity_position_assignment*);
    // b972c0's position-bit test, with factual lookups and an owned assignment
    // instead of refreshing live link/entity/assignment cached indices.
    const auto flag=[&](df::unit* target,int32_t entityId,df::entity_position_flags bit)->std::optional<bool> {
        const auto* hf=df::historical_figure::find(target->hist_figure_id);
        if(!hf)return false;
        if(hf->entity_links.size()>4096)return std::nullopt;
        for(auto* link:hf->entity_links) {
            if(!link)return std::nullopt;
            if(link->getType()!=df::histfig_entity_link_type::POSITION || link->entity_id!=entityId)continue;
            auto* entity=df::historical_entity::find(entityId);if(!entity)continue;
            if(entity->positions.assignments.size()>65536 || entity->positions.own.size()>65536)return std::nullopt;
            auto* assignment=reinterpret_cast<FindAssignment>(base+0xb9dc0)(link->getPosition(),&entity->positions.assignments);
            if(!assignment)continue;
            df::entity_position_assignment owned;owned.position_id=assignment->position_id;owned.position_vector_idx=-1;
            auto* position=reinterpret_cast<Position>(base+0xbbe40)(entity,&owned);
            if(position && position->flags.is_set(bit))return true;
        }
        return false;
    };
    const auto role=[&](df::unit* target)->std::optional<int32_t> {
        if(reinterpret_cast<Responsibility>(base+0x13b9c00)(target,3,plot->group_id,-1,-1))return 2;
        for(auto bit:{df::entity_position_flags::ELECTED,df::entity_position_flags::SUCCESSION_BY_HEIR}) {
            for(auto entityId:{plot->civ_id,plot->group_id}) {
                const auto value=flag(target,entityId,bit);if(!value)return std::nullopt;
                if(*value)return bit==df::entity_position_flags::ELECTED?1:0;
            }
        }
        return -1;
    };
    ExpelGroup result;
    const auto own=role(unit);if(!own)return std::nullopt;
    result.reason=*own;if(result.reason!=-1)return result;
    using Insert=int32_t (*)(int32_t,std::vector<int32_t>*);
    const auto add=[&](int32_t id){reinterpret_cast<Insert>(base+0xb9e70)(id,&result.units);};
    const auto* hf=df::historical_figure::find(unit->hist_figure_id);
    if(hf) {
        if(hf->histfig_links.size()>4096)return std::nullopt;
        add(unit->id);
        for(auto* link:hf->histfig_links) {
            if(!link)return std::nullopt;
            const auto type=link->getType();
            const bool spouse=type==df::histfig_hf_link_type::SPOUSE;
            if(!spouse && type!=df::histfig_hf_link_type::CHILD)continue;
            auto* related=df::historical_figure::find(link->target_hf);
            if(!related || related->died_year!=-1)continue;
            const auto* where=related->info?related->info->whereabouts:nullptr;
            if(where && int(where->state)==1 && where->site_id!=plot->site_id)continue;
            using Resolve=df::unit* (*)(const std::vector<df::unit*>*,int32_t);
            auto* relative=reinterpret_cast<Resolve>(base+0x13cc4d0)(&df::global::world->units.all,related->id);
            if(!relative) {
                if(spouse || related->profession==df::profession::CHILD || related->profession==df::profession::BABY) {
                    result.reason=spouse?3:7;return result;
                }
                continue;
            }
            if(!spouse && relative->profession!=df::profession::CHILD && relative->profession!=df::profession::BABY)continue;
            if(relative->flags1.bits.inactive){result.reason=spouse?3:7;return result;}
            const auto refusal=role(relative);if(!refusal)return std::nullopt;
            if(*refusal!=-1){result.reason=(spouse?4:8)+*refusal;return result;}
            add(relative->id);
        }
    }
    // Native scans active units for each initially gathered member, backwards.
    // The same native sorted insertion handles duplicate IDs and ordering.
    if(df::global::world->units.active.size()>1000000)return std::nullopt;
    for(int i=int(result.units.size())-1;i>=0;--i) {
        auto* member=df::unit::find(result.units[size_t(i)]);if(!member)continue;
        for(auto* follower:df::global::world->units.active) {
            if(!follower)return std::nullopt;
            if((!follower->flags1.bits.inactive || follower->flags1.bits.incoming) && follower->relationship_ids[0]==member->id)add(follower->id);
        }
    }
    return result;
}
// Destination orchestration1b0f02..1b10ed. Every helper reads world semantics;
// siteLink's create argument is always false. No native menu choices are read.
inline std::optional<std::vector<int32_t>> expelDestinations() {
    static const bool supported=[] {
        if(!df3d_production::farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x1b0f02,0x1eb,UINT64_C(0x2918e55a94180fdc)},
            {0x9b4e70,0x5d,UINT64_C(0x8acee59abdfa33fb)},
            {0x93ce30,0xb7,UINT64_C(0xd664ff2de27cabfb)},
            {0x9364d0,0x1da,UINT64_C(0x65231f4d74787177)},
            {0x9b4e40,0x2e,UINT64_C(0xdfc69385713967b3)},
            {0xffa80,0xc,UINT64_C(0xed630f8b7614e879)},
            {0xba0a0,0xa8,UINT64_C(0xcf6b2a7b534d3331)},
            {0xb9dc0,0xa7,UINT64_C(0x4d8961b901732215)},
            {0xb9e70,0xf8,UINT64_C(0x7dab880be6ec9cba)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();
    if(!supported || !df::global::world || !df::global::world->world_data || !df::global::plotinfo)return std::nullopt;
    static_assert(offsetof(df::historical_entity,relations)+offsetof(df::historical_entity::T_relations,diplomacy)==0x1028);
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    const auto* plot=df::global::plotinfo;
    auto* civ=df::historical_entity::find(plot->civ_id);
    auto* fortress=df::historical_entity::find(plot->group_id);
    if(!fortress)return std::nullopt;
    std::vector<int32_t> result;if(!civ)return result;
    using SiteLink=df::entity_site_link* (*)(df::historical_entity*,int32_t,bool);
    using Owner=df::historical_entity* (*)(df::world_site*);
    using Civilization=df::historical_entity* (*)(df::historical_entity*);
    using Assignment=df::entity_position_assignment* (*)(int32_t,const std::vector<df::entity_position_assignment*>*);
    using Diplomacy=df::diplomacy_statest* (*)(const std::vector<df::diplomacy_statest*>*,int32_t);
    using Market=int32_t (*)(df::historical_entity*,uint32_t);
    auto* current=reinterpret_cast<SiteLink>(base+0x9364d0)(civ,plot->site_id,false);
    const int32_t profile=current && current->entity_id==civ->id?current->position_profile_id:-1;
    for(auto* site:df::global::world->world_data->sites) {
        if(!site)return std::nullopt;
        auto* owner=reinterpret_cast<Owner>(base+0x9b4e70)(site);
        if(!owner || owner==fortress)continue;
        auto* ownerCiv=reinterpret_cast<Civilization>(base+0x93ce30)(owner);
        if(!ownerCiv)return std::nullopt;
        auto* link=reinterpret_cast<SiteLink>(base+0x9364d0)(civ,site->id,false);
        bool allowed=false;
        if(profile!=-1 && link) {
            allowed=link->position_profile_id==profile;
            if(!allowed && link->position_profile_id!=-1) {
                auto* assignment=reinterpret_cast<Assignment>(base+0xb9dc0)(link->position_profile_id,&ownerCiv->positions.assignments);
                allowed=assignment && assignment->vassal_of_entity_id==civ->id && assignment->vassal_of_position_profile_id==profile;
            }
        }
        if(!allowed) {
            auto* relation=reinterpret_cast<Diplomacy>(base+0xffa80)(&fortress->relations.diplomacy.state,owner->id);
            allowed=relation && relation->relation==df::diplomacy_state_type::AcceptingTribute && ownerCiv==civ;
        }
        if(!allowed)allowed=reinterpret_cast<Market>(base+0x9b4e40)(owner,8)==plot->site_id;
        if(allowed)reinterpret_cast<int32_t (*)(int32_t,std::vector<int32_t>*)>(base+0xb9e70)(site->id,&result);
    }
    if(!result.empty())result.insert(result.begin(),-1);
    return result;
}
}
