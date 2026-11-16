#pragma once
#include "trade_display_native.h"
#include "trade_negotiation_native.h"

namespace df3d_production {
inline bool tradeCounterNativeReady(){
    if(!tradeDisplayFactsReady())return false;
    static const bool ready=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin{size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={{0x386aa2,0x1db,UINT64_C(0xc5466a818a7dcff6)},
            {0x386691,0x60,UINT64_C(0x7cafc1a73701fba4)},
            {0x162b3d0,0x1d,UINT64_C(0x6e5db7b135279807)},
            {0x162b3a8,0x21,UINT64_C(0x475e169b3db71206)},
            {0x15eed60,0x5,UINT64_C(0x90c27c21966538cb)}};
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}if(hash!=pin.hash)return false;}
        return true;
    }();return ready;
}
struct TradeCounterPage {TradeDisplayPage page;std::array<std::string,2> heading;std::string dismiss;};
// The enclosing session validates source/revision and owns this checkpoint.
// List visibility is independent of counterOffer: native retains these rows
// after acceptance until Okay clears only the requested-items vector.
inline std::optional<TradeCounterPage> tradeCounterPage(df::building* building,size_t caravanIndex,
    const TradeNegotiationCheckpoint& saved,size_t offset,size_t limit){
    const auto& ids=saved.conversation.requestedItems;
    if(!tradeCounterNativeReady() || !limit || limit>64 || offset>ids.size() || ids.size()>1048576)return {};
    TradeCounterPage result;result.page.offset=offset;result.page.total=ids.size();
    const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    result.heading={reinterpret_cast<const char*>(base+0x162b3d0),reinterpret_cast<const char*>(base+0x162b3a8)};
    result.dismiss=reinterpret_cast<const char*>(base+0x15eed60);
    std::vector<int32_t> wanted;
    for(size_t i=offset;i<std::min(ids.size(),offset+limit);++i){
        const auto id=ids[i];bool present=false;
        for(int side=1;side>=0;--side){if(side==0 && saved.conversation.counterOffer)break;
            const auto& goods=saved.draft.sides[side].items;present|=std::find(goods.begin(),goods.end(),id)!=goods.end();}
        auto* item=present?df::item::find(id):nullptr;if(!item)return {};
        TradeDisplayRow row;row.id=id;row.type=int(item->getType());row.subtype=item->getSubtype();
        if(!tradeDisplayItemFacts(item,1,0,row))return {};
        row.expandable=false;result.page.rows.push_back(std::move(row));wanted.push_back(id);
    }
    const auto values=tradeRowValuesForItems(building,caravanIndex,wanted);if(!values)return {};
    for(size_t i=0;i<values->size();++i)result.page.rows[i].valuation=(*values)[i];
    return result;
}
}
