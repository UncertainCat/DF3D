#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest.h>
#include "df3d_mesher/level_block_revision.h"
#include "df3d_mesher/minimap.h"

using namespace df3d::mesher;

TEST_CASE("selected-level cache ignores unrelated z but detects every relevant block and scope") {
    wm::WorldModel model;
    std::array<wm::TileState,256> selected{}, other{};
    for (auto& tile : selected) tile.shape = wm::TileShape::Floor;
    other = selected;
    wm::SnapshotData snapshot;
    snapshot.mapSize = {33,17,4}; snapshot.tick = 1;
    snapshot.terrainScope = wm::TerrainScope::Full;
    snapshot.blocks = {{{0,0,1},selected.data()},{{0,0,2},other.data()}};
    model.ingest(snapshot, 0);
    LevelBlockRevision cache;
    CHECK(cache.update(model,1));
    CHECK(cache.blockChecks == 6); // Includes unknown/partial edge blocks.
    CHECK_FALSE(cache.update(model,1));
    CHECK(cache.blockChecks == 6); // No block checks for unchanged publication.
    snapshot.terrainScope = wm::TerrainScope::Delta; snapshot.tick++;
    other[0].liquidLevel = 3; other[0].liquidKind = wm::LiquidKind::Water;
    snapshot.blocks = {{{0,0,2},other.data()}};
    model.ingest(snapshot,1);
    CHECK_FALSE(cache.update(model,1));
    CHECK(cache.blockChecks == 12); // Unrelated z never requires tile sampling.
    selected[0].liquidLevel = 1; selected[0].liquidKind = wm::LiquidKind::Water;
    snapshot.blocks = {{{0,0,1},selected.data()}}; snapshot.tick++;
    model.ingest(snapshot,2);
    CHECK(cache.update(model,1));
    const int water = minimapColor(model.tileAt({0,0,1}));
    selected[0].liquidLevel = 7; snapshot.tick++;
    model.ingest(snapshot,3);
    CHECK(cache.update(model,1));
    CHECK(minimapColor(model.tileAt({0,0,1})) == water);
    // Order changes on hidden cells still invalidate; minimap remains hidden.
    selected[1].flags = wm::kTileHidden | wm::kTileDigDesignated;
    selected[1].designation = wm::DesignationKind::Dig;
    snapshot.tick++; model.ingest(snapshot,4);
    CHECK(cache.update(model,1));
    CHECK(minimapColor(model.tileAt({1,0,1})) == -1);
    selected[1].flags = wm::kTileHidden | wm::kTileSmoothDesignated;
    selected[1].designation = wm::DesignationKind::Smooth;
    snapshot.tick++; model.ingest(snapshot,5);
    CHECK(cache.update(model,1));
    selected[1].designationPriority = 1;
    snapshot.tick++; model.ingest(snapshot,5.1);
    CHECK(cache.update(model,1));
    selected[1].designationMarker = true;
    snapshot.tick++; model.ingest(snapshot,5.2);
    CHECK(cache.update(model,1));
    selected[1].track = 9;
    snapshot.tick++; model.ingest(snapshot,5.3); CHECK(cache.update(model,1));
    selected[1].traffic = 2;
    snapshot.tick++; model.ingest(snapshot,5.4); CHECK(cache.update(model,1));
    selected[1].warnings = 1;
    snapshot.tick++; model.ingest(snapshot,5.5); CHECK(cache.update(model,1));
    // Identical retransmissions change neither block nor cached level.
    const auto checks = cache.blockChecks;
    snapshot.tick++; model.ingest(snapshot,6);
    CHECK_FALSE(cache.update(model,1));
    CHECK(cache.blockChecks == checks);
    snapshot.blocks = {{{2,1,1},selected.data()}}; snapshot.tick++;
    model.ingest(snapshot,7);
    CHECK(cache.update(model,1)); // Previously unknown edge block.
    CHECK(cache.update(model,2));
    CHECK(cache.update(model,1));
    CHECK(cache.update(model,-1)); CHECK_FALSE(cache.update(model,-1));
    CHECK(cache.update(model,1));
    // Generation prevents aliasing reset block versions and cached empty maps.
    snapshot.tick = 1; snapshot.terrainScope = wm::TerrainScope::Full;
    model.ingest(snapshot,8);
    CHECK(cache.update(model,1));
    snapshot.mapSize = {16,16,2}; snapshot.tick++;
    snapshot.blocks = {{{0,0,1},selected.data()}};
    model.ingest(snapshot,9);
    CHECK(cache.update(model,1)); CHECK(cache.versions.size() == 1);
}

TEST_CASE("minimap refreshes lower liquid and selected occupancy without sampling unrelated levels") {
 wm::WorldModel model;
 std::array<wm::TileState,256> selected{},lower{},other{};
 wm::SnapshotData snap;snap.mapSize={16,16,3};snap.tick=1;snap.terrainScope=wm::TerrainScope::Full;
 snap.blocks={{{0,0,0},lower.data()},{{0,0,1},selected.data()},{{0,0,2},other.data()}};
 model.ingest(snap,0);MinimapRevision cache;
 CHECK(cache.update(model,1));CHECK_FALSE(cache.update(model,1));
 snap.terrainScope=wm::TerrainScope::Delta;snap.tick++;
 lower[0].liquidLevel=7;lower[0].liquidKind=wm::LiquidKind::Water;
 snap.blocks={{{0,0,0},lower.data()}};model.ingest(snap,1);
 CHECK(cache.update(model,1));
 CHECK(minimapColor(model.tileAt({0,0,1}),model.tileAt({0,0,0}))==0x0018c0);
 selected[0].buildingOccupancy=2;snap.tick++;snap.blocks={{{0,0,1},selected.data()}};model.ingest(snap,2);
 CHECK(cache.update(model,1));
 CHECK(minimapColor(model.tileAt({0,0,1}),model.tileAt({0,0,0}))==0xc88c00);
 other[0].buildingOccupancy=2;snap.tick++;snap.blocks={{{0,0,2},other.data()}};model.ingest(snap,3);
 CHECK_FALSE(cache.update(model,1));
 selected[0].buildingOccupancy=0;snap.tick++;snap.blocks={{{0,0,1},selected.data()}};model.ingest(snap,4);
 CHECK(cache.update(model,1));
 CHECK(minimapColor(model.tileAt({0,0,1}),model.tileAt({0,0,0}))==0x0018c0);
 model.resetSession();CHECK(cache.update(model,1));
}
