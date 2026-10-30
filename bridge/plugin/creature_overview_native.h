#pragma once
#include "building_item_native.h"
#include "df/unit_inventory_item.h"

namespace df3d_creature {
struct HaulingSummary { int32_t itemId=-1; std::string text; };
// Overview166e81 calls this read-only inventory selector, then the same owned
// item-caption formatter used by building contents. Never invoke the enclosing
// sheet renderer14ef90: it reads and writes global UI state.
inline std::optional<HaulingSummary> haulingSummary(df::unit* unit) {
    using Select=df::item* (*)(df::unit*);
    static const auto select=[]()->Select {
        if(!df3d_production::farmFunctions())return nullptr;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x2c;++i){hash^=base[0x1324b50+i];hash*=UINT64_C(1099511628211);}
        if(hash!=UINT64_C(0xda0ae0ab2370567d))return nullptr;
        return reinterpret_cast<Select>(const_cast<uint8_t*>(base)+0x1324b50);
    }();
    static_assert(offsetof(df::unit,inventory)==0x408);
    static_assert(offsetof(df::unit_inventory_item,mode)==8);
    if(!select || !unit || unit->inventory.size()>4096)return std::nullopt;
    for(const auto* entry:unit->inventory)if(!entry || !entry->item)return std::nullopt;
    HaulingSummary result;
    if(auto* item=select(unit)) {
        auto caption=df3d_production::buildingItemCaption(item);
        if(!caption || caption->size()>500)return std::nullopt;
        result.itemId=item->id;
        result.text="Haul: "+*caption; // Native literal at renderer166ee6.
    }
    return result;
}
}
