#pragma once
#include "creature_skills_native.h"
#include "written_detail_native.h"
#include "musical_detail_native.h"
namespace df3d_creature {
// Safe-point selected-entry reader. Native page construction revalidates
// membership on owned unit/soul scratch before any detail formatter runs.
// The same owned adapters serve live requests and diagnostic comparisons.
// Unsupported or stale selections return no text; callers publish a typed result.
inline std::optional<std::string> selectedKnowledgeDetail(df::unit* unit,int32_t kind,int32_t id) {
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
struct KnowledgeCacheProbe {
    std::optional<std::string> text;
    size_t coldInsertions=0;
    bool nestedRestored=false,exceptionRestored=false,originalRestored=false;
};
// Diagnostic only: force the pinned historical-material cache miss, then run
// the selected formatter inside the same private-cache lifetime.
inline std::optional<KnowledgeCacheProbe> knowledgeCacheProbe(df::unit* unit,int32_t kind,int32_t id) {
    if(!unit || !df::global::world || unit->hist_figure_id<0)return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    const auto hash=[&](size_t rva,size_t size){uint64_t h=UINT64_C(14695981039346656037);
        for(size_t i=0;i<size;++i){h^=base[rva+i];h*=UINT64_C(1099511628211);}return h;};
    if(hash(0x14add70,0x12f)!=UINT64_C(0x01f897b15772d540) ||
       hash(0x701e70,0x20e)!=UINT64_C(0xead0193006374e44))return std::nullopt;
    auto& cache=df::global::world->raws.creatures.hist_fig_to_creature_map;
    const auto digest=[&](){uint64_t h=UINT64_C(14695981039346656037);
        const auto* bytes=reinterpret_cast<const uint8_t*>(&cache);
        for(size_t i=0;i<sizeof(cache);++i){h^=bytes[i];h*=UINT64_C(1099511628211);}
        for(const auto& node:cache){h^=reinterpret_cast<uintptr_t>(&node);h*=UINT64_C(1099511628211);
            h^=uint32_t(node.first);h*=UINT64_C(1099511628211);h^=uint32_t(node.second);h*=UINT64_C(1099511628211);}
        return h;};
    const auto original=digest();KnowledgeCacheProbe result;
    {
        KnowledgeMaterialCacheRestore outer(cache);cache.clear();
        reinterpret_cast<void*(*)(df::world*,int16_t,int32_t)>(base+0x14add70)(df::global::world,219,unit->hist_figure_id);
        result.coldInsertions=cache.size();
        const auto populated=digest();
        result.text=selectedKnowledgeDetail(unit,kind,id);
        result.nestedRestored=digest()==populated;
        struct ProbeException {};
        try{KnowledgeMaterialCacheRestore inner(cache);cache.clear();throw ProbeException{};}
        catch(const ProbeException&){}
        result.exceptionRestored=digest()==populated;
    }
    result.originalRestored=digest()==original;
    return result;
}

}
