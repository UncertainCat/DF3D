// Semantic terrain / creature / building / item -> texture region resolution over the asset index, mirroring how DF v50 draws (class tiles, STATE_COLOR palette rows, PLANT_GRAPHICS); pure.
#pragma once

#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "df3d_assets/asset_index.h"
#include "wm/types.h"

namespace df3d::assets {

enum class FaceSide : uint8_t { Top, Bottom, Side, Slope, Cross };
enum class FaceKind : uint8_t { Terrain, Feature, Liquid };
// The side a ramp wedge rises toward, in DF's compass (north = -y).
enum class SlopeDir : uint8_t { None, North, South, West, East };

struct TerrainQuery {
  wm::TileShape shape = wm::TileShape::Empty;
  wm::MaterialKind kind = wm::MaterialKind::None;
  std::string_view material;  // wm::WorldModel::materialName token ("" = none)
  uint8_t flags = 0;          // wm::kTile* bits
  FaceSide side = FaceSide::Top;
  FaceKind part = FaceKind::Terrain;
  wm::LiquidKind liquid = wm::LiquidKind::None;
  SlopeDir slope = SlopeDir::None;  // Ramp faces: the wedge's high side
  // Which of the tile's eight same-z neighbours are cubes (kWall* bits
  // below); selects the wall family member for a wall's top face.
  uint8_t walls = 0;
  uint8_t completedTrack = 0; // native completed N=1,S=2,E=4,W=8
};

// TerrainQuery::walls bits (mirrors df3d::mesher::kWall*; DF compass,
// north = -y).
inline constexpr uint8_t kWallN = 1u << 0;
inline constexpr uint8_t kWallS = 1u << 1;
inline constexpr uint8_t kWallW = 1u << 2;
inline constexpr uint8_t kWallE = 1u << 3;
inline constexpr uint8_t kWallNW = 1u << 4;
inline constexpr uint8_t kWallNE = 1u << 5;
inline constexpr uint8_t kWallSW = 1u << 6;
inline constexpr uint8_t kWallSE = 1u << 7;

// Exposed cardinal edges in N,S,W,E order (the inverse of occupied
// neighbors). Empty when all four cardinal neighbors are solid.
std::string wallVariantSuffix(uint8_t walls);
// Cardinal edge member, then open diagonals between solid cardinals (native DF composites them); enclosed = empty, pillar = N_S_W_E.
std::vector<std::string> wallTopSuffixes(uint8_t walls);

// DF terrain colouring (README "Recolouring"): `paletteRow` swaps keyed pixels, `fill` composites over the row's base colour.
struct TerrainSprite {
  bool found = false;
  SpriteRef sprite;
  // Wall tops only: sprite names the family for caching; wallLayers composite over the rock backing (empty = plain rock).
  bool layeredWall = false;
  std::vector<SpriteRef> wallLayers;
  std::string colorName;  // STATE_COLOR id of the material ("" = none)
  int paletteRow = -1;    // palette row for colorName (-1 = default row)
  bool tinted = false;    // colorName has a descriptor RGB (`tint`), for
  Rgb tint;               // tools and palette-less fallbacks
  bool fill = false;      // composite the tile over the palette base colour
  bool cutout = false;    // alpha-tested plane (plant crosses)
  const char* rule = "none";  // which rule produced it (or why none)
};

TerrainSprite resolveTerrain(const AssetIndex& index, const TerrainQuery& q);

// Creature states in the simple graphics format.
enum class CreatureState : uint8_t { Default, Child, Animated, Corpse, TrainedWar, TrainedHunter };

struct CreatureSprite {
  bool found = false;
  bool layered = false;  // species uses LAYER_SET: no simple sprite
  SpriteRef sprite;
  const char* rule = "none";
};

// species = creature raw id; falls back to the DEFAULT state, then the first CREATURE_CASTE_GRAPHICS.
CreatureSprite resolveCreature(const AssetIndex& index, std::string_view species,
                               CreatureState state = CreatureState::Default);

const char* creatureStateToken(CreatureState s);

// --- buildings and map items --- pages drawn per material class (_WOOD/_STONE/_METAL/_GLASS) and palette-recoloured per material.
enum class MaterialClass : uint8_t { Unknown = 0, Wood, Stone, Metal, Glass };
MaterialClass materialClassOf(const AssetIndex& index, std::string_view token);
const char* materialClassToken(MaterialClass c);  // "WOOD", "STONE", ... ("" = Unknown)

struct BuildingQuery {
  wm::BuildingKind kind = wm::BuildingKind::Unknown;
  uint16_t subtype = wm::kNoSubtype;  // DF per-kind subtype (workshop_type, ...)
  std::string_view custom;            // custom workshop / furnace code
  wm::BuildingStage stage = wm::BuildingStage::Complete;
  int width = 1, height = 1;
  std::string_view material;  // wm material token ("" = none)
  uint8_t flags = 0;          // wm::kBuilding* bits
  // Row-major width*height occupancy (wm::Building::extents); nullptr/empty = whole rectangle; edge decals read it.
  const std::vector<uint8_t>* extents = nullptr;
};

// One sprite for building tile (lx, ly); a tile may carry several in draw order.
struct BuildingTile {
  // Drawing coordinates may spill outside the semantic building footprint
  // (e.g. the north half of a stockpile rope). They do not imply occupancy.
  int lx = 0, ly = 0;
  SpriteRef sprite;
  // Native foreground artwork is drawn above creatures. This is presentation
  // metadata only; negative drawing rows do not expand semantic occupancy.
  bool foreground = false;
};

struct BuildingSprites {
  bool found = false;
  std::vector<BuildingTile> tiles;
  std::string colorName;  // STATE_COLOR id of the material ("" = none)
  int paletteRow = -1;    // palette row for colorName (-1 = as painted)
  bool decal = false;     // floor decal drawn under everything else (stockpiles, zones, farms, roads)
  bool stageArt = false;  // the tiles are the raws' own in-progress art
  const char* rule = "none";
};

// Every occupied tile gets a sprite when the kind resolves; unknown kinds yield found = false with the rule saying why.
BuildingSprites resolveBuildingTiles(const AssetIndex& index, const BuildingQuery& q);

// Layout name a building kind/subtype/custom code resolves to (WORKSHOP_MASON, TRADE_DEPOT, ...); "" when not layout-drawn.
std::string buildingLayoutName(wm::BuildingKind kind, uint16_t subtype, std::string_view custom);

struct ItemQuery {
  wm::ItemKind kind = wm::ItemKind::Unknown;
  std::string_view subtypeRaw;  // itemdef raw id ("ITEM_WEAPON_PICK"), "" = none
  std::string_view material;    // wm material token
  uint8_t flags = 0;            // wm::kItem* bits
  uint32_t stack = 1;
  // Corpse flags (wm::kCorpse* bits) and the item id, which picks deterministic variants.
  uint16_t corpseFlags = 0;
  uint32_t id = 0;
};

struct ItemSprite {
  bool found = false;
  SpriteRef sprite;
  std::string colorName;
  int paletteRow = -1;
  // The sprite is a body-part / bone-pile tile (BODYPART_*, GUTS_*,
  // SKELETON) chosen from the corpse flags rather than the creature's art.
  bool bodyPart = false;
  const char* rule = "none";
};

// Body-part tile name for a CorpsePiece: by corpse flags first, then the material token's tissue, else BODYPART_LARGE_1.
std::string corpsePieceTileName(uint16_t corpseFlags, std::string_view material, uint32_t id);

ItemSprite resolveItem(const AssetIndex& index, const ItemQuery& q);

}  // namespace df3d::assets
