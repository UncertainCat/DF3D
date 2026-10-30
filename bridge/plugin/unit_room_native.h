#pragma once
#include "farm_native.h"
#include "df/unit.h"
#include "df/unit_soul.h"
#include "df/unit_preference.h"

namespace df3d_room {
// Both Overview and Zone owner status use the native valuation graph. Keep
// mutable preferences private to each calculation, preserving caller order.
// Furnishing artwork can still undergo native semantic lazy initialization;
// this is not a global read-only guarantee. No native UI state is borrowed.
inline bool valuationReady() {
    static const bool supported=[] {
        if(!df3d_production::farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x134a830,0xe3,UINT64_C(0xc1f6ffa4ccd5f4ee)},
            {0x559610,0xf53,UINT64_C(0xb4aa2d070c8d24f1)},
            {0x133ee00,0x710,UINT64_C(0x375cfcfb29c559f6)},
            {0x133ec90,0x170,UINT64_C(0x83882aff6a50dc16)},
            {0x559410,0xc0,UINT64_C(0x2a4708690268841e)},
            {0x5594d0,0xa2,UINT64_C(0x62566748cd465187)},
            {0xc66c30,0x953,UINT64_C(0x5975fb4b92954e30)},
            {0xc5fbb0,0x67,UINT64_C(0xac238af7cbf2a301)},
            {0xc66650,0x5d9,UINT64_C(0x5a95a4e89d5d5bcc)},
            {0xfcdd0,0x92,UINT64_C(0x7b286f02725115ba)},
            {0xc9fbf0,0x2f4,UINT64_C(0x0fe3eeb8af2e0984)},
            {0xcaede0,0xb2,UINT64_C(0x30a9c58074719c0e)},
            {0x14d0c70,0x5cc,UINT64_C(0x93e5fad4bd72b45f)},
            {0x14add70,0x12f,UINT64_C(0x01f897b15772d540)},
            {0xcabb50,0x21e,UINT64_C(0xee57b9bc216cc548)},
            {0xcc83e0,0xe6,UINT64_C(0x153208913b9388eb)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();
    return supported;
}
class ValuationContext {
    struct OwnedUnit final:df::unit { OwnedUnit():df::unit(){} } owned;
    df::unit_soul soul;
    std::vector<df::unit_preference> preferences;
    bool valid_=false;
public:
    explicit ValuationContext(const df::unit* source) {
        owned.status.current_soul=nullptr;
        if(!source || source->owned_buildings.size()>4096)return;
        static_assert(offsetof(df::unit,owned_buildings)==0x450);
        static_assert(offsetof(df::unit,race)==0xa4);
        static_assert(offsetof(df::unit,status)+offsetof(df::unit::T_status,current_soul)==0xa98);
        static_assert(offsetof(df::unit_soul,preferences)==0x230);
        static_assert(offsetof(df::unit_preference,flags)==0x16);
        owned.race=source->race;
        owned.owned_buildings=source->owned_buildings;
        for(const auto* building:owned.owned_buildings)if(!building)return;
        owned.status.current_soul=nullptr;
        if(const auto* live=source->status.current_soul) {
            if(live->preferences.size()>4096)return;
            preferences.reserve(live->preferences.size());
            for(const auto* preference:live->preferences) {
                if(!preference)return;
                preferences.push_back(*preference);
            }
            for(auto& preference:preferences)soul.preferences.push_back(&preference);
            owned.status.current_soul=&soul;
        }
        valid_=true;
    }
    ValuationContext(const ValuationContext&)=delete;
    ValuationContext& operator=(const ValuationContext&)=delete;
    bool valid() const { return valid_; }
    df::unit* unit() { return &owned; }
};
}
