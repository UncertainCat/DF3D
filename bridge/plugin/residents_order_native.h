#pragma once
#include <algorithm>
#include <optional>
#include <vector>
#include "location_staff_order_native.h"
#include "df/world.h"
#include "df/global_objects.h"

namespace df3d_residents {
// Safe-point diagnostic provider. Native comparators receive owned tagged
// references; no native widget, callback object, or menu list is borrowed.
// Activity and text filtering require a separate owned context and are not
// silently approximated by this provider.
inline bool orderingSupported() {
    static const bool ready=[] {
        if(!df3d_area::staffOrderingFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x3d5df0,0xb6,UINT64_C(0xe02f1be2a36139d6)},
            {0x1435ed0,0x67,UINT64_C(0x5fa2b3269858314f)},
            {0x1431370,0x64,UINT64_C(0x5854757b83da8810)},
            {0x1435a10,0x110,UINT64_C(0x98ce3d80a8c10b09)},
            {0x14358c0,0x110,UINT64_C(0x7476642b05457b5b)},
            {0x14240d0,0x89,UINT64_C(0x4b41b81d7b2cdc3e)},
            {0x1425170,0x89,UINT64_C(0x86b6c3e85719b169)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();return ready;
}
inline std::optional<std::vector<int32_t>> orderedResidents(int sort,bool descending) {
    if(!df::global::world || !orderingSupported() || sort<0 || sort>3)return std::nullopt;
    using Entry=df3d_area::StaffUnitReference;
    using Excluded=bool (*)(void*,const Entry*);
    using Compare=bool (*)(void*,const Entry*,const Entry*);
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    const auto excluded=reinterpret_cast<Excluded>(const_cast<uint8_t*>(base+0x3d5df0));
    constexpr size_t comparators[]={0x1431370,0x1435a10,0x14358c0,0x1435ed0};
    const auto compare=reinterpret_cast<Compare>(const_cast<uint8_t*>(base+comparators[sort]));
    std::vector<Entry> entries;
    for(auto* unit:df::global::world->units.active) {
        if(!unit)continue;
        Entry entry{unit};
        if(!excluded(nullptr,&entry))entries.push_back(entry);
    }
    std::stable_sort(entries.begin(),entries.end(),[&](const Entry& a,const Entry& b) {
        return descending?compare(nullptr,&b,&a):compare(nullptr,&a,&b);
    });
    std::vector<int32_t> ids;ids.reserve(entries.size());
    for(const auto& entry:entries)ids.push_back(entry.unit->id);
    return ids;
}
}
