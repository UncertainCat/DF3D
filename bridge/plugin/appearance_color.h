#pragma once
#include <cstdint>

namespace df3d_appearance {
// Protected native age/color controls022107,022304,022657. DF's integer
// percentage must exceed50; a mathematical midpoint is not equivalent.
inline double nativeAgeDays(int32_t year, int32_t tick, int32_t birthYear, int32_t birthTick) {
    return (double(year)-birthYear)*336.0 + (double(tick)-birthTick)/1200.0;
}
inline bool nativeColorModifierActive(int32_t start, int32_t end, double ageDays) {
    if (ageDays < start) return false;
    if (end <= start || ageDays >= end) return true;
    const auto percent = static_cast<int32_t>((ageDays-start)*100.0/(double(end)-start));
    return percent > 50;
}
}
