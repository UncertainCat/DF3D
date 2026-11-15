#pragma once
#include <cstdint>
namespace df3d_production {
enum class MachineryStatus : uint8_t { NoNetwork, Active, Inactive, FrozenHere, FrozenElsewhere };
struct MachineryBody {
    int32_t machineId=-1,produced=0,required=0;
    MachineryStatus status=MachineryStatus::NoNetwork;
    bool stableFoundation=false,disengaged=false;
    int8_t pumpManual=-1,pumpDirection=-1;
};
inline bool machineryType(int type){return type==33 || (type>=40 && type<=44) || type==50;}
inline bool validMachineryBody(const MachineryBody& v,int type) {
    const bool network=v.status!=MachineryStatus::NoNetwork;
    return machineryType(type) && uint8_t(v.status)<=4 && v.machineId>=-1 && network==(v.machineId>=0) &&
        (network || (!v.produced && !v.required)) && (!v.disengaged || type==40) &&
        (type==33 ? (v.pumpManual>=0 && v.pumpManual<=1 && v.pumpDirection>=0 && v.pumpDirection<=3):
                    (v.pumpManual==-1 && v.pumpDirection==-1));
}
}
