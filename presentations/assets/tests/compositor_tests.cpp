// Tier 0: the unit appearance compositor on procedural pixels. Every image
// here is generated in the test (no PNG, no art): tiny 4x4-tile pages and
// a palette strip handed in through the injected loader.
#include <doctest.h>

#include <map>
#include <string>
#include <vector>

#include "df3d_assets/compositor.h"
#include "df3d_assets/terrain_fill.h"
#include "df3d_assets/wall_top.h"
#include "df3d_assets/bitmap_slots.h"

using namespace df3d::assets;

TEST_CASE("bitmap slots require exact dimensions and bytes even on hash collision") {
  BitmapSlots slots(+[](const RgbaImage&) -> uint64_t { return 7; });
  auto image = RgbaImage::blank(2, 1);
  image.set(0, 0, {1, 2, 3, 255});
  CHECK(slots.intern(image, 10) == 10);
  CHECK(slots.intern(image, 11) == 10);
  auto different = image;
  different.pixels.back() = 1;
  CHECK(slots.intern(different, 11) == 11);
  auto reshaped = image;
  reshaped.width = 1; reshaped.height = 2;
  CHECK(slots.intern(reshaped, 12) == 12);
  CHECK(slots.intern(image, 13) == 10);
  CHECK(slots.hits() == 2);
  CHECK(slots.unique() == 3);
  slots.clear();
  CHECK(slots.hits() == 0);
  CHECK(slots.unique() == 0);
  CHECK(slots.intern(image, 30) == 30);
}

TEST_CASE("wall backing ignores transparent colors and composes multiple corners into one opaque tile") {
  AssetIndex index;
  index.pages.push_back({"WALL", "", "/wall", 2, 2, 4, 2});
  index.pages.push_back({"ROCK", "", "/rock", 2, 2, 2, 2});
  index.tileGraphics["HIDDEN_ROCK_1"] = {SpriteRef{1, 0, 0, 1, 1}};
  index.palette = Palette{};
  index.palette->absPath = "/palette";
  index.palette->defaultRow = 0;
  RgbaImage rock = RgbaImage::blank(2, 2);
  rock.set(0, 0, {12, 24, 36, 255}); rock.set(1, 0, {12, 24, 36, 255});
  rock.set(0, 1, {250, 0, 0, 0}); rock.set(1, 1, {0, 250, 0, 128});
  const Rgba fallback{1, 2, 3, 255};
  CHECK(dominantOpaque(rock, {1, 0, 0, 2, 2}, fallback) == Rgba{12, 24, 36, 255});
  CHECK(dominantOpaque(RgbaImage::blank(2, 2), {1, 0, 0, 2, 2}, fallback) == fallback);
  RgbaImage wallPixels = RgbaImage::blank(4, 2);
  wallPixels.set(0, 0, {16, 16, 16, 255});
  wallPixels.set(3, 1, {20, 40, 60, 128});
  RgbaImage palette = RgbaImage::blank(1, 2);
  palette.set(0, 0, {16, 16, 16, 255}); palette.set(0, 1, {200, 100, 50, 255});
  const ImageLoader loader = [&](const std::string& path) -> const RgbaImage* {
    if (path == "/rock") return &rock;
    if (path == "/wall") return &wallPixels;
    if (path == "/palette") return &palette;
    return nullptr;
  };
  TerrainSprite wall;
  wall.found = wall.layeredWall = true;
  wall.sprite = {0, 0, 0, 1, 1}; wall.paletteRow = 1;
  wall.wallLayers = {{0, 0, 0, 1, 1}, {0, 1, 0, 1, 1}};
  std::string why;
  auto image = composeWallTop(index, wall, loader, why);
  REQUIRE(why.empty()); REQUIRE(image.width == 2); REQUIRE(image.height == 2);
  CHECK(image.get(0, 0) == Rgba{200, 100, 50, 255});
  CHECK(image.get(1, 0) == Rgba{12, 24, 36, 255});
  const Rgba corner{16, 32, 48, 255};
  CHECK(image.get(1, 1) == corner);
  wall.wallLayers.clear();
  image = composeWallTop(index, wall, loader, why);
  CHECK(image.get(0, 0) == Rgba{12, 24, 36, 255});
  CHECK(image.get(1, 1) == Rgba{12, 24, 36, 255});
  // Modded installs missing the source rock selector keep a deterministic
  // opaque palette backing. Missing required edge images fail explicitly.
  index.tileGraphics.erase("HIDDEN_ROCK_1");
  image = composeWallTop(index, wall, loader, why);
  CHECK(image.get(0, 0) == Rgba{200, 100, 50, 255});
  wall.wallLayers = {{0, 5, 0, 1, 1}};
  CHECK(composeWallTop(index, wall, loader, why).empty());
  CHECK_FALSE(why.empty());
}

TEST_CASE("opaque wall rounding matches native soil overlays without changing unit blending") {
  const Rgba background{12, 24, 36, 255};
  const Rgba foreground{21, 40, 60, 128};
  CHECK(blendWallOverOpaque(background, foreground) == Rgba{17, 32, 48, 255});
  Rgba unit = background; blendOver(unit, foreground);
  CHECK(unit == Rgba{16, 32, 48, 255});
  CHECK(blendWallOverOpaque(background, {250, 1, 2, 0}) == background);
  CHECK(blendWallOverOpaque(background, {250, 1, 2, 255}) == Rgba{250, 1, 2, 255});
  AssetIndex missing;
  CHECK(nativeRockBacking(missing, {}, {3, 5, 7, 0}) == Rgba{3, 5, 7, 255});
}

TEST_CASE("terrain backing follows tile art, not merely material palette availability") {
  // Adjacent unkeyed sand and keyed stone on one procedural page. A dark
  // material base must remain for stone but must not punch holes in sand.
  const uint32_t keys[] = {0x101010};
  const uint8_t pixels[] = {
      210,180,110,255, 16,16,16,0, 16,16,16,128, 0,0,0,0,
      200,170,100,255, 255,0,255,0, 80,80,80,255, 0,0,0,0};
  CHECK(terrainFillBase(pixels,4,2,0,0,2,2,keys,0x2f2c2d) == 0xcdaf69);
  CHECK(terrainFillBase(pixels,4,2,2,0,2,2,keys,0x2f2c2d) == 0x2f2c2d);
  CHECK(terrainFillBase(pixels,4,2,0,0,2,2,{},0x404040) == 0xcdaf69);
  CHECK(terrainFillBase(pixels,4,2,3,0,1,2,keys,0x2f2c2d) == 0x2f2c2d);
}

namespace {

constexpr int kTile = 4;  // synthetic tile size

Rgba rgba(uint8_t r, uint8_t g, uint8_t b, uint8_t a = 255) { return Rgba{r, g, b, a}; }

// Palette keys (row 0) and two replacement rows.
const Rgba kKey0 = rgba(10, 20, 30), kKey1 = rgba(40, 50, 60), kKey2 = rgba(70, 80, 90);
const Rgba kRow1c0 = rgba(200, 0, 0), kRow1c1 = rgba(0, 200, 0), kRow1c2 = rgba(0, 0, 200);
const Rgba kRow2c0 = rgba(11, 11, 11), kRow2c1 = rgba(22, 22, 22), kRow2c2 = rgba(33, 33, 33);
const Rgba kPlain = rgba(123, 45, 67);  // never a key

RgbaImage makePalette() {
  RgbaImage p = RgbaImage::blank(3, 3);
  p.set(0, 0, kKey0);
  p.set(1, 0, kKey1);
  p.set(2, 0, kKey2);
  p.set(0, 1, kRow1c0);
  p.set(1, 1, kRow1c1);
  p.set(2, 1, kRow1c2);
  p.set(0, 2, kRow2c0);
  p.set(1, 2, kRow2c1);
  p.set(2, 2, kRow2c2);
  return p;
}

// A synthetic environment: pages BODY (4x4 tiles of 4 px) and BIG (2x2
// tiles of 8 px), palette "pal/p.png", all served from memory.
struct Synth {
  AssetIndex index;
  std::map<std::string, RgbaImage> images;
  CompositeContext ctx;
  std::vector<std::string> pageNames{"BODY", "BIG"};
  std::vector<std::string> paletteNames{"pal/p.png"};
  int loads = 0;

  Synth() {
    TilePage body;
    body.name = "BODY";
    body.absPath = "/inst/body.png";
    body.tileW = body.tileH = kTile;
    body.pageW = body.pageH = 4 * kTile;
    TilePage big;
    big.name = "BIG";
    big.absPath = "/inst/big.png";
    big.tileW = big.tileH = 2 * kTile;
    big.pageW = big.pageH = 2 * 2 * kTile;
    index.pages = {body, big};
    index.pageByName = {{"BODY", 0}, {"BIG", 1}};

    // BODY: tile (0,0) = solid key0; tile (1,0) = key1 at (0,0) only, rest
    // transparent; tile (2,0) = plain colour, half alpha; tile (3,0) = key2
    // with alpha 128 (semi-transparent keyed); tile (0,1) = key colour with
    // alpha 0 (must stay invisible); tile (1,1) = opaque plain.
    RgbaImage b = RgbaImage::blank(4 * kTile, 4 * kTile);
    for (int y = 0; y < kTile; ++y)
      for (int x = 0; x < kTile; ++x) {
        b.set(x, y, kKey0);
        b.set(2 * kTile + x, y, rgba(kPlain.r, kPlain.g, kPlain.b, 128));
        b.set(3 * kTile + x, y, rgba(kKey2.r, kKey2.g, kKey2.b, 128));
        b.set(x, kTile + y, rgba(kKey0.r, kKey0.g, kKey0.b, 0));
        b.set(kTile + x, kTile + y, kPlain);
      }
    b.set(kTile, 0, kKey1);
    images["/inst/body.png"] = b;

    // BIG: tile (0,0) is 8x8: a 2x2 checker of key0 / plain per pixel so
    // scaling by 2 samples a known pattern.
    RgbaImage g = RgbaImage::blank(2 * 2 * kTile, 2 * 2 * kTile);
    for (int y = 0; y < 2 * kTile; ++y)
      for (int x = 0; x < 2 * kTile; ++x) g.set(x, y, ((x + y) % 2 == 0) ? kKey0 : kPlain);
    images["/inst/big.png"] = g;

    images["/inst/pal/p.png"] = makePalette();

    ctx.index = &index;
    ctx.installRoot = "/inst";
    ctx.names.page = [this](wm::PageId id) {
      return id < pageNames.size() ? std::string_view(pageNames[id]) : std::string_view();
    };
    ctx.names.palette = [this](wm::PaletteId id) {
      return id < paletteNames.size() ? std::string_view(paletteNames[id]) : std::string_view();
    };
    ctx.load = [this](const std::string& path) -> const RgbaImage* {
      ++loads;
      auto it = images.find(path);
      return it == images.end() ? nullptr : &it->second;
    };
  }
};

wm::AppearanceLayer layer(wm::PageId page, int tx, int ty, int cx = 1, int cy = 1,
                          int8_t ox = 0, int8_t oy = 0) {
  wm::AppearanceLayer l;
  l.page = page;
  l.tileX = static_cast<uint16_t>(tx);
  l.tileY = static_cast<uint16_t>(ty);
  l.cellsX = static_cast<uint8_t>(cx);
  l.cellsY = static_cast<uint8_t>(cy);
  l.offsetX = ox;
  l.offsetY = oy;
  return l;
}

wm::AppearanceLayer withPalette(wm::AppearanceLayer l, int row, int keyRow = 0) {
  l.palette = 0;
  l.paletteRow = static_cast<int16_t>(row);
  l.paletteKeyRow = static_cast<int16_t>(keyRow);
  return l;
}

}  // namespace

TEST_CASE("compositor: blendOver is the bridge's integer alpha-over") {
  Rgba d = rgba(0, 0, 0, 0);
  blendOver(d, rgba(1, 2, 3, 0));
  CHECK(d == rgba(0, 0, 0, 0));  // fully transparent source is a no-op
  blendOver(d, rgba(9, 8, 7, 200));
  CHECK(d == rgba(9, 8, 7, 200));  // over an empty pixel: copy
  blendOver(d, rgba(100, 100, 100, 255));
  CHECK(d == rgba(100, 100, 100, 255));  // opaque source replaces
  // Half over opaque: (s*sa + d*da*(255-sa)/255) / oa with oa = 255.
  Rgba e = rgba(0, 0, 0, 255);
  blendOver(e, rgba(255, 255, 255, 128));
  CHECK(e.a == 255);
  CHECK(e.r == (255 * 128 + 0) / 255);
  CHECK(e.r == 128);
  // Half over half: oa = 128 + 128*127/255 = 191.
  Rgba f = rgba(0, 0, 0, 128);
  blendOver(f, rgba(255, 255, 255, 128));
  CHECK(f.a == 191);
  CHECK(f.r == (255 * 128) / 191);
}

TEST_CASE("compositor: fitFactor") {
  CHECK(fitFactor(32, 32, 32, 32) == 1);
  CHECK(fitFactor(16, 16, 32, 32) == 1);
  CHECK(fitFactor(64, 64, 32, 32) == 2);
  CHECK(fitFactor(64, 32, 32, 32) == 2);
  CHECK(fitFactor(96, 64, 32, 32) == 3);
  CHECK(fitFactor(33, 32, 32, 32) == 2);
  CHECK(fitFactor(64, 64, 64, 32) == 2);
  CHECK(fitFactor(10, 10, 0, 0) == 1);
}

TEST_CASE("compositor: palette swap table and exactness") {
  const RgbaImage pal = makePalette();
  PaletteSwap sw;
  REQUIRE(buildPaletteSwap(pal, 0, 1, sw));
  CHECK(sw.table.size() == 3);
  uint32_t out = 0;
  CHECK(sw.lookup(packRgb(kKey0), out));
  CHECK(out == packRgb(kRow1c0));
  CHECK(sw.lookup(packRgb(kKey2), out));
  CHECK(out == packRgb(kRow1c2));
  CHECK_FALSE(sw.lookup(packRgb(kPlain), out));
  // Rows outside the image fail; the key row may equal the row (identity).
  CHECK_FALSE(buildPaletteSwap(pal, 0, 3, sw));
  CHECK_FALSE(buildPaletteSwap(pal, -1, 1, sw));
  REQUIRE(buildPaletteSwap(pal, 1, 1, sw));
  CHECK(sw.lookup(packRgb(kRow1c1), out));
  CHECK(out == packRgb(kRow1c1));
  // A duplicated key keeps its first column (the bridge stops at the first
  // matching column).
  RgbaImage dup = RgbaImage::blank(2, 2);
  dup.set(0, 0, kKey0);
  dup.set(1, 0, kKey0);
  dup.set(0, 1, kRow1c0);
  dup.set(1, 1, kRow1c1);
  REQUIRE(buildPaletteSwap(dup, 0, 1, sw));
  CHECK(sw.table.size() == 1);
  CHECK(sw.lookup(packRgb(kKey0), out));
  CHECK(out == packRgb(kRow1c0));

  // On pixels: keyed opaque swapped; keyed semi-transparent swapped with
  // alpha kept; non-key untouched; alpha-0 key colour stays invisible.
  Synth s;
  const wm::AppearanceLayer layers[] = {withPalette(layer(0, 3, 0), 1)};
  CompositeResult r = compositeAppearance(s.ctx, layers);
  REQUIRE_MESSAGE(r.ok, r.why);
  CHECK(r.image.width == kTile);
  CHECK(r.image.height == kTile);
  CHECK(r.image.get(0, 0) == rgba(kRow1c2.r, kRow1c2.g, kRow1c2.b, 128));
  CHECK(r.image.get(kTile - 1, kTile - 1) == rgba(kRow1c2.r, kRow1c2.g, kRow1c2.b, 128));

  const wm::AppearanceLayer plain[] = {withPalette(layer(0, 1, 1), 1)};
  r = compositeAppearance(s.ctx, plain);
  REQUIRE(r.ok);
  CHECK(r.image.get(0, 0) == kPlain);
  CHECK(r.image.get(kTile - 1, 0) == kPlain);

  const wm::AppearanceLayer invisible[] = {withPalette(layer(0, 0, 1), 1)};
  r = compositeAppearance(s.ctx, invisible);
  REQUIRE(r.ok);
  for (int y = 0; y < kTile; ++y)
    for (int x = 0; x < kTile; ++x) CHECK(r.image.get(x, y).a == 0);

  // Without a palette the key colour is drawn as-is.
  const wm::AppearanceLayer asIs[] = {layer(0, 0, 0)};
  r = compositeAppearance(s.ctx, asIs);
  REQUIRE(r.ok);
  CHECK(r.image.get(1, 1) == kKey0);

  // Another row gives another replacement; key row 1 makes row-1 colours
  // the keys (row 0's are then not keys).
  const wm::AppearanceLayer row2[] = {withPalette(layer(0, 0, 0), 2)};
  r = compositeAppearance(s.ctx, row2);
  REQUIRE(r.ok);
  CHECK(r.image.get(2, 2) == kRow2c0);
  const wm::AppearanceLayer keyRow1[] = {withPalette(layer(0, 0, 0), 2, 1)};
  r = compositeAppearance(s.ctx, keyRow1);
  REQUIRE(r.ok);
  CHECK(r.image.get(2, 2) == kKey0);
}

TEST_CASE("compositor: layer order, transparency and blending") {
  Synth s;
  // Bottom: solid key0 tile. Top: tile (1,0) = one key1 pixel at (0,0),
  // transparent elsewhere: the bottom shows through, the top wins at (0,0).
  const wm::AppearanceLayer layers[] = {layer(0, 0, 0), layer(0, 1, 0)};
  CompositeResult r = compositeAppearance(s.ctx, layers);
  REQUIRE_MESSAGE(r.ok, r.why);
  CHECK(r.layersDrawn == 2);
  CHECK(r.image.get(0, 0) == kKey1);
  CHECK(r.image.get(1, 0) == kKey0);
  CHECK(r.image.get(3, 3) == kKey0);

  // Reversed order: the solid tile covers the single pixel.
  const wm::AppearanceLayer reversed[] = {layer(0, 1, 0), layer(0, 0, 0)};
  r = compositeAppearance(s.ctx, reversed);
  REQUIRE(r.ok);
  CHECK(r.image.get(0, 0) == kKey0);

  // A half-alpha layer over an opaque one blends with the bridge formula.
  const wm::AppearanceLayer blended[] = {layer(0, 0, 0), layer(0, 2, 0)};
  r = compositeAppearance(s.ctx, blended);
  REQUIRE(r.ok);
  Rgba expect = kKey0;
  blendOver(expect, rgba(kPlain.r, kPlain.g, kPlain.b, 128));
  CHECK(r.image.get(2, 2) == expect);
  CHECK(r.image.get(2, 2).a == 255);

  // A half-alpha layer alone keeps its alpha on the transparent canvas.
  const wm::AppearanceLayer alone[] = {layer(0, 2, 0)};
  r = compositeAppearance(s.ctx, alone);
  REQUIRE(r.ok);
  CHECK(r.image.get(1, 1) == rgba(kPlain.r, kPlain.g, kPlain.b, 128));

  // Each layer swaps with its own palette row.
  const wm::AppearanceLayer rows[] = {withPalette(layer(0, 0, 0), 1), withPalette(layer(0, 1, 0), 2)};
  r = compositeAppearance(s.ctx, rows);
  REQUIRE(r.ok);
  CHECK(r.image.get(0, 0) == kRow2c1);
  CHECK(r.image.get(1, 1) == kRow1c0);
}

TEST_CASE("compositor: offsets move a layer and clip at the canvas") {
  Synth s;
  // Top layer's single pixel at (0,0) lands at (2,1) with offset (2,1).
  const wm::AppearanceLayer layers[] = {layer(0, 0, 0), layer(0, 1, 0, 1, 1, 2, 1)};
  CompositeResult r = compositeAppearance(s.ctx, layers);
  REQUIRE_MESSAGE(r.ok, r.why);
  CHECK(r.image.get(2, 1) == kKey1);
  CHECK(r.image.get(0, 0) == kKey0);

  // Negative offsets push it off the canvas: dropped, nothing else moves.
  const wm::AppearanceLayer off[] = {layer(0, 0, 0), layer(0, 1, 0, 1, 1, -1, 0)};
  r = compositeAppearance(s.ctx, off);
  REQUIRE(r.ok);
  for (int y = 0; y < kTile; ++y)
    for (int x = 0; x < kTile; ++x) CHECK(r.image.get(x, y) == kKey0);

  // The first (bottom) layer's own offset shifts it too: the canvas stays
  // the unit cell, so a solid tile at (1,0) leaves column 0 transparent.
  const wm::AppearanceLayer bottom[] = {layer(0, 0, 0, 1, 1, 1, 0)};
  r = compositeAppearance(s.ctx, bottom);
  REQUIRE(r.ok);
  CHECK(r.image.width == kTile);
  CHECK(r.image.get(0, 0).a == 0);
  CHECK(r.image.get(1, 0) == kKey0);
  CHECK(r.image.get(kTile - 1, 0) == kKey0);
}

TEST_CASE("compositor: layers larger than the unit cell are scaled down to fit") {
  Synth s;
  // Unit cell = BODY tile (4x4). The BIG page's tile is 8x8: factor 2,
  // sampling even pixels of the checker (all key0 since (x+y) even), so the
  // whole cell is key0, swapped through the palette after sampling.
  const wm::AppearanceLayer layers[] = {layer(0, 0, 1), withPalette(layer(1, 0, 0), 1)};
  CompositeResult r = compositeAppearance(s.ctx, layers);
  REQUIRE_MESSAGE(r.ok, r.why);
  CHECK(r.image.width == kTile);
  CHECK(r.image.height == kTile);
  CHECK(r.layersScaled == 1);
  for (int y = 0; y < kTile; ++y)
    for (int x = 0; x < kTile; ++x) CHECK(r.image.get(x, y) == kRow1c0);

  // A 2x2-cell BODY layer (8x8) on a 1x1 cell: factor 2 as well; the
  // sampled pixels come from tiles (0,0) and (1,1) (even rows/columns of
  // the 2x2 block): key0 top-left quadrant, plain bottom-right quadrant,
  // transparent elsewhere (tile (1,0) has its pixel at an even position:
  // (4,0) -> (2,0)).
  const wm::AppearanceLayer big2[] = {layer(0, 0, 1), layer(0, 0, 0, 2, 2)};
  r = compositeAppearance(s.ctx, big2);
  REQUIRE(r.ok);
  CHECK(r.image.get(0, 0) == kKey0);
  CHECK(r.image.get(1, 1) == kKey0);
  CHECK(r.image.get(2, 0) == kKey1);
  CHECK(r.image.get(3, 1).a == 0);  // tile (1,0) transparent elsewhere
  CHECK(r.image.get(0, 2).a == 0);  // tile (0,1): alpha-0 keys
  CHECK(r.image.get(2, 2) == kPlain);
  CHECK(r.image.get(3, 3) == kPlain);

  // Offsets apply after scaling.
  const wm::AppearanceLayer shifted[] = {layer(0, 0, 1), layer(0, 0, 0, 2, 2, 1, 1)};
  r = compositeAppearance(s.ctx, shifted);
  REQUIRE(r.ok);
  CHECK(r.image.get(0, 0).a == 0);
  CHECK(r.image.get(1, 1) == kKey0);
  CHECK(r.image.get(3, 3) == kPlain);

  // A large-image unit (first layer 2x1 cells) gets a 2x1-tile canvas and a
  // 2x1 layer is not scaled.
  const wm::AppearanceLayer wide[] = {layer(0, 0, 0, 2, 1)};
  r = compositeAppearance(s.ctx, wide);
  REQUIRE(r.ok);
  CHECK(r.cellsX == 2);
  CHECK(r.cellsY == 1);
  CHECK(r.image.width == 2 * kTile);
  CHECK(r.image.height == kTile);
  CHECK(r.layersScaled == 0);
  CHECK(r.image.get(0, 0) == kKey0);
  CHECK(r.image.get(kTile, 0) == kKey1);
  CHECK(r.image.get(kTile + 1, 0).a == 0);
}

TEST_CASE("compositor: held weapons preserve pixels outside the logical body") {
  Synth s;
  auto page = s.index.pages[0]; page.name = "WIELDABLES";
  s.index.pages.push_back(page); s.index.pageByName[page.name] = 2;
  s.pageNames.push_back(page.name);
  // Weapon before body, as in native layer order: its outside blade must
  // survive while clothing can still cover its inside pixels.
  const wm::AppearanceLayer layers[] = {layer(0,0,1), withPalette(layer(2,0,0,2,1),1), layer(0,1,1)};
  auto r = compositeAppearance(s.ctx,layers);
  REQUIRE_MESSAGE(r.ok,r.why);
  CHECK(r.cellsX == 1); CHECK(r.cellsY == 1);
  CHECK(r.image.width == 2*kTile); CHECK(r.image.height == kTile);
  CHECK(r.originX == -kTile); CHECK(r.originY == 0);
  CHECK(r.layersScaled == 0);
  CHECK(r.image.get(0,0) == kRow1c0);
  CHECK(r.image.get(kTile-1,kTile-1) == kRow1c0);
  CHECK(r.image.get(kTile,0) == kPlain);
  CHECK(r.image.get(2*kTile-1,kTile-1) == kPlain);
  // Taller weapons extend above, without changing the body's pivot/height.
  const wm::AppearanceLayer tall[] = {layer(0,0,1), layer(2,0,0,2,2)};
  r = compositeAppearance(s.ctx,tall);
  REQUIRE(r.ok); CHECK(r.originY == -kTile); CHECK(r.image.height == 2*kTile);
  CHECK(r.cellsY == 1); CHECK(r.layersScaled == 0);
  CHECK(r.image.get(0,0) == kKey0);
  CHECK(r.image.get(kTile,kTile) == kPlain);
  // Offsets move the weapon, with enough canvas for both body and blade.
  const wm::AppearanceLayer offset[] = {layer(0,1,1), layer(2,0,0,2,1,-1,-1)};
  r = compositeAppearance(s.ctx,offset);
  REQUIRE(r.ok); CHECK(r.originX == -kTile-1); CHECK(r.originY == -1);
  CHECK(r.image.width == 2*kTile+1); CHECK(r.image.height == kTile+1);
  CHECK(r.image.get(0,0) == kKey0);
  CHECK(r.image.get(r.image.width-1,r.image.height-1) == kPlain);
}

TEST_CASE("compositor: failures leave no sprite") {
  Synth s;
  CompositeResult r = compositeAppearance(s.ctx, std::span<const wm::AppearanceLayer>());
  CHECK_FALSE(r.ok);
  CHECK(r.why == "no layers");

  const wm::AppearanceLayer badPage[] = {layer(7, 0, 0)};
  r = compositeAppearance(s.ctx, badPage);
  CHECK_FALSE(r.ok);
  CHECK(r.why.find("unknown page") != std::string::npos);
  CHECK(r.image.empty());

  const wm::AppearanceLayer outside[] = {layer(0, 4, 0)};
  r = compositeAppearance(s.ctx, outside);
  CHECK_FALSE(r.ok);
  CHECK(r.why.find("outside page BODY") != std::string::npos);

  wm::AppearanceLayer badPal = withPalette(layer(0, 0, 0), 1);
  badPal.palette = 9;
  const wm::AppearanceLayer badPalette[] = {badPal};
  r = compositeAppearance(s.ctx, badPalette);
  CHECK_FALSE(r.ok);
  CHECK(r.why.find("unknown palette") != std::string::npos);

  const wm::AppearanceLayer badRow[] = {withPalette(layer(0, 0, 0), 5)};
  r = compositeAppearance(s.ctx, badRow);
  CHECK_FALSE(r.ok);
  CHECK(r.why.find("outside the palette image") != std::string::npos);

  // A failing layer anywhere in the stack fails the whole composite
  // (the caller keeps its fallback rather than showing half a dwarf).
  const wm::AppearanceLayer mixed[] = {layer(0, 0, 0), layer(0, 9, 9)};
  r = compositeAppearance(s.ctx, mixed);
  CHECK_FALSE(r.ok);
  CHECK(r.image.empty());

  // An unloadable image.
  s.index.pages[0].absPath = "/inst/missing.png";
  const wm::AppearanceLayer missing[] = {layer(0, 0, 0)};
  r = compositeAppearance(s.ctx, missing);
  CHECK_FALSE(r.ok);
  CHECK(r.why.find("cannot load") != std::string::npos);
}

TEST_CASE("compositor: cache keyed by appearance version") {
  Synth s;
  CompositeCache cache;
  CHECK(cache.find(0x1234) == nullptr);
  const wm::AppearanceLayer a[] = {layer(0, 0, 0)};
  const wm::AppearanceLayer b[] = {layer(0, 1, 1)};
  const CompositeResult& ra = cache.put(0x1234, compositeAppearance(s.ctx, a));
  CHECK(ra.ok);
  CHECK(cache.size() == 1);
  CHECK(cache.imageBytes() == static_cast<size_t>(kTile * kTile * 4));
  // Two units sharing a version share the entry: no second composite.
  const int loadsBefore = s.loads;
  const CompositeResult* hit = cache.find(0x1234);
  REQUIRE(hit != nullptr);
  CHECK(hit == &ra);
  CHECK(s.loads == loadsBefore);
  CHECK(hit->image.get(0, 0) == kKey0);
  // A different version is a different sprite even for a similar stack.
  CHECK(cache.find(0x1235) == nullptr);
  cache.put(0x1235, compositeAppearance(s.ctx, b));
  CHECK(cache.size() == 2);
  CHECK(cache.find(0x1235)->image.get(0, 0) == kPlain);
  // Replacing a version swaps its sprite.
  cache.put(0x1234, compositeAppearance(s.ctx, b));
  CHECK(cache.find(0x1234)->image.get(0, 0) == kPlain);
  CHECK(cache.size() == 2);
  // Failed composites can be cached too (so a bad stack is not retried
  // every frame) and report !ok.
  const wm::AppearanceLayer bad[] = {layer(0, 9, 9)};
  cache.put(0x9999, compositeAppearance(s.ctx, bad));
  CHECK_FALSE(cache.find(0x9999)->ok);
  // retain() drops what no unit references any more.
  CHECK(cache.retain([](uint32_t v) { return v == 0x1235; }) == 2);
  CHECK(cache.size() == 1);
  CHECK(cache.find(0x1235) != nullptr);
  CHECK(cache.erase(0x1235));
  CHECK_FALSE(cache.erase(0x1235));
  CHECK(cache.size() == 0);
}
