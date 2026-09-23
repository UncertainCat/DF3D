// Corpse appearance references and classic glyph tables: builder
// emission, every validator rule, the Web item flag.
#include <doctest.h>

#include <string>
#include <vector>

#include "appearance_util.h"
#include "fixture_io.h"
#include "glyph_util.h"
#include "synthetic_builder.h"
#include "terrain_util.h"
#include "validate.h"

using namespace df3d::mirror;

namespace {

FixtureStream mustParse(const SyntheticFort& fort) {
  FixtureStream fs;
  std::string err;
  REQUIRE_MESSAGE(parseFixture(fort.serialize(), fs, err), err);
  return fs;
}

std::optional<std::string> validateBytes(const std::vector<uint8_t>& bytes) {
  FixtureStream fs;
  std::string err;
  REQUIRE_MESSAGE(parseFixture(bytes, fs, err), err);
  return validateStream(fs);
}

SyntheticFort::ItemSpec corpse(int32_t x, int32_t y, int32_t z, ItemKind kind = ItemKind::Corpse) {
  SyntheticFort::ItemSpec it;
  it.kind = kind;
  it.x = x;
  it.y = y;
  it.z = z;
  return it;
}

std::vector<SyntheticFort::Layer> corpseStack() {
  SyntheticFort::Layer body;
  body.page = "DWARF_BODY_CORPSE";
  body.tileX = 1;
  body.tileY = 4;
  body.palette =
      "data/vanilla/vanilla_creatures_graphics/graphics/images/dwarf/dwarf_body_palettes.png";
  body.paletteRow = 2;
  body.paletteKeyRow = 0;
  SyntheticFort::Layer hair;
  hair.page = "DWARF_HAIR_CORPSE";
  hair.tileX = 3;
  hair.tileY = 2;
  hair.palette =
      "data/vanilla/vanilla_creatures_graphics/graphics/images/dwarf/dwarf_hair_palettes.png";
  hair.paletteRow = 5;
  hair.paletteKeyRow = 0;
  return {body, hair};
}

Glyph glyph(uint8_t tile, uint8_t fg, uint8_t bg, uint8_t bright) {
  return Glyph(tile, fg, bg, bright);
}

// A raw single-snapshot v5 fixture with one Full item table of `items`
// and hand-built item appearances / glyph tables.
struct RawParts {
  std::vector<flatbuffers::Offset<MapItem>> items;
  AppearanceScope itemAppScope = AppearanceScope::None;
  std::vector<flatbuffers::Offset<ItemAppearance>> itemApps;
  std::vector<std::string> pages, palettes;
  ChangeScope glyphScope = ChangeScope::None;
  std::vector<flatbuffers::Offset<CreatureGlyph>> creatures;
  std::vector<flatbuffers::Offset<MaterialGlyph>> materials;
  std::vector<flatbuffers::Offset<ItemDefGlyph>> itemdefs;
};

template <class F>
std::vector<uint8_t> rawFixture(F&& fill) {
  flatbuffers::FlatBufferBuilder fbb;
  RawParts p;
  fill(fbb, p);
  const TilePos dims(20, 20, 3);
  auto units = fbb.CreateVector(std::vector<flatbuffers::Offset<UnitState>>{});
  auto items = fbb.CreateVector(p.items);
  auto apps = fbb.CreateVector(p.itemApps);
  auto pages = fbb.CreateVectorOfStrings(p.pages);
  auto palettes = fbb.CreateVectorOfStrings(p.palettes);
  auto creatures = fbb.CreateVector(p.creatures);
  auto materials = fbb.CreateVector(p.materials);
  auto itemdefs = fbb.CreateVector(p.itemdefs);
  auto snap = CreateSnapshot(fbb, static_cast<uint32_t>(SchemaVersion::Current), 1, 10, &dims,
                             units, TerrainScope::None, 0, 0, AppearanceScope::None, 0, pages,
                             palettes, ChangeScope::None, 0, 0,
                             p.items.empty() ? ChangeScope::None : ChangeScope::Full, items, 0,
                             p.itemAppScope, apps, p.glyphScope, creatures, materials, itemdefs);
  fbb.FinishSizePrefixed(snap, SnapshotIdentifier());
  return assembleFixture(
      {std::vector<uint8_t>(fbb.GetBufferPointer(), fbb.GetBufferPointer() + fbb.GetSize())});
}

flatbuffers::Offset<MapItem> rawItem(flatbuffers::FlatBufferBuilder& fbb, uint32_t id, ItemKind kind) {
  const TilePos pos(1, 1, 0);
  return CreateMapItemDirect(fbb, id, kind, kNoSubtype, nullptr, kNoMaterial, &pos);
}

flatbuffers::Offset<ItemAppearance> rawApp(flatbuffers::FlatBufferBuilder& fbb, uint32_t id,
                                           std::vector<AppearanceLayer> layers = {}) {
  auto vec = fbb.CreateVectorOfStructs(layers);
  return CreateItemAppearance(fbb, id, 7, vec);
}

}  // namespace

// --- item appearances: builder emission ---

TEST_CASE("item appearances: none until set; ride with the item record; Full covers corpses") {
  SyntheticFort fort(20, 20, 2);
  fort.placeItem(1, corpse(3, 3, 0));
  fort.placeItem(2, corpse(4, 3, 0, ItemKind::CorpsePiece));
  fort.placeItem(3, corpse(5, 3, 0, ItemKind::Wood));
  fort.snapshot(1);  // item Full: corpses get empty entries, the log none
  fort.setItemAppearance(1, corpseStack());
  fort.snapshot(2);  // Delta: item 1 re-sent with its stack
  fort.moveItem(3, 6, 3, 0);
  fort.snapshot(3);  // Delta: the log moves, no appearance entries
  fort.requestFullItems();
  fort.snapshot(4);  // Full again: item 1's stack, item 2 empty
  auto fs = mustParse(fort);
  CHECK_FALSE(validateStream(fs));
  REQUIRE(fs.snapshots.size() == 4);

  const Snapshot* a = fs.snapshots[0];
  CHECK(a->item_scope() == ChangeScope::Full);
  CHECK(a->item_appearance_scope() == AppearanceScope::Full);
  REQUIRE(a->item_appearances()->size() == 2);
  CHECK(a->item_appearances()->Get(0)->item() == 1);
  CHECK(a->item_appearances()->Get(0)->layers()->size() == 0);
  CHECK(a->item_appearances()->Get(1)->item() == 2);

  const Snapshot* b = fs.snapshots[1];
  CHECK(b->item_scope() == ChangeScope::Delta);
  CHECK(b->item_appearance_scope() == AppearanceScope::Delta);
  REQUIRE(b->items()->size() == 1);
  CHECK(b->items()->Get(0)->id() == 1);
  REQUIRE(b->item_appearances()->size() == 1);
  const ItemAppearance* ia = b->item_appearances()->Get(0);
  CHECK(ia->item() == 1);
  REQUIRE(ia->layers()->size() == 2);
  CHECK(std::string(b->tile_pages()->Get(ia->layers()->Get(0)->page())->c_str()) ==
        "DWARF_BODY_CORPSE");
  CHECK(std::string(b->tile_pages()->Get(ia->layers()->Get(1)->page())->c_str()) ==
        "DWARF_HAIR_CORPSE");
  CHECK(b->palettes()->size() == 2);
  CHECK(ia->layers()->Get(0)->palette_row() == 2);
  // version = the hash convention over the layers.
  uint32_t h = appearanceHashBegin();
  for (const auto& l : corpseStack())
    h = appearanceHashLayer(h, l.page.data(), l.page.size(), l.tileX, l.tileY, l.cellsX, l.cellsY,
                            l.palette.data(), l.palette.size(), l.paletteRow, l.paletteKeyRow,
                            l.offsetX, l.offsetY);
  CHECK(ia->version() == h);

  const Snapshot* c = fs.snapshots[2];
  CHECK(c->item_scope() == ChangeScope::Delta);
  CHECK(c->item_appearance_scope() == AppearanceScope::None);
  CHECK(c->item_appearances() == nullptr);

  const Snapshot* d = fs.snapshots[3];
  CHECK(d->item_appearance_scope() == AppearanceScope::Full);
  REQUIRE(d->item_appearances()->size() == 2);
  CHECK(d->item_appearances()->Get(0)->layers()->size() == 2);
  CHECK(d->item_appearances()->Get(1)->layers()->size() == 0);
}

TEST_CASE("item appearances: a removed item drops its stack; unit and item layers share the tables") {
  SyntheticFort fort(20, 20, 2);
  fort.addUnit(1, "DWARF", 1, 1, 0);
  fort.placeItem(1, corpse(3, 3, 0));
  fort.setItemAppearance(1, corpseStack());
  fort.setAppearance(1, corpseStack());  // same pages: interned once
  fort.snapshot(1);
  fort.removeItem(1);
  fort.snapshot(2);
  auto fs = mustParse(fort);
  CHECK_FALSE(validateStream(fs));
  const Snapshot* a = fs.snapshots[0];
  CHECK(a->tile_pages()->size() == 2);
  CHECK(a->palettes()->size() == 2);
  CHECK(a->appearances()->size() == 1);
  CHECK(a->item_appearances()->size() == 1);
  const Snapshot* b = fs.snapshots[1];
  CHECK(b->item_appearance_scope() == AppearanceScope::None);
  CHECK(b->removed_items()->size() == 1);
  CHECK_THROWS_AS(fort.setItemAppearance(1, corpseStack()), std::out_of_range);
}

// --- item appearances: validator rules ---

TEST_CASE("validator rejects item appearances under scope None or naming absent items") {
  auto err = validateBytes(rawFixture([](flatbuffers::FlatBufferBuilder& fbb, RawParts& p) {
    p.items.push_back(rawItem(fbb, 1, ItemKind::Corpse));
    p.itemApps.push_back(rawApp(fbb, 1));
  }));
  REQUIRE(err);
  CHECK(err->find("item_appearance_scope None but 1 item appearances present") != std::string::npos);

  err = validateBytes(rawFixture([](flatbuffers::FlatBufferBuilder& fbb, RawParts& p) {
    p.items.push_back(rawItem(fbb, 1, ItemKind::Corpse));
    p.itemAppScope = AppearanceScope::Delta;
    p.itemApps.push_back(rawApp(fbb, 1));
    p.itemApps.push_back(rawApp(fbb, 9));
  }));
  REQUIRE(err);
  CHECK(err->find("appearance of item 9: item not in this snapshot") != std::string::npos);

  err = validateBytes(rawFixture([](flatbuffers::FlatBufferBuilder& fbb, RawParts& p) {
    p.items.push_back(rawItem(fbb, 1, ItemKind::Corpse));
    p.itemAppScope = AppearanceScope::Delta;
    p.itemApps.push_back(rawApp(fbb, 1));
    p.itemApps.push_back(rawApp(fbb, 1));
  }));
  REQUIRE(err);
  CHECK(err->find("appearance of item 1: duplicate appearance") != std::string::npos);

  err = validateBytes(rawFixture([](flatbuffers::FlatBufferBuilder& fbb, RawParts& p) {
    p.items.push_back(rawItem(fbb, 1, ItemKind::Corpse));
    p.itemAppScope = static_cast<AppearanceScope>(7);
  }));
  REQUIRE(err);
  CHECK(err->find("invalid item_appearance_scope value 7") != std::string::npos);
}

TEST_CASE("validator: Full item appearances must cover every corpse item; layers are range-checked") {
  auto err = validateBytes(rawFixture([](flatbuffers::FlatBufferBuilder& fbb, RawParts& p) {
    p.items.push_back(rawItem(fbb, 1, ItemKind::Corpse));
    p.items.push_back(rawItem(fbb, 2, ItemKind::CorpsePiece));
    p.items.push_back(rawItem(fbb, 3, ItemKind::Wood));
    p.itemAppScope = AppearanceScope::Full;
    p.itemApps.push_back(rawApp(fbb, 1));
  }));
  REQUIRE(err);
  CHECK(err->find("item_appearance_scope Full but corpse item 2 has no appearance") !=
        std::string::npos);

  // Non-corpse items need no entry under Full.
  err = validateBytes(rawFixture([](flatbuffers::FlatBufferBuilder& fbb, RawParts& p) {
    p.items.push_back(rawItem(fbb, 1, ItemKind::Corpse));
    p.items.push_back(rawItem(fbb, 3, ItemKind::Wood));
    p.itemAppScope = AppearanceScope::Full;
    p.itemApps.push_back(rawApp(fbb, 1));
  }));
  CHECK_FALSE(err);

  // A layer whose page index is outside tile_pages.
  err = validateBytes(rawFixture([](flatbuffers::FlatBufferBuilder& fbb, RawParts& p) {
    p.items.push_back(rawItem(fbb, 1, ItemKind::Corpse));
    p.itemAppScope = AppearanceScope::Delta;
    p.pages = {"DWARF_BODY_CORPSE"};
    p.itemApps.push_back(rawApp(fbb, 1, {AppearanceLayer(3, 0, 0, 1, 1, kNoPalette, -1, -1, 0, 0)}));
  }));
  REQUIRE(err);
  CHECK(err->find("appearance of item 1: layer 0: page index 3 out of range") != std::string::npos);
}

// --- corpse flags ---

TEST_CASE("corpse flags round-trip on corpse items and are rejected elsewhere or with unknown bits") {
  SyntheticFort fort(20, 20, 2);
  SyntheticFort::ItemSpec c = corpse(3, 3, 0);
  c.corpseFlags = CorpseFlags::Bone | CorpseFlags::Skull;
  fort.placeItem(1, c);
  fort.snapshot(1);
  auto fs = mustParse(fort);
  CHECK_FALSE(validateStream(fs));
  CHECK(fs.snapshots[0]->items()->Get(0)->corpse_flags() == (CorpseFlags::Bone | CorpseFlags::Skull));

  SyntheticFort bad(20, 20, 2);
  SyntheticFort::ItemSpec log = corpse(3, 3, 0, ItemKind::Wood);
  log.corpseFlags = CorpseFlags::Wood;
  bad.placeItem(1, log);
  bad.snapshot(1);
  auto err = validateStream(mustParse(bad));
  REQUIRE(err);
  CHECK(err->find("corpse_flags 64 on a non-corpse item") != std::string::npos);

  SyntheticFort bits(20, 20, 2);
  c.corpseFlags = static_cast<CorpseFlags>(0x8000);
  bits.placeItem(1, c);
  bits.snapshot(1);
  err = validateStream(mustParse(bits));
  REQUIRE(err);
  CHECK(err->find("unknown corpse flag bits in 32768") != std::string::npos);
}

// --- Web flag ---

TEST_CASE("Web item flag round-trips and is accepted by the validator") {
  SyntheticFort fort(20, 20, 2);
  SyntheticFort::ItemSpec web;
  web.kind = ItemKind::Thread;
  web.x = 2;
  web.y = 2;
  web.z = 0;
  web.flags = ItemFlags::Web;
  fort.placeItem(1, web);
  fort.snapshot(1);
  auto fs = mustParse(fort);
  CHECK_FALSE(validateStream(fs));
  CHECK(fs.snapshots[0]->items()->Get(0)->flags() == ItemFlags::Web);
  CHECK(static_cast<uint8_t>(ItemFlags::Web) == 0x40);
}

// --- glyph tables: builder emission ---

TEST_CASE("glyphs: none until set, Full once, then Delta of changes, identical re-set is not a change") {
  SyntheticFort fort(8, 8, 1);
  fort.snapshot(1);
  SyntheticFort::CreatureGlyphSpec dwarf;
  dwarf.glyph = glyph(1, 3, 0, 0);
  dwarf.soldierTile = 2;
  fort.creatureGlyph("DWARF", dwarf);
  SyntheticFort::MaterialGlyphSpec granite;
  granite.tile = 7;
  granite.itemSymbol = 0;
  granite.basicFg = 7;
  granite.basicBright = 0;
  granite.build = glyph(7, 7, 7, 1);
  granite.tileColor = glyph(7, 7, 7, 1);
  fort.materialGlyph("INORGANIC:GRANITE", granite);
  fort.itemDefGlyph(ItemKind::Tool, "ITEM_TOOL_CAULDRON", 147);
  fort.snapshot(2);  // Full
  fort.creatureGlyph("DWARF", dwarf);  // identical: no change
  fort.snapshot(3);  // None
  SyntheticFort::CreatureGlyphSpec cat;
  cat.glyph = glyph('c', 7, 0, 0);
  fort.creatureGlyph("CAT", cat);
  granite.basicBright = 1;
  fort.materialGlyph("INORGANIC:GRANITE", granite);
  fort.snapshot(4);  // Delta: CAT new, GRANITE changed
  fort.requestFullGlyphs();
  fort.snapshot(5);  // Full: DWARF, CAT, GRANITE, the tool
  auto fs = mustParse(fort);
  CHECK_FALSE(validateStream(fs));
  REQUIRE(fs.snapshots.size() == 5);
  CHECK(fs.snapshots[0]->glyph_scope() == ChangeScope::None);
  CHECK(fs.snapshots[0]->creature_glyphs() == nullptr);

  const Snapshot* a = fs.snapshots[1];
  CHECK(a->glyph_scope() == ChangeScope::Full);
  REQUIRE(a->creature_glyphs()->size() == 1);
  const CreatureGlyph* cg = a->creature_glyphs()->Get(0);
  CHECK(std::string(cg->species()->c_str()) == "DWARF");
  CHECK(cg->glyph()->tile() == 1);
  CHECK(cg->glyph()->fg() == 3);
  CHECK(cg->soldier_tile() == 2);
  REQUIRE(a->material_glyphs()->size() == 1);
  const MaterialGlyph* mg = a->material_glyphs()->Get(0);
  CHECK(std::string(mg->material()->c_str()) == "INORGANIC:GRANITE");
  CHECK(mg->tile() == 7);
  CHECK(mg->basic_fg() == 7);
  CHECK(mg->build()->bright() == 1);
  REQUIRE(a->itemdef_glyphs()->size() == 1);
  CHECK(a->itemdef_glyphs()->Get(0)->kind() == ItemKind::Tool);
  CHECK(std::string(a->itemdef_glyphs()->Get(0)->subtype_raw()->c_str()) == "ITEM_TOOL_CAULDRON");
  CHECK(a->itemdef_glyphs()->Get(0)->tile() == 147);

  CHECK(fs.snapshots[2]->glyph_scope() == ChangeScope::None);

  const Snapshot* d = fs.snapshots[3];
  CHECK(d->glyph_scope() == ChangeScope::Delta);
  REQUIRE(d->creature_glyphs()->size() == 1);
  CHECK(std::string(d->creature_glyphs()->Get(0)->species()->c_str()) == "CAT");
  REQUIRE(d->material_glyphs()->size() == 1);
  CHECK(d->material_glyphs()->Get(0)->basic_bright() == 1);
  CHECK(d->itemdef_glyphs()->size() == 0);

  const Snapshot* e = fs.snapshots[4];
  CHECK(e->glyph_scope() == ChangeScope::Full);
  CHECK(e->creature_glyphs()->size() == 2);
  CHECK(e->material_glyphs()->size() == 1);
  CHECK(e->itemdef_glyphs()->size() == 1);
}

// --- glyph tables: validator rules ---

TEST_CASE("validator rejects glyph entries under scope None, empty keys, duplicates, bad colours") {
  auto err = validateBytes(rawFixture([](flatbuffers::FlatBufferBuilder& fbb, RawParts& p) {
    const Glyph g(1, 1, 0, 0);
    p.creatures.push_back(CreateCreatureGlyphDirect(fbb, "DWARF", &g, 1));
  }));
  REQUIRE(err);
  CHECK(err->find("glyph_scope None but 1 glyph entries present") != std::string::npos);

  err = validateBytes(rawFixture([](flatbuffers::FlatBufferBuilder& fbb, RawParts& p) {
    p.glyphScope = ChangeScope::Full;
    const Glyph g(1, 1, 0, 0);
    p.creatures.push_back(CreateCreatureGlyphDirect(fbb, "", &g, 1));
  }));
  REQUIRE(err);
  CHECK(err->find("creature glyph with empty species") != std::string::npos);

  err = validateBytes(rawFixture([](flatbuffers::FlatBufferBuilder& fbb, RawParts& p) {
    p.glyphScope = ChangeScope::Delta;
    const Glyph g(1, 1, 0, 0);
    p.creatures.push_back(CreateCreatureGlyphDirect(fbb, "DWARF", &g, 1));
    p.creatures.push_back(CreateCreatureGlyphDirect(fbb, "DWARF", &g, 1));
  }));
  REQUIRE(err);
  CHECK(err->find("creature glyph DWARF: duplicate species") != std::string::npos);

  err = validateBytes(rawFixture([](flatbuffers::FlatBufferBuilder& fbb, RawParts& p) {
    p.glyphScope = ChangeScope::Full;
    const Glyph g(1, 9, 0, 0);
    p.creatures.push_back(CreateCreatureGlyphDirect(fbb, "DWARF", &g, 1));
  }));
  REQUIRE(err);
  CHECK(err->find("creature glyph DWARF: glyph colour (9,0,0) outside") != std::string::npos);

  err = validateBytes(rawFixture([](flatbuffers::FlatBufferBuilder& fbb, RawParts& p) {
    p.glyphScope = ChangeScope::Full;
    const Glyph ok(7, 7, 0, 1), bad(7, 0, 0, 2);
    p.materials.push_back(CreateMaterialGlyphDirect(fbb, "INORGANIC:GRANITE", 7, 0, 7, 0, &ok, &bad));
  }));
  REQUIRE(err);
  CHECK(err->find("material glyph INORGANIC:GRANITE: tile_color colour (0,0,2) outside") !=
        std::string::npos);

  err = validateBytes(rawFixture([](flatbuffers::FlatBufferBuilder& fbb, RawParts& p) {
    p.glyphScope = ChangeScope::Full;
    const Glyph ok(7, 7, 0, 1);
    p.materials.push_back(CreateMaterialGlyphDirect(fbb, "INORGANIC:GRANITE", 7, 0, 8, 0, &ok, &ok));
  }));
  REQUIRE(err);
  CHECK(err->find("basic colour (8,0) outside") != std::string::npos);

  err = validateBytes(rawFixture([](flatbuffers::FlatBufferBuilder& fbb, RawParts& p) {
    p.glyphScope = ChangeScope::Full;
    const Glyph ok(7, 7, 0, 1);
    p.materials.push_back(CreateMaterialGlyphDirect(fbb, "INORGANIC:GRANITE", 7, 0, 7, 0, &ok, &ok));
    p.materials.push_back(CreateMaterialGlyphDirect(fbb, "INORGANIC:GRANITE", 7, 0, 7, 0, &ok, &ok));
  }));
  REQUIRE(err);
  CHECK(err->find("material glyph INORGANIC:GRANITE: duplicate material") != std::string::npos);

  err = validateBytes(rawFixture([](flatbuffers::FlatBufferBuilder& fbb, RawParts& p) {
    p.glyphScope = ChangeScope::Full;
    p.itemdefs.push_back(CreateItemDefGlyphDirect(fbb, static_cast<ItemKind>(200), "ITEM_TOOL_X", 1));
  }));
  REQUIRE(err);
  CHECK(err->find("itemdef glyph with invalid kind value 200") != std::string::npos);

  err = validateBytes(rawFixture([](flatbuffers::FlatBufferBuilder& fbb, RawParts& p) {
    p.glyphScope = ChangeScope::Full;
    p.itemdefs.push_back(CreateItemDefGlyphDirect(fbb, ItemKind::Tool, "", 1));
  }));
  REQUIRE(err);
  CHECK(err->find("itemdef glyph with empty subtype_raw") != std::string::npos);

  err = validateBytes(rawFixture([](flatbuffers::FlatBufferBuilder& fbb, RawParts& p) {
    p.glyphScope = ChangeScope::Full;
    p.itemdefs.push_back(CreateItemDefGlyphDirect(fbb, ItemKind::Tool, "ITEM_TOOL_X", 1));
    p.itemdefs.push_back(CreateItemDefGlyphDirect(fbb, ItemKind::Tool, "ITEM_TOOL_X", 2));
  }));
  REQUIRE(err);
  CHECK(err->find("itemdef glyph ITEM_TOOL_X: duplicate") != std::string::npos);

  err = validateBytes(rawFixture([](flatbuffers::FlatBufferBuilder&, RawParts& p) {
    p.glyphScope = static_cast<ChangeScope>(9);
  }));
  REQUIRE(err);
  CHECK(err->find("invalid glyph_scope value 9") != std::string::npos);
}
