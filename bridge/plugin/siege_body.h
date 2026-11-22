#pragma once
#include <array>
#include <cstdint>
namespace df3d_production {
struct SiegeBody {
    int8_t type=-1,action=-1,resting=-1,facing=-1;
    std::array<int32_t,4> ammunition{{-1,-1,-1,-1}};
};
inline bool validSiegeBody(const SiegeBody& value) {
    if(value.type<0 || value.type>2 || value.action<0 || value.action>4 ||
       value.resting<0 || value.resting>7 || value.facing<0 || value.facing>7)return false;
    for(auto count:value.ammunition)if(value.type==2?count<0:count!=-1)return false;
    return true;
}
}
