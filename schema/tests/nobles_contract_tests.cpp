#include <doctest.h>
#include "management_util.h"
namespace m=df3d::mirror;
TEST_CASE("Nobles continuations require bounded pages and membership identity") {
 for(int fault=0;fault<7;++fault){flatbuffers::FlatBufferBuilder b;
  auto q=m::CreateNoblesRequest(b,fault==1?65537:fault==2?1:0,fault==3?0:fault==4?65:32,fault==5?UINT64_MAX:0);
  m::ConstructionRequestBuilder r(b);r.add_client_id(1);r.add_seq(1);r.add_world_epoch(1);
  r.add_action(m::ManagementAction::NoblesRead);if(fault!=6)r.add_nobles(q);b.Finish(r.Finish());
  CHECK(bool(m::validateConstructionRequest(*flatbuffers::GetRoot<m::ConstructionRequest>(b.GetBufferPointer())))==(fault!=0));
 }
}
TEST_CASE("Nobles pages validate office triples and complete assessments") {
 for(int fault=0;fault<12;++fault){flatbuffers::FlatBufferBuilder b;
  auto text=b.CreateString("fixture");auto values=b.CreateVector(std::vector<int32_t>(fault==3?3:4,0));
  std::vector<flatbuffers::Offset<m::NoblesRow>> rows;
  for(int i=0;i<(fault==1?2:1);++i)rows.push_back(m::CreateNoblesRow(b,7,2,fault==2?-2:-1,
    fault==4?-1:10,-1,0,text,text,text,true,true,values,values,values,values,fault==5?4:-1,-1));
  auto payload=m::CreateNoblesState(b,m::NoblesOutcome::None,fault==6?0:1,fault==7?0:rows.size(),fault==8?3:0,b.CreateVector(rows));
  m::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(fault==9?m::ManagementAction::PlacesRead:m::ManagementAction::NoblesRead);
  state.add_status(fault==10?m::ManagementStatus::Rejected:m::ManagementStatus::Ok);if(fault!=11)state.add_nobles(payload);b.Finish(state.Finish());
  CHECK(bool(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())))==(fault!=0));
 }
}
TEST_CASE("Nobles vacancy and NEW rows retain distinct assignment identity") {
 flatbuffers::FlatBufferBuilder b;auto text=b.CreateString("fixture");auto zero=b.CreateVector(std::vector<int32_t>(4,0));
 std::vector<flatbuffers::Offset<m::NoblesRow>> rows;
 for(int assignment:{-1,42})rows.push_back(m::CreateNoblesRow(b,7,2,assignment,-1,-1,0,text,text,text,true,false,zero,zero,zero,zero));
 auto payload=m::CreateNoblesState(b,m::NoblesOutcome::None,1,2,0,b.CreateVector(rows));
 m::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(m::ManagementAction::NoblesRead);state.add_status(m::ManagementStatus::Ok);state.add_nobles(payload);b.Finish(state.Finish());
 CHECK_FALSE(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())));
}
TEST_CASE("Nobles refusals cannot carry a successful page") {
 for(auto outcome:{m::NoblesOutcome::Rejected,m::NoblesOutcome::Stale})for(int fault=0;fault<3;++fault){
  flatbuffers::FlatBufferBuilder b;auto rows=b.CreateVector(std::vector<flatbuffers::Offset<m::NoblesRow>>{});
  auto payload=m::CreateNoblesState(b,outcome,fault==1?1:0,0,0,rows);
  m::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(m::ManagementAction::NoblesRead);
  state.add_status(fault==2?m::ManagementStatus::Ok:m::ManagementStatus::Rejected);state.add_nobles(payload);b.Finish(state.Finish());
  CHECK(bool(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())))==(fault!=0));
 }
}

TEST_CASE("Nobles holder artwork rejects vacant rows and empty recipes") {
 for(int fault=0;fault<3;++fault){flatbuffers::FlatBufferBuilder b;
  auto text=b.CreateString("fixture");auto zero=b.CreateVector(std::vector<int32_t>(4,0));
  auto names=b.CreateVector(std::vector<flatbuffers::Offset<flatbuffers::String>>{text});
  std::vector<m::AppearanceLayer> layers;
  if(fault!=2)layers.emplace_back(0,0,0,1,1,65535,0,0,0,0);
  auto look=m::CreateSelectionAppearance(b,names,b.CreateVector(std::vector<flatbuffers::Offset<flatbuffers::String>>{}),b.CreateVectorOfStructs(layers));
  auto row=m::CreateNoblesRow(b,7,2,42,fault==1?-1:10,-1,0,text,text,text,true,fault!=1,zero,zero,zero,zero,-1,-1,look);
  auto payload=m::CreateNoblesState(b,m::NoblesOutcome::None,1,1,0,b.CreateVector(std::vector<flatbuffers::Offset<m::NoblesRow>>{row}));
  m::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(m::ManagementAction::NoblesRead);
  state.add_status(m::ManagementStatus::Ok);state.add_nobles(payload);b.Finish(state.Finish());
  CHECK(bool(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())))==(fault!=0));
 }
}
