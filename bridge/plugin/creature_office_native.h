#pragma once
#include "farm_native.h"
#include "df/unit.h"
#include "df/historical_figure.h"
#include "df/historical_entity.h"
#include "df/histfig_entity_link.h"
#include "df/entity_position.h"
#include "df/entity_position_assignment.h"

namespace df3d_creature {
struct OfficeTitle { int32_t positionId,entityId; bool spouse; std::string text; };
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
