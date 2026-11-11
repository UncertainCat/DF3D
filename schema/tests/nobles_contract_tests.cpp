#include <doctest.h>
#include "management_util.h"
namespace m=df3d::mirror;
TEST_CASE("Symbol steps only accompany successful symbol effects") {
 for(int fault=0;fault<7;++fault){flatbuffers::FlatBufferBuilder b;
  auto rows=b.CreateVector(std::vector<flatbuffers::Offset<m::NoblesRow>>{});
  auto step=m::CreateNoblesSymbolStep(b,fault==1?0:123,fault==2?-1:261,fault==3?4097:2);
  auto payload=m::CreateNoblesState(b,fault==4?m::NoblesOutcome::Unknown:m::NoblesOutcome::Applied,0,0,0,rows,0,0,0,0,step);
  m::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(fault==5?m::ManagementAction::NoblesCommit:fault==6?m::ManagementAction::NoblesSymbolNameEdit:m::ManagementAction::NoblesSymbolsApply);
  state.add_status(fault==4?m::ManagementStatus::Rejected:m::ManagementStatus::Ok);state.add_nobles(payload);b.Finish(state.Finish());
  CHECK(bool(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())))==(fault!=0));
 }
}
TEST_CASE("Symbol pages require unique items and an existing office") {
 for(int fault=0;fault<7;++fault){flatbuffers::FlatBufferBuilder b;
  auto text=b.CreateString("fixture");auto empty=b.CreateString("");
  auto row=m::CreateNoblesSymbol(b,fault==1?-1:123,5,100,nullptr,nullptr,text,empty,empty,0,fault==6);
  std::vector<flatbuffers::Offset<m::NoblesSymbol>> entries{row};if(fault==2)entries.push_back(row);
  auto symbols=b.CreateVector(entries);auto rows=b.CreateVector(std::vector<flatbuffers::Offset<m::NoblesRow>>{});
  m::NoblesOffice target(7,2,fault==3?-1:42,0);
  auto payload=m::CreateNoblesState(b,m::NoblesOutcome::None,11,entries.size(),0,rows,&target,12,0,symbols,0,0,fault==5?0:text);
  m::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(fault==4?m::ManagementAction::NoblesRead:m::ManagementAction::NoblesSymbolsRead);
  state.add_status(m::ManagementStatus::Ok);state.add_nobles(payload);b.Finish(state.Finish());
  CHECK(bool(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())))==(fault!=0));
 }
}
TEST_CASE("Nobles accounting requires a fresh office and bounded expected setting") {
 for(int fault=0;fault<10;++fault){flatbuffers::FlatBufferBuilder b;
  m::NoblesOffice key(7,2,42,0);
  auto q=m::CreateNoblesRequest(b,fault==1?1:0,fault==2?64:32,fault==3?0:11,0,fault==4?nullptr:&key,fault==5?12:0,fault==6?-1:fault==7?5:2,fault==8?5:3);
  m::ConstructionRequestBuilder r(b);r.add_client_id(1);r.add_seq(1);r.add_world_epoch(1);r.add_action(fault==9?m::ManagementAction::NoblesCandidates:m::ManagementAction::NoblesAccounting);r.add_nobles(q);b.Finish(r.Finish());
  CHECK(bool(m::validateConstructionRequest(*flatbuffers::GetRoot<m::ConstructionRequest>(b.GetBufferPointer())))==(fault!=0));
 }
}
TEST_CASE("Nobles accounting receipts cannot carry pages or hide uncertainty") {
 for(auto outcome:{m::NoblesOutcome::Applied,m::NoblesOutcome::Unknown,m::NoblesOutcome::Stale,m::NoblesOutcome::Rejected})for(int fault=0;fault<2;++fault){
  flatbuffers::FlatBufferBuilder b;auto rows=b.CreateVector(std::vector<flatbuffers::Offset<m::NoblesRow>>{});
  auto payload=m::CreateNoblesState(b,outcome,fault?11:0,0,0,rows);
  m::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(m::ManagementAction::NoblesAccounting);
  state.add_status(outcome==m::NoblesOutcome::Applied?m::ManagementStatus::Ok:m::ManagementStatus::Rejected);state.add_nobles(payload);b.Finish(state.Finish());
  CHECK(bool(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())))==bool(fault));
 }
}
TEST_CASE("Nobles draft requests bind their base and only reference earlier NEW slots") {
 for(int fault=0;fault<8;++fault){flatbuffers::FlatBufferBuilder b;
  m::NoblesOffice key(7,2,fault==3?42:-1,fault==1 || fault==3?1:0);
  auto choice=m::CreateNoblesChoice(b,&key,-1,fault==4?-2:10);
  auto choices=b.CreateVector(std::vector<flatbuffers::Offset<m::NoblesChoice>>{choice});
  auto q=m::CreateNoblesRequest(b,0,32,fault==2?0:11,choices,fault==5?&key:nullptr,fault==6?1:0);
  m::ConstructionRequestBuilder r(b);r.add_client_id(1);r.add_seq(1);r.add_world_epoch(1);
  r.add_action(fault==7?m::ManagementAction::PlacesRead:m::ManagementAction::NoblesRead);r.add_nobles(q);b.Finish(r.Finish());
  CHECK(bool(m::validateConstructionRequest(*flatbuffers::GetRoot<m::ConstructionRequest>(b.GetBufferPointer())))==(fault!=0));
 }
}
TEST_CASE("Nobles candidate continuation binds both office and candidate order") {
 for(int fault=0;fault<6;++fault){flatbuffers::FlatBufferBuilder b;
  m::NoblesOffice key(7,2,-1,fault==4?1:0);
  auto q=m::CreateNoblesRequest(b,1,32,fault==1?0:11,0,fault==2?nullptr:&key,fault==3?0:12);
  m::ConstructionRequestBuilder r(b);r.add_client_id(1);r.add_seq(1);r.add_world_epoch(1);
  r.add_action(fault==5?m::ManagementAction::NoblesRead:m::ManagementAction::NoblesCandidates);r.add_nobles(q);b.Finish(r.Finish());
  CHECK(bool(m::validateConstructionRequest(*flatbuffers::GetRoot<m::ConstructionRequest>(b.GetBufferPointer())))==(fault!=0));
 }
}
TEST_CASE("Nobles commit cannot be disguised as a paged read") {
 for(int fault=0;fault<6;++fault){flatbuffers::FlatBufferBuilder b;
  m::NoblesOffice key(7,2,42,0);
  auto choice=m::CreateNoblesChoice(b,&key,10,-1);
  std::vector<flatbuffers::Offset<m::NoblesChoice>> entries;if(fault!=1)entries.push_back(choice);
  auto q=m::CreateNoblesRequest(b,fault==2?1:0,fault==3?64:32,fault==4?0:11,b.CreateVector(entries),fault==5?&key:nullptr);
  m::ConstructionRequestBuilder r(b);r.add_client_id(1);r.add_seq(1);r.add_world_epoch(1);r.add_action(m::ManagementAction::NoblesCommit);r.add_nobles(q);b.Finish(r.Finish());
  CHECK(bool(m::validateConstructionRequest(*flatbuffers::GetRoot<m::ConstructionRequest>(b.GetBufferPointer())))==(fault!=0));
 }
}
TEST_CASE("Nobles candidate pages validate native captions and positive distinct skills") {
 for(int fault=0;fault<9;++fault){flatbuffers::FlatBufferBuilder b;
  auto text=b.CreateString("fixture");auto empty=b.CreateString("");
  std::vector<flatbuffers::Offset<m::NoblesCandidateSkill>> skills;
  skills.push_back(m::CreateNoblesCandidateSkill(b,fault==1?-1:4,fault==2?0:7,text));
  if(fault==3)skills.push_back(m::CreateNoblesCandidateSkill(b,4,8,text));
  auto candidate=m::CreateNoblesCandidate(b,fault==4?-1:10,7,text,fault==5?text:empty,b.CreateVector(skills));
  auto rows=b.CreateVector(std::vector<flatbuffers::Offset<m::NoblesRow>>{});
  std::vector<flatbuffers::Offset<m::NoblesCandidate>> entries{candidate};if(fault==6)entries.push_back(candidate);
  m::NoblesOffice key(7,2,-1,0);
  auto payload=m::CreateNoblesState(b,m::NoblesOutcome::None,11,entries.size(),0,rows,fault==7?nullptr:&key,fault==8?0:12,b.CreateVector(entries));
  m::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(m::ManagementAction::NoblesCandidates);state.add_status(m::ManagementStatus::Ok);state.add_nobles(payload);b.Finish(state.Finish());
  CHECK(bool(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())))==(fault!=0));
 }
}
TEST_CASE("Nobles NEW slots remain distinct and existing assignments cannot carry slots") {
 for(int fault=0;fault<3;++fault){flatbuffers::FlatBufferBuilder b;
  auto text=b.CreateString("fixture");auto zero=b.CreateVector(std::vector<int32_t>(4,0));
  std::vector<flatbuffers::Offset<m::NoblesRow>> rows;
  for(uint32_t slot:{0u,1u})rows.push_back(m::CreateNoblesRow(b,7,2,fault==2?42:-1,-1,-1,0,text,text,text,true,false,zero,zero,zero,zero,-1,-1,0,0,fault==1?0:slot));
  auto payload=m::CreateNoblesState(b,m::NoblesOutcome::None,11,2,0,b.CreateVector(rows));
  m::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(m::ManagementAction::NoblesRead);state.add_status(m::ManagementStatus::Ok);state.add_nobles(payload);b.Finish(state.Finish());
  CHECK(bool(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())))==(fault!=0));
 }
}
TEST_CASE("Nobles commit receipts distinguish unknown effects from successful application") {
 for(auto outcome:{m::NoblesOutcome::Applied,m::NoblesOutcome::Unknown,m::NoblesOutcome::Stale,m::NoblesOutcome::Rejected})for(int fault=0;fault<3;++fault){
  flatbuffers::FlatBufferBuilder b;auto rows=b.CreateVector(std::vector<flatbuffers::Offset<m::NoblesRow>>{});
  auto payload=m::CreateNoblesState(b,outcome,fault==1?11:0,0,0,rows);
  m::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(fault==2?m::ManagementAction::NoblesRead:m::ManagementAction::NoblesCommit);
  state.add_status(outcome==m::NoblesOutcome::Applied?m::ManagementStatus::Ok:m::ManagementStatus::Rejected);state.add_nobles(payload);b.Finish(state.Finish());
  const bool bad=fault==1 || (fault==2 && (outcome==m::NoblesOutcome::Applied || outcome==m::NoblesOutcome::Unknown));
  CHECK(bool(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())))==bad);
 }
}
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

TEST_CASE("Nobles help validates holder-only facts, colors and shared page budget") {
 for(int fault=0;fault<8;++fault){flatbuffers::FlatBufferBuilder b;
  auto text=b.CreateString("fixture");auto empty=b.CreateString("");
  auto part=m::CreateNoblesAssessmentHelp(b,text,empty,fault==2?5:15);
  auto parts=b.CreateVector(std::vector<flatbuffers::Offset<m::NoblesAssessmentHelp>>(fault==1?3:4,part));
  auto item=m::CreateNoblesObligationHelp(b,text,fault==3?11:6);
  auto items=b.CreateVector(std::vector<flatbuffers::Offset<m::NoblesObligationHelp>>{item});
  auto accounting=m::CreateNoblesAccountingHelp(b,fault==4?5:0,fault==5?5:0,text,text,text,empty);
  auto help=m::CreateNoblesHelp(b,text,parts,parts,items,items,accounting);b.Finish(help);
  size_t bytes=fault==7?384*1024:0;
  CHECK(bool(m::validateNoblesHelp(*flatbuffers::GetRoot<m::NoblesHelp>(b.GetBufferPointer()),fault!=6,bytes))==(fault!=0));
 }
}
