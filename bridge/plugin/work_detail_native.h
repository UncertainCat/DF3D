#pragma once
#include <algorithm>
#include "farm_native.h"
#include "df/plotinfost.h"
#include "df/work_detail.h"
#include "df/unit.h"
#include "location_staff_order_native.h"
#include "location_staff_mutation_native.h"

namespace df3d_production {
// Match citizens.lua receipt()/detail_info(): list headers plus the selected
// membership vector. This is DF3D request identity, not native menu state.
// Optional owned labors predict the receipt of a definition-only commit without
// temporarily changing simulation state while preparing an allocation-safe reply.
inline std::optional<uint64_t> workDetailReceipt(int32_t index,const std::array<bool,94>* ownedLabors=nullptr) {
    if(!df::global::plotinfo)return std::nullopt;
    const auto& all=df::global::plotinfo->labor_info.work_details;
    if(index<0 || size_t(index)>=all.size() || all.size()>128)return std::nullopt;
    constexpr uint64_t seed=UINT64_C(0xcbf29ce484222325);
    const auto byte=[](uint64_t h,uint8_t value){return (h^value)*UINT64_C(0x100000001b3);};
    const auto integer=[&](uint64_t h,uint64_t value){
        for(int i=0;i<8;++i){h=byte(h,uint8_t(value));value>>=8;}return h;
    };
    const auto revision=[](uint64_t h){h&=UINT64_C(0x7fffffffffffffff);return h?h:1;};
    uint64_t headers=integer(seed,all.size());
    size_t detailIndex=0;
    for(const auto* detail:all) {
        if(!detail)return std::nullopt;
        headers=integer(headers,detail->name.size());
        for(unsigned char ch:detail->name)headers=byte(headers,ch);
        headers=integer(headers,detail->flags.whole);
        headers=integer(headers,int64_t(detail->icon));
        const auto& labors=ownedLabors && detailIndex==size_t(index)?*ownedLabors:detail->allowed_labors;
        for(bool allowed:labors)headers=byte(headers,allowed?1:0);
        ++detailIndex;
        headers=integer(headers,detail->assigned_units.size());
    }
    const auto& members=all[size_t(index)]->assigned_units;
    if(members.size()>1024)return std::nullopt;
    uint64_t membership=seed;
    for(int32_t id:members)membership=integer(membership,int64_t(id));
    return revision(integer(integer(seed,revision(headers)),membership));
}
// These closure bodies consume only explicit simulation pointers. The unused
// leading slots are owned padding, not vtables or borrowed native widgets.
inline bool nativeWorkDetailEdit(int32_t index,int32_t mode,bool reset) {
    if(!farmFunctions() || !df::global::plotinfo || !df::global::world)return false;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    static const bool supported=[&] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={{0x468760,0x69,UINT64_C(0x5eb42948ad8aef26)},
            {0x468660,0x4e,UINT64_C(0xbaef94519752815d)},
            {0x468560,0x4e,UINT64_C(0x7412463ed1cac4d0)},
            {0x468940,0x16c,UINT64_C(0x0ececdab2a29b2ca)}};
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;}
        return true;
    }();
    if(!supported)return false;
    const auto& all=df::global::plotinfo->labor_info.work_details;
    if(index<0 || size_t(index)>=all.size() || all.size()>128)return false;
    auto* detail=all[size_t(index)];if(!detail)return false;
    if(reset) {
        if(!detail->flags.bits.no_modify)return false;
        struct Context {std::array<std::byte,0x20> unused{};df::work_detail* detail;};
        static_assert(offsetof(Context,detail)==0x20);
        Context context{{},detail};
        return reinterpret_cast<bool(*)(Context*)>(base+0x468940)(&context);
    }
    if(mode<1 || mode>3 || (mode==1 && detail->flags.bits.cannot_be_everybody))return false;
    struct Context {uintptr_t unused=0;df::work_detail* detail;};
    static_assert(offsetof(Context,detail)==8);
    Context context{0,detail};
    constexpr size_t handlers[]={0,0x468760,0x468560,0x468660};
    return reinterpret_cast<bool(*)(Context*)>(base+handlers[mode])(&context);
}
// Semantic portion of Delete468b60..468c43: remove the explicit definition and
// recalculate every active unit. Native widget rebuild42f190 is deliberately
// outside this adapter. Retain the detached object because native widgets may
// still reference it; the bridge owns the bounded slot before the first write.
inline bool nativeWorkDetailDelete(int32_t index,void*& retired) {
    const auto& functions=df3d_area::staffMutationFunctions();
    if(!functions || !df::global::plotinfo || !df::global::world || retired)return false;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    static const bool supported=[&] {
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0xe3;++i){hash^=base[0x468b60+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0x6c77ff90a821251c);
    }();
    if(!supported)return false;
    auto& all=df::global::plotinfo->labor_info.work_details;
    if(index<0 || size_t(index)>=all.size() || all.size()>128)return false;
    auto* detail=all[size_t(index)];if(!detail || detail->flags.bits.no_modify)return false;
    // Native removes every matching pointer; malformed aliasing is rejected
    // before mutation instead of retiring the same allocation more than once.
    if(std::count(all.begin(),all.end(),detail)!=1)return false;
    for(const auto* unit:df::global::world->units.active)if(!unit)return false;
    retired=detail;
    all.erase(all.begin()+index);
    for(auto* unit:df::global::world->units.active)functions.labors(unit);
    return true;
}
// Work Details46c900 delegates to this simulation-only closure body. Unlike
// creature Labor's inline handler, it accepts an explicit work-detail pointer.
inline bool nativeWorkDetailMembership(int32_t index,int32_t unitId,bool member) {
    if(!farmFunctions() || !df::global::plotinfo || !df::global::world)return false;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    static const bool supported=[&] {
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x265;++i){hash^=base[0x42ef20+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0x6a11a5c233a29fc5);
    }();
    if(!supported)return false;
    const auto& all=df::global::plotinfo->labor_info.work_details;
    if(index<0 || size_t(index)>=all.size() || all.size()>128)return false;
    for(const auto* detail:all)if(!detail || detail->assigned_units.size()>1024)return false;
    auto* unit=df::unit::find(unitId);if(!unit)return false;
    auto* selected=all[size_t(index)];
    const df3d_area::StaffUnitReference reference{unit};
    reinterpret_cast<void(*)(df::work_detail**,const df3d_area::StaffUnitReference*,bool)>(base+0x42ef20)(&selected,&reference,member);
    return true;
}
struct WorkDetailDefaults {std::string name;int32_t icon=10;};
// Native42f8a0 combines construction with a Labor widget rebuild. Its name
// uniqueness and icon-balancing branches are inline, so pin those branches;
// use the separate native suffix formatter on an owned string. Never call the
// screen callback or inspect its widgets. Safe-point simulation reads only.
inline std::optional<WorkDetailDefaults> nativeWorkDetailDefaults() {
    if(!farmFunctions() || !df::global::plotinfo)return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    static const bool supported=[&] {
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={{0x42f93b,0x15c,UINT64_C(0x4de121376a258c60)},
            {0x52c130,0x30,UINT64_C(0xbbc32f0ecc0060be)}};
        for(const auto& pin:pins){uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;}
        return true;
    }();
    if(!supported)return std::nullopt;
    const auto& all=df::global::plotinfo->labor_info.work_details;
    if(all.size()>128)return std::nullopt;
    for(const auto* detail:all)if(!detail)return std::nullopt;
    WorkDetailDefaults result;
    int suffix=1;
    for(;suffix<=99;++suffix) {
        result.name.assign(reinterpret_cast<const char*>(base+0x163d018),14);
        reinterpret_cast<void(*)(int32_t,std::string*)>(base+0x52c130)(suffix,&result.name);
        bool used=false;for(const auto* detail:all)if(detail->name==result.name){used=true;break;}
        if(!used)break;
    }
    if(suffix==100)result.name.assign(reinterpret_cast<const char*>(base+0x163d008),13);
    std::array<uint32_t,8> counts{};
    for(const auto* detail:all){const int icon=int(detail->icon);if(icon>=10 && icon<=17)++counts[size_t(icon-10)];}
    size_t least=0;for(size_t i=1;i<counts.size();++i)if(counts[i]<counts[least])least=i;
    result.icon=int32_t(least)+10;
    return result;
}
}
