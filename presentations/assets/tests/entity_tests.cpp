// Tier 0: building and item graphics on synthetic raw snippets:
// the layout / item-family / per-material parsers, the cache round trip
// of the new records, and the building / item resolvers' rules. No
// images, no install.
#include <doctest.h>

#include <string>
#include <vector>

#include "df3d_assets/asset_index.h"
#include "df3d_assets/raw_tokens.h"
#include "df3d_assets/resolver.h"
#include "df3d_assets/steam_install.h"

using namespace df3d::assets;

namespace {

std::string dataDir() { return std::string(DF3D_ASSETS_TEST_DIR) + "/data"; }

std::string readData(const char* name) {
  std::string text, err;
  REQUIRE_MESSAGE(readTextFile(dataDir() + "/" + name, text, err), err);
  return text;
}

// The terrain / creature synthetic index plus the building and item
// snippets (their tile pages arrive last, so every page is a late one).
AssetIndex entityIndex(std::vector<std::string>* diag = nullptr) {
  AssetIndex idx;
  const std::string g = "/synth/mod/graphics";
  ingestRawText(idx, readData("tile_page_test.txt"), g, "tile_page_test", diag);
  ingestRawText(idx, readData("descriptor_color_test.txt"), g, "colors", diag);
  ingestRawText(idx, readData("material_template_test.txt"), g, "templates", diag);
  ingestRawText(idx, readData("palette_test.txt"), g, "palette", diag);
  ingestRawText(idx, readData("graphics_tiles_test.txt"), g, "tiles", diag);
  ingestRawText(idx, readData("graphics_plants_test.txt"), g, "plants_gfx", diag);
  ingestRawText(idx, readData("graphics_creatures_test.txt"), g, "creatures_gfx", diag);
  ingestRawText(idx, readData("graphics_buildings_test.txt"), g, "buildings_gfx", diag);
  ingestRawText(idx, readData("graphics_items_test.txt"), g, "items_gfx", diag);
  ingestRawText(idx, readData("tile_page_late_test.txt"), g, "tile_page_late", diag);
  ingestRawText(idx, readData("tile_page_entities_test.txt"), g, "tile_page_entities", diag);
  ingestRawText(idx, readData("graphics_bodyparts_test.txt"), g, "bodyparts_gfx", diag);
  ingestRawText(idx, readData("tile_page_bodyparts_test.txt"), g, "tile_page_bodyparts", diag);
  ingestRawText(idx, readData("inorganic_test.txt"), g, "inorganic", diag);
  ingestRawText(idx, readData("plant_test.txt"), g, "plant", diag);
  finalizeIndex(idx);
  return idx;
}

SpriteRef at(const AssetIndex& idx, const char* page, int x, int y) {
  SpriteRef s;
  s.page = idx.pageIndex(page);
  s.x = x;
  s.y = y;
  return s;
}

BuildingQuery bq(wm::BuildingKind kind, int w, int h, std::string_view material,
                 wm::BuildingStage stage = wm::BuildingStage::Complete,
                 uint16_t subtype = wm::kNoSubtype, std::string_view custom = {}) {
  BuildingQuery q;
  q.kind = kind;
  q.width = w;
  q.height = h;
  q.material = material;
  q.stage = stage;
  q.subtype = subtype;
  q.custom = custom;
  return q;
}

ItemQuery iq(wm::ItemKind kind, std::string_view material, std::string_view raw = {},
             uint8_t flags = 0, uint32_t stack = 1) {
  ItemQuery q;
  q.kind = kind;
  q.material = material;
  q.subtypeRaw = raw;
  q.flags = flags;
  q.stack = stack;
  return q;
}

const BuildingTile* tileAt(const BuildingSprites& r, int lx, int ly, size_t nth = 0) {
  for (const BuildingTile& t : r.tiles) {
    if (t.lx != lx || t.ly != ly) continue;
    if (nth == 0) return &t;
    --nth;
  }
  return nullptr;
}

}  // namespace

// --- parsing ---

TEST_CASE("layouts: stage:lx:ly, custom codes, stage-less, 1x1 shops") {
  std::vector<std::string> diag;
  const AssetIndex idx = entityIndex(&diag);
  // (The shared palette snippet's second PALETTE block is diagnosed by
  // design; nothing from the building / item snippets may be.)
  std::string joined;
  for (const std::string& d : diag)
    if (d.find("_gfx") != std::string::npos || d.find("entities") != std::string::npos)
      joined += d + "; ";
  CHECK_MESSAGE(joined.empty(), joined);

  const BuildingLayout* mason = idx.layout("WORKSHOP_MASON");
  REQUIRE(mason);
  CHECK(mason->width == 3);
  CHECK(mason->height == 4);
  REQUIRE(mason->stages.size() == 2);
  CHECK(mason->stages.count(3) == 1);
  CHECK(mason->stages.count(1) == 1);
  // Tiles listed out of order land on their (lx, ly).
  REQUIRE(mason->tile(3, 1, 1));
  CHECK(*mason->tile(3, 1, 1) == at(idx, "WORKSHOPS", 1, 5));
  CHECK(*mason->tile(3, 0, 0) == at(idx, "WORKSHOPS", 0, 4));
  CHECK(*mason->tile(1, 2, 3) == at(idx, "WORKSHOPS", 8, 7));
  // Stage fallback: the highest stage below, else the lowest present.
  CHECK(mason->stageFor(3) == 3);
  CHECK(mason->stageFor(2) == 1);
  CHECK(mason->stageFor(1) == 1);
  CHECK(mason->stageFor(0) == 1);
  CHECK(mason->stageFor(9) == 3);
  CHECK(*mason->tile(2, 0, 0) == at(idx, "WORKSHOPS", 6, 4));
  CHECK(mason->tile(3, 3, 0) == nullptr);
  // The plain name still lists every entry as variants (unchanged).
  CHECK(idx.tileGraphics.at("WORKSHOP_MASON").size() == 24);
  // Overlays are separate layouts.
  CHECK(idx.layout("WORKSHOP_MASON_OVERLAY"));

  const BuildingLayout* custom = idx.layout("WORKSHOP_CUSTOM:SOAP_MAKER");
  REQUIRE(custom);
  CHECK(custom->width == 2);
  CHECK(custom->height == 2);
  CHECK(*custom->tile(3, 1, 1) == at(idx, "WORKSHOPS", 1, 61));
  REQUIRE(idx.layout("WORKSHOP_CUSTOM"));
  CHECK(*idx.layout("WORKSHOP_CUSTOM")->tile(3, 0, 0) == at(idx, "WORKSHOPS", 0, 56));

  // The 1x1 shops' `NAME:stage:row` reads as a (bogus, column-0-empty)
  // lx:ly layout; the resolver falls back to the variant column.
  REQUIRE(idx.layout("WORKSHOP_QUERN"));
  CHECK(idx.layout("WORKSHOP_QUERN")->tile(1, 0, 0) == nullptr);
  CHECK(idx.tileGraphics.at("WORKSHOP_QUERN").size() == 2);
  const BuildingLayout* press = idx.layout("WORKSHOP_CUSTOM:SCREW_PRESS");
  REQUIRE(press);
  CHECK(press->width == 1);
  CHECK(press->height == 2);
  CHECK(press->stages.begin()->first == 1);
  // A single trailing integer is a variant, not a layout.
  CHECK(idx.layout("WORKSHOP_MILLSTONE_TURNING") == nullptr);
  CHECK(idx.tileGraphics.at("WORKSHOP_MILLSTONE_TURNING").size() == 2);

  const BuildingLayout* windmill = idx.layout("WINDMILL_S_1");
  REQUIRE(windmill);
  CHECK(windmill->width == 3);
  CHECK(windmill->height == 4);
  REQUIRE(windmill->stages.count(kLayoutNoStage) == 1);
  CHECK(*windmill->tile(kLayoutNoStage, 2, 3) == at(idx, "WINDMILL", 2, 3));
  CHECK(*windmill->tile(3, 2, 3) == at(idx, "WINDMILL", 2, 3));  // any stage maps to it

  // The documented ambiguity: NAME:variant:frame also lands as a layout.
  CHECK(idx.layout("ITEM_DOOR_VARIANT_DAMAGED"));
  CHECK(idx.stats.buildingLayouts >= 8);
  CHECK(idx.stats.layoutTiles > 60);
}

TEST_CASE("item families: blocks, variants, inline sprites, per-material items") {
  const AssetIndex idx = entityIndex();
  const ItemDefGraphics* pick = idx.itemDef("ITEM_WEAPON_PICK");
  REQUIRE(pick);
  CHECK(pick->base == at(idx, "WEAPONS", 0, 7));
  CHECK(pick->variants.at("DEFAULT") == at(idx, "WEAPONS", 0, 7));
  CHECK(pick->variants.at("WOOD") == at(idx, "WEAPONS", 2, 7));
  CHECK(pick->variants.at("ARTIFACT") == at(idx, "WEAPONS", 3, 7));
  CHECK(pick->variants.at("WEAPON_TRAP") == at(idx, "TRAPS_WEAPON", 1, 3));
  CHECK(idx.itemDef("WEAPON_WHIP_DEFAULT") == nullptr);  // procedural, not an itemdef

  const ItemDefGraphics* nest = idx.itemDef("ITEM_TOOL_NEST_BOX");
  REQUIRE(nest);
  CHECK(nest->base == at(idx, "TOOLS", 0, 10));
  CHECK(nest->variants.at("STONE") == at(idx, "TOOLS", 1, 10));  // the ALL condition is skipped
  CHECK(nest->variants.at("GLASS") == at(idx, "TOOLS", 3, 10));
  CHECK(idx.itemDef("ITEM_TOOL_HIVE")->variants.at("HIVE_BLD") == at(idx, "TOOLS", 0, 11));
  CHECK(idx.itemDef("ITEM_TOOL_MINECART")->variants.at("WOOD") == at(idx, "TOOLS", 0, 14));

  const ItemDefGraphics* boat = idx.itemDef("ITEM_TOY_BOAT");
  REQUIRE(boat);
  CHECK(boat->base == at(idx, "ITEM_TOY", 0, 1));
  CHECK(boat->variants.at("WOOD") == at(idx, "ITEM_TOY", 0, 1));
  CHECK(boat->variants.at("STONE") == at(idx, "ITEM_TOY", 1, 1));

  const ItemDefGraphics* bolts = idx.itemDef("ITEM_AMMO_BOLTS");
  REQUIRE(bolts);
  CHECK(bolts->base == at(idx, "ITEM_AMMO", 0, 1));
  CHECK(bolts->variants.at("STRAIGHT_WOOD") == at(idx, "ITEM_AMMO", 0, 0));

  CHECK(idx.itemDef("ITEM_ARMOR_BREASTPLATE")->base == at(idx, "ITEM_EQUIPMENT", 4, 6));
  const ItemDefGraphics* boots = idx.itemDef("ITEM_SHOES_BOOTS");
  REQUIRE(boots);
  CHECK(boots->base == at(idx, "ITEM_EQUIPMENT", 4, 17));
  CHECK(boots->variants.at("METAL") == at(idx, "ITEM_EQUIPMENT", 4, 19));
  CHECK(idx.itemDef("ITEM_FOOD_ROAST")->base == at(idx, "ITEM_FOOD", 2, 0));

  CHECK(idx.boulderGraphics.at("INORGANIC:HEMATITE") == at(idx, "BOULDERS", 0, 13));
  CHECK(idx.barsGraphics.at("POTASH") == at(idx, "ITEM_CONSTRUCTION", 0, 3));
  CHECK(idx.barsGraphics.at("COAL:COKE") == at(idx, "ITEM_CONSTRUCTION", 0, 4));
  CHECK(idx.roughGemGraphics.at("GLASS_GREEN") == at(idx, "BOULDERS", 0, 8));
  CHECK(idx.stats.materialItems == 5);
  CHECK(idx.stats.itemDefs == 11);

  const PlantGraphics& plump = idx.plants.at("MUSHROOM_HELMET_PLUMP");
  CHECK(plump.picked == at(idx, "PLANT_STANDARD", 1, 0));
  CHECK(plump.seed == at(idx, "PLANT_STANDARD", 2, 0));
  CHECK(idx.plants.at("BLUEBERRY").growthPicked == at(idx, "PLANT_GARDEN", 3, 53));
}

TEST_CASE("cache round trip keeps layouts, item defs, material items, plant item forms") {
  AssetIndex idx = entityIndex();
  idx.buildId = "24557528";
  idx.contentHash = 42;
  const std::string text = serializeIndex(idx);
  AssetIndex back;
  std::string err;
  REQUIRE_MESSAGE(deserializeIndex(text, back, err), err);
  REQUIRE(back.layout("WORKSHOP_MASON"));
  CHECK(back.layout("WORKSHOP_MASON")->stages == idx.layout("WORKSHOP_MASON")->stages);
  CHECK(back.layout("WINDMILL_S_1")->stages == idx.layout("WINDMILL_S_1")->stages);
  CHECK(back.buildingLayouts.size() == idx.buildingLayouts.size());
  REQUIRE(back.itemDef("ITEM_WEAPON_PICK"));
  CHECK(back.itemDef("ITEM_WEAPON_PICK")->variants == idx.itemDef("ITEM_WEAPON_PICK")->variants);
  CHECK(back.itemDefs.size() == idx.itemDefs.size());
  CHECK(back.boulderGraphics == idx.boulderGraphics);
  CHECK(back.barsGraphics == idx.barsGraphics);
  CHECK(back.roughGemGraphics == idx.roughGemGraphics);
  CHECK(back.plants.at("MUSHROOM_HELMET_PLUMP").picked == idx.plants.at("MUSHROOM_HELMET_PLUMP").picked);
  CHECK(back.plants.at("BLUEBERRY").growthPicked == idx.plants.at("BLUEBERRY").growthPicked);
  CHECK(back.stats.layoutTiles == idx.stats.layoutTiles);
  CHECK(back.stats.itemVariants == idx.stats.itemVariants);
  CHECK(serializeIndex(back).size() == text.size());
  CHECK_FALSE(deserializeIndex("DF3DAIX 3 x 0\nltile\t3\t0\t0\t1\t2\t3\t1\t1\n", back, err));
  CHECK_FALSE(deserializeIndex("DF3DAIX 3 x 0\nlayout\tX\t99\t1\n", back, err));
}

// --- building resolution ---

TEST_CASE("buildings: workshop layouts map the building grid under the overhang row") {
  const AssetIndex idx = entityIndex();
  BuildingSprites r = resolveBuildingTiles(idx, bq(wm::BuildingKind::Workshop, 3, 3,
                                                   "INORGANIC:GRANITE",
                                                   wm::BuildingStage::Complete, 2));
  REQUIRE(r.found);
  CHECK(r.rule == std::string("layout"));
  CHECK(r.tiles.size() == 13); // twelve base cells plus sparse native foreground
  CHECK_FALSE(r.decal);
  CHECK_FALSE(r.stageArt);
  // Building (0,0) is layout (0,1): row 0 sticks up above the shop.
  REQUIRE(tileAt(r, 0, 0));
  CHECK(tileAt(r, 0, 0)->sprite == at(idx, "WORKSHOPS", 0, 5));
  CHECK(tileAt(r, 2, 2)->sprite == at(idx, "WORKSHOPS", 2, 7));
  REQUIRE(tileAt(r, 0, -1));
  CHECK(tileAt(r, 0, -1)->sprite == at(idx, "WORKSHOPS", 0, 4));
  CHECK(r.tiles.back().foreground);
  CHECK(r.tiles.back().lx == 0);
  CHECK(r.tiles.back().ly == -1); // sparse overlay uses BASE layout anchor
  CHECK(r.tiles.back().sprite == at(idx, "WORKSHOPS", 12, 4));
  CHECK(r.colorName == "CLEAR");
  CHECK(r.paletteRow == 25);

  // In progress: the stage below the complete one, flagged as stage art.
  r = resolveBuildingTiles(idx, bq(wm::BuildingKind::Workshop, 3, 3, "INORGANIC:GRANITE",
                                   wm::BuildingStage::InProgress, 2));
  REQUIRE(r.found);
  CHECK(r.stageArt);
  CHECK(tileAt(r, 0, 0)->sprite == at(idx, "WORKSHOPS", 6, 5));
  // Planned: the complete art (the presentation ghosts it).
  r = resolveBuildingTiles(idx, bq(wm::BuildingKind::Workshop, 3, 3, "INORGANIC:GRANITE",
                                   wm::BuildingStage::Planned, 2));
  REQUIRE(r.found);
  CHECK_FALSE(r.stageArt);
  CHECK(tileAt(r, 1, 1)->sprite == at(idx, "WORKSHOPS", 1, 6));

  // Extents restrict the tiles.
  const std::vector<uint8_t> ext = {1, 0, 0, 0, 1, 0, 0, 0, 1};
  BuildingQuery q = bq(wm::BuildingKind::Workshop, 3, 3, "INORGANIC:GRANITE",
                       wm::BuildingStage::Complete, 2);
  q.extents = &ext;
  r = resolveBuildingTiles(idx, q);
  CHECK(r.tiles.size() == 5); // three occupied cells, one north spill + foreground
  CHECK(tileAt(r, 1, -1) == nullptr); // absent owner cannot create north art

  // Custom code, generic fallback, 1x1 shop, unknown subtype.
  r = resolveBuildingTiles(idx, bq(wm::BuildingKind::Workshop, 2, 2, "INORGANIC:GRANITE",
                                   wm::BuildingStage::Complete, 23, "SOAP_MAKER"));
  REQUIRE(r.found);
  CHECK(tileAt(r, 1, 1)->sprite == at(idx, "WORKSHOPS", 1, 61));
  r = resolveBuildingTiles(idx, bq(wm::BuildingKind::Workshop, 2, 2, "INORGANIC:GRANITE",
                                   wm::BuildingStage::Complete, 23, "MODDED_SHOP"));
  REQUIRE(r.found);
  CHECK(r.rule == std::string("layout.custom-generic"));
  CHECK(tileAt(r, 0, 0)->sprite == at(idx, "WORKSHOPS", 0, 56));
  // 1x1 shops: the variant column's bottom entry (the top sticks up).
  r = resolveBuildingTiles(idx, bq(wm::BuildingKind::Workshop, 1, 1, "INORGANIC:GRANITE",
                                   wm::BuildingStage::Complete, 17));
  REQUIRE(r.found);
  CHECK(r.tiles.size() == 2);
  CHECK(tileAt(r, 0, 0)->sprite == at(idx, "WORKSHOPS_1x1", 3, 1));
  CHECK(tileAt(r, 0, -1)->sprite == at(idx, "WORKSHOPS_1x1", 3, 0));
  r = resolveBuildingTiles(idx, bq(wm::BuildingKind::Workshop, 1, 1, "INORGANIC:GRANITE",
                                   wm::BuildingStage::Complete, 23, "SCREW_PRESS"));
  REQUIRE(r.found);
  CHECK(tileAt(r, 0, 0)->sprite == at(idx, "WORKSHOPS_1x1", 0, 1));
  CHECK(tileAt(r, 0, -1)->sprite == at(idx, "WORKSHOPS_1x1", 0, 0));
  r = resolveBuildingTiles(idx, bq(wm::BuildingKind::ScrewPump, 1, 2, "PLANT:OAK:WOOD"));
  REQUIRE(r.found);
  CHECK(r.tiles.size() == 2);
  CHECK(r.tiles[0].sprite == at(idx, "SCREWPUMP", 0, 2));
  CHECK(r.tiles[1].sprite == at(idx, "SCREWPUMP", 0, 3));
  // A workshop type without art of its own takes the generic custom art.
  r = resolveBuildingTiles(idx, bq(wm::BuildingKind::Workshop, 3, 3, "INORGANIC:GRANITE",
                                   wm::BuildingStage::Complete, 0));  // carpenter: not in the data
  REQUIRE(r.found);
  CHECK(r.rule == std::string("layout.custom-generic"));
  r = resolveBuildingTiles(idx, bq(wm::BuildingKind::TradeDepot, 5, 5, "INORGANIC:GRANITE"));
  CHECK_FALSE(r.found);
  CHECK(r.rule == std::string("no-layout"));
  CHECK(buildingLayoutName(wm::BuildingKind::Furnace, 1, "") == "FURNACE_SMELTER");
  CHECK(buildingLayoutName(wm::BuildingKind::Furnace, 7, "MAGMA_KILN_X") ==
        "WORKSHOP_CUSTOM:MAGMA_KILN_X");
  CHECK(buildingLayoutName(wm::BuildingKind::TradeDepot, wm::kNoSubtype, "") == "TRADE_DEPOT");

  // Stage-less layouts: a windmill (3x4 art on a 3x3 building), a siege
  // engine with its construction art.
  r = resolveBuildingTiles(idx, bq(wm::BuildingKind::Windmill, 3, 3, "PLANT:OAK:WOOD"));
  REQUIRE(r.found);
  CHECK(r.tiles.size() == 12);
  CHECK(tileAt(r, 0, 0)->sprite == at(idx, "WINDMILL", 0, 1));
  r = resolveBuildingTiles(idx, bq(wm::BuildingKind::SiegeEngine, 3, 3, "PLANT:OAK:WOOD",
                                   wm::BuildingStage::Complete, 0));
  REQUIRE(r.found);
  CHECK(tileAt(r, 1, 1)->sprite == at(idx, "SIEGE_WEAPONS", 1, 7));
  CHECK_FALSE(r.stageArt);
  r = resolveBuildingTiles(idx, bq(wm::BuildingKind::SiegeEngine, 3, 3, "PLANT:OAK:WOOD",
                                   wm::BuildingStage::InProgress, 0));
  REQUIRE(r.found);
  CHECK(r.stageArt);
  CHECK(tileAt(r, 1, 1)->sprite == at(idx, "SIEGE_WEAPONS", 4, 13));
}

TEST_CASE("buildings: furniture takes the item page member for the material class") {
  const AssetIndex idx = entityIndex();
  CHECK(materialClassOf(idx, "PLANT:OAK:WOOD") == MaterialClass::Wood);
  CHECK(materialClassOf(idx, "INORGANIC:GRANITE") == MaterialClass::Stone);
  CHECK(materialClassOf(idx, "INORGANIC:IRON") == MaterialClass::Metal);
  CHECK(materialClassOf(idx, "INORGANIC:UNLISTED") == MaterialClass::Stone);
  CHECK(materialClassOf(idx, "CREATURE:COW:BONE") == MaterialClass::Unknown);
  CHECK(materialClassOf(idx, "") == MaterialClass::Unknown);

  BuildingSprites r = resolveBuildingTiles(idx, bq(wm::BuildingKind::Bed, 1, 1, "PLANT:OAK:WOOD"));
  REQUIRE(r.found);
  CHECK(r.tiles.size() == 1);
  CHECK(r.tiles[0].sprite == at(idx, "ITEM_BED", 0, 0));  // ITEM_BED_WOOD:1
  CHECK(r.rule == std::string("furniture.bed"));

  r = resolveBuildingTiles(idx, bq(wm::BuildingKind::Chair, 1, 1, "INORGANIC:GRANITE"));
  REQUIRE(r.found);
  CHECK(r.tiles[0].sprite == at(idx, "ITEM_CHAIR", 0, 1));  // ITEM_CHAIR_STONE:1
  CHECK(r.paletteRow == 25);
  // No metal chair member in the data: the wood one stands in.
  r = resolveBuildingTiles(idx, bq(wm::BuildingKind::Chair, 1, 1, "INORGANIC:IRON"));
  REQUIRE(r.found);
  CHECK(r.tiles[0].sprite == at(idx, "ITEM_CHAIR", 0, 0));
  CHECK(r.paletteRow == 50);
  // A bone chair (unknown class) falls back the same way.
  r = resolveBuildingTiles(idx, bq(wm::BuildingKind::Chair, 1, 1, "CREATURE:COW:BONE"));
  REQUIRE(r.found);
  CHECK(r.tiles[0].sprite == at(idx, "ITEM_CHAIR", 0, 0));
  CHECK(r.paletteRow == -1);

  // Doors: the closed member, plus the forbidden overlay.
  r = resolveBuildingTiles(idx, bq(wm::BuildingKind::Door, 1, 1, "INORGANIC:GRANITE"));
  REQUIRE(r.found);
  CHECK(r.tiles.size() == 1);
  CHECK(r.tiles[0].sprite == at(idx, "ITEM_DOOR", 1, 1));
  BuildingQuery q = bq(wm::BuildingKind::Door, 1, 1, "PLANT:OAK:WOOD");
  q.flags = wm::kBuildingForbidden;
  r = resolveBuildingTiles(idx, q);
  REQUIRE(r.tiles.size() == 2);
  CHECK(r.tiles[0].sprite == at(idx, "ITEM_DOOR", 1, 0));
  CHECK(r.tiles[1].sprite == at(idx, "ITEM_DOOR", 14, 0));

  r = resolveBuildingTiles(idx, bq(wm::BuildingKind::Statue, 1, 1, "INORGANIC:GRANITE"));
  REQUIRE(r.found);
  CHECK(r.tiles[0].sprite == at(idx, "STATUES", 0, 0));
  r = resolveBuildingTiles(idx, bq(wm::BuildingKind::Support, 1, 1, "INORGANIC:IRON"));
  REQUIRE(r.found);
  CHECK(r.tiles[0].sprite == at(idx, "SUPPORT", 2, 0));
  r = resolveBuildingTiles(idx, bq(wm::BuildingKind::Well, 1, 1, "INORGANIC:GRANITE"));
  CHECK(r.found);
  r = resolveBuildingTiles(idx, bq(wm::BuildingKind::Trap, 1, 1, "INORGANIC:IRON",
                                   wm::BuildingStage::Complete, 2));
  REQUIRE(r.found);
  CHECK(r.tiles[0].sprite == at(idx, "TRAPS", 9, 1));
  r = resolveBuildingTiles(idx, bq(wm::BuildingKind::Trap, 1, 1, "INORGANIC:IRON",
                                   wm::BuildingStage::Complete, 0));  // lever: not in the data
  CHECK_FALSE(r.found);
  CHECK(r.rule == std::string("missing-tile"));
  // Kinds the raws have no art for.
  r = resolveBuildingTiles(idx, bq(wm::BuildingKind::Shop, 3, 3, "INORGANIC:GRANITE"));
  CHECK_FALSE(r.found);
  CHECK(r.rule == std::string("no-art"));
  r = resolveBuildingTiles(idx, bq(wm::BuildingKind::Cabinet, 1, 1, "PLANT:OAK:WOOD"));
  CHECK_FALSE(r.found);  // no ITEM_CABINET in the data
}

TEST_CASE("buildings: stockpiles, zones and bridges are edge-dressed decals") {
  const AssetIndex idx = entityIndex();
  BuildingSprites r = resolveBuildingTiles(idx, bq(wm::BuildingKind::Stockpile, 2, 2, ""));
  REQUIRE(r.found);
  CHECK(r.decal);
  CHECK(r.tiles.size() == 18);  // floor, lower edges, six north-spilling upper halves
  REQUIRE(tileAt(r, 0, 0, 0));
  CHECK(tileAt(r, 0, 0, 0)->sprite == at(idx, "STOCKPILE", 0, 1));  // floor first
  CHECK(tileAt(r, 0, 0, 1)->sprite == at(idx, "STOCKPILE", 0, 3));  // N
  CHECK(tileAt(r, 0, 0, 2)->sprite == at(idx, "STOCKPILE", 0, 6));  // W
  CHECK(tileAt(r, 1, 1, 1)->sprite == at(idx, "STOCKPILE", 0, 4));  // S
  CHECK(tileAt(r, 1, 1, 2)->sprite == at(idx, "STOCKPILE", 0, 8));  // E
  REQUIRE(tileAt(r,0,-1,0));
  CHECK(tileAt(r,0,-1,0)->sprite==at(idx,"STOCKPILE",0,2)); // N_UP outside footprint
  CHECK(tileAt(r,0,-1,1)->sprite==at(idx,"STOCKPILE",0,5)); // W_UP
  CHECK(tileAt(r,1,-1,1)->sprite==at(idx,"STOCKPILE",0,7)); // E_UP
  CHECK(tileAt(r,0,0,3)->sprite==at(idx,"STOCKPILE",0,5)); // next row's W_UP overlays floor
  // An L-shaped pile: the missing tile's neighbours gain borders.
  const std::vector<uint8_t> ext = {1, 1, 1, 0};
  BuildingQuery q = bq(wm::BuildingKind::Stockpile, 2, 2, "");
  q.extents = &ext;
  r = resolveBuildingTiles(idx, q);
  // (0,0) keeps two borders, (1,0) and (0,1) gain a third from the gap.
  CHECK(r.tiles.size() == 17); // eleven lower/floor tiles and six upper halves
  CHECK(tileAt(r, 1, 0, 2)->sprite == at(idx, "STOCKPILE", 0, 4));  // S border of (1,0)
  CHECK_FALSE(tileAt(r,1,1)); // semantic hole does not gain floor or lower edges
  CHECK(tileAt(r,0,0,4)->sprite==at(idx,"STOCKPILE",0,7)); // E_UP from exposed hole edge

  r = resolveBuildingTiles(idx, bq(wm::BuildingKind::Civzone, 1, 1, ""));
  REQUIRE(r.found);
  CHECK(r.decal);
  CHECK(r.tiles[0].sprite == at(idx, "ACTIVITY_ZONES", 2, 0));  // N_S_W_E
  r = resolveBuildingTiles(idx, bq(wm::BuildingKind::Civzone, 3, 1, ""));
  CHECK(tileAt(r, 1, 0)->sprite == at(idx, "ACTIVITY_ZONES", 2, 9));  // N_S
  CHECK(tileAt(r, 0, 0)->sprite == at(idx, "ACTIVITY_ZONES", 2, 13));  // N_S_W
  r = resolveBuildingTiles(idx, bq(wm::BuildingKind::Civzone, 3, 3, ""));
  CHECK(tileAt(r, 1, 1)->sprite == at(idx, "ACTIVITY_ZONES", 2, 15));  // interior
  CHECK(tileAt(r, 0, 0)->sprite == at(idx, "ACTIVITY_ZONES", 2, 1));   // N_W
  CHECK(tileAt(r, 2, 0)->sprite == at(idx, "ACTIVITY_ZONES", 2, 15));  // N_E missing -> plain

  r = resolveBuildingTiles(idx, bq(wm::BuildingKind::Bridge, 1, 1, "INORGANIC:GRANITE"));
  REQUIRE(r.found);
  CHECK_FALSE(r.decal);
  CHECK(r.tiles[0].sprite == at(idx, "BRIDGES", 1, 60));  // 1x1
  r = resolveBuildingTiles(idx, bq(wm::BuildingKind::Bridge, 3, 3, "INORGANIC:GRANITE"));
  CHECK(tileAt(r, 0, 0)->sprite == at(idx, "BRIDGES", 1, 73));  // NW
  CHECK(tileAt(r, 1, 0)->sprite == at(idx, "BRIDGES", 1, 66));  // N
  CHECK(tileAt(r, 1, 1)->sprite == at(idx, "BRIDGES", 1, 61));  // CENTER
  CHECK(tileAt(r, 0, 1)->sprite == at(idx, "BRIDGES", 1, 61));  // W missing -> CENTER
  r = resolveBuildingTiles(idx, bq(wm::BuildingKind::Bridge, 1, 1, "PLANT:OAK:WOOD"));
  CHECK(r.tiles[0].sprite == at(idx, "BRIDGES", 0, 60));
  r = resolveBuildingTiles(idx, bq(wm::BuildingKind::Bridge, 1, 1, "INORGANIC:IRON"));
  CHECK_FALSE(r.found);  // no metal bridge members in the data
}

// --- item resolution ---

TEST_CASE("items: kind, itemdef raw, material and flags pick the sprite") {
  const AssetIndex idx = entityIndex();
  ItemSprite r = resolveItem(idx, iq(wm::ItemKind::Boulder, "INORGANIC:HEMATITE"));
  REQUIRE(r.found);
  CHECK(r.sprite == at(idx, "BOULDERS", 0, 13));
  CHECK(r.rule == std::string("boulder.material"));
  r = resolveItem(idx, iq(wm::ItemKind::Boulder, "INORGANIC:GRANITE"));
  REQUIRE(r.found);
  CHECK(r.sprite == at(idx, "BOULDERS", 0, 1));
  CHECK(r.paletteRow == 25);
  CHECK(r.colorName == "CLEAR");

  CHECK(resolveItem(idx, iq(wm::ItemKind::Bar, "INORGANIC:POTASH")).sprite ==
        at(idx, "ITEM_CONSTRUCTION", 0, 3));
  CHECK(resolveItem(idx, iq(wm::ItemKind::Bar, "INORGANIC:IRON")).sprite ==
        at(idx, "ITEM_CONSTRUCTION", 0, 1));
  CHECK(resolveItem(idx, iq(wm::ItemKind::Bar, "CREATURE:COW:SOAP")).sprite ==
        at(idx, "ITEM_CONSTRUCTION", 1, 1));
  CHECK(resolveItem(idx, iq(wm::ItemKind::Rough, "INORGANIC:GLASS_GREEN")).sprite ==
        at(idx, "BOULDERS", 0, 8));
  CHECK(resolveItem(idx, iq(wm::ItemKind::SmallGem, "INORGANIC:RUBY")).rule ==
        std::string("gem.cut->rough"));

  // Weapons: default / wood / artifact variants of the itemdef.
  r = resolveItem(idx, iq(wm::ItemKind::Weapon, "INORGANIC:IRON", "ITEM_WEAPON_PICK"));
  REQUIRE(r.found);
  CHECK(r.sprite == at(idx, "WEAPONS", 0, 7));
  CHECK(r.paletteRow == 50);
  CHECK(resolveItem(idx, iq(wm::ItemKind::Weapon, "PLANT:OAK:WOOD", "ITEM_WEAPON_PICK")).sprite ==
        at(idx, "WEAPONS", 2, 7));
  CHECK(resolveItem(idx, iq(wm::ItemKind::Weapon, "INORGANIC:IRON", "ITEM_WEAPON_PICK",
                            wm::kItemArtifact))
            .sprite == at(idx, "WEAPONS", 3, 7));
  r = resolveItem(idx, iq(wm::ItemKind::Weapon, "INORGANIC:IRON", "ITEM_WEAPON_MODDED"));
  REQUIRE(r.found);
  CHECK(r.rule == std::string("itemdef-fallback"));
  CHECK(r.sprite == at(idx, "TOOLS", 0, 0));

  // Tools and toys by material class; ammo by wood; boots by metal.
  CHECK(resolveItem(idx, iq(wm::ItemKind::Tool, "INORGANIC:GRANITE", "ITEM_TOOL_NEST_BOX")).sprite ==
        at(idx, "TOOLS", 1, 10));
  CHECK(resolveItem(idx, iq(wm::ItemKind::Tool, "CREATURE:COW:BONE", "ITEM_TOOL_NEST_BOX")).sprite ==
        at(idx, "TOOLS", 0, 10));
  CHECK(resolveItem(idx, iq(wm::ItemKind::Toy, "INORGANIC:GRANITE", "ITEM_TOY_BOAT")).sprite ==
        at(idx, "ITEM_TOY", 1, 1));
  CHECK(resolveItem(idx, iq(wm::ItemKind::Ammo, "PLANT:OAK:WOOD", "ITEM_AMMO_BOLTS")).sprite ==
        at(idx, "ITEM_AMMO", 0, 0));
  CHECK(resolveItem(idx, iq(wm::ItemKind::Ammo, "INORGANIC:IRON", "ITEM_AMMO_BOLTS")).sprite ==
        at(idx, "ITEM_AMMO", 0, 1));
  CHECK(resolveItem(idx, iq(wm::ItemKind::Shoes, "INORGANIC:IRON", "ITEM_SHOES_BOOTS")).sprite ==
        at(idx, "ITEM_EQUIPMENT", 4, 19));
  CHECK(resolveItem(idx, iq(wm::ItemKind::Shoes, "PLANT:OAK:LEAF", "ITEM_SHOES_BOOTS")).sprite ==
        at(idx, "ITEM_EQUIPMENT", 4, 17));
  CHECK(resolveItem(idx, iq(wm::ItemKind::Armor, "INORGANIC:IRON", "ITEM_ARMOR_BREASTPLATE")).sprite ==
        at(idx, "ITEM_EQUIPMENT", 4, 6));
  CHECK(resolveItem(idx, iq(wm::ItemKind::Food, "", "ITEM_FOOD_ROAST")).sprite ==
        at(idx, "ITEM_FOOD", 2, 0));
  CHECK(resolveItem(idx, iq(wm::ItemKind::Food, "", "ITEM_FOOD_UNKNOWN")).sprite ==
        at(idx, "ITEM_FOOD", 1, 0));

  // Furniture items: the abstract member per class.
  CHECK(resolveItem(idx, iq(wm::ItemKind::Door, "INORGANIC:GRANITE")).sprite ==
        at(idx, "ITEM_DOOR", 1, 1));
  CHECK(resolveItem(idx, iq(wm::ItemKind::Statue, "INORGANIC:GRANITE")).sprite ==
        at(idx, "STATUES", 0, 0));
  CHECK(resolveItem(idx, iq(wm::ItemKind::Chair, "PLANT:OAK:WOOD")).sprite ==
        at(idx, "ITEM_CHAIR", 0, 0));

  // Coins by stack, containers, cloth.
  CHECK(resolveItem(idx, iq(wm::ItemKind::Coin, "INORGANIC:IRON", "", 0, 1)).sprite ==
        at(idx, "ITEM_COINS", 0, 0));
  CHECK(resolveItem(idx, iq(wm::ItemKind::Coin, "INORGANIC:IRON", "", 0, 5)).sprite ==
        at(idx, "ITEM_COINS", 1, 0));
  CHECK(resolveItem(idx, iq(wm::ItemKind::Coin, "INORGANIC:IRON", "", 0, 500)).sprite ==
        at(idx, "ITEM_COINS", 4, 0));
  CHECK(resolveItem(idx, iq(wm::ItemKind::Bin, "PLANT:OAK:WOOD")).sprite ==
        at(idx, "CONTAINERS", 0, 4));
  CHECK(resolveItem(idx, iq(wm::ItemKind::Bin, "INORGANIC:IRON")).sprite ==
        at(idx, "CONTAINERS", 3, 4));
  CHECK(resolveItem(idx, iq(wm::ItemKind::Thread, "CREATURE:SPIDER_CAVE:SILK")).sprite ==
        at(idx, "ITEM_CLOTH", 0, 0));
  CHECK(resolveItem(idx, iq(wm::ItemKind::Bag, "CREATURE:SPIDER_CAVE:SILK")).sprite ==
        at(idx, "CONTAINERS", 0, 0));

  // Plants and seeds through PLANT_GRAPHICS; corpses through the creature.
  CHECK(resolveItem(idx, iq(wm::ItemKind::Seeds, "PLANT:MUSHROOM_HELMET_PLUMP:SEED")).sprite ==
        at(idx, "PLANT_STANDARD", 2, 0));
  CHECK(resolveItem(idx, iq(wm::ItemKind::Seeds, "PLANT:UNKNOWN_PLANT:SEED")).sprite ==
        at(idx, "CONTAINERS", 4, 0));
  CHECK(resolveItem(idx, iq(wm::ItemKind::Plant, "PLANT:MUSHROOM_HELMET_PLUMP:STRUCTURAL")).sprite ==
        at(idx, "PLANT_STANDARD", 1, 0));
  CHECK(resolveItem(idx, iq(wm::ItemKind::PlantGrowth, "PLANT:BLUEBERRY:FRUIT")).sprite ==
        at(idx, "PLANT_GARDEN", 3, 53));
  r = resolveItem(idx, iq(wm::ItemKind::Corpse, "CREATURE:DOG:MUSCLE"));
  REQUIRE(r.found);
  CHECK(r.sprite == at(idx, "CREATURES_DOMESTIC", 10, 6));  // the dog's CORPSE state
  r = resolveItem(idx, iq(wm::ItemKind::Corpse, "CREATURE:CAT:MUSCLE"));
  REQUIRE(r.found);
  CHECK(r.sprite == at(idx, "CREATURES_DOMESTIC", 0, 2));  // no CORPSE: DEFAULT stands in
  r = resolveItem(idx, iq(wm::ItemKind::CorpsePiece, "CREATURE:DWARF:BONE"));
  CHECK(r.found);  // body parts have their own tiles (BODYPART_LARGE_1 without flags)
  CHECK(r.rule == std::string("piece.bodypart"));
  CHECK(r.sprite == at(idx, "BODYPARTS", 0, 19));
  r = resolveItem(idx, iq(wm::ItemKind::Corpse, "CREATURE:DWARF:MUSCLE"));
  CHECK_FALSE(r.found);
  CHECK(r.rule == std::string("creature.layered"));
  r = resolveItem(idx, iq(wm::ItemKind::Corpse, "INORGANIC:GRANITE"));
  CHECK_FALSE(r.found);
  CHECK(r.rule == std::string("corpse.no-species"));
  CHECK(resolveItem(idx, iq(wm::ItemKind::Remains, "CREATURE:BIRD_CARDINAL:MUSCLE")).sprite ==
        at(idx, "ITEM_NATURE", 2, 0));

  // No art in vanilla.
  r = resolveItem(idx, iq(wm::ItemKind::Meat, "CREATURE:COW:MUSCLE"));
  CHECK_FALSE(r.found);
  CHECK(r.rule == std::string("no-art"));
  r = resolveItem(idx, iq(wm::ItemKind::Cabinet, "PLANT:OAK:WOOD"));
  CHECK_FALSE(r.found);
  CHECK(r.rule == std::string("missing-tile"));
}

// --- corpses, body parts and webs ---

TEST_CASE("corpse pieces: the body-part tile name from corpse flags and tissue") {
  using namespace std::string_literals;
  CHECK(corpsePieceTileName(wm::kCorpseBone | wm::kCorpseSkull, "CREATURE:GOBLIN:BONE", 8) ==
        "BODYPART_SKULL_2"s);
  CHECK(corpsePieceTileName(wm::kCorpseBone | wm::kCorpseSkull, "CREATURE:GOBLIN:BONE", 9) ==
        "BODYPART_SKULL_1"s);
  CHECK(corpsePieceTileName(wm::kCorpseBone, "CREATURE:DWARF:BONE", 1) == "BODYPART_BONE"s);
  // A severed, rotted limb (Unbutchered | Bone) is a LARGE part, not a bone
  // (measured live: goblin limbs on lone tiles draw LARGE_1..3).
  CHECK(corpsePieceTileName(wm::kCorpseUnbutchered | wm::kCorpseBone, "CREATURE:GOBLIN:BONE", 93135) ==
        "BODYPART_LARGE_1"s);
  CHECK(corpsePieceTileName(wm::kCorpseUnbutchered | wm::kCorpseBone, "CREATURE:GOBLIN:BONE", 93136) ==
        "BODYPART_LARGE_2"s);
  CHECK(corpsePieceTileName(wm::kCorpseUnbutchered, "CREATURE:GOBLIN:MUSCLE", 93134) == "BODYPART_LARGE_3"s);
  CHECK(corpsePieceTileName(wm::kCorpseTooth, "CREATURE:ELEPHANT:TOOTH", 1) == "BODYPART_TEETH"s);
  // A butchered tooth carries no corpse flag (measured live, corpse_probe).
  CHECK(corpsePieceTileName(0, "CREATURE:PIG:TOOTH", 55181) == "BODYPART_TEETH"s);
  CHECK(corpsePieceTileName(wm::kCorpseHorn, "CREATURE:COW:HORN", 1) == "BODYPART_HORN"s);
  CHECK(corpsePieceTileName(wm::kCorpseHorn, "CREATURE:HORSE:HOOF", 1) == "BODYPART_HOOF"s);
  CHECK(corpsePieceTileName(wm::kCorpseHorn, "CREATURE:DEER:ANTLER", 1) == "BODYPART_ANTLER"s);
  CHECK(corpsePieceTileName(wm::kCorpseShell, "CREATURE:TURTLE:SHELL", 1) == "BODYPART_SHELL"s);
  CHECK(corpsePieceTileName(wm::kCorpsePearl, "CREATURE:OYSTER:PEARL", 1) == "BODYPART_SHELL"s);
  CHECK(corpsePieceTileName(wm::kCorpseHairWool, "CREATURE:DWARF:HAIR", 1) == "BODYPART_HAIR"s);
  CHECK(corpsePieceTileName(wm::kCorpseHairWool, "CREATURE:SHEEP:WOOL", 1) == "BODYPART_WOOL"s);
  CHECK(corpsePieceTileName(wm::kCorpseLeather, "CREATURE:DWARF:SKIN", 1) == "BODYPART_SKIN_SMOOTH"s);
  CHECK(corpsePieceTileName(wm::kCorpseLeather, "CREATURE:CROCODILE:SCALE", 1) == "BODYPART_SKIN_SCALES"s);
  CHECK(corpsePieceTileName(wm::kCorpseLeather, "CREATURE:BIRD_CROW:FEATHER", 1) == "BODYPART_SKIN_FEATHERS"s);
  CHECK(corpsePieceTileName(wm::kCorpseSilk, "CREATURE:SPIDER_CAVE:SILK", 1) == "BODYPART_SMALL_1"s);
  // Unflagged pieces by tissue: organs, meat, fat, brain, chitin, scale, ...
  CHECK(corpsePieceTileName(0, "CREATURE:DWARF:MUSCLE", 1) == "BODYPART_MEAT"s);
  CHECK(corpsePieceTileName(0, "CREATURE:DWARF:FAT", 1) == "BODYPART_FAT"s);
  CHECK(corpsePieceTileName(0, "CREATURE:DWARF:HEART", 1) == "BODYPART_HEART"s);
  CHECK(corpsePieceTileName(0, "CREATURE:DWARF:GUT", 1) == "BODYPART_INTESTINES"s);
  CHECK(corpsePieceTileName(0, "CREATURE:DWARF:BRAIN", 1) == "BODYPART_BRAIN"s);
  CHECK(corpsePieceTileName(0, "CREATURE:DWARF:EYE", 1) == "BODYPART_EYE"s);
  CHECK(corpsePieceTileName(0, "CREATURE:BEETLE:CHITIN", 1) == "BODYPART_CHITIN_1"s);
  CHECK(corpsePieceTileName(0, "CREATURE:LIZARD:SCALE", 1) == "BODYPART_SCALE"s);
  CHECK(corpsePieceTileName(0, "CREATURE:DWARF:SKIN", 1) == "BODYPART_SKIN_SMOOTH"s);
  // Flags outrank the tissue name; unknown tissue is the generic large part.
  CHECK(corpsePieceTileName(wm::kCorpseBone, "CREATURE:DWARF:MUSCLE", 1) == "BODYPART_BONE"s);
  CHECK(corpsePieceTileName(0, "CREATURE:DWARF:TENDON", 1) == "BODYPART_LARGE_1"s);
  CHECK(corpsePieceTileName(0, "INORGANIC:GRANITE", 1) == "BODYPART_LARGE_1"s);
}

TEST_CASE("items: corpse pieces, skeletons and webs resolve to DF's tiles") {
  const AssetIndex idx = entityIndex();
  auto q = [&](wm::ItemKind kind, std::string_view material, uint16_t corpseFlags, uint32_t id,
               uint8_t flags = 0) {
    ItemQuery iq;
    iq.kind = kind;
    iq.material = material;
    iq.corpseFlags = corpseFlags;
    iq.id = id;
    iq.flags = flags;
    return iq;
  };
  SUBCASE("skull, bone, skin, hair, organ pieces") {
    ItemSprite r = resolveItem(idx, q(wm::ItemKind::CorpsePiece, "CREATURE:GOBLIN:BONE",
                                      wm::kCorpseBone | wm::kCorpseSkull, 10));
    CHECK(r.found);
    CHECK(r.bodyPart);
    CHECK(std::string(r.rule) == "piece.bodypart");
    CHECK(r.sprite == at(idx, "BODYPARTS", 1, 14));  // even id -> SKULL_2 (measured on item 50048)
    r = resolveItem(idx, q(wm::ItemKind::CorpsePiece, "CREATURE:GOBLIN:BONE",
                           wm::kCorpseBone | wm::kCorpseSkull, 11));
    CHECK(r.sprite == at(idx, "BODYPARTS", 0, 14));
    r = resolveItem(idx, q(wm::ItemKind::CorpsePiece, "CREATURE:DWARF:BONE", wm::kCorpseBone, 1));
    CHECK(r.sprite == at(idx, "BODYPARTS", 0, 19));
    r = resolveItem(idx, q(wm::ItemKind::CorpsePiece, "CREATURE:DWARF:SKIN", wm::kCorpseLeather, 1));
    CHECK(r.sprite == at(idx, "HIDES", 0, 1));
    r = resolveItem(idx, q(wm::ItemKind::CorpsePiece, "CREATURE:SHEEP:WOOL", wm::kCorpseHairWool, 1));
    CHECK(r.sprite == at(idx, "BODYPARTS", 0, 26));
    r = resolveItem(idx, q(wm::ItemKind::CorpsePiece, "CREATURE:DWARF:HEART", 0, 1));
    CHECK(r.sprite == at(idx, "BODYPARTS", 0, 4));
    r = resolveItem(idx, q(wm::ItemKind::CorpsePiece, "CREATURE:DWARF:MUSCLE", wm::kCorpseRottable, 1));
    CHECK(r.sprite == at(idx, "BODYPARTS", 0, 16));
  }
  SUBCASE("a tissue with no tile of its own is the generic large part") {
    const ItemSprite r = resolveItem(idx, q(wm::ItemKind::CorpsePiece, "CREATURE:DWARF:TENDON", 0, 1));
    CHECK(r.found);
    CHECK(r.sprite == at(idx, "BODYPARTS", 0, 21));
  }
  SUBCASE("a whole corpse rotted to bone is the bone pile; a fresh layered one stays for the stack") {
    ItemSprite r = resolveItem(idx, q(wm::ItemKind::Corpse, "CREATURE:DWARF:MUSCLE", wm::kCorpseBone, 1));
    CHECK(r.found);
    CHECK(r.bodyPart);
    CHECK(std::string(r.rule) == "corpse.skeleton");
    CHECK(r.sprite == at(idx, "BONE_PILE", 0, 0));
    r = resolveItem(idx, q(wm::ItemKind::Corpse, "CREATURE:DWARF:MUSCLE",
                           wm::kCorpseBone | wm::kCorpseRottable | wm::kCorpseLeather, 1));
    CHECK(!r.found);
    CHECK(std::string(r.rule) == "creature.layered");
    CHECK(!r.bodyPart);
  }
  SUBCASE("webs pick one of the four harmless tiles by id; plain thread is a spool") {
    ItemSprite r = resolveItem(idx, q(wm::ItemKind::Thread, "CREATURE:SPIDER_CAVE:SILK", 0, 4, wm::kItemWeb));
    CHECK(r.found);
    CHECK(std::string(r.rule) == "web.harmless");
    CHECK(r.sprite == at(idx, "ITEM_WEBS", 0, 0));
    r = resolveItem(idx, q(wm::ItemKind::Thread, "CREATURE:SPIDER_CAVE:SILK", 0, 7, wm::kItemWeb));
    CHECK(r.sprite == at(idx, "ITEM_WEBS", 3, 0));
    r = resolveItem(idx, q(wm::ItemKind::Thread, "CREATURE:SPIDER_CAVE:SILK", 0, 7, wm::kItemWeb | wm::kItemForbidden));
    CHECK(r.sprite == at(idx, "ITEM_WEBS", 3, 0));
    r = resolveItem(idx, q(wm::ItemKind::Thread, "PLANT:ROPE_REED:THREAD", 0, 7));
    CHECK(std::string(r.rule) == "thread");
    CHECK(r.sprite == at(idx, "ITEM_CLOTH", 0, 0));
  }
}
