#pragma once
#include <algorithm>
#include <cstdint>

// Terrain rescan scheduling. The rotating slice is bounded (`df3d scan <n>`
// is clamped) and a full rescan is spread across updates instead of scanning
// every block in one tick.
namespace df3d_scan_schedule {
// Upper bound for `df3d scan <n>`: 4096 blocks is a 64x64-block level per
// update, an order of magnitude above the default 256 and still bounded on a
// 16x16-embark (about 30 000 blocks over 100+ levels).
inline constexpr uint32_t kMaxSliceBlocks = 4096;
// Blocks per update while a requested full rescan is outstanding.
inline constexpr uint32_t kRescanSliceBlocks = 1024;

inline uint32_t clampSlice(uint32_t requested) {
    return std::clamp<uint32_t>(requested, 1, kMaxSliceBlocks);
}
// Blocks to scan from the rotating cursor this update. `rescanRemaining`
// counts the blocks a `df3d rescan` still owes; it is decremented by the
// returned count by the caller.
inline uint32_t sliceThisUpdate(uint32_t sliceBlocks, uint32_t rescanRemaining, uint32_t blockCount) {
    const uint32_t regular = std::min(sliceBlocks, blockCount);
    if (rescanRemaining == 0) return regular;
    return std::min(std::max(regular, kRescanSliceBlocks), std::min(rescanRemaining, blockCount));
}
}  // namespace df3d_scan_schedule
