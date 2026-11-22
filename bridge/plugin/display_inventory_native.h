#pragma once
#include "stocks_native.h"
#include "df/building_display_furniturest.h"
#include "df/building_actual.h"
#include "df/buildingitemst.h"
#include "df/general_ref.h"
#include "df/itemlistst.h"

namespace df3d_production {
// Native367710 combines this inventory with global menu initialization. Extract
// only the pinned eligibility block and invoke its semantic dependencies. The
// supplied list owns its storage; item.base_uniform_score is never scratch.
inline std::optional<std::vector<int32_t>> displayInventory(df::building* building) {
    auto* display=virtual_cast<df::building_display_furniturest>(building);
    if(!display || display->getBuildStage()!=display->getMaxBuildStage() ||
       display->displayed_items.size()>1048576 || !df3d_room::valuationReady())return {};
    const auto inventory=df3d_stocks::inventory();if(!inventory)return {};
    const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    static const bool ready=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x369290,0x188,UINT64_C(0xcd446c869b296eb4)},
            {0xac9b20,0x104,UINT64_C(0x85a87c4052172340)},
            {0xac94a0,0x267,UINT64_C(0x9ffb5171a7177c99)},
            {0xaca720,0x7a,UINT64_C(0x12b032d63e998c99)}};
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=*reinterpret_cast<const uint8_t*>(base+pin.rva+i);hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();
    if(!ready)return {};
    df::itemlistst ordered;
    for(auto id:*inventory) {
        auto* item=df::item::find(id);
        const auto available=df3d_stocks::inventoryAvailable(item);if(!available)return {};
        if(!*available || (item->flags.whole&0x10000))continue;
        if(item->general_refs.size()>4096)return {};
        bool constructionPart=false;
        if(item->flags.bits.in_building) {
            for(auto* ref:item->general_refs) {
                if(!ref)return {};
                if(int(ref->getType())!=36)continue;
                auto* holder=ref->getBuilding();
                if(holder && holder->isActual()) {
                    auto* actual=static_cast<df::building_actual*>(holder);
                    if(actual->contained_items.size()>1048576)return {};
                    for(auto* contained:actual->contained_items) {
                        if(!contained)return {};
                        if(contained->item==item && int(contained->use_mode)==2){constructionPart=true;break;}
                    }
                }
                break;
            }
        }
        if(constructionPart || std::find(display->displayed_items.begin(),display->displayed_items.end(),id)!=display->displayed_items.end())continue;
        reinterpret_cast<void(*)(df::itemlistst*,df::item*)>(base+0xac9b20)(&ordered,item);
    }
    std::vector<int32_t> result;result.reserve(ordered.l_item.size());
    for(auto* item:ordered.l_item)result.push_back(item->id);
    return result;
}
}
