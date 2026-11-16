#pragma once
#include "trade_projection_native.h"
#include "depot_selection_native.h"

namespace df3d_production {
struct TradeRowValue {int32_t id=-1,value=0,appraisal=0;std::string valueCaption,weightCaption;};
// Native row rendering386df3..386f64 /387d6c..387ee1: current trader
// Appraisal overrides the broker fallback; value uses caravan/civ and excludes
// bin contents. Native weight and effective-skill routines may refresh semantic
// caches. No appraisal training/history, menu or graphics storage is accessed.
inline std::optional<std::vector<TradeRowValue>> tradeRowValuesForItems(df::building* building,
    size_t caravanIndex,const std::vector<int32_t>& items) {
    if(items.size()>64 || !depotGoodsValuesReady() || !depotValuationReady())return {};
    const auto entry=tradeEntryFacts(building,caravanIndex);if(!entry)return {};
    const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    static const bool ready=[&] {
        uint64_t hash=UINT64_C(14695981039346656037);
        const auto* bytes=reinterpret_cast<const uint8_t*>(base+0x133e7a0);
        for(size_t i=0;i<0x32d;++i){hash^=bytes[i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0xb3c6cbdbc8f6dade);
    }();if(!ready)return {};
    auto* trader=df::unit::find(entry->fortressTrader);auto* civ=df::historical_entity::find(entry->entity);
    if(!trader || !civ)return {};
    auto* caravan=df::global::plotinfo->caravans[caravanIndex];
    const auto skill=reinterpret_cast<int32_t(*)(df::unit*,int32_t)>(base+0x133e7a0)(trader,73);
    if(skill==INT32_MAX)return {};
    const auto appraisal=std::max(0,skill)+1;
    std::vector<TradeRowValue> result;
    for(size_t i=0;i<items.size();++i) {
        auto* item=df::item::find(items[i]);if(!item)return {};
        TradeRowValue row;row.id=item->id;row.appraisal=appraisal;
        row.value=reinterpret_cast<int32_t(*)(df::item*,df::caravan_state*,df::historical_entity*,bool,bool)>(base+0xc66020)(item,caravan,civ,false,true);
        const auto value=depotValueCaption(row.value,appraisal);const auto weight=itemWeightCaption(item);
        if(!value || !weight || value->size()>512 || weight->size()>512)return {};
        row.valueCaption=*value;row.weightCaption=*weight;result.push_back(std::move(row));
    }
    return result;
}
inline std::optional<std::vector<TradeRowValue>> tradeRowValues(df::building* building,
    size_t caravanIndex,int32_t side,size_t offset,size_t limit) {
    if(side<0 || side>1 || !limit || limit>64)return {};
    const auto projected=tradeProjection(building,caravanIndex);if(!projected)return {};
    const auto& items=(*projected)[side].items;if(offset>items.size())return {};
    return tradeRowValuesForItems(building,caravanIndex,{items.begin()+offset,items.begin()+std::min(items.size(),offset+limit)});
}
}
