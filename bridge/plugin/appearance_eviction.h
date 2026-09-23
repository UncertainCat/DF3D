#pragma once
#include <cstddef>
#include <cstdint>
#include <deque>

// Bounded eviction of per-unit appearance entries. Units that left the
// active list (died, left the map, were caged off-map) never return through
// the unit walk, so their entries would otherwise live until map unload.
// Each call inspects at most `maxPerCall` ids from a round-robin ring, so the
// per-tick cost is constant regardless of population. Entries seen within
// `ttlFrames` simulated frames stay; the ring keeps them for the next round.
namespace df3d_appearance_eviction {
// A unit's entry is stale after this many simulated frames without a sighting:
// 1200 frames is one in-game day at 100 FPS, far beyond the refresh rotation
// (256 / 128 frames), so a live unit is never evicted between two sightings.
inline constexpr int32_t kTtlFrames = 1200;
inline constexpr size_t kMaxPerCall = 64;

using Ring = std::deque<int32_t>;

// `map` must expose find(id) / end() / erase(iterator) with entries carrying
// a `lastSeenFrame` member (std::unordered_map<int32_t, Entry>). Returns the
// number of entries evicted. Frames running backwards (a reloaded older save
// inside one map) never evict: a negative age counts as fresh.
template <class Map>
size_t evict(Ring& ring, Map& map, int32_t frame, int32_t ttlFrames = kTtlFrames, size_t maxPerCall = kMaxPerCall) {
    size_t evicted = 0;
    size_t budget = ring.size() < maxPerCall ? ring.size() : maxPerCall;
    while (budget-- > 0) {
        const int32_t id = ring.front();
        ring.pop_front();
        auto it = map.find(id);
        if (it == map.end()) continue;  // already gone (map reset)
        const int64_t age = int64_t(frame) - int64_t(it->second.lastSeenFrame);
        if (age > ttlFrames) {
            map.erase(it);
            ++evicted;
        } else {
            ring.push_back(id);
        }
    }
    return evicted;
}
}  // namespace df3d_appearance_eviction
