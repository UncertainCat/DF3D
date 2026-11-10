#pragma once
#include "df/buildings_interfacest.h"
#include "df/building.h"
#include "df/building_civzonest.h"
#include "df/abstract_building.h"
#include "df/language_name.h"
#include "df/plotinfost.h"
#include "df/world_site.h"
#include "df/world.h"
#include "df/building_farmplotst.h"
#include "df/plant_raw.h"
#include "df/workshop_profile.h"
#include "unit_description_native.h"
#include "knowledge_detail_native.h"
#include "df/historical_figure.h"
#include "df/squad.h"
#include "df/building_squad_infost.h"
#include <array>
#include <optional>
#include <unordered_set>
#include <vector>

namespace df3d_places {
using Lists=std::array<std::vector<int32_t>,6>;
struct BuildingRow {
    int32_t id=-1;df::coord position;std::string name,subtitle,jobCaption,statusCaption;
    int32_t additionalJobs=0;
};
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
            hash(0x39e048,0x1ab)==UINT64_C(0xed6f67d3565c0cc5) &&
            hash(0x1601fc8,12)==UINT64_C(0x322fc54d5030cedf) &&
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
inline std::optional<std::string> zoneSubtitle(df::building_civzonest& zone) {
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool ready=[base]{
        const auto hash=[base](size_t rva,size_t count){uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<count;++i){h^=base[rva+i];h*=UINT64_C(1099511628211);}return h;};
        return df3d_creature::knowledgeDescriptionReady() &&
            hash(0x30ff50,0x58)==UINT64_C(0x04257022b325dad5) &&
            hash(0x39c809,0x335)==UINT64_C(0x60f6b8d4c02ea044);
    }();
    if(!ready)return std::nullopt;
    std::string text;
    // Native precedence: attached location, assigned owner, then squads.
    if(zone.site_id!=-1 && zone.location_id!=-1) {
        if(!df::world_site::find(zone.site_id))return text;
        // Native39c83e uses the current fortress site after validating site_id.
        auto* site=df::global::plotinfo->main.fortress_site;if(!site)return text;
        df::abstract_building* location=nullptr;
        for(auto* candidate:site->buildings){if(!candidate)return std::nullopt;if(candidate->id==zone.location_id){location=candidate;break;}}
        if(!location)return text;
        const auto* source=location->getName();
        if(!source || !source->has_name)return std::string(reinterpret_cast<const char*>(base+0x162b830));
        auto owned=*source;
        reinterpret_cast<void(*)(df::language_name*,std::string*,bool,bool)>(base+0xa946e0)(&owned,&text,true,false);
    } else if(zone.assigned_unit_id!=-1) {
        // Do not pass zone.owner_unit_cached_index to native14db50. Unit lookup
        // is read-only, while the formatter receives independently owned data.
        if(auto* owner=df::unit::find(zone.assigned_unit_id)) {
            if(owner->inventory.size()>10000)return std::nullopt;
            for(auto* item:owner->inventory)if(!item)return std::nullopt;
            df3d_creature::InventoryRandomRestore restore(base);
            df3d_creature::InventoryDescriptionContext owned(*owner);
            reinterpret_cast<void(*)(df::unit*,std::string*,bool)>(base+0x1330c30)(owned.unit(),&text,false);
        } else {
            // Read-only native reverse lookup by historical figure's unit ID.
            auto* figure=reinterpret_cast<df::historical_figure*(*)(void*,int32_t)>(base+0x30ff50)(base+0x24f9cb8,zone.assigned_unit_id);
            if(figure) {
                df3d_creature::InventoryRandomRestore random(base);
                df3d_creature::KnowledgeMaterialCacheRestore cache(df::global::world->raws.creatures.hist_fig_to_creature_map);
                alignas(8) std::array<uint8_t,0xc8> context{};
                reinterpret_cast<void(*)(void*)>(base+0x72080)(context.data());
                using Name=void(*)(void*,std::string*,int32_t,void*,int16_t,int16_t);
                reinterpret_cast<Name>(base+0xb92f10)(base+0x24f9cb8,&text,figure->id,context.data(),1,1);
            }
        }
    } else if(zone.squad_room_info.size()>1) {
        if(zone.squad_room_info.size()>1048576)return std::nullopt;
        reinterpret_cast<void(*)(int32_t,std::string*)>(base+0x52c130)(int32_t(zone.squad_room_info.size()),&text);
        text+=reinterpret_cast<const char*>(base+0x162b788);
    } else if(zone.squad_room_info.size()==1) {
        if(!zone.squad_room_info.front())return std::nullopt;
        if(auto* squad=df::squad::find(zone.squad_room_info.front()->squad_id)) {
            // Native uses the translated name here, not the squad alias.
            auto owned=squad->name;
            reinterpret_cast<void(*)(df::language_name*,std::string*,bool,bool)>(base+0xa946e0)(&owned,&text,true,false);
            reinterpret_cast<void(*)(std::string*)>(base+0x52d650)(&text);
            text+=reinterpret_cast<const char*>(base+0x162b778);
        }
    }
    return text;
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
        auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
        if(mode==0) {
            auto* zone=virtual_cast<df::building_civzonest>(building);if(!zone)return std::nullopt;
            auto subtitle=zoneSubtitle(*zone);if(!subtitle)return std::nullopt;row.subtitle=std::move(*subtitle);
        } else if(mode==3) {
            if(!df3d_creature::inventoryDescriptionReady())return std::nullopt;
            // Native39de95 selects only the first permitted worker, if present.
            if(auto* profile=building->getWorkshopProfile();profile && !profile->permitted_workers.empty()) {
                if(auto* worker=df::unit::find(profile->permitted_workers.front())) {
                    if(worker->inventory.size()>10000)return std::nullopt;
                    for(auto* entry:worker->inventory)if(!entry)return std::nullopt;
                    df3d_creature::InventoryRandomRestore restore(base);
                    df3d_creature::InventoryDescriptionContext owned(*worker);
                    reinterpret_cast<void(*)(df::unit*,std::string*,bool)>(base+0x1330c30)(owned.unit(),&row.subtitle,false);
                }
            }
            // Native39df6c uses the first queued job, including suspended jobs.
            static const bool jobPinned=[base]{uint64_t hash=UINT64_C(14695981039346656037);
                for(size_t i=0;i<0x12b;++i){hash^=base[0xd03170+i];hash*=UINT64_C(1099511628211);}
                return hash==UINT64_C(0x90da46373e49508e);}();
            if(!jobPinned || building->jobs.size()>1048576)return std::nullopt;
            if(!building->jobs.empty()) {
                if(!building->jobs.front())return std::nullopt;
                reinterpret_cast<void(*)(df::job*,std::string*)>(base+0xd03170)(building->jobs.front(),&row.jobCaption);
                row.additionalJobs=int32_t(building->jobs.size()-1);
            }
        } else if(mode==4) {
            // Native39e048..39e1ee reads the selected seasonal crop, not a
            // reconstructed eligibility list. Capitalization is inline in DF.
            auto* farm=virtual_cast<df::building_farmplotst>(building);
            if(!farm || !df::global::cur_season || unsigned(*df::global::cur_season)>3)return std::nullopt;
            const int crop=farm->plant_id[*df::global::cur_season];
            if(crop==-1)row.statusCaption=std::string(reinterpret_cast<const char*>(base+0x1601fc8),12);
            else if(crop>=0 && size_t(crop)<df::global::world->raws.plants.all.size()) {
                auto* plant=df::global::world->raws.plants.all[crop];if(!plant)return std::nullopt;
                row.subtitle=plant->name;
                if(!row.subtitle.empty() && row.subtitle[0]>='a' && row.subtitle[0]<='z')row.subtitle[0]-=32;
            }
        }
        if(row.name.size()>16384)return std::nullopt;
        if(row.subtitle.size()>16384 || row.jobCaption.size()>16384)return std::nullopt;
        result[mode].push_back(std::move(row));
    }
    return result;
}
}
