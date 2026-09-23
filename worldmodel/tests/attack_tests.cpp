#include <doctest.h>
#include "wm/world_model.h"
#include "fixture_io.h"
#include "validate.h"
using namespace wm;
namespace m = df3d::mirror;
namespace {
std::vector<uint8_t> attackSnapshot(Tick tick, int action, int target = 2, int timer = 8, int x = 1) {
  flatbuffers::FlatBufferBuilder f;
  auto species = f.CreateString("DWARF");
  m::TilePos pos(x,1,1), targetPos(3,1,1), dims(16,16,4);
  flatbuffers::Offset<m::UnitAttack> attack;
  if (action != -1) attack = m::CreateUnitAttack(f, action, target, timer, 5);
  auto a = m::CreateUnitState(f,1,&pos,species,m::JobKind::Idle,attack);
  auto b = m::CreateUnitState(f,2,&targetPos,species);
  auto units = f.CreateVector(std::vector{a,b});
  m::SnapshotBuilder s(f);
  s.add_schema_version(static_cast<uint32_t>(m::SchemaVersion::Current));
  s.add_tick(tick); s.add_map_size(&dims); s.add_units(units);
  m::FinishSizePrefixedSnapshotBuffer(f,s.Finish());
  return {f.GetBufferPointer(),f.GetBufferPointer()+f.GetSize()};
}
}
TEST_CASE("attack observations survive semantic pipeline at delayed tick without changing movement") {
  WorldModel model;
  std::string error;
  REQUIRE_MESSAGE(loadFixtureBytes(model, m::assembleFixture({
    attackSnapshot(100,-1), attackSnapshot(102,17), attackSnapshot(103,17,2,7),
    attackSnapshot(104,17,2,6), attackSnapshot(106,-1), attackSnapshot(110,-1,2,8,2)}), error), error);
  CHECK(model.evaluate(1,101.9).attack.actionId == -1);
  auto attack = model.evaluate(1,103).attack;
  CHECK(attack.actionId == 17); CHECK(attack.targetId == 2);
  CHECK(attack.observedAt == 102); CHECK(attack.timer1 == 8);
  CHECK(model.evaluate(1,105.9).attack.actionId == 17);
  CHECK(model.evaluate(1,106).attack.actionId == -1);
  CHECK(model.evaluate(1,105).pos.x == doctest::Approx(1.5));
  CHECK(model.unitsInBox({0,0,0},{15,15,3},103).front().second.attack.actionId == 17);
  WorldModel old; REQUIRE(loadFixtureBytes(old,m::assembleFixture({attackSnapshot(1,-1)}),error));
  CHECK(old.evaluate(1,1).attack.actionId == -1);
}
TEST_CASE("attack validation rejects absent self and negative target or invalid identity") {
  for (auto [action,target] : std::vector<std::pair<int,int>>{{17,99},{17,1},{17,-2},{-2,2}}) {
    auto bytes = attackSnapshot(1,action,target);
    CHECK(m::validateSnapshot(*m::GetSizePrefixedSnapshot(bytes.data())).has_value());
  }
  auto bytes = attackSnapshot(1,17,2,-1);
  CHECK_FALSE(m::validateSnapshot(*m::GetSizePrefixedSnapshot(bytes.data())).has_value());
}
TEST_CASE("attack history is bounded independent from motion and absent after departure reset") {
  WorldModel model;
  SnapshotData s; s.mapSize={16,16,4};
  s.units={{1,{1,1,1},JobKind::Idle,"DWARF"},{2,{2,1,1},JobKind::Idle,"GOBLIN"}};
  for (Tick tick=1;tick<400;++tick) {
    s.tick=tick; s.units[0].attack={static_cast<int32_t>(tick),2,8,5,tick};
    model.ingest(s, static_cast<double>(tick));
  }
  CHECK(model.evaluate(1,399).attack.actionId == 399);
  CHECK(model.evaluate(1,398).attack.actionId == 398);
  CHECK(model.evaluate(1,2).attack.actionId == -1);
  s.tick=400; s.units.clear(); model.ingest(s,400);
  CHECK(model.evaluate(1,400).presence == Presence::Departed);
  CHECK(model.evaluate(1,400).attack.actionId == -1);
  model.resetSession();
  CHECK(model.evaluate(1,399).attack.actionId == -1);
}
