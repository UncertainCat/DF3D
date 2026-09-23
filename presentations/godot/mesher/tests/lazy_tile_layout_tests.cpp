#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest.h>
#include "df3d_mesher/lazy_tile_layout.h"
#include "df3d_mesher/depth_scene.h" // Retained full-scene oracle, test-only consumer.
#include <limits>

using namespace df3d::mesher;
namespace {
uint64_t fragment(int x,int y) { return (uint64_t(uint32_t(x))<<32)|uint32_t(y); }
DepthPiece piece(int category,uint64_t entity,int x,int y,int z=0,uint64_t part=0) {
    DepthPiece p;
    p.id={category,entity,part};p.footprint={x+.5f,y+.5f,.5f,.5f,z,category};
    return p;
}
void same(const DepthInterval& actual,const DepthInterval& expected) {
    CHECK(actual.bottom==expected.bottom);CHECK(actual.thickness==expected.thickness);
}
}

TEST_CASE("lazy per tile allocation exactly matches full scene decals items units and foreground") {
    for (bool reveal : {false,true}) {
        wm::WorldModel model;
        wm::SnapshotData snap;
        snap.tick=100;snap.mapSize={16,16,2};snap.terrainScope=wm::TerrainScope::Full;
        snap.tileStorage.resize(512);
        for(auto& tile:snap.tileStorage)tile.shape=wm::TileShape::Floor;
        snap.tileStorage[wm::tileIndexInBlock(3,2)].flags=wm::kTileHidden;
        snap.blocks={{{0,0,0},snap.tileStorage.data()},{{0,0,1},snap.tileStorage.data()+256}};
        snap.buildingScope=wm::ChangeScope::Full;
        for(auto [id,kind]:std::vector<std::pair<int,wm::BuildingKind>>{
            {10,wm::BuildingKind::Stockpile},{11,wm::BuildingKind::Civzone},{20,wm::BuildingKind::Workshop}}) {
            wm::BuildingObservation b;b.id=id;b.kind=kind;b.x1=b.x2=b.y1=b.y2=2;b.z=0;
            snap.buildings.push_back(b);
        }
        snap.itemScope=wm::ChangeScope::Full;
        const wm::ItemKind kinds[]={wm::ItemKind::Chair,wm::ItemKind::Barrel,wm::ItemKind::Wood,wm::ItemKind::Tool};
        for(int i=99;i>=0;--i) {
            wm::ItemObservation item;item.id=100+i;item.kind=kinds[i%4];item.pos={2+i%2,2,0};
            item.stack=i%3?200:1;item.subtype=i%7;item.subtypeRaw=i%3==0?"":i%3==1?"B":"A";
            snap.items.push_back(item);
        }
        snap.units={{8,{2,2,0},wm::JobKind::Idle,"DWARF"},{2,{2,2,0},wm::JobKind::Idle,"DWARF"},
            {11,{2,2,1},wm::JobKind::Idle,"DWARF"}};
        model.ingest(snap,0);
        DepthSceneSources source;source.generation=model.sessionGeneration();source.top=1;source.window=2;source.reveal=reveal;
        for(auto id:{10,11,20}) source.buildings[id]={model.building(id)->version,{{0,0}}, {}};
        source.buildings[20].cells={{0,-1},{0,0},{1,0}};
        source.buildings[20].foreground=source.buildings[20].cells;
        const auto expected=prepareDepthScene(model,source);REQUIRE(expected.valid);
        LazyTileLayoutCache cache;
        std::map<DepthEntityKey,std::vector<DepthPiece>> records;
        model.forEachBuilding([&](const wm::Building& b){
            for(const auto& [lx,ly]:source.buildings.at(b.id).cells) {
                const int x=b.x1+lx,y=b.y1+ly;
                if(!b.occupies(x,y) || (!reveal && (model.tileAt({x,y,b.z})->flags&wm::kTileHidden)))continue;
                auto p=piece(isFurniturePiece(b.kind)?1:0,b.id,x,y,b.z,fragment(x,y));
                records[{DepthEntityKind::Building,b.id}].push_back(p);
                if(b.id==20) {
                    auto foreground=p;foreground.id.category=4;foreground.parent=p.id;
                    records[{DepthEntityKind::Building,b.id}].push_back(foreground);
                }
            }
        });
        model.forEachItem([&](const wm::MapItem& item){
            if(!reveal && (model.tileAt(item.pos)->flags&wm::kTileHidden))return;
            for(uint64_t quantity=0;quantity<(item.stack>1?2u:1u);++quantity) {
                auto p=piece(2,item.id,item.pos.x,item.pos.y,item.pos.z,quantity);
                p.order={itemStackRank(item.kind),int(item.kind),item.subtypeRaw,item.subtype};
                records[{DepthEntityKind::Item,item.id}].push_back(p);
            }
        });
        for(auto id:model.unitIds()) {
            const auto p=model.evaluate(id,double(model.latestTick())).pos;
            records[{DepthEntityKind::Unit,id}].push_back(piece(3,id,int(p.x),int(p.y),int(p.z)));
        }
        // Reverse insertion/order deliberately: allocator owns stable ordering.
        for(auto it=records.rbegin();it!=records.rend();++it) {
            auto values=it->second;std::reverse(values.begin(),values.end());cache.replace(it->first,std::move(values));
        }
        std::map<DepthPieceId,DepthInterval> oracle;
        for(const auto& [key,interval]:expected.buildings) {
            const auto [id,x,y]=key;
            oracle[{isFurniturePiece(model.building(id)->kind)?1:0,id,fragment(x,y)}]=interval;
        }
        for(const auto& [key,interval]:expected.foreground) {
            const auto [id,x,y]=key;oracle[{4,id,fragment(x,y)}]=interval;
        }
        std::map<wm::ItemId,uint64_t> quantities;
        for(size_t i=0;i<expected.items.size();++i)oracle[{2,expected.items[i],quantities[expected.items[i]]++}]=expected.itemDepth[i];
        for(size_t i=0;i<expected.units.size();++i)oracle[{3,expected.units[i],0}]=expected.unitDepth[i];
        size_t compared=0;
        for(const auto& tile:cache.occupiedTiles({0,0,0},{1,15,15})) for(const auto& actual:cache.query(tile)) {
            REQUIRE(oracle.count(actual.id)==1);same(actual.interval,oracle.at(actual.id));++compared;
            if(actual.id.category==4 && actual.id.fragment==fragment(2,1))CHECK(actual.collapsed);
        }
        CHECK(compared==oracle.size());
    }
}

TEST_CASE("lazy replacements invalidate only union old new tiles and queries never scan offscreen owners") {
    LazyTileLayoutCache cache(2);
    auto base=piece(1,7,0,0);auto front=piece(4,7,0,0);front.parent=base.id;
    cache.replace({DepthEntityKind::Building,7},{front,base});
    for(uint64_t i=0;i<4096;++i)cache.replace({DepthEntityKind::Item,100+i},{piece(2,100+i,1000+int(i),1000)});
    auto before=cache.stats();
    auto local=cache.occupiedTiles({0,0,0},{0,15,15});
    REQUIRE(local.size()==1);CHECK(local[0]==DepthTile{0,0,0});
    CHECK(cache.stats().candidateBlockChecks==before.candidateBlockChecks+1);
    CHECK(cache.stats().candidateTileChecks==before.candidateTileChecks+1);
    const auto alone=cache.query({0,0,0});REQUIRE(alone.size()==2);CHECK(alone[1].collapsed);
    CHECK(cache.stats().contributorsVisited==before.contributorsVisited+2);
    cache.consumeDirtyTiles();
    before=cache.stats();cache.query({0,0,0});
    CHECK(cache.stats().layoutsBuilt==before.layoutsBuilt);CHECK(cache.stats().cacheHits==before.cacheHits+1);
    CHECK_FALSE(cache.replace({DepthEntityKind::Building,7},{base,front}));
    CHECK(cache.consumeDirtyTiles().empty());
    auto unit=piece(3,7,0,0);cache.replace({DepthEntityKind::Unit,7},{unit});
    CHECK(cache.consumeDirtyTiles()==std::vector<DepthTile>{{0,0,0}});
    CHECK(cache.needsLayout({0,0,0})); // Draining notices did not mark the layout clean.
    const auto contested=cache.query({0,0,0});REQUIRE(contested.size()==3);CHECK(contested.back().collapsed);
    same(contested.back().interval,alone[0].interval);
    CHECK(contested[1].interval.bottom>contested.back().interval.bottom+contested.back().interval.thickness);
    unit.footprint.x=16.5f;cache.replace({DepthEntityKind::Unit,7},{unit});
    CHECK(cache.consumeDirtyTiles()==std::vector<DepthTile>{{0,0,0},{0,16,0}});
    CHECK(cache.query({0,0,0}).back().collapsed);
    CHECK(cache.query({0,16,0}).size()==1);
    CHECK(cache.remove({DepthEntityKind::Unit,7}));CHECK(cache.query({0,16,0}).empty());
    CHECK(cache.occupiedTiles({0,16,0},{0,31,15}).empty());
    // Reusing an ID synchronously cannot retain an old incarnation's layout.
    const auto revision=cache.layoutRevision({0,0,0});
    cache.remove({DepthEntityKind::Building,7});cache.replace({DepthEntityKind::Building,7},{base,front});
    CHECK(cache.needsLayout({0,0,0}));cache.query({0,0,0});CHECK(cache.layoutRevision({0,0,0})>revision);
}

TEST_CASE("computed layout eviction retains occupancy negative cells and epoch safety") {
    LazyTileLayoutCache cache(1);
    cache.replace({DepthEntityKind::Item,1},{piece(2,1,-17,-1)});
    cache.replace({DepthEntityKind::Item,2},{piece(2,2,16,16)});
    CHECK(cache.occupiedTiles({0,-17,-1},{0,-17,-1})==std::vector<DepthTile>{{0,-17,-1}});
    cache.query({0,-17,-1});const auto old=cache.layoutRevision({0,-17,-1});
    cache.query({0,16,16});CHECK(cache.stats().residentLayouts==1);CHECK(cache.stats().evictions==1);
    CHECK(cache.needsLayout({0,-17,-1}));CHECK(cache.query({0,-17,-1}).size()==1);
    CHECK(cache.layoutRevision({0,-17,-1})>old);CHECK(cache.stats().owners==2);
    cache.clear(99);CHECK(cache.epoch()==99);CHECK(cache.stats().owners==0);CHECK(cache.stats().occupiedTiles==0);
    CHECK(cache.consumeDirtyTiles().empty());CHECK(cache.query({0,-17,-1}).empty());
    cache.replace({DepthEntityKind::Item,1},{piece(2,1,0,0)});
    CHECK(cache.query({0,0,0}).size()==1);CHECK(cache.layoutRevision({0,0,0})>old);
    CHECK(cache.occupiedTiles({1,0,0},{0,5,5}).empty());
}

TEST_CASE("invalid replacements are rejected without partial removal") {
    LazyTileLayoutCache cache;
    const DepthEntityKey owner{DepthEntityKind::Item,1};auto valid=piece(2,1,0,0);
    cache.replace(owner,{valid});cache.query({0,0,0});cache.consumeDirtyTiles();
    auto bad=valid;bad.footprint.x=std::numeric_limits<float>::quiet_NaN();
    CHECK_THROWS_AS(cache.replace(owner,{bad}),std::invalid_argument);
    CHECK_THROWS_AS(cache.replace(owner,{valid,valid}),std::invalid_argument);
    bad=valid;bad.id.entity=2;CHECK_THROWS_AS(cache.replace(owner,{bad}),std::invalid_argument);
    CHECK_THROWS_AS(cache.replace({static_cast<DepthEntityKind>(99),1},{valid}),std::invalid_argument);
    CHECK_FALSE(cache.needsLayout({0,0,0}));CHECK(cache.query({0,0,0}).size()==1);
    CHECK(cache.consumeDirtyTiles().empty());
}

TEST_CASE("creature movement preserves object ordering without visiting object contributors") {
    LazyTileLayoutCache cache;
    for(int i=0;i<2000;++i)cache.replace({DepthEntityKind::Item,uint64_t(i)},{piece(2,i,4,4)});
    const auto objects=cache.queryCategory({0,4,4},2);
    REQUIRE(objects.size()==2000);
    const auto before=cache.stats();
    cache.replace({DepthEntityKind::Unit,9000},{piece(3,9000,4,4)});
    CHECK((cache.dirtyCategories({0,4,4})&4)==0);
    REQUIRE(cache.queryCategory({0,4,4},3).size()==1);
    CHECK(cache.categoryCount({0,4,4},2)==2000);
    CHECK(cache.categoryCount({0,4,4},3)==1);
    CHECK(cache.stats().contributorsVisited-before.contributorsVisited==1);
    const auto& unchanged=cache.queryCategory({0,4,4},2);
    for(size_t i=0;i<objects.size();++i) {
        CHECK(unchanged[i].id==objects[i].id);
        same(unchanged[i].interval,objects[i].interval);
    }
    cache.remove({DepthEntityKind::Unit,9000});
    CHECK((cache.dirtyCategories({0,4,4})&4)==0);
    CHECK(cache.categoryCount({0,4,4},3)==0);
    CHECK(cache.queryCategory({0,4,4},3).empty());
    CHECK(cache.stats().contributorsVisited-before.contributorsVisited==1);
}

TEST_CASE("shared category mapping matches physical pile ceiling and hierarchy") {
    for(int objects:{0,1,2,7,2000})for(int creatures:{0,1,4,19}) {
        if(objects+creatures==0)continue;
        const float support=kBuildingBottom+kBuildingThickness+kBuildingSpillBias;
        std::vector<DepthFootprint> footprints(objects+creatures);
        const auto expected=depthLayout(footprints,kPieceCeiling,std::vector<float>(footprints.size(),support));
        float previous=support;
        for(int i=0;i<objects+creatures;++i) {
            const auto actual=sharedStackInterval(support,objects,creatures,i<objects?2:3,i<objects?i:i-objects);
            same(actual,expected[i]);
            CHECK(actual.bottom>=previous);
            CHECK(actual.bottom+actual.thickness<kPieceCeiling);
            previous=actual.bottom+actual.thickness;
        }
    }
}

TEST_CASE("eviction does not reinterpret a creature arrival as object source changes") {
    LazyTileLayoutCache cache(1);
    cache.replace({DepthEntityKind::Item,1},{piece(2,1,4,4)});
    cache.queryCategory({0,4,4},2);
    cache.replace({DepthEntityKind::Unit,2},{piece(3,2,8,8)});
    cache.queryCategory({0,8,8},3); // Evicts the computed object layout only.
    const auto before=cache.stats();
    cache.replace({DepthEntityKind::Unit,2},{piece(3,2,4,4)});
    CHECK((cache.dirtyCategories({0,4,4})&4)==0);
    cache.queryCategory({0,4,4},3);
    CHECK(cache.stats().contributorsVisited-before.contributorsVisited==1);
}
