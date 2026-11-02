#pragma once
#include "work_order_rows_native.h"
#include "df/job_item_filter.h"

namespace df3d_production {
inline bool workOrderSuggestionsSupported() {
    static const bool supported=[] {
        if(!workOrderRowsSupported())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0xa9ce10,0x890,UINT64_C(0x45f247042723739d)},
            {0xd160c0,0x1047,UINT64_C(0x824b3791b709c77c)},
            {0x14eda2,0x28,UINT64_C(0x9eb9c219b43e040e)},
            {0x1fb050,0x123,UINT64_C(0x3ea393db12f2c677)},
            {0xa2adb0,0x185c,UINT64_C(0x236e98c86197e94e)},
            {0x3926b1,0x1ef,UINT64_C(0x07d2b75807214414)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();return supported;
}
// Compose the renderer's condition-to-filter mapping (3926b1..39289a),
// then call its item-description leaf. All filter storage belongs to this call.
inline std::optional<std::string> nativeWorkOrderConditionCaption(const df::manager_order_condition_item& source) {
    if(!workOrderSuggestionsSupported() || !df::global::world || source.contains.size()>64 ||
       source.reaction_class.size()>128 || source.has_material_reaction_product.size()>128)return std::nullopt;
    static_assert(sizeof(df::job_item_filter)==0x110);
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    using Init=void (*)(df::job_item_filter*);
    using Describe=void (*)(df::job_item_filter*,std::string*,int16_t);
    df::job_item_filter filter;
    reinterpret_cast<Init>(base+0x1fb050)(&filter);
    filter.item_type=source.item_type;filter.item_subtype=source.item_subtype;
    filter.mat_type=source.mat_type;filter.mat_index=source.mat_index;filter.use_mat_index=source.mat_index!=-1;
    filter.flags1=source.flags1;
    filter.flags2=source.flags2;filter.use_flags2=source.flags2.whole!=0;
    filter.flags3=source.flags3;filter.use_flags3=source.flags3.whole!=0;
    filter.flags4=source.flags4;filter.use_flags4=source.flags4!=0;
    filter.flags5=source.flags5;filter.use_flags5=source.flags5!=0;
    filter.metal_ore=source.metal_ore;filter.use_metal_ore=source.metal_ore!=-1;
    filter.reaction_class=source.reaction_class;filter.use_reaction_class=!source.reaction_class.empty();
    filter.has_material_reaction_product=source.has_material_reaction_product;
    filter.use_reaction_product=!source.has_material_reaction_product.empty();
    filter.min_dimension=source.min_dimension;filter.reaction_id=source.reaction_id;
    filter.contains=source.contains;filter.use_contains=!source.contains.empty();
    filter.has_tool_use=source.has_tool_use;filter.dye_color=source.dye_color;
    df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    std::string result;
    reinterpret_cast<Describe>(base+0xa2adb0)(&filter,&result,-1);
    if(result.size()>1024)return std::nullopt;
    return result;
}
// A9ce10 is the suggestion builder, not the conditions renderer/input handler.
// Its only context input is order+8 and its only output is the pointer vector
// at+58. Supply this independent scratch layout, never an open native panel.
inline std::optional<std::vector<df::manager_order_condition_item>> nativeWorkOrderSuggestions(const df::manager_order& source) {
    if(!workOrderSuggestionsSupported() || !df::global::world || source.reaction_name.size()>128)return std::nullopt;
    df::manager_order recipe;
    recipe.job_type=source.job_type;recipe.reaction_name=source.reaction_name;
    recipe.item_type=source.item_type;recipe.item_subtype=source.item_subtype;
    recipe.mat_type=source.mat_type;recipe.mat_index=source.mat_index;
    recipe.specflag=source.specflag;recipe.specdata=source.specdata;recipe.material_category=source.material_category;
    recipe.art_spec=source.art_spec;recipe.items=nullptr;
    struct Scratch {
        uint64_t reserved=0;
        df::manager_order* order=nullptr;
        std::array<uint8_t,0x48> unused{};
        std::vector<df::manager_order_condition_item*> rows;
    } scratch;
    static_assert(offsetof(Scratch,order)==8 && offsetof(Scratch,rows)==0x58);
    static_assert(sizeof(df::manager_order_condition_item)==0x98);
    static_assert(offsetof(df::manager_order_condition_item,contains)==0x70);
    scratch.order=&recipe;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    struct Cleanup {
        Scratch& scratch;const uint8_t* base;
        ~Cleanup() {
            using Clear=void (*)(void*);using Free=void (*)(void*,size_t);
            for(auto* row:scratch.rows)if(row) {
                reinterpret_cast<Clear>(base+0x6f750)(&row->contains);
                reinterpret_cast<Clear>(base+0x6f850)(&row->has_material_reaction_product);
                reinterpret_cast<Clear>(base+0x6f850)(&row->reaction_class);
                reinterpret_cast<Free>(base+0x1539680)(row,0x98);
            }
        }
    } cleanup{scratch,base};
    df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
    using Build=void (*)(Scratch*);
    reinterpret_cast<Build>(base+0xa9ce10)(&scratch);
    if(scratch.rows.size()>128)return std::nullopt;
    std::vector<df::manager_order_condition_item> result;
    result.reserve(scratch.rows.size());
    for(const auto* row:scratch.rows) {
        if(!row || row->contains.size()>64 || row->reaction_class.size()>128 || row->has_material_reaction_product.size()>128)return std::nullopt;
        result.push_back(*row);
    }
    return result;
}
}
