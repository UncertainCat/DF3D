#include <doctest.h>
#include "management_util.h"
namespace m=df3d::mirror;
TEST_CASE("Tasks requests reject stale-page and edit shape errors") {
 for(bool edit:{false,true})for(int fault=0;fault<6;++fault){
  flatbuffers::FlatBufferBuilder b;
  m::TasksRequestBuilder q(b);
  if(edit){q.add_job_id(42);q.add_building_id(7);q.add_expected_revision(fault==1?0:11);
   q.add_operation(fault==2?m::TasksOperation::RemoveWorker:m::TasksOperation::Suspend);
   q.add_expected_state(fault==3?2:0);if(fault==4)q.add_offset(1);
  }else {q.add_limit(fault==1?65:32);if(fault==2)q.add_offset(1);
   if(fault==3)q.add_job_id(42);if(fault==4)q.add_expected_state(0);
  }
  const auto payload=q.Finish();m::ConstructionRequestBuilder request(b);
  request.add_client_id(1);request.add_seq(1);request.add_world_epoch(1);
  request.add_action(edit?m::ManagementAction::TasksApply:m::ManagementAction::TasksRead);
  if(fault!=5)request.add_tasks(payload);b.Finish(request.Finish());
  CHECK(bool(m::validateConstructionRequest(*flatbuffers::GetRoot<m::ConstructionRequest>(b.GetBufferPointer())))==(fault!=0));
 }
}
TEST_CASE("Tasks pages enforce ownership progress uniqueness and payload budget") {
 for(int fault=0;fault<8;++fault){
  flatbuffers::FlatBufferBuilder b;const auto empty=b.CreateString("");
  const auto caption=b.CreateString(fault==7?std::string(16384,'x'):"fixture");
  std::vector<flatbuffers::Offset<m::TasksRow>> rows;
  const int count=fault==7?32:fault==1?2:fault==3?0:1;
  for(int i=0;i<count;++i){m::TasksRowBuilder row(b);row.add_job_id(fault==1?42:42+i);
   row.add_revision(fault==4?0:11);row.add_caption(caption);row.add_worker_name(empty);row.add_building_caption(empty);
   if(fault==5)row.add_worker_id(1);if(fault==6)row.add_can_cancel(true);rows.push_back(row.Finish());}
  const auto payload=m::CreateTasksState(b,m::TasksOutcome::None,1,fault==3?1:count,fault==2?2:0,b.CreateVector(rows));
  m::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(m::ManagementAction::TasksRead);
  state.add_status(m::ManagementStatus::Ok);state.add_tasks(payload);b.Finish(state.Finish());
  CHECK(bool(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())))==(fault!=0));
 }
}
TEST_CASE("Tasks unknown mutation receipts cannot masquerade as read success") {
 for(int fault=0;fault<3;++fault){flatbuffers::FlatBufferBuilder b;
  const auto rows=b.CreateVector(std::vector<flatbuffers::Offset<m::TasksRow>>{});
  const auto payload=m::CreateTasksState(b,m::TasksOutcome::Unknown,0,0,0,rows,42);
  m::ManagementStateBuilder state(b);state.add_revision(1);
  state.add_action(fault==1?m::ManagementAction::TasksRead:m::ManagementAction::TasksApply);
  state.add_status(fault==2?m::ManagementStatus::Ok:m::ManagementStatus::Rejected);state.add_tasks(payload);b.Finish(state.Finish());
  CHECK(bool(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())))==(fault!=0));
 }
}
