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
 auto row=m::CreatePlacesRow(b,7,&pos,text,text,text,text,text,text,text,2,3);
 auto payload=m::CreatePlacesState(b,m::PlacesOutcome::None,5,123,2,1,b.CreateVector(std::vector{row}));
 m::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(m::ManagementAction::PlacesRead);
 state.add_status(m::ManagementStatus::Ok);state.add_places(payload);b.Finish(state.Finish());
 const auto owned=codec::decodeState(flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer()));b.Clear();
 REQUIRE(owned.places);CHECK(owned.places->tab==5);CHECK(owned.places->listRevision==123);
 CHECK(owned.places->offset==1);REQUIRE(owned.places->rows.size()==1);const auto& v=owned.places->rows[0];
 CHECK(v.buildingId==7);CHECK(v.name=="fixture");CHECK(v.statusOverlay=="fixture");CHECK(v.operatorCaption=="fixture");
 CHECK(v.additionalJobs==2);CHECK(v.siegeAction==3);REQUIRE(v.position);CHECK(v.position->z==14);
}
