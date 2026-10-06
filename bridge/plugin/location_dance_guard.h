#pragma once
#include <cstddef>
#include <cstdint>

namespace df3d_area {
constexpr uint32_t kLocationDanceRva = 0x6c5a0;
constexpr size_t kLocationDanceBytes = 0x59f;

// Full routine fingerprint, not just a shared compiler prologue. The supported
// PE has no base relocations in this range, so ASLR does not alter these bytes.
inline bool matchesLocationDance(uint16_t machine, uint32_t timestamp,
    uint32_t imageSize, const uint8_t* code, size_t length) {
    if (machine != 0x8664 || timestamp != 0x6a70a6d9 || imageSize != 0x2711000 ||
        !code || length != kLocationDanceBytes) return false;
    uint64_t hash = UINT64_C(14695981039346656037);
    for (size_t i = 0; i < length; ++i) {
        hash ^= code[i];
        hash *= UINT64_C(1099511628211);
    }
    return hash == UINT64_C(0x74e2790e72a689f3);
}
}
