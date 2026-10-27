#pragma once
#include <array>
#include <cstdint>
#include <algorithm>
#include <optional>
#include <string>
#include <vector>
#include <windows.h>
#include "df/building_farmplotst.h"
#include "df/plotinfost.h"
#include "df/world.h"
#include "df/global_objects.h"
#include "df/plant_raw.h"
#include "df/item_seedsst.h"

namespace df3d_production {
// Semantic readers called by the native farm sheet. No selected building,
// sheet season, crop vector or native menu scratch is an input to either call.
struct FarmFunctions {
    using Eligible=bool (*)(df::building_farmplotst*,int32_t);
    using Seasons=void (*)(int16_t,std::array<uint8_t,4>*);
    using PlantingWarning=bool (*)(df::plotinfost*,int16_t);
    using Name=bool (*)(std::vector<df::plant_raw*>*,int32_t,std::string*,bool,bool);
    using Compare=int8_t (*)(const std::string*,const std::string*);
    Eligible eligible=nullptr;
    Seasons seasons=nullptr;
    PlantingWarning plantingWarning=nullptr;
    Name name=nullptr;
    Compare compare=nullptr;
    explicit operator bool() const {return eligible && seasons && plantingWarning && name && compare;}
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
           hash(0x1a5583,7)!=UINT64_C(0x7d4fd2130cf4907e))return {};
        return {reinterpret_cast<FarmFunctions::Eligible>(base+0x557770),
                reinterpret_cast<FarmFunctions::Seasons>(base+0xaae1a0),
                reinterpret_cast<FarmFunctions::PlantingWarning>(base+0x57c050),
                reinterpret_cast<FarmFunctions::Name>(base+0x144d90),
                reinterpret_cast<FarmFunctions::Compare>(base+0xb9d50)};
    }();
    return functions;
}
struct FarmChoice {
    int32_t cropId=-1;
    std::string name;
    bool seedsAvailable=false,currentSeasonWarning=false;
    int priority=0;
};
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
