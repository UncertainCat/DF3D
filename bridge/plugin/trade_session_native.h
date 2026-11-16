#pragma once
#include "trade_projection_native.h"
#include "trade_display_native.h"
#include "trade_value_totals_native.h"
#include "trade_capacity_native.h"
#include "trade_dialogue_native.h"
#include "trade_header_native.h"
#include "trade_negotiation_native.h"
#include <limits>
#include <stdexcept>

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
    std::optional<TradeConversation> conversation;
};
enum class TradeExchangeStatus {Available,Rejected,Retired,Unknown};
struct TradeExchangeResult {TradeExchangeStatus status=TradeExchangeStatus::Rejected;TradeSessionRead selection;};
struct TradeSessionDisplay {TradeSessionStatus status=TradeSessionStatus::Rejected;uint64_t session=0,revision=0;std::string query;std::optional<TradeDisplayPage> page;};
struct TradeSessionSummary {
    TradeSessionStatus status=TradeSessionStatus::Rejected;
    uint64_t session=0,revision=0;
    std::optional<TradeEntryFacts> entry;
    std::optional<TradeValueTotals> values;
    std::optional<TradeCapacity> capacity;
    std::optional<TradeHeader> header;
    std::vector<std::string> dialogueLines;
    uint16_t columns=0;
};
class TradeSelectionSession {
    struct Binding {
        uint64_t session=0,revision=1,epoch=0,source=0;
        int32_t depot=-1;size_t caravan=0;
        TradeDraftCheckpoint draft;
        std::optional<TradeConversation> conversation;
    };
    std::optional<Binding> current;
    uint64_t serial=0;
    TradeSessionRead reply(TradeSessionStatus status) const {
        TradeSessionRead result;result.status=status;
        if(current){result.session=current->session;result.revision=current->revision;
            if(status==TradeSessionStatus::Available){result.draft=current->draft;result.conversation=current->conversation;}}
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
    TradeSessionSummary summary(uint64_t epoch,uint64_t session,uint64_t revision,uint16_t columns=102) {
        TradeSessionSummary result;
        if(columns<1 || columns>512)return result;
        const auto read=access(epoch,session,revision);result.status=read.status;
        if(read.status!=TradeSessionStatus::Available || !read.draft || !current)return result;
        auto* building=df::building::find(current->depot);
        auto entry=tradeEntryFacts(building,current->caravan);
        auto values=tradeValueTotals(building,current->caravan,read.draft->sides);
        auto capacity=tradeCapacity(building,current->caravan,read.draft->sides);
        if(!entry || !values || !capacity){result.status=TradeSessionStatus::Rejected;return result;}
        if(current->conversation)entry->dialogue=current->conversation->dialogue;
        auto header=tradeHeader(building,current->caravan,entry->dialogue);
        const auto lines=header?tradeDialogueLines(header->dialogue,columns):std::nullopt;
        if(!header || !lines){result.status=TradeSessionStatus::Rejected;return result;}
        result.session=read.session;result.revision=read.revision;
        result.entry=std::move(entry);result.values=std::move(values);result.capacity=std::move(capacity);
        result.header=std::move(header);result.dialogueLines=*lines;result.columns=columns;
        return result;
    }
    std::optional<TradeDisplayPage> display(uint64_t epoch,uint64_t session,uint64_t revision,int32_t side,size_t offset,size_t limit) {
        return displayRead(epoch,session,revision,side,offset,limit).page;
    }
    TradeSessionDisplay displayRead(uint64_t epoch,uint64_t session,uint64_t revision,int32_t side,size_t offset,size_t limit) {
        TradeSessionDisplay result;
        if(side<0 || side>1 || !limit || limit>64)return result;
        const auto read=access(epoch,session,revision);
        result.status=read.status;
        if(read.status!=TradeSessionStatus::Available || !read.draft || !current)return result;
        result.page=tradeDisplayPage(df::building::find(current->depot),current->caravan,read.draft->sides[side],offset,limit,side);
        if(!result.page){result.status=TradeSessionStatus::Rejected;return result;}
        result.session=read.session;result.revision=read.revision;result.query=read.draft->filters[side];return result;
    }
    // Explicit semantic Trade/Accept Counteroffer action. The same revision
    // cannot execute twice. Post-effect failures retire ownership as Unknown;
    // never rebuild a retryable request from an uncertain outcome.
    TradeExchangeResult exchange(uint64_t epoch,uint64_t session,uint64_t revision){
        TradeExchangeResult result;bool started=false;
        try{
            const auto read=access(epoch,session,revision);
            if(read.status==TradeSessionStatus::Retired){result.status=TradeExchangeStatus::Retired;return result;}
            if(read.status!=TradeSessionStatus::Available || !current || current->revision==uint64_t(INT64_MAX))return result;
            auto* building=df::building::find(current->depot);
            TradeNegotiationNative context(building,current->caravan,current->draft);
            if(!context || (current->conversation && !context.restore({current->draft,*current->conversation})))return result;
            const auto check=context.checkOffer();if(check.disposition==TradeOfferDisposition::Unavailable)return result;
            if(check.disposition==TradeOfferDisposition::Refused)context.refuseOffer(&started);
            else if(!context.negotiate(&started))return result;
            auto outcome=context.checkpoint();if(!outcome)throw std::runtime_error("Trade outcome unavailable");
            TradeDraftNative fresh(building,current->caravan);
            const auto initial=fresh.checkpoint();
            const auto source=initial?tradeSelectionSource(building,current->caravan,*initial):std::nullopt;
            if(!source)throw std::runtime_error("Trade source unavailable");
            if(context.goodsNeedRebuild()){
                // Renderer385007..3855ef resets selections/groups, retaining
                // each search string and projecting it over the new goods.
                for(int side=0;side<2;++side)if(!fresh.setFilter(side,outcome->draft.filters[side]))throw std::runtime_error("Trade filter unavailable");
                const auto rebuilt=fresh.checkpoint();if(!rebuilt)throw std::runtime_error("Trade goods unavailable");
                outcome->draft=*rebuilt;
            }
            TradeNegotiationNative verified(building,current->caravan,outcome->draft);
            if(!verified.restore(*outcome))throw std::runtime_error("Trade conversation unavailable");
            auto next=*current;next.source=*source;next.draft=std::move(outcome->draft);next.conversation=std::move(outcome->conversation);++next.revision;
            current=std::move(next);result.selection=reply(TradeSessionStatus::Available);result.status=TradeExchangeStatus::Available;return result;
        }catch(...){
            if(started){reset();result.status=TradeExchangeStatus::Unknown;}
            return result;
        }
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
            if(current->revision==uint64_t(INT64_MAX))return reply(TradeSessionStatus::Rejected);
            if(current->conversation){
                TradeNegotiationNative context(building,current->caravan,current->draft);
                if(!context.restore({current->draft,*current->conversation}) || !context.apply(*intent))return reply(TradeSessionStatus::Rejected);
                auto updated=context.checkpoint();if(!updated)return reply(TradeSessionStatus::Rejected);
                current->draft=std::move(updated->draft);current->conversation=std::move(updated->conversation);
            }else{
                if(!native.apply(*intent))return reply(TradeSessionStatus::Rejected);
                const auto updated=native.checkpoint();if(!updated)return reply(TradeSessionStatus::Rejected);
                current->draft=*updated;
            }
            ++current->revision;
        }
        return reply(TradeSessionStatus::Available);
    }
};
// Separate from public management transport until catalog/session lifecycle and
// negotiation ownership are integrated. Reset at native map/world teardown.
inline TradeSelectionSession& tradeDiagnosticSession(){static TradeSelectionSession value;return value;}
}
