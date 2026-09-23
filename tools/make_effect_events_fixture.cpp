// Small deterministic source-event fixture for adapter timing/compatibility.
#include "fixture_io.h"
#include "validate.h"
#include <cstdio>
using namespace df3d::mirror;
int main(int argc,char** argv) {
  if(argc!=2) return 2;
  flatbuffers::FlatBufferBuilder f;
  const TilePos size(16,16,2),pos(3,4,1),other(5,4,1);
  auto source=[&](int id,const char* type,const char* subtype,const char* material) {
    auto t=f.CreateString(type),s=f.CreateString(subtype),m=f.CreateString(material);
    return CreateEventItem(f,id,t,s,m,id==9?4u:id>=10?2u:0u,true);
  };
  auto weapon=source(8,"WEAPON","ITEM_WEAPON_CROSSBOW","PLANT:OAK:WOOD");
  auto ammo=source(9,"AMMO","ITEM_AMMO_BOLTS","CREATURE:DWARF:BONE");
  auto wound=CreateCombatEvent(f,1,95,CombatEventKind::Wound,1,2,3,&pos,51,4,weapon);
  auto wounds=f.CreateVector(std::vector{wound});
  auto shot=CreateProjectileSample(f,1,7,98,9,1,&pos,&pos,&pos,&other,true,true,ammo,weapon);
  auto shots=f.CreateVector(std::vector{shot});
  auto report=[&](int id,int tick,const char* token,bool located) {
    auto type=f.CreateString(token);return CreateReportEvent(f,id,tick,id+50,type,located?&pos:nullptr,located?&other:nullptr,0,-1);
  };
  auto first=report(1,90,"COMBAT_PARRY",true),second=report(2,100,"MIGRANTS_ARRIVAL",false);
  auto reports=f.CreateVector(std::vector{first,second});
  auto iron=source(10,"WEAPON","ITEM_WEAPON_SWORD_SHORT","INORGANIC:IRON");
  auto armor=source(11,"ARMOR","ITEM_ARMOR_BREASTPLATE","INORGANIC:IRON");
  auto contact=CreateItemContactEvent(f,1,96,iron,armor,&pos);
  auto contacts=f.CreateVector(std::vector{contact});
  auto pair=CreateAttackContact(f,iron,armor);
  auto pairs=f.CreateVector(std::vector{pair});
  auto head=f.CreateString("HEAD");
  auto part=CreateAttackWoundPart(f,3,1,head,head,4,1);
  auto parts=f.CreateVector(std::vector{part});
  auto woundResult=CreateAttackWound(f,12,2,true,false,parts,true);
  auto injuryResults=f.CreateVector(std::vector{woundResult});
  auto attack=CreateResolvedAttack(f,1,97,1,2,7,iron,&pos,pairs,true,injuryResults,true,AttackOutcome::Hit,true,true);
  auto attacks=f.CreateVector(std::vector{attack});
  auto projectile=CreateProjectileCombatEvent(f,1,98,7,1,-1,ProjectileCombatKind::Release,WeaponLauncher::Crossbow,ammo,weapon,&pos,true);
  auto projectileEvents=f.CreateVector(std::vector{projectile});
  SnapshotBuilder b(f);b.add_schema_version(uint32_t(SchemaVersion::Current));b.add_tick(100);b.add_emitted_at_ms(1000);b.add_map_size(&size);
  b.add_report_events(reports);b.add_combat_events(wounds);b.add_projectile_samples(shots);b.add_report_events_dropped(7);
  b.add_item_contacts(contacts);b.add_item_contacts_dropped(2);
  b.add_item_contacts_available(true);
  b.add_projectile_combat_events(projectileEvents);b.add_projectile_combat_events_available(true);
  b.add_resolved_attacks(attacks);b.add_resolved_attacks_available(true);
  FinishSizePrefixedSnapshotBuffer(f,b.Finish());
  std::vector<uint8_t> frame(f.GetBufferPointer(),f.GetBufferPointer()+f.GetSize());
  if(auto invalid=validateSnapshot(*GetSizePrefixedSnapshot(frame.data()))) {std::fprintf(stderr,"%s\n",invalid->c_str());return 1;}
  std::string error;
  if(!writeFixtureFile(argv[1],assembleFixture({frame}),error)) return 1;
  std::puts("EFFECT_EVENTS_FIXTURE_PASS");
}
