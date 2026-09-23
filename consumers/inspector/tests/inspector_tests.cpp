// Tier 1 for the inspector: fixture → world model → report text.
#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest.h>

#include "inspect.h"
#include "synthetic_builder.h"
#include "wm/world_model.h"

namespace m = df3d::mirror;

TEST_CASE("report lists units with species, position, and motion") {
  m::SyntheticFort fort(48, 48, 10);
  fort.addUnit(7, "DWARF", 10, 10, 5, m::JobKind::Mine);
  fort.snapshot(100);
  fort.moveUnit(7, 11, 10, 5);
  fort.snapshot(101);

  wm::WorldModel model;
  std::string err;
  REQUIRE_MESSAGE(wm::loadFixtureBytes(model, fort.serialize(), err), err);

  const std::string text = inspector::report(model, 100.5);
  CHECK(text.find("map 48x48x10") != std::string::npos);
  CHECK(text.find("unit 7") != std::string::npos);
  CHECK(text.find("DWARF") != std::string::npos);
  CHECK(text.find("present") != std::string::npos);
  CHECK(text.find("(10.50, 10.00, 5.00)") != std::string::npos);
  CHECK(text.find("job=Mine") != std::string::npos);
  CHECK(text.find("motion=Continuous") != std::string::npos);
}

TEST_CASE("departed units are reported without a position") {
  m::SyntheticFort fort(16, 16, 4);
  fort.addUnit(1, "GOBLIN", 2, 2, 0);
  fort.snapshot(10);
  fort.removeUnit(1);
  fort.snapshot(11);

  wm::WorldModel model;
  std::string err;
  REQUIRE(wm::loadFixtureBytes(model, fort.serialize(), err));

  const std::string text = inspector::report(model, 11.0);
  CHECK(text.find("departed") != std::string::npos);
  CHECK(text.find("GOBLIN") != std::string::npos);
}

TEST_CASE("report is deterministic") {
  m::SyntheticFort fort(16, 16, 4);
  fort.addUnit(1, "DWARF", 2, 2, 0);
  fort.addUnit(2, "CAT", 3, 3, 0);
  fort.snapshot(10);
  fort.snapshot(11);

  wm::WorldModel a, b;
  std::string err;
  auto bytes = fort.serialize();
  REQUIRE(wm::loadFixtureBytes(a, bytes, err));
  REQUIRE(wm::loadFixtureBytes(b, bytes, err));
  CHECK(inspector::report(a, 10.5) == inspector::report(b, 10.5));
}

// --- terrain ---

namespace {
m::TileState tileOf(m::TileShape shape, m::MaterialKind kind, uint16_t mat,
                    m::TileFlags flags = m::TileFlags::NONE) {
  return m::TileState(shape, kind, mat, 0, m::LiquidKind::None, flags, df3d::mirror::DesignationKind::None);
}
}  // namespace

TEST_CASE("report says 'no terrain' for a units-only stream") {
  m::SyntheticFort fort(16, 16, 2);
  fort.addUnit(1, "DWARF", 1, 1, 0);
  fort.snapshot(10);
  wm::WorldModel model;
  std::string err;
  REQUIRE(wm::loadFixtureBytes(model, fort.serialize(), err));
  const std::string text = inspector::report(model, 10.0);
  CHECK(text.find("terrain: none") != std::string::npos);
  CHECK(text.find("(no terrain)") != std::string::npos);
}

TEST_CASE("terrain summary and z-level rendering with semantic glyphs") {
  m::SyntheticFort fort(20, 4, 3);
  const uint16_t granite = fort.material("GRANITE");
  const uint16_t loam = fort.material("CLAY_LOAM");
  fort.fillBox(m::TilePos(0, 0, 0), m::TilePos(19, 3, 0),
               tileOf(m::TileShape::Wall, m::MaterialKind::Stone, granite, m::TileFlags::Hidden));
  fort.fillBox(m::TilePos(0, 0, 1), m::TilePos(19, 3, 1),
               tileOf(m::TileShape::Floor, m::MaterialKind::Soil, loam));
  fort.setTile(0, 0, 1, tileOf(m::TileShape::Wall, m::MaterialKind::Stone, granite));
  fort.setTile(1, 0, 1, tileOf(m::TileShape::Wall, m::MaterialKind::Mineral, granite));
  fort.setTile(2, 0, 1, tileOf(m::TileShape::StairDown, m::MaterialKind::Soil, loam));
  fort.setTile(3, 0, 1, tileOf(m::TileShape::Wall, m::MaterialKind::Soil, loam, m::TileFlags::Hidden));
  fort.setTile(4, 0, 1, m::TileState(m::TileShape::Floor, m::MaterialKind::Soil, loam, 7,
                                     m::LiquidKind::Water, m::TileFlags::NONE, df3d::mirror::DesignationKind::None));
  fort.setTile(5, 0, 1, m::TileState(m::TileShape::Floor, m::MaterialKind::Stone, granite, 7,
                                     m::LiquidKind::Magma, m::TileFlags::NONE, df3d::mirror::DesignationKind::None));
  fort.setTile(6, 0, 1, tileOf(m::TileShape::Floor, m::MaterialKind::Soil, loam,
                               m::TileFlags::Smooth | m::TileFlags::Engraved));
  fort.setTile(7, 0, 1, tileOf(m::TileShape::TreeTrunk, m::MaterialKind::Wood, loam));
  fort.fillBox(m::TilePos(0, 0, 2), m::TilePos(19, 3, 2),
               tileOf(m::TileShape::Empty, m::MaterialKind::None, m::kNoMaterial));
  fort.addUnit(1, "DWARF", 10, 2, 1);
  fort.addUnit(2, "CAT", 11, 2, 1);
  fort.addUnit(3, "DWARF", 1, 1, 2);
  fort.snapshot(10);
  fort.snapshot(11);

  wm::WorldModel model;
  std::string err;
  REQUIRE(wm::loadFixtureBytes(model, fort.serialize(), err));

  const std::string summary = inspector::terrainSummary(model);
  CHECK(summary.find("terrain: 6/6 blocks known | version 1 | 2 materials") != std::string::npos);
  CHECK(summary.find("Wall=83") != std::string::npos);   // 80 hidden + 3 on z=1
  CHECK(summary.find("Floor=75") != std::string::npos);  // 80 - 8 replaced + 3 still floors
  CHECK(summary.find("hidden=81") != std::string::npos);
  CHECK(summary.find("water=1 magma=1") != std::string::npos);

  // Default z is the level with the most present units (z=1: two units).
  CHECK(inspector::defaultZ(model, 11.0) == 1);
  const std::string slab = inspector::renderZ(model, 1, 11.0);
  CHECK(slab.find("z=1 (20x4)\n") == 0);
  // Row 0: wall, vein, stair down, hidden, water, magma, engraved, trunk, floors.
  CHECK(slab.find("\n#%>?~&+T............\n") != std::string::npos);
  // Row 2 carries the two units.
  CHECK(slab.find("\n..........@@........\n") != std::string::npos);
  // z=0 is entirely hidden -> all unknown.
  const std::string hidden = inspector::renderZ(model, 0, 11.0);
  CHECK(hidden.find("\n????????????????????\n") != std::string::npos);
  CHECK(hidden.substr(0, hidden.find("legend")).find('#') == std::string::npos);
  // Open sky with one unit.
  const std::string sky = inspector::renderZ(model, 2, 11.0);
  CHECK(sky.find("\n @                  \n") != std::string::npos);

  // report() honours an explicit z and defaults otherwise.
  CHECK(inspector::report(model, 11.0).find("z=1 (20x4)") != std::string::npos);
  CHECK(inspector::report(model, 11.0, 2).find("z=2 (20x4)") != std::string::npos);
}

TEST_CASE("appearance summary: none yet, layered stack with page names, no graphics") {
  m::SyntheticFort fort(16, 16, 4);
  fort.addUnit(1, "DWARF", 2, 2, 0);
  fort.addUnit(2, "CAT", 3, 2, 0);
  fort.addUnit(3, "DOG", 4, 2, 0);
  m::SyntheticFort::Layer body;
  body.page = "DWARF_BODY";
  body.tileX = 3;
  body.tileY = 4;
  body.palette = "data/vanilla/x/graphics/images/dwarf/dwarf_body_palettes.png";
  body.paletteRow = 2;
  body.paletteKeyRow = 0;
  m::SyntheticFort::Layer hair = body;
  hair.page = "DWARF_HAIR";
  hair.palette = "data/vanilla/x/graphics/images/dwarf/dwarf_hair_palettes.png";
  m::SyntheticFort::Layer beard = hair;  // same page and palette as hair
  fort.setAppearance(1, {body, hair, beard});
  fort.setAppearance(3, {});
  fort.snapshot(10);

  wm::WorldModel model;
  std::string err;
  REQUIRE_MESSAGE(wm::loadFixtureBytes(model, fort.serialize(), err), err);

  CHECK(inspector::appearanceSummary(model, 2) == "appearance: none yet");
  const std::string s1 = inspector::appearanceSummary(model, 1);
  CHECK(s1.find("3 layers [DWARF_BODY, DWARF_HAIR] palettes 2") != std::string::npos);
  CHECK(s1.rfind("appearance v", 0) == 0);
  CHECK(inspector::appearanceSummary(model, 3).find("no graphics") != std::string::npos);

  const std::string text = inspector::report(model, 10.0);
  CHECK(text.find("3 layers [DWARF_BODY, DWARF_HAIR]") != std::string::npos);
  // Units without an appearance get no summary line.
  CHECK(text.find("none yet") == std::string::npos);
}

// --- buildings and map items ---

namespace {
m::SyntheticFort::BuildingSpec buildingSpec(m::BuildingKind kind, int32_t x1, int32_t y1, int32_t x2,
                                            int32_t y2, int32_t z, uint16_t material = m::kNoMaterial,
                                            m::BuildingStage stage = m::BuildingStage::Complete) {
  m::SyntheticFort::BuildingSpec b;
  b.kind = kind;
  b.x1 = x1;
  b.y1 = y1;
  b.x2 = x2;
  b.y2 = y2;
  b.z = z;
  b.material = material;
  b.stage = stage;
  return b;
}

m::SyntheticFort::ItemSpec itemSpec(m::ItemKind kind, int32_t x, int32_t y, int32_t z,
                                    uint16_t material = m::kNoMaterial, uint32_t stack = 1,
                                    m::ItemFlags flags = m::ItemFlags::NONE) {
  m::SyntheticFort::ItemSpec it;
  it.kind = kind;
  it.x = x;
  it.y = y;
  it.z = z;
  it.material = material;
  it.stack = stack;
  it.flags = flags;
  return it;
}
}  // namespace

TEST_CASE("building and item summaries: none before a Full, then counts by kind and stage") {
  m::SyntheticFort fort(20, 4, 2);
  fort.addUnit(1, "DWARF", 1, 1, 1);
  fort.snapshot(10);
  wm::WorldModel none;
  std::string err;
  REQUIRE(wm::loadFixtureBytes(none, fort.serialize(), err));
  CHECK(inspector::buildingSummary(none).find("buildings: none") != std::string::npos);
  CHECK(inspector::itemSummary(none).find("items: none") != std::string::npos);

  const uint16_t granite = fort.material("GRANITE");
  fort.placeBuilding(1, buildingSpec(m::BuildingKind::Workshop, 2, 0, 4, 2, 1, granite));
  fort.placeBuilding(2, buildingSpec(m::BuildingKind::Bed, 6, 0, 6, 0, 1));
  fort.placeBuilding(3, buildingSpec(m::BuildingKind::Bed, 7, 0, 7, 0, 1, m::kNoMaterial,
                                     m::BuildingStage::Planned));
  fort.placeItem(100, itemSpec(m::ItemKind::Wood, 10, 1, 1));
  fort.placeItem(101, itemSpec(m::ItemKind::Wood, 11, 1, 1));
  fort.placeItem(102, itemSpec(m::ItemKind::Bar, 12, 1, 1, granite, 5, m::ItemFlags::Melt));
  fort.snapshot(11);
  wm::WorldModel model;
  REQUIRE_MESSAGE(wm::loadFixtureBytes(model, fort.serialize(), err), err);
  const std::string b = inspector::buildingSummary(model);
  CHECK(b.find("buildings: 3 known | version 1") != std::string::npos);
  CHECK(b.find("kinds: Bed=2 Workshop=1") != std::string::npos);
  CHECK(b.find("stages: Planned=1 InProgress=0 Complete=2") != std::string::npos);
  const std::string i = inspector::itemSummary(model);
  CHECK(i.find("items: 3 on map | version 1") != std::string::npos);
  CHECK(i.find("kinds: Bar=1 Wood=2") != std::string::npos);
  const std::string text = inspector::report(model, 11.0);
  CHECK(text.find("buildings: 3 known") != std::string::npos);
  CHECK(text.find("items: 3 on map") != std::string::npos);
}

TEST_CASE("slab overlays buildings (extents), items and units with that precedence") {
  m::SyntheticFort fort(20, 4, 2);
  const uint16_t granite = fort.material("GRANITE");
  const uint16_t loam = fort.material("CLAY_LOAM");
  fort.fillBox(m::TilePos(0, 0, 1), m::TilePos(19, 3, 1),
               tileOf(m::TileShape::Floor, m::MaterialKind::Soil, loam));
  fort.placeBuilding(1, buildingSpec(m::BuildingKind::Workshop, 0, 0, 2, 2, 1, granite));
  m::SyntheticFort::BuildingSpec pile = buildingSpec(m::BuildingKind::Stockpile, 4, 0, 6, 1, 1);
  pile.extents = {1, 1, 0, 1, 1, 1};  // (6,0) left out
  fort.placeBuilding(2, pile);
  fort.placeBuilding(3, buildingSpec(m::BuildingKind::Bridge, 8, 0, 9, 0, 1, granite,
                                     m::BuildingStage::InProgress));
  fort.placeBuilding(4, buildingSpec(m::BuildingKind::Door, 12, 0, 12, 0, 0));  // other level
  fort.placeItem(100, itemSpec(m::ItemKind::Wood, 5, 1, 1));    // on the stockpile
  fort.placeItem(101, itemSpec(m::ItemKind::Boulder, 14, 0, 1));
  fort.placeItem(102, itemSpec(m::ItemKind::Weapon, 15, 0, 1));
  fort.placeItem(103, itemSpec(m::ItemKind::Bar, 16, 0, 1));
  fort.placeItem(104, itemSpec(m::ItemKind::Fish, 17, 0, 1));
  fort.placeItem(105, itemSpec(m::ItemKind::Corpse, 18, 0, 1));
  fort.placeItem(106, itemSpec(m::ItemKind::Barrel, 19, 0, 1));
  fort.addUnit(1, "DWARF", 1, 1, 1);  // on the workshop
  fort.addUnit(2, "CAT", 14, 0, 1);   // on the boulder
  fort.snapshot(10);
  wm::WorldModel model;
  std::string err;
  REQUIRE_MESSAGE(wm::loadFixtureBytes(model, fort.serialize(), err), err);

  const std::string slab = inspector::renderZ(model, 1, 10.0);
  // Row 0: workshop, floor, stockpile with its hole, floor, unbuilt bridge,
  // floors, the item parade (unit over the boulder).
  CHECK(slab.find("\nWWW.pp..xx....@)$ev;\n") != std::string::npos);
  // Row 1: unit over the workshop, stockpile with the log on it.
  CHECK(slab.find("\nW@W.plp.............\n") != std::string::npos);
  // z=0 is known open air (Full carries every block) with the door on it.
  CHECK(inspector::renderZ(model, 0, 10.0).find("\n            o       \n") !=
        std::string::npos);
  CHECK(std::string(inspector::glyphLegend()).find("x=unbuilt") != std::string::npos);
}

TEST_CASE("per-z listing names kind, subtype, rectangle, material, stage, flags") {
  m::SyntheticFort fort(20, 4, 2);
  const uint16_t granite = fort.material("GRANITE");
  m::SyntheticFort::BuildingSpec shop = buildingSpec(m::BuildingKind::Workshop, 2, 0, 4, 2, 1, granite);
  shop.subtype = 2;
  fort.placeBuilding(1, shop);
  m::SyntheticFort::BuildingSpec soap = buildingSpec(m::BuildingKind::Furnace, 6, 0, 8, 2, 1);
  soap.subtype = 7;
  soap.custom = "SOAP_MAKER";
  soap.flags = m::BuildingFlags::Forbidden;
  fort.placeBuilding(2, soap);
  fort.placeBuilding(3, buildingSpec(m::BuildingKind::Bed, 0, 0, 0, 0, 0));
  m::SyntheticFort::ItemSpec pick = itemSpec(m::ItemKind::Weapon, 10, 1, 1, granite, 1,
                                             m::ItemFlags::Forbidden | m::ItemFlags::Dump);
  pick.subtype = 12;
  pick.subtypeRaw = "ITEM_WEAPON_PICK";
  fort.placeItem(100, pick);
  fort.placeItem(101, itemSpec(m::ItemKind::Bar, 11, 1, 1, m::kNoMaterial, 5));
  fort.placeItem(102, itemSpec(m::ItemKind::Wood, 0, 0, 0));
  fort.snapshot(10);
  wm::WorldModel model;
  std::string err;
  REQUIRE_MESSAGE(wm::loadFixtureBytes(model, fort.serialize(), err), err);

  const std::string b = inspector::listBuildingsAt(model, 1);
  CHECK(b.find("building 1 Workshop/2     (2,0)-(4,2) center (3,1) material=GRANITE stage=Complete flags=- v1") != std::string::npos);
  CHECK(b.find("building 2 Furnace/7(SOAP_MAKER) (6,0)-(8,2)") != std::string::npos);
  CHECK(b.find("flags=Forbidden") != std::string::npos);
  CHECK(b.find("building 3") == std::string::npos);  // other level
  const std::string i = inspector::listItemsAt(model, 1);
  CHECK(i.find("item 100 Weapon(ITEM_WEAPON_PICK) x1 (10,1) material=GRANITE flags=Forbidden,Dump v1") != std::string::npos);
  CHECK(i.find("item 101 Bar            x5 (11,1) material=- flags=- v1") != std::string::npos);
  CHECK(i.find("item 102") == std::string::npos);

  inspector::ReportOptions opts;
  opts.listEntities = true;
  CHECK(inspector::report(model, 10.0, 1).find("building 1") == std::string::npos);
  const std::string text = inspector::report(model, 10.0, 1, opts);
  CHECK(text.find("building 1 Workshop/2") != std::string::npos);
  CHECK(text.find("item 100 Weapon") != std::string::npos);
}

// --- corpse appearances, webs and glyph tables ---

TEST_CASE("item summary counts webs and corpses with stacks; listing shows layers; glyph line") {
  m::SyntheticFort fort(20, 4, 2);
  fort.addUnit(1, "DWARF", 1, 1, 1);
  m::SyntheticFort::ItemSpec corpse = itemSpec(m::ItemKind::Corpse, 10, 1, 1);
  corpse.corpseFlags = m::CorpseFlags::Bone | m::CorpseFlags::Rottable | m::CorpseFlags::Leather;
  fort.placeItem(100, corpse);
  m::SyntheticFort::ItemSpec skull = itemSpec(m::ItemKind::CorpsePiece, 11, 1, 1);
  skull.corpseFlags = m::CorpseFlags::Bone | m::CorpseFlags::Skull;
  fort.placeItem(101, skull);
  fort.placeItem(102, itemSpec(m::ItemKind::Thread, 12, 1, 1, m::kNoMaterial, 1, m::ItemFlags::Web));
  m::SyntheticFort::Layer body;
  body.page = "DWARF_BODY_CORPSE";
  body.tileX = 1;
  body.tileY = 4;
  m::SyntheticFort::Layer hair = body;
  hair.page = "DWARF_HAIR_CORPSE";
  fort.setItemAppearance(100, {body, hair});
  wm::WorldModel none;
  std::string err;
  fort.snapshot(10);
  REQUIRE(wm::loadFixtureBytes(none, fort.serialize(), err));
  CHECK(inspector::glyphSummary(none).find("glyphs: no Full yet | species 0, materials 0, itemdefs 0") !=
        std::string::npos);

  m::SyntheticFort::CreatureGlyphSpec dwarf;
  dwarf.glyph = m::Glyph(1, 3, 0, 0);
  fort.creatureGlyph("DWARF", dwarf);
  m::SyntheticFort::MaterialGlyphSpec granite;
  fort.materialGlyph("GRANITE", granite);
  fort.itemDefGlyph(m::ItemKind::Tool, "ITEM_TOOL_CAULDRON", 147);
  fort.snapshot(11);
  wm::WorldModel model;
  REQUIRE_MESSAGE(wm::loadFixtureBytes(model, fort.serialize(), err), err);
  const std::string i = inspector::itemSummary(model);
  CHECK(i.find("items: 3 on map") != std::string::npos);
  CHECK(i.find("webs=1 corpses=2 with-appearance=1 (2 layers) | appearance version 1") !=
        std::string::npos);
  const std::string list = inspector::listItemsAt(model, 1);
  CHECK(list.find("item 100 Corpse") != std::string::npos);
  CHECK(list.find(" appearance v") != std::string::npos);
  CHECK(list.find(": 2 layers\n") != std::string::npos);
  CHECK(list.find("item 101 CorpsePiece") != std::string::npos);
  CHECK(list.find(": 0 layers\n") != std::string::npos);
  CHECK(list.find("corpse=Leather,Bone,Rottable appearance") != std::string::npos);
  CHECK(list.find("corpse=Bone,Skull (skeleton) appearance") != std::string::npos);
  CHECK(list.find("flags=Web") != std::string::npos);
  const std::string g = inspector::glyphSummary(model);
  CHECK(g.find("glyphs: known | species 1, materials 1, itemdefs 1 | version 1") != std::string::npos);
  const std::string text = inspector::report(model, 11.0);
  CHECK(text.find("glyphs: known") != std::string::npos);
  CHECK(text.find("webs=1") != std::string::npos);
}
