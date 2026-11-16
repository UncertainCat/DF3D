#pragma once
#include "trade_projection_native.h"
#include "trade_value_totals_native.h"
#include "trade_capacity_native.h"
#include "trade_dialogue_native.h"

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
enum class TradeOfferDisposition {Unavailable,Refused,Ready};
struct TradeOfferCheck {TradeOfferDisposition disposition=TradeOfferDisposition::Unavailable;int16_t reply=-1;bool alternating=false,ethical=false;};
inline bool tradeRefusalNativeReady(){
    if(!tradeDialogueNativeReady())return false;
    static const bool ready=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin{size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={{0x31a552,0x132,UINT64_C(0x0bf32f01daaa3f16)},
            {0x31b252,0x3c3,UINT64_C(0x9503654d447f154d)},
            {0xc90bc0,0x3a1,UINT64_C(0xa28c8ad0b097a1e3)},
            {0x36a780,0xb3,UINT64_C(0x0ac637bc9fd1bbdb)},
            {0x71f30,0x53,UINT64_C(0x5eb4fcfbdedb7745)}};
        for(const auto& pin:pins){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<pin.length;++i){h^=base[pin.rva+i];h*=UINT64_C(1099511628211);}if(h!=pin.hash)return false;}
        return true;
    }();return ready;
}
// Safe-point lifetime only. Entry metadata and goods are independently owned;
// no active native trade menu is read or borrowed. This context does not yet
// expose exchange execution. Refusal checks retain DF's inline branch order;
// semantic item/ethics queries, random choice and ethical consequences call DF.
class TradeNegotiationNative {
    TradeDraftNative draft;
    size_t caravanIndex=0;
    bool valid=false;
public:
    TradeNegotiationNative(df::building* building,size_t caravanIndex,const TradeDraftCheckpoint& selection)
        :draft(building,caravanIndex),caravanIndex(caravanIndex) {
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
    TradeOfferCheck checkOffer() const {
        if(!valid || !tradeRefusalNativeReady())return {};
        const auto& owned=draft.owned;
        if(!owned.merchant_trader || !owned.havetalker || owned.stillunloading || (owned.mer->flags.whole&0x20))return {};
        const auto rows=draft.snapshot();if(!rows)return {};
        const auto values=tradeValueTotals(owned.bld,caravanIndex,*rows);
        const auto capacity=tradeCapacity(owned.bld,caravanIndex,*rows);
        if(!values || !capacity)return {};
        const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
        const auto forbids=reinterpret_cast<bool(*)(int16_t)>(base+0x75cfd0);
        const auto animal=int16_t(owned.civ->resources.ethic[df::ethic_type::KILL_ANIMAL]);
        const bool forbidAnimal=forbids(animal) || animal==5 || animal==6;
        const bool forbidPlant=forbids(int16_t(owned.civ->resources.ethic[df::ethic_type::KILL_PLANT]));
        bool animalOffer=false,plantOffer=false;
        for(size_t i=0;i<owned.good[1].size();++i)if(owned.goodflag[1][i].bits.selected){
            auto* item=owned.good[1][i];
            animalOffer|=forbidAnimal && item->isAnimalProduct();
            plantOffer|=forbidPlant && reinterpret_cast<bool(*)(df::item*)>(base+0xc90bc0)(item);
        }
        if(animalOffer || plantOffer)return {TradeOfferDisposition::Refused,int16_t(animalOffer?(plantOffer?18:19):20),false,true};
        int16_t reply=-1;
        if(values->actual[0]<=0 && values->actual[1]<=0)reply=12;
        else if(values->actual[1]<=0)reply=14;
        else if(values->actual[0]<=0)reply=16;
        else if(values->actualProfit<0 && capacity->whole<0)reply=1;
        else if(values->actualProfit<0)reply=5;
        else if(capacity->whole<0)reply=3;
        return reply<0?TradeOfferCheck{TradeOfferDisposition::Ready}:TradeOfferCheck{TradeOfferDisposition::Refused,reply,true,false};
    }
    // An explicit action, never a read: the first alternating reply consumes
    // native RNG, and ethical refusal can train the broker and retire a caravan.
    // Caller supplies saving/source/revision gates and must not replay uncertainty.
    TradeOfferCheck refuseOffer(bool* effectsStarted=nullptr){
        const auto result=checkOffer();if(result.disposition!=TradeOfferDisposition::Refused)return result;
        auto& owned=draft.owned;const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
        int16_t reply=result.reply;
        if(effectsStarted)*effectsStarted=true;
        if(result.alternating){
            const auto previous=int16_t(owned.talkline);
            reply=previous==reply?int16_t(reply+1):previous==reply+1?reply:int16_t(reply+reinterpret_cast<int32_t(*)(int32_t)>(base+0x71f30)(2));
        }
        owned.talkline=df::talk_line_type(reply);
        if(result.ethical){
            reinterpret_cast<void(*)(df::trade_interfacest*)>(base+0x36a780)(&owned);
            if(owned.mer->time_remaining>501)owned.mer->time_remaining=501;
        }
        return result;
    }
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
