#include <doctest.h>
#include "management_util.h"
namespace m=df3d::mirror;
TEST_CASE("Creature lists preserve typed identity and reject duplicate or impossible members") {
 for(int fault=0;fault<8;++fault) {
  flatbuffers::FlatBufferBuilder b;
  std::vector<int32_t> ids{7,fault==3?-1:7};
  std::vector<m::CreatureListKind> kinds{m::CreatureListKind::Unit,
    fault==1?m::CreatureListKind::Unit:fault==2?static_cast<m::CreatureListKind>(2):m::CreatureListKind::Item};
  auto list=m::CreateCreatureListState(b,fault==4?m::CreatureListTab::Dead:fault==5?static_cast<m::CreatureListTab>(0):m::CreatureListTab::Pets,b.CreateVector(ids),b.CreateVector(kinds));
  m::ManagementStateBuilder s(b);s.add_revision(1);
  s.add_action(fault==6?m::ManagementAction::Catalog:m::ManagementAction::CreatureListQuery);
  s.add_status(m::ManagementStatus::Ok);if(fault!=7)s.add_creature_list(list);b.Finish(s.Finish());
  CHECK(bool(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())))==(fault!=0));
 }
}
TEST_CASE("Creature list sorts and textbox bytes preserve native admission") {
 for(int tab=0;tab<5;++tab)for(int sort=0;sort<7;++sort)for(int query=0;query<3;++query) {
  flatbuffers::FlatBufferBuilder b;
  // Partial UTF-8 is native textbox state; embedded NUL is not.
  const std::vector<uint8_t> bytes=query==0?std::vector<uint8_t>{0xc3}:query==1?std::vector<uint8_t>{0}:std::vector<uint8_t>(m::kResidentsQueryBytes+1,'a');
  auto list=m::CreateCreatureListRequest(b,static_cast<m::CreatureListTab>(tab),static_cast<m::CreatureListSort>(sort),false,b.CreateVector(bytes));
  m::ConstructionRequestBuilder r(b);r.add_client_id(1);r.add_seq(1);r.add_world_epoch(1);
  r.add_action(m::ManagementAction::CreatureListQuery);r.add_creature_list(list);b.Finish(r.Finish());
  const bool valid=tab>=1 && tab<=3 && (sort<=2 || sort==4 || (sort==5 && tab==1)) && query==0;
  CHECK(bool(m::validateConstructionRequest(*flatbuffers::GetRoot<m::ConstructionRequest>(b.GetBufferPointer())))==!valid);
 }
}
TEST_CASE("Creature list query requires matching envelope and current management version") {
 for(int fault=0;fault<4;++fault) {
  flatbuffers::FlatBufferBuilder b;
  auto list=m::CreateCreatureListRequest(b,m::CreatureListTab::Other,m::CreatureListSort::Name,false,b.CreateVector(std::vector<uint8_t>{}));
  m::ConstructionRequestBuilder r(b);r.add_client_id(1);r.add_seq(1);r.add_world_epoch(1);
  r.add_schema_version(fault==1?255:m::kManagementVersion);
  r.add_action(fault==2?m::ManagementAction::Catalog:m::ManagementAction::CreatureListQuery);
  if(fault!=3)r.add_creature_list(list);b.Finish(r.Finish());
  CHECK(bool(m::validateConstructionRequest(*flatbuffers::GetRoot<m::ConstructionRequest>(b.GetBufferPointer())))==(fault!=0));
 }
}
TEST_CASE("Maximum creature roster fits a management reply and requires aligned identities") {
 for(int fault=0;fault<3;++fault) {
  flatbuffers::FlatBufferBuilder b;
  std::vector<int32_t> ids(m::kCreatureListEntries+(fault==2?1:0));
  for(size_t i=0;i<ids.size();++i)ids[i]=int32_t(i);
  std::vector<m::CreatureListKind> kinds(ids.size()-(fault==1?1:0),m::CreatureListKind::Unit);
  auto list=m::CreateCreatureListState(b,m::CreatureListTab::Dead,b.CreateVector(ids),b.CreateVector(kinds));
  m::ManagementStateBuilder s(b);s.add_revision(1);s.add_action(m::ManagementAction::CreatureListQuery);
  s.add_status(m::ManagementStatus::Ok);s.add_creature_list(list);b.Finish(s.Finish());
  CHECK(bool(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())))==(fault!=0));
  if(fault==0)CHECK(b.GetSize()<m::kManagementCapacity);
 }
}
