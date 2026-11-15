#pragma once
#include <cstdint>
#include <string>
namespace df3d_production {
// Owned semantic facts; strings stay CP437 until transport encoding.
struct DepotBody {
    uint32_t flags=0,awaitingItems=0;
    bool goods=false,trade=false;
    int32_t workerId=-1,brokerId=-1,brokerJobId=-1;
    std::string brokerName,activity;
    int16_t foreground=7,background=0;
    bool bright=false,accessible=false;
};
inline bool validDepotBody(const DepotBody& v) {
    return v.awaitingItems<=1048576 && (!v.trade || v.goods) && v.workerId>=-1 && v.brokerId>=-1 && v.brokerJobId>=-1 &&
        v.brokerName.size()<=512 && v.activity.size()<=512 && v.foreground>=0 && v.foreground<=7 && v.background>=0 && v.background<=7 &&
        (v.brokerId>=0 ? !v.brokerName.empty() : (v.brokerName.empty() && v.activity.empty() && v.foreground==7 && v.background==0 && !v.bright && !v.accessible && v.brokerJobId==-1));
}
}
