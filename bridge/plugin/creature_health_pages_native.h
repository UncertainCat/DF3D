#pragma once
#include "unit_description_native.h"
#include "df/unit_health_info.h"
#include "df/unit_wound.h"
#include "df/unit_wound_layerst.h"
#include <memory>
#include "df/game_mode.h"
#include <cstddef>
namespace df3d_creature {
// Diagnostic-only first entry into the shared Health text builder. Other page
// paths require additional ownership auditing before expanding this allowlist.
inline std::optional<std::vector<std::string>> healthPageProbe(df::unit* source,int page) {
    if(!source || (page<0 || page>2) || !df::global::gamemode || *df::global::gamemode!=df::game_mode::DWARF)return std::nullopt;
    if(!inventoryDescriptionReady())return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    struct Pin {size_t rva,length;uint64_t hash;};
    constexpr Pin pins[]={
        {0x479f40,0x4074,UINT64_C(0x11442695a7629f0c)},
        {0xbb9b0,0x74,UINT64_C(0x7532991bab65be09)},
        {0x14ed20,0x2c,UINT64_C(0x46a2348317a3bcad)},
        {0x14e330,0xa4,UINT64_C(0x2ad742620f1a9069)},
        {0x5b06d0,0x59,UINT64_C(0x0dcdd6fc41f10b2a)},
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
    InventoryRandomRestore random(base);
    reinterpret_cast<void(*)(void*,df::unit*)>(base+0x479f40)(&context,unit.unit());
    if(context.strings.size()!=context.boxes.size() || context.strings.size()>4096)return std::nullopt;
    std::vector<std::string> result;result.reserve(context.strings.size());
    for(const auto* text:context.strings){if(!text || text->size()>65536)return std::nullopt;result.push_back(*text);}
    return result;
}
}
