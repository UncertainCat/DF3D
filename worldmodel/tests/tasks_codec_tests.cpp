#include <doctest.h>
#include "management_codecs.h"
namespace m=df3d::mirror;
namespace codec=wm::detail::management;
TEST_CASE("Tasks model requests retain page identity and all edit preconditions") {
 for(int mode=0;mode<5;++mode){
  wm::ManagementRequest q;q.action=mode?wm::ManagementAction::TasksApply:wm::ManagementAction::TasksRead;
  if(!mode){q.tasks.offset=32;q.tasks.limit=16;q.tasks.expectedListRevision=123;}
  else {q.tasks.jobId=42;q.tasks.workerId=9;q.tasks.buildingId=7;q.tasks.expectedRevision=456;
   q.tasks.operation=wm::TasksOperation(mode-1);q.tasks.expectedState=mode<=2?1:-1;}
  flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,11,12,13);
  const auto* request=flatbuffers::GetRoot<m::ConstructionRequest>(b.GetBufferPointer());
  REQUIRE_FALSE(m::validateConstructionRequest(*request));const auto* r=request->tasks();REQUIRE(r);
  CHECK(r->offset()==q.tasks.offset);CHECK(r->limit()==q.tasks.limit);CHECK(r->expected_list_revision()==q.tasks.expectedListRevision);
  CHECK(r->job_id()==q.tasks.jobId);CHECK(r->worker_id()==q.tasks.workerId);CHECK(r->building_id()==q.tasks.buildingId);
  CHECK(r->expected_revision()==q.tasks.expectedRevision);CHECK(int(r->operation())==int(q.tasks.operation));CHECK(r->expected_state()==q.tasks.expectedState);
 }
}
TEST_CASE("Tasks model owns decoded text color positions and artwork after reply retirement") {
 flatbuffers::FlatBufferBuilder b;const auto text=b.CreateString("fixture"),empty=b.CreateString("");
 const auto color=m::CreateAreaNameColor(b,3,0,1,3,0,0,1);
 const auto pages=b.CreateVector(std::vector{b.CreateString("SYNTHETIC_TASK")});
 const auto palettes=b.CreateVector(std::vector<flatbuffers::Offset<flatbuffers::String>>{});
 const auto layers=b.CreateVectorOfStructs(std::vector<m::AppearanceLayer>{{0,2,3,1,1,65535,-1,-1,0,0}});
 const auto art=m::CreateSelectionAppearance(b,pages,palettes,layers);const m::TilePos position(4,5,6);
 m::TasksRowBuilder row(b);row.add_job_id(42);row.add_worker_id(9);row.add_building_id(7);row.add_revision(456);
 row.add_caption(text);row.add_worker_name(text);row.add_building_caption(empty);row.add_worker_color(color);
 row.add_worker_position(&position);row.add_can_suspend(true);row.add_suspended(true);row.add_worker_appearance(art);row.add_building_appearance(art);
 const auto r=row.Finish();const auto payload=m::CreateTasksState(b,m::TasksOutcome::None,123,33,32,b.CreateVector(std::vector{r}));
 m::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(m::ManagementAction::TasksRead);state.add_status(m::ManagementStatus::Ok);state.add_tasks(payload);b.Finish(state.Finish());
 const auto* wire=flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer());REQUIRE_FALSE(m::validateManagementState(*wire));
 const auto owned=codec::decodeState(wire);b.Clear();REQUIRE(owned.tasks);CHECK(owned.tasks->listRevision==123);CHECK(owned.tasks->offset==32);CHECK(owned.tasks->total==33);
 REQUIRE(owned.tasks->rows.size()==1);const auto& v=owned.tasks->rows[0];CHECK(v.caption=="fixture");CHECK(v.workerName=="fixture");CHECK(v.buildingCaption.empty());
 REQUIRE(v.workerPosition);CHECK(v.workerPosition->x==4);CHECK_FALSE(v.buildingPosition);REQUIRE(v.workerColor);CHECK(v.workerColor->effect==1);
 CHECK(v.canSuspend);CHECK(v.suspended);CHECK_FALSE(v.canCancel);CHECK(v.revision==456);
 REQUIRE(v.workerAppearance);REQUIRE(v.buildingAppearance);CHECK(v.workerAppearance->tilePages[0]=="SYNTHETIC_TASK");CHECK(v.buildingAppearance->layers[0].tileX==2);
}
TEST_CASE("Tasks unknown receipts retain the target without fabricating a list") {
 flatbuffers::FlatBufferBuilder b;const auto rows=b.CreateVector(std::vector<flatbuffers::Offset<m::TasksRow>>{});
 const auto payload=m::CreateTasksState(b,m::TasksOutcome::Unknown,0,0,0,rows,42);
 m::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(m::ManagementAction::TasksApply);state.add_status(m::ManagementStatus::Rejected);state.add_tasks(payload);b.Finish(state.Finish());
 const auto* wire=flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer());REQUIRE_FALSE(m::validateManagementState(*wire));
 const auto owned=codec::decodeState(wire);REQUIRE(owned.tasks);CHECK(owned.tasks->outcome==wm::TasksOutcome::Unknown);CHECK(owned.tasks->jobId==42);CHECK(owned.tasks->rows.empty());CHECK(owned.tasks->listRevision==0);
}
