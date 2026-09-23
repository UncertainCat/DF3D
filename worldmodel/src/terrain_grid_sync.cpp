#include "terrain_grid_sync.h"

#include "terrain_util.h"

namespace wm::detail {

namespace shm = df3d::shm;

namespace {

inline TileState fromGridTile(const shm::TerrainTile& t) {
  TileState o;
  o.shape = static_cast<TileShape>(t.shape);
  o.materialKind = static_cast<MaterialKind>(t.material_kind);
  o.material = t.material;
  o.liquidLevel = t.liquid_level;
  o.liquidKind = static_cast<LiquidKind>(t.liquid_kind);
  o.flags = t.flags;
  o.designation = static_cast<DesignationKind>(shm::terrainOperation(t.designation));
  o.designationPriority = shm::terrainPriority(t.designation);
  o.designationMarker = shm::terrainMarker(t.designation);
  o.track=t.track; o.traffic=t.traffic; o.warnings=t.warnings;
  o.trackClearanceBlocked=(t.track_blockers&1)!=0;
  o.trackHorizontalBlocked=(t.track_blockers&2)!=0;
  o.trackSupport=(t.track_blockers&4)!=0; o.trackOpen=(t.track_blockers&8)!=0;
  return o;
}

}  // namespace

bool synthesizeFullFromGrid(const shm::TerrainHeader* h, GridScratch& scratch, SnapshotData& data,
                            uint64_t& gridTick, std::string& error) {
  error.clear();
  if (data.mapSize.x != h->sizeX || data.mapSize.y != h->sizeY || data.mapSize.z != h->sizeZ) {
    error = "terrain grid map size disagrees with the snapshot";
    return false;
  }
  const size_t nBlocks = h->blockCount;
  scratch.tiles.resize(nBlocks * shm::kTerrainTilesPerBlock);
  scratch.versions.resize(nBlocks);
  scratch.materials.resize(h->materialsCapacity);
  shm::TerrainReadResult rr;
  if (!shm::readTerrainGrid(h, scratch.tiles.data(), scratch.versions.data(),
                            scratch.materials.data(), rr)) {
    return false;  // torn: retry later
  }
  scratch.materialViews.clear();
  scratch.materialViews.reserve(static_cast<size_t>(rr.materialCount));
  size_t off = 0;
  const char* s = nullptr;
  uint16_t len = 0;
  while (scratch.materialViews.size() < rr.materialCount &&
         shm::terrainMaterialNext(scratch.materials.data(), static_cast<size_t>(rr.materialBytes),
                                  off, &s, &len)) {
    scratch.materialViews.emplace_back(s, len);
  }

  data.terrainScope = TerrainScope::Full;
  // Ring entity indices refer to the ring table, not the grid table.
  // Keep them stable while interning the grid's independently ordered names.
  std::vector<uint16_t> remap;
  for (auto name : scratch.materialViews) {
    auto it = std::find(data.materials.begin(), data.materials.end(), name);
    size_t index = static_cast<size_t>(it - data.materials.begin());
    if (it == data.materials.end() && index < kNoMaterial) data.materials.push_back(name);
    remap.push_back(index < kNoMaterial ? static_cast<uint16_t>(index) : kNoMaterial);
  }
  data.tileStorage.resize(nBlocks * kTilesPerBlock);
  for (size_t i = 0, n = data.tileStorage.size(); i < n; ++i) {
    const shm::TerrainTile& raw = scratch.tiles[i];
    // Same range checks as the ring validator (schema/cpp/validate.cpp).
    const auto fault = df3d::mirror::checkTileValues(df3d::mirror::RawTileValues{
        raw.shape, raw.material_kind, raw.liquid_level, raw.liquid_kind, raw.flags,
        shm::terrainOperation(raw.designation)});
    if (fault != df3d::mirror::TileFault::None) {
      error = std::string("terrain grid has ") + df3d::mirror::tileFaultName(fault);
      return false;
    }
    TileState t = fromGridTile(raw);
    if (t.material != kNoMaterial && t.material >= scratch.materialViews.size())
      t.material = kNoMaterial;  // string not published yet: degrade to none
    if (t.material != kNoMaterial) t.material = remap[t.material];
    data.tileStorage[i] = t;
  }
  data.blocks.clear();
  data.blocks.reserve(nBlocks);
  for (int32_t bz = 0; bz < h->sizeZ; ++bz) {
    for (int32_t by = 0; by < h->blocksY; ++by) {
      for (int32_t bx = 0; bx < h->blocksX; ++bx) {
        const size_t idx = shm::terrainBlockIndex(h, bx, by, bz);
        data.blocks.push_back(BlockObservation{BlockPos{bx, by, bz},
                                               data.tileStorage.data() + idx * kTilesPerBlock});
      }
    }
  }
  gridTick = rr.gridTick;
  return true;
}

}  // namespace wm::detail
