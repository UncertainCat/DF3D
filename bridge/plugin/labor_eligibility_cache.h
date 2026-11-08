#pragma once
#include <vector>
#include <utility>
#include "df/unit.h"
#include "df/historical_figure.h"
#include "df/historical_entity.h"
#include "df/histfig_entity_link_positionst.h"
#include "df/histfig_hf_link.h"
#include "df/entity_position_assignment.h"

namespace df3d_creature {
// Native13b99b0 and its office/spouse lookups refresh these indices. Capture
// before a read and restore in reverse order, including shared figure entries.
struct LaborEligibilityCacheRestore {
    std::vector<std::pair<int32_t*,int32_t>> values;
    void keep(int32_t& value){values.emplace_back(&value,value);}
    ~LaborEligibilityCacheRestore(){for(auto it=values.rbegin();it!=values.rend();++it)*it->first=it->second;}
    bool capture(df::unit* unit,int32_t group) {
        if(!unit)return false;
    static_assert(offsetof(df::unit,enemy)+offsetof(df::unit::T_enemy,histfig_vector_idx)==0x1274);
    keep(unit->enemy.histfig_vector_idx);
    const auto* hf=df::historical_figure::find(unit->hist_figure_id);
    const auto keepFigure=[&](const df::historical_figure* figure)->bool {
        if(!figure)return true;
        if(figure->entity_links.size()>4096)return false;
        for(auto* link:figure->entity_links) {
            if(!link)return false;
            if(link->getType()!=df::histfig_entity_link_type::POSITION || (group!=-1 && link->entity_id!=group))continue;
            auto* position=static_cast<df::histfig_entity_link_positionst*>(link);
            keep(link->entity_vector_idx);keep(position->assignment_vector_idx);
            const auto* entity=df::historical_entity::find(link->entity_id);
            if(!entity)continue;
            if(entity->positions.assignments.size()>65536)return false;
            for(auto* assignment:entity->positions.assignments) {
                if(!assignment)return false;
                if(assignment->id==position->assignment_id){keep(assignment->position_vector_idx);break;}
            }
        }
        return true;
    };
    if(!keepFigure(hf))return false;
    if(hf) {
        if(hf->histfig_links.size()>4096)return false;
        for(auto* link:hf->histfig_links) {
            if(!link)return false;
            if(link->getType()==df::histfig_hf_link_type::SPOUSE) {
                if(!keepFigure(df::historical_figure::find(link->target_hf)))return false;
                break; // Native13b9b55 considers the first spouse link only.
            }
        }
    }
        return true;
    }
};
}
