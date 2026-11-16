#pragma once
#include "trade_projection_native.h"
#include "trade_value_totals_native.h"
#include "trade_capacity_native.h"
#include "trade_dialogue_native.h"
#include <memory>

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
inline bool tradeNegotiationNativeReady(){
    if(!tradeRefusalNativeReady())return false;
    static const bool ready=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin{size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={{0x369490,0x12f0,UINT64_C(0x26d292e102cd0ee8)},
            {0x36a9c0,0x6f0,UINT64_C(0xee4669ba81c63227)},
            {0x1367d10,0xaa0,UINT64_C(0x9f1dafacf3bb34b1)},
            {0x13687b0,0x1e6,UINT64_C(0x5cc0af1f23613928)},
            {0x13b1230,0x1d5,UINT64_C(0x18579bd4fd08baf0)}};
        for(const auto& pin:pins){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<pin.length;++i){h^=base[pin.rva+i];h*=UINT64_C(1099511628211);}if(h!=pin.hash)return false;}
        return true;
    }();return ready;
}
inline bool tradeGiftNativeReady(){
    if(!tradeNegotiationNativeReady())return false;
    static const bool ready=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin{size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={{0x31b61c,0xc75,UINT64_C(0xf26de1911580f308)},
            {0x31a684,0x4f,UINT64_C(0x6a2b6cc1ea1df08b)},
            {0xc90690,0x191,UINT64_C(0xcdaf6397bb0e22cd)},
            {0xc88300,0xdd,UINT64_C(0xe270d2ba3f4072a3)},
            {0x54bdc0,0x134,UINT64_C(0x4fb33b5d7f53a49a)},
            {0x30cbb0,0xc0,UINT64_C(0x844796c1331a0efa)},
            {0x72660,0x7d,UINT64_C(0x2414953f9e9e9670)}};
        for(const auto& pin:pins){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<pin.length;++i){h^=base[pin.rva+i];h*=UINT64_C(1099511628211);}if(h!=pin.hash)return false;}
        return true;
    }();return ready;
}
inline bool tradeSeizeNativeReady(){
    if(!tradeGiftNativeReady())return false;
    static const bool ready=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin{size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={{0x31a6fc,0xaf6,UINT64_C(0x468cd562be8dc42e)},
            {0xc90540,0x14e,UINT64_C(0x58919eb607da9f3e)}};
        for(const auto& pin:pins){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<pin.length;++i){h^=base[pin.rva+i];h*=UINT64_C(1099511628211);}if(h!=pin.hash)return false;}
        return true;
    }();return ready;
}
// Safe-point lifetime only. Entry metadata and goods are independently owned;
// no active native trade menu is read or borrowed.
// Refusal checks retain DF's inline branch order;
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
        owned.buildlists=0; // Draft goods have already been constructed independently.
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
    // Rehydrate only into a freshly constructed context after the owner has
    // validated epoch/session/source. Resolve requested goods from this fresh
    // goods vectors, never from a retained pointer or arbitrary ID. Accepted
    // counteroffer rows remain visible after their items change sides.
    bool restore(const TradeNegotiationCheckpoint& saved){
        if(!valid)return false;
        const auto& c=saved.conversation;
        if(c.dialogue < -1 || c.dialogue>28 || c.requestedItems.size()>1048576 || c.announcement.size()>2049)return false;
        size_t bytes=0;
        std::vector<std::unique_ptr<std::string>> lines;lines.reserve(c.announcement.size());
        for(const auto& line:c.announcement){bytes+=line.size();if(line.size()>2048 || bytes>16384)return false;lines.push_back(std::make_unique<std::string>(line));}
        auto& owned=draft.owned;
        std::vector<df::item*> requested;requested.reserve(c.requestedItems.size());
        for(auto id:c.requestedItems){
            df::item* resolved=nullptr;
            for(int side=1;side>=0;--side){
                if(side==0 && c.counterOffer)break;
                const auto found=std::find_if(owned.good[side].begin(),owned.good[side].end(),[id](const auto* item){return item && item->id==id;});
                if(found!=owned.good[side].end()){resolved=*found;break;}
            }
            if(id<0 || !resolved)return false;
            requested.push_back(resolved);
        }
        std::vector<std::string*> text;text.reserve(lines.size());for(const auto& line:lines)text.push_back(line.get());
        if(!draft.restore(saved.draft))return false;
        const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
        reinterpret_cast<void(*)(df::curses_text_boxst*)>(base+0xbb9b0)(&owned.big_announce);
        owned.big_announce.text.swap(text);for(auto& line:lines)line.release();
        owned.counter_offer_item.swap(requested);owned.counter_offer=c.counterOffer;owned.talkline=df::talk_line_type(c.dialogue);
        return true;
    }
    bool dismissCounteroffer(){
        if(!valid || draft.owned.counter_offer_item.empty())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        static const bool ready=[&]{
            uint64_t call=UINT64_C(14695981039346656037),leaf=call;
            for(size_t i=0;i<0xc;++i){call^=base[0x316469+i];call*=UINT64_C(1099511628211);}
            for(size_t i=0;i<0x10;++i){leaf^=base[0x6f290+i];leaf*=UINT64_C(1099511628211);}
            return call==UINT64_C(0x7ac93c1f9e5ff193) && leaf==UINT64_C(0x75c670f8be377ee6);
        }();if(!ready)return false;
        reinterpret_cast<void(*)(std::vector<df::item*>*)>(const_cast<uint8_t*>(base)+0x6f290)(&draft.owned.counter_offer_item);
        return true;
    }
    bool apply(const TradeSelectionIntent& intent){return valid && draft.apply(intent);}
    bool goodsNeedRebuild() const {return valid && draft.owned.buildlists!=0;}
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
    // Mutating native negotiation, never a preview. A successful call can
    // train both traders, change caravan state, request a counteroffer or
    // transfer goods. The owning session must retire/rebind its source after
    // effects and report uncertainty if copying the outcome fails.
    bool negotiate(bool* effectsStarted=nullptr){
        if(!tradeNegotiationNativeReady() || checkOffer().disposition!=TradeOfferDisposition::Ready)return false;
        const auto rows=draft.snapshot();if(!rows)return false;
        auto& owned=draft.owned;
        const auto values=tradeValueTotals(owned.bld,caravanIndex,*rows);
        const auto capacity=tradeCapacity(owned.bld,caravanIndex,*rows);
        if(!values || !capacity)return false;
        df::massst remaining{};remaining.whole=capacity->whole;remaining.fraction=capacity->fraction;
        const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
        if(effectsStarted)*effectsStarted=true;
        reinterpret_cast<void(*)(df::trade_interfacest*,int32_t,int32_t,df::massst*)>(base+0x369490)(&owned,values->actual[0],values->actual[1],&remaining);
        return true;
    }
    // Native Gift is inline in input31b61c..31c291. Keep its dispatch order
    // here; ownership, container detachment, depot insertion, reference and
    // artifact-history effects use DF routines with this owned context.
    bool offerGift(bool* effectsStarted=nullptr){
        if(!valid || !tradeGiftNativeReady())return false;
        auto& owned=draft.owned;
        static_assert(offsetof(df::plotinfost,king_arrived)==0xaa);
        if(df::global::plotinfo->king_arrived && owned.civ->id==df::global::plotinfo->civ_id)return false;
        const auto check=checkOffer();if(check.disposition==TradeOfferDisposition::Unavailable)return false;
        const auto rows=draft.snapshot();if(!rows)return false;
        const auto values=tradeValueTotals(owned.bld,caravanIndex,*rows);
        const auto capacity=tradeCapacity(owned.bld,caravanIndex,*rows);
        if(!values || !capacity || !df::global::world || df::global::world->artifact_history_suppression_count==INT32_MAX)return false;
        // Native exposed selection uses whole stacks; reject a foreign draft
        // rather than introducing a partial-stack interface that DF does not use.
        for(size_t i=0;i<owned.good[1].size();++i){
            if(owned.good_amount[1][i])return false;
            // Native31a684..31a6ce disables Gift for selected imported goods.
            if(owned.goodflag[1][i].bits.selected && owned.good[1][i]->flags.bits.foreign)return false;
        }
        const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
        if(effectsStarted)*effectsStarted=true;
        if(check.ethical)refuseOffer();
        else if(capacity->whole<0){
            const auto previous=int16_t(owned.talkline);
            owned.talkline=df::talk_line_type(previous==3?4:previous==4?3:3+reinterpret_cast<int32_t(*)(int32_t)>(base+0x71f30)(2));
        }else if(values->actual[1]<=0)owned.talkline=df::talk_line_type(10);
        else{
            owned.talkline=df::talk_line_type(8);
            for(size_t i=0;i<owned.good[1].size();++i){
                auto* item=owned.good[1][i];const bool selected=owned.goodflag[1][i].bits.selected;
                {
                    struct SuppressHistory {int32_t& count;explicit SuppressHistory(int32_t& v):count(v){++count;}~SuppressHistory(){--count;}} suppression(df::global::world->artifact_history_suppression_count);
                    if(selected)reinterpret_cast<void(*)(df::item*,df::historical_entity*,bool)>(base+0xc90690)(item,owned.civ,true);
                    bool detach=false;
                    for(auto* ref:item->general_refs)if(ref && ref->getType()==df::general_ref_type::CONTAINED_IN_ITEM){
                        auto* parent=ref->getItem();if(parent && bool(parent->flags.bits.trader)!=selected){detach=true;break;}
                    }
                    if(detach){
                        reinterpret_cast<void(*)(df::item*)>(base+0xc88300)(item);
                        reinterpret_cast<void(*)(df::building*,df::item*)>(base+0x54bdc0)(owned.bld,item);
                        item->flags.bits.in_building=true;
                    }
                    if(selected){
                        reinterpret_cast<void(*)(df::item*)>(base+0x30cbb0)(item);
                        reinterpret_cast<void(*)(df::item*,int32_t,int32_t)>(base+0x72660)(item,int32_t(df::general_ref_type::ENTITY_OFFERED),owned.civ->id);
                    }
                }
                if(selected)reinterpret_cast<void(*)(df::trade_interfacest*,df::item*,df::historical_entity*,df::historical_entity*,bool,bool)>(base+0x36a9c0)(&owned,item,owned.civ,df::global::plotinfo->main.fortress_entity,true,false);
            }
            owned.buildlists=1;
        }
        owned.counter_offer=false;
        return true;
    }
    // Seize has its own native gates, not Trade's ethical/capacity refusal path.
    // Native31a6fc..31b1f2 dispatches the inline action; all item ownership
    // and artifact effects operate on this independently owned context.
    bool seize(bool* effectsStarted=nullptr){
        if(!valid || !tradeSeizeNativeReady())return false;
        auto& owned=draft.owned;
        if(!df::global::plotinfo || !df::global::world || !owned.civ || !owned.mer ||
           !df::global::plotinfo->main.fortress_entity || owned.civ->id==df::global::plotinfo->civ_id ||
           df::global::world->artifact_history_suppression_count==INT32_MAX)return false;
        const auto rows=draft.snapshot();if(!rows)return false;
        const auto values=tradeValueTotals(owned.bld,caravanIndex,*rows);if(!values)return false;
        for(auto amount:owned.good_amount[0])if(amount)return false;
        const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
        if(effectsStarted)*effectsStarted=true;
        // Native empty Seize changes dialogue only, retaining the counteroffer.
        if(values->actual[0]<=0){owned.talkline=df::talk_line_type(11);return true;}
        owned.talkline=df::talk_line_type(9);
        for(size_t i=0;i<owned.good[0].size();++i){
            auto* item=owned.good[0][i];const bool selected=owned.goodflag[0][i].bits.selected;
            {
                struct SuppressHistory {int32_t& count;explicit SuppressHistory(int32_t& v):count(v){++count;}~SuppressHistory(){--count;}} suppression(df::global::world->artifact_history_suppression_count);
                if(selected)reinterpret_cast<void(*)(df::item*,bool)>(base+0xc90540)(item,true);
                bool detach=false;
                for(auto* ref:item->general_refs)if(ref && ref->getType()==df::general_ref_type::CONTAINED_IN_ITEM){
                    auto* parent=ref->getItem();if(parent && bool(parent->flags.bits.trader)==selected){detach=true;break;}
                }
                if(detach){
                    reinterpret_cast<void(*)(df::item*)>(base+0xc88300)(item);
                    reinterpret_cast<void(*)(df::building*,df::item*)>(base+0x54bdc0)(owned.bld,item);
                }
                if(selected){
                    item->flags.bits.in_building=false;
                    reinterpret_cast<void(*)(df::item*)>(base+0x30cbb0)(item);
                    reinterpret_cast<void(*)(df::item*,int32_t,int32_t)>(base+0x72660)(item,int32_t(df::general_ref_type::ENTITY_STOLEN),owned.civ->id);
                    owned.mer->flags.whole|=0x30;
                    owned.mer->mood=0;
                    if(owned.mer->time_remaining>501)owned.mer->time_remaining=501;
                }
            }
            if(selected)reinterpret_cast<void(*)(df::trade_interfacest*,df::item*,df::historical_entity*,df::historical_entity*,bool,bool)>(base+0x36a9c0)(&owned,item,df::global::plotinfo->main.fortress_entity,owned.civ,false,true);
        }
        owned.buildlists=1;owned.counter_offer=false;
        return true;
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
