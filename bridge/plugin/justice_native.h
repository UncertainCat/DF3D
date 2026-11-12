#pragma once
#include "df/crime.h"
#include "df/world.h"
#include "df/plotinfost.h"
#include "df/unit.h"
#include "unit_description_native.h"
#include "location_staff_order_native.h"
#include <algorithm>
#include <array>
#include <vector>
#include <optional>
#include <string>
#include <unordered_map>

namespace df3d_justice {
struct CandidateFact {int32_t unitId=-1,rank=0;uint32_t flags=0;};
namespace detail {
// Native46e260 consumes only these two maps from its first argument. This is
// owned data storage, not a widget: no vtable, callbacks or native menu borrow.
struct CandidateContext {
    std::array<std::byte,0x360> prefix{};
    std::unordered_map<df::unit*,int32_t> ranks;
    std::unordered_map<df::unit*,uint32_t> flags;
};
static_assert(sizeof(std::unordered_map<df::unit*,int32_t>)==0x40);
static_assert(offsetof(CandidateContext,ranks)==0x360);
static_assert(offsetof(CandidateContext,flags)==0x3a0);
}
inline std::optional<std::vector<CandidateFact>> candidateFacts(const df::crime* crime) {
    auto* world=df::global::world;
    if(!crime || !world || world->units.active.size()>1048576)return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    if(reinterpret_cast<uint8_t*>(&world->units.active)!=base+0x23e50c8)return std::nullopt;
    static const bool pinned=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x46e260,0x333,UINT64_C(0xb8efe10280fed5ee)},
            {0x4857c0,0x2ec,UINT64_C(0x577d8e87ebb2ebc1)},
            {0x138ed20,0xff,UINT64_C(0x430951f9f3e403c2)},
        };
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;}
        return true;
    }();
    if(!pinned)return std::nullopt;
    for(const auto* unit:world->units.active)if(!unit)return std::nullopt;
    const auto ownedCrime=*crime;
    detail::CandidateContext context;
    reinterpret_cast<void(*)(detail::CandidateContext*,const df::crime*)>(base+0x46e260)(&context,&ownedCrime);
    std::vector<CandidateFact> result;result.reserve(world->units.active.size());
    for(auto* unit:world->units.active) {
        const auto rank=context.ranks.find(unit);const auto flags=context.flags.find(unit);
        if(rank==context.ranks.end() || flags==context.flags.end())return std::nullopt;
        result.push_back({unit->id,rank->second,flags->second});
    }
    return result;
}
using Cases=std::array<std::vector<int32_t>,3>; // Open, Closed, Cold.
// Initial Convict picker: empty search, native Crime then Name priorities.
// The generic widget builder142c4b0 has no standalone list boundary. Adapt its
// stable sort pipeline over owned facts, calling the semantic visibility/name
// readers. Never call487db0: that comparator reads the global Justice map.
inline std::optional<std::vector<CandidateFact>> initialConvictionCandidates(const df::crime* crime) {
    const auto facts=candidateFacts(crime);
    const auto& text=df3d_area::staffOrderingFunctions();
    if(!facts || !text || !df3d_creature::inventoryDescriptionReady())return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool pinned=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x487db0,0x94,UINT64_C(0xe48b5fbbfc0a83b0)},
            {0x487c90,0x31,UINT64_C(0xdd03a6e3629b5c52)},
            {0x1435a10,0x110,UINT64_C(0x98ce3d80a8c10b09)},
            {0x14240d0,0x89,UINT64_C(0x4b41b81d7b2cdc3e)},
            {0x142c4b0,0x73e,UINT64_C(0x2dcc9b7815303ef5)},
            {0x137bd50,0x2d0,UINT64_C(0xdee22d5bacd12bc9)},
            {0x1367430,0xc6,UINT64_C(0xc0292be8a6dacf2c)},
            {0xc8be10,0x14c,UINT64_C(0x1ba19b485a3fa56b)},
            {0xc8baa0,0x11a,UINT64_C(0x2c62fce4a0555c66)},
            {0xedfa60,0xbd,UINT64_C(0x2f89116df6b958cc)},
            {0xedfb20,0x13,UINT64_C(0xa222e60f2f8301e4)},
            {0x14db50,0xb1,UINT64_C(0x4b9c987ca0656b35)},
            {0x14dc10,0x5a,UINT64_C(0xfb6e6c7bccbf765b)},
            {0x67270,6,UINT64_C(0x7dce27ae257f083d)},
            {0x7a840,6,UINT64_C(0xeff4222c8d49c252)},
        };
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;}
        return true;
    }();
    if(!pinned)return std::nullopt;
    struct Row {CandidateFact fact;std::string name;};
    std::vector<Row> rows;rows.reserve(facts->size());
    df3d_creature::InventoryRandomRestore restore(base);
    for(const auto& fact:*facts) {
        auto* unit=df::unit::find(fact.unitId);if(!unit)return std::nullopt;
        if(reinterpret_cast<bool(*)(df::unit*)>(base+0x137bd50)(unit))continue;
        if(unit->inventory.size()>10000)return std::nullopt;
        for(const auto* entry:unit->inventory)if(!entry)return std::nullopt;
        df3d_creature::InventoryDescriptionContext owned(*unit);
        Row row{fact,{}};text.name(owned.unit(),&row.name,false);text.normalize(&row.name);
        if(row.name.size()>16384)return std::nullopt;
        rows.push_back(std::move(row));
    }
    std::stable_sort(rows.begin(),rows.end(),[](const Row& a,const Row& b) {
        return a.fact.rank!=b.fact.rank ? a.fact.rank>b.fact.rank : a.name<b.name;
    });
    std::vector<CandidateFact> result;result.reserve(rows.size());
    for(const auto& row:rows)result.push_back(row.fact);
    return result;
}
// DF inlines this selection in widget construction470757..470f7e; there is
// no standalone list API at that boundary. Copy the audited selection only,
// preserving world-vector order. Never call the UI builder or read its lists.
inline std::optional<Cases> cases() {
    auto* world=df::global::world;auto* plot=df::global::plotinfo;
    if(!world || !plot || !df::global::cur_year || !df::global::cur_year_tick ||
       world->crimes.all.size()>1048576)return std::nullopt;
    auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    const auto at=[base](const void* address,size_t rva){return reinterpret_cast<const uint8_t*>(address)==base+rva;};
    if(!at(&world->crimes.all,0x24e7d48) || !at(&world->units.all,0x23e50b0) ||
       !at(&plot->site_id,0x2393674) || !at(&plot->group_id,0x2393678) ||
       !at(df::global::cur_year,0x23746f4) || !at(df::global::cur_year_tick,0x2387fc4))return std::nullopt;
    static const bool pinned=[base] {
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x827;++i){hash^=base[0x470757+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0xd3944d9a7b7de020);
    }();
    if(!pinned)return std::nullopt;
    static_assert(offsetof(df::crime,accused)==0x40);
    static_assert(offsetof(df::crime,flags)==0xa0);
    static_assert(offsetof(df::crime,discovered_year)==0xb0);
    static_assert(offsetof(df::crime,discovered_time)==0xb4);
    static_assert(offsetof(df::crime,site)==0xb8);
    static_assert(offsetof(df::crime,entity)==0xbc);
    Cases result;
    for(const auto* crime:world->crimes.all) {
        if(!crime || crime->id<0)return std::nullopt;
        if(!crime->flags.bits.discovered || crime->site!=plot->site_id || crime->entity!=plot->group_id)continue;
        size_t category=1;
        if(crime->flags.bits.needs_trial && !df::unit::find(crime->accused)) {
            const auto anniversary=int32_t(uint32_t(crime->discovered_year)+1U);
            const bool cold=crime->discovered_year!=-1 &&
                (anniversary<*df::global::cur_year ||
                 (anniversary==*df::global::cur_year && *df::global::cur_year_tick>=crime->discovered_time));
            category=cold?2:0;
        }
        result[category].push_back(crime->id);
    }
    return result;
}
// Native case-list construction47083f/470c89 calls this plain string builder.
// It reads crime facts, unit names and agreement details; it does not access
// Justice widgets. Both the crime value and output storage belong to this call.
inline std::optional<std::string> caption(const df::crime* crime) {
    if(!crime || !df::global::world)return std::nullopt;
    static_assert(offsetof(df::crime,mode)==4);
    static_assert(offsetof(df::crime,victim)==0x70);
    static_assert(offsetof(df::crime,agreement_id)==0x110);
    auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    static const bool pinned=[base] {
        uint64_t hash=UINT64_C(14695981039346656037);
        // Includes the full function and its19-way dispatch table.
        for(size_t i=0;i<0x4f8;++i){hash^=base[0x46d660+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0xec4ef57098e332dc);
    }();
    if(!pinned)return std::nullopt;
    const auto owned=*crime;
    std::string text;
    using Caption=std::string*(*)(std::string*,const df::crime*);
    reinterpret_cast<Caption>(const_cast<uint8_t*>(base)+0x46d660)(&text,&owned);
    if(text.size()>16384)return std::nullopt;
    return text;
}
}
