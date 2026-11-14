#pragma once
#include "creature_follow_native.h"
#include "df/caste_raw.h"
#include "df/creature_raw.h"
#include "df/engraving.h"
#include "df/vermin.h"
#include "df/view_sheet_type.h"

namespace df3d_selection {
struct Target {df::view_sheet_type kind=df::view_sheet_type::NONE;int32_t id=-1;};
struct Selection {
    std::vector<int32_t> units,items,vermin;
    int32_t building=-1;
    std::vector<Target> tabs;
    Target active;
};
// Native1a0d60 interleaves its collection with tutorial/menu mutation and sheet
// activation. Project its ordinary fortress branches into owned storage; call
// the same semantic visibility/footprint leaves, never the sheet entry point.
// The caller holds a DF safe point. This establishes choices, not edit authority.
inline std::optional<Selection> collect(int32_t x,int32_t y,int32_t z) {
    if(x<0 || y<0 || z<0 || x>32767 || y>32767 || z>32767 ||
       !df::global::world || !DFHack::Maps::IsValid())return std::nullopt;
    auto* block=DFHack::Maps::getTileBlock(x,y,z);
    if(!block || block->designation[x&15][y&15].bits.hidden)return std::nullopt;
    // Reuse the visibility/reference resolver dependency audit. Null performs
    // only compatibility checks and returns the invalid position sentinel.
    if(!df3d_creature::sheetPosition(nullptr))return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool supported=[base] {
        const auto hash=[base](size_t rva,size_t length) {
            uint64_t value=UINT64_C(14695981039346656037);
            for(size_t i=0;i<length;++i){value^=base[rva+i];value*=UINT64_C(1099511628211);}
            return value;
        };
        return hash(0x1a0d60,0xf42)==UINT64_C(0x7a0661ede1a658ae) &&
               hash(0x14da20,0x12c)==UINT64_C(0xe4024d0451e33fb3) &&
               hash(0x5587b0,0x79)==UINT64_C(0x14b4f3f138690067);
    }();
    if(!supported)return std::nullopt;
    Selection result;
    auto* world=df::global::world;
    const df::coord pos{uint16_t(x),uint16_t(y),uint16_t(z)};
    const auto append=[](std::vector<int32_t>& rows,int32_t id) {
        if(rows.size()>=4096 || id<0)return false;
        rows.push_back(id);return true;
    };
    for(auto* unit:world->units.active) {
        if(!unit || (unit->flags1.whole&0x2000002))continue;
        if(reinterpret_cast<bool(*)(df::unit*)>(base+0x137bd50)(unit))continue;
        if(!reinterpret_cast<bool(*)(df::unit*,int16_t,int16_t,int16_t)>(base+0x14da20)(unit,pos.x,pos.y,pos.z))continue;
        if(!append(result.units,unit->id))return std::nullopt;
    }
    for(auto id:block->items) {
        auto* item=df::item::find(id);
        if(item && !item->flags.bits.garbage_collect && item->pos==pos && !append(result.items,id))return std::nullopt;
    }
    for(auto* building:world->buildings.all) {
        // Native isVisibleInUI's ordinary fortress branch is !isHidden;
        // native hide/unhide menu overrides are not runtime inputs.
        if(!building || building->isHidden() || !building->isSettingOccupancy() || building->z!=z)continue;
        const auto kind=building->getType();
        if(kind==df::building_type::Stockpile || kind==df::building_type::Civzone)continue;
        if(building->isExtentShaped() && building->room.extents) {
            if(!reinterpret_cast<bool(*)(df::building*,int16_t,int16_t,int16_t)>(base+0x5587b0)(building,pos.x,pos.y,pos.z))continue;
        } else if(x<building->x1 || x>building->x2 || y<building->y1 || y>building->y2)continue;
        result.building=building->id;
    }
    const auto& creatures=world->raws.creatures.all;
    for(auto* vermin:world->event.vermin) {
        if(!vermin || !vermin->visible || (vermin->flags.whole&1) || vermin->pos!=pos ||
           vermin->race<0 || size_t(vermin->race)>=creatures.size() || vermin->caste<0)continue;
        auto* race=creatures[vermin->race];
        if(!race || size_t(vermin->caste)>=race->caste.size())continue;
        auto* caste=race->caste[vermin->caste];
        if(caste && !append(result.vermin,caste->index))return std::nullopt;
    }
    using Kind=df::view_sheet_type;
    const bool groupedUnits=result.units.size()>=6;
    const size_t itemThreshold=std::max(2,6-(groupedUnits?0:int(result.units.size()))-(result.building>=0?1:0));
    const bool groupedItems=result.items.size()>=itemThreshold;
    if(groupedUnits)result.tabs.push_back({Kind::UNIT_LIST,-1});
    else for(auto id:result.units)result.tabs.push_back({Kind::UNIT,id});
    for(auto id:result.vermin)result.tabs.push_back({Kind::VERMIN,id});
    if(result.building>=0)result.tabs.push_back({Kind::BUILDING,result.building});
    if(groupedItems)result.tabs.push_back({Kind::ITEM_LIST,-1});
    else for(auto id:result.items)result.tabs.push_back({Kind::ITEM,id});
    bool engraved=false;
    for(auto* engraving:world->event.engravings)if(engraving && engraving->pos==pos){engraved=true;break;}
    if(engraved)result.tabs.push_back({Kind::ENGRAVING,-1});
    else if(block->designation[x&15][y&15].whole&0x100)result.tabs.push_back({Kind::ENGRAVING_PLANNED,-1});
    if(groupedUnits)result.active={Kind::UNIT_LIST,-1};
    else if(!result.units.empty())result.active={Kind::UNIT,result.units.front()};
    else if(result.building>=0)result.active={Kind::BUILDING,result.building};
    else if(groupedItems)result.active={Kind::ITEM_LIST,-1};
    else if(!result.items.empty())result.active={Kind::ITEM,result.items.front()};
    else if(!result.vermin.empty())result.active={Kind::VERMIN,result.vermin.front()};
    else if(!result.tabs.empty())result.active=result.tabs.front();
    if(result.tabs.size()==1 && result.units.size()<=1 && result.items.size()<=1)result.tabs.clear();
    return result;
}
}
