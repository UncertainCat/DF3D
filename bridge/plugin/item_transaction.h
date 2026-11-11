#pragma once
#include "building_item_transaction.h"

namespace df3d_production {
struct ItemLocationLink { int32_t id=-1,type=-1;std::string name; };
struct ItemCarrier { int32_t kind=0,id=-1,itemType=-1;std::string name;std::optional<ItemInspectionAppearance> appearance; };
struct ItemOwner { int32_t id=-1;std::string name; };
struct ItemAmmunitionAssignment {int8_t kind=0;int32_t squadId=-1;std::string caption;};
struct ItemSheetContent {
    int32_t kind=0,id=-1; // 1 item, 2 unit
    std::string caption;
    std::optional<ItemFacts> item;
    std::optional<ItemInspectionAppearance> appearance;
};
struct ItemUseRow {std::string caption;int32_t reaction=-1;};
struct ItemObservation {
    std::optional<std::vector<ItemUseRow>> uses;
    std::optional<std::vector<ItemSheetContent>> contents;
    std::optional<ItemAmmunitionAssignment> ammunitionAssignment;
    std::optional<ItemOwner> owner;
    ItemFacts item;
    std::string weight,description;
    std::optional<ItemLocationLink> buildingHolder,stockpile;
    int32_t stockpileCategories=-1;
    std::optional<ItemCarrier> carrier;
    std::optional<ItemInspectionAppearance> appearance;
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
    byte(value.ammunitionAssignment.has_value());if(value.ammunitionAssignment){const auto& a=*value.ammunitionAssignment;byte(a.kind);number(a.squadId);text(a.caption);}
    number(item.id);number(item.itemType);number(item.flags);byte(item.countdown);byte(item.delay);
    byte(value.owner.has_value());if(value.owner){number(value.owner->id);text(value.owner->name);}
    text(item.caption);text(item.materialToken);text(item.subtypeRaw);text(value.weight);text(value.description);
    byte(item.forbid);byte(item.dump);byte(item.melt);byte(item.hidden);byte(item.canDump);byte(item.canMelt);
    number(item.jobs.size());for(const auto& job:item.jobs){number(job.id);number(job.type);number(job.flags);}
    for(const auto* link:{&value.buildingHolder,&value.stockpile}) {
        byte(link->has_value());if(*link){number((*link)->id);number((*link)->type);text((*link)->name);}
    }
    number(value.stockpileCategories);
    byte(value.carrier.has_value());if(value.carrier){const auto& c=*value.carrier;number(c.kind);number(c.id);number(c.itemType);text(c.name);byte(c.appearance.has_value());if(c.appearance){const auto& a=*c.appearance;text(a.materialToken);text(a.subtypeRaw);text(a.colorToken);number(a.stack);byte(a.flags);byte(a.instrumentFamily);byte(a.instrumentPlaced);byte(a.floodgateOpen);byte(a.doorOpen);byte(a.doorForbidden);byte(a.doorWear);byte(a.bucketLiquid);text(a.bucketLiquidColor);byte(a.cageMaterialFamily);byte(a.cageOccupantEntity);number(a.cageOccupantId);text(a.cageSolidColor);byte(a.restraintRope);text(a.restraintSolidColor);byte(a.slabEngraving);hashItemRecipe(a.portrait,number,text);hashItemRecipe(a.cageOccupant,number,text);hashItemRecipe(a.corpseSelector,number,text);hashItemRecipe(a.legwearSelector,number,text);byte(a.craftSoftMaterial);byte(a.artifactMood);byte(a.coffinUnused);byte(a.craftGemColor.has_value());if(a.craftGemColor)text(*a.craftGemColor);byte(a.contents.has_value());if(a.contents){byte(a.contents->container);byte(a.contents->materialInorganic);text(a.contents->solidColor);number(a.contents->entries.size());for(const auto& e:a.contents->entries){number(e.itemType);text(e.materialToken);text(e.colorToken);byte(e.effectiveArmorLevel);byte(e.metal);byte(e.coal);byte(e.containsPowder);byte(e.rollsSheets);byte(e.protectsFoldedSheets);byte(e.containsWriting);byte(e.liquid);byte(e.subterraneanPlant);}}}}
    byte(value.appearance.has_value());if(value.appearance){const auto& a=*value.appearance;text(a.materialToken);text(a.subtypeRaw);text(a.colorToken);number(a.stack);byte(a.flags);byte(a.instrumentFamily);byte(a.instrumentPlaced);byte(a.floodgateOpen);byte(a.doorOpen);byte(a.doorForbidden);byte(a.doorWear);byte(a.bucketLiquid);text(a.bucketLiquidColor);byte(a.cageMaterialFamily);byte(a.cageOccupantEntity);number(a.cageOccupantId);text(a.cageSolidColor);byte(a.restraintRope);text(a.restraintSolidColor);byte(a.slabEngraving);hashItemRecipe(a.portrait,number,text);hashItemRecipe(a.cageOccupant,number,text);hashItemRecipe(a.corpseSelector,number,text);hashItemRecipe(a.legwearSelector,number,text);byte(a.craftSoftMaterial);byte(a.artifactMood);byte(a.coffinUnused);byte(a.craftGemColor.has_value());if(a.craftGemColor)text(*a.craftGemColor);byte(a.contents.has_value());if(a.contents){byte(a.contents->container);byte(a.contents->materialInorganic);text(a.contents->solidColor);number(a.contents->entries.size());for(const auto& e:a.contents->entries){number(e.itemType);text(e.materialToken);text(e.colorToken);byte(e.effectiveArmorLevel);byte(e.metal);byte(e.coal);byte(e.containsPowder);byte(e.rollsSheets);byte(e.protectsFoldedSheets);byte(e.containsWriting);byte(e.liquid);byte(e.subterraneanPlant);}}}
    byte(value.uses.has_value());if(value.uses){number(value.uses->size());for(const auto& row:*value.uses){text(row.caption);number(row.reaction);}}
    byte(value.contents.has_value());
    if(value.contents){number(value.contents->size());for(const auto& row:*value.contents){
        number(row.kind);number(row.id);text(row.caption);
        if(row.item){ItemObservation child;child.item=*row.item;child.appearance=row.appearance;number(itemObservationRevision(child));}
    }}
    return (hash&INT64_MAX)?(hash&INT64_MAX):1;
}
inline bool validItemObservation(const ItemObservation& value) {
    const auto& item=value.item;
    if(value.uses){if(value.uses->size()>4096)return false;for(const auto& row:*value.uses)if(row.caption.size()>16384 || row.reaction< -1)return false;}
    if(value.contents){
        if(value.contents->size()>4096)return false;
        for(const auto& row:*value.contents){
            if(row.id<0 || row.caption.size()>128*1024 || (row.kind!=1&&row.kind!=2) || (row.kind==1)!=row.item.has_value() || (row.kind==1)!=row.appearance.has_value())return false;
            if(row.item){ItemObservation child;child.item=*row.item;child.appearance=row.appearance;child.revision=itemObservationRevision(child);
                if(row.id!=child.item.id || row.caption!=child.item.caption || !validItemObservation(child))return false;}
        }
    }
    if(value.ammunitionAssignment){const auto& a=*value.ammunitionAssignment;if(item.itemType!=39 || a.kind<0 || a.kind>2 || (a.kind==2?a.squadId<0:a.squadId!=-1) || a.caption.size()>1024 || (a.kind==0)!=a.caption.empty())return false;}
    if(value.owner && (value.owner->id<0 || value.owner->name.size()>512))return false;
    if(value.carrier){const auto& c=*value.carrier;if(value.buildingHolder || c.id<0 || c.name.size()>512 || (c.kind!=1&&c.kind!=2) || (c.kind==1?(c.itemType<0||c.itemType>92):c.itemType!=-1))return false;}
    if(value.carrier){const auto& c=*value.carrier;if((c.kind==1)!=c.appearance.has_value())return false;if(c.appearance){const auto& a=*c.appearance;if(!validInspectionInstrument(a,c.itemType)||a.materialToken.empty()||a.materialToken.size()>256||a.subtypeRaw.size()>128||a.colorToken.size()>128||a.stack<1||(a.flags&~96))return false;}}
    if((item.itemType==30||item.itemType==13) && !value.appearance)return false;
    if(value.appearance){const auto& a=*value.appearance;if(!validInspectionInstrument(a,item.itemType)||a.materialToken.empty()||a.materialToken.size()>256||a.subtypeRaw.size()>128||a.colorToken.size()>128||a.stack<1||(a.flags&~96)||a.materialToken!=item.materialToken||a.subtypeRaw!=item.subtypeRaw)return false;}
    if(value.stockpile ? (value.stockpileCategories<0 || value.stockpileCategories>0x1ffff) : value.stockpileCategories!=-1)return false;
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
    BuildingItemAction action,bool desired,Apply apply,Observe observe,int32_t contentsItemId=-1) {
    FarmEditResult<ItemObservation> result;
    const auto target=[&](const ItemObservation& value)->const ItemFacts* {
        if(contentsItemId==-1)return &value.item;
        if(contentsItemId<0 || contentsItemId==value.item.id || !value.contents)return nullptr;
        for(const auto& row:*value.contents)if(row.kind==1 && row.id==contentsItemId && row.item)return &*row.item;
        return nullptr;
    };
    try {
        if(!expected||!validItemObservation(before))return result;
        if(before.revision!=expected){result.outcome=FarmEditOutcome::Stale;return result;}
        const auto* selected=target(before);if(!selected)return result;
        switch(action) {
        case BuildingItemAction::Dump:if(!selected->canDump)return result;break;
        case BuildingItemAction::Melt:if(!selected->canMelt)return result;break;
        case BuildingItemAction::Forbid:case BuildingItemAction::Hidden:break;
        default:return result;
        }
        if(buildingItemValue(*selected,action)==desired) {
            result.receipt=before;result.outcome=FarmEditOutcome::Completed;return result;
        }
    }catch(...){return result;}
    result.mutated=true;result.outcome=FarmEditOutcome::Unknown;
    try {
        if(!apply()){result.mutated=false;result.outcome=FarmEditOutcome::Rejected;return result;}
        auto after=observe();
        if(!after||!validItemObservation(*after)||after->item.id!=before.item.id||
           !target(*after)||buildingItemValue(*target(*after),action)!=desired)return result;
        result.receipt=std::move(after);result.outcome=FarmEditOutcome::Completed;
    }catch(...){result.receipt.reset();}
    return result;
}
}
