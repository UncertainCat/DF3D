#include "zone_native.h"
#include "location_value_native.h"
#include "df/world_site.h"
#include "df/abstract_building.h"
#include "df/building_civzonest.h"
#include "df/building_archerytargetst.h"
#include "df/building_doorst.h"
#include "df/world.h"
#include "df/unit.h"
#include "df/item.h"
#include "df/job.h"
#include "df/plotinfost.h"
#include "df/punishment.h"
#include "df/historical_figure.h"
#include "df/histfig_site_link.h"
#include "df/squad.h"
#include "df/squad_barracks_infost.h"
#include "df/building_squad_infost.h"
#include <algorithm>
#include <windows.h>
#include <cstdint>
#include <cstdlib>
#include <climits>
#include <cstring>
#include <unordered_map>
#include <vector>

namespace df3d_area {
namespace {
uint64_t hash(const uint8_t* bytes,size_t size) {
    uint64_t value=14695981039346656037ULL;
    while(size--){value^=*bytes++;value*=1099511628211ULL;}
    return value;
}
bool refreshOverlaps(const uint8_t* base,const df::building_civzonest* excluded=nullptr) {
    const auto& zones=df::global::world->buildings.other.ANY_ZONE;
    std::vector<bool> collisions(zones.size(),false);
    // Nativeac8490 uses map_block.path_cost as an ownership grid, with door
    // centers reserved before visiting zones in reverse order. Own that grid
    // instead: never borrow native search generations or map search scratch.
    constexpr size_t doorOwner=SIZE_MAX;
    std::unordered_map<uint64_t,size_t> owners;
    const auto key=[](int32_t x,int32_t y,int32_t z) {
        return uint64_t(uint16_t(x))|(uint64_t(uint16_t(y))<<16)|(uint64_t(uint16_t(z))<<32);
    };
    for(const auto* door:df::global::world->buildings.other.DOOR) {
        if(!door)return false;
        if(door->centerx>=0 && door->centerx<=32767 && door->centery>=0 && door->centery<=32767 && door->z>=0 && door->z<=32767)
            owners[key(door->centerx,door->centery,door->z)]=doorOwner;
    }
    for(size_t i=zones.size();i-->0;) {
        const auto* zone=zones[i];
        if(!zone)return false;
        if(zone==excluded)continue;
        const int type=int(zone->type);
        // Immutable native dispatch: eight room types participate. Other
        // zone flags are still cleared, as in native's initial all-zone pass.
        if(!zone->room.extents || type<79 || type>97 || base[0xac91ac+type-79]!=0)continue;
        const auto& room=zone->room;
        if(room.width<=0 || room.height<=0)continue;
        if(room.x<0 || room.y<0 || zone->z<0 || zone->z>32767 ||
           int64_t(room.x)+room.width>32768 || int64_t(room.y)+room.height>32768)return false;
        for(int32_t y=0;y<room.height;++y)for(int32_t x=0;x<room.width;++x) {
            if(room.extents[size_t(y)*room.width+x]==df::building_extents_type::None)continue;
            const auto tx=room.x+x,ty=room.y+y;
            // This exact false/0 call path reads semantic map/building facts
            // only. It skips the movement-search and temperature-query paths.
            if(!nativeZoneTileEligible(int16_t(tx),int16_t(ty),int16_t(zone->z)))continue;
            auto [it,inserted]=owners.emplace(key(tx,ty,zone->z),i);
            if(inserted || it->second==doorOwner)continue;
            collisions[i]=true;collisions[it->second]=true;it->second=i;
        }
    }
    // Allocation/observation failure above leaves preexisting flags intact.
    for(size_t i=0;i<zones.size();++i)zones[i]->flags.bits.room_collision=collisions[i];
    return true;
}
}
bool nativeZoneDefaultsReady() {
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    if(!base)return false;
    static const bool compatible=[&] {
        const auto* dos=reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
        if(dos->e_magic!=IMAGE_DOS_SIGNATURE || dos->e_lfanew<=0 || dos->e_lfanew>4096)return false;
        const auto* pe=reinterpret_cast<const IMAGE_NT_HEADERS64*>(base+dos->e_lfanew);
        return pe->Signature==IMAGE_NT_SIGNATURE && pe->FileHeader.Machine==0x8664 &&
            pe->FileHeader.TimeDateStamp==0x6a70a6d9 && pe->OptionalHeader.SizeOfImage==0x2711000 &&
            hash(base+0x30f550,0x5b)==0xed4d0c73606384a4ULL &&
            hash(base+0x3579af,0x80)==0xd862207edcc7f2bbULL &&
            hash(base+0x357a2f,0x461)==0x6df7802f8dfd9811ULL &&
            hash(base+0x5587b0,0x79)==0x14b4f3f138690067ULL;
    }();
    return compatible;
}
bool nativeZoneDefaults(df::building_civzonest& zone) {
    if(!nativeZoneDefaultsReady())return false;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    // DF53.16 creation calls this leaf at356f16/357765. All branches write
    // only the supplied type and settings union; no globals, calls or scratch.
    using Initialize=void (*)(df::building_civzonest*,df::civzone_type);
    reinterpret_cast<Initialize>(base+0x30f550)(&zone,zone.type);
    // These two post-creation effects are inline at3579e7..357a2a.
    // Pond's check_occupants bit is distinct from its user-facing fill mode.
    if(zone.type==df::civzone_type::Pen)zone.zone_settings.pen.flags.bits.check_occupants=true;
    if(zone.type==df::civzone_type::Pond)zone.zone_settings.pond.flag.bits.check_occupants=true;
    if(zone.type==df::civzone_type::ArcheryRange) {
        if(!df::global::world || !zone.room.extents || zone.x1<0 || zone.y1<0 || zone.z<0 ||
           zone.x2<zone.x1 || zone.y2<zone.y1 || zone.x2>32767 || zone.y2>32767 || zone.z>32767 ||
           int64_t(zone.x2-zone.x1+1)*(zone.y2-zone.y1+1)>32768)return false;
        // Native357a2f..357e90 has no independent direction entry point.
        // Its inclusion tests call5587b0 with the actual zone; that leaf reads
        // only supplied bounds/extents. Do not substitute usable-tile counts.
        using Contains=bool (*)(df::building*,int16_t,int16_t,int16_t);
        const auto contains=reinterpret_cast<Contains>(base+0x5587b0);
        int64_t cells=0,cellX=0,cellY=0,targets=0,targetX=0,targetY=0;
        for(int32_t x=zone.x1;x<=zone.x2;++x)for(int32_t y=zone.y1;y<=zone.y2;++y) {
            if(!contains(&zone,int16_t(x),int16_t(y),int16_t(zone.z)))continue;
            ++cells;cellX+=x;cellY+=y;
        }
        for(const auto* target:df::global::world->buildings.other.ARCHERY_TARGET) {
            if(!target)return false;
            if(!contains(&zone,int16_t(target->centerx),int16_t(target->centery),int16_t(target->z)))continue;
            ++targets;targetX+=target->centerx;targetY+=target->centery;
            if(targets>INT32_MAX || targetX>INT32_MAX || targetY>INT32_MAX)return false;
        }
        // No targets retains DF's initializer default. Native truncates each
        // mean before comparing, resolves axis ties toward X, and center ties
        // toward negative X. These are observed native choices, not UX policy.
        if(cells && targets) {
            const auto dx=cellX/cells-targetX/targets,dy=cellY/cells-targetY/targets;
            auto& range=zone.zone_settings.archery;
            if(std::abs(dx)>=std::abs(dy)){range.dir_x=dx<0?1:-1;range.dir_y=0;}
            else {range.dir_x=0;range.dir_y=dy<0?1:-1;}
        }
    }
    return true;
}
bool nativeZoneCreateReady() {
    if(!nativeZoneDefaultsReady())return false;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    static const bool compatible=
        hash(base+0x28b650,0x23)==0x1bc97f28bb55040dULL &&
        hash(base+0x28b710,0xb2)==0x0a9c60d382679201ULL &&
        hash(base+0x54bb60,0x110)==0xad02785ff295fa9bULL &&
        hash(base+0x577040,0x3500)==0x758911d1932d14dbULL &&
        hash(base+0x57fc70,0xcb)==0x9c1f8dc48a9760b0ULL &&
        hash(base+0x558550,0x13b)==0x60e1b99a5ab1f65dULL &&
        hash(base+0x558690,0x111)==0x36b85ab14744745bULL &&
        hash(base+0x558830,0xfa)==0xc5a7534fb1c71db4ULL &&
        hash(base+0xac8490,0xd2f)==0x25176e90bd30f8cfULL &&
        hash(base+0x14adea0,0xcb4)==0x1818a722f3967dcbULL &&
        hash(base+0x5a8390,0x230)==0xabed683b2febe641ULL &&
        hash(base+0x359718,0xc5)==0x8d6f08d35500c848ULL &&
        hash(base+0x67e80,0x10)==0x7580a2b541177a3aULL &&
        hash(base+0x6ff00,0xa8)==0x95c810961f82c229ULL &&
        locationRefreshFunction()!=nullptr;
    return compatible;
}
bool nativeZoneTileEligible(int16_t x,int16_t y,int16_t z) {
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    using Eligible=bool (*)(df::world*,int16_t,int16_t,int16_t,bool,uint32_t);
    return reinterpret_cast<Eligible>(base+0x14adea0)(df::global::world,x,y,z,false,0);
}
bool nativeZoneMultiReady() {
    if(!nativeZoneCreateReady())return false;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    static const bool compatible=hash(base+0x356ee8,0x3f1)==0xe4ddd80a024ca99ULL &&
          hash(base+0x355c53,0x1d0)==0xcda8023a0a668bcfULL;
    return compatible;
}
bool nativeZoneCompleteMulti(df::building_civzonest& zone) {
    if(!df::global::world || !nativeZoneMultiReady())return false;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    using Complete=void (*)(df::building*,bool);
    using Relationships=void (*)(df::building*);
    // Native35710b..35716c: no per-room overlap calculation here.
    reinterpret_cast<Complete>(base+0x577040)(&zone,true);
    zone.categorize(true);
    reinterpret_cast<Relationships>(base+0x558550)(&zone);
    reinterpret_cast<Relationships>(base+0x558690)(&zone);
    reinterpret_cast<Relationships>(base+0x558830)(&zone);
    // Native35716d..3572b9 counts the actual contained furniture after
    // categorization. Do not select Dormitory from a presentation prediction.
    if(zone.type==df::civzone_type::Bedroom) {
        size_t beds=0;
        for(auto* member:zone.contained_buildings) {
            if(!member)return false;
            if(member->getType()==df::building_type::Bed)++beds;
        }
        if(beds>=2)zone.type=df::civzone_type::Dormitory;
    }
    return true;
}
bool nativeZoneRefreshOverlaps() {
    if(!df::global::world || !nativeZoneMultiReady())return false;
    return refreshOverlaps(reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr)));
}
df::building_civzonest* nativeZoneAllocate() {
    if(!df::global::world || !nativeZoneCreateReady())return nullptr;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    using Allocate=df::building_civzonest* (*)();
    return reinterpret_cast<Allocate>(base+0x28b650)();
}
bool nativeZoneComplete(df::building_civzonest& zone) {
    if(!df::global::world || !nativeZoneCreateReady())return false;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    using Complete=void (*)(df::building*,bool);
    // Native357948..3579a4: completion, categorization, relationship refresh.
    // The relationship routines use semantic world lists and supplied extents.
    // In particular558830 tests candidate x1/y1, not the DFHack center heuristic.
    reinterpret_cast<Complete>(base+0x577040)(&zone,true);
    zone.categorize(true);
    return nativeZoneRefresh(zone);
}
bool nativeZoneRemoveReady() {
    if(!nativeZoneCreateReady())return false;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    static const bool compatible=
        hash(base+0x34cb5f,0xf9)==0x87ac923b4a09daddULL &&
        hash(base+0x587d80,0xc98)==0x0f7410a976032a15ULL &&
        hash(base+0x5874f0,0x335)==0x5897323f436cb82fULL &&
        hash(base+0x586ac0,0x205)==0x963ec0e2ff50cf12ULL &&
        hash(base+0xcb1420,0xe2)==0x5d444e44fe3e3f89ULL &&
        hash(base+0x13969f0,0xde)==0xc1ab930415137e8fULL &&
        hash(base+0xd09860,0xe4)==0xfcb5fa4617e93dbbULL &&
        hash(base+0xb98640,0x3a5)==0x724b201c98c64573ULL &&
        hash(base+0x7db20,0xb6)==0x4ee4244d4f7af0aeULL &&
        hash(base+0x6ff00,0xa8)==0x95c810961f82c229ULL &&
        hash(base+0x5a78e0,0xce)==0x3d9bdaeb35702e06ULL &&
        hash(base+0x582e00,0xbb)==0x33e9a77fb397d8eaULL &&
        hash(base+0x28b7d0,0x18e)==0x94d00db7f2604223ULL &&
        hash(base+0x583430,0x216)==0x8b65477dae955283ULL;
    return compatible;
}
bool nativeZoneRemove(df::building_civzonest& zone,ZoneRemovalKind kind) {
    if(!df::global::world || !df::global::plotinfo || !nativeZoneRemoveReady())return false;
    if(zone.flags.bits.almost_deleted)return true;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    const int32_t id=zone.id;
    zone.flags.bits.almost_deleted=true;
    // Zone-specific branch of587d80. The generic entry calls removeUses,
    // whose overlap calculation borrows global pathfinding scratch. Keep
    // the independent semantic cleanup calls and own the inline orchestration.
    using Mark=void (*)(df::building*,bool);
    reinterpret_cast<Mark>(base+0x586ac0)(&zone,true);
    using Relationships=void (*)(df::building*);
    reinterpret_cast<Relationships>(base+0x558690)(&zone);
    using ItemRef=bool (*)(df::item*,int32_t,int32_t);
    for(const auto itemId:zone.assigned_items)
        if(auto* item=df::item::find(itemId))
            reinterpret_cast<ItemRef>(base+0xcb1420)(item,31,id);
    using UnitRef=bool (*)(df::unit*,int32_t,int32_t);
    for(const auto unitId:zone.assigned_units)
        if(auto* unit=df::unit::find(unitId))
            reinterpret_cast<UnitRef>(base+0x13969f0)(unit,0,id);
    using SiteLink=void (*)(df::historical_figure*,int32_t,bool);
    for(const auto hfId:zone.home_general_hf)if(auto* hf=df::historical_figure::find(hfId)) {
        for(size_t i=hf->site_links.size();i-->0;) {
            auto* link=hf->site_links[i];
            if(link && int(link->getType())==7 &&
               (zone.site_id==-1 || link->site==zone.site_id) &&
               (id==-1 || link->sub_id==id))
                reinterpret_cast<SiteLink>(base+0xb98640)(hf,int32_t(i),false);
        }
    }
    zone.home_general_hf.clear();
    reinterpret_cast<Relationships>(base+0x558550)(&zone);
    // Retain DFHack's reciprocal squad cleanup. Native destruction frees
    // zone-side records but does not remove squad.rooms. Native destruction
    // itself now handles all unit.owned_buildings pointers (including duplicates).
    for(auto* info:zone.squad_room_info)if(info) {
        if(auto* squad=df::squad::find(info->squad_id))
            for(size_t i=squad->rooms.size();i-->0;)
                if(squad->rooms[i] && squad->rooms[i]->building_id==id) {
                    auto* room=squad->rooms[i];
                    squad->rooms.erase(squad->rooms.begin()+i);
                    delete room;
                }
    }
    for(auto* unit:df::global::world->units.active)
        if(unit && unit->job.destroy_target==&zone)unit->job.destroy_target=nullptr;
    auto& taxRooms=df::global::plotinfo->tax_collection.rooms;
    taxRooms.erase(std::remove(taxRooms.begin(),taxRooms.end(),id),taxRooms.end());
    for(auto* punishment:df::global::plotinfo->punishments)
        if(punishment && punishment->chain==id)punishment->chain=-1;
    using JobRef=bool (*)(df::job*,int32_t,int32_t);
    for(auto* job:df::global::world->jobs.list)
        if(job && (job->flags.bits.dessource || job->flags.bits.special))
            reinterpret_cast<JobRef>(base+0xd09860)(job,36,id);
    // All remaining furniture/map branches of587d80 are inapplicable to a
    // civzone. Preserve its deferred-retirement contract during building update.
    // Refresh before retirement with an excluded identity, never a freed pointer.
    // Native Multi Undo34cb5f..34cc58 calls587d80 for each history entry
    // and exits without a final overlap refresh. Preserve that timing using
    // owned scratch; do not silently substitute ordinary-panel behavior.
    const bool overlapOk=refreshOverlaps(base,kind==ZoneRemovalKind::MultiUndo?nullptr:&zone);
    if(!zone.flags.bits.in_update) {
        using Retire=void (*)(df::building*);
        reinterpret_cast<Retire>(base+0x5a78e0)(&zone);
    }
    return overlapOk;
}
bool nativeZoneRefresh(df::building_civzonest& zone) {
    if(!df::global::world || !nativeZoneCreateReady())return false;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    using Relationships=void (*)(df::building*);
    // Native repaint35857e..35859d,358a23..358a42,35953c..35955b and
    //3596f3..359712 use the same semantic sequence after changing extents.
    reinterpret_cast<Relationships>(base+0x558550)(&zone);
    reinterpret_cast<Relationships>(base+0x558690)(&zone);
    reinterpret_cast<Relationships>(base+0x558830)(&zone);
    if(!refreshOverlaps(base))return false;
    // Native359718..3597dd (also3585a3,358a48,359561): a repaint
    // refreshes its current site's Location contents after membership changes.
    // Resolve the semantic site identity, never the native selected-zone state.
    if(zone.location_id!=-1 && df::global::plotinfo && zone.site_id==df::global::plotinfo->site_id) {
        if(auto* site=df::world_site::find(zone.site_id)) {
            using Find=df::abstract_building* (*)(df::world_site*,int32_t);
            if(auto* location=reinterpret_cast<Find>(base+0x67e80)(site,zone.location_id)) {
                if(auto* contents=location->getContents()) {
                    locationRefreshFunction()(contents,location->id,true);
                    contents->update_timer=100;contents->update_count=0;
                }
            }
        }
    }
    return true;
}
}

namespace df3d_area {
std::optional<std::string> nativeZoneName(const df::building_civzonest& zone) {
    if(!nativeZoneDefaultsReady())return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    static const bool compatible=
        hash(base+0x3e82ac,0x687)==0x9e602a58bae0d0c3ULL &&
        hash(base+0x3fd14c,0x93)==0x21149f62e643e75fULL &&
        hash(base+0x1601700,0x400)==0xf275b232f4ad58e1ULL;
    if(!compatible)return std::nullopt;
    if(!zone.name.empty())return zone.name;
    // Native3e82ac..3e8933 renders the choice inline. No independent semantic
    // callable exists here. Read its immutable dispatch and string operands;
    // never call the render function or consult its current-zone pointer.
    uint32_t branch=0x3e88fc;
    const int type=int(zone.type);
    if(type>=79 && type<=97)std::memcpy(&branch,base+0x3fd14c+(type-79)*4,4);
    if(branch==0x3e83f6) {
        size_t counts[4]={};
        for(auto* member:zone.contained_buildings) {
            if(!member)return std::nullopt;
            const int furniture=int(member->getType());
            if(furniture<3 || furniture>53)continue;
            const auto group=base[0x3fd1ac+furniture-3];
            if(group<4)++counts[group];
        }
        // Memorial wins outright. Sculpture must beat both zoo and display;
        // otherwise zoo must beat display. Ties therefore resolve as native.
        branch=counts[0]?0x3e84dd:
            counts[1]>counts[2] && counts[1]>counts[3]?0x3e852b:
            counts[2]>counts[3]?0x3e8574:counts[3]?0x3e85bc:0x3e8600;
    }
    if(branch<0x3e82d4 || branch>0x3e88fc || base[branch]!=0x48 ||
        base[branch+1]!=0x8d || base[branch+2]!=0x15)return std::nullopt;
    int32_t displacement=0;std::memcpy(&displacement,base+branch+3,4);
    const int64_t text=int64_t(branch)+7+displacement;
    if(text<0x1601700 || text>=0x1601b00)return std::nullopt;
    const auto* value=reinterpret_cast<const char*>(base+text);
    const auto* end=static_cast<const char*>(std::memchr(value,0,size_t(0x1601b00-text)));
    if(!end)return std::nullopt;
    return std::string(value,end);
}
}
