#pragma once
#include <cstdint>

namespace df3d_map_indicators {
inline bool buildingBlocksMiningWarning(uint8_t occupancy, bool closedDoorGrateBars) {
    return occupancy==6 || (occupancy==7 && closedDoorGrateBars);
}

// DF 53.16 renderer 0xe861e0 and damp helper 0x149f0b0. Callback receives
// relative coordinates, returning the observed water/aquifer-wall predicate.
// Warm wins; no neighbor below or vertically diagonal participates.
template<class DampSource>
uint8_t miningWarning(uint16_t temperature, DampSource&& damp) {
    if(temperature>=10075) return 2;
    for(int dx=-1;dx<=1;++dx) for(int dy=-1;dy<=1;++dy)
        if(damp(dx,dy,0)) return 1;
    return damp(0,0,1) ? 1 : 0;
}
}
