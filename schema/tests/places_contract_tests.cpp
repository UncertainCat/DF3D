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
