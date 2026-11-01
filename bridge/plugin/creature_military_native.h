#pragma once
#include "knowledge_detail_native.h"
#include "df/historical_figure_info.h"
#include "df/historical_kills.h"
namespace df3d_creature {
inline std::optional<std::string> militaryKills(df::unit* unit) {
    if(!unit || !df::global::world || !knowledgeDescriptionReady())return std::nullopt;
    auto* figure=df::historical_figure::find(unit->hist_figure_id);
    if(!figure || !figure->info || !figure->info->kills)return std::string{};
    const auto& kills=*figure->info->kills;
    const auto count=kills.killed_race.size();
    if(kills.killed_caste.size()!=count || kills.killed_underground_region.size()!=count ||
       kills.killed_region.size()!=count || kills.killed_site.size()!=count ||
       kills.killed_undead.size()!=count || kills.killed_count.size()!=count)return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    struct Pin {size_t rva,length;uint64_t hash;};
    constexpr Pin pins[]={
        {0xbba250,0xe75,UINT64_C(0x48a4e452c843519f)},
        {0xbba000,0x24e,UINT64_C(0xef7bd883f0a2eabf)},
        {0xb92640,0x2b4,UINT64_C(0xed9f612ded76daea)},
        {0xb93930,0x15a,UINT64_C(0x1ab3438f9be56fa2)},
        {0xb94940,0xf6,UINT64_C(0x9212620ec0e20427)},
        {0xb94a40,0x157,UINT64_C(0x47255515af7da23e)},
        {0x52d3c0,0x288,UINT64_C(0x6e1fbc2416fba9fc)},
        {0xb9b80,0x144,UINT64_C(0x91ddb6c319015f9b)},
    };
    for(const auto& pin:pins){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<pin.length;++i){h^=base[pin.rva+i];h*=UINT64_C(1099511628211);}if(h!=pin.hash)return std::nullopt;}
    // Native47f537 calls this semantic formatter with flags0. It copies the
    // kill vectors before filtering them; output and formatting scratch are owned.
    // Resolve the historical figure without changing the unit's lookup cache.
    KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    std::string result;
    reinterpret_cast<void(*)(df::historical_figure*,std::string*,int32_t)>(base+0xbba250)(figure,&result,0);
    if(result.size()>65536)return std::nullopt;
    return result;
}
}
