#include <doctest.h>
#include "management_util.h"
namespace m=df3d::mirror;
TEST_CASE("Justice conviction requires case and candidate revisions and a single target") {
 for(bool apply:{false,true})for(int fault=0;fault<10;++fault){
  flatbuffers::FlatBufferBuilder b;
  auto query=b.CreateString(fault==7?std::string(513,'x'):fault==8?std::string("a\0b",3):"fixture");
  auto q=m::CreateJusticeRequest(b,0,fault==6?1:0,32,fault==1?0:7,9,fault==2?0:8,
    query,fault==3?UINT64_MAX:fault==4?0:9,apply?(fault==5?-1:42):(fault==5?42:-1));
  m::ConstructionRequestBuilder r(b);r.add_client_id(1);r.add_seq(1);r.add_world_epoch(1);
  r.add_action(fault==9?m::ManagementAction::JusticeCaseRead:apply?m::ManagementAction::JusticeConvict:m::ManagementAction::JusticeCandidatesRead);
  r.add_justice(q);b.Finish(r.Finish());
  const bool invalid=fault!=0 && !(fault==4 && !apply) && !(fault==6 && !apply);
  CHECK(bool(m::validateConstructionRequest(*flatbuffers::GetRoot<m::ConstructionRequest>(b.GetBufferPointer())))==invalid);
 }
}
TEST_CASE("Justice candidate pages bind unique units to a crime and revision") {
 for(int fault=0;fault<8;++fault){flatbuffers::FlatBufferBuilder b;
  std::vector<flatbuffers::Offset<m::JusticeCandidateRow>> rows;
  rows.push_back(m::CreateJusticeCandidateRow(b,42,39,true,false));
  rows.push_back(m::CreateJusticeCandidateRow(b,fault==1?42:43,0,false,true));
  auto candidates=m::CreateJusticeCandidatePage(b,fault==2?-1:9,fault==3?0:8,fault==4?1:2,0,b.CreateVector(rows));
  auto result=m::CreateJusticeState(b,fault==5?m::JusticeOutcome::Stale:m::JusticeOutcome::None,0,7,0,0,
    b.CreateVector(std::vector<flatbuffers::Offset<m::JusticeCaseRow>>{}),0,candidates);
  m::ManagementStateBuilder s(b);s.add_revision(1);s.add_action(fault==6?m::ManagementAction::JusticeRead:m::ManagementAction::JusticeCandidatesRead);
  s.add_status(fault==7?m::ManagementStatus::Rejected:m::ManagementStatus::Ok);s.add_justice(result);b.Finish(s.Finish());
  CHECK(bool(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())))==(fault!=0));
 }
}
TEST_CASE("Justice mutation outcomes cannot masquerade as reads or carry reusable data") {
 for(auto outcome:{m::JusticeOutcome::None,m::JusticeOutcome::Rejected,m::JusticeOutcome::Stale,m::JusticeOutcome::Applied,m::JusticeOutcome::Unknown})
 for(bool ok:{false,true})for(bool read:{false,true})for(bool data:{false,true}){
  flatbuffers::FlatBufferBuilder b;
  auto result=m::CreateJusticeState(b,outcome,0,data?7:0,0,0,b.CreateVector(std::vector<flatbuffers::Offset<m::JusticeCaseRow>>{}));
  m::ManagementStateBuilder s(b);s.add_revision(1);s.add_action(read?m::ManagementAction::JusticeCandidatesRead:m::ManagementAction::JusticeConvict);
  s.add_status(ok?m::ManagementStatus::Ok:m::ManagementStatus::Rejected);s.add_justice(result);b.Finish(s.Finish());
  const bool valid=!data && (read ? !ok && (outcome==m::JusticeOutcome::Rejected || outcome==m::JusticeOutcome::Stale) :
    ok ? outcome==m::JusticeOutcome::Applied : outcome==m::JusticeOutcome::Rejected || outcome==m::JusticeOutcome::Stale || outcome==m::JusticeOutcome::Unknown);
  CHECK(bool(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())))==!valid);
 }
}
TEST_CASE("Justice requests scope paged reads to list and case revisions") {
 for(bool detail:{false,true})for(int fault=0;fault<10;++fault){
  flatbuffers::FlatBufferBuilder b;
  auto q=m::CreateJusticeRequest(b,fault==1?3:0,fault==2?1:0,fault==3?65:32,
    fault==4?UINT64_MAX:detail?7:0,fault==5?-2:detail?9:-1,fault==6?UINT64_MAX:0);
  auto other=m::CreateObjectsRequest(b);
  m::ConstructionRequestBuilder r(b);r.add_client_id(1);r.add_seq(1);r.add_world_epoch(1);
  r.add_action(fault==8?m::ManagementAction::ObjectsRead:detail?m::ManagementAction::JusticeCaseRead:m::ManagementAction::JusticeRead);
  if(fault!=7)r.add_justice(q);
  if(fault==9)r.add_objects(other);
  b.Finish(r.Finish());
  CHECK(bool(m::validateConstructionRequest(*flatbuffers::GetRoot<m::ConstructionRequest>(b.GetBufferPointer())))==(fault!=0));
 }
}
TEST_CASE("Justice case pages preserve paired native witness captions and reject malformed replies") {
 for(int fault=0;fault<16;++fault){flatbuffers::FlatBufferBuilder b;
  auto text=b.CreateString(fault==8?std::string(16385,'x'):fault==9?std::string(16384,'x'):"fixture");
  std::vector<flatbuffers::Offset<m::JusticeWitnessRow>> witnesses;
  int count=fault==9?32:fault==10?0:1;
  for(int i=0;i<count;++i)witnesses.push_back(m::CreateJusticeWitnessRow(b,text,text,text,text));
  auto detail=m::CreateJusticeCaseDetail(b,fault==1?-1:9,fault==2?0:7,text,0,text,
    fault==10?1:count,fault==3?2:0,b.CreateVector(witnesses),fault==14?m::JusticeCaseResolution::None:fault==15?m::JusticeCaseResolution(4):m::JusticeCaseResolution::Unsolved);
  auto result=m::CreateJusticeState(b,fault==4?m::JusticeOutcome::Stale:m::JusticeOutcome::None,
    fault==5?3:0,fault==6?0:7,fault==11?1:0,0,b.CreateVector(std::vector<flatbuffers::Offset<m::JusticeCaseRow>>{}),fault==12?0:detail);
  m::ManagementStateBuilder s(b);s.add_revision(1);s.add_action(fault==7?m::ManagementAction::JusticeRead:m::ManagementAction::JusticeCaseRead);
  s.add_status(fault==13?m::ManagementStatus::Rejected:m::ManagementStatus::Ok);s.add_justice(result);b.Finish(s.Finish());
  CHECK(bool(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())))==(fault!=0));
 }
}
TEST_CASE("Justice lists reject duplicate case IDs and unusable stale data") {
 for(int fault=0;fault<7;++fault){flatbuffers::FlatBufferBuilder b;auto text=b.CreateString("fixture");
  std::vector<flatbuffers::Offset<m::JusticeCaseRow>> rows;
  for(int i=0;i<2;++i)rows.push_back(m::CreateJusticeCaseRow(b,fault==1?9:9+i,text));
  auto result=m::CreateJusticeState(b,fault==2?m::JusticeOutcome::Stale:m::JusticeOutcome::None,0,
    fault==3?UINT64_MAX:7,fault==4?1:2,0,b.CreateVector(rows));
  m::ManagementStateBuilder s(b);s.add_revision(1);s.add_action(fault==5?m::ManagementAction::ObjectsRead:m::ManagementAction::JusticeRead);
  s.add_status(fault==6?m::ManagementStatus::Rejected:m::ManagementStatus::Ok);s.add_justice(result);b.Finish(s.Finish());
  CHECK(bool(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())))==(fault!=0));
 }
 for(auto action:{m::ManagementAction::JusticeRead,m::ManagementAction::JusticeCaseRead}){
  flatbuffers::FlatBufferBuilder b;
  auto result=m::CreateJusticeState(b,m::JusticeOutcome::Stale,0,0,0,0,b.CreateVector(std::vector<flatbuffers::Offset<m::JusticeCaseRow>>{}));
  m::ManagementStateBuilder s(b);s.add_revision(1);s.add_action(action);s.add_status(m::ManagementStatus::Rejected);s.add_justice(result);b.Finish(s.Finish());
  CHECK_FALSE(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())));
 }
}
