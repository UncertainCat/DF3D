#include "df3d_world.h"
#include <algorithm>
#include <cmath>

namespace df3d_godot {
int Df3dWorld::doorCellClass(int x, int y, int z) const {
        const auto state = source_.model().tileAt({x, y, z});
        if (!state || (state->flags & wm::kTileHidden)) return 0;
        switch (state->shape) {
            case wm::TileShape::Wall:
            case wm::TileShape::Fortification:
            case wm::TileShape::TreeTrunk: return 1;
            case wm::TileShape::Floor:
            case wm::TileShape::Ramp:
            case wm::TileShape::StairUp:
            case wm::TileShape::StairDown:
            case wm::TileShape::StairUpDown:
            case wm::TileShape::Boulder:
            case wm::TileShape::Pebbles:
            case wm::TileShape::Shrub:
            case wm::TileShape::Sapling: return -1;
            default: return 0;
        }
}

void Df3dWorld::resetDoorOrientationCache() const {
    doorOrientationCells_.clear();
    doorOrientationScope_ = {source_.model().sessionGeneration(), topZ_, get_window_depth(), revealHidden_};
    doorOrientationTerrain_ = UINT64_MAX;
    ++doorOrientationRevision_;
}

void Df3dWorld::ensureDoorOrientationScope() const {
    if (doorOrientationScope_ != std::make_tuple(source_.model().sessionGeneration(), topZ_, get_window_depth(), revealHidden_))
        resetDoorOrientationCache();
}

int64_t Df3dWorld::door_orientation_revision() const {
    ensureDoorOrientationScope();
    if (doorOrientationTerrain_ != source_.model().terrainVersion()) {
        bool changed = false;
        for (auto& [cell, before] : doorOrientationCells_) {
            const auto [x, y, z] = cell;
            const int current = doorCellClass(x, y, z);
            changed = changed || before != current;
            before = current;
        }
        doorOrientationTerrain_ = source_.model().terrainVersion();
        if (changed) ++doorOrientationRevision_;
    }
    return static_cast<int64_t>(doorOrientationRevision_);
}

godot::Dictionary Df3dWorld::door_orientation(const godot::Vector3i& tile) const {
    ensureDoorOrientationScope();
    // Preserve old evidence until the shared revision has observed changes,
    // even when a direct query arrives first in a new publication.
    const auto classify = [&](int x, int y) {
        const int current = doorCellClass(x, y, tile.z);
        doorOrientationCells_.emplace(SpriteCeilingCell{x, y, tile.z}, current);
        return current;
    };
    const int dx[4] = {1, -1, 0, 0}, dy[4] = {0, 0, 1, -1};
    int neighbors[4];
    for (int i = 0; i < 4; ++i) neighbors[i] = classify(tile.x + dx[i], tile.y + dy[i]);
    int ew = 0, ns = 0;
    for (int i = 0; i < 2; ++i) {
        if (neighbors[i] == 1) ew += 8;
        if (neighbors[i + 2] == 1) ns += 8;
    }
    if (neighbors[2] == -1 && neighbors[3] == -1) ew += 4;
    if (neighbors[0] == -1 && neighbors[1] == -1) ns += 4;
    for (int i = 0; i < 4; ++i) {
        if (classify(tile.x + dx[i] * 2, tile.y + dy[i] * 2) == 1) {
            if (i < 2) ++ew;
            else ++ns;
        }
    }
    godot::Dictionary result;
    result["axis"] = ew >= ns ? "ew" : "ns";
    result["ambiguous"] = ew == ns;
    return result;
}

void Df3dWorld::resetSpriteCeilingCache() const {
    spriteCeilingCache_.clear();
}

int64_t Df3dWorld::sprite_ceiling_source_revision(const godot::AABB& bounds, int floorZ) const {
    return static_cast<int64_t>(spriteCeilingQuery(bounds,floorZ).revision);
}

double Df3dWorld::sprite_ceiling(const godot::AABB& bounds, int floorZ) const {
    return spriteCeilingQuery(bounds,floorZ).ceiling;
}

SpriteCeilingCache::Result Df3dWorld::spriteCeilingQuery(const godot::AABB& bounds, int floorZ) const {
    const auto end = bounds.get_end();
    const SpriteCeilingCache::Bounds coverage{
        int(std::floor(bounds.position.x+.0001)),int(std::floor(bounds.position.z+.0001)),floorZ+1,
        int(std::floor(end.x-.0001)),int(std::floor(end.z-.0001)),int(std::ceil(end.y))};
    return spriteCeilingCache_.query(source_.model(),coverage,topZ_,get_window_depth());
}

godot::Dictionary Df3dWorld::sprite_ceiling_cache_stats() const {
    const auto& stats=spriteCeilingCache_.stats;
    godot::Dictionary result;
    result["requests"]=int64_t(stats.requests);result["hits"]=int64_t(stats.hits);
    result["block_checks"]=int64_t(stats.blockChecks);result["block_samples"]=int64_t(stats.blockSamples);
    result["tile_samples"]=int64_t(stats.tileSamples);result["source_changes"]=int64_t(stats.changes);
    result["evictions"]=int64_t(stats.evictions);result["queries"]=int64_t(spriteCeilingCache_.size());
    result["blocks"]=int64_t(spriteCeilingCache_.blockCount());
    return result;
}

} // namespace df3d_godot
