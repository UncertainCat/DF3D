#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest.h>
#include "../src/sprite_ceiling_cache.h"
using namespace wm;
using df3d_godot::SpriteCeilingCache;
namespace {
struct Terrain {
    WorldModel model;
    std::map<BlockPos,std::array<TileState,256>> blocks;
    Tick tick=0;
    Terrain() {
        for(int z=0;z<4;++z)for(int x=0;x<3;++x)blocks[{x,0,z}]={};
        publish(true);
    }
    void publish(bool full=false) {
        SnapshotData state;state.tick=++tick;state.mapSize={48,16,4};
        state.terrainScope=full?TerrainScope::Full:TerrainScope::Delta;
        for(const auto& [position,tiles]:blocks)state.blocks.push_back({position,tiles.data()});
        model.ingest(state,double(tick));
    }
    TileState& tile(int x,int y,int z) { return blocks[{x/16,y/16,z}][y%16*16+x%16]; }
};
}
TEST_CASE("local source tokens ignore remote tiles material changes and animation polling") {
    Terrain terrain;SpriteCeilingCache cache;
    const SpriteCeilingCache::Bounds a{2,2,1,2,2,3},b{18,2,1,18,2,3};
    const auto first=cache.query(terrain.model,a,3,4);
    const auto remote=cache.query(terrain.model,b,3,4);
    CHECK(first.ceiling==SpriteCeilingCache::noCeiling);
    const auto idle=cache.stats;
    for(int i=0;i<100;++i)CHECK(cache.query(terrain.model,a,3,4).revision==first.revision);
    CHECK(cache.stats.blockChecks==idle.blockChecks);CHECK(cache.stats.tileSamples==idle.tileSamples);
    terrain.tile(34,2,1).shape=TileShape::Floor;terrain.publish();
    CHECK(cache.query(terrain.model,a,3,4).revision==first.revision);
    CHECK(cache.query(terrain.model,b,3,4).revision==remote.revision);
    CHECK(cache.stats.tileSamples==idle.tileSamples);
    terrain.tile(3,2,1).shape=TileShape::Floor;terrain.publish();
    CHECK(cache.query(terrain.model,a,3,4).revision==first.revision);
    const auto sameBlockSamples=cache.stats.tileSamples;
    CHECK(sameBlockSamples==idle.tileSamples+256);
    CHECK(cache.query(terrain.model,b,3,4).revision==remote.revision);
    CHECK(cache.stats.tileSamples==sameBlockSamples);
    terrain.tile(2,2,1).liquidKind=LiquidKind::Water;terrain.tile(2,2,1).liquidLevel=7;terrain.publish();
    CHECK(cache.query(terrain.model,a,3,4).revision==first.revision);
    terrain.tile(2,2,2).shape=TileShape::Floor;terrain.publish();
    const auto roof=cache.query(terrain.model,a,3,4);
    CHECK(roof.revision!=first.revision);CHECK(roof.ceiling==doctest::Approx(1.994));
    CHECK(cache.query(terrain.model,b,3,4).revision==remote.revision);
    terrain.tile(2,2,2).shape=TileShape::Wall;terrain.publish();
    CHECK(cache.query(terrain.model,a,3,4).revision==roof.revision);
}
TEST_CASE("group revision tracks all covered occupancy even with an unchanged lowest plane") {
    Terrain terrain;SpriteCeilingCache cache;
    const SpriteCeilingCache::Bounds group{2,2,1,18,2,3};
    terrain.tile(2,2,1).shape=TileShape::Floor;terrain.publish();
    const auto initial=cache.query(terrain.model,group,3,4);
    terrain.tile(18,2,3).shape=TileShape::Floor;terrain.publish();
    const auto changed=cache.query(terrain.model,group,3,4);
    CHECK(changed.revision!=initial.revision);CHECK(changed.ceiling==initial.ceiling);
    const auto sampled=cache.stats.blockSamples;
    cache.query(terrain.model,{18,2,1,18,2,3},3,4);
    CHECK(cache.stats.blockSamples==sampled);
}
TEST_CASE("hidden missing out of map slice session and eviction stay conservative") {
    Terrain terrain;SpriteCeilingCache cache(2);
    const SpriteCeilingCache::Bounds bounds{2,2,1,2,2,3};
    auto open=cache.query(terrain.model,bounds,3,4);
    terrain.tile(2,2,1).flags=kTileHidden;terrain.publish();
    auto hidden=cache.query(terrain.model,bounds,3,4);
    CHECK(hidden.revision!=open.revision);CHECK(hidden.ceiling==doctest::Approx(.994));
    auto cut=cache.query(terrain.model,bounds,0,1);
    CHECK(cut.ceiling==SpriteCeilingCache::noCeiling);CHECK(cut.revision!=hidden.revision);
    auto outside=cache.query(terrain.model,{-1,2,1,-1,2,3},3,4);
    CHECK(outside.ceiling==doctest::Approx(.994));
    terrain.model.resetSession();
    auto missing=cache.query(terrain.model,bounds,3,4);
    CHECK(missing.ceiling==doctest::Approx(.994));CHECK(missing.revision!=hidden.revision);
    cache.query(terrain.model,{3,2,1,3,2,3},3,4);
    cache.query(terrain.model,{4,2,1,4,2,3},3,4);
    CHECK(cache.size()==2);CHECK(cache.stats.evictions>0);
    CHECK(cache.query(terrain.model,bounds,3,4).revision!=missing.revision);
}
