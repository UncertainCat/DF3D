#pragma once
#include <cstdint>

// Fixed-interval retry for a resource that failed to initialize (a shared
// memory mapping another process holds, for example). The owner calls due()
// once per update; after a failure the next attempt waits `interval` updates
// so a persistent failure costs one attempt per interval, never one per tick.
namespace df3d_retry_backoff {
struct Backoff {
    uint32_t remaining = 0;
    bool due() {
        if (remaining == 0) return true;
        --remaining;
        return false;
    }
    void failed(uint32_t interval) { remaining = interval; }
    void reset() { remaining = 0; }
};
}  // namespace df3d_retry_backoff
