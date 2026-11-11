#include <doctest.h>
#include "management_util.h"
namespace m=df3d::mirror;
TEST_CASE("Objects artwork carries bounded item facts with a known item type") {
 for(int fault=0;fault<7;++fault){flatbuffers::FlatBufferBuilder b;
  const auto text=b.CreateString("fixture"),empty=b.CreateString("");
  const auto material=b.CreateString(fault==3?std::string(257,'x'):"INORGANIC:IRON");
  const auto art=m::CreateItemInspectionAppearance(b,fault==2?0:material,empty,empty,fault==4?0:1,fault==5?1:32);
  const auto row=m::CreateObjectsRow(b,7,8,text,text,text,nullptr,art,fault==1?-1:fault==6?93:36);
  const auto payload=m::CreateObjectsState(b,m::ObjectsOutcome::None,0,1,1,0,b.CreateVector(std::vector{row}));
  m::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(m::ManagementAction::ObjectsRead);
  state.add_status(m::ManagementStatus::Ok);state.add_objects(payload);b.Finish(state.Finish());
  CHECK(bool(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())))==(fault!=0));
 }
}
TEST_CASE("Objects pages and destinations require scoped read identities") {
 for(bool locate:{false,true})for(int fault=0;fault<9;++fault){
  flatbuffers::FlatBufferBuilder b;
  auto q=m::CreateObjectsRequest(b,fault==1?4:0,fault==2?1:0,fault==3?65:32,
    fault==4?UINT64_MAX:locate && fault!=5?7:0,fault==6?-2:locate?42:-1);
  m::ConstructionRequestBuilder r(b);r.add_client_id(1);r.add_seq(1);r.add_world_epoch(1);
  r.add_action(fault==8?m::ManagementAction::PlacesRead:locate?m::ManagementAction::ObjectsLocate:m::ManagementAction::ObjectsRead);
  if(fault!=7)r.add_objects(q);b.Finish(r.Finish());
  const bool bad=fault!=0 && (fault!=5 || locate);
  CHECK(bool(m::validateConstructionRequest(*flatbuffers::GetRoot<m::ConstructionRequest>(b.GetBufferPointer())))==bad);
 }
}
TEST_CASE("Objects pages reject duplicate artifacts and incomplete paging") {
 for(int fault=0;fault<10;++fault){flatbuffers::FlatBufferBuilder b;
  const auto text=b.CreateString(fault==8?std::string(16385,'x'):fault==9?std::string(16384,'x'):"fixture");
  const m::TilePos pos(fault==7?-1:12,13,14);
  std::vector<flatbuffers::Offset<m::ObjectsRow>> rows;
  const int count=fault==1?2:fault==2?0:fault==9?32:1;
  for(int i=0;i<count;++i)rows.push_back(m::CreateObjectsRow(b,fault==1?7:7+i,fault==6?-1:8+i,text,text,text,&pos));
  auto payload=m::CreateObjectsState(b,m::ObjectsOutcome::None,0,fault==3?0:7,fault==2?1:count,fault==4?2:0,b.CreateVector(rows));
  m::ManagementStateBuilder s(b);s.add_revision(1);s.add_action(fault==5?m::ManagementAction::ObjectsLocate:m::ManagementAction::ObjectsRead);
  s.add_status(m::ManagementStatus::Ok);s.add_objects(payload);b.Finish(s.Finish());
  CHECK(bool(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())))==(fault!=0));
 }
}
TEST_CASE("Objects destination can be unavailable without inventing coordinates") {
 for(bool positioned:{false,true})for(int fault=0;fault<7;++fault){flatbuffers::FlatBufferBuilder b;
  const m::TilePos pos(1,2,3);
  auto destination=m::CreateObjectsDestination(b,fault==1?-1:7,fault==2?-1:8,positioned?&pos:nullptr);
  auto payload=m::CreateObjectsState(b,m::ObjectsOutcome::None,0,fault==3?0:7,fault==4?1:0,0,
    b.CreateVector(std::vector<flatbuffers::Offset<m::ObjectsRow>>{}),fault==5?0:destination);
  m::ManagementStateBuilder s(b);s.add_revision(1);s.add_action(fault==6?m::ManagementAction::ObjectsRead:m::ManagementAction::ObjectsLocate);
  s.add_status(m::ManagementStatus::Ok);s.add_objects(payload);b.Finish(s.Finish());
  CHECK(bool(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())))==(fault!=0));
 }
}
TEST_CASE("Objects refusal cannot carry usable stale rows or destination") {
 for(auto action:{m::ManagementAction::ObjectsRead,m::ManagementAction::ObjectsLocate})
 for(auto outcome:{m::ObjectsOutcome::Rejected,m::ObjectsOutcome::Stale})for(int fault=0;fault<5;++fault){
  flatbuffers::FlatBufferBuilder b;
  auto destination=m::CreateObjectsDestination(b,7,8);
  auto payload=m::CreateObjectsState(b,fault==1?m::ObjectsOutcome::None:outcome,0,fault==2?7:0,0,0,
    b.CreateVector(std::vector<flatbuffers::Offset<m::ObjectsRow>>{}),fault==3?destination:0);
  m::ManagementStateBuilder s(b);s.add_revision(1);s.add_action(action);
  s.add_status(fault==4?m::ManagementStatus::Ok:m::ManagementStatus::Rejected);s.add_objects(payload);b.Finish(s.Finish());
  CHECK(bool(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())))==(fault!=0));
 }
}
