#pragma once
#include "df3d_assets/compositor.h"
#include <cstdint>
#include <map>
#include <vector>

namespace df3d::assets {
// Exact bitmap identity, independent of the logical appearance/topology key.
// Hashes select candidates only; dimensions and every byte decide equality.
class BitmapSlots {
public:
    using Hash = uint64_t (*)(const RgbaImage&);
    explicit BitmapSlots(Hash hash = hashImage) : hash_(hash) {}
    int intern(const RgbaImage& image, int newSlot) {
        auto& bucket = buckets_[hash_(image)];
        for (const auto& entry : bucket)
            if (entry.image.width == image.width && entry.image.height == image.height &&
                entry.image.pixels == image.pixels) { ++hits_; return entry.slot; }
        bucket.push_back({image, newSlot});
        ++unique_;
        return newSlot;
    }
    void clear() { buckets_.clear(); hits_ = unique_ = 0; }
    uint64_t hits() const { return hits_; }
    uint64_t unique() const { return unique_; }
private:
    static uint64_t hashImage(const RgbaImage& image) {
        uint64_t value = 14695981039346656037ULL;
        for (uint8_t byte : image.pixels) { value ^= byte; value *= 1099511628211ULL; }
        return value;
    }
    struct Entry { RgbaImage image; int slot; };
    Hash hash_;
    std::map<uint64_t, std::vector<Entry>> buckets_;
    uint64_t hits_ = 0, unique_ = 0;
};
} // namespace df3d::assets
