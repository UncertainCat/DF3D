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

TEST_CASE("Justice interrogation request retains comparison state") {
 wm::ManagementRequest r;r.action=wm::ManagementAction::JusticeInterrogate;
 auto& q=r.justice;q.crimeId=9;q.unitId=42;q.expectedListRevision=7;q.expectedCaseRevision=8;q.expectedCandidateRevision=9;
 q.interrogate=true;q.expectedSelected=true;
 flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,1,1);
 const auto* request=flatbuffers::GetRoot<m::ConstructionRequest>(b.GetBufferPointer());
 REQUIRE_FALSE(m::validateConstructionRequest(*request));CHECK(request->justice()->interrogate());CHECK(request->justice()->expected_selected());
}

TEST_CASE("Justice guard codec owns rows after wire storage is retired") {
 flatbuffers::FlatBufferBuilder b;
 auto row=m::CreateJusticeUnitRow(b,42,2000,b.CreateString("synthetic name"),b.CreateString("synthetic profession"),m::CreateAreaNameColor(b));
 auto guard=m::CreateJusticeGuardPage(b,b.CreateString("synthetic capacity"),12,b.CreateVector(std::vector{row}));
 auto result=m::CreateJusticeState(b,m::JusticeOutcome::None,3,7,1,0,b.CreateVector(std::vector<flatbuffers::Offset<m::JusticeCaseRow>>{}),0,0,guard);
 m::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(m::ManagementAction::JusticeGuardRead);state.add_status(m::ManagementStatus::Ok);state.add_justice(result);b.Finish(state.Finish());
 const auto* wire=flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer());REQUIRE_FALSE(m::validateManagementState(*wire));
 const auto owned=codec::decodeState(wire);std::fill(b.GetBufferPointer(),b.GetBufferPointer()+b.GetSize(),uint8_t(0));b.Clear();
 REQUIRE(owned.justice);REQUIRE(owned.justice->guard);const auto& page=*owned.justice->guard;
 CHECK(page.caption=="synthetic capacity");CHECK(page.color==12);REQUIRE(page.rows.size()==1);
 CHECK(page.rows[0].unitId==42);CHECK(page.rows[0].rank==2000);CHECK(page.rows[0].firstLine=="synthetic name");CHECK(page.rows[0].secondLine=="synthetic profession");
 CHECK_FALSE(page.rows[0].sheetIcon);CHECK_FALSE(page.rows[0].position);
}

TEST_CASE("Convict details own sentence, officer and crime text after buffer retirement") {
 flatbuffers::FlatBufferBuilder b;
 auto c=m::CreateJusticeConvictCrime(b,9,b.CreateString("synthetic crime"),b.CreateString("synthetic victim"));
 auto d=m::CreateJusticeConvictDetail(b,42,11,b.CreateVector(std::vector{b.CreateString("synthetic sentence")}),b.CreateString("synthetic officer"),1,0,b.CreateVector(std::vector{c}));
 auto result=m::CreateJusticeState(b,m::JusticeOutcome::None,4,7,0,0,b.CreateVector(std::vector<flatbuffers::Offset<m::JusticeCaseRow>>{}),0,0,0,0,d);
 m::ManagementStateBuilder s(b);s.add_revision(1);s.add_action(m::ManagementAction::JusticeConvictDetailRead);s.add_status(m::ManagementStatus::Ok);s.add_justice(result);b.Finish(s.Finish());
 const auto* wire=flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer());REQUIRE_FALSE(m::validateManagementState(*wire));const auto owned=codec::decodeState(wire);
 std::fill(b.GetBufferPointer(),b.GetBufferPointer()+b.GetSize(),uint8_t(0));b.Clear();REQUIRE(owned.justice);REQUIRE(owned.justice->convictDetail);
 const auto& v=*owned.justice->convictDetail;CHECK(v.unitId==42);CHECK(v.revision==11);REQUIRE(v.sentence.size()==1);CHECK(v.sentence[0]=="synthetic sentence");REQUIRE(v.officer);CHECK(*v.officer=="synthetic officer");REQUIRE(v.crimes.size()==1);CHECK(v.crimes[0].caption=="synthetic crime");REQUIRE(v.crimes[0].injuredParty);CHECK(*v.crimes[0].injuredParty=="synthetic victim");
}

TEST_CASE("Intelligence detail owns lines after wire retirement") {
 flatbuffers::FlatBufferBuilder b;
 auto p=m::CreateJusticeIntelligencePage(b,0,112,b.CreateVector(std::vector<flatbuffers::Offset<m::JusticeIntelligenceReport>>{}),b.CreateVector(std::vector{b.CreateString("synthetic report")}));
 auto result=m::CreateJusticeState(b,m::JusticeOutcome::None,5,7,1,0,b.CreateVector(std::vector<flatbuffers::Offset<m::JusticeCaseRow>>{}),0,0,0,0,0,p);
 m::ManagementStateBuilder s(b);s.add_revision(1);s.add_action(m::ManagementAction::JusticeIntelligenceRead);s.add_status(m::ManagementStatus::Ok);s.add_justice(result);b.Finish(s.Finish());
 const auto* wire=flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer());REQUIRE_FALSE(m::validateManagementState(*wire));const auto owned=codec::decodeState(wire);std::fill(b.GetBufferPointer(),b.GetBufferPointer()+b.GetSize(),uint8_t(0));b.Clear();
 REQUIRE(owned.justice);REQUIRE(owned.justice->intelligence);CHECK(owned.justice->intelligence->lines==std::vector<std::string>{"synthetic report"});
}

TEST_CASE("Intelligence graph decoding owns names and cross-page references") {
 flatbuffers::FlatBufferBuilder b;auto none=b.CreateVector(std::vector<int32_t>{});
 auto row=m::CreateJusticeGraphActor(b,907,-1,b.CreateString("synthetic actor"),b.CreateVector(std::vector<int32_t>{42}),0,none,b.CreateVector(std::vector<int32_t>{0}));
 auto graph=m::CreateJusticeGraphPage(b,m::JusticeGraphKind::Actors,1,1,1,0,b.CreateVector(std::vector{row}),b.CreateVector(std::vector<flatbuffers::Offset<m::JusticeGraphOrganization>>{}),b.CreateVector(std::vector<flatbuffers::Offset<m::JusticeGraphPlot>>{}),b.CreateVector(std::vector<flatbuffers::Offset<m::JusticeGraphNode>>{}));
 auto rows=b.CreateVector(std::vector<flatbuffers::Offset<m::JusticeCaseRow>>{});
 m::JusticeStateBuilder j(b);j.add_tab(5);j.add_list_revision(33);j.add_total(1);j.add_rows(rows);j.add_graph(graph);auto result=j.Finish();
 m::ManagementStateBuilder r(b);r.add_revision(1);r.add_action(m::ManagementAction::JusticeIntelligenceGraphRead);r.add_status(m::ManagementStatus::Ok);r.add_justice(result);b.Finish(r.Finish());
 auto owned=codec::decodeState(flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer()));
 std::fill(b.GetBufferPointer(),b.GetBufferPointer()+b.GetSize(),uint8_t(0));b.Clear();
 REQUIRE(owned.justice);REQUIRE(owned.justice->graph);const auto& page=*owned.justice->graph;
 CHECK(page.kind==wm::JusticeGraphKind::Actors);CHECK(page.organizationCount==1);REQUIRE(page.actors.size()==1);
 CHECK(page.actors[0].name=="synthetic actor");CHECK(page.actors[0].historicalFigure==907);CHECK(page.actors[0].aliases==std::vector<int32_t>{42});CHECK(page.actors[0].plots==std::vector<int32_t>{0});
}
