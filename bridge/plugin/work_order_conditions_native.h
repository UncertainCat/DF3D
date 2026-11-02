#pragma once
#include "work_order_rows_native.h"

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
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();return supported;
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
