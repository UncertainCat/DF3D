#pragma once
#include "farm_native.h"
#include "df/item_constructed.h"
#include "df/itemimprovement_coveredst.h"
#include "df/material.h"
#include "df/descriptor_pattern.h"
#include "df/world.h"
#include <optional>

namespace df3d_production {
// Native c811ea..c812e5's first qualifying encrustation, before the craft
// compositor. Semantic improvement/material inputs only; no graphics_info.
// -1 means no usable overlay color; nullopt means unavailable/invalid inputs.
inline std::optional<int32_t> craftGemColor(df::item* item) {
    if(!item || !farmFunctions())return std::nullopt;
    const auto kind=int(item->getType());
    if(kind<36 || kind>43 || kind==39)return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool pinned=[base] {
        const auto hash=[base](size_t at,size_t count) {
            uint64_t value=UINT64_C(14695981039346656037);
            for(size_t i=0;i<count;++i){value^=base[at+i];value*=UINT64_C(1099511628211);}
            return value;
        };
        return hash(0xc811ea,0xfb)==UINT64_C(0xbdcd9037365f5c20) &&
            hash(0x145bee0,0x5e)==UINT64_C(0x6abc4e374e372eef) &&
            hash(0x14add70,0x12f)==UINT64_C(0x01f897b15772d540);
    }();
    if(!pinned)return std::nullopt;
    static_assert(offsetof(df::item_constructed,improvements)==0xd0);
    static_assert(offsetof(df::itemimprovement_coveredst,cover_flags)==0x28);
    static_assert(offsetof(df::material,state_color)==0x9c);
    static_assert(offsetof(df::descriptor_pattern,colors)==0x20);
    auto* constructed=virtual_cast<df::item_constructed>(item);
    if(!constructed || constructed->improvements.size()>65536)return std::nullopt;
    using Flag=bool(*)(df::world*,int32_t,int16_t,int32_t);
    using Resolve=df::material*(*)(df::world*,int16_t,int32_t);
    for(auto* improvement:constructed->improvements) {
        if(!improvement)return std::nullopt;
        if(int(improvement->getType())!=1)continue;
        const auto* covered=static_cast<df::itemimprovement_coveredst*>(improvement);
        if((covered->cover_flags.whole&1) || improvement->mat_type!=0 ||
           !reinterpret_cast<Flag>(base+0x145bee0)(df::global::world,0x30,0,improvement->mat_index))continue;
        const auto* material=reinterpret_cast<Resolve>(base+0x14add70)(df::global::world,improvement->mat_type,improvement->mat_index);
        const auto* pattern=material?df::descriptor_pattern::find(material->state_color[0]):nullptr;
        // Native stops at the first qualifying improvement even if its color
        // cannot be resolved; it does not try a later gemstone.
        if(!pattern || pattern->colors.empty())return -1;
        const auto color=int32_t(pattern->colors.front());
        return color>=0 && color<255?color:-1;
    }
    return -1;
}
}
