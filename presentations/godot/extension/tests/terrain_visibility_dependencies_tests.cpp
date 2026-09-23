#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest.h>
#include "../src/terrain_visibility_dependencies.h"
#include <array>
using df3d_godot::TerrainVisibilityDependencies;

TEST_CASE("terrain-only mutations do not invalidate entities") {
    TerrainVisibilityDependencies dependencies;
    std::array<wm::TileState,wm::kTilesPerBlock> tiles{};
    const wm::BlockPos block{1,2,3};
    CHECK(dependencies.observe(block,tiles.data(),false).tiles.all());
    tiles[17].liquidLevel=4; tiles[17].liquidKind=wm::LiquidKind::Water;
    tiles[30].designation=wm::DesignationKind::Dig;
    tiles[31].shape=wm::TileShape::Wall;
    tiles[32].materialKind=wm::MaterialKind::Stone;
    CHECK(dependencies.observe(block,tiles.data(),false).tiles.none());
    tiles[17].flags |= wm::kTileHidden;
    const auto changes=dependencies.observe(block,tiles.data(),false);
    CHECK(changes.tiles.count()==1);
    CHECK(changes.contains(17,33));
    CHECK_FALSE(changes.contains(18,33));
    CHECK_FALSE(changes.contains(1,33));
    CHECK_FALSE(changes.contains(17,49));
    CHECK(dependencies.observe(block,tiles.data(),false).tiles.none());
}

TEST_CASE("missing blocks, reveal toggles and resets preserve visibility semantics") {
    TerrainVisibilityDependencies dependencies;
    std::array<wm::TileState,wm::kTilesPerBlock> tiles{};
    const wm::BlockPos block{0,0,0};
    dependencies.observe(block,nullptr,false);
    tiles[0].flags=wm::kTileHidden;
    CHECK(dependencies.observe(block,tiles.data(),false).tiles.count()==1);
    CHECK(dependencies.observe(block,tiles.data(),true).tiles.count()==1);
    tiles[1].flags=wm::kTileHidden;
    CHECK(dependencies.observe(block,tiles.data(),true).tiles.none());
    CHECK(dependencies.observe(block,tiles.data(),false).tiles.count()==2);
    CHECK(dependencies.observe(block,nullptr,false).tiles.count()==2);
    dependencies.clear();
    CHECK(dependencies.observe(block,tiles.data(),false).tiles.all());
}

TEST_CASE("artwork spill is matched in its actual block, independently of building origin") {
    TerrainVisibilityDependencies dependencies;
    std::array<wm::TileState,wm::kTilesPerBlock> tiles{};
    const wm::BlockPos block{0,0,4};
    dependencies.observe(block,tiles.data(),false);
    tiles[wm::tileIndexInBlock(8,15)].flags=wm::kTileHidden;
    const auto changes=dependencies.observe(block,tiles.data(),false);
    // Building starts at (8,16), but its artwork extends one tile north.
    CHECK(changes.contains(8+0,16-1));
    CHECK_FALSE(changes.contains(8+0,16+0));
    CHECK(dependencies.observe({0,0,5},tiles.data(),false).tiles.all());
    CHECK(dependencies.observe(block,tiles.data(),false).tiles.none());
}
