#include <doctest.h>
#include "management_codecs.h"
#include "management_util.h"
namespace m=df3d::mirror;
static auto candidateDisplay(flatbuffers::FlatBufferBuilder& b) {
 auto name=b.CreateString("synthetic name"),label=b.CreateString("synthetic witness label"),empty=b.CreateString("");
 return m::CreateJusticeCandidateDisplay(b,28,name,m::CreateAreaNameColor(b,4,0,1,6,0,0,1),39,label,10,empty);
}

namespace codec=wm::detail::management;
TEST_CASE("Justice candidate and conviction codecs retain query, target and all revisions") {
 for(bool apply:{false,true}){
  wm::ManagementRequest q;q.action=apply?wm::ManagementAction::JusticeConvict:wm::ManagementAction::JusticeCandidatesRead;
  q.justice.crimeId=9;q.justice.expectedListRevision=123;q.justice.expectedCaseRevision=456;
  q.justice.expectedCandidateRevision=789;q.justice.query="synthetic query";
  q.justice.unitId=apply?42:-1;q.justice.offset=apply?0:32;
  q.justice.sorts={{wm::JusticeCandidateColumn::Name,true},{wm::JusticeCandidateColumn::Crime,false},{wm::JusticeCandidateColumn::Name,true}};
  flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,11,12,13);
  const auto* wire=flatbuffers::GetRoot<m::ConstructionRequest>(b.GetBufferPointer());
  REQUIRE_FALSE(m::validateConstructionRequest(*wire));const auto* r=wire->justice();REQUIRE(r);
  CHECK(r->crime_id()==9);CHECK(r->expected_list_revision()==123);CHECK(r->expected_case_revision()==456);
  REQUIRE(r->sorts());REQUIRE(r->sorts()->size()==3);CHECK(r->sorts()->Get(0)->column()==m::JusticeCandidateColumn::Name);
  CHECK(r->sorts()->Get(0)->reverse());CHECK(r->sorts()->Get(1)->column()==m::JusticeCandidateColumn::Crime);CHECK_FALSE(r->sorts()->Get(1)->reverse());CHECK(r->sorts()->Get(2)->reverse());
  CHECK(r->expected_candidate_revision()==789);CHECK(r->unit_id()==(apply?42:-1));CHECK(r->query()->str()==q.justice.query);
 }
}
TEST_CASE("Justice candidate decode owns native order and distinct flags") {
 flatbuffers::FlatBufferBuilder b;
 auto icon=m::CreateSelectionAppearance(b,b.CreateVector(std::vector<flatbuffers::Offset<flatbuffers::String>>{b.CreateString("synthetic-page")}),b.CreateVector(std::vector<flatbuffers::Offset<flatbuffers::String>>{}),b.CreateVectorOfStructs(std::vector<m::AppearanceLayer>{m::AppearanceLayer(0,1,2,1,1,65535,0,0,0,0)}));
 auto first=m::CreateJusticeCandidateRow(b,42,39,true,false,candidateDisplay(b),icon),second=m::CreateJusticeCandidateRow(b,9,0,false,true,candidateDisplay(b));
 auto candidates=m::CreateJusticeCandidatePage(b,19,789,34,32,b.CreateVector(std::vector{first,second}));
 auto payload=m::CreateJusticeState(b,m::JusticeOutcome::None,0,123,0,0,b.CreateVector(std::vector<flatbuffers::Offset<m::JusticeCaseRow>>{}),0,candidates);
 m::ManagementStateBuilder s(b);s.add_revision(1);s.add_action(m::ManagementAction::JusticeCandidatesRead);
 s.add_status(m::ManagementStatus::Ok);s.add_justice(payload);b.Finish(s.Finish());
 const auto* wire=flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer());REQUIRE_FALSE(m::validateManagementState(*wire));
 const auto owned=codec::decodeState(wire);std::fill(b.GetBufferPointer(),b.GetBufferPointer()+b.GetSize(),uint8_t(0));b.Clear();
 REQUIRE(owned.justice);REQUIRE(owned.justice->candidates);const auto& page=*owned.justice->candidates;
 CHECK(page.crimeId==19);CHECK(page.revision==789);CHECK(page.total==34);CHECK(page.offset==32);REQUIRE(page.rows.size()==2);
 CHECK(page.rows[0].unitId==42);CHECK(page.rows[0].rank==39);CHECK(page.rows[0].interrogationPending);CHECK_FALSE(page.rows[0].counterintelligence);
 CHECK(page.rows[1].unitId==9);CHECK(page.rows[1].rank==0);CHECK_FALSE(page.rows[1].interrogationPending);CHECK(page.rows[1].counterintelligence);
 const auto& display=page.rows[0].display;CHECK(display.columns==28);CHECK(display.name=="synthetic name");
 CHECK(display.witnessCount==39);CHECK(display.witnessLabel=="synthetic witness label");CHECK(display.witnessColor==10);CHECK(display.deceased.empty());
 CHECK(display.nameColor.color==std::array<uint8_t,3>{4,0,1});CHECK(display.nameColor.alternate==std::array<uint8_t,3>{6,0,0});CHECK(display.nameColor.effect==1);
 REQUIRE(page.rows[0].sheetIcon);CHECK(page.rows[0].sheetIcon->tilePages==std::vector<std::string>{"synthetic-page"});
 REQUIRE(page.rows[0].sheetIcon->layers.size()==1);CHECK(page.rows[0].sheetIcon->layers[0].tileY==2);CHECK_FALSE(page.rows[1].sheetIcon);
 CHECK_FALSE(owned.justice->detail);CHECK(owned.justice->rows.empty());
}
TEST_CASE("Justice mutation decode preserves applied and unknown without candidate data") {
 for(auto outcome:{m::JusticeOutcome::Applied,m::JusticeOutcome::Rejected,m::JusticeOutcome::Stale,m::JusticeOutcome::Unknown}){
  flatbuffers::FlatBufferBuilder b;
  auto payload=m::CreateJusticeState(b,outcome,0,0,0,0,b.CreateVector(std::vector<flatbuffers::Offset<m::JusticeCaseRow>>{}));
  m::ManagementStateBuilder s(b);s.add_revision(1);s.add_action(m::ManagementAction::JusticeConvict);
  s.add_status(outcome==m::JusticeOutcome::Applied?m::ManagementStatus::Ok:m::ManagementStatus::Rejected);s.add_justice(payload);b.Finish(s.Finish());
  const auto* wire=flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer());REQUIRE_FALSE(m::validateManagementState(*wire));
  const auto owned=codec::decodeState(wire);REQUIRE(owned.justice);
  CHECK(owned.justice->outcome==wm::JusticeOutcome(outcome));CHECK_FALSE(owned.justice->candidates);CHECK_FALSE(owned.justice->detail);CHECK(owned.justice->rows.empty());
 }
}
TEST_CASE("Justice request codecs preserve both pagination identities") {
 for(bool detail:{false,true}){
  wm::ManagementRequest q;q.action=detail?wm::ManagementAction::JusticeCaseRead:wm::ManagementAction::JusticeRead;
  q.justice.tab=2;q.justice.offset=32;q.justice.limit=16;q.justice.expectedListRevision=123;
  if(detail){q.justice.crimeId=9;q.justice.expectedCaseRevision=456;}
  flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,11,12,13);
  const auto* wire=flatbuffers::GetRoot<m::ConstructionRequest>(b.GetBufferPointer());
  REQUIRE_FALSE(m::validateConstructionRequest(*wire));const auto* r=wire->justice();REQUIRE(r);
  CHECK(r->tab()==2);CHECK(r->offset()==32);CHECK(r->limit()==16);CHECK(r->expected_list_revision()==123);
  CHECK(r->crime_id()==(detail?9:-1));CHECK(r->expected_case_revision()==(detail?456:0));CHECK_FALSE(wire->objects());
 }
}
TEST_CASE("Justice decode owns captions and keeps case and witness ordering") {
 for(bool detail:{false,true})for(bool injured:{false,true}){
  flatbuffers::FlatBufferBuilder b;
  auto first=b.CreateString("synthetic first"),second=b.CreateString("synthetic second"),empty=b.CreateString("");
  auto event=b.CreateString("synthetic event date"),reported=b.CreateString("synthetic reported date");
  std::vector<flatbuffers::Offset<m::JusticeCaseRow>> rows;
  flatbuffers::Offset<m::JusticeCaseDetail> d;
  if(detail){
   auto a=m::CreateJusticeWitnessRow(b,second,empty,event,reported);
   auto z=m::CreateJusticeWitnessRow(b,first,second,reported,event);
   d=m::CreateJusticeCaseDetail(b,9,456,first,injured?second:0,second,34,32,b.CreateVector(std::vector{a,z}),injured?m::JusticeCaseResolution::Convicted:m::JusticeCaseResolution::Unsolved);
  }else{
   rows.push_back(m::CreateJusticeCaseRow(b,19,second));rows.push_back(m::CreateJusticeCaseRow(b,9,first));
  }
  auto payload=m::CreateJusticeState(b,m::JusticeOutcome::None,2,123,detail?0:34,detail?0:32,b.CreateVector(rows),d);
  m::ManagementStateBuilder s(b);s.add_revision(1);s.add_action(detail?m::ManagementAction::JusticeCaseRead:m::ManagementAction::JusticeRead);
  s.add_status(m::ManagementStatus::Ok);s.add_justice(payload);b.Finish(s.Finish());
  const auto* wire=flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer());REQUIRE_FALSE(m::validateManagementState(*wire));
  const auto owned=codec::decodeState(wire);
  std::fill(b.GetBufferPointer(),b.GetBufferPointer()+b.GetSize(),uint8_t(0));b.Clear();
  REQUIRE(owned.justice);const auto& r=*owned.justice;CHECK(r.tab==2);CHECK(r.listRevision==123);CHECK_FALSE(owned.objects);
  if(detail){REQUIRE(r.detail);CHECK(r.rows.empty());const auto& v=*r.detail;
   CHECK(v.resolution==(injured?wm::JusticeCaseResolution::Convicted:wm::JusticeCaseResolution::Unsolved));CHECK(v.crimeId==9);CHECK(v.revision==456);CHECK(v.caption=="synthetic first");CHECK(v.status=="synthetic second");
   CHECK(bool(v.injuredParty)==injured);if(injured)CHECK(*v.injuredParty=="synthetic second");
   CHECK(v.total==34);CHECK(v.offset==32);REQUIRE(v.witnesses.size()==2);
   CHECK(v.witnesses[0].witness=="synthetic second");CHECK(v.witnesses[0].description.empty());
   CHECK(v.witnesses[0].date=="synthetic event date");CHECK(v.witnesses[0].reported=="synthetic reported date");
   CHECK(v.witnesses[1].witness=="synthetic first");CHECK(v.witnesses[1].description=="synthetic second");
   CHECK(v.witnesses[1].date=="synthetic reported date");CHECK(v.witnesses[1].reported=="synthetic event date");
  }else{CHECK_FALSE(r.detail);CHECK(r.total==34);CHECK(r.offset==32);REQUIRE(r.rows.size()==2);
   CHECK(r.rows[0].crimeId==19);CHECK(r.rows[0].caption=="synthetic second");CHECK(r.rows[1].crimeId==9);CHECK(r.rows[1].caption=="synthetic first");}
 }
}
TEST_CASE("Justice refusal decoding does not retain prior detail") {
 for(auto outcome:{m::JusticeOutcome::Rejected,m::JusticeOutcome::Stale}){
  flatbuffers::FlatBufferBuilder b;
  auto payload=m::CreateJusticeState(b,outcome,1,0,0,0,b.CreateVector(std::vector<flatbuffers::Offset<m::JusticeCaseRow>>{}));
  m::ManagementStateBuilder s(b);s.add_revision(1);s.add_action(m::ManagementAction::JusticeCaseRead);
  s.add_status(m::ManagementStatus::Rejected);s.add_justice(payload);b.Finish(s.Finish());
  const auto* wire=flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer());REQUIRE_FALSE(m::validateManagementState(*wire));
  const auto owned=codec::decodeState(wire);REQUIRE(owned.justice);const auto& r=*owned.justice;
  CHECK(r.outcome==wm::JusticeOutcome(outcome));CHECK(r.rows.empty());CHECK_FALSE(r.detail);CHECK(r.listRevision==0);
 }
}
