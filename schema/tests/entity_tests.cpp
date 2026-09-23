// Tier 0 for schema v4 buildings and map items: SyntheticFort
// emission (None / Full / Delta / removals), every validator rule (one test
// per rule; shapes the builder will not author are assembled raw), the
// stream rule.
#include <doctest.h>

#include <functional>
#include <optional>
#include <string>
#include <vector>

#include "entity_util.h"
#include "fixture_io.h"
#include "synthetic_builder.h"
#include "terrain_util.h"
#include "validate.h"

using namespace df3d::mirror;

TEST_CASE("native building footprints intersect map bounds without phantom edge tiles") {
  // Testfort, year 356: native building 5358 extends two rows past the map.
  auto b = clipBuildingFootprint({92, 78, 116, 145, 104, 111}, 153, 144, 144, 171);
  REQUIRE(b);
  CHECK(b->x1 == 92); CHECK(b->y1 == 78);
  CHECK(b->x2 == 116); CHECK(b->y2 == 143);
  CHECK(b->cx == 104); CHECK(b->cy == 111);
  CHECK(rectArea(b->x1, b->y1, b->x2, b->y2) == 25 * 66);
  b = clipBuildingFootprint({-4, -3, 2, 4, -1, -2}, 0, 16, 16, 1);
  REQUIRE(b);
  CHECK(b->x1 == 0); CHECK(b->y1 == 0);
  CHECK(b->x2 == 2); CHECK(b->y2 == 4);
  CHECK(b->cx == 0); CHECK(b->cy == 0);
  CHECK_FALSE(clipBuildingFootprint({144, 0, 150, 5, 145, 2}, 0, 144, 144, 1));
  CHECK_FALSE(clipBuildingFootprint({-10, 0, -1, 5, -5, 2}, 0, 144, 144, 1));
  CHECK_FALSE(clipBuildingFootprint({0, 0, 1, 1, 0, 0}, -1, 144, 144, 1));
  CHECK_FALSE(clipBuildingFootprint({0, 0, 1, 1, 0, 0}, 1, 144, 144, 1));
  b = clipBuildingFootprint({5, 7, 2, 3, 4, 6}, 0, 16, 16, 1);
  REQUIRE(b);
  CHECK(b->x1 == 2); CHECK(b->y1 == 3);
  CHECK(b->x2 == 5); CHECK(b->y2 == 7);
}

namespace {

FixtureStream mustParse(const SyntheticFort& fort) {
  FixtureStream fs;
  std::string err;
  REQUIRE_MESSAGE(parseFixture(fort.serialize(), fs, err), err);
  return fs;
}

std::optional<std::string> validateBytes(const std::vector<uint8_t>& bytes) {
  FixtureStream fs;
  std::string err;
  REQUIRE_MESSAGE(parseFixture(bytes, fs, err), err);
  return validateStream(fs);
}

SyntheticFort::BuildingSpec workshop(int32_t x1, int32_t y1, int32_t z, uint16_t mat = kNoMaterial) {
  SyntheticFort::BuildingSpec b;
  b.kind = BuildingKind::Workshop;
  b.subtype = 2;  // workshop_type::Masons
  b.x1 = x1;
  b.y1 = y1;
  b.x2 = x1 + 2;
  b.y2 = y1 + 2;
  b.z = z;
  b.material = mat;
  return b;
}

SyntheticFort::ItemSpec log(int32_t x, int32_t y, int32_t z, uint16_t mat = kNoMaterial) {
  SyntheticFort::ItemSpec it;
  it.kind = ItemKind::Wood;
  it.material = mat;
  it.x = x;
  it.y = y;
  it.z = z;
  return it;
}

// Raw single-snapshot fixtures for shapes SyntheticFort will not produce
// (duplicate ids, removed-and-present, a missing item position).
struct RawParts {
  ChangeScope buildingScope = ChangeScope::None;
  std::vector<flatbuffers::Offset<Building>> buildings;
  std::vector<uint32_t> removedBuildings;
  ChangeScope itemScope = ChangeScope::None;
  std::vector<flatbuffers::Offset<MapItem>> items;
  std::vector<uint32_t> removedItems;
};

template <class F>
std::vector<uint8_t> rawFixture(TilePos dims, F&& fill) {
  flatbuffers::FlatBufferBuilder fbb;
  RawParts p;
  fill(fbb, p);
  auto units = fbb.CreateVector(std::vector<flatbuffers::Offset<UnitState>>{});
  auto buildings = fbb.CreateVector(p.buildings);
  auto removedB = fbb.CreateVector(p.removedBuildings);
  auto items = fbb.CreateVector(p.items);
  auto removedI = fbb.CreateVector(p.removedItems);
  auto snap = CreateSnapshot(fbb, static_cast<uint32_t>(SchemaVersion::Current), 1, 10, &dims,
                             units, TerrainScope::None, 0, 0, AppearanceScope::None, 0, 0, 0,
                             p.buildingScope, buildings, removedB, p.itemScope, items, removedI);
  fbb.FinishSizePrefixed(snap, SnapshotIdentifier());
  return assembleFixture(
      {std::vector<uint8_t>(fbb.GetBufferPointer(), fbb.GetBufferPointer() + fbb.GetSize())});
}

flatbuffers::Offset<Building> rawBed(flatbuffers::FlatBufferBuilder& fbb, uint32_t id, int32_t x,
                                     int32_t y) {
  return CreateBuildingDirect(fbb, id, BuildingKind::Bed, kNoSubtype, nullptr, x, y, x, y, 0, x,
                              y);
}

flatbuffers::Offset<MapItem> rawItem(flatbuffers::FlatBufferBuilder& fbb, uint32_t id,
                                     const TilePos* pos) {
  return CreateMapItemDirect(fbb, id, ItemKind::Boulder, kNoSubtype, nullptr, kNoMaterial, pos);
}

const TilePos kDims(20, 20, 3);

}  // namespace

// ---------------------------------------------------------------- builder

TEST_CASE("entities: a fort that never places anything emits scope None and no vectors") {
  SyntheticFort fort(20, 20, 3);
  fort.addUnit(1, "DWARF", 1, 1, 0);
  fort.snapshot(1);
  auto fs = mustParse(fort);
  CHECK(!fort.buildingsEnabled());
  CHECK(!fort.itemsEnabled());
  const Snapshot* s = fs.snapshots[0];
  CHECK(s->building_scope() == ChangeScope::None);
  CHECK(s->buildings() == nullptr);
  CHECK(s->removed_buildings() == nullptr);
  CHECK(s->item_scope() == ChangeScope::None);
  CHECK(s->items() == nullptr);
  CHECK(s->removed_items() == nullptr);
  CHECK(s->materials() == nullptr);
  CHECK(!validateStream(fs));
}

TEST_CASE("entities: material() alone no longer turns terrain on; the table is still emitted") {
  SyntheticFort fort(20, 20, 3);
  const uint16_t granite = fort.material("GRANITE");
  fort.placeBuilding(7, workshop(2, 2, 0, granite));
  fort.snapshot(1);
  auto fs = mustParse(fort);
  REQUIRE(!validateStream(fs));
  CHECK(!fort.terrainEnabled());
  const Snapshot* s = fs.snapshots[0];
  CHECK(s->terrain_scope() == TerrainScope::None);
  CHECK(s->blocks() == nullptr);
  REQUIRE(s->materials());
  CHECK(s->materials()->size() == 1);
  CHECK(s->buildings()->Get(0)->material() == granite);
}

TEST_CASE("buildings: first snapshot is Full, later ones Delta with changes and removals") {
  SyntheticFort fort(20, 20, 3);
  const uint16_t granite = fort.material("GRANITE");
  fort.placeBuilding(1, workshop(2, 2, 0, granite));
  SyntheticFort::BuildingSpec bed;
  bed.kind = BuildingKind::Bed;
  bed.x1 = bed.x2 = 10;
  bed.y1 = bed.y2 = 10;
  bed.z = 1;
  bed.stage = BuildingStage::Planned;
  bed.flags = BuildingFlags::RoomAssigned;
  fort.placeBuilding(2, bed);
  fort.snapshot(1);  // Full: both
  fort.placeBuilding(1, workshop(2, 2, 0, granite));  // identical: no-op
  fort.snapshot(2);  // Delta: nothing
  fort.setBuildingStage(2, BuildingStage::Complete);
  fort.snapshot(3);  // Delta: bed
  fort.removeBuilding(1);
  fort.snapshot(4);  // Delta: removed 1
  fort.placeBuilding(3, workshop(5, 5, 2));
  fort.removeBuilding(3);  // placed and removed within one tick
  fort.snapshot(5);
  fort.removeBuilding(2);
  fort.placeBuilding(2, bed);  // removed and re-added within one tick: a change, not a removal
  fort.snapshot(6);
  fort.requestFullBuildings();
  fort.snapshot(7);
  CHECK_THROWS_AS(fort.removeBuilding(99), std::out_of_range);
  CHECK_THROWS_AS(fort.building(99), std::out_of_range);

  auto fs = mustParse(fort);
  REQUIRE_MESSAGE(!validateStream(fs), *validateStream(fs));
  REQUIRE(fs.snapshots.size() == 7);
  const Snapshot* s0 = fs.snapshots[0];
  CHECK(s0->building_scope() == ChangeScope::Full);
  REQUIRE(s0->buildings()->size() == 2);
  const Building* w = s0->buildings()->Get(0);
  CHECK(w->id() == 1);
  CHECK(w->kind() == BuildingKind::Workshop);
  CHECK(w->subtype() == 2);
  CHECK(w->custom() == nullptr);
  CHECK(w->x1() == 2);
  CHECK(w->x2() == 4);
  CHECK(w->center_x() == 3);  // resolved from the rectangle
  CHECK(w->center_y() == 3);
  CHECK(w->extents() == nullptr);
  CHECK(w->material() == granite);
  CHECK(w->stage() == BuildingStage::Complete);
  const Building* b = s0->buildings()->Get(1);
  CHECK(b->kind() == BuildingKind::Bed);
  CHECK(b->stage() == BuildingStage::Planned);
  CHECK(b->flags() == BuildingFlags::RoomAssigned);
  CHECK(b->material() == kNoMaterial);
  CHECK(s0->removed_buildings()->size() == 0);
  CHECK(fort.building(2).centerX == 10);

  CHECK(fs.snapshots[1]->building_scope() == ChangeScope::Delta);
  CHECK(fs.snapshots[1]->buildings()->size() == 0);
  CHECK(fs.snapshots[1]->removed_buildings()->size() == 0);
  REQUIRE(fs.snapshots[2]->buildings()->size() == 1);
  CHECK(fs.snapshots[2]->buildings()->Get(0)->id() == 2);
  CHECK(fs.snapshots[2]->buildings()->Get(0)->stage() == BuildingStage::Complete);
  CHECK(fs.snapshots[3]->buildings()->size() == 0);
  REQUIRE(fs.snapshots[3]->removed_buildings()->size() == 1);
  CHECK(fs.snapshots[3]->removed_buildings()->Get(0) == 1);
  // Placed-and-removed within one tick: only the removal is visible.
  CHECK(fs.snapshots[4]->buildings()->size() == 0);
  REQUIRE(fs.snapshots[4]->removed_buildings()->size() == 1);
  CHECK(fs.snapshots[4]->removed_buildings()->Get(0) == 3);
  // Removed-and-re-added: present, not removed.
  REQUIRE(fs.snapshots[5]->buildings()->size() == 1);
  CHECK(fs.snapshots[5]->buildings()->Get(0)->id() == 2);
  CHECK(fs.snapshots[5]->removed_buildings()->size() == 0);
  CHECK(fs.snapshots[6]->building_scope() == ChangeScope::Full);
  CHECK(fs.snapshots[6]->buildings()->size() == 1);
}

TEST_CASE("buildings: extents and custom raw id round-trip") {
  SyntheticFort fort(20, 20, 3);
  SyntheticFort::BuildingSpec pile;
  pile.kind = BuildingKind::Stockpile;
  pile.x1 = 1;
  pile.y1 = 1;
  pile.x2 = 3;
  pile.y2 = 2;
  pile.extents = {1, 1, 0, 0, 1, 1};
  fort.placeBuilding(1, pile);
  SyntheticFort::BuildingSpec soap = workshop(6, 6, 0);
  soap.subtype = 23;  // workshop_type::Custom
  soap.custom = "SOAP_MAKER";
  fort.placeBuilding(2, soap);
  fort.snapshot(1);
  auto fs = mustParse(fort);
  REQUIRE(!validateStream(fs));
  const Building* p = fs.snapshots[0]->buildings()->Get(0);
  REQUIRE(p->extents());
  CHECK(p->extents()->size() == 6);
  CHECK(p->extents()->Get(2) == 0);
  const Building* s = fs.snapshots[0]->buildings()->Get(1);
  REQUIRE(s->custom());
  CHECK(std::string(s->custom()->c_str()) == "SOAP_MAKER");
}

TEST_CASE("items: Full then Deltas with moves, flag changes and removals") {
  SyntheticFort fort(20, 20, 3);
  const uint16_t oak = fort.material("OAK");
  const uint16_t iron = fort.material("IRON");
  fort.placeItem(100, log(3, 3, 0, oak));
  SyntheticFort::ItemSpec bars;
  bars.kind = ItemKind::Bar;
  bars.material = iron;
  bars.x = 4;
  bars.y = 3;
  bars.z = 0;
  bars.stack = 5;
  bars.flags = ItemFlags::Melt;
  fort.placeItem(101, bars);
  SyntheticFort::ItemSpec pick;
  pick.kind = ItemKind::Weapon;
  pick.subtype = 12;
  pick.subtypeRaw = "ITEM_WEAPON_PICK";
  pick.material = iron;
  pick.x = 5;
  pick.y = 3;
  pick.z = 0;
  fort.placeItem(102, pick);
  fort.snapshot(1);  // Full
  fort.moveItem(100, 3, 4, 0);
  fort.snapshot(2);  // Delta: 100
  fort.setItemFlags(101, ItemFlags::Melt | ItemFlags::Forbidden);
  fort.removeItem(102);
  fort.snapshot(3);  // Delta: 101, removed 102
  fort.placeItem(100, fort.item(100));  // identical
  fort.snapshot(4);  // Delta: nothing
  fort.requestFullItems();
  fort.snapshot(5);
  CHECK_THROWS_AS(fort.removeItem(102), std::out_of_range);
  CHECK_THROWS_AS(fort.item(102), std::out_of_range);

  auto fs = mustParse(fort);
  REQUIRE_MESSAGE(!validateStream(fs), *validateStream(fs));
  const Snapshot* s0 = fs.snapshots[0];
  CHECK(s0->item_scope() == ChangeScope::Full);
  REQUIRE(s0->items()->size() == 3);
  const MapItem* l = s0->items()->Get(0);
  CHECK(l->id() == 100);
  CHECK(l->kind() == ItemKind::Wood);
  CHECK(l->material() == oak);
  CHECK(l->pos()->x() == 3);
  CHECK(l->stack() == 1);
  CHECK(l->subtype() == kNoSubtype);
  CHECK(l->subtype_raw() == nullptr);
  const MapItem* b = s0->items()->Get(1);
  CHECK(b->stack() == 5);
  CHECK(b->flags() == ItemFlags::Melt);
  const MapItem* w = s0->items()->Get(2);
  CHECK(w->subtype() == 12);
  CHECK(std::string(w->subtype_raw()->c_str()) == "ITEM_WEAPON_PICK");
  CHECK(fs.snapshots[1]->item_scope() == ChangeScope::Delta);
  REQUIRE(fs.snapshots[1]->items()->size() == 1);
  CHECK(fs.snapshots[1]->items()->Get(0)->pos()->y() == 4);
  REQUIRE(fs.snapshots[2]->items()->size() == 1);
  CHECK(fs.snapshots[2]->items()->Get(0)->id() == 101);
  CHECK(fs.snapshots[2]->items()->Get(0)->flags() == (ItemFlags::Melt | ItemFlags::Forbidden));
  REQUIRE(fs.snapshots[2]->removed_items()->size() == 1);
  CHECK(fs.snapshots[2]->removed_items()->Get(0) == 102);
  CHECK(fs.snapshots[3]->items()->size() == 0);
  CHECK(fs.snapshots[4]->item_scope() == ChangeScope::Full);
  CHECK(fs.snapshots[4]->items()->size() == 2);
}

// ------------------------------------------------------------- validators

namespace {
// One building placed with `mutate` applied, in a 20x20x3 map.
std::optional<std::string> validateBuildingSpec(const SyntheticFort::BuildingSpec& spec) {
  SyntheticFort fort(20, 20, 3);
  fort.material("GRANITE");
  fort.placeBuilding(1, spec);
  fort.snapshot(1);
  return validateStream(mustParse(fort));
}

std::optional<std::string> validateItemSpec(const SyntheticFort::ItemSpec& spec) {
  SyntheticFort fort(20, 20, 3);
  fort.material("GRANITE");
  fort.placeItem(1, spec);
  fort.snapshot(1);
  return validateStream(mustParse(fort));
}
}  // namespace

TEST_CASE("validator: accepts a well-formed building and item stream") {
  SyntheticFort fort(20, 20, 3);
  const uint16_t granite = fort.material("GRANITE");
  fort.placeBuilding(1, workshop(0, 0, 0, granite));
  SyntheticFort::BuildingSpec edge = workshop(17, 17, 2, granite);  // touches the far corner
  fort.placeBuilding(2, edge);
  fort.placeItem(1, log(19, 19, 2, granite));
  fort.snapshot(1);
  fort.removeBuilding(2);
  fort.removeItem(1);
  fort.snapshot(2);
  CHECK(!validateStream(mustParse(fort)));
}

namespace {
struct RejectCase {
  const char* name;
  std::function<std::optional<std::string>()> validate;
  const char* expected;  // must appear in the error
};
struct AcceptCase {
  const char* name;
  std::function<std::optional<std::string>()> validate;
};
using BuildingMutation = void (*)(SyntheticFort::BuildingSpec&);
using ItemMutation = void (*)(SyntheticFort::ItemSpec&);
std::optional<std::string> building(BuildingMutation mutate, int x = 5, int y = 5, uint16_t material = kNoMaterial) {
  SyntheticFort::BuildingSpec b = workshop(x, y, 0, material);
  mutate(b);
  return validateBuildingSpec(b);
}
std::optional<std::string> item(ItemMutation mutate, uint16_t material = kNoMaterial) {
  SyntheticFort::ItemSpec it = log(0, 0, 0, material);
  mutate(it);
  return validateItemSpec(it);
}
// One fort with one placed building / item whose next scope is forged.
std::optional<std::string> forgedBuildingScope(ChangeScope scope) {
  SyntheticFort fort(20, 20, 3);
  fort.placeBuilding(1, workshop(0, 0, 0));
  fort.forgeNextBuildingScope(scope);
  fort.snapshot(1);
  return validateStream(mustParse(fort));
}
std::optional<std::string> forgedItemScope(ChangeScope scope, bool removeFirst = false) {
  SyntheticFort fort(20, 20, 3);
  fort.placeItem(1, log(0, 0, 0));
  if (removeFirst) {
    fort.snapshot(1);
    fort.removeItem(1);
  }
  fort.forgeNextItemScope(scope);
  fort.snapshot(removeFirst ? 2 : 1);
  return validateStream(mustParse(fort));
}
}  // namespace

TEST_CASE("validator rejects malformed buildings and items (one row per rule)") {
  const std::vector<RejectCase> rejections = {
      {"invalid building_scope value", [] { return forgedBuildingScope(static_cast<ChangeScope>(9)); },
       "invalid building_scope value 9"},
      {"invalid item_scope value", [] { return forgedItemScope(static_cast<ChangeScope>(9)); },
       "invalid item_scope value 9"},
      {"entries under building_scope None", [] { return forgedBuildingScope(ChangeScope::None); },
       "building_scope None but 1 entries and 0 removed ids"},
      {"removed ids under item_scope None", [] { return forgedItemScope(ChangeScope::None, true); },
       "item_scope None but 0 entries and 1 removed ids"},
      {"inverted rectangle (x2 < x1)", [] { return building([](SyntheticFort::BuildingSpec& b) { b.x2 = 4; }); }, "is inverted"},
      {"inverted rectangle (y2 < y1)", [] { return building([](SyntheticFort::BuildingSpec& b) { b.y2 = 4; }); }, "is inverted"},
      {"rectangle x1 < 0", [] { return building([](SyntheticFort::BuildingSpec& b) { b.x1 = -1; b.centerX = 0; }, 0, 0); }, "outside map"},
      {"rectangle x2 past the map", [] { return building([](SyntheticFort::BuildingSpec& b) { b.x2 = 20; }, 0, 0); }, "outside map"},
      {"rectangle y1 < 0", [] { return building([](SyntheticFort::BuildingSpec& b) { b.y1 = -1; b.centerY = 0; }, 0, 0); }, "outside map"},
      {"rectangle y2 past the map", [] { return building([](SyntheticFort::BuildingSpec& b) { b.y2 = 20; }, 0, 0); }, "outside map"},
      {"z past the map", [] { return building([](SyntheticFort::BuildingSpec& b) { b.z = 3; }, 0, 0); }, "outside map"},
      {"z < 0", [] { return building([](SyntheticFort::BuildingSpec& b) { b.z = -1; }, 0, 0); }, "outside map"},
      {"centre outside its rectangle",
       [] { return building([](SyntheticFort::BuildingSpec& b) { b.centerX = 8; b.centerY = 6; }); },
       "center (8,6) outside the rectangle"},
      {"extents of the wrong length (3x3 = 9 tiles)",
       [] { return building([](SyntheticFort::BuildingSpec& b) { b.extents = std::vector<uint8_t>(8, 1); }); },
       "extents has 8 bytes, rectangle area is 9"},
      {"extents with a value other than 0/1",
       [] { return building([](SyntheticFort::BuildingSpec& b) { b.extents = std::vector<uint8_t>(9, 1); b.extents[4] = 2; }); },
       "extents[4] = 2"},
      {"invalid building kind", [] { return building([](SyntheticFort::BuildingSpec& b) { b.kind = static_cast<BuildingKind>(200); }); },
       "invalid kind value 200"},
      {"invalid building stage", [] { return building([](SyntheticFort::BuildingSpec& b) { b.stage = static_cast<BuildingStage>(3); }); },
       "invalid stage value 3"},
      {"unknown building flag bits", [] { return building([](SyntheticFort::BuildingSpec& b) { b.flags = static_cast<BuildingFlags>(0x80); }); },
       "unknown flag bits in 128"},
      {"building material index out of range (only GRANITE exists)",
       [] { return validateBuildingSpec(workshop(5, 5, 0, 1)); },
       "material index 1 out of range (materials.size() = 1)"},
      {"duplicate building ids",
       [] {
         return validateBytes(rawFixture(kDims, [](flatbuffers::FlatBufferBuilder& fbb, RawParts& p) {
           p.buildingScope = ChangeScope::Full;
           p.buildings = {rawBed(fbb, 5, 1, 1), rawBed(fbb, 5, 2, 2)};
         }));
       },
       "building 5: duplicate id"},
      {"removed building id that is also present",
       [] {
         return validateBytes(rawFixture(kDims, [](flatbuffers::FlatBufferBuilder& fbb, RawParts& p) {
           p.buildingScope = ChangeScope::Full;
           p.buildings = {rawBed(fbb, 5, 1, 1)};
           p.removedBuildings = {5};
         }));
       },
       "removed building 5 is also present"},
      {"removed building id listed twice",
       [] {
         return validateBytes(rawFixture(kDims, [](flatbuffers::FlatBufferBuilder&, RawParts& p) {
           p.buildingScope = ChangeScope::Full;
           p.removedBuildings = {6, 6};
         }));
       },
       "removed building 6 listed twice"},
      {"building Delta before any Full", [] { return forgedBuildingScope(ChangeScope::Delta); },
       "building_scope Delta before any Full"},
      {"item x < 0", [] { return item([](SyntheticFort::ItemSpec& i) { i.x = -1; }); }, "outside map"},
      {"item x past the map", [] { return item([](SyntheticFort::ItemSpec& i) { i.x = 20; }); }, "outside map"},
      {"item y past the map", [] { return item([](SyntheticFort::ItemSpec& i) { i.y = 20; }); }, "outside map"},
      {"item z past the map", [] { return item([](SyntheticFort::ItemSpec& i) { i.z = 3; }); }, "outside map"},
      {"item without a position",
       [] {
         return validateBytes(rawFixture(kDims, [](flatbuffers::FlatBufferBuilder& fbb, RawParts& p) {
           p.itemScope = ChangeScope::Full;
           p.items = {rawItem(fbb, 1, nullptr)};
         }));
       },
       "item 1: missing pos"},
      {"zero item stack", [] { return item([](SyntheticFort::ItemSpec& i) { i.stack = 0; }); }, "stack 0 below 1"},
      {"invalid item kind", [] { return item([](SyntheticFort::ItemSpec& i) { i.kind = static_cast<ItemKind>(250); }); },
       "invalid kind value 250"},
      {"unknown item flag bits", [] { return item([](SyntheticFort::ItemSpec& i) { i.flags = static_cast<ItemFlags>(0x80); }); },
       "unknown flag bits in 128"},
      {"item material index out of range", [] { return validateItemSpec(log(0, 0, 0, 3)); },
       "material index 3 out of range (materials.size() = 1)"},
      {"duplicate item ids",
       [] {
         return validateBytes(rawFixture(kDims, [](flatbuffers::FlatBufferBuilder& fbb, RawParts& p) {
           TilePos pos(1, 1, 0);
           p.itemScope = ChangeScope::Full;
           p.items = {rawItem(fbb, 9, &pos), rawItem(fbb, 9, &pos)};
         }));
       },
       "item 9: duplicate id"},
      {"removed item that is also present",
       [] {
         return validateBytes(rawFixture(kDims, [](flatbuffers::FlatBufferBuilder& fbb, RawParts& p) {
           TilePos pos(1, 1, 0);
           p.itemScope = ChangeScope::Full;
           p.items = {rawItem(fbb, 9, &pos)};
           p.removedItems = {9};
         }));
       },
       "removed item 9 is also present"},
      {"item Delta before any Full", [] { return forgedItemScope(ChangeScope::Delta); },
       "item_scope Delta before any Full"},
  };
  for (const auto& c : rejections) {
    INFO(c.name);
    auto err = c.validate();
    REQUIRE(err);
    CHECK_MESSAGE(err->find(c.expected) != std::string::npos, *err);
  }

  std::vector<AcceptCase> acceptance = {
      {"extents of the right length with 0/1 values",
       [] { return building([](SyntheticFort::BuildingSpec& b) { b.extents = std::vector<uint8_t>(9, 1); b.extents[4] = 0; }); }},
      {"building material index 0", [] { return validateBuildingSpec(workshop(5, 5, 0, 0)); }},
      {"building without a material", [] { return validateBuildingSpec(workshop(5, 5, 0, kNoMaterial)); }},
      {"Web item flag", [] { return item([](SyntheticFort::ItemSpec& i) { i.flags = ItemFlags::Web; }); }},
  };
  // Every named kind is accepted.
  for (uint8_t k = 0; k <= static_cast<uint8_t>(BuildingKind::MAX); ++k)
    acceptance.push_back({"named building kind", [k] {
                            SyntheticFort::BuildingSpec b = workshop(5, 5, 0);
                            b.kind = static_cast<BuildingKind>(k);
                            return validateBuildingSpec(b);
                          }});
  for (uint8_t k = 0; k <= static_cast<uint8_t>(ItemKind::MAX); ++k)
    acceptance.push_back({"named item kind", [k] {
                            SyntheticFort::ItemSpec it = log(0, 0, 0);
                            it.kind = static_cast<ItemKind>(k);
                            return validateItemSpec(it);
                          }});
  for (const auto& c : acceptance) {
    INFO(c.name);
    auto err = c.validate();
    CHECK_MESSAGE(!err, err.value_or(""));
  }
}

TEST_CASE("EntityStreamState tracks Full per table") {
  SyntheticFort ok(20, 20, 3);
  ok.placeBuilding(1, workshop(0, 0, 0));
  ok.snapshot(1);  // buildings Full, items None
  ok.placeItem(1, log(0, 0, 0));
  ok.snapshot(2);  // buildings Delta, items Full
  ok.snapshot(3);  // both Delta
  auto fs = mustParse(ok);
  EntityStreamState st;
  CHECK(!st.check(*fs.snapshots[0]));
  CHECK(st.seenFullBuildings());
  CHECK(!st.seenFullItems());
  CHECK(!st.check(*fs.snapshots[1]));
  CHECK(st.seenFullItems());
  CHECK(!st.check(*fs.snapshots[2]));
  EntityStreamState fresh;
  CHECK(fresh.check(*fs.snapshots[2]));  // both Deltas without a Full
}
