#pragma once
#include "depot_native.h"
#include "df/caravan_state.h"
#include "df/trade_interfacest.h"
#include "df/world_site.h"

namespace df3d_production {
struct TradeEntryFacts {
    int32_t entity=-1,fortressTrader=-1,merchantTrader=-1;
    int16_t dialogue=-1;
    bool unloading=false,hasSpeaker=false;
    std::string title,speaker,fortress,place;
};
// Initializes independently owned native storage. Never call the menu opener
// 36b970 or renderer384850: those tear down menus or apply appraisal effects.
inline bool tradeEntryNativeReady() {
    if(!depotNativeReady() || !df::global::world || !df::global::plotinfo)return false;
    static const bool ready=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x36b590,0x3d9,UINT64_C(0x7e362e3d93d7506a)},
            {0xa94030,0x6a1,UINT64_C(0xd81db68b3c9b33d2)},
            {0x1330c30,0x688,UINT64_C(0x0e165ee31decf426)},
            {0x52d3c0,0x288,UINT64_C(0x6e1fbc2416fba9fc)},
            {0xbb9b0,0x74,UINT64_C(0x7532991bab65be09)},
        };
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}if(hash!=pin.hash)return false;}
        return true;
    }();return ready;
}
// Caravan index is a synchronous diagnostic selector, not an async identity.
// Public commands still need source revision and caravan identity validation.
inline std::optional<TradeEntryFacts> tradeEntryFacts(df::building* building,size_t caravanIndex) {
    if(!tradeEntryNativeReady())return {};
    auto* depot=virtual_cast<df::building_tradedepotst>(building);
    const auto depotState=depotFacts(building);
    if(!depot || !depotState || !depotState->trade || depotState->worker<0)return {};
    for(const auto* job:depot->jobs)if(!job || job->job_type==df::job_type::DestroyBuilding)return {};
    const auto& caravans=df::global::plotinfo->caravans;
    if(caravanIndex>=caravans.size() || !caravans[caravanIndex])return {};
    auto* caravan=caravans[caravanIndex];
    if(int(caravan->trade_state)!=2 || caravan->flags.bits.tribute)return {};
    auto* site=df::world_site::find(df::global::plotinfo->site_id);
    if(!site || !df::historical_entity::find(caravan->entity))return {};
    static_assert(offsetof(df::trade_interfacest,st)==0xa8);
    static_assert(offsetof(df::trade_interfacest,bld)==0xb0);
    static_assert(offsetof(df::trade_interfacest,fortress_trader)==0xd8);
    static_assert(offsetof(df::trade_interfacest,buildlists)==0x37c);
    df::trade_interfacest owned{};owned.st=site;owned.bld=depot;
    const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    reinterpret_cast<void(*)(df::trade_interfacest*,df::caravan_state*)>(base+0x36b590)(&owned,caravan);
    if(owned.mer!=caravan || !owned.civ || !owned.fortress_trader || owned.fortress_trader->id!=depotState->worker ||
       owned.title.size()>512 || owned.talker.size()>512 || owned.fortname.size()>512 || owned.place.size()>512)return {};
    TradeEntryFacts result;result.entity=owned.civ->id;result.fortressTrader=owned.fortress_trader->id;
    result.merchantTrader=owned.merchant_trader?owned.merchant_trader->id:-1;
    result.dialogue=int16_t(owned.talkline);result.unloading=owned.stillunloading!=0;result.hasSpeaker=owned.havetalker!=0;
    result.title=std::move(owned.title);result.speaker=std::move(owned.talker);
    result.fortress=std::move(owned.fortname);result.place=std::move(owned.place);
    return result;
}
}
