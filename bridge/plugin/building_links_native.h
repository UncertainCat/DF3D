#pragma once
#include "tasks_artwork_native.h"
#include "df/building.h"
#include "df/building_actual.h"
#include "df/building_trapst.h"
#include "df/buildingitemst.h"
#include "df/item.h"
#include "df/general_ref.h"
#include "df/general_ref_type.h"
#include "modules/Maps.h"
#include <windows.h>
#include <cstdint>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace df3d_production {
struct BuildingLink {
    int32_t itemId=-1,referenceType=-1,id=-1,type=-1;
    int32_t x=-1,y=-1,z=-1;
    std::string name;
    std::optional<ItemAppearanceRecipe> appearance;
};
struct BuildingLinksSnapshot {
    int32_t buildingId=-1;
    uint64_t revision=0;
    bool tabs=false;
    std::vector<BuildingLink> rows;
};
inline bool buildingLinksNativeReady() {
    static const bool ready=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x180749,0x339,UINT64_C(0xea03ece7bd271b38)},
            {0x19ba20,0x297,UINT64_C(0x8c5cbc36b2c73d9a)},
            {0x19cab9,0x33,UINT64_C(0x001955632bb638a9)},
            {0x1b0278,0x2d5,UINT64_C(0xdd7f7cba91e7c125)},
        };
        for(const auto& p:pins) {
            uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<p.length;++i){h^=base[p.rva+i];h*=UINT64_C(1099511628211);}
            if(h!=p.hash)return false;
        }
        return true;
    }();
    return ready;
}
// Safe-point only. Native19ba20..19bc86 traverses item references directly;
// no menu collection, sorting or deduplication participates. getName writes
// into caller-owned storage. Coordinates support viewer-owned recentering.
inline std::optional<BuildingLinksSnapshot> buildingLinks(df::building* building) {
    if(!buildingLinksNativeReady() || !building)return {};
    auto* actual=virtual_cast<df::building_actual>(building);
    auto* tile=DFHack::Maps::getTileDesignation(building->centerx,building->centery,building->z);
    if(!actual || !tile || tile->bits.hidden || actual->contained_items.size()>32767)return {};
    BuildingLinksSnapshot result;result.buildingId=building->id;
    if(auto* trap=virtual_cast<df::building_trapst>(building))
        result.tabs=int(trap->trap_type)==0 || int(trap->trap_type)==1;
    uint64_t hash=UINT64_C(14695981039346656037);
    const auto number=[&](uint64_t n){for(int i=0;i<8;++i){hash^=uint8_t(n);hash*=UINT64_C(1099511628211);n>>=8;}};
    number(result.buildingId);number(int(building->getType()));
    for(const auto* held:actual->contained_items) {
        if(!held || !held->item || held->item->general_refs.size()>32767)return {};
        for(auto* ref:held->item->general_refs) {
            if(!ref)return {};
            const auto kind=ref->getType();
            if(kind!=df::general_ref_type::BUILDING_TRIGGER && kind!=df::general_ref_type::BUILDING_TRIGGERTARGET)continue;
            auto* target=ref->getBuilding();
            if(!target)continue;
            if(result.rows.size()>=32767)return {};
            BuildingLink row;row.itemId=held->item->id;row.referenceType=int(kind);
            row.id=target->id;row.type=int(target->getType());
            row.x=target->centerx;row.y=target->centery;row.z=target->z;
            target->getName(&row.name);
            row.appearance=df3d_tasks::linkedBuildingArtwork(target);
            if(row.name.size()>512)return {};
            for(int32_t n:{row.itemId,row.referenceType,row.id,row.type,row.x,row.y,row.z})number(n);
            number(row.name.size());for(unsigned char c:row.name){hash^=c;hash*=UINT64_C(1099511628211);}
            number(bool(row.appearance));
            if(row.appearance) {
                const auto strings=[&](const auto& values){number(values.size());for(const auto& value:values){number(value.size());for(unsigned char c:value){hash^=c;hash*=UINT64_C(1099511628211);}}};
                strings(row.appearance->pages);strings(row.appearance->palettes);number(row.appearance->layers.size());
                for(const auto& layer:row.appearance->layers)for(auto value:layer)number(value);
            }
            result.rows.push_back(std::move(row));
        }
    }
    result.tabs|=!result.rows.empty();number(result.tabs);number(result.rows.size());
    result.revision=(hash&INT64_MAX)?(hash&INT64_MAX):1;
    return result;
}
}
