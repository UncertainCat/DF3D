// Appearance references: builder emission, validators, hash convention.
#include <doctest.h>

#include "appearance_util.h"
#include "fixture_io.h"
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

std::vector<SyntheticFort::Layer> dwarfStack() {
  SyntheticFort::Layer shadow;
  shadow.page = "DWARF_BODY";
  shadow.tileX = 8;
  shadow.tileY = 3;
  SyntheticFort::Layer body;
  body.page = "DWARF_BODY";
  body.tileX = 3;
  body.tileY = 4;
  body.palette =
      "data/vanilla/vanilla_creatures_graphics/graphics/images/dwarf/dwarf_body_palettes.png";
  body.paletteRow = 2;
  body.paletteKeyRow = 0;
  SyntheticFort::Layer hair;
  hair.page = "DWARF_HAIR";
  hair.tileX = 3;
  hair.tileY = 13;
  hair.cellsX = 1;
  hair.cellsY = 2;
  hair.palette =
      "data/vanilla/vanilla_creatures_graphics/graphics/images/dwarf/dwarf_hair_palettes.png";
  hair.paletteRow = 5;
  hair.paletteKeyRow = 0;
  hair.offsetY = -2;
  return {shadow, body, hair};
}

uint32_t hashOf(const std::vector<SyntheticFort::Layer>& ls) {
  uint32_t h = appearanceHashBegin();
  for (const auto& l : ls)
    h = appearanceHashLayer(h, l.page.data(), l.page.size(), l.tileX, l.tileY, l.cellsX,
                            l.cellsY, l.palette.data(), l.palette.size(), l.paletteRow,
                            l.paletteKeyRow, l.offsetX, l.offsetY);
  return h;
}

// Builds a one-unit, one-layer fixture with `mutate` applied to the layer.
std::optional<std::string> errorFor(void (*mutate)(SyntheticFort::Layer&),
                                    AppearanceScope forged = AppearanceScope::Delta) {
  SyntheticFort fort(8, 8, 1);
  fort.addUnit(1, "DWARF", 1, 1, 0);
  SyntheticFort::Layer l = dwarfStack()[1];
  mutate(l);
  fort.setAppearance(1, {l});
  if (forged != AppearanceScope::Delta) fort.forgeNextAppearanceScope(forged);
  fort.snapshot(1);
  return validateStream(mustParse(fort));
}

// Hand-builds a one-unit snapshot (unit id 7) with the given appearances
// so the validator can be fed shapes the builder refuses to produce.
std::optional<std::string> validateHandBuilt(
    uint64_t unitId, std::vector<std::pair<uint64_t, AppearanceLayer>> entries) {
  flatbuffers::FlatBufferBuilder fbb;
  std::vector<flatbuffers::Offset<UnitState>> units;
  TilePos p(1, 1, 0);
  units.push_back(CreateUnitState(fbb, unitId, &p, fbb.CreateString("DWARF")));
  auto unitsVec = fbb.CreateVector(units);
  std::vector<flatbuffers::Offset<UnitAppearance>> apps;
  for (const auto& [id, layer] : entries) {
    std::vector<AppearanceLayer> layers{layer};
    auto layersVec = fbb.CreateVectorOfStructs(layers);
    apps.push_back(CreateUnitAppearance(fbb, id, 1, layersVec));
  }
  auto appsVec = fbb.CreateVector(apps);
  auto pages = fbb.CreateVectorOfStrings(std::vector<std::string>{"DWARF_BODY"});
  TilePos dims(8, 8, 1);
  auto snap = CreateSnapshot(fbb, static_cast<uint32_t>(SchemaVersion::Current), 1, 10, &dims,
                             unitsVec, TerrainScope::None, 0, 0, AppearanceScope::Delta, appsVec,
                             pages, 0);
  fbb.FinishSizePrefixed(snap, SnapshotIdentifier());
  std::vector<uint8_t> buf(fbb.GetBufferPointer(), fbb.GetBufferPointer() + fbb.GetSize());
  FixtureStream fs;
  std::string err;
  REQUIRE(parseFixture(assembleFixture({buf}), fs, err));
  return validateStream(fs);
}

}  // namespace

TEST_CASE("appearance: none until set, Delta on change, Full on request") {
  SyntheticFort fort(48, 48, 10);
  fort.addUnit(1, "DWARF", 10, 10, 5);
  fort.addUnit(2, "CAT", 12, 10, 5);
  fort.snapshot(100);  // no appearance yet
  fort.setAppearance(1, dwarfStack());
  fort.snapshot(101);  // Delta: unit 1
  fort.snapshot(102);  // nothing changed: None
  fort.requestFullAppearances();
  fort.snapshot(103);  // Full: 1 with stack, 2 with empty stack
  auto fs = mustParse(fort);
  REQUIRE_FALSE(validateStream(fs));
  REQUIRE(fs.snapshots.size() == 4);
  CHECK(fs.snapshots[0]->appearance_scope() == AppearanceScope::None);
  CHECK(fs.snapshots[0]->appearances() == nullptr);

  const Snapshot* d = fs.snapshots[1];
  CHECK(d->appearance_scope() == AppearanceScope::Delta);
  REQUIRE(d->appearances()->size() == 1);
  const UnitAppearance* a = d->appearances()->Get(0);
  CHECK(a->unit() == 1);
  REQUIRE(a->layers()->size() == 3);
  REQUIRE(d->tile_pages()->size() == 2);
  CHECK(std::string(d->tile_pages()->Get(0)->c_str()) == "DWARF_BODY");
  CHECK(std::string(d->tile_pages()->Get(1)->c_str()) == "DWARF_HAIR");
  REQUIRE(d->palettes()->size() == 2);
  const AppearanceLayer* shadow = a->layers()->Get(0);
  CHECK(shadow->page() == 0);
  CHECK(shadow->tile_x() == 8);
  CHECK(shadow->palette() == kNoPalette);
  CHECK(shadow->palette_row() == kNoPaletteRow);
  const AppearanceLayer* hair = a->layers()->Get(2);
  CHECK(hair->page() == 1);
  CHECK(hair->cells_y() == 2);
  CHECK(hair->palette() == 1);
  CHECK(hair->palette_row() == 5);
  CHECK(hair->palette_key_row() == 0);
  CHECK(hair->offset_y() == -2);

  CHECK(fs.snapshots[2]->appearance_scope() == AppearanceScope::None);

  const Snapshot* f = fs.snapshots[3];
  CHECK(f->appearance_scope() == AppearanceScope::Full);
  REQUIRE(f->appearances()->size() == 2);
  CHECK(f->appearances()->Get(1)->unit() == 2);
  CHECK(f->appearances()->Get(1)->layers()->size() == 0);
  // The version is the layer-stack hash: equal stacks, equal versions.
  CHECK(f->appearances()->Get(0)->version() == a->version());
  CHECK(f->appearances()->Get(1)->version() != a->version());
}

TEST_CASE("appearance: version changes with any field of any layer, and with order") {
  auto base = dwarfStack();
  uint32_t versions[6];
  versions[0] = hashOf(base);
  auto v = base;
  v[1].paletteRow = 3;
  versions[1] = hashOf(v);
  v = base;
  v[2].tileX = 4;
  versions[2] = hashOf(v);
  v = base;
  v[0].page = "DWARF_HAIR";
  versions[3] = hashOf(v);
  v = base;
  v.pop_back();
  versions[4] = hashOf(v);
  v = base;
  std::swap(v[0], v[1]);  // draw order matters
  versions[5] = hashOf(v);
  for (int i = 0; i < 6; ++i)
    for (int j = i + 1; j < 6; ++j) CHECK(versions[i] != versions[j]);
  // Deterministic: the builder stamps the same hash.
  SyntheticFort fort(8, 8, 1);
  fort.addUnit(1, "DWARF", 1, 1, 0);
  fort.setAppearance(1, base);
  fort.snapshot(1);
  auto fs = mustParse(fort);
  CHECK(fs.snapshots[0]->appearances()->Get(0)->version() == versions[0]);
}

TEST_CASE("appearance: removed units drop their appearance; re-set re-sends") {
  SyntheticFort fort(8, 8, 1);
  fort.addUnit(1, "DWARF", 1, 1, 0);
  fort.addUnit(2, "DWARF", 2, 1, 0);
  fort.setAppearance(1, dwarfStack());
  fort.setAppearance(2, dwarfStack());
  fort.snapshot(1);
  fort.removeUnit(2);
  fort.setAppearance(1, dwarfStack());  // same stack, re-sent (builder does not dedupe)
  fort.snapshot(2);
  auto fs = mustParse(fort);
  CHECK_FALSE(validateStream(fs));
  REQUIRE(fs.snapshots[1]->appearances()->size() == 1);
  CHECK(fs.snapshots[1]->appearances()->Get(0)->unit() == 1);
  CHECK_THROWS(fort.setAppearance(2, dwarfStack()));
}

TEST_CASE("validator: layer field ranges and palette consistency") {
  CHECK_FALSE(errorFor([](SyntheticFort::Layer&) {}));
  auto e = errorFor([](SyntheticFort::Layer& l) { l.cellsX = 0; });
  REQUIRE(e);
  CHECK(e->find("cells") != std::string::npos);
  e = errorFor([](SyntheticFort::Layer& l) { l.cellsY = 3; });
  REQUIRE(e);
  CHECK(e->find("cells") != std::string::npos);
  e = errorFor([](SyntheticFort::Layer& l) { l.palette.clear(); });  // row stays 2
  REQUIRE(e);
  CHECK(e->find("no palette") != std::string::npos);
  e = errorFor([](SyntheticFort::Layer& l) { l.paletteRow = -1; });
  REQUIRE(e);
  CHECK(e->find("negative") != std::string::npos);
  e = errorFor([](SyntheticFort::Layer& l) { l.palette = "C:/abs/palettes.png"; });
  REQUIRE(e);
  CHECK(e->find("install-relative") != std::string::npos);
  e = errorFor([](SyntheticFort::Layer& l) { l.palette = "data\\vanilla\\p.png"; });
  REQUIRE(e);
  CHECK(e->find("install-relative") != std::string::npos);
  e = errorFor([](SyntheticFort::Layer& l) { l.palette = "/data/p.png"; });
  REQUIRE(e);
}

TEST_CASE("validator: appearance scope rules") {
  // None with entries attached.
  auto e = errorFor([](SyntheticFort::Layer&) {}, AppearanceScope::None);
  REQUIRE(e);
  CHECK(e->find("None but") != std::string::npos);
  // Full must cover every unit.
  SyntheticFort fort(8, 8, 1);
  fort.addUnit(1, "DWARF", 1, 1, 0);
  fort.addUnit(2, "CAT", 2, 1, 0);
  fort.setAppearance(1, dwarfStack());
  fort.forgeNextAppearanceScope(AppearanceScope::Full);
  fort.snapshot(1);
  e = validateStream(mustParse(fort));
  REQUIRE(e);
  CHECK(e->find("Full with 1 appearances for 2 units") != std::string::npos);
  // A Delta covering a subset is fine.
  SyntheticFort fort2(8, 8, 1);
  fort2.addUnit(1, "DWARF", 1, 1, 0);
  fort2.addUnit(2, "CAT", 2, 1, 0);
  fort2.setAppearance(2, dwarfStack());
  fort2.snapshot(1);
  CHECK_FALSE(validateStream(mustParse(fort2)));
}

TEST_CASE("validator: appearance must reference a unit of the snapshot exactly once") {
  const AppearanceLayer ok(0, 1, 1, 1, 1, kNoPalette, -1, -1, 0, 0);
  CHECK_FALSE(validateHandBuilt(7, {{7, ok}}));
  auto e = validateHandBuilt(7, {{9, ok}});
  REQUIRE(e);
  CHECK(e->find("unit not in this snapshot") != std::string::npos);
  e = validateHandBuilt(7, {{7, ok}, {7, ok}});
  REQUIRE(e);
  CHECK(e->find("duplicate appearance") != std::string::npos);
  const AppearanceLayer badPage(1, 1, 1, 1, 1, kNoPalette, -1, -1, 0, 0);
  e = validateHandBuilt(7, {{7, badPage}});
  REQUIRE(e);
  CHECK(e->find("page index 1 out of range") != std::string::npos);
  const AppearanceLayer badPalette(0, 1, 1, 1, 1, 0, 0, 0, 0, 0);  // no palettes table
  e = validateHandBuilt(7, {{7, badPalette}});
  REQUIRE(e);
  CHECK(e->find("palette index 0 out of range") != std::string::npos);
}
