#pragma once
#include "trade_projection_native.h"
#include "unit_room_native.h"

namespace df3d_production {
struct TradeAppraisalEffect {size_t recorded=0,trained=0;};
// Explicit simulation mutation, never a query/refresh side effect. The inline
// native phase385603..3857bd deduplicates against caravan history, trains the
// physically present fortress trader for merchant goods, then records own goods.
// Native skill/attribute helpers own rust, caste rates, RNG, level-up and thoughts.
// No native trade menu, renderer or input state is an argument or scratch area.
// Index selection is diagnostic only; public transport needs caravan/session
// identity and revision validation before invoking this safe-point operation.
inline std::optional<TradeAppraisalEffect> tradeAppraise(df::building* building,size_t caravanIndex) {
    const auto entry=tradeEntryFacts(building,caravanIndex);if(!entry || !df3d_room::valuationReady())return {};
    const auto projected=tradeProjection(building,caravanIndex);if(!projected)return {};
    static const bool ready=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x385603,0x1ba,UINT64_C(0xdc886763f8f65d71)},
            {0x133baf0,0xc0,UINT64_C(0x1e6b18070415062e)},
            {0x10e8cf0,0x434,UINT64_C(0x6bb3f70556fa4ebf)},
            {0x133bcf0,0x2636,UINT64_C(0xbf332d0f67ce1d24)},
            {0x13eff80,0xa0,UINT64_C(0xb66acd69c2fb79b5)},
            {0x13d5020,0xc7,UINT64_C(0xd7891ab0b0d26797)},
            {0x775520,0xe07,UINT64_C(0x53e52af075dc35e5)},
            {0x13cadc0,0x9c,UINT64_C(0x15e778bc2a6c6fc2)},
            {0x131f610,0xa5,UINT64_C(0xef93518a44539319)},
        };
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}if(hash!=pin.hash)return false;}
        return true;
    }();if(!ready)return {};
    auto* trader=df::unit::find(entry->fortressTrader);
    auto* civ=df::historical_entity::find(entry->entity);if(!trader || !civ)return {};
    auto* caravan=df::global::plotinfo->caravans[caravanIndex];
    static_assert(offsetof(df::caravan_state,goods)==0x2100);
    std::array<std::vector<df::item*>,2> items;
    size_t count=0;
    for(size_t side=0;side<2;++side)for(auto id:(*projected)[side].items) {
        auto* item=df::item::find(id);if(!item)return {};
        items[side].push_back(item);++count;
    }
    auto& history=caravan->goods;
    if(count>history.max_size()-history.size())return {};
    // Resolve every target and allocate history before the first training call.
    // After this boundary, do not return an ordinary precondition rejection or
    // attempt to roll back native skill/world side effects.
    history.reserve(history.size()+count);
    const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    using Value=int32_t(*)(df::item*,df::caravan_state*,df::historical_entity*);
    using Train=void(*)(df::unit*,int16_t,int32_t);
    TradeAppraisalEffect result;
    for(size_t side=0;side<2;++side)for(auto* item:items[side]) {
        if(std::find(history.begin(),history.end(),item->id)!=history.end())continue;
        if(side==0) {
            const auto value=reinterpret_cast<Value>(base+0xc66c30)(item,caravan,civ);
            const auto amount=std::min(50,value/10+1);
            reinterpret_cast<Train>(base+0x133baf0)(trader,73,amount);
            reinterpret_cast<Train>(base+0x13d5020)(trader,73,amount*6);
            ++result.trained;
        }
        history.push_back(item->id);++result.recorded;
    }
    return result;
}
}
