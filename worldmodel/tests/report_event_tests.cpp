#include <doctest.h>
#include "wm/world_model.h"
#include "fixture_io.h"
#include "validate.h"
using namespace wm;
namespace m=df3d::mirror;
namespace {
ReportEvent report(uint64_t id,Tick tick=100) {
  ReportEvent e;e.id=id;e.tick=tick;e.reportId=int32_t(id+40);e.type="COMBAT_PARRY";return e;
}
std::vector<uint8_t> bytes(uint64_t id,Tick tick,std::string type,int x=-1,int sourceId=50) {
  flatbuffers::FlatBufferBuilder f;m::TilePos size(16,16,4),pos(x,2,1);
  auto token=f.CreateString(type);
  auto e=m::CreateReportEvent(f,id,tick,sourceId,token,x<0?nullptr:&pos,nullptr,3,-1);
  auto events=f.CreateVector(std::vector{e});m::SnapshotBuilder b(f);
  b.add_schema_version(static_cast<uint32_t>(m::SchemaVersion::Current));b.add_tick(100);b.add_map_size(&size);
  b.add_report_events(events);b.add_report_events_dropped(7);
  m::FinishSizePrefixedSnapshotBuffer(f,b.Finish());return {f.GetBufferPointer(),f.GetBufferPointer()+f.GetSize()};
}
}
TEST_CASE("report journal owns tokens deduplicates expires and rewinds with the session") {
  WorldModel w;SnapshotData s;s.mapSize={16,16,4};s.tick=100;s.reportEvents={report(1)};s.reportEventsDropped=5;
  w.ingest(s,0);w.ingest(s,1);CHECK(w.reportEvents().size()==1);CHECK(w.reportEventsDropped()==5);
  s.reportEvents[0].type="overwritten";CHECK(w.reportEvents()[0].type=="COMBAT_PARRY");
  s.tick=701;s.reportEvents.clear();w.ingest(s,2);CHECK(w.reportEvents().empty());
  s.reportEvents={report(1)};w.ingest(s,3);CHECK(w.reportEvents().empty());
  for(uint64_t id=2;id<=600;++id) {s.reportEvents={report(id,701)};w.ingest(s,4);}
  CHECK(w.reportEvents().size()==512);
  s.tick=10;s.reportEvents={report(1,10)};s.reportEventsDropped=0;w.ingest(s,5);
  REQUIRE(w.reportEvents().size()==1);CHECK(w.reportEvents()[0].id==1);CHECK(w.reportEventsDropped()==0);
  w.resetSession();CHECK(w.reportEvents().empty());
}
TEST_CASE("report schema roundtrip preserves neutral types optional locations and counter") {
  for(int x:{-1,3}) {
    auto data=bytes(1,99,"COMBAT_PARRY",x);
    CHECK_FALSE(m::validateSnapshot(*m::GetSizePrefixedSnapshot(data.data())).has_value());
    WorldModel w;std::string error;REQUIRE_MESSAGE(loadFixtureBytes(w,m::assembleFixture({data}),error),error);
    REQUIRE(w.reportEvents().size()==1);const auto& e=w.reportEvents().front();
    CHECK(e.type=="COMBAT_PARRY");CHECK(e.reportId==50);CHECK(e.tick==99);CHECK(e.repeatCount==3);
    CHECK(e.hasPosition==(x>=0));CHECK_FALSE(e.hasSecondary);CHECK(w.reportEventsDropped()==7);
    if(x>=0) CHECK(e.pos.x==x);else CHECK((e.pos==TilePos{-1,-1,-1}));
  }
  for(auto bad:{bytes(0,99,"COMBAT_BLOCK"),bytes(1,101,"COMBAT_BLOCK"),bytes(1,99,""),
      bytes(1,99,"COMBAT BLOCK"),bytes(1,99,"COMBAT_BLOCK",16),bytes(1,99,"COMBAT_BLOCK",0,-1)})
    CHECK(m::validateSnapshot(*m::GetSizePrefixedSnapshot(bad.data())).has_value());
}
TEST_CASE("event item metadata remains optional qualified and owned after decoding") {
  auto make=[](int action,int item,std::string material,bool projectile) {
    flatbuffers::FlatBufferBuilder f;m::TilePos size(16,16,4),pos(2,2,1);
    auto type=f.CreateString("WEAPON"),subtype=f.CreateString("ITEM_WEAPON_AXE_BATTLE"),mat=f.CreateString(material);
    auto weapon=m::CreateEventItem(f,item,type,subtype,mat);
    auto event=m::CreateCombatEvent(f,1,100,m::CombatEventKind::Wound,1,2,3,&pos,50,action,weapon);
    auto events=f.CreateVector(std::vector{event});
    auto p=m::CreateProjectileSample(f,1,7,100,item,1,&pos,&pos,&pos,&pos,true,true,weapon,weapon);
    auto projectiles=f.CreateVector(std::vector{p});
    m::SnapshotBuilder b(f);b.add_schema_version(static_cast<uint32_t>(m::SchemaVersion::Current));
    b.add_tick(100);b.add_map_size(&size);
    if(projectile)b.add_projectile_samples(projectiles);else b.add_combat_events(events);
    m::FinishSizePrefixedSnapshotBuffer(f,b.Finish());return std::vector<uint8_t>(f.GetBufferPointer(),f.GetBufferPointer()+f.GetSize());
  };
  for(bool projectile:{false,true}) {
    auto data=make(4,8,"INORGANIC:STEEL",projectile);
    CHECK_FALSE(m::validateSnapshot(*m::GetSizePrefixedSnapshot(data.data())).has_value());
    WorldModel w;std::string error;REQUIRE_MESSAGE(loadFixtureBytes(w,m::assembleFixture({data}),error),error);
    data.clear();
    const auto& weapon=projectile?w.projectileSamples().front().launcher:w.combatEvents().front().weapon;
    CHECK(weapon.id==8);CHECK(weapon.material=="INORGANIC:STEEL");CHECK(weapon.subtypeRaw=="ITEM_WEAPON_AXE_BATTLE");
    if(!projectile) {CHECK(w.combatEvents().front().sourceActionId==4);CHECK(w.combatEvents().front().reportId==50);}
  }
  for(auto bad:{make(-1,8,"INORGANIC:STEEL",false),make(4,-2,"INORGANIC:STEEL",false),make(4,8,"bad\nmaterial",true)})
    CHECK(m::validateSnapshot(*m::GetSizePrefixedSnapshot(bad.data())).has_value());
}
