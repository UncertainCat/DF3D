#pragma once
#include "farm_native.h"
#include "df/plotinfost.h"
#include "df/work_detail.h"

namespace df3d_production {
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
