// Tier 0: classic glyph rendering and the classic tile tables on
// procedural pixels and synthetic raw snippets: colors.txt / init FONT
// parsing, tileset discovery on a synthetic install tree, the renderer's
// keying and tinting, ASCII_GRAPHICS parsing and its cache round trip,
// and the item / building / creature glyph choices. No art is read.
#include <doctest.h>

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

#include "df3d_assets/asset_index.h"
#include "df3d_assets/classic_glyphs.h"
#include "df3d_assets/raw_tokens.h"

using namespace df3d::assets;
namespace fs = std::filesystem;

namespace {

std::string dataDir() { return std::string(DF3D_ASSETS_TEST_DIR) + "/data"; }

std::string readData(const char* name) {
  std::string text, err;
  REQUIRE_MESSAGE(readTextFile(dataDir() + "/" + name, text, err), err);
  return text;
}

// A 16x16 grid of 2x2 cells (32x32 px). Cell c has: (0,0) white, (1,0)
// half grey (128), (0,1) magenta key, (1,1) transparent -- except cell
// 219 which is fully white (the full block) and cell 0 which is all key.
RgbaImage makeSheet() {
  RgbaImage s = RgbaImage::blank(32, 32);
  for (int c = 0; c < 256; ++c) {
    const int x = (c % 16) * 2, y = (c / 16) * 2;
    if (c == 0) {
      for (int dy = 0; dy < 2; ++dy)
        for (int dx = 0; dx < 2; ++dx) s.set(x + dx, y + dy, Rgba{255, 0, 255, 255});
      continue;
    }
    if (c == 219) {
      for (int dy = 0; dy < 2; ++dy)
        for (int dx = 0; dx < 2; ++dx) s.set(x + dx, y + dy, Rgba{255, 255, 255, 255});
      continue;
    }
    s.set(x, y, Rgba{255, 255, 255, 255});
    s.set(x + 1, y, Rgba{128, 128, 128, 255});
    s.set(x, y + 1, Rgba{255, 0, 255, 255});
    s.set(x + 1, y + 1, Rgba{0, 0, 0, 0});
  }
  return s;
}

struct TempInstall {
  fs::path root;
  TempInstall() {
    root = fs::temp_directory_path() / ("df3d_glyph_test_" + std::to_string(std::rand()));
    fs::create_directories(root / "data" / "art");
    fs::create_directories(root / "data" / "init");
    fs::create_directories(root / "prefs");
  }
  ~TempInstall() {
    std::error_code ec;
    fs::remove_all(root, ec);
  }
  void write(const fs::path& rel, const std::string& text) {
    fs::create_directories((root / rel).parent_path());
    std::ofstream(root / rel) << text;
  }
};

}  // namespace

TEST_CASE("classic colours: colors.txt parses into DF's 16-colour order") {
  ClassicPalette p;
  CHECK(parseClassicColors(readData("colors_test.txt"), p) == 48);
  CHECK(p.complete());
  CHECK(p.colors[0] == Rgb{1, 2, 3});
  CHECK(p.colors[1] == Rgb{0, 0, 200});
  CHECK(p.colors[7] == Rgb{170, 170, 170});
  CHECK(p.colors[8] == Rgb{85, 85, 85});
  CHECK(p.colors[15] == Rgb{255, 255, 254});
  CHECK(p.color(4, 0) == Rgb{170, 0, 0});    // RED
  CHECK(p.color(4, 1) == Rgb{255, 85, 85});  // LRED
  CHECK(p.color(6, 1) == Rgb{255, 255, 85}); // YELLOW = bright BROWN
  CHECK(std::string(classicColorName(6)) == "BROWN");
  CHECK(std::string(classicColorName(14)) == "YELLOW");
  CHECK(std::string(classicColorName(16)).empty());

  ClassicPalette partial;
  CHECK(parseClassicColors("[RED_R:9][RED_G:8][RED_B:7][NOPE_R:1][GREEN_X:2][BLUE_R:x]", partial) == 3);
  CHECK(!partial.complete());
  CHECK(partial.colors[4] == Rgb{9, 8, 7});
  CHECK(parseClassicColors("[BLUE_R:999]", partial) == 1);
  CHECK(partial.colors[1].r == 255);  // clamped

  const ClassicPalette d = defaultClassicPalette();
  CHECK(d.complete());
  CHECK(d.colors[0] == Rgb{0, 0, 0});
  CHECK(d.colors[15] == Rgb{255, 255, 255});
  CHECK(d.colors[1] == Rgb{32, 125, 241});
}

TEST_CASE("classic tileset: init FONT parse and discovery order") {
  CHECK(parseInitFont("[WINDOWEDX:1200]\n[FONT:curses_640x300.png]\n[FULLFONT:big.png]") ==
        "curses_640x300.png");
  CHECK(parseInitFont("[FONT:a.png][FULLFONT:b.png]", "FULLFONT") == "b.png");
  CHECK(parseInitFont("no tokens here").empty());

  TempInstall inst;
  SUBCASE("nothing at all") {
    const ClassicTileset t = resolveClassicTileset(inst.root.string());
    CHECK(t.absPath.empty());
    CHECK(t.source == "none");
  }
  SUBCASE("fallback square tileset") {
    inst.write("data/art/curses_square_16x16.png", "x");
    const ClassicTileset t = resolveClassicTileset(inst.root.string());
    CHECK(t.file == "curses_square_16x16.png");
    CHECK(t.source == "fallback");
    CHECK(fs::exists(t.absPath));
  }
  SUBCASE("init_default names an existing font; prefs wins when its font exists") {
    inst.write("data/art/curses_square_16x16.png", "x");
    inst.write("data/art/curses_640x300.png", "x");
    inst.write("data/init/init_default.txt", "[FONT:curses_640x300.png]");
    ClassicTileset t = resolveClassicTileset(inst.root.string());
    CHECK(t.file == "curses_640x300.png");
    CHECK(t.source == "data/init/init_default.txt FONT");
    // prefs naming a missing file is skipped
    inst.write("prefs/init.txt", "[FONT:missing.png]");
    t = resolveClassicTileset(inst.root.string());
    CHECK(t.source == "data/init/init_default.txt FONT");
    inst.write("data/art/custom.png", "x");
    inst.write("prefs/init.txt", "[PRINT_MODE:STANDARD]\n[FONT:custom.png]");
    t = resolveClassicTileset(inst.root.string());
    CHECK(t.file == "custom.png");
    CHECK(t.source == "prefs/init.txt FONT");
  }
}

TEST_CASE("glyph renderer: keying, tinting, backgrounds, sheets") {
  GlyphRenderer r;
  std::string err;
  RgbaImage bad = RgbaImage::blank(30, 32);
  CHECK(!r.setTileset(bad, err));
  CHECK(!r.ready());
  CHECK(r.render(wm::Glyph{65, 7, 0, 0}).empty());
  REQUIRE(r.setTileset(makeSheet(), err));
  CHECK(r.ready());
  CHECK(r.tileW() == 2);
  CHECK(r.tileH() == 2);
  ClassicPalette p;
  parseClassicColors(readData("colors_test.txt"), p);
  r.setPalette(p);

  SUBCASE("foreground tint, key transparent on black background") {
    const RgbaImage g = r.render(wm::Glyph{65, 4, 0, 0});  // 'A' in RED (170,0,0)
    REQUIRE(g.width == 2);
    REQUIRE(g.height == 2);
    CHECK(g.get(0, 0) == Rgba{170, 0, 0, 255});
    // grey 128 * 170 / 255 = 85 (rounded)
    CHECK(g.get(1, 0) == Rgba{85, 0, 0, 255});
    CHECK(g.get(0, 1) == Rgba{0, 0, 0, 0});  // magenta key
    CHECK(g.get(1, 1) == Rgba{0, 0, 0, 0});  // transparent stays
  }
  SUBCASE("bright selects the upper eight; a coloured background fills the keys") {
    const RgbaImage g = r.render(wm::Glyph{65, 4, 1, 1});  // LRED on BLUE
    CHECK(g.get(0, 0) == Rgba{255, 85, 85, 255});
    CHECK(g.get(0, 1) == Rgba{0, 0, 200, 255});
    CHECK(g.get(1, 1) == Rgba{0, 0, 200, 255});
    // black background kept opaque on request
    const RgbaImage k = r.render(wm::Glyph{65, 7, 0, 0}, false);
    CHECK(k.get(0, 1) == Rgba{1, 2, 3, 255});
  }
  SUBCASE("the full block is solid colour; code point 0 is empty") {
    const RgbaImage b = r.render(wm::Glyph{219, 2, 0, 0});
    for (int y = 0; y < 2; ++y)
      for (int x = 0; x < 2; ++x) CHECK(b.get(x, y) == Rgba{0, 160, 0, 255});
    const RgbaImage z = r.render(wm::Glyph{0, 7, 0, 0});
    for (int y = 0; y < 2; ++y)
      for (int x = 0; x < 2; ++x) CHECK(z.get(x, y).a == 0);
  }
  SUBCASE("a sheet holds every code point's render in its cell") {
    const RgbaImage s = r.renderSheet(3, 0, 1);  // LCYAN
    REQUIRE(s.width == 32);
    REQUIRE(s.height == 32);
    for (int c : {1, 64, 219, 255}) {
      const RgbaImage one = r.render(wm::Glyph{static_cast<uint8_t>(c), 3, 0, 1});
      const int x0 = (c % 16) * 2, y0 = (c / 16) * 2;
      for (int y = 0; y < 2; ++y)
        for (int x = 0; x < 2; ++x) CHECK(s.get(x0 + x, y0 + y) == one.get(x, y));
    }
  }
  SUBCASE("isKey") {
    CHECK(GlyphRenderer::isKey(Rgba{255, 0, 255, 255}));
    CHECK(GlyphRenderer::isKey(Rgba{9, 9, 9, 0}));
    CHECK(!GlyphRenderer::isKey(Rgba{255, 0, 254, 255}));
    CHECK(!GlyphRenderer::isKey(Rgba{0, 0, 0, 255}));
  }
}

TEST_CASE("ASCII_GRAPHICS rows: parsing, quoted characters, first wins, cache round trip") {
  AssetIndex idx;
  std::vector<std::string> diag;
  ingestRawText(idx, readData("graphics_classic_test.txt"), "/synth/mod/graphics", "classic", &diag);
  finalizeIndex(idx);
  CHECK(idx.stats.asciiGraphics == 8);
  REQUIRE(idx.asciiGraphics.count("INTERFACE_BACKGROUND"));
  CHECK(idx.asciiGraphics.at("INTERFACE_BACKGROUND") == wm::Glyph{' ', 0, 0, 0});
  CHECK(idx.asciiGraphics.at("BORDER_TOP_LEFT") == wm::Glyph{218, 6, 0, 1});  // first cell wins
  CHECK(idx.asciiGraphics.at("BUTTON_CLOSE") == wm::Glyph{'X', 4, 0, 1});
  CHECK(idx.asciiGraphics.at("COLON_CELL") == wm::Glyph{':', 7, 0, 0});
  CHECK(idx.asciiGraphics.at("UNQUOTED_CELL") == wm::Glyph{'?', 3, 0, 1});
  CHECK(idx.asciiGraphics.at("BUILDING_ITEM_TASK") == wm::Glyph{'T', 3, 0, 1});
  CHECK(idx.asciiGraphics.at("ITEM_BAR") == wm::Glyph{'=', 6, 0, 1});
  CHECK(!idx.asciiGraphics.count("BUTTON_RECTANGLE"));  // ASCII_RECTANGLE ignored
  CHECK(!idx.asciiGraphics.count("MALFORMED"));
  bool malformedDiag = false;
  for (const std::string& d : diag) malformedDiag |= d.find("ASCII_GRAPHICS") != std::string::npos;
  CHECK(malformedDiag);

  idx.buildId = "test";
  const std::string text = serializeIndex(idx);
  AssetIndex back;
  std::string err;
  REQUIRE_MESSAGE(deserializeIndex(text, back, err), err);
  CHECK(back.asciiGraphics == idx.asciiGraphics);
  CHECK(back.stats.asciiGraphics == 8);
}

TEST_CASE("classic item glyphs: ascii row, material symbol, itemdef tile, creature tile, assumed table") {
  AssetIndex idx;
  ingestRawText(idx, readData("graphics_classic_test.txt"), "/synth/mod/graphics", "classic", nullptr);
  finalizeIndex(idx);
  wm::MaterialGlyph iron;
  iron.tile = 7;
  iron.itemSymbol = 0;
  iron.basicFg = 0;
  iron.basicBright = 1;
  iron.build = wm::Glyph{7, 4, 0, 1};
  wm::MaterialGlyph ruby;
  ruby.itemSymbol = 15;
  ruby.basicFg = 4;
  ruby.basicBright = 1;
  const uint8_t cauldron = 147;  // ITEM_TOOL_CAULDRON [TILE:147]
  wm::CreatureGlyph rat{wm::Glyph{'r', 6, 0, 0}, 'r'};

  SUBCASE("an install row names the kind: tile and colour come from it") {
    const ClassicGlyphChoice c = classicItemGlyph(idx, wm::ItemKind::Bar, &iron, 0, nullptr);
    CHECK(c.found);
    CHECK(c.tileSource == GlyphSource::AsciiGraphics);
    CHECK(c.glyph == wm::Glyph{'=', 6, 0, 1});
    CHECK(!c.materialColour);
  }
  SUBCASE("gems take the material's ITEM_SYMBOL and BASIC_COLOR") {
    const ClassicGlyphChoice c = classicItemGlyph(idx, wm::ItemKind::SmallGem, &ruby, 0, nullptr);
    CHECK(c.tileSource == GlyphSource::MaterialSymbol);
    CHECK(c.glyph == wm::Glyph{15, 4, 0, 1});
    CHECK(c.materialColour);
    // a cut gem is always 4 (measured); a boulder is the material's symbol
    const ClassicGlyphChoice d = classicItemGlyph(idx, wm::ItemKind::Gem, &ruby, 0, nullptr);
    CHECK(d.tileSource == GlyphSource::MeasuredTable);
    CHECK(d.glyph.tile == 4);
    const ClassicGlyphChoice b = classicItemGlyph(idx, wm::ItemKind::Boulder, &ruby, 0, nullptr);
    CHECK(b.tileSource == GlyphSource::MaterialSymbol);
    CHECK(b.glyph.tile == 15);
    // the default symbol 7 does not override a rough gem's 15
    wm::MaterialGlyph quartz = ruby;
    quartz.itemSymbol = 7;
    const ClassicGlyphChoice r = classicItemGlyph(idx, wm::ItemKind::Rough, &quartz, 0, nullptr);
    CHECK(r.tileSource == GlyphSource::MeasuredTable);
    CHECK(r.glyph.tile == 15);
  }
  SUBCASE("tools take the itemdef TILE; other kinds ignore it") {
    const ClassicGlyphChoice c = classicItemGlyph(idx, wm::ItemKind::Tool, &iron, cauldron, nullptr);
    CHECK(c.tileSource == GlyphSource::ItemDefTile);
    CHECK(c.glyph.tile == 147);
    CHECK(c.glyph.fg == 0);
    CHECK(c.glyph.bright == 1);
    const ClassicGlyphChoice w = classicItemGlyph(idx, wm::ItemKind::Weapon, &iron, cauldron, nullptr);
    CHECK(w.tileSource == GlyphSource::MeasuredTable);
    CHECK(w.glyph.tile == 47);
  }
  SUBCASE("vermin and pets draw the creature's tile in its colour") {
    const ClassicGlyphChoice c = classicItemGlyph(idx, wm::ItemKind::Vermin, &iron, 0, &rat);
    CHECK(c.tileSource == GlyphSource::CreatureTile);
    CHECK(c.glyph == wm::Glyph{'r', 6, 0, 0});
    CHECK(!c.materialColour);
    const ClassicGlyphChoice m = classicItemGlyph(idx, wm::ItemKind::Meat, &iron, 0, &rat);
    CHECK(m.tileSource == GlyphSource::AssumedTable);
    CHECK(m.glyph.tile == '%');
    // a corpse is the creature's tile in its colour (measured: a troglodyte
    // corpse draws 116 in 6:0:0); without a creature glyph the table's %
    const ClassicGlyphChoice k = classicItemGlyph(idx, wm::ItemKind::Corpse, &iron, 0, &rat);
    CHECK(k.tileSource == GlyphSource::CreatureTile);
    CHECK(k.glyph == wm::Glyph{'r', 6, 0, 0});
    CHECK(classicItemGlyph(idx, wm::ItemKind::Corpse, &iron, 0, nullptr).glyph.tile == '%');
  }
  SUBCASE("measured colour rules: inverted containers, food, remains, webs") {
    const ClassicGlyphChoice bin = classicItemGlyph(idx, wm::ItemKind::Bin, &iron, 0, nullptr);
    CHECK(bin.glyph == wm::Glyph{88, 0, 0, 1});  // iron 0:1 -> fg 0, bg 0, bright 1
    wm::MaterialGlyph oak;
    oak.basicFg = 6;
    oak.basicBright = 0;
    const ClassicGlyphChoice door = classicItemGlyph(idx, wm::ItemKind::Door, &oak, 0, nullptr);
    CHECK(door.glyph == wm::Glyph{186, 0, 6, 0});
    CHECK(classicItemGlyph(idx, wm::ItemKind::Barrel, &oak, 0, nullptr).glyph == wm::Glyph{246, 0, 6, 0});
    const ClassicGlyphChoice food = classicItemGlyph(idx, wm::ItemKind::Food, &ruby, 0, nullptr);
    CHECK(food.glyph == wm::Glyph{37, 6, 0, 0});
    CHECK(!food.materialColour);
    CHECK(classicItemGlyph(idx, wm::ItemKind::Remains, &ruby, 0, &rat).glyph == wm::Glyph{253, 5, 0, 0});
    const ClassicGlyphChoice web = classicItemGlyph(idx, wm::ItemKind::Thread, &ruby, 0, nullptr, wm::kItemWeb);
    CHECK(web.glyph.tile == 15);
    CHECK(web.tileSource == GlyphSource::MeasuredTable);
    CHECK(classicItemGlyph(idx, wm::ItemKind::Thread, &ruby, 0, nullptr).glyph.tile == 237);
    CHECK(itemTileMeasured(wm::ItemKind::Bin));
    CHECK(!itemTileMeasured(wm::ItemKind::Coin));
  }
  SUBCASE("no material: light grey on black; Unknown kind: nothing") {
    const ClassicGlyphChoice c = classicItemGlyph(idx, wm::ItemKind::Wood, nullptr, 0, nullptr);
    CHECK(c.found);
    CHECK(c.glyph == wm::Glyph{22, 7, 0, 0});
    CHECK(!c.materialColour);
    CHECK(!classicItemGlyph(idx, wm::ItemKind::Unknown, &iron, 0, nullptr).found);
  }
  SUBCASE("every kind has a token and a tile") {
    for (int k = 1; k <= static_cast<int>(wm::ItemKind::Branch); ++k) {
      const auto kind = static_cast<wm::ItemKind>(k);
      CHECK(*itemKindToken(kind) != '\0');
      CHECK(assumedItemTile(kind) != 0);
    }
    CHECK(std::string(itemKindToken(wm::ItemKind::CorpsePiece)) == "CORPSEPIECE");
    CHECK(std::string(itemKindToken(wm::ItemKind::FishRaw)) == "FISH_RAW");
  }
}

TEST_CASE("classic building and creature glyphs") {
  AssetIndex idx;
  ingestRawText(idx, readData("graphics_classic_test.txt"), "/synth/mod/graphics", "classic", nullptr);
  finalizeIndex(idx);
  wm::MaterialGlyph granite;
  granite.build = wm::Glyph{7, 7, 0, 1};
  const ClassicGlyphChoice shop = classicBuildingGlyph(idx, wm::BuildingKind::Shop, &granite);
  CHECK(shop.tileSource == GlyphSource::AsciiGraphics);
  CHECK(shop.glyph == wm::Glyph{178, 2, 0, 0});
  const ClassicGlyphChoice ws = classicBuildingGlyph(idx, wm::BuildingKind::Workshop, &granite);
  CHECK(ws.tileSource == GlyphSource::AssumedTable);
  CHECK(ws.glyph.tile == assumedBuildingTile(wm::BuildingKind::Workshop));
  CHECK(ws.glyph.fg == 7);
  CHECK(ws.glyph.bright == 1);
  CHECK(ws.materialColour);
  const ClassicGlyphChoice bare = classicBuildingGlyph(idx, wm::BuildingKind::Well, nullptr);
  CHECK(bare.glyph == wm::Glyph{79, 7, 0, 0});

  wm::CreatureGlyph dwarf{wm::Glyph{1, 3, 0, 0}, 2};
  CHECK(classicCreatureGlyph(dwarf, false) == wm::Glyph{1, 3, 0, 0});
  CHECK(classicCreatureGlyph(dwarf, true) == wm::Glyph{2, 3, 0, 0});
  wm::CreatureGlyph beast{wm::Glyph{'B', 5, 0, 1}, 0};
  CHECK(classicCreatureGlyph(beast, true).tile == 'B');
  CHECK(std::string(glyphSourceName(GlyphSource::AssumedTable)) == "assumed-table");
  CHECK(std::string(glyphSourceName(GlyphSource::MeasuredTable)) == "measured-table");
}
