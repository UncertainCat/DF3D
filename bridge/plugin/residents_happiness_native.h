#pragma once
#include "residents_activity_native.h"

namespace df3d_residents {
inline bool happinessSupported() {
    static const bool ready=[] {
        if(!activitySupported())return false;
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        struct Pin {size_t rva,length;uint64_t hash;};
        constexpr Pin pins[]={
            {0x1428db0,0x2f8,UINT64_C(0x68c5a1ed918c5bf3)},
            {0x142e310,0x2d7,UINT64_C(0x116fafa02c0043bc)},
            {0x30c5f0,0x34,UINT64_C(0xc70e9bfc0f980e09)},
            {0x1432890,0x2b,UINT64_C(0xb58f484d6d9273b0)},
            {0xf17b0,0xf,UINT64_C(0xac779f1a015d8e50)},
            {0x1433db0,0x14,UINT64_C(0xe493c01c52bb9a3)},
            {0xf1a90,0xd,UINT64_C(0x966f6da0b46f8407)},
            {0xf1a70,0x12,UINT64_C(0x7924f0768e34c1e4)},
            {0x2446e0,0x136,UINT64_C(0xa467a02b1bd3d595)},
            {0x2470c0,0x5a,UINT64_C(0x53741b6681acfaaa)},
            {0xf2610,0x6a,UINT64_C(0x5ebfd6a646879611)},
        };
        for(const auto& pin:pins) {
            uint64_t hash=UINT64_C(14695981039346656037);
            for(size_t i=0;i<pin.length;++i){hash^=base[pin.rva+i];hash*=UINT64_C(1099511628211);}
            if(hash!=pin.hash)return false;
        }
        return true;
    }();return ready;
}
// Native displayed tier, happiest0 through most distressed6. Mood overrides
// and missing-soul behavior stay inside DF's constructor, not a copied cutoff
// table. Its hover callback is retained only in this independently owned tree;
// no callback, widget feed, layout or render may execute.
inline std::optional<uint8_t> happinessTier(df::unit* unit) {
    if(!unit || !happinessSupported())return std::nullopt;
    auto row=ownedRow();if(!row)return std::nullopt;
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    using Produce=void (*)(std::shared_ptr<df::widget_container>,df::unit*);
    reinterpret_cast<Produce>(const_cast<uint8_t*>(base+0x1428db0))(row,unit);
    const auto found=row->children_by_name.find("Happiness indicator");
    if(found==row->children_by_name.end() || found->second->displaying_tooltip)return std::nullopt;
    // Factory142e310 builds widget + one native indicator enum at0x150.
    static_assert(sizeof(df::widget)==0x150);
    int32_t indicator=-1;
    std::memcpy(&indicator,reinterpret_cast<const uint8_t*>(found->second.get())+sizeof(df::widget),sizeof(indicator));
    if(indicator<6 || indicator>12)return std::nullopt;
    return uint8_t(indicator-6);
}
}
