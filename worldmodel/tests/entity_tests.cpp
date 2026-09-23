// Buildings and map items. Tier 0: the stores driven directly
// through WorldModel::ingest with hand-built SnapshotData (upsert,
// versions, Full-drops-absent, removals, coalesced events, shared material
// interning, config switches, map change). Tier 1: SyntheticFort streams
// and the demo fixture's changes over ticks, stepwise and whole.
#include <doctest.h>

#include <algorithm>
#include <string>

#include "synthetic_builder.h"
#include "wm/world_model.h"

using namespace wm;
namespace m = df3d::mirror;

TEST_CASE("item spatial queries match full scans across mutation and value snapshots") {
  auto verify = [](const WorldModel& model) {
    for (const auto& [minimum,maximum] : std::vector<std::pair<TilePos,TilePos>>{
        {{-20,-20,-2},{64,64,12}},{{0,0,0},{15,15,3}},{{16,16,1},{31,31,1}},
        {{-17,-17,-1},{-1,-1,4}},{{2,2,0},{1,1,9}},
        {{INT32_MIN,INT32_MIN,INT32_MIN},{INT32_MAX,INT32_MAX,INT32_MAX}}}) {
      std::vector<ItemId> expected,actual;
      model.forEachItem([&](const auto& item) {
        const auto p=item.pos;
        if(p.x>=minimum.x && p.x<=maximum.x && p.y>=minimum.y && p.y<=maximum.y &&
            p.z>=minimum.z && p.z<=maximum.z)expected.push_back(item.id);
      });
      model.forEachItemInBox(minimum,maximum,[&](const auto& item) {
        CHECK(&item==model.item(item.id));actual.push_back(item.id);
      });
      std::sort(expected.begin(),expected.end());std::sort(actual.begin(),actual.end());
      CHECK(actual==expected);
    }
    for (auto [lo, hi] : std::vector<std::pair<int32_t,int32_t>>{
        {-5,20},{0,0},{1,3},{4,4},{9,12},{12,9}}) {
      std::vector<ItemId> expected, actual;
      model.forEachItem([&](const MapItem& item) {
        if (item.pos.z >= lo && item.pos.z <= hi) expected.push_back(item.id);
      });
      model.forEachItemInZRange(lo, hi, [&](const MapItem& item) {
        CHECK(&item == model.item(item.id));
        actual.push_back(item.id);
      });
      std::sort(expected.begin(), expected.end());
      std::sort(actual.begin(), actual.end());
      CHECK(actual == expected);
    }
    for (int32_t z : {-1,0,1,2,3,4,9}) {
      std::vector<ItemId> expected, actual;
      model.forEachItem([&](const MapItem& item) { if (item.pos.z == z) expected.push_back(item.id); });
      for (const auto* item : model.itemsAt(z)) actual.push_back(item->id);
      std::sort(expected.begin(), expected.end());
      CHECK(actual == expected);
      for (int32_t x : {-17,-16,-1,0,1,15,16,31,32,63}) {
        const TilePos p{x, x, z};
        expected.clear(); actual.clear();
        model.forEachItem([&](const MapItem& item) { if (item.pos == p) expected.push_back(item.id); });
        for (const auto* item : model.itemsAtTile(p)) actual.push_back(item->id);
        std::sort(expected.begin(), expected.end());
        CHECK(actual == expected);
      }
    }
  };
  WorldModel model;
  SnapshotData full;
  full.tick = 1; full.mapSize = {64,64,16}; full.itemScope = ChangeScope::Full;
  for (int i=0; i<200; ++i) {
    ItemObservation item;
    item.id = i; item.kind = ItemKind::Wood;
    item.pos = {i%64,i%64,i%5};
    full.items.push_back(item);
  }
  model.ingest(full, 0); verify(model);
  const WorldModel published = model;
  auto delta = full;
  delta.tick = 2; delta.itemScope = ChangeScope::Delta;
  delta.items.clear();
  for (int i : {0,1,2,3,4,5}) {
    auto item = full.items[i];
    // Same block move, XY block transition, level transition, appearance-only
    // update, and negative block boundaries all leave old snapshots intact.
    if (i==0) item.pos = {1,1,0};
    if (i==1) item.pos = {32,32,1};
    if (i==2) item.pos = {2,2,9};
    if (i==3) item.stack = 50;
    if (i==4) item.pos = {-1,-1,4};
    if (i==5) item.pos = {-17,-17,-1};
    delta.items.push_back(item);
  }
  delta.removedItems = {7,198,199}; // Includes swap/pop and final vector slots.
  model.ingest(delta, 1); verify(model); verify(published);
  CHECK(published.item(2)->pos.z == 2);
  CHECK(model.item(2)->pos.z == 9);
  auto reused = delta;
  reused.tick = 3; reused.items = {full.items[7]}; reused.items[0].pos = {63,63,9};
  reused.removedItems.clear();
  model.ingest(reused, 2); verify(model); verify(published);
  REQUIRE(model.item(7)); CHECK(model.item(7)->pos.z == 9);
  // A Full removes omitted IDs, including whole blocks/levels. Copies made
  // before and after mutation must never resolve IDs against another snapshot.
  WorldModel second = model;
  reused.tick = 4; reused.itemScope = ChangeScope::Full;
  model.ingest(reused, 3); verify(model); verify(second); verify(published);
  CHECK(model.itemCount() == 1);
  SnapshotData reset;
  reset.tick = 1; reset.mapSize = {32,32,2}; reset.itemScope = ChangeScope::Full;
  auto replacement = full.items[7]; replacement.pos = {0,0,1};
  reset.items = {replacement};
  model.ingest(reset, 4); verify(model); verify(second); verify(published);
  CHECK(model.itemCount() == 1); CHECK(model.itemsAt(9).empty());
}

namespace {

const TilePos kMap{48, 48, 6};

SnapshotData snap(Tick tick, ChangeScope buildings, ChangeScope items,
                  std::vector<std::string_view> materials = {}) {
  SnapshotData d;
  d.tick = tick;
  d.mapSize = kMap;
  d.buildingScope = buildings;
  d.itemScope = items;
  d.materials = std::move(materials);
  return d;
}

BuildingObservation bld(BuildingId id, BuildingKind kind, int32_t x1, int32_t y1, int32_t x2,
                        int32_t y2, int32_t z, uint16_t material = kNoMaterial,
                        BuildingStage stage = BuildingStage::Complete, uint8_t flags = 0) {
  BuildingObservation b;
  b.id = id;
  b.kind = kind;
  b.x1 = x1;
  b.y1 = y1;
  b.x2 = x2;
  b.y2 = y2;
  b.z = z;
  b.centerX = x1 + (x2 - x1) / 2;
  b.centerY = y1 + (y2 - y1) / 2;
  b.material = material;
  b.stage = stage;
  b.flags = flags;
  return b;
}

ItemObservation itm(ItemId id, ItemKind kind, int32_t x, int32_t y, int32_t z,
                    uint16_t material = kNoMaterial, uint32_t stack = 1, uint8_t flags = 0) {
  ItemObservation i;
  i.id = id;
  i.kind = kind;
  i.pos = TilePos{x, y, z};
  i.material = material;
  i.stack = stack;
  i.flags = flags;
  return i;
}

// The base scene: a workshop over a stockpile (with a hole), a bed on
// another level; a log, bars on the pile, a boulder on the bed's level.
SnapshotData baseFull(Tick tick = 1) {
  SnapshotData d = snap(tick, ChangeScope::Full, ChangeScope::Full, {"GRANITE", "OAK", "IRON"});
  d.buildings.push_back(bld(1, BuildingKind::Workshop, 10, 10, 12, 12, 2, 0));
  d.buildings.back().subtype = 2;
  BuildingObservation pile = bld(2, BuildingKind::Stockpile, 9, 9, 13, 13, 2);
  pile.extents.assign(25, 1);
  pile.extents[0] = 0;  // (9,9) left out
  d.buildings.push_back(std::move(pile));
  d.buildings.push_back(bld(3, BuildingKind::Bed, 5, 5, 5, 5, 3, 1, BuildingStage::Complete,
                            kBuildingRoomAssigned));
  d.items.push_back(itm(100, ItemKind::Wood, 20, 20, 2, 1));
  d.items.push_back(itm(101, ItemKind::Bar, 13, 13, 2, 2, 5, kItemMelt));
  d.items.push_back(itm(102, ItemKind::Boulder, 6, 5, 3, 0, 1, kItemDump));
  return d;
}

template <class E>
const E* findEvent(const std::vector<E>& events, uint32_t id) {
  auto it = std::find_if(events.begin(), events.end(), [id](const E& e) { return e.id == id; });
  return it == events.end() ? nullptr : &*it;
}

}  // namespace

TEST_CASE("entities: nothing known before a Full; every query is empty") {
  WorldModel model;
  model.ingest(snap(1, ChangeScope::None, ChangeScope::None), 0.0);
  CHECK(!model.buildingsKnown());
  CHECK(!model.itemsKnown());
  CHECK(model.buildingCount() == 0);
  CHECK(model.itemCount() == 0);
  CHECK(model.buildingsVersion() == 0);
  CHECK(model.itemsVersion() == 0);
  CHECK(model.building(1) == nullptr);
  CHECK(model.item(1) == nullptr);
  CHECK(model.buildingsAt(0).empty());
  CHECK(model.buildingsInRect(0, 0, 47, 47, 0).empty());
  CHECK(model.buildingAt(TilePos{0, 0, 0}) == nullptr);
  CHECK(model.itemsAt(0).empty());
  CHECK(model.itemsAtTile(TilePos{0, 0, 0}).empty());
  CHECK(model.drainBuildingEvents().empty());
  CHECK(model.drainItemEvents().empty());
  int n = 0;
  model.forEachBuilding([&](const Building&) { ++n; });
  model.forEachItem([&](const MapItem&) { ++n; });
  CHECK(n == 0);
}

TEST_CASE("entities: Full stores everything with model-wide materials, versions 1, queries") {
  WorldModel model;
  model.ingest(baseFull(), 0.0);
  CHECK(model.buildingsKnown());
  CHECK(model.itemsKnown());
  CHECK(model.buildingCount() == 3);
  CHECK(model.itemCount() == 3);
  CHECK(model.buildingsVersion() == 1);
  CHECK(model.itemsVersion() == 1);

  const Building* w = model.building(1);
  REQUIRE(w);
  CHECK(w->kind == BuildingKind::Workshop);
  CHECK(w->subtype == 2);
  CHECK(w->custom.empty());
  CHECK(w->width() == 3);
  CHECK(w->height() == 3);
  CHECK(w->centerX == 11);
  CHECK(w->version == 1);
  CHECK(w->tick == 1);
  CHECK(model.materialName(w->material) == "GRANITE");
  const Building* bed = model.building(3);
  REQUIRE(bed);
  CHECK(model.materialName(bed->material) == "OAK");
  CHECK((bed->flags & kBuildingRoomAssigned) != 0);
  CHECK(model.building(2)->material == kNoMaterial);
  CHECK(model.building(4) == nullptr);

  // Level and rectangle queries, sorted by id.
  auto atZ2 = model.buildingsAt(2);
  REQUIRE(atZ2.size() == 2);
  CHECK(atZ2[0]->id == 1);
  CHECK(atZ2[1]->id == 2);
  CHECK(model.buildingsAt(3).size() == 1);
  CHECK(model.buildingsAt(0).empty());
  auto touching = model.buildingsInRect(13, 0, 20, 47, 2);  // x=13 clips the stockpile only
  REQUIRE(touching.size() == 1);
  CHECK(touching[0]->id == 2);
  CHECK(model.buildingsInRect(0, 0, 47, 47, 2).size() == 2);
  CHECK(model.buildingsInRect(14, 14, 20, 20, 2).empty());
  // Tile occupancy honours extents and prefers the lowest id on overlap.
  CHECK(model.buildingAt(TilePos{9, 9, 2}) == nullptr);  // the hole
  REQUIRE(model.buildingAt(TilePos{9, 10, 2}));
  CHECK(model.buildingAt(TilePos{9, 10, 2})->id == 2);
  CHECK(model.buildingAt(TilePos{11, 11, 2})->id == 1);  // workshop over stockpile
  CHECK(model.buildingAt(TilePos{11, 11, 3}) == nullptr);
  CHECK(model.building(2)->occupies(13, 13));
  CHECK(!model.building(2)->occupies(14, 13));

  const MapItem* bars = model.item(101);
  REQUIRE(bars);
  CHECK(bars->kind == ItemKind::Bar);
  CHECK(bars->stack == 5);
  CHECK((bars->flags & kItemMelt) != 0);
  CHECK(model.materialName(bars->material) == "IRON");
  CHECK(bars->version == 1);
  auto z2 = model.itemsAt(2);
  REQUIRE(z2.size() == 2);
  CHECK(z2[0]->id == 100);
  CHECK(z2[1]->id == 101);
  CHECK(model.itemsAt(3).size() == 1);
  CHECK(model.itemsAtTile(TilePos{13, 13, 2}).size() == 1);
  CHECK(model.itemsAtTile(TilePos{13, 13, 3}).empty());
  CHECK(model.materialCount() == 3);

  auto bev = model.drainBuildingEvents();
  REQUIRE(bev.size() == 3);
  for (const auto& e : bev) {
    CHECK(e.change == EntityChange::Added);
    CHECK(e.version == 1);
    CHECK(e.tick == 1);
  }
  CHECK(bev[0].id == 1);
  auto iev = model.drainItemEvents();
  REQUIRE(iev.size() == 3);
  CHECK(iev[2].id == 102);
  CHECK(model.drainBuildingEvents().empty());
  CHECK(model.drainItemEvents().empty());
}

TEST_CASE("entities: Delta upserts changed / new, removes listed, ignores identical re-sends") {
  WorldModel model;
  model.ingest(baseFull(), 0.0);
  model.drainBuildingEvents();
  model.drainItemEvents();

  SnapshotData d = snap(2, ChangeScope::Delta, ChangeScope::Delta, {"OAK", "GRANITE"});
  d.buildings.push_back(bld(1, BuildingKind::Workshop, 10, 10, 12, 12, 2, 1));  // GRANITE again
  d.buildings.back().subtype = 2;
  d.buildings.push_back(bld(3, BuildingKind::Bed, 5, 5, 5, 5, 3, 0, BuildingStage::Complete,
                            kBuildingRoomAssigned | kBuildingForbidden));  // flags changed
  d.buildings.push_back(bld(4, BuildingKind::Door, 13, 11, 13, 11, 2, 1, BuildingStage::Planned));
  d.removedBuildings = {2, 77};  // 77 unknown: ignored
  d.items.push_back(itm(100, ItemKind::Wood, 20, 21, 2, 0));  // moved one tile
  d.removedItems = {101};
  model.ingest(d, 0.0);

  CHECK(model.buildingsVersion() == 2);
  CHECK(model.buildingCount() == 3);
  CHECK(model.building(1)->version == 1);  // identical under a reordered table
  CHECK(model.building(3)->version == 2);
  CHECK(model.building(3)->tick == 2);
  CHECK(model.building(4)->version == 1);
  CHECK(model.building(4)->stage == BuildingStage::Planned);
  CHECK(model.building(2) == nullptr);
  CHECK(model.materialCount() == 3);  // no new names
  auto bev = model.drainBuildingEvents();
  REQUIRE(bev.size() == 3);
  REQUIRE(findEvent(bev, 3));
  CHECK(findEvent(bev, 3)->change == EntityChange::Changed);
  CHECK(findEvent(bev, 3)->version == 2);
  REQUIRE(findEvent(bev, 4));
  CHECK(findEvent(bev, 4)->change == EntityChange::Added);
  REQUIRE(findEvent(bev, 2));
  CHECK(findEvent(bev, 2)->change == EntityChange::Removed);
  CHECK(findEvent(bev, 2)->version == 1);
  CHECK(findEvent(bev, 2)->tick == 2);
  CHECK(findEvent(bev, 1) == nullptr);

  CHECK(model.itemsVersion() == 2);
  CHECK(model.itemCount() == 2);
  CHECK(model.item(100)->pos == TilePos{20, 21, 2});
  CHECK(model.item(100)->version == 2);
  CHECK(model.item(101) == nullptr);
  auto iev = model.drainItemEvents();
  REQUIRE(iev.size() == 2);
  CHECK(findEvent(iev, 100)->change == EntityChange::Changed);
  CHECK(findEvent(iev, 101)->change == EntityChange::Removed);

  // An empty Delta changes nothing.
  model.ingest(snap(3, ChangeScope::Delta, ChangeScope::Delta), 0.0);
  CHECK(model.buildingsVersion() == 2);
  CHECK(model.itemsVersion() == 2);
  CHECK(model.drainBuildingEvents().empty());
  CHECK(model.drainItemEvents().empty());
}

TEST_CASE("entities: events coalesce per id between drains") {
  WorldModel model;
  model.ingest(baseFull(), 0.0);
  model.drainBuildingEvents();
  model.drainItemEvents();

  // Added then Removed: nothing. Changed then Removed: Removed. Removed
  // then re-Added: Changed (version restarts at 1). Added then Changed:
  // Added carrying the latest version.
  SnapshotData a = snap(2, ChangeScope::Delta, ChangeScope::Delta);
  a.buildings.push_back(bld(5, BuildingKind::Chair, 1, 1, 1, 1, 0));
  a.buildings.push_back(bld(3, BuildingKind::Bed, 5, 5, 5, 5, 3, kNoMaterial));  // changed
  a.removedBuildings = {1};
  a.items.push_back(itm(103, ItemKind::Boulder, 1, 1, 0));
  model.ingest(a, 0.0);
  SnapshotData b = snap(3, ChangeScope::Delta, ChangeScope::Delta);
  b.removedBuildings = {5, 3};
  b.buildings.push_back(bld(1, BuildingKind::Workshop, 10, 10, 12, 12, 2));  // re-added
  b.items.push_back(itm(103, ItemKind::Boulder, 2, 1, 0));  // moved after being added
  model.ingest(b, 0.0);

  auto bev = model.drainBuildingEvents();
  REQUIRE(bev.size() == 2);
  CHECK(findEvent(bev, 5) == nullptr);
  REQUIRE(findEvent(bev, 3));
  CHECK(findEvent(bev, 3)->change == EntityChange::Removed);
  CHECK(findEvent(bev, 3)->version == 2);
  CHECK(findEvent(bev, 3)->tick == 3);
  REQUIRE(findEvent(bev, 1));
  CHECK(findEvent(bev, 1)->change == EntityChange::Changed);
  CHECK(findEvent(bev, 1)->version == 1);
  CHECK(findEvent(bev, 1)->tick == 3);
  auto iev = model.drainItemEvents();
  REQUIRE(iev.size() == 1);
  CHECK(iev[0].id == 103);
  CHECK(iev[0].change == EntityChange::Added);
  CHECK(iev[0].version == 2);
  CHECK(model.buildingsVersion() == 3);
}

TEST_CASE("entities: a Full drops everything it does not list") {
  WorldModel model;
  model.ingest(baseFull(), 0.0);
  model.drainBuildingEvents();
  model.drainItemEvents();
  SnapshotData full = snap(2, ChangeScope::Full, ChangeScope::Full, {"OAK"});
  full.buildings.push_back(bld(3, BuildingKind::Bed, 5, 5, 5, 5, 3, 0, BuildingStage::Complete,
                               kBuildingRoomAssigned));  // unchanged
  full.items.push_back(itm(102, ItemKind::Boulder, 6, 5, 3, kNoMaterial, 1, kItemDump));  // material lost
  model.ingest(full, 0.0);
  CHECK(model.buildingCount() == 1);
  CHECK(model.building(3)->version == 1);
  CHECK(model.buildingsVersion() == 2);
  auto bev = model.drainBuildingEvents();
  REQUIRE(bev.size() == 2);
  CHECK(findEvent(bev, 1)->change == EntityChange::Removed);
  CHECK(findEvent(bev, 2)->change == EntityChange::Removed);
  CHECK(model.itemCount() == 1);
  CHECK(model.item(102)->version == 2);
  auto iev = model.drainItemEvents();
  REQUIRE(iev.size() == 3);
  CHECK(findEvent(iev, 102)->change == EntityChange::Changed);
  CHECK(findEvent(iev, 100)->change == EntityChange::Removed);
}

TEST_CASE("entities: ingestBuildings / ingestItems off keep the stores empty") {
  WorldModelConfig cfg;
  cfg.ingestBuildings = false;
  cfg.ingestItems = false;
  WorldModel model(cfg);
  model.ingest(baseFull(), 0.0);
  CHECK(!model.buildingsKnown());
  CHECK(!model.itemsKnown());
  CHECK(model.buildingCount() == 0);
  CHECK(model.itemCount() == 0);
  CHECK(model.drainBuildingEvents().empty());
  CHECK(model.drainItemEvents().empty());

  WorldModelConfig only;
  only.ingestItems = false;
  WorldModel partial(only);
  partial.ingest(baseFull(), 0.0);
  CHECK(partial.buildingCount() == 3);
  CHECK(partial.itemCount() == 0);
}

TEST_CASE("entities: materials intern without terrain and stay stable across tables") {
  WorldModel model;
  SnapshotData a = snap(1, ChangeScope::Full, ChangeScope::None, {"OAK"});
  a.buildings.push_back(bld(1, BuildingKind::Bed, 1, 1, 1, 1, 0, 0));
  model.ingest(a, 0.0);
  const MaterialId oak = model.building(1)->material;
  CHECK(model.materialName(oak) == "OAK");
  SnapshotData b = snap(2, ChangeScope::None, ChangeScope::Full, {"GRANITE", "OAK"});
  b.items.push_back(itm(9, ItemKind::Wood, 2, 2, 0, 1));
  model.ingest(b, 0.0);
  CHECK(model.item(9)->material == oak);
  CHECK(model.materialCount() == 2);
  CHECK(!model.hasTerrain());
}

TEST_CASE("entities: a map change clears both stores and invalidates the session") {
  WorldModel model;
  model.ingest(baseFull(), 0.0);
  model.drainBuildingEvents();
  model.drainItemEvents();
  SnapshotData other = snap(2, ChangeScope::None, ChangeScope::None);
  other.mapSize = TilePos{16, 16, 2};
  model.ingest(other, 0.0);
  CHECK(model.buildingCount() == 0);
  CHECK(model.itemCount() == 0);
  CHECK(!model.buildingsKnown());
  CHECK(model.sessionGeneration() == 1);
  CHECK(model.drainBuildingEvents().empty());
  CHECK(model.drainItemEvents().empty());
}

// ------------------------------------------------------------------ tier 1

TEST_CASE("entities: SyntheticFort Full then Deltas reach the store through the fixture path") {
  m::SyntheticFort fort(48, 48, 6);
  const uint16_t granite = fort.material("GRANITE");
  m::SyntheticFort::BuildingSpec bridge;
  bridge.kind = m::BuildingKind::Bridge;
  bridge.x1 = 30;
  bridge.y1 = 26;
  bridge.x2 = 32;
  bridge.y2 = 27;
  bridge.z = 5;
  bridge.material = granite;
  bridge.stage = m::BuildingStage::InProgress;
  fort.placeBuilding(5, bridge);
  m::SyntheticFort::ItemSpec log;
  log.kind = m::ItemKind::Wood;
  log.x = 5;
  log.y = 40;
  log.z = 5;
  fort.placeItem(100, log);
  fort.snapshot(10);
  fort.setBuildingStage(5, m::BuildingStage::Complete);
  fort.removeItem(100);
  fort.snapshot(11);

  WorldModel model;
  std::string err;
  REQUIRE_MESSAGE(loadFixtureBytes(model, fort.serialize(), err), err);
  CHECK(model.buildingsKnown());
  CHECK(model.itemsKnown());
  REQUIRE(model.building(5));
  CHECK(model.building(5)->stage == BuildingStage::Complete);
  CHECK(model.building(5)->version == 2);
  CHECK(model.building(5)->tick == 11);
  CHECK(model.materialName(model.building(5)->material) == "GRANITE");
  CHECK(model.item(100) == nullptr);
  CHECK(model.itemsVersion() == 2);
  auto bev = model.drainBuildingEvents();
  REQUIRE(bev.size() == 1);
  CHECK(bev[0].change == EntityChange::Added);  // added and changed before any drain
  CHECK(bev[0].version == 2);
  CHECK(model.drainItemEvents().empty());  // added and removed before any drain
}

TEST_CASE("demo fort fixture: buildings and items change over ticks") {
  // fixtures/synthetic/demo_fort.df3dfix (see tools/make_demo_fixture.cpp):
  // Full at 1000; the log 100 is hauled at 1003; the bridge 5 completes at
  // 1008; a planned chair 6 and a dug boulder 105 appear at 1009; the
  // dwarf corpse 106 rots at 1011 (v5); boulder 103 is kicked at 1012; the
  // chair is cancelled at 1013.
  WorldModel model;
  std::string err;
  REQUIRE_MESSAGE(loadFixtureFile(model, DF3D_FIXTURE_DIR "/synthetic/demo_fort.df3dfix", err),
                  err);
  CHECK(model.buildingsKnown());
  CHECK(model.itemsKnown());
  CHECK(model.buildingCount() == 6);  // + the shop
  CHECK(model.itemCount() == 9);  // + corpse, corpse piece, web (v5), dog meat
  CHECK(model.buildingsVersion() == 4);  // Full, bridge, chair in, chair out
  CHECK(model.itemsVersion() == 5);      // Full, log out, boulder in, corpse rots, boulder kicked

  const Building* shop = model.building(1);
  REQUIRE(shop);
  CHECK(shop->kind == BuildingKind::Workshop);
  CHECK(shop->subtype == 2);
  CHECK(shop->x1 == 24);
  CHECK(shop->y2 == 32);
  CHECK(shop->z == 5);
  CHECK(model.materialName(shop->material) == "GRANITE");
  CHECK((model.building(3)->flags & kBuildingForbidden) != 0);
  const Building* bridge = model.building(5);
  REQUIRE(bridge);
  CHECK(bridge->stage == BuildingStage::Complete);
  CHECK(bridge->version == 2);
  CHECK(bridge->tick == 1008);
  CHECK(model.building(6) == nullptr);
  const Building* pile = model.building(4);
  REQUIRE(pile);
  CHECK(pile->extents.size() == 20);
  CHECK(model.buildingAt(TilePos{16, 30, 5}) == nullptr);
  CHECK(model.buildingAt(TilePos{17, 30, 5}) == pile);
  CHECK(model.buildingsAt(5).size() == 6);

  CHECK(model.item(100) == nullptr);
  REQUIRE(model.item(101));
  REQUIRE(model.item(102));
  CHECK(model.item(102)->stack == 5);
  CHECK((model.item(102)->flags & kItemMelt) != 0);
  CHECK(model.materialName(model.item(102)->material) == "IRON");
  CHECK(model.itemsAtTile(TilePos{17, 31, 5}).size() == 1);
  REQUIRE(model.item(103));
  CHECK(model.item(103)->pos == TilePos{12, 26, 5});
  CHECK(model.item(103)->version == 2);
  CHECK(model.item(103)->tick == 1012);
  CHECK(model.item(104)->subtypeRaw == "ITEM_WEAPON_PICK");
  CHECK(model.item(104)->subtype == 12);
  REQUIRE(model.item(105));
  CHECK(model.item(105)->pos == TilePos{9, 21, 4});
  CHECK(model.item(105)->tick == 1009);
  CHECK(model.itemsAt(4).size() == 1);

  // Never drained: every surviving entity reads as Added; the chair and
  // the hauled log (added and removed) yield nothing.
  auto bev = model.drainBuildingEvents();
  CHECK(bev.size() == 6);
  for (const auto& e : bev) CHECK(e.change == EntityChange::Added);
  CHECK(findEvent(bev, 5)->version == 2);
  auto iev = model.drainItemEvents();
  CHECK(iev.size() == 9);
  CHECK(findEvent(iev, 100) == nullptr);

  // Stepwise replay sees the intermediate states.
  auto replay = FixtureReplay::open(DF3D_FIXTURE_DIR "/synthetic/demo_fort.df3dfix", err);
  REQUIRE_MESSAGE(replay, err);
  WorldModel step;
  replay->stepTo(step, 10.07);  // through tick 1007 (emitted_at_ms = tick * 10)
  CHECK(step.building(5)->stage == BuildingStage::InProgress);
  CHECK(step.item(100) == nullptr);
  CHECK(step.item(105) == nullptr);
  step.drainBuildingEvents();
  step.drainItemEvents();
  replay->stepTo(step, 10.09);  // 1008 and 1009
  auto sb = step.drainBuildingEvents();
  REQUIRE(sb.size() == 2);
  CHECK(findEvent(sb, 5)->change == EntityChange::Changed);
  CHECK(findEvent(sb, 5)->version == 2);
  CHECK(findEvent(sb, 6)->change == EntityChange::Added);
  CHECK(step.building(6)->stage == BuildingStage::Planned);
  auto si = step.drainItemEvents();
  REQUIRE(si.size() == 1);
  CHECK(si[0].id == 105);
  replay->stepAll(step);
  sb = step.drainBuildingEvents();
  REQUIRE(sb.size() == 1);
  CHECK(sb[0].id == 6);
  CHECK(sb[0].change == EntityChange::Removed);
  CHECK(sb[0].tick == 1013);
  si = step.drainItemEvents();
  REQUIRE(si.size() == 2);  // the corpse rots (1011), the boulder is kicked (1012)
  CHECK(findEvent(si, 103)->change == EntityChange::Changed);
  CHECK(findEvent(si, 103)->tick == 1012);
  CHECK(findEvent(si, 106)->change == EntityChange::Changed);
  CHECK(findEvent(si, 106)->tick == 1011);
}


TEST_CASE("corpse identity remains semantic and participates in item revisions") {
  WorldModel model;
  SnapshotData snapshot; snapshot.tick = 1; snapshot.mapSize = {16,16,2};
  snapshot.itemScope = ChangeScope::Full;
  ItemObservation item; item.id = 11; item.kind = ItemKind::Corpse;
  item.pos = {1,1,0}; item.corpseUnitId = 77;
  snapshot.items.push_back(item); model.ingest(snapshot, double(snapshot.tick));
  REQUIRE(model.item(11)); CHECK(model.item(11)->corpseUnitId == 77);
  const auto before = model.item(11)->version;
  snapshot.tick = 2; snapshot.items[0].corpseUnitId = 88; model.ingest(snapshot, double(snapshot.tick));
  CHECK(model.item(11)->corpseUnitId == 88); CHECK(model.item(11)->version > before);
  CHECK(ItemObservation{}.corpseUnitId == -1);
}
