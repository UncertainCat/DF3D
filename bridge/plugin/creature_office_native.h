#pragma once
#include "farm_native.h"
#include "df/unit.h"
#include "df/historical_figure.h"
#include "df/historical_entity.h"
#include "df/histfig_entity_link.h"
#include "df/entity_position.h"
#include "df/entity_position_assignment.h"
#include "df/unit_soul.h"
#include "df/unit_preference.h"
#include "df/plotinfost.h"
#include <array>

namespace df3d_creature {
struct OfficeFallback { std::string status,position;int32_t color=15; };
// Called only when neither titles nor a room warning occupy this quadrant.
// Native166b65..166da2 gates status with semantic unit/caste/link predicates.
inline std::optional<OfficeFallback> noOfficeFallback(df::unit* unit) {
    static const bool supported=[] {
        if(!df3d_production::farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        const auto hash=[&](size_t rva,size_t length) {
            uint64_t value=UINT64_C(14695981039346656037);
            for(size_t i=0;i<length;++i){value^=base[rva+i];value*=UINT64_C(1099511628211);}
            return value;
        };
        return hash(0x138ed20,0xff)==UINT64_C(0x430951f9f3e403c2) &&
               hash(0x1376500,0xf0)==UINT64_C(0x2c5ca25b0abc0a79) &&
               hash(0x73760,0x4c)==UINT64_C(0xd6e159fb1367c80e) &&
               hash(0xb973c0,0x79)==UINT64_C(0xe30c0166fa2e4d2a);
    }();
    if(!supported || !unit || !df::global::plotinfo)return std::nullopt;
    static_assert(offsetof(df::plotinfost,group_id)==0x2448); // Native RVA2393678.
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    OfficeFallback result;
    using UnitPredicate=bool (*)(df::unit*);
    using CastePredicate=bool (*)(int16_t,int16_t);
    if(!reinterpret_cast<UnitPredicate>(base+0x138ed20)(unit) ||
       reinterpret_cast<CastePredicate>(base+0x1376500)(unit->race,unit->caste) ||
       !reinterpret_cast<UnitPredicate>(base+0x73760)(unit))return result;
    const auto* hf=df::historical_figure::find(unit->hist_figure_id);
    if(hf && hf->entity_links.size()>4096)return std::nullopt;
    if(hf)for(const auto* link:hf->entity_links)if(!link)return std::nullopt;
    using Strength=int16_t (*)(const df::historical_figure*,int16_t,int32_t);
    const bool member=hf && reinterpret_cast<Strength>(base+0xb973c0)(hf,0,df::global::plotinfo->group_id)!=0;
    // Native literals15ff7a8/15ff798/15ff780 and palette at166c23/166ca4/166d23.
    result.status=member?"Citizen":"Resident";result.color=member?11:15;
    result.position="No official position";
    return result;
}
// Native room valuation marks matching unit preferences. Keep those writes in
// an owned unit/soul/preferences context. Furnishing artwork may still undergo
// native semantic lazy initialization (as in the native sheet); no UI cache is
// read or borrowed. This is not a promise of global read-only behavior.
inline std::optional<std::array<int32_t,4>> actualRooms(df::unit* source) {
    static const bool supported=[] {
        if(!df3d_production::farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x134a830,0xe3,UINT64_C(0xc1f6ffa4ccd5f4ee)},
            {0x559610,0xf53,UINT64_C(0xb4aa2d070c8d24f1)},
            {0x133ee00,0x710,UINT64_C(0x375cfcfb29c559f6)},
            {0x133ec90,0x170,UINT64_C(0x83882aff6a50dc16)},
            {0x559410,0xc0,UINT64_C(0x2a4708690268841e)},
            {0x5594d0,0xa2,UINT64_C(0x62566748cd465187)},
            {0xc66c30,0x953,UINT64_C(0x5975fb4b92954e30)},
            {0xc5fbb0,0x67,UINT64_C(0xac238af7cbf2a301)},
            {0xc66650,0x5d9,UINT64_C(0x5a95a4e89d5d5bcc)},
            {0xfcdd0,0x92,UINT64_C(0x7b286f02725115ba)},
            {0xc9fbf0,0x2f4,UINT64_C(0x0fe3eeb8af2e0984)},
            {0xcaede0,0xb2,UINT64_C(0x30a9c58074719c0e)},
            {0x14d0c70,0x5cc,UINT64_C(0x93e5fad4bd72b45f)},
            {0x14add70,0x12f,UINT64_C(0x01f897b15772d540)},
            {0xcabb50,0x21e,UINT64_C(0xee57b9bc216cc548)},
            {0xcc83e0,0xe6,UINT64_C(0x153208913b9388eb)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();
    if(!supported || !source || source->owned_buildings.size()>4096)return std::nullopt;
    static_assert(offsetof(df::unit,owned_buildings)==0x450);
    static_assert(offsetof(df::unit,race)==0xa4);
    static_assert(offsetof(df::unit,status)+offsetof(df::unit::T_status,current_soul)==0xa98);
    static_assert(offsetof(df::unit_soul,preferences)==0x230);
    static_assert(offsetof(df::unit_preference,flags)==0x16);
    struct OwnedUnit final:df::unit { OwnedUnit():df::unit(){} } owned;
    df::unit_soul soul;
    std::vector<df::unit_preference> preferences;
    owned.race=source->race;
    owned.owned_buildings=source->owned_buildings;
    for(const auto* building:owned.owned_buildings)if(!building)return std::nullopt;
    owned.status.current_soul=nullptr;
    if(const auto* live=source->status.current_soul) {
        if(live->preferences.size()>4096)return std::nullopt;
        preferences.reserve(live->preferences.size());
        for(const auto* preference:live->preferences) {
            if(!preference)return std::nullopt;
            preferences.push_back(*preference);
        }
        for(auto& preference:preferences)soul.preferences.push_back(&preference);
        owned.status.current_soul=&soul;
    }
    std::array<int32_t,4> result{};
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    reinterpret_cast<void (*)(df::unit*,int32_t*)>(base+0x134a830)(&owned,result.data());
    return result;
}
// Native requirement aggregation accepts optional assignment/holder/entity
// arrays. Populate those from factual own-position links, with independent
// assignments: bbe40 refreshes position_vector_idx. The alternate native path
// would also refresh the live unit's historical-figure index.
inline std::optional<std::array<int32_t,4>> requiredRooms(df::unit* unit) {
    static const bool supported=[] {
        if(!df3d_production::farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        const auto hash=[&](size_t rva,size_t length) {
            uint64_t value=UINT64_C(14695981039346656037);
            for(size_t i=0;i<length;++i){value^=base[rva+i];value*=UINT64_C(1099511628211);}
            return value;
        };
        return hash(0x134a5e0,0x246)==UINT64_C(0xd73a74b32f6acbe4) &&
               hash(0xba0a0,0xa8)==UINT64_C(0xcf6b2a7b534d3331) &&
               hash(0xb9dc0,0xa7)==UINT64_C(0x4d8961b901732215) &&
               hash(0xbbe40,0xad)==UINT64_C(0x062a266340f9bf38);
    }();
    if(!supported || !unit)return std::nullopt;
    static_assert(offsetof(df::unit,hist_figure_id)==0xc30);
    static_assert(offsetof(df::entity_position_assignment,position_vector_idx)==0x10);
    static_assert(offsetof(df::entity_position,required_office)==0x390);
    std::array<int32_t,4> result{};
    const auto* hf=df::historical_figure::find(unit->hist_figure_id);
    if(!hf)return result;
    if(hf->entity_links.size()>4096)return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    using Find=df::entity_position_assignment* (*)(int32_t,const std::vector<df::entity_position_assignment*>*);
    std::vector<df::entity_position_assignment> owned;owned.reserve(hf->entity_links.size());
    std::vector<int32_t> holders,entities;
    for(auto* link:hf->entity_links) {
        if(!link)return std::nullopt;
        if(link->getType()!=df::histfig_entity_link_type::POSITION)continue;
        const auto* entity=df::historical_entity::find(link->entity_id);
        if(!entity)continue;
        if(entity->positions.assignments.size()>65536 || entity->positions.own.size()>65536)return std::nullopt;
        const auto* assignment=reinterpret_cast<Find>(base+0xb9dc0)(link->getPosition(),&entity->positions.assignments);
        if(!assignment)continue;
        owned.emplace_back();owned.back().position_id=assignment->position_id;
        owned.back().position_vector_idx=-1;
        holders.push_back(unit->hist_figure_id);entities.push_back(entity->id);
    }
    std::vector<df::entity_position_assignment*> assignments;
    for(auto& value:owned)assignments.push_back(&value);
    using Aggregate=void (*)(df::unit*,int32_t*,const std::vector<df::entity_position_assignment*>*,const std::vector<int32_t>*,const std::vector<int32_t>*);
    // With all three vectors supplied, the native routine only reads unit HF ID.
    reinterpret_cast<Aggregate>(base+0x134a5e0)(unit,result.data(),&assignments,&holders,&entities);
    return result;
}
struct OfficeTitle { int32_t positionId,entityId; bool spouse; std::string text; };
struct RoomWarning { std::string text;int32_t color=15; };
inline std::optional<RoomWarning> roomWarning(const std::array<int32_t,4>& required,const std::array<int32_t,4>& actual) {
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool supported=[](const uint8_t* base) {
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x3b0;++i){hash^=base[0xab4f20+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0x7740ba5bc0108c80);
    }(base);
    if(!supported)return std::nullopt;
    RoomWarning result;
    // Overview16699a..166b65 displays only the first unmet requirement.
    // ab4ee0 writes global drawing colors; reproduce its scalar result instead.
    for(int16_t i=0;i<4;++i)if(required[i]>0 && actual[i]<required[i]) {
        reinterpret_cast<void (*)(std::string*,int32_t,int16_t)>(base+0xab4f20)(&result.text,required[i],i);
        result.text.insert(0,"Needs "); // Native literal at166aae.
        result.color=actual[i]>0?14:12;
        break;
    }
    return result;
}
// Title collection is inline in native1a5f41..1a61d7, not a reusable semantic
// API. Preserve its own-link then spouse-link order; DFHack's noble collector
// sorts by precedence. Never call the surrounding viewsheet initializer.
inline std::optional<std::vector<OfficeTitle>> officeTitles(df::unit* unit) {
    static const bool supported=[] {
        if(!df3d_production::farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        const auto hash=[&](size_t rva,size_t length) {
            uint64_t value=UINT64_C(14695981039346656037);
            for(size_t i=0;i<length;++i){value^=base[rva+i];value*=UINT64_C(1099511628211);}
            return value;
        };
        return hash(0x99a3c0,0x113)==UINT64_C(0x14b5664261afc791) &&
               hash(0x52d650,0x2b4)==UINT64_C(0x9e8023d09def7af9) && // body and case tables
               hash(0xb98d30,0x5f)==UINT64_C(0x0b20f43042d158dc) &&
               hash(0xb9dc0,0xa7)==UINT64_C(0x4d8961b901732215) &&
               hash(0x1ba140,0xa8)==UINT64_C(0xdb6eb9072d509b29);
    }();
    if(!supported || !unit)return std::nullopt;
    static_assert(offsetof(df::entity_position,name)==0x98 && offsetof(df::entity_position,spouse)==0x158);
    static_assert(offsetof(df::entity_position,spouse_female)==0x198 && offsetof(df::entity_position,spouse_male)==0x1d8);
    static_assert(offsetof(df::historical_figure,sex)==6);
    static_assert(offsetof(df::entity_position_assignment,position_id)==12);
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    using Assignment=df::entity_position_assignment* (*)(int32_t,const std::vector<df::entity_position_assignment*>*);
    using Position=df::entity_position* (*)(int32_t,const std::vector<df::entity_position*>*);
    using Name=const std::string* (*)(const df::entity_position*,int8_t,bool,bool);
    using Capitalize=void (*)(std::string*);
    using Spouse=int32_t (*)(df::historical_figure*,int16_t);
    const auto* hf=df::historical_figure::find(unit->hist_figure_id);
    std::vector<OfficeTitle> result;
    if(!hf)return result;
    const auto append=[&](const df::historical_figure* source,bool spouse)->bool {
        if(!source)return true;
        if(source->entity_links.size()>4096)return false;
        for(auto* link:source->entity_links) {
            if(result.size()==3)break; // Native Overview's first three collected positions.
            if(!link)return false;
            if(link->getType()!=df::histfig_entity_link_type::POSITION)continue;
            const auto* entity=df::historical_entity::find(link->entity_id);
            if(!entity)continue;
            if(entity->positions.assignments.size()>65536 || entity->positions.own.size()>65536)return false;
            const auto* assignment=reinterpret_cast<Assignment>(base+0xb9dc0)(link->getPosition(),&entity->positions.assignments);
            if(!assignment)continue;
            const auto* position=reinterpret_cast<Position>(base+0x1ba140)(assignment->position_id,&entity->positions.own);
            if(!position)continue;
            if(spouse && position->spouse[0].empty() && position->spouse_female[0].empty() && position->spouse_male[0].empty())continue;
            const auto* name=reinterpret_cast<Name>(base+0x99a3c0)(position,hf->sex,false,spouse);
            if(!name || name->size()>512)return false;
            OfficeTitle title{position->id,entity->id,spouse,*name};
            reinterpret_cast<Capitalize>(base+0x52d650)(&title.text);
            result.push_back(std::move(title));
        }
        return true;
    };
    if(!append(hf,false))return std::nullopt;
    if(result.size()<3) {
        if(hf->histfig_links.size()>4096)return std::nullopt;
        const int32_t spouse=reinterpret_cast<Spouse>(base+0xb98d30)(const_cast<df::historical_figure*>(hf),2);
        if(spouse!=-1 && !append(df::historical_figure::find(spouse),true))return std::nullopt;
    }
    return result;
}
}
