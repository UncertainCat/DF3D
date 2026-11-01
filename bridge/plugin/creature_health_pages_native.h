#pragma once
#include "unit_description_native.h"
#include "df/unit_health_info.h"
#include "df/curse_attr_change.h"
#include "df/unit_ghost_info.h"
#include "df/unit_wound.h"
#include "df/unit_wound_layerst.h"
#include <memory>
#include "df/game_mode.h"
#include <cstddef>
namespace df3d_creature {
// Diagnostic-only first entry into the shared Health text builder. Other page
// paths require additional ownership auditing before expanding this allowlist.
inline std::optional<std::vector<std::string>> healthPageProbe(df::unit* source,int page) {
    if(!source || (page<0 || page>4 || page==3) || !df::global::gamemode || *df::global::gamemode!=df::game_mode::DWARF)return std::nullopt;
    if(!inventoryDescriptionReady())return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    struct Pin {size_t rva,length;uint64_t hash;};
    constexpr Pin pins[]={
        {0x479f40,0x4074,UINT64_C(0x11442695a7629f0c)},
        {0xbb9b0,0x74,UINT64_C(0x7532991bab65be09)},
        {0x14ed20,0x2c,UINT64_C(0x46a2348317a3bcad)},
        {0x14e330,0xa4,UINT64_C(0x2ad742620f1a9069)},
        {0x5b06d0,0x59,UINT64_C(0x0dcdd6fc41f10b2a)},
        {0x1380480,0xd28,UINT64_C(0x72a25fcd6cf2084f)},
        {0x13cae60,0x72a,UINT64_C(0x78512b1dbad00fa1)},
        {0x70f070,0x3248,UINT64_C(0x74d713ef279a2c06)},
        {0x712370,0x47fc,UINT64_C(0x617842ad4866396f)},
        {0x14d1920,0x459,UINT64_C(0xf48e28715360ed9a)},
        {0x6ba400,0x1c6,UINT64_C(0x28499b332b1e3f27)},
        {0x5c0b20,0x9f,UINT64_C(0x09c0a9b2e39ead96)},
        {0x5c0bc0,0xd9,UINT64_C(0x4e535cd298e1e834)},
        {0x13daa50,0x138,UINT64_C(0xfbd6ecb5aa4696ea)},
        {0x13b3030,0x56,UINT64_C(0xf9404dd6eb50e2af)},
    };
    for(const auto& pin:pins){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<pin.length;++i){h^=base[pin.rva+i];h*=UINT64_C(1099511628211);}if(h!=pin.hash)return std::nullopt;}
    // This is owned formatter storage, not a view_sheets instance or copy.
    struct Context {
        std::array<uint8_t,0x1c88> prefix{};
        std::vector<std::string*> strings;
        std::vector<void*> boxes;
        uint8_t* base;
        explicit Context(uint8_t* b):base(b){}
        ~Context(){
            reinterpret_cast<void(*)(std::vector<std::string*>*)>(base+0xbb9b0)(&strings);
            for(auto* box:boxes)if(box)reinterpret_cast<void(*)(void*)>(base+0x14ed20)(box);
        }
    } context(base);
    static_assert(offsetof(Context,strings)==0x1c88 && offsetof(Context,boxes)==0x1ca0);
    std::memcpy(context.prefix.data()+0x1c7c,&page,sizeof(page));
    InventoryDescriptionContext unit(*source);
    unit.unit()->status=source->status;unit.unit()->status2=source->status2;
    unit.unit()->counters=source->counters;unit.unit()->counters2=source->counters2;
    struct OwnedHealth final:df::unit_health_info {OwnedHealth():df::unit_health_info(){}} health;
    if(source->health){static_cast<df::unit_health_info&>(health)=*source->health;unit.unit()->health=&health;}
    // Wounds traverses diagnosed wounds and their tissue/effect vectors. Own
    // those records and backing arrays as well as the unit's pointer list.
    struct OwnedWound final:df::unit_wound {OwnedWound():df::unit_wound(){}};
    struct OwnedLayer final:df::unit_wound_layerst {OwnedLayer():df::unit_wound_layerst(){}};
    std::vector<std::unique_ptr<OwnedWound>> wounds;
    std::vector<std::unique_ptr<OwnedLayer>> layers;
    unit.unit()->body.wounds.clear();
    for(const auto* sourceWound:source->body.wounds){
        if(!sourceWound)return std::nullopt;
        auto wound=std::make_unique<OwnedWound>();
        static_cast<df::unit_wound&>(*wound)=*sourceWound;wound->parts.clear();
        for(const auto* sourceLayer:sourceWound->parts){
            if(!sourceLayer)return std::nullopt;
            auto layer=std::make_unique<OwnedLayer>();
            static_cast<df::unit_wound_layerst&>(*layer)=*sourceLayer;
            wound->parts.push_back(layer.get());layers.push_back(std::move(layer));
        }
        unit.unit()->body.wounds.push_back(wound.get());wounds.push_back(std::move(wound));
    }
    // Description uses semantic appearance/age inputs, never sheet text caches.
    static_assert(offsetof(df::unit,appearance)==0x6e8);
    static_assert(offsetof(df::unit,uwss_att_change)==0x8e8);
    static_assert(offsetof(df::unit,birth_year)==0x38c);
    static_assert(offsetof(df::unit,ghost_info)==0x380);
    static_assert(offsetof(df::unit,enemy)+offsetof(df::unit::T_enemy,normal_race)==0xd90);
    unit.unit()->appearance=source->appearance;
    unit.unit()->birth_year=source->birth_year;unit.unit()->birth_time=source->birth_time;
    unit.unit()->uwss_body_modifier=source->uwss_body_modifier;
    unit.unit()->uwss_bp_modifer=source->uwss_bp_modifer;
    df::curse_attr_change attributes;
    if(source->uwss_att_change){attributes=*source->uwss_att_change;unit.unit()->uwss_att_change=&attributes;}
    df::unit_ghost_info ghost;
    if(source->ghost_info){ghost=*source->ghost_info;unit.unit()->ghost_info=&ghost;}
    InventoryRandomRestore random(base);
    reinterpret_cast<void(*)(void*,df::unit*)>(base+0x479f40)(&context,unit.unit());
    if(context.strings.size()!=context.boxes.size() || context.strings.size()>4096)return std::nullopt;
    std::vector<std::string> result;result.reserve(context.strings.size());
    for(const auto* text:context.strings){if(!text || text->size()>65536)return std::nullopt;result.push_back(*text);}
    return result;
}
}
