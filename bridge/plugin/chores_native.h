#pragma once
#include "standing_orders_native.h"
#include "location_staff_order_native.h"
#include "labor_eligibility_cache.h"
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
}
