// Internal (worldmodel/src only): synthesizes a Full terrain SnapshotData
// from a mapped terrain grid. Pure over the grid's memory, so the
// tier-1 tests drive it on a heap-built grid; MirrorClient calls it on the
// real shared mapping. Not installed with public headers.
#pragma once

#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

#include "shm_layout.h"
#include "wm/world_model.h"

namespace wm::detail {

// Buffers that outlive the SnapshotData (its material string_views point
// into `materials`).
struct GridScratch {
  std::vector<df3d::shm::TerrainTile> tiles;
  std::vector<uint64_t> versions;
  std::vector<uint8_t> materials;
  std::vector<std::string_view> materialViews;
};

// Replaces `data`'s terrain payload with a Full built from the grid
// (blocks in (bz, by, bx) order, one per grid block). `data.mapSize` must
// match the grid. On a torn read (bridge writing continuously) returns
// false with an empty error: caller retries later. On a real mismatch
// returns false with `error` set. On success sets `gridTick` to the sim
// tick the grid state is current to.
bool synthesizeFullFromGrid(const df3d::shm::TerrainHeader* grid, GridScratch& scratch,
                            SnapshotData& data, uint64_t& gridTick, std::string& error);

}  // namespace wm::detail
