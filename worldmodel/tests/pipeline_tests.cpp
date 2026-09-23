// Tier 1: semantic pipeline — synthetic fixture in → world model →
// assertions on queries and lifecycle events.
#include <doctest.h>

#include <algorithm>

#include "synthetic_builder.h"
#include "fixture_io.h"
#include "wm/world_model.h"

using namespace wm;
namespace m = df3d::mirror;

namespace {
WorldModel modelFrom(const m::SyntheticFort& fort, WorldModelConfig cfg = {}) {
  WorldModel model(cfg);
  std::string err;
  REQUIRE_MESSAGE(loadFixtureBytes(model, fort.serialize(), err), err);
  return model;
}
}  // namespace

TEST_CASE("fixture → model: identity, species, positions queryable") {
  m::SyntheticFort fort(48, 48, 10);
  fort.addUnit(7, "DWARF", 10, 10, 5, m::JobKind::Mine);
  fort.addUnit(9, "CAT", 20, 20, 5);
  fort.snapshot(100);
  fort.moveUnit(7, 11, 10, 5);
  fort.snapshot(101);

  auto model = modelFrom(fort);
  CHECK(model.hasData());
  CHECK(model.latestTick() == 101);
  CHECK(model.mapSize() == TilePos{48, 48, 10});
  CHECK(model.unitIds() == std::vector<UnitId>{7, 9});
  REQUIRE(model.unitSpecies(7));
  CHECK(*model.unitSpecies(7) == "DWARF");
  REQUIRE(model.unitSpecies(9));
  CHECK(*model.unitSpecies(9) == "CAT");

  auto r = model.evaluate(7, 100.5);
  CHECK(r.presence == Presence::Present);
  CHECK(r.pos.x == doctest::Approx(10.5f));
  CHECK(r.job == JobKind::Mine);
}

TEST_CASE("lifecycle: appear and depart events with correct ticks") {
  m::SyntheticFort fort(16, 16, 4);
  fort.addUnit(1, "DWARF", 1, 1, 0);
  fort.snapshot(10);
  fort.addUnit(2, "GOBLIN", 8, 8, 0);
  fort.snapshot(11);
  fort.removeUnit(2);  // slain
  fort.snapshot(12);

  auto model = modelFrom(fort);
  auto events = model.drainEvents();
  REQUIRE(events.size() == 3);
  CHECK(events[0].kind == LifecycleEvent::Kind::Appeared);
  CHECK(events[0].id == 1);
  CHECK(events[0].tick == 10);
  CHECK(events[1].kind == LifecycleEvent::Kind::Appeared);
  CHECK(events[1].id == 2);
  CHECK(events[2].kind == LifecycleEvent::Kind::Departed);
  CHECK(events[2].id == 2);
  CHECK(events[2].tick == 12);
  CHECK(model.drainEvents().empty());  // drained

  CHECK(model.evaluate(2, 11.5).presence == Presence::Present);
  CHECK(model.evaluate(2, 12.0).presence == Presence::Departed);
}

TEST_CASE("teleport through the full pipeline is classified, not smoothed") {
  m::SyntheticFort fort(64, 64, 4);
  fort.addUnit(3, "DWARF", 2, 2, 0);
  fort.snapshot(50);
  fort.moveUnit(3, 60, 60, 0);  // non-physical jump
  fort.snapshot(51);

  auto model = modelFrom(fort);
  auto mid = model.evaluate(3, 50.5);
  CHECK(mid.segment == SegmentKind::Teleport);
  CHECK(mid.pos.x == doctest::Approx(2.0f));
}

TEST_CASE("unitsInBox returns present units inside the box, sorted by id") {
  m::SyntheticFort fort(32, 32, 4);
  fort.addUnit(5, "DWARF", 4, 4, 1);
  fort.addUnit(6, "DWARF", 10, 10, 1);
  fort.addUnit(8, "CAT", 5, 5, 1);
  fort.snapshot(20);
  fort.snapshot(21);

  auto model = modelFrom(fort);
  auto hits = model.unitsInBox(TilePos{0, 0, 0}, TilePos{6, 6, 3}, 20.5);
  REQUIRE(hits.size() == 2);
  CHECK(hits[0].first == 5);
  CHECK(hits[1].first == 8);
}

TEST_CASE("render tick derives from replayed snapshot timing") {
  m::SyntheticFort fort(16, 16, 4);
  fort.addUnit(1, "DWARF", 1, 1, 0);
  // 1 tick per 100 ms → 10 ticks/sec, replayed from emitted_at_ms.
  fort.snapshot(100, 10000);
  fort.moveUnit(1, 2, 1, 0);
  fort.snapshot(101, 10100);
  fort.moveUnit(1, 3, 1, 0);
  fort.snapshot(102, 10200);

  WorldModelConfig cfg;
  cfg.renderDelayTicks = 1.0;
  auto model = modelFrom(fort, cfg);
  // At the last arrival (10.2s wall): estimate ≈ tick 102, render tick ≈ 101.
  CHECK(model.renderTickAt(10.2) == doctest::Approx(101.0));
  // 50 ms later the render tick has advanced half a tick.
  CHECK(model.renderTickAt(10.25) == doctest::Approx(101.5));
}

TEST_CASE("attaching to a paused sim shows the current state immediately") {
  // One snapshot (sim paused since attach): the delayed render clock would
  // sit before the only keyframe and evaluate an empty world. renderTickAt
  // clamps to the first ingested tick instead.
  m::SyntheticFort fort(16, 16, 4);
  fort.addUnit(1, "DWARF", 3, 3, 1);
  fort.snapshot(500, 20000);

  auto model = modelFrom(fort);
  const double rt = model.renderTickAt(25.0);  // 5s later, still paused
  CHECK(rt == doctest::Approx(500.0));
  CHECK(model.evaluate(1, rt).presence == Presence::Present);
}

TEST_CASE("invalid fixture is rejected loudly, not ingested") {
  m::SyntheticFort fort(8, 8, 2);
  fort.addUnit(1, "DWARF", 1, 1, 0);
  fort.forgeSchemaVersion(9999);  // any value != SchemaVersion::Current
  fort.snapshot(5);
  WorldModel model;
  std::string err;
  CHECK(!loadFixtureBytes(model, fort.serialize(), err));
  CHECK(err.find("schema version mismatch") != std::string::npos);
  CHECK(!model.hasData());
}

TEST_CASE("reappearance after departure emits a fresh Appeared event") {
  m::SyntheticFort fort(16, 16, 4);
  fort.addUnit(4, "DWARF", 3, 3, 0);
  fort.snapshot(10);
  fort.removeUnit(4);
  fort.snapshot(11);
  fort.addUnit(4, "DWARF", 3, 3, 0);
  fort.snapshot(12);

  auto model = modelFrom(fort);
  auto events = model.drainEvents();
  REQUIRE(events.size() == 3);
  CHECK(events[2].kind == LifecycleEvent::Kind::Appeared);
  CHECK(events[2].tick == 12);
  CHECK(model.evaluate(4, 12.0).presence == Presence::Present);
}

TEST_CASE("smooth motion through the pipeline: a walker never jumps") {
  // A dwarf walking one tile every 10 ticks, mirrored every tick. With
  // change-point keyframes and the move window, evaluated motion is
  // constant-speed: no sample moves more than 0.1 tile per tick.
  m::SyntheticFort fort(64, 64, 4);
  fort.addUnit(1, "DWARF", 10, 10, 1, m::JobKind::HaulItem);
  Tick tick = 1000;
  for (int step = 0; step < 6; ++step) {
    for (int k = 0; k < 10; ++k) fort.snapshot(tick++);
    fort.moveUnit(1, 10 + step + 1, 10, 1);
  }
  fort.snapshot(tick);

  auto model = modelFrom(fort);
  float prev = model.evaluate(1, 1010.0).pos.x;
  float maxJump = 0.0f;
  for (double t = 1010.5; t <= 1059.0; t += 0.5) {
    float x = model.evaluate(1, t).pos.x;
    maxJump = std::max(maxJump, x - prev);
    CHECK(x >= prev);
    prev = x;
  }
  CHECK(maxJump <= 0.05f + 1e-4f);
  // The full walk was covered, not skipped.
  CHECK(model.evaluate(1, 1059.0).pos.x == doctest::Approx(15.9f));
}

// --- terrain through the fixture pipeline ---

namespace {
m::TileState wallOf(m::MaterialKind kind, uint16_t mat, m::TileFlags flags = m::TileFlags::NONE) {
  return m::TileState(m::TileShape::Wall, kind, mat, 0, m::LiquidKind::None, flags, df3d::mirror::DesignationKind::None);
}

TEST_CASE("v7 ring ingestion preserves exact designation changes with identical flags") {
  m::SyntheticFort fort(16,16,1);
  const auto material=fort.material("GRANITE");
  fort.setTile(2,3,0,m::TileState(m::TileShape::Wall,m::MaterialKind::Stone,material,0,m::LiquidKind::None,
      m::TileFlags::DigDesignated,m::DesignationKind::Dig));
  fort.snapshot(10);
  fort.setTile(2,3,0,m::TileState(m::TileShape::Wall,m::MaterialKind::Stone,material,0,m::LiquidKind::None,
      m::TileFlags::DigDesignated,m::DesignationKind::Channel));
  fort.snapshot(11);
  auto model=modelFrom(fort);
  REQUIRE(model.tileAt({2,3,0}));
  CHECK(model.tileAt({2,3,0})->designation==DesignationKind::Channel);
  CHECK(model.terrainVersion()==2);
}
}  // namespace

TEST_CASE("terrain: Full then Deltas from the synthetic builder reach the store") {
  m::SyntheticFort fort(40, 24, 3);  // 3x2 blocks per z, partial edge blocks
  const uint16_t granite = fort.material("GRANITE");
  const uint16_t loam = fort.material("CLAY_LOAM");
  fort.fillBox(m::TilePos(0, 0, 0), m::TilePos(39, 23, 1), wallOf(m::MaterialKind::Stone, granite));
  fort.fillBox(m::TilePos(0, 0, 2), m::TilePos(39, 23, 2), wallOf(m::MaterialKind::Soil, loam));
  fort.addUnit(1, "DWARF", 3, 3, 2);
  fort.snapshot(10);  // Full
  fort.snapshot(11);  // empty Delta
  fort.setTile(20, 5, 1, m::TileState(m::TileShape::Floor, m::MaterialKind::Stone, granite, 0,
                                      m::LiquidKind::None, m::TileFlags::NONE, df3d::mirror::DesignationKind::None));
  fort.snapshot(12);  // Delta: block (1,0,1)

  auto model = modelFrom(fort);
  CHECK(model.hasTerrain());
  CHECK(model.mapBlockCount() == 18);
  CHECK(model.knownBlockCount() == 18);
  CHECK(model.terrainVersion() == 2);
  CHECK(model.blockVersion(BlockPos{1, 0, 1}) == 2);
  CHECK(model.blockVersion(BlockPos{0, 0, 1}) == 1);
  auto t = model.tileAt(TilePos{20, 5, 1});
  REQUIRE(t);
  CHECK(t->shape == TileShape::Floor);
  CHECK(model.materialName(t->material) == "GRANITE");
  CHECK(model.materialName(model.tileAt(TilePos{39, 23, 2})->material) == "CLAY_LOAM");
  CHECK(!model.tileAt(TilePos{40, 0, 0}));

  auto ev = model.drainTerrainEvents();
  REQUIRE(ev.size() == 18);  // 18 from the Full; the later change coalesces
  const auto changed = std::find_if(ev.begin(), ev.end(), [](const TerrainBlockEvent& e) {
    return e.pos == BlockPos{1, 0, 1};
  });
  REQUIRE(changed != ev.end());
  CHECK(changed->version == 2);
  CHECK(changed->tick == 12);
}

TEST_CASE("terrain: units-only recorded stream leaves terrain unknown") {
  m::SyntheticFort fort(16, 16, 2);
  fort.addUnit(1, "DWARF", 1, 1, 0);
  fort.snapshot(10);
  fort.snapshot(11);
  auto model = modelFrom(fort);
  CHECK(!model.hasTerrain());
  CHECK(model.mapBlockCount() == 2);
  CHECK(model.knownBlockCount() == 0);
  CHECK(model.drainTerrainEvents().empty());
}

TEST_CASE("demo fort fixture: dig designations are mined out block by block") {
  // fixtures/synthetic/demo_fort.df3dfix: tick 1000 is the Full; ticks
  // 1001..1006 each mine out the column x=8+i, y=20..22 at z=4, all inside
  // block (0,1,4); tick 1011 opens the shaft at (14,20) on z=2..5.
  WorldModel model;
  std::string err;
  REQUIRE_MESSAGE(loadFixtureFile(model, DF3D_FIXTURE_DIR "/synthetic/demo_fort.df3dfix", err),
                  err);
  CHECK(model.hasTerrain());
  CHECK(model.mapSize() == TilePos{48, 48, 12});
  CHECK(model.mapBlockCount() == 108);
  CHECK(model.knownBlockCount() == 108);

  // Designations that were mined out are now floors; the rest still stand.
  for (int i = 1; i <= 6; ++i) {
    auto t = model.tileAt(TilePos{8 + i, 21, 4});
    REQUIRE(t);
    CHECK(t->shape == TileShape::Floor);
    CHECK((t->flags & kTileDigDesignated) == 0);
    CHECK(model.materialName(t->material) == "CLAY_LOAM");
  }
  auto pending = model.tileAt(TilePos{9, 20, 4});  // x=9 was mined (i=1)...
  REQUIRE(pending);
  CHECK(pending->shape == TileShape::Floor);
  auto shaft = model.tileAt(TilePos{14, 20, 3});
  REQUIRE(shaft);
  CHECK(shaft->shape == TileShape::Empty);

  // Block (0,1,4) changed once per mining tick plus the shaft opening
  // (14,20,4 lies in it too): 1 (Full) + 6 + 1 = 8. Neighbours untouched.
  CHECK(model.blockVersion(BlockPos{0, 1, 4}) == 8);
  CHECK(model.blockVersion(BlockPos{1, 1, 4}) == 1);
  CHECK(model.blockVersion(BlockPos{0, 1, 3}) == 2);  // shaft only
  CHECK(model.blockVersion(BlockPos{0, 1, 5}) == 2);
  CHECK(model.blockVersion(BlockPos{0, 1, 2}) == 2);
  CHECK(model.blockVersion(BlockPos{0, 0, 4}) == 1);
  CHECK(model.terrainVersion() == 8);  // Full + 6 mining ticks + shaft

  // Events: one per block, so 108; the changed ones carry their final
  // version and last-change tick.
  auto ev = model.drainTerrainEvents();
  CHECK(ev.size() == 108);
  auto find = [&](BlockPos p) {
    return std::find_if(ev.begin(), ev.end(),
                        [p](const TerrainBlockEvent& e) { return e.pos == p; });
  };
  REQUIRE(find(BlockPos{0, 1, 4}) != ev.end());
  CHECK(find(BlockPos{0, 1, 4})->version == 8);
  CHECK(find(BlockPos{0, 1, 4})->tick == 1011);
  CHECK(find(BlockPos{1, 1, 4})->tick == 1000);
  CHECK(model.drainTerrainEvents().empty());

  // Materials of the demo fort interned once each (five terrain materials,
  // the iron of the bars and pick (v4), the corpse, corpse piece and web
  // materials (v5)).
  CHECK(model.materialCount() == 10);  // + CREATURE:DOG:MUSCLE
  CHECK(model.materialName(model.tileAt(TilePos{33, 11, 1})->material) == "MAGNETITE");
  CHECK(model.tileAt(TilePos{36, 36, 5})->liquidLevel == 7);
  CHECK(model.tileAt(TilePos{41, 41, 0})->liquidKind == LiquidKind::Magma);
}

TEST_CASE("mining out designations one block-Delta per tick bumps only that block") {
  // The demo fort's dig scenario reproduced with the builder: Full, then
  // one-block Deltas; the changed-block events single out that block.
  m::SyntheticFort fort(48, 48, 6);
  const uint16_t loam = fort.material("CLAY_LOAM");
  fort.fillBox(m::TilePos(0, 0, 0), m::TilePos(47, 47, 5),
               wallOf(m::MaterialKind::Soil, loam, m::TileFlags::Hidden));
  fort.fillBox(m::TilePos(9, 20, 4), m::TilePos(14, 22, 4),
               wallOf(m::MaterialKind::Soil, loam, m::TileFlags::Hidden | m::TileFlags::DigDesignated));
  fort.snapshot(1000);
  WorldModel model;
  std::string err;
  REQUIRE(loadFixtureBytes(model, fort.serialize(), err));
  CHECK(model.drainTerrainEvents().size() == 54);

  // Fixture replay is whole-stream, so each step builds a fresh model from
  // the extended stream and asserts that exactly one block carries a
  // bumped version, with the tick of the step that changed it.
  const m::TileState dug(m::TileShape::Floor, m::MaterialKind::Soil, loam, 0,
                         m::LiquidKind::None, m::TileFlags::NONE, m::DesignationKind::None);
  for (int i = 1; i <= 6; ++i) {
    fort.fillBox(m::TilePos(8 + i, 20, 4), m::TilePos(8 + i, 22, 4), dug);
    fort.snapshot(1000 + i);
    WorldModel m2;
    REQUIRE(loadFixtureBytes(m2, fort.serialize(), err));
    CHECK(m2.blockVersion(BlockPos{0, 1, 4}) == static_cast<uint64_t>(1 + i));
    CHECK(m2.terrainVersion() == static_cast<uint64_t>(1 + i));
    auto ev = m2.drainTerrainEvents();
    CHECK(ev.size() == 54);
    int bumped = 0;
    for (const auto& e : ev) {
      if (e.version > 1) {
        ++bumped;
        CHECK(e.pos == BlockPos{0, 1, 4});
        CHECK(e.tick == static_cast<Tick>(1000 + i));
      }
    }
    CHECK(bumped == 1);
  }
}

TEST_CASE("FixtureReplay ingests snapshots as the injected clock passes their arrival") {
  m::SyntheticFort fort(16, 16, 2);
  const uint16_t loam = fort.material("CLAY_LOAM");
  fort.fillBox(m::TilePos(0, 0, 0), m::TilePos(15, 15, 0), wallOf(m::MaterialKind::Soil, loam));
  fort.addUnit(1, "DWARF", 1, 1, 1);
  fort.snapshot(100, 1000);  // arrival 1.0 s
  fort.moveUnit(1, 2, 1, 1);
  fort.setTile(3, 3, 0, m::TileState(m::TileShape::Floor, m::MaterialKind::Soil, loam, 0,
                                     m::LiquidKind::None, m::TileFlags::NONE, df3d::mirror::DesignationKind::None));
  fort.snapshot(101, 1500);  // 1.5 s
  fort.addUnit(2, "CAT", 5, 5, 1);
  fort.snapshot(102, 2000);  // 2.0 s

  std::string err;
  auto replay = FixtureReplay::fromBytes(fort.serialize(), err);
  REQUIRE_MESSAGE(replay, err);
  CHECK(replay->snapshotCount() == 3);
  CHECK(replay->firstArrivalSeconds() == doctest::Approx(1.0));
  CHECK(replay->lastArrivalSeconds() == doctest::Approx(2.0));

  WorldModel model;
  CHECK(replay->stepTo(model, 0.5) == 0);
  CHECK(!model.hasData());
  CHECK(replay->stepTo(model, 1.0) == 1);
  CHECK(model.hasTerrain());
  CHECK(model.latestTick() == 100);
  CHECK(model.drainTerrainEvents().size() == 2);  // the Full: both z levels
  CHECK(model.unitIds().size() == 1);
  CHECK(replay->stepTo(model, 1.2) == 0);
  CHECK(replay->stepTo(model, 1.6) == 1);
  CHECK(model.latestTick() == 101);
  CHECK(model.drainTerrainEvents().size() == 1);  // the one-block Delta
  CHECK(!replay->done());
  CHECK(replay->stepAll(model) == 1);
  CHECK(replay->done());
  CHECK(model.unitIds().size() == 2);
  CHECK(replay->stepAll(model) == 0);

  // The demo fixture opens and validates; an invalid one is refused.
  auto demo = FixtureReplay::open(DF3D_FIXTURE_DIR "/synthetic/demo_fort.df3dfix", err);
  REQUIRE_MESSAGE(demo, err);
  CHECK(demo->snapshotCount() == 15);
  CHECK(FixtureReplay::open(DF3D_FIXTURE_DIR "/does_not_exist.df3dfix", err) == nullptr);
  CHECK(!err.empty());
}

// --- unit appearance references ---

namespace {
std::vector<m::SyntheticFort::Layer> stackFor(int16_t skinRow, bool helm) {
  m::SyntheticFort::Layer body;
  body.page = "DWARF_BODY";
  body.tileX = 3;
  body.tileY = 4;
  body.palette = "data/vanilla/x/graphics/images/dwarf/dwarf_body_palettes.png";
  body.paletteRow = skinRow;
  body.paletteKeyRow = 0;
  m::SyntheticFort::Layer hair;
  hair.page = "DWARF_HAIR";
  hair.tileX = 3;
  hair.tileY = 13;
  hair.cellsY = 2;
  hair.offsetY = -2;
  std::vector<m::SyntheticFort::Layer> s{body, hair};
  if (helm) {
    m::SyntheticFort::Layer h;
    h.page = "DWARF_WEARABLES";
    h.tileX = 0;
    h.tileY = 24;
    s.push_back(h);
  }
  return s;
}
}  // namespace

TEST_CASE("appearance: arrives, is queryable with model-wide ids, and is kept for departed units") {
  m::SyntheticFort fort(48, 48, 10);
  fort.addUnit(1, "DWARF", 10, 10, 5);
  fort.addUnit(2, "CAT", 12, 10, 5);
  fort.snapshot(100);  // no appearance yet
  fort.setAppearance(1, stackFor(2, false));
  fort.snapshot(101);
  fort.removeUnit(1);
  fort.snapshot(102);

  auto model = modelFrom(fort);
  CHECK(model.unitAppearance(2) == nullptr);
  const UnitAppearance* a = model.unitAppearance(1);
  REQUIRE(a);
  CHECK(a->tick == 101);
  REQUIRE(a->layers.size() == 2);
  CHECK(model.tilePageName(a->layers[0].page) == "DWARF_BODY");
  CHECK(model.tilePageName(a->layers[1].page) == "DWARF_HAIR");
  CHECK(a->layers[0].tileX == 3);
  CHECK(a->layers[0].paletteRow == 2);
  CHECK(a->layers[0].paletteKeyRow == 0);
  CHECK(model.paletteName(a->layers[0].palette) ==
        "data/vanilla/x/graphics/images/dwarf/dwarf_body_palettes.png");
  CHECK(a->layers[1].palette == kNoPalette);
  CHECK(model.paletteName(a->layers[1].palette).empty());
  CHECK(a->layers[1].cellsY == 2);
  CHECK(a->layers[1].offsetY == -2);
  CHECK(model.tilePageCount() == 2);
  CHECK(model.paletteCount() == 1);
  CHECK(model.appearanceVersion() == 1);
  // Departed at 102, appearance still known.
  CHECK(model.evaluate(1, 102.5).presence == Presence::Departed);
  CHECK(model.unitAppearance(1) != nullptr);
}

TEST_CASE("appearance: upsert on change, no event on identical re-send, events coalesce") {
  m::SyntheticFort fort(48, 48, 10);
  fort.addUnit(1, "DWARF", 10, 10, 5);
  fort.addUnit(2, "DWARF", 12, 10, 5);
  fort.setAppearance(1, stackFor(2, false));
  fort.setAppearance(2, stackFor(3, false));
  fort.snapshot(100);
  fort.setAppearance(1, stackFor(2, false));  // identical re-send
  fort.snapshot(101);
  fort.setAppearance(1, stackFor(2, true));  // helm on
  fort.snapshot(102);
  fort.setAppearance(1, stackFor(4, true));  // skin row changes
  fort.snapshot(103);

  WorldModel model;
  std::string err;
  auto replay = FixtureReplay::fromBytes(fort.serialize(), err);
  REQUIRE_MESSAGE(replay, err);
  replay->stepTo(model, 1.0);  // tick 100 only
  auto ev = model.drainAppearanceEvents();
  REQUIRE(ev.size() == 2);
  CHECK(ev[0].id == 1);
  CHECK(ev[1].id == 2);
  CHECK(ev[0].tick == 100);
  const uint32_t v0 = ev[0].version;
  CHECK(model.appearanceVersion() == 1);

  replay->stepTo(model, 1.01);  // tick 101: identical re-send
  CHECK(model.drainAppearanceEvents().empty());
  CHECK(model.appearanceVersion() == 1);
  CHECK(model.unitAppearance(1)->tick == 100);

  replay->stepAll(model);  // ticks 102 and 103 both change unit 1
  ev = model.drainAppearanceEvents();
  REQUIRE(ev.size() == 1);  // coalesced
  CHECK(ev[0].id == 1);
  CHECK(ev[0].tick == 103);
  CHECK(ev[0].version != v0);
  CHECK(model.appearanceVersion() == 3);
  const UnitAppearance* a = model.unitAppearance(1);
  REQUIRE(a);
  REQUIRE(a->layers.size() == 3);
  CHECK(model.tilePageName(a->layers[2].page) == "DWARF_WEARABLES");
  CHECK(a->layers[0].paletteRow == 4);
  CHECK(model.drainAppearanceEvents().empty());
  // Page ids are model-wide: the same token maps to the same id later.
  CHECK(model.unitAppearance(2)->layers[0].page == a->layers[0].page);
}

TEST_CASE("appearance: Full covers every unit, including empty stacks") {
  m::SyntheticFort fort(48, 48, 10);
  fort.addUnit(1, "DWARF", 10, 10, 5);
  fort.addUnit(2, "CAT", 12, 10, 5);
  fort.setAppearance(1, stackFor(1, false));
  fort.requestFullAppearances();
  fort.snapshot(100);
  auto model = modelFrom(fort);
  REQUIRE(model.unitAppearance(2));
  CHECK(model.unitAppearance(2)->layers.empty());
  CHECK(model.drainAppearanceEvents().size() == 2);
}

TEST_CASE("demo fort fixture carries appearances and one mid-stream change") {
  WorldModel model;
  std::string err;
  REQUIRE_MESSAGE(loadFixtureFile(model, DF3D_FIXTURE_DIR "/synthetic/demo_fort.df3dfix", err), err);
  for (UnitId id : {1u, 2u, 3u, 4u}) {
    REQUIRE_MESSAGE(model.unitAppearance(id), "unit " << id);
    CHECK_FALSE(model.unitAppearance(id)->layers.empty());
  }
  CHECK(model.unitAppearance(9) == nullptr);  // the goblin never got one
  CHECK(model.unitAppearance(2)->tick == 1007);  // helm on
  CHECK(model.unitAppearance(1)->tick == 1000);
  CHECK(model.tilePageName(model.unitAppearance(3)->layers[0].page) == "DOMESTIC");
}

TEST_CASE("session reset drops reused identities, clocks and session tables") {
  WorldModel model;
  SnapshotData old;
  old.tick = 500; old.mapSize = {16, 16, 1};
  old.units.push_back({7, {1, 1, 0}, JobKind::Idle, "DWARF"});
  old.appearanceScope = AppearanceScope::Full;
  old.appearances.push_back({7, 42, {}});
  old.glyphScope = ChangeScope::Full;
  old.creatureGlyphs.push_back({"DWARF", {}});
  old.itemScope = ChangeScope::Full;
  ItemObservation item; item.id = 4; old.items.push_back(item);
  model.ingest(old, 0.0);
  const auto generation = model.sessionGeneration();
  SnapshotData fresh;
  fresh.tick = 3; fresh.mapSize = old.mapSize;
  fresh.units.push_back({7, {9, 9, 0}, JobKind::Idle, "CAT"});
  model.ingest(fresh, 1.0);
  CHECK(model.sessionGeneration() == generation + 1);
  CHECK(model.renderTickAt(1.0) == 3.0);
  CHECK(model.evaluate(7, model.renderTickAt(1.0)).pos.x == 9);
  CHECK(*model.unitSpecies(7) == "CAT");
  CHECK(model.unitAppearance(7) == nullptr);
  CHECK(model.creatureGlyph("DWARF") == nullptr);
  CHECK(model.itemCount() == 0);
  CHECK_FALSE(model.itemsKnown());
  model.resetSession();
  CHECK(model.sessionGeneration() == generation + 2);
  CHECK_FALSE(model.hasData());
  CHECK(model.unitIds().empty());
}

TEST_CASE("body volume survives transport, growth and unknown producers") {
  m::SyntheticFort fort(16,16,4);
  fort.addUnit(1,"DWARF",1,1,0);
  fort.snapshot(1);
  CHECK(modelFrom(fort).unitBodyVolume(1) == 0);
  fort.setBodyVolume(1,3000);
  fort.snapshot(2);
  CHECK(modelFrom(fort).unitBodyVolume(1) == 3000);
  fort.setBodyVolume(1,60000);
  fort.snapshot(3);
  CHECK(modelFrom(fort).unitBodyVolume(1) == 60000);
  CHECK(modelFrom(fort).unitBodyVolume(999) == 0);
}

TEST_CASE("unit status flags replace authoritative state and reset with session") {
  WorldModel model;
  SnapshotData snapshot;
  snapshot.tick=1; snapshot.mapSize={16,16,4};
  snapshot.units.push_back({1,{1,1,0},JobKind::Idle,"DWARF"});
  model.ingest(snapshot,0.0);
  CHECK(model.unitStatusFlags(1)==0);
  snapshot.tick=2;
  snapshot.units[0].statusFlags=UnitStatus::Stunned|UnitStatus::TellingStory;
  model.ingest(snapshot,0.1);
  CHECK(model.unitStatusFlags(1)==(UnitStatus::Stunned|UnitStatus::TellingStory));
  snapshot.tick=3; snapshot.units[0].statusFlags=UnitStatus::Sleeping;
  model.ingest(snapshot,0.2);
  CHECK(model.unitStatusFlags(1)==UnitStatus::Sleeping);
  CHECK(model.unitStatusFlags(999)==0);
  model.resetSession();
  CHECK(model.unitStatusFlags(1)==0);
}

TEST_CASE("unit status survives snapshot transport and legacy default") {
  m::SyntheticFort fort(16,16,4);
  fort.addUnit(1,"DWARF",1,1,0);
  fort.snapshot(1);
  CHECK(modelFrom(fort).unitStatusFlags(1)==0);
  fort.setUnitStatusFlags(1,UnitStatus::RecitingPoetry|UnitStatus::Stunned|UnitStatus::MajorInjury|UnitStatus::Climbing);
  fort.snapshot(2);
  CHECK(modelFrom(fort).unitStatusFlags(1)==(UnitStatus::RecitingPoetry|UnitStatus::Stunned|UnitStatus::MajorInjury|UnitStatus::Climbing));
  fort.setUnitStatusFlags(1,0);
  fort.snapshot(3);
  CHECK(modelFrom(fort).unitStatusFlags(1)==0);
}

TEST_CASE("sparse designation details ingest independently of fixed tile operation") {
  flatbuffers::FlatBufferBuilder fbb;
  std::vector<m::TileState> tiles(256,m::emptyTile());
  tiles[50]=m::TileState(m::TileShape::Wall,m::MaterialKind::Stone,m::kNoMaterial,0,m::LiquidKind::None,m::TileFlags::DigDesignated,m::DesignationKind::Channel);
  const auto details=fbb.CreateVectorOfStructs(std::vector<m::DesignationDetail>{{50,3,true}});
  const auto indicators=fbb.CreateVectorOfStructs(std::vector<m::MapIndicator>{{50,9,2,1}});
  const auto block=m::CreateMapBlock(fbb,0,0,0,fbb.CreateVectorOfStructs(tiles),details,indicators,fbb.CreateVector(std::vector<uint16_t>{50}),fbb.CreateVector(std::vector<uint16_t>{50}),fbb.CreateVector(std::vector<uint16_t>{50}),fbb.CreateVector(std::vector<uint16_t>{50}));
  const auto blocks=fbb.CreateVector(std::vector<flatbuffers::Offset<m::MapBlock>>{block});
  const auto units=fbb.CreateVector(std::vector<flatbuffers::Offset<m::UnitState>>{});
  const m::TilePos dims(16,16,1);
  const auto snap=m::CreateSnapshot(fbb,uint32_t(m::SchemaVersion::Current),1,1,&dims,units,m::TerrainScope::Full,blocks);
  fbb.FinishSizePrefixed(snap,m::SnapshotIdentifier());
  WorldModel model;std::string error;
  REQUIRE_MESSAGE(loadFixtureBytes(model,m::assembleFixture({std::vector<uint8_t>(fbb.GetBufferPointer(),fbb.GetBufferPointer()+fbb.GetSize())}),error),error);
  const auto tile=model.tileAt({2,3,0});REQUIRE(tile);
  CHECK(tile->designation==DesignationKind::Channel);
  CHECK(tile->designationPriority==3);
  CHECK(tile->designationMarker);
  CHECK(tile->track==9); CHECK(tile->traffic==2); CHECK(tile->warnings==1);
  CHECK(tile->trackClearanceBlocked); CHECK(tile->trackHorizontalBlocked);
  CHECK(tile->trackSupport); CHECK(tile->trackOpen);
  CHECK_FALSE(model.tileAt({0,0,0})->trackClearanceBlocked);
  CHECK(model.tileAt({0,0,0})->track==0); CHECK(model.tileAt({0,0,0})->warnings==0);
  CHECK(model.tileAt({0,0,0})->designationPriority==0);
  CHECK_FALSE(model.tileAt({0,0,0})->designationMarker);
}
