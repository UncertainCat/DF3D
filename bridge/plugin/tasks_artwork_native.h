#pragma once
#include "residents_activity_native.h"
#include "building_item_native.h"
#include "df/building_stockpilest.h"
#include "df/building_def_workshopst.h"
#include "df/building_def_furnacest.h"

namespace df3d_tasks {
// Native Tasks398d2f..399489 inline icon dispatch. These are original installed
// icon slots, not composed texture caches. Custom raw icons precede fallbacks.
inline std::optional<df3d_production::ItemAppearanceRecipe> destinationArtwork(df::building* building,bool customRawIcons=true) {
    if(!building || !df::global::world)return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool pinned=[base] {
        if(!df3d_residents::activitySupported())return false;
        struct Pin{size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x398d2f,0x75a,UINT64_C(0x730fc12ea3c2854d)},
            {0x399724,0x265,UINT64_C(0xf9ca45cd075d8991)},
        };
        for(const auto& p:pins){uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<p.length;++i){h^=base[p.rva+i];h*=UINT64_C(1099511628211);}if(h!=p.hash)return false;}
        return true;
    }();
    if(!pinned)return std::nullopt;
    constexpr uint32_t types[]={0x264b0b0,0x264b0ac,0x264b0b4,0x264b0c0,0x264b080,0x0,0x264b02c,0x0,0x264b0e0,0x264b138,0x264b0b8,0x264b180,0x264b184,0x0,0x264b0bc,0x264b0c8,0x264b11c,0x264b120,0x264b134,0x264b0fc,0x264b104,0x264b100,0x0,0x0,0x264b164,0x264b124,0x264b17c,0x264b15c,0x264b160,0x0,0x0,0x264b178,0x264b194,0x264b13c,0x0,0x264b0e4,0x264b10c,0x264b110,0x264b114,0x264b118,0x264b148,0x264b14c,0x264b150,0x264b140,0x264b144,0x264b0cc,0x264b0c4,0x264b0a4,0x264b0a4,0x264b0a8,0x264b158,0x264b0dc,0x264b0d0,0x264b0d4,0x264b0d8};
    constexpr uint32_t workshops[]={0x264b030,0x264b098,0x264b034,0x264b040,0x264b044,0x264b038,0x264b038,0x264b050,0x264b054,0x264b058,0x264b088,0x264b070,0x264b08c,0x264b078,0x264b090,0x264b084,0x264b074,0x264b09c,0x264b0a0,0x264b094,0x264b05c,0x264b07c,0x264b154,0xffffffff,0x264b00c};
    constexpr uint32_t furnaces[]={0x264b060,0x264b064,0x264b068,0x264b06c,0x264b064,0x264b068,0x264b06c,0xffffffff};
    constexpr uint32_t traps[]={0x264b130,0x264b168,0x264b174,0x264b16c,0x264b170,0x264b12c};
    constexpr uint32_t constructions[]={0x264b108,0x264b0e8,0x264b0f0,0x264b0f8,0x264b0f8,0x264b0f8,0x264b0f4,0x264b128,0x264b128,0x264b128,0x264b128,0x264b128,0x264b128,0x264b128,0x264b128,0x264b128,0x264b128,0x264b128,0x264b128,0x264b128,0x264b128,0x264b128,0x264b128,0x264b128,0x264b128,0x264b128,0x264b128,0x264b128,0x264b128,0x264b128,0x264b128,0x264b128,0x264b128,0x264b128,0x264b128,0x264b128,0x264b128,0x264b0ec};
    constexpr uint32_t siege[]={0x264b18c,0x264b188,0x264b190};
    constexpr uint32_t stockpiles[]={0x264b498,0x264b4b4,0x264b4b8,0x264b4ac,0x264b4c4,0x264b4cc,0x264b494,0x264b4a8,0x264b4a0,0x264b4bc,0x264b4b0,0x264b4c0,0x264b4a4,0x264b4d4,0x264b4d0,0x264b49c,0x264b4c8};
    const auto pick=[](const auto& values,int index)->uint32_t{return index>=0 && size_t(index)<std::size(values)?values[index]:0;};
    const int type=int(building->getType());
    uint32_t slot=pick(types,type);int32_t tile=0;
    if(type==5 || type==13){
        const int subtype=building->getSubtype();
        slot=type==5?pick(furnaces,subtype):pick(workshops,subtype);
        if(slot==0xffffffff){
            const int id=building->getCustomType();
            if(customRawIcons) {
                if(type==5){for(auto* raw:df::global::world->raws.buildings.furnaces)if(raw && raw->id==id){tile=raw->list_icon_texpos;break;}}
                else {for(auto* raw:df::global::world->raws.buildings.workshops)if(raw && raw->id==id){tile=raw->list_icon_texpos;break;}}
            }
            slot=type==5?0x264b03c:0x264b00c;
        }
    } else if(type==22)slot=pick(siege,building->getSubtype());
    else if(type==23)slot=pick(traps,building->getSubtype());
    else if(type==34)slot=pick(constructions,building->getSubtype());
    else if(type==29){
        static_assert(offsetof(df::building_stockpilest,settings)==0x120);
        const uint32_t flags=static_cast<df::building_stockpilest*>(building)->settings.flags.whole;
        slot=0x264b4d8;
        for(size_t i=0;i<std::size(stockpiles);++i)if(flags==(uint32_t(1)<<i)){slot=stockpiles[i];break;}
    }
    if(!tile && slot)tile=*reinterpret_cast<const int32_t*>(base+slot);
    if(tile<=0)return std::nullopt;
    df3d_appearance::Result recipe;
    if(!df3d_appearance::resolveOriginalItemTile(tile,recipe))return std::nullopt;
    return df3d_production::ownedItemRecipe(recipe);
}
// Linked-building renderer uses the same type/subtype/category slots, but
// custom workshops/furnaces always use the generic installed icon.
inline std::optional<df3d_production::ItemAppearanceRecipe> linkedBuildingArtwork(df::building* building) {
    static const bool ready=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0xa39;++i){hash^=base[0x19bff9+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0x2f8dfc511a72bc35);
    }();
    return ready?destinationArtwork(building,false):std::nullopt;
}
// Item-holder renderer155919..156449 uses the same fixed dispatch and custom
// raw list_icon_texpos precedence as Tasks. Keep that reuse version-qualified.
inline std::optional<df3d_production::ItemAppearanceRecipe> itemHolderArtwork(df::building* building) {
    static const bool ready=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0xb30;++i){hash^=base[0x155919+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0x2accec46dc8a4843);
    }();
    return ready?destinationArtwork(building):std::nullopt;
}

}
