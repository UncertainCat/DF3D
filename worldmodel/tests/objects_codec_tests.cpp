#include <doctest.h>
#include "management_codecs.h"
#include "management_util.h"
namespace m=df3d::mirror;
namespace codec=wm::detail::management;
TEST_CASE("Objects request codec preserves continuation and navigation identity") {
 for(bool locate:{false,true}){
  wm::ManagementRequest q;q.action=locate?wm::ManagementAction::ObjectsLocate:wm::ManagementAction::ObjectsRead;
  q.objects.tab=3;q.objects.expectedListRevision=123;
  if(locate)q.objects.artifactId=42;else{q.objects.offset=16;q.objects.limit=16;}
  flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,11,12,13);
  const auto* request=flatbuffers::GetRoot<m::ConstructionRequest>(b.GetBufferPointer());
  REQUIRE_FALSE(m::validateConstructionRequest(*request));const auto* r=request->objects();REQUIRE(r);
  CHECK(r->tab()==3);CHECK(r->expected_list_revision()==123);
  CHECK(r->offset()==(locate?0:16));CHECK(r->limit()==(locate?32:16));CHECK(r->artifact_id()==(locate?42:-1));
 }
}
TEST_CASE("Objects rows own captions and artwork after source bytes are replaced") {
 flatbuffers::FlatBufferBuilder b;
 auto original=b.CreateString("synthetic original"),translated=b.CreateString("synthetic translation"),owner=b.CreateString("synthetic owner");
 const auto material=b.CreateString("SYNTHETIC_MATERIAL"),subtype=b.CreateString("SYNTHETIC_SUBTYPE"),color=b.CreateString("SYNTHETIC_COLOR");
 const auto art=m::CreateItemInspectionAppearance(b,material,subtype,color,1,32);const m::TilePos pos(4,5,6);
 const auto row=m::CreateObjectsRow(b,42,43,original,translated,owner,&pos,art,36);
 const auto payload=m::CreateObjectsState(b,m::ObjectsOutcome::None,2,123,33,32,b.CreateVector(std::vector{row}));
 m::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(m::ManagementAction::ObjectsRead);
 state.add_status(m::ManagementStatus::Ok);state.add_objects(payload);b.Finish(state.Finish());
 const auto* wire=flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer());REQUIRE_FALSE(m::validateManagementState(*wire));
 const auto owned=codec::decodeState(wire);
 std::fill(b.GetBufferPointer(),b.GetBufferPointer()+b.GetSize(),uint8_t(0));b.Clear();
 REQUIRE(owned.objects);const auto& r=*owned.objects;CHECK(r.tab==2);CHECK(r.listRevision==123);CHECK(r.total==33);CHECK(r.offset==32);
 REQUIRE(r.rows.size()==1);const auto& v=r.rows[0];CHECK(v.artifactId==42);CHECK(v.itemId==43);
 CHECK(v.nativeName=="synthetic original");CHECK(v.translatedName=="synthetic translation");CHECK(v.ownership=="synthetic owner");
 REQUIRE(v.position);CHECK(v.position->x==4);CHECK(v.position->z==6);
 REQUIRE(v.appearance);CHECK(v.itemType==36);CHECK(v.appearance->materialToken=="SYNTHETIC_MATERIAL");CHECK(v.appearance->subtypeRaw=="SYNTHETIC_SUBTYPE");CHECK(v.appearance->colorToken=="SYNTHETIC_COLOR");
 CHECK_FALSE(r.destination);
}
TEST_CASE("Objects lookup preserves unavailable destination and typed stale refusal") {
 for(int mode=0;mode<3;++mode){flatbuffers::FlatBufferBuilder b;const m::TilePos pos(4,5,6);
  auto target=m::CreateObjectsDestination(b,42,43,mode==1?&pos:nullptr);
  auto payload=m::CreateObjectsState(b,mode==2?m::ObjectsOutcome::Stale:m::ObjectsOutcome::None,1,mode==2?0:123,0,0,
    b.CreateVector(std::vector<flatbuffers::Offset<m::ObjectsRow>>{}),mode==2?0:target);
  m::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(m::ManagementAction::ObjectsLocate);
  state.add_status(mode==2?m::ManagementStatus::Rejected:m::ManagementStatus::Ok);state.add_objects(payload);b.Finish(state.Finish());
  const auto* wire=flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer());REQUIRE_FALSE(m::validateManagementState(*wire));
  const auto owned=codec::decodeState(wire);b.Clear();REQUIRE(owned.objects);CHECK(owned.objects->rows.empty());
  if(mode==2){CHECK(owned.objects->outcome==wm::ObjectsOutcome::Stale);CHECK_FALSE(owned.objects->destination);}
  else{REQUIRE(owned.objects->destination);const auto& d=*owned.objects->destination;CHECK(d.artifactId==42);CHECK(d.itemId==43);
    CHECK(bool(d.position)==(mode==1));if(d.position)CHECK(d.position->y==5);}
 }
}
