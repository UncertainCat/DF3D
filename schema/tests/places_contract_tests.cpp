#include <doctest.h>
#include "management_util.h"
namespace m=df3d::mirror;
TEST_CASE("Places requests require bounded pages and continuation identity") {
 for(int fault=0;fault<6;++fault){flatbuffers::FlatBufferBuilder b;
  auto q=m::CreatePlacesRequest(b,fault==1?6:0,fault==2?1:0,fault==3?65:32,fault==4?UINT64_MAX:0);
  m::ConstructionRequestBuilder r(b);r.add_client_id(1);r.add_seq(1);r.add_world_epoch(1);
  r.add_action(m::ManagementAction::PlacesRead);if(fault!=5)r.add_places(q);b.Finish(r.Finish());
  CHECK(bool(m::validateConstructionRequest(*flatbuffers::GetRoot<m::ConstructionRequest>(b.GetBufferPointer())))==(fault!=0));
 }
}
TEST_CASE("Places pages reject duplicate identities invalid action and stalled paging") {
 for(int fault=0;fault<7;++fault){flatbuffers::FlatBufferBuilder b;
  auto text=b.CreateString(fault==6?std::string(16384,'x'):"fixture");
  std::vector<flatbuffers::Offset<m::PlacesRow>> rows;
  const int count=fault==1?2:fault==2?0:fault==6?32:1;
  for(int i=0;i<count;++i)rows.push_back(m::CreatePlacesRow(b,fault==1?7:7+i,nullptr,text,text,text,text,text,text,text,0,fault==3?4:-1));
  auto p=m::CreatePlacesState(b,m::PlacesOutcome::None,0,fault==4?0:1,fault==2?1:count,fault==5?2:0,b.CreateVector(rows));
  m::ManagementStateBuilder s(b);s.add_revision(1);s.add_action(m::ManagementAction::PlacesRead);s.add_status(m::ManagementStatus::Ok);s.add_places(p);b.Finish(s.Finish());
  CHECK(bool(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())))==(fault!=0));
 }
}

TEST_CASE("Places subtitle location belongs only to zone rows") {
 for(int tab=0;tab<6;++tab)for(int location:{-2,-1,42}){
  flatbuffers::FlatBufferBuilder b;auto text=b.CreateString("fixture");
  auto row=m::CreatePlacesRow(b,7,nullptr,text,text,text,text,text,text,text,0,tab==5?0:-1,0,location);
  auto payload=m::CreatePlacesState(b,m::PlacesOutcome::None,tab,1,1,0,b.CreateVector(std::vector{row}));
  m::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(m::ManagementAction::PlacesRead);
  state.add_status(m::ManagementStatus::Ok);state.add_places(payload);b.Finish(state.Finish());
  CHECK(bool(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())))==(location<-1 || (tab!=0 && location!=-1)));
 }
}

TEST_CASE("Places siege intents require an observed membership and exact target scope") {
 for(int id:{-1,7})for(int action=0;action<5;++action)for(int fault=0;fault<9;++fault){
  flatbuffers::FlatBufferBuilder b;
  auto q=m::CreatePlacesRequest(b,fault==1?0:5,fault==2?1:0,fault==3?16:32,
    fault==4?0:fault==5?UINT64_MAX:17,fault==6?-2:id,fault==7?5:action);
  m::ConstructionRequestBuilder r(b);r.add_client_id(1);r.add_seq(1);r.add_world_epoch(1);
  r.add_action(fault==8?m::ManagementAction::PlacesRead:m::ManagementAction::PlacesApply);r.add_places(q);b.Finish(r.Finish());
  CHECK(bool(m::validateConstructionRequest(*flatbuffers::GetRoot<m::ConstructionRequest>(b.GetBufferPointer())))==(fault!=0));
 }
}
TEST_CASE("Places receipts separate acknowledged mutations from read pages") {
 for(auto outcome:{m::PlacesOutcome::Applied,m::PlacesOutcome::Rejected,m::PlacesOutcome::Stale,m::PlacesOutcome::Unknown})
 for(int fault=0;fault<8;++fault){flatbuffers::FlatBufferBuilder b;
  auto rows=b.CreateVector(std::vector<flatbuffers::Offset<m::PlacesRow>>{});
  auto payload=m::CreatePlacesState(b,fault==1?m::PlacesOutcome::None:outcome,fault==2?0:5,
    fault==3?1:0,fault==4?1:0,0,rows,fault==5?-2:7,fault==6?-1:3);
  m::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(m::ManagementAction::PlacesApply);
  state.add_status((outcome==m::PlacesOutcome::Applied) != (fault==7)?m::ManagementStatus::Ok:m::ManagementStatus::Rejected);
  state.add_places(payload);b.Finish(state.Finish());
  CHECK(bool(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())))==(fault!=0));
 }
}
