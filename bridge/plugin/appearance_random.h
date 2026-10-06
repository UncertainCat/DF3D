#pragma once
#include <cstdint>
#include <string_view>

namespace df3d_appearance {
// DF53.16 unit layer predicate, native 0x14071f220..0x14071f30f.
// Arithmetic wraps at64 bits; the raw part name is a sequence of signed bytes.
inline int32_t nativeRandomPart(uint32_t appearanceSeed, std::string_view name, int32_t maximum) {
    if (maximum <= 0) return 1;
    uint64_t state = appearanceSeed;
    for (unsigned char byte : name)
        state *= static_cast<uint64_t>(static_cast<int64_t>(byte < 128 ? int(byte) : int(byte)-256));
    state += UINT64_C(0x9e3779b97f4a7c15);
    state = (state ^ (state >> 30)) * UINT64_C(0xbf58476d1ce4e5b9);
    state = (state ^ (state >> 27)) * UINT64_C(0x94d049bb133111eb);
    state ^= state >> 31;
    return static_cast<int32_t>((state >> 32) % static_cast<uint32_t>(maximum)) + 1;
}
}
