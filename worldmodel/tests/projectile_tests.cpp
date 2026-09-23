#include <doctest.h>
#include "wm/world_model.h"
#include "fixture_io.h"
#include "validate.h"
using namespace wm;
namespace m=df3d::mirror;
namespace {
ProjectileSample sample(uint64_t sequence,Tick tick,int x,bool active=true,bool first=false) {
 return {sequence,7,tick,55,11,{x,2,1},{x-1,2,1},{1,2,1},{12,2,1},active,first};
}
}
TEST_CASE("projectiles use observed motion delayed lifetime and pause-safe non-destructive queries") {
 WorldModel w;SnapshotData s;s.mapSize={16,16,4};s.tick=103;
 s.projectileSamples={sample(1,100,2,true,true),sample(2,101,4),sample(3,102,6),sample(4,103,6,false)};
 w.ingest(s,0);w.ingest(s,1);
 REQUIRE(w.projectileSamples().size()==4);CHECK(w.projectileSamples()[0].firstObserved);
 CHECK(w.projectilesAt(99.9).empty());
 auto flight=w.projectilesAt(100.5);REQUIRE(flight.size()==1);
 CHECK(flight[0].id==7);CHECK(flight[0].firerId==11);CHECK(flight[0].itemId==55);
 CHECK(flight[0].pos.x==doctest::Approx(3));CHECK(flight[0].direction.x==doctest::Approx(1));
 CHECK(w.projectilesAt(100.5)[0].pos.x==flight[0].pos.x);
 CHECK(w.projectilesAt(102.9).size()==1);CHECK(w.projectilesAt(103).empty());
 s.tick=225;s.projectileSamples.clear();w.ingest(s,2);CHECK(w.projectileSamples().empty());
 w.resetSession();s.tick=100;s.projectileSamples={sample(1,100,2,true,true)};w.ingest(s,0);
 REQUIRE(w.projectileSamples().size()==1);CHECK(w.projectileSamples()[0].sequence==1);
 CHECK(w.projectilesAt(102.1).empty()); // missing final observation never flies forever
 w.resetSession();CHECK(w.projectilesAt(100).empty());
}
TEST_CASE("projectile retention remains bounded and tick rewind starts a new epoch") {
 WorldModel w;SnapshotData s;s.mapSize={16,16,4};s.tick=100;
 for(uint64_t seq=1;seq<=600;++seq) {s.projectileSamples={sample(seq,100,2)};w.ingest(s,0);}
 CHECK(w.projectileSamples().size()==512);
 s.tick=10;s.projectileSamples={sample(1,10,3,true,true)};w.ingest(s,1);
 REQUIRE(w.projectileSamples().size()==1);CHECK(w.projectileSamples()[0].sequence==1);
}
TEST_CASE("projectile schema roundtrip optional field and invalid sample checks") {
 auto make=[](uint64_t sequence,Tick tick,int x) {
  flatbuffers::FlatBufferBuilder f;m::TilePos dims(16,16,4),pos(x,2,1),origin(1,2,1),target(12,2,1);
  auto p=m::CreateProjectileSample(f,sequence,7,tick,55,11,&pos,&origin,&origin,&target,true,true);
  auto samples=f.CreateVector(std::vector{p});m::SnapshotBuilder b(f);
  b.add_schema_version(static_cast<uint32_t>(m::SchemaVersion::Current));b.add_tick(100);b.add_map_size(&dims);b.add_projectile_samples(samples);
  m::FinishSizePrefixedSnapshotBuffer(f,b.Finish());return std::vector<uint8_t>(f.GetBufferPointer(),f.GetBufferPointer()+f.GetSize());
 };
 auto bytes=make(1,100,2);CHECK_FALSE(m::validateSnapshot(*m::GetSizePrefixedSnapshot(bytes.data())).has_value());
 WorldModel w;std::string error;REQUIRE_MESSAGE(loadFixtureBytes(w,m::assembleFixture({bytes}),error),error);
 REQUIRE(w.projectileSamples().size()==1);CHECK(w.projectilesAt(100)[0].itemId==55);
 for(auto bad : {make(0,100,2),make(1,101,2),make(1,100,16)})
  CHECK(m::validateSnapshot(*m::GetSizePrefixedSnapshot(bad.data())).has_value());
}
