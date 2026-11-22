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
  r.add_schema_version(fault==1?m::kManagementVersion-1:m::kManagementVersion);
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

TEST_CASE("Pet mutations require exact observed target and revision") {
 for(int kind=0;kind<3;++kind)for(int action=0;action<7;++action)for(uint64_t revision:{uint64_t(0),uint64_t(7),UINT64_MAX}) {
  flatbuffers::FlatBufferBuilder b;
  auto target=m::CreateCreatureListIdentity(b,m::CreatureListKind(kind),42);
  auto edit=m::CreatePetActionRequest(b,target,revision,m::PetAction(action),true);
  m::ConstructionRequestBuilder r(b);r.add_client_id(1);r.add_seq(1);r.add_world_epoch(1);
  r.add_action(m::ManagementAction::PetActionApply);r.add_pet_action(edit);b.Finish(r.Finish());
  const bool valid=kind<2 && action<6 && action!=3 && (kind==0 || action==1) && revision==7;
  CHECK(bool(m::validateConstructionRequest(*flatbuffers::GetRoot<m::ConstructionRequest>(b.GetBufferPointer())))==!valid);
 }
}
TEST_CASE("Trainer selection separates generic modes from individual identity") {
 for(int mode=0;mode<5;++mode)for(int trainer:{-2,-1,42}) {
  flatbuffers::FlatBufferBuilder b;
  auto edit=m::CreatePetTrainerRequest(b,7,1,m::PetTrainerMode(mode),trainer);
  m::ConstructionRequestBuilder r(b);r.add_client_id(1);r.add_seq(1);r.add_world_epoch(1);
  r.add_action(m::ManagementAction::PetTrainerApply);r.add_pet_trainer(edit);b.Finish(r.Finish());
  const bool valid=mode<4 && (mode==3?trainer>=0:trainer==-1);
  CHECK(bool(m::validateConstructionRequest(*flatbuffers::GetRoot<m::ConstructionRequest>(b.GetBufferPointer())))==!valid);
 }
}
TEST_CASE("Dead rows do not gain live navigation and item identity remains separate") {
 for(int fault=0;fault<7;++fault) {
  flatbuffers::FlatBufferBuilder b;const auto text=b.CreateString("name"),empty=b.CreateString("");
  const auto color=m::CreateAreaNameColor(b);
  const auto activity=m::CreatePetCaption(b,empty,7);
  const m::TilePos position(1,2,3);
  m::CreatureListRowBuilder row(b);row.add_id(42);row.add_kind(fault==1?m::CreatureListKind::Item:m::CreatureListKind::Unit);
  row.add_first_line(text);row.add_second_line(empty);row.add_name_color(color);row.add_activity(activity);
  if(fault==2)row.add_position(&position);if(fault==3)row.add_can_inspect(true);
  auto value=row.Finish();std::vector<flatbuffers::Offset<m::CreatureListRow>> rows{value};
  if(fault==4)rows.push_back(value);
  const auto payload=m::CreateCreatureListRowsState(b,fault==5?m::CreatureListTab::Other:m::CreatureListTab::Dead,b.CreateVector(rows));
  m::ManagementStateBuilder s(b);s.add_revision(1);s.add_action(fault==6?m::ManagementAction::CreatureListQuery:m::ManagementAction::CreatureListRowsRead);
  s.add_status(m::ManagementStatus::Ok);s.add_creature_list_rows(payload);b.Finish(s.Finish());
  CHECK(bool(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())))==(fault!=0));
 }
}
TEST_CASE("Pet outcomes never report unknown application as success") {
 for(int outcome=0;outcome<6;++outcome)for(bool success:{false,true}) {
  flatbuffers::FlatBufferBuilder b;auto target=m::CreateCreatureListIdentity(b,m::CreatureListKind::Unit,7);
  auto edit=m::CreatePetEditState(b,target,m::PetOutcome(outcome));
  m::ManagementStateBuilder s(b);s.add_revision(1);s.add_action(m::ManagementAction::PetActionApply);
  s.add_status(success?m::ManagementStatus::Ok:m::ManagementStatus::Rejected);s.add_pet_edit(edit);b.Finish(s.Finish());
  CHECK(bool(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())))==!(outcome<5 && success==(outcome==0)));
 }
}
TEST_CASE("Knowledge continuation requires a receipt") {
 for(int fault=0;fault<4;++fault) {
  flatbuffers::FlatBufferBuilder b;
  auto read=m::CreatePetKnowledgeRequest(b,fault==1?0:7,64,fault==2?0:fault==3?65:64);
  m::ConstructionRequestBuilder r(b);r.add_client_id(1);r.add_seq(1);r.add_world_epoch(1);
  r.add_action(m::ManagementAction::PetKnowledgeRead);r.add_pet_knowledge(read);b.Finish(r.Finish());
  CHECK(bool(m::validateConstructionRequest(*flatbuffers::GetRoot<m::ConstructionRequest>(b.GetBufferPointer())))==(fault!=0));
 }
}
TEST_CASE("Trainer heading and native warning captions retain bounded source text") {
 for(int fault=0;fault<5;++fault) {
  flatbuffers::FlatBufferBuilder b;
  auto header=b.CreateString(fault==1?"":fault==2?std::string(4097,'x'):"native heading fixture");
  auto first=b.CreateString("trainer"),empty=b.CreateString("");
  auto warning=m::CreatePetCaption(b,b.CreateString(fault==4?std::string("bad\0text",8):"warning fixture"),fault==3?8:2,0,true);
  auto color=m::CreateAreaNameColor(b);
  auto row=m::CreatePetTrainerRow(b,12,first,empty,color,0,b.CreateVector(std::vector<flatbuffers::Offset<flatbuffers::String>>{}),warning);
  auto payload=m::CreatePetTrainersState(b,7,1,false,-1,false,false,b.CreateVector(std::vector<int32_t>{12}),b.CreateVector(std::vector{row}),header);
  m::ManagementStateBuilder s(b);s.add_revision(1);s.add_action(m::ManagementAction::PetTrainersRead);
  s.add_status(m::ManagementStatus::Ok);s.add_pet_trainers(payload);b.Finish(s.Finish());
  CHECK(bool(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())))==(fault!=0));
 }
}

TEST_CASE("Pet training captions retain their own bounded semantic group") {
 for(int fault=0;fault<5;++fault) {
  flatbuffers::FlatBufferBuilder b;
  auto caption=m::CreatePetCaption(b,b.CreateString(fault==3?std::string(4097,'x'):"trainer fixture"),fault==2?8:7,0,true);
  auto p=m::CreatePetRowControls(b,1,b.CreateVector(std::vector<flatbuffers::Offset<m::PetCaption>>{}),
    b.CreateVector(std::vector<flatbuffers::Offset<m::PetOwner>>{}),b.CreateVector(std::vector<flatbuffers::Offset<m::PetControl>>{}),
    b.CreateVector(std::vector<flatbuffers::Offset<m::PetCaption>>(fault==4?33:1,caption)));
  b.Finish(p);size_t bytes=0;
  CHECK(m::validPetControls(flatbuffers::GetRoot<m::PetRowControls>(b.GetBufferPointer()),
    fault==1?m::CreatureListKind::Item:m::CreatureListKind::Unit,bytes)==(fault==0));
 }
}
