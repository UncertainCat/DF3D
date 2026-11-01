#pragma once
#include <functional>
#include "creature_office_native.h"
#include "df/histfig_entity_link_positionst.h"
#include "df/workshop_profile.h"
#include "df/occupation.h"
#include "df/abstract_building.h"
#include "df/abstract_building_contents.h"
#include "df/world_site.h"
#include "df/building_civzonest.h"
#include "df/buildings_other_id.h"
#include "df/unit_relationship_type.h"
#include "location_staff_mutation_native.h"

namespace df3d_creature {
inline uint64_t locationAssignmentRevision(df::unit* unit, const df::occupation* target) {
    uint64_t hash=UINT64_C(14695981039346656037);
    const auto add=[&](int32_t value) {
        for(unsigned shift=0;shift<32;shift+=8){hash^=(uint32_t(value)>>shift)&255;hash*=UINT64_C(1099511628211);}
    };
    add(unit->id);add(unit->hist_figure_id);add(target->id);
    for(const auto* held:unit->occupations) {
        if(!held){add(-1);continue;}
        add(held->id);add(int32_t(held->type));add(held->unit_id);add(held->histfig_id);
        add(held->site_id);add(held->location_id);
    }
    return (hash & UINT64_C(0x1fffffffffffff)) | 1;
}
struct LaborLocation {
    int32_t id=-1,type=-1,siteId=-1,locationId=-1,locationType=-1,tier=-1;
    std::string role,name;
    bool removable=false;
    uint64_t revision=0;
    int32_t zoneId=-1,x=0,y=0,z=0;
};
inline std::optional<std::vector<LaborLocation>> laborLocations(df::unit* unit) {
    static const bool supported=[] {
        if(!df3d_production::farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,size;uint64_t hash;};
        constexpr Pin pins[]={
            {0x67e80,0x10,UINT64_C(0x7580a2b541177a3a)},
            {0x6ff00,0xa9,UINT64_C(0x05b714178b312b1f)},
            {0x17496c,0x2d1,UINT64_C(0xe8556955319c4255)},
            {0x174c3d,0xd9,UINT64_C(0xf047015836ce3169)},
            {0xa946e0,0x7c2,UINT64_C(0xdbc3db5f052419ee)},
            {0x138ed20,0xff,UINT64_C(0x430951f9f3e403c2)},
            {0x1752cc,0x68,UINT64_C(0xd7b528da9895a0f2)},
            {0x19f47c,0x2c,UINT64_C(0x8a9ffc4374c47f93)},
            {0x1b51cc,0x10c,UINT64_C(0x09421756d3340f65)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.size;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();
    if(!supported || !unit || !df::global::plotinfo)return std::nullopt;
    auto* site=df::world_site::find(df::global::plotinfo->site_id);
    if(!site)return std::nullopt;
    static_assert(offsetof(df::world_site,id)==0x88 && offsetof(df::world_site,buildings)==0x2b0);
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    // Native renderer iterates this simulation vector directly; no menu list.
    // Captions are the literal strings selected by its pinned role switch.
    constexpr size_t captions[]={0x15ffd40,0x15ffd30,0x15ffd28,0x15ffd10,0x15ffd00,0x15ffd1c,0,0x15ffcf8,0x15ffce8,0x15fff10,0x15fff00};
    std::vector<LaborLocation> rows;rows.reserve(unit->occupations.size());
    for(const auto* occupation:unit->occupations) {
        if(!occupation)return std::nullopt;
        LaborLocation row;row.id=occupation->id;row.type=int32_t(occupation->type);
        row.revision=locationAssignmentRevision(unit,occupation);
        row.siteId=occupation->site_id;row.locationId=occupation->location_id;
        if(row.type>=0 && row.type<=10 && row.type!=6)
            row.removable=row.type==3 || row.type==4 || reinterpret_cast<bool (*)(df::unit*)>(base+0x138ed20)(unit);
        if(row.type>=0 && row.type<11 && captions[row.type])row.role=reinterpret_cast<const char*>(base+captions[row.type]);
        if(row.locationId>=0 && row.siteId==site->id) {
            auto* place=reinterpret_cast<df::abstract_building* (*)(df::world_site*,int32_t)>(base+0x67e80)(site,row.locationId);
            if(place && !place->flags.is_set(df::abstract_building_flags::DOES_NOT_EXIST) && !place->flags.is_set(df::abstract_building_flags::WG_RUINED)) {
                row.locationType=int32_t(place->getType());
                static_assert(offsetof(df::building,site_id)==0x114 && offsetof(df::building,location_id)==0x118);
                // Native navigation walks ACTIVITY_ZONE in simulation order,
                // selecting the first zone linked to this actual location.
                for(auto* entry:df::global::world->buildings.other[df::buildings_other_id::ACTIVITY_ZONE]) {
                    auto* zone=static_cast<df::building_civzonest*>(entry);
                    if(zone && zone->site_id==place->site_id && zone->location_id==place->id) {
                        if(zone->centerx!=-30000){row.zoneId=zone->id;row.x=zone->centerx;row.y=zone->centery;row.z=zone->z;}
                        break;
                    }
                }
                if(const auto* contents=place->getContents())row.tier=contents->location_tier;
                if(const auto* name=place->getName();name && name->has_name) {
                    auto owned=*name;
                    reinterpret_cast<void (*)(df::language_name*,std::string*,bool,bool)>(base+0xa946e0)(&owned,&row.name,true,false);
                }
            }
        }
        rows.push_back(std::move(row));
    }
    return rows;
}
enum class LocationRemoveOutcome { Rejected,Applied,Unavailable,Unknown };
inline LocationRemoveOutcome removeLocationAssignment(df::unit* unit,int32_t occupationId,uint64_t revision) {
    const auto& native=df3d_area::staffMutationFunctions();
    static const bool supported=[] {
        if(!df3d_production::farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x8b;++i){hash^=base[0xba570+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0xade65cab95ecb0c3);
    }();
    if(!supported || !native)return LocationRemoveOutcome::Unavailable;
    if(!unit)return LocationRemoveOutcome::Rejected;
    const auto rows=laborLocations(unit);
    if(!rows)return LocationRemoveOutcome::Unavailable;
    const auto found=std::find_if(rows->begin(),rows->end(),[&](const auto& row){return row.id==occupationId && row.revision==revision && row.removable;});
    if(found==rows->end())return LocationRemoveOutcome::Rejected;
    auto* target=df::occupation::find(occupationId);
    if(!target || target->unit_id!=unit->id ||
       std::find(unit->occupations.begin(),unit->occupations.end(),target)==unit->occupations.end())return LocationRemoveOutcome::Rejected;
    // Native creature input1b53ce..1b5427: detach, update profession with
    // announcements suppressed, then clear the holder. Removal retains labors.
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    try {
        reinterpret_cast<void (*)(df::occupation*,std::vector<df::occupation*>*)>(base+0xba570)(target,&unit->occupations);
        unit->flags2.bits.no_notify=true;
        native.profession(unit,false);
        unit->flags2.bits.no_notify=false;
        target->unit_id=-1;target->histfig_id=-1;
        return LocationRemoveOutcome::Applied;
    } catch(const std::exception&) {
        unit->flags2.bits.no_notify=false;
        return LocationRemoveOutcome::Unknown;
    }
}
inline uint64_t workshopAssignmentRevision(df::unit* unit,df::building* building,df::workshop_profile* profile) {
    uint64_t hash=UINT64_C(14695981039346656037);
    const auto add=[&](int32_t value) {
        for(unsigned shift=0;shift<32;shift+=8){hash^=(uint32_t(value)>>shift)&255;hash*=UINT64_C(1099511628211);}
    };
    add(unit->id);add(building->id);add(int32_t(building->getType()));add(building->getSubtype());
    for(const auto id:profile->permitted_workers)add(id);
    // Generic creature facts pass through Lua numbers; preserve exact integers.
    return (hash & UINT64_C(0x1fffffffffffff)) | 1;
}
struct LaborWorkshop {
    int32_t id=-1,type=-1,subtype=-1,custom=-1,x=0,y=0,z=0;
    std::string caption;
    uint64_t revision=0;
};
// Native47dfc0's Workshops branch touches only these owned vectors and reads
// simulation building profiles. It never receives the live creature sheet.
inline std::optional<std::vector<LaborWorkshop>> laborWorkshops(df::unit* unit) {
    static const bool supported=[] {
        if(!df3d_production::farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        const auto hash=[&](size_t rva,size_t length) {
            uint64_t value=UINT64_C(14695981039346656037);
            for(size_t i=0;i<length;++i){value^=base[rva+i];value*=UINT64_C(1099511628211);}
            return value;
        };
        return hash(0x47dfc0,0x2ae)==UINT64_C(0xe5aeb067816dc769) &&
               hash(0xb9e70,0xf8)==UINT64_C(0x7dab880be6ec9cba) &&
               hash(0x173ed8,0x33)==UINT64_C(0x85034fcd774d5e9b);
    }();
    if(!supported || !unit || !df::global::world)return std::nullopt;
    struct Context {
        std::array<uint8_t,0x1ac4> prefix{};
        int32_t page=1;
        std::array<uint8_t,8> unused{};
        std::vector<int32_t> workshops,assignedAnimals,availableAnimals;
    } context;
    static_assert(offsetof(Context,workshops)==0x1ad0 && offsetof(Context,availableAnimals)==0x1b00);
    // At most one ID per building (native insertion deduplicates). Reserving
    // this owned storage keeps native code out of its vector allocation path.
    context.workshops.reserve(df::global::world->buildings.all.size());
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    reinterpret_cast<void (*)(Context*,df::unit*)>(base+0x47dfc0)(&context,unit);
    std::vector<LaborWorkshop> rows;rows.reserve(context.workshops.size());
    for(const auto id:context.workshops) {
        auto* building=df::building::find(id);if(!building)return std::nullopt;
        LaborWorkshop row;row.id=id;row.type=int32_t(building->getType());row.subtype=building->getSubtype();row.custom=building->getCustomType();
        row.x=building->centerx;row.y=building->centery;row.z=building->z;
        auto* profile=building->getWorkshopProfile();if(!profile)return std::nullopt;
        row.revision=workshopAssignmentRevision(unit,building,profile);
        building->getName(&row.caption);rows.push_back(std::move(row));
    }
    return rows;
}
enum class WorkshopRemoveOutcome { Rejected,Applied,Unavailable };
inline WorkshopRemoveOutcome removeWorkshopAssignment(df::unit* unit,int32_t buildingId,uint64_t revision) {
    static const bool supported=[] {
        if(!df3d_production::farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x57;++i){hash^=base[0x14ddb0+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0x94222cd85df6aa22);
    }();
    if(!supported)return WorkshopRemoveOutcome::Unavailable;
    if(!unit)return WorkshopRemoveOutcome::Rejected;
    const auto rows=laborWorkshops(unit);
    if(!rows)return WorkshopRemoveOutcome::Unavailable;
    const auto found=std::find_if(rows->begin(),rows->end(),[&](const auto& row){return row.id==buildingId && row.revision==revision;});
    if(found==rows->end())return WorkshopRemoveOutcome::Rejected;
    auto* building=df::building::find(buildingId);
    auto* profile=building?building->getWorkshopProfile():nullptr;
    if(!profile)return WorkshopRemoveOutcome::Rejected;
    const auto& workers=profile->permitted_workers;
    if(std::find(workers.begin(),workers.end(),unit->id)==workers.end())return WorkshopRemoveOutcome::Rejected;
    // Native Labor remove input1b58b1 calls this semantic routine. The rest of
    // its handler only updates menu rows, which are owned by the presentation.
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    reinterpret_cast<void (*)(df::workshop_profile*,int32_t)>(base+0x14ddb0)(profile,unit->id);
    return WorkshopRemoveOutcome::Applied;
}
// Creature Labor input1b4580..1b45e1. DF owns caste, unit and office/spouse
// eligibility. Its office predicate refreshes lookup indices; restore only
// those semantic caches, without borrowing any sheet or menu state.
inline std::optional<bool> laborEligible(df::unit* unit,const std::function<void()>& collect={}) {
    static const bool supported=[] {
        if(!df3d_production::farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x1b4580,0x61,UINT64_C(0xfdfbba8b0e09e10e)},
            {0x1376500,0xf0,UINT64_C(0x2c5ca25b0abc0a79)},
            {0x138ed20,0xff,UINT64_C(0x430951f9f3e403c2)},
            {0x13b99b0,0x250,UINT64_C(0x2846bbdb177934c5)},
            {0xb530b0,0xac,UINT64_C(0x7c6f66602bdab157)},
            {0xb972c0,0xf8,UINT64_C(0x462a923de0759a7a)},
            {0xbbef0,0xad,UINT64_C(0xa7990fc1186ffa89)},
            {0xbbd90,0xad,UINT64_C(0x18680dd18e5ba980)},
            {0xbbe40,0xad,UINT64_C(0x062a266340f9bf38)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();
    if(!supported || !df::global::plotinfo)return std::nullopt;
    if(!unit)return false;
    if(unit->profession==df::profession::CHILD || unit->profession==df::profession::BABY)return false;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    if(reinterpret_cast<bool (*)(int16_t,int16_t)>(base+0x1376500)(unit->race,unit->caste) ||
       !reinterpret_cast<bool (*)(df::unit*)>(base+0x138ed20)(unit))return false;
    struct CacheRestore {
        std::vector<std::pair<int32_t*,int32_t>> values;
        void keep(int32_t& value){values.emplace_back(&value,value);}
        ~CacheRestore(){for(auto it=values.rbegin();it!=values.rend();++it)*it->first=it->second;}
    } restore;
    static_assert(offsetof(df::unit,enemy)+offsetof(df::unit::T_enemy,histfig_vector_idx)==0x1274);
    restore.keep(unit->enemy.histfig_vector_idx);
    const auto* hf=df::historical_figure::find(unit->hist_figure_id);
    const int32_t group=df::global::plotinfo->group_id;
    const auto keepFigure=[&](const df::historical_figure* figure)->bool {
        if(!figure)return true;
        if(figure->entity_links.size()>4096)return false;
        for(auto* link:figure->entity_links) {
            if(!link)return false;
            if(link->getType()!=df::histfig_entity_link_type::POSITION || (group!=-1 && link->entity_id!=group))continue;
            auto* position=static_cast<df::histfig_entity_link_positionst*>(link);
            restore.keep(link->entity_vector_idx);restore.keep(position->assignment_vector_idx);
            const auto* entity=df::historical_entity::find(link->entity_id);
            if(!entity)continue;
            if(entity->positions.assignments.size()>65536)return false;
            for(auto* assignment:entity->positions.assignments) {
                if(!assignment)return false;
                if(assignment->id==position->assignment_id){restore.keep(assignment->position_vector_idx);break;}
            }
        }
        return true;
    };
    if(!keepFigure(hf))return std::nullopt;
    if(hf) {
        if(hf->histfig_links.size()>4096)return std::nullopt;
        for(auto* link:hf->histfig_links) {
            if(!link)return std::nullopt;
            if(link->getType()==df::histfig_hf_link_type::SPOUSE) {
                if(!keepFigure(df::historical_figure::find(link->target_hf)))return std::nullopt;
                break; // Native13b9b55 considers the first spouse link only.
            }
        }
    }
    const bool eligible=!reinterpret_cast<bool (*)(df::unit*,int32_t)>(base+0x13b99b0)(unit,group);
    // The Work animals collector repeats this predicate. Keep its lookup-cache
    // refresh inside the same restoration lifetime as the eligibility read.
    if(eligible && collect)collect();
    return eligible;
}
inline uint64_t animalAssignmentRevision(df::unit* unit,df::unit* animal) {
    uint64_t hash=UINT64_C(14695981039346656037);
    const auto add=[&](int32_t value) {
        for(unsigned shift=0;shift<32;shift+=8){hash^=(uint32_t(value)>>shift)&255;hash*=UINT64_C(1099511628211);}
    };
    add(unit->id);add(unit->hist_figure_id);add(unit->civ_id);
    add(animal->id);add(animal->hist_figure_id);add(animal->race);add(animal->caste);
    add(int32_t(animal->profession));add(animal->relationship_ids[df::unit_relationship_type::PetOwner]);
    add(animal->following?animal->following->id:-1);add(int32_t(animal->owner_type));add(animal->follow_distance);
    add(animal->name.has_name?1:0);
    return (hash & UINT64_C(0x1fffffffffffff)) | 1;
}
struct LaborAnimal {
    int32_t id=-1,ownerId=-1;
    uint64_t revision=0;
    df::coord position{-30000,-30000,-30000};
    bool assigned=false;
    std::string caption;
};
inline std::optional<std::vector<LaborAnimal>> laborAnimals(df::unit* unit) {
    if(!unit || !df::global::world || !df3d_area::staffOrderingFunctions())return std::nullopt;
    static const bool supported=[] {
        if(!df3d_production::farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x47dfc0,0x2ae,UINT64_C(0xe5aeb067816dc769)},
            {0x1367430,0xc6,UINT64_C(0xc0292be8a6dacf2c)},
            {0xc8be10,0x14c,UINT64_C(0x1ba19b485a3fa56b)},
            {0xc8baa0,0x11a,UINT64_C(0x2c62fce4a0555c66)},
            {0xedfa60,0xbd,UINT64_C(0x2f89116df6b958cc)},
            {0xedfb20,0x13,UINT64_C(0xa222e60f2f8301e4)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();
    if(!supported)return std::nullopt;
    struct Context {
        std::array<uint8_t,0x1ac4> prefix{};
        int32_t page=3;
        std::array<uint8_t,8> unused{};
        std::vector<int32_t> workshops,assignedAnimals,availableAnimals;
    } context;
    static_assert(offsetof(Context,assignedAnimals)==0x1ae8 && offsetof(Context,availableAnimals)==0x1b00);
    const auto count=df::global::world->units.active.size();
    context.assignedAnimals.reserve(count);context.availableAnimals.reserve(count);
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    const auto eligible=laborEligible(unit,[&] {
        reinterpret_cast<void (*)(Context*,df::unit*)>(base+0x47dfc0)(&context,unit);
    });
    if(!eligible)return std::nullopt;
    std::vector<LaborAnimal> rows;
    rows.reserve(context.assignedAnimals.size()+context.availableAnimals.size());
    for(const auto* list:{&context.assignedAnimals,&context.availableAnimals}) {
        for(const auto id:*list) {
            auto* animal=df::unit::find(id);if(!animal)return std::nullopt;
            LaborAnimal row;row.id=id;row.assigned=list==&context.assignedAnimals;
            row.revision=animalAssignmentRevision(unit,animal);
            row.ownerId=animal->relationship_ids[df::unit_relationship_type::PetOwner];
            // Native Work animals recenter1b4af6 resolves containment here.
            reinterpret_cast<void (*)(df::unit*,int16_t*,int16_t*,int16_t*)>(base+0x1367430)(animal,&row.position.x,&row.position.y,&row.position.z);
            // Native renderer175e56 calls this formatter with sex/training suffixes.
            df3d_area::staffOrderingFunctions().name(animal,&row.caption,true);
            rows.push_back(std::move(row));
        }
    }
    return rows;
}
enum class AnimalEditOutcome { Rejected,Applied,Unavailable,Unknown };
inline AnimalEditOutcome editAnimalAssignment(df::unit* unit,int32_t animalId,uint64_t revision,bool assigned) {
    static const bool supported=[] {
        if(!df3d_production::farmFunctions())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x1b4d28,0xe9,UINT64_C(0x06ae42c5aad2fa01)},
            {0x138c120,0x17,UINT64_C(0xdfbd4def57b3f6b4)},
            {0x13918c0,0xae,UINT64_C(0x9c94fa1548e239ee)},
            {0x1391970,0x126,UINT64_C(0x22034be79ba5c743)},
            {0x138a350,0x13ba,UINT64_C(0xe6251c2e132c1a41)},
            {0x931860,0x2f9,UINT64_C(0x3f40974d82863764)},
            {0x13b3090,0x19,UINT64_C(0x901cd2f6d41c1657)},
            {0x14d760,0x8e,UINT64_C(0xb80187200c6ef5c9)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();
    if(!supported)return AnimalEditOutcome::Unavailable;
    if(!unit)return AnimalEditOutcome::Rejected;
    const auto rows=laborAnimals(unit);if(!rows)return AnimalEditOutcome::Unavailable;
    const auto found=std::find_if(rows->begin(),rows->end(),[&](const auto& row){return row.id==animalId && row.revision==revision;});
    if(found==rows->end())return AnimalEditOutcome::Rejected;
    if(found->assigned==assigned)return AnimalEditOutcome::Applied;
    auto* animal=df::unit::find(animalId);if(!animal)return AnimalEditOutcome::Rejected;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    try {
        // Native creature Labor input1b4d28..1b4e11. These semantic routines
        // own following, historical records/links, history events and naming.
        reinterpret_cast<void (*)(df::unit*,df::unit*,int32_t,int16_t)>(base+0x138c120)(animal,assigned?unit:nullptr,2,0);
        animal->relationship_ids[df::unit_relationship_type::PetOwner]=assigned?unit->id:-1;
        if(!assigned) {
            reinterpret_cast<void (*)(df::unit*,int16_t,int32_t,bool)>(base+0x13918c0)(animal,13,-1,false);
        } else {
            reinterpret_cast<df::nemesis_record* (*)(df::unit*,int8_t,int8_t,bool)>(base+0x138a350)(animal,0,1,false);
            if(unit->hist_figure_id!=-1)
                reinterpret_cast<void (*)(df::unit*,int16_t,int32_t,int16_t,bool)>(base+0x1391970)(animal,13,unit->hist_figure_id,100,true);
            if(!animal->name.has_name) {
                if(auto* entity=df::historical_entity::find(unit->civ_id)) {
                    reinterpret_cast<void (*)(df::historical_entity*,df::language_name*,int16_t)>(base+0x931860)(entity,&animal->name,0);
                    if(auto* figure=reinterpret_cast<df::historical_figure* (*)(df::unit*)>(base+0x13b3090)(animal))
                        reinterpret_cast<void (*)(df::language_name*,df::language_name*)>(base+0x14d760)(&figure->name,&animal->name);
                }
            }
        }
        return AnimalEditOutcome::Applied;
    } catch(const std::exception&) {
        // Allocation can fail after relationship/history effects. Never replay.
        return AnimalEditOutcome::Unknown;
    }
}
}
