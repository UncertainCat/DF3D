#pragma once
#include "df/building_wellst.h"
#include <windows.h>
#include <cstdint>
#include <optional>

namespace df3d_production {
// Native building-sheet189edf calls560b60 directly. The routine reads installed
// bucket capacity and the well column, with no selected-sheet/menu input.
// Preserve native refusal codes: -1 operational,84 no bucket,85 full,86 dry.
inline std::optional<int16_t> wellStatus(df::building* building) {
    if(!building || building->getType()!=df::building_type::Well ||
       building->getBuildStage()!=building->getMaxBuildStage())return {};
    static const bool ready=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x3ad;++i){hash^=base[0x560b60+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0x1e6023461b843633);
    }();
    if(!ready)return {};
    using Read=int16_t(__fastcall*)(df::building_wellst*);
    const auto base=reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    const auto status=reinterpret_cast<Read>(base+0x560b60)(static_cast<df::building_wellst*>(building));
    if(status!=-1 && status!=84 && status!=85 && status!=86)return {};
    return status;
}
}
