#pragma once
#include "farm_native.h"
#include "df/item.h"
#include "df/itemdef_pantsst.h"
#include "modules/Items.h"
#include <optional>

namespace df3d_production {
// Original installed artwork selected by cf24bc..cf24e7, before cf2330's
// tint/composite cache. Never consult or populate graphics_info.
inline std::optional<int32_t> legwearOriginalTile(df::item* item) {
    if(!item || item->getType()!=df::item_type::PANTS || !farmFunctions())return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool pinned=[base] {
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<43;++i){hash^=base[0xcf24bc+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0x5313d04e2b768fc7);
    }();
    if(!pinned)return std::nullopt;
    static_assert(offsetof(df::itemdef_pantsst,texpos_item)==0x148);
    static_assert(offsetof(df::itemdef_pantsst,procedural_item_graphics)==0x168);
    auto* raw=static_cast<df::itemdef_pantsst*>(DFHack::Items::getSubtypeDef(item->getType(),item->getSubtype()));
    if(!raw)return std::nullopt;
    // The generated DFHack enum names do not match this pinned executable's
    // values. Preserve the observed native branch, including raw-art fallback.
    const auto shape=static_cast<int32_t>(raw->procedural_item_graphics);
    const auto tile=shape==10?*reinterpret_cast<const int32_t*>(base+0x264af54):
        shape==11?*reinterpret_cast<const int32_t*>(base+0x264af58):raw->texpos_item;
    return tile>0?std::optional<int32_t>(tile):std::nullopt;
}
}
