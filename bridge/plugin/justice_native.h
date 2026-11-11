#pragma once
#include "df/crime.h"
#include "df/world.h"
#include "df/plotinfost.h"
#include "df/unit.h"
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
