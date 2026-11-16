#pragma once
#include "farm_native.h"
#include "df/item_threadst.h"
#include "df/world.h"
#include <optional>

namespace df3d_production {
struct WebAppearanceFacts { int8_t pattern, thick; };
// c7e552..c7e5fb selects web artwork from absolute position and is_thick.
// 2471c0 mutates only its supplied seed. Supply owned scratch, never the
// renderer's global seed or graphics tables. Call at a simulation safe point.
inline std::optional<WebAppearanceFacts> itemWebAppearance(df::item* item) {
    if(!item || !df::global::world || !farmFunctions() ||
       item->getType()!=df::item_type::THREAD || !item->flags.bits.spider_web)return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool pinned=[base] {
        const auto hash=[base](size_t at,size_t count) {
            uint64_t value=UINT64_C(14695981039346656037);
            for(size_t i=0;i<count;++i){value^=base[at+i];value*=UINT64_C(1099511628211);}
            return value;
        };
        return hash(0xc7e552,0xaa)==UINT64_C(0x2d6449608f0bd9ba) &&
            hash(0x2471c0,0x4b)==UINT64_C(0xa34702d10f978500);
    }();
    if(!pinned)return std::nullopt;
    static_assert(offsetof(df::item_threadst,is_thick)==0x144);
    static_assert(offsetof(df::world,map)+offsetof(df::world::T_map,region_x)==0x116bf8);
    static_assert(offsetof(df::world::T_map,region_y)==offsetof(df::world::T_map,region_x)+4);
    static_assert(offsetof(df::world::T_map,region_z)==offsetof(df::world::T_map,region_x)+8);
    const auto& map=df::global::world->map;
    // Unsigned arithmetic preserves the native modulo-2^64 seed for all inputs.
    uint64_t seed=uint64_t(int64_t(item->pos.z))+uint64_t(int64_t(map.region_z));
    seed=seed*10000+uint64_t(int64_t(item->pos.y))+uint64_t(int64_t(map.region_y))*48;
    seed=seed*10000+uint64_t(int64_t(item->pos.x))+uint64_t(int64_t(map.region_x))*48;
    using Next=uint64_t(*)(uint64_t*);
    const auto pattern=(reinterpret_cast<Next>(base+0x2471c0)(&seed)>>32)&3;
    return WebAppearanceFacts{int8_t(pattern),int8_t(static_cast<df::item_threadst*>(item)->is_thick)};
}
}
