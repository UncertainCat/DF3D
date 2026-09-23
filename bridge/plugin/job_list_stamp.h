#pragma once
#include <cstdint>

// Cheap identity of the designation-relevant content of DF's job list. The
// pending-work index (pending_work.h) is rebuilt only when the stamp changes,
// so a paused game with a static job list costs one linear walk per update
// instead of three maps and their set differences.
namespace df3d_job_list_stamp {
struct Stamp {
    uint64_t count = 0;
    uint64_t hash = 14695981039346656037ull;  // FNV-1a offset basis
    void add(int32_t id, int32_t type, int32_t x, int32_t y, int32_t z, uint32_t flags) {
        auto mix = [this](uint64_t v) {
            for (int i = 0; i < 8; ++i) {
                hash ^= (v >> (i * 8)) & 0xFF;
                hash *= 1099511628211ull;
            }
        };
        mix(uint64_t(uint32_t(id)) | (uint64_t(uint32_t(type)) << 32));
        mix(uint64_t(uint32_t(x)) | (uint64_t(uint32_t(y)) << 32));
        mix(uint64_t(uint32_t(z)) | (uint64_t(flags) << 32));
        ++count;
    }
    bool operator==(const Stamp& o) const { return count == o.count && hash == o.hash; }
    bool operator!=(const Stamp& o) const { return !(*this == o); }
};
}  // namespace df3d_job_list_stamp
