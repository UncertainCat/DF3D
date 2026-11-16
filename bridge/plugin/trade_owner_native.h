#pragma once
#include "trade_catalog_native.h"
#include "trade_session_native.h"
#include "trade_appraisal_native.h"

namespace df3d_production {
enum class TradeOpenStatus {Available,Rejected,Unknown};
struct TradeOpenResult {
    TradeOpenStatus status=TradeOpenStatus::Rejected;
    std::optional<TradeEntryFacts> entry;
    std::optional<TradeAppraisalEffect> appraisal;
    TradeSessionRead selection;
};
// One connection owns this object. All calls run at a DF safe point; the caller
// retires it on connection/world replacement and excludes saving. Only the
// explicit open appraises goods; explicit exchange negotiates or transfers them.
class TradeOwner {
    TradeCatalogOwner catalog;
    TradeSelectionSession selection;
public:
    void reset(){catalog.reset();selection.reset();}
    std::optional<TradeCaravanCatalog> refresh(uint64_t epoch,df::building* depot) {
        selection.reset();return catalog.refresh(epoch,depot);
    }
    TradeOpenResult open(uint64_t epoch,int32_t depot,uint64_t token) {
        TradeOpenResult result;bool effectsStarted=false;
        try {
            const auto index=catalog.take(epoch,depot,token);
            if(!index)return result;
            selection.reset();
            auto* building=df::building::find(depot);
            result.appraisal=tradeAppraise(building,*index,&effectsStarted);
            if(!result.appraisal)return result;
            // Appraisal changes caravan.goods and can change the trader's
            // profession. Bind the session and captions AFTER those effects.
            result.entry=tradeEntryFacts(building,*index);
            if(result.entry)result.selection=selection.open(epoch,building,*index);
            if(result.entry && result.selection.status==TradeSessionStatus::Available){result.status=TradeOpenStatus::Available;return result;}
        }catch(...){/* A post-effect failure must never become a retryable rejection. */}
        selection.reset();result.entry.reset();result.selection={};
        result.status=effectsStarted?TradeOpenStatus::Unknown:TradeOpenStatus::Rejected;
        return result;
    }
    TradeSessionRead access(uint64_t epoch,uint64_t session,uint64_t revision,const TradeSelectionIntent* intent=nullptr) {
        return selection.access(epoch,session,revision,intent);
    }
    TradeSessionDisplay displayRead(uint64_t epoch,uint64_t session,uint64_t revision,int32_t side,size_t offset,size_t limit) {
        return selection.displayRead(epoch,session,revision,side,offset,limit);
    }
    TradeExchangeResult exchange(uint64_t epoch,uint64_t session,uint64_t revision){return selection.exchange(epoch,session,revision);}
    TradeExchangeResult gift(uint64_t epoch,uint64_t session,uint64_t revision){return selection.gift(epoch,session,revision);}
    std::optional<TradeCounterPage> counterPage(uint64_t epoch,uint64_t session,uint64_t revision,size_t offset,size_t limit){
        return selection.counterPage(epoch,session,revision,offset,limit);
    }
    TradeSessionRead dismissCounteroffer(uint64_t epoch,uint64_t session,uint64_t revision){return selection.dismissCounteroffer(epoch,session,revision);}
    TradeSessionRead close(uint64_t session){return selection.close(session);}
    TradeSessionSummary summary(uint64_t epoch,uint64_t session,uint64_t revision,uint16_t columns=102) {
        return selection.summary(epoch,session,revision,columns);
    }
    std::optional<TradeDisplayPage> display(uint64_t epoch,uint64_t session,uint64_t revision,int32_t side,size_t offset,size_t limit) {
        return selection.display(epoch,session,revision,side,offset,limit);
    }
};
inline TradeOwner& tradeDiagnosticOwner(){static TradeOwner value;return value;}
}
