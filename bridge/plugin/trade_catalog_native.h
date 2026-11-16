#pragma once
#include "trade_entry_native.h"
#include <limits>

namespace df3d_production {
struct TradeCaravanChoice {uint64_t token=0;int32_t entity=-1;std::string race,name;};
struct TradeCaravanCatalog {std::string title,from;std::vector<TradeCaravanChoice> choices;};
// Native opener36b9df..36ba49 enumerates inline; its remaining menu teardown is
// forbidden here. Labels follow renderer384bc9..384cad via native name helpers.
inline bool tradeCatalogNativeReady() {
    if(!tradeEntryNativeReady())return false;
    static const bool ready=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x36b9df,0x6a,UINT64_C(0xc9eac0173c3adce9)},
            {0x384bc9,0xe4,UINT64_C(0x0f00d092ac0aa5a3)},
            {0xaa3bd0,0x1c3,UINT64_C(0x0f9cd818efc6bad8)},
            {0x52d650,0x2b4,UINT64_C(0x9e8023d09def7af9)},
        };
        for(const auto& pin:pins){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<pin.length;++i){h^=base[pin.rva+i];h*=UINT64_C(1099511628211);}if(h!=pin.hash)return false;}
        return std::string(reinterpret_cast<const char*>(base+0x162a938))=="Select a merchant group to trade with:" &&
            std::string(reinterpret_cast<const char*>(base+0x15ed97c))==" from ";
    }();return ready;
}
class TradeCatalogOwner {
    struct Source {TradeCaravanCatalog catalog;std::vector<size_t> indices;uint64_t fingerprint=0;};
    struct Binding {uint64_t epoch=0;int32_t depot=-1;Source source;};
    std::optional<Binding> current;
    uint64_t serial=0;
    static std::optional<Source> read(df::building* building) {
        if(!tradeCatalogNativeReady())return {};
        const auto depot=depotFacts(building);
        if(!building || !depot || !depot->trade || depot->worker<0)return {};
        if(!df::world_site::find(df::global::plotinfo->site_id))return {};
        const auto& caravans=df::global::plotinfo->caravans;if(caravans.size()>4096)return {};
        Source result;result.catalog.title="Select a merchant group to trade with:";result.catalog.from=" from ";
        uint64_t hash=UINT64_C(14695981039346656037);
        const auto add=[&](uint64_t value){for(unsigned i=0;i<8;++i){hash^=uint8_t(value>>(8*i));hash*=UINT64_C(1099511628211);}};
        add(building->id);add(depot->worker);add(caravans.size());
        const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
        for(size_t i=0;i<caravans.size();++i) {
            const auto* caravan=caravans[i];if(!caravan)return {};
            // Internal observation only; addresses never leave this fingerprint.
            add(reinterpret_cast<uintptr_t>(caravan));add(caravan->entity);add(caravan->flags.whole);add(int(caravan->trade_state));
            if(caravan->flags.bits.tribute || int(caravan->trade_state)!=2)continue;
            const auto entry=tradeEntryFacts(building,i);if(!entry)return {};
            auto* civ=df::historical_entity::find(caravan->entity);if(!civ)return {};
            add(reinterpret_cast<uintptr_t>(caravan->buy_prices));add(reinterpret_cast<uintptr_t>(caravan->sell_prices));
            add(caravan->total_capacity.whole);add(caravan->total_capacity.fraction);add(caravan->mood);add(caravan->haggle_fail_count);
            add(caravan->goods.size());for(auto id:caravan->goods)add(id);
            TradeCaravanChoice choice;choice.entity=caravan->entity;
            reinterpret_cast<void(*)(int16_t,std::string*,bool,int16_t)>(base+0xaa3bd0)(civ->race,&choice.race,true,-1);
            reinterpret_cast<void(*)(std::string*)>(base+0x52d650)(&choice.race);
            reinterpret_cast<void(*)(df::language_name*,std::string*)>(base+0xa94030)(&civ->name,&choice.name);
            if(choice.race.size()>512 || choice.name.size()>512)return {};
            add(choice.race.size());for(unsigned char ch:choice.race)add(ch);
            add(choice.name.size());for(unsigned char ch:choice.name)add(ch);
            result.catalog.choices.push_back(std::move(choice));result.indices.push_back(i);
        }
        result.fingerprint=hash?hash:1;return result;
    }
public:
    void reset(){current.reset();}
    std::optional<TradeCaravanCatalog> refresh(uint64_t epoch,df::building* building) {
        reset();if(!epoch)return {};
        auto source=read(building);if(!source || source->catalog.choices.size()>std::numeric_limits<uint64_t>::max()-serial)return {};
        for(auto& choice:source->catalog.choices)choice.token=++serial;
        current=Binding{epoch,building->id,std::move(*source)};return current->source.catalog;
    }
    // Consume a choice only after re-reading the catalog. The index is returned
    // to a same-safe-point bridge caller, never used as the public choice ID.
    // This is entry selection, not authorization to transfer goods later.
    std::optional<size_t> take(uint64_t epoch,int32_t depot,uint64_t token) {
        if(!current || current->epoch!=epoch || current->depot!=depot)return {};
        size_t row=0;while(row<current->source.catalog.choices.size() && current->source.catalog.choices[row].token!=token)++row;
        if(row==current->source.catalog.choices.size())return {};
        const auto fresh=read(df::building::find(depot));
        if(!fresh || fresh->fingerprint!=current->source.fingerprint || fresh->indices!=current->source.indices){reset();return {};}
        const auto index=current->source.indices[row];reset();return index;
    }
};
inline TradeCatalogOwner& tradeDiagnosticCatalog(){static TradeCatalogOwner value;return value;}
}
