#pragma once
#include "building_item_native.h"
#include "df/world.h"

namespace df3d_stocks {
// Native Stocks initializer377fe0 enumerates IN_PLAY and excludes c93160.
// Use only its semantic predicate: never call that menu initializer or touch
// item.temporary_32/base_uniform_score. Returned IDs retain simulation order;
// native Stocks sorting/grouping is a separate, not-yet-exposed operation.
inline std::optional<std::vector<int32_t>> inventory() {
    static const auto predicate=[]()->bool (*)(df::item*) {
        if(!df3d_production::farmFunctions())return nullptr;
        auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0xc93160,0x213,UINT64_C(0x07d957dea30ed105)},
            {0xc93060,0xf2,UINT64_C(0xaa1dff2bbdba178e)},
            {0x137bd50,0x2d0,UINT64_C(0xdee22d5bacd12bc9)},
            {0x1367430,0xc6,UINT64_C(0xc0292be8a6dacf2c)},
            {0x138ed20,0xff,UINT64_C(0x430951f9f3e403c2)},
            {0xc8be10,0x14c,UINT64_C(0x1ba19b485a3fa56b)},
            {0xc8baa0,0x11a,UINT64_C(0x2c62fce4a0555c66)},
            {0xedfa60,0xbd,UINT64_C(0x2f89116df6b958cc)},
            {0xedfb20,0x13,UINT64_C(0xa222e60f2f8301e4)},
            {0x14db50,0xb1,UINT64_C(0x4b9c987ca0656b35)},
            {0x14dc10,0x5a,UINT64_C(0xfb6e6c7bccbf765b)},
            {0x67270,6,UINT64_C(0x7dce27ae257f083d)},
            {0x7a840,6,UINT64_C(0xeff4222c8d49c252)}};
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return nullptr;}
        return reinterpret_cast<bool (*)(df::item*)>(base+0xc93160);
    }();
    if(!predicate || !df::global::world)return std::nullopt;
    const auto& items=df::global::world->items.other.IN_PLAY;
    if(items.size()>1048576)return std::nullopt; // Bound owned diagnostic output.
    std::vector<int32_t> ids;ids.reserve(items.size());
    for(auto* item:items){if(!item)return std::nullopt;if(!predicate(item))ids.push_back(item->id);}
    return ids;
}
}
