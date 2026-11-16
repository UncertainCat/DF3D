#pragma once
#include "trade_row_values_native.h"
#include <cstring>

namespace df3d_production {
struct TradeValueTotals {
    std::array<int32_t,2> actual{},estimated{};
    int32_t actualProfit=0,estimatedProfit=0,profitColor=6,brokerAppraisal=0;
    std::array<std::string,2> valueCaptions;
    std::string profitCaption;
};
// Value-only footer projection. Native estimates each selected row with broker
// knowledge before summation, even when row captions use the present trader.
// Carrying capacity/weight and negotiation eligibility are separate contracts.
inline std::optional<TradeValueTotals> tradeValueTotals(df::building* building,size_t caravanIndex,
    const std::array<TradeProjectedSide,2>& projected) {
    if(!depotGoodsValuesReady())return {};
    const auto entry=tradeEntryFacts(building,caravanIndex);const auto appraisal=depotAppraisal();
    if(!entry || !appraisal)return {};
    const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    static const bool ready=[&] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={{0x77f740,0x1dc,UINT64_C(0xab69b8693d1a4899)},
            {0x38886a,0x105,UINT64_C(0x25ae0e84553030d0)},
            {0x389076,0xf9,UINT64_C(0xc0f945a62fa4450a)},
            {0x3891b4,0x346,UINT64_C(0x491865fa9766ec7a)},
            {0x52c130,0xb3,UINT64_C(0xf2e358ad54df1c09)}};
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);const auto* bytes=reinterpret_cast<const uint8_t*>(base+pin.rva);for(size_t i=0;i<pin.length;++i){hash^=bytes[i];hash*=UINT64_C(1099511628211);}if(hash!=pin.hash)return false;}
        return std::memcmp(reinterpret_cast<const void*>(base+0x15fe080),"Value: ",8)==0 &&
            std::memcmp(reinterpret_cast<const void*>(base+0x162b278),"Trader Profit: ",16)==0 &&
            std::memcmp(reinterpret_cast<const void*>(base+0x162b268),"Trader Loss: ",14)==0;
    }();if(!ready)return {};
    auto* civ=df::historical_entity::find(entry->entity);if(!civ)return {};
    auto* caravan=df::global::plotinfo->caravans[caravanIndex];
    const auto signedBits=[](uint32_t bits){int32_t value;std::memcpy(&value,&bits,sizeof(value));return value;};
    TradeValueTotals result;result.brokerAppraisal=*appraisal;
    for(size_t side=0;side<2;++side) {
        const auto& rows=projected[side];if(rows.items.size()!=rows.flags.size() || rows.items.size()!=rows.amounts.size())return {};
        uint32_t actual=0,estimated=0;
        for(size_t i=0;i<rows.items.size();++i) {
            // No partial-quantity UI is qualified yet. Never temporarily change
            // simulation stack sizes to calculate an unsupported draft.
            if(rows.amounts[i]!=0)return {};
            if(!(rows.flags[i]&1))continue;
            auto* item=df::item::find(rows.items[i]);if(!item)return {};
            const auto value=reinterpret_cast<int32_t(*)(df::item*,df::caravan_state*,df::historical_entity*,bool,bool)>(base+0xc66020)(item,caravan,civ,false,true);
            const auto estimate=reinterpret_cast<int32_t(*)(int32_t,int32_t)>(base+0x77f740)(value,*appraisal-1);
            actual+=uint32_t(value);estimated+=uint32_t(estimate);
        }
        result.actual[side]=signedBits(actual);result.estimated[side]=signedBits(estimated);
    }
    result.actualProfit=signedBits(uint32_t(result.actual[1])-uint32_t(result.actual[0]));
    result.estimatedProfit=signedBits(uint32_t(result.estimated[1])-uint32_t(result.estimated[0]));
    if(result.estimatedProfit<0 || result.actualProfit<0)result.profitColor=4;
    else if(result.actual[0]>0 && signedBits(uint32_t(result.actualProfit)*100u)/result.actual[0]>=50)result.profitColor=2;
    // Native389272/38932a formats the already-estimated sum directly. Calling
    // the item appraisal formatter here would incorrectly estimate it twice.
    const auto caption=[base](size_t label,int32_t value) {
        std::string text=reinterpret_cast<const char*>(base+label);
        reinterpret_cast<void(*)(int32_t,std::string*)>(base+0x52c130)(value,&text);
        text.push_back('\x0f');return text;
    };
    for(size_t side=0;side<2;++side)result.valueCaptions[side]=caption(0x15fe080,result.estimated[side]);
    const bool loss=result.estimatedProfit<0;
    result.profitCaption=caption(loss?0x162b268:0x162b278,
        loss?signedBits(0u-uint32_t(result.estimatedProfit)):result.estimatedProfit);
    return result;
}
}
