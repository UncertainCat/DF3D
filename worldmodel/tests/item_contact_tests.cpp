#include <doctest.h>
#include "wm/world_model.h"
#include "fixture_io.h"
#include "validate.h"
using namespace wm;
namespace m=df3d::mirror;
namespace {
ItemContactEvent contact(uint64_t id,Tick tick) {
  return {id,tick,{10,"WEAPON","SWORD","INORGANIC:IRON"},
          {11,"ARMOR","BREASTPLATE","INORGANIC:IRON"},{2,3,1}};
}
std::vector<uint8_t> bytes(uint64_t id=1,Tick tick=100,int secondId=11,int x=2) {
  flatbuffers::FlatBufferBuilder f;m::TilePos size(16,16,4),pos(x,3,1);
  auto material=f.CreateString("INORGANIC:IRON"),type=f.CreateString("WEAPON");
  auto a=m::CreateEventItem(f,10,type,{},material),b=m::CreateEventItem(f,secondId,type,{},material);
  auto e=m::CreateItemContactEvent(f,id,tick,a,b,&pos);
  auto es=f.CreateVector(std::vector{e});m::SnapshotBuilder s(f);
  s.add_schema_version(uint32_t(m::SchemaVersion::Current));s.add_tick(100);s.add_map_size(&size);
  s.add_item_contacts(es);s.add_item_contacts_dropped(4);
  m::FinishSizePrefixedSnapshotBuffer(f,s.Finish());return {f.GetBufferPointer(),f.GetBufferPointer()+f.GetSize()};
}
}
TEST_CASE("positive item contacts survive transport with owned identities") {
  auto data=bytes();WorldModel w;std::string error;
  REQUIRE_FALSE(m::validateSnapshot(*m::GetSizePrefixedSnapshot(data.data())).has_value());
  REQUIRE_MESSAGE(loadFixtureBytes(w,m::assembleFixture({data}),error),error);
  data.clear();REQUIRE(w.itemContacts().size()==1);
  CHECK(w.itemContacts()[0].first.material=="INORGANIC:IRON");
  CHECK(w.itemContacts()[0].second.id==11);CHECK(w.itemContactsDropped()==4);
  for(const auto& bad:{bytes(0),bytes(1,101),bytes(1,100,10),bytes(1,100,-1),bytes(1,100,11,16)})
    CHECK(m::validateSnapshot(*m::GetSizePrefixedSnapshot(bad.data())).has_value());
}
TEST_CASE("item contact journal repeats are idempotent and sessions isolate identity") {
  WorldModel w;SnapshotData s;s.mapSize={16,16,4};s.tick=100;s.itemContacts={contact(1,100)};
  s.itemContactsDropped=3;w.ingest(s,0);w.ingest(s,1);
  REQUIRE(w.itemContacts().size()==1);CHECK(w.itemContactsDropped()==3);
  auto copy=w;s.itemContacts[0].first.material="changed";
  CHECK(copy.itemContacts()[0].first.material=="INORGANIC:IRON");
  s.itemContacts.clear();s.tick=701;w.ingest(s,2);CHECK(w.itemContacts().empty());
  s.itemContacts={contact(1,100)};w.ingest(s,3);CHECK(w.itemContacts().empty());
  for(uint64_t id=2;id<=600;++id){s.itemContacts={contact(id,701)};w.ingest(s,4);}
  CHECK(w.itemContacts().size()==512);
  s.tick=10;s.itemContacts={contact(1,10)};s.itemContactsDropped=0;w.ingest(s,5);
  REQUIRE(w.itemContacts().size()==1);CHECK(w.itemContacts()[0].id==1);CHECK(w.itemContactsDropped()==0);
  w.resetSession();CHECK(w.itemContacts().empty());
}

TEST_CASE("resolved attack transport keeps nested contacts and coverage") {
  flatbuffers::FlatBufferBuilder f;m::TilePos size(16,16,4),pos(2,3,1);
  auto mat=f.CreateString("INORGANIC:IRON"),type=f.CreateString("WEAPON");
  auto first=m::CreateEventItem(f,10,type,{},mat,2,true,f.CreateString("SWORD")),second=m::CreateEventItem(f,11,type,{},mat);
  auto contact=m::CreateAttackContact(f,first,second);
  auto contacts=f.CreateVector(std::vector{contact});
  auto token=f.CreateString("BRAIN"),category=f.CreateString("BRAIN");
  auto part=m::CreateAttackWoundPart(f,4,1,token,category,uint32_t(AttackDamageFlag::SmashedApart),uint32_t(AttackAnatomyFlag::Thought));
  auto parts=f.CreateVector(std::vector{part});
  auto wound=m::CreateAttackWound(f,12,2,false,false,parts,true);
  auto wounds=f.CreateVector(std::vector{wound});
  auto attack=m::CreateResolvedAttack(f,1,100,1,2,7,first,&pos,contacts,true,wounds,true,m::AttackOutcome::Hit,true,true);
  auto attacks=f.CreateVector(std::vector{attack});m::SnapshotBuilder b(f);
  b.add_schema_version(uint32_t(m::SchemaVersion::Current));b.add_tick(100);b.add_map_size(&size);
  b.add_resolved_attacks(attacks);b.add_resolved_attacks_available(true);b.add_resolved_attacks_dropped(3);
  m::FinishSizePrefixedSnapshotBuffer(f,b.Finish());
  auto* snap=m::GetSizePrefixedSnapshot(f.GetBufferPointer());
  REQUIRE_FALSE(m::validateSnapshot(*snap));
  WorldModel w;std::string error;
  std::vector<uint8_t> bytes(f.GetBufferPointer(),f.GetBufferPointer()+f.GetSize());
  REQUIRE(loadFixtureBytes(w,m::assembleFixture({bytes}),error));
  REQUIRE(w.resolvedAttacks().size()==1);
  const auto& e=w.resolvedAttacks().front();
  CHECK(e.outcome==AttackOutcome::Hit);CHECK(e.outcomeComplete);CHECK(e.weaponContextComplete);
  CHECK(e.weapon.materialFlags==2);CHECK(e.weapon.materialFlagsKnown);CHECK(e.weapon.meleeSkill=="SWORD");
  CHECK(e.actionId==7);CHECK(e.attackerId==1);CHECK(e.defenderId==2);
  CHECK(e.equipmentContactsComplete);REQUIRE(e.contacts.size()==1);
  CHECK(e.contacts[0].second.id==11);CHECK(e.contacts[0].first.material=="INORGANIC:IRON");
  CHECK(w.resolvedAttacksAvailable());CHECK(w.resolvedAttacksDropped()==3);
  CHECK(e.woundsComplete);REQUIRE(e.wounds.size()==1);
  const auto& injury=e.wounds.front();CHECK(injury.woundId==12);CHECK(injury.victimId==2);
  CHECK(injury.partsComplete);REQUIRE(injury.parts.size()==1);
  CHECK(injury.parts.front().bodyPartToken=="BRAIN");
  CHECK(injury.parts.front().damageFlags==uint32_t(AttackDamageFlag::SmashedApart));
  CHECK(injury.parts.front().anatomyFlags==uint32_t(AttackAnatomyFlag::Thought));
}
TEST_CASE("resolved attack journal owns execution identity and resets") {
  WorldModel w;SnapshotData s;s.mapSize={16,16,4};s.tick=100;
  ResolvedAttack a;a.id=1;a.tick=100;a.actionId=7;
  s.resolvedAttacks={a};s.resolvedAttacksAvailable=true;
  w.ingest(s,0);w.ingest(s,1);CHECK(w.resolvedAttacks().size()==1);
  a.id=2;s.resolvedAttacks.push_back(a);w.ingest(s,2);
  CHECK(w.resolvedAttacks().size()==2);
  s.tick=701;s.resolvedAttacks.clear();w.ingest(s,3);CHECK(w.resolvedAttacks().empty());
  for(uint64_t id=3;id<600;++id){a.id=id;a.tick=701;s.resolvedAttacks={a};w.ingest(s,4);}
  CHECK(w.resolvedAttacks().size()==512);
  s.tick=10;a.id=1;a.tick=10;s.resolvedAttacks={a};w.ingest(s,5);
  REQUIRE(w.resolvedAttacks().size()==1);CHECK(w.resolvedAttacks().front().id==1);
  w.resetSession();CHECK(w.resolvedAttacks().empty());CHECK_FALSE(w.resolvedAttacksAvailable());
}

TEST_CASE("causal wound schema rejects ambiguous or invalid results") {
  auto fixture=[](int victim,int woundId,uint32_t damage,size_t count) {
    flatbuffers::FlatBufferBuilder f;m::TilePos size(16,16,4),pos(2,3,1);
    std::vector<flatbuffers::Offset<m::AttackWoundPart>> parts;
    for(size_t i=0;i<count;++i)parts.push_back(m::CreateAttackWoundPart(f,1,0,{}, {},damage,0));
    auto pv=f.CreateVector(parts);auto w=m::CreateAttackWound(f,woundId,victim,false,false,pv,true);
    auto ws=f.CreateVector(std::vector{w});
    auto a=m::CreateResolvedAttack(f,1,100,1,2,7,{},&pos,{},true,ws,true);
    auto as=f.CreateVector(std::vector{a});m::SnapshotBuilder b(f);
    b.add_schema_version(uint32_t(m::SchemaVersion::Current));b.add_tick(100);b.add_map_size(&size);b.add_resolved_attacks(as);
    m::FinishSizePrefixedSnapshotBuffer(f,b.Finish());
    return m::validateSnapshot(*m::GetSizePrefixedSnapshot(f.GetBufferPointer()));
  };
  CHECK_FALSE(fixture(2,12,4,1));
  CHECK(fixture(3,12,4,1));CHECK(fixture(2,-1,4,1));
  CHECK(fixture(2,12,1024,1));CHECK(fixture(2,12,4,129));
}

TEST_CASE("projectile combat transport retains source phase without temporal joins") {
  flatbuffers::FlatBufferBuilder f;m::TilePos size(16,16,4),pos(2,3,1);
  auto type=f.CreateString("AMMO"),mat=f.CreateString("INORGANIC:IRON");
  auto item=m::CreateEventItem(f,20,type,{},mat,2,true);
  auto event=m::CreateProjectileCombatEvent(f,1,100,42,1,2,m::ProjectileCombatKind::HitCreature,
    m::WeaponLauncher::Crossbow,item,{},&pos,true);
  auto events=f.CreateVector(std::vector{event});m::SnapshotBuilder b(f);
  b.add_schema_version(uint32_t(m::SchemaVersion::Current));b.add_tick(100);b.add_map_size(&size);
  b.add_projectile_combat_events(events);b.add_projectile_combat_events_available(true);b.add_projectile_combat_events_dropped(4);
  m::FinishSizePrefixedSnapshotBuffer(f,b.Finish());
  REQUIRE_FALSE(m::validateSnapshot(*m::GetSizePrefixedSnapshot(f.GetBufferPointer())));
  std::vector<uint8_t> data(f.GetBufferPointer(),f.GetBufferPointer()+f.GetSize());
  WorldModel w;std::string error;REQUIRE(loadFixtureBytes(w,m::assembleFixture({data}),error));
  data.clear();REQUIRE(w.projectileCombatEvents().size()==1);
  const auto& e=w.projectileCombatEvents().front();
  CHECK(e.projectileId==42);CHECK(e.sourceUnitId==1);CHECK(e.targetUnitId==2);
  CHECK(e.kind==ProjectileCombatKind::HitCreature);CHECK(e.launcher==WeaponLauncher::Crossbow);
  CHECK(e.ammunition.materialFlagsKnown);CHECK(e.ammunition.materialFlags==2);CHECK(e.contextComplete);
  CHECK(w.projectileCombatEventsAvailable());CHECK(w.projectileCombatEventsDropped()==4);
}
TEST_CASE("projectile combat journal deduplicates, expires and isolates source sessions") {
  WorldModel w;SnapshotData s;s.mapSize={16,16,4};s.tick=100;
  ProjectileCombatEvent e;e.id=1;e.tick=100;e.projectileId=42;e.kind=ProjectileCombatKind::Release;
  s.projectileCombatEvents={e};s.projectileCombatEventsAvailable=true;s.projectileCombatEventsDropped=2;
  w.ingest(s,0);w.ingest(s,1);CHECK(w.projectileCombatEvents().size()==1);
  e.id=2;e.kind=ProjectileCombatKind::GroundImpact;s.projectileCombatEvents.push_back(e);w.ingest(s,2);
  CHECK(w.projectileCombatEvents().size()==2);
  s.tick=701;s.projectileCombatEvents.clear();w.ingest(s,3);CHECK(w.projectileCombatEvents().empty());
  for(uint64_t id=3;id<600;++id){e.id=id;e.tick=701;s.projectileCombatEvents={e};w.ingest(s,4);}
  CHECK(w.projectileCombatEvents().size()==512);
  s.tick=10;e.id=1;e.tick=10;s.projectileCombatEvents={e};s.projectileCombatEventsDropped=0;w.ingest(s,5);
  REQUIRE(w.projectileCombatEvents().size()==1);CHECK(w.projectileCombatEvents().front().id==1);
  CHECK(w.projectileCombatEventsDropped()==0);w.resetSession();CHECK(w.projectileCombatEvents().empty());
  CHECK_FALSE(w.projectileCombatEventsAvailable());
}
