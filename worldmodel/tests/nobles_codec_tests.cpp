#include <doctest.h>
#include "management_codecs.h"
#include "management_util.h"
namespace m=df3d::mirror;
namespace codec=wm::detail::management;
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
 auto row=m::CreateNoblesRow(b,7,2,42,10,11,9,text,text,text,true,true,values,values,values,values,2,3,look);
 auto payload=m::CreateNoblesState(b,m::NoblesOutcome::None,123,2,1,b.CreateVector(std::vector{row}));
 m::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(m::ManagementAction::NoblesRead);state.add_status(m::ManagementStatus::Ok);state.add_nobles(payload);b.Finish(state.Finish());
 REQUIRE_FALSE(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())));
 const auto owned=codec::decodeState(flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer()));b.Clear();
 REQUIRE(owned.nobles);CHECK(owned.nobles->listRevision==123);CHECK(owned.nobles->offset==1);REQUIRE(owned.nobles->rows.size()==1);
 const auto& v=owned.nobles->rows[0];CHECK(v.title=="fixture");CHECK(v.squadCaption=="fixture");CHECK(v.holderCaption=="fixture");
 CHECK(v.entityId==7);CHECK(v.positionId==2);CHECK(v.assignmentId==42);CHECK(v.unitId==10);CHECK(v.nemesisId==11);CHECK(v.priority==9);
 REQUIRE(v.appearance);CHECK(v.appearance->tilePages[0]=="fixture");
 CHECK(v.canAppoint);CHECK(v.hasRoomAssessment);CHECK(v.requiredRooms[3]==4);CHECK(v.actualRooms[2]==3);
 CHECK(v.requiredFurniture[1]==2);CHECK(v.actualFurniture[0]==1);CHECK(v.demandStatus==2);CHECK(v.mandateStatus==3);
}
