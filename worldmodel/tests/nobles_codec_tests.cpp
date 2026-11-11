#include <doctest.h>
#include "management_codecs.h"
#include "management_util.h"
namespace m=df3d::mirror;
namespace codec=wm::detail::management;
TEST_CASE("Nobles draft requests retain slot and candidate identities") {
 wm::ManagementRequest q;q.action=wm::ManagementAction::NoblesCandidates;
 q.nobles.expectedListRevision=123;q.nobles.offset=4;q.nobles.limit=4;
 q.nobles.choices.push_back({{7,2,-1,0},-1,10});
 q.nobles.target=wm::NoblesOffice{7,2,-1,1};q.nobles.expectedCandidateRevision=456;
 flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,11,12,13);
 const auto* r=flatbuffers::GetRoot<m::ConstructionRequest>(b.GetBufferPointer());
 REQUIRE_FALSE(m::validateConstructionRequest(*r));REQUIRE(r->nobles());
 CHECK(r->nobles()->target()->draft_slot()==1);CHECK(r->nobles()->expected_candidate_revision()==456);
 REQUIRE(r->nobles()->choices()->size()==1);const auto* choice=r->nobles()->choices()->Get(0);
 CHECK(choice->target()->assignment_id()==-1);CHECK(choice->target()->draft_slot()==0);
 CHECK(choice->expected_unit_id()==-1);CHECK(choice->unit_id()==10);
 b.Clear();q.action=wm::ManagementAction::NoblesCommit;q.nobles.offset=0;q.nobles.limit=32;
 q.nobles.target.reset();q.nobles.expectedCandidateRevision=0;codec::encodeRequest(b,q,11,12,14);
 r=flatbuffers::GetRoot<m::ConstructionRequest>(b.GetBufferPointer());
 REQUIRE_FALSE(m::validateConstructionRequest(*r));CHECK(r->action()==m::ManagementAction::NoblesCommit);
 CHECK(r->nobles()->expected_list_revision()==123);CHECK(r->nobles()->choices()->Get(0)->unit_id()==10);
}
TEST_CASE("Nobles candidate text and artwork outlive reply storage") {
 flatbuffers::FlatBufferBuilder b;auto text=b.CreateString("fixture");auto empty=b.CreateString("");
 auto look=m::CreateSelectionAppearance(b,b.CreateVector(std::vector<flatbuffers::Offset<flatbuffers::String>>{text}),b.CreateVector(std::vector<flatbuffers::Offset<flatbuffers::String>>{}),b.CreateVectorOfStructs(std::vector<m::AppearanceLayer>{m::AppearanceLayer(0,1,2,1,1,65535,0,0,0,0)}));
 auto skill=m::CreateNoblesCandidateSkill(b,2,3,text);
 auto candidate=m::CreateNoblesCandidate(b,10,42,text,empty,b.CreateVector(std::vector{skill}),look);
 m::NoblesOffice target(7,2,-1,1);
 auto payload=m::CreateNoblesState(b,m::NoblesOutcome::None,123,1,0,b.CreateVector(std::vector<flatbuffers::Offset<m::NoblesRow>>{}),&target,456,b.CreateVector(std::vector{candidate}));
 m::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(m::ManagementAction::NoblesCandidates);state.add_status(m::ManagementStatus::Ok);state.add_nobles(payload);b.Finish(state.Finish());
 REQUIRE_FALSE(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())));
 const auto owned=codec::decodeState(flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer()));b.Clear();
 REQUIRE(owned.nobles);REQUIRE(owned.nobles->target);CHECK(owned.nobles->target->draftSlot==1);
 CHECK(owned.nobles->candidateRevision==456);REQUIRE(owned.nobles->candidates.size()==1);
 const auto& v=owned.nobles->candidates[0];CHECK(v.unitId==10);CHECK(v.value==42);CHECK(v.caption=="fixture");CHECK(v.noSkills.empty());
 REQUIRE(v.skills.size()==1);CHECK(v.skills[0].id==2);CHECK(v.skills[0].rating==3);CHECK(v.skills[0].caption=="fixture");
 REQUIRE(v.appearance);CHECK(v.appearance->tilePages[0]=="fixture");
}
TEST_CASE("Nobles request retains continuation identity") {
 wm::ManagementRequest q;q.action=wm::ManagementAction::NoblesRead;q.nobles={4,4,123};
 flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,11,12,13);
 const auto* r=flatbuffers::GetRoot<m::ConstructionRequest>(b.GetBufferPointer());
 REQUIRE_FALSE(m::validateConstructionRequest(*r));REQUIRE(r->nobles());
 CHECK(r->nobles()->offset()==4);CHECK(r->nobles()->limit()==4);CHECK(r->nobles()->expected_list_revision()==123);
}
TEST_CASE("Nobles decoded assessments and names outlive reply storage") {
 flatbuffers::FlatBufferBuilder b;auto text=b.CreateString("fixture");auto values=b.CreateVector(std::vector<int32_t>{1,2,3,4});
 auto look=m::CreateSelectionAppearance(b,b.CreateVector(std::vector<flatbuffers::Offset<flatbuffers::String>>{text}),b.CreateVector(std::vector<flatbuffers::Offset<flatbuffers::String>>{}),b.CreateVectorOfStructs(std::vector<m::AppearanceLayer>{m::AppearanceLayer(0,1,2,1,1,65535,0,0,0,0)}));
 auto part=m::CreateNoblesAssessmentHelp(b,text,text,15);
 auto parts=b.CreateVector(std::vector<flatbuffers::Offset<m::NoblesAssessmentHelp>>(4,part));
 auto item=m::CreateNoblesObligationHelp(b,text,6);
 auto items=b.CreateVector(std::vector<flatbuffers::Offset<m::NoblesObligationHelp>>{item});
 auto account=m::CreateNoblesAccountingHelp(b,2,1,text,text,text,text);
 auto help=m::CreateNoblesHelp(b,text,parts,parts,items,items,account);
 auto row=m::CreateNoblesRow(b,7,2,42,10,11,9,text,text,text,true,true,values,values,values,values,2,3,look,help);
 auto payload=m::CreateNoblesState(b,m::NoblesOutcome::None,123,2,1,b.CreateVector(std::vector{row}));
 m::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(m::ManagementAction::NoblesRead);state.add_status(m::ManagementStatus::Ok);state.add_nobles(payload);b.Finish(state.Finish());
 REQUIRE_FALSE(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())));
 const auto owned=codec::decodeState(flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer()));b.Clear();
 REQUIRE(owned.nobles);CHECK(owned.nobles->listRevision==123);CHECK(owned.nobles->offset==1);REQUIRE(owned.nobles->rows.size()==1);
 const auto& v=owned.nobles->rows[0];CHECK(v.title=="fixture");CHECK(v.squadCaption=="fixture");CHECK(v.holderCaption=="fixture");
 CHECK(v.entityId==7);CHECK(v.positionId==2);CHECK(v.assignmentId==42);CHECK(v.unitId==10);CHECK(v.nemesisId==11);CHECK(v.priority==9);
 REQUIRE(v.help);CHECK(v.help->rooms[0].actual=="fixture");CHECK(v.help->furniture[3].required=="fixture");CHECK(v.help->demands[0].color==6);REQUIRE(v.help->accounting);CHECK(v.help->accounting->setting==2);
 REQUIRE(v.appearance);CHECK(v.appearance->tilePages[0]=="fixture");
 CHECK(v.canAppoint);CHECK(v.hasRoomAssessment);CHECK(v.requiredRooms[3]==4);CHECK(v.actualRooms[2]==3);
 CHECK(v.requiredFurniture[1]==2);CHECK(v.actualFurniture[0]==1);CHECK(v.demandStatus==2);CHECK(v.mandateStatus==3);
}
