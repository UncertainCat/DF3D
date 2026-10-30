#pragma once
#include "building_item_transaction.h"

namespace df3d_production {
struct ItemLocationLink { int32_t id=-1,type=-1;std::string name; };
struct ItemObservation {
    ItemFacts item;
    std::string weight,description;
    std::optional<ItemLocationLink> buildingHolder,stockpile;
    uint64_t revision=0;
};
// Item authority never depends on the former containing building or its rows.
// Coordinates belong to follow, not edit authority. Semantic location links do.
inline uint64_t itemObservationRevision(const ItemObservation& value) {
    uint64_t hash=UINT64_C(14695981039346656037);
    const auto byte=[&](uint8_t n){hash^=n;hash*=UINT64_C(1099511628211);};
    const auto number=[&](uint64_t n){for(int i=0;i<8;++i){byte(uint8_t(n));n>>=8;}};
    const auto text=[&](const std::string& s){number(s.size());for(unsigned char c:s)byte(c);};
    const auto& item=value.item;
    number(item.id);number(item.itemType);number(item.flags);byte(item.countdown);byte(item.delay);
    text(item.caption);text(item.materialToken);text(item.subtypeRaw);text(value.weight);text(value.description);
    byte(item.forbid);byte(item.dump);byte(item.melt);byte(item.hidden);byte(item.canDump);byte(item.canMelt);
    number(item.jobs.size());for(const auto& job:item.jobs){number(job.id);number(job.type);number(job.flags);}
    for(const auto* link:{&value.buildingHolder,&value.stockpile}) {
        byte(link->has_value());if(*link){number((*link)->id);number((*link)->type);text((*link)->name);}
    }
    return (hash&INT64_MAX)?(hash&INT64_MAX):1;
}
inline bool validItemObservation(const ItemObservation& value) {
    const auto& item=value.item;
    if(item.id<0||item.itemType<0||item.itemType>92||item.caption.size()>128*1024||
       item.materialToken.size()>256||item.subtypeRaw.size()>128||value.weight.size()>128||
       value.description.size()>32*1024||!value.revision||value.revision!=itemObservationRevision(value))return false;
    for(const auto& job:item.jobs)if(job.id<0||job.type<0)return false;
    for(const auto* link:{&value.buildingHolder,&value.stockpile})
        if(*link&&((*link)->id<0||(*link)->type<0||(*link)->name.size()>512))return false;
    return true;
}
template<class Apply,class Observe>
FarmEditResult<ItemObservation> finishItemEdit(const ItemObservation& before,uint64_t expected,
    BuildingItemAction action,bool desired,Apply apply,Observe observe) {
    FarmEditResult<ItemObservation> result;
    try {
        if(!expected||!validItemObservation(before))return result;
        if(before.revision!=expected){result.outcome=FarmEditOutcome::Stale;return result;}
        switch(action) {
        case BuildingItemAction::Dump:if(!before.item.canDump)return result;break;
        case BuildingItemAction::Melt:if(!before.item.canMelt)return result;break;
        case BuildingItemAction::Forbid:case BuildingItemAction::Hidden:break;
        default:return result;
        }
        if(buildingItemValue(before.item,action)==desired) {
            result.receipt=before;result.outcome=FarmEditOutcome::Completed;return result;
        }
    }catch(...){return result;}
    result.mutated=true;result.outcome=FarmEditOutcome::Unknown;
    try {
        if(!apply()){result.mutated=false;result.outcome=FarmEditOutcome::Rejected;return result;}
        auto after=observe();
        if(!after||!validItemObservation(*after)||after->item.id!=before.item.id||
           buildingItemValue(after->item,action)!=desired)return result;
        result.receipt=std::move(after);result.outcome=FarmEditOutcome::Completed;
    }catch(...){result.receipt.reset();}
    return result;
}
}
