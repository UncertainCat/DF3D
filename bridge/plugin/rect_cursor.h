#pragma once
#include <cstdint>

// Resumable walk over an inclusive tile rectangle spanning [z, maxZ]. A
// designation command may touch 65 536 tiles per level; the bridge executes
// it in slices across simulation ticks so no single update exceeds its budget.
// Order is z outer, then y, then x (the original single-tick loop order).
namespace df3d_rect_cursor {
struct Cursor {
    int32_t x1 = 0, y1 = 0, x2 = -1, y2 = -1, z1 = 0, z2 = -1;
    int32_t x = 0, y = 0, z = 0;
    bool done = true;
    void begin(int32_t ax1, int32_t ay1, int32_t ax2, int32_t ay2, int32_t az1, int32_t az2) {
        x1 = ax1; y1 = ay1; x2 = ax2; y2 = ay2; z1 = az1; z2 = az2;
        x = x1; y = y1; z = z1;
        done = x1 > x2 || y1 > y2 || z1 > z2;
    }
    // Advances past the current tile.
    void next() {
        if (done) return;
        if (++x > x2) { x = x1; if (++y > y2) { y = y1; if (++z > z2) done = true; } }
    }
    uint64_t total() const {
        if (x1 > x2 || y1 > y2 || z1 > z2) return 0;
        return uint64_t(x2 - x1 + 1) * uint64_t(y2 - y1 + 1) * uint64_t(z2 - z1 + 1);
    }
};
}  // namespace df3d_rect_cursor
