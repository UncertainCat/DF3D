#pragma once
#include "df/buildings_interfacest.h"
#include "df/building.h"
#include "df/building_civzonest.h"
#include "df/abstract_building.h"
#include "df/language_name.h"
#include "df/plotinfost.h"
#include "df/world_site.h"
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
// Places' zone label switch is inline and differs from the zone inspector's
// furniture-sensitive naming. Read only pinned immutable dispatch/string data;
// never invoke the renderer or borrow its current building or output scratch.
inline std::optional<std::string> heading(df::building& building,size_t mode) {
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool pinned=[base] {
        const auto hash=[base](size_t rva,size_t length){uint64_t value=UINT64_C(14695981039346656037);
            for(size_t i=0;i<length;++i){value^=base[rva+i];value*=UINT64_C(1099511628211);}return value;};
        return hash(0x39c70c,0xf2)==UINT64_C(0x70abcfd93acd33b6) &&
            hash(0x39f0fc,0x4c)==UINT64_C(0x0e9e313b6cc4485d) &&
            hash(0x162a000,0x2000)==UINT64_C(0xe8ebf9afb96d15b8) &&
            hash(0xa946e0,0x7c2)==UINT64_C(0xdbc3db5f052419ee);
    }();
    if(!pinned)return std::nullopt;
    std::string result;
    if(mode>=2){building.getName(&result);return result;}
    auto* zone=virtual_cast<df::building_civzonest>(&building);if(!zone)return std::nullopt;
    if(mode==0) {
        if(!zone->name.empty())return zone->name;
        const int type=int(zone->type);if(type<79 || type>97)return result;
        uint32_t branch=0;std::memcpy(&branch,base+0x39f0fc+(type-79)*4,4);
        if(branch==0x39c7f7)return result;
        if(branch<0x39c742 || branch>0x39c7e4 || base[branch]!=0x48 || base[branch+1]!=0x8d || base[branch+2]!=0x15)return std::nullopt;
        int32_t displacement=0;std::memcpy(&displacement,base+branch+3,4);
        const int64_t address=int64_t(branch)+7+displacement;
        if(address<0x162a000 || address>=0x162c000)return std::nullopt;
        const auto* begin=reinterpret_cast<const char*>(base+address);
        const auto* end=static_cast<const char*>(std::memchr(begin,0,size_t(0x162c000-address)));
        if(!end)return std::nullopt;return std::string(begin,end);
    }
    // Renderer39d1f9 reads this simulation site, not a Places selection.
    if(!df::global::plotinfo || reinterpret_cast<uint8_t*>(&df::global::plotinfo->main.fortress_site)!=base+0x239a1f0)return std::nullopt;
    auto* site=df::global::plotinfo->main.fortress_site;if(!site)return std::nullopt;
    df::abstract_building* location=nullptr;
    for(auto* entry:site->buildings){if(!entry)return std::nullopt;if(entry->id==zone->location_id){location=entry;break;}}
    if(!location)return std::string(reinterpret_cast<const char*>(base+0x162bd58));
    const auto* name=location->getName();
    if(!name || !name->has_name)return std::string(reinterpret_cast<const char*>(base+0x162b830));
    auto owned=*name;
    // Native39d247: English name, supplied name and output are privately owned.
    reinterpret_cast<void(*)(df::language_name*,std::string*,bool,bool)>(base+0xa946e0)(&owned,&result,true,false);
    return result;
}
// Native Places39dba6/39de70/39e029/39e4a5 use building::getName for
// Stockpiles, Workshops, Farm plots and Siege engines.
inline std::optional<BuildingRows> buildingRows() {
    const auto ids=lists();if(!ids)return std::nullopt;
    BuildingRows result;
    for(size_t mode=0;mode<ids->size();++mode)for(auto id:(*ids)[mode]) {
        auto* building=df::building::find(id);if(!building)return std::nullopt;
        BuildingRow row;row.id=id;row.position=df::coord(building->centerx,building->centery,building->z);
        const auto name=heading(*building,mode);if(!name)return std::nullopt;row.name=*name;
        if(row.name.size()>16384)return std::nullopt;
        result[mode].push_back(std::move(row));
    }
    return result;
}
}
