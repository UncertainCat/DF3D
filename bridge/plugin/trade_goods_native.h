#pragma once
#include "trade_entry_native.h"
#include "df/buildingitemst.h"
#include "df/item.h"
#include <array>
#include <vector>

namespace df3d_production {
using TradeGoodsSources=std::array<std::vector<int32_t>,2>;
// Native384d53..384f06 enumerates inline in its renderer. Keep that small
// simulation adapter here; use DF's owner resolution, comparator and qsort.
// No rendering, appraisal history, menu vectors or item mutation is involved.
inline std::optional<TradeGoodsSources> tradeGoodsSources(df::building* building,size_t caravanIndex) {
    const auto entry=tradeEntryFacts(building,caravanIndex);if(!entry)return {};
    auto* depot=virtual_cast<df::building_tradedepotst>(building);
    if(!depot || depot->contained_items.size()>1048576)return {};
    static const bool ready=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x384d53,0x1b3,UINT64_C(0xbd494cd051a74426)},
            {0x384790,0xb9,UINT64_C(0xd282802910de7b79)},
            {0xcb1790,0x63,UINT64_C(0x3417555f1a78414f)},
        };
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}if(hash!=pin.hash)return false;}
        return true;
    }();if(!ready)return {};
    const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    using Owner=df::historical_entity*(*)(df::item*,int32_t);
    using Compare=int(*)(const void*,const void*);
    using Sort=void(*)(void*,size_t,size_t,Compare);
    const auto owner=reinterpret_cast<Owner>(base+0xcb1790);
    const auto compare=reinterpret_cast<Compare>(base+0x384790);
    // Pinned executable import: api-ms-win-crt-utility-l1-1-0.dll!qsort.
    const auto sort=*reinterpret_cast<const Sort*>(base+0x15e5d60);
    if(!sort)return {};
    auto* civilization=df::historical_entity::find(entry->entity);if(!civilization)return {};
    std::array<std::vector<df::item*>,2> owned;
    for(const auto* contained:depot->contained_items) {
        if(!contained || !contained->item)return {};
        auto* item=contained->item;
        if(int(contained->use_mode)==2 || !item->flags.bits.in_building)continue;
        if(item->id<0)return {};
        if(item->flags.bits.trader){if(owner(item,45)==civilization)owned[0].push_back(item);}
        else owned[1].push_back(item);
    }
    TradeGoodsSources result;
    for(size_t side=0;side<2;++side){auto& list=owned[side];if(!list.empty())sort(list.data(),list.size(),sizeof(df::item*),compare);result[side].reserve(list.size());for(const auto* item:list)result[side].push_back(item->id);}
    return result;
}
}
