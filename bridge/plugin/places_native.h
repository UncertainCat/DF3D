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
#include "df/abstract_building_templest.h"
#include "df/abstract_building_guildhallst.h"
#include "df/historical_entity.h"
#include "df/occupation.h"
#include "df/buildingitemst.h"
#include "df/map_block.h"
#include "modules/Maps.h"
#include "building_item_native.h"
#include "df/building_chainst.h"
#include "df/building_siegeenginest.h"
#include "creature_follow_native.h"
#include <array>
#include <optional>
#include <unordered_set>
#include <vector>

namespace df3d_places {
using Lists=std::array<std::vector<int32_t>,6>;
struct BuildingRow {
    int32_t id=-1;df::coord position;std::string name,subtitle,jobCaption,statusCaption,secondaryStatus,statusOverlay;
    int32_t additionalJobs=0,siegeAction=-1;
    std::string operatorCaption;
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
inline bool locationDetails(df::building_civzonest& zone,BuildingRow& row) {
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool ready=[base]{
        const auto hash=[base](size_t rva,size_t count){uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<count;++i){h^=base[rva+i];h*=UINT64_C(1099511628211);}return h;};
        return df3d_creature::knowledgeDescriptionReady() &&
            hash(0x39d32a,0x52d)==UINT64_C(0x064d3ad96b0c0caf) &&
            hash(0x132e0c0,0x368)==UINT64_C(0x5020a6b8e463a24d) &&
            hash(0x132cc10,0x14a4)==UINT64_C(0x32cb3990ee45026b) &&
            hash(0x52c2b0,0xd8)==UINT64_C(0x38b6489e35387929) &&
            hash(0x15eb518,5)==UINT64_C(0x39ead4ecd4054252) &&
            hash(0x15ed5b4,5)==UINT64_C(0x56a7d5c347508a2a);
    }();
    if(!ready || !df::global::plotinfo->main.fortress_site)return false;
    df::abstract_building* location=nullptr;
    for(auto* entry:df::global::plotinfo->main.fortress_site->buildings){if(!entry)return false;if(entry->id==zone.location_id){location=entry;break;}}
    if(!location)return true;
    const auto literal=[base](size_t rva){return reinterpret_cast<const char*>(base+rva);};
    const auto translated=[base](const df::language_name& name,bool capitalize){
        auto owned=name;std::string text;
        reinterpret_cast<void(*)(df::language_name*,std::string*,bool,bool)>(base+0xa946e0)(&owned,&text,true,false);
        if(capitalize)reinterpret_cast<void(*)(std::string*)>(base+0x52d650)(&text);return text;
    };
    switch(int(location->getType())) {
    case 8:row.subtitle=literal(0x162b7c8);break;
    case 9:row.subtitle=literal(0x162b7c0);break;
    case 13:row.subtitle=literal(0x162bd38);break;
    case 11: {
        auto* guild=virtual_cast<df::abstract_building_guildhallst>(location);if(!guild)return false;
        const auto& contents=guild->contents;
        using Profession=bool(*)(std::string*,int16_t,int16_t,int16_t,bool,bool,int16_t);
        const auto race=df::global::plotinfo->race_id;
        // Explicit default race avoids the formatter's -2 UI-mode fallback.
        // Renderer guild/member scans before this call do not feed its output.
        reinterpret_cast<Profession>(base+0x132e0c0)(&row.subtitle,int16_t(contents.profession),race,-1,true,true,race);
        const size_t suffix[]={0x162bce0,0x162bd18,0x162bd00};
        if(contents.location_tier>=0 && contents.location_tier<=2)row.subtitle+=literal(suffix[contents.location_tier]);
        break;
    }
    case 2: {
        auto* temple=virtual_cast<df::abstract_building_templest>(location);if(!temple)return false;
        const auto tier=temple->contents.location_tier;const size_t labels[]={0x162b7d8,0x162b7d0,0x162bcf0};
        if(tier>=0 && tier<=2)row.subtitle=literal(labels[tier]);
        if(int(temple->deity_type)==1) {
            if(auto* religion=df::historical_entity::find(temple->deity_data.practice_id))row.subtitle+=std::string(literal(0x15eb518))+translated(religion->name,true);
        } else if(int(temple->deity_type)==0) {
            if(auto* deity=df::historical_figure::find(temple->deity_data.practice_id))row.subtitle+=std::string(literal(tier==0?0x15ed5b4:0x15eb518))+translated(deity->name,false);
        }
        break;
    }
    default:break;
    }
    // Native39d4eb counts occupied slots only when their unit resolves in all.
    if(location->occupations.size()>1048576)return false;
    int32_t assigned=0;
    for(auto* slot:location->occupations){if(!slot)return false;if(slot->unit_id!=-1 && df::unit::find(slot->unit_id))++assigned;}
    if(assigned>0) {
        reinterpret_cast<void(*)(int32_t,std::string*)>(base+0x52c2b0)(assigned,&row.statusCaption);
        row.statusCaption+=literal(0x162b778);
    }
    return true;
}
inline bool countStatusReady() {
    static const bool ready=[] {
        auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
        const auto hash=[base](size_t rva,size_t count){uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<count;++i){h^=base[rva+i];h*=UINT64_C(1099511628211);}return h;};
        return hash(0x39dbc9,0x1a6)==UINT64_C(0x98470b9a922b03c1) &&
            hash(0x39e1fe,0x64)==UINT64_C(0x2b001eaec2a55cc6) &&
            hash(0x39df83,0x94)==UINT64_C(0x51710cd3b9de4e48) &&
            hash(0x15e9298,2)==UINT64_C(0x08d90e07b578eac6) &&
            hash(0x52c2b0,0xd8)==UINT64_C(0x38b6489e35387929);
    }();return ready;
}
inline std::string countCaption(int32_t count,size_t suffix) {
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));std::string text;
    reinterpret_cast<void(*)(int32_t,std::string*)>(base+0x52c2b0)(count,&text);
    text+=reinterpret_cast<const char*>(base+suffix);return text;
}
inline bool zoneStatus(df::building_civzonest& zone,BuildingRow& row) {
    if(int(zone.type)!=88 && int(zone.type)!=96)return true;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool pinned=[base]{
        const auto hash=[base](size_t rva,size_t count){uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<count;++i){h^=base[rva+i];h*=UINT64_C(1099511628211);}return h;};
        return hash(0x39cb3d,0x6bc)==UINT64_C(0x499a5488333ae955) &&
            hash(0x5587b0,0x79)==UINT64_C(0x14b4f3f138690067) &&
            hash(0x1615860,11)==UINT64_C(0x8517038a788c3c2a);
    }();
    if(!pinned || !countStatusReady())return false;
    int32_t first=0,second=0;
    if(int(zone.type)==88) {
        if(zone.assigned_units.size()>1048576)return false;
        for(auto id:zone.assigned_units) {
            auto* unit=df::unit::find(id);if(!unit)continue;++first;
            df::coord position=unit->pos;
            if(unit->flags1.bits.caged) {
                position=df::coord(-30000,-30000,-30000);
                for(auto* ref:unit->general_refs) {
                    if(!ref)return false;
                    if(ref->getType()!=df::general_ref_type::CONTAINED_IN_ITEM)continue;
                    if(auto* holder=ref->getItem()) {
                        const auto resolved=df3d_production::itemPosition(holder);if(!resolved)return false;
                        position=*resolved;break;
                    }
                }
            }
            if(position.x!=-30000 && reinterpret_cast<bool(*)(df::building*,int16_t,int16_t,int16_t)>(base+0x5587b0)(&zone,position.x,position.y,position.z))++second;
        }
        if(first>0){row.statusCaption=countCaption(first,0x162b778);row.secondaryStatus=countCaption(second,0x162b7b0);}
    } else {
        static_assert(offsetof(df::building_chainst,chained)==0x150);
        if(zone.contained_buildings.size()>1048576)return false;
        for(auto* building:zone.contained_buildings) {
            if(!building)return false;
            if(auto* chain=virtual_cast<df::building_chainst>(building)) {
                if(chain->chained)++first;else ++second;
            } else if(int(building->getType())==28) {
                auto* cage=virtual_cast<df::building_actual>(building);if(!cage)return false;
                int32_t contained=0;
                // Native39cbd6 inspects only the first contained cage item.
                if(!cage->contained_items.empty()) {
                    auto* entry=cage->contained_items.front();if(!entry || !entry->item)return false;
                    if(entry->item->general_refs.size()>1048576)return false;
                    for(auto* ref:entry->item->general_refs) {
                        if(!ref)return false;
                        if(ref->getType()==df::general_ref_type::CONTAINS_UNIT && ref->getUnit())++contained;
                    }
                }
                if(contained>0)first+=contained;else ++second;
            }
        }
        if(first>0 || second>0){row.statusCaption=countCaption(first,0x162b7a0);row.secondaryStatus=countCaption(second,0x1615860);}
    }
    return true;
}
inline bool stockpileStatus(df::building& building,BuildingRow& row) {
    if(!countStatusReady())return false;
    const auto& room=building.room;
    if(room.width<0 || room.height<0 || int64_t(room.width)*room.height>1048576 ||
        (room.width && room.height && !room.extents) || building.jobs.size()>1048576)return false;
    int32_t total=0,occupied=0;
    // Native39dbc9: enabled extent tiles, item occupancy OR a queued storage
    // job at the tile. No item eligibility or capacity rules are re-created.
    for(int32_t dy=0;dy<room.height;++dy)for(int32_t dx=0;dx<room.width;++dx) {
        if(!int(room.extents[dy*room.width+dx]))continue;
        ++total;const int32_t x=room.x+dx,y=room.y+dy;
        if(x<0 || y<0 || x>32767 || y>32767 || building.z<0 || building.z>32767)return false;
        bool reserved=false;
        for(auto it=building.jobs.rbegin();it!=building.jobs.rend();++it) {
            auto* job=*it;if(!job)return false;
            if(job->job_type==df::job_type::StoreItemInStockpile && job->pos==df::coord(x,y,building.z)){reserved=true;break;}
        }
        auto* block=DFHack::Maps::getTileBlock(x,y,building.z);
        if(reserved || (block && block->occupancy[x&15][y&15].bits.item))++occupied;
    }
    int32_t percentage=100;
    if(occupied<total){percentage=std::min(99,occupied*100/total);if(occupied>0 && percentage<=0)percentage=1;}
    row.statusCaption=countCaption(percentage,0x162bd48);return true;
}
inline bool farmStatus(df::building_farmplotst& farm,BuildingRow& row) {
    if(!countStatusReady() || farm.contained_items.size()>1048576)return false;
    int32_t planted=0;int64_t harvest=0;
    // Native39e1fe: seeds count individually; plants contribute stack size.
    for(auto* entry:farm.contained_items) {
        if(!entry)return false;auto* item=entry->item;
        if(!item || !item->flags.bits.in_building)continue;
        if(item->getType()==df::item_type::SEEDS)++planted;
        else if(item->getType()==df::item_type::PLANT)harvest+=item->getStackSize();
    }
    if(harvest<0 || harvest>INT32_MAX)return false;
    if(planted>0)row.statusCaption=countCaption(planted,0x162bca8);
    if(harvest>0)row.secondaryStatus=countCaption(int32_t(harvest),0x162bc98);
    return true;
}
inline bool siegeDetails(df::building_siegeenginest& siege,BuildingRow& row) {
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool ready=[base]{
        const auto hash=[base](size_t rva,size_t count){uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<count;++i){h^=base[rva+i];h*=UINT64_C(1099511628211);}return h;};
        return hash(0x39e498,0x64d)==UINT64_C(0xebe6e8a4cff4b5d4) &&
            hash(0xd09a90,0x63)==UINT64_C(0x3a4361e260fd4063);
    }();
    if(!ready || !countStatusReady() || siege.contained_items.size()>1048576)return false;
    row.siegeAction=int(siege.action);
    const auto literal=[base](size_t rva){return reinterpret_cast<const char*>(base+rva);};
    int64_t ammo=0;
    for(auto* entry:siege.contained_items) {
        if(!entry)return false;if(int(entry->use_mode)==2)continue;
        if(!entry->item)return false;
        if(int(siege.type)==2 && int(entry->item->getType())!=39)continue;
        ammo+=entry->item->getStackSize();
    }
    if(ammo<0 || ammo>INT32_MAX)return false;
    if(ammo==0)row.subtitle=std::string(literal(0x39e749),8); // Native immediate "Unloaded".
    else if(int(siege.type)!=2)row.subtitle=literal(0x162bcd8);
    else {row.subtitle=countCaption(int32_t(ammo),0x15e873c)+literal(0x162bcb4);if(ammo!=1)row.subtitle+=literal(0x15e9298);}
    if(siege.jobs.empty())return true;
    auto* job=siege.jobs.front();if(!job || job->general_refs.size()>1048576)return false;
    const int kind=int(job->job_type);
    if(kind!=246 && kind!=135 && kind!=136 && kind!=247 && kind!=137 && kind!=138)return true;
    for(auto* ref:job->general_refs)if(!ref)return false;
    // Native d09a90 returns the first matching reference's unit (no UI state).
    auto* worker=reinterpret_cast<df::unit*(*)(df::job*,int32_t)>(base+0xd09a90)(job,19);
    if(kind==246 || kind==135 || kind==136)row.operatorCaption=literal(worker?0x162bcd0:0x162bbf0);
    else if(!worker)row.operatorCaption=literal(0x162bc08);
    else {
        const auto position=df3d_creature::sheetPosition(worker);if(!position)return false;
        const bool present=std::abs(int(position->x)-siege.centerx)<=1 &&
            std::abs(int(position->y)-siege.centery)<=1 && int(position->z)==siege.z;
        row.operatorCaption=literal(present?0x162bbd8:0x162bc18);
    }
    return true;
}
inline bool hospitalStatus(df::building_civzonest& selected,BuildingRow& row) {
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool ready=[base]{
        const auto hash=[base](size_t rva,size_t count){uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<count;++i){h^=base[rva+i];h*=UINT64_C(1099511628211);}return h;};
        return hash(0x39d857,0x30d)==UINT64_C(0x6815f80ea73b75cf) &&
            hash(0x138ed20,0xff)==UINT64_C(0x430951f9f3e403c2) &&
            hash(0x5587b0,0x79)==UINT64_C(0x14b4f3f138690067) &&
            hash(0x15e9298,2)==UINT64_C(0x08d90e07b578eac6);
    }();
    if(!ready || !countStatusReady())return false;
    df::abstract_building* location=nullptr;
    for(auto* entry:df::global::plotinfo->main.fortress_site->buildings)if(entry && entry->id==selected.location_id){location=entry;break;}
    if(!location || int(location->getType())!=13)return true;
    if(df::global::world->units.active.size()>1048576)return false;
    int32_t patients=0;
    for(auto* unit:df::global::world->units.active) {
        if(!unit)return false;
        if(!unit->job.current_job || unit->job.current_job->job_type!=df::job_type::Rest)continue;
        // Native138ed20 is a leaf predicate: simulation reads only, no writes.
        if(!reinterpret_cast<bool(*)(df::unit*)>(base+0x138ed20)(unit))continue;
        df::coord position=unit->pos;
        if(unit->flags1.bits.caged) {
            position=df::coord(-30000,-30000,-30000);
            for(auto* ref:unit->general_refs) {
                if(!ref)return false;
                if(ref->getType()!=df::general_ref_type::CONTAINED_IN_ITEM)continue;
                if(auto* holder=ref->getItem()){auto resolved=df3d_production::itemPosition(holder);if(!resolved)return false;position=*resolved;break;}
            }
        }
        if(position.x==-30000)continue;
        // Native39d975 scans every zone belonging to this abstract location.
        // Its inline extent test is identical to the read-only leaf5587b0.
        for(auto* building:df::global::world->buildings.other[df::buildings_other_id::ACTIVITY_ZONE]) {
            if(!building)return false;
            if(building->site_id==location->site_id && building->location_id==location->id &&
                reinterpret_cast<bool(*)(df::building*,int16_t,int16_t,int16_t)>(base+0x5587b0)(building,position.x,position.y,position.z)){++patients;break;}
        }
    }
    // Native draws this over assigned staff on the SAME line without clearing.
    // Keep both captions so the presentation can preserve that drawing order.
    if(patients>0){row.statusOverlay=countCaption(patients,0x162bd28);if(patients!=1)row.statusOverlay+=reinterpret_cast<const char*>(base+0x15e9298);}
    return true;
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
            if(!zoneStatus(*zone,row))return std::nullopt;
        } else if(mode==1) {
            auto* zone=virtual_cast<df::building_civzonest>(building);if(!zone || !locationDetails(*zone,row))return std::nullopt;
            if(!hospitalStatus(*zone,row))return std::nullopt;
        } else if(mode==2) {
            if(!stockpileStatus(*building,row))return std::nullopt;
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
                if(row.additionalJobs>0) {
                    if(!countStatusReady())return std::nullopt;
                    row.secondaryStatus=std::string(reinterpret_cast<const char*>(base+0x162bc90))+countCaption(row.additionalJobs,0x162bc88);
                    if(row.additionalJobs!=1)row.secondaryStatus+=reinterpret_cast<const char*>(base+0x15e9298);
                }
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
            if(crop!=-1 && !farmStatus(*farm,row))return std::nullopt;
        } else if(mode==5) {
            auto* siege=virtual_cast<df::building_siegeenginest>(building);if(!siege || !siegeDetails(*siege,row))return std::nullopt;
        }
        if(row.name.size()>16384)return std::nullopt;
        if(row.subtitle.size()>16384 || row.jobCaption.size()>16384)return std::nullopt;
        result[mode].push_back(std::move(row));
    }
    return result;
}
}
