#pragma once
#include "trade_projection_native.h"

namespace df3d_production {
// Pointer-free conversation state. A session must validate its source before
// rehydrating it; item IDs alone do not authorize an exchange.
struct TradeConversation {
    int16_t dialogue=0;
    bool counterOffer=false;
    std::vector<int32_t> requestedItems;
    std::vector<std::string> announcement;
};
struct TradeNegotiationCheckpoint {
    TradeDraftCheckpoint draft;
    TradeConversation conversation;
};
// Safe-point lifetime only. Entry metadata and goods are independently owned;
// no active native trade menu is read or borrowed. This context does not yet
// expose execution: native refusal checks and exchange effects remain separate.
class TradeNegotiationNative {
    TradeDraftNative draft;
    bool valid=false;
public:
    TradeNegotiationNative(df::building* building,size_t caravanIndex,const TradeDraftCheckpoint& selection)
        :draft(building,caravanIndex) {
        if(!draft || !draft.restore(selection) || !tradeEntryNativeReady())return;
        auto* depot=virtual_cast<df::building_tradedepotst>(building);
        auto* site=df::world_site::find(df::global::plotinfo->site_id);
        if(!depot || !site || caravanIndex>=df::global::plotinfo->caravans.size())return;
        auto* caravan=df::global::plotinfo->caravans[caravanIndex];if(!caravan)return;
        auto& owned=draft.owned;owned.st=site;owned.bld=depot;
        const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
        reinterpret_cast<void(*)(df::trade_interfacest*,df::caravan_state*)>(base+0x36b590)(&owned,caravan);
        valid=owned.mer==caravan && owned.civ && owned.fortress_trader;
    }
    TradeNegotiationNative(const TradeNegotiationNative&)=delete;
    TradeNegotiationNative& operator=(const TradeNegotiationNative&)=delete;
    ~TradeNegotiationNative(){
        // curses_text_boxst owns pointers, unlike the context's value vectors.
        // Initialization is already version-checked before it can allocate.
        if(!draft.owned.big_announce.text.empty()){
            const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
            reinterpret_cast<void(*)(df::curses_text_boxst*)>(base+0xbb9b0)(&draft.owned.big_announce);
        }
    }
    explicit operator bool() const{return valid;}
    std::optional<TradeNegotiationCheckpoint> checkpoint() const {
        if(!valid)return {};
        const auto sides=draft.snapshot();if(!sides)return {};
        const auto& owned=draft.owned;
        TradeNegotiationCheckpoint result;result.draft={*sides,owned.item_filter};
        auto& c=result.conversation;c.dialogue=int16_t(owned.talkline);c.counterOffer=owned.counter_offer;
        if(c.dialogue < -1 || c.dialogue>28 || owned.counter_offer_item.size()>1048576 || owned.big_announce.text.size()>2049)return {};
        for(const auto* item:owned.counter_offer_item){if(!item || item->id<0)return {};c.requestedItems.push_back(item->id);}
        size_t bytes=0;
        for(const auto* line:owned.big_announce.text){if(!line || line->size()>2048)return {};bytes+=line->size();if(bytes>16384)return {};c.announcement.push_back(*line);}
        return result;
    }
};
}
