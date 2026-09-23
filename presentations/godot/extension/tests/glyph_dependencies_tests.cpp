#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest.h>
#include "../src/glyph_dependencies.h"
#include "../src/unit_art_key.h"
using namespace wm;
using df3d_godot::ItemGlyphDependency;
namespace {
SnapshotData frame(Tick tick, ChangeScope scope = ChangeScope::Delta) {
    SnapshotData result;
    result.tick = tick; result.mapSize = {16,16,2}; result.glyphScope = scope;
    return result;
}
}
TEST_CASE("unrelated appended glyph rows do not invalidate an existing fallback") {
    WorldModel model;
    auto initial = frame(1, ChangeScope::Full);
    initial.materials = {"INORGANIC:IRON"};
    MaterialGlyph iron; iron.itemSymbol = 42;
    initial.materialGlyphs.push_back({"INORGANIC:IRON", iron});
    model.ingest(initial, 0.0);
    ItemGlyphDependency dependency{0, ItemKind::Bar, "", {}};
    dependency.observed = dependency.read(model);
    REQUIRE(dependency.observed.material.has_value());
    auto delta = frame(2);
    delta.materialGlyphs.push_back({"INORGANIC:GOLD", MaterialGlyph{}});
    delta.creatureGlyphs.push_back({"DOG", CreatureGlyph{}});
    delta.itemDefGlyphs.push_back({ItemKind::Tool, "UNRELATED", 17});
    model.ingest(delta, 0.1);
    CHECK(model.glyphVersion() == 2);
    CHECK(dependency.read(model) == dependency.observed);
    auto edited = frame(3);
    iron.itemSymbol = 43;
    edited.materialGlyphs.push_back({"INORGANIC:IRON", iron});
    model.ingest(edited, 0.2);
    CHECK_FALSE(dependency.read(model) == dependency.observed);
}
TEST_CASE("missing material, creature and item definition rows remain dependencies") {
    WorldModel model;
    auto initial = frame(1, ChangeScope::Full);
    initial.materials = {"CREATURE:DWARF:BONE"};
    model.ingest(initial, 0.0);
    ItemGlyphDependency dependency{0, ItemKind::Tool, "CAULDRON", {}};
    dependency.observed = dependency.read(model);
    CHECK_FALSE(dependency.observed.material);
    CHECK_FALSE(dependency.observed.creature);
    CHECK_FALSE(dependency.observed.itemDefTile);
    auto material = frame(2);
    material.materialGlyphs.push_back({"CREATURE:DWARF:BONE", MaterialGlyph{}});
    model.ingest(material, 0.1);
    CHECK_FALSE(dependency.read(model) == dependency.observed);
    dependency.observed = dependency.read(model);
    auto creature = frame(3);
    creature.creatureGlyphs.push_back({"DWARF", CreatureGlyph{Glyph{1,7,0,0},2}});
    model.ingest(creature, 0.2);
    CHECK_FALSE(dependency.read(model) == dependency.observed);
    dependency.observed = dependency.read(model);
    auto itemdef = frame(4);
    itemdef.itemDefGlyphs.push_back({ItemKind::Tool, "CAULDRON", 147});
    model.ingest(itemdef, 0.3);
    CHECK_FALSE(dependency.read(model) == dependency.observed);
    dependency.observed = dependency.read(model);
    auto edit = frame(5);
    edit.itemDefGlyphs.push_back({ItemKind::Tool, "CAULDRON", 148});
    model.ingest(edit, 0.4);
    CHECK_FALSE(dependency.read(model) == dependency.observed);
    dependency.observed = dependency.read(model);
    auto creatureEdit = frame(6);
    creatureEdit.creatureGlyphs.push_back({"DWARF", CreatureGlyph{Glyph{2,3,0,1},2}});
    model.ingest(creatureEdit, 0.5);
    CHECK_FALSE(dependency.read(model) == dependency.observed);
    dependency.observed = dependency.read(model);
    auto epoch = frame(7, ChangeScope::Full);
    epoch.mapSize = {32,32,2};
    model.ingest(epoch, 0.6);
    CHECK_FALSE(dependency.read(model) == dependency.observed);
}
TEST_CASE("empty Full known transition is observable even without version change") {
    WorldModel model;
    ItemGlyphDependency dependency;
    dependency.observed = dependency.read(model);
    model.ingest(frame(1, ChangeScope::Full), 0.0);
    CHECK(model.glyphVersion() == 0);
    CHECK_FALSE(dependency.read(model) == dependency.observed);
    dependency.observed = dependency.read(model);
    model.ingest(frame(2, ChangeScope::Full), 0.1);
    CHECK(dependency.read(model) == dependency.observed);
    WorldModel nextSession;
    CHECK_FALSE(dependency.read(nextSession) == dependency.observed);
}

TEST_CASE("unit artwork cache accepts only unchanged source appearance and resource inputs") {
    df3d_godot::UnitArtKey key;
    key.resources=3;key.appearance=42;key.hasLayers=true;key.volume=60000;key.species="DWARF";
    CHECK(key.matches(3,42,true,60000,"DWARF",false,{}));
    CHECK_FALSE(key.matches(4,42,true,60000,"DWARF",false,{}));
    CHECK_FALSE(key.matches(3,43,true,60000,"DWARF",false,{}));
    CHECK_FALSE(key.matches(3,42,false,60000,"DWARF",false,{}));
    CHECK_FALSE(key.matches(3,42,true,70000,"DWARF",false,{}));
    CHECK_FALSE(key.matches(3,42,true,60000,"GOBLIN",false,{}));
    CreatureGlyph changed;changed.soldierTile=83;
    // Textured art must not churn when unrelated glyph metadata appears.
    CHECK(key.matches(3,42,true,60000,"DWARF",true,changed));
}
TEST_CASE("unit artwork fallback tracks late glyph arrival and glyph reset") {
    df3d_godot::UnitArtKey key;
    key.species="UNRESOLVED";key.glyphDependent=true;
    CHECK(key.matches(0,0,false,0,"UNRESOLVED",false,{}));
    CHECK_FALSE(key.matches(0,0,false,0,"UNRESOLVED",true,{}));
    CreatureGlyph glyph;glyph.soldierTile=40;
    CHECK_FALSE(key.matches(0,0,false,0,"UNRESOLVED",false,glyph));
    key.glyphsKnown=true;key.glyph=glyph;
    CHECK(key.matches(0,0,false,0,"UNRESOLVED",true,glyph));
    CHECK_FALSE(key.matches(0,0,false,0,"UNRESOLVED",true,{}));
    glyph.soldierTile=41;
    CHECK_FALSE(key.matches(0,0,false,0,"UNRESOLVED",true,glyph));
}
