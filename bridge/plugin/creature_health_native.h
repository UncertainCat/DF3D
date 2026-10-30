#pragma once
#include "farm_native.h"
#include "df/unit.h"
#include "df/unit_soul.h"
#include "df/game_mode.h"
#include <optional>
#include <vector>
namespace df3d_creature {
struct HealthStatus { std::string text; int32_t color=15, flash=0; };
// Renderer164389..166742 has no aggregate semantic formatter. Port its scalar
// fortress selection only; invoke native bleeding/injury helpers, never drawing.
// flash1 alternates dark/bright each500ms; flash2 is drowning's four125ms phases.
inline std::optional<std::vector<HealthStatus>> overviewHealth(df::unit* unit) {
    if(!unit || !df::global::gamemode || *df::global::gamemode!=df::game_mode::DWARF)return std::nullopt;
    static const bool supported=[] {
        if(!df3d_production::farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x164389,0x23b9,UINT64_C(0x62030b11da9ae730)},
            {0x14d940,0xde,UINT64_C(0xa4ba33cd7bf564c6)},
            {0x13406b0,0x166,UINT64_C(0x35584320cb46fabb)},
            {0xedfb70,0x71,UINT64_C(0x54bfec341c3232fc)},
            {0x28bec0,8,UINT64_C(0xe9ac3ddf829a4b63)},
            {0x548f90,6,UINT64_C(0x8827482a6d039876)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();
    if(!supported)return std::nullopt;
    static_assert(offsetof(df::unit,counters)+offsetof(df::unit::T_counters,pain)==0x818);
    static_assert(offsetof(df::unit,counters2)+offsetof(df::unit::T_counters2,hunger_timer)==0x988);
    static_assert(offsetof(df::unit_soul,personality)+offsetof(df::unit_personality,longterm_stress)==0x3c8);
    std::vector<HealthStatus> rows;
    const auto add=[&](const char* text,int color,int flash=0) {if(rows.size()<6)rows.push_back({text,color,flash});};
    const int mood=int(unit->mood);
    if((mood<5 || mood>9) && unit->status.current_soul) {
        const auto stress=unit->status.current_soul->personality.longterm_stress;
        if(stress>=100000)add("Harrowed",13);else if(stress>=50000)add("Haggard",12);else if(stress>=20000)add("Stressed",14);
    }
    const auto& c=unit->counters;const auto& c2=unit->counters2;
    if(c2.hunger_timer>=75000)add("Starving",12);else if(c2.hunger_timer>=50000)add("Hungry",6);
    if(c2.thirst_timer>=50000)add("Dehydrated",12);else if(c2.thirst_timer>=25000)add("Thirsty",9);
    if(c2.sleepiness_timer>=150000)add("Very drowsy",12);else if(c2.sleepiness_timer>=57600)add("Drowsy",9);
    if(c.unconscious>0)add("Unconscious",15);
    else if(c2.paralysis>=100)add("Paralyzed",11);else if(c2.paralysis>=50)add("Partially paralyzed",11);else if(c2.paralysis>0)add("Sluggish",11);
    if(c.stunned>0)add("Stunned",11);else if(c.dizziness>0)add("Dizzy",11);
    else if(c2.exhaustion>=6000)add("Exhausted",14);else if(c2.exhaustion>=4000)add("Over-exerted",14);else if(c2.exhaustion>=2000)add("Tired",14);
    if(c.winded>0){if(unit->flags1.bits.drowning)add("Drowning",1,2);else add("Winded",7);}
    if(c.nausea>0)add("Nauseous",10);
    if(c.pain>=100)add("Extreme pain",14);else if(c.pain>=50)add("Pain",6);
    if(c2.numbness>0)add("Numb",3);
    if(unit->body.blood_count<(unit->body.blood_max>>2))add("Pale",5,1);
    else if(unit->body.blood_count<(unit->body.blood_max>>1))add("Faint",13);
    if(c2.fever>0)add("Fever",12);
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    using Read=int32_t(*)(df::unit*);
    if(rows.size()<6) {
        const auto bleeding=reinterpret_cast<Read>(const_cast<uint8_t*>(base+0x14d940))(unit);
        if(bleeding>=10)add("Heavy bleeding",4,1);else if(bleeding>0)add("Bleeding",12);
    }
    // Native evaluates pain twice with different colors. Preserve that ordering.
    if(c.pain>=100)add("Extreme pain",6,1);else if(c.pain>=50)add("Pain",14);
    if(c.webbed>=10)add("Webbed",15);else if(c.webbed>0)add("Partially webbed",15);
    if(rows.size()<6) {
        const auto injury=reinterpret_cast<Read>(const_cast<uint8_t*>(base+0x13406b0))(unit);
        if(injury==0)add("Seriously injured",12);else if(injury==1)add("Injured",12);
    }
    if(rows.empty())add("Healthy",15);
    return rows;
}
}
