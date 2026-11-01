#pragma once
#include "creature_items_native.h"

namespace df3d_production {
struct ItemOwnerDescription { int32_t id=-1;std::string name; };
// Sheet154878 resolves UNIT_ITEMOWNER (16), independently of UNIT_HOLDER (18).
// Keep the name formatter's unit/body scratch and random streams owned.
inline std::optional<ItemOwnerDescription> itemOwnerDescription(df::item* item) {
    if(!item||!df3d_creature::inventoryDescriptionReady())return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool pinned=[base] {
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x63;++i){hash^=base[0xcb1640+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0x576ff7966803ca67);
    }();
    if(!pinned)return std::nullopt;
    using Find=df::unit* (*)(df::item*,int32_t);
    using Name=void (*)(df::unit*,std::string*,bool);
    ItemOwnerDescription result;
    if(auto* owner=reinterpret_cast<Find>(base+0xcb1640)(item,16)) {
        if(owner->inventory.size()>10000)return std::nullopt;
        for(const auto* entry:owner->inventory)if(!entry)return std::nullopt;
        df3d_creature::InventoryRandomRestore restore(base);
        df3d_creature::InventoryDescriptionContext context(*owner);
        result.id=owner->id;
        reinterpret_cast<Name>(base+0x1330c30)(context.unit(),&result.name,false);
        if(result.name.size()>512)return std::nullopt;
    }
    return result;
}
} // namespace df3d_production
