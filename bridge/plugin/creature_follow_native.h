#pragma once
#include "building_item_native.h"

namespace df3d_creature {
// Native camera loops35e5a6/8b6a4b. Own every output; never inspect native
// follow IDs, sheets or camera globals. Invalid coordinates mean follow stops;
// nullopt means the supported semantic entry points are unavailable.
// Visibility137bd50 reads simulation mode/debug_showambush, fortress control,
// containment and map designation. Its holder resolver writes only its local
// specific_ref output; semantic reference getters may warm cached indices.
// Native unit-sheet button1422830 uses1367430 directly, without follow's
// inactive/visibility filters. This read never opens a sheet or moves a camera.
inline std::optional<df::coord> sheetPosition(df::unit* unit) {
    static const bool supported=[] {
        if(!df3d_production::farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x1367430,0xc6,UINT64_C(0xc0292be8a6dacf2c)},
            {0x137bd50,0x2d0,UINT64_C(0xdee22d5bacd12bc9)},
            {0x138ed20,0xff,UINT64_C(0x430951f9f3e403c2)},
            {0xc8be10,0x14c,UINT64_C(0x1ba19b485a3fa56b)},
            {0xc8baa0,0x11a,UINT64_C(0x2c62fce4a0555c66)},
            {0xedfa60,0xbd,UINT64_C(0x2f89116df6b958cc)},
            {0xedfb20,0x13,UINT64_C(0xa222e60f2f8301e4)},
            {0x14db50,0xb1,UINT64_C(0x4b9c987ca0656b35)},
            {0x14dc10,0x5a,UINT64_C(0xfb6e6c7bccbf765b)},
            {0x67270,6,UINT64_C(0x7dce27ae257f083d)},
            {0x7a840,6,UINT64_C(0xeff4222c8d49c252)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();
    if(!supported)return std::nullopt;
    const df::coord invalid(-30000,-30000,-30000);
    if(!unit)return invalid;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    int16_t x=-30000,y=-30000,z=-30000;
    reinterpret_cast<void (*)(df::unit*,int16_t*,int16_t*,int16_t*)>(base+0x1367430)(unit,&x,&y,&z);
    return df::coord(x,y,z);
}
inline std::optional<df::coord> followPosition(df::unit* unit) {
    const auto position=sheetPosition(unit);
    if(!position)return std::nullopt;
    const df::coord invalid(-30000,-30000,-30000);
    if(!unit || position->x==-30000 || unit->flags1.bits.inactive)return invalid;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    if(reinterpret_cast<bool (*)(df::unit*)>(base+0x137bd50)(unit))return invalid;
    return position;
}
}
