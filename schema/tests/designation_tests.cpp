#include <doctest.h>
#include "fixture_io.h"
#include "synthetic_builder.h"
#include "terrain_util.h"
#include "validate.h"
using namespace df3d::mirror;

TEST_CASE("v7 exact operation survives equal-flag terrain updates") {
  SyntheticFort fort(16,16,1);
  const auto material=fort.material("GRANITE");
  TileState dig(TileShape::Wall,MaterialKind::Stone,material,0,LiquidKind::None,TileFlags::DigDesignated,DesignationKind::Dig);
  TileState channel(TileShape::Wall,MaterialKind::Stone,material,0,LiquidKind::None,TileFlags::DigDesignated,DesignationKind::Channel);
  CHECK(sizeof(TileState)==8);
  CHECK(!tileEquals(dig,channel));
  fort.setTile(2,3,0,dig);fort.snapshot(10);
  fort.setTile(2,3,0,channel);fort.snapshot(11);
  FixtureStream stream;std::string error;
  REQUIRE(parseFixture(fort.serialize(),stream,error));
  CHECK(!validateStream(stream));
  REQUIRE(stream.snapshots[1]->blocks()->size()==1);
  CHECK(stream.snapshots[0]->blocks()->Get(0)->tiles()->Get(50)->designation()==DesignationKind::Dig);
  CHECK(stream.snapshots[1]->blocks()->Get(0)->tiles()->Get(50)->designation()==DesignationKind::Channel);
}
TEST_CASE("v7 validator rejects unknown operation bytes") {
  SyntheticFort fort(16,16,1);
  fort.setTile(0,0,0,TileState(TileShape::Wall,MaterialKind::Stone,kNoMaterial,0,LiquidKind::None,
      TileFlags::DigDesignated,static_cast<DesignationKind>(255)));
  fort.snapshot(1);FixtureStream stream;std::string error;
  REQUIRE(parseFixture(fort.serialize(),stream,error));
  const auto invalid=validateStream(stream);
  REQUIRE(invalid);CHECK(invalid->find("designation kind")!=std::string::npos);
}

TEST_CASE("additive designation details preserve tile ABI and validate sparse metadata") {
  auto fixture=[](std::vector<DesignationDetail> details) {
    flatbuffers::FlatBufferBuilder fbb;
    std::vector<TileState> tiles(256,emptyTile());
    tiles[50]=TileState(TileShape::Wall,MaterialKind::Stone,kNoMaterial,0,LiquidKind::None,TileFlags::DigDesignated,DesignationKind::Dig);
    const auto block=CreateMapBlock(fbb,0,0,0,fbb.CreateVectorOfStructs(tiles),fbb.CreateVectorOfStructs(details));
    const auto blocks=fbb.CreateVector(std::vector<flatbuffers::Offset<MapBlock>>{block});
    const auto units=fbb.CreateVector(std::vector<flatbuffers::Offset<UnitState>>{});
    const TilePos dims(16,16,1);
    const auto snap=CreateSnapshot(fbb,uint32_t(SchemaVersion::Current),1,1,&dims,units,TerrainScope::Full,blocks);
    fbb.FinishSizePrefixed(snap,SnapshotIdentifier());
    return assembleFixture({std::vector<uint8_t>(fbb.GetBufferPointer(),fbb.GetBufferPointer()+fbb.GetSize())});
  };
  for(const auto& details:std::vector<std::vector<DesignationDetail>>{{},{DesignationDetail(50,1,true)},{DesignationDetail(50,7,false)}}) {
    FixtureStream fs;std::string error;
    REQUIRE_MESSAGE(parseFixture(fixture(details),fs,error),error);
    CHECK_FALSE(validateStream(fs));
    CHECK(sizeof(TileState)==8);
    CHECK(fs.snapshots[0]->blocks()->Get(0)->tiles()->Get(50)->designation()==DesignationKind::Dig);
  }
  for(const auto& details:std::vector<std::vector<DesignationDetail>>{{DesignationDetail(256,1,false)},{DesignationDetail(50,8,false)},{DesignationDetail(50,1,false),DesignationDetail(50,2,false)}}) {
    FixtureStream fs;std::string error;
    REQUIRE_MESSAGE(parseFixture(fixture(details),fs,error),error);
    CHECK(validateStream(fs).has_value());
  }
}

TEST_CASE("sparse map indicators validate known direction and warning bits") {
  auto fixture=[](std::vector<MapIndicator> indicators) {
    flatbuffers::FlatBufferBuilder fbb;
    std::vector<TileState> tiles(256,emptyTile());
    auto block=CreateMapBlock(fbb,0,0,0,fbb.CreateVectorOfStructs(tiles),0,fbb.CreateVectorOfStructs(indicators));
    auto blocks=fbb.CreateVector(std::vector<flatbuffers::Offset<MapBlock>>{block});
    auto units=fbb.CreateVector(std::vector<flatbuffers::Offset<UnitState>>{});
    TilePos dims(16,16,1);
    auto snap=CreateSnapshot(fbb,uint32_t(SchemaVersion::Current),1,1,&dims,units,TerrainScope::Full,blocks);
    fbb.FinishSizePrefixed(snap,SnapshotIdentifier());
    return assembleFixture({std::vector<uint8_t>(fbb.GetBufferPointer(),fbb.GetBufferPointer()+fbb.GetSize())});
  };
  for(auto list:std::vector<std::vector<MapIndicator>>{{},{MapIndicator(50,15,3,3)}}) {
    FixtureStream fs;std::string error; REQUIRE(parseFixture(fixture(list),fs,error)); CHECK_FALSE(validateStream(fs));
  }
  for(auto list:std::vector<std::vector<MapIndicator>>{{MapIndicator(256,0,0,0)},{MapIndicator(0,16,0,0)},
      {MapIndicator(0,0,4,0)},{MapIndicator(0,0,0,4)},{MapIndicator(0,1,0,0),MapIndicator(0,2,0,0)}}) {
    FixtureStream fs;std::string error; REQUIRE(parseFixture(fixture(list),fs,error)); CHECK(validateStream(fs).has_value());
  }
}

#include "track_route.h"
TEST_CASE("track route connects endpoints and can detour beyond selection") {
    using namespace df3d::track;
    const auto ground=[](Point p) { return p.x>=0 && p.y>=0 && p.x<8 && p.y<8; };
    auto line=route(Point{1,3},Point{5,3},ground);
    REQUIRE(line.size()==5);
    CHECK(line.front().mask==4); CHECK(line.back().mask==8);
    CHECK(line[2].mask==12);
    auto blocked=[&](Point p) { return ground(p) && p!=Point{3,3}; };
    auto path=route(Point{1,3},Point{5,3},blocked);
    REQUIRE(path.size()==7);
    bool outside=false;
    for(size_t i=0;i<path.size();++i) {
        CHECK(blocked(path[i].point)); outside|=path[i].point.y!=3;
        if(i) CHECK(distance(path[i-1].point,path[i].point)==1);
    }
    CHECK(outside);
    CHECK(route(Point{1,3},Point{1,3},ground).empty());
    CHECK(route(Point{1,3},Point{5,3},ground,1).empty());
    CHECK(route(Point{1,3},Point{5,3},[](Point){return false;}).empty());
}

TEST_CASE("track traversal metadata rejects duplicate and out-of-block indices") {
  for(auto indices:std::vector<std::vector<uint16_t>>{{},{0,255},{256},{4,4}}) {
    flatbuffers::FlatBufferBuilder fbb;
    std::vector<TileState> tiles(256,emptyTile());
    auto bits=fbb.CreateVector(indices);
    auto block=CreateMapBlock(fbb,0,0,0,fbb.CreateVectorOfStructs(tiles),0,0,bits,bits,bits,bits);
    auto blocks=fbb.CreateVector(std::vector<flatbuffers::Offset<MapBlock>>{block});
    TilePos dims(16,16,1);
    auto snap=CreateSnapshot(fbb,uint32_t(SchemaVersion::Current),1,1,&dims,0,TerrainScope::Full,blocks);
    fbb.FinishSizePrefixed(snap,SnapshotIdentifier());
    FixtureStream fs;std::string error;
    REQUIRE(parseFixture(assembleFixture({std::vector<uint8_t>(fbb.GetBufferPointer(),fbb.GetBufferPointer()+fbb.GetSize())}),fs,error));
    CHECK(validateStream(fs).has_value()==(indices==std::vector<uint16_t>{256} || indices==std::vector<uint16_t>{4,4}));
  }
}
