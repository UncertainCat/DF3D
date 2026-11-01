#pragma once
#include "creature_office_native.h"
#include "df/histfig_entity_link_positionst.h"

namespace df3d_creature {
struct LaborWorkshop {
    int32_t id=-1,type=-1,subtype=-1,custom=-1,x=0,y=0,z=0;
    std::string caption;
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
        building->getName(&row.caption);rows.push_back(std::move(row));
    }
    return rows;
}
// Creature Labor input1b4580..1b45e1. DF owns caste, unit and office/spouse
// eligibility. Its office predicate refreshes lookup indices; restore only
// those semantic caches, without borrowing any sheet or menu state.
inline std::optional<bool> laborEligible(df::unit* unit) {
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
    return !reinterpret_cast<bool (*)(df::unit*,int32_t)>(base+0x13b99b0)(unit,group);
}
}
