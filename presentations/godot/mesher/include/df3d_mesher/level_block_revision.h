#pragma once
#include "wm/world_model.h"
#include <limits>
#include <vector>

namespace df3d::mesher {
// Exact selected-level signature, independent of cameras and reveal modes.
// Unchanged global revisions are O(1); unrelated-level changes inspect only
// this level's block versions (never its tiles). No probabilistic hash aliases.
struct LevelBlockRevision {
    uint64_t generation = std::numeric_limits<uint64_t>::max();
    uint64_t terrain = std::numeric_limits<uint64_t>::max();
    wm::TilePos size{};
    int z = -1;
    bool known = false;
    std::vector<uint64_t> versions;
    uint64_t blockChecks = 0;

    bool update(const wm::WorldModel& model, int level) {
        const auto dimensions = model.mapSize();
        const bool scope = generation != model.sessionGeneration() || size != dimensions ||
            z != level || known != model.hasTerrain();
        if (!scope && terrain == model.terrainVersion()) return false;
        std::vector<uint64_t> next;
        if (level >= 0 && level < dimensions.z && dimensions.x > 0 && dimensions.y > 0) {
            const int width = (dimensions.x - 1) / 16 + 1;
            const int height = (dimensions.y - 1) / 16 + 1;
            next.reserve(size_t(width) * height);
            for (int by = 0; by < height; ++by) for (int bx = 0; bx < width; ++bx) {
                next.push_back(model.blockVersion({bx, by, level}));
                ++blockChecks;
            }
        }
        const bool changed = scope || next != versions;
        generation = model.sessionGeneration(); terrain = model.terrainVersion();
        size = dimensions; z = level; known = model.hasTerrain();
        versions = std::move(next);
        return changed;
    }
};
// Open space and brook surfaces depend on liquid immediately below.
struct MinimapRevision {
    LevelBlockRevision selected, below;
    uint64_t blockChecks = 0;
    bool update(const wm::WorldModel& model, int level) {
        const bool changed=selected.update(model,level);
        const bool lowerChanged=below.update(model,level-1);
        blockChecks=selected.blockChecks+below.blockChecks;
        return changed || lowerChanged;
    }
};
}
