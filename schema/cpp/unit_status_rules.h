#pragma once
#include "unit_status.h"

// Pure semantic portions of Steam DF 53.16's fortress status selector.
// Source trace: tools/smoke/inspect_native_unit_indicators.py / UNIT_STATUS_SEMANTICS.
namespace df3d::unit_status {
constexpr uint64_t needs(int hunger, int thirst, int drowsiness) {
    return (hunger >= 50000 ? Hungry : 0) | (thirst >= 25000 ? Thirsty : 0) |
        (drowsiness >= 57600 ? Drowsy : 0);
}
constexpr uint64_t focus(int stress, int current, int undistracted) {
    const int64_t percent = undistracted > 0 ? int64_t(current)*100/undistracted : 100;
    return (stress >= 10000 ? Stressed : 0) | (percent <= 80 ? Distracted : 0);
}
constexpr uint64_t injury(int graspCount, int graspMax, int standCount, int standMax,
                         bool crutch, int blood, int bloodMax, bool criticalOrganLoss) {
    if (crutch && standMax >= 2) ++standCount;
    if (graspCount < graspMax-1 || blood < (bloodMax>>2) ||
        (standMax != 0 && standCount <= (standMax>>1)) || criticalOrganLoss) return MajorInjury;
    if (graspCount < graspMax || blood < (bloodMax>>1)) return MinorInjury;
    return 0;
}
}
