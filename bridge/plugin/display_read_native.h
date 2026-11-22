#pragma once
#include "display_picker_native.h"

namespace df3d_production {
struct DisplayItemDetail : ItemFacts {
    std::optional<ItemInspectionAppearance> appearance;
};
struct DisplayRead {
    DisplayAssignments assignments;
    uint64_t inventoryRevision=0;
    std::vector<DisplayBodyRow> body;
    std::optional<DisplayPicker> picker;
    std::vector<DisplayItemDetail> items;
};
// Bind local picker intent to current semantic item identity/eligibility. Do not
// retain native pointers or count lazy rendering caches as source changes.
inline std::optional<uint64_t> displayInventoryRevision(const DisplayAssignments& assignments,
                                                       const std::vector<int32_t>& ids) {
    if(ids.size()>1048576)return {};
    uint64_t hash=UINT64_C(14695981039346656037);
    const auto add=[&](uint64_t value){for(int i=0;i<8;++i){hash^=uint8_t(value);hash*=UINT64_C(1099511628211);value>>=8;}};
    add(assignments.revision);add(ids.size());
    for(auto id:ids) {
        auto* item=df::item::find(id);if(!item || item->general_refs.size()>4096)return {};
        add(id);auto flags=item->flags;flags.bits.weight_computed=false;
        add(flags.whole);add(item->flags2.whole);add(item->getType());add(item->getSubtype());
        add(item->getMaterial());add(item->getMaterialIndex());add(item->getStackSize());
        add(item->pos.x);add(item->pos.y);add(item->pos.z);add(item->general_refs.size());
        for(auto* ref:item->general_refs){if(!ref)return {};add(int(ref->getType()));add(ref->getID());}
    }
    return (hash&INT64_MAX)|1;
}
inline bool displayTargetVisible(df::building* building) {
    if(!building)return false;
    auto* tile=DFHack::Maps::getTileDesignation(building->centerx,building->centery,building->z);
    return tile && !tile->bits.hidden;
}
// category -1 is the parent sheet; -2 opens the first native picker category.
// Item detail requests are bounded visible-page
// IDs, with parent membership or picker category membership checked at read time.
inline std::optional<DisplayRead> readDisplay(df::building* building,int16_t category,
                                            const std::string& query,const std::vector<int32_t>& ids) {
    if(!displayTargetVisible(building) || category<-2 || category>=93 || query.size()>1024 || ids.size()>64 || (category<0 && !query.empty()))return {};
    const auto assignments=displayAssignments(building);const auto body=displayBody(building);
    if(!assignments || !body)return {};
    DisplayRead result;result.assignments=*assignments;result.body=*body;
    if(category!=-1) {
        if(assignments->removing)return {};
        const auto inventory=displayInventory(building);if(!inventory)return {};
        const auto revision=displayInventoryRevision(*assignments,*inventory);if(!revision)return {};
        result.inventoryRevision=*revision;
        result.picker=displayPicker(building,category==-2?-1:category,query);if(!result.picker)return {};
    }
    const auto& eligible=result.picker?result.picker->items:assignments->items;
    std::vector<int32_t> seen;seen.reserve(ids.size());
    for(auto id:ids) {
        if(std::find(seen.begin(),seen.end(),id)!=seen.end() || std::find(eligible.begin(),eligible.end(),id)==eligible.end())return {};
        seen.push_back(id);auto* item=df::item::find(id);const auto facts=itemFacts(item);if(!facts)return {};
        DisplayItemDetail row;static_cast<ItemFacts&>(row)=*facts;
        row.appearance=itemAppearance(item);result.items.push_back(std::move(row));
    }
    return result;
}
// The viewer owns draft selection. Epoch, connection and explicit-action guards
// are enforced by the enclosing management caller. Rejected/stale preflight never
// changes the world; uncertainty after effects is inherited from the native edit.
inline DisplayEdit commitDisplayDraft(df::building* building,uint64_t expectedInventory,
                                     const std::vector<int32_t>& ids) {
    DisplayEdit result;
    if(!displayTargetVisible(building) || !expectedInventory || expectedInventory>INT64_MAX)return result;
    const auto assignments=displayAssignments(building);const auto inventory=displayInventory(building);
    if(!assignments || !inventory || assignments->removing)return result;
    const auto revision=displayInventoryRevision(*assignments,*inventory);if(!revision)return result;
    if(*revision!=expectedInventory){result.outcome=DisplayOutcome::Stale;return result;}
    return editDisplayAssignments(building,assignments->revision,ids,true);
}
inline DisplayEdit removeDisplayItem(df::building* building,uint64_t expectedAssignments,int32_t item) {
    if(!displayTargetVisible(building))return {};
    return editDisplayAssignments(building,expectedAssignments,{item},false);
}
}
