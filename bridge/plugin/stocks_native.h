#pragma once
#include "building_item_native.h"
#include "df/world.h"
#include <cstddef>

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
struct Group {int16_t type,subtype,subcat1,subcat2;int32_t amount;bool expanded;};
// Native ac9c30 owns no globals: abstract-list insertion/matching uses the
// supplied vectors and authoritative item properties/history. Keep all storage
// here, including MSVC's packed expanded bits; no stocks_interfacest is borrowed.
inline std::optional<std::vector<Group>> groups() {
    const auto ids=inventory();if(!ids)return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool supported=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0xac9c30,0x50a,UINT64_C(0x7fbce42d6c033414)},
            {0xac9890,0x173,UINT64_C(0xc19090f1c488ecc4)},
            {0xac9710,0x17a,UINT64_C(0xcdf19b8b33e636a4)},
            {0xaca720,0x7a,UINT64_C(0x12b032d63e998c99)},
            {0x13bfd0,0xe8,UINT64_C(0xd4a98ca43e7cadb7)},
            {0x13c270,0x229,UINT64_C(0x09e5c9aa6e43d09c)},
            {0x13d4f0,0xed,UINT64_C(0xe857e2f78065b8b9)},
            {0x70e20,0x117,UINT64_C(0x09aba69f846f6c10)},
            {0x71040,0x112,UINT64_C(0x5f2ee621244a5576)}};
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;}
        return true;
    }();
    if(!supported)return std::nullopt;
    struct Context {
        std::vector<int16_t> type,subtype,subcat1,subcat2;
        std::vector<int32_t> amount;
        std::vector<bool> expanded;
    } owned;
    static_assert(offsetof(Context,amount)==0x60 && offsetof(Context,expanded)==0x78 && sizeof(Context)==0x98);
    const auto add=reinterpret_cast<void (*)(Context*,df::item*)>(base+0xac9c30);
    for(auto id:*ids){auto* item=df::item::find(id);if(!item)return std::nullopt;add(&owned,item);}
    const auto count=owned.type.size();
    if(owned.subtype.size()!=count || owned.subcat1.size()!=count || owned.subcat2.size()!=count ||
       owned.amount.size()!=count || owned.expanded.size()!=count)return std::nullopt;
    std::vector<Group> result;result.reserve(count);
    for(size_t i=0;i<count;++i)result.push_back({owned.type[i],owned.subtype[i],owned.subcat1[i],owned.subcat2[i],owned.amount[i],owned.expanded[i]});
    return result;
}
}
