#include "zone_native.h"
#include "location_value_native.h"
#include "location_staff_order_native.h"
#include "df/world_site.h"
#include "df/abstract_building.h"
#include "df/building_civzonest.h"
#include "df/building_archerytargetst.h"
#include "df/building_doorst.h"
#include "df/building_chainst.h"
#include "df/building_cagest.h"
#include "df/buildingitemst.h"
#include "df/world.h"
#include "df/unit.h"
#include "df/unit_soul.h"
#include "df/item.h"
#include "df/item_critter.h"
#include "df/job.h"
#include "df/plotinfost.h"
#include "df/punishment.h"
#include "df/historical_figure.h"
#include "df/identity.h"
#include "df/historical_entity.h"
#include "df/entity_position.h"
#include "df/entity_position_assignment.h"
#include "df/creature_raw.h"
#include "df/caste_raw.h"
#include "df/histfig_site_link.h"
#include "df/histfig_entity_link.h"
#include "df/histfig_hf_link.h"
#include "df/unit_active_animationst.h"
#include "df/unit_inventory_item.h"
#include "df/unit_skill.h"
#include "df/material.h"
#include "df/descriptor_pattern.h"
#include "df/descriptor_color.h"
#include "df/general_ref.h"
#include "df/nemesis_record.h"
#include "df/game_mode.h"
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
#include <unordered_set>
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
bool nativeZoneAnimalAssignmentReady() {
    static_assert(offsetof(df::building_chainst,assigned)==0x148);
    static_assert(offsetof(df::building_civzonest,assigned_units)==0x120);
    static_assert(offsetof(df::item,general_refs)==0x38);
    static_assert(offsetof(df::building_civzonest,assigned_items)==0x138);
    static_assert(offsetof(df::job,general_refs)==0xb0);
    static_assert(offsetof(df::unit,general_refs)==0x1d8);
    if(!nativeZoneRemoveReady() || !nativeZoneOwnerReady())return false;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    static const bool compatible=
        hash(base+0x8bfbd0,0x113)==0x3e51e038d97579d3ULL &&
        hash(base+0x72660,0x7d)==0x2414953f9e9e9670ULL &&
        hash(base+0x3a6780,0x567)==0x8e96382099041ad4ULL &&
        hash(base+0x3ce1b0,0x36e)==0xf4022a51bef4e82fULL &&
        hash(base+0x8bfcf0,0xfc)==0x33e02893abe20204ULL &&
        hash(base+0x8bfdf0,0xe1)==0xd59a5f62e8bbe548ULL &&
        hash(base+0xa67820,0xcc)==0x506ce8a2c4eefca6ULL &&
        hash(base+0xd022c0,0x3da)==0x8ba54d16439fb188ULL &&
        hash(base+0xd02ea0,0x2c7)==0x10f4f4bafc0b5ae4ULL &&
        hash(base+0xd026a0,0x14d)==0xf2201bbca6b34feaULL &&
        hash(base+0x73a60,0x5a)==0x69958e8b9109b7abULL &&
        hash(base+0x8dc3e0,0x71)==0x1cc295c6b2f19cf1ULL &&
        hash(base+0x30d190,0x7d)==0x3fa8848647806f05ULL &&
        hash(base+0xedf070,0x9e4)==0x3a7d957c1bb23db0ULL &&
        hash(base+0x70e20,0x117)==0x09aba69f846f6c10ULL &&
        hash(base+0x71830,0x88)==0x929730bf6bcaccccULL &&
        hash(base+0xfd300,0x6)==0x16014dac0538de61ULL &&
        hash(base+0x5be920,0x4)==0x131caae42d746532ULL &&
        hash(base+0x5be930,0x4)==0x1d6faef6ff900168ULL &&
        hash(base+0x723f0,0x2b)==0x025ba84042f1157dULL;
    return compatible;
}
std::optional<std::vector<ZoneAnimalCandidate>> nativeZoneAnimalCandidates(const df::building_civzonest& zone) {
    static_assert(offsetof(df::unit,flags1)==0x110);
    static_assert(offsetof(df::unit,flags2)==0x114);
    static_assert(offsetof(df::unit,relationship_ids)==0x3bc);
    static_assert(offsetof(df::unit,uwss_add_caste_flag)==0x828);
    static_assert(offsetof(df::unit,uwss_remove_caste_flag)==0x82c);
    static_assert(offsetof(df::unit,enemy)+offsetof(df::unit::T_enemy,undead)==0xd80);
    static_assert(offsetof(df::unit,enemy)+offsetof(df::unit::T_enemy,caste_flags)==0x1278);
    static_assert(int(df::caste_raw_flags::CAN_LEARN)==58);
    if(!df::global::world || !nativeZoneOwnerCandidatesReady())return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    static const bool compatible=hash(base+0x3a5e30,0x498)==0xfebd497fb8d62a98ULL &&
        hash(base+0x3a6780,0x567)==0x8e96382099041ad4ULL;
    if(!compatible || (zone.type!=df::civzone_type::Pen && zone.type!=df::civzone_type::Pond))return std::nullopt;
    if(zone.assigned_units.size()>4096 || zone.assigned_items.size()>4096-zone.assigned_units.size())return std::nullopt;
    std::vector<ZoneAnimalCandidate> result;
    std::unordered_set<int32_t> units(zone.assigned_units.begin(),zone.assigned_units.end());
    std::unordered_set<int32_t> items(zone.assigned_items.begin(),zone.assigned_items.end());
    const auto append=[&](int32_t id,bool item,bool assigned) {
        if(result.size()>=4096)return false;
        result.push_back({id,item,assigned});return true;
    };
    // Assigned objects precede fresh admissions, even if their present state
    // would exclude them. Missing IDs are skipped, as in both native producers.
    for(auto id:zone.assigned_units)if(df::unit::find(id) && !append(id,false,true))return std::nullopt;
    for(auto id:zone.assigned_items)if(df::item::find(id) && !append(id,true,true))return std::nullopt;
    for(auto* unit:df::global::world->units.active) {
        if(!unit || unit->flags1.bits.inactive || unit->flags2.bits.locked_in_for_trading)continue;
        const bool controlled=reinterpret_cast<bool (*)(df::unit*)>(base+0x138ed20)(unit);
        if(controlled) {
            const bool learns=(unit->enemy.caste_flags.is_set(df::caste_raw_flags::CAN_LEARN) ||
                unit->uwss_add_caste_flag.bits.CAN_LEARN) && !unit->uwss_remove_caste_flag.bits.CAN_LEARN;
            if(!unit->enemy.undead && learns)continue;
        } else if(!unit->flags1.bits.caged)continue;
        // PetOwner is relationship slot0 in the pinned producer.
        if(zone.type==df::civzone_type::Pond && unit->relationship_ids[0]!=-1)continue;
        if(!units.count(unit->id) && !append(unit->id,false,false))return std::nullopt;
    }
    if(zone.type==df::civzone_type::Pond)for(auto* item:df::global::world->items.other.ANY_CRITTER)
        if(item && !items.count(item->id) && !append(item->id,true,false))return std::nullopt;
    return result;
}
std::optional<std::vector<ZoneAnimalCandidate>> nativeZoneAnimalPickerCandidates(
    const df::building_civzonest& zone,int32_t sort,bool descending,std::string query) {
    const auto& readers=staffOrderingFunctions();
    if(!readers || sort<0 || sort>3 || query.size()>128)return std::nullopt;
    auto candidates=nativeZoneAnimalCandidates(zone);if(!candidates)return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    static const bool compatible=
        hash(base+0x1435a10,0x110)==0x98ce3d80a8c10b09ULL &&
        hash(base+0x14358c0,0x110)==0x7476642b05457b5bULL &&
        hash(base+0x1431370,0x64)==0x5854757b83da8810ULL &&
        hash(base+0x14240d0,0x89)==0x4b41b81d7b2cdc3eULL &&
        hash(base+0x1425170,0x89)==0x86b6c3e85719b169ULL &&
        hash(base+0x1424c30,0x218)==0x14952fd1a693777fULL;
    if(!compatible)return std::nullopt;
    readers.normalize(&query);
    struct Ranked { ZoneAnimalCandidate candidate; std::string key; std::array<int32_t,2> category{}; };
    struct Entry { void* object; uint8_t kind; uint8_t padding[7]{}; };
    static_assert(sizeof(Entry)==16);
    std::vector<Ranked> rows;rows.reserve(candidates->size());
    for(const auto& candidate:*candidates) {
        Ranked row{candidate};std::string name;
        Entry entry{};
        if(candidate.item) {
            auto* item=df::item::find(candidate.id);if(!item)return std::nullopt;
            const auto text=nativeZoneAnimalItemText(*item);if(!text)return std::nullopt;
            name=*text;entry.object=item;entry.kind=1;
            if(sort==3)row.key=name;
        } else {
            auto* unit=df::unit::find(candidate.id);if(!unit)return std::nullopt;
            readers.name(unit,&name,false);entry.object=unit;
            if(sort==3)readers.profession(unit,&row.key,false);
        }
        if(name.size()>2048 || row.key.size()>2048)return std::nullopt;
        readers.normalize(&name);
        // Animal lists have no current-job option or secondary job search text.
        // Never consult the widget cache, and do not add numeric-ID matching.
        if(name.find(query)==std::string::npos)continue;
        if(sort==1)row.key=std::move(name);
        else if(sort==3)readers.normalize(&row.key);
        else {
            // Native item category keys contain masked pointer bits. They stay
            // within this safe-point call; only the resulting ID order escapes.
            using Category=void (*)(std::array<int32_t,2>*,const Entry*);
            reinterpret_cast<Category>(base+0x1425050)(&row.category,&entry);
        }
        rows.push_back(std::move(row));
    }
    std::stable_sort(rows.begin(),rows.end(),[&](const auto& a,const auto& b) {
        if(a.candidate.assigned!=b.candidate.assigned)return a.candidate.assigned;
        if(sort==0 || sort==2)return descending?a.category>b.category:a.category<b.category;
        const int compared=a.key.compare(b.key);
        return descending?compared>0:compared<0;
    });
    candidates->clear();for(const auto& row:rows)candidates->push_back(row.candidate);
    return candidates;
}
std::optional<std::string> nativeZoneAnimalItemText(df::item& item) {
    if(!nativeZoneOwnerCandidatesReady())return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    static const bool compatible=
        hash(base+0x1423fe0,0xe8)==0x4440bb550e8d935cULL &&
        hash(base+0xc65450,0xaba)==0x47fa672b7bbcd332ULL &&
        hash(base+0xca2a80,0x105)==0x929848fe2ea708afULL &&
        hash(base+0xca5bb0,0x1b2)==0x1cce1123abcfa32aULL &&
        hash(base+0xc653e0,0x65)==0x7440b2fdafd0606cULL &&
        hash(base+0xa94030,0x6a1)==0xd81db68b3c9b33d2ULL &&
        hash(base+0xa82c10,0x56ec)==0x66347214dfd39a0bULL &&
        hash(base+0xb9b80,0x144)==0x91ddb6c319015f9bULL;
    if(!compatible)return std::nullopt;
    const auto* table=*reinterpret_cast<const uint8_t* const*>(&item);
    if(table!=base+0x165cd68 && table!=base+0x16bbad0)return std::nullopt;
    // Widget1423fe0 uses false/-1. Its setDisplayColor and draw calls are
    // deliberately outside this semantic description call. The routine reads
    // item/raw/name facts, game mode and improvement-quality display settings.
    std::string text;
    reinterpret_cast<void (*)(df::item*,std::string*,bool,int32_t)>(base+0xc65450)(&item,&text,false,-1);
    if(text.size()>2048)return std::nullopt;
    return text;
}
bool nativeZoneItemEligible(const df::building_civzonest& zone,const df::item& item) {
    if(!df::global::world || !nativeZoneAnimalAssignmentReady())return false;
    if(zone.type!=df::civzone_type::Pen && zone.type!=df::civzone_type::Pond)return false;
    if(std::find(zone.assigned_items.begin(),zone.assigned_items.end(),item.id)!=zone.assigned_items.end())return true;
    if(zone.type!=df::civzone_type::Pond)return false;
    // Native Pond producer3a6bb3..3a6c42 appends ANY_CRITTER without further
    // filtering. Both producers first retain existing assigned items.
    const auto& items=df::global::world->items.other.ANY_CRITTER;
    return std::find(items.begin(),items.end(),&item)!=items.end();
}
bool nativeZoneAssignItem(df::building_civzonest& zone,df::item& item,bool assign) {
    if(!df::global::world || !nativeZoneAnimalAssignmentReady())return false;
    if(zone.type!=df::civzone_type::Pen && zone.type!=df::civzone_type::Pond)return false;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    struct Entry { df::item* item; uint8_t kind; uint8_t padding[7]; };
    static_assert(sizeof(Entry)==16);
    Entry entry{&item,1,{}};auto* context=&zone;
    // Item branch is semantic: cage and prior zone membership/reference cleanup,
    // followed by destination membership/reference allocation. No chain/UI path.
    reinterpret_cast<void (*)(df::building_civzonest**,Entry*,bool)>(base+0x3ce1b0)(&context,&entry,assign);
    return true;
}
bool nativeZoneAssignUnit(df::building_civzonest& zone,df::unit& unit,bool assign) {
    if(!df::global::world || !nativeZoneAnimalAssignmentReady())return false;
    if(zone.type!=df::civzone_type::Pen && zone.type!=df::civzone_type::Pond)return false;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    if(assign) {
        // Native order: cage membership, chain assignment/jobs, zone transfer.
        // The ordinary chain helper calls job deletion with BUILDING_HOLDER
        // references intact. Job detach then reads native selection/cursor.
        // Perform only that reciprocal semantic detach here. Native deletion
        // owns all remaining job effects and destruction with no holder branch.
        reinterpret_cast<void (*)(df::unit*)>(base+0x8bfcf0)(&unit);
        for(auto* chain:df::global::world->buildings.other.CHAIN) {
            if(!chain || chain->assigned!=&unit)continue;
            chain->assigned=nullptr;
            for(size_t i=chain->jobs.size();i-->0;) {
                auto* job=chain->jobs[i];
                if(!job || job->job_type!=df::job_type::ChainAnimal)continue;
                for(size_t r=job->general_refs.size();r-->0;) {
                    auto* ref=job->general_refs[r];
                    if(!ref || ref->getType()!=df::general_ref_type::BUILDING_HOLDER)continue;
                    if(auto* holder=ref->getBuilding()) {
                        auto& jobs=holder->jobs;
                        jobs.erase(std::remove(jobs.begin(),jobs.end(),job),jobs.end());
                    }
                    // Native reference destruction/erase; no UI bookkeeping.
                    reinterpret_cast<bool (*)(df::job*,int32_t,int32_t)>(base+0xd09860)(job,36,-1);
                }
                reinterpret_cast<void (*)(df::job*)>(base+0xa67820)(job);
                // Valid native holder relationships removed this entry. Avoid
                // retaining a dangling job in malformed semantic input too.
                auto& jobs=chain->jobs;
                jobs.erase(std::remove(jobs.begin(),jobs.end(),job),jobs.end());
                i=std::min(i,jobs.size());
            }
        }
    }
    struct Entry { df::unit* unit; uint8_t kind; uint8_t padding[7]; };
    static_assert(sizeof(Entry)==16);
    Entry entry{&unit,0,{}};
    auto* context=&zone;
    // Cage/chain cleanup now has no remaining assignments to visit.
    // This native routine supplies the zone-vector and reference effects.
    reinterpret_cast<void (*)(df::building_civzonest**,Entry*,bool)>(base+0x3ce1b0)(&context,&entry,assign);
    return true;
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
bool nativeZoneOwnerReady() {
    if(!nativeZoneDefaultsReady())return false;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    static const bool compatible=[](const uint8_t* base) {
        return hash(base+0x557a60,0x430)==0x3e0ce87555a6acb4ULL &&
            hash(base+0x14dc10,0x6a)==0x4236d6a46ef2b909ULL &&
            hash(base+0x28b6d0,0x25)==0x548f955775d99314ULL &&
            hash(base+0x28b700,0xb)==0x0212e826f13a713bULL &&
            hash(base+0x28b6c0,0xb)==0x05a3e126f1ce8880ULL &&
            hash(base+0x28b680,0x8)==0x4072f6cfbb0db12eULL &&
            hash(base+0xbad30,0x118)==0xea445ea01cfc50c1ULL &&
            hash(base+0x717a0,0x88)==0x1f072fdf02087d16ULL &&
            hash(base+0x707d0,0x59)==0xeaa671999c0fd514ULL;
    }(base);
    return compatible;
}
bool nativeZoneOwnerCandidatesReady() {
    static_assert(offsetof(df::plotinfost,economy_active)==0xac);
    static_assert(offsetof(df::plotinfost,civ_id)==0x2440);
    static_assert(offsetof(df::plotinfost,group_id)==0x2448);
    if(!nativeZoneOwnerReady())return false;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    static const bool compatible=[](const uint8_t* base) {
        return hash(base+0x3a6610,0x162)==0x41362e655e075244ULL &&
            hash(base+0x136e800,0x6e)==0x3faa0b26247825f2ULL &&
            hash(base+0x138ed20,0xff)==0x430951f9f3e403c2ULL &&
            hash(base+0x134bcd0,0x16b)==0x9c0b7a9a63908761ULL &&
            hash(base+0xb530b0,0xac)==0x7c6f66602bdab157ULL &&
            hash(base+0xba0a0,0xa8)==0xcf6b2a7b534d3331ULL &&
            hash(base+0xb9dc0,0xa7)==0x4d8961b901732215ULL &&
            hash(base+0xbbe40,0xad)==0x062a266340f9bf38ULL &&
            hash(base+0x671f0,0x6)==0x8a7e08d8a2d0223aULL &&
            hash(base+0x72930,0x4)==0x1d394ef6ff61ced8ULL;
    }(base);
    return compatible;
}
static std::optional<bool> zoneOwnerEligible(int32_t type,bool spouseShared,df::unit* owner,const void* zoneFacts,df::unit& candidate) {
    if(!df::global::world || !df::global::plotinfo || !nativeZoneOwnerCandidatesReady())return std::nullopt;
    struct Context {int32_t type;bool spouseShared;uint8_t padding[3];df::unit* owner;const void* zone;};
    struct Entry {df::unit* unit;uint8_t isItem;uint8_t padding[7];};
    static_assert(sizeof(Context)==24 && offsetof(Context,owner)==8 && offsetof(Context,zone)==16);
    static_assert(sizeof(Entry)==16 && offsetof(Entry,isItem)==8);
    Context context{type,spouseShared,{},owner,zoneFacts};
    Entry entry{&candidate,0,{}};
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    using Exclude=bool (*)(const Context*,const Entry*);
    // Global reads are game mode, economy activation, civilization/group IDs
    // and semantic history/entity records. No widget/menu/search state is used.
    return !reinterpret_cast<Exclude>(const_cast<uint8_t*>(base+0x3a6610))(&context,&entry);
}
std::optional<bool> nativeZoneOwnerEligible(df::building_civzonest& zone,df::unit& candidate) {
    if(!df::global::world || !df::global::plotinfo || !nativeZoneOwnerCandidatesReady())return std::nullopt;
    return zoneOwnerEligible(int32_t(zone.type),zone.canUseSpouseRoom(),
        df::unit::find(zone.assigned_unit_id),&zone,candidate);
}
std::optional<bool> nativeZoneNewOwnerEligible(int32_t type,df::unit& candidate) {
    switch(static_cast<df::civzone_type>(type)) {
        case df::civzone_type::Bedroom:case df::civzone_type::DiningHall:
        case df::civzone_type::Office:case df::civzone_type::Tomb:break;
        default:return false;
    }
    // The fully pinned predicate reads only assigned_unit_id from this pointer
    // (3a6645..3a6655); all helper calls receive the candidate, never the zone.
    // With no owner the spouse branch is unreachable. No DF object is constructed.
    static_assert(offsetof(df::building_civzonest,assigned_unit_id)==0x1a0);
    struct Facts {std::array<uint8_t,0x1a0> padding{};int32_t assigned=-1;};
    static_assert(offsetof(Facts,assigned)==0x1a0);
    const Facts facts;
    return zoneOwnerEligible(type,false,nullptr,&facts,candidate);
}
std::optional<ZoneOwnerOrderFacts> nativeZoneOwnerOrderFacts(df::building_civzonest& zone,df::unit& candidate) {
    if(!df::global::world || !df::global::plotinfo || !nativeZoneOwnerCandidatesReady())return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    static const bool compatible=
        hash(base+0x3d0440,0x55)==0x86ff43fac058fd1bULL &&
        hash(base+0x3d04d0,0xe0)==0x4769466e05837caaULL &&
        hash(base+0x134bc90,0x33)==0x2e15d1b196b9c323ULL &&
        hash(base+0x134bb20,0x166)==0x35dbd90ce33cd29eULL &&
        hash(base+0x1431370,0x64)==0x5854757b83da8810ULL &&
        hash(base+0x1435a10,0x110)==0x98ce3d80a8c10b09ULL &&
        hash(base+0x14358c0,0x110)==0x7476642b05457b5bULL &&
        hash(base+0x1435ed0,0x67)==0x5fa2b3269858314fULL &&
        hash(base+0x14240d0,0x89)==0x4b41b81d7b2cdc3eULL &&
        hash(base+0x1425170,0x89)==0x86b6c3e85719b169ULL &&
        hash(base+0xb9d50,0x69)==0x979704ba6b6743e5ULL;
    const auto& ordering=staffOrderingFunctions();
    if(!compatible || !ordering)return std::nullopt;
    struct Context {uint64_t unused;int32_t type;};
    struct Entry {df::unit* unit;uint8_t isItem;uint8_t padding[7];};
    static_assert(offsetof(Context,type)==8 && sizeof(Entry)==16);
    Context context{0,int32_t(zone.type)};Entry entry{&candidate,0,{}};
    std::array<int32_t,2> category{};StaffUnitReference reference{&candidate};
    using Partition=bool (*)(const Context*,const Entry*);
    using Priority=int32_t (*)(df::unit*,int32_t,int32_t);
    // Owned inputs only. Priority refreshes the audited semantic lookup indices;
    // category reads unit traits and creature raws. No native picker is supplied.
    const bool withoutRoom=reinterpret_cast<Partition>(base+0x3d0440)(&context,&entry);
    const int32_t priority=reinterpret_cast<Priority>(base+0x134bc90)(&candidate,
        df::global::plotinfo->civ_id,df::global::plotinfo->group_id);
    ordering.category(&category,&reference);
    ZoneOwnerOrderFacts facts{withoutRoom,priority,category[0],category[1],-200000,{},{}};
    ordering.name(&candidate,&facts.nameKey,false);ordering.normalize(&facts.nameKey);
    ordering.profession(&candidate,&facts.professionKey,false);ordering.normalize(&facts.professionKey);
    static_assert(offsetof(df::unit,status)+offsetof(decltype(df::unit::status),current_soul)==0xa98);
    static_assert(offsetof(df::unit_soul,personality)+offsetof(df::unit_personality,stress)==0x368);
    // The pinned native Stress comparator reads this semantic scalar inline;
    // its missing-soul sentinel is -200000, not a derived happiness category.
    if(candidate.status.current_soul)facts.stress=candidate.status.current_soul->personality.stress;
    return facts;
}
std::optional<std::array<uint8_t,3>> nativeZoneOwnerProfessionColor(const df::unit& candidate,int16_t profession) {
    if(!df::global::world || !staffOrderingFunctions())return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    // These native routines write graphics globals. Read their pinned immutable
    // dispatch and semantic raws instead; never execute either drawing routine.
    static const bool compatible=hash(base+0x13337a0,0x26b)==UINT64_C(0x4d6839cd6f042ed5) &&
        hash(base+0x7022c0,0xe5)==UINT64_C(0xb01a72d65e66e9a3);
    if(!compatible)return std::nullopt;
    static_assert(offsetof(df::creature_raw,color)==0x138 && offsetof(df::caste_raw,caste_color)==0x46e);
    static_assert(int(df::caste_raw_flags::HAS_COLOR)==128 && int(df::caste_raw_flags::NO_UNIT_TYPE_COLOR)==41);
    std::array<uint8_t,3> result{4,4,1};
    const auto& creatures=df::global::world->raws.creatures.all;
    const df::caste_raw* caste=nullptr;
    if(candidate.race>=0 && size_t(candidate.race)<creatures.size() && creatures[candidate.race]) {
        const auto* creature=creatures[candidate.race];
        if(candidate.caste>=0 && size_t(candidate.caste)<creature->caste.size())caste=creature->caste[candidate.caste];
        const auto& color=caste && caste->flags.is_set(df::caste_raw_flags::HAS_COLOR)?caste->caste_color:creature->color;
        result={uint8_t(color[0]),uint8_t(color[1]),uint8_t(color[2])};
        if(color[0]==color[1])result[2]=1;
    }
    if(!caste || !caste->flags.is_set(df::caste_raw_flags::NO_UNIT_TYPE_COLOR)) {
        if(profession>=0 && profession<=134) {
            const auto key=base[0x1333984+profession];
            // Values correspond to all16 pinned native branch destinations.
            // Entry15 retains the creature/caste result (including STANDARD).
            constexpr std::array<uint8_t,16> palette{7,14,15,2,8,10,9,1,6,12,5,13,3,11,4,255};
            if(key>=palette.size())return std::nullopt;
            if(palette[key]!=255)result={uint8_t(palette[key]%8),0,uint8_t(palette[key]/8)};
        }
    }
    if(result[0]==result[1] && !result[2] && result[1])result[0]=0;
    return result;
}
std::optional<ZoneOwnerColorSources> nativeZoneOwnerColorSources(df::unit& candidate) {
    if(!df::global::world || !nativeZoneOwnerCandidatesReady())return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    static const bool compatible=
        hash(base+0x13b3030,0x56)==UINT64_C(0xf9404dd6eb50e2af) &&
        hash(base+0x72570,0x98)==UINT64_C(0xa69932c0f279084a) &&
        hash(base+0xbeb780,0x114)==UINT64_C(0x2bea0cd9ba41c566) &&
        hash(base+0x1ba140,0xa8)==UINT64_C(0xdb6eb9072d509b29) &&
        hash(base+0xb973c0,0x79)==UINT64_C(0xe30c0166fa2e4d2a) &&
        hash(base+0xb98d90,0x79)==UINT64_C(0x043fd29d5a07e88a) &&
        hash(base+0x1333bc0,0xa0d)==UINT64_C(0x8d3fa1210a66c482);
    if(!compatible)return std::nullopt;
    static_assert(offsetof(df::historical_figure,entity_links)==0xe8 && offsetof(df::historical_figure,histfig_links)==0x118);
    static const bool linkTypesCompatible=[](const uint8_t* base) {
        // All entity/HF link type leaves in the supported executable's vtables.
        constexpr uint32_t leaves[]{0x66e90,0x67500,0x67540,0x67520,0x67a40,0x67a50,0x67b90,0x67530,
            0x67860,0x676d0,0x671f0,0x67270,0x67490,0x673c0,0x7b7a0,0x79ce0,0x7a270};
        const uint8_t zero[]{0x33,0xc0,0xc3};
        if(std::memcmp(base+leaves[0],zero,sizeof(zero)))return false;
        for(uint8_t i=1;i<std::size(leaves);++i) {
            const uint8_t code[]{0xb8,i,0,0,0,0xc3};
            if(std::memcmp(base+leaves[i],code,sizeof(code)))return false;
        }
        const uint8_t none[]{0xb8,0xff,0xff,0xff,0xff,0xc3};
        return std::memcmp(base+0x66e60,none,sizeof(none))==0;
    }(base);
    if(!linkTypesCompatible)return std::nullopt;
    static_assert(offsetof(df::histfig_entity_link,link_strength)==0x10 && offsetof(df::histfig_hf_link,link_strength)==0xc);
    static_assert(int(df::histfig_flags::deity)==2 && offsetof(df::historical_figure,flags)==0xc8);
    static_assert(offsetof(df::identity,profession)==0xac && offsetof(df::identity,impersonated_hf)==0x88);
    static_assert(offsetof(df::entity_position,precedence)==0x2d0 && offsetof(df::entity_position,color)==0x378);
    static_assert(offsetof(df::historical_entity,positions)+offsetof(decltype(df::historical_entity::positions),own)==0x10c0);
    static_assert(offsetof(df::historical_entity,positions)+offsetof(decltype(df::historical_entity::positions),assignments)==0x1110);
    using Identity=df::identity* (*)(df::unit*);
    using Position=df::entity_position* (*)(df::historical_figure*,int32_t,df::historical_entity**,df::entity_position_assignment**);
    using Strength=int16_t (*)(df::historical_figure*,int16_t,int32_t);
    ZoneOwnerColorSources result;
    // Native identity lookup may refresh the unit's semantic HF index. Native
    // position selection scans current position links and keeps minimum
    // precedence, preserving the first equal-priority link. Outputs are owned.
    if(auto* identity=reinterpret_cast<Identity>(base+0x13b3030)(&candidate)) {
        result.identityId=identity->id;result.identityProfession=int32_t(identity->profession);result.identityImpersonatedHistfig=identity->impersonated_hf;
    }
    if(auto* hf=df::historical_figure::find(candidate.hist_figure_id)) {
        df::historical_entity* entity=nullptr;df::entity_position_assignment* assignment=nullptr;
        if(auto* position=reinterpret_cast<Position>(base+0xbeb780)(hf,-1,&entity,&assignment)) {
            result.positionId=position->id;result.entityId=entity?entity->id:-1;result.assignmentId=assignment?assignment->id:-1;
            result.positionHasColor=position->flags.is_set(df::entity_position_flags::COLOR);result.positionColor=position->color;
        }
        // Native helpers return the first matching link's signed strength,
        // including zero; they do not search for the strongest/positive link.
        // Virtual dependencies only return the link-type enum.
        result.slaveStrength=reinterpret_cast<Strength>(base+0xb973c0)(hf,4,-1);
        result.prisonerStrength=reinterpret_cast<Strength>(base+0xb973c0)(hf,6,-1);
        result.imprisonerStrength=reinterpret_cast<Strength>(base+0xb98d90)(hf,7,-1);
        result.deityHistfigId=result.identityId>=0?result.identityImpersonatedHistfig:hf->id;
        if(const auto* displayed=df::historical_figure::find(result.deityHistfigId))
            result.deity=displayed->flags.is_set(df::histfig_flags::deity);
    }
    const auto baseColor=nativeZoneOwnerProfessionColor(candidate,int16_t(result.identityProfession!=-1?result.identityProfession:int(candidate.profession)));
    if(!baseColor)return std::nullopt;
    result.ordinaryColor=*baseColor;
    if(result.identityProfession==-1) {
        if(result.positionHasColor)for(size_t i=0;i<3;++i)result.ordinaryColor[i]=uint8_t(result.positionColor[i]);
        if(result.slaveStrength>0 || result.prisonerStrength>0 || result.imprisonerStrength>0)result.ordinaryColor={7,0,0};
    }
    if(result.deity)result.ordinaryColor={6,0,1};
    result.ordinaryFlashColor=result.ordinaryColor;
    result.ordinaryFlashColor[2]=uint8_t(1-result.ordinaryFlashColor[2]);
    if(!result.ordinaryFlashColor[0] && !result.ordinaryFlashColor[1] && !result.ordinaryFlashColor[2])result.ordinaryFlashColor[0]=7;
    if(result.ordinaryFlashColor[0]==result.ordinaryFlashColor[1] && !result.ordinaryFlashColor[2] && result.ordinaryFlashColor[1])result.ordinaryFlashColor[0]=0;
    if(result.ordinaryColor[0]==result.ordinaryColor[1] && !result.ordinaryColor[2] && result.ordinaryColor[1])result.ordinaryColor[0]=0;
    return result;
}
std::optional<ZoneOwnerNameColor> nativeZoneOwnerNameColor(df::unit& candidate) {
    if(!df::global::world || !df::global::plotinfo || !df::global::gamemode || int(*df::global::gamemode)!=0 || !nativeZoneOwnerCandidatesReady())return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    static const bool compatible=hash(base+0x1333bc0,0xa0d)==UINT64_C(0x8d3fa1210a66c482) &&
        hash(base+0x247d80,0xbf)==UINT64_C(0xc034bea0c49abf36) &&
        hash(base+0x14add70,0x12f)==UINT64_C(0x01f897b15772d540) &&
        hash(base+0xedfca0,0x17)==UINT64_C(0x275e5d9367823fc0) &&
        std::memcmp(base+0x67520,"\xb8\x03\x00\x00\x00\xc3",6)==0;
    if(!compatible)return std::nullopt;
    static_assert(offsetof(df::unit,uwss_display_tile)==0x8a0 && offsetof(df::unit_active_animationst,root_body_part_id)==0x18);
    static_assert(offsetof(df::caste_raw,misc)+offsetof(df::caste_raw::T_misc,remains_color)==0x48a);
    static_assert(offsetof(df::caste_raw,extracts)+offsetof(df::caste_raw::T_extracts,blood_state)==0x3c74);
    static_assert(offsetof(df::material,state_color)==0x9c && offsetof(df::descriptor_color,color)==0x70 && offsetof(df::descriptor_color,bold)==0x71);
    static_assert(int(df::caste_raw_flags::HAS_BLOOD)==69 && int(df::caste_raw_flags::AQUATIC_UNDERSWIM)==62);
    static_assert(offsetof(df::nemesis_record,flags)==0x58 && int(df::nemesis_flags::FLASHES)==7);
    const auto steady=[](std::array<uint8_t,3> color,uint8_t source) {return ZoneOwnerNameColor{color,color,0,source};};
    if(candidate.uwss_display_tile)return steady({uint8_t(candidate.uwss_display_color_f),uint8_t(candidate.uwss_display_color_b),uint8_t(candidate.uwss_display_color_br)},1);
    if(candidate.flags3.bits.ghostly)return steady({7,0,1},2);
    const df::caste_raw* caste=nullptr;
    const auto& creatures=df::global::world->raws.creatures.all;
    if(candidate.race>=0 && size_t(candidate.race)<creatures.size() && creatures[candidate.race]) {
        const auto& castes=creatures[candidate.race]->caste;
        if(candidate.caste>=0 && size_t(candidate.caste)<castes.size())caste=castes[candidate.caste];
    }
    if(candidate.enemy.undead && candidate.enemy.undead->root_body_part_id>=1) {
        if(caste && caste->flags.is_set(df::caste_raw_flags::HAS_BLOOD)) {
            using Material=df::material* (*)(df::world*,int16_t,int32_t);
            auto* material=reinterpret_cast<Material>(base+0x14add70)(df::global::world,caste->extracts.blood_mat,caste->extracts.blood_matidx);
            const int state=int(caste->extracts.blood_state);
            if(material && state>=0 && size_t(state)<material->state_color.size()) {
                const int patternId=material->state_color[state];const auto& descriptors=df::global::world->raws.descriptors;
                if(patternId>=0 && size_t(patternId)<descriptors.patterns.size()) {
                    const auto* pattern=descriptors.patterns[patternId];
                    if(pattern && !pattern->colors.empty()) {
                        const int colorId=pattern->colors[0];
                        if(colorId>=0 && size_t(colorId)<descriptors.colors.size() && descriptors.colors[colorId]) {
                            const auto* color=descriptors.colors[colorId];
                            return steady({uint8_t(color->color),0,uint8_t(int(color->color)==0?1:color->bold)},3);
                        }
                    }
                }
            }
            return steady({4,0,1},3);
        }
        std::array<uint8_t,3> color{5,0,0};
        if(caste)for(size_t i=0;i<3;++i)color[i]=uint8_t(caste->misc.remains_color[i]);
        if(color[0]==color[1])color[2]=1;
        return steady(color,3);
    }
    using Depth=uint8_t (*)(df::world*,int16_t,int16_t,int16_t);
    const auto depth=reinterpret_cast<Depth>(base+0x247d80);
    if(!(candidate.flags1.whole&0x2010002) && depth(df::global::world,candidate.pos.x,candidate.pos.y,candidate.pos.z)==7 &&
       ((caste && caste->flags.is_set(df::caste_raw_flags::AQUATIC_UNDERSWIM)) || !candidate.flags2.bits.swimming ||
        depth(df::global::world,candidate.pos.x,candidate.pos.y,int16_t(candidate.pos.z+1))>0))return steady({1,1,1},4);
    bool fire=false;
    for(const auto* entry:candidate.inventory)if(entry && entry->item && entry->item->flags.bits.on_fire){fire=true;break;}
    if(!fire)for(const auto& part:candidate.body.components.body_part_status)if(!part.bits.missing && part.bits.on_fire){fire=true;break;}
    // Native selects these alternatives via simulation RNG. Expose the effect
    // without advancing that RNG merely because a viewer requests its rows.
    if(fire)return ZoneOwnerNameColor{{4,0,1},{6,0,1},3,5};
    const auto ordinary=nativeZoneOwnerColorSources(candidate);if(!ordinary)return std::nullopt;
    auto result=steady(ordinary->ordinaryColor,0);
    using Member=bool (*)(df::unit*);
    const bool member=reinterpret_cast<Member>(base+0x138ed20)(&candidate);
    if(member && candidate.status.current_soul) {
        for(const auto* skill:candidate.status.current_soul->skills)if(skill && skill->rating>=15 && int(skill->id)!=114){result.effect=1;break;}
    }
    if(!member && ordinary->identityProfession==-1 && candidate.flags1.bits.important_historical_figure) {
        for(auto* ref:candidate.general_refs)if(ref && ref->getType()==df::general_ref_type::IS_NEMESIS) {
            using Nemesis=df::nemesis_record* (*)(df::general_ref*);
            const auto* nemesis=reinterpret_cast<Nemesis>(base+0xedfca0)(ref);
            if(nemesis && nemesis->flags.is_set(df::nemesis_flags::FLASHES))result.effect=2;
            break;
        }
    }
    if(result.effect)result.alternate=ordinary->ordinaryFlashColor;
    return result;
}
std::optional<ZoneOwnerRoomStatus> nativeZoneOwnerRoomStatus(df::building_civzonest& zone,df::unit& candidate) {
    if(!df::global::world || !staffOrderingFunctions())return std::nullopt;
    int16_t roomKind;
    switch(zone.type) {
        case df::civzone_type::Office:roomKind=0;break;
        case df::civzone_type::Bedroom:roomKind=1;break;
        case df::civzone_type::DiningHall:roomKind=2;break;
        case df::civzone_type::Tomb:roomKind=3;break;
        default:return std::nullopt;
    }
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    // Reference3a8730 aggregates semantic owned rooms; its drawing operations
    // are excluded. Value calculation owns temporary vectors and reads map,
    // furnishings, materials and unit preferences. It uses no menu scratch.
    if(hash(base+0x3a8730,0x656)!=UINT64_C(0xbfe45639816b3835) ||
       hash(base+0x559610,0xf53)!=UINT64_C(0xb4aa2d070c8d24f1) ||
       hash(base+0xab4f20,0x3b0)!=UINT64_C(0x7740ba5bc0108c80) ||
       hash(base+0x14d0c70,0x5cc)!=UINT64_C(0x93e5fad4bd72b45f) ||
       hash(base+0x14add70,0x12f)!=UINT64_C(0x01f897b15772d540))return std::nullopt;
    static_assert(offsetof(df::unit,owned_buildings)==0x450);
    using Value=int32_t (*)(df::building_civzonest*,df::unit*);
    using Label=void (*)(std::string*,int32_t,int16_t);
    ZoneOwnerRoomStatus result;
    for(auto* building:candidate.owned_buildings) {
        auto* room=virtual_cast<df::building_civzonest>(building);
        if(!room || room->type!=zone.type)continue;
        result.value=std::max({result.value,1,reinterpret_cast<Value>(const_cast<uint8_t*>(base+0x559610))(room,&candidate)});
    }
    if(result.value>0) {
        reinterpret_cast<Label>(const_cast<uint8_t*>(base+0xab4f20))(&result.label,result.value,roomKind);
        result.label.insert(0,"Has "); // Native inline prefix at3a8814 (and other room branches).
    }
    return result;
}
std::optional<ZoneOwnerDisplayText> nativeZoneOwnerDisplayText(df::unit& candidate,int32_t columns) {
    const auto& order=staffOrderingFunctions();
    if(!order || !df::global::world || columns<3 || columns>2048)return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    // Widget14237a0 uses combined text when it fits, otherwise these two
    // semantic readers. Global widget output strings are never borrowed.
    if(hash(base+0x1330500,0x37d)!=UINT64_C(0x963e5805735092ee) ||
       hash(base+0x1330880,0x3ac)!=UINT64_C(0xbef834f2b924d785) ||
       hash(base+0x52d910,0x5c4)!=UINT64_C(0x3cc66a9b45f7baa9))return std::nullopt;
    ZoneOwnerDisplayText result;
    order.name(&candidate,&result.combined,true);
    using Name=void (*)(df::unit*,std::string*);
    reinterpret_cast<Name>(const_cast<uint8_t*>(base+0x1330500))(&candidate,&result.name);
    reinterpret_cast<StaffOrderingFunctions::Text>(const_cast<uint8_t*>(base+0x1330880))(&candidate,&result.profession,true);
    const auto fit=[&](std::string text) {
        if(text.size()>size_t(columns)) {
            using Shorten=void (*)(std::string*,int32_t);
            reinterpret_cast<Shorten>(const_cast<uint8_t*>(base+0x52d910))(&text,columns);
            if(text.size()>size_t(columns)) {text.resize(columns);text.replace(columns-3,3,"...");}
        }
        return text;
    };
    if(result.combined.size()<=size_t(columns))result.firstLine=result.combined;
    else {result.firstLine=fit(result.name);result.secondLine=fit(result.profession);}
    return result;
}
std::optional<ZoneAnimalUnitDisplay> nativeZoneAnimalUnitDisplay(df::unit& candidate,int32_t columns) {
    const auto text=nativeZoneOwnerDisplayText(candidate,columns);
    const auto color=nativeZoneOwnerNameColor(candidate);
    if(!text || !color)return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    // Pin the observed inline variant, but never enter its render function.
    // Its GRAZER test is the cached caste flag, not the broader DFHack helper.
    static const bool compatible=hash(base+0x14237a0,0x83f)==UINT64_C(0xbc38168cc5c544cd);
    if(!compatible)return std::nullopt;
    static_assert(int(df::caste_raw_flags::GRAZER)==106);
    static_assert(offsetof(df::unit,enemy)+offsetof(df::unit::T_enemy,caste_flags)==0x1278);
    ZoneAnimalUnitDisplay result{*text,*color,candidate.enemy.caste_flags.is_set(df::caste_raw_flags::GRAZER),{}};
    // Inline warning copies at1423dda/1423de4 refer to this immutable literal.
    if(result.grazer)result.warning.assign(reinterpret_cast<const char*>(base+0x1786f68),24);
    return result;
}
namespace {
bool animalStatusReady() {
    if(!df::global::world || !nativeZoneDefaultsReady())return false;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    // Pin the render branches as evidence; never invoke them or read their UI.
    static const bool compatible=hash(base+0x3d0260,0x156)==UINT64_C(0x968a686c50852edc) &&
        hash(base+0x3acdc0,0x3dd)==UINT64_C(0xe237949d71a1e280) &&
        hash(base+0x3a8200,0x1d9)==UINT64_C(0x47f2c45f78dc3f23);
    return compatible;
}
ZoneAnimalStatus animalZoneStatus(const df::building_civzonest& picker) {
    return {uint8_t(picker.type==df::civzone_type::Pond?
        (picker.zone_settings.pond.flag.bits.keep_filled?3:2):1),0,-1};
}
df::item* firstBuildingItem(df::building_actual* building) {
    if(!building || building->contained_items.empty() || !building->contained_items.front())return nullptr;
    return building->contained_items.front()->item;
}
}
std::optional<ZoneAnimalStatus> nativeZoneAnimalItemStatus(df::building_civzonest& picker,bool selected) {
    if(!animalStatusReady() || (picker.type!=df::civzone_type::Pen && picker.type!=df::civzone_type::Pond))return std::nullopt;
    return selected?animalZoneStatus(picker):ZoneAnimalStatus{};
}
std::optional<ZoneAnimalStatus> nativeZoneAnimalStatus(df::building_civzonest& picker,df::unit& candidate) {
    if(!animalStatusReady() || (picker.type!=df::civzone_type::Pen && picker.type!=df::civzone_type::Pond))return std::nullopt;
    const auto firstRef=[&](df::general_ref_type kind)->df::general_ref* {
        for(auto* ref:candidate.general_refs)if(ref && ref->getType()==kind)return ref;
        return nullptr;
    };
    if(auto* ref=firstRef(df::general_ref_type::BUILDING_CIVZONE_ASSIGNED))
        if(ref->getBuilding())return animalZoneStatus(picker);
    if(!candidate.flags1.bits.chained && !candidate.flags1.bits.caged)return ZoneAnimalStatus{};
    const auto status=[](df::item* item,uint8_t relation) {return ZoneAnimalStatus{4,relation,item->id};};
    if(candidate.flags1.bits.chained) {
        if(auto* ref=firstRef(df::general_ref_type::BUILDING_CHAIN)) {
            auto* building=ref->getBuilding();
            if(building && building->isActual())
                if(auto* item=firstBuildingItem(static_cast<df::building_actual*>(building)))return status(item,1);
        }
    }
    if(candidate.flags1.bits.caged)
        if(auto* ref=firstRef(df::general_ref_type::CONTAINED_IN_ITEM))
            if(auto* item=ref->getItem())return status(item,2);
    // Native falls back to pending assignments only while containment flags are set.
    for(auto* chain:df::global::world->buildings.other.CHAIN)
        if(chain && chain->assigned==&candidate)
            if(auto* item=firstBuildingItem(chain))return status(item,3);
    for(auto* cage:df::global::world->buildings.other.CAGE)
        if(cage && std::find(cage->assigned_units.begin(),cage->assigned_units.end(),candidate.id)!=cage->assigned_units.end())
            if(auto* item=firstBuildingItem(cage))return status(item,4);
    return ZoneAnimalStatus{5,0,-1};
}
std::optional<std::string> nativeZoneOwnerQuery(std::string query) {
    const auto& order=staffOrderingFunctions();
    if(!order)return std::nullopt;
    order.normalize(&query);return query;
}
bool nativeZoneSetOwner(df::building_civzonest& zone,df::unit* owner) {
    if(!df::global::world || !nativeZoneOwnerReady() || !zone.canBeRoomSubset())return false;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    // Semantic zone/unit inputs only. DF owns spouse lists, prior-tomb transfer,
    // restriction bits and native vector allocation; no picker state is read.
    using Assign=void (*)(df::building_civzonest*,df::unit*);
    reinterpret_cast<Assign>(const_cast<uint8_t*>(base+0x557a60))(&zone,owner);
    return true;
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
          hash(base+0x355c53,0x1d0)==0xcda8023a0a668bcfULL &&
          hash(base+0x3557d3,0x14c)==0x653b8536a1033853ULL &&
          hash(base+0x35568f,0x1859)==0xa9a811e14015b6d3ULL;
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
