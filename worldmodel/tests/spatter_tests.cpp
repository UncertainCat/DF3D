#include <doctest.h>
#include "wm/world_model.h"
#include "fixture_io.h"
#include "validate.h"
using namespace wm;
namespace m = df3d::mirror;

TEST_CASE("spatter invalidations remain keyed while presentation is stalled") {
  WorldModel model; SnapshotData s; s.mapSize={16,16,1};
  s.materials={"WATER"}; s.spatterScope=ChangeScope::Delta;
  for (uint64_t tick=1; tick<=10000; ++tick) {
    s.tick=tick;
    s.spatters={{{0,0,0},{{0,uint8_t(1+tick%254),0,MatterState::Liquid}}}};
    model.ingest(s,double(tick));
  }
  CHECK(model.drainSpatterEvents()==std::vector<BlockPos>{{0,0,0}});
  CHECK(model.drainSpatterEvents().empty());
}

TEST_CASE("ground contamination remaps materials replaces blocks and preserves immutable copies") {
  WorldModel model; SnapshotData s; s.mapSize={32,16,2}; s.tick=10;
  s.materials={"WATER","CREATURE:DWARF:BLOOD"}; s.spatterScope=ChangeScope::Full;
  s.spatters={{{0,0,0},{{3,20,1,MatterState::Liquid},{2,5,0,MatterState::Liquid}}},
              {{1,0,0},{{0,10,1,MatterState::Liquid}}}};
  model.ingest(s,0); REQUIRE(model.spattersAt({0,0,0}).size()==2);
  CHECK(model.spattersAt({0,0,0})[0].tile==2);
  CHECK(model.materialName(model.spattersAt({0,0,0})[1].material)=="CREATURE:DWARF:BLOOD");
  CHECK(model.drainSpatterEvents().size()==2); CHECK(model.drainTerrainEvents().empty());
  const auto revision=model.spatterVersion(); const auto terrain=model.terrainVersion();
  model.ingest(s,0.1); CHECK(model.spatterVersion()==revision); CHECK(model.drainSpatterEvents().empty());
  auto old=model;
  s.tick=11;s.spatterScope=ChangeScope::Delta;s.materials={"CREATURE:DWARF:BLOOD"};
  s.spatters={{{0,0,0},{{3,80,0,MatterState::Liquid}}}};model.ingest(s,0.2);
  CHECK(model.spattersAt({0,0,0})[0].amount==80);CHECK(old.spattersAt({0,0,0}).size()==2);
  CHECK(model.spattersAt({1,0,0}).size()==1); CHECK(model.terrainVersion()==terrain);
  auto events=model.drainAllEvents(); REQUIRE(events.spatters.size()==1);
  model.restoreEvents(events); CHECK(model.drainSpatterEvents().size()==1);
  s.tick=12;s.spatters={{{0,0,0},{}}};model.ingest(s,0.3);
  CHECK(model.spattersAt({0,0,0}).empty());CHECK(model.drainSpatterEvents().size()==1);
  s.tick=13;s.spatterScope=ChangeScope::None;s.spatters.clear();model.ingest(s,0.4);
  CHECK(model.spattersAt({1,0,0}).size()==1);
  s.tick=14;s.spatterScope=ChangeScope::Full;model.ingest(s,0.5);
  CHECK(model.spattersAt({1,0,0}).empty());CHECK(model.drainSpatterEvents().size()==1);
  model.resetSession(); CHECK(model.spattersAt({0,0,0}).empty());
}

TEST_CASE("ground contamination schema validates and survives fixture transport") {
  const auto make=[](uint8_t amount,uint16_t material,m::MatterState state,int bx,int local,
                     bool duplicate=false,m::ChangeScope scope=m::ChangeScope::Full) {
    flatbuffers::FlatBufferBuilder f;
    std::vector<m::GroundSpatter> es{{uint8_t(local),amount,material,state}};
    if(duplicate)es.push_back(es.front());
    const auto entries=f.CreateVectorOfStructs(es);
    const auto block=m::CreateSpatterBlock(f,bx,0,0,entries);
    const auto blocks=f.CreateVector(std::vector{block});
    const auto materials=f.CreateVector(std::vector{f.CreateString("CREATURE:DWARF:BLOOD")});
    const m::TilePos size(17,16,1);m::SnapshotBuilder b(f);
    b.add_schema_version(uint32_t(m::SchemaVersion::Current));b.add_tick(10);b.add_map_size(&size);
    b.add_materials(materials);b.add_spatter_scope(scope);b.add_spatters(blocks);
    m::FinishSizePrefixedSnapshotBuffer(f,b.Finish());
    return std::vector<uint8_t>(f.GetBufferPointer(),f.GetBufferPointer()+f.GetSize());
  };
  const auto good=make(100,0,m::MatterState::Liquid,0,7);
  CHECK_FALSE(m::validateSnapshot(*m::GetSizePrefixedSnapshot(good.data())).has_value());
  WorldModel model;std::string error;
  REQUIRE_MESSAGE(loadFixtureBytes(model,m::assembleFixture({good}),error),error);
  REQUIRE(model.spattersAt({0,0,0}).size()==1);
  CHECK(model.spattersAt({0,0,0})[0].amount==100);
  for(const auto& bad: {make(0,0,m::MatterState::Liquid,0,0),make(1,1,m::MatterState::Liquid,0,0),
      make(1,0,static_cast<m::MatterState>(9),0,0),make(1,0,m::MatterState::Liquid,2,0),
      make(1,0,m::MatterState::Liquid,1,1),make(1,0,m::MatterState::Liquid,0,0,true),
      make(1,0,m::MatterState::Liquid,0,0,false,m::ChangeScope::None)})
    CHECK(m::validateSnapshot(*m::GetSizePrefixedSnapshot(bad.data())).has_value());
}
