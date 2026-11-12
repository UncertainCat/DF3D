#include <doctest.h>
#include "management_util.h"
namespace m=df3d::mirror;
static auto candidateDisplay(flatbuffers::FlatBufferBuilder& b) {
 auto name=b.CreateString("synthetic name"),label=b.CreateString("synthetic witness label"),empty=b.CreateString("");
 return m::CreateJusticeCandidateDisplay(b,28,name,m::CreateAreaNameColor(b,4,0,1,6,0,0,1),39,label,10,empty);
}

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
  rows.push_back(m::CreateJusticeCandidateRow(b,42,39,true,false,candidateDisplay(b)));
  rows.push_back(m::CreateJusticeCandidateRow(b,fault==1?42:43,0,false,true,candidateDisplay(b)));
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

TEST_CASE("Justice candidate display rejects malformed bounds and colors") {
 for(int fault=0;fault<8;++fault){flatbuffers::FlatBufferBuilder b;
  auto name=b.CreateString(fault==1?std::string(16385,'x'):"synthetic"),empty=b.CreateString("");
  auto color=m::CreateAreaNameColor(b,fault==2?8:4,0,0,4,0,0,fault==3?4:0);
  auto display=m::CreateJusticeCandidateDisplay(b,fault==4?2:fault==5?2049:28,name,color,fault==6?1048577:0,empty,fault==7?16:6,empty);
  auto row=m::CreateJusticeCandidateRow(b,42,0,false,false,display);
  auto page=m::CreateJusticeCandidatePage(b,9,8,1,0,b.CreateVector(std::vector{row}));
  auto result=m::CreateJusticeState(b,m::JusticeOutcome::None,0,7,0,0,b.CreateVector(std::vector<flatbuffers::Offset<m::JusticeCaseRow>>{}),0,page);
  m::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(m::ManagementAction::JusticeCandidatesRead);
  state.add_status(m::ManagementStatus::Ok);state.add_justice(result);b.Finish(state.Finish());
  CHECK(bool(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())))==(fault!=0));
 }
}

TEST_CASE("Justice sort scope permits shared repeated directions and rejects malformed priorities") {
 for(int fault=0;fault<6;++fault){flatbuffers::FlatBufferBuilder b;
  std::vector<flatbuffers::Offset<m::JusticeSort>> sorts;
  if(fault!=1){sorts.push_back(m::CreateJusticeSort(b,m::JusticeCandidateColumn::Name,true));
   sorts.push_back(m::CreateJusticeSort(b,fault==2?m::JusticeCandidateColumn(4):m::JusticeCandidateColumn::Name,fault!=3));}
  if(fault==4)sorts.resize(65537,sorts[0]);
  auto q=m::CreateJusticeRequest(b,0,0,32,7,9,8,0,0,-1,b.CreateVector(sorts));
  m::ConstructionRequestBuilder request(b);request.add_client_id(1);request.add_seq(1);request.add_world_epoch(1);
  request.add_action(fault==5?m::ManagementAction::JusticeCaseRead:m::ManagementAction::JusticeCandidatesRead);request.add_justice(q);b.Finish(request.Finish());
  CHECK(bool(m::validateConstructionRequest(*flatbuffers::GetRoot<m::ConstructionRequest>(b.GetBufferPointer())))==(fault!=0));
 }
}

TEST_CASE("Justice candidate artwork validates page references and preserves absence") {
 for(int fault=0;fault<5;++fault){flatbuffers::FlatBufferBuilder b;
  auto names=b.CreateVector(std::vector<flatbuffers::Offset<flatbuffers::String>>(fault==4?256:1,b.CreateString(fault==4?std::string(256,'x'):"synthetic-page")));
  auto icon=m::CreateSelectionAppearance(b,names,b.CreateVector(std::vector<flatbuffers::Offset<flatbuffers::String>>{}),
   b.CreateVectorOfStructs(std::vector<m::AppearanceLayer>{m::AppearanceLayer(fault==1?1:0,1,2,fault==2?0:1,1,65535,0,0,0,0)}));
  auto empty=b.CreateString("");auto display=m::CreateJusticeCandidateDisplay(b,28,empty,m::CreateAreaNameColor(b),0,empty,6,empty);
  auto row=m::CreateJusticeCandidateRow(b,42,0,false,false,display,fault==3?0:icon);
  std::vector<flatbuffers::Offset<m::JusticeCandidateRow>> rows{row};
  if(fault==4)for(int id=43;id<48;++id)rows.push_back(m::CreateJusticeCandidateRow(b,id,0,false,false,display,icon));
  auto page=m::CreateJusticeCandidatePage(b,9,8,uint32_t(rows.size()),0,b.CreateVector(rows));
  auto result=m::CreateJusticeState(b,m::JusticeOutcome::None,0,7,0,0,b.CreateVector(std::vector<flatbuffers::Offset<m::JusticeCaseRow>>{}),0,page);
  m::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(m::ManagementAction::JusticeCandidatesRead);
  state.add_status(m::ManagementStatus::Ok);state.add_justice(result);b.Finish(state.Finish());
  CHECK(bool(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())))==(fault==1 || fault==2 || fault==4));
 }
}

TEST_CASE("Justice interrogation binds explicit mode and expected checkbox state") {
 for(auto action:{m::ManagementAction::JusticeCandidatesRead,m::ManagementAction::JusticeConvict,m::ManagementAction::JusticeInterrogate})
 for(bool mode:{false,true})for(bool selected:{false,true}) {
  flatbuffers::FlatBufferBuilder b;
  const bool read=action==m::ManagementAction::JusticeCandidatesRead;
  auto q=m::CreateJusticeRequest(b,0,0,32,7,9,8,b.CreateString(""),9,read?-1:42,0,mode,selected);
  m::ConstructionRequestBuilder r(b);r.add_client_id(1);r.add_seq(1);r.add_world_epoch(1);r.add_action(action);r.add_justice(q);b.Finish(r.Finish());
  const bool valid=action==m::ManagementAction::JusticeInterrogate?mode:!selected && (read || !mode);
  CHECK(bool(m::validateConstructionRequest(*flatbuffers::GetRoot<m::ConstructionRequest>(b.GetBufferPointer())))==!valid);
 }
}

TEST_CASE("Justice guard requests cannot carry case or mutation state") {
 for(int fault=0;fault<8;++fault){flatbuffers::FlatBufferBuilder b;
  auto q=m::CreateJusticeRequest(b,fault==1?0:3,fault==2?1:0,32,0,fault==3?9:-1,fault==4?8:0,b.CreateString(""),fault==5?9:0,fault==6?42:-1,0,fault==7);
  m::ConstructionRequestBuilder r(b);r.add_client_id(1);r.add_seq(1);r.add_world_epoch(1);r.add_action(m::ManagementAction::JusticeGuardRead);r.add_justice(q);b.Finish(r.Finish());
  CHECK(bool(m::validateConstructionRequest(*flatbuffers::GetRoot<m::ConstructionRequest>(b.GetBufferPointer())))==(fault!=0));
 }
}
TEST_CASE("Justice guard replies reject mixed pages and duplicate identities") {
 for(int fault=0;fault<5;++fault){flatbuffers::FlatBufferBuilder b;
  auto empty=b.CreateString("");auto color=m::CreateAreaNameColor(b);auto row=m::CreateJusticeUnitRow(b,42,2000,empty,empty,color);
  auto other=m::CreateJusticeUnitRow(b,fault==2?42:43,1000,empty,empty,color);
  auto guard=m::CreateJusticeGuardPage(b,empty,fault==3?16:12,b.CreateVector(std::vector{row,other}));
  auto payload=m::CreateJusticeState(b,m::JusticeOutcome::None,fault==1?0:3,9,2,0,b.CreateVector(std::vector<flatbuffers::Offset<m::JusticeCaseRow>>{}),0,0,guard);
  m::ManagementStateBuilder r(b);r.add_revision(1);r.add_action(fault==4?m::ManagementAction::JusticeRead:m::ManagementAction::JusticeGuardRead);r.add_status(m::ManagementStatus::Ok);r.add_justice(payload);b.Finish(r.Finish());
  CHECK(bool(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())))==(fault!=0));
 }
}

TEST_CASE("Convicts detail requires target and list receipt, and excludes crime sorting") {
 for(int fault=0;fault<6;++fault){flatbuffers::FlatBufferBuilder b;
  auto sort=m::CreateJusticeSort(b,fault==3?m::JusticeCandidateColumn::Crime:m::JusticeCandidateColumn::Category);
  auto q=m::CreateJusticeRequest(b,4,0,32,fault==1?0:7,fault==4?9:-1,0,b.CreateString(""),0,fault==2?-1:42,b.CreateVector(std::vector{sort}),fault==5);
  m::ConstructionRequestBuilder r(b);r.add_client_id(1);r.add_seq(1);r.add_world_epoch(1);r.add_action(m::ManagementAction::JusticeConvictDetailRead);r.add_justice(q);b.Finish(r.Finish());
  CHECK(bool(m::validateConstructionRequest(*flatbuffers::GetRoot<m::ConstructionRequest>(b.GetBufferPointer())))==(fault!=0));
 }
}

TEST_CASE("Intelligence detail binds index to receipt and rejects case selectors") {
 for(int fault=0;fault<5;++fault){flatbuffers::FlatBufferBuilder b;
  m::JusticeRequestBuilder q(b);q.add_tab(5);q.add_limit(32);q.add_report_index(0);q.add_text_columns(fault==1?0:112);q.add_expected_list_revision(fault==2?0:7);if(fault==3)q.add_crime_id(9);auto request=q.Finish();
  m::ConstructionRequestBuilder r(b);r.add_client_id(1);r.add_seq(1);r.add_world_epoch(1);r.add_action(fault==4?m::ManagementAction::JusticeRead:m::ManagementAction::JusticeIntelligenceRead);r.add_justice(request);b.Finish(r.Finish());
  CHECK(bool(m::validateConstructionRequest(*flatbuffers::GetRoot<m::ConstructionRequest>(b.GetBufferPointer())))==(fault!=0));
 }
}
