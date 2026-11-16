#pragma once
#include "unit_description_native.h"
#include "building_item_native.h"
#include "zone_native.h"
#include "building_room_native.h"
#include "df/building_actual.h"
#include "df/building_civzonest.h"
#include "df/item_slabst.h"
#include "df/historical_figure.h"
#include "df/creature_raw.h"

namespace df3d_production {
// Semantic body inputs for Coffin/Slab; viewer owns layout and local navigation.
struct FuneraryBody {
    int32_t buildingId=-1,unitId=-1,historicalFigureId=-1;
    int32_t roomId=-1,roomType=-1;
    std::vector<int32_t> relevantZones;
    std::vector<std::string> notices;
    std::string introduction,name,roomIntroduction,roomName,deceased;
    std::optional<ItemAppearanceRecipe> ownerAppearance;
};
inline bool funeraryReady() {
    if(!df3d_creature::inventoryDescriptionReady())return false;
    static const bool ready=[] {
        auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t value;};
        const Pin pins[]={
            // Entire room predicate, including both returns and jump tables.
            {0x54bb10,0x47,UINT64_C(0x94acd2997276546c)},
            {0xa94030,0x6a1,UINT64_C(0xd81db68b3c9b33d2)},
            {0xaa3bd0,0x1c3,UINT64_C(0x0f9cd818efc6bad8)},
        };
        for(const auto& pin:pins) {
            uint64_t value=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){value^=base[pin.rva+i];value*=UINT64_C(1099511628211);}
            if(value!=pin.value)return false;
        }
        return std::strcmp(reinterpret_cast<const char*>(base+0x16014d0),"This is a memorial to")==0 &&
               std::strcmp(reinterpret_cast<const char*>(base+0x1601c40),"This is the resting place of")==0 &&
               std::strcmp(reinterpret_cast<const char*>(base+0x15ed620),"a ")==0 &&
               std::strcmp(reinterpret_cast<const char*>(base+0x1601c30),"Deceased")==0 &&
               std::strcmp(reinterpret_cast<const char*>(base+0x1601800),"This furniture is a part of")==0 &&
               std::strcmp(reinterpret_cast<const char*>(base+0x1601820),"This furniture is a part of multiple rooms.")==0 &&
               std::strcmp(reinterpret_cast<const char*>(base+0x1601c90),"You must designate a tomb")==0 &&
               std::strcmp(reinterpret_cast<const char*>(base+0x1601c78),"before this coffin will")==0 &&
               std::strcmp(reinterpret_cast<const char*>(base+0x1601c60),"be used for burial.")==0;
    }();
    return ready;
}
inline std::optional<FuneraryBody> funeraryBody(df::building* building) {
    if(!building || !funeraryReady())return std::nullopt;
    const auto type=building->getType();
    if(type!=df::building_type::Coffin && type!=df::building_type::Slab)return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    FuneraryBody result;result.buildingId=building->id;
    if(type==df::building_type::Coffin) {
        static_assert(offsetof(df::building,relations)==0xa0);
        static_assert(offsetof(df::building_civzonest,type)==0x150);
        static_assert(offsetof(df::building_civzonest,assigned_unit_id)==0x1a0);
        const auto rooms=relevantBuildingRooms(*building);if(!rooms)return std::nullopt;
        df::building_civzonest* tomb=nullptr;
        for(auto* zone:*rooms){result.relevantZones.push_back(zone->id);tomb=zone;}
        if(result.relevantZones.empty()) {
            for(const size_t rva:{0x1601c90,0x1601c78,0x1601c60})result.notices.emplace_back(reinterpret_cast<const char*>(base+rva));
        }else if(result.relevantZones.size()>1)result.notices.emplace_back(reinterpret_cast<const char*>(base+0x1601820));
        if(result.relevantZones.size()==1 && int32_t(tomb->type)==97) {
            auto zoneName=df3d_area::nativeZoneName(*tomb);if(!zoneName || zoneName->size()>1536)return std::nullopt;
            result.roomId=tomb->id;result.roomType=int32_t(tomb->type);
            result.roomName=std::move(*zoneName);result.roomIntroduction=reinterpret_cast<const char*>(base+0x1601800);
            auto* unit=df::unit::find(tomb->assigned_unit_id);
            if(unit) {
                if(!unit->body.body_plan || unit->inventory.size()>10000)return std::nullopt;
                for(const auto* entry:unit->inventory)if(!entry)return std::nullopt;
                df3d_creature::InventoryRandomRestore restore(base);
                df3d_creature::InventoryDescriptionContext owned(*unit);
                reinterpret_cast<void(*)(df::unit*,std::string*,bool)>(base+0x1330c30)(owned.unit(),&result.name,false);
                result.unitId=unit->id;
                result.introduction=reinterpret_cast<const char*>(base+0x1601c40);
                // Inline card1952fd..19534c tests DEAD, IS_EQUIPMENT and ZOMBIE.
                static_assert(offsetof(df::unit,flags1)==0x110);
                if((unit->flags1.whole&0x502)==2)result.deceased=reinterpret_cast<const char*>(base+0x1601c30);
                df3d_appearance::Result appearance;
                if(df3d_appearance::resolveUnitSelector(unit,appearance))result.ownerAppearance=ownedItemRecipe(appearance);
                if(!result.ownerAppearance)return std::nullopt;
            }
        }
    }else {
        static_assert(offsetof(df::building_actual,contained_items)==0x128);
        static_assert(offsetof(df::item_slabst,topic)==0x108);
        static_assert(offsetof(df::item_slabst,engraving_type)==0x10c);
        auto* actual=virtual_cast<df::building_actual>(building);
        if(!actual || actual->contained_items.empty())return result;
        const auto* held=actual->contained_items.front();if(!held || !held->item)return std::nullopt;
        auto* slab=virtual_cast<df::item_slabst>(held->item);
        if(!slab || int32_t(slab->engraving_type)!=0 || slab->topic==-1)return result;
        auto* figure=df::historical_figure::find(slab->topic);if(!figure)return result;
        result.historicalFigureId=figure->id;
        result.introduction=reinterpret_cast<const char*>(base+0x16014d0);
        if(figure->name.has_name) {
            auto owned=figure->name;
            reinterpret_cast<void(*)(df::language_name*,std::string*)>(base+0xa94030)(&owned,&result.name);
        }else {
            // Native18aacd uses the generic race/caste caption, not a
            // synthesized historical-figure name.
            if(figure->race<0 || size_t(figure->race)>=df::global::world->raws.creatures.all.size())return std::nullopt;
            const auto* race=df::global::world->raws.creatures.all[figure->race];
            if(!race || figure->caste<0 || size_t(figure->caste)>=race->caste.size())return std::nullopt;
            result.name=reinterpret_cast<const char*>(base+0x15ed620);
            std::string caste;
            reinterpret_cast<void(*)(int16_t,std::string*,bool,int16_t)>(base+0xaa3bd0)(figure->race,&caste,false,figure->caste);
            result.name+=caste;
        }
    }
    if(result.name.size()>1536)return std::nullopt;
    return result;
}
}
