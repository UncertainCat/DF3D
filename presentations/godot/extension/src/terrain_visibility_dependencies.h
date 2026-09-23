#pragma once
#include "wm/world_model.h"
#include <bitset>
#include <map>
#include <tuple>

namespace df3d_godot {
// Entity placement depends on tile visibility, not on liquid, designation or
// terrain artwork. Keep this projection in the presentation layer.
class TerrainVisibilityDependencies {
public:
    using Mask = std::bitset<wm::kTilesPerBlock>;
    struct Stats {
        uint64_t blocksObserved = 0, blocksUnchanged = 0, tilesChanged = 0;
    };
    struct Changes {
        wm::BlockPos block;
        Mask tiles;
        bool contains(int x, int y) const {
            const int lx = x - block.bx * wm::kBlockSize;
            const int ly = y - block.by * wm::kBlockSize;
            return lx >= 0 && ly >= 0 && lx < wm::kBlockSize && ly < wm::kBlockSize &&
                tiles.test(wm::tileIndexInBlock(lx, ly));
        }
    };
    Changes observe(wm::BlockPos pos, const wm::TileState* tiles, bool reveal) {
        Mask visible;
        for (size_t i = 0; i < wm::kTilesPerBlock; ++i)
            visible.set(i, reveal || !tiles || !(tiles[i].flags & wm::kTileHidden));
        const auto key = std::tuple{pos.bx, pos.by, pos.bz};
        const auto old = observed_.find(key);
        // A missing baseline may have consumers built before observation.
        const Mask changed = old == observed_.end() ? Mask{}.set() : old->second ^ visible;
        observed_[key] = visible;
        ++stats_.blocksObserved;
        stats_.blocksUnchanged += changed.none();
        stats_.tilesChanged += changed.count();
        return {pos, changed};
    }
    void clear() { observed_.clear(); }
    const Stats& stats() const { return stats_; }
private:
    Stats stats_;
    std::map<std::tuple<int,int,int>, Mask> observed_;
};
}
