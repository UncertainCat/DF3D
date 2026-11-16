#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include "special_building_native.h"
#include "farm_native.h"
#include "unit_description_native.h"
#include "building_item_native.h"
#include "df/building_nest_boxst.h"
#include "df/building_animaltrapst.h"
#include "df/building_hivest.h"
#include "df/buildings_other_id.h"
#include "df/item_critter.h"
#include <cstring>

namespace df3d_production {
namespace {
bool ready() {
    if(!farmFunctions() || !df::global::world)return false;
    static_assert(offsetof(df::building_nest_boxst,claimed_by)==0x148);
    static_assert(offsetof(df::building_animaltrapst,bait_type)==0x148);
    static_assert(offsetof(df::building_hivest,hive_flags)==0x148);
    static_assert(offsetof(df::item_critter,race)==0xb8);
    static const bool pinned=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t at,length;uint64_t hash;};
        // Renderer ranges are static evidence for semantic branches only. They
        // are never executed and no widget, drawing or selection state is read.
        constexpr Pin pins[]={
            {0x196637,0x1e5,UINT64_C(0x2d9024af9aff7e00)},
            {0x19836c,0x8ce,UINT64_C(0xbe461fd3fa5ca647)},
            {0x18b841,0xea1,UINT64_C(0x82a7f8fc147226ff)},
            {0x1330c30,0x688,UINT64_C(0x0e165ee31decf426)},
            {0x560f10,0x293,UINT64_C(0xc30f8d5969d48a48)}};
        for(const auto& p:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<p.length;++i){hash^=base[p.at+i];hash*=UINT64_C(1099511628211);}
            if(hash!=p.hash)return false;
        }
        struct Text {size_t at;const char* value;};
        constexpr Text texts[]={{0x1601c18,"Nest box claimed by"},{0x1601c00,"Nest box unclaimed"},
            {0x1601da0,"Desired bait: "},{0x1601d98,"Nothing"},{0x1601d8c,"Meat"},
            {0x1601d84,"Fish"},{0x1601d78,"Large gem"},
            {0x1600d10,"Trap Occupied:"},{0x1601fe0,"Trap Baited:"}};
        for(const auto& t:texts)if(std::strcmp(reinterpret_cast<const char*>(base+t.at),t.value))return false;
        return true;
    }();return pinned;
}
std::string text(size_t at) {
    return reinterpret_cast<const char*>(reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr))+at);
}
bool target(df::building* building,df::building_type type) {
    return ready() && building && building->getType()==type &&
        building->getBuildStage()==building->getMaxBuildStage();
}
}
std::optional<NestBoxBody> nestBoxBody(df::building* building) {
    if(!target(building,df::building_type::NestBox))return {};
    const auto& nest=*static_cast<df::building_nest_boxst*>(building);
    NestBoxBody result;
    auto* unit=df::unit::find(nest.claimed_by);
    result.status=text(unit?0x1601c18:0x1601c00);
    if(!unit)return result;
    if(unit->inventory.size()>10000 || !unit->body.body_plan)return {};
    for(auto* held:unit->inventory)if(!held || !held->item)return {};
    result.nameColor=df3d_area::nativeZoneOwnerNameColor(*unit);
    if(!result.nameColor)return {};
    df3d_creature::InventoryDescriptionContext owned(*unit);
    using Name=void(*)(df::unit*,std::string*,bool);
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    reinterpret_cast<Name>(base+0x1330c30)(owned.unit(),&result.name,false);
    if(result.name.size()>2048)return {};
    result.claimantId=unit->id;return result;
}
std::optional<AnimalTrapBody> animalTrapBody(df::building* building) {
    if(!target(building,df::building_type::AnimalTrap))return {};
    const auto& trap=*static_cast<df::building_animaltrapst*>(building);
    AnimalTrapBody result;result.baitType=trap.bait_type;
    if(trap.contained_items.size()>10000)return {};
    if(trap.contained_items.empty())return result;
    if(trap.contained_items.size()==1) {
        result.state=AnimalTrapBody::State::Empty;result.status=text(0x1601da0);
        switch(trap.bait_type) {
        case -1:result.status+=text(0x1601d98);break;
        case 48:result.status+=text(0x1601d8c);break;
        case 49:result.status+=text(0x1601d84);break;
        case 44:result.status+=text(0x1601d78);break;
        default:break; // Native leaves the suffix empty for other values.
        }
        return result;
    }
    const auto* entry=trap.contained_items[1];if(!entry || !entry->item)return {};
    auto* item=entry->item;const bool occupied=item->getType()==df::item_type::VERMIN;
    result.state=occupied?AnimalTrapBody::State::Occupied:AnimalTrapBody::State::Baited;
    result.status=text(occupied?0x1600d10:0x1601fe0);result.itemId=item->id;
    const auto caption=buildingItemCaption(item);if(!caption || caption->size()>2048)return {};
    result.name=*caption;return result;
}
std::optional<HiveBody> hiveBody(df::building* building) {
    if(!target(building,df::building_type::Hive))return {};
    auto& hive=*static_cast<df::building_hivest*>(building);
    HiveBody result;result.flags=hive.hive_flags.whole;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    auto& hives=df::global::world->buildings.other.HIVE;
    if(reinterpret_cast<const void*>(&hives)!=base+0x23eeb40 || hives.size()>100000 || hive.contained_items.size()>10000)return {};
    // Standalone native map/tile query, with no UI or scratch inputs.
    result.outdoorAccess=reinterpret_cast<bool(*)(df::building*)>(base+0x560f10)(&hive);
    for(const auto* entry:hive.contained_items) {
        if(!entry || !entry->item)return {};
        auto* item=entry->item;
        if(!item->flags.bits.in_building || item->getType()!=df::item_type::VERMIN)continue;
        result.colonyRace=static_cast<df::item_critter*>(item)->race;
        // Native18c49f calls virtual slot9 (getRace). One matching colony per
        // hive, including this hive; the first installed colony sets the race.
        for(const auto* other:hives) {
            if(!other || other->contained_items.size()>10000)return {};
            for(const auto* contained:other->contained_items) {
                if(!contained || !contained->item)return {};
                auto* candidate=contained->item;
                if(candidate->flags.bits.in_building && candidate->getType()==df::item_type::VERMIN && candidate->getRace()==result.colonyRace) {
                    ++result.matchingColonies;break;
                }
            }
        }
        result.crowding=result.matchingColonies>=60?2:result.matchingColonies>40?1:0;
        break;
    }
    return result;
}
}
