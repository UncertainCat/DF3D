#pragma once
#include "knowledge_detail_native.h"
#include "df/historical_figure_info.h"
#include "df/historical_kills.h"
#include "creature_items_native.h"
#include "df/squad.h"
#include "df/squad_position.h"
namespace df3d_creature {
struct UniformRow {
    int32_t id=-1,itemType=-1;
    std::optional<df3d_production::ItemInspectionAppearance> appearance;
    bool resolved=false,carried=false;
    std::string caption,role;
    df::coord position{-30000,-30000,-30000};
};
struct UniformPage {bool hasSquad=false;std::vector<UniformRow> rows;};
inline std::optional<UniformPage> militaryUniform(const df::unit* source) {
    if(!source || !inventoryDescriptionReady())return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool supported=[&]{uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0xb45;++i){hash^=base[0x17bd91+i];hash*=UINT64_C(1099511628211);}return hash==UINT64_C(0x478e6b1bbf1baf1d);}();
    if(!supported)return std::nullopt;
    UniformPage page;
    auto* squad=df::squad::find(source->military.squad_id);
    if(!squad)return page;
    const auto index=source->military.squad_position;
    if(index<0 || size_t(index)>=squad->positions.size() || !squad->positions[index])return std::nullopt;
    page.hasSquad=true;
    if(!source->body.body_plan || source->inventory.size()>10000)return std::nullopt;
    for(const auto* entry:source->inventory)if(!entry || !entry->item)return std::nullopt;
    InventoryDescriptionContext context(*source);InventoryRandomRestore random(base);
    // Native17bd91..17c8d6 reads assigned_items directly, preserving unresolved
    // entries as blank rows. There is no separate native list-building routine.
    for(const auto id:squad->positions[index]->equipment.assigned_items) {
        UniformRow row;row.id=id;
        if(auto* item=df::item::find(id)) {
            row.resolved=true;row.itemType=int32_t(item->getType());
            row.appearance=df3d_production::itemAppearance(item);if(!row.appearance)return std::nullopt;
            auto caption=df3d_production::buildingItemCaption(item);if(!caption)return std::nullopt;
            row.caption=std::move(*caption);
            for(const auto& entry:context.inventory())if(entry.item==item) {
                auto input=entry;row.carried=true;
                reinterpret_cast<void(*)(df::unit*,std::string*,df::unit_inventory_item*)>(base+0x1393900)(context.unit(),&row.role,&input);break;
            }
            if(!row.carried){auto position=df3d_production::itemPosition(item);if(position)row.position=*position;}
        }
        page.rows.push_back(std::move(row));
    }
    return page;
}
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
