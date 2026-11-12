#pragma once
#include "df/crime.h"
#include "df/world.h"
#include "df/plotinfost.h"
#include "df/unit.h"
#include "df/witness_reportst.h"
#include "unit_description_native.h"
#include "location_staff_order_native.h"
#include <algorithm>
#include <array>
#include <vector>
#include <optional>
#include <string>
#include <unordered_map>
#include <variant>

namespace df3d_justice {
struct CandidateFact {int32_t unitId=-1,rank=0;uint32_t flags=0;};
enum class CaseResolution : uint8_t {Unsolved=1,Convicted=2,UnknownConvict=3};
struct CaseSummary {CaseResolution resolution=CaseResolution::Unsolved;std::optional<std::string> injuredParty;std::string status;};
// Native46db60 builds widgets around these inline branches; there is no plain
// summary formatter. Isolate its semantic selection and use the same native
// name formatter on owned units. Missing victims produce no injured-party row.
inline std::optional<CaseSummary> caseSummary(const df::crime* crime) {
    if(!crime || !df::global::world || !df3d_creature::inventoryDescriptionReady())return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    if(reinterpret_cast<uint8_t*>(&df::global::world->units.all)!=base+0x23e50b0)return std::nullopt;
    static const bool pinned=[base] {
        uint64_t h=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x700;++i){h^=base[0x46db60+i];h*=UINT64_C(1099511628211);}
        return h==UINT64_C(0x323159eb80349041);
    }();
    if(!pinned)return std::nullopt;
    static_assert(offsetof(df::crime,victim)==0x70 && offsetof(df::crime,accused)==0x40);
    df3d_creature::InventoryRandomRestore restore(base);
    const auto name=[base](df::unit* unit)->std::optional<std::string> {
        if(unit->inventory.size()>10000)return std::nullopt;
        for(const auto* entry:unit->inventory)if(!entry)return std::nullopt;
        df3d_creature::InventoryDescriptionContext owned(*unit);
        std::string result;
        reinterpret_cast<void(*)(df::unit*,std::string*,bool)>(base+0x1330c30)(owned.unit(),&result,false);
        if(result.size()>16384)return std::nullopt;
        return result;
    };
    CaseSummary result;
    if(auto* victim=df::unit::find(crime->victim)) {
        const auto text=name(victim);if(!text)return std::nullopt;
        result.injuredParty="Injured party: "+*text+".";
    }
    if(crime->accused==-1)result.status="Unsolved.";
    else if(auto* accused=df::unit::find(crime->accused)) {
        const auto text=name(accused);if(!text)return std::nullopt;
        result.resolution=CaseResolution::Convicted;result.status="Convicted: "+*text+".";
    }else {result.resolution=CaseResolution::UnknownConvict;result.status="Unknown convict.";}
    return result;
}
struct WitnessDates {std::string date,reported;};
// Case-detail builder473a8d..473ed30 uses the standalone tick and integer
// formatters. Preserve its year source for Reported (report.year, not
// reported_year); never invoke the widget builder to obtain these strings.
inline std::optional<WitnessDates> witnessDates(const df::witness_reportst& report) {
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool pinned=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x7734e0,0x199,UINT64_C(0xb71d7de6d18f9da5)},
            {0x773390,0x150,UINT64_C(0x4549a748969f469c)},
            {0x52c130,0xb3,UINT64_C(0xf2e358ad54df1c09)},
            {0x52c2b0,0xd8,UINT64_C(0x38b6489e35387929)},
            {0x473a8d,0x443,UINT64_C(0x49141d410fe3dec1)},
        };
        for(const auto& p:pins){uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<p.length;++i){h^=base[p.rva+i];h*=UINT64_C(1099511628211);}
            if(h!=p.hash)return false;}
        return true;
    }();
    if(!pinned)return std::nullopt;
    static_assert(offsetof(df::witness_reportst,year)==0xc);
    static_assert(offsetof(df::witness_reportst,year_tick)==0x10);
    static_assert(offsetof(df::witness_reportst,reported_year_tick)==0x74);
    using Format=void(*)(int32_t,std::string*);
    std::string year,date,reported;
    reinterpret_cast<Format>(base+0x52c2b0)(report.year,&year);
    reinterpret_cast<Format>(base+0x7734e0)(report.year_tick,&date);
    reinterpret_cast<Format>(base+0x7734e0)(report.reported_year_tick,&reported);
    return WitnessDates{"Date: "+date+", "+year,"Reported: "+reported+", "+year};
}
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
// Search1424c30 reads only this owned map and normalized query. Justice's
// picker has no CUR_JOB option, so its job-search map remains empty.
struct CandidateSearch {
    std::array<std::byte,0x330> prefix{};
    std::unordered_map<std::variant<df::unit*,df::item*>,std::string> jobs;
    std::array<std::byte,0x310> gap{};
    std::string query;
};
static_assert(offsetof(CandidateSearch,jobs)==0x330);
static_assert(offsetof(CandidateSearch,query)==0x680);
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
enum class CandidateColumn:uint8_t {Category,Name,Profession,Crime};
struct CandidateSort {CandidateColumn column;bool reverse=false;};
// Convict picker search, with native default Crime then Name priorities.
// The generic widget builder142c4b0 has no standalone list boundary. Adapt its
// stable sort pipeline over owned facts, calling the semantic visibility/name
// readers. Never call487db0: that comparator reads the global Justice map.
inline std::optional<std::vector<CandidateFact>> orderedCandidateFacts(const std::vector<CandidateFact>& input,std::string query,
    std::vector<CandidateSort> sorts,bool ascendingRank=false) {
    if(sorts.size()>65536)return std::nullopt;
    if(sorts.empty())sorts.push_back({CandidateColumn::Category,false});
    std::array<int8_t,4> directions{-1,-1,-1,-1};std::vector<CandidateSort> priorities;
    for(const auto& sort:sorts){const auto column=size_t(sort.column);if(column>=directions.size())return std::nullopt;
        if(directions[column]>=0){if(bool(directions[column])!=sort.reverse)return std::nullopt;continue;}
        directions[column]=int8_t(sort.reverse);priorities.push_back(sort);}
    const auto* facts=&input;
    const auto& text=df3d_area::staffOrderingFunctions();
    if(!facts || !text || query.size()>512 || !df3d_creature::inventoryDescriptionReady())return std::nullopt;
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool pinned=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x487db0,0x94,UINT64_C(0xe48b5fbbfc0a83b0)},
            {0x487c90,0x31,UINT64_C(0xdd03a6e3629b5c52)},
            {0x1435a10,0x110,UINT64_C(0x98ce3d80a8c10b09)},
            {0x1431370,0x64,UINT64_C(0x5854757b83da8810)},
            {0x14358c0,0x110,UINT64_C(0x7476642b05457b5b)},
            {0x1425170,0x89,UINT64_C(0x86b6c3e85719b169)},
            {0x14240d0,0x89,UINT64_C(0x4b41b81d7b2cdc3e)},
            {0x142c4b0,0x73e,UINT64_C(0x2dcc9b7815303ef5)},
            {0x1424c30,0x218,UINT64_C(0x14952fd1a693777f)},
            {0x3c9c30,0xe7,UINT64_C(0x3eae3e81c7aa002f)},
            {0xe1990,0xc7,UINT64_C(0x1c45e5635f4ffde2)},
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
    detail::CandidateSearch search;search.query=std::move(query);text.normalize(&search.query);
    auto* searchPointer=&search;
    struct Row {CandidateFact fact;std::string name,profession;std::array<int32_t,2> category{};};
    std::vector<Row> rows;rows.reserve(facts->size());
    df3d_creature::InventoryRandomRestore restore(base);
    for(const auto& fact:*facts) {
        auto* unit=df::unit::find(fact.unitId);if(!unit)return std::nullopt;
        if(reinterpret_cast<bool(*)(df::unit*)>(base+0x137bd50)(unit))continue;
        if(unit->inventory.size()>10000)return std::nullopt;
        for(const auto* entry:unit->inventory)if(!entry)return std::nullopt;
        df3d_creature::InventoryDescriptionContext owned(*unit);
        const df3d_area::StaffUnitReference reference{owned.unit()};
        if(reinterpret_cast<bool(*)(detail::CandidateSearch**,const df3d_area::StaffUnitReference*)>(base+0x1424c30)(&searchPointer,&reference))continue;
        Row row{fact,{}};text.name(owned.unit(),&row.name,false);text.normalize(&row.name);
        if(directions[size_t(CandidateColumn::Profession)]>=0){text.profession(owned.unit(),&row.profession,false);text.normalize(&row.profession);}
        if(directions[size_t(CandidateColumn::Category)]>=0){
            // Pinned1425050 is read-only and needs status/curse fields outside
            // the inventory/name context. Its tagged input is independently
            // owned; the referenced unit is authoritative simulation data.
            const df3d_area::StaffUnitReference categoryReference{unit};text.category(&row.category,&categoryReference);
        }
        if(row.name.size()>16384 || row.profession.size()>16384)return std::nullopt;
        rows.push_back(std::move(row));
    }
    // Native142c879 applies stable sorts from the last priority to the first.
    // Equivalent keys retain source order. Duplicate priorities share one native
    // direction entry, so only their first occurrence can affect the result.
    std::stable_sort(rows.begin(),rows.end(),[&](const Row& a,const Row& b) {
        for(const auto& sort:priorities){int order=0;
            switch(sort.column){
                case CandidateColumn::Category:order=a.category<b.category?-1:a.category>b.category?1:0;break;
                case CandidateColumn::Name:order=a.name.compare(b.name);break;
                case CandidateColumn::Profession:order=a.profession.compare(b.profession);break;
                case CandidateColumn::Crime:order=a.fact.rank>b.fact.rank?-1:a.fact.rank<b.fact.rank?1:0;if(ascendingRank)order=-order;break;
            }
            if(order)return sort.reverse?order>0:order<0;
        }
        return false;
    });
    std::vector<CandidateFact> result;result.reserve(rows.size());
    for(const auto& row:rows)result.push_back(row.fact);
    return result;
}
inline std::optional<std::vector<CandidateFact>> convictionCandidates(const df::crime* crime,std::string query={},
    std::vector<CandidateSort> sorts={{CandidateColumn::Crime,false},{CandidateColumn::Name,false}}) {
    const auto facts=candidateFacts(crime);if(!facts)return std::nullopt;
    return orderedCandidateFacts(*facts,std::move(query),std::move(sorts));
}
// Interrogate rebuilds the same filtered/sorted list, then stable-partitions
// selected entries first (142cb85 ->1430be0). Native1432690/1433fe0 read the
// widget's selected set; use the independently observed crime flag instead.
// A checkbox alone does not rebuild native row order. The presentation retains
// that order until an explicit search/sort/reopen triggers this query again.
inline std::optional<std::vector<CandidateFact>> interrogationCandidates(const df::crime* crime,std::string query={},
    std::vector<CandidateSort> sorts={{CandidateColumn::Crime,false},{CandidateColumn::Name,false}}) {
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    static const bool pinned=[base] {
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x1a6;++i){hash^=base[0x1430be0+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0xda252c1126314abf);
    }();
    if(!pinned)return std::nullopt;
    auto rows=convictionCandidates(crime,std::move(query),std::move(sorts));if(!rows)return std::nullopt;
    std::stable_partition(rows->begin(),rows->end(),[](const CandidateFact& row){return bool(row.flags&1);});
    return rows;
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
