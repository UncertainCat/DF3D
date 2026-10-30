#pragma once
#include "building_item_native.h"
#include "df/unit_inventory_item.h"
#include "df/squad.h"
#include "df/unit_soul.h"
#include "df/personality_needst.h"
#include "zone_native.h"

namespace df3d_creature {
// Native14d720 refreshes focus caches through e2c090. Supply independent
// personality storage and copied needs; all cache/timestamp writes stay owned.
inline std::optional<int32_t> focusPercent(const df::unit_personality& source) {
    static const bool supported=[] {
        if(!df3d_production::farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        const auto hash=[&](size_t rva,size_t length) {
            uint64_t value=UINT64_C(14695981039346656037);
            for(size_t i=0;i<length;++i){value^=base[rva+i];value*=UINT64_C(1099511628211);}
            return value;
        };
        return hash(0x14d720,0x33)==UINT64_C(0x011b14951ccbf4f2) &&
               hash(0xe2c090,0x1c7)==UINT64_C(0xd98351a8d8b2ee07);
    }();
    static_assert(offsetof(df::unit_personality,needs)==0x138);
    static_assert(offsetof(df::unit_personality,flags)==0x150);
    static_assert(offsetof(df::unit_personality,slack_end_year)==0x160);
    static_assert(offsetof(df::unit_personality,current_focus)==0x184);
    static_assert(offsetof(df::personality_needst,focus_level)==8);
    if(!supported || source.needs.size()>256)return std::nullopt;
    df::unit_personality owned;
    std::vector<df::personality_needst> needs;needs.reserve(source.needs.size());
    for(const auto* need:source.needs) {
        if(!need)return std::nullopt;
        needs.push_back(*need);
    }
    for(auto& need:needs)owned.needs.push_back(&need);
    owned.flags=source.flags;
    owned.current_focus=source.current_focus;owned.undistracted_focus=source.undistracted_focus;
    owned.slack_end_year=source.slack_end_year;owned.slack_end_year_tick=source.slack_end_year_tick;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    return reinterpret_cast<int32_t (*)(df::unit_personality*)>(base+0x14d720)(&owned);
}
struct OverviewStatus {
    bool personality=false,needs=false,assignedSquad=false;
    std::string squad;
    std::string focus;
    int32_t focusColor=15;
};
// Native Overview166fca and16797d use these pure semantic predicates. The
// fortress predicate reads simulation globals, never menu/widget state.
inline std::optional<OverviewStatus> overviewStatus(df::unit* unit) {
    static const bool supported=[] {
        if(!df3d_production::farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        const auto hash=[&](size_t rva,size_t length) {
            uint64_t value=UINT64_C(14695981039346656037);
            for(size_t i=0;i<length;++i){value^=base[rva+i];value*=UINT64_C(1099511628211);}
            return value;
        };
        return hash(0x73710,0x4c)==UINT64_C(0xe700e2d52b0deb31) &&
               hash(0x73b50,0x13)==UINT64_C(0xa0106d5e9beb23b7) &&
               hash(0x138ed20,0xff)==UINT64_C(0x430951f9f3e403c2);
    }();
    if(!supported || !unit)return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    using Predicate=bool (*)(df::unit*);
    OverviewStatus result;
    result.personality=reinterpret_cast<Predicate>(base+0x73710)(unit);
    const bool controlled=result.personality && reinterpret_cast<Predicate>(base+0x138ed20)(unit);
    result.needs=unit->status.current_soul && reinterpret_cast<Predicate>(base+0x73b50)(unit) && controlled;
    if(result.needs) {
        const auto percent=focusPercent(unit->status.current_soul->personality);
        if(!percent)return std::nullopt;
        // Native Overview167a03..167c49 thresholds, literals and palette codes.
        if(*percent>=140){result.focus="Focused!";result.focusColor=10;}
        else if(*percent>=120){result.focus="Focused";result.focusColor=10;}
        else if(*percent<=60){result.focus="Distracted!";result.focusColor=12;}
        else if(*percent<=80){result.focus="Distracted";result.focusColor=14;}
    }
    if(controlled) {
        if(const auto* squad=df::squad::find(unit->military.squad_id)) {
            auto name=df3d_area::nativeZoneSquadName(*squad);
            if(!name)return std::nullopt;
            result.squad=*name;result.assignedSquad=true;
        } else result.squad="None"; // Native Overview167173.
    }
    return result;
}
struct HaulingSummary { int32_t itemId=-1; std::string text; };
// Overview166e81 calls this read-only inventory selector, then the same owned
// item-caption formatter used by building contents. Never invoke the enclosing
// sheet renderer14ef90: it reads and writes global UI state.
inline std::optional<HaulingSummary> haulingSummary(df::unit* unit) {
    using Select=df::item* (*)(df::unit*);
    static const auto select=[]()->Select {
        if(!df3d_production::farmFunctions())return nullptr;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x2c;++i){hash^=base[0x1324b50+i];hash*=UINT64_C(1099511628211);}
        if(hash!=UINT64_C(0xda0ae0ab2370567d))return nullptr;
        return reinterpret_cast<Select>(const_cast<uint8_t*>(base)+0x1324b50);
    }();
    static_assert(offsetof(df::unit,inventory)==0x408);
    static_assert(offsetof(df::unit_inventory_item,mode)==8);
    if(!select || !unit || unit->inventory.size()>4096)return std::nullopt;
    for(const auto* entry:unit->inventory)if(!entry || !entry->item)return std::nullopt;
    HaulingSummary result;
    if(auto* item=select(unit)) {
        auto caption=df3d_production::buildingItemCaption(item);
        if(!caption || caption->size()>500)return std::nullopt;
        result.itemId=item->id;
        result.text="Haul: "+*caption; // Native literal at renderer166ee6.
    }
    return result;
}
}
