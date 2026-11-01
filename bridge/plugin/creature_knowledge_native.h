#pragma once
#include "creature_skills_native.h"
#include "written_detail_native.h"
#include "musical_detail_native.h"
namespace df3d_creature {
// Diagnostic selected-entry adapter. Native page construction revalidates
// membership on owned unit/soul scratch before any detail formatter runs.
// Production admission still requires the formatter/event coverage documented
// in ENGINEERING; this wrapper does not widen that acceptance.
inline std::optional<std::string> selectedKnowledgeDetailProbe(df::unit* unit,int32_t kind,int32_t id) {
    if(!unit || kind<14 || kind>17 || id<0)return std::nullopt;
    const auto page=skillsPageProbe(unit,4);if(!page)return std::nullopt;
    bool found=false;
    for(size_t i=0;i<page->knowledgeTypes.size();++i)
        if(page->knowledgeTypes[i]==kind && page->knowledgeIds[i]==id){found=true;break;}
    if(!found)return std::nullopt;
    switch(kind){
    case 14:return poeticDetailProbe(df::poetic_form::find(id));
    case 15:return musicalDetailProbe(df::musical_form::find(id));
    case 16:return danceDetailProbe(df::dance_form::find(id));
    case 17:return writtenDetailProbe(df::written_content::find(id));
    default:return std::nullopt;
    }
}
}
