// The parsed asset index: what DF3D reads out of the install's raws.
//
// Everything here is *derived* from the user's Dwarf Fortress install at
// runtime: tile pages (name -> PNG + tile geometry), the
// named tile graphics of the environment mod, plant graphics (grass,
// shrub, sapling, per-species tree tiles), simple-format creature
// graphics, and material colours (STATE_COLOR through templates, resolved
// to RGB through the colour descriptors). Nothing visual is invented; the
// index is a lookup structure over the raws and is what the cache stores.
#pragma once

#include <array>
#include <cstdint>
#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

#include "wm/types.h"

namespace df3d::assets {

struct TilePage {
  std::string name;
  std::string file;     // as written in the raw, relative to the mod's graphics dir
  std::string absPath;  // resolved absolute path of the PNG
  int tileW = 32, tileH = 32;
  int pageW = 0, pageH = 0;  // pixels (from PAGE_DIM_PIXELS or PAGE_DIM * tile)
};

// A rectangle of tiles on a page (inclusive raw coordinates converted to
// origin + size). page < 0 means "none".
struct SpriteRef {
  int page = -1;
  int x = 0, y = 0;  // tile column / row
  int w = 1, h = 1;  // tiles
  bool valid() const { return page >= 0; }
  friend bool operator==(const SpriteRef&, const SpriteRef&) = default;
};

struct PixelRect {
  int page = -1;
  int px = 0, py = 0, pw = 0, ph = 0;
  bool valid() const { return page >= 0; }
};

struct Rgb {
  uint8_t r = 0, g = 0, b = 0;
  friend bool operator==(const Rgb&, const Rgb&) = default;
};

struct PlantGraphics {
  std::array<SpriteRef, 4> grass{};  // GRASS_1..GRASS_4
  SpriteRef shrub, shrubDead, sapling;
  std::unordered_map<std::string, SpriteRef> treeTiles;  // TREE_TILE:<NAME>
  // Item forms of the plant (graphics_plant_*.txt): PICKED (the plant
  // item), SEED, and the first GROWTH_PICKED (a picked fruit / leaf).
  SpriteRef picked, seed, growthPicked;
};

// A multi-tile building layout (graphics_workshops.txt, graphics_buildings
// .txt, graphics_machines.txt): `TILE_GRAPHICS:PAGE:x:y:NAME:stage:lx:ly`
// per tile and construction stage (0 = just started .. 3 = complete for
// workshops / furnaces / depots; the 1x1 shops carry stage 1 only), or
// `NAME:lx:ly` without a stage (windmills, water wheels, siege engines,
// wagons). A custom workshop is `WORKSHOP_CUSTOM:CODE:stage:lx:ly` and is
// keyed as "WORKSHOP_CUSTOM:CODE". Vanilla layouts carry one row more
// than the building is tall: row 0 is art "sticking up above the shop"
// (drawn on the tile north of it); the resolver maps building tile (i, j)
// to layout tile (i, j + height - buildingHeight).
inline constexpr int kLayoutNoStage = -1;
struct BuildingLayout {
  int width = 0, height = 0;  // extent of (lx, ly) seen, plus one
  // stage -> row-major width*height sprites (invalid = no tile there).
  std::map<int, std::vector<SpriteRef>> stages;
  // The sprite for a tile at a stage: the exact stage, else the highest
  // stage below it, else the lowest stage present; nullptr when the
  // layout has no tile there or is empty.
  const SpriteRef* tile(int stage, int lx, int ly) const;
  // The stage the lookup above would use (kLayoutNoStage - 2 when empty).
  int stageFor(int stage) const;
};

// Graphics of one itemdef raw (graphics_items.txt): the block header's
// sprite (WEAPON_GRAPHICS_DEFAULT, the inline TOOL_GRAPHICS / ARMOR_
// GRAPHICS / ... sprite) and its variants keyed by the token suffix:
// "WOOD", "STONE", "METAL", "GLASS" (TOOL_GRAPHICS_<MAT>:ALL:PAGE:x:y and
// TOY_GRAPHICS:...:NAME:<MAT>), "WOOD_GROWN", "ARTIFACT", "SPECIAL_MAT",
// "MATERIAL" (weapons), "STRAIGHT_DEFAULT" / "STRAIGHT_WOOD" (ammo),
// "WEAPON_TRAP" (trap components / weapons in a weapon trap), "WOODEN"
// (shields), "HIVE_BLD" / "HIVE_BLD_IN_USE" (the hive as a building),
// "CONTAINER_WOOD_LIQUID" ... (large pots).
struct ItemDefGraphics {
  SpriteRef base;
  std::unordered_map<std::string, SpriteRef> variants;
};

struct CreatureGraphics {
  // State token -> sprite: DEFAULT, CHILD, BABY, ANIMATED, CORPSE,
  // TRAINED_WAR, TRAINED_HUNTER, ... (first occurrence wins; conditions
  // after the sprite are ignored in this pass).
  std::unordered_map<std::string, SpriteRef> states;
  bool layered = false;  // has a LAYER_SET (dwarves etc.): not resolved here
};

// Material flags gathered from the material's own tokens and its template.
inline constexpr uint32_t kMatMetal = 1u << 0;
inline constexpr uint32_t kMatStone = 1u << 1;
inline constexpr uint32_t kMatGem = 1u << 2;
inline constexpr uint32_t kMatSoil = 1u << 3;
inline constexpr uint32_t kMatSand = 1u << 4;
inline constexpr uint32_t kMatGlass = 1u << 5;
inline constexpr uint32_t kMatWood = 1u << 6;

struct MaterialDef {
  std::string solidColor;  // STATE_COLOR ALL_SOLID / ALL / SOLID descriptor name ("" = unset)
  std::string liquidColor;
  std::string mapDescriptor; // Installed *_MAP_DESCRIPTOR material token.
  int displayFg = -1, displayBg = 0, displayBright = 0;  // DISPLAY_COLOR
  uint32_t flags = 0;
  std::string templateName;
};

// DF's recolour mechanism (vanilla_descriptors_graphics/graphics/
// palette_default.txt): palettes.png row `defaultRow` holds the key
// colours the terrain pages are painted in; PALETTE_COLOR:<COLOR>:<row>
// names the replacement ramp for a material whose STATE_COLOR is <COLOR>.
struct Palette {
  std::string name;
  std::string file, absPath;
  int defaultRow = 0;
  std::unordered_map<std::string, int> rows;  // colour id -> row
};

struct IndexStats {
  int rawFiles = 0, graphicsFiles = 0, tilePageFiles = 0;
  int tilePages = 0, duplicatePages = 0;
  int tileGraphics = 0;
  int plantGraphics = 0, grassPlants = 0, treePlants = 0;
  int creatureGraphics = 0, creatureSimple = 0, creatureLayered = 0, creatureCastes = 0;
  int colors = 0, materialTemplates = 0, inorganics = 0, plants = 0;
  int buildingLayouts = 0, layoutTiles = 0, itemDefs = 0, itemVariants = 0, materialItems = 0;
  int asciiGraphics = 0;  // ASCII_GRAPHICS rows (graphics_classic.txt)
};

struct AssetIndex {
  std::string buildId;
  uint64_t contentHash = 0;

  std::vector<TilePage> pages;
  std::unordered_map<std::string, int> pageByName;
  // TILE_GRAPHICS name -> variants in raw order (STONE_WALL_N_S_W_E_1 is
  // one name; FIRE:1..4 frames land on one name too).
  std::unordered_map<std::string, std::vector<SpriteRef>> tileGraphics;
  std::unordered_map<std::string, PlantGraphics> plants;
  std::unordered_map<std::string, CreatureGraphics> creatures;
  // CREATURE_CASTE_GRAPHICS: creature id -> first caste's graphics
  std::unordered_map<std::string, CreatureGraphics> creatureCastes;
  std::unordered_map<std::string, Rgb> colors;  // descriptor COLOR id -> RGB
  std::unordered_map<std::string, MaterialDef> materialTemplates;
  std::unordered_map<std::string, std::unordered_map<std::string, MaterialDef>> creatureMaterials;
  std::unordered_map<std::string, std::string> creatureMaterialParents;
  std::unordered_map<std::string, MaterialDef> inorganics;
  // plant id -> material name (STRUCTURAL, WOOD, LEAF, ...) -> def
  std::unordered_map<std::string, std::unordered_map<std::string, MaterialDef>> plantMaterials;
  std::optional<Palette> palette;  // the first [PALETTE:...] block seen
  // Building layouts keyed by name ("WORKSHOP_MASON", "FURNACE_SMELTER",
  // "TRADE_DEPOT", "WORKSHOP_CUSTOM:SOAP_MAKER", "WINDMILL_S_1", ...).
  std::unordered_map<std::string, BuildingLayout> buildingLayouts;
  // Itemdef graphics keyed by the itemdef raw id ("ITEM_WEAPON_PICK",
  // "ITEM_TOOL_NEST_BOX", "ITEM_ARMOR_BREASTPLATE", "ITEM_AMMO_BOLTS").
  std::unordered_map<std::string, ItemDefGraphics> itemDefs;
  // Per-material item sprites: BOULDER_GRAPHICS keyed "INORGANIC:<id>",
  // BARS_GRAPHICS keyed by its material args joined with ':' ("POTASH",
  // "COAL:COKE"), ROUGH_GEM_GRAPHICS keyed by the inorganic id.
  std::unordered_map<std::string, SpriteRef> boulderGraphics;
  std::unordered_map<std::string, SpriteRef> barsGraphics;
  std::unordered_map<std::string, SpriteRef> roughGemGraphics;
  // Classic-mode glyphs (graphics_classic.txt): `ASCII_GRAPHICS:
  // tile:fg:bg:bright:NAME[:x[:y]]` rows keyed by NAME, first row wins
  // (a multi-cell name keeps its first cell). The tile is a code point or
  // a quoted character. Vanilla 53.16 names only interface art here.
  std::unordered_map<std::string, wm::Glyph> asciiGraphics;
  IndexStats stats;
  // Pages referenced by graphics before their TILE_PAGE was seen: name ->
  // placeholder index in `pages`, resolved when the definition arrives.
  std::unordered_map<std::string, int> pendingPages;

  int pageIndex(std::string_view name) const;
  const SpriteRef* tile(std::string_view name, size_t variant = 0) const;
  const BuildingLayout* layout(std::string_view name) const;
  const ItemDefGraphics* itemDef(std::string_view rawId) const;
  const TilePage* page(int idx) const {
    return idx >= 0 && idx < static_cast<int>(pages.size()) ? &pages[idx] : nullptr;
  }
  PixelRect pixels(const SpriteRef& s) const;

  // Solid-state colour id (STATE_COLOR ALL_SOLID) of a world-model material
  // token (INORGANIC:GRANITE, PLANT:OAK:WOOD, PLANT:MEADOW-GRASS:STRUCTURAL,
  // ...); "" when the material is unknown or has none. CLEAR is a real
  // palette row in v50 and is returned as such.
  std::string_view materialColorName(std::string_view token) const;
  std::string_view materialSpatterFamily(std::string_view token, bool liquid = true) const;
  // Its descriptor RGB; nullopt when unknown or the colour has no RGB.
  std::optional<Rgb> materialColor(std::string_view token) const;
  // Palette row for a colour id (-1 when no palette or the colour has none).
  int paletteRow(std::string_view color) const;
  // Flags for the token (0 when unknown).
  uint32_t materialFlags(std::string_view token) const;
  // The raw id part of a token: INORGANIC:X -> X, PLANT:X:MAT -> X.
  static std::string_view materialRawId(std::string_view token);
};

// --- parsing (pure over text; tier-0 testable) ---

// Feeds one raw file into the index. `graphicsDir` is the directory the
// file lives in (tile page FILE entries are relative to it); `sourceName`
// is used in diagnostics. Files whose OBJECT type is not consumed are
// counted and skipped. Returns the number of tokens consumed.
size_t ingestRawText(AssetIndex& index, std::string_view text, const std::string& graphicsDir,
                     const std::string& sourceName, std::vector<std::string>* diagnostics);

// Finalises cross-references after all files were ingested (resolves
// pages named by graphics tokens that appeared before their TILE_PAGE).
void finalizeIndex(AssetIndex& index);

// Parses a single creature state token's sprite arguments starting at
// args[first] : PAGE [LARGE_IMAGE] x y [x2 y2] [AS_IS|ADD_COLOR] [cond..].
// Returns nullopt when the shape does not match.
std::optional<SpriteRef> parseSpriteArgs(const AssetIndex& index,
                                         const std::vector<std::string>& args, size_t first,
                                         std::unordered_map<std::string, int>* pendingPages);

// --- cache serialisation (text, tab separated) ---
std::string serializeIndex(const AssetIndex& index);
bool deserializeIndex(std::string_view text, AssetIndex& out, std::string& err);
// Reads only the header line; false when it is not a DF3D index.
bool peekIndexKey(std::string_view text, std::string& buildId, uint64_t& hash);

}  // namespace df3d::assets
