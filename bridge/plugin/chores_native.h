#pragma once
#include "standing_orders_native.h"
#include "location_staff_order_native.h"
#include "labor_eligibility_cache.h"
#include "location_staff_mutation_native.h"
#include "work_detail_settings_native.h"
#include <algorithm>
#include <cstddef>

namespace df3d_chores {
inline uint8_t* supportedBase() {
    auto* base=df3d_standing::supportedBase();
    if(!base || !df3d_area::staffOrderingFunctions())return nullptr;
    static const bool valid=[base] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x42c6e0,0x663,UINT64_C(0xb255abee7d7c66c4)},
            {0x4340a3,0x244,UINT64_C(0xed00155b8d57c027)},
            {0x13b99b0,0x250,UINT64_C(0x2846bbdb177934c5)},
            {0xb530b0,0xac,UINT64_C(0x7c6f66602bdab157)},
            {0xb972c0,0xf8,UINT64_C(0x462a923de0759a7a)},
            {0xbbef0,0xad,UINT64_C(0xa7990fc1186ffa89)},
            {0xbbd90,0xad,UINT64_C(0x18680dd18e5ba980)},
            {0xbbe40,0xad,UINT64_C(0x062a266340f9bf38)}};
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;}
        return true;
    }();
    return valid?base:nullptr;
}
// Native42c6e0 is a roster/catalog builder, not an input/render dispatcher.
// Its only context writes are these owned fields. No widget, vtable, live menu
// source, scroll state or callback is supplied. Native owns eligibility/order.
struct Context {
    std::array<std::byte,0x150> prefix{};
    int32_t category=0;
    int32_t alignment=0;
    std::vector<df::unit*> children;
    std::vector<int32_t> labors;
    int32_t laborFirst=0;
    bool laborDragging=false;
    std::array<std::byte,3> laborPadding{};
    int32_t childFirst=0;
    bool childDragging=false;
    std::array<std::byte,3> childPadding{};
};
static_assert(offsetof(Context,children)==0x158 && offsetof(Context,labors)==0x170);
static_assert(offsetof(Context,laborFirst)==0x188 && offsetof(Context,childDragging)==0x194);
struct Snapshot {
    bool enabled=false;
    std::vector<int32_t> children,exempted;
    std::vector<std::pair<int32_t,bool>> labors;
};
inline std::optional<Snapshot> read() {
    auto* base=supportedBase();
    if(!base || !df::global::world || !df::global::plotinfo)return std::nullopt;
    const auto& active=df::global::world->units.active;
    if(active.size()>65536)return std::nullopt;
    const auto& settings=df::global::plotinfo->labor_info;
    if(reinterpret_cast<const uint8_t*>(&settings.flags)!=base+0x2399978 ||
       reinterpret_cast<const uint8_t*>(settings.chores.data())!=base+0x2399998 ||
       reinterpret_cast<const uint8_t*>(&settings.chores_exempted_children)!=base+0x23999f8 ||
       settings.chores_exempted_children.size()>65536)return std::nullopt;
    const auto& exempted=settings.chores_exempted_children;
    if(!std::is_sorted(exempted.begin(),exempted.end()) ||
       std::adjacent_find(exempted.begin(),exempted.end())!=exempted.end())return std::nullopt;
    df3d_creature::LaborEligibilityCacheRestore restore;
    for(auto* unit:active)if(!restore.capture(unit,df::global::plotinfo->group_id))return std::nullopt;
    Context owned;
    reinterpret_cast<void(*)(Context*)>(base+0x42c6e0)(&owned);
    if(owned.children.size()>active.size() || owned.labors.size()!=14)return std::nullopt;
    Snapshot result;result.enabled=settings.flags.bits.children_do_chores;
    result.exempted=exempted;
    for(auto* unit:owned.children){if(!unit || unit->id<0)return std::nullopt;result.children.push_back(unit->id);}
    for(int32_t id:owned.labors){if(id<0 || size_t(id)>=settings.chores.size())return std::nullopt;
        result.labors.emplace_back(id,settings.chores[size_t(id)]);}
    return result;
}
struct Caption {int32_t id=-1;std::string text;};
struct Captions {std::vector<Caption> children,labors;};
// Chores renderer43703b uses name(unit, owned, false), and437736 uses the
// same labor formatter as Work Details. Return full native strings; viewport
// truncation is local presentation work, never a reason to alter the receipt.
inline std::optional<Captions> captions(const Snapshot& snapshot) {
    if(!supportedBase() || !df3d_production::work_detail_settings::supported())return std::nullopt;
    const auto& names=df3d_area::staffOrderingFunctions();
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    Captions result;
    result.children.reserve(snapshot.children.size());result.labors.reserve(snapshot.labors.size());
    for(int32_t id:snapshot.children) {
        auto* unit=df::unit::find(id);if(!unit)return std::nullopt;
        std::string text;names.name(unit,&text,false);
        if(text.empty() || text.size()>4096)return std::nullopt;
        result.children.push_back({id,std::move(text)});
    }
    for(const auto& row:snapshot.labors) {
        std::string text;reinterpret_cast<void(*)(std::string*,int32_t)>(base+0xacb830)(&text,row.first);
        if(text.empty() || text.size()>512)return std::nullopt;
        result.labors.push_back({row.first,std::move(text)});
    }
    return result;
}

enum class Operation {Enabled=1,Labor=2,Exempt=3};
enum class Outcome {Rejected=0,Applied=1,Stale=2};
inline bool same(const Snapshot& a,const Snapshot& b) {
    return a.enabled==b.enabled && a.children==b.children &&
        a.exempted==b.exempted && a.labors==b.labors;
}
// Native input mutates these simulation fields inline, then invokes4390d0.
// Prepare the replacement exemption vector before the first write. A caller
// must treat failure after writeStarted as Unknown, never replay it.
inline Outcome apply(Operation operation,int32_t id,bool desired,const Snapshot& expected,bool* writeStarted=nullptr) {
    const auto& functions=df3d_area::staffMutationFunctions();
    if(!functions)return Outcome::Rejected;
    const auto current=read();if(!current)return Outcome::Rejected;
    if(!same(*current,expected))return Outcome::Stale;
    auto& settings=df::global::plotinfo->labor_info;
    df::unit* child=nullptr;
    std::vector<int32_t> exemptions;
    switch(operation) {
    case Operation::Enabled:
        if(id!=-1)return Outcome::Rejected;
        break;
    case Operation::Labor:
        if(std::none_of(current->labors.begin(),current->labors.end(),[id](const auto& row){return row.first==id;}))return Outcome::Rejected;
        break;
    case Operation::Exempt:
        if(std::find(current->children.begin(),current->children.end(),id)==current->children.end())return Outcome::Rejected;
        child=df::unit::find(id);if(!child)return Outcome::Rejected;
        exemptions=current->exempted;
        {auto it=std::lower_bound(exemptions.begin(),exemptions.end(),id);
        const bool exists=it!=exemptions.end() && *it==id;
        if(desired && !exists)exemptions.insert(it,id);
        else if(!desired && exists)exemptions.erase(it);}
        break;
    default:return Outcome::Rejected;
    }
    if(writeStarted)*writeStarted=true;
    if(operation==Operation::Enabled)settings.flags.bits.children_do_chores=desired;
    else if(operation==Operation::Labor)settings.chores[size_t(id)]=desired;
    else settings.chores_exempted_children.swap(exemptions);
    if(child)functions.labors(child);
    else for(auto* unit:df::global::world->units.active)functions.labors(unit);
    return Outcome::Applied;
}

}
