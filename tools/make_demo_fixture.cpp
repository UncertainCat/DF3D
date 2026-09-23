// Generates the checked-in demo fixture: a small scripted scene exercising
// walking, jobs, appearance/departure, a z-transition, a fall, and a
// teleport, on authored terrain (surface, soil and stone layers, a mineral
// vein, a stair shaft, a pond, a magma pool, dig designations that are
// mined out tick by tick so the stream carries Deltas after its Full), with
// a few buildings and map items (v4) that change over the ticks: a
// bridge completes, a planned chair appears and is cancelled, a log is
// hauled away, a boulder appears where the miners dug and another is
// kicked one tile. Schema v5: a dwarf corpse on the surface carrying
// a synthetic CORPSE-role layer stack (a fresh corpse whose stack changes
// when it rots to bone), a goblin corpse piece with an empty stack, a
// spider web (Web flag), a Meat item, a Shop and a forgotten beast (things
// vanilla has no art for: drawn as classic glyphs), and the
// classic glyph tables (creature, material
// and itemdef entries; Full first, one Delta later).
// Regenerate with: make_demo_fixture <out-path>
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <utility>
#include <vector>

#include "entity_util.h"
#include "fixture_io.h"
#include "synthetic_builder.h"
#include "terrain_util.h"
#include "validate.h"

using namespace df3d::mirror;

namespace {

TileState tileOf(TileShape shape, MaterialKind kind, uint16_t mat,
                 TileFlags flags = TileFlags::NONE) {
  return TileState(shape, kind, mat, 0, LiquidKind::None, flags, df3d::mirror::DesignationKind::None);
}

TileState liquidOn(const TileState& base, LiquidKind kind, uint8_t level) {
  return TileState(base.shape(), base.material_kind(), base.material(), level, kind,
                   base.flags(), df3d::mirror::DesignationKind::None);
}

// Surface at z=5 (units walk there); z 0..4 underground; z 6..11 open sky.
constexpr int32_t kSurfaceZ = 5;

void authorTerrain(SyntheticFort& fort) {
  const uint16_t granite = fort.material("GRANITE");
  const uint16_t magnetite = fort.material("MAGNETITE");
  const uint16_t loam = fort.material("CLAY_LOAM");
  const uint16_t grass = fort.material("GRASS_TEMPERATE");
  const uint16_t oak = fort.material("OAK");

  const TileState stoneWall =
      tileOf(TileShape::Wall, MaterialKind::Stone, granite, TileFlags::Hidden);
  const TileState oreWall =
      tileOf(TileShape::Wall, MaterialKind::Mineral, magnetite, TileFlags::Hidden);
  const TileState soilWall = tileOf(TileShape::Wall, MaterialKind::Soil, loam, TileFlags::Hidden);
  const TileState stoneFloor = tileOf(TileShape::Floor, MaterialKind::Stone, granite);
  const TileState soilFloor = tileOf(TileShape::Floor, MaterialKind::Soil, loam);
  const TileState turf = tileOf(TileShape::Floor, MaterialKind::Grass, grass, TileFlags::Outside);
  const TileState sky =
      tileOf(TileShape::Empty, MaterialKind::None, kNoMaterial, TileFlags::Outside);

  fort.fillBox(TilePos(0, 0, 0), TilePos(47, 47, 2), stoneWall);
  fort.fillBox(TilePos(30, 10, 1), TilePos(36, 13, 1), oreWall);  // magnetite vein
  fort.fillBox(TilePos(0, 0, 3), TilePos(47, 47, 4), soilWall);
  fort.fillBox(TilePos(0, 0, kSurfaceZ), TilePos(47, 47, kSurfaceZ), turf);
  fort.fillBox(TilePos(0, 0, kSurfaceZ + 1), TilePos(47, 47, 11), sky);

  // A few oaks: trunk on the surface, branches one level up.
  const std::pair<int32_t, int32_t> oaks[] = {{6, 40}, {40, 6}, {42, 42}};
  for (const auto& [tx, ty] : oaks) {
    fort.setTile(tx, ty, kSurfaceZ,
                 tileOf(TileShape::TreeTrunk, MaterialKind::Wood, oak, TileFlags::Outside));
    fort.fillBox(TilePos(tx - 1, ty - 1, kSurfaceZ + 1), TilePos(tx + 1, ty + 1, kSurfaceZ + 1),
                 tileOf(TileShape::TreeBranch, MaterialKind::Wood, oak, TileFlags::Outside));
  }
  fort.setTile(12, 36, kSurfaceZ,
               tileOf(TileShape::Shrub, MaterialKind::Plant, kNoMaterial, TileFlags::Outside));
  fort.setTile(13, 37, kSurfaceZ,
               tileOf(TileShape::Sapling, MaterialKind::Wood, oak, TileFlags::Outside));
  fort.setTile(2, 2, kSurfaceZ,
               tileOf(TileShape::Boulder, MaterialKind::Stone, granite, TileFlags::Outside));
  fort.setTile(3, 2, kSurfaceZ,
               tileOf(TileShape::Pebbles, MaterialKind::Stone, granite, TileFlags::Outside));

  // Pond on the surface, deeper toward the middle.
  for (int32_t y = 34; y <= 38; ++y)
    for (int32_t x = 34; x <= 38; ++x) {
      const int32_t d = std::max(std::abs(x - 36), std::abs(y - 36));
      fort.setTile(x, y, kSurfaceZ,
                   liquidOn(soilFloor, LiquidKind::Water, static_cast<uint8_t>(7 - 2 * d)));
    }
  // Magma pool at the bottom.
  fort.fillBox(TilePos(40, 40, 0), TilePos(43, 43, 0), liquidOn(stoneFloor, LiquidKind::Magma, 7));

  // Stair shaft from the surface at (20,12) down to z=1; unit 4 takes it
  // to z=4 where a smoothed, engraved hall waits.
  fort.setTile(20, 12, kSurfaceZ,
               tileOf(TileShape::StairDown, MaterialKind::Soil, loam, TileFlags::Outside));
  for (int32_t z = 2; z <= 4; ++z) {
    fort.setTile(20, 12, z,
                 tileOf(TileShape::StairUpDown, z >= 3 ? MaterialKind::Soil : MaterialKind::Stone,
                        z >= 3 ? loam : granite));
  }
  fort.setTile(20, 12, 1, tileOf(TileShape::StairUp, MaterialKind::Stone, granite));
  fort.fillBox(TilePos(18, 8, 4), TilePos(22, 11, 4), soilFloor);
  fort.fillBox(TilePos(19, 9, 4), TilePos(21, 10, 4),
               tileOf(TileShape::Floor, MaterialKind::Soil, loam,
                      TileFlags::Smooth | TileFlags::Engraved));
  fort.setTile(18, 8, 4, tileOf(TileShape::Fortification, MaterialKind::Soil, loam));
  // Deep gallery at z=1 where miner 1 lands after the fall.
  fort.fillBox(TilePos(12, 18, 1), TilePos(22, 22, 1), stoneFloor);
  // A ramp up out of the gallery.
  fort.setTile(22, 20, 1, tileOf(TileShape::Ramp, MaterialKind::Stone, granite));
  fort.setTile(22, 20, 2, tileOf(TileShape::RampTop, MaterialKind::None, kNoMaterial));

  // Dig designations at z=4 under the miners' route; mined out tick by tick.
  fort.fillBox(TilePos(9, 20, 4), TilePos(14, 22, 4),
               tileOf(TileShape::Wall, MaterialKind::Soil, loam,
                      TileFlags::Hidden | TileFlags::DigDesignated));
}

// A dwarf's layer stack in the vanilla DWARF_BODY / DWARF_HAIR shape:
// skin palette row, hair palette row, optional helm layer on top.
std::vector<SyntheticFort::Layer> dwarfStack(int16_t skinRow, int16_t hairRow, bool helm) {
  const std::string bodyPalette =
      "data/vanilla/vanilla_creatures_graphics/graphics/images/dwarf/dwarf_body_palettes.png";
  const std::string hairPalette =
      "data/vanilla/vanilla_creatures_graphics/graphics/images/dwarf/dwarf_hair_palettes.png";
  std::vector<SyntheticFort::Layer> stack;
  SyntheticFort::Layer shadow;
  shadow.page = "DWARF_BODY";
  shadow.tileX = 8;
  shadow.tileY = 3;
  stack.push_back(shadow);
  SyntheticFort::Layer body;
  body.page = "DWARF_BODY";
  body.tileX = 3;
  body.tileY = 4;
  body.palette = bodyPalette;
  body.paletteRow = skinRow;
  body.paletteKeyRow = 0;
  stack.push_back(body);
  SyntheticFort::Layer hair;
  hair.page = "DWARF_HAIR";
  hair.tileX = 3;
  hair.tileY = 13;
  hair.cellsY = 2;
  hair.palette = hairPalette;
  hair.paletteRow = hairRow;
  hair.paletteKeyRow = 0;
  stack.push_back(hair);
  if (helm) {
    SyntheticFort::Layer h;
    h.page = "DWARF_WEARABLES";
    h.tileX = 0;
    h.tileY = 24;
    h.palette = "data/vanilla/vanilla_descriptors_graphics/graphics/images/palettes.png";
    h.paletteRow = 17;
    h.paletteKeyRow = 0;
    stack.push_back(h);
  }
  return stack;
}

void authorAppearances(SyntheticFort& fort) {
  fort.setAppearance(1, dwarfStack(2, 5, false));
  fort.setAppearance(2, dwarfStack(3, 0, false));
  fort.setAppearance(4, dwarfStack(1, 7, true));
  SyntheticFort::Layer cat;
  cat.page = "DOMESTIC";
  cat.tileX = 0;
  cat.tileY = 2;
  fort.setAppearance(3, {cat});
}

// --- buildings and map items (v4) ---
// Ids follow DF's habit of small building ids and larger item ids.
constexpr uint32_t kWorkshop = 1, kBed = 2, kDoor = 3, kStockpile = 4, kBridge = 5, kChair = 6;
constexpr uint32_t kLogA = 100, kLogB = 101, kBars = 102, kBoulder = 103, kPick = 104,
                   kDugBoulder = 105, kCorpse = 106, kCorpsePiece = 107, kWeb = 108,
                   kMeat = 109;
constexpr uint32_t kShop = 7;

// A dwarf corpse's stack in the vanilla DWARF_BODY_CORPSE / DWARF_HAIR_CORPSE
// shape: body parts recoloured by the skin palette row, hair by the
// hair palette row; `skeleton` swaps the whole stack for the bone pile tile.
std::vector<SyntheticFort::Layer> corpseStack(int16_t skinRow, int16_t hairRow, bool skeleton) {
  std::vector<SyntheticFort::Layer> stack;
  if (skeleton) {
    SyntheticFort::Layer bones;
    bones.page = "BONE_PILE";
    bones.tileX = 0;
    bones.tileY = 0;
    stack.push_back(bones);
    return stack;
  }
  const std::string bodyPalette =
      "data/vanilla/vanilla_creatures_graphics/graphics/images/dwarf/dwarf_body_palettes.png";
  const std::string hairPalette =
      "data/vanilla/vanilla_creatures_graphics/graphics/images/dwarf/dwarf_hair_palettes.png";
  const std::pair<uint16_t, uint16_t> parts[] = {{1, 3}, {1, 2}, {1, 1}, {1, 0}, {1, 7},
                                                 {1, 8}, {1, 4}, {1, 5}, {2, 5}};
  for (const auto& [x, y] : parts) {
    SyntheticFort::Layer l;
    l.page = "DWARF_BODY_CORPSE";
    l.tileX = x;
    l.tileY = y;
    l.palette = bodyPalette;
    l.paletteRow = skinRow;
    l.paletteKeyRow = 0;
    stack.push_back(l);
  }
  SyntheticFort::Layer hair;
  hair.page = "DWARF_HAIR_CORPSE";
  hair.tileX = 4;
  hair.tileY = 3;
  hair.palette = hairPalette;
  hair.paletteRow = hairRow;
  hair.paletteKeyRow = 0;
  stack.push_back(hair);
  return stack;
}

void authorGlyphs(SyntheticFort& fort) {
  // CREATURE_TILE / COLOR as the vanilla raws give them.
  SyntheticFort::CreatureGlyphSpec dwarf;
  dwarf.glyph = Glyph(1, 3, 0, 0);  // [CREATURE_TILE:1][COLOR:3:0:0]
  dwarf.soldierTile = 2;            // [SOLDIER_TILE:2]
  fort.creatureGlyph("DWARF", dwarf);
  SyntheticFort::CreatureGlyphSpec cat;
  cat.glyph = Glyph('c', 7, 0, 0);
  cat.soldierTile = 'c';
  fort.creatureGlyph("CAT", cat);
  SyntheticFort::CreatureGlyphSpec goblin;
  goblin.glyph = Glyph('g', 2, 0, 0);
  goblin.soldierTile = 'G';
  fort.creatureGlyph("GOBLIN", goblin);
  // A procedurally generated creature: DF publishes no page art
  // for it, so its CREATURE_TILE / COLOR is all a presentation has.
  SyntheticFort::CreatureGlyphSpec beast;
  beast.glyph = Glyph('F', 5, 0, 1);
  beast.soldierTile = 'F';
  fort.creatureGlyph("FORGOTTEN_BEAST_7", beast);
  SyntheticFort::MaterialGlyphSpec granite;
  granite.tile = 7;  // [TILE:7]? vanilla stone layers carry none; the default
  granite.itemSymbol = 0;
  granite.basicFg = 7;
  granite.basicBright = 0;
  granite.build = Glyph(7, 7, 7, 1);   // [BUILD_COLOR:7:7:1]
  granite.tileColor = Glyph(7, 7, 7, 1);
  fort.materialGlyph("GRANITE", granite);
  SyntheticFort::MaterialGlyphSpec iron;
  iron.tile = 7;
  iron.basicFg = 7;
  iron.basicBright = 1;
  iron.build = Glyph(7, 7, 7, 1);
  iron.tileColor = Glyph(7, 7, 7, 1);
  fort.materialGlyph("IRON", iron);
  // Dog meat: [BASIC_COLOR:4:0] (red) colours the meat glyph, the only art
  // vanilla has for a Meat item.
  SyntheticFort::MaterialGlyphSpec dogMeat;
  dogMeat.tile = 0;
  dogMeat.basicFg = 4;
  dogMeat.basicBright = 0;
  dogMeat.build = Glyph(0, 4, 0, 0);
  dogMeat.tileColor = Glyph(0, 4, 0, 0);
  fort.materialGlyph("CREATURE:DOG:MUSCLE", dogMeat);
  fort.itemDefGlyph(ItemKind::Tool, "ITEM_TOOL_CAULDRON", 147);
}

SyntheticFort::BuildingSpec rect(BuildingKind kind, int32_t x1, int32_t y1, int32_t x2,
                                 int32_t y2, int32_t z, uint16_t material = kNoMaterial,
                                 BuildingStage stage = BuildingStage::Complete) {
  SyntheticFort::BuildingSpec b;
  b.kind = kind;
  b.x1 = x1;
  b.y1 = y1;
  b.x2 = x2;
  b.y2 = y2;
  b.z = z;
  b.material = material;
  b.stage = stage;
  return b;
}

SyntheticFort::ItemSpec itemAt(ItemKind kind, int32_t x, int32_t y, int32_t z,
                               uint16_t material = kNoMaterial, uint32_t stack = 1,
                               ItemFlags flags = ItemFlags::NONE) {
  SyntheticFort::ItemSpec it;
  it.kind = kind;
  it.material = material;
  it.x = x;
  it.y = y;
  it.z = z;
  it.stack = stack;
  it.flags = flags;
  return it;
}

void authorBuildings(SyntheticFort& fort) {
  const uint16_t granite = fort.material("GRANITE");
  const uint16_t oak = fort.material("OAK");
  // A mason's workshop (workshop_type::Masons = 2), 3x3 on the surface.
  SyntheticFort::BuildingSpec mason = rect(BuildingKind::Workshop, 24, 30, 26, 32, kSurfaceZ, granite);
  mason.subtype = 2;
  fort.placeBuilding(kWorkshop, mason);
  // A bed with a bedroom assigned.
  SyntheticFort::BuildingSpec bed = rect(BuildingKind::Bed, 30, 40, 30, 40, kSurfaceZ, oak);
  bed.flags = BuildingFlags::RoomAssigned;
  fort.placeBuilding(kBed, bed);
  // A shop (BuildingKind::Shop, shop_type 0): vanilla has no art for it,
  // so it draws as classic glyphs.
  SyntheticFort::BuildingSpec shop = rect(BuildingKind::Shop, 34, 12, 36, 14, kSurfaceZ, granite);
  shop.subtype = 0;
  fort.placeBuilding(kShop, shop);
  // A forbidden door east of the workshop.
  SyntheticFort::BuildingSpec door = rect(BuildingKind::Door, 27, 31, 27, 31, kSurfaceZ, granite);
  door.flags = BuildingFlags::Forbidden;
  fort.placeBuilding(kDoor, door);
  // A 5x4 stockpile with two corners left out (extents).
  SyntheticFort::BuildingSpec pile = rect(BuildingKind::Stockpile, 16, 30, 20, 33, kSurfaceZ);
  pile.extents.assign(20, 1);
  pile.extents[0] = 0;   // (16,30)
  pile.extents[19] = 0;  // (20,33)
  fort.placeBuilding(kStockpile, pile);
  // A 3x2 bridge still under construction; it completes at tick 1008.
  fort.placeBuilding(kBridge, rect(BuildingKind::Bridge, 30, 26, 32, 27, kSurfaceZ, granite,
                                   BuildingStage::InProgress));
}

void authorItems(SyntheticFort& fort) {
  const uint16_t granite = fort.material("GRANITE");
  const uint16_t oak = fort.material("OAK");
  const uint16_t iron = fort.material("IRON");
  // Logs by the south-west oak; kLogA is hauled away at tick 1003.
  fort.placeItem(kLogA, itemAt(ItemKind::Wood, 5, 40, kSurfaceZ, oak));
  fort.placeItem(kLogB, itemAt(ItemKind::Wood, 7, 41, kSurfaceZ, oak));
  // A stack of iron bars marked for melting and a forbidden pick on the
  // stockpile floor (items on a stockpile are on the ground).
  fort.placeItem(kBars, itemAt(ItemKind::Bar, 17, 31, kSurfaceZ, iron, 5, ItemFlags::Melt));
  SyntheticFort::ItemSpec pick =
      itemAt(ItemKind::Weapon, 18, 31, kSurfaceZ, iron, 1, ItemFlags::Forbidden);
  pick.subtype = 12;
  pick.subtypeRaw = "ITEM_WEAPON_PICK";
  fort.placeItem(kPick, pick);
  // A boulder marked for dumping; kicked one tile at tick 1012.
  fort.placeItem(kBoulder, itemAt(ItemKind::Boulder, 12, 25, kSurfaceZ, granite, 1, ItemFlags::Dump));
  // A dwarf corpse by the oak with its CORPSE-role stack (v5); it
  // rots to bone at tick 1011 (stack change with the Rotten flag), and a
  // goblin corpse piece with no page-resolvable art (empty stack).
  const uint16_t dwarfMat = fort.material("CREATURE:DWARF:MUSCLE");
  SyntheticFort::ItemSpec corpse = itemAt(ItemKind::Corpse, 41, 8, kSurfaceZ, dwarfMat);
  corpse.corpseFlags = CorpseFlags::Unbutchered | CorpseFlags::Leather | CorpseFlags::Bone |
                       CorpseFlags::Rottable | CorpseFlags::HairWool;
  fort.placeItem(kCorpse, corpse);
  fort.setItemAppearance(kCorpse, corpseStack(2, 5, false));
  SyntheticFort::ItemSpec skull =
      itemAt(ItemKind::CorpsePiece, 44, 24, kSurfaceZ, fort.material("CREATURE:GOBLIN:BONE"));
  skull.corpseFlags = CorpseFlags::Bone | CorpseFlags::Skull;
  fort.placeItem(kCorpsePiece, skull);
  // A piece of dog meat on the turf: no vanilla art, drawn as its classic
  // glyph in the material's BASIC_COLOR.
  fort.placeItem(kMeat, itemAt(ItemKind::Meat, 36, 20, kSurfaceZ, fort.material("CREATURE:DOG:MUSCLE")));
  // A spider web across the tunnel mouth (a THREAD item with the Web flag).
  fort.placeItem(kWeb, itemAt(ItemKind::Thread, 21, 12, kSurfaceZ, fort.material("CREATURE:SPIDER_CAVE:SILK"),
                              1, ItemFlags::Web));
}

}  // namespace

int main(int argc, char** argv) {
  const std::string out = argc > 1 ? argv[1] : "demo_fort.df3dfix";

  SyntheticFort fort(48, 48, 12);
  authorTerrain(fort);
  // A mining pair heading east, a wandering cat, an idle dwarf by a stair.
  fort.addUnit(1, "DWARF", 8, 20, 5, JobKind::Mine);
  fort.addUnit(2, "DWARF", 8, 22, 5, JobKind::Mine);
  fort.addUnit(3, "CAT", 30, 30, 5);
  fort.addUnit(4, "DWARF", 20, 10, 5);
  // A forgotten beast lumbering on the surface: procedurally generated, so
  // it never gets a layer stack and draws as its classic glyph.
  fort.addUnit(12, "FORGOTTEN_BEAST_7", 40, 30, 5, JobKind::Fight);
  // Appearance references (v3): the dwarves get a layered stack in
  // the shape the bridge publishes (shadow, body with a skin palette row,
  // hair as a 1x2 large image); the cat a single as-is sprite. Unit 2's
  // stack changes mid-stream (a helm goes on) so the Delta path is covered.
  authorAppearances(fort);
  // Buildings and items (v4): Full at the first snapshot, Deltas
  // after: the bridge completes (1008), a planned chair appears (1009) and
  // is cancelled (1013), a log is hauled away (1003), a boulder appears
  // where the miners dug (1009), another is kicked one tile (1012).
  authorBuildings(fort);
  authorItems(fort);
  // Classic glyph tables (v5): Full at the first snapshot, a Delta when a
  // new species (the goblin) shows up at 1007.
  authorGlyphs(fort);
  fort.snapshot(1000);  // terrain: Full; appearances: Delta (all four units)

  const TileState dugFloor = tileOf(TileShape::Floor, MaterialKind::Soil, fort.material("CLAY_LOAM"));
  for (int i = 1; i <= 6; ++i) {
    fort.moveUnit(1, 8 + i, 20, 5);
    fort.moveUnit(2, 8 + i, 22, 5);
    fort.moveUnit(3, 30 + (i % 2), 30 - i, 5);  // cat meanders north
    // The column under the miners is mined out (a one-block Delta per tick).
    fort.fillBox(TilePos(8 + i, 20, 4), TilePos(8 + i, 22, 4), dugFloor);
    if (i == 3) fort.removeItem(kLogA);  // hauled off the map tile
    fort.snapshot(1000 + i);
  }

  // A goblin arrives at the edge, rushes in, and is slain. Dwarf 2 puts a
  // helm on the same tick (appearance Delta for one unit).
  fort.addUnit(9, "GOBLIN", 46, 24, 5, JobKind::Fight);
  fort.setAppearance(2, dwarfStack(3, 0, true));
  SyntheticFort::CreatureGlyphSpec troll;
  troll.glyph = Glyph('T', 6, 0, 0);
  troll.soldierTile = 'T';
  fort.creatureGlyph("TROLL", troll);  // glyph Delta: a species the fort just learned of
  fort.snapshot(1007);
  fort.moveUnit(9, 45, 24, 5);
  fort.moveUnit(4, 20, 11, 5);
  fort.setBuildingStage(kBridge, BuildingStage::Complete);
  fort.snapshot(1008);
  fort.moveUnit(9, 44, 24, 5);
  fort.placeBuilding(kChair, rect(BuildingKind::Chair, 28, 40, 28, 40, kSurfaceZ, kNoMaterial,
                                  BuildingStage::Planned));
  fort.placeItem(kDugBoulder, itemAt(ItemKind::Boulder, 9, 21, 4, fort.material("GRANITE")));
  fort.snapshot(1009);
  fort.removeUnit(9);
  fort.snapshot(1010);

  // The idle dwarf takes the stairs down (z-transition), then a miner
  // falls into the dug shaft, and the cat is caught in a dwarven
  // teleportation accident (tests never-lerp behavior).
  fort.moveUnit(4, 20, 12, 4);
  // The shaft under miner 1 opens (channelled through to the gallery).
  for (int32_t z = 2; z <= 5; ++z) {
    fort.setTile(14, 20, z,
                 tileOf(TileShape::Empty, MaterialKind::None, kNoMaterial,
                        z == 5 ? TileFlags::Outside : TileFlags::NONE));
  }
  // The corpse rots to bone: Rotten flag, nothing rottable left (a
  // skeleton by the derivation), a one-layer bone-pile stack.
  {
    SyntheticFort::ItemSpec bones = fort.item(kCorpse);
    bones.flags = ItemFlags::Rotten;
    bones.corpseFlags = CorpseFlags::Bone;
    fort.placeItem(kCorpse, bones);
  }
  fort.setItemAppearance(kCorpse, corpseStack(2, 5, true));
  fort.snapshot(1011);
  fort.moveUnit(1, 14, 20, 1);  // 4-level fall
  fort.moveItem(kBoulder, 12, 26, kSurfaceZ);  // kicked one tile
  fort.snapshot(1012);
  fort.moveUnit(3, 5, 5, 5);  // teleport
  fort.removeBuilding(kChair);  // the planned chair is cancelled
  fort.snapshot(1013);
  fort.snapshot(1014);

  const auto bytes = fort.serialize();
  FixtureStream fs;
  std::string err;
  if (!parseFixture(bytes, fs, err)) {
    std::fprintf(stderr, "generator bug, fixture does not parse: %s\n", err.c_str());
    return 1;
  }
  if (auto verr = validateStream(fs)) {
    std::fprintf(stderr, "generator bug, fixture invalid: %s\n", verr->c_str());
    return 1;
  }
  if (!writeFixtureFile(out, bytes, err)) {
    std::fprintf(stderr, "%s\n", err.c_str());
    return 1;
  }
  std::printf("wrote %s (%zu snapshots, %zu bytes)\n", out.c_str(), fs.snapshots.size(),
              bytes.size());
  return 0;
}
