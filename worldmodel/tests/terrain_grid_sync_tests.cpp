// Tier 1: Full terrain synthesis from a terrain grid, driven on a
// heap-built grid exactly as MirrorClient drives the shared mapping —
// grid -> SnapshotData -> WorldModel queries, materials remapped, torn
// reads refused, and the Delta-floor rule (a ring Delta not newer than the
// grid must not roll a block back).
#include <doctest.h>

#include <memory>
#include <string>

#include "shm_layout.h"
#include "terrain_grid_sync.h"
#include "wm/world_model.h"

using namespace wm;
namespace shm = df3d::shm;

namespace {

struct Grid {
  std::unique_ptr<uint8_t[]> mem;
  shm::TerrainHeader* h;
};

Grid makeGrid(int32_t sx, int32_t sy, int32_t sz) {
  Grid g;
  const size_t size = shm::terrainRegionSize(shm::terrainBlockCount(sx, sy, sz), 4096);
  g.mem = std::make_unique<uint8_t[]>(size);
  g.h = reinterpret_cast<shm::TerrainHeader*>(g.mem.get());
  shm::initTerrain(g.h, 2, sx, sy, sz, 0x1234, 4096);
  return g;
}

shm::TerrainTile gridTile(uint8_t shape, uint8_t kind, uint16_t mat, uint8_t flags = 0) {
  shm::TerrainTile t{};
  t.shape = shape;
  t.material_kind = kind;
  t.material = mat;
  t.flags = flags;
  return t;
}

void fillBlock(shm::TerrainHeader* h, int bx, int by, int bz, const shm::TerrainTile& t) {
  shm::TerrainTile tiles[256];
  for (auto& x : tiles) x = t;
  shm::terrainWriteBlock(h, shm::terrainBlockIndex(h, bx, by, bz), tiles);
}

}  // namespace

TEST_CASE("v7 shared grid preserves exact operation and rejects invalid values") {
  auto g=makeGrid(16,16,1);
  auto tile=gridTile(11,6,kNoMaterial,kTileDigDesignated);
  tile.designation=shm::terrainDesignation(uint8_t(DesignationKind::Chop),2,true);
  tile.track=9; tile.traffic=2; tile.warnings=1; tile.track_blockers=15 | (10<<4);
  shm::terrainBeginWrite(g.h);fillBlock(g.h,0,0,0,tile);shm::terrainEndWrite(g.h,10);
  SnapshotData data;data.tick=10;data.mapSize={16,16,1};
  detail::GridScratch scratch;uint64_t tick=0;std::string error;
  REQUIRE(detail::synthesizeFullFromGrid(g.h,scratch,data,tick,error));
  WorldModel model;model.ingest(data,0.0);
  REQUIRE(model.tileAt({2,3,0}));
  CHECK(model.tileAt({2,3,0})->designation==DesignationKind::Chop);
  CHECK(model.tileAt({2,3,0})->designationPriority==2);
  CHECK(model.tileAt({2,3,0})->designationMarker);
  CHECK(model.tileAt({2,3,0})->track==9);
  CHECK(model.tileAt({2,3,0})->completedTrack==10);
  CHECK(model.tileAt({2,3,0})->trackClearanceBlocked);
  CHECK(model.tileAt({2,3,0})->trackHorizontalBlocked);
  CHECK(model.tileAt({2,3,0})->trackSupport); CHECK(model.tileAt({2,3,0})->trackOpen);
  CHECK(model.tileAt({2,3,0})->traffic==2);
  CHECK(model.tileAt({2,3,0})->warnings==1);
  CHECK(shm::checkTerrain(g.h,2)==nullptr);
  g.h->layoutVersion=1;
  CHECK(shm::checkTerrain(g.h,2)!=nullptr);
  g.h->layoutVersion=shm::kTerrainLayoutVersion;
  tile.designation=255;
  shm::terrainBeginWrite(g.h);fillBlock(g.h,0,0,0,tile);shm::terrainEndWrite(g.h,11);
  CHECK(!detail::synthesizeFullFromGrid(g.h,scratch,data,tick,error));
  CHECK(error.find("designation kind")!=std::string::npos);
}

TEST_CASE("grid -> Full snapshot -> world model: every block known, materials resolved") {
  auto g = makeGrid(20, 16, 2);  // 2x1x2 = 4 blocks, x-edge block partial
  REQUIRE(g.h->blockCount == 4);
  REQUIRE(shm::terrainAppendMaterial(g.h, "INORGANIC:GRANITE", 17) == 0);
  REQUIRE(shm::terrainAppendMaterial(g.h, "PLANT:OAK:WOOD", 14) == 1);
  shm::terrainBeginWrite(g.h);
  fillBlock(g.h, 0, 0, 0, gridTile(1 /*Wall*/, 1 /*Stone*/, 0));
  fillBlock(g.h, 1, 0, 0, gridTile(1, 1, 0, kTileHidden));
  fillBlock(g.h, 0, 0, 1, gridTile(2 /*Floor*/, 8 /*Grass*/, 1));
  fillBlock(g.h, 1, 0, 1, gridTile(11 /*TreeTrunk*/, 6 /*Wood*/, 1));
  shm::terrainEndWrite(g.h, 700);

  SnapshotData data;
  data.tick = 705;
  data.mapSize = TilePos{20, 16, 2};
  detail::GridScratch scratch;
  uint64_t gridTick = 0;
  std::string err;
  REQUIRE(detail::synthesizeFullFromGrid(g.h, scratch, data, gridTick, err));
  CHECK(err.empty());
  CHECK(gridTick == 700);
  CHECK(data.terrainScope == TerrainScope::Full);
  CHECK(data.blocks.size() == 4);
  CHECK(data.materials.size() == 2);
  CHECK(data.materials[1] == "PLANT:OAK:WOOD");

  WorldModel model;
  model.ingest(data, 0.0);
  CHECK(model.hasTerrain());
  CHECK(model.knownBlockCount() == 4);
  CHECK(model.mapBlockCount() == 4);
  auto t = model.tileAt(TilePos{3, 3, 0});
  REQUIRE(t);
  CHECK(t->shape == TileShape::Wall);
  CHECK(t->materialKind == MaterialKind::Stone);
  CHECK(model.materialName(t->material) == "INORGANIC:GRANITE");
  auto hidden = model.tileAt(TilePos{17, 0, 0});
  REQUIRE(hidden);
  CHECK((hidden->flags & kTileHidden) != 0);
  auto tree = model.tileAt(TilePos{19, 15, 1});
  REQUIRE(tree);
  CHECK(tree->shape == TileShape::TreeTrunk);
  CHECK(model.materialName(tree->material) == "PLANT:OAK:WOOD");
  CHECK_FALSE(model.tileAt(TilePos{20, 0, 0}));  // padding beyond the map
}

TEST_CASE("synthesis refuses a torn grid and a map-size mismatch") {
  auto g = makeGrid(16, 16, 1);
  detail::GridScratch scratch;
  uint64_t gridTick = 0;
  std::string err;

  SnapshotData wrong;
  wrong.mapSize = TilePos{32, 16, 1};
  CHECK_FALSE(detail::synthesizeFullFromGrid(g.h, scratch, wrong, gridTick, err));
  CHECK_FALSE(err.empty());

  SnapshotData data;
  data.mapSize = TilePos{16, 16, 1};
  shm::terrainBeginWrite(g.h);  // bridge mid-write: seq odd
  CHECK_FALSE(detail::synthesizeFullFromGrid(g.h, scratch, data, gridTick, err));
  CHECK(err.empty());  // "retry later", not an error
  shm::terrainEndWrite(g.h, 9);
  CHECK(detail::synthesizeFullFromGrid(g.h, scratch, data, gridTick, err));
  CHECK(gridTick == 9);
}

TEST_CASE("unpublished material index degrades to none instead of dangling") {
  auto g = makeGrid(16, 16, 1);
  shm::terrainBeginWrite(g.h);
  fillBlock(g.h, 0, 0, 0, gridTile(1, 1, 5));  // material 5 was never appended
  shm::terrainEndWrite(g.h, 1);
  SnapshotData data;
  data.mapSize = TilePos{16, 16, 1};
  detail::GridScratch scratch;
  uint64_t gridTick = 0;
  std::string err;
  REQUIRE(detail::synthesizeFullFromGrid(g.h, scratch, data, gridTick, err));
  CHECK(data.blocks[0].tiles[0].material == kNoMaterial);
}

TEST_CASE("Delta floor: a Delta not newer than the grid tick would roll a block back") {
  // Documents why MirrorClient strips Deltas with tick <= gridTick: the
  // grid at tick 10 already contains the change; a ring Delta from tick 8
  // (an older state of the same block) must not be applied over it.
  auto g = makeGrid(16, 16, 1);
  shm::terrainBeginWrite(g.h);
  fillBlock(g.h, 0, 0, 0, gridTile(2 /*Floor*/, 0, kNoMaterial));  // state at tick 10: dug out
  shm::terrainEndWrite(g.h, 10);
  SnapshotData full;
  full.tick = 10;
  full.mapSize = TilePos{16, 16, 1};
  detail::GridScratch scratch;
  uint64_t gridTick = 0;
  std::string err;
  REQUIRE(detail::synthesizeFullFromGrid(g.h, scratch, full, gridTick, err));
  WorldModel model;
  model.ingest(full, 0.0);
  REQUIRE(model.tileAt(TilePos{0, 0, 0})->shape == TileShape::Floor);

  // The stale Delta (tick 8: still a wall). Applying it is wrong...
  SnapshotData stale;
  stale.tick = 11;  // arrives later in wall time, but describes tick 8's state
  stale.mapSize = full.mapSize;
  stale.terrainScope = TerrainScope::Delta;
  stale.tileStorage.assign(kTilesPerBlock, TileState{});
  for (auto& t : stale.tileStorage) t.shape = TileShape::Wall;
  stale.blocks.push_back(BlockObservation{BlockPos{0, 0, 0}, stale.tileStorage.data()});
  WorldModel wrongModel;
  wrongModel.ingest(full, 0.0);
  wrongModel.ingest(stale, 0.1);
  CHECK(wrongModel.tileAt(TilePos{0, 0, 0})->shape == TileShape::Wall);  // rolled back
  // ...so the client strips it: a tick <= gridTick Delta is dropped, and
  // the model keeps the grid's (newer) state.
  const uint64_t floorTick = gridTick;
  if (8 <= floorTick) {
    stale.terrainScope = TerrainScope::None;
    stale.blocks.clear();
  }
  model.ingest(stale, 0.1);
  CHECK(model.tileAt(TilePos{0, 0, 0})->shape == TileShape::Floor);
}

TEST_CASE("grid path rejects every out-of-range tile value, not only the designation") {
  auto g = makeGrid(16, 16, 1);
  SnapshotData data;
  data.tick = 1;
  data.mapSize = {16, 16, 1};
  detail::GridScratch scratch;
  uint64_t tick = 0;
  std::string error;
  auto expectFault = [&](const shm::TerrainTile& tile, const char* text) {
    shm::terrainBeginWrite(g.h);
    fillBlock(g.h, 0, 0, 0, tile);
    shm::terrainEndWrite(g.h, ++data.tick);
    CHECK_FALSE(detail::synthesizeFullFromGrid(g.h, scratch, data, tick, error));
    CHECK_MESSAGE(error.find(text) != std::string::npos, error);
  };
  expectFault(gridTile(200, 0, kNoMaterial), "shape");
  expectFault(gridTile(1, 99, kNoMaterial), "material_kind");
  auto liquid = gridTile(2, 0, kNoMaterial);
  liquid.liquid_kind = 5;
  liquid.liquid_level = 3;
  expectFault(liquid, "liquid_kind");
  auto level = gridTile(2, 0, kNoMaterial);
  level.liquid_kind = 1;
  level.liquid_level = 8;
  expectFault(level, "liquid_level");
  auto inconsistent = gridTile(2, 0, kNoMaterial);
  inconsistent.liquid_level = 3;  // with liquid_kind None
  expectFault(inconsistent, "inconsistent");
  // In-range values on the same block are accepted afterwards.
  shm::terrainBeginWrite(g.h);
  fillBlock(g.h, 0, 0, 0, gridTile(2, 8, kNoMaterial));
  shm::terrainEndWrite(g.h, ++data.tick);
  CHECK(detail::synthesizeFullFromGrid(g.h, scratch, data, tick, error));
  CHECK(error.empty());
}

TEST_CASE("resident tile environment is preserved cleared and validated") {
  auto g=makeGrid(16,16,1);auto tile=gridTile(2,1,kNoMaterial);
  tile.environment_flags=7;tile.building_occupancy=7;
  SnapshotData data;data.tick=10;data.mapSize={16,16,1};
  detail::GridScratch scratch;uint64_t tick=0;std::string error;
  shm::terrainBeginWrite(g.h);fillBlock(g.h,0,0,0,tile);shm::terrainEndWrite(g.h,10);
  REQUIRE(detail::synthesizeFullFromGrid(g.h,scratch,data,tick,error));
  WorldModel model;model.ingest(data,0.0);
  const auto old=model.tileAt({2,3,0});REQUIRE(old);
  CHECK(old->subterranean);CHECK(old->brookTop);CHECK(old->root);CHECK(old->buildingOccupancy==7);
  tile.environment_flags=0;tile.building_occupancy=0;data.tick=11;
  shm::terrainBeginWrite(g.h);fillBlock(g.h,0,0,0,tile);shm::terrainEndWrite(g.h,11);
  REQUIRE(detail::synthesizeFullFromGrid(g.h,scratch,data,tick,error));model.ingest(data,0.1);
  const auto cleared=model.tileAt({2,3,0});REQUIRE(cleared);
  CHECK_FALSE(cleared->subterranean);CHECK_FALSE(cleared->brookTop);CHECK_FALSE(cleared->root);CHECK(cleared->buildingOccupancy==0);
  for(int field=0;field<2;++field) {
    tile.environment_flags=field==0?8:0;tile.building_occupancy=field==1?8:0;
    shm::terrainBeginWrite(g.h);fillBlock(g.h,0,0,0,tile);shm::terrainEndWrite(g.h,12+field);
    CHECK_FALSE(detail::synthesizeFullFromGrid(g.h,scratch,data,tick,error));
    CHECK(error=="invalid tile environment");
  }
}
