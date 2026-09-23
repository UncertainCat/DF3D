#include "unit_status.h"
// Adapter from mirror buffers to the world model's neutral SnapshotData.
// The only world model translation unit that touches generated mirror code;
// public wm headers stay free of it so presentations cannot reach the
// mirror through us.
#include <limits>

#include "appearance_util.h"
#include "command_util.h"
#include "entity_util.h"
#include "fixture_io.h"
#include "snapshot_convert.h"
#include "terrain_util.h"
#include "validate.h"
#include "wm/world_model.h"

namespace wm {

namespace {

namespace m = df3d::mirror;

// The wm enums mirror the schema enums value-for-value; a drift here is a
// build error, not a runtime surprise.
static_assert(static_cast<uint16_t>(JobKind::Idle) == static_cast<uint16_t>(m::JobKind::Idle));
static_assert(static_cast<uint16_t>(JobKind::Mine) == static_cast<uint16_t>(m::JobKind::Mine));
static_assert(static_cast<uint16_t>(JobKind::HaulItem) ==
              static_cast<uint16_t>(m::JobKind::HaulItem));
static_assert(static_cast<uint16_t>(JobKind::ConstructBuilding) ==
              static_cast<uint16_t>(m::JobKind::ConstructBuilding));
static_assert(static_cast<uint16_t>(JobKind::Sleep) == static_cast<uint16_t>(m::JobKind::Sleep));
static_assert(static_cast<uint16_t>(JobKind::Eat) == static_cast<uint16_t>(m::JobKind::Eat));
static_assert(static_cast<uint16_t>(JobKind::Drink) == static_cast<uint16_t>(m::JobKind::Drink));
static_assert(static_cast<uint16_t>(JobKind::Fight) == static_cast<uint16_t>(m::JobKind::Fight));
static_assert(static_cast<uint16_t>(JobKind::Flee) == static_cast<uint16_t>(m::JobKind::Flee));
static_assert(static_cast<uint16_t>(m::JobKind::MAX) == static_cast<uint16_t>(JobKind::Flee),
              "schema JobKind grew: extend wm::JobKind, jobName(), and these asserts");

// Terrain enums: value-for-value with the schema, every member
// checked plus MAX so growth is a build error here.
#define DF3D_SAME(W, M) static_assert(static_cast<int>(W) == static_cast<int>(M))
DF3D_SAME(TileShape::Empty, m::TileShape::Empty);
DF3D_SAME(TileShape::Wall, m::TileShape::Wall);
DF3D_SAME(TileShape::Floor, m::TileShape::Floor);
DF3D_SAME(TileShape::Ramp, m::TileShape::Ramp);
DF3D_SAME(TileShape::RampTop, m::TileShape::RampTop);
DF3D_SAME(TileShape::StairUp, m::TileShape::StairUp);
DF3D_SAME(TileShape::StairDown, m::TileShape::StairDown);
DF3D_SAME(TileShape::StairUpDown, m::TileShape::StairUpDown);
DF3D_SAME(TileShape::Fortification, m::TileShape::Fortification);
DF3D_SAME(TileShape::Boulder, m::TileShape::Boulder);
DF3D_SAME(TileShape::Pebbles, m::TileShape::Pebbles);
DF3D_SAME(TileShape::TreeTrunk, m::TileShape::TreeTrunk);
DF3D_SAME(TileShape::TreeBranch, m::TileShape::TreeBranch);
DF3D_SAME(TileShape::Shrub, m::TileShape::Shrub);
DF3D_SAME(TileShape::Sapling, m::TileShape::Sapling);
DF3D_SAME(TileShape::Unknown, m::TileShape::Unknown);
static_assert(static_cast<int>(m::TileShape::MAX) == static_cast<int>(TileShape::Unknown),
              "schema TileShape grew: extend wm::TileShape and tileShapeName()");
DF3D_SAME(MaterialKind::None, m::MaterialKind::None);
DF3D_SAME(MaterialKind::Stone, m::MaterialKind::Stone);
DF3D_SAME(MaterialKind::Soil, m::MaterialKind::Soil);
DF3D_SAME(MaterialKind::Mineral, m::MaterialKind::Mineral);
DF3D_SAME(MaterialKind::Gem, m::MaterialKind::Gem);
DF3D_SAME(MaterialKind::Ice, m::MaterialKind::Ice);
DF3D_SAME(MaterialKind::Wood, m::MaterialKind::Wood);
DF3D_SAME(MaterialKind::Plant, m::MaterialKind::Plant);
DF3D_SAME(MaterialKind::Grass, m::MaterialKind::Grass);
DF3D_SAME(MaterialKind::Constructed, m::MaterialKind::Constructed);
DF3D_SAME(MaterialKind::Water, m::MaterialKind::Water);
DF3D_SAME(MaterialKind::Magma, m::MaterialKind::Magma);
DF3D_SAME(MaterialKind::Unknown, m::MaterialKind::Unknown);
static_assert(static_cast<int>(m::MaterialKind::MAX) == static_cast<int>(MaterialKind::Unknown),
              "schema MaterialKind grew: extend wm::MaterialKind and materialKindName()");
DF3D_SAME(LiquidKind::None, m::LiquidKind::None);
DF3D_SAME(LiquidKind::Water, m::LiquidKind::Water);
DF3D_SAME(LiquidKind::Magma, m::LiquidKind::Magma);
static_assert(static_cast<int>(m::LiquidKind::MAX) == static_cast<int>(LiquidKind::Magma));
DF3D_SAME(kTileHidden, m::TileFlags::Hidden);
DF3D_SAME(kTileDigDesignated, m::TileFlags::DigDesignated);
DF3D_SAME(kTileSmooth, m::TileFlags::Smooth);
DF3D_SAME(kTileEngraved, m::TileFlags::Engraved);
DF3D_SAME(kTileOutside, m::TileFlags::Outside);
DF3D_SAME(kTileSmoothDesignated, m::TileFlags::SmoothDesignated);
DF3D_SAME(kTileEngraveDesignated, m::TileFlags::EngraveDesignated);
static_assert(static_cast<int>(m::TileFlags::ANY) ==
                  (kTileHidden | kTileDigDesignated | kTileSmooth | kTileEngraved | kTileOutside |
                   kTileSmoothDesignated | kTileEngraveDesignated | kTileDigAuto),
              "schema TileFlags grew: add the wm::kTile* constant");
DF3D_SAME(TerrainScope::None, m::TerrainScope::None);
DF3D_SAME(TerrainScope::Delta, m::TerrainScope::Delta);
DF3D_SAME(TerrainScope::Full, m::TerrainScope::Full);
DF3D_SAME(kNoMaterial, m::kNoMaterial);
DF3D_SAME(kBlockSize, m::kBlockSize);
DF3D_SAME(kTilesPerBlock, m::kTilesPerBlock);
// Appearance references.
DF3D_SAME(AppearanceScope::None, m::AppearanceScope::None);
DF3D_SAME(AppearanceScope::Delta, m::AppearanceScope::Delta);
DF3D_SAME(AppearanceScope::Full, m::AppearanceScope::Full);
static_assert(static_cast<int>(m::AppearanceScope::MAX) == static_cast<int>(AppearanceScope::Full));
DF3D_SAME(kNoPalette, m::kNoPalette);
DF3D_SAME(kNoPaletteRow, m::kNoPaletteRow);
static_assert(sizeof(AppearanceLayer) == sizeof(m::AppearanceLayer));
// Buildings and map items: every member plus MAX.
DF3D_SAME(BuildingKind::Unknown, m::BuildingKind::Unknown);
DF3D_SAME(BuildingKind::Chair, m::BuildingKind::Chair);
DF3D_SAME(BuildingKind::Bed, m::BuildingKind::Bed);
DF3D_SAME(BuildingKind::Table, m::BuildingKind::Table);
DF3D_SAME(BuildingKind::Coffin, m::BuildingKind::Coffin);
DF3D_SAME(BuildingKind::FarmPlot, m::BuildingKind::FarmPlot);
DF3D_SAME(BuildingKind::Furnace, m::BuildingKind::Furnace);
DF3D_SAME(BuildingKind::TradeDepot, m::BuildingKind::TradeDepot);
DF3D_SAME(BuildingKind::Shop, m::BuildingKind::Shop);
DF3D_SAME(BuildingKind::Door, m::BuildingKind::Door);
DF3D_SAME(BuildingKind::Floodgate, m::BuildingKind::Floodgate);
DF3D_SAME(BuildingKind::Box, m::BuildingKind::Box);
DF3D_SAME(BuildingKind::Weaponrack, m::BuildingKind::Weaponrack);
DF3D_SAME(BuildingKind::Armorstand, m::BuildingKind::Armorstand);
DF3D_SAME(BuildingKind::Workshop, m::BuildingKind::Workshop);
DF3D_SAME(BuildingKind::Cabinet, m::BuildingKind::Cabinet);
DF3D_SAME(BuildingKind::Statue, m::BuildingKind::Statue);
DF3D_SAME(BuildingKind::WindowGlass, m::BuildingKind::WindowGlass);
DF3D_SAME(BuildingKind::WindowGem, m::BuildingKind::WindowGem);
DF3D_SAME(BuildingKind::Well, m::BuildingKind::Well);
DF3D_SAME(BuildingKind::Bridge, m::BuildingKind::Bridge);
DF3D_SAME(BuildingKind::RoadDirt, m::BuildingKind::RoadDirt);
DF3D_SAME(BuildingKind::RoadPaved, m::BuildingKind::RoadPaved);
DF3D_SAME(BuildingKind::SiegeEngine, m::BuildingKind::SiegeEngine);
DF3D_SAME(BuildingKind::Trap, m::BuildingKind::Trap);
DF3D_SAME(BuildingKind::AnimalTrap, m::BuildingKind::AnimalTrap);
DF3D_SAME(BuildingKind::Support, m::BuildingKind::Support);
DF3D_SAME(BuildingKind::ArcheryTarget, m::BuildingKind::ArcheryTarget);
DF3D_SAME(BuildingKind::Chain, m::BuildingKind::Chain);
DF3D_SAME(BuildingKind::Cage, m::BuildingKind::Cage);
DF3D_SAME(BuildingKind::Stockpile, m::BuildingKind::Stockpile);
DF3D_SAME(BuildingKind::Civzone, m::BuildingKind::Civzone);
DF3D_SAME(BuildingKind::Weapon, m::BuildingKind::Weapon);
DF3D_SAME(BuildingKind::Wagon, m::BuildingKind::Wagon);
DF3D_SAME(BuildingKind::ScrewPump, m::BuildingKind::ScrewPump);
DF3D_SAME(BuildingKind::Hatch, m::BuildingKind::Hatch);
DF3D_SAME(BuildingKind::GrateWall, m::BuildingKind::GrateWall);
DF3D_SAME(BuildingKind::GrateFloor, m::BuildingKind::GrateFloor);
DF3D_SAME(BuildingKind::BarsVertical, m::BuildingKind::BarsVertical);
DF3D_SAME(BuildingKind::BarsFloor, m::BuildingKind::BarsFloor);
DF3D_SAME(BuildingKind::GearAssembly, m::BuildingKind::GearAssembly);
DF3D_SAME(BuildingKind::AxleHorizontal, m::BuildingKind::AxleHorizontal);
DF3D_SAME(BuildingKind::AxleVertical, m::BuildingKind::AxleVertical);
DF3D_SAME(BuildingKind::WaterWheel, m::BuildingKind::WaterWheel);
DF3D_SAME(BuildingKind::Windmill, m::BuildingKind::Windmill);
DF3D_SAME(BuildingKind::TractionBench, m::BuildingKind::TractionBench);
DF3D_SAME(BuildingKind::Slab, m::BuildingKind::Slab);
DF3D_SAME(BuildingKind::Nest, m::BuildingKind::Nest);
DF3D_SAME(BuildingKind::NestBox, m::BuildingKind::NestBox);
DF3D_SAME(BuildingKind::Hive, m::BuildingKind::Hive);
DF3D_SAME(BuildingKind::Rollers, m::BuildingKind::Rollers);
DF3D_SAME(BuildingKind::Instrument, m::BuildingKind::Instrument);
DF3D_SAME(BuildingKind::Bookcase, m::BuildingKind::Bookcase);
DF3D_SAME(BuildingKind::DisplayFurniture, m::BuildingKind::DisplayFurniture);
DF3D_SAME(BuildingKind::OfferingPlace, m::BuildingKind::OfferingPlace);
static_assert(static_cast<int>(m::BuildingKind::MAX) == static_cast<int>(BuildingKind::OfferingPlace),
              "schema BuildingKind grew: extend wm::BuildingKind and buildingKindName()");
DF3D_SAME(ItemKind::Unknown, m::ItemKind::Unknown);
DF3D_SAME(ItemKind::Bar, m::ItemKind::Bar);
DF3D_SAME(ItemKind::SmallGem, m::ItemKind::SmallGem);
DF3D_SAME(ItemKind::Blocks, m::ItemKind::Blocks);
DF3D_SAME(ItemKind::Rough, m::ItemKind::Rough);
DF3D_SAME(ItemKind::Boulder, m::ItemKind::Boulder);
DF3D_SAME(ItemKind::Wood, m::ItemKind::Wood);
DF3D_SAME(ItemKind::Door, m::ItemKind::Door);
DF3D_SAME(ItemKind::Floodgate, m::ItemKind::Floodgate);
DF3D_SAME(ItemKind::Bed, m::ItemKind::Bed);
DF3D_SAME(ItemKind::Chair, m::ItemKind::Chair);
DF3D_SAME(ItemKind::Chain, m::ItemKind::Chain);
DF3D_SAME(ItemKind::Flask, m::ItemKind::Flask);
DF3D_SAME(ItemKind::Goblet, m::ItemKind::Goblet);
DF3D_SAME(ItemKind::Instrument, m::ItemKind::Instrument);
DF3D_SAME(ItemKind::Toy, m::ItemKind::Toy);
DF3D_SAME(ItemKind::Window, m::ItemKind::Window);
DF3D_SAME(ItemKind::Cage, m::ItemKind::Cage);
DF3D_SAME(ItemKind::Barrel, m::ItemKind::Barrel);
DF3D_SAME(ItemKind::Bucket, m::ItemKind::Bucket);
DF3D_SAME(ItemKind::AnimalTrap, m::ItemKind::AnimalTrap);
DF3D_SAME(ItemKind::Table, m::ItemKind::Table);
DF3D_SAME(ItemKind::Coffin, m::ItemKind::Coffin);
DF3D_SAME(ItemKind::Statue, m::ItemKind::Statue);
DF3D_SAME(ItemKind::Corpse, m::ItemKind::Corpse);
DF3D_SAME(ItemKind::Weapon, m::ItemKind::Weapon);
DF3D_SAME(ItemKind::Armor, m::ItemKind::Armor);
DF3D_SAME(ItemKind::Shoes, m::ItemKind::Shoes);
DF3D_SAME(ItemKind::Shield, m::ItemKind::Shield);
DF3D_SAME(ItemKind::Helm, m::ItemKind::Helm);
DF3D_SAME(ItemKind::Gloves, m::ItemKind::Gloves);
DF3D_SAME(ItemKind::Box, m::ItemKind::Box);
DF3D_SAME(ItemKind::Bag, m::ItemKind::Bag);
DF3D_SAME(ItemKind::Bin, m::ItemKind::Bin);
DF3D_SAME(ItemKind::Armorstand, m::ItemKind::Armorstand);
DF3D_SAME(ItemKind::Weaponrack, m::ItemKind::Weaponrack);
DF3D_SAME(ItemKind::Cabinet, m::ItemKind::Cabinet);
DF3D_SAME(ItemKind::Figurine, m::ItemKind::Figurine);
DF3D_SAME(ItemKind::Amulet, m::ItemKind::Amulet);
DF3D_SAME(ItemKind::Scepter, m::ItemKind::Scepter);
DF3D_SAME(ItemKind::Ammo, m::ItemKind::Ammo);
DF3D_SAME(ItemKind::Crown, m::ItemKind::Crown);
DF3D_SAME(ItemKind::Ring, m::ItemKind::Ring);
DF3D_SAME(ItemKind::Earring, m::ItemKind::Earring);
DF3D_SAME(ItemKind::Bracelet, m::ItemKind::Bracelet);
DF3D_SAME(ItemKind::Gem, m::ItemKind::Gem);
DF3D_SAME(ItemKind::Anvil, m::ItemKind::Anvil);
DF3D_SAME(ItemKind::CorpsePiece, m::ItemKind::CorpsePiece);
DF3D_SAME(ItemKind::Remains, m::ItemKind::Remains);
DF3D_SAME(ItemKind::Meat, m::ItemKind::Meat);
DF3D_SAME(ItemKind::Fish, m::ItemKind::Fish);
DF3D_SAME(ItemKind::FishRaw, m::ItemKind::FishRaw);
DF3D_SAME(ItemKind::Vermin, m::ItemKind::Vermin);
DF3D_SAME(ItemKind::Pet, m::ItemKind::Pet);
DF3D_SAME(ItemKind::Seeds, m::ItemKind::Seeds);
DF3D_SAME(ItemKind::Plant, m::ItemKind::Plant);
DF3D_SAME(ItemKind::SkinTanned, m::ItemKind::SkinTanned);
DF3D_SAME(ItemKind::PlantGrowth, m::ItemKind::PlantGrowth);
DF3D_SAME(ItemKind::Thread, m::ItemKind::Thread);
DF3D_SAME(ItemKind::Cloth, m::ItemKind::Cloth);
DF3D_SAME(ItemKind::Totem, m::ItemKind::Totem);
DF3D_SAME(ItemKind::Pants, m::ItemKind::Pants);
DF3D_SAME(ItemKind::Backpack, m::ItemKind::Backpack);
DF3D_SAME(ItemKind::Quiver, m::ItemKind::Quiver);
DF3D_SAME(ItemKind::CatapultParts, m::ItemKind::CatapultParts);
DF3D_SAME(ItemKind::BallistaParts, m::ItemKind::BallistaParts);
DF3D_SAME(ItemKind::SiegeAmmo, m::ItemKind::SiegeAmmo);
DF3D_SAME(ItemKind::BallistaArrowhead, m::ItemKind::BallistaArrowhead);
DF3D_SAME(ItemKind::TrapParts, m::ItemKind::TrapParts);
DF3D_SAME(ItemKind::TrapComp, m::ItemKind::TrapComp);
DF3D_SAME(ItemKind::Drink, m::ItemKind::Drink);
DF3D_SAME(ItemKind::PowderMisc, m::ItemKind::PowderMisc);
DF3D_SAME(ItemKind::Cheese, m::ItemKind::Cheese);
DF3D_SAME(ItemKind::Food, m::ItemKind::Food);
DF3D_SAME(ItemKind::LiquidMisc, m::ItemKind::LiquidMisc);
DF3D_SAME(ItemKind::Coin, m::ItemKind::Coin);
DF3D_SAME(ItemKind::Glob, m::ItemKind::Glob);
DF3D_SAME(ItemKind::Rock, m::ItemKind::Rock);
DF3D_SAME(ItemKind::PipeSection, m::ItemKind::PipeSection);
DF3D_SAME(ItemKind::HatchCover, m::ItemKind::HatchCover);
DF3D_SAME(ItemKind::Grate, m::ItemKind::Grate);
DF3D_SAME(ItemKind::Quern, m::ItemKind::Quern);
DF3D_SAME(ItemKind::Millstone, m::ItemKind::Millstone);
DF3D_SAME(ItemKind::Splint, m::ItemKind::Splint);
DF3D_SAME(ItemKind::Crutch, m::ItemKind::Crutch);
DF3D_SAME(ItemKind::TractionBench, m::ItemKind::TractionBench);
DF3D_SAME(ItemKind::OrthopedicCast, m::ItemKind::OrthopedicCast);
DF3D_SAME(ItemKind::Tool, m::ItemKind::Tool);
DF3D_SAME(ItemKind::Slab, m::ItemKind::Slab);
DF3D_SAME(ItemKind::Egg, m::ItemKind::Egg);
DF3D_SAME(ItemKind::Book, m::ItemKind::Book);
DF3D_SAME(ItemKind::Sheet, m::ItemKind::Sheet);
DF3D_SAME(ItemKind::Branch, m::ItemKind::Branch);
static_assert(static_cast<int>(m::ItemKind::MAX) == static_cast<int>(ItemKind::Branch),
              "schema ItemKind grew: extend wm::ItemKind and itemKindName()");
DF3D_SAME(BuildingStage::Planned, m::BuildingStage::Planned);
DF3D_SAME(BuildingStage::InProgress, m::BuildingStage::InProgress);
DF3D_SAME(BuildingStage::Complete, m::BuildingStage::Complete);
static_assert(static_cast<int>(m::BuildingStage::MAX) == static_cast<int>(BuildingStage::Complete));
DF3D_SAME(kBuildingForbidden, m::BuildingFlags::Forbidden);
DF3D_SAME(kBuildingRoomAssigned, m::BuildingFlags::RoomAssigned);
static_assert(static_cast<int>(m::BuildingFlags::ANY) == (kBuildingForbidden | kBuildingRoomAssigned));
DF3D_SAME(kItemForbidden, m::ItemFlags::Forbidden);
DF3D_SAME(kItemDump, m::ItemFlags::Dump);
DF3D_SAME(kItemMelt, m::ItemFlags::Melt);
DF3D_SAME(kItemOnFire, m::ItemFlags::OnFire);
DF3D_SAME(kItemRotten, m::ItemFlags::Rotten);
DF3D_SAME(kItemArtifact, m::ItemFlags::Artifact);
DF3D_SAME(kItemWeb, m::ItemFlags::Web);
static_assert(static_cast<int>(m::ItemFlags::ANY) ==
              (kItemForbidden | kItemDump | kItemMelt | kItemOnFire | kItemRotten | kItemArtifact |
               kItemWeb));
static_assert(sizeof(Glyph) == sizeof(m::Glyph));
DF3D_SAME(kCorpseUnbutchered, m::CorpseFlags::Unbutchered);
DF3D_SAME(kCorpsePlant, m::CorpseFlags::Plant);
DF3D_SAME(kCorpseSilk, m::CorpseFlags::Silk);
DF3D_SAME(kCorpseLeather, m::CorpseFlags::Leather);
DF3D_SAME(kCorpseBone, m::CorpseFlags::Bone);
DF3D_SAME(kCorpseShell, m::CorpseFlags::Shell);
DF3D_SAME(kCorpseWood, m::CorpseFlags::Wood);
DF3D_SAME(kCorpseSoap, m::CorpseFlags::Soap);
DF3D_SAME(kCorpseTooth, m::CorpseFlags::Tooth);
DF3D_SAME(kCorpseHorn, m::CorpseFlags::Horn);
DF3D_SAME(kCorpsePearl, m::CorpseFlags::Pearl);
DF3D_SAME(kCorpseRottable, m::CorpseFlags::Rottable);
DF3D_SAME(kCorpseSkull, m::CorpseFlags::Skull);
DF3D_SAME(kCorpseHairWool, m::CorpseFlags::HairWool);
DF3D_SAME(kCorpseYarn, m::CorpseFlags::Yarn);
DF3D_SAME(kCorpseAll, m::CorpseFlags::ANY);
DF3D_SAME(ChangeScope::None, m::ChangeScope::None);
DF3D_SAME(ChangeScope::Delta, m::ChangeScope::Delta);
DF3D_SAME(ChangeScope::Full, m::ChangeScope::Full);
static_assert(static_cast<int>(m::ChangeScope::MAX) == static_cast<int>(ChangeScope::Full));
DF3D_SAME(kNoSubtype, m::kNoSubtype);
// Commands.
DF3D_SAME(DigKind::Dig, m::DigKind::Dig);
DF3D_SAME(DigKind::Channel, m::DigKind::Channel);
DF3D_SAME(DigKind::RampUp, m::DigKind::RampUp);
DF3D_SAME(DigKind::StairsUp, m::DigKind::StairsUp);
DF3D_SAME(DigKind::StairsDown, m::DigKind::StairsDown);
DF3D_SAME(DigKind::StairsUpDown, m::DigKind::StairsUpDown);
DF3D_SAME(DigKind::Remove, m::DigKind::Remove);
static_assert(static_cast<int>(m::DigKind::MAX) == static_cast<int>(DigKind::StairsSpan));
DF3D_SAME(SmoothKind::Smooth, m::SmoothKind::Smooth);
DF3D_SAME(SmoothKind::Engrave, m::SmoothKind::Engrave);
DF3D_SAME(SmoothKind::Remove, m::SmoothKind::Remove);
static_assert(static_cast<int>(m::SmoothKind::MAX) == static_cast<int>(SmoothKind::Track));
DF3D_SAME(OptionalBool::Unchanged, m::OptionalBool::Unchanged);
DF3D_SAME(OptionalBool::Set, m::OptionalBool::Set);
DF3D_SAME(OptionalBool::Clear, m::OptionalBool::Clear);
static_assert(static_cast<int>(m::OptionalBool::MAX) == static_cast<int>(OptionalBool::Clear));
DF3D_SAME(CommandStatus::Ok, m::CommandStatus::Ok);
DF3D_SAME(CommandStatus::Rejected, m::CommandStatus::Rejected);
DF3D_SAME(CommandStatus::Unknown, m::CommandStatus::Unknown);
static_assert(static_cast<int>(m::CommandStatus::MAX) == static_cast<int>(CommandStatus::Unknown));
DF3D_SAME(kMinDigPriority, m::kMinDigPriority);
DF3D_SAME(kMaxDigPriority, m::kMaxDigPriority);
DF3D_SAME(kDefaultDigPriority, m::kDefaultDigPriority);
#undef DF3D_SAME

inline AppearanceLayer toLayer(const m::AppearanceLayer& l) {
  AppearanceLayer o;
  o.page = l.page();
  o.tileX = l.tile_x();
  o.tileY = l.tile_y();
  o.cellsX = l.cells_x();
  o.cellsY = l.cells_y();
  o.palette = l.palette();
  o.paletteRow = l.palette_row();
  o.paletteKeyRow = l.palette_key_row();
  o.offsetX = l.offset_x();
  o.offsetY = l.offset_y();
  return o;
}

inline Glyph toGlyph(const m::Glyph* g) {
  Glyph o;
  if (!g) return o;
  o.tile = g->tile();
  o.fg = g->fg();
  o.bg = g->bg();
  o.bright = g->bright();
  return o;
}

inline TileState toTile(const m::TileState& t) {
  TileState o;
  o.shape = static_cast<TileShape>(t.shape());
  o.materialKind = static_cast<MaterialKind>(t.material_kind());
  o.material = t.material();
  o.liquidLevel = t.liquid_level();
  o.liquidKind = static_cast<LiquidKind>(t.liquid_kind());
  o.flags = static_cast<uint8_t>(t.flags());
  o.designation = static_cast<DesignationKind>(t.designation());
  return o;
}

}  // namespace

SnapshotData detail::toSnapshotData(const m::Snapshot& s, bool withTerrain) {
  SnapshotData out;
  out.tick = s.tick();
  out.emittedAtMs = s.emitted_at_ms();
  out.mapSize = TilePos{s.map_size()->x(), s.map_size()->y(), s.map_size()->z()};
  if (const auto* units = s.units()) {
    out.units.reserve(units->size());
    for (const m::UnitState* u : *units) {
      UnitObservation obs;
      obs.id = u->id();
      obs.bodyVolumeCm3 = u->body_volume_cm3();
      obs.statusFlags = u->status_flags();
      obs.pos = TilePos{u->pos()->x(), u->pos()->y(), u->pos()->z()};
      obs.job = static_cast<JobKind>(static_cast<uint16_t>(u->job()));
      if (const auto* a = u->attack())
        obs.attack = {a->action_id(), a->target_unit_id(), a->timer1(), a->timer2(), s.tick()};
      obs.species = std::string_view{u->species()->c_str(), u->species()->size()};
      out.units.push_back(obs);
    }
  }
  out.appearanceScope = static_cast<AppearanceScope>(static_cast<uint8_t>(s.appearance_scope()));
  if (out.appearanceScope != AppearanceScope::None) {
    if (const auto* pages = s.tile_pages()) {
      out.tilePages.reserve(pages->size());
      for (const auto* name : *pages) out.tilePages.emplace_back(name->c_str(), name->size());
    }
    if (const auto* pals = s.palettes()) {
      out.palettes.reserve(pals->size());
      for (const auto* name : *pals) out.palettes.emplace_back(name->c_str(), name->size());
    }
    if (const auto* apps = s.appearances()) {
      out.appearances.reserve(apps->size());
      for (const m::UnitAppearance* a : *apps) {
        AppearanceObservation obs;
        obs.id = a->unit();
        obs.version = a->version();
        if (const auto* layers = a->layers()) {
          obs.layers.reserve(layers->size());
          for (const m::AppearanceLayer* l : *layers) obs.layers.push_back(toLayer(*l));
        }
        out.appearances.push_back(std::move(obs));
      }
    }
  }
  // The material table serves terrain, buildings and items (v4).
  if (const auto* mats = s.materials()) {
    out.materials.reserve(mats->size());
    for (const auto* name : *mats) out.materials.emplace_back(name->c_str(), name->size());
  }
  out.buildingScope = static_cast<ChangeScope>(static_cast<uint8_t>(s.building_scope()));
  if (out.buildingScope != ChangeScope::None) {
    if (const auto* list = s.buildings()) {
      out.buildings.reserve(list->size());
      for (const m::Building* b : *list) {
        BuildingObservation obs;
        obs.id = b->id();
        obs.kind = static_cast<BuildingKind>(static_cast<uint8_t>(b->kind()));
        obs.subtype = b->subtype();
        if (const auto* c = b->custom()) obs.custom = std::string_view{c->c_str(), c->size()};
        obs.x1 = b->x1();
        obs.y1 = b->y1();
        obs.x2 = b->x2();
        obs.y2 = b->y2();
        obs.z = b->z();
        obs.centerX = b->center_x();
        obs.centerY = b->center_y();
        if (const auto* ext = b->extents()) obs.extents.assign(ext->begin(), ext->end());
        obs.material = b->material();
        obs.stage = static_cast<BuildingStage>(static_cast<uint8_t>(b->stage()));
        obs.flags = static_cast<uint8_t>(b->flags());
        out.buildings.push_back(std::move(obs));
      }
    }
    if (const auto* removed = s.removed_buildings()) {
      out.removedBuildings.assign(removed->begin(), removed->end());
    }
  }
  out.itemScope = static_cast<ChangeScope>(static_cast<uint8_t>(s.item_scope()));
  if (out.itemScope != ChangeScope::None) {
    if (const auto* list = s.items()) {
      out.items.reserve(list->size());
      for (const m::MapItem* it : *list) {
        ItemObservation obs;
        obs.id = it->id();
        obs.kind = static_cast<ItemKind>(static_cast<uint8_t>(it->kind()));
        obs.subtype = it->subtype();
        if (const auto* r = it->subtype_raw()) obs.subtypeRaw = std::string_view{r->c_str(), r->size()};
        obs.material = it->material();
        if (const auto* p = it->pos()) obs.pos = TilePos{p->x(), p->y(), p->z()};
        obs.stack = it->stack();
        obs.flags = static_cast<uint8_t>(it->flags());
        obs.corpseUnitId = it->corpse_unit_id();
        obs.corpseFlags = static_cast<uint16_t>(it->corpse_flags());
        out.items.push_back(obs);
      }
    }
    if (const auto* removed = s.removed_items()) {
      out.removedItems.assign(removed->begin(), removed->end());
    }
    // Corpse appearances (v5) share the appearance tables; fill them if
    // the unit appearances did not.
    out.itemAppearanceScope =
        static_cast<AppearanceScope>(static_cast<uint8_t>(s.item_appearance_scope()));
    if (out.itemAppearanceScope != AppearanceScope::None) {
      if (out.tilePages.empty()) {
        if (const auto* pages = s.tile_pages()) {
          out.tilePages.reserve(pages->size());
          for (const auto* name : *pages) out.tilePages.emplace_back(name->c_str(), name->size());
        }
      }
      if (out.palettes.empty()) {
        if (const auto* pals = s.palettes()) {
          out.palettes.reserve(pals->size());
          for (const auto* name : *pals) out.palettes.emplace_back(name->c_str(), name->size());
        }
      }
      if (const auto* apps = s.item_appearances()) {
        out.itemAppearances.reserve(apps->size());
        for (const m::ItemAppearance* a : *apps) {
          ItemAppearanceObservation obs;
          obs.id = a->item();
          obs.version = a->version();
          if (const auto* layers = a->layers()) {
            obs.layers.reserve(layers->size());
            for (const m::AppearanceLayer* l : *layers) obs.layers.push_back(toLayer(*l));
          }
          out.itemAppearances.push_back(std::move(obs));
        }
      }
    }
  }
  // Glyph tables (v5).
  out.glyphScope = static_cast<ChangeScope>(static_cast<uint8_t>(s.glyph_scope()));
  if (out.glyphScope != ChangeScope::None) {
    if (const auto* list = s.creature_glyphs()) {
      out.creatureGlyphs.reserve(list->size());
      for (const m::CreatureGlyph* g : *list) {
        CreatureGlyphObservation obs;
        if (const auto* sp = g->species()) obs.species = std::string_view{sp->c_str(), sp->size()};
        obs.glyph.glyph = toGlyph(g->glyph());
        obs.glyph.soldierTile = g->soldier_tile();
        out.creatureGlyphs.push_back(obs);
      }
    }
    if (const auto* list = s.material_glyphs()) {
      out.materialGlyphs.reserve(list->size());
      for (const m::MaterialGlyph* g : *list) {
        MaterialGlyphObservation obs;
        if (const auto* mt = g->material()) obs.material = std::string_view{mt->c_str(), mt->size()};
        obs.glyph.tile = g->tile();
        obs.glyph.itemSymbol = g->item_symbol();
        obs.glyph.basicFg = g->basic_fg();
        obs.glyph.basicBright = g->basic_bright();
        obs.glyph.build = toGlyph(g->build());
        obs.glyph.tileColor = toGlyph(g->tile_color());
        out.materialGlyphs.push_back(obs);
      }
    }
    if (const auto* list = s.itemdef_glyphs()) {
      out.itemDefGlyphs.reserve(list->size());
      for (const m::ItemDefGlyph* g : *list) {
        ItemDefGlyphObservation obs;
        obs.kind = static_cast<ItemKind>(static_cast<uint8_t>(g->kind()));
        if (const auto* r = g->subtype_raw()) obs.subtypeRaw = std::string_view{r->c_str(), r->size()};
        obs.tile = g->tile();
        out.itemDefGlyphs.push_back(obs);
      }
    }
  }
  // Command results (v6).
  auto eventItem=[](const m::EventItem* item) {
    EventItem out;
    if(item) {
      out.id=item->id();
      out.materialFlags=item->material_flags();out.materialFlagsKnown=item->material_flags_known();
      if(item->melee_skill())out.meleeSkill=item->melee_skill()->str();
      if(item->type()) out.type=item->type()->str();
      if(item->subtype_raw()) out.subtypeRaw=item->subtype_raw()->str();
      if(item->material()) out.material=item->material()->str();
    }
    return out;
  };
  if (const auto* samples = s.projectile_samples()) {
    auto pos=[](const m::TilePos* p) { return TilePos{p->x(),p->y(),p->z()}; };
    out.projectileSamples.reserve(samples->size());
    for (const auto* p : *samples) out.projectileSamples.push_back({p->sequence(),p->projectile_id(),
      p->tick(),p->item_id(),p->firer_id(),pos(p->pos()),pos(p->previous()),pos(p->origin()),pos(p->target()),
      p->active(),p->first_observed(),eventItem(p->ammunition()),eventItem(p->launcher())});
  }
  if (const auto* events = s.combat_events()) {
    out.combatEvents.reserve(events->size());
    for (const auto* e : *events) out.combatEvents.push_back({e->id(), e->tick(),
      static_cast<CombatEventKind>(e->kind()), e->attacker_id(), e->victim_id(),
      e->wound_id(), {e->pos()->x(),e->pos()->y(),e->pos()->z()},e->report_id(),e->source_action_id(),eventItem(e->weapon())});
  }
  if(const auto* events=s.report_events()) {
    out.reportEvents.reserve(events->size());
    for(const auto* e:*events) {
      ReportEvent event;
      event.id=e->id();event.tick=e->tick();event.reportId=e->report_id();event.type=e->type()->str();
      event.hasPosition=e->pos()!=nullptr;event.hasSecondary=e->pos2()!=nullptr;
      if(event.hasPosition) event.pos={e->pos()->x(),e->pos()->y(),e->pos()->z()};
      if(event.hasSecondary) event.pos2={e->pos2()->x(),e->pos2()->y(),e->pos2()->z()};
      event.repeatCount=e->repeat_count();event.speakerId=e->speaker_id();
      out.reportEvents.push_back(std::move(event));
    }
  }
  out.reportEventsDropped=s.report_events_dropped();
  if(const auto* events=s.projectile_combat_events()) {
    out.projectileCombatEvents.reserve(events->size());
    for(const auto* e:*events) {
      ProjectileCombatEvent event;
      event.id=e->id();event.tick=e->tick();event.projectileId=e->projectile_id();
      event.sourceUnitId=e->source_unit_id();event.targetUnitId=e->target_unit_id();
      event.kind=static_cast<ProjectileCombatKind>(e->kind());event.launcher=static_cast<WeaponLauncher>(e->launcher());
      event.ammunition=eventItem(e->ammunition());event.weapon=eventItem(e->weapon());
      event.pos={e->pos()->x(),e->pos()->y(),e->pos()->z()};event.contextComplete=e->context_complete();
      out.projectileCombatEvents.push_back(std::move(event));
    }
  }
  out.projectileCombatEventsDropped=s.projectile_combat_events_dropped();
  out.projectileCombatEventsAvailable=s.projectile_combat_events_available();
  if(const auto* events=s.resolved_attacks()) {
    out.resolvedAttacks.reserve(events->size());
    for(const auto* e:*events) {
      ResolvedAttack attack;
      attack.id=e->id();attack.tick=e->tick();attack.attackerId=e->attacker_id();
      attack.defenderId=e->defender_id();attack.actionId=e->action_id();
      attack.weapon=eventItem(e->weapon());attack.pos={e->pos()->x(),e->pos()->y(),e->pos()->z()};
      attack.equipmentContactsComplete=e->equipment_contacts_complete();
      attack.woundsComplete=e->wounds_complete();
      attack.outcome=static_cast<AttackOutcome>(e->outcome());
      attack.outcomeComplete=e->outcome_complete();attack.weaponContextComplete=e->weapon_context_complete();
      if(const auto* wounds=e->wounds()) for(const auto* w:*wounds) {
        AttackWound wound;
        wound.woundId=w->wound_id();wound.victimId=w->victim_id();
        wound.severedPart=w->severed_part();wound.poppedOut=w->popped_out();wound.partsComplete=w->parts_complete();
        if(const auto* parts=w->parts()) for(const auto* p:*parts)
          wound.parts.push_back({p->body_part_id(),p->layer_id(),p->body_part_token()?p->body_part_token()->str():std::string{},p->body_part_category()?p->body_part_category()->str():std::string{},
                                p->damage_flags(),p->anatomy_flags()});
        attack.wounds.push_back(std::move(wound));
      }
      if(const auto* contacts=e->contacts()) for(const auto* c:*contacts)
        attack.contacts.push_back({eventItem(c->first()),eventItem(c->second())});
      out.resolvedAttacks.push_back(std::move(attack));
    }
  }
  out.resolvedAttacksDropped=s.resolved_attacks_dropped();
  out.resolvedAttacksAvailable=s.resolved_attacks_available();
  if(const auto* events=s.item_contacts()) {
    out.itemContacts.reserve(events->size());
    for(const auto* e:*events) out.itemContacts.push_back({e->id(),e->tick(),
      eventItem(e->first()),eventItem(e->second()),{e->pos()->x(),e->pos()->y(),e->pos()->z()}});
  }
  out.itemContactsDropped=s.item_contacts_dropped();
  out.itemContactsAvailable=s.item_contacts_available();
  if (const auto* results = s.command_results()) {
    out.commandResults.reserve(results->size());
    for (const m::CommandResult* r : *results) {
      CommandResultObservation obs;
      obs.seq = r->seq();
      obs.status = static_cast<CommandStatus>(static_cast<uint8_t>(r->status()));
      if (const auto* msg = r->message()) obs.message = std::string_view{msg->c_str(), msg->size()};
      out.commandResults.push_back(obs);
    }
  }
  if (!withTerrain) return out;
  out.spatterScope = static_cast<ChangeScope>(s.spatter_scope());
  if (const auto* blocks = s.spatters()) for (const auto* block : *blocks) {
    SpatterBlockObservation obs{{block->bx(), block->by(), block->bz()}, {}};
    if (const auto* entries = block->entries()) for (const auto* e : *entries)
      obs.entries.push_back({e->tile(),e->amount(),e->material(),static_cast<MatterState>(e->state())});
    out.spatters.push_back(std::move(obs));
  }
  out.terrainScope = static_cast<TerrainScope>(static_cast<uint8_t>(s.terrain_scope()));
  if (out.terrainScope != TerrainScope::None) {
    if (const auto* blocks = s.blocks()) {
      // Sized up front: BlockObservation::tiles points into tileStorage.
      out.tileStorage.resize(static_cast<size_t>(blocks->size()) * kTilesPerBlock);
      out.blocks.reserve(blocks->size());
      size_t base = 0;
      for (const m::MapBlock* b : *blocks) {
        const auto* tiles = b->tiles();  // validators guarantee exactly 256
        for (uint32_t i = 0; i < kTilesPerBlock; ++i) {
          out.tileStorage[base + i] = toTile(*tiles->Get(i));
        }
        if (const auto* details = b->designation_details()) for (const auto* d : *details) {
          auto& tile = out.tileStorage[base + d->tile_index()];
          tile.designationPriority = d->priority();
          tile.designationMarker = d->marker();
        }
        if (const auto* indicators=b->indicators()) for (const auto* d : *indicators) {
          auto& tile=out.tileStorage[base+d->tile_index()];
          tile.track=d->track(); tile.traffic=d->traffic(); tile.warnings=d->warnings();
        }
        if(const auto* bits=b->track_support()) for(uint16_t index:*bits) out.tileStorage[base+index].trackSupport=true;
        if(const auto* bits=b->track_open()) for(uint16_t index:*bits) out.tileStorage[base+index].trackOpen=true;
        if(const auto* blocked=b->track_horizontal_blocked()) for(uint16_t index:*blocked)
          out.tileStorage[base+index].trackHorizontalBlocked=true;
        if(const auto* blocked=b->track_clearance_blocked()) for(uint16_t index:*blocked)
          out.tileStorage[base+index].trackClearanceBlocked=true;
        out.blocks.push_back(
            BlockObservation{BlockPos{b->bx(), b->by(), b->bz()}, out.tileStorage.data() + base});
        base += kTilesPerBlock;
      }
    }
  }
  return out;
}

namespace {

bool ingestStream(WorldModel& model, const m::FixtureStream& fs, std::string& error) {
  if (auto verr = m::validateStream(fs)) {
    error = "fixture failed validation: " + *verr;
    return false;
  }
  for (const m::Snapshot* s : fs.snapshots) {
    // Replay arrival timing from the recorded bridge clock (deterministic).
    model.ingest(detail::toSnapshotData(*s, model.config().ingestTerrain),
                 static_cast<double>(s->emitted_at_ms()) / 1000.0);
  }
  return true;
}

}  // namespace

bool loadFixtureFile(WorldModel& model, const std::string& path, std::string& error) {
  m::FixtureStream fs;
  if (!m::loadFixtureFile(path, fs, error)) return false;
  return ingestStream(model, fs, error);
}

bool loadFixtureBytes(WorldModel& model, std::vector<uint8_t> bytes, std::string& error) {
  m::FixtureStream fs;
  if (!m::parseFixture(std::move(bytes), fs, error)) return false;
  return ingestStream(model, fs, error);
}

// --- FixtureReplay ---

struct FixtureReplay::Impl {
  m::FixtureStream fs;
};

FixtureReplay::FixtureReplay() : impl_(std::make_unique<Impl>()) {}
FixtureReplay::~FixtureReplay() = default;

std::unique_ptr<FixtureReplay> FixtureReplay::open(const std::string& path, std::string& error) {
  std::unique_ptr<FixtureReplay> r(new FixtureReplay());
  if (!m::loadFixtureFile(path, r->impl_->fs, error)) return nullptr;
  if (auto verr = m::validateStream(r->impl_->fs)) {
    error = "fixture failed validation: " + *verr;
    return nullptr;
  }
  return r;
}

std::unique_ptr<FixtureReplay> FixtureReplay::fromBytes(std::vector<uint8_t> bytes,
                                                        std::string& error) {
  std::unique_ptr<FixtureReplay> r(new FixtureReplay());
  if (!m::parseFixture(std::move(bytes), r->impl_->fs, error)) return nullptr;
  if (auto verr = m::validateStream(r->impl_->fs)) {
    error = "fixture failed validation: " + *verr;
    return nullptr;
  }
  return r;
}

size_t FixtureReplay::snapshotCount() const { return impl_->fs.snapshots.size(); }

double FixtureReplay::firstArrivalSeconds() const {
  const auto& s = impl_->fs.snapshots;
  return s.empty() ? 0.0 : static_cast<double>(s.front()->emitted_at_ms()) / 1000.0;
}

double FixtureReplay::lastArrivalSeconds() const {
  const auto& s = impl_->fs.snapshots;
  return s.empty() ? 0.0 : static_cast<double>(s.back()->emitted_at_ms()) / 1000.0;
}

size_t FixtureReplay::stepTo(WorldModel& model, double wallSeconds) {
  const auto& s = impl_->fs.snapshots;
  size_t n = 0;
  while (next_ < s.size()) {
    const double arrival = static_cast<double>(s[next_]->emitted_at_ms()) / 1000.0;
    if (arrival > wallSeconds) break;
    model.ingest(detail::toSnapshotData(*s[next_], model.config().ingestTerrain), arrival);
    ++next_;
    ++n;
  }
  return n;
}

size_t FixtureReplay::stepAll(WorldModel& model) {
  return stepTo(model, std::numeric_limits<double>::infinity());
}

}  // namespace wm

// Public WM vocabulary stays independent of the private mirror headers.
static_assert(wm::UnitStatus::Sleeping == df3d::unit_status::Sleeping);
static_assert(wm::UnitStatus::Webbed == df3d::unit_status::Webbed);
static_assert(wm::UnitStatus::Stunned == df3d::unit_status::Stunned);
static_assert(wm::UnitStatus::Unconscious == df3d::unit_status::Unconscious);
static_assert(wm::UnitStatus::Fey == df3d::unit_status::Fey);
static_assert(wm::UnitStatus::Secretive == df3d::unit_status::Secretive);
static_assert(wm::UnitStatus::Possessed == df3d::unit_status::Possessed);
static_assert(wm::UnitStatus::Macabre == df3d::unit_status::Macabre);
static_assert(wm::UnitStatus::Fell == df3d::unit_status::Fell);
static_assert(wm::UnitStatus::Melancholy == df3d::unit_status::Melancholy);
static_assert(wm::UnitStatus::Raving == df3d::unit_status::Raving);
static_assert(wm::UnitStatus::Berserk == df3d::unit_status::Berserk);
static_assert(wm::UnitStatus::Traumatized == df3d::unit_status::Traumatized);
static_assert(wm::UnitStatus::TellingStory == df3d::unit_status::TellingStory);
static_assert(wm::UnitStatus::RecitingPoetry == df3d::unit_status::RecitingPoetry);
static_assert(wm::UnitStatus::PerformingMusic == df3d::unit_status::PerformingMusic);
static_assert(wm::UnitStatus::Dancing == df3d::unit_status::Dancing);
static_assert(wm::UnitStatus::Migrant == df3d::unit_status::Migrant);
static_assert(wm::UnitStatus::NoJob == df3d::unit_status::NoJob);
static_assert(wm::UnitStatus::NoDestination == df3d::unit_status::NoDestination);
static_assert(wm::UnitStatus::Hungry == df3d::unit_status::Hungry);
static_assert(wm::UnitStatus::Thirsty == df3d::unit_status::Thirsty);
static_assert(wm::UnitStatus::Drowsy == df3d::unit_status::Drowsy);
static_assert(wm::UnitStatus::Stressed == df3d::unit_status::Stressed);
static_assert(wm::UnitStatus::Distracted == df3d::unit_status::Distracted);
static_assert(wm::UnitStatus::Tantrum == df3d::unit_status::Tantrum);
static_assert(wm::UnitStatus::Oblivious == df3d::unit_status::Oblivious);
static_assert(wm::UnitStatus::Depression == df3d::unit_status::Depression);
static_assert(wm::UnitStatus::Enraged == df3d::unit_status::Enraged);
static_assert(wm::UnitStatus::MartialTrance == df3d::unit_status::MartialTrance);
static_assert(wm::UnitStatus::Terrified == df3d::unit_status::Terrified);
static_assert(wm::UnitStatus::Wrestling == df3d::unit_status::Wrestling);
static_assert(wm::UnitStatus::MinorInjury == df3d::unit_status::MinorInjury);
static_assert(wm::UnitStatus::MajorInjury == df3d::unit_status::MajorInjury);
static_assert(wm::UnitStatus::Paralyzed == df3d::unit_status::Paralyzed);
static_assert(wm::UnitStatus::Nausea == df3d::unit_status::Nausea);
static_assert(wm::UnitStatus::Winded == df3d::unit_status::Winded);
static_assert(wm::UnitStatus::Fevered == df3d::unit_status::Fevered);
static_assert(wm::UnitStatus::Yielding == df3d::unit_status::Yielding);
static_assert(wm::UnitStatus::PlayingMakeBelieve == df3d::unit_status::PlayingMakeBelieve);
static_assert(wm::UnitStatus::Projectile == df3d::unit_status::Projectile);
static_assert(wm::UnitStatus::Grounded == df3d::unit_status::Grounded);
static_assert(wm::UnitStatus::Climbing == df3d::unit_status::Climbing);
