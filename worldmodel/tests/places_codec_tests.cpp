#include <doctest.h>
#include "management_codecs.h"
#include "management_util.h"
namespace m=df3d::mirror;
namespace codec=wm::detail::management;
TEST_CASE("Places encoding retains selected tab and continuation identity") {
 wm::ManagementRequest q;q.action=wm::ManagementAction::PlacesRead;
 q.places={5,16,16,123};flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,11,12,13);
 const auto* request=flatbuffers::GetRoot<m::ConstructionRequest>(b.GetBufferPointer());
 REQUIRE_FALSE(m::validateConstructionRequest(*request));const auto* r=request->places();REQUIRE(r);
 CHECK(r->tab()==5);CHECK(r->offset()==16);CHECK(r->limit()==16);CHECK(r->expected_list_revision()==123);
}
TEST_CASE("Places decoding owns captions across reply retirement") {
 flatbuffers::FlatBufferBuilder b;const auto text=b.CreateString("fixture");
 const m::TilePos pos(12,13,14);
 auto row=m::CreatePlacesRow(b,7,&pos,text,text,text,text,text,text,text,2,-1,0,42);
 auto payload=m::CreatePlacesState(b,m::PlacesOutcome::None,0,123,2,1,b.CreateVector(std::vector{row}));
 m::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(m::ManagementAction::PlacesRead);
 state.add_status(m::ManagementStatus::Ok);state.add_places(payload);b.Finish(state.Finish());
 const auto owned=codec::decodeState(flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer()));b.Clear();
 REQUIRE(owned.places);CHECK(owned.places->tab==0);CHECK(owned.places->listRevision==123);
 CHECK(owned.places->offset==1);REQUIRE(owned.places->rows.size()==1);const auto& v=owned.places->rows[0];
 CHECK(v.buildingId==7);CHECK(v.name=="fixture");CHECK(v.statusOverlay=="fixture");CHECK(v.operatorCaption=="fixture");
 CHECK(v.additionalJobs==2);CHECK(v.siegeAction==-1);CHECK(v.subtitleLocationId==42);REQUIRE(v.position);CHECK(v.position->z==14);
}

TEST_CASE("Places siege mutation encoding and uncertain receipt retain identity") {
 wm::ManagementRequest q;q.action=wm::ManagementAction::PlacesApply;q.places={5,0,32,17,42,3};
 flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,11,12,13);
 auto* request=flatbuffers::GetRoot<m::ConstructionRequest>(b.GetBufferPointer());
 REQUIRE_FALSE(m::validateConstructionRequest(*request));REQUIRE(request->places());
 CHECK(request->places()->building_id()==42);CHECK(request->places()->siege_action()==3);
 CHECK(request->places()->expected_list_revision()==17);b.Clear();
 auto payload=m::CreatePlacesState(b,m::PlacesOutcome::Unknown,5,0,0,0,
   b.CreateVector(std::vector<flatbuffers::Offset<m::PlacesRow>>{}),42,3);
 m::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(m::ManagementAction::PlacesApply);
 state.add_status(m::ManagementStatus::Rejected);state.add_places(payload);b.Finish(state.Finish());
 REQUIRE_FALSE(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())));
 const auto owned=codec::decodeState(flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer()));b.Clear();
 REQUIRE(owned.places);CHECK(owned.places->outcome==wm::PlacesOutcome::Unknown);
 CHECK(owned.places->buildingId==42);CHECK(owned.places->siegeAction==3);CHECK(owned.places->rows.empty());
}
