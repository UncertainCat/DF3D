#pragma once
#include "trade_projection_native.h"
#include "trade_display_native.h"
#include <limits>

namespace df3d_production {
// Selection-session source only, not exchange authorization. Pointer identities
// are hashed locally from freshly resolved objects, never retained/dereferenced
// later or exposed as object addresses. Public caravan selection still needs an
// opaque catalog identity; the positional selector below is diagnostic-only.
inline std::optional<uint64_t> tradeSelectionSource(df::building* building,size_t caravanIndex,
    const TradeDraftCheckpoint& initial) {
    const auto entry=tradeEntryFacts(building,caravanIndex);if(!entry)return {};
    uint64_t hash=UINT64_C(14695981039346656037);
    const auto add=[&](uint64_t value){for(unsigned i=0;i<8;++i){hash^=uint8_t(value>>(8*i));hash*=UINT64_C(1099511628211);}};
    const auto& caravans=df::global::plotinfo->caravans;
    add(caravans.size());for(const auto* caravan:caravans)add(reinterpret_cast<uintptr_t>(caravan));
    add(caravanIndex);add(building->id);add(entry->entity);add(entry->fortressTrader);add(entry->merchantTrader);
    add(entry->unloading);add(entry->hasSpeaker);
    const auto* caravan=caravans[caravanIndex];add(caravan->flags.whole);add(int(caravan->trade_state));
    add(caravan->goods.size());for(auto id:caravan->goods)add(id);
    const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    for(const auto& side:initial.sides) {
        add(side.items.size());
        for(size_t i=0;i<side.items.size();++i) {
            auto* item=df::item::find(side.items[i]);if(!item)return {};
            auto flags=item->flags;flags.bits.weight_computed=false;
            add(item->id);add(reinterpret_cast<uintptr_t>(item));add(flags.whole);add(item->getStackSize());
            add(int(item->getType()));add(item->getSubtype());add(side.flags[i]&2);
            std::string caption;
            reinterpret_cast<void(*)(df::item*,std::string*,bool,int32_t)>(base+0xc65450)(item,&caption,false,-1);
            add(caption.size());for(unsigned char ch:caption)add(ch);
        }
        add(side.groups.size());for(const auto& group:side.groups){add(group.type);add(group.subtype);}
    }
    return hash?hash:1;
}
enum class TradeSessionStatus {Available,Rejected,Retired,Closed};
struct TradeSessionRead {
    TradeSessionStatus status=TradeSessionStatus::Rejected;
    uint64_t session=0,revision=0;
    std::optional<TradeDraftCheckpoint> draft;
};
class TradeSelectionSession {
    struct Binding {
        uint64_t session=0,revision=1,epoch=0,source=0;
        int32_t depot=-1;size_t caravan=0;
        TradeDraftCheckpoint draft;
    };
    std::optional<Binding> current;
    uint64_t serial=0;
    TradeSessionRead reply(TradeSessionStatus status) const {
        TradeSessionRead result;result.status=status;
        if(current){result.session=current->session;result.revision=current->revision;
            if(status==TradeSessionStatus::Available)result.draft=current->draft;}
        return result;
    }
public:
    void reset(){current.reset();} // Never rewind serial: late replies/actions cannot alias a new owner.
    TradeSessionRead open(uint64_t epoch,df::building* building,size_t caravanIndex) {
        reset();if(!epoch || serial==uint64_t(INT64_MAX))return reply(TradeSessionStatus::Rejected);
        TradeDraftNative native(building,caravanIndex);const auto draft=native.checkpoint();if(!draft)return reply(TradeSessionStatus::Rejected);
        const auto source=tradeSelectionSource(building,caravanIndex,*draft);if(!source)return reply(TradeSessionStatus::Rejected);
        current=Binding{++serial,1,epoch,*source,building->id,caravanIndex,*draft};
        return reply(TradeSessionStatus::Available);
    }
    TradeSessionRead close(uint64_t session) {
        if(!current || current->session!=session)return reply(TradeSessionStatus::Rejected);
        reset();return reply(TradeSessionStatus::Closed);
    }
    std::optional<TradeDisplayPage> display(uint64_t epoch,uint64_t session,uint64_t revision,int32_t side,size_t offset,size_t limit) {
        if(side<0 || side>1 || !limit || limit>64)return {};
        const auto read=access(epoch,session,revision);
        if(read.status!=TradeSessionStatus::Available || !read.draft || !current)return {};
        return tradeDisplayPage(df::building::find(current->depot),current->caravan,read.draft->sides[side],offset,limit);
    }
    // Caller owns connection/epoch retirement and saving gates. Read validates
    // the live source but never appraises, changes simulation, or advances revision.
    TradeSessionRead access(uint64_t epoch,uint64_t session,uint64_t expectedRevision,
        const TradeSelectionIntent* intent=nullptr) {
        if(!current || current->session!=session)return reply(TradeSessionStatus::Rejected);
        if(current->epoch!=epoch){reset();return reply(TradeSessionStatus::Retired);}
        auto* building=df::building::find(current->depot);
        TradeDraftNative native(building,current->caravan);const auto fresh=native.checkpoint();
        const auto source=fresh?tradeSelectionSource(building,current->caravan,*fresh):std::nullopt;
        if(!source || *source!=current->source || !native.restore(current->draft)) {
            reset();return reply(TradeSessionStatus::Retired);
        }
        if(expectedRevision!=current->revision)return reply(TradeSessionStatus::Rejected);
        if(intent) {
            if(current->revision==uint64_t(INT64_MAX) || !native.apply(*intent))return reply(TradeSessionStatus::Rejected);
            const auto updated=native.checkpoint();if(!updated)return reply(TradeSessionStatus::Rejected);
            current->draft=*updated;++current->revision;
        }
        return reply(TradeSessionStatus::Available);
    }
};
// Separate from public management transport until catalog/session lifecycle and
// negotiation ownership are integrated. Reset at native map/world teardown.
inline TradeSelectionSession& tradeDiagnosticSession(){static TradeSelectionSession value;return value;}
}
