#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace wm {

using Tick = uint64_t;
using UnitId = uint64_t;

struct TilePos {
  int32_t x = 0, y = 0, z = 0;
  friend bool operator==(const TilePos&, const TilePos&) = default;
};

// Continuous position in tile coordinates (interpolation output).
struct Vec3 {
  float x = 0, y = 0, z = 0;
  friend bool operator==(const Vec3&, const Vec3&) = default;
};

struct EventItem {
  int32_t id = -1;
  std::string type, subtypeRaw, material;
  uint32_t materialFlags = 0;
  bool materialFlagsKnown = false;
  std::string meleeSkill;
};

struct AttackContact { EventItem first, second; };
enum class AttackDamageFlag : uint32_t {
  Cut=1, Smashed=2, SmashedApart=4, Broken=8, Gouged=16, CompoundFracture=32,
  MotorNerveSevered=64, SensoryNerveSevered=128, MajorArtery=256, GutsSpilled=512
};
enum class AttackAnatomyFlag : uint32_t { Head=1, Thought=2, Circulation=4, Throat=8, Internal=16 };
struct AttackWoundPart {
  int32_t bodyPartId = -1, layerId = -1;
  std::string bodyPartToken, bodyPartCategory;
  uint32_t damageFlags = 0, anatomyFlags = 0;
};
struct AttackWound {
  int32_t woundId = -1, victimId = -1;
  bool severedPart = false, poppedOut = false;
  std::vector<AttackWoundPart> parts;
  bool partsComplete = false;
};
enum class ProjectileCombatKind : uint8_t { Unknown, Release, HitCreature, Blocked, GroundImpact };
enum class WeaponLauncher : uint8_t { Unknown, Bow, Crossbow, Ballista };
struct ProjectileCombatEvent {
  uint64_t id=0, tick=0;
  int32_t projectileId=-1, sourceUnitId=-1, targetUnitId=-1;
  ProjectileCombatKind kind=ProjectileCombatKind::Unknown;
  WeaponLauncher launcher=WeaponLauncher::Unknown;
  EventItem ammunition, weapon;
  TilePos pos;
  bool contextComplete=false;
};

enum class AttackOutcome : uint8_t { Unknown, Miss, Hit, Blocked, ParrySuccess, ParryFailed, Wrestle };
struct ResolvedAttack {
  uint64_t id = 0;
  Tick tick = 0;
  int32_t attackerId = -1, defenderId = -1, actionId = -1;
  EventItem weapon;
  TilePos pos;
  std::vector<AttackContact> contacts;
  bool equipmentContactsComplete = false;
  std::vector<AttackWound> wounds;
  bool woundsComplete = false;
  AttackOutcome outcome = AttackOutcome::Unknown;
  bool outcomeComplete = false, weaponContextComplete = false;
};
struct ItemContactEvent {
  uint64_t id = 0;
  Tick tick = 0;
  EventItem first{}, second{};
  TilePos pos{};
};

struct ProjectileSample {
  uint64_t sequence = 0, projectileId = 0;
  Tick tick = 0;
  int32_t itemId = -1, firerId = -1;
  TilePos pos{}, previous{}, origin{}, target{};
  bool active = true, firstObserved = false;
  EventItem ammunition{}, launcher{};
};
struct ProjectileState {
  uint64_t id = 0;
  int32_t itemId = -1, firerId = -1;
  Vec3 pos{}, direction{};
};

enum class CombatEventKind : uint8_t { Wound = 1, Death = 2 };
struct CombatEvent {
  uint64_t id = 0;
  Tick tick = 0;
  CombatEventKind kind = CombatEventKind::Wound;
  int32_t attackerId = -1, victimId = -1, woundId = -1;
  TilePos pos{};
  int32_t reportId = -1, sourceActionId = -1;
  EventItem weapon{};
};

struct ReportEvent {
  uint64_t id = 0;
  Tick tick = 0;
  int32_t reportId = -1;
  std::string type;
  TilePos pos{-1,-1,-1}, pos2{-1,-1,-1};
  bool hasPosition = false, hasSecondary = false;
  uint32_t repeatCount = 0;
  int32_t speakerId = -1;
};

// Semantic snapshot state. Bit positions are append-only (UnitState.status_flags).
namespace UnitStatus {
constexpr uint64_t Sleeping=1ULL<<0, Webbed=1ULL<<1, Stunned=1ULL<<2,
    Unconscious=1ULL<<3, Fey=1ULL<<4, Secretive=1ULL<<5, Possessed=1ULL<<6,
    Macabre=1ULL<<7, Fell=1ULL<<8, Melancholy=1ULL<<9, Raving=1ULL<<10,
    Berserk=1ULL<<11, Traumatized=1ULL<<12, TellingStory=1ULL<<13,
    RecitingPoetry=1ULL<<14, PerformingMusic=1ULL<<15, Dancing=1ULL<<16,
    Migrant=1ULL<<17, NoJob=1ULL<<18, NoDestination=1ULL<<19,
    Hungry=1ULL<<20, Thirsty=1ULL<<21, Drowsy=1ULL<<22,
    Stressed=1ULL<<23, Distracted=1ULL<<24, Tantrum=1ULL<<25,
    Oblivious=1ULL<<26, Depression=1ULL<<27, Enraged=1ULL<<28,
    MartialTrance=1ULL<<29, Terrified=1ULL<<30, Wrestling=1ULL<<31,
    MinorInjury=1ULL<<32, MajorInjury=1ULL<<33, Paralyzed=1ULL<<34,
    Nausea=1ULL<<35, Winded=1ULL<<36, Fevered=1ULL<<37,
    Yielding=1ULL<<38, PlayingMakeBelieve=1ULL<<39,
    Projectile=1ULL<<40, Grounded=1ULL<<41, Climbing=1ULL<<42, Baby=1ULL<<43;
}

// Semantic observation of a melee action, never an inferred hit. Counters
// are sampled at first observation of this identity; observedAt is that tick.
struct UnitAttack {
  int32_t actionId = -1;
  int32_t targetId = -1;
  int32_t timer1 = 0, timer2 = 0;
  Tick observedAt = 0;
};

// Must stay value-compatible with df3d.mirror.JobKind (append-only).
enum class JobKind : uint16_t {
  Idle = 0,
  Mine,
  HaulItem,
  ConstructBuilding,
  Sleep,
  Eat,
  Drink,
  Fight,
  Flee,
};

const char* jobName(JobKind job);

// --- Terrain ---
// Plain-old-data at the boundary so a C-ABI adapter can pass these through
// unchanged. Values mirror the schema enums one-for-one (append-only).

enum class TileShape : uint8_t {
  Empty = 0,  // open air / nothing here
  Wall,
  Floor,
  Ramp,
  RampTop,  // the open tile above a ramp
  StairUp,
  StairDown,
  StairUpDown,
  Fortification,
  Boulder,
  Pebbles,
  TreeTrunk,
  TreeBranch,
  Shrub,
  Sapling,
  Unknown,  // bridge could not classify; treat as opaque
};

enum class MaterialKind : uint8_t {
  None = 0,
  Stone,
  Soil,
  Mineral,  // ore / gem veins embedded in stone layers
  Gem,
  Ice,
  Wood,
  Plant,
  Grass,
  Constructed,
  Water,
  Magma,
  Unknown,
};

enum class LiquidKind : uint8_t {
  None = 0,
  Water,
  Magma,
};

// TileState::flags bits.
inline constexpr uint8_t kTileHidden = 1u << 0;         // not yet revealed to the player
inline constexpr uint8_t kTileDigDesignated = 1u << 1;  // any dig/channel/ramp/stair designation
inline constexpr uint8_t kTileSmooth = 1u << 2;
inline constexpr uint8_t kTileEngraved = 1u << 3;
inline constexpr uint8_t kTileOutside = 1u << 4;  // open to the sky
// v6: pending smooth / engrave designations (the work is not done
// yet; kTileSmooth / kTileEngraved are the finished states).
inline constexpr uint8_t kTileSmoothDesignated = 1u << 5;
inline constexpr uint8_t kTileEngraveDesignated = 1u << 6;
inline constexpr uint8_t kTileDigAuto = 1u << 7;

// Model-wide material identifier (stable for the life of a WorldModel;
// resolve with WorldModel::materialName). kNoMaterial = the tile has none.
using MaterialId = uint16_t;
inline constexpr MaterialId kNoMaterial = 0xFFFF;
inline constexpr uint8_t kMaxLiquidLevel = 7;

enum class DesignationKind : uint8_t {
  None=0, Dig, Channel, StairUp, StairDown, StairUpDown, Ramp,
  RemoveConstruction, Chop, Gather, Smooth, Engrave, Fortify, Unknown
};

// One tile's semantic state, no indirection.
struct TileState {
  TileShape shape = TileShape::Empty;
  MaterialKind materialKind = MaterialKind::None;
  MaterialId material = kNoMaterial;
  uint8_t liquidLevel = 0;  // 0..7; 0 iff liquidKind == None
  LiquidKind liquidKind = LiquidKind::None;
  uint8_t flags = 0;  // kTile* bits
  DesignationKind designation = DesignationKind::None;
  uint8_t designationPriority = 0; // 0 unknown, 1..7
  bool designationMarker = false;
  uint8_t track = 0;
  uint8_t traffic = 0;
  uint8_t warnings = 0;
  uint8_t subterranean : 1 = false;
  uint8_t brookTop : 1 = false;
  uint8_t root : 1 = false; // native root tissue, distinct from trunk wood
  uint8_t buildingOccupancy : 3 = 0; // native occupancy, independent of room extents
  uint8_t trackClearanceBlocked : 1 = false;
  uint8_t trackHorizontalBlocked : 1 = false;
  uint8_t trackSupport : 1 = false;
  uint8_t trackOpen : 1 = false;
  uint8_t completedTrack : 4 = 0; // finished tile connections, independent of track designation
  friend bool operator==(const TileState&, const TileState&) = default;
};
static_assert(sizeof(TileState) == 16);

// Terrain is stored at DF map-block granularity: 16x16 tiles at one z.
inline constexpr int32_t kBlockSize = 16;
inline constexpr uint32_t kTilesPerBlock = 256;

// Block coordinates: tile x = bx*16 + local x; bz is the z level itself.
struct BlockPos {
  int32_t bx = 0, by = 0, bz = 0;
  friend bool operator==(const BlockPos&, const BlockPos&) = default;
  friend bool operator<(const BlockPos& a, const BlockPos& b) {
    return a.bz != b.bz ? a.bz < b.bz : a.by != b.by ? a.by < b.by : a.bx < b.bx;
  }
};

inline constexpr BlockPos blockOf(TilePos p) {
  return BlockPos{p.x / kBlockSize, p.y / kBlockSize, p.z};
}
// Index into a block's 256 tiles (row-major, local y outer, local x inner).
inline constexpr uint32_t tileIndexInBlock(int32_t localX, int32_t localY) {
  return static_cast<uint32_t>(localY) * kBlockSize + static_cast<uint32_t>(localX);
}

// --- Unit appearance references (schema v3) ---
// The one ruled exception to "semantic vocabulary only": how DF draws a
// unit, as DF resolved it, expressed as references into the install's
// graphics raws (tile page token, tile coordinates, palette file, palette
// row). Never pixels. Presentations resolve them through the asset
// provider against the user's install.

// Model-wide ids (stable for the life of a WorldModel; resolve with
// WorldModel::tilePageName / paletteName). kNoPalette = drawn as-is.
using PageId = uint16_t;
using PaletteId = uint16_t;
inline constexpr PaletteId kNoPalette = 0xFFFF;
// A layer whose page reference could not be resolved (index outside the
// snapshot's table, or the model's page table is full). Never a real page.
inline constexpr PageId kNoPage = 0xFFFF;
inline constexpr int16_t kNoPaletteRow = -1;

// One drawn layer: a `cellsX` x `cellsY` tile region of a page starting at
// (tileX, tileY), optionally recoloured by swapping the palette file's
// `paletteKeyRow` colours for its `paletteRow` colours, drawn at a pixel
// offset. 16 bytes, no indirection.
struct AppearanceLayer {
  PageId page = 0;
  uint16_t tileX = 0, tileY = 0;
  uint8_t cellsX = 1, cellsY = 1;
  PaletteId palette = kNoPalette;
  int16_t paletteRow = kNoPaletteRow, paletteKeyRow = kNoPaletteRow;
  int8_t offsetX = 0, offsetY = 0;
  friend bool operator==(const AppearanceLayer&, const AppearanceLayer&) = default;
};
static_assert(sizeof(AppearanceLayer) == 16);

const char* tileShapeName(TileShape s);
const char* materialKindName(MaterialKind k);
const char* liquidKindName(LiquidKind k);

// --- Buildings and map items (schema v4) ---
// Keyed by DF's own ids. Values mirror the schema enums one-for-one
// (append-only); the mapping is static_asserted in mirror_ingest.cpp.

using BuildingId = uint32_t;
using ItemId = uint32_t;
inline constexpr uint16_t kNoSubtype = 0xFFFF;

// DF's building_type in df-structures order, offset by one (0 = Unknown).
// Constructions are terrain, never buildings.
enum class BuildingKind : uint8_t {
  Unknown = 0,
  Chair,
  Bed,
  Table,
  Coffin,
  FarmPlot,
  Furnace,      // subtype = DF furnace_type
  TradeDepot,
  Shop,         // subtype = DF shop_type
  Door,
  Floodgate,
  Box,
  Weaponrack,
  Armorstand,
  Workshop,     // subtype = DF workshop_type
  Cabinet,
  Statue,
  WindowGlass,
  WindowGem,
  Well,
  Bridge,
  RoadDirt,
  RoadPaved,
  SiegeEngine,  // subtype = DF siegeengine_type
  Trap,         // subtype = DF trap_type
  AnimalTrap,
  Support,
  ArcheryTarget,
  Chain,
  Cage,
  Stockpile,
  Civzone,      // subtype = DF civzone_type
  Weapon,
  Wagon,
  ScrewPump,
  Hatch,
  GrateWall,
  GrateFloor,
  BarsVertical,
  BarsFloor,
  GearAssembly,
  AxleHorizontal,
  AxleVertical,
  WaterWheel,
  Windmill,
  TractionBench,
  Slab,
  Nest,
  NestBox,
  Hive,
  Rollers,
  Instrument,
  Bookcase,
  DisplayFurniture,
  OfferingPlace,
  Construction,
};

enum class BuildingStage : uint8_t { Planned = 0, InProgress, Complete };

// Building::flags bits.
inline constexpr uint8_t kBuildingForbidden = 1u << 0;
inline constexpr uint8_t kBuildingRoomAssigned = 1u << 1;

// DF's item_type in df-structures order, offset by one (0 = Unknown).
enum class ItemKind : uint8_t {
  Unknown = 0,
  Bar,
  SmallGem,
  Blocks,
  Rough,
  Boulder,
  Wood,
  Door,
  Floodgate,
  Bed,
  Chair,
  Chain,
  Flask,
  Goblet,
  Instrument,
  Toy,
  Window,
  Cage,
  Barrel,
  Bucket,
  AnimalTrap,
  Table,
  Coffin,
  Statue,
  Corpse,
  Weapon,
  Armor,
  Shoes,
  Shield,
  Helm,
  Gloves,
  Box,
  Bag,
  Bin,
  Armorstand,
  Weaponrack,
  Cabinet,
  Figurine,
  Amulet,
  Scepter,
  Ammo,
  Crown,
  Ring,
  Earring,
  Bracelet,
  Gem,
  Anvil,
  CorpsePiece,
  Remains,
  Meat,
  Fish,
  FishRaw,
  Vermin,
  Pet,
  Seeds,
  Plant,
  SkinTanned,
  PlantGrowth,
  Thread,
  Cloth,
  Totem,
  Pants,
  Backpack,
  Quiver,
  CatapultParts,
  BallistaParts,
  SiegeAmmo,
  BallistaArrowhead,
  TrapParts,
  TrapComp,
  Drink,
  PowderMisc,
  Cheese,
  Food,
  LiquidMisc,
  Coin,
  Glob,
  Rock,
  PipeSection,
  HatchCover,
  Grate,
  Quern,
  Millstone,
  Splint,
  Crutch,
  TractionBench,
  OrthopedicCast,
  Tool,
  Slab,
  Egg,
  Book,
  Sheet,
  Branch,
};

// MapItem::flags bits (DF item.flags of the same name).
inline constexpr uint8_t kItemForbidden = 1u << 0;
inline constexpr uint8_t kItemDump = 1u << 1;
inline constexpr uint8_t kItemMelt = 1u << 2;
inline constexpr uint8_t kItemOnFire = 1u << 3;
inline constexpr uint8_t kItemRotten = 1u << 4;
inline constexpr uint8_t kItemArtifact = 1u << 5;
inline constexpr uint8_t kItemWeb = 1u << 6;  // a spider's web (THREAD item)

// MapItem::corpseFlags bits (DF item_body_component.corpse_flags):
// what a Corpse / CorpsePiece item counts as; 0 on every other kind.
inline constexpr uint16_t kCorpseUnbutchered = 1u << 0;
inline constexpr uint16_t kCorpsePlant = 1u << 1;
inline constexpr uint16_t kCorpseSilk = 1u << 2;
inline constexpr uint16_t kCorpseLeather = 1u << 3;
inline constexpr uint16_t kCorpseBone = 1u << 4;
inline constexpr uint16_t kCorpseShell = 1u << 5;
inline constexpr uint16_t kCorpseWood = 1u << 6;
inline constexpr uint16_t kCorpseSoap = 1u << 7;
inline constexpr uint16_t kCorpseTooth = 1u << 8;
inline constexpr uint16_t kCorpseHorn = 1u << 9;
inline constexpr uint16_t kCorpsePearl = 1u << 10;
inline constexpr uint16_t kCorpseRottable = 1u << 11;
inline constexpr uint16_t kCorpseSkull = 1u << 12;
inline constexpr uint16_t kCorpseHairWool = 1u << 13;
inline constexpr uint16_t kCorpseYarn = 1u << 14;
inline constexpr uint16_t kCorpseAll = (1u << 15) - 1;
// A whole corpse that has rotted to a skeleton: bone left, nothing
// rottable (derivation from the flags; live verification PENDING).
inline constexpr bool isSkeleton(uint16_t corpseFlags) {
  return (corpseFlags & kCorpseBone) != 0 && (corpseFlags & kCorpseRottable) == 0;
}

// --- Commands (schema v6) ---
// Semantic intents a presentation sends through MirrorClient; the bridge
// executes them and answers with a CommandResult per seq. Values mirror
// the schema enums (append-only; static_asserted in mirror_ingest.cpp).

// An inclusive tile rectangle on one z level, in map tile coordinates.
struct TileRect {
  int32_t x1 = 0, y1 = 0, x2 = 0, y2 = 0, z = 0;
  friend bool operator==(const TileRect&, const TileRect&) = default;
};

enum class DigKind : uint8_t {
  Dig = 0,       // mine out a wall; removing ramps/stairs is a separate operation
  Channel,
  RampUp,
  StairsUp,
  StairsDown,
  StairsUpDown,
  Remove,        // clear any dig designation
  RemoveStairsRamps, Activate, Mark, StairsSpan,
};

enum class SmoothKind : uint8_t { Smooth = 0, Engrave, Remove, Fortify, Track };

// A tri-state flag change.
enum class OptionalBool : uint8_t { Unchanged = 0, Set, Clear };

// DF work priorities: 1 (highest) .. 7 (lowest), default 4.
inline constexpr uint8_t kMinDigPriority = 1;
inline constexpr uint8_t kMaxDigPriority = 7;
inline constexpr uint8_t kDefaultDigPriority = 4;

enum class CommandStatus : uint8_t {
  Ok = 0,     // executed; message may summarise ("9 of 9 tiles")
  Rejected,   // not executed; message says why
  Unknown,    // the bridge does not understand the payload
};

// --- Classic glyphs (schema v5) ---
// DF's own classic (CP437 / curses) glyph data from the raws, the second
// ruled exception to "semantic vocabulary only": what classic DF draws
// for a creature, a material or an itemdef, so a presentation can draw
// anything it has no sprite for the way DF's classic mode does. Values
// are references into the install's curses tileset, never pixels.

// A code point on the classic tileset plus DF's colour triple
// (foreground 0..7, background 0..7, bright 0/1). 4 bytes.
struct Glyph {
  uint8_t tile = 0, fg = 7, bg = 0, bright = 0;
  friend bool operator==(const Glyph&, const Glyph&) = default;
};
static_assert(sizeof(Glyph) == 4);

// `[CREATURE_TILE]` + `[COLOR]` of a creature raw; `soldierTile` is
// `[SOLDIER_TILE]` or the same tile when unset.
struct CreatureGlyph {
  Glyph glyph;
  uint8_t soldierTile = 0;
  friend bool operator==(const CreatureGlyph&, const CreatureGlyph&) = default;
};

// `[TILE]`, `[ITEM_SYMBOL]`, `[BASIC_COLOR:fg:br]`, `[BUILD_COLOR]` and
// `[TILE_COLOR]` of a material (build / tileColor carry the material's
// tile with the respective colour triple).
struct MaterialGlyph {
  uint8_t tile = 0, itemSymbol = 0, basicFg = 7, basicBright = 0;
  Glyph build, tileColor;
  friend bool operator==(const MaterialGlyph&, const MaterialGlyph&) = default;
};

const char* buildingKindName(BuildingKind k);
const char* buildingStageName(BuildingStage s);
const char* itemKindName(ItemKind k);

}  // namespace wm
