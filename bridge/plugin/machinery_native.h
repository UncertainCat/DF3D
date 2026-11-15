#pragma once
#include "df/building.h"
#include "df/building_gear_assemblyst.h"
#include "df/building_screw_pumpst.h"
#include "df/machine.h"
#include "df/machine_info.h"
#include <windows.h>
#include <cstdint>
#include <optional>

namespace df3d_production {
enum class MachineryStatus : uint8_t { NoNetwork, Active, Inactive, FrozenHere, FrozenElsewhere };
struct MachineryBody {
    int32_t machineId=-1,produced=0,required=0;
    MachineryStatus status=MachineryStatus::NoNetwork;
    bool stableFoundation=false,disengaged=false;
    int8_t pumpManual=-1,pumpDirection=-1;
};
inline bool machineryBuildingType(df::building_type type) {
    return type==df::building_type::ScrewPump || type==df::building_type::GearAssembly ||
        type==df::building_type::AxleHorizontal || type==df::building_type::AxleVertical ||
        type==df::building_type::WaterWheel || type==df::building_type::Windmill || type==df::building_type::Rollers;
}
inline bool machineryNativeReady() {
    static const bool ready=[] {
        const auto* base=reinterpret_cast<const uint8_t*>(GetModuleHandleW(nullptr));
        // Native foundation predicate, including its tile classification jump table.
        uint64_t hash=UINT64_C(14695981039346656037);
        for(size_t i=0;i<0x422;++i){hash^=base[0x5acd00+i];hash*=UINT64_C(1099511628211);}
        return hash==UINT64_C(0x235749a142df8a03);
    }();
    return ready;
}
inline std::optional<MachineryBody> machineryBody(df::building* building) {
    if(!building || !machineryBuildingType(building->getType()) || !machineryNativeReady())return {};
    MachineryBody value;
    const auto* info=building->getMachineInfo();
    if(!info)return {};
    // Renderer18a0fc/19ad.. uses the resolved network, not component getPowerInfo.
    if(const auto* network=df::machine::find(info->machine_id)) {
        value.machineId=network->id;value.produced=network->cur_power;value.required=network->min_power;
        value.status=network->flags.bits.frozen ?
            (info->flags.bits.frozen?MachineryStatus::FrozenHere:MachineryStatus::FrozenElsewhere):
            (network->flags.bits.active?MachineryStatus::Active:MachineryStatus::Inactive);
    }
    // Simulation terrain is the only input; no native panel or graphics scratch.
    auto* base=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
    value.stableFoundation=reinterpret_cast<bool(*)(df::building*)>(base+0x5acd00)(building);
    if(building->getType()==df::building_type::GearAssembly)
        value.disengaged=static_cast<df::building_gear_assemblyst*>(building)->gear_flags.bits.disengaged;
    if(building->getType()==df::building_type::ScrewPump) {
        const auto* pump=static_cast<df::building_screw_pumpst*>(building);
        value.pumpManual=pump->pump_manually?1:0;value.pumpDirection=int8_t(pump->direction);
        if(value.pumpDirection<0 || value.pumpDirection>3)return {};
    }
    return value;
}
}
