#pragma once
#include "df/building_actual.h"
#include "df/building_bridgest.h"
#include "df/building_farmplotst.h"
#include "df/building_roadst.h"
#include "df/building_design.h"
#include <array>
#include <cstring>
#include <optional>
#include <windows.h>

namespace df3d_production {
// Native slot37 leaves are read-only and stage-independent. Copy only their
// semantic inputs; never run the renderer's setBuildStage loop on live state.
inline std::optional<int32_t> pendingBuildDuration(df::building* building) {
    if(!building)return {};
    const auto type=building->getType();
    if(type==df::building_type::Stockpile || type==df::building_type::Civzone)return {};
    const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
    struct Pin {size_t rva,length;uint64_t hash;};
    static constexpr Pin pins[]={
        {0x28b9d0,0x1e,UINT64_C(0xfc23a963f0a5badb)},
        {0x548db0,0x21,UINT64_C(0x1d15d76f5caa85af)},
        {0x54a590,0x1f,UINT64_C(0xd7b04b2f857f0d68)},
        {0x54b370,0x2f,UINT64_C(0x95b7cdfbd7017355)},
        {0x54a330,0x1e,UINT64_C(0xe28caa2ddaa3c64b)},
    };
    static const bool ready=[base]{
        for(const auto& p:pins){uint64_t h=UINT64_C(14695981039346656037);
            for(size_t i=0;i<p.length;++i){h^=base[p.rva+i];h*=UINT64_C(1099511628211);}if(h!=p.hash)return false;}
        return true;
    }();
    if(!ready)return {};
    const auto* entry=(*reinterpret_cast<const void* const* const*>(building))[37];
    const size_t expected=type==df::building_type::Bridge?0x548db0:type==df::building_type::FarmPlot?0x54a590:
        (type==df::building_type::RoadDirt || type==df::building_type::RoadPaved)?0x54b370:type==df::building_type::Well?0x54a330:0x28b9d0;
    if(entry!=base+expected)return {};
    alignas(8) std::array<uint8_t,0x158> input{};
    alignas(8) std::array<uint8_t,0x18> design{};
    const auto put=[&](size_t offset,const auto& value){std::memcpy(input.data()+offset,&value,sizeof(value));};
    auto* actual=static_cast<df::building_actual*>(building);
    if(actual->design){const uint32_t flags=actual->design->flags.whole;
        std::memcpy(design.data()+0x14,&flags,sizeof(flags));const void* pointer=design.data();put(0x140,pointer);}
    if(type==df::building_type::Bridge)put(0x14c,static_cast<df::building_bridgest*>(building)->material_amount);
    else if(type==df::building_type::FarmPlot)put(0x150,static_cast<df::building_farmplotst*>(building)->material_amount);
    else if(type==df::building_type::RoadDirt || type==df::building_type::RoadPaved){
        put(0x148,static_cast<df::building_roadst*>(building)->material_amount);put(0x28,building->mat_type);}
    using Duration=int32_t (*)(const void*);
    return reinterpret_cast<Duration>(const_cast<void*>(entry))(input.data());
}
}
