#pragma once
#include "tasks_artwork_native.h"
#include "df/building_civzonest.h"
#include "df/abstract_building.h"
#include "df/abstract_building_contents.h"
#include "df/plotinfost.h"
#include "df/world_site.h"

namespace df3d_places {
// Original installed icon selectors from Places39ba3b..39c68a. Rendering
// scratch is never consulted. Ordinary building selectors agree with Tasks;
// empty stockpiles and zone/location icons are specific to this surface.
inline std::optional<df3d_production::ItemAppearanceRecipe> artwork(df::building& building,size_t mode) {
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool pinned=[base]{
        uint64_t h=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0xc4f;++i){h^=base[0x39ba3b+i];h*=UINT64_C(1099511628211);}
        if(h!=UINT64_C(0x18ecbdb9488f0248))return false;
        h=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x194;++i){h^=base[0x39ef50+i];h*=UINT64_C(1099511628211);}
        return h==UINT64_C(0x8e7e7738bc271bba);
    }();
    if(!pinned)return std::nullopt;
    uint32_t slot=0;
    if(mode>=2){
        auto* pile=virtual_cast<df::building_stockpilest>(&building);
        if(mode==2 && pile && pile->settings.flags.whole==0)slot=0x264b490;
        else return df3d_tasks::destinationArtwork(&building);
    }else{
        auto* zone=virtual_cast<df::building_civzonest>(&building);
        if(!zone || !df::global::plotinfo)return std::nullopt;
        constexpr uint32_t zones[]={0x264b384,0x264b374,0,0x264b390,0x264b39c,0x264b3a8,0x264b394,0x264b3a4,0x264b3b0,0x264b3a0,0x264b3ac,0x264b3b8,0x264b398,0x264b370,0x264b378,0x264b37c,0x264b380,0x264b388,0x264b38c};
        const int type=int(zone->type);
        if(mode==0 && type>=79 && type<=97)slot=zones[type-79];
        if(mode==1 || type==87){
            df::abstract_building* location=nullptr;
            auto* site=df::global::plotinfo->main.fortress_site;
            if(site && zone->site_id==df::global::plotinfo->site_id)
                for(auto* entry:site->buildings)if(entry && entry->id==zone->location_id){location=entry;break;}
            if(location){
                auto* contents=location->getContents();
                static_assert(offsetof(df::abstract_building_contents,location_tier)==0x34);
                switch(int(location->getType())){
                    case 2: slot=contents?(contents->location_tier==1?0x264b3d4:contents->location_tier==2?0x264b3d8:0x264b3d0):0;break;
                    case 8: slot=0x264b3c0;break;
                    case 9: slot=0x264b3c4;break;
                    case 11: slot=contents?(contents->location_tier==2?0x264b3cc:0x264b3c8):0;break;
                    case 13: slot=0x264b3b4;break;
                    default: slot=0x264b3b0;break;
                }
            }
        }
    }
    if(!slot)return std::nullopt;
    const int32_t tile=*reinterpret_cast<const int32_t*>(base+slot);
    df3d_appearance::Result recipe;
    if(tile<=0 || !df3d_appearance::resolveOriginalItemTile(tile,recipe))return std::nullopt;
    return df3d_production::ownedItemRecipe(recipe);
}
}
