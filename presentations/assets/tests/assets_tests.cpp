// Tier 0: the asset provider on synthetic raw snippets (tests/data/*.txt,
// hand-written in DF's raw format; no images, no install). Covers the
// tokenizer, Steam manifest parsing, install verification, every parser
// the index has, the resolver's precedence rules, cache round-trip and
// cache-key mismatch behaviour, and the provider over a synthetic install
// tree built in a temp directory.
#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest.h>

#include <chrono>
#include <filesystem>
#include <fstream>
#include <string>
#include <set>
#include <sstream>

#include "df3d_assets/asset_index.h"
#include "df3d_assets/provider.h"
#include "df3d_assets/raw_tokens.h"
#include "df3d_assets/resolver.h"
#include "df3d_assets/steam_install.h"

using namespace df3d::assets;
namespace fs = std::filesystem;

namespace {

std::string dataDir() { return std::string(DF3D_ASSETS_TEST_DIR) + "/data"; }

std::string readData(const char* name) {
  std::string text, err;
  REQUIRE_MESSAGE(readTextFile(dataDir() + "/" + name, text, err), err);
  return text;
}

// The full synthetic index: pages, tiles (with a page defined only after
// its use), plants, creatures, colours, templates, inorganics, plants.
AssetIndex synthIndex(std::vector<std::string>* diag = nullptr) {
  AssetIndex idx;
  const std::string g = "/synth/mod/graphics";
  ingestRawText(idx, readData("tile_page_test.txt"), g, "tile_page_test", diag);
  ingestRawText(idx, readData("descriptor_color_test.txt"), g, "colors", diag);
  ingestRawText(idx, readData("material_template_test.txt"), g, "templates", diag);
  ingestRawText(idx, readData("palette_test.txt"), g, "palette", diag);
  ingestRawText(idx, readData("graphics_tiles_test.txt"), g, "tiles", diag);
  ingestRawText(idx, readData("tile_page_late_test.txt"), g, "tile_page_late", diag);
  ingestRawText(idx, readData("graphics_plants_test.txt"), g, "plants_gfx", diag);
  ingestRawText(idx, readData("graphics_creatures_test.txt"), g, "creatures_gfx", diag);
  ingestRawText(idx, readData("inorganic_test.txt"), g, "inorganic", diag);
  ingestRawText(idx, readData("plant_test.txt"), g, "plant", diag);
  finalizeIndex(idx);
  return idx;
}

TerrainQuery q(wm::TileShape shape, wm::MaterialKind kind, std::string_view mat,
               FaceSide side = FaceSide::Top, FaceKind part = FaceKind::Terrain,
               uint8_t flags = 0, SlopeDir slope = SlopeDir::None) {
  TerrainQuery t;
  t.shape = shape;
  t.kind = kind;
  t.material = mat;
  t.side = side;
  t.part = part;
  t.flags = flags;
  t.slope = slope;
  return t;
}

}  // namespace

// --- tokenizer ---

TEST_CASE("tokenizer: brackets, multi-token lines, comments, odd ids") {
  const auto toks = tokenizeRaw(
      "header line\n[OBJECT:GRAPHICS]\n[A:1:2][B:x]  trailing text\n"
      "[PLANT_GRAPHICS:DOG'S TOOTH GRASS]\n\t[GRASS_1:GRASS:0:0]***comment\n"
      "[BAMBOO, HEDGE]\n[EMPTY]\n[unterminated");
  REQUIRE(toks.size() == 7);
  CHECK(toks[0].name() == "OBJECT");
  CHECK(toks[1].args == std::vector<std::string>{"A", "1", "2"});
  CHECK(toks[1].line == 3);
  CHECK(toks[2].name() == "B");
  CHECK(toks[2].line == 3);
  CHECK(toks[3].args[1] == "DOG'S TOOTH GRASS");
  CHECK(toks[4].line == 5);
  CHECK(toks[5].args[0] == "BAMBOO, HEDGE");
  CHECK(toks[6].args == std::vector<std::string>{"EMPTY"});
  CHECK(rawObjectType(toks) == "GRAPHICS");
  int v = 0;
  CHECK(parseInt("42", v));
  CHECK(v == 42);
  CHECK_FALSE(parseInt("AS_IS", v));
  CHECK_FALSE(parseInt("", v));
}

TEST_CASE("tokenizer: CRLF files keep clean arguments") {
  const auto toks = tokenizeRaw("[A:B]\r\n[C]\r\n");
  REQUIRE(toks.size() == 2);
  CHECK(toks[1].line == 2);
  CHECK(toks[0].args[1] == "B");
}

// --- Steam ---

TEST_CASE("vdf: libraryfolders and appmanifest") {
  VdfNode root;
  std::string err;
  REQUIRE_MESSAGE(parseVdf(readData("libraryfolders_test.vdf"), root, err), err);
  const auto libs = parseLibraryFolders(root);
  REQUIRE(libs.size() == 2);
  CHECK(libs[0].path == "C:\\Program Files (x86)\\Steam");
  CHECK(libs[0].apps.size() == 2);
  CHECK(libs[1].path == "D:\\SteamLibrary");
  REQUIRE(libs[1].apps.size() == 1);
  CHECK(libs[1].apps[0] == kDfSteamAppId);

  VdfNode m;
  REQUIRE(parseVdf(readData("appmanifest_test.acf"), m, err));
  const auto app = parseAppManifest(m);
  REQUIRE(app.has_value());
  CHECK(app->appId == "975370");
  CHECK(app->installDir == "Dwarf Fortress");
  CHECK(app->buildId == "24557528");
  CHECK(m.child("AppState")->child("InstalledDepots")->child("975371")->value("manifest") ==
        "4712032431285104732");

  VdfNode bad;
  CHECK_FALSE(parseVdf("\"a\" { \"b\" ", bad, err));
  CHECK(err.find("vdf") != std::string::npos);
}

TEST_CASE("pe timestamp from synthetic bytes") {
  std::string img(0x100, '\0');
  img[0] = 'M';
  img[1] = 'Z';
  img[0x3C] = 0x80;  // e_lfanew
  img[0x80] = 'P';
  img[0x81] = 'E';
  img[0x88] = static_cast<char>(0xD9);
  img[0x89] = static_cast<char>(0xA6);
  img[0x8A] = static_cast<char>(0x70);
  img[0x8B] = static_cast<char>(0x6A);
  CHECK(peTimestampOf(img) == 0x6A70A6D9u);
  CHECK(peTimestampOf("not an exe") == 0);
  CHECK(peTimestampOf(std::string(0x40, 'M')) == 0);
}

TEST_CASE("install verification: manifest build, PE fallback, clear errors") {
  InstallInfo info;
  info.root = "X:/DF";
  info.buildId = "24557528";
  std::string err;
  CHECK(verifyInstallBuild(info, "24557528", 0x6A70A6D9u, err));
  info.buildId = "23622201";
  CHECK_FALSE(verifyInstallBuild(info, "24557528", 0x6A70A6D9u, err));
  CHECK(err.find("23622201") != std::string::npos);
  CHECK(err.find("24557528") != std::string::npos);
  CHECK(err.find("PINS.md") != std::string::npos);
  info.buildId.clear();
  info.peTimestamp = 0x6A70A6D9u;
  CHECK(verifyInstallBuild(info, "24557528", 0x6A70A6D9u, err));
  info.peTimestamp = 1;
  CHECK_FALSE(verifyInstallBuild(info, "24557528", 0x6A70A6D9u, err));
  CHECK(err.find("no Steam manifest") != std::string::npos);
}

TEST_CASE("locate: missing override is a hard, explained failure") {
  LocateOptions lo;
  lo.installOverride = "Z:/definitely/not/here";
  std::string err;
  CHECK_FALSE(locateInstall(lo, err).has_value());
  CHECK(err.find("does not exist") != std::string::npos);
  lo.installOverride.clear();
  lo.steamRoot = "Z:/no/steam";
  CHECK_FALSE(locateInstall(lo, err).has_value());
  CHECK(err.find("not found in any Steam library") != std::string::npos);
  CHECK(err.find("Classic") != std::string::npos);
}

TEST_CASE("path helpers") {
  CHECK(joinPath("C:\\a\\", "b/c") == "C:/a/b/c");
  CHECK(joinPath("C:/a", "/b") == "C:/a/b");
  CHECK(parentPath("C:/a/b/c/") == "C:/a/b");
  CHECK(parentPath("C:\\a\\b") == "C:/a");
  CHECK(parentPath("file") == "");
}

// --- index parsing ---

TEST_CASE("tile pages: dims, pixels, duplicates, absolute paths") {
  std::vector<std::string> diag;
  const AssetIndex idx = synthIndex(&diag);
  CHECK(idx.stats.tilePageFiles == 2);
  CHECK(idx.stats.duplicatePages == 1);
  const TilePage* ws = idx.page(idx.pageIndex("WALL_STONE"));
  REQUIRE(ws);
  CHECK(ws->pageW == 128);
  CHECK(ws->pageH == 320);
  CHECK(ws->absPath == "/synth/mod/graphics/images/wall_stone.png");
  const TilePage* g = idx.page(idx.pageIndex("GRASS"));
  REQUIRE(g);
  CHECK(g->file == "images/grass.png");  // first definition wins
  CHECK(g->pageW == 128);
  CHECK(g->tileW == 32);
  // Referenced before defined: same page index after the late file.
  const SpriteRef* soil = idx.tile("SOIL_WALL_N_S_W_E_1");
  REQUIRE(soil);
  CHECK(soil->page == idx.pageIndex("WALL_SOIL"));
  CHECK(idx.page(soil->page)->pageW == 128);
  // Referenced and never defined: placeholder with no file.
  const SpriteRef* sand = idx.tile("SAND_WALL_N_S_W_E");
  REQUIRE(sand);
  CHECK(idx.page(sand->page)->name == "WALL_SAND");
  CHECK(idx.page(sand->page)->absPath.empty());
}

TEST_CASE("tile graphics: variants, frames, rectangles, pixel regions") {
  const AssetIndex idx = synthIndex();
  REQUIRE(idx.tileGraphics.count("STONE_WALL_N_S_W_E_1"));
  const SpriteRef* s = idx.tile("STONE_WALL_N_S_W_E_1");
  REQUIRE(s);
  CHECK(s->x == 0);
  CHECK(s->y == 7);
  CHECK(s->w == 1);
  const PixelRect px = idx.pixels(*s);
  CHECK(px.px == 0);
  CHECK(px.py == 224);
  CHECK(px.pw == 32);
  CHECK(px.ph == 32);
  // Multi-token line and trailing comment both parsed.
  CHECK(idx.tile("SAND_YELLOW_FLOOR_5") != nullptr);
  CHECK(idx.tile("MAGMA_1") != nullptr);
  // FIRE:1 and FIRE:2 are two variants of one name; BOULDER has two.
  CHECK(idx.tileGraphics.at("FIRE").size() == 2);
  CHECK(idx.tileGraphics.at("BOULDER").size() == 2);
  CHECK(idx.tile("BOULDER", 1)->x == 1);
  CHECK(idx.tile("BOULDER", 99)->x == 1);  // clamped
  const SpriteRef* snake = idx.tile("BEAST_SNAKE");
  REQUIRE(snake);
  CHECK(snake->x == 3);
  CHECK(snake->w == 3);
  CHECK(snake->h == 2);
  CHECK(idx.tile("NOPE") == nullptr);
}

TEST_CASE("plant graphics: grass, shrub, sapling, tree tiles, odd ids") {
  const AssetIndex idx = synthIndex();
  CHECK(idx.stats.plantGraphics == 6);
  CHECK(idx.stats.grassPlants == 3);
  CHECK(idx.stats.treePlants == 1);
  const PlantGraphics& mg = idx.plants.at("MEADOW-GRASS");
  CHECK(mg.grass[0].x == 0);
  CHECK(mg.grass[3].x == 3);
  CHECK(mg.grass[3].page == idx.pageIndex("GRASS"));
  CHECK(idx.plants.at("DOG'S TOOTH GRASS").grass[0].valid());
  CHECK_FALSE(idx.plants.at("DOG'S TOOTH GRASS").grass[1].valid());
  CHECK(idx.plants.at("BAMBOO, HEDGE").grass[0].x == 1);
  const PlantGraphics& bb = idx.plants.at("BLUEBERRY");
  CHECK(bb.shrub.y == 53);
  CHECK(bb.shrubDead.x == 8);
  CHECK_FALSE(bb.sapling.valid());
  const PlantGraphics& oak = idx.plants.at("OAK");
  CHECK(oak.sapling.x == 5);
  CHECK(oak.treeTiles.empty());
  const PlantGraphics& sag = idx.plants.at("SAGUARO");
  CHECK(sag.treeTiles.at("TREE_TRUNK_PILLAR").x == 11);
  CHECK(sag.treeTiles.at("TREE_OVERLEAVES_HEAVY_BRANCH_E_AUTUMN:2").y == 6);
  CHECK(sag.treeTiles.size() == 3);
}

TEST_CASE("creature graphics: simple states, child parents, large images, layered, castes") {
  const AssetIndex idx = synthIndex();
  CHECK(idx.stats.creatureGraphics == 5);
  CHECK(idx.stats.creatureSimple == 3);  // DOG, CAT, GIANT_SLOTH
  CHECK(idx.stats.creatureLayered == 1);
  CHECK(idx.stats.creatureCastes == 1);
  const CreatureGraphics& dog = idx.creatures.at("DOG");
  CHECK(dog.states.at("DEFAULT").x == 0);
  CHECK(dog.states.at("DEFAULT").y == 6);
  CHECK(dog.states.at("CHILD").x == 1);            // child of DEFAULT
  CHECK(dog.states.at("CHILD:ANIMATED").x == 3);
  CHECK(dog.states.at("CHILD:CORPSE").x == 11);
  CHECK(dog.states.at("TRAINED_WAR").x == 4);
  CHECK(dog.states.at("CORPSE").x == 10);
  CHECK_FALSE(dog.layered);
  const SpriteRef& sloth = idx.creatures.at("GIANT_SLOTH").states.at("DEFAULT");
  CHECK(sloth.w == 3);
  CHECK(sloth.h == 2);
  CHECK(sloth.page == idx.pageIndex("CREATURES_SURFACE_GIANT"));
  const CreatureGraphics& dwarf = idx.creatures.at("DWARF");
  CHECK(dwarf.layered);
  CHECK(dwarf.states.count("DEFAULT") == 0);
  CHECK(dwarf.states.count("BP_APPEARANCE_MODIFIER_RANGE") == 0);
  CHECK(dwarf.states.count("LAYER") == 0);
  CHECK(dwarf.states.at("SKELETON_WITH_SKULL").x == 1);
  CHECK(idx.pageIndex("HEIGHT") < 0);  // no placeholder page from layer tokens
  // Statue rectangles never shadow the creature sprite.
  CHECK(dog.states.at("DEFAULT").page == idx.pageIndex("CREATURES_DOMESTIC"));
  CHECK(idx.creatureCastes.at("BIRD_DUCK").states.at("DEFAULT").x == 0);  // first caste
  CHECK(idx.creatures.at("BIRD_CARDINAL").states.count("VERMIN") == 1);
  CHECK(idx.creatures.at("BIRD_CARDINAL").states.count("DEFAULT") == 0);
}

TEST_CASE("materials: template inheritance, overrides, colours, flags") {
  const AssetIndex idx = synthIndex();
  CHECK(idx.stats.colors == 6);
  CHECK(idx.colors.at("SCARLET") == Rgb{255, 36, 0});
  CHECK(idx.stats.materialTemplates == 5);
  CHECK(idx.stats.inorganics == 7);
  CHECK(idx.stats.plants == 2);
  // Template applies first, then the entry's own tokens.
  CHECK(idx.inorganics.at("PLAIN_STONE").solidColor == "GRAY");
  CHECK((idx.inorganics.at("PLAIN_STONE").flags & kMatStone) != 0);
  CHECK(idx.inorganics.at("GRANITE").solidColor == "CLEAR");
  CHECK(idx.inorganics.at("LIMESTONE").solidColor == "BEIGE");
  CHECK(idx.inorganics.at("RUBY").displayFg == 4);
  CHECK(idx.inorganics.at("RUBY").displayBg == 7);
  CHECK((idx.inorganics.at("RUBY").flags & kMatGem) != 0);
  CHECK((idx.inorganics.at("SAND_YELLOW").flags & kMatSand) != 0);
  CHECK((idx.inorganics.at("SAND_YELLOW").flags & kMatSoil) != 0);
  CHECK((idx.inorganics.at("IRON").flags & kMatMetal) != 0);
  // Token lookups.
  CHECK(idx.materialColor("INORGANIC:LIMESTONE") == Rgb{245, 245, 220});
  CHECK(idx.materialColor("INORGANIC:RUBY") == Rgb{255, 36, 0});
  CHECK(idx.materialColor("INORGANIC:GRANITE") == Rgb{128, 128, 128});  // CLEAR is a colour
  CHECK(idx.materialColorName("INORGANIC:GRANITE") == "CLEAR");
  CHECK(idx.materialColorName("INORGANIC:CLAY_LOAM") == "ECRU");
  CHECK_FALSE(idx.materialColor("INORGANIC:CLAY_LOAM").has_value());  // ECRU has no RGB here
  CHECK(idx.materialColorName("INORGANIC:NOPE").empty());
  // Palette: first block wins, rows by colour id.
  REQUIRE(idx.palette.has_value());
  CHECK(idx.palette->name == "DEFAULT");
  CHECK(idx.palette->absPath == "/synth/mod/graphics/images/palettes.png");
  CHECK(idx.palette->defaultRow == 0);
  CHECK(idx.palette->rows.size() == 6);
  CHECK(idx.paletteRow("BEIGE") == 8);
  CHECK(idx.paletteRow("CLEAR") == 25);
  CHECK(idx.paletteRow("ECRU") == -1);
  CHECK(idx.paletteRow("") == -1);
  CHECK_FALSE(idx.materialColor("INORGANIC:NOPE").has_value());
  CHECK_FALSE(idx.materialColor("WATER").has_value());
  CHECK(idx.materialColor("PLANT:OAK:WOOD") == Rgb{165, 42, 42});
  CHECK(idx.materialColor("PLANT:OAK:STRUCTURAL") == Rgb{150, 75, 0});
  CHECK((idx.materialFlags("PLANT:OAK:WOOD") & kMatWood) != 0);
  CHECK(idx.materialFlags("PLANT:MEADOW-GRASS:STRUCTURAL") == 0);
  CHECK(AssetIndex::materialRawId("PLANT:DOG'S TOOTH GRASS:STRUCTURAL") == "DOG'S TOOTH GRASS");
  CHECK(AssetIndex::materialRawId("INORGANIC:GRANITE") == "GRANITE");
  CHECK(AssetIndex::materialRawId("ASH") == "ASH");
}

TEST_CASE("ingest: files of unconsumed object types are skipped, not errors") {
  AssetIndex idx;
  CHECK(ingestRawText(idx, "x\n[OBJECT:CREATURE]\n[CREATURE:DOG]\n", "/g", "c", nullptr) == 0);
  CHECK(idx.stats.rawFiles == 1);
  std::vector<std::string> diag;
  ingestRawText(idx, "[OBJECT:GRAPHICS]\n[TILE_GRAPHICS:P:a:b:NAME]\n", "/g", "bad.txt", &diag);
  REQUIRE(diag.size() == 1);
  CHECK(diag[0].find("bad.txt:2") == 0);
}

// --- resolver ---

TEST_CASE("resolver: walls by kind, flags and material, with tint rules") {
  using S = wm::TileShape;
  using M = wm::MaterialKind;
  const AssetIndex idx = synthIndex();
  auto r = resolveTerrain(idx, q(S::Wall, M::Stone, "INORGANIC:LIMESTONE", FaceSide::Side));
  CHECK(r.found);
  CHECK(r.sprite == *idx.tile("STONE_WALL_N_S_W_E_1"));
  CHECK(r.tinted);
  CHECK(r.tint == Rgb{245, 245, 220});
  CHECK(r.colorName == "BEIGE");
  CHECK(r.paletteRow == 8);
  CHECK(r.fill);
  CHECK_FALSE(r.cutout);
  CHECK(std::string(r.rule) == "wall.stone");
  // Granite is CLEAR: a real palette row in v50, not "as is".
  r = resolveTerrain(idx, q(S::Wall, M::Stone, "INORGANIC:GRANITE"));
  CHECK(r.found);
  CHECK(r.colorName == "CLEAR");
  CHECK(r.paletteRow == 25);
  r = resolveTerrain(idx, q(S::Wall, M::Stone, "INORGANIC:LIMESTONE", FaceSide::Side,
                            FaceKind::Terrain, wm::kTileSmooth));
  CHECK(r.sprite == *idx.tile("SMOOTHED_STONE_WALL_N_S_W_E"));
  r = resolveTerrain(idx, q(S::Wall, M::Stone, "INORGANIC:LIMESTONE", FaceSide::Side,
                            FaceKind::Terrain, wm::kTileSmooth | wm::kTileEngraved));
  CHECK(r.sprite == *idx.tile("ENGRAVED_STONE_WALL_N_S_W_E"));
  CHECK(resolveTerrain(idx, q(S::Wall, M::Mineral, "INORGANIC:IRON")).sprite ==
        *idx.tile("ORE_VEIN_WALL_N_S_W_E"));
  r = resolveTerrain(idx, q(S::Wall, M::Gem, "INORGANIC:RUBY"));
  CHECK(r.sprite == *idx.tile("GEM_A_WALL_N_S_W_E"));
  CHECK(r.tint == Rgb{255, 36, 0});
  r = resolveTerrain(idx, q(S::Wall, M::Soil, "INORGANIC:CLAY_LOAM"));
  CHECK(r.sprite == *idx.tile("SOIL_WALL_N_S_W_E_1"));
  CHECK(r.colorName == "ECRU");  // soil is recoloured like everything else
  CHECK(r.paletteRow == -1);     // ...but ECRU has no row in the synthetic palette
  CHECK_FALSE(r.tinted);
  r = resolveTerrain(idx, q(S::Wall, M::Soil, "INORGANIC:SAND_YELLOW"));
  CHECK(r.sprite == *idx.tile("SAND_Y_WALL_N_S_W_E"));
  CHECK(std::string(r.rule) == "wall.sand");
  r = resolveTerrain(idx, q(S::Wall, M::Constructed, "PLANT:OAK:WOOD"));
  CHECK(r.sprite == *idx.tile("WOODEN_WALL_N_S_W_E"));
  r = resolveTerrain(idx, q(S::Wall, M::Constructed, "INORGANIC:IRON"));
  CHECK(r.sprite == *idx.tile("REINFORCED_METAL_WALL_N_S_W_E"));
  r = resolveTerrain(idx, q(S::Wall, M::Constructed, "INORGANIC:LIMESTONE"));
  CHECK(r.sprite == *idx.tile("ROCK_BLOCKS_WALL_N_S_W_E"));
  CHECK(r.paletteRow == 8);
  r = resolveTerrain(idx, q(S::Wall, M::Constructed, "PLANT:OAK:WOOD"));
  CHECK(r.paletteRow == 6);  // AUBURN: oak walls are auburn in DF too
  r = resolveTerrain(idx, q(S::Unknown, M::Unknown, ""));
  CHECK(r.found);
  CHECK(std::string(r.rule) == "wall.unknown->stone");
  CHECK_FALSE(r.tinted);
  CHECK(r.colorName.empty());
  CHECK(r.paletteRow == -1);
  CHECK(r.fill);
  // Ice tiles are not in the synthetic set: found=false, rule says why.
  r = resolveTerrain(idx, q(S::Wall, M::Ice, "WATER"));
  CHECK_FALSE(r.found);
  CHECK(std::string(r.rule) == "missing-tile");
}

TEST_CASE("resolver: wall tops expose edges and retain all diagonal corners on one texture") {
  using S = wm::TileShape;
  using M = wm::MaterialKind;
  const AssetIndex idx = synthIndex();
  CHECK(wallVariantSuffix(0) == "N_S_W_E");
  CHECK(wallVariantSuffix(kWallW | kWallE) == "N_S");
  CHECK(wallVariantSuffix(kWallN | kWallS) == "W_E");
  CHECK(wallVariantSuffix(255).empty());
  CHECK(wallTopSuffixes(255).empty());
  CHECK(wallTopSuffixes(0) == std::vector<std::string>{"N_S_W_E"});
  CHECK(wallTopSuffixes(kWallN | kWallS | kWallW | kWallE) ==
        std::vector<std::string>{"NW", "NE", "SW", "SE"});
  CHECK(wallTopSuffixes(kWallS | kWallW) == std::vector<std::string>{"N_E", "SW"});
  CHECK(wallTopSuffixes(kWallN | kWallS | kWallW) ==
        std::vector<std::string>{"E", "NW", "SW"});
  for (int mask = 0; mask < 256; ++mask) {
    const auto layers = wallTopSuffixes(static_cast<uint8_t>(mask));
    CHECK(layers.size() <= 4);
    CHECK(std::set<std::string>(layers.begin(), layers.end()).size() == layers.size());
  }
  auto top = [&](uint8_t walls, uint8_t flags = 0) {
    TerrainQuery t = q(S::Wall, M::Stone, "INORGANIC:LIMESTONE", FaceSide::Top,
                       FaceKind::Terrain, flags);
    t.walls = walls;
    return resolveTerrain(idx, t);
  };
  const auto horizontal = top(kWallW | kWallE);
  REQUIRE(horizontal.layeredWall);
  REQUIRE(horizontal.wallLayers.size() == 1);
  CHECK(horizontal.wallLayers[0] == *idx.tile("STONE_WALL_N_S_1"));
  CHECK(horizontal.paletteRow == 8);
  CHECK(horizontal.fill);
  CHECK(top(kWallN | kWallS).wallLayers[0] == *idx.tile("STONE_WALL_W_E_1"));
  CHECK(top(kWallW | kWallE, wm::kTileSmooth).wallLayers[0] == *idx.tile("SMOOTHED_STONE_WALL_N_S"));
  const auto enclosed = top(255);
  CHECK(enclosed.found);
  CHECK(enclosed.layeredWall);
  CHECK(enclosed.wallLayers.empty());
  // The synthetic install omits SW. Never silently drop a required corner.
  const auto incomplete = top(kWallS | kWallW);
  CHECK_FALSE(incomplete.layeredWall);
  CHECK(incomplete.wallLayers.empty());
  CHECK(incomplete.sprite == *idx.tile("STONE_WALL_N_S_W_E_1"));
  TerrainQuery side = q(S::Wall, M::Stone, "INORGANIC:LIMESTONE", FaceSide::Side);
  side.walls = kWallN;
  CHECK_FALSE(resolveTerrain(idx, side).layeredWall);
  CHECK(resolveTerrain(idx, side).sprite == *idx.tile("STONE_WALL_N_S_W_E_1"));
  side.side = FaceSide::Bottom;
  CHECK_FALSE(resolveTerrain(idx, side).layeredWall);
  TerrainQuery unk = q(S::Unknown, M::Unknown, "", FaceSide::Top);
  unk.walls = kWallN | kWallS;
  CHECK(resolveTerrain(idx, unk).wallLayers[0] == *idx.tile("STONE_WALL_W_E_1"));
  TerrainQuery fort = q(S::Fortification, M::Stone, "INORGANIC:LIMESTONE", FaceSide::Top);
  CHECK_FALSE(resolveTerrain(idx, fort).layeredWall);
}

TEST_CASE("native Chantmansion wall topology: all 76 exposed stone, soil and constructed samples") {
  // Captured from native DF 53.16. Every
  // expected layer set has alpha-exact agreement with DF's runtime surface.
  std::istringstream input(readData("wall_topology_chantmansion.txt"));
  int x, y, z, mask, count = 0;
  std::string expected;
  while (input >> x >> y >> z >> mask >> expected) {
    CAPTURE(x); CAPTURE(y); CAPTURE(z); CAPTURE(mask);
    std::string actual;
    for (const auto& layer : wallTopSuffixes(static_cast<uint8_t>(mask))) {
      if (!actual.empty()) actual += ',';
      actual += layer;
    }
    CHECK((actual.empty() ? "-" : actual) == expected);
    ++count;
  }
  CHECK(count == 76);
}

TEST_CASE("resolver: floors, grass species, ramps, stairs, features, liquids") {
  using S = wm::TileShape;
  using M = wm::MaterialKind;
  const AssetIndex idx = synthIndex();
  auto r = resolveTerrain(idx, q(S::Floor, M::Stone, "INORGANIC:LIMESTONE"));
  CHECK(r.sprite == *idx.tile("STONE_FLOOR_5"));
  CHECK(r.paletteRow == 8);
  CHECK(r.fill);
  r = resolveTerrain(idx, q(S::Floor, M::Stone, "INORGANIC:LIMESTONE", FaceSide::Top,
                            FaceKind::Terrain, wm::kTileSmooth));
  CHECK(r.sprite == *idx.tile("SMOOTH_FLOOR"));
  // Grass: the species' own GRASS_1 beats the generic floor tile.
  r = resolveTerrain(idx, q(S::Floor, M::Grass, "PLANT:MEADOW-GRASS:STRUCTURAL"));
  CHECK(r.sprite == idx.plants.at("MEADOW-GRASS").grass[0]);
  CHECK(std::string(r.rule) == "floor.grass.species");
  CHECK(r.colorName == "BROWN");  // STRUCTURAL template colour; grass art is unkeyed
  CHECK(r.paletteRow == -1);
  CHECK(r.fill);
  r = resolveTerrain(idx, q(S::Floor, M::Grass, "PLANT:UNKNOWN GRASS:STRUCTURAL"));
  CHECK(r.sprite == *idx.tile("GRASS_5"));
  CHECK(std::string(r.rule) == "floor.grass.generic");
  CHECK(resolveTerrain(idx, q(S::Floor, M::Soil, "INORGANIC:SAND_YELLOW")).sprite ==
        *idx.tile("SAND_YELLOW_FLOOR_5"));
  CHECK(resolveTerrain(idx, q(S::Floor, M::Constructed, "PLANT:OAK:WOOD")).sprite ==
        *idx.tile("WOOD_FLOOR"));
  CHECK(resolveTerrain(idx, q(S::Floor, M::Constructed, "INORGANIC:IRON")).sprite ==
        *idx.tile("METAL_FLOOR"));
  CHECK(resolveTerrain(idx, q(S::Floor, M::Constructed, "INORGANIC:LIMESTONE")).sprite ==
        *idx.tile("FLOOR_STONE_BLOCK"));
  // Ramp: the slope takes DF's ramp art for the wedge's high side
  // (`<K>_RAMP_WITH_WALL_<D>`), a lone ramp's top `<K>_RAMP_OTHER`, the
  // sides the wall; a direction whose tile the install lacks falls back to
  // the floor family (the synthetic raws have no SOIL_RAMP tiles).
  using SD = SlopeDir;
  r = resolveTerrain(idx, q(S::Ramp, M::Stone, "INORGANIC:LIMESTONE", FaceSide::Slope,
                            FaceKind::Terrain, 0, SD::North));
  CHECK(r.sprite == *idx.tile("STONE_RAMP_WITH_WALL_N"));
  CHECK(std::string(r.rule) == "ramp.stone");
  CHECK(r.paletteRow == 8);  // colourised like every opaque face (a no-op on the unkeyed page)
  CHECK(r.fill);
  CHECK(resolveTerrain(idx, q(S::Ramp, M::Stone, "INORGANIC:LIMESTONE", FaceSide::Slope,
                              FaceKind::Terrain, 0, SD::South)).sprite ==
        *idx.tile("STONE_RAMP_WITH_WALL_S"));
  CHECK(resolveTerrain(idx, q(S::Ramp, M::Mineral, "INORGANIC:HEMATITE", FaceSide::Slope,
                              FaceKind::Terrain, 0, SD::East)).sprite ==
        *idx.tile("STONE_RAMP_WITH_WALL_E"));
  CHECK(resolveTerrain(idx, q(S::Ramp, M::Constructed, "INORGANIC:LIMESTONE", FaceSide::Slope,
                              FaceKind::Terrain, 0, SD::West)).sprite ==
        *idx.tile("STONE_RAMP_WITH_WALL_W"));
  r = resolveTerrain(idx, q(S::Ramp, M::Stone, "INORGANIC:LIMESTONE", FaceSide::Top));
  CHECK(r.sprite == *idx.tile("STONE_RAMP_OTHER"));  // lone ramp: flat top
  r = resolveTerrain(idx, q(S::Ramp, M::Stone, "INORGANIC:LIMESTONE", FaceSide::Side,
                            FaceKind::Terrain, 0, SD::North));
  CHECK(r.sprite == *idx.tile("STONE_WALL_N_S_W_E_1"));
  CHECK(std::string(r.rule) == "ramp.side->wall");
  r = resolveTerrain(idx, q(S::Ramp, M::Grass, "PLANT:MEADOW-GRASS:STRUCTURAL", FaceSide::Slope,
                            FaceKind::Terrain, 0, SD::South));
  CHECK(r.sprite == *idx.tile("GRASS_RAMP_WITH_WALL_S"));
  CHECK(std::string(r.rule) == "ramp.grass");
  r = resolveTerrain(idx, q(S::Ramp, M::Soil, "INORGANIC:SAND_YELLOW", FaceSide::Slope,
                            FaceKind::Terrain, 0, SD::North));
  CHECK(r.sprite == *idx.tile("SAND_YELLOW_RAMP_WITH_WALL_N"));
  CHECK(std::string(r.rule) == "ramp.sand");
  // Fallbacks: a missing direction tile (GRASS has only S) -> the species
  // grass; a family the install lacks (SOIL_RAMP) -> the floor.
  r = resolveTerrain(idx, q(S::Ramp, M::Grass, "PLANT:MEADOW-GRASS:STRUCTURAL", FaceSide::Slope,
                            FaceKind::Terrain, 0, SD::North));
  CHECK(std::string(r.rule) == "ramp.grass.species");
  r = resolveTerrain(idx, q(S::Ramp, M::Soil, "INORGANIC:CLAY", FaceSide::Slope,
                            FaceKind::Terrain, 0, SD::North));
  CHECK(r.sprite == *idx.tile("DIRT_FLOOR_5"));
  CHECK(std::string(r.rule) == "ramp.slope->floor");
  // Stairs: slab is floor; the full-tile feature preserves sprite alpha.
  r = resolveTerrain(idx, q(S::StairUpDown, M::Stone, "INORGANIC:LIMESTONE"));
  CHECK(r.sprite == *idx.tile("STONE_FLOOR_5"));
  r = resolveTerrain(idx, q(S::StairUp, M::Stone, "INORGANIC:LIMESTONE", FaceSide::Top,
                            FaceKind::Feature));
  CHECK(r.sprite == *idx.tile("STONE_STAIR_UP"));
  CHECK(r.paletteRow == 8);
  CHECK(r.cutout);
  CHECK_FALSE(r.fill);
  r = resolveTerrain(idx, q(S::StairDown, M::Stone, "INORGANIC:LIMESTONE", FaceSide::Side,
                            FaceKind::Feature));
  CHECK(r.sprite == *idx.tile("STONE_WALL_N_S_W_E_1"));
  r = resolveTerrain(idx, q(S::StairUp, M::Grass, "PLANT:MEADOW-GRASS:STRUCTURAL", FaceSide::Top,
                            FaceKind::Feature));
  CHECK(r.sprite == *idx.tile("GRASS_STAIR_UP"));
  // Boulders take the material tint; branches / shrubs / saplings are cutouts.
  r = resolveTerrain(idx, q(S::Boulder, M::Stone, "INORGANIC:RUBY", FaceSide::Top, FaceKind::Feature));
  CHECK(r.sprite == *idx.tile("BOULDER"));
  CHECK(r.paletteRow == 94);
  CHECK(r.fill);
  r = resolveTerrain(idx, q(S::TreeBranch, M::Wood, "PLANT:OAK:WOOD", FaceSide::Cross,
                            FaceKind::Feature));
  CHECK(r.sprite == *idx.tile("TREE_TWIGS_FULL"));
  CHECK(r.cutout);
  CHECK_FALSE(r.fill);
  CHECK(r.paletteRow == 6);  // oak wood: AUBURN
  CHECK(std::string(r.rule) == "feature.branch.default");
  r = resolveTerrain(idx, q(S::TreeBranch, M::Wood, "PLANT:SAGUARO:WOOD", FaceSide::Cross,
                            FaceKind::Feature));
  CHECK(r.sprite == idx.plants.at("SAGUARO").treeTiles.at("TREE_TWIGS_FULL"));
  CHECK(std::string(r.rule) == "feature.branch.species");
  // Each leaf shell face uses identical original art with alpha preserved.
  for (auto side : {FaceSide::Top, FaceSide::Bottom, FaceSide::Side}) {
    const auto leaf = resolveTerrain(idx, q(S::TreeBranch, M::Wood, "PLANT:OAK:WOOD",
                                           side, FaceKind::Feature));
    CHECK(leaf.sprite == *idx.tile("TREE_TWIGS_FULL"));
    CHECK(leaf.cutout);
    CHECK_FALSE(leaf.fill);
  }
  // Trunk cubes: cross-section on top, bark on the sides.
  CHECK(resolveTerrain(idx, q(S::TreeTrunk, M::Wood, "PLANT:OAK:WOOD", FaceSide::Top)).sprite ==
        *idx.tile("TREE_TRUNK_PILLAR"));
  CHECK(resolveTerrain(idx, q(S::TreeTrunk, M::Wood, "PLANT:OAK:WOOD", FaceSide::Side)).sprite ==
        *idx.tile("TREE_TRUNK_THICK_INTERIOR"));
  CHECK(resolveTerrain(idx, q(S::TreeTrunk, M::Wood, "PLANT:SAGUARO:WOOD", FaceSide::Side)).rule ==
        std::string("trunk.species"));
  r = resolveTerrain(idx, q(S::Shrub, M::Plant, "PLANT:BLUEBERRY:STRUCTURAL", FaceSide::Cross,
                            FaceKind::Feature));
  CHECK(r.sprite == idx.plants.at("BLUEBERRY").shrub);
  CHECK(r.cutout);
  r = resolveTerrain(idx, q(S::Shrub, M::Plant, "PLANT:NOPE:STRUCTURAL", FaceSide::Cross,
                            FaceKind::Feature));
  CHECK(r.sprite == *idx.tile("SHRUB"));
  r = resolveTerrain(idx, q(S::Sapling, M::Plant, "PLANT:OAK:STRUCTURAL", FaceSide::Cross,
                            FaceKind::Feature));
  CHECK(r.sprite == idx.plants.at("OAK").sapling);
  // Shrub slab under the cross is a floor.
  CHECK(resolveTerrain(idx, q(S::Shrub, M::Plant, "PLANT:BLUEBERRY:STRUCTURAL")).sprite ==
        *idx.tile("DIRT_FLOOR_5"));
  // Liquids.
  TerrainQuery lq = q(S::Floor, M::Stone, "INORGANIC:LIMESTONE", FaceSide::Top, FaceKind::Liquid);
  lq.liquid = wm::LiquidKind::Water;
  r = resolveTerrain(idx, lq);
  CHECK(r.sprite == *idx.tile("WATER"));
  CHECK_FALSE(r.tinted);
  CHECK_FALSE(r.fill);
  CHECK(r.paletteRow == -1);
  lq.liquid = wm::LiquidKind::Magma;
  CHECK(resolveTerrain(idx, lq).sprite == *idx.tile("MAGMA_1"));
  // Nothing for empty air.
  r = resolveTerrain(idx, q(S::Empty, M::None, ""));
  CHECK_FALSE(r.found);
  CHECK(std::string(r.rule) == "no-geometry");
}

TEST_CASE("resolver: creatures") {
  const AssetIndex idx = synthIndex();
  auto r = resolveCreature(idx, "DOG");
  CHECK(r.found);
  CHECK(r.sprite.x == 0);
  CHECK(r.sprite.y == 6);
  CHECK(std::string(r.rule) == "creature");
  CHECK(resolveCreature(idx, "DOG", CreatureState::Child).sprite.x == 1);
  CHECK(resolveCreature(idx, "DOG", CreatureState::TrainedWar).sprite.x == 4);
  r = resolveCreature(idx, "DOG", CreatureState::TrainedHunter);  // absent -> DEFAULT
  CHECK(r.found);
  CHECK(r.sprite.x == 0);
  CHECK(std::string(r.rule) == "default-fallback");
  r = resolveCreature(idx, "GIANT_SLOTH");
  CHECK(r.sprite.w == 3);
  r = resolveCreature(idx, "BIRD_DUCK");
  CHECK(r.found);
  CHECK(std::string(r.rule) == "caste");
  r = resolveCreature(idx, "DWARF");
  CHECK_FALSE(r.found);
  CHECK(r.layered);
  CHECK(std::string(r.rule) == "layered");
  r = resolveCreature(idx, "BIRD_CARDINAL");
  CHECK_FALSE(r.found);
  CHECK(std::string(r.rule) == "no-default");
  r = resolveCreature(idx, "UNICORN_OF_NOWHERE");
  CHECK_FALSE(r.found);
  CHECK(std::string(r.rule) == "unknown-species");
}

// --- cache ---

TEST_CASE("cache: serialise / deserialise round trip and key checks") {
  AssetIndex idx = synthIndex();
  idx.buildId = "24557528";
  idx.contentHash = 0x0123456789abcdefull;
  const std::string text = serializeIndex(idx);
  std::string b;
  uint64_t h = 0;
  REQUIRE(peekIndexKey(text, b, h));
  CHECK(b == "24557528");
  CHECK(h == 0x0123456789abcdefull);
  AssetIndex back;
  std::string err;
  REQUIRE_MESSAGE(deserializeIndex(text, back, err), err);
  CHECK(back.pages.size() == idx.pages.size());
  CHECK(back.pageByName == idx.pageByName);
  CHECK(back.tileGraphics.size() == idx.tileGraphics.size());
  CHECK(back.tile("STONE_WALL_N_S_W_E_1")->y == 7);
  CHECK(back.tileGraphics.at("BOULDER").size() == 2);
  CHECK(back.plants.at("SAGUARO").treeTiles == idx.plants.at("SAGUARO").treeTiles);
  CHECK(back.plants.at("MEADOW-GRASS").grass == idx.plants.at("MEADOW-GRASS").grass);
  CHECK(back.creatures.at("DOG").states == idx.creatures.at("DOG").states);
  CHECK(back.creatures.at("DWARF").layered);
  CHECK(back.creatureCastes.at("BIRD_DUCK").states.at("DEFAULT").x == 0);
  CHECK(back.colors == idx.colors);
  CHECK(back.inorganics.at("RUBY").solidColor == "SCARLET");
  CHECK(back.inorganics.at("RUBY").flags == idx.inorganics.at("RUBY").flags);
  CHECK(back.plantMaterials.at("OAK").at("WOOD").solidColor == "AUBURN");
  REQUIRE(back.palette.has_value());
  CHECK(back.palette->rows == idx.palette->rows);
  CHECK(back.palette->absPath == idx.palette->absPath);
  CHECK(back.stats.creatureSimple == idx.stats.creatureSimple);
  CHECK(back.stats.tileGraphics == idx.stats.tileGraphics);
  // Same output for the same index (deterministic enough to diff keys).
  CHECK(serializeIndex(back).size() == text.size());
  // Corrupt / foreign inputs.
  CHECK_FALSE(peekIndexKey("hello\n", b, h));
  const auto header=text.substr(0,text.find('\n')+1);
  CHECK_FALSE(deserializeIndex(header+"bogus\t1\n", back, err));
  CHECK(err.find("unknown record") != std::string::npos);
  CHECK_FALSE(deserializeIndex(header+"tile\tNAME\tnotanumber\n", back, err));
}

// --- provider over a synthetic install tree ---

namespace {

struct TempInstall {
  fs::path root;
  TempInstall() {
    root = fs::temp_directory_path() / ("df3d_assets_test_" + std::to_string(std::rand()));
    const fs::path mod = root / "data" / "vanilla";
    fs::create_directories(mod / "env" / "graphics");
    fs::create_directories(mod / "mats" / "objects");
    copy("tile_page_test.txt", mod / "env" / "graphics" / "tile_page_test.txt");
    copy("tile_page_late_test.txt", mod / "env" / "graphics" / "tile_page_late.txt");
    copy("graphics_tiles_test.txt", mod / "env" / "graphics" / "graphics_tiles.txt");
    copy("graphics_plants_test.txt", mod / "env" / "graphics" / "graphics_plants.txt");
    copy("graphics_creatures_test.txt", mod / "env" / "graphics" / "graphics_creatures.txt");
    copy("descriptor_color_test.txt", mod / "mats" / "objects" / "descriptor_color.txt");
    copy("material_template_test.txt", mod / "mats" / "objects" / "material_template.txt");
    copy("palette_test.txt", mod / "env" / "graphics" / "palette_default.txt");
    copy("inorganic_test.txt", mod / "mats" / "objects" / "inorganic.txt");
    copy("plant_test.txt", mod / "mats" / "objects" / "plant.txt");
  }
  void copy(const char* name, const fs::path& to) {
    std::ofstream(to, std::ios::binary) << readData(name);
  }
  ~TempInstall() {
    std::error_code ec;
    fs::remove_all(root, ec);
  }
};

}  // namespace

TEST_CASE("provider: synthetic install, cache miss then hit, key mismatch regenerates") {
  TempInstall ti;
  const std::string root = ti.root.generic_string();
  const auto files = listRawFiles(root);
  CHECK(files.size() == 10);
  CHECK(files.front().find("data/vanilla/") == 0);
  const uint64_t h1 = contentHashOf(root, files);
  CHECK(h1 != 0);

  ProviderOptions po;
  po.installOverride = root;
  po.cacheDir = (ti.root / "cache").generic_string();
  std::string err;
  // No manifest and no exe: build verification fails loudly by default.
  CHECK(openProvider(po, err) == nullptr);
  CHECK(err.find("Cannot verify") != std::string::npos);

  po.allowBuildMismatch = true;
  auto p = openProvider(po, err);
  REQUIRE_MESSAGE(p != nullptr, err);
  CHECK(p->buildMismatch);
  CHECK_FALSE(p->cacheHit);
  CHECK(p->index.contentHash == h1);
  CHECK(p->index.buildId == "nomanifest");
  CHECK(p->index.tile("STONE_WALL_N_S_W_E_1") != nullptr);
  CHECK(p->index.creatures.count("DOG") == 1);
  CHECK(fs::exists(p->cachePath));
  // Pages resolve to absolute paths under the install.
  const TilePage* ws = p->index.page(p->index.pageIndex("WALL_STONE"));
  REQUIRE(ws);
  CHECK(ws->absPath == root + "/data/vanilla/env/graphics/images/wall_stone.png");

  auto p2 = openProvider(po, err);
  REQUIRE(p2 != nullptr);
  CHECK(p2->cacheHit);
  CHECK(p2->index.tileGraphics.size() == p->index.tileGraphics.size());
  CHECK(p2->index.stats.inorganics == p->index.stats.inorganics);

  // Editing a raw changes the content hash: the old cache is not used.
  std::ofstream(ti.root / "data" / "vanilla" / "env" / "graphics" / "graphics_tiles.txt",
                std::ios::app)
      << "\n[TILE_GRAPHICS:FLOORS:8:8:EXTRA_TILE]\n";
  auto p3 = openProvider(po, err);
  REQUIRE(p3 != nullptr);
  CHECK_FALSE(p3->cacheHit);
  CHECK(p3->index.contentHash != h1);
  CHECK(p3->cachePath != p->cachePath);
  CHECK(p3->index.tile("EXTRA_TILE") != nullptr);

  // A cache file whose header key does not match its name is rejected.
  {
    std::string text = serializeIndex(p3->index);
    text.replace(text.find(p3->index.buildId), p3->index.buildId.size(), "otherbuild");
    std::ofstream(p3->cachePath, std::ios::binary) << text;
  }
  auto p4 = openProvider(po, err);
  REQUIRE(p4 != nullptr);
  CHECK_FALSE(p4->cacheHit);
  bool rejected = false;
  for (const auto& d : p4->diagnostics) rejected |= d.find("cache rejected") != std::string::npos;
  CHECK(rejected);
  CHECK(cacheFileName("24557528", 0xabcull) == "index_24557528_0000000000000abc.txt");
}

TEST_CASE("provider: the (size, mtime) manifest skips hashing; any stamp change or a rehash falls back") {
  TempInstall ti;
  const std::string root = ti.root.generic_string();
  const auto files = listRawFiles(root);
  const uint64_t h1 = contentHashOf(root, files);
  const auto stamps = stampRawFiles(root, files);
  REQUIRE(stamps.size() == files.size());
  CHECK(stamps.front().rel == files.front());
  CHECK(stamps.front().size > 0);
  CHECK(stamps.front().mtime != 0);
  // The walk's own stamps (what openProvider uses) agree with a stat pass.
  CHECK(listRawFileStamps(root) == stamps);

  // Pure round trip and the ways a manifest can fail to match.
  const std::string text = serializeManifest("nomanifest", h1, stamps);
  CHECK(text.rfind("DF3DAMF 1 nomanifest ", 0) == 0);
  uint64_t got = 0;
  CHECK(manifestMatches(text, "nomanifest", stamps, got));
  CHECK(got == h1);
  CHECK_FALSE(manifestMatches(text, "otherbuild", stamps, got));
  CHECK_FALSE(manifestMatches("", "nomanifest", stamps, got));
  CHECK_FALSE(manifestMatches("garbage\n", "nomanifest", stamps, got));
  {
    auto touched = stamps;
    touched[3].mtime += 1;
    CHECK_FALSE(manifestMatches(text, "nomanifest", touched, got));
    auto resized = stamps;
    resized[3].size += 1;
    CHECK_FALSE(manifestMatches(text, "nomanifest", resized, got));
    auto fewer = stamps;
    fewer.pop_back();
    CHECK_FALSE(manifestMatches(text, "nomanifest", fewer, got));
    auto renamed = stamps;
    renamed[0].rel += "x";
    CHECK_FALSE(manifestMatches(text, "nomanifest", renamed, got));
    // Extra trailing entries are a mismatch too.
    CHECK_FALSE(manifestMatches(text + "extra\t1\t2\n", "nomanifest", stamps, got));
  }

  ProviderOptions po;
  po.installOverride = root;
  po.cacheDir = (ti.root / "cache").generic_string();
  po.allowBuildMismatch = true;
  std::string err;
  // First start: no manifest, hash the contents, write index + manifest.
  auto p1 = openProvider(po, err);
  REQUIRE_MESSAGE(p1 != nullptr, err);
  CHECK_FALSE(p1->manifestHit);
  CHECK_FALSE(p1->cacheHit);
  CHECK(p1->index.contentHash == h1);
  const fs::path manifest = ti.root / "cache" / manifestFileName("nomanifest");
  CHECK(fs::exists(manifest));

  // Second start: stamps identical -> hash from the manifest, cache hit.
  auto p2 = openProvider(po, err);
  REQUIRE(p2 != nullptr);
  CHECK(p2->manifestHit);
  CHECK(p2->cacheHit);
  CHECK(p2->index.contentHash == h1);
  CHECK(p2->cachePath == p1->cachePath);

  // A touched file (new mtime, same content): manifest miss, the content
  // hash is recomputed and is unchanged, so the index cache still hits and
  // the manifest is refreshed.
  const fs::path tiles = ti.root / "data" / "vanilla" / "env" / "graphics" / "graphics_tiles.txt";
  fs::last_write_time(tiles, fs::last_write_time(tiles) + std::chrono::seconds(5));
  auto p3 = openProvider(po, err);
  REQUIRE(p3 != nullptr);
  CHECK_FALSE(p3->manifestHit);
  CHECK(p3->cacheHit);
  CHECK(p3->index.contentHash == h1);
  auto p3b = openProvider(po, err);
  REQUIRE(p3b != nullptr);
  CHECK(p3b->manifestHit);

  // An edit that changes the size: manifest miss, new hash, index rebuilt.
  std::ofstream(tiles, std::ios::app) << "\n[TILE_GRAPHICS:FLOORS:8:8:EXTRA_TILE]\n";
  auto p4 = openProvider(po, err);
  REQUIRE(p4 != nullptr);
  CHECK_FALSE(p4->manifestHit);
  CHECK_FALSE(p4->cacheHit);
  CHECK(p4->index.contentHash != h1);
  CHECK(p4->index.tile("EXTRA_TILE") != nullptr);
  auto p5 = openProvider(po, err);
  REQUIRE(p5 != nullptr);
  CHECK(p5->manifestHit);
  CHECK(p5->cacheHit);
  CHECK(p5->index.tile("EXTRA_TILE") != nullptr);

  // The documented blind spot: an edit that keeps size and mtime is
  // invisible to the manifest -- and `rehash` is the way through it.
  {
    const auto before = fs::last_write_time(tiles);
    std::string t, e;
    REQUIRE(readTextFile(tiles.generic_string(), t, e));
    const size_t at = t.find("EXTRA_TILE");
    REQUIRE(at != std::string::npos);
    t.replace(at, 10, "OTHER_TILE");  // same length
    std::ofstream(tiles, std::ios::binary | std::ios::trunc) << t;
    fs::last_write_time(tiles, before);
  }
  auto p6 = openProvider(po, err);
  REQUIRE(p6 != nullptr);
  CHECK(p6->manifestHit);  // stale by design
  CHECK(p6->index.tile("EXTRA_TILE") != nullptr);
  po.rehash = true;
  auto p7 = openProvider(po, err);
  REQUIRE(p7 != nullptr);
  CHECK_FALSE(p7->manifestHit);
  CHECK_FALSE(p7->cacheHit);
  CHECK(p7->index.tile("OTHER_TILE") != nullptr);
  CHECK(p7->index.tile("EXTRA_TILE") == nullptr);
  po.rehash = false;
  auto p8 = openProvider(po, err);  // the rehash rewrote the manifest
  REQUIRE(p8 != nullptr);
  CHECK(p8->manifestHit);
  CHECK(p8->index.tile("OTHER_TILE") != nullptr);

  // useCache off: neither manifest nor index cache is consulted.
  po.useCache = false;
  auto p9 = openProvider(po, err);
  REQUIRE(p9 != nullptr);
  CHECK_FALSE(p9->manifestHit);
  CHECK_FALSE(p9->cacheHit);
}

TEST_CASE("provider: install without the terrain vocabulary is refused") {
  TempInstall ti;
  fs::remove(ti.root / "data" / "vanilla" / "env" / "graphics" / "graphics_tiles.txt");
  ProviderOptions po;
  po.installOverride = ti.root.generic_string();
  po.cacheDir = (ti.root / "cache").generic_string();
  po.allowBuildMismatch = true;
  std::string err;
  CHECK(openProvider(po, err) == nullptr);
  CHECK(err.find("STONE_WALL_N_S_W_E_1") != std::string::npos);
}

TEST_CASE("interface layout selectors preserve each original widget cell across cache") {
  AssetIndex index;
  index.buildId = "synthetic-ui";
  ingestRawText(index, "[OBJECT:TILE_PAGE][TILE_PAGE:UI][FILE:ui.png][TILE_DIM:8:12][PAGE_DIM_PIXELS:128:128]", "/test", "page", nullptr);
  ingestRawText(index, "[OBJECT:GRAPHICS][TILE_GRAPHICS:UI:4:5:BUTTON_RECTANGLE:0:0][TILE_GRAPHICS:UI:5:5:BUTTON_RECTANGLE:1:0][TILE_GRAPHICS:UI:4:6:BUTTON_RECTANGLE:0:1][TILE_GRAPHICS:UI:5:6:BUTTON_RECTANGLE:1:1][TILE_GRAPHICS:UI:6:5:BUTTON_RECTANGLE_SELECTED:0:0]", "/test", "ui", nullptr);
  finalizeIndex(index);
  const auto* layout = index.layout("BUTTON_RECTANGLE");
  REQUIRE(layout);
  CHECK(layout->width == 2);
  CHECK(layout->height == 2);
  REQUIRE(layout->tile(-1,1,1));
  CHECK(layout->tile(-1,1,1)->x == 5);
  CHECK(layout->tile(-1,1,1)->y == 6);
  AssetIndex cached;
  std::string error;
  REQUIRE(deserializeIndex(serializeIndex(index), cached, error));
  REQUIRE(cached.layout("BUTTON_RECTANGLE"));
  CHECK(*cached.layout("BUTTON_RECTANGLE")->tile(-1,1,1) == *layout->tile(-1,1,1));
  REQUIRE(cached.layout("BUTTON_RECTANGLE_SELECTED"));
  CHECK(cached.layout("BUTTON_RECTANGLE_SELECTED")->tile(-1,0,0)->x == 6);
}
