#pragma once
#include "machinery_native.h"
#include "well_native.h"
#include "depot_native.h"
#include "cage_body_native.h"
#include "chain_body_native.h"
#include "siege_body_native.h"
#include <array>
#include <cstdint>
#include <algorithm>
#include <optional>
#include <string>
#include <vector>
#include <windows.h>
#include "building_header_transaction.h"
#include "df/building_farmplotst.h"
#include "df/plotinfost.h"
#include "df/world.h"
#include "df/global_objects.h"
#include "df/plant_raw.h"
#include "df/item_seedsst.h"
#include "df/job.h"
#include "df/job_type.h"

namespace df3d_production {
// Semantic readers called by the native farm sheet. No selected building,
// sheet season, crop vector or native menu scratch is an input to either call.
struct FarmFunctions {
    using Eligible=bool (*)(df::building_farmplotst*,int32_t);
    using Seasons=void (*)(int16_t,std::array<uint8_t,4>*);
    using PlantingWarning=bool (*)(df::plotinfost*,int16_t);
    using Name=bool (*)(std::vector<df::plant_raw*>*,int32_t,std::string*,bool,bool);
    using Compare=int8_t (*)(const std::string*,const std::string*);
    using CancelJob=void (*)(df::building_farmplotst*,int32_t);
    using Fertilize=void (*)(df::building_farmplotst*);
    using CancelRemoval=void (*)(df::building*);
    using HasWorker=bool (*)(df::job*);
    using FormatName=void (*)(std::string*);
    Eligible eligible=nullptr;
    Seasons seasons=nullptr;
    PlantingWarning plantingWarning=nullptr;
    Name name=nullptr;
    Compare compare=nullptr;
    CancelJob cancelJob=nullptr;
    Fertilize scheduleFertilization=nullptr,cancelFertilization=nullptr;
    HasWorker hasWorker=nullptr;
    FormatName formatName=nullptr;
    CancelRemoval cancelRemoval=nullptr;
    explicit operator bool() const {return eligible && seasons && plantingWarning && name && compare && cancelJob && scheduleFertilization && cancelFertilization && hasWorker && formatName && cancelRemoval;}
};
inline const FarmFunctions& farmFunctions() {
    static const auto functions=[]()->FarmFunctions {
        auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
        if(!base)return {};
        const auto* dos=reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
        if(dos->e_magic!=IMAGE_DOS_SIGNATURE || dos->e_lfanew<=0 || dos->e_lfanew>0x1000)return {};
        const auto* pe=reinterpret_cast<const IMAGE_NT_HEADERS64*>(base+dos->e_lfanew);
        if(pe->Signature!=IMAGE_NT_SIGNATURE || pe->FileHeader.Machine!=IMAGE_FILE_MACHINE_AMD64 ||
            pe->FileHeader.TimeDateStamp!=0x6a70a6d9 || pe->OptionalHeader.SizeOfImage!=0x2711000)return {};
        const auto hash=[&](size_t rva,size_t length) {
            uint64_t value=UINT64_C(14695981039346656037);
            for(size_t i=0;i<length;++i){value^=base[rva+i];value*=UINT64_C(1099511628211);}
            return value;
        };
        // Complete semantic bodies and immediate tile predicates; none of
        // these ranges contains PE base relocations. Seasons spans unwind entries.
        if(hash(0x557770,0xdd)!=UINT64_C(0x20402352c38579ef) ||
           hash(0xaae1a0,0x12b)!=UINT64_C(0x8a101112ecf87493) ||
           hash(0x14b1460,0xb7)!=UINT64_C(0xf10a5339f477c759) ||
           hash(0x14b1520,0x202)!=UINT64_C(0x93c5ad7f34f5db75) ||
           hash(0x57c050,0xcb)!=UINT64_C(0x243c738f199909d3) ||
           hash(0x144d90,0xba)!=UINT64_C(0x97aed5d23117e68f) ||
           hash(0xb9d50,0x69)!=UINT64_C(0x979704ba6b6743e5) ||
           hash(0x1a5583,7)!=UINT64_C(0x7d4fd2130cf4907e) ||
           hash(0x54bcd0,0x15)!=UINT64_C(0x23931f03386d1254) ||
           hash(0x5894a0,0x333)!=UINT64_C(0x994b63e6b42eacdc) ||
           hash(0x589930,0x5e)!=UINT64_C(0xb07885291e299644) ||
           hash(0xa67820,0xcc)!=UINT64_C(0x506ce8a2c4eefca6) ||
           hash(0xd02850,0x4b)!=UINT64_C(0xea0c7dfd75f644de) ||
           hash(0x52d650,0x2b0)!=UINT64_C(0xcf43211ff8e2c344) ||
           hash(0x54c130,0xe6)!=UINT64_C(0xcab44276dbb81fae))return {};
        return {reinterpret_cast<FarmFunctions::Eligible>(base+0x557770),
                reinterpret_cast<FarmFunctions::Seasons>(base+0xaae1a0),
                reinterpret_cast<FarmFunctions::PlantingWarning>(base+0x57c050),
                reinterpret_cast<FarmFunctions::Name>(base+0x144d90),
                reinterpret_cast<FarmFunctions::Compare>(base+0xb9d50),
                reinterpret_cast<FarmFunctions::CancelJob>(base+0x54bcd0),
                reinterpret_cast<FarmFunctions::Fertilize>(base+0x5894a0),
                reinterpret_cast<FarmFunctions::Fertilize>(base+0x589930),
                reinterpret_cast<FarmFunctions::HasWorker>(base+0xd02850),
                reinterpret_cast<FarmFunctions::FormatName>(base+0x52d650),
                reinterpret_cast<FarmFunctions::CancelRemoval>(base+0x54c130)};
    }();
    return functions;
}
// Families whose native sheet consists of the shared header and contents.
inline bool plainFurnitureType(df::building_type type) {
    switch(type) {
    case df::building_type::Chair:case df::building_type::Bed:case df::building_type::Table:
    case df::building_type::Weaponrack:case df::building_type::Armorstand:case df::building_type::Cabinet:
    case df::building_type::Statue:case df::building_type::Instrument:case df::building_type::Bookcase:
    case df::building_type::OfferingPlace:case df::building_type::Wagon:case df::building_type::TractionBench:
    case df::building_type::WindowGlass:case df::building_type::WindowGem:
    case df::building_type::RoadDirt:case df::building_type::RoadPaved:
    case df::building_type::Support:case df::building_type::ArcheryTarget:case df::building_type::Weapon:return true;
    default:return false;
    }
}
inline bool specialFurnitureType(df::building_type type) {return type==df::building_type::NestBox || type==df::building_type::AnimalTrap || type==df::building_type::Hive;}
inline bool linkedFurnitureType(df::building_type type) {
    return type==df::building_type::Bridge || type==df::building_type::Floodgate || type==df::building_type::Hatch ||
        type==df::building_type::GrateWall || type==df::building_type::GrateFloor ||
        type==df::building_type::BarsVertical || type==df::building_type::BarsFloor;
}
inline bool ordinaryTrapBuilding(df::building* building) {
    return building && building->getType()==df::building_type::Trap &&
        building->getSubtype()>=2 && building->getSubtype()<=5;
}
inline bool funeraryFurnitureType(df::building_type type) {
    return type==df::building_type::Coffin || type==df::building_type::Slab;
}
struct BuildingHeader {
    std::string customNameCp437,nativeNameCp437,headerNameCp437;
    bool removing=false,suspended=false,hasWorker=false;
};
// Native Workers/Work orders use getWorkshopProfile for completed levers too.
// Keep admission subtype-specific; other traps have not been qualified.
inline bool productionProfileBuilding(df::building* building) {
    if(!building)return false;
    const auto type=building->getType();
    return type==df::building_type::Workshop || type==df::building_type::Furnace ||
        (type==df::building_type::Trap && (building->getSubtype()==0 || building->getSubtype()==1));
}
// Native sheet1b00a3 cancels building jobs and restores completed occupancy.
// It takes only a building, not selected-sheet or input scratch. The caller
// owns safe-point validation and treats exceptions after entry as unknown.
inline bool cancelBuildingRemoval(df::building* building) {
    const auto& native=farmFunctions();
    if(!native || !building ||
       (!specialFurnitureType(building->getType()) && building->getType()!=df::building_type::Cage && building->getType()!=df::building_type::Chain && building->getType()!=df::building_type::SiegeEngine && building->getType()!=df::building_type::TradeDepot && building->getType()!=df::building_type::Well && !machineryBuildingType(building->getType()) && !ordinaryTrapBuilding(building) && !plainFurnitureType(building->getType()) && !funeraryFurnitureType(building->getType()) && !linkedFurnitureType(building->getType()) && building->getType()!=df::building_type::Door && building->getType()!=df::building_type::FarmPlot && building->getType()!=df::building_type::Box && !productionProfileBuilding(building)) || building->getBuildStage()!=building->getMaxBuildStage() ||
       building->jobs.size()>size_t(INT16_MAX))return false;
    bool removing=false;
    for(const auto* job:building->jobs) {
        if(!job)return false;
        if(job->job_type==df::job_type::DestroyBuilding)removing=true;
    }
    if(!removing)return false;
    native.cancelRemoval(building);return true;
}
inline bool cancelFarmRemoval(df::building_farmplotst* farm) {
    return cancelBuildingRemoval(farm);
}
// Native header1804bb calls virtual getName; removal180c3c..180de1 uses
// the first job's suspend flag and native worker predicate, not job.working.
inline std::optional<BuildingHeader> buildingHeader(df::building* farm,bool allowLever=false) {
    const auto& native=farmFunctions();
    if(!native || !farm || farm->name.size()>512 || farm->jobs.size()>size_t(INT32_MAX))return {};
    const auto type=farm->getType();
    if(!specialFurnitureType(type) && type!=df::building_type::Cage && type!=df::building_type::Chain && type!=df::building_type::SiegeEngine && type!=df::building_type::TradeDepot && type!=df::building_type::Well && !machineryBuildingType(type) && !ordinaryTrapBuilding(farm) && !(allowLever && type==df::building_type::Trap && (farm->getSubtype()==0 || farm->getSubtype()==1)) && !plainFurnitureType(type) && !funeraryFurnitureType(type) && !linkedFurnitureType(type) && type!=df::building_type::Door && type!=df::building_type::FarmPlot && type!=df::building_type::Box && type!=df::building_type::Workshop && type!=df::building_type::Furnace)return {};
    BuildingHeader value;value.customNameCp437=farm->name;farm->getName(&value.nativeNameCp437);
    if(value.nativeNameCp437.size()>512)return {};
    value.headerNameCp437=value.nativeNameCp437;native.formatName(&value.headerNameCp437);
    for(const auto* job:farm->jobs)if(job && job->job_type==df::job_type::DestroyBuilding)value.removing=true;
    if(value.removing && !farm->jobs.empty()) {
        auto* first=farm->jobs.front();if(!first)return {};
        value.suspended=first->flags.bits.suspend;value.hasWorker=native.hasWorker(first);
    }
    return value;
}
inline std::optional<BuildingHeader> farmHeader(df::building_farmplotst* farm) {
    return buildingHeader(farm);
}
// Shared semantic header observation for independent building action authority.
inline std::optional<BuildingHeaderObservation> observeBuildingHeader(df::building* building,bool allowLever=false) {
    const auto header=buildingHeader(building,allowLever);if(!header)return {};
    BuildingHeaderObservation value;value.id=building->id;value.type=int32_t(building->getType());
    value.stage=building->getBuildStage();value.maxStage=building->getMaxBuildStage();
    value.customName=header->customNameCp437;value.nativeName=header->nativeNameCp437;
    value.headerName=header->headerNameCp437;value.removing=header->removing;
    value.suspended=header->suspended;value.hasWorker=header->hasWorker;value.forbidden=building->isForbidden();
    for(const auto* job:building->jobs) {
        if(!job)return {};
        value.jobs.push_back({job->id,int32_t(job->job_type),job->flags.whole});
    }
    if(machineryBuildingType(building->getType())){value.machinery=machineryBody(building);if(!value.machinery)return {};}
    if(building->getType()==df::building_type::Well){const auto status=wellStatus(building);if(!status)return {};value.wellStatus=uint8_t(*status==-1?0:*status-83);}
    if(building->getType()==df::building_type::TradeDepot){value.depot=depotBody(building);if(!value.depot)return {};}
    if(building->getType()==df::building_type::Cage){value.cage=cageBody(building);if(!value.cage)return {};}
    if(building->getType()==df::building_type::Chain){value.cage=chainBody(building);if(!value.cage)return {};}
    if(value.type==48){value.nest=nestBoxBody(building);if(!value.nest)return {};}
    if(value.type==24 || value.type==49){const auto controls=specialBuildingControls(building);if(!controls)return {};
        value.trap=controls->trap;value.hive=controls->hive;value.specialRevision=controls->revision;}
    if(value.type==22){const auto controls=siegeControls(building);if(!controls)return {};
        value.siege=siegeBody(building);if(!value.siege)return {};value.siegeRevision=controls->revision;}
    value.revision=buildingHeaderRevision(value);
    if(!validBuildingHeader(value))return {};
    return value;
}
// The native checkbox dispatch (sheet1afe40) is inline. Both job operations
// accept only the farm; scheduling owns its local position vectors and consumes
// simulation RNG. Do not restore RNG or borrow native selected-sheet storage.
inline bool toggleFarmFertilization(df::building_farmplotst* farm) {
    const auto& native=farmFunctions();
    if(!native || !farm || !df::global::world || farm->getBuildStage()!=farm->getMaxBuildStage())return false;
    int64_t pending=0;
    for(const auto* job:farm->jobs)if(job && job->job_type==df::job_type::FertilizeField)++pending;
    if(int64_t(farm->current_fertilization)+pending<farm->max_fertilization)native.scheduleFertilization(farm);
    else native.cancelFertilization(farm);
    return true;
}
inline bool setFarmSeasonalFertilization(df::building_farmplotst* farm,bool enabled) {
    if(!farmFunctions() || !farm || !df::global::world || farm->getBuildStage()!=farm->getMaxBuildStage())return false;
    // Native sheet1b0012 toggles this bit; semantic intent supplies its value.
    farm->farm_flags.bits.seasonal_fertilize=enabled;
    return true;
}
struct FarmChoice {
    int32_t cropId=-1;
    std::string name;
    bool seedsAvailable=false,currentSeasonWarning=false;
    int priority=0;
};
// Native sheet1afe61..1affc8 keeps the season write/branching inline; its
// cancellation helper is semantic. Reproduce only that inline transaction,
// validating membership with the native readers rather than borrowing UI rows.
// nullopt means unavailable/invalid context, false means an inadmissible choice.
inline std::optional<bool> setFarmCrop(df::building_farmplotst* farm,int season,int32_t crop) {
    const auto& native=farmFunctions();
    if(!native || !farm || !df::global::world || !df::global::plotinfo ||
       !df::global::cur_season || season<0 || season>3 || crop<-1 || crop>32767 ||
       farm->jobs.size()>size_t(INT32_MAX))return {};
    if(crop>=0) {
        auto& plants=df::global::world->raws.plants.all;
        if(size_t(crop)>=plants.size() || !plants[size_t(crop)] ||
           !plants[size_t(crop)]->flags.is_set(df::plant_raw_flags::SEED))return false;
        std::array<uint8_t,4> seasons{};native.seasons(int16_t(crop),&seasons);
        if(!seasons[size_t(season)] || !native.eligible(farm,crop))return false;
        if(farm->plant_id[size_t(season)]==crop)return true;
        if(season==*df::global::cur_season && native.plantingWarning(df::global::plotinfo,int16_t(crop)))return false;
    }
    farm->plant_id[size_t(season)]=int16_t(crop);
    if(season==*df::global::cur_season) {
        for(size_t i=farm->jobs.size();i-->0;) {
            auto* job=farm->jobs[i];
            if(job && job->job_type==df::job_type::PlantSeeds)native.cancelJob(farm,int32_t(i));
        }
    }
    return true;
}
// The native sheet's list builder owns UI globals and cannot be called here.
// Its inline seed mask and priority/insertion policy are reproduced explicitly;
// eligibility, seasons, names, text comparison and warning use native routines.
// All list storage is ours. The fallow control is separate from plant choices.
inline std::optional<std::vector<FarmChoice>> farmChoices(df::building_farmplotst* farm,int season) {
    const auto& native=farmFunctions();
    auto* world=df::global::world;
    if(!native || !farm || !world || !df::global::plotinfo || season<0 || season>3)return {};
    auto& plants=world->raws.plants.all;
    if(plants.size()>32768)return {};
    std::vector<bool> seeds(plants.size(),false);
    // Sheet1a5583: rejects in-building/removed/etc.; neither seed stack count
    // nor the old adapter's smaller flag subset defines menu availability.
    for(auto* item:world->items.other.SEEDS) {
        if(item && !(item->flags.whole&UINT32_C(0xe98fb0)) &&
            item->mat_type>=419 && item->mat_type<=618 && item->mat_index>=0 &&
            size_t(item->mat_index)<plants.size())seeds[size_t(item->mat_index)]=true;
    }
    std::vector<FarmChoice> rows;
    for(size_t index=plants.size();index>0;--index) {
        const auto id=int32_t(index-1);
        auto* plant=plants[size_t(id)];
        if(!plant || !plant->flags.is_set(df::plant_raw_flags::SEED))continue;
        std::array<uint8_t,4> seasons{};native.seasons(int16_t(id),&seasons);
        if(!seasons[size_t(season)] || !native.eligible(farm,id))continue;
        FarmChoice row;row.cropId=id;row.seedsAvailable=seeds[size_t(id)];
        row.currentSeasonWarning=native.plantingWarning(df::global::plotinfo,int16_t(id));
        if(!native.name(&plants,id,&row.name,true,true))return {};
        row.priority=farm->plant_id[size_t(season)]==id?2:(row.seedsAvailable?1:0);
        rows.push_back(std::move(row));
    }
    // Reverse raw traversal plus stable order retains native equal-name ties.
    std::stable_sort(rows.begin(),rows.end(),[&](const auto& a,const auto& b) {
        if(a.priority!=b.priority)return a.priority>b.priority;
        return native.compare(&a.name,&b.name)<0;
    });
    return rows;
}
}
