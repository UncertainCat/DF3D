#pragma once
#include <cstdint>
#include <cstring>
namespace df3d_production {
// Native1811a7..1815c3 aggregates identical per-stage native durations. Preserve
// the machine's 32-bit sums and float quotient before its double thresholds.
// 0=no caption, 1=waiting, 2=initiated, 3=partial, 4=nearly done.
inline int8_t pendingProgress(int32_t duration,int32_t stage,int32_t maximum,bool hasJob,int32_t timer) {
    const auto signedValue=[](uint32_t bits){int32_t value;std::memcpy(&value,&bits,sizeof(value));return value;};
    const int32_t total=signedValue(uint32_t(duration)*uint32_t(maximum));
    if(total<=0)return 0;
    uint32_t work=uint32_t(duration)*uint32_t(stage);
    if(hasJob && timer!=-1)work+=uint32_t(duration)-uint32_t(timer);
    const float ratio=static_cast<float>(signedValue(work))/static_cast<float>(total);
    if(ratio<=0.0f)return 1;
    if(static_cast<double>(ratio)<0.33)return 2;
    if(static_cast<double>(ratio)<0.66)return 3;
    return 4;
}
}
