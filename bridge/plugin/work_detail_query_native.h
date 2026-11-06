#pragma once
#include <functional>
#include "work_detail_native.h"
#include "workshop_workers_native.h"
#include "residents_query_native.h"

namespace df3d_production {
namespace work_detail_query {
using Entry=df3d_area::StaffUnitReference;
using Predicate=std::function<bool(const Entry&)>;
struct Sort {std::function<bool(const Entry&,const Entry&)> compare;std::string name;};
// Independently owned query data consumed by142c4b0. No widget is constructed:
// prefix/gaps contain no vtable, UI callbacks, mutex or retained menu state.
struct Context {
    std::array<std::byte,0x178> prefix{};
    std::vector<Sort> sorting;
    std::vector<std::function<bool(const Entry&,const Entry&)>> always;
    std::vector<Predicate> partitions;
    std::unordered_map<std::string,bool> ascending;
    uint8_t sortFlags=0,flags=2; // Explicit source, including an empty source.
    std::array<std::byte,6> padding{};
    std::vector<Predicate> filters;
    std::array<std::byte,0x2d8-0x220> middle{};
    std::vector<Entry> entries;
    std::array<std::byte,0x330-0x2f0> beforeActivities{};
    // The shared text filter checks this map after a name/profession miss,
    // even on a Work Details list with no Activity column. Empty is valid;
    // zero-filled unordered-map storage is not.
    df3d_residents::detail::ActivityMap activities;
    std::array<std::byte,0x428-0x370> tail{};
    std::array<int32_t,149> skills{};
    std::array<std::byte,4> alignment{};
    std::string query;
};
static_assert(sizeof(Predicate)==0x40 && sizeof(Sort)==0x60);
static_assert(offsetof(Context,sorting)==0x178 && offsetof(Context,always)==0x190);
static_assert(offsetof(Context,partitions)==0x1a8 && offsetof(Context,ascending)==0x1c0);
static_assert(offsetof(Context,flags)==0x201 && offsetof(Context,filters)==0x208);
static_assert(offsetof(Context,entries)==0x2d8 && offsetof(Context,skills)==0x428);
static_assert(offsetof(Context,activities)==0x330);
static_assert(offsetof(Context,query)==0x680);
inline bool supported() {
    static const bool ready=[] {
        if(!farmFunctions() || !df3d_residents::orderingSupported() || !df3d_residents::querySupported())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={{0x142c4b0,0x743,UINT64_C(0xc8b500f53174d212)},
            {0x1435db0,0xe2,UINT64_C(0x19e300fea6d845e9)},
            {0x46a350,0x6d,UINT64_C(0x90c96dbca3600012)},
            {0x42d8a0,0xa34,UINT64_C(0xb4aa3cc9a442495d)}};
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;}
        return true;
    }();return ready;
}
}

// Safe-point provider. Sort0=Category,1=Name,2=Profession,3=Skills. The native
// query applies filtering, stable ordering, then its selected-worker partition.
inline std::optional<std::vector<int32_t>> queryWorkDetailWorkers(int32_t index,int sort,bool descending,std::string query) {
    if(!df::global::world || !df::global::plotinfo || sort<0 || sort>3 || !work_detail_query::supported())return std::nullopt;
    const auto& details=df::global::plotinfo->labor_info.work_details;
    if(index<0 || size_t(index)>=details.size() || details.size()>128 || !details[size_t(index)])return std::nullopt;
    auto* detail=details[size_t(index)];if(detail->assigned_units.size()>1024)return std::nullopt;
    using namespace work_detail_query;
    Context context;
    // Inline setup belongs to the widget constructor42cd50, not a callable
    // semantic leaf. Preserve its pinned labor-to-skill union in owned storage.
    constexpr std::pair<int16_t,int16_t> weights[]={
        {0,0},{10,1},{11,2},{12,135},{13,136},{14,3},{15,4},{16,5},{17,6},
        {18,58},{19,59},{20,60},{21,61},{22,57},{25,10},{26,11},{27,8},{28,35},
        {29,12},{30,14},{31,65},{32,13},{33,15},{34,16},{35,17},{36,18},{37,19},
        {38,20},{39,21},{40,22},{41,23},{42,9},{43,7},{44,43},{44,51},{44,98},
        {44,56},{45,24},{46,26},{47,27},{48,28},{49,33},{50,29},{51,30},{52,31},
        {53,32},{54,36},{55,34},{56,25},{57,46},{58,47},{59,48},{60,54},
        {61,66},{62,64},{63,67},{64,63},{65,68},{66,107},{67,108},{68,109},
        {69,110},{70,111},{71,112},{72,113},{78,115},{81,131},{82,132}};
    for(const auto& [labor,skill]:weights)if(detail->allowed_labors[labor])context.skills[skill]=1;
    for(auto* unit:df::global::world->units.active) {
        const auto allowed=workshopWorkerAllowed(unit);if(!allowed)return std::nullopt;
        if(*allowed)context.entries.push_back({unit});
    }
    context.query=std::move(query);df3d_area::staffOrderingFunctions().normalize(&context.query);
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    struct Closure {uintptr_t unused=0;Context* value;};
    Closure closure{0,&context};auto* pointer=&context;
    context.filters.emplace_back([&](const Entry& entry) {
        return reinterpret_cast<bool(*)(Context**,const Entry*)>(base+0x1424c30)(&pointer,&entry);
    });
    constexpr size_t comparators[]={0x1431370,0x1435a10,0x14358c0,0x1435db0};
    constexpr const char* names[]={"Cat","Name","Prof","Skills"};
    const auto compare=reinterpret_cast<bool(*)(Closure*,const Entry*,const Entry*)>(base+comparators[sort]);
    context.sorting.push_back({[&](const Entry& a,const Entry& b) {
        return compare(&closure,&a,&b);
    },names[sort]});
    context.ascending.emplace(names[sort],descending);
    struct Selection {uintptr_t unused=0;df::work_detail* value;};Selection selected{0,detail};
    context.partitions.emplace_back([&](const Entry& entry) {
        return reinterpret_cast<bool(*)(Selection*,const Entry*)>(base+0x46a350)(&selected,&entry);
    });
    std::vector<Entry> ordered;
    reinterpret_cast<void(*)(Context*,std::vector<Entry>*)>(base+0x142c4b0)(&context,&ordered);
    std::vector<int32_t> result;result.reserve(ordered.size());
    for(const auto& entry:ordered){if(entry.kind!=0 || !entry.unit)return std::nullopt;result.push_back(entry.unit->id);}
    return result;
}
}
