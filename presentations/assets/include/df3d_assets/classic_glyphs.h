// Classic (curses / CP437) glyph rendering for anything the install has no sprite for, from the install's own tileset, colors.txt palette, graphics_classic.txt rows and raw tiles; pure and engine-agnostic.
#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <string_view>

#include "df3d_assets/asset_index.h"
#include "df3d_assets/compositor.h"
#include "wm/types.h"

namespace df3d::assets {

// DF's 16 classic colours in colors.txt order; index = fg + 8 * bright.
struct ClassicPalette {
  std::array<Rgb, 16> colors{};
  int channels = 0;  // R/G/B tokens parsed (48 = complete)
  bool complete() const { return channels == 48; }
  Rgb color(uint8_t fg, uint8_t bright) const {
    return colors[static_cast<size_t>((fg & 7) + (bright ? 8 : 0))];
  }
  friend bool operator==(const ClassicPalette&, const ClassicPalette&) = default;
};

// The colour names in index order (tests, diagnostics).
const char* classicColorName(int index);

// Parses colors.txt `[<NAME>_R:n]`/_G/_B tokens into `out`; returns channels parsed.
int parseClassicColors(std::string_view text, ClassicPalette& out);

// Vanilla 53.16 colors.txt defaults for an install whose colors.txt cannot be read.
ClassicPalette defaultClassicPalette();

// `[<key>:file]` of an init file ("" when absent); key is FONT, FULLFONT
// or BASIC_FONT.
std::string parseInitFont(std::string_view initText, std::string_view key = "FONT");

// Tileset PNG selection: prefs/init.txt FONT, else init_default.txt FONT, else curses_square_16x16.png; `source` says which rule.
struct ClassicTileset {
  std::string absPath;
  std::string file;    // as named in the init
  std::string source;  // "prefs/init.txt FONT", "data/init/init_default.txt FONT", "fallback", "none"
};
ClassicTileset resolveClassicTileset(const std::string& installRoot);

// Renders code points of a curses tileset in DF's colours.
class GlyphRenderer {
 public:
  // The sheet must be a 16 x 16 grid (width and height multiples of 16).
  bool setTileset(RgbaImage sheet, std::string& err);
  bool ready() const { return tileW_ > 0; }
  int tileW() const { return tileW_; }
  int tileH() const { return tileH_; }
  void setPalette(const ClassicPalette& p) { palette_ = p; }
  const ClassicPalette& palette() const { return palette_; }

  // Magenta (255, 0, 255) or fully transparent: the cell background.
  static bool isKey(Rgba p) {
    return p.a == 0 || (p.r == 255 && p.g == 0 && p.b == 255);
  }

  // One code point as an image: non-key pixels tinted by fg, key pixels bg (transparent when black and `transparentBlack`).
  RgbaImage render(wm::Glyph g, bool transparentBlack = true) const;
  // The whole 16 x 16 sheet in one colour triple; cell = (tile % 16, tile / 16).
  RgbaImage renderSheet(uint8_t fg, uint8_t bg, uint8_t bright, bool transparentBlack = true) const;

 private:
  void tint(RgbaImage& out, int dstX, int dstY, int srcX, int srcY, Rgb fgc, Rgb bgc,
            bool bgTransparent) const;
  RgbaImage sheet_;
  int tileW_ = 0, tileH_ = 0;
  ClassicPalette palette_ = defaultClassicPalette();
};

// --- classic tile tables ---

// Where a classic glyph came from (overlay / docs / tests).
enum class GlyphSource : uint8_t {
  None = 0,
  AsciiGraphics,   // graphics_classic.txt ASCII_GRAPHICS row for the kind
  MaterialSymbol,  // the material's [ITEM_SYMBOL] (gems)
  ItemDefTile,     // the tool itemdef's [TILE]
  CreatureTile,    // the creature's [CREATURE_TILE] (vermin, pets)
  AssumedTable,    // the per-kind table below, a row DF's vtable was not asked about
  MeasuredTable,   // the per-kind table below, a row measured on DF 53.16 (item::drawSelf)
};
const char* glyphSourceName(GlyphSource s);

struct ClassicGlyphChoice {
  bool found = false;
  wm::Glyph glyph;
  GlyphSource tileSource = GlyphSource::None;
  bool materialColour = false;  // fg / bright came from the material's BASIC_COLOR
};

// DF's item_type token for a kind ("BAR", "SMALLGEM", "CORPSEPIECE", ...);
// "" for Unknown. The ASCII_GRAPHICS lookup key is "ITEM_" + token.
const char* itemKindToken(wm::ItemKind kind);
// Classic tile per item kind (66 of 92 measured on 53.16 via tools/smoke/classic_glyph_probe.ps1, the rest transcribed; itemTileMeasured tells them apart); 0 for Unknown.
uint8_t assumedItemTile(wm::ItemKind kind);
bool itemTileMeasured(wm::ItemKind kind);
// The assumed classic tile for a building kind the raws have no art for.
uint8_t assumedBuildingTile(wm::BuildingKind kind);

// Item glyph: tile from ASCII_GRAPHICS row, ITEM_SYMBOL, tool TILE, creature tile, web (15) or the kind table; colour from the ASCII row, else BASIC_COLOR (background for containers/doors), else light grey.
ClassicGlyphChoice classicItemGlyph(const AssetIndex& index, wm::ItemKind kind,
                                    const wm::MaterialGlyph* material, uint8_t itemDefTile,
                                    const wm::CreatureGlyph* creature, uint8_t itemFlags = 0);
// Building glyph without art: ASCII_GRAPHICS BUILDING_<KIND> row, else the assumed tile in the material's BUILD_COLOR.
ClassicGlyphChoice classicBuildingGlyph(const AssetIndex& index, wm::BuildingKind kind,
                                        const wm::MaterialGlyph* material);
// A unit's classic glyph: the creature's tile (`soldier` selects
// SOLDIER_TILE) and colour.
wm::Glyph classicCreatureGlyph(const wm::CreatureGlyph& c, bool soldier);

}  // namespace df3d::assets
