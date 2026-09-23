#include <doctest.h>
#include "wm/world_model.h"
#include "fixture_io.h"
#include "validate.h"
using namespace wm;
namespace m = df3d::mirror;
TEST_CASE("combat observations deduplicate pause expire bound and reset") {
 WorldModel w; SnapshotData s; s.mapSize={16,16,4};s.tick=100;
 s.combatEvents={{1,100,CombatEventKind::Wound,1,2,0,{1,1,1}},{2,100,CombatEventKind::Death,-1,2,-1,{1,1,1}}};
 w.ingest(s,0);w.ingest(s,1);CHECK(w.combatEvents().size()==2);
 CHECK(w.combatEvents().back().victimId==2); // departed victims are valid
 s.tick=701;s.combatEvents.clear();w.ingest(s,2);CHECK(w.combatEvents().empty());
 s.tick=702;s.combatEvents={{2,100,CombatEventKind::Death,-1,2,-1,{1,1,1}}};w.ingest(s,3);CHECK(w.combatEvents().empty());
 for (uint64_t id=3;id<400;++id) {s.tick=703;s.combatEvents={{id,703,CombatEventKind::Wound,1,2,int(id),{1,1,1}}};w.ingest(s,4);}
 CHECK(w.combatEvents().size()==256);w.resetSession();CHECK(w.combatEvents().empty());
 s.tick=1;s.combatEvents={{1,1,CombatEventKind::Death,-1,2,-1,{1,1,1}}};w.ingest(s,0);CHECK(w.combatEvents().front().id==1);
}
TEST_CASE("combat schema optional roundtrip validates historic participants") {
 auto make=[](uint64_t id, uint64_t tick, int victim, m::CombatEventKind kind) {
  flatbuffers::FlatBufferBuilder f;m::TilePos dims(16,16,4),pos(1,1,1);
  auto event=m::CreateCombatEvent(f,id,tick,kind,1,victim,0,&pos);
  auto events=f.CreateVector(std::vector{event});m::SnapshotBuilder b(f);
  b.add_schema_version(static_cast<uint32_t>(m::SchemaVersion::Current));b.add_tick(100);b.add_map_size(&dims);b.add_combat_events(events);
  m::FinishSizePrefixedSnapshotBuffer(f,b.Finish());return std::vector<uint8_t>(f.GetBufferPointer(),f.GetBufferPointer()+f.GetSize());
 };
 auto bytes=make(1,99,2,m::CombatEventKind::Wound);CHECK_FALSE(m::validateSnapshot(*m::GetSizePrefixedSnapshot(bytes.data())).has_value());
 WorldModel model;std::string error;REQUIRE_MESSAGE(loadFixtureBytes(model,m::assembleFixture({bytes}),error),error);
 REQUIRE(model.combatEvents().size()==1);CHECK(model.combatEvents()[0].tick==99);CHECK(model.combatEvents()[0].woundId==0);
 for(auto bad : {make(0,99,2,m::CombatEventKind::Wound),make(1,101,2,m::CombatEventKind::Wound),make(1,99,-1,m::CombatEventKind::Wound),make(1,99,2,static_cast<m::CombatEventKind>(9))})
  CHECK(m::validateSnapshot(*m::GetSizePrefixedSnapshot(bad.data())).has_value());
}
