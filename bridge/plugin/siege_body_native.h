#pragma once
#include "siege_controls_native.h"
#include "ammunition_assignment_native.h"
#include "df/buildingitemst.h"
#include "df/item.h"
#include <array>

namespace df3d_production {
// The count loops are inline in native192b65..1933af. Use native semantic
// availability, effective-position and component queries with owned outputs.
inline std::optional<std::array<int32_t,4>> siegeAmmunition(df::building* building) {
    const auto controls=siegeControls(building);
    if(!controls || controls->type!=2 || !df::global::world)return {};
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    static const bool ready=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x19205a,0x1c93,UINT64_C(0xe20b8847f0767cff)},
            {0xc93380,0x98,UINT64_C(0x9455ba082ba604c4)},
            {0xc93160,0x213,UINT64_C(0x07d957dea30ed105)},
            {0xc8baa0,0x11a,UINT64_C(0x2c62fce4a0555c66)},
            {0x10afe0,0xb9,UINT64_C(0xdd7dd1f9769e2f8a)}};
        for(const auto& p:pins) {
            uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<p.length;++i){h^=base[p.rva+i];h*=UINT64_C(1099511628211);}
            if(h!=p.hash)return false;
        }return true;
    }();
    auto& world=*df::global::world;
    auto& engine=*static_cast<df::building_siegeenginest*>(building);
    if(!ready || reinterpret_cast<const uint8_t*>(&world)!=base+0x23d14f0 ||
       reinterpret_cast<const uint8_t*>(&world.items.other.AMMO)!=base+0x23e55e8 ||
       engine.contained_items.size()>1000000 || world.items.other.AMMO.size()>1000000)return {};
    static_assert(offsetof(df::building,centerx)==0x10);
    static_assert(offsetof(df::building,centery)==0x1c);
    using Walk=int32_t (*)(df::world*,int16_t,int16_t,int16_t);
    const auto walk=reinterpret_cast<Walk>(base+0x10afe0);
    std::array<int32_t,8> components{};size_t count=0;
    for(int dx=-1;dx<=1;++dx)for(int dy=-1;dy<=1;++dy) {
        if(!dx && !dy)continue;
        const auto value=walk(&world,int16_t(engine.centerx+dx),int16_t(engine.centery+dy),int16_t(engine.z));
        if(value>0)components[count++]=value;
    }
    std::array<int32_t,4> result{};
    const auto add=[&](size_t index,df::item* item) {
        const auto amount=item->getStackSize();
        if(amount<0 || amount>INT32_MAX-result[index])return false;
        result[index]+=amount;return true;
    };
    for(const auto* entry:engine.contained_items) {
        if(!entry || !entry->item)return {};
        if(entry->item->getType()==df::item_type::AMMO && !add(0,entry->item))return {};
    }
    using Check=bool (*)(df::item*);
    using Position=void (*)(df::item*,int16_t*,int16_t*,int16_t*);
    std::string ammoClass="BOLT";
    constexpr uint64_t excluded=UINT64_C(0x800000000)|0x20|0x10|0x10000|0x400|0x800|0x400000|0x200000|0x800000|2|0x80000|0x2000|0x80;
    for(auto* item:world.items.other.AMMO) {
        if(!item)return {};
        if(!reinterpret_cast<Check>(base+0xc93380)(item) || (item->flags.whole&excluded) || !item->isAmmoClass(&ammoClass))continue;
        int16_t x=-30000,y=-30000,z=-30000;
        reinterpret_cast<Position>(base+0xc8baa0)(item,&x,&y,&z);
        if(x==-30000)continue;
        const auto component=walk(&world,x,y,z);
        if(std::find(components.begin(),components.begin()+count,component)==components.begin()+count)continue;
        const auto allocation=ammunitionAllocation(item->id);if(!allocation)return {};
        const size_t index=allocation->kind==1?3:allocation->kind==2?2:1;
        if(!add(index,item))return {};
    }
    return result;
}
}
