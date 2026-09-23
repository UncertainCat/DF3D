// Classic glyph rendering and the classic tile tables. See
// classic_glyphs.h for the sources and the rendering rule.
#include "df3d_assets/classic_glyphs.h"

#include <algorithm>
#include <filesystem>
#include <string>

#include "df3d_assets/raw_tokens.h"

namespace df3d::assets {

using wm::BuildingKind;
using wm::ItemKind;

namespace {

constexpr const char* kColorNames[16] = {"BLACK",  "BLUE",  "GREEN",  "CYAN",  "RED",
                                         "MAGENTA", "BROWN", "LGRAY",  "DGRAY", "LBLUE",
                                         "LGREEN", "LCYAN", "LRED",   "LMAGENTA", "YELLOW",
                                         "WHITE"};

}  // namespace

const char* classicColorName(int index) {
  return index >= 0 && index < 16 ? kColorNames[index] : "";
}

int parseClassicColors(std::string_view text, ClassicPalette& out) {
  int parsed = 0;
  for (const RawToken& t : tokenizeRaw(text)) {
    if (t.argc() < 2) continue;
    const std::string& n = t.name();
    if (n.size() < 3 || n[n.size() - 2] != '_') continue;
    const char channel = n.back();
    if (channel != 'R' && channel != 'G' && channel != 'B') continue;
    const std::string_view colour(n.data(), n.size() - 2);
    int idx = -1;
    for (int i = 0; i < 16; ++i)
      if (colour == kColorNames[i]) idx = i;
    int v = 0;
    if (idx < 0 || !parseInt(t.args[1], v)) continue;
    const auto b = static_cast<uint8_t>(std::clamp(v, 0, 255));
    Rgb& c = out.colors[static_cast<size_t>(idx)];
    (channel == 'R' ? c.r : channel == 'G' ? c.g : c.b) = b;
    ++parsed;
  }
  out.channels = std::min(48, out.channels + parsed);
  return parsed;
}

ClassicPalette defaultClassicPalette() {
  // Vanilla 53.16 data/init/colors.txt.
  ClassicPalette p;
  const Rgb v[16] = {{0, 0, 0},       {32, 125, 241}, {162, 220, 52}, {113, 187, 176},
                     {255, 17, 58},   {167, 60, 213}, {215, 155, 45}, {192, 192, 192},
                     {160, 160, 160}, {140, 102, 255}, {19, 253, 101}, {18, 254, 207},
                     {255, 113, 17},  {232, 17, 255}, {255, 225, 17},  {255, 255, 255}};
  for (size_t i = 0; i < 16; ++i) p.colors[i] = v[i];
  p.channels = 48;
  return p;
}

std::string parseInitFont(std::string_view initText, std::string_view key) {
  for (const RawToken& t : tokenizeRaw(initText)) {
    if (t.argc() >= 2 && t.name() == key) return t.args[1];
  }
  return {};
}

ClassicTileset resolveClassicTileset(const std::string& installRoot) {
  namespace fs = std::filesystem;
  ClassicTileset r;
  const fs::path root(installRoot);
  const fs::path art = root / "data" / "art";
  auto tryInit = [&](const fs::path& init, const char* source) {
    std::string text, err;
    if (!readTextFile(init.string(), text, err)) return false;
    const std::string font = parseInitFont(text);
    if (font.empty()) return false;
    std::error_code ec;
    if (!fs::exists(art / font, ec)) return false;
    r.absPath = (art / font).string();
    r.file = font;
    r.source = source;
    return true;
  };
  if (tryInit(root / "prefs" / "init.txt", "prefs/init.txt FONT")) return r;
  if (tryInit(root / "data" / "init" / "init_default.txt", "data/init/init_default.txt FONT"))
    return r;
  std::error_code ec;
  const fs::path fallback = art / "curses_square_16x16.png";
  if (fs::exists(fallback, ec)) {
    r.absPath = fallback.string();
    r.file = "curses_square_16x16.png";
    r.source = "fallback";
    return r;
  }
  r.source = "none";
  return r;
}

// --- renderer ---

bool GlyphRenderer::setTileset(RgbaImage sheet, std::string& err) {
  if (sheet.empty() || sheet.width % 16 != 0 || sheet.height % 16 != 0) {
    err = "classic tileset is not a 16x16 grid (" + std::to_string(sheet.width) + "x" +
          std::to_string(sheet.height) + ")";
    tileW_ = tileH_ = 0;
    return false;
  }
  if (sheet.pixels.size() != static_cast<size_t>(sheet.width) * sheet.height * 4) {
    err = "classic tileset pixel buffer does not match its size";
    tileW_ = tileH_ = 0;
    return false;
  }
  tileW_ = sheet.width / 16;
  tileH_ = sheet.height / 16;
  sheet_ = std::move(sheet);
  return true;
}

void GlyphRenderer::tint(RgbaImage& out, int dstX, int dstY, int srcX, int srcY, Rgb fgc, Rgb bgc,
                         bool bgTransparent) const {
  for (int y = 0; y < tileH_; ++y) {
    for (int x = 0; x < tileW_; ++x) {
      const Rgba p = sheet_.get(srcX + x, srcY + y);
      Rgba o;
      if (isKey(p)) {
        o = bgTransparent ? Rgba{0, 0, 0, 0} : Rgba{bgc.r, bgc.g, bgc.b, 255};
      } else {
        o.r = static_cast<uint8_t>((p.r * fgc.r + 127) / 255);
        o.g = static_cast<uint8_t>((p.g * fgc.g + 127) / 255);
        o.b = static_cast<uint8_t>((p.b * fgc.b + 127) / 255);
        o.a = p.a;
      }
      out.set(dstX + x, dstY + y, o);
    }
  }
}

RgbaImage GlyphRenderer::render(wm::Glyph g, bool transparentBlack) const {
  if (!ready()) return {};
  RgbaImage out = RgbaImage::blank(tileW_, tileH_);
  const Rgb fgc = palette_.color(g.fg, g.bright);
  const Rgb bgc = palette_.color(g.bg, 0);
  const bool bgTransparent = transparentBlack && (g.bg & 7) == 0;
  tint(out, 0, 0, (g.tile % 16) * tileW_, (g.tile / 16) * tileH_, fgc, bgc, bgTransparent);
  return out;
}

RgbaImage GlyphRenderer::renderSheet(uint8_t fg, uint8_t bg, uint8_t bright,
                                     bool transparentBlack) const {
  if (!ready()) return {};
  RgbaImage out = RgbaImage::blank(sheet_.width, sheet_.height);
  const Rgb fgc = palette_.color(fg, bright);
  const Rgb bgc = palette_.color(bg, 0);
  const bool bgTransparent = transparentBlack && (bg & 7) == 0;
  for (int ty = 0; ty < 16; ++ty)
    for (int tx = 0; tx < 16; ++tx)
      tint(out, tx * tileW_, ty * tileH_, tx * tileW_, ty * tileH_, fgc, bgc, bgTransparent);
  return out;
}

// --- tables ---

const char* glyphSourceName(GlyphSource s) {
  switch (s) {
    case GlyphSource::None: return "none";
    case GlyphSource::AsciiGraphics: return "ascii-graphics";
    case GlyphSource::MaterialSymbol: return "material.item_symbol";
    case GlyphSource::ItemDefTile: return "itemdef.tile";
    case GlyphSource::CreatureTile: return "creature.tile";
    case GlyphSource::AssumedTable: return "assumed-table";
    case GlyphSource::MeasuredTable: return "measured-table";
  }
  return "?";
}

const char* itemKindToken(ItemKind kind) {
  switch (kind) {
    case ItemKind::Unknown: return "";
    case ItemKind::Bar: return "BAR";
    case ItemKind::SmallGem: return "SMALLGEM";
    case ItemKind::Blocks: return "BLOCKS";
    case ItemKind::Rough: return "ROUGH";
    case ItemKind::Boulder: return "BOULDER";
    case ItemKind::Wood: return "WOOD";
    case ItemKind::Door: return "DOOR";
    case ItemKind::Floodgate: return "FLOODGATE";
    case ItemKind::Bed: return "BED";
    case ItemKind::Chair: return "CHAIR";
    case ItemKind::Chain: return "CHAIN";
    case ItemKind::Flask: return "FLASK";
    case ItemKind::Goblet: return "GOBLET";
    case ItemKind::Instrument: return "INSTRUMENT";
    case ItemKind::Toy: return "TOY";
    case ItemKind::Window: return "WINDOW";
    case ItemKind::Cage: return "CAGE";
    case ItemKind::Barrel: return "BARREL";
    case ItemKind::Bucket: return "BUCKET";
    case ItemKind::AnimalTrap: return "ANIMALTRAP";
    case ItemKind::Table: return "TABLE";
    case ItemKind::Coffin: return "COFFIN";
    case ItemKind::Statue: return "STATUE";
    case ItemKind::Corpse: return "CORPSE";
    case ItemKind::Weapon: return "WEAPON";
    case ItemKind::Armor: return "ARMOR";
    case ItemKind::Shoes: return "SHOES";
    case ItemKind::Shield: return "SHIELD";
    case ItemKind::Helm: return "HELM";
    case ItemKind::Gloves: return "GLOVES";
    case ItemKind::Box: return "BOX";
    case ItemKind::Bag: return "BAG";
    case ItemKind::Bin: return "BIN";
    case ItemKind::Armorstand: return "ARMORSTAND";
    case ItemKind::Weaponrack: return "WEAPONRACK";
    case ItemKind::Cabinet: return "CABINET";
    case ItemKind::Figurine: return "FIGURINE";
    case ItemKind::Amulet: return "AMULET";
    case ItemKind::Scepter: return "SCEPTER";
    case ItemKind::Ammo: return "AMMO";
    case ItemKind::Crown: return "CROWN";
    case ItemKind::Ring: return "RING";
    case ItemKind::Earring: return "EARRING";
    case ItemKind::Bracelet: return "BRACELET";
    case ItemKind::Gem: return "GEM";
    case ItemKind::Anvil: return "ANVIL";
    case ItemKind::CorpsePiece: return "CORPSEPIECE";
    case ItemKind::Remains: return "REMAINS";
    case ItemKind::Meat: return "MEAT";
    case ItemKind::Fish: return "FISH";
    case ItemKind::FishRaw: return "FISH_RAW";
    case ItemKind::Vermin: return "VERMIN";
    case ItemKind::Pet: return "PET";
    case ItemKind::Seeds: return "SEEDS";
    case ItemKind::Plant: return "PLANT";
    case ItemKind::SkinTanned: return "SKIN_TANNED";
    case ItemKind::PlantGrowth: return "PLANT_GROWTH";
    case ItemKind::Thread: return "THREAD";
    case ItemKind::Cloth: return "CLOTH";
    case ItemKind::Totem: return "TOTEM";
    case ItemKind::Pants: return "PANTS";
    case ItemKind::Backpack: return "BACKPACK";
    case ItemKind::Quiver: return "QUIVER";
    case ItemKind::CatapultParts: return "CATAPULTPARTS";
    case ItemKind::BallistaParts: return "BALLISTAPARTS";
    case ItemKind::SiegeAmmo: return "SIEGEAMMO";
    case ItemKind::BallistaArrowhead: return "BALLISTAARROWHEAD";
    case ItemKind::TrapParts: return "TRAPPARTS";
    case ItemKind::TrapComp: return "TRAPCOMP";
    case ItemKind::Drink: return "DRINK";
    case ItemKind::PowderMisc: return "POWDER_MISC";
    case ItemKind::Cheese: return "CHEESE";
    case ItemKind::Food: return "FOOD";
    case ItemKind::LiquidMisc: return "LIQUID_MISC";
    case ItemKind::Coin: return "COIN";
    case ItemKind::Glob: return "GLOB";
    case ItemKind::Rock: return "ROCK";
    case ItemKind::PipeSection: return "PIPE_SECTION";
    case ItemKind::HatchCover: return "HATCH_COVER";
    case ItemKind::Grate: return "GRATE";
    case ItemKind::Quern: return "QUERN";
    case ItemKind::Millstone: return "MILLSTONE";
    case ItemKind::Splint: return "SPLINT";
    case ItemKind::Crutch: return "CRUTCH";
    case ItemKind::TractionBench: return "TRACTION_BENCH";
    case ItemKind::OrthopedicCast: return "ORTHOPEDIC_CAST";
    case ItemKind::Tool: return "TOOL";
    case ItemKind::Slab: return "SLAB";
    case ItemKind::Egg: return "EGG";
    case ItemKind::Book: return "BOOK";
    case ItemKind::Sheet: return "SHEET";
    case ItemKind::Branch: return "BRANCH";
  }
  return "";
}

// The classic tile per item kind as classic DF draws it, transcribed
// (not measured). CP437 code points; the
// comments name the character. Kinds DF draws from their material
// (gems: ITEM_SYMBOL) or itemdef (tools: TILE) get those first in
// classicItemGlyph; this is the last word.
uint8_t assumedItemTile(ItemKind kind) {
  switch (kind) {
    case ItemKind::Unknown: return 0;         // assumed  
    case ItemKind::Bar: return 240;           // measured ≡
    case ItemKind::SmallGem: return 15;       // assumed  ☼ (absent)
    case ItemKind::Blocks: return 254;        // measured ■
    case ItemKind::Rough: return 15;          // measured ☼
    case ItemKind::Boulder: return 7;         // measured • (the material ITEM_SYMBOL: magnetite *)
    case ItemKind::Wood: return 22;           // measured ▬
    case ItemKind::Door: return 186;          // measured ║
    case ItemKind::Floodgate: return 215;     // measured ╧
    case ItemKind::Bed: return 233;           // measured θ
    case ItemKind::Chair: return 210;         // measured ╥
    case ItemKind::Chain: return 21;          // measured §
    case ItemKind::Flask: return 173;         // measured ¡
    case ItemKind::Goblet: return 20;         // measured ¶
    case ItemKind::Instrument: return 168;    // measured ¿
    case ItemKind::Toy: return 145;           // measured æ
    case ItemKind::Window: return 178;        // assumed  ▓ (absent)
    case ItemKind::Cage: return 19;           // measured ‼
    case ItemKind::Barrel: return 246;        // measured ÷
    case ItemKind::Bucket: return 150;        // measured û
    case ItemKind::AnimalTrap: return 207;    // assumed  ¤ (absent)
    case ItemKind::Table: return 209;         // measured ╤
    case ItemKind::Coffin: return 48;         // measured 0
    case ItemKind::Statue: return 234;        // measured Ω
    case ItemKind::Corpse: return 37;         // measured % (only without a creature glyph: the creature tile)
    case ItemKind::Weapon: return 47;         // measured /
    case ItemKind::Armor: return 91;          // measured [
    case ItemKind::Shoes: return 91;          // measured [
    case ItemKind::Shield: return 91;         // measured [
    case ItemKind::Helm: return 91;           // measured [
    case ItemKind::Gloves: return 91;         // measured [
    case ItemKind::Box: return 146;           // measured Æ
    case ItemKind::Bag: return 11;            // measured ♂
    case ItemKind::Bin: return 88;            // measured X
    case ItemKind::Armorstand: return 14;     // measured ♫
    case ItemKind::Weaponrack: return 251;    // measured √
    case ItemKind::Cabinet: return 227;       // measured π
    case ItemKind::Figurine: return 143;      // measured Å
    case ItemKind::Amulet: return 12;         // measured ♀
    case ItemKind::Scepter: return 15;        // assumed  ☼ (absent)
    case ItemKind::Ammo: return 47;           // measured /
    case ItemKind::Crown: return 230;         // measured µ
    case ItemKind::Ring: return 148;          // measured ë
    case ItemKind::Earring: return 235;       // measured δ
    case ItemKind::Bracelet: return 15;       // assumed  ☼ (absent)
    case ItemKind::Gem: return 4;             // measured ♦
    case ItemKind::Anvil: return 229;         // measured σ
    case ItemKind::CorpsePiece: return 253;   // measured ²
    case ItemKind::Remains: return 253;       // measured ²
    case ItemKind::Meat: return 37;           // assumed  % (absent)
    case ItemKind::Fish: return 37;           // assumed  % (absent)
    case ItemKind::FishRaw: return 37;        // assumed  % (absent)
    case ItemKind::Vermin: return 37;         // assumed  % (absent; creature tile first)
    case ItemKind::Pet: return 37;            // assumed  % (absent; creature tile first)
    case ItemKind::Seeds: return 250;         // measured · (colour: the plant SEED colour)
    case ItemKind::Plant: return 231;         // measured τ (the plant PICKED_TILE)
    case ItemKind::SkinTanned: return 225;    // measured ß
    case ItemKind::PlantGrowth: return 6;     // measured ♠ leaves / 37 % fruit (GROWTH_PRINT)
    case ItemKind::Thread: return 237;        // measured φ (webs: 15 ☼)
    case ItemKind::Cloth: return 167;         // measured º
    case ItemKind::Totem: return 15;          // assumed  ☼ (absent)
    case ItemKind::Pants: return 91;          // measured [
    case ItemKind::Backpack: return 146;      // measured Æ
    case ItemKind::Quiver: return 146;        // measured Æ
    case ItemKind::CatapultParts: return 216; // assumed  ╪ (absent)
    case ItemKind::BallistaParts: return 216; // assumed  ╪ (absent)
    case ItemKind::SiegeAmmo: return 47;      // assumed  / (absent)
    case ItemKind::BallistaArrowhead: return 47;// assumed  / (absent)
    case ItemKind::TrapParts: return 128;     // measured Ç
    case ItemKind::TrapComp: return 228;      // measured ε
    case ItemKind::Drink: return 247;         // measured ≈
    case ItemKind::PowderMisc: return 176;    // measured ░
    case ItemKind::Cheese: return 37;         // assumed  % (absent)
    case ItemKind::Food: return 37;           // measured % (colour 6:0:0)
    case ItemKind::LiquidMisc: return 247;    // measured ≈
    case ItemKind::Coin: return 36;           // assumed  $ (absent)
    case ItemKind::Glob: return 37;           // assumed  % (absent)
    case ItemKind::Rock: return 7;            // assumed  • (absent)
    case ItemKind::PipeSection: return 205;   // assumed  ═ (absent)
    case ItemKind::HatchCover: return 155;    // measured ¢
    case ItemKind::Grate: return 35;          // assumed  # (absent)
    case ItemKind::Quern: return 177;         // assumed  ▒ (absent)
    case ItemKind::Millstone: return 177;     // assumed  ▒ (absent)
    case ItemKind::Splint: return 159;        // measured ƒ
    case ItemKind::Crutch: return 194;        // measured ┬
    case ItemKind::TractionBench: return 232; // measured Φ
    case ItemKind::OrthopedicCast: return 91; // assumed  [ (absent)
    case ItemKind::Tool: return 15;           // assumed  ☼ (itemdef TILE first; no tool without one was present)
    case ItemKind::Slab: return 239;          // measured ∩
    case ItemKind::Egg: return 37;            // assumed  % (absent)
    case ItemKind::Book: return 8;            // measured ◘
    case ItemKind::Sheet: return 245;         // measured §
    case ItemKind::Branch: return 240;        // assumed  ≡ (absent)
  }
  return 63;
}

bool itemTileMeasured(ItemKind kind) {
  switch (kind) {
    case ItemKind::Bar:
    case ItemKind::Blocks:
    case ItemKind::Rough:
    case ItemKind::Boulder:
    case ItemKind::Wood:
    case ItemKind::Door:
    case ItemKind::Floodgate:
    case ItemKind::Bed:
    case ItemKind::Chair:
    case ItemKind::Chain:
    case ItemKind::Flask:
    case ItemKind::Goblet:
    case ItemKind::Instrument:
    case ItemKind::Toy:
    case ItemKind::Cage:
    case ItemKind::Barrel:
    case ItemKind::Bucket:
    case ItemKind::Table:
    case ItemKind::Coffin:
    case ItemKind::Statue:
    case ItemKind::Corpse:
    case ItemKind::Weapon:
    case ItemKind::Armor:
    case ItemKind::Shoes:
    case ItemKind::Shield:
    case ItemKind::Helm:
    case ItemKind::Gloves:
    case ItemKind::Box:
    case ItemKind::Bag:
    case ItemKind::Bin:
    case ItemKind::Armorstand:
    case ItemKind::Weaponrack:
    case ItemKind::Cabinet:
    case ItemKind::Figurine:
    case ItemKind::Amulet:
    case ItemKind::Ammo:
    case ItemKind::Crown:
    case ItemKind::Ring:
    case ItemKind::Earring:
    case ItemKind::Gem:
    case ItemKind::Anvil:
    case ItemKind::CorpsePiece:
    case ItemKind::Remains:
    case ItemKind::Seeds:
    case ItemKind::Plant:
    case ItemKind::SkinTanned:
    case ItemKind::PlantGrowth:
    case ItemKind::Thread:
    case ItemKind::Cloth:
    case ItemKind::Pants:
    case ItemKind::Backpack:
    case ItemKind::Quiver:
    case ItemKind::TrapParts:
    case ItemKind::TrapComp:
    case ItemKind::Drink:
    case ItemKind::PowderMisc:
    case ItemKind::Food:
    case ItemKind::LiquidMisc:
    case ItemKind::HatchCover:
    case ItemKind::Splint:
    case ItemKind::Crutch:
    case ItemKind::TractionBench:
    case ItemKind::Slab:
    case ItemKind::Book:
    case ItemKind::Sheet:
      return true;
    default:
      return false;
  }
}

uint8_t assumedBuildingTile(BuildingKind kind) {
  switch (kind) {
    case BuildingKind::Shop: return 178;      // ▓ (a shop floor)
    case BuildingKind::Workshop: return 177;  // ▒ (the tool workshop, no vanilla layout)
    case BuildingKind::Furnace: return 177;   // ▒
    case BuildingKind::Unknown: return 63;    // ?
    default: return 79;                       // O: any other kind that lost its art
  }
}

namespace {

// wm::buildingKindName's spelling (the world model library is not linked
// into the asset provider; the names are the enum's, in order).
const char* buildingKindToken(BuildingKind kind) {
  static constexpr const char* kNames[] = {
      "Unknown",     "Chair",        "Bed",           "Table",         "Coffin",
      "FarmPlot",    "Furnace",      "TradeDepot",    "Shop",          "Door",
      "Floodgate",   "Box",          "Weaponrack",    "Armorstand",    "Workshop",
      "Cabinet",     "Statue",       "WindowGlass",   "WindowGem",     "Well",
      "Bridge",      "RoadDirt",     "RoadPaved",     "SiegeEngine",   "Trap",
      "AnimalTrap",  "Support",      "ArcheryTarget", "Chain",         "Cage",
      "Stockpile",   "Civzone",      "Weapon",        "Wagon",         "ScrewPump",
      "Hatch",       "GrateWall",    "GrateFloor",    "BarsVertical",  "BarsFloor",
      "GearAssembly", "AxleHorizontal", "AxleVertical", "WaterWheel",  "Windmill",
      "TractionBench", "Slab",       "Nest",          "NestBox",       "Hive",
      "Rollers",     "Instrument",   "Bookcase",      "DisplayFurniture", "OfferingPlace"};
  const auto i = static_cast<size_t>(kind);
  return i < sizeof(kNames) / sizeof(kNames[0]) ? kNames[i] : "?";
}

const wm::Glyph* asciiRow(const AssetIndex& index, const std::string& name) {
  auto it = index.asciiGraphics.find(name);
  return it == index.asciiGraphics.end() ? nullptr : &it->second;
}

}  // namespace

// Measured on DF 53.16 (tools/smoke/classic_glyph_probe.ps1:
// item::drawSelf / getsymbol and item::setDisplayColor per item, cross-
// checked on the classic-ASCII screen): the tile is the per-kind table
// with these rules on top -- a Boulder is the material's ITEM_SYMBOL (its
// default 7 is the boulder tile; magnetite '*'), a rough gem / small gem
// takes a non-default ITEM_SYMBOL, a cut Gem is always 4, a Tool its
// itemdef TILE, a Corpse the creature's tile in the creature's colour,
// a web (Thread + kItemWeb) 15. The colour is the material's BASIC_COLOR
// on black, except Door / Floodgate / Barrel / Bin / Cage / HatchCover
// (DF's setcolor puts the material colour in the background: fg 0),
// Food (always 6:0:0) and Remains (always 5:0:0).
ClassicGlyphChoice classicItemGlyph(const AssetIndex& index, ItemKind kind,
                                    const wm::MaterialGlyph* material, uint8_t itemDefTile,
                                    const wm::CreatureGlyph* creature, uint8_t itemFlags) {
  ClassicGlyphChoice c;
  const char* token = itemKindToken(kind);
  if (!*token) return c;
  if (const wm::Glyph* row = asciiRow(index, std::string("ITEM_") + token)) {
    c.found = true;
    c.glyph = *row;
    c.tileSource = GlyphSource::AsciiGraphics;
    return c;
  }
  c.found = true;
  c.glyph.fg = 7;
  c.glyph.bg = 0;
  c.glyph.bright = 0;
  if (material) {
    c.glyph.fg = material->basicFg;
    c.glyph.bright = material->basicBright;
    c.materialColour = true;
  }
  const GlyphSource table = itemTileMeasured(kind) ? GlyphSource::MeasuredTable : GlyphSource::AssumedTable;
  if (material && material->itemSymbol != 0 && kind == ItemKind::Boulder) {
    c.glyph.tile = material->itemSymbol;
    c.tileSource = GlyphSource::MaterialSymbol;
  } else if (material && material->itemSymbol != 0 && material->itemSymbol != 7 &&
             (kind == ItemKind::SmallGem || kind == ItemKind::Rough)) {
    c.glyph.tile = material->itemSymbol;
    c.tileSource = GlyphSource::MaterialSymbol;
  } else if (itemDefTile != 0 && kind == ItemKind::Tool) {
    c.glyph.tile = itemDefTile;
    c.tileSource = GlyphSource::ItemDefTile;
  } else if (creature && (kind == ItemKind::Vermin || kind == ItemKind::Pet || kind == ItemKind::Corpse)) {
    c.glyph.tile = creature->glyph.tile;
    c.glyph.fg = creature->glyph.fg;
    c.glyph.bg = creature->glyph.bg;
    c.glyph.bright = creature->glyph.bright;
    c.materialColour = false;
    c.tileSource = GlyphSource::CreatureTile;
  } else if (kind == ItemKind::Thread && (itemFlags & wm::kItemWeb)) {
    c.glyph.tile = 15;
    c.tileSource = GlyphSource::MeasuredTable;
  } else {
    c.glyph.tile = assumedItemTile(kind);
    c.tileSource = table;
  }
  switch (kind) {
    case ItemKind::Door:
    case ItemKind::Floodgate:
    case ItemKind::Barrel:
    case ItemKind::Bin:
    case ItemKind::Cage:
    case ItemKind::HatchCover:
      c.glyph.bg = c.glyph.fg;
      c.glyph.fg = 0;
      break;
    case ItemKind::Food:
      c.glyph.fg = 6; c.glyph.bg = 0; c.glyph.bright = 0;
      c.materialColour = false;
      break;
    case ItemKind::Remains:
      c.glyph.fg = 5; c.glyph.bg = 0; c.glyph.bright = 0;
      c.materialColour = false;
      break;
    default:
      break;
  }
  return c;
}

ClassicGlyphChoice classicBuildingGlyph(const AssetIndex& index, BuildingKind kind,
                                        const wm::MaterialGlyph* material) {
  ClassicGlyphChoice c;
  if (const wm::Glyph* row =
          asciiRow(index, std::string("BUILDING_") + buildingKindToken(kind))) {
    c.found = true;
    c.glyph = *row;
    c.tileSource = GlyphSource::AsciiGraphics;
    return c;
  }
  c.found = true;
  c.glyph.tile = assumedBuildingTile(kind);
  c.glyph.fg = 7;
  c.glyph.bg = 0;
  c.glyph.bright = 0;
  if (material) {
    c.glyph.fg = material->build.fg;
    c.glyph.bg = material->build.bg;
    c.glyph.bright = material->build.bright;
    c.materialColour = true;
  }
  c.tileSource = GlyphSource::AssumedTable;
  return c;
}

wm::Glyph classicCreatureGlyph(const wm::CreatureGlyph& c, bool soldier) {
  wm::Glyph g = c.glyph;
  if (soldier && c.soldierTile != 0) g.tile = c.soldierTile;
  return g;
}

}  // namespace df3d::assets
