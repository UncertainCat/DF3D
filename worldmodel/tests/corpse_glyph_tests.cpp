// Corpse appearance references and classic glyph tables (schema v5).
// Tier 0: the stores driven through WorldModel::ingest with
// hand-built SnapshotData (arrival, upsert, identical re-send, events
// coalesced, removal with the item, map change, glyph upsert by key).
// Tier 1: SyntheticFort streams and the demo fixture through the fixture
// path.
#include <doctest.h>

#include <string>

#include "synthetic_builder.h"
#include "wm/world_model.h"

using namespace wm;
namespace m = df3d::mirror;

namespace {

const TilePos kMap{48, 48, 6};

SnapshotData base(Tick tick) {
  SnapshotData d;
  d.tick = tick;
  d.mapSize = kMap;
  return d;
}

ItemObservation itm(ItemId id, ItemKind kind, int32_t x, int32_t y, int32_t z, uint8_t flags = 0) {
  ItemObservation i;
  i.id = id;
  i.kind = kind;
  i.pos = TilePos{x, y, z};
  i.flags = flags;
  return i;
}

AppearanceLayer layer(PageId page, uint16_t tx, uint16_t ty, PaletteId palette = kNoPalette,
                      int16_t row = kNoPaletteRow) {
  AppearanceLayer l;
  l.page = page;
  l.tileX = tx;
  l.tileY = ty;
  l.palette = palette;
  l.paletteRow = row;
  l.paletteKeyRow = palette == kNoPalette ? kNoPaletteRow : 0;
  return l;
}

// A Full item table with a dwarf corpse (two layers), a corpse piece (no
// art) and a web; the appearance tables name two pages and one palette.
SnapshotData fullScene(Tick tick = 1) {
  SnapshotData d = base(tick);
  d.itemScope = ChangeScope::Full;
  d.items.push_back(itm(1, ItemKind::Corpse, 5, 5, 2));
  d.items.push_back(itm(2, ItemKind::CorpsePiece, 6, 5, 2));
  d.items.push_back(itm(3, ItemKind::Thread, 7, 5, 2, kItemWeb));
  d.tilePages = {"DWARF_BODY_CORPSE", "DWARF_HAIR_CORPSE"};
  d.palettes = {"data/vanilla/x/dwarf_body_palettes.png"};
  d.itemAppearanceScope = AppearanceScope::Full;
  d.itemAppearances.push_back({1, 0xC0FFEE, {layer(0, 1, 4, 0, 2), layer(1, 3, 2)}});
  d.itemAppearances.push_back({2, 0, {}});
  return d;
}

}  // namespace

TEST_CASE("item appearances: arrive with the item Full, remap to model-wide ids, empty stacks kept") {
  WorldModel model;
  // Unit appearances first so the model's page table is not in snapshot order.
  SnapshotData u = base(0);
  u.units.push_back(UnitObservation{7, TilePos{1, 1, 1}, JobKind::Idle, "DWARF"});
  u.appearanceScope = AppearanceScope::Delta;
  u.tilePages = {"DWARF_HAIR_CORPSE"};
  u.appearances.push_back({7, 1, {layer(0, 0, 0)}});
  model.ingest(u, 0.0);
  model.ingest(fullScene(1), 0.1);

  CHECK(model.itemAppearanceCount() == 2);
  CHECK(model.itemAppearanceVersion() == 1);
  const ItemAppearance* a = model.itemAppearance(1);
  REQUIRE(a);
  CHECK(a->version == 0xC0FFEE);
  CHECK(a->tick == 1);
  REQUIRE(a->layers.size() == 2);
  CHECK(model.tilePageName(a->layers[0].page) == "DWARF_BODY_CORPSE");
  CHECK(model.tilePageName(a->layers[1].page) == "DWARF_HAIR_CORPSE");
  CHECK(a->layers[1].page == 0);  // interned by the unit appearance first
  CHECK(model.paletteName(a->layers[0].palette) == "data/vanilla/x/dwarf_body_palettes.png");
  CHECK(a->layers[0].paletteRow == 2);
  CHECK(a->layers[1].palette == kNoPalette);
  const ItemAppearance* b = model.itemAppearance(2);
  REQUIRE(b);
  CHECK(b->layers.empty());
  CHECK(model.itemAppearance(3) == nullptr);
  CHECK((model.item(3)->flags & kItemWeb) != 0);

  auto ev = model.drainItemAppearanceEvents();
  REQUIRE(ev.size() == 2);
  CHECK(ev[0].id == 1);
  CHECK(ev[0].version == 0xC0FFEE);
  CHECK(ev[1].id == 2);
  CHECK(model.drainItemAppearanceEvents().empty());
}

TEST_CASE("item appearances: Delta upserts, identical re-send is no change, events coalesce, removal drops") {
  WorldModel model;
  model.ingest(fullScene(1), 0.0);
  model.drainItemAppearanceEvents();
  model.drainItemEvents();

  // Identical re-send with the item record (the bridge's repeat window).
  SnapshotData same = base(2);
  same.itemScope = ChangeScope::Delta;
  same.items.push_back(itm(1, ItemKind::Corpse, 5, 5, 2));
  same.tilePages = {"DWARF_HAIR_CORPSE", "DWARF_BODY_CORPSE"};  // other order, same names
  same.palettes = {"data/vanilla/x/dwarf_body_palettes.png"};
  same.itemAppearanceScope = AppearanceScope::Delta;
  same.itemAppearances.push_back({1, 0xC0FFEE, {layer(1, 1, 4, 0, 2), layer(0, 3, 2)}});
  model.ingest(same, 0.1);
  CHECK(model.itemAppearanceVersion() == 1);
  CHECK(model.drainItemAppearanceEvents().empty());

  // The corpse rots: a one-layer bone stack, twice before a drain.
  SnapshotData rot = base(3);
  rot.itemScope = ChangeScope::Delta;
  rot.items.push_back(itm(1, ItemKind::Corpse, 5, 5, 2, kItemRotten));
  rot.tilePages = {"BONE_PILE"};
  rot.itemAppearanceScope = AppearanceScope::Delta;
  rot.itemAppearances.push_back({1, 0xB0BE, {layer(0, 0, 0)}});
  model.ingest(rot, 0.2);
  SnapshotData rot2 = rot;
  rot2.tick = 4;
  rot2.itemAppearances[0].version = 0xB0BF;
  model.ingest(rot2, 0.3);
  CHECK(model.itemAppearanceVersion() == 3);
  const ItemAppearance* a = model.itemAppearance(1);
  REQUIRE(a);
  CHECK(a->version == 0xB0BF);
  CHECK(a->tick == 4);
  REQUIRE(a->layers.size() == 1);
  CHECK(model.tilePageName(a->layers[0].page) == "BONE_PILE");
  auto ev = model.drainItemAppearanceEvents();
  REQUIRE(ev.size() == 1);
  CHECK(ev[0].id == 1);
  CHECK(ev[0].version == 0xB0BF);
  CHECK(ev[0].tick == 4);

  // Hauled away: the appearance goes with the item, no appearance event.
  SnapshotData gone = base(5);
  gone.itemScope = ChangeScope::Delta;
  gone.removedItems = {1};
  model.ingest(gone, 0.4);
  CHECK(model.item(1) == nullptr);
  CHECK(model.itemAppearance(1) == nullptr);
  CHECK(model.itemAppearanceCount() == 1);
  CHECK(model.drainItemAppearanceEvents().empty());
  CHECK(model.drainItemEvents().size() == 1);

  // A Full without the corpse piece drops its appearance too.
  SnapshotData full = base(6);
  full.itemScope = ChangeScope::Full;
  full.items.push_back(itm(3, ItemKind::Thread, 7, 5, 2, kItemWeb));
  model.ingest(full, 0.5);
  CHECK(model.itemAppearanceCount() == 0);
}

TEST_CASE("item appearances: an entry for an unknown item is ignored; a map change clears the store") {
  WorldModel model;
  SnapshotData d = fullScene(1);
  d.itemAppearances.push_back({99, 5, {}});
  model.ingest(d, 0.0);
  CHECK(model.itemAppearanceCount() == 2);
  CHECK(model.itemAppearance(99) == nullptr);

  SnapshotData other = base(2);
  other.mapSize = TilePos{16, 16, 2};
  model.ingest(other, 0.1);
  CHECK(model.itemAppearanceCount() == 0);
  CHECK(model.itemAppearance(1) == nullptr);
}

TEST_CASE("item appearances: ingestItems off keeps the store empty") {
  WorldModelConfig cfg;
  cfg.ingestItems = false;
  WorldModel model(cfg);
  model.ingest(fullScene(1), 0.0);
  CHECK(model.itemAppearanceCount() == 0);
  CHECK(model.drainItemAppearanceEvents().empty());
}

// --- glyph tables ---

namespace {
SnapshotData glyphFull(Tick tick = 1) {
  SnapshotData d = base(tick);
  d.glyphScope = ChangeScope::Full;
  d.creatureGlyphs.push_back({"DWARF", CreatureGlyph{Glyph{1, 3, 0, 0}, 2}});
  d.creatureGlyphs.push_back({"CAT", CreatureGlyph{Glyph{'c', 7, 0, 0}, 'c'}});
  MaterialGlyph granite;
  granite.tile = 7;
  granite.basicFg = 7;
  granite.basicBright = 0;
  granite.build = Glyph{7, 7, 7, 1};
  granite.tileColor = Glyph{7, 7, 7, 1};
  d.materialGlyphs.push_back({"INORGANIC:GRANITE", granite});
  d.itemDefGlyphs.push_back({ItemKind::Tool, "ITEM_TOOL_CAULDRON", 147});
  return d;
}
}  // namespace

TEST_CASE("glyphs: unknown before a Full; Full stores by key with model-wide material ids") {
  WorldModel model;
  CHECK_FALSE(model.glyphsKnown());
  CHECK(model.creatureGlyph("DWARF") == nullptr);
  CHECK(model.itemDefGlyph(ItemKind::Tool, "ITEM_TOOL_CAULDRON") == nullptr);
  model.ingest(glyphFull(), 0.0);
  CHECK(model.glyphsKnown());
  CHECK(model.glyphVersion() == 1);
  CHECK(model.creatureGlyphCount() == 2);
  CHECK(model.materialGlyphCount() == 1);
  CHECK(model.itemDefGlyphCount() == 1);
  const CreatureGlyph* dwarf = model.creatureGlyph("DWARF");
  REQUIRE(dwarf);
  CHECK(dwarf->glyph.tile == 1);
  CHECK(dwarf->glyph.fg == 3);
  CHECK(dwarf->soldierTile == 2);
  CHECK(model.creatureGlyph("CAT")->glyph.tile == 'c');
  CHECK(model.creatureGlyph("DOG") == nullptr);
  // The material was interned by the glyph table; terrain and items that
  // name it later resolve to the same id.
  CHECK(model.materialCount() == 1);
  CHECK(model.materialName(0) == "INORGANIC:GRANITE");
  const MaterialGlyph* granite = model.materialGlyph(0);
  REQUIRE(granite);
  CHECK(granite->tile == 7);
  CHECK(granite->build.bright == 1);
  CHECK(model.materialGlyph(1) == nullptr);
  CHECK(model.materialGlyph(kNoMaterial) == nullptr);
  const ItemDefGlyph* cauldron = model.itemDefGlyph(ItemKind::Tool, "ITEM_TOOL_CAULDRON");
  REQUIRE(cauldron);
  CHECK(cauldron->tile == 147);
  CHECK(cauldron->kind == ItemKind::Tool);
  CHECK(model.itemDefGlyph(ItemKind::Weapon, "ITEM_TOOL_CAULDRON") == nullptr);

  SnapshotData items = base(2);
  items.itemScope = ChangeScope::Full;
  items.materials = {"INORGANIC:GRANITE"};
  ItemObservation boulder = itm(1, ItemKind::Boulder, 1, 1, 1);
  boulder.material = 0;
  items.items.push_back(boulder);
  model.ingest(items, 0.1);
  CHECK(model.materialCount() == 1);
  CHECK(model.materialGlyph(model.item(1)->material) == granite);
}

TEST_CASE("glyphs: Delta upserts new and changed entries; identical re-sends are not changes") {
  WorldModel model;
  model.ingest(glyphFull(1), 0.0);
  SnapshotData same = glyphFull(2);
  same.glyphScope = ChangeScope::Delta;
  model.ingest(same, 0.1);
  CHECK(model.glyphVersion() == 1);

  SnapshotData delta = base(3);
  delta.glyphScope = ChangeScope::Delta;
  delta.creatureGlyphs.push_back({"DWARF", CreatureGlyph{Glyph{1, 3, 0, 1}, 2}});  // brighter
  delta.creatureGlyphs.push_back({"GOBLIN", CreatureGlyph{Glyph{'g', 2, 0, 0}, 'G'}});
  MaterialGlyph iron;
  iron.tile = 7;
  iron.basicFg = 7;
  iron.basicBright = 1;
  delta.materialGlyphs.push_back({"INORGANIC:IRON", iron});
  delta.itemDefGlyphs.push_back({ItemKind::Tool, "ITEM_TOOL_CAULDRON", 148});
  model.ingest(delta, 0.2);
  CHECK(model.glyphVersion() == 2);
  CHECK(model.creatureGlyphCount() == 3);
  CHECK(model.creatureGlyph("DWARF")->glyph.bright == 1);
  CHECK(model.creatureGlyph("GOBLIN")->soldierTile == 'G');
  CHECK(model.materialGlyphCount() == 2);
  CHECK(model.materialGlyph(1)->basicBright == 1);
  CHECK(model.itemDefGlyph(ItemKind::Tool, "ITEM_TOOL_CAULDRON")->tile == 148);

  // Raw tables belong to a session; a new world may reuse their keys.
  SnapshotData other = base(4);
  other.mapSize = TilePos{16, 16, 2};
  model.ingest(other, 0.3);
  CHECK(model.sessionGeneration() == 1);
  CHECK(model.creatureGlyphCount() == 0);
  CHECK_FALSE(model.glyphsKnown());
}

// --- tier 1 ---

TEST_CASE("SyntheticFort corpse stacks and glyph tables reach the model through the fixture path") {
  m::SyntheticFort fort(20, 20, 2);
  m::SyntheticFort::ItemSpec corpse;
  corpse.kind = m::ItemKind::Corpse;
  corpse.x = 3;
  corpse.y = 3;
  corpse.z = 0;
  fort.placeItem(1, corpse);
  m::SyntheticFort::ItemSpec web = corpse;
  web.kind = m::ItemKind::Thread;
  web.x = 4;
  web.flags = m::ItemFlags::Web;
  fort.placeItem(2, web);
  m::SyntheticFort::Layer body;
  body.page = "DWARF_BODY_CORPSE";
  body.tileX = 1;
  body.tileY = 4;
  body.palette = "data/vanilla/x/dwarf_body_palettes.png";
  body.paletteRow = 2;
  body.paletteKeyRow = 0;
  fort.setItemAppearance(1, {body});
  m::SyntheticFort::CreatureGlyphSpec dwarf;
  dwarf.glyph = m::Glyph(1, 3, 0, 0);
  dwarf.soldierTile = 2;
  fort.creatureGlyph("DWARF", dwarf);
  fort.snapshot(1);
  m::SyntheticFort::Layer bones;
  bones.page = "BONE_PILE";
  fort.setItemAppearance(1, {bones});
  m::SyntheticFort::CreatureGlyphSpec cat;
  cat.glyph = m::Glyph('c', 7, 0, 0);
  fort.creatureGlyph("CAT", cat);
  fort.snapshot(2);

  WorldModel model;
  std::string err;
  REQUIRE_MESSAGE(loadFixtureBytes(model, fort.serialize(), err), err);
  CHECK(model.itemCount() == 2);
  CHECK((model.item(2)->flags & kItemWeb) != 0);
  const ItemAppearance* a = model.itemAppearance(1);
  REQUIRE(a);
  CHECK(a->tick == 2);
  REQUIRE(a->layers.size() == 1);
  CHECK(model.tilePageName(a->layers[0].page) == "BONE_PILE");
  CHECK(model.itemAppearanceVersion() == 2);
  CHECK(model.glyphsKnown());
  CHECK(model.creatureGlyphCount() == 2);
  CHECK(model.glyphVersion() == 2);
  auto ev = model.drainItemAppearanceEvents();
  REQUIRE(ev.size() == 1);
  CHECK(ev[0].id == 1);
}

TEST_CASE("demo fort fixture: the dwarf corpse rots at 1011, the web is flagged, glyphs Full then Delta") {
  WorldModel model;
  std::string err;
  REQUIRE_MESSAGE(loadFixtureFile(model, DF3D_FIXTURE_DIR "/synthetic/demo_fort.df3dfix", err),
                  err);
  const MapItem* corpse = model.item(106);
  REQUIRE(corpse);
  CHECK(corpse->kind == ItemKind::Corpse);
  CHECK((corpse->flags & kItemRotten) != 0);
  CHECK(corpse->corpseFlags == kCorpseBone);
  CHECK(isSkeleton(corpse->corpseFlags));
  CHECK(corpse->tick == 1011);
  CHECK(model.item(107)->corpseFlags == (kCorpseBone | kCorpseSkull));
  // isSkeleton() is a whole-corpse derivation; a bone piece satisfies it
  // trivially, so consumers test the kind first.
  CHECK(model.item(107)->kind == ItemKind::CorpsePiece);
  const ItemAppearance* a = model.itemAppearance(106);
  REQUIRE(a);
  CHECK(a->tick == 1011);
  REQUIRE(a->layers.size() == 1);
  CHECK(model.tilePageName(a->layers[0].page) == "BONE_PILE");
  const ItemAppearance* piece = model.itemAppearance(107);
  REQUIRE(piece);
  CHECK(piece->layers.empty());
  CHECK(model.itemAppearance(108) == nullptr);
  CHECK((model.item(108)->flags & kItemWeb) != 0);
  CHECK(model.item(108)->kind == ItemKind::Thread);
  CHECK(model.itemAppearanceVersion() == 2);  // Full at 1000, the rot at 1011
  CHECK(model.glyphsKnown());
  CHECK(model.creatureGlyphCount() == 5);  // DWARF, CAT, GOBLIN, FORGOTTEN_BEAST_7, then TROLL at 1007
  CHECK(model.materialGlyphCount() == 3);
  CHECK(model.itemDefGlyphCount() == 1);
  CHECK(model.glyphVersion() == 2);
  CHECK(model.creatureGlyph("TROLL")->glyph.tile == 'T');

  // Stepwise: the fresh corpse's ten-layer stack before the rot.
  auto replay = FixtureReplay::open(DF3D_FIXTURE_DIR "/synthetic/demo_fort.df3dfix", err);
  REQUIRE_MESSAGE(replay, err);
  WorldModel step;
  replay->stepTo(step, 10.05);
  CHECK((step.item(106)->corpseFlags & kCorpseRottable) != 0);
  CHECK_FALSE(isSkeleton(step.item(106)->corpseFlags));
  const ItemAppearance* fresh = step.itemAppearance(106);
  REQUIRE(fresh);
  CHECK(fresh->layers.size() == 10);
  CHECK(step.tilePageName(fresh->layers[0].page) == "DWARF_BODY_CORPSE");
  CHECK(step.tilePageName(fresh->layers[9].page) == "DWARF_HAIR_CORPSE");
  CHECK(step.creatureGlyphCount() == 4);
  CHECK(step.drainItemAppearanceEvents().size() == 2);
  replay->stepAll(step);
  auto ev = step.drainItemAppearanceEvents();
  REQUIRE(ev.size() == 1);
  CHECK(ev[0].id == 106);
  CHECK(ev[0].tick == 1011);
}
