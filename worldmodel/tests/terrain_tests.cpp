// Tier 0: the terrain store driven directly through
// WorldModel::ingest with hand-built SnapshotData — upsert, versions,
// material interning across snapshots, Delta after Full, unknown tiles.
#include <doctest.h>

#include <array>

#include "wm/world_model.h"

using namespace wm;

namespace {

TileState tile(TileShape shape, MaterialKind kind, MaterialId mat, uint8_t flags = 0) {
  TileState t;
  t.shape = shape;
  t.materialKind = kind;
  t.material = mat;
  t.flags = flags;
  return t;
}

// A snapshot builder over a fixed map: fill() sets every tile of a block;
// blocks share the snapshot's own material table.
struct Snap {
  SnapshotData data;
  explicit Snap(Tick tick, TilePos mapSize, TerrainScope scope,
                std::vector<std::string_view> materials = {}) {
    data.tick = tick;
    data.mapSize = mapSize;
    data.terrainScope = scope;
    data.materials = std::move(materials);
    data.tileStorage.reserve(64 * kTilesPerBlock);  // no reallocation below
  }
  Snap& block(BlockPos pos, const TileState& fill) {
    const size_t base = data.tileStorage.size();
    data.tileStorage.insert(data.tileStorage.end(), kTilesPerBlock, fill);
    data.blocks.push_back(BlockObservation{pos, data.tileStorage.data() + base});
    return *this;
  }
  // Overrides one local tile of the most recently added block.
  Snap& set(int32_t lx, int32_t ly, const TileState& t) {
    const size_t base = data.tileStorage.size() - kTilesPerBlock;
    data.tileStorage[base + tileIndexInBlock(lx, ly)] = t;
    return *this;
  }
};

const TilePos kMap{20, 20, 2};  // 2x2 blocks per z (partial edge blocks), 2 levels

}  // namespace

TEST_CASE("no terrain until a Full snapshot; everything reports unknown") {
  WorldModel model;
  Snap s(1, kMap, TerrainScope::None);
  model.ingest(s.data, 0.0);
  CHECK(!model.hasTerrain());
  CHECK(model.terrainVersion() == 0);
  CHECK(model.knownBlockCount() == 0);
  CHECK(model.mapBlockCount() == 8);
  CHECK(!model.tileAt(TilePos{1, 1, 0}));
  CHECK(!model.block(BlockPos{0, 0, 0}));
  CHECK(model.blockVersion(BlockPos{0, 0, 0}) == 0);
  CHECK(model.blocksAtZ(0).empty());
  CHECK(model.drainTerrainEvents().empty());
  int visited = 0;
  model.forEachTileAtZ(0, [&](TilePos, const TileState&) { ++visited; });
  CHECK(visited == 0);
}

TEST_CASE("Full snapshot: blocks upserted, versions 1, padding ignored, materials interned") {
  WorldModel model;
  const TileState wall = tile(TileShape::Wall, MaterialKind::Stone, 0, kTileHidden);
  const TileState floor = tile(TileShape::Floor, MaterialKind::Soil, 1);
  Snap s(1, kMap, TerrainScope::Full, {"GRANITE", "CLAY_LOAM"});
  s.block(BlockPos{0, 0, 0}, wall).set(3, 4, floor);
  s.block(BlockPos{1, 0, 0}, wall);
  s.block(BlockPos{0, 1, 0}, wall);
  s.block(BlockPos{1, 1, 0}, wall);
  for (int by = 0; by < 2; ++by)
    for (int bx = 0; bx < 2; ++bx) s.block(BlockPos{bx, by, 1}, TileState{});
  model.ingest(s.data, 0.0);

  CHECK(model.hasTerrain());
  CHECK(model.terrainVersion() == 1);
  CHECK(model.knownBlockCount() == 8);
  CHECK(model.blockVersion(BlockPos{0, 0, 0}) == 1);
  CHECK(model.blockVersion(BlockPos{1, 1, 1}) == 1);

  auto t = model.tileAt(TilePos{3, 4, 0});
  REQUIRE(t);
  CHECK(t->shape == TileShape::Floor);
  CHECK(t->materialKind == MaterialKind::Soil);
  CHECK(model.materialName(t->material) == "CLAY_LOAM");
  auto w = model.tileAt(TilePos{19, 19, 0});
  REQUIRE(w);
  CHECK(w->shape == TileShape::Wall);
  CHECK((w->flags & kTileHidden) != 0);
  CHECK(model.materialName(w->material) == "GRANITE");
  CHECK(model.materialCount() == 2);
  CHECK(model.materialName(kNoMaterial).empty());
  CHECK(model.materialName(99).empty());

  // Outside the map (but inside the padded edge block) is unknown, and the
  // stored padding tile is Empty regardless of what the snapshot carried.
  CHECK(!model.tileAt(TilePos{20, 5, 0}));
  CHECK(!model.tileAt(TilePos{5, 20, 0}));
  CHECK(!model.tileAt(TilePos{-1, 0, 0}));
  CHECK(!model.tileAt(TilePos{0, 0, 2}));
  auto bv = model.block(BlockPos{1, 1, 0});
  REQUIRE(bv);
  CHECK(bv->version == 1);
  CHECK(bv->tiles[tileIndexInBlock(3, 3)].shape == TileShape::Wall);   // (19,19): in map
  CHECK(bv->tiles[tileIndexInBlock(4, 3)].shape == TileShape::Empty);  // (20,19): padding
  CHECK(bv->tiles[tileIndexInBlock(4, 3)].material == kNoMaterial);

  // Slab helper visits exactly the in-map tiles of z=0, block by block.
  int visited = 0, floors = 0;
  model.forEachTileAtZ(0, [&](TilePos p, const TileState& ts) {
    ++visited;
    CHECK(p.x < 20);
    CHECK(p.y < 20);
    CHECK(p.z == 0);
    if (ts.shape == TileShape::Floor) {
      ++floors;
      CHECK(p == TilePos{3, 4, 0});
    }
  });
  CHECK(visited == 400);
  CHECK(floors == 1);
  CHECK(model.blocksAtZ(0).size() == 4);
  CHECK(model.blocksAtZ(0)[1].pos == BlockPos{1, 0, 0});  // (by, bx) order
  CHECK(model.blocksAtZ(1).size() == 4);
  CHECK(model.blocksAtZ(2).empty());

  auto ev = model.drainTerrainEvents();
  CHECK(ev.size() == 8);
  CHECK(ev[0].pos == BlockPos{0, 0, 0});
  CHECK(ev[0].version == 1);
  CHECK(ev[0].tick == 1);
  CHECK(model.drainTerrainEvents().empty());
}

TEST_CASE("Delta after Full: only changed blocks bump; identical re-sends do not") {
  WorldModel model;
  const TileState wall = tile(TileShape::Wall, MaterialKind::Stone, 0);
  Snap full(1, kMap, TerrainScope::Full, {"GRANITE"});
  for (int z = 0; z < 2; ++z)
    for (int by = 0; by < 2; ++by)
      for (int bx = 0; bx < 2; ++bx) full.block(BlockPos{bx, by, z}, wall);
  model.ingest(full.data, 0.0);
  model.drainTerrainEvents();

  // Delta carrying one changed block and one byte-identical block.
  Snap d(2, kMap, TerrainScope::Delta, {"GRANITE"});
  d.block(BlockPos{1, 0, 1}, wall).set(2, 2, tile(TileShape::Floor, MaterialKind::Stone, 0));
  d.block(BlockPos{0, 0, 0}, wall);
  model.ingest(d.data, 0.0);

  CHECK(model.terrainVersion() == 2);
  CHECK(model.blockVersion(BlockPos{1, 0, 1}) == 2);
  CHECK(model.blockVersion(BlockPos{0, 0, 0}) == 1);
  CHECK(model.knownBlockCount() == 8);
  auto t = model.tileAt(TilePos{18, 2, 1});
  REQUIRE(t);
  CHECK(t->shape == TileShape::Floor);
  auto ev = model.drainTerrainEvents();
  REQUIRE(ev.size() == 1);
  CHECK(ev[0].pos == BlockPos{1, 0, 1});
  CHECK(ev[0].version == 2);
  CHECK(ev[0].tick == 2);

  // A Delta with nothing new changes nothing.
  Snap d2(3, kMap, TerrainScope::Delta, {"GRANITE"});
  d2.block(BlockPos{0, 1, 0}, wall);
  model.ingest(d2.data, 0.0);
  CHECK(model.terrainVersion() == 2);
  CHECK(model.drainTerrainEvents().empty());

  // A Delta for a block the model never saw is still upserted (version 1).
  WorldModel partial;
  Snap onlyOne(1, kMap, TerrainScope::Full, {"GRANITE"});
  onlyOne.block(BlockPos{0, 0, 0}, wall);
  partial.ingest(onlyOne.data, 0.0);
  Snap late(2, kMap, TerrainScope::Delta, {"GRANITE"});
  late.block(BlockPos{1, 1, 1}, wall);
  partial.ingest(late.data, 0.0);
  CHECK(partial.blockVersion(BlockPos{1, 1, 1}) == 1);
  CHECK(partial.knownBlockCount() == 2);
}

TEST_CASE("events coalesce per block across ingests until drained") {
  WorldModel model;
  Snap full(1, kMap, TerrainScope::Full, {"GRANITE"});
  for (int z = 0; z < 2; ++z)
    for (int by = 0; by < 2; ++by)
      for (int bx = 0; bx < 2; ++bx) full.block(BlockPos{bx, by, z}, TileState{});
  model.ingest(full.data, 0.0);
  model.drainTerrainEvents();

  for (Tick tick = 2; tick <= 4; ++tick) {
    Snap d(tick, kMap, TerrainScope::Delta, {"GRANITE"});
    d.block(BlockPos{0, 0, 0}, TileState{})
        .set(static_cast<int32_t>(tick), 0, tile(TileShape::Wall, MaterialKind::Stone, 0));
    model.ingest(d.data, 0.0);
  }
  CHECK(model.blockVersion(BlockPos{0, 0, 0}) == 4);
  CHECK(model.terrainVersion() == 4);
  auto ev = model.drainTerrainEvents();
  REQUIRE(ev.size() == 1);  // three changes, one event
  CHECK(ev[0].version == 4);
  CHECK(ev[0].tick == 4);
}

TEST_CASE("material ids are model-wide and stable across per-snapshot tables") {
  WorldModel model;
  Snap full(1, kMap, TerrainScope::Full, {"GRANITE", "MAGNETITE"});
  for (int z = 0; z < 2; ++z)
    for (int by = 0; by < 2; ++by)
      for (int bx = 0; bx < 2; ++bx) {
        full.block(BlockPos{bx, by, z}, tile(TileShape::Wall, MaterialKind::Stone, 0));
      }
  full.set(0, 0, tile(TileShape::Wall, MaterialKind::Mineral, 1));  // last block: (1,1,1)
  model.ingest(full.data, 0.0);
  const MaterialId granite = model.tileAt(TilePos{0, 0, 0})->material;
  const MaterialId magnetite = model.tileAt(TilePos{16, 16, 1})->material;
  CHECK(model.materialName(granite) == "GRANITE");
  CHECK(model.materialName(magnetite) == "MAGNETITE");

  // A Delta whose own table orders materials differently and adds one:
  // the same names resolve to the same model ids; re-sending a granite
  // wall under a different local index is not a change.
  Snap d(2, kMap, TerrainScope::Delta, {"OAK", "MAGNETITE", "GRANITE"});
  d.block(BlockPos{0, 0, 0}, tile(TileShape::Wall, MaterialKind::Stone, 2))
      .set(5, 5, tile(TileShape::TreeTrunk, MaterialKind::Wood, 0));
  model.ingest(d.data, 0.0);
  CHECK(model.materialCount() == 3);
  CHECK(model.tileAt(TilePos{0, 0, 0})->material == granite);
  CHECK(model.materialName(model.tileAt(TilePos{5, 5, 0})->material) == "OAK");
  CHECK(model.tileAt(TilePos{16, 16, 1})->material == magnetite);
  CHECK(model.blockVersion(BlockPos{0, 0, 0}) == 2);

  // Same block, same content, different table order: no bump.
  Snap d2(3, kMap, TerrainScope::Delta, {"GRANITE", "OAK"});
  d2.block(BlockPos{0, 0, 0}, tile(TileShape::Wall, MaterialKind::Stone, 0))
      .set(5, 5, tile(TileShape::TreeTrunk, MaterialKind::Wood, 1));
  model.ingest(d2.data, 0.0);
  CHECK(model.blockVersion(BlockPos{0, 0, 0}) == 2);
  CHECK(model.terrainVersion() == 2);
}

TEST_CASE("liquid and flags round-trip through tileAt") {
  WorldModel model;
  Snap full(1, kMap, TerrainScope::Full, {"CLAY_LOAM"});
  for (int z = 0; z < 2; ++z)
    for (int by = 0; by < 2; ++by)
      for (int bx = 0; bx < 2; ++bx) full.block(BlockPos{bx, by, z}, TileState{});
  TileState pond = tile(TileShape::Floor, MaterialKind::Soil, 0, kTileOutside | kTileSmooth);
  pond.liquidKind = LiquidKind::Water;
  pond.liquidLevel = 5;
  full.set(15, 15, pond);  // last block (1,1,1) -> tile (31,31,1) is padding... use in-map
  full.set(1, 2, pond);    // tile (17, 18, 1)
  model.ingest(full.data, 0.0);
  CHECK(!model.tileAt(TilePos{31, 31, 1}));
  auto t = model.tileAt(TilePos{17, 18, 1});
  REQUIRE(t);
  CHECK(t->liquidKind == LiquidKind::Water);
  CHECK(t->liquidLevel == 5);
  CHECK((t->flags & kTileSmooth) != 0);
  CHECK((t->flags & kTileHidden) == 0);
}

TEST_CASE("ingestTerrain=false keeps the model units-only") {
  WorldModelConfig cfg;
  cfg.ingestTerrain = false;
  WorldModel model(cfg);
  Snap full(1, kMap, TerrainScope::Full, {"GRANITE"});
  for (int z = 0; z < 2; ++z)
    for (int by = 0; by < 2; ++by)
      for (int bx = 0; bx < 2; ++bx) full.block(BlockPos{bx, by, z}, TileState{});
  model.ingest(full.data, 0.0);
  CHECK(!model.hasTerrain());
  CHECK(model.knownBlockCount() == 0);
  CHECK(model.materialCount() == 0);
}

TEST_CASE("block ordering helpers") {
  CHECK(blockOf(TilePos{17, 33, 4}) == BlockPos{1, 2, 4});
  CHECK(tileIndexInBlock(3, 2) == 35);
  static_assert(sizeof(std::array<TileState, kTilesPerBlock>) == 3584);
}

TEST_CASE("value snapshots share terrain payloads and detach only changed blocks") {
  WorldModel worker;
  Snap initial(1, TilePos{32, 16, 1}, TerrainScope::Full);
  initial.block({0, 0, 0}, tile(TileShape::Wall, MaterialKind::Stone, kNoMaterial));
  initial.block({1, 0, 0}, tile(TileShape::Floor, MaterialKind::Stone, kNoMaterial));
  worker.ingest(initial.data, 0.0);
  WorldModel published = worker;
  REQUIRE(worker.block({0, 0, 0}));
  CHECK(worker.block({0, 0, 0})->tiles == published.block({0, 0, 0})->tiles);
  CHECK(worker.block({1, 0, 0})->tiles == published.block({1, 0, 0})->tiles);
  Snap unchanged(2, TilePos{32, 16, 1}, TerrainScope::Delta);
  unchanged.block({0, 0, 0}, tile(TileShape::Wall, MaterialKind::Stone, kNoMaterial));
  worker.ingest(unchanged.data, 0.01);
  CHECK(worker.block({0, 0, 0})->tiles == published.block({0, 0, 0})->tiles);
  Snap changed(3, TilePos{32, 16, 1}, TerrainScope::Delta);
  changed.block({0, 0, 0}, tile(TileShape::Floor, MaterialKind::Stone, kNoMaterial));
  worker.ingest(changed.data, 0.02);
  CHECK(worker.block({0, 0, 0})->tiles != published.block({0, 0, 0})->tiles);
  CHECK(worker.block({1, 0, 0})->tiles == published.block({1, 0, 0})->tiles);
  CHECK(published.tileAt({0, 0, 0})->shape == TileShape::Wall);
  CHECK(worker.tileAt({0, 0, 0})->shape == TileShape::Floor);
  CHECK(published.latestTick() == 1);
  CHECK(published.drainTerrainEvents().size() == 2);
  CHECK(worker.drainTerrainEvents().size() == 2);
  worker.resetSession();
  CHECK(published.tileAt({0, 0, 0})->shape == TileShape::Wall);
}

TEST_CASE("track obstruction metadata invalidates resident terrain") {
  WorldModel model;
  Snap full(1, kMap, TerrainScope::Full, {"GRANITE"});
  auto ground=tile(TileShape::Floor, MaterialKind::Stone, 0);
  full.block({0,0,0},ground);model.ingest(full.data,0.0);
  const auto revision=model.terrainVersion();
  Snap delta(2,kMap,TerrainScope::Delta,{"GRANITE"});
  ground.trackClearanceBlocked=true;ground.trackHorizontalBlocked=true;
  delta.block({0,0,0},ground);model.ingest(delta.data,0.1);
  CHECK(model.terrainVersion()==revision+1);
  CHECK(model.tileAt({0,0,0})->trackClearanceBlocked);
  CHECK(model.tileAt({0,0,0})->trackHorizontalBlocked);
}
