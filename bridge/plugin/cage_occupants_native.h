#pragma once
#include "cage_native.h"
#include "unit_description_native.h"
#include "df/buildingitemst.h"
#include "df/general_ref.h"
#include <cstring>

namespace df3d_production {
struct CageOccupant {
    int32_t id=-1;uint8_t entity=0;
    bool contained=false,assigned=false,resolved=false;
    std::string name,status;
    uint8_t statusColor=15;
};
struct CageOccupants {
    int32_t buildingId=-1;uint64_t revision=0;
    bool removing=false,justiceRestraint=false;
    std::vector<CageOccupant> rows;
};
inline bool cageOccupantsReady() {
    if(!cageCandidatesReady())return false;
    static const bool ready=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        const auto pin=[base](size_t at,size_t count,uint64_t expected) {
            uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<count;++i){h^=base[at+i];h*=UINT64_C(1099511628211);}
            return h==expected;
        };
        // Read-only evidence of native iteration/description branches. Never
        // invoke the renderer or borrow its list/scroll/selected-row storage.
        return pin(0x18c6e2,0x1f75,UINT64_C(0x4d283d2de0187a50)) &&
            pin(0x1330c30,0x688,UINT64_C(0x0e165ee31decf426)) &&
            std::strcmp(reinterpret_cast<const char*>(base+0x15ec998),"Prisoner")==0 &&
            std::strcmp(reinterpret_cast<const char*>(base+0x16014b0),"Assigned")==0 &&
            std::strcmp(reinterpret_cast<const char*>(base+0x16015d0),"Occupant")==0 &&
            std::strcmp(reinterpret_cast<const char*>(base+0x16018d0),"Unassigned occupant")==0;
    }();return ready;
}
inline std::optional<CageOccupants> observeCageOccupants(df::building* building) {
    if(!building || building->getType()!=df::building_type::Cage || !cageOccupantsReady())return {};
    auto& cage=*static_cast<df::building_cagest*>(building);
    const auto authority=observeCage(building);if(!authority)return {};
    CageOccupants result;result.buildingId=cage.id;result.removing=authority->removing;result.justiceRestraint=authority->justiceRestraint;
    std::unordered_set<int32_t> containedUnits,containedItems;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    const auto append=[&](int32_t id,bool item,bool contained)->bool {
        if(result.rows.size()>=4096)return false;
        CageOccupant row;row.id=id;row.entity=item?2:1;row.contained=contained;
        const auto& assignments=item?cage.assigned_items:cage.assigned_units;
        row.assigned=std::find(assignments.begin(),assignments.end(),id)!=assignments.end();
        if(item) {
            if(auto* subject=df::item::find(id)) {
                const auto name=df3d_area::nativeZoneAnimalItemText(*subject);if(!name)return false;
                row.name=*name;row.resolved=true;
            }
        } else if(auto* subject=df::unit::find(id)) {
            if(subject->inventory.size()>10000 || !subject->body.body_plan)return false;
            for(auto* held:subject->inventory)if(!held || !held->item)return false;
            df3d_creature::InventoryDescriptionContext owned(*subject);
            using Name=void(*)(df::unit*,std::string*,bool);
            reinterpret_cast<Name>(const_cast<uint8_t*>(base+0x1330c30))(owned.unit(),&row.name,true);
            row.resolved=true;
        }
        if(row.name.size()>2048)return false;
        const size_t text=result.justiceRestraint?0x15ec998:!contained?0x16014b0:row.assigned?0x16015d0:0x16018d0;
        row.status=reinterpret_cast<const char*>(base+text);
        row.statusColor=result.justiceRestraint?9:!contained?15:row.assigned?10:12;
        result.rows.push_back(std::move(row));return true;
    };
    // Native counts unresolved unit references as blank slots. Item references
    // require a resolved live animal. Assigned-only rows follow reference order.
    if(!cage.contained_items.empty()) {
        const auto* entry=cage.contained_items.front();if(!entry || !entry->item)return {};
        if(entry->item->general_refs.size()>10000)return {};
        for(auto* ref:entry->item->general_refs) {
            if(!ref)return {};
            if(ref->getType()==df::general_ref_type::CONTAINS_UNIT) {
                const auto id=ref->getID();containedUnits.insert(id);if(!append(id,false,true))return {};
            } else if(ref->getType()==df::general_ref_type::CONTAINS_ITEM) {
                // Deduplication in native uses every item ref, even a non-animal.
                containedItems.insert(ref->getID());
                if(auto* item=ref->getItem();item && item->isLiveAnimal())if(!append(item->id,true,true))return {};
            }
        }
    }
    for(auto id:cage.assigned_units)if(!containedUnits.count(id) && !append(id,false,false))return {};
    for(auto id:cage.assigned_items)if(!containedItems.count(id) && !append(id,true,false))return {};
    uint64_t hash=UINT64_C(14695981039346656037);
    const auto byte=[&](uint8_t n){hash^=n;hash*=UINT64_C(1099511628211);};
    const auto number=[&](uint64_t n){for(int i=0;i<8;++i){byte(uint8_t(n));n>>=8;}};
    number(authority->revision);number(result.rows.size());
    for(const auto& row:result.rows) {
        number(row.id);byte(row.entity);byte(row.contained);byte(row.assigned);byte(row.resolved);byte(row.statusColor);
        for(const auto* text:{&row.name,&row.status}){number(text->size());for(unsigned char ch:*text)byte(ch);}
    }
    result.revision=(hash&INT64_MAX)?hash&INT64_MAX:1;return result;
}
}
