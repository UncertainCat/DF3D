// Tier 0: building and item graphics on synthetic raw snippets:
// the layout / item-family / per-material parsers, the cache round trip
// of the new records, and the building / item resolvers' rules. No
// images, no install.
#include <doctest.h>

#include <string>
#include <vector>
#include <fstream>
#include <sstream>
#include <algorithm>

#include "df3d_assets/asset_index.h"
#include "df3d_assets/raw_tokens.h"
#include "df3d_assets/resolver.h"
#include "df3d_assets/steam_install.h"

using namespace df3d::assets;

TEST_CASE("bridge direction and raised footprint match native captured cells") {
  std::ifstream input(std::string(DF3D_ASSETS_TEST_DIR)+"/../../../fixtures/construction/bridge_render_tiles.txt");
  REQUIRE(input.good());
  std::string line;std::getline(input,line);int cases=0;
  int width,height,direction,raised,count;
  while(input>>width>>height>>direction>>raised>>count) {
    AssetIndex idx;idx.inorganics["GRANITE"].flags=kMatStone;
    std::vector<std::pair<int,int>> expected;
    std::vector<std::string> expectedNames;
    for(int i=0;i<count;++i) {
      int x,y;std::string aliases;REQUIRE(bool(input>>x>>y>>aliases));
      expected.push_back({x,y});
      expectedNames.push_back(aliases.substr(0,aliases.find(',')));
      std::istringstream names(aliases);std::string name;
      while(std::getline(names,name,','))idx.tileGraphics[name]={{0,i,0,1,1}};
    }
    BuildingQuery q;q.kind=wm::BuildingKind::Bridge;q.material="INORGANIC:GRANITE";
    q.width=width;q.height=height;q.bridgeDirection=int8_t(direction);q.bridgeRaised=raised!=0;
    const auto result=resolveBuildingTiles(idx,q);
    INFO(width,"x",height," direction=",direction," raised=",raised);
    REQUIRE(result.found);REQUIRE(result.tiles.size()==expected.size());
    for(const auto& tile:result.tiles) {
      REQUIRE(tile.sprite.x>=0);REQUIRE(size_t(tile.sprite.x)<expected.size());
      const auto position=std::find(expected.begin(),expected.end(),std::pair(tile.lx,tile.ly));
      REQUIRE(position!=expected.end());
      CHECK(tile.sprite.x==idx.tile(expectedNames[size_t(position-expected.begin())])->x);
    }
    ++cases;
  }
  CHECK(cases==70);
}

TEST_CASE("bolt thrower parts resolve their own installed graphics token") {
  AssetIndex idx;
  idx.pages.push_back({"ITEM_CONSTRUCTION","","/synthetic",32,32,256,320});
  idx.tileGraphics["ITEM_BALLISTA_PARTS"]={{0,1,9,1,1}};
  idx.tileGraphics["ITEM_BOLT_THROWER_PARTS"]={{0,2,9,1,1}};
  ItemQuery q; q.kind=wm::ItemKind::BoltThrowerParts;
  auto r=resolveItem(idx,q);
  REQUIRE(r.found); CHECK(r.sprite.x==2); CHECK(r.sprite.y==9);
}

TEST_CASE("container contents choose occupied art and independent material overlays") {
  AssetIndex idx;
  idx.pages.push_back({"CONTAINERS","","/containers",32,32,256,320});
  idx.tileGraphics["ITEM_BIN_WOOD_EMPTY"]={{0,0,4,1,1}};
  idx.tileGraphics["ITEM_BIN_WOOD_IN_USE"]={{0,1,4,1,1}};
  idx.tileGraphics["ITEM_BIN_TOP_BARS"]={{0,5,5,1,1}};
  idx.tileGraphics["ITEM_BIN_TOP_BLOCKS"]={{0,4,5,1,1}};
  idx.tileGraphics["ITEM_BARREL_WOOD_LIQUID"]={{0,2,2,1,1}};
  idx.tileGraphics["LIQUID_FOR_BARREL_WOOD"]={{0,6,2,1,1}};
  ItemQuery q; q.kind=wm::ItemKind::Bin; q.material="PLANT:OAK:WOOD";
  auto r=resolveItem(idx,q);
  CHECK(r.sprite.x==0); CHECK(r.overlays.empty()); // unknown contents
  q.containedCount=0;
  CHECK(resolveItem(idx,q).sprite.x==0);
  q.containedCount=5; q.containedKind=wm::ItemKind::Bar;
  r=resolveItem(idx,q);
  CHECK(r.sprite.x==1); REQUIRE(r.overlays.size()==1);
  CHECK(r.overlays[0].sprite.x==5);
  q.containedKind=wm::ItemKind::Blocks;
  r=resolveItem(idx,q); REQUIRE(r.overlays.size()==1);
  CHECK(r.overlays[0].sprite.x==4);
  q.kind=wm::ItemKind::Barrel; q.containedKind=wm::ItemKind::Drink;
  r=resolveItem(idx,q); CHECK(r.sprite.x==2); REQUIRE(r.overlays.size()==1);
  CHECK(r.overlays[0].sprite.x==6);
}

TEST_CASE("installed statues combine quality pedestal and creature or event figure") {
  AssetIndex idx;
  ingestRawText(idx,R"([OBJECT:GRAPHICS]
    [TILE_PAGE:STATUES][FILE:statues.png][TILE_DIM:32:32][PAGE_DIM:8:8]
    [TILE_GRAPHICS:STATUES:0:0:ITEM_STATUE_STONE:1]
    [TILE_GRAPHICS:STATUES:1:0:ITEM_STATUE_STONE:2]
    [TILE_GRAPHICS:STATUES:2:0:ITEM_STATUE_ARTIFACT]
    [TILE_GRAPHICS:STATUES:1:3:ITEM_DEFAULT_STATUE_TOP]
    [TILE_GRAPHICS:STATUES:1:4:ITEM_DEFAULT_STATUE_BOTTOM]
    [TILE_GRAPHICS:STATUES:2:3:ITEM_STATUE_GENERIC_DUEL_TOP]
    [TILE_GRAPHICS:STATUES:2:4:ITEM_STATUE_GENERIC_DUEL_BOTTOM]
    [STATUE_CREATURE_GRAPHICS:DWARF][DEFAULT:STATUES:0:6:0:7]
    [STATUE_CREATURE_CASTE_GRAPHICS:TEST_BIRD:FEMALE][DEFAULT:STATUES:3:6:3:7]
  )","/synthetic","statues",nullptr);
  finalizeIndex(idx);
  BuildingQuery q; q.kind=wm::BuildingKind::Statue; q.statue.quality=1;
  q.statue.subject=wm::ArtSubject::Creature; q.statue.subjectRaw="DWARF";
  auto r=resolveBuildingTiles(idx,q);
  REQUIRE(r.tiles.size()==3);
  CHECK(r.tiles[0].sprite.x==1);
  CHECK(r.tiles[1].ly==-1); CHECK(r.tiles[1].sprite.y==6);
  CHECK(r.tiles[2].ly==0); CHECK(r.tiles[2].sprite.y==7);
  q.statue.subjectRaw="TEST_BIRD"; q.statue.casteRaw="FEMALE"; q.statue.quality=6;
  r=resolveBuildingTiles(idx,q); REQUIRE(r.tiles.size()==3);
  CHECK(r.tiles[0].sprite.x==2); CHECK(r.tiles[1].sprite.x==3);
  q.statue.subject=wm::ArtSubject::Event; q.statue.event=wm::ArtEvent::Duel;
  r=resolveBuildingTiles(idx,q); REQUIRE(r.tiles.size()==3);
  CHECK(r.tiles[1].sprite.x==2); CHECK(r.tiles[1].sprite.y==3);
  q.statue={}; r=resolveBuildingTiles(idx,q); REQUIRE(r.tiles.size()==3);
  CHECK(r.tiles[0].sprite.x==0); CHECK(r.tiles[1].sprite.x==1);
}

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
  CHECK(r.colorName.empty()); // no construction component
  CHECK(r.paletteRow == -1);

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
        std::string("gem.small.generic"));

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
        at(idx, "STATUES", 7, 0));
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

TEST_CASE("pending construction uses native directional art without material recolouring") {
  auto idx = entityIndex();
  // Native captured zigzag: S, NE, SW, NE, W. Also cover raw EW/WE spelling.
  ingestRawText(idx, "[OBJECT:GRAPHICS]\n"
    "[TILE_GRAPHICS:WORKSHOPS:0:0:PLANNED_CONSTRUCTION_TRACK_S]\n"
    "[TILE_GRAPHICS:WORKSHOPS:1:0:PLANNED_CONSTRUCTION_TRACK_NE]\n"
    "[TILE_GRAPHICS:WORKSHOPS:2:0:PLANNED_CONSTRUCTION_TRACK_SW]\n"
    "[TILE_GRAPHICS:WORKSHOPS:3:0:PLANNED_CONSTRUCTION_TRACK_W]\n"
    "[TILE_GRAPHICS:WORKSHOPS:4:0:PLANNED_CONSTRUCTION_TRACK_WE]\n"
    "[TILE_GRAPHICS:WORKSHOPS:5:0:PLANNED_CONSTRUCTION_TRACK_RNSWE]\n",
    "/synth/mod/graphics", "pending", nullptr);
  finalizeIndex(idx);
  const uint16_t subtypes[] = {8,12,15,10,16,36};
  for (int i=0;i<6;++i) {
    auto q=bq(wm::BuildingKind::Construction,1,1,"INORGANIC:GRANITE",wm::BuildingStage::Planned,subtypes[i]);
    auto r=resolveBuildingTiles(idx,q);
    REQUIRE(r.found); REQUIRE(r.tiles.size()==1);
    CHECK(r.tiles[0].sprite.x==i); CHECK(r.tiles[0].sprite.y==0);
    CHECK(r.decal); CHECK(r.stageArt); CHECK(r.paletteRow==-1); CHECK(r.colorName.empty());
    q.stage=wm::BuildingStage::Complete;
    CHECK_FALSE(resolveBuildingTiles(idx,q).found);
    q.stage=wm::BuildingStage::Planned;q.subtype=65535;
    CHECK_FALSE(resolveBuildingTiles(idx,q).found);
  }
}

TEST_CASE("stationary pump cells match four captured native intake directions") {
  // pump_rendering.json: native completed and planned sprites share these cells.
  AssetIndex idx;idx.pages.push_back({"SCREWPUMP","","/synthetic",32,32,128,160});
  const char* names[]={"SCREWPUMP_S_1","SCREWPUMP_W_1","SCREWPUMP_N_1","SCREWPUMP_E_1"};
  const int x[]={2,2,0,0},y[]={2,0,2,0};
  for(int d=0;d<4;++d) {
    const bool horizontal=(d%2)!=0;
    for(int i=0;i<2;++i)idx.tileGraphics[names[d]].push_back({0,x[d]+(horizontal?i:0),y[d]+(horizontal?0:i),1,1});
    for(auto stage:{wm::BuildingStage::Planned,wm::BuildingStage::Complete}) {
      BuildingQuery q;q.kind=wm::BuildingKind::ScrewPump;q.pumpDirection=int8_t(d);
      q.width=horizontal?2:1;q.height=horizontal?1:2;q.stage=stage;q.material="INORGANIC:GRANITE";
      const auto r=resolveBuildingTiles(idx,q);REQUIRE(r.found);REQUIRE(r.tiles.size()==2);
      CHECK(r.paletteRow==-1);
      for(int i=0;i<2;++i) {
        CHECK(r.tiles[i].lx==(horizontal?i:0));CHECK(r.tiles[i].ly==(horizontal?0:i));
        CHECK(r.tiles[i].sprite.x==x[d]+(horizontal?i:0));CHECK(r.tiles[i].sprite.y==y[d]+(horizontal?0:i));
      }
    }
  }
}

TEST_CASE("track stop cells follow captured native terrain connections") {
  AssetIndex idx;idx.pages.push_back({"TRACK_STOPS","","/synthetic",32,32,512,64});
  const char* names[]={"NS","WE","SE","SW","NE","NW","NSW","NSE","SWE","NWE","NSWE"};
  for(int i=0;i<11;++i)idx.tileGraphics[std::string("TRACK_STOP_STONE_")+names[i]].push_back({0,i,0,1,1});
  // Expected sheet columns from 160 native stage/dump/direction observations.
  const int columns[]={10,0,0,0,1,4,2,7,1,5,3,6,1,9,8,10};
  for(int mask=0;mask<16;++mask)for(auto stage:{wm::BuildingStage::Planned,wm::BuildingStage::Complete}) {
    BuildingQuery q;q.kind=wm::BuildingKind::Trap;q.subtype=5;q.completedTrack=uint8_t(mask);
    q.stage=stage;q.material="INORGANIC:GRANITE";
    auto r=resolveBuildingTiles(idx,q);REQUIRE(r.found);REQUIRE(r.tiles.size()==1);
    CHECK(r.tiles[0].sprite.x==(stage==wm::BuildingStage::Complete?columns[mask]:10));
    CHECK(r.paletteRow==-1);
  }
}

TEST_CASE("track stop uses first item kind rather than wood material class") {
 auto idx=entityIndex();
 idx.tileGraphics["TRACK_STOP_STONE_NSWE"]={{0,0,0,1,1}};
 idx.tileGraphics["TRACK_STOP_WOOD_NSWE"]={{0,1,0,1,1}};
 BuildingQuery q;q.kind=wm::BuildingKind::Trap;q.subtype=5;q.material="PLANT:OAK:WOOD";
 q.constructionItemMaterial="INORGANIC:GRANITE";
 for(int8_t log:{-1,0,1}) {
  q.constructionItemIsLog=log;q.stage=wm::BuildingStage::Complete;
  auto r=resolveBuildingTiles(idx,q);REQUIRE(r.found);CHECK(r.tiles[0].sprite.x==(log==1?1:0));
  CHECK(r.paletteRow==(log==-1?-1:idx.paletteRow(idx.materialColorName(q.constructionItemMaterial))));
  q.stage=wm::BuildingStage::Planned;r=resolveBuildingTiles(idx,q);
  CHECK(r.tiles[0].sprite.x==0);CHECK(r.paletteRow==-1);
 }
}

TEST_CASE("rollers resolve native per-cell track, item material and machine position") {
  auto idx=entityIndex();
  const char* names[]={"NS","WE","SE","SW","NE","NW","NSW","NSE","SWE","NWE","NSWE"};
  for(int wood=0;wood<2;++wood)for(int frame=1;frame<=2;++frame)for(int shape=0;shape<11;++shape)
    idx.tileGraphics[std::string(wood?"ROLLERS_WOOD_":"ROLLERS_STONE_")+names[shape]+"_"+std::to_string(frame)]={{0,shape,wood*2+frame-1,1,1}};
  // Captured native sheet columns for all16 track masks.
  const int columns[]={10,0,0,0,1,4,2,7,1,5,3,6,1,9,8,10};
  // Native frame1 coordinate residues, indexed by direction then machine position.
  const int firstResidue[4][3]={{2,1,0},{0,1,2},{0,1,2},{2,1,0}};
  BuildingQuery q;q.kind=wm::BuildingKind::Rollers;q.material="PLANT:OAK:WOOD";
  q.constructionItemMaterial="INORGANIC:GRANITE";
  std::vector<uint8_t> tracks(3);q.completedTracks=&tracks;
  for(int direction=0;direction<4;++direction)for(int phase=0;phase<3;++phase)
  for(int log=-1;log<=1;++log)for(int mask=0;mask<16;++mask) {
    q.rollerDirection=int8_t(direction);q.rollerMachinePosition=int16_t(phase);q.constructionItemIsLog=int8_t(log);
    q.width=(direction&1)?3:1;q.height=(direction&1)?1:3;q.x1=99;q.y1=39;
    tracks={uint8_t(mask),5,12}; // varied underlying shapes within one building
    for(auto stage:{wm::BuildingStage::Complete,wm::BuildingStage::Planned}) {
      q.stage=stage;auto r=resolveBuildingTiles(idx,q);REQUIRE(r.found);REQUIRE(r.tiles.size()==3);
      CHECK(std::string(r.rule)=="machine.rollers");
      const bool complete=stage==wm::BuildingStage::Complete;
      CHECK(r.paletteRow==(complete && log!=-1?idx.paletteRow(idx.materialColorName(q.constructionItemMaterial)):-1));
      for(int cell=0;cell<3;++cell) {
        CHECK(r.tiles[cell].lx==((direction&1)?cell:0));CHECK(r.tiles[cell].ly==((direction&1)?0:cell));
        CHECK(r.tiles[cell].sprite.x==(complete?columns[tracks[cell]]:direction%2));
        const int frameRow=complete && cell!=firstResidue[direction][phase]?1:0;
        CHECK(r.tiles[cell].sprite.y==((complete && log==1?2:0)+frameRow));
      }
    }
  }
  q.stage=wm::BuildingStage::Complete;q.width=1;q.height=1;q.rollerDirection=1;
  q.constructionItemIsLog=-1;q.completedTracks=nullptr;q.rollerMachinePosition=-129;
  auto r=resolveBuildingTiles(idx,q);REQUIRE(r.tiles.size()==1);CHECK(r.tiles[0].sprite.x==10);CHECK(r.tiles[0].sprite.y==0);
  q.rollerMachinePosition=-128;r=resolveBuildingTiles(idx,q);CHECK(r.tiles[0].sprite.y==1);
  q.rollerMachinePosition=127;q.x1=100;r=resolveBuildingTiles(idx,q);CHECK(r.tiles[0].sprite.y==0);
  q.rollerDirection=-1;r=resolveBuildingTiles(idx,q);CHECK(r.tiles[0].sprite.y==0);
}

TEST_CASE("instrument artwork follows native family, definition and construction stage") {
  auto idx=entityIndex();const char* names[]={"KEYBOARD","STRINGED","WIND","PERCUSSION"};
  // Installed sheet columns differ from semantic family order.
  const int columns[]={0,2,3,1};
  for(int family=0;family<4;++family)for(int placed=0;placed<2;++placed)
    idx.tileGraphics[std::string("ITEM_INSTRUMENT_")+names[family]+(placed?"_BUILDING":"_HANDHELD")]={{0,columns[family],1-placed,1,1}};
  BuildingQuery q;q.kind=wm::BuildingKind::Instrument;q.material="PLANT:OAK:WOOD";
  q.constructionItemMaterial="INORGANIC:GRANITE";
  for(int family=-1;family<4;++family)for(int placed=0;placed<2;++placed)
  for(auto stage:{wm::BuildingStage::Planned,wm::BuildingStage::InProgress,wm::BuildingStage::Complete}) {
    q.instrumentFamily=int8_t(family);q.instrumentPlaced=family<0?-1:int8_t(placed);q.stage=stage;
    const auto r=resolveBuildingTiles(idx,q);REQUIRE(r.found);REQUIRE(r.tiles.size()==1);
    const bool complete=stage==wm::BuildingStage::Complete;
    CHECK(r.tiles[0].sprite.x==(complete && family>=0?columns[family]:0));
    CHECK(r.tiles[0].sprite.y==(complete && family>=0?1-placed:0));
    CHECK(r.paletteRow==(complete?(family<0?-1:idx.paletteRow(idx.materialColorName(q.constructionItemMaterial))):idx.paletteRow(idx.materialColorName(q.material))));
    CHECK(std::string_view(r.rule)=="instrument.native");
  }
}

TEST_CASE("instrument item artwork uses candidate definition facts") {
 auto idx=entityIndex();const char* names[]={"KEYBOARD","STRINGED","WIND","PERCUSSION"};
 const int columns[]={0,2,3,1};
 for(int family=0;family<4;++family)for(int placed=0;placed<2;++placed)
  idx.tileGraphics[std::string("ITEM_INSTRUMENT_")+names[family]+(placed?"_BUILDING":"_HANDHELD")]={{0,columns[family],1-placed,1,1}};
 ItemQuery q;q.kind=wm::ItemKind::Instrument;q.material="INORGANIC:GRANITE";
 for(int family=0;family<4;++family)for(int placed=0;placed<2;++placed) {
  q.instrumentFamily=int8_t(family);q.instrumentPlaced=int8_t(placed);
  const auto r=resolveItem(idx,q);REQUIRE(r.found);
  CHECK(r.sprite.x==columns[family]);CHECK(r.sprite.y==1-placed);
  CHECK(r.paletteRow==25);CHECK(std::string_view(r.rule)=="instrument.native");
 }
}

TEST_CASE("one-cell axle orientation uses native axis and transmission art uses first item material") {
 auto idx=entityIndex();idx.tileGraphics["AXLE_HORIZONTAL_NS_1"]={{0,2,0,1,1}};idx.tileGraphics["AXLE_HORIZONTAL_WE_1"]={{0,2,1,1,1}};
 idx.tileGraphics["AXLE_VERTICAL_1"]={{0,2,3,1,1}};idx.tileGraphics["GEAR_ASSEMBLY_1"]={{0,0,2,1,1}};
 BuildingQuery q;q.material="INORGANIC:GRANITE";q.constructionItemMaterial="PLANT:OAK:WOOD";
 for(auto kind:{wm::BuildingKind::AxleHorizontal,wm::BuildingKind::AxleVertical,wm::BuildingKind::GearAssembly})for(int axis:{-1,0,1})for(int present:{-1,0,1})for(auto stage:{wm::BuildingStage::Complete,wm::BuildingStage::Planned}) {
  q.kind=kind;q.horizontalAxleVertical=axis;q.constructionItemIsLog=present;q.stage=stage;
  const auto r=resolveBuildingTiles(idx,q);REQUIRE(r.found);REQUIRE(r.tiles.size()==1);
  const int row=kind==wm::BuildingKind::GearAssembly?2:kind==wm::BuildingKind::AxleVertical?3:axis==0?1:0;
  CHECK(r.tiles[0].sprite.y==row);CHECK(r.paletteRow==(stage==wm::BuildingStage::Complete && present>=0?idx.paletteRow(idx.materialColorName(q.constructionItemMaterial)):-1));
 }
}

TEST_CASE("placed slab engraving and first item determine native artwork") {
 auto idx=entityIndex();idx.tileGraphics["ITEM_SLAB_BLANK"]={{0,0,0,1,1}};idx.tileGraphics["ITEM_SLAB_ENGRAVED_MEMORIAL"]={{0,0,1,1,1}};idx.tileGraphics["ITEM_SLAB_ENGRAVED_SECRET"]={{0,0,2,1,1}};
 BuildingQuery q;q.kind=wm::BuildingKind::Slab;q.material="PLANT:OAK:WOOD";q.constructionItemMaterial="INORGANIC:GRANITE";
 for(int present:{-1,0})for(int engraving:{-2,-1,0,1,5,6})for(auto stage:{wm::BuildingStage::Planned,wm::BuildingStage::Complete}) {
  q.constructionItemIsLog=present;q.slabEngraving=engraving;q.stage=stage;const auto r=resolveBuildingTiles(idx,q);REQUIRE(r.found);REQUIRE(r.tiles.size()==1);
  const bool known=present>=0 && stage==wm::BuildingStage::Complete && (engraving==-1 || engraving==0 || engraving==6);
  CHECK(r.tiles[0].sprite.y==(known?(engraving==0?1:engraving==6?2:0):0));CHECK(r.paletteRow==(known?25:-1));
 }
}

TEST_CASE("Exact native layout stages select base and overlay together") {
 auto idx=entityIndex();
 auto& base=idx.buildingLayouts["WORKSHOP_CARPENTER"];base.width=1;base.height=2;
 auto& overlay=idx.buildingLayouts["WORKSHOP_CARPENTER_OVERLAY"];overlay.width=1;overlay.height=2;
 for(int stage=0;stage<4;++stage) {
  base.stages[stage]={at(idx,"WORKSHOPS",stage,0),at(idx,"WORKSHOPS",stage,1)};
  overlay.stages[stage]={at(idx,"WORKSHOPS",stage+4,0),at(idx,"WORKSHOPS",stage+4,1)};
 }
 auto q=bq(wm::BuildingKind::Workshop,1,1,"INORGANIC:GRANITE",wm::BuildingStage::Planned,0);
 for(int stage:{0,1,2,3,1,2}) {
  q.constructionStage=stage;q.stage=stage==0?wm::BuildingStage::Planned:stage==3?wm::BuildingStage::Complete:wm::BuildingStage::InProgress;
  auto r=resolveBuildingTiles(idx,q);REQUIRE(r.found);REQUIRE(r.tiles.size()==4);
  CHECK(tileAt(r,0,0)->sprite.x==stage);CHECK(tileAt(r,0,-1)->sprite.x==stage);
  CHECK(tileAt(r,0,0,1)->sprite.x==stage+4);CHECK(tileAt(r,0,-1,1)->sprite.x==stage+4);
  CHECK(r.stageArt==(stage!=3));CHECK(r.gridLayout);
  if(stage<=1) {CHECK(r.paletteRow==-1);CHECK(r.colorName.empty());}
 }
 q.constructionStage=-1;q.stage=wm::BuildingStage::Planned;
 auto r=resolveBuildingTiles(idx,q);CHECK_FALSE(r.stageArt);CHECK(tileAt(r,0,0)->sprite.x==3);
}

TEST_CASE("Layout base palette follows its construction component at every stage") {
 const auto idx=entityIndex();
 auto q=bq(wm::BuildingKind::Workshop,3,3,"PLANT:OAK:WOOD",wm::BuildingStage::InProgress,2);
 q.constructionItemIsLog=0;q.constructionItemMaterial="INORGANIC:GRANITE";
 for(auto stage:{wm::BuildingStage::Planned,wm::BuildingStage::InProgress,wm::BuildingStage::Complete}) {
  q.stage=stage;auto r=resolveBuildingTiles(idx,q);REQUIRE(r.found);CHECK(r.paletteRow==25);CHECK(r.colorName=="CLEAR");
 }
 q.constructionItemIsLog=-1;auto r=resolveBuildingTiles(idx,q);CHECK(r.paletteRow==-1);
}

TEST_CASE("Quern column uses component palette and native descriptor") {
 const auto idx=entityIndex();auto q=bq(wm::BuildingKind::Workshop,1,1,"INORGANIC:GRANITE",wm::BuildingStage::Planned,17);
 auto r=resolveBuildingTiles(idx,q);REQUIRE(r.found);CHECK_FALSE(r.gridLayout);CHECK(r.paletteRow==-1);
 q.constructionItemIsLog=0;q.constructionItemMaterial="INORGANIC:GRANITE";r=resolveBuildingTiles(idx,q);CHECK(r.paletteRow==25);
 q.stage=wm::BuildingStage::Complete;r=resolveBuildingTiles(idx,q);CHECK(r.paletteRow==25);
 q.constructionItemSolidColor="CLEAR";q.constructionItemMaterial="UNKNOWN";r=resolveBuildingTiles(idx,q);CHECK(r.paletteRow==25);
}

TEST_CASE("Siege artwork follows native facing timer contents and exact construction stage") {
 auto idx=entityIndex();
 const char* dirs[]={"N","NE","E","SE","S","SW","W","NW"};
 for(const char* base:{"CATAPULT","BALLISTA"}) {
  for(int n=0;n<4;++n)idx.tileGraphics[std::string(base)+"_CONST_"+std::to_string(n)]={{0,n,0,1,1}};
  for(int d=0;d<8;++d)for(int fire=0;fire<2;++fire)
   idx.tileGraphics[std::string(base)+"_"+dirs[d]+(fire?"_FIRING":"")]={{0,d,fire+1,1,1}};
 }
 for(int d=0;d<8;++d)for(int fire=0;fire<2;++fire)
  idx.tileGraphics[std::string("BOLT_THROWER_")+(fire?"FIRING_":"READY_")+dirs[d]]={{0,d,fire+1,1,1}};
 // Remove real test layouts so these sentinel columns isolate selection.
 for(auto it=idx.buildingLayouts.begin();it!=idx.buildingLayouts.end();) {
  if(it->first.find("CATAPULT")==0 || it->first.find("BALLISTA")==0)it=idx.buildingLayouts.erase(it);else ++it;
 }
 auto q=bq(wm::BuildingKind::SiegeEngine,1,1,"PLANT:OAK:WOOD",wm::BuildingStage::Complete,0);
 q.constructionItemIsLog=0;q.constructionItemMaterial="INORGANIC:GRANITE";
 for(int type=0;type<3;++type)for(int d=0;d<8;++d)for(int count:{0,1,2,3,4})for(int timer:{-129,-128,-1,0,1,2,3,4,5,6,127}) {
  q.subtype=type;q.siegeFacing=d;q.siegeFireTimer=timer;q.containedItemCount=count;
  const auto r=resolveBuildingTiles(idx,q);REQUIRE(r.found);REQUIRE(r.tiles.size()==1);
  CHECK(r.tiles[0].sprite.x==d);
  const bool fire=(timer>=1 && timer<=(type==2?2:5)) || (type==1 && count==3);
  CHECK(r.tiles[0].sprite.y==(fire?2:1));CHECK(r.paletteRow==25);CHECK_FALSE(r.stageArt);
 }
 for(int type=0;type<3;++type)for(int d=0;d<8;++d)for(int count:{0,1})for(int stage=0;stage<3;++stage) {
  q.subtype=type;q.siegeFacing=d;q.containedItemCount=count;q.constructionStage=stage;
  q.stage=stage?wm::BuildingStage::InProgress:wm::BuildingStage::Planned;
  const auto r=resolveBuildingTiles(idx,q);REQUIRE(r.found);CHECK(r.stageArt);CHECK(r.paletteRow==-1);
  CHECK(r.tiles[0].sprite.x==(type==2?d:count?stage+1:0));
 }
 q.stage=wm::BuildingStage::Complete;q.constructionItemIsLog=-1;
 CHECK(resolveBuildingTiles(idx,q).paletteRow==-1);
 q.constructionItemIsLog=0;q.constructionItemMaterial="UNKNOWN";q.constructionItemSolidColor="CLEAR";
 CHECK(resolveBuildingTiles(idx,q).paletteRow==25);
}

TEST_CASE("single-tile workshop planned art keeps component color and halves source alpha") {
 auto idx=entityIndex();idx.tileGraphics["WORKSHOP_MILLSTONE"]={{0,0,0,1,1},{0,0,1,1,1}};
 auto q=bq(wm::BuildingKind::Workshop,1,1,"PLANT:OAK:WOOD",wm::BuildingStage::Planned,22);
 q.constructionItemIsLog=0;q.constructionItemMaterial="INORGANIC:GRANITE";
 auto r=resolveBuildingTiles(idx,q);REQUIRE(r.found);CHECK(r.plannedHalfAlpha);CHECK(r.stageArt);CHECK(r.paletteRow==25);
 q.stage=wm::BuildingStage::Complete;r=resolveBuildingTiles(idx,q);CHECK_FALSE(r.plannedHalfAlpha);CHECK(r.paletteRow==25);
}

TEST_CASE("Archery targets retain raw palette and use metal artwork for glass") {
 auto idx=entityIndex();idx.tileGraphics["BLD_ARCHERY_TARGET_METAL"]={{0,0,0,1,1}};
 auto q=bq(wm::BuildingKind::ArcheryTarget,1,1,"GLASS_GREEN",wm::BuildingStage::Planned);
 auto r=resolveBuildingTiles(idx,q);REQUIRE(r.found);CHECK(r.paletteRow==-1);CHECK(r.tiles[0].sprite.x==0);
 q.stage=wm::BuildingStage::Complete;r=resolveBuildingTiles(idx,q);CHECK(r.paletteRow==-1);
}

TEST_CASE("Mechanism traps use native state colors top layers and planned opacity") {
 auto idx=entityIndex();
 const char* names[]={"LEVER_SET","LEVER_PULLED","TRAP_PLATE_READY","TRAP_PLATE_PRESSED","TRAP_CAGE","TRAP_CAGE_UNLOADED","TRAP_CAGE_TOP","TRAP_STONE","TRAP_STONE_UNLOADED","TRAP_STONE_TOP"};
 for(int i=0;i<10;++i)idx.tileGraphics[names[i]]={{0,i,0,1,1}};
 for(int pressed=0;pressed<2;++pressed)for(int trigger=0;trigger<3;++trigger)
  idx.tileGraphics[std::string(pressed?"TRAP_PLATE_PRESSED":"TRAP_PLATE_READY")+std::vector<std::string>{"_WATER","_MAGMA","_MINECART"}[trigger]]={{0,10+trigger,pressed,1,1}};
 auto q=bq(wm::BuildingKind::Trap,1,1,"PLANT:OAK:WOOD",wm::BuildingStage::Complete,0);
 q.constructionItemIsLog=0;q.constructionItemMaterial="INORGANIC:GRANITE";q.containedItemCount=2;
 for(int state:{-129,-128,-1,0,1,127}) {
  q.trapState=state;auto r=resolveBuildingTiles(idx,q);REQUIRE(r.found);CHECK(r.tiles.size()==1);CHECK(r.tiles[0].sprite.x==(state>0?1:0));CHECK(r.paletteRow==25);
 }
 q.subtype=1;q.trapState=0;q.trapTriggerFlags=63;
 for(int ready:{-32769,-32768,-1,0,1,32767})for(int fill:{-32769,-32768,-1,0,1,32767}) {
  q.trapReadyTimeout=ready;q.trapFillTimer=fill;auto r=resolveBuildingTiles(idx,q);
  REQUIRE(r.found);CHECK(r.tiles.size()==1);CHECK(r.tiles[0].sprite.x==11);CHECK(r.tiles[0].sprite.y==int(ready>0 || fill>0));
 }
 for(int type:{2,3})for(int count:{0,1,2,3,4})for(int state:{-128,0,1,127}) {
  q.subtype=type;q.containedItemCount=count;q.trapState=state;
  auto r=resolveBuildingTiles(idx,q);const bool loaded=count>=2 && state<=0;
  REQUIRE(r.found);CHECK(r.tiles.size()==(loaded?2:1));
  CHECK(r.tiles[0].sprite.x==(type==2?4:7)+(loaded?0:1));
  if(loaded){CHECK(r.tiles[1].ly==-1);CHECK(r.tiles[1].foreground);CHECK(r.tiles[1].rawPalette);CHECK_FALSE(r.gridLayout);}
 }
 for(int type=0;type<4;++type) {
  q.subtype=type;q.stage=wm::BuildingStage::Planned;
  auto r=resolveBuildingTiles(idx,q);REQUIRE(r.found);CHECK(r.stageArt);CHECK(r.plannedHalfAlpha);CHECK(r.paletteRow==-1);CHECK(r.tiles.size()==1);
  q.stage=wm::BuildingStage::Complete;q.constructionItemIsLog=-1;
  r=resolveBuildingTiles(idx,q);CHECK(r.found);CHECK(r.tiles.empty());
 }
}

TEST_CASE("Weapon traps use the selected weapon only when complete loaded and armed") {
 auto idx=entityIndex();idx.tileGraphics["TRAP_WEAPON"]={{0,0,0,1,1}};
 idx.itemDefs["ITEM_WEAPON_SWORD_SHORT"].variants["WEAPON_TRAP"]={0,1,0,1,1};
 idx.itemDefs["ITEM_TRAPCOMP_MENACINGSPIKE"].variants["WEAPON_TRAP"]={0,2,0,1,1};
 auto q=bq(wm::BuildingKind::Trap,1,1,"PLANT:OAK:WOOD",wm::BuildingStage::Complete,4);
 q.constructionItemIsLog=0;q.constructionItemMaterial="INORGANIC:GRANITE";
 for(const char* raw:{"ITEM_WEAPON_SWORD_SHORT","ITEM_TRAPCOMP_MENACINGSPIKE"})for(int count:{0,1,2,10})for(int state:{-128,-1,0,1,127}) {
  q.constructionWeaponRaw=raw;q.containedItemCount=count;q.weaponCount=1;q.trapState=state;
  auto r=resolveBuildingTiles(idx,q);REQUIRE(r.found);REQUIRE(r.tiles.size()==1);
  const bool armed=count>=2 && state<=0;
  CHECK(r.tiles[0].sprite.x==(armed?(q.constructionWeaponRaw=="ITEM_WEAPON_SWORD_SHORT"?1:2):0));CHECK(r.paletteRow==(armed?25:-1));
 }
 q.containedItemCount=2;q.trapState=0;q.weaponCount=0;
 CHECK(resolveBuildingTiles(idx,q).tiles[0].sprite.x==0);
 q.weaponCount=2;q.stage=wm::BuildingStage::Planned;
 auto r=resolveBuildingTiles(idx,q);CHECK(r.tiles[0].sprite.x==0);CHECK(r.paletteRow==-1);CHECK(r.stageArt);CHECK(r.plannedHalfAlpha);
 q.stage=wm::BuildingStage::Complete;q.constructionWeaponRaw="MISSING";
 CHECK(resolveBuildingTiles(idx,q).tiles[0].sprite.x==0);
}

TEST_CASE("Upright weapons select declared count art and native retracted palette") {
 auto idx=entityIndex();
 for(int n=1;n<=10;++n) {
  idx.tileGraphics["UPRIGHT_WEAPON_RETRACTED_"+std::to_string(n)]={{0,n,0,1,1}};
  auto& variants=idx.itemDefs["ITEM_TRAPCOMP_MENACINGSPIKE"].variants;
  variants["UPRIGHT_"+std::to_string(n)+"T"]={0,n,1,1,1};
  variants["UPRIGHT_"+std::to_string(n)+"B"]={0,n,2,1,1};
 }
 auto q=bq(wm::BuildingKind::Weapon,1,1,"PLANT:OAK:WOOD",wm::BuildingStage::Complete);
 q.constructionWeaponRaw="ITEM_TRAPCOMP_MENACINGSPIKE";q.constructionItemMaterial="INORGANIC:GRANITE";
 for(int n=0;n<=11;++n)for(int retracted:{0,1}) {
  q.weaponCount=n;q.weaponRetracted=retracted;auto r=resolveBuildingTiles(idx,q);
  REQUIRE(r.found);const bool raised=n>0 && !retracted;
  REQUIRE(r.tiles.size()==(raised?2:1));CHECK(r.paletteRow==(raised?25:-1));
  CHECK(r.tiles[0].sprite.x==(n==0?10:std::min(n,10)));CHECK(r.tiles[0].sprite.y==(raised?2:0));
  if(raised){CHECK(r.tiles[1].ly==-1);CHECK(r.tiles[1].foreground);CHECK_FALSE(r.tiles[1].rawPalette);CHECK(r.tiles[1].sprite.y==1);}
 }
 q.stage=wm::BuildingStage::Planned;q.weaponCount=3;q.weaponRetracted=0;
 auto r=resolveBuildingTiles(idx,q);REQUIRE(r.tiles.size()==1);CHECK(r.tiles[0].sprite.x==10);CHECK(r.paletteRow==-1);CHECK(r.stageArt);CHECK(r.plannedHalfAlpha);
 q.stage=wm::BuildingStage::Complete;q.weaponCount=-1;
 CHECK(std::string(resolveBuildingTiles(idx,q).rule)=="upright-weapon.unknown");
}
