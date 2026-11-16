#pragma once
#include "trade_dialogue_native.h"
#include "unit_description_native.h"
#include "zone_native.h"

namespace df3d_production {
struct TradeHeader {
    std::string name,dialogue,mood;
    std::vector<std::string> status;
    std::optional<df3d_area::ZoneOwnerNameColor> nameColor;
    int8_t moodColor=-1,statusColor=-1;
    int32_t speaker=-1;
};
inline bool tradeHeaderNativeReady() {
    if(!tradeDialogueNativeReady() || !df3d_creature::inventoryDescriptionReady())return false;
    static const bool ready=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x385b33,0x86,UINT64_C(0x5e8a15c2a68c0557)},
            {0x3863c1,0x18a,UINT64_C(0xc9ad6b202b54f6a2)},
            {0x38a407,0x105,UINT64_C(0x6a72ff9558af16f2)},
            {0x133e7a0,0x32d,UINT64_C(0xb3c6cbdbc8f6dade)},
            {0x8e7310,0x121,UINT64_C(0x672cfcd6c9373787)},
            {0x15f71e4,5,UINT64_C(0xf302b01c91704c3b)},
            {0x162ab40,8,UINT64_C(0x45e00f82a09b94ba)},
            {0x162ab20,0x1a,UINT64_C(0x5b53134d8a127581)},
            {0x162b310,0x1d,UINT64_C(0xf7be52f2dd96e05c)},
            {0x162b2f0,0x19,UINT64_C(0x7fa1dbea9322b5af)},
            {0x162b350,0x11,UINT64_C(0x4da29faa41d6eb02)},
            {0x162b330,0x1e,UINT64_C(0x6bbe1cc306f0116f)},
            {0x162b380,0x24,UINT64_C(0x7b21d1bfef1e2317)},
            {0x162b368,0x13,UINT64_C(0x62cb19ce40f91c2b)},
            {0x15e85b4,2,UINT64_C(0x07da2c07b4a05dc3)},
            {0x162a908,0x29,UINT64_C(0x2c2c1c96ba7a4a9e)},
            {0x162a998,0x15,UINT64_C(0xc6a466bdf7d20c2a)},
            {0x162a960,0x34,UINT64_C(0x54f12dfb3318cd1e)},
        };
        for(const auto& pin:pins){uint64_t h=UINT64_C(14695981039346656037);for(size_t i=0;i<pin.length;++i){h^=base[pin.rva+i];h*=UINT64_C(1099511628211);}if(h!=pin.hash)return false;}
        return true;
    }();return ready;
}
// Native3861cc supplies the available dialogue width to8e7310. Layout width
// is owned by the caller; no gps/window/menu state is an input here. CP437
// bytes remain intact until transport converts each resulting line to UTF-8.
inline std::optional<std::vector<std::string>> tradeDialogueLines(std::string dialogue,int32_t columns) {
    if(!tradeHeaderNativeReady() || columns<1 || columns>512 || dialogue.size()>2048)return {};
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    df::curses_text_boxst box;
    struct Cleanup {df::curses_text_boxst& box;const uint8_t* base;
        ~Cleanup(){reinterpret_cast<void(*)(df::curses_text_boxst*)>(base+0xbb9b0)(&box);}
    } cleanup{box,base};
    reinterpret_cast<void(*)(df::curses_text_boxst*,std::string*,int32_t)>(base+0x8e7310)(&box,&dialogue,columns);
    if(box.text.size()>2049)return {};
    std::vector<std::string> result;result.reserve(box.text.size());
    for(const auto* line:box.text){if(!line || line->size()>2048)return {};result.push_back(*line);}
    return result;
}
// Header semantic text only. Portrait selection and wrapping belong to their
// independently qualified providers; never expose native cached textures.
inline std::optional<TradeHeader> tradeHeader(df::building* building,size_t caravanIndex,int16_t line) {
    if(!tradeHeaderNativeReady())return {};
    const auto entry=tradeEntryFacts(building,caravanIndex);if(!entry)return {};
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    const auto text=[&](size_t rva){return std::string(reinterpret_cast<const char*>(base+rva));};
    TradeHeader result;result.speaker=entry->merchantTrader;
    if(result.speaker>=0) {
        auto* speaker=df::unit::find(result.speaker);if(!speaker || speaker->inventory.size()>10000)return {};
        for(const auto* item:speaker->inventory)if(!item)return {};
        df3d_creature::InventoryRandomRestore random(base);
        df3d_creature::InventoryDescriptionContext owned(*speaker);
        reinterpret_cast<void(*)(df::unit*,std::string*,bool)>(base+0x1330c30)(owned.unit(),&result.name,false);
        result.nameColor=df3d_area::nativeZoneOwnerNameColor(*speaker);
        if(!result.nameColor || result.name.size()>2048)return {};
    }
    if(entry->unloading || !entry->hasSpeaker) {
        if(entry->hasSpeaker){result.status={text(0x162a908),text(0x162a998)};result.statusColor=14;}
        else {result.status={text(0x162a960)};result.statusColor=7;}
        return result;
    }
    if(result.speaker<0)return result;
    auto* civ=df::historical_entity::find(entry->entity);auto* broker=df::unit::find(entry->fortressTrader);
    auto* caravan=df::global::plotinfo->caravans[caravanIndex];if(!civ || !caravan)return {};
    const auto dialogue=tradeDialogue(*civ,*caravan,broker,line);if(!dialogue)return {};
    result.dialogue=*dialogue;
    // Native effective-skill query may refresh semantic body/vision caches;
    // it does not train the broker or consult UI state.
    if(broker && reinterpret_cast<int32_t(*)(df::unit*,int32_t)>(base+0x133e7a0)(broker,72)>0) {
        static_assert(offsetof(df::caravan_state,mood)==0x2118);
        const auto mood=caravan->mood;
        size_t caption=0;int8_t color=0;
        if(mood>=100){caption=0x162ab20;color=10;}
        else if(mood>=80){caption=0x162b310;color=11;}
        else if(mood>=60){caption=0x162b2f0;color=9;}
        else if(mood>=40){caption=0x162b350;color=15;}
        else if(mood>=20){caption=0x162b330;color=14;}
        else if(mood>0){caption=0x162b380;color=12;}
        else {caption=0x162b368;color=13;}
        result.mood=entry->speaker+text(mood>=20?0x162ab40:0x15f71e4)+text(caption)+text(0x15e85b4);
        result.moodColor=color;if(result.mood.size()>2048)return {};
    }
    return result;
}
}
