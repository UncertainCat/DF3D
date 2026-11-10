#pragma once
#include "df/buildings_interfacest.h"
#include "df/building.h"
#include "df/world.h"
#include <array>
#include <optional>
#include <unordered_set>
#include <vector>

namespace df3d_places {
using Lists=std::array<std::vector<int32_t>,6>;
struct BuildingRow {int32_t id=-1;df::coord position;std::string name;};
using BuildingRows=std::array<std::vector<BuildingRow>,6>;
// Native323a7e invokes375450 with a buildings_interfacest. The builder only
// writes that context and a local location-ID vector. Sort callbacks read zone
// subtype/name, location type, stockpile category and workshop virtual getName;
// their temporary strings are private. Never pass the native menu context.
inline std::optional<Lists> lists() {
    if(!df::global::world || df::global::world->buildings.all.size()>1048576)return std::nullopt;
    static_assert(sizeof(df::buildings_interfacest)==0xb8);
    static_assert(offsetof(df::buildings_interfacest,list)==8);
    static_assert(offsetof(df::buildings_interfacest,scrolling_position)==0x98);
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool pinned=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x375450,0x5fb,UINT64_C(0xe4828dbd4a7fe625)},
            {0x374a00,0x2d0,UINT64_C(0x86f0abc6997c9113)},
            {0x374cd0,0x160,UINT64_C(0xb7273583b7c7ddbe)},
            {0x374e30,0x460,UINT64_C(0x25149640954780da)},
            {0x375290,0x1b7,UINT64_C(0x41ec931cd3349a7b)},
        };
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}if(hash!=pin.hash)return false;}
        return true;
    }();
    if(!pinned)return std::nullopt;
    df::buildings_interfacest owned;
    reinterpret_cast<void(*)(df::buildings_interfacest*)>(base+0x375450)(&owned);
    Lists result;
    for(size_t mode=0;mode<result.size();++mode) {
        if(owned.list[mode].size()>1048576)return std::nullopt;
        std::unordered_set<int32_t> seen;
        for(const auto* building:owned.list[mode]) {
            if(!building || building->id<0 || !seen.insert(building->id).second)return std::nullopt;
            result[mode].push_back(building->id);
        }
    }
    return result;
}
// Native Places39dba6/39de70/39e029/39e4a5 use building::getName for
// Stockpiles, Workshops, Farm plots and Siege engines. Zones/Locations have
// separate composed headings; leave those unprovided until their audit lands.
inline std::optional<BuildingRows> buildingRows() {
    const auto ids=lists();if(!ids)return std::nullopt;
    BuildingRows result;
    for(size_t mode=0;mode<ids->size();++mode)for(auto id:(*ids)[mode]) {
        auto* building=df::building::find(id);if(!building)return std::nullopt;
        BuildingRow row;row.id=id;row.position=df::coord(building->centerx,building->centery,building->z);
        if(mode>=2)building->getName(&row.name);
        if(row.name.size()>16384)return std::nullopt;
        result[mode].push_back(std::move(row));
    }
    return result;
}
}
