// Tier 0 for schema v2 terrain: SyntheticFort terrain authoring
// (Full-then-Delta emission) and every terrain validator rule, one test per
// rule. Invalid shapes the builder refuses to author are assembled raw.
#include <doctest.h>

#include <functional>
#include <optional>
#include <string>
#include <vector>

#include "fixture_io.h"
#include "synthetic_builder.h"
#include "terrain_util.h"
#include "validate.h"

using namespace df3d::mirror;

namespace {

TileState granite(uint16_t mat) {
  return TileState(TileShape::Wall, MaterialKind::Stone, mat, 0, LiquidKind::None,
                   TileFlags::NONE, df3d::mirror::DesignationKind::None);
}

std::optional<std::string> validateBytes(const std::vector<uint8_t>& bytes) {
  FixtureStream fs;
  std::string err;
  REQUIRE_MESSAGE(parseFixture(bytes, fs, err), err);
  return validateStream(fs);
}

FixtureStream mustParse(const SyntheticFort& fort) {
  FixtureStream fs;
  std::string err;
  REQUIRE_MESSAGE(parseFixture(fort.serialize(), fs, err), err);
  return fs;
}

// Raw single-snapshot fixture for shapes SyntheticFort will not produce.
struct RawBlock {
  int32_t bx, by, bz;
  std::vector<TileState> tiles;
};

std::vector<uint8_t> rawSnapshot(TilePos dims, TerrainScope scope,
                                 const std::vector<RawBlock>& blocks,
                                 const std::vector<std::string>& materials, uint64_t tick = 1) {
  flatbuffers::FlatBufferBuilder fbb;
  std::vector<flatbuffers::Offset<MapBlock>> blockOffs;
  for (const auto& b : blocks) {
    auto tiles = fbb.CreateVectorOfStructs(b.tiles.data(), b.tiles.size());
    blockOffs.push_back(CreateMapBlock(fbb, b.bx, b.by, b.bz, tiles));
  }
  auto blocksVec = fbb.CreateVector(blockOffs);
  std::vector<flatbuffers::Offset<flatbuffers::String>> mats;
  for (const auto& m : materials) mats.push_back(fbb.CreateString(m));
  auto matsVec = fbb.CreateVector(mats);
  auto units = fbb.CreateVector(std::vector<flatbuffers::Offset<UnitState>>{});
  auto snap = CreateSnapshot(fbb, static_cast<uint32_t>(SchemaVersion::Current), tick, tick * 10,
                             &dims, units, scope, blocksVec, matsVec);
  fbb.FinishSizePrefixed(snap, SnapshotIdentifier());
  return std::vector<uint8_t>(fbb.GetBufferPointer(), fbb.GetBufferPointer() + fbb.GetSize());
}

std::vector<TileState> fullBlock(const TileState& t = emptyTile()) {
  return std::vector<TileState>(kTilesPerBlock, t);
}

// A 16x16x1 map: exactly one block, so Full == one block.
const TilePos kOneBlockMap(16, 16, 1);

std::optional<std::string> validateRaw(TerrainScope scope, const std::vector<RawBlock>& blocks,
                                       const std::vector<std::string>& materials = {},
                                       TilePos dims = kOneBlockMap) {
  return validateBytes(assembleFixture({rawSnapshot(dims, scope, blocks, materials)}));
}

// One rejection per row: `validate` builds the shape; every `expected`
// substring must appear in the error. Accept rows must validate cleanly.
struct RejectCase {
  const char* name;
  std::function<std::optional<std::string>()> validate;
  std::vector<const char*> expected;
};
struct AcceptCase {
  const char* name;
  std::function<std::optional<std::string>()> validate;
};
void expectRejections(const std::vector<RejectCase>& cases) {
  for (const auto& c : cases) {
    INFO(c.name);
    auto err = c.validate();
    REQUIRE(err);
    for (const char* e : c.expected) CHECK_MESSAGE(err->find(e) != std::string::npos, *err);
  }
}
void expectAcceptance(const std::vector<AcceptCase>& cases) {
  for (const auto& c : cases) {
    INFO(c.name);
    auto err = c.validate();
    CHECK_MESSAGE(!err, err.value_or(""));
  }
}

std::vector<TileState> blockWith(size_t index, const TileState& t) {
  auto tiles = fullBlock();
  tiles[index] = t;
  return tiles;
}
TileState liquidTile(uint8_t level, LiquidKind kind) {
  return TileState(TileShape::Floor, MaterialKind::None, kNoMaterial, level, kind, TileFlags::NONE,
                   df3d::mirror::DesignationKind::None);
}
// A one-block fort whose next snapshot's terrain_scope is forged.
std::optional<std::string> forgedScopeStream(TerrainScope scope, int snapshots) {
  SyntheticFort fort(16, 16, 1);
  fort.setTile(0, 0, 0, granite(fort.material("GRANITE")));
  fort.forgeNextTerrainScope(scope);
  for (int i = 1; i <= snapshots; ++i) fort.snapshot(i);
  return validateStream(mustParse(fort));
}

}  // namespace

// ---------------------------------------------------------------- builder

TEST_CASE("terrain: units-only fort emits terrain_scope None and no blocks") {
  SyntheticFort fort(20, 20, 3);
  fort.addUnit(1, "DWARF", 1, 1, 0);
  fort.snapshot(1);
  auto fs = mustParse(fort);
  CHECK(!fort.terrainEnabled());
  CHECK(fs.snapshots[0]->terrain_scope() == TerrainScope::None);
  CHECK(fs.snapshots[0]->blocks() == nullptr);
  CHECK(fs.snapshots[0]->materials() == nullptr);
  CHECK(!validateStream(fs));
}

TEST_CASE("terrain: first terrain snapshot is Full with every block, row-major tiles") {
  SyntheticFort fort(20, 40, 3);  // 2 x 3 x 3 = 18 blocks
  const uint16_t gr = fort.material("GRANITE");
  fort.setTile(17, 33, 2, granite(gr));  // block (1,2,2), local (1,1) -> index 17
  fort.snapshot(1);
  auto fs = mustParse(fort);
  REQUIRE(!validateStream(fs));
  const Snapshot* s = fs.snapshots[0];
  CHECK(s->terrain_scope() == TerrainScope::Full);
  REQUIRE(s->blocks()->size() == 18);
  CHECK(blockCount(20, 40, 3) == 18);
  REQUIRE(s->materials()->size() == 1);
  CHECK(std::string(s->materials()->Get(0)->c_str()) == "GRANITE");

  size_t nonEmpty = 0;
  const MapBlock* hit = nullptr;
  for (const MapBlock* b : *s->blocks()) {
    REQUIRE(b->tiles()->size() == kTilesPerBlock);
    for (const TileState* t : *b->tiles()) {
      if (t->shape() != TileShape::Empty) {
        ++nonEmpty;
        hit = b;
      }
    }
  }
  CHECK(nonEmpty == 1);
  REQUIRE(hit);
  CHECK(hit->bx() == 1);
  CHECK(hit->by() == 2);
  CHECK(hit->bz() == 2);
  const TileState* t = hit->tiles()->Get(static_cast<flatbuffers::uoffset_t>(tileIndex(1, 1)));
  CHECK(t->shape() == TileShape::Wall);
  CHECK(t->material_kind() == MaterialKind::Stone);
  CHECK(t->material() == gr);
  // Untouched tiles carry the documented empty state, not zeroes.
  const TileState* e = hit->tiles()->Get(0);
  CHECK(e->shape() == TileShape::Empty);
  CHECK(e->material() == kNoMaterial);
}

TEST_CASE("terrain: later snapshots are Deltas carrying only dirty blocks") {
  SyntheticFort fort(32, 32, 2);  // 8 blocks
  const uint16_t gr = fort.material("GRANITE");
  fort.setTile(0, 0, 0, granite(gr));
  fort.snapshot(1);  // Full
  fort.setTile(20, 5, 1, granite(gr));  // block (1,0,1)
  fort.setTile(20, 6, 1, granite(gr));  // same block
  fort.snapshot(2);  // Delta, one block
  fort.snapshot(3);  // Delta, nothing changed
  fort.setTile(0, 0, 0, granite(gr));  // no-op: identical tile does not dirty
  fort.snapshot(4);
  auto fs = mustParse(fort);
  REQUIRE(!validateStream(fs));
  REQUIRE(fs.snapshots.size() == 4);
  CHECK(fs.snapshots[0]->terrain_scope() == TerrainScope::Full);
  CHECK(fs.snapshots[0]->blocks()->size() == 8);
  CHECK(fs.snapshots[1]->terrain_scope() == TerrainScope::Delta);
  REQUIRE(fs.snapshots[1]->blocks()->size() == 1);
  CHECK(fs.snapshots[1]->blocks()->Get(0)->bx() == 1);
  CHECK(fs.snapshots[1]->blocks()->Get(0)->by() == 0);
  CHECK(fs.snapshots[1]->blocks()->Get(0)->bz() == 1);
  CHECK(fs.snapshots[2]->terrain_scope() == TerrainScope::Delta);
  CHECK(fs.snapshots[2]->blocks()->size() == 0);
  CHECK(fs.snapshots[3]->blocks()->size() == 0);
}

TEST_CASE("terrain: markBlockDirty and requestFullTerrain force emission") {
  SyntheticFort fort(16, 16, 2);
  fort.setTile(1, 1, 0, granite(fort.material("GRANITE")));
  fort.snapshot(1);  // Full
  fort.markBlockDirty(0, 0, 1);
  fort.snapshot(2);  // Delta with the forced block
  fort.requestFullTerrain();
  fort.snapshot(3);  // Full again
  fort.snapshot(4);  // back to Delta
  auto fs = mustParse(fort);
  REQUIRE(!validateStream(fs));
  CHECK(fs.snapshots[1]->terrain_scope() == TerrainScope::Delta);
  REQUIRE(fs.snapshots[1]->blocks()->size() == 1);
  CHECK(fs.snapshots[1]->blocks()->Get(0)->bz() == 1);
  CHECK(fs.snapshots[2]->terrain_scope() == TerrainScope::Full);
  CHECK(fs.snapshots[2]->blocks()->size() == 2);
  CHECK(fs.snapshots[3]->terrain_scope() == TerrainScope::Delta);
  CHECK(fs.snapshots[3]->blocks()->size() == 0);
  CHECK_THROWS_AS(fort.markBlockDirty(1, 0, 0), std::out_of_range);
}

TEST_CASE("terrain: material interning is idempotent and ordered") {
  SyntheticFort fort(16, 16, 1);
  CHECK(fort.material("GRANITE") == 0);
  CHECK(fort.material("SAND") == 1);
  CHECK(fort.material("GRANITE") == 0);
  CHECK_THROWS_AS(fort.material(""), std::invalid_argument);
  fort.snapshot(1);
  fort.material("CLAY");  // interned after the first snapshot
  fort.snapshot(2);
  auto fs = mustParse(fort);
  REQUIRE(!validateStream(fs));
  CHECK(fs.snapshots[0]->materials()->size() == 2);
  CHECK(fs.snapshots[1]->materials()->size() == 3);
  CHECK(std::string(fs.snapshots[1]->materials()->Get(2)->c_str()) == "CLAY");
}

TEST_CASE("terrain: fillBox, tile readback, bounds") {
  SyntheticFort fort(20, 20, 4);
  CHECK(fort.tile(3, 3, 3).shape() == TileShape::Empty);  // before any terrain
  const uint16_t soil = fort.material("CLAY_LOAM");
  TileState floor(TileShape::Floor, MaterialKind::Soil, soil, 0, LiquidKind::None,
                  TileFlags::Outside, DesignationKind::None);
  fort.fillBox(TilePos(2, 2, 1), TilePos(19, 19, 1), floor);
  CHECK(fort.tile(19, 19, 1).shape() == TileShape::Floor);
  CHECK(fort.tile(19, 19, 1).flags() == TileFlags::Outside);
  CHECK(fort.tile(1, 1, 1).shape() == TileShape::Empty);
  CHECK_THROWS_AS(fort.setTile(20, 0, 0, floor), std::out_of_range);
  CHECK_THROWS_AS(fort.tile(0, -1, 0), std::out_of_range);
  fort.snapshot(1);
  CHECK(!validateStream(mustParse(fort)));
}

TEST_CASE("terrain: existing unit API is unaffected by terrain") {
  SyntheticFort fort(16, 16, 1);
  fort.addUnit(1, "DWARF", 1, 1, 0, JobKind::Mine);
  fort.setTile(1, 1, 0, TileState(TileShape::Floor, MaterialKind::Stone, fort.material("GRANITE"),
                                  0, LiquidKind::None, TileFlags::Smooth, df3d::mirror::DesignationKind::None));
  fort.snapshot(1);
  fort.moveUnit(1, 2, 1, 0);
  fort.snapshot(2);
  auto fs = mustParse(fort);
  REQUIRE(!validateStream(fs));
  CHECK(fs.snapshots[1]->units()->Get(0)->pos()->x() == 2);
  CHECK(fs.snapshots[1]->units()->Get(0)->job() == JobKind::Mine);
}

// ------------------------------------------------------------- validators

TEST_CASE("validator: accepts a well-formed Full + Delta terrain stream") {
  SyntheticFort fort(40, 24, 3);
  const uint16_t gr = fort.material("GRANITE");
  fort.fillBox(TilePos(0, 0, 0), TilePos(39, 23, 0), granite(gr));
  fort.setTile(5, 5, 1, TileState(TileShape::Floor, MaterialKind::Stone, gr, 3, LiquidKind::Water,
                                  TileFlags::Hidden | TileFlags::DigDesignated, df3d::mirror::DesignationKind::None));
  fort.snapshot(1);
  fort.setTile(5, 5, 1, TileState(TileShape::Floor, MaterialKind::Stone, gr, 7, LiquidKind::Magma,
                                  TileFlags::Smooth | TileFlags::Engraved, df3d::mirror::DesignationKind::None));
  fort.snapshot(2);
  CHECK(!validateStream(mustParse(fort)));
}

TEST_CASE("validator rejects malformed terrain (one row per rule)") {
  const TilePos dims20(20, 20, 2);  // 2x2x2 blocks (ceil), so bx=2 / bz=2 are out
  const TilePos dims4(17, 16, 2);   // 2 x 1 x 2 = 4 blocks
  const std::vector<std::string> twoMaterials{"GRANITE", "SAND"};
  expectRejections({
      {"invalid terrain_scope value",
       [] { return validateRaw(static_cast<TerrainScope>(7), {}); }, {"invalid terrain_scope"}},
      {"blocks attached to a terrain_scope None snapshot",
       [] { return forgedScopeStream(TerrainScope::None, 1); }, {"terrain_scope None but 1 blocks"}},
      // Delta-before-Full is a stream rule; an in-grid block only fails that one.
      {"block (1,1,1) inside the 2x2x2 grid fails only the stream rule",
       [&] { return validateRaw(TerrainScope::Delta, {{1, 1, 1, fullBlock()}}, {}, dims20); },
       {"Delta before any Full"}},
      {"bx=2 outside the block grid",
       [&] { return validateRaw(TerrainScope::Delta, {{2, 0, 0, fullBlock()}}, {}, dims20); },
       {"outside block grid 2x2x2"}},
      {"by=2 outside the block grid",
       [&] { return validateRaw(TerrainScope::Delta, {{0, 2, 0, fullBlock()}}, {}, dims20); },
       {"outside block grid 2x2x2"}},
      {"bz=2 outside the block grid",
       [&] { return validateRaw(TerrainScope::Delta, {{0, 0, 2, fullBlock()}}, {}, dims20); },
       {"outside block grid 2x2x2"}},
      {"bx=-1 outside the block grid",
       [&] { return validateRaw(TerrainScope::Delta, {{-1, 0, 0, fullBlock()}}, {}, dims20); },
       {"outside block grid 2x2x2"}},
      {"block with 255 tiles",
       [] { return validateRaw(TerrainScope::Full, {{0, 0, 0, std::vector<TileState>(255, emptyTile())}}); },
       {"has 255 tiles, expected 256"}},
      {"block with 257 tiles",
       [] { return validateRaw(TerrainScope::Full, {{0, 0, 0, std::vector<TileState>(257, emptyTile())}}); },
       {"has 257 tiles"}},
      {"invalid shape value",
       [] {
         return validateRaw(TerrainScope::Full,
                            {{0, 0, 0, blockWith(7, TileState(static_cast<TileShape>(200), MaterialKind::None, kNoMaterial, 0,
                                                              LiquidKind::None, TileFlags::NONE, df3d::mirror::DesignationKind::None))}});
       },
       {"tile 7: invalid shape value 200"}},
      {"invalid material_kind value",
       [] {
         return validateRaw(TerrainScope::Full,
                            {{0, 0, 0, blockWith(0, TileState(TileShape::Wall, static_cast<MaterialKind>(99), kNoMaterial, 0,
                                                              LiquidKind::None, TileFlags::NONE, df3d::mirror::DesignationKind::None))}});
       },
       {"invalid material_kind value 99"}},
      {"invalid liquid_kind value",
       [] { return validateRaw(TerrainScope::Full, {{0, 0, 0, blockWith(255, liquidTile(1, static_cast<LiquidKind>(5)))}}); },
       {"tile 255: invalid liquid_kind value 5"}},
      {"material index out of range",
       [&] { return validateRaw(TerrainScope::Full, {{0, 0, 0, blockWith(1, granite(2))}}, twoMaterials); },
       {"material index 2 out of range (materials.size() = 2)"}},
      {"material index 0 without any table",
       [] { return validateRaw(TerrainScope::Full, {{0, 0, 0, blockWith(1, granite(0))}}, {}); },
       {"material index 0 out of range"}},
      {"empty material identifier",
       [] { return validateRaw(TerrainScope::Full, {{0, 0, 0, fullBlock()}}, {"GRANITE", ""}); },
       {"materials[1] is empty"}},
      {"liquid_level above 7",
       [] { return validateRaw(TerrainScope::Full, {{0, 0, 0, blockWith(9, liquidTile(8, LiquidKind::Water))}}); },
       {"tile 9: liquid_level 8 exceeds 7"}},
      {"liquid_level 3 with liquid_kind None",
       [] { return validateRaw(TerrainScope::Full, {{0, 0, 0, blockWith(9, liquidTile(3, LiquidKind::None))}}); },
       {"inconsistent with liquid_kind"}},
      {"liquid_level 0 with liquid_kind Magma",
       [] { return validateRaw(TerrainScope::Full, {{0, 0, 0, blockWith(9, liquidTile(0, LiquidKind::Magma))}}); },
       {"inconsistent with liquid_kind"}},
      {"duplicate block coordinates in one snapshot",
       [] { return validateRaw(TerrainScope::Full, {{0, 0, 0, fullBlock()}, {0, 0, 0, fullBlock()}}, {}, TilePos(16, 16, 2)); },
       {"duplicate block coordinates"}},
      {"Full snapshot that does not cover the whole map",
       [&] {
         return validateRaw(TerrainScope::Full, {{0, 0, 0, fullBlock()}, {1, 0, 0, fullBlock()}, {0, 0, 1, fullBlock()}},
                            {}, dims4);
       },
       {"terrain_scope Full with 3 blocks, map needs 4"}},
      {"Delta before the first Full in a stream",
       [] { return forgedScopeStream(TerrainScope::Delta, 2); }, {"snapshot #0", "Delta before any Full"}},
      {"v1 (schema_version 1) snapshots are rejected loudly",
       [] {
         SyntheticFort fort(8, 8, 2);
         fort.addUnit(1, "DWARF", 0, 0, 0);
         fort.forgeSchemaVersion(1);
         fort.snapshot(1);
         return validateStream(mustParse(fort));
       },
       {"schema version mismatch: snapshot has 1, consumer expects 11"}},
  });
  expectAcceptance({
      {"material index 1 of 2",
       [&] { return validateRaw(TerrainScope::Full, {{0, 0, 0, blockWith(1, granite(1))}}, twoMaterials); }},
      {"0xFFFF means no material even without a table",
       [] { return validateRaw(TerrainScope::Full, {{0, 0, 0, blockWith(1, granite(kNoMaterial))}}, {}); }},
      {"liquid_level 7 with liquid_kind Magma",
       [] { return validateRaw(TerrainScope::Full, {{0, 0, 0, blockWith(9, liquidTile(7, LiquidKind::Magma))}}); }},
      {"Full snapshot covering all 4 blocks",
       [&] {
         return validateRaw(TerrainScope::Full,
                            {{0, 0, 0, fullBlock()}, {1, 0, 0, fullBlock()}, {0, 0, 1, fullBlock()}, {1, 0, 1, fullBlock()}},
                            {}, dims4);
       }},
  });
}

TEST_CASE("validator accepts automatic mining and every allocated tile flag") {
  auto tiles = fullBlock();
  tiles[3] = TileState(TileShape::Floor, MaterialKind::None, kNoMaterial, 0, LiquidKind::None,
                       TileFlags::DigAuto, df3d::mirror::DesignationKind::None);
  auto err = validateRaw(TerrainScope::Full, {{0, 0, 0, tiles}});
  CHECK_FALSE(err);
  // Every defined bit at once is fine.
  tiles[3] = TileState(TileShape::Floor, MaterialKind::None, kNoMaterial, 0, LiquidKind::None,
                       TileFlags::ANY, df3d::mirror::DesignationKind::None);
  CHECK(!validateRaw(TerrainScope::Full, {{0, 0, 0, tiles}}));
}

TEST_CASE("validator: None snapshots may precede the first Full; Delta after Full is fine") {
  SyntheticFort fort(16, 16, 1);
  fort.addUnit(1, "DWARF", 0, 0, 0);
  fort.snapshot(1);  // None (terrain untouched yet)
  fort.snapshot(2);  // None
  fort.setTile(0, 0, 0, granite(fort.material("GRANITE")));
  fort.snapshot(3);  // Full
  fort.setTile(1, 0, 0, granite(0));
  fort.snapshot(4);  // Delta
  auto fs = mustParse(fort);
  CHECK(!validateStream(fs));
  CHECK(fs.snapshots[0]->terrain_scope() == TerrainScope::None);
  CHECK(fs.snapshots[2]->terrain_scope() == TerrainScope::Full);
  CHECK(fs.snapshots[3]->terrain_scope() == TerrainScope::Delta);
}

TEST_CASE("TerrainStreamState tracks Full across snapshots") {
  SyntheticFort fort(16, 16, 1);
  fort.snapshot(1);  // None
  fort.setTile(0, 0, 0, granite(fort.material("GRANITE")));
  fort.snapshot(2);  // Full
  fort.snapshot(3);  // Delta
  auto fs = mustParse(fort);
  TerrainStreamState st;
  CHECK(!st.check(*fs.snapshots[0]));
  CHECK(!st.seenFull());
  CHECK(st.check(*fs.snapshots[2]));  // Delta first: rejected
  CHECK(!st.check(*fs.snapshots[1]));
  CHECK(st.seenFull());
  CHECK(!st.check(*fs.snapshots[2]));
}

TEST_CASE("terrain helpers: block arithmetic") {
  CHECK(blocksAlong(1) == 1);
  CHECK(blocksAlong(16) == 1);
  CHECK(blocksAlong(17) == 2);
  CHECK(blocksAlong(192) == 12);
  CHECK(blockCount(192, 192, 145) == 12 * 12 * 145);
  CHECK(tileIndex(0, 0) == 0);
  CHECK(tileIndex(15, 0) == 15);
  CHECK(tileIndex(0, 1) == 16);
  CHECK(tileIndex(15, 15) == 255);
  CHECK(sizeof(TileState) == 8);
  CHECK(tileEquals(emptyTile(), emptyTile()));
  CHECK(!tileEquals(emptyTile(), granite(0)));
}
