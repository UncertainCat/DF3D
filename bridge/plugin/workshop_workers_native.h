#pragma once
#include "creature_labor_native.h"
#include "location_staff_order_native.h"

namespace df3d_production {
// Worker selector setup3a53b0 installs filter3d5f60. Its closure has no captured
// state: the second argument is an owned tagged unit reference. Only semantic
// unit/caste/occupation/fortress facts are read, never selector/widget storage.
inline std::optional<bool> workshopWorkerAllowed(df::unit* unit) {
    static const bool supported=[] {
        if(!farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        const auto hash=[&](size_t rva,size_t length) {
            uint64_t value=UINT64_C(14695981039346656037);
            for(size_t i=0;i<length;++i){value^=base[rva+i];value*=UINT64_C(1099511628211);}
            return value;
        };
        return hash(0x3d5f60,0x167)==UINT64_C(0x33702827971671a0) &&
               hash(0xb973c0,0x79)==UINT64_C(0xe30c0166fa2e4d2a);
    }();
    if(!supported)return std::nullopt;
    if(!unit)return false;
    bool allowed=false;
    // The filter contains all Labor's child/caste/office exclusions. Reuse its
    // native gate and restoration lifetime for unit/HF/office lookup caches.
    const auto labor=df3d_creature::laborEligible(unit,[&] {
        const df3d_area::StaffUnitReference reference{unit};
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        using Excluded=bool (*)(const void*,const df3d_area::StaffUnitReference*);
        allowed=!reinterpret_cast<Excluded>(base+0x3d5f60)(nullptr,&reference);
    });
    if(!labor)return std::nullopt;
    return *labor && allowed;
}

inline std::optional<std::vector<int32_t>> workshopWorkerCandidates(df::building* building) {
    if(!building || !df::global::world ||
       (building->getType()!=df::building_type::Workshop && building->getType()!=df::building_type::Furnace) ||
       !building->getWorkshopProfile())return std::nullopt;
    std::vector<int32_t> result;
    for(auto* unit:df::global::world->units.active) {
        const auto allowed=workshopWorkerAllowed(unit);if(!allowed)return std::nullopt;
        if(*allowed)result.push_back(unit->id);
    }
    return result; // Source order only; presentation sorting is a separate read.
}
}
