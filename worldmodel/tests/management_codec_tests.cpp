#include <doctest.h>

#include <algorithm>
#include <iostream>

#include "management_codecs.h"
#include "management_util.h"

namespace codec = wm::detail::management;
namespace wire = df3d::mirror;

TEST_CASE("well bodies preserve native state and reject missing or foreign facts") {
  for(int type:{18,15})for(int status:{-1,0,1,2,3,4,255}) {
    flatbuffers::FlatBufferBuilder b;const auto empty=b.CreateString("");
    const auto body=status<0?flatbuffers::Offset<wire::WellBodySnapshot>{}:wire::CreateWellBodySnapshot(b,static_cast<wire::WellStatus>(status));
    const auto snapshot=wire::CreateBuildingHeaderSnapshot(b,161,type,9007199254740993ULL,1,1,
      empty,b.CreateString("native"),b.CreateString("Native"),false,false,false,0,0,0,0,body);
    const auto header=wire::CreateBuildingHeaderState(b,snapshot);
    wire::ProductionStateBuilder p(b);p.add_building_header(header);const auto payload=p.Finish();
    wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_action(wire::ManagementAction::ProductionInspect);
    root.add_status(wire::ManagementStatus::Ok);root.add_production(payload);b.Finish(root.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    const bool valid=type==18 ? status>=0 && status<=3 : status==-1;
    CAPTURE(type);CAPTURE(status);CHECK(bool(wire::validateManagementState(*value))==!valid);
    if(valid){auto decoded=codec::decodeProduction(value->production());b.Clear();
      REQUIRE(decoded.buildingHeader->snapshot);const auto& well=decoded.buildingHeader->snapshot->well;
      CHECK(well.has_value()==(type==18));if(well)CHECK(int(well->status)==status);}
  }
}

TEST_CASE("machinery bodies reject missing and contradictory authority") {
  for(int type:{33,40,41,42,43,44,50})for(int fault=0;fault<7;++fault) {
    flatbuffers::FlatBufferBuilder b;const auto empty=b.CreateString("");
    const auto body=wire::CreateMachineryBodySnapshot(b,fault==2?-1:1,100,20,
      fault==3?wire::MachineryStatus::NoNetwork:wire::MachineryStatus::Active,true,
      fault==4, type==33?(fault==5?2:0):(fault==5?0:-1),type==33?0:-1);
    const auto snapshot=wire::CreateBuildingHeaderSnapshot(b,220,fault==6?15:type,9007199254740993ULL,1,1,
      empty,b.CreateString("native"),b.CreateString("Native"),false,false,false,0,0,0,fault==1?0:body);
    const auto header=wire::CreateBuildingHeaderState(b,snapshot);
    wire::ProductionStateBuilder p(b);p.add_building_header(header);const auto payload=p.Finish();
    wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_action(wire::ManagementAction::ProductionInspect);
    root.add_status(wire::ManagementStatus::Ok);root.add_production(payload);b.Finish(root.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    const bool valid=fault==0 || (fault==4 && type==40);
    CAPTURE(type);CAPTURE(fault);CHECK(bool(wire::validateManagementState(*value))==!valid);
    if(valid){const auto decoded=codec::decodeProduction(value->production());
      REQUIRE(decoded.buildingHeader->snapshot->machinery);
      CHECK(decoded.buildingHeader->snapshot->revision==9007199254740993ULL);
      CHECK(decoded.buildingHeader->snapshot->machinery->produced==100);
      CHECK(decoded.buildingHeader->snapshot->machinery->pumpManual==(type==33?0:-1));}
  }
}

TEST_CASE("pump settings require explicit intent and header revision") {
  for(int desired:{0,1})for(int fault=0;fault<7;++fault) {
    wm::ManagementRequest r;r.action=wm::ManagementAction::FarmEdit;
    auto& p=r.production;p.buildingId=42;p.buildingHeader=true;p.expectedRevision=9007199254740993ULL;
    p.farmOperation=wm::FarmOperation::PumpManual;p.itemValue=desired;
    if(fault==1)p.buildingHeader=false;if(fault==2)p.itemValue=-1;if(fault==3)p.expectedRevision=0;
    if(fault==4)p.itemId=123;if(fault==5)p.workerId=123;if(fault==6)r.action=wm::ManagementAction::ProductionInspect;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CAPTURE(desired);CAPTURE(fault);CHECK(bool(wire::validateConstructionRequest(*value))==(fault!=0));
    CHECK(value->production()->item_value()==p.itemValue);
  }
}

TEST_CASE("lever intents retain identities and reject mixed or unbound actions") {
  for(int op=0;op<4;++op)for(int fault=0;fault<8;++fault) {
    wm::ManagementRequest r;r.action=op>=2?wm::ManagementAction::ProductionQueue:wm::ManagementAction::ProductionInspect;
    auto& p=r.production;p.buildingId=55;p.expectedRevision=9007199254740993ULL;
    auto& v=p.lever.emplace();v.operation=uint8_t(op);
    if(op==1 || op==3){v.position=std::array<int16_t,3>{97,100,165};v.sourceMechanism=24480;v.targetMechanism=48520;}
    if(op==3)v.targetId=16;
    if(fault==1)p.buildingLinks=true;
    if(fault==2)p.workshopWorkers=true;
    if(fault==3)p.cursor=1;
    if(fault==4)v.operation=4;
    if(fault==5)p.expectedRevision=0;
    if(fault==6)v.targetMechanism=v.sourceMechanism=5;
    if(fault==7)r.action=wm::ManagementAction::FarmEdit;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CAPTURE(op);CAPTURE(fault);CHECK(bool(wire::validateConstructionRequest(*value))==(fault!=0 && !(fault==5 && op==0)));
    REQUIRE(value->production()->lever());CHECK(value->production()->lever()->source_mechanism()==v.sourceMechanism);
    CHECK(value->production()->expected_revision()==p.expectedRevision);
  }
}

TEST_CASE("lever receipts preserve wide revisions and require a job for applied mutations") {
  for(int fault=0;fault<6;++fault) {
    flatbuffers::FlatBufferBuilder b;
    const auto lever=wire::CreateLeverState(b,55,9007199254740993ULL,3,fault==1?0:1,24480,48520,
      b.CreateString("source mechanism"),b.CreateString("target mechanism"),fault==2?-1:16,fault==3?-1:71234);
    wire::ProductionStateBuilder p(b);p.add_lever(lever);if(fault==4)p.add_selected_building(55);const auto prod=p.Finish();
    wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_action(fault==5?wire::ManagementAction::ProductionInspect:wire::ManagementAction::ProductionQueue);
    root.add_status(wire::ManagementStatus::Ok);root.add_production(prod);b.Finish(root.Finish());
    const auto* s=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CAPTURE(fault);CHECK(bool(wire::validateManagementState(*s))==(fault!=0));
    if(!fault){auto result=codec::decodeProduction(s->production());b.Clear();REQUIRE(result.lever);
      CHECK(result.lever->revision==9007199254740993ULL);CHECK(result.lever->targetId==16);CHECK(result.lever->jobId==71234);CHECK(result.lever->sourceName=="source mechanism");}
  }
}

TEST_CASE("building link requests require revision-bound exclusive reads") {
  for(int fault=0;fault<10;++fault) {
    wm::ManagementRequest r;r.action=wm::ManagementAction::ProductionInspect;
    auto& p=r.production;p.buildingLinks=true;p.buildingId=55;p.cursor=64;p.expectedRevision=9007199254740993ULL;
    if(fault==1)p.expectedRevision=0;
    if(fault==2)p.contents=true;
    if(fault==3)p.pendingBuilding=true;
    if(fault==4)p.buildingHeader=true;
    if(fault==5)p.itemId=17;
    if(fault==6)r.action=wm::ManagementAction::FarmEdit;
    if(fault==7)p.cursor=32768;
    if(fault==8)p.taskCategory="mixed";
    if(fault==9)p.farmOperation=wm::FarmOperation::Remove;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CAPTURE(fault);CHECK(bool(wire::validateConstructionRequest(*value))==(fault!=0));
    CHECK(value->production()->building_links());
    CHECK(value->production()->expected_revision()==p.expectedRevision);
  }
}

TEST_CASE("building link pages preserve duplicate targets and reject broken continuations") {
  for(int fault=0;fault<10;++fault) {
    flatbuffers::FlatBufferBuilder b;
    const wire::TilePos position(97,105,fault==6?-1:164);
    std::vector<flatbuffers::Offset<wire::BuildingLinkRow>> rows;
    for(int i=0;i<2;++i)rows.push_back(wire::CreateBuildingLinkRow(b,1588+i,fault==5?34:33,40,9,b.CreateString("dolomite Floodgate"),&position));
    const auto page=wire::CreateBuildingLinksPage(b,55,fault==3?0:9007199254740993ULL,fault!=4,64,fault==1?65:66,fault==2?65:67,b.CreateVector(rows));
    wire::ProductionStateBuilder p(b);p.add_building_links(page);
    if(fault==7)p.add_selected_building(55);
    const auto prod=p.Finish();
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_production(prod);
    state.add_action(fault==8?wire::ManagementAction::FarmEdit:wire::ManagementAction::ProductionInspect);
    state.add_status(fault==9?wire::ManagementStatus::Rejected:wire::ManagementStatus::Ok);
    b.Finish(state.Finish());const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CAPTURE(fault);CHECK(bool(wire::validateManagementState(*value))==(fault!=0));
    if(!fault) {
      const auto decoded=codec::decodeProduction(value->production());REQUIRE(decoded.buildingLinks);
      const auto& result=*decoded.buildingLinks;CHECK(result.revision==9007199254740993ULL);CHECK(result.nextCursor==66);
      REQUIRE(result.rows.size()==2);CHECK(result.rows[0].id==result.rows[1].id);
      CHECK(result.rows[0].itemId!=result.rows[1].itemId);CHECK(result.rows[0].z==164);
      CHECK(result.rows[0].name=="dolomite Floodgate");
    }
  }
}

TEST_CASE("pending header artwork validates native recipe references") {
  for(int fault=0;fault<8;++fault) {
    flatbuffers::FlatBufferBuilder b;
    std::vector<wire::AppearanceLayer> layers;
    if(fault!=1)layers.emplace_back(fault==2?1:0,3,4,1,1,65535,-1,-1,0,0);
    const auto icon=wire::CreateSelectionAppearance(b,b.CreateVectorOfStrings(std::vector<std::string>{"PAGE"}),
      b.CreateVectorOfStrings(std::vector<std::string>{}),b.CreateVectorOfStructs(layers));
    const auto snapshot=wire::CreatePendingBuildingSnapshot(b,965,fault==6?15:23,1,0,1,68196,true,false,b.CreateString("Statue"),false,false,icon,fault==3?-1:fault==4?5:4,fault==5?-1:1,fault==7?-1:0);
    const auto pending=wire::CreatePendingBuildingState(b,snapshot);
    wire::ProductionStateBuilder p(b);p.add_pending_building(pending);const auto prod=p.Finish();
    wire::ManagementStateBuilder s(b);s.add_revision(1);s.add_production(prod);
    s.add_action(wire::ManagementAction::ProductionInspect);s.add_status(wire::ManagementStatus::Ok);b.Finish(s.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(fault!=0));
    if(!fault){const auto decoded=codec::decodeProduction(value->production());
      REQUIRE(decoded.pendingBuilding->snapshot->appearance);CHECK(decoded.pendingBuilding->snapshot->triggerKind==1);
      CHECK(decoded.pendingBuilding->snapshot->appearance->tilePages==std::vector<std::string>{"PAGE"});}
  }
}

TEST_CASE("pending removal and idle snapshots retain distinct authority") {
  for(int operation=0;operation<=3;++operation) {
    wm::ManagementRequest r;r.action=wm::ManagementAction::FarmEdit;
    r.production.pendingBuilding=true;r.production.buildingId=1490;
    r.production.expectedRevision=9007199254740993ULL;r.production.pendingOperation=int8_t(operation);
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK_FALSE(wire::validateConstructionRequest(*value));
    CHECK(value->production()->pending_operation()==operation);
  }
  for(int job:{-2,-1,382797})for(bool removing:{false,true})for(bool suspended:{false,true})for(bool worker:{false,true}) {
    flatbuffers::FlatBufferBuilder b;
    const auto snapshot=wire::CreatePendingBuildingSnapshot(b,1490,4,9007199254740993ULL,
      1,3,job,suspended,worker,b.CreateString("Farm Plot"),removing,true,0,removing?0:3,0,2);
    const auto payload=wire::CreatePendingBuildingState(b,snapshot,wire::FarmEditOutcome::Completed);
    wire::ProductionStateBuilder p(b);p.add_pending_building(payload);const auto prod=p.Finish();
    wire::ManagementStateBuilder s(b);s.add_revision(1);s.add_production(prod);
    s.add_action(wire::ManagementAction::FarmEdit);s.add_status(wire::ManagementStatus::Ok);b.Finish(s.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    const bool invalid=job<-1 || (job==-1 && (removing || suspended || worker));
    CAPTURE(job);CAPTURE(removing);CAPTURE(suspended);CAPTURE(worker);
    CHECK(bool(wire::validateManagementState(*value))==invalid);
    if(!invalid) {
      const auto decoded=codec::decodeProduction(value->production());REQUIRE(decoded.pendingBuilding);
      REQUIRE(decoded.pendingBuilding->snapshot);const auto& result=*decoded.pendingBuilding->snapshot;
      CHECK(result.jobId==job);CHECK(result.removing==removing);CHECK(result.suspended==suspended);
      CHECK(result.hasWorker==worker);CHECK(result.revision==9007199254740993ULL);CHECK(result.forbidden);CHECK(result.progress==(removing?0:3));CHECK(result.triggerKind==0);CHECK(result.triggerLinks==2);
    }
  }
}

TEST_CASE("pending building transport distinguishes observations from retirement") {
  for(bool edit:{false,true})for(int fault=0;fault<9;++fault) {
    wm::ManagementRequest r;r.action=edit?wm::ManagementAction::FarmEdit:wm::ManagementAction::ProductionInspect;
    auto& p=r.production;p.pendingBuilding=true;p.buildingId=965;
    if(edit){p.expectedRevision=9007199254740993ULL;p.pendingOperation=2;}
    if(fault==1)p.buildingId=-1;
    if(fault==2)p.expectedRevision=edit?0:1;
    if(fault==3)p.pendingOperation=edit?4:0;
    if(fault==4)p.doorControls=true;
    if(fault==5)p.contents=true;
    if(fault==6)p.pendingBuilding=false,p.pendingOperation=0;
    if(fault==7)p.taskCategory="mixed";
    if(fault==8)r.action=wm::ManagementAction::ProductionQueue;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CAPTURE(edit);CAPTURE(fault);CHECK(bool(wire::validateConstructionRequest(*value))==(fault!=0));
  }
  for(int mode=0;mode<4;++mode)for(int fault=0;fault<8;++fault) {
    flatbuffers::FlatBufferBuilder b;
    const auto snapshot=wire::CreatePendingBuildingSnapshot(b,965,15,9007199254740993ULL,
      fault==1?1:0,1,68196,true,false,b.CreateString("Platinum Statue"),false,false,0,4,0,0);
    const bool terminal=mode>=2;
    const auto payload=wire::CreatePendingBuildingState(b,terminal?(fault==2?snapshot:0):(fault==2?0:snapshot),
      fault==3?wire::FarmEditOutcome::Unknown:mode==0?wire::FarmEditOutcome::None:wire::FarmEditOutcome::Completed,
      mode==2 || fault==4,mode==3 || fault==4);
    wire::ProductionStateBuilder p(b);p.add_pending_building(payload);if(fault==5)p.add_selected_building(965);
    const auto prod=p.Finish();wire::ManagementStateBuilder s(b);s.add_revision(1);s.add_production(prod);
    s.add_action(fault==6?wire::ManagementAction::ProductionList:mode==0?wire::ManagementAction::ProductionInspect:wire::ManagementAction::FarmEdit);
    s.add_status(fault==7?wire::ManagementStatus::Rejected:wire::ManagementStatus::Ok);b.Finish(s.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CAPTURE(mode);CAPTURE(fault);const bool invalid=fault!=0 && !(fault==1 && terminal);
    CHECK(bool(wire::validateManagementState(*value))==invalid);
    if(!invalid){const auto decoded=codec::decodeProduction(value->production());REQUIRE(decoded.pendingBuilding);
      CHECK(decoded.pendingBuilding->removed==(mode==2));CHECK(decoded.pendingBuilding->removing==(mode==3));
      if(!terminal){REQUIRE(decoded.pendingBuilding->snapshot);CHECK(decoded.pendingBuilding->snapshot->revision==9007199254740993ULL);CHECK(decoded.pendingBuilding->snapshot->headerName=="Platinum Statue");}}
  }
}

TEST_CASE("door control transport separates read and edit authority") {
  for(bool edit:{false,true})for(int fault=0;fault<10;++fault) {
    wm::ManagementRequest r;r.action=edit?wm::ManagementAction::FarmEdit:wm::ManagementAction::ProductionInspect;
    auto& p=r.production;p.doorControls=true;p.buildingId=16;
    if(edit){p.expectedRevision=9007199254740993ULL;p.doorForbidden=1;}
    if(fault==1)p.buildingId=-1;
    if(fault==2)p.expectedRevision=edit?0:1;
    if(fault==3)p.doorForbidden=edit?2:0;
    if(fault==4)p.buildingHeader=true;
    if(fault==5)p.workshopOrders=true;
    if(fault==6)p.contentsItemId=1;
    if(fault==7)p.taskCategory="category";
    if(fault==8)p.doorControls=false,p.doorForbidden=0;
    if(fault==9)r.action=wm::ManagementAction::ProductionQueue;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CAPTURE(edit);CAPTURE(fault);CHECK(bool(wire::validateConstructionRequest(*value))==(fault!=0));
    if(!fault){CHECK(value->production()->door_controls());CHECK(value->production()->expected_revision()==p.expectedRevision);}
  }
  for(bool edit:{false,true})for(int fault=0;fault<7;++fault) {
    flatbuffers::FlatBufferBuilder b;
    const auto snapshot=wire::CreateDoorControlsSnapshot(b,16,fault==1?0:9007199254740993ULL,true,true,true,false,true);
    const auto door=wire::CreateDoorControlsState(b,fault==2?0:snapshot,
      fault==3?wire::FarmEditOutcome::Unknown:edit?wire::FarmEditOutcome::Completed:wire::FarmEditOutcome::None);
    wire::ProductionStateBuilder p(b);p.add_door_controls(door);if(fault==4)p.add_selected_building(16);
    const auto payload=p.Finish();wire::ManagementStateBuilder s(b);s.add_revision(1);s.add_production(payload);
    s.add_action(fault==5?wire::ManagementAction::ProductionList:edit?wire::ManagementAction::FarmEdit:wire::ManagementAction::ProductionInspect);
    s.add_status(fault==6?wire::ManagementStatus::Rejected:wire::ManagementStatus::Ok);b.Finish(s.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CAPTURE(edit);CAPTURE(fault);CHECK(bool(wire::validateManagementState(*value))==(fault!=0));
    if(!fault){const auto decoded=codec::decodeProduction(value->production());REQUIRE(decoded.doorControls);REQUIRE(decoded.doorControls->snapshot);
      CHECK(decoded.doorControls->snapshot->revision==9007199254740993ULL);CHECK(decoded.doorControls->snapshot->forbidden);
      CHECK(decoded.doorControls->snapshot->takenByInvaders);CHECK_FALSE(decoded.doorControls->snapshot->usedByIntruder);CHECK(decoded.doorControls->snapshot->operatedByMechanisms);}
  }
}

TEST_CASE("workshop Move up requires a distinct predecessor and an exclusive job edit") {
  for(int fault=0;fault<10;++fault) {
    wm::ManagementRequest r;r.action=wm::ManagementAction::ProductionJobEdit;
    auto& p=r.production;p.buildingId=4;p.jobId=71;p.expectedPreviousJobId=70;
    if(fault==1)p.expectedPreviousJobId=-2;
    if(fault==2)p.expectedPreviousJobId=71;
    if(fault==3)p.cancel=true;
    if(fault==4)p.repeat=1;
    if(fault==5)p.suspend=1;
    if(fault==6){p.priority=1;p.expectedPriority=0;}
    if(fault==7)r.action=wm::ManagementAction::ProductionInspect;
    if(fault==8)p.jobId=-1;
    if(fault==9)p.expectedPreviousJobId=-1;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(bool(wire::validateConstructionRequest(*value))==(fault!=0));
    CHECK(value->production()->expected_previous_job_id()==p.expectedPreviousJobId);
  }
}
TEST_CASE("legacy production jobs preserve unknown Move up capability") {
  for(int capability:{-1,0,1}) {
    flatbuffers::FlatBufferBuilder b;
    auto caption=b.CreateString("Make bed");
    wire::ProductionJobBuilder row(b);row.add_id(71);row.add_name(caption);
    if(capability>=0)row.add_can_move_up(int8_t(capability));
    auto jobs=b.CreateVector(std::vector<flatbuffers::Offset<wire::ProductionJob>>{row.Finish()});
    wire::ProductionStateBuilder state(b);state.add_jobs(jobs);b.Finish(state.Finish());
    auto decoded=codec::decodeProduction(flatbuffers::GetRoot<wire::ProductionState>(b.GetBufferPointer()));
    REQUIRE(decoded.jobs.size()==1);CHECK(decoded.jobs[0].canMoveUp==capability);
  }
}

TEST_CASE("legacy job activity stays unknown") {
  for(int active:{-1,0,1}) {
    flatbuffers::FlatBufferBuilder b;
    auto caption=b.CreateString("Make bed");wire::ProductionJobBuilder row(b);
    row.add_id(71);row.add_name(caption);if(active>=0)row.add_active(int8_t(active));
    auto jobs=b.CreateVector(std::vector<flatbuffers::Offset<wire::ProductionJob>>{row.Finish()});
    wire::ProductionStateBuilder state(b);state.add_jobs(jobs);b.Finish(state.Finish());
    auto decoded=codec::decodeProduction(flatbuffers::GetRoot<wire::ProductionState>(b.GetBufferPointer()));
    REQUIRE(decoded.jobs.size()==1);CHECK(decoded.jobs[0].active==active);
  }
}
TEST_CASE("workshop Priority intents require a displayed opposite state and no mixed edit") {
  for(int desired:{0,1})for(int fault=0;fault<8;++fault) {
    wm::ManagementRequest r;r.action=wm::ManagementAction::ProductionJobEdit;
    auto& p=r.production;p.buildingId=4;p.jobId=71;p.priority=desired;p.expectedPriority=1-desired;
    if(fault==1)p.expectedPriority=-1;
    if(fault==2)p.expectedPriority=desired;
    if(fault==3)p.priority=2;
    if(fault==4)p.cancel=true;
    if(fault==5)p.repeat=1;
    if(fault==6)r.action=wm::ManagementAction::ProductionInspect;
    if(fault==7)p.priority=-1;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(bool(wire::validateConstructionRequest(*value))==(fault!=0));
    CHECK(value->production()->priority()==p.priority);
    CHECK(value->production()->expected_priority()==p.expectedPriority);
  }
}
TEST_CASE("legacy production jobs do not invent an inactive Priority observation") {
  for(int priority:{-1,0,1}) {
    flatbuffers::FlatBufferBuilder b;
    auto caption=b.CreateString("Make bed");
    wire::ProductionJobBuilder row(b);row.add_id(71);row.add_name(caption);
    if(priority>=0)row.add_priority(int8_t(priority));
    auto jobs=b.CreateVector(std::vector<flatbuffers::Offset<wire::ProductionJob>>{row.Finish()});
    wire::ProductionStateBuilder state(b);state.add_jobs(jobs);b.Finish(state.Finish());
    auto decoded=codec::decodeProduction(flatbuffers::GetRoot<wire::ProductionState>(b.GetBufferPointer()));
    REQUIRE(decoded.jobs.size()==1);CHECK(decoded.jobs[0].priority==priority);
  }
}

TEST_CASE("Job draft requests share bounded artwork semantics and preserve source receipts") {
  for(bool writing:{false,true})for(int fault=0;fault<7;++fault) {
    wm::ManagementRequest r;r.action=writing?wm::ManagementAction::JobSettingsApply:wm::ManagementAction::JobSettingsRead;
    wm::WorkOrderArtRequest art;art.page=6;art.draft.emplace();art.draft->columns=118;
    art.draft->action=writing?wm::WorkOrderArtDraftAction::GenerateName:wm::WorkOrderArtDraftAction::Inspect;
    if(fault==1)art.page=19;
    if(fault==2)art.draft->columns=0;
    if(fault==3)art.draft->action=writing?wm::WorkOrderArtDraftAction::Inspect:wm::WorkOrderArtDraftAction::GenerateName;
    if(fault==4)art.draft->value.elements.push_back({7,-1,-1,1});
    if(writing){auto& q=r.jobSettingsEdit;q.jobId=71;q.buildingId=3;q.unitId=42;q.option=0;q.expectedRevision=fault==5?0:91;q.art=art;if(fault==6)q.choice=0;}
    else {auto& q=r.jobSettings;q.jobId=71;q.buildingId=3;q.unitId=42;q.option=0;q.expectedRevision=fault==5?0:91;q.art=art;if(fault==6)q.query="mixed";}
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(bool(wire::validateConstructionRequest(*value))==(fault!=0));
    const auto* encoded=writing?value->job_settings_edit()->art():value->job_settings()->art();
    REQUIRE(encoded);REQUIRE(encoded->draft());CHECK(encoded->draft()->columns()==art.draft->columns);
  }
}
TEST_CASE("Job draft unknown outcome is explicit and cannot claim success") {
  for(bool ok:{false,true}) {
    flatbuffers::FlatBufferBuilder b;auto edit=wire::CreateJobSettingsEditState(b,71,3,42,wire::JobSettingsEditOutcome::Unknown);
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(wire::ManagementAction::JobSettingsApply);
    state.add_status(ok?wire::ManagementStatus::Ok:wire::ManagementStatus::Rejected);state.add_job_settings_edit(edit);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());CHECK(bool(wire::validateManagementState(*value))==ok);
    if(!ok){auto decoded=codec::decodeState(value);REQUIRE(decoded.jobSettingsEdit);CHECK(decoded.jobSettingsEdit->outcome==wm::JobSettingsEditOutcome::Unknown);}
  }
}

TEST_CASE("Job artwork edit modes preserve authority and reject malformed choices") {
  for(int16_t page:{int16_t(-1),int16_t(0),int16_t(1),int16_t(2),int16_t(3),int16_t(5)}) {
    wm::ManagementRequest base;base.action=wm::ManagementAction::JobSettingsApply;
    base.jobSettingsEdit={71,3,42,0,UINT64_C(9007199254740993),page==0?0u:92u,page<=0?-1:page==5?0:9876,page,page>0?"query":""};
    for(int fault=0;fault<6;++fault) {
      auto r=base;auto& q=r.jobSettingsEdit;
      if(fault==1)q.artPage=6;
      if(fault==2)q.expectedRevision=0;
      if(fault==3)q.query=std::string(129,'x');
      if(fault==4)q.choice=page<=0?0:-1;
      if(fault==5)q.expectedChoicesRevision=page==0?1:0;
      flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
      const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
      CHECK(bool(wire::validateConstructionRequest(*value))==(fault!=0));
      REQUIRE(value->job_settings_edit());CHECK(value->job_settings_edit()->art_page()==q.artPage);CHECK(value->job_settings_edit()->query()->str()==q.query);
    }
  }
}

TEST_CASE("Job artwork reads preserve receipts and reject mixed request fields") {
  wm::ManagementRequest base;base.action=wm::ManagementAction::JobSettingsRead;
  base.jobSettings={42,3,6534,0,"",128,1,UINT64_C(9007199254740993),9876,118};
  for(int fault=0;fault<9;++fault) {
    auto r=base;auto& q=r.jobSettings;
    if(fault==1)q.artPage=-2;
    if(fault==2)q.artPage=6;
    if(fault==3)q.option=-1;
    if(fault==4)q.expectedListRevision=0;
    if(fault==5)q.previewColumns=0;
    if(fault==6)q.cursor=262145;
    if(fault==7)q.artPage=-1;
    if(fault==8)q.hovered=-1;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(bool(wire::validateConstructionRequest(*value))==(fault!=0));
    REQUIRE(value->job_settings());CHECK(value->job_settings()->expected_list_revision()==q.expectedListRevision);
  }
}
TEST_CASE("Job artwork results decode and reject malformed previews") {
  for(int fault=0;fault<7;++fault) {
    flatbuffers::FlatBufferBuilder b;
    const auto row=wire::CreateWorkOrderArtRow(b,9876,b.CreateString("Subject"));
    const auto rows=b.CreateVector(std::vector<flatbuffers::Offset<wire::WorkOrderArtRow>>{row});
    const auto preview=b.CreateVector(std::vector<flatbuffers::Offset<flatbuffers::String>>{b.CreateString("Description")});
    const auto art=wire::CreateWorkOrderArtState(b,fault==1?6:1,b.CreateString("Image information"),rows,fault==2?0:92,1,0,fault==3?9999:9876,fault==4?0:preview);
    const auto option=wire::CreateWorkOrderDetailsOption(b,fault==5?0:1,-1,b.CreateString("Image"));
    const auto options=b.CreateVector(std::vector<flatbuffers::Offset<wire::WorkOrderDetailsOption>>{option});
    const auto empty=b.CreateVector(std::vector<flatbuffers::Offset<wire::JobSettingsChoice>>{});
    const auto job=wire::CreateJobSettingsState(b,42,3,6534,91,b.CreateString("Make statue"),options,0,empty,0,0,0,0,0,0,art);
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(fault==6?wire::ManagementAction::Catalog:wire::ManagementAction::JobSettingsRead);state.add_status(wire::ManagementStatus::Ok);state.add_job_settings(job);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(fault!=0));
    if(!fault){const auto decoded=codec::decodeState(value);REQUIRE(decoded.jobSettings);REQUIRE(decoded.jobSettings->art);CHECK(decoded.jobSettings->art->rows[0].id==9876);REQUIRE(decoded.jobSettings->art->preview);CHECK(decoded.jobSettings->art->preview->at(0)=="Description");}
  }
}

TEST_CASE("Job edits preserve exact authority and reject invalid request bounds") {
  wm::ManagementRequest base;base.action=wm::ManagementAction::JobSettingsApply;
  base.jobSettingsEdit={71,3,42,0,UINT64_C(9007199254740993),INT64_MAX,1};
  for(int variant=0;variant<10;++variant) {
    auto r=base;auto& q=r.jobSettingsEdit;
    if(variant==1)q.jobId=-1;
    if(variant==2)q.buildingId=-1;
    if(variant==3)q.unitId=-2;
    if(variant==4)q.option=-1;
    if(variant==5)q.option=65;
    if(variant==6)q.expectedRevision=0;
    if(variant==7)q.expectedChoicesRevision=UINT64_MAX;
    if(variant==8)q.choice=-1;
    if(variant==9)q.choice=16384;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(bool(wire::validateConstructionRequest(*value))==(variant!=0));
    REQUIRE(value->job_settings_edit());CHECK_FALSE(value->job_settings());
    CHECK(value->job_settings_edit()->expected_revision()==q.expectedRevision);
    CHECK(value->job_settings_edit()->expected_choices_revision()==q.expectedChoicesRevision);
  }
}
TEST_CASE("Job edit outcomes require matching status and retire independently of reads") {
  for(int variant=0;variant<8;++variant) {
    flatbuffers::FlatBufferBuilder b;
    const auto outcome=variant==1?wire::JobSettingsEditOutcome::Stale:variant==2?wire::JobSettingsEditOutcome::Rejected:variant==6?wire::JobSettingsEditOutcome(255):wire::JobSettingsEditOutcome::Applied;
    const auto edit=wire::CreateJobSettingsEditState(b,variant==5?-1:71,3,42,outcome);
    wire::ManagementStateBuilder state(b);state.add_revision(1);
    state.add_action(variant==3?wire::ManagementAction::Catalog:wire::ManagementAction::JobSettingsApply);
    state.add_status(variant==1 || variant==2 || variant==4?wire::ManagementStatus::Rejected:wire::ManagementStatus::Ok);
    if(variant!=7)state.add_job_settings_edit(edit);
    b.Finish(state.Finish());const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(variant>=3));
    if(variant<3) {
      auto decoded=codec::decodeState(value);REQUIRE(decoded.jobSettingsEdit);CHECK_FALSE(decoded.jobSettings);
      CHECK(decoded.jobSettingsEdit->jobId==71);CHECK(decoded.jobSettingsEdit->buildingId==3);CHECK(decoded.jobSettingsEdit->unitId==42);
      CHECK(int(decoded.jobSettingsEdit->outcome)==int(outcome));
      flatbuffers::FlatBufferBuilder empty;wire::ManagementStateBuilder other(empty);other.add_revision(2);other.add_status(wire::ManagementStatus::Ok);empty.Finish(other.Finish());
      decoded=codec::decodeState(flatbuffers::GetRoot<wire::ManagementState>(empty.GetBufferPointer()));CHECK_FALSE(decoded.jobSettingsEdit);
    }
  }
}

TEST_CASE("Residents job targets are optional bounded identities exclusive of event targets") {
  for(int variant=0;variant<5;++variant) {
    flatbuffers::FlatBufferBuilder b;const auto empty=b.CreateString("");const auto color=wire::CreateAreaNameColor(b);
    const auto target=variant?wire::CreateResidentJobTarget(b,variant==2?-1:71,variant==3?-1:3):flatbuffers::Offset<wire::ResidentJobTarget>{};
    const auto event=variant==4?wire::CreateResidentActivityTarget(b,4,5):flatbuffers::Offset<wire::ResidentActivityTarget>{};
    const auto row=wire::CreateResidentRow(b,42,empty,empty,empty,empty,empty,color,empty,7,0,false,{},-1,{},{},nullptr,event,target);
    const auto payload=wire::CreateResidentsRowsState(b,b.CreateVector(std::vector{row}));
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(wire::ManagementAction::ResidentsRowsRead);
    state.add_status(wire::ManagementStatus::Ok);state.add_residents_rows(payload);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(variant>=2));
    if(variant<2) {
      const auto decoded=codec::decodeState(value);const auto& result=decoded.residentsRows->rows[0].jobTarget;
      CHECK(result.has_value()==(variant==1));
      if(result){CHECK(result->jobId==71);CHECK(result->buildingId==3);}
    }
  }
}

TEST_CASE("Residents positions preserve captured signed coordinates and optional absence") {
  for(int variant=0;variant<4;++variant) {
    flatbuffers::FlatBufferBuilder b;const auto empty=b.CreateString("");const auto color=wire::CreateAreaNameColor(b);
    const wire::TilePos position(variant==3?32768:variant==2?-30000:25,31,4);
    const auto row=wire::CreateResidentRow(b,42,empty,empty,empty,empty,empty,color,empty,7,0,false,{},-1,{},{},variant?&position:nullptr);
    const auto payload=wire::CreateResidentsRowsState(b,b.CreateVector(std::vector{row}));
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(wire::ManagementAction::ResidentsRowsRead);
    state.add_status(wire::ManagementStatus::Ok);state.add_residents_rows(payload);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(variant==3));
    if(variant<3) {
      const auto decoded=codec::decodeState(value);const auto& result=decoded.residentsRows->rows[0].position;
      CHECK(result.has_value()==(variant!=0));
      if(result){CHECK(result->x==position.x());CHECK(result->y==31);CHECK(result->z==4);}
    }
  }
}

TEST_CASE("Residents assignment observations preserve absence and validate semantic fields") {
  for(int variant=0;variant<3;++variant) {
    flatbuffers::FlatBufferBuilder b;const auto empty=b.CreateString("");const auto color=wire::CreateAreaNameColor(b);
    flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<wire::LocationStaffAssignment>>> entries;
    if(variant)entries=b.CreateVector(std::vector{wire::CreateLocationStaffAssignment(b,wire::LocationStaffAssignmentKind::WorkDetail,2,3,variant==2?7:-1,-1,b.CreateString("fixture"),empty)});
    const auto row=wire::CreateResidentRow(b,42,empty,empty,empty,empty,empty,color,empty,7,0,false,{},-1,{},entries);
    const auto payload=wire::CreateResidentsRowsState(b,b.CreateVector(std::vector{row}));
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(wire::ManagementAction::ResidentsRowsRead);
    state.add_status(wire::ManagementStatus::Ok);state.add_residents_rows(payload);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(variant==2));
    if(variant<2) {
      const auto decoded=codec::decodeState(value);const auto& result=decoded.residentsRows->rows[0].assignments;
      CHECK(result.has_value()==(variant==1));if(result){CHECK(result->size()==1);CHECK(result->front().name=="fixture");CHECK(result->front().id==2);}
    }
  }
}

TEST_CASE("Residents specialization binds edits to positive revisions and validates outcomes") {
  wm::ManagementRequest request;request.action=wm::ManagementAction::ResidentsSpecialize;
  request.residentsSpecialization={42,91,true};
  for(int variant=0;variant<3;++variant) {
    auto r=request;if(variant==1)r.residentsSpecialization.expectedRevision=0;if(variant==2)r.residentsSpecialization.unitId=-1;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(bool(wire::validateConstructionRequest(*value))==(variant!=0));
    if(!variant){REQUIRE(value->residents_specialization());CHECK(value->residents_specialization()->expected_revision()==91);CHECK(value->residents_specialization()->only_assigned());}
  }
  for(int outcome=0;outcome<5;++outcome) {
    flatbuffers::FlatBufferBuilder b;
    const auto payload=wire::CreateResidentsSpecializationState(b,42,wire::ResidentsSpecializationOutcome(outcome),true);
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(wire::ManagementAction::ResidentsSpecialize);
    state.add_status(outcome==0?wire::ManagementStatus::Ok:wire::ManagementStatus::Rejected);state.add_residents_specialization(payload);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());CHECK_FALSE(wire::validateManagementState(*value));
    const auto decoded=codec::decodeState(value);REQUIRE(decoded.residentsSpecialization);
    CHECK(decoded.residentsSpecialization->unitId==42);CHECK(int(decoded.residentsSpecialization->outcome)==outcome);CHECK(decoded.residentsSpecialization->onlyAssigned);
  }
}

TEST_CASE("Residents happiness preserves absence and rejects unknown tiers") {
  for(int tier=-2;tier<=7;++tier) {
    flatbuffers::FlatBufferBuilder b;
    const auto empty=b.CreateString("");const auto color=wire::CreateAreaNameColor(b);
    const auto row=wire::CreateResidentRow(b,42,empty,empty,empty,empty,empty,color,empty,7,0,false,{},int8_t(tier));
    const auto payload=wire::CreateResidentsRowsState(b,b.CreateVector(std::vector{row}));
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(wire::ManagementAction::ResidentsRowsRead);
    state.add_status(wire::ManagementStatus::Ok);state.add_residents_rows(payload);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(tier < -1 || tier>6));
    if(tier>=-1 && tier<=6)CHECK(codec::decodeState(value).residentsRows->rows.front().happiness==tier);
  }
}

TEST_CASE("Residents artwork is an optional owned recipe with validated page identities") {
  for(int variant=0;variant<3;++variant) {
    flatbuffers::FlatBufferBuilder b;
    flatbuffers::Offset<wire::SelectionAppearance> icon;
    if(variant) {
      const auto pages=b.CreateVectorOfStrings(std::vector<std::string>{"fixture-page"});
      const auto palettes=b.CreateVectorOfStrings(std::vector<std::string>{});
      std::vector<wire::AppearanceLayer> layers{wire::AppearanceLayer(variant==2?1:0,2,3,1,1,65535,0,0,-1,2)};
      icon=wire::CreateSelectionAppearance(b,pages,palettes,b.CreateVectorOfStructs(layers));
    }
    const auto empty=b.CreateString("");const auto color=wire::CreateAreaNameColor(b);
    const auto row=wire::CreateResidentRow(b,42,empty,empty,empty,empty,empty,color,empty,7,0,false,icon);
    const auto payload=wire::CreateResidentsRowsState(b,b.CreateVector(std::vector{row}));
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(wire::ManagementAction::ResidentsRowsRead);
    state.add_status(wire::ManagementStatus::Ok);state.add_residents_rows(payload);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(variant==2));
    if(variant<2) {
      auto decoded=codec::decodeState(value);REQUIRE(decoded.residentsRows);
      const auto& image=decoded.residentsRows->rows.front().sheetIcon;
      CHECK(image.has_value()==(variant==1));
      if(image){CHECK(image->tilePages[0]=="fixture-page");CHECK(image->layers[0].offsetX==-1);}
    }
  }
}

TEST_CASE("Work Details content requests retain selected authority and reject mixed domains") {
  for(int fault=0;fault<7;++fault) {
    wm::ManagementRequest r;r.action=wm::ManagementAction::WorkDetailRowsRead;
    r.residentsRows={{42,7},30,false,3,UINT64_C(9007199254740993)};
    if(fault==1)r.residentsRows.detailIndex=-1;
    if(fault==2)r.residentsRows.detailIndex=128;
    if(fault==3)r.residentsRows.expectedRevision=0;
    if(fault==4)r.residentsRows.expectedRevision=uint64_t(INT64_MAX)+1;
    if(fault==5)r.action=wm::ManagementAction::ResidentsRowsRead;
    if(fault==6)r.residentsRows.unitIds={42,42};
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(bool(wire::validateConstructionRequest(*value))==(fault!=0));
    if(fault==0){CHECK(value->residents_rows()->detail_index()==3);CHECK(value->residents_rows()->expected_revision()==UINT64_C(9007199254740993));}
  }
}
TEST_CASE("Work Details row skills are complete ordered observations, not single best skill") {
  for(int fault=0;fault<9;++fault) {
    flatbuffers::FlatBufferBuilder b;
    const auto empty=b.CreateString("");const auto text=b.CreateString("Synthetic caption");
    const auto color=wire::CreateAreaNameColor(b,7,0,1);
    std::vector<flatbuffers::Offset<wire::WorkDetailSkill>> skills;
    skills.push_back(wire::CreateWorkDetailSkill(b,0,fault==2?0:25,text));
    skills.push_back(wire::CreateWorkDetailSkill(b,fault==3?0:fault==4?149:21,15,text));
    const auto skillVector=b.CreateVector(skills);
    wire::ResidentRowBuilder row(b);row.add_id(42);row.add_name(text);row.add_combined(text);row.add_profession(empty);
    row.add_first_line(text);row.add_second_line(empty);row.add_name_color(color);row.add_activity(fault==5?text:empty);
    row.add_detail_member(fault==6?2:1);if(fault!=1)row.add_work_detail_skills(skillVector);
    if(fault==8)row.add_happiness(0);
    const auto rows=wire::CreateResidentsRowsState(b,b.CreateVector(std::vector{row.Finish()}));
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_status(wire::ManagementStatus::Ok);
    state.add_action(fault==7?wire::ManagementAction::ResidentsRowsRead:wire::ManagementAction::WorkDetailRowsRead);state.add_residents_rows(rows);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(fault!=0));
    if(fault==0){const auto result=codec::decodeState(value);const auto& decoded=result.residentsRows->rows[0];
      CHECK(decoded.detailMember==1);REQUIRE(decoded.workDetailSkills);REQUIRE(decoded.workDetailSkills->size()==2);
      CHECK(decoded.workDetailSkills->at(0).rating==25);CHECK(decoded.workDetailSkills->at(1).skill==21);CHECK(decoded.happiness==-1);}
  }
}

TEST_CASE("Residents content reads preserve explicit order and bound each batch") {
  wm::ManagementRequest request;request.action=wm::ManagementAction::ResidentsRowsRead;
  request.residentsRows={{42,7},30,false};
  for(int variant=0;variant<6;++variant) {
    auto r=request;
    if(variant==1)r.residentsRows.unitIds={42,42};
    if(variant==2)r.residentsRows.unitIds={-1};
    if(variant==3)r.residentsRows.unitIds.clear();
    if(variant==4)r.residentsRows.columns=31;
    if(variant==5){r.residentsRows.unitIds.resize(65);for(int i=0;i<65;++i)r.residentsRows.unitIds[i]=i;}
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,11,12,13);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    REQUIRE(value->residents_rows());
    CHECK(bool(wire::validateConstructionRequest(*value))==(variant!=0));
    if(variant==0) {
      CHECK(value->residents_rows()->unit_ids()->Get(0)==42);
      CHECK(value->residents_rows()->unit_ids()->Get(1)==7);
      CHECK_FALSE(value->residents_rows()->show_gender());
    }
  }
}

TEST_CASE("Residents row content keeps native captions and rejects invalid payloads") {
  for(int variant=0;variant<7;++variant) {
    flatbuffers::FlatBufferBuilder b;
    const auto color=wire::CreateAreaNameColor(b,variant==2?8:2,0,1,3,0,0,1);
    const auto text=b.CreateString(variant==3?std::string(4097,'x'):variant==4?std::string("a\0b",3):"Native caption");
    const auto empty=b.CreateString("");
    std::vector<flatbuffers::Offset<wire::ResidentRow>> rows;
    const int count=variant==6?33:2;
    for(int i=0;i<count;++i) {
      const auto field=variant==6?b.CreateString(std::string(4096,'x')):text;
      rows.push_back(wire::CreateResidentRow(b,variant==1?42:(i==0?42:i==1?7:100+i),field,field,empty,text,empty,color,field,7,0,true));
    }
    const auto payload=wire::CreateResidentsRowsState(b,b.CreateVector(rows));
    wire::ManagementStateBuilder state(b);state.add_revision(1);
    state.add_action(variant==5?wire::ManagementAction::Catalog:wire::ManagementAction::ResidentsRowsRead);
    state.add_status(wire::ManagementStatus::Ok);state.add_residents_rows(payload);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(variant!=0));
    if(variant==0) {
      const auto decoded=codec::decodeState(value);REQUIRE(decoded.residentsRows);
      REQUIRE(decoded.residentsRows->rows.size()==2);
      CHECK(decoded.residentsRows->rows[0].id==42);CHECK(decoded.residentsRows->rows[1].id==7);
      CHECK(decoded.residentsRows->rows[0].firstLine=="Native caption");
      CHECK(decoded.residentsRows->rows[0].secondLine.empty());
      CHECK(decoded.residentsRows->rows[0].nameColor.effect==1);
      CHECK(decoded.residentsRows->rows[0].activityBright);
    }
  }
}

TEST_CASE("Residents query preserves native textbox bytes and validates its domain") {
  wm::ManagementRequest request;request.action=wm::ManagementAction::ResidentsQuery;
  request.residents.sort=wm::ResidentsSort::Activity;request.residents.descending=true;
  // Includes an incomplete UTF-8 sequence, possible after native Backspace.
  request.residents.queryBytes={'T',0xc3};
  for(int variant=0;variant<5;++variant) {
    auto r=request;
    if(variant==1)r.residents.queryBytes={0};
    if(variant==2)r.residents.queryBytes.resize(wire::kResidentsQueryBytes+1,'x');
    if(variant==3)r.residents.sort=wm::ResidentsSort(255);
    if(variant==4)r.residents.queryBytes.clear();
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,11,12,13);
    const auto* encoded=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    REQUIRE(encoded->residents());CHECK(encoded->residents()->descending());
    CHECK(std::vector<uint8_t>(encoded->residents()->query_bytes()->begin(),encoded->residents()->query_bytes()->end())==r.residents.queryBytes);
    const auto error=wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer()));
    CHECK(bool(error)==(variant>=1 && variant<=3));
  }
  flatbuffers::FlatBufferBuilder b;
  const auto q=wire::CreateResidentsRequest(b,wire::ResidentsSort::Category,false,b.CreateVector(std::vector<uint8_t>{}));
  wire::ConstructionRequestBuilder r(b);r.add_client_id(1);r.add_seq(1);r.add_residents(q);b.Finish(r.Finish());
  REQUIRE(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer())));
  CHECK(*wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer()))=="unexpected residents query");
}

TEST_CASE("Work-detail worker queries bind native bytes to a selected detail receipt") {
  wm::ManagementRequest request;request.action=wm::ManagementAction::WorkDetailWorkersQuery;
  request.workDetailWorkers={7,9007199254740993ull,{{wm::WorkDetailWorkerSort::Skills,true},{wm::WorkDetailWorkerSort::Name,false},{wm::WorkDetailWorkerSort::Skills,true}},{'T',0xc3}};
  for(int variant=0;variant<11;++variant) {
    auto r=request;
    if(variant==1)r.workDetailWorkers.detailIndex=-1;
    if(variant==2)r.workDetailWorkers.detailIndex=128;
    if(variant==3)r.workDetailWorkers.expectedRevision=0;
    if(variant==4)r.workDetailWorkers.expectedRevision=uint64_t(INT64_MAX)+1;
    if(variant==5)r.workDetailWorkers.sorts[0].column=wm::WorkDetailWorkerSort(4);
    if(variant==6)r.workDetailWorkers.queryBytes={0};
    if(variant==7)r.workDetailWorkers.queryBytes.resize(wire::kResidentsQueryBytes+1,'x');
    if(variant==8)r.workDetailWorkers.sorts.clear();
    if(variant==9)r.workDetailWorkers.sorts[2].descending=false;
    if(variant==10)r.workDetailWorkers.sorts.resize(65537);
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,11,12,13);
    const auto* encoded=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    REQUIRE(encoded->work_detail_workers());const auto* q=encoded->work_detail_workers();
    CHECK(q->detail_index()==r.workDetailWorkers.detailIndex);CHECK(q->expected_revision()==r.workDetailWorkers.expectedRevision);
    CHECK(q->sorts()->size()==r.workDetailWorkers.sorts.size());
    for(size_t i=0;i<r.workDetailWorkers.sorts.size();++i){CHECK(q->sorts()->Get(i)->column()==wire::WorkDetailWorkerSort(r.workDetailWorkers.sorts[i].column));CHECK(q->sorts()->Get(i)->descending()==r.workDetailWorkers.sorts[i].descending);}CHECK(std::vector<uint8_t>(q->query_bytes()->begin(),q->query_bytes()->end())==r.workDetailWorkers.queryBytes);
    CHECK(bool(wire::validateConstructionRequest(*encoded))==(variant!=0));
  }
  flatbuffers::FlatBufferBuilder b;
  const auto q=wire::CreateWorkDetailWorkersRequest(b,0,1,b.CreateVector(std::vector<flatbuffers::Offset<wire::WorkDetailSort>>{wire::CreateWorkDetailSort(b,wire::WorkDetailWorkerSort::Skills,false)}),b.CreateVector(std::vector<uint8_t>{}));
  wire::ConstructionRequestBuilder r(b);r.add_client_id(1);r.add_seq(1);r.add_work_detail_workers(q);b.Finish(r.Finish());
  REQUIRE(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer())));
  CHECK(*wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer()))=="unexpected work-detail worker query");
}

TEST_CASE("Residents reply retains complete order and rejects duplicate or truncated identities") {
 for(auto action:{wire::ManagementAction::ResidentsQuery,wire::ManagementAction::WorkDetailWorkersQuery}) {
  for(int variant=0;variant<7;++variant) {
    std::vector<int32_t> ids={7,2,9};
    if(variant==1)ids={7,2,7};
    if(variant==2)ids={-1};
    if(variant==3)ids.clear();
    if(variant==4){ids.resize(wire::kResidentsQueryUnits+1);for(size_t i=0;i<ids.size();++i)ids[i]=int32_t(i);}
    flatbuffers::FlatBufferBuilder b;
    const auto rows=wire::CreateResidentsState(b,variant==5?flatbuffers::Offset<flatbuffers::Vector<int32_t>>{}:b.CreateVector(ids));
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_world_epoch(13);state.add_request_seq(12);
    state.add_action(variant==6?wire::ManagementAction::Catalog:action);
    state.add_status(wire::ManagementStatus::Ok);state.add_residents(rows);b.Finish(state.Finish());
    const auto error=wire::validateManagementState(*flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer()));
    const bool valid=variant==0 || variant==3;
    CHECK(bool(error)==!valid);
    if(valid) {
      const auto decoded=codec::decodeState(flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer()));
      REQUIRE(decoded.residents);CHECK(decoded.residents->unitIds==ids);
    }
  }
 }
}

TEST_CASE("farm edits require exact revisions owned only by crop requests") {
  for(int variant=0;variant<16;++variant) {
    CAPTURE(variant);wm::ManagementRequest r;r.action=wm::ManagementAction::FarmEdit;
    auto& p=r.production;p.buildingId=227;p.season=1;p.cropId=-1;p.expectedRevision=9007199254740993ULL;
    if(variant==1)p.expectedRevision=0;
    if(variant==2)p.expectedRevision=UINT64_MAX;
    if(variant==3)r.action=wm::ManagementAction::ProductionInspect;
    if(variant==4)p.jobId=1;
    if(variant==5)p.cursor=1;
    if(variant==6)p.repeat=1;
    if(variant==7)p.suspend=0;
    if(variant==8)p.cancel=true;
    if(variant==9)p.recipe="unowned";
    if(variant==10)p.query="unowned";
    if(variant==11)p.farmOperation=wm::FarmOperation(6);
    if(variant==12)p.seasonalFertilization=0;
    if(variant==13)p.farmOperation=wm::FarmOperation::SeasonalFertilization;
    if(variant==14){p.farmOperation=wm::FarmOperation::FertilizationToggle;p.cropId=175;}
    if(variant==15){p.farmOperation=wm::FarmOperation::FertilizationToggle;r.action=wm::ManagementAction::ProductionInspect;p.expectedRevision=0;}
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(bool(wire::validateConstructionRequest(*value))==(variant!=0));
    if(!variant)CHECK(value->production()->expected_revision()==9007199254740993ULL);
  }
}
TEST_CASE("farm removal intents preserve exact revision and reject unrelated fields") {
  for(auto operation:{wm::FarmOperation::Remove,wm::FarmOperation::CancelRemoval})for(int fault=0;fault<5;++fault) {
    wm::ManagementRequest r;r.action=wm::ManagementAction::FarmEdit;
    auto& p=r.production;p.buildingId=227;p.season=1;p.expectedRevision=9007199254740993ULL;p.farmOperation=operation;
    if(fault==1)p.expectedRevision=0;
    if(fault==2)p.cropId=175;
    if(fault==3)p.seasonalFertilization=0;
    if(fault==4)p.farmName="unowned";
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(bool(wire::validateConstructionRequest(*value))==(fault!=0));
    CHECK(int(value->production()->farm_operation())==int(operation));
    CHECK(value->production()->expected_revision()==p.expectedRevision);
  }
}
TEST_CASE("successful farm edit cannot omit its production result") {
  flatbuffers::FlatBufferBuilder b;wire::ManagementStateBuilder s(b);
  s.add_revision(1);s.add_schema_version(wire::kManagementVersion);
  s.add_action(wire::ManagementAction::FarmEdit);s.add_status(wire::ManagementStatus::Ok);
  b.Finish(s.Finish());
  CHECK(wire::validateManagementState(*flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer())).has_value());
}
TEST_CASE("farm rename owns a present bounded name and preserves exact UTF8 bytes") {
  for(int variant=0;variant<10;++variant) {
    CAPTURE(variant);wm::ManagementRequest r;r.action=wm::ManagementAction::FarmEdit;
    auto& p=r.production;p.buildingId=227;p.season=1;p.expectedRevision=9007199254740993ULL;
    p.farmOperation=wm::FarmOperation::Rename;p.farmName="\xc3\xa9 farm";
    if(variant==1)p.farmName.clear();
    if(variant==2)p.farmName=std::string(90,'x');
    if(variant==3)p.farmName=std::string(91,'x');
    if(variant==4)p.farmName=std::string("a\0b",3);
    if(variant==5)p.farmOperation=wm::FarmOperation::Crop;
    if(variant==6)p.cropId=175;
    if(variant==7)p.seasonalFertilization=0;
    if(variant==8){r.action=wm::ManagementAction::ProductionInspect;p.expectedRevision=0;}
    if(variant==9)p.expectedRevision=0;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(bool(wire::validateConstructionRequest(*value))==(variant>=3));
    REQUIRE(value->production()->farm_name());CHECK(value->production()->farm_name()->str()==p.farmName);
  }
  flatbuffers::FlatBufferBuilder b;
  wire::ProductionRequestBuilder p(b);p.add_building_id(227);p.add_season(1);p.add_expected_revision(1);p.add_farm_operation(wire::FarmOperation::Rename);
  auto prod=p.Finish();wire::ConstructionRequestBuilder r(b);r.add_schema_version(wire::kManagementVersion);
  r.add_client_id(1);r.add_seq(1);r.add_world_epoch(1);
  r.add_action(wire::ManagementAction::FarmEdit);r.add_production(prod);b.Finish(r.Finish());
  const auto* request=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
  CHECK(wire::validateConstructionRequest(*request)==std::optional<std::string>("invalid farm name"));
}
TEST_CASE("farm outcomes grant snapshot authority only to confirmed completion") {
  for(int outcome=0;outcome<6;++outcome)for(bool ok:{false,true})for(bool receipt:{false,true})for(bool edit:{false,true}) {
    CAPTURE(outcome);CAPTURE(ok);CAPTURE(receipt);CAPTURE(edit);
    flatbuffers::FlatBufferBuilder b;
    auto farm=wire::CreateFarmSnapshot(b,227,17,1,1,b.CreateVector(std::vector<int32_t>{175,-1,176,-1}),b.CreateVector(std::vector<flatbuffers::Offset<wire::NativeFarmCrop>>{}),0,0,0,false,b.CreateString(""),b.CreateString("Farm Plot"));
    wire::ProductionStateBuilder p(b);p.add_selected_building(227);
    p.add_farm_edit_outcome(static_cast<wire::FarmEditOutcome>(outcome));if(receipt)p.add_farm(farm);
    auto prod=p.Finish();wire::ManagementStateBuilder state(b);
    state.add_revision(1);state.add_schema_version(wire::kManagementVersion);
    state.add_action(edit?wire::ManagementAction::FarmEdit:wire::ManagementAction::ProductionInspect);
    state.add_status(ok?wire::ManagementStatus::Ok:wire::ManagementStatus::Rejected);state.add_production(prod);
    b.Finish(state.Finish());const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    const bool valid=outcome<5 && (edit?(outcome==1?ok && receipt:!ok && !receipt):outcome==0);
    CHECK(bool(wire::validateManagementState(*value))==!valid);
    if(valid)CHECK(int(codec::decodeProduction(value->production()).farmEditOutcome)==outcome);
  }
}

TEST_CASE("native farm receipts preserve order and exact revisions without legacy synthesis") {
  for(int variant=0;variant<28;++variant) {
    CAPTURE(variant);flatbuffers::FlatBufferBuilder b;
    std::vector<flatbuffers::Offset<wire::NativeFarmCrop>> rows;
    for(int i=0;i<(variant==8?257:2);++i)
      rows.push_back(wire::CreateNativeFarmCrop(b,variant==7?175:175+i,
        b.CreateString(variant==6?"":i==0?"Plump helmets":"Sweet pods"),i==0,i==1,
        variant==18?flatbuffers::Offset<flatbuffers::String>{}:b.CreateString(variant==19?"":variant==20?std::string(129,'A'):i==0?"MUSHROOM_HELMET_PLUMP":"POD_SWEET")));
    std::vector<int32_t> seasons{175,-1,176,-1};
    if(variant==4)seasons.pop_back();if(variant==5)seasons[1]=-2;
    auto f=wire::CreateFarmSnapshot(b,variant==1?-1:227,variant==2?0:variant==3?UINT64_MAX:9007199254740993ULL,
      variant==9?4:1,variant==10?-1:1,b.CreateVector(seasons),b.CreateVector(rows),
      variant==15?-1:4,variant==16?-1:29,variant==17?-1:2,true,
      variant==21?flatbuffers::Offset<flatbuffers::String>{}:b.CreateString(variant==23?std::string(1537,'x'):"test farm"),
      variant==22?flatbuffers::Offset<flatbuffers::String>{}:b.CreateString(variant==24?std::string(1537,'x'):variant==25?"":"Test farm"),
      variant!=26 && variant!=27,variant!=27,variant!=26);
    auto legacy=wire::CreateFarmCrop(b,175,b.CreateString("old singular name"),15,42);
    auto legacyRows=b.CreateVector(std::vector{legacy});
    wire::ProductionStateBuilder p(b);p.add_selected_building(variant==11?228:227);
    if(variant!=14)p.add_farm(f);
    if(variant==12 || variant==14)p.add_crops(legacyRows);
    auto production=p.Finish();wire::ManagementStateBuilder state(b);
    state.add_schema_version(wire::kManagementVersion-(variant==13?1:0));state.add_revision(1);
    state.add_action(wire::ManagementAction::ProductionInspect);state.add_production(production);
    b.Finish(state.Finish());const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(variant>0 && variant!=14));
    if(variant==0 || variant==14) {
      auto decoded=codec::decodeProduction(value->production());
      CHECK(decoded.farm.has_value()==(variant==0));
      if(decoded.farm) {
        CHECK(decoded.farm->revision==9007199254740993ULL);
        CHECK(decoded.farm->customName=="test farm");CHECK(decoded.farm->headerName=="Test farm");
        CHECK(decoded.farm->removing);CHECK(decoded.farm->removalSuspended);CHECK(decoded.farm->removalHasWorker);
        CHECK(decoded.farm->currentFertilization==4);CHECK(decoded.farm->maxFertilization==29);
        CHECK(decoded.farm->pendingFertilization==2);CHECK(decoded.farm->seasonalFertilization);
        REQUIRE(decoded.farm->choices.size()==2);
        CHECK(decoded.farm->choices[0].id==175);CHECK(decoded.farm->choices[1].id==176);
        CHECK(decoded.farm->choices[0].seedsAvailable);CHECK_FALSE(decoded.farm->choices[0].currentSeasonWarning);
        CHECK_FALSE(decoded.farm->choices[1].seedsAvailable);CHECK(decoded.farm->choices[1].currentSeasonWarning);
        CHECK(decoded.farm->choices[0].rawId=="MUSHROOM_HELMET_PLUMP");
        CHECK(decoded.farm->choices[1].rawId=="POD_SWEET");
        CHECK(decoded.farm->seasonalCrops==seasons);
      } else CHECK(decoded.crops[0].seeds==42);
    }
  }
}

TEST_CASE("Location naming requests retain bytes and canonical revisions with strict field ownership") {
  for(int mode=0;mode<4;++mode)for(int variant=0;variant<7;++variant) {
    wm::ManagementRequest r;r.action=wm::ManagementAction::AreaUpdate;
    auto& a=r.area;a.kind=wm::AreaKind::Zone;a.operation=wm::AreaOperation::LocationNameEdit;
    a.locationSiteId=651;a.locationId=1;a.expectedRevision=9007199254740993LL;
    a.nameEdit.emplace();auto& e=*a.nameEdit;e.mode=wm::LocationNameMode(mode);
    if(mode!=3){e.target=0;e.displayed=0;e.queryBytes={0x82,0xff};}
    if(mode==1){e.word=0;e.part=2;}
    if(variant==1)a.expectedRevision=0;
    if(variant==2)a.locationId=-1;
    if(variant==3)a.id=23;
    if(variant==4)r.action=wm::ManagementAction::AreaInspect;
    if(variant==5)a.nameQuery.emplace();
    if(variant==6)e.mode=wm::LocationNameMode(4);
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* q=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CAPTURE(mode);CAPTURE(variant);CHECK(bool(wire::validateConstructionRequest(*q))==(variant!=0));
    if(!variant) {
      CHECK(q->area()->expected_revision()==9007199254740993ULL);
      CHECK(int(q->area()->name_edit()->mode())==mode);
      if(mode!=3)CHECK(q->area()->name_edit()->query_bytes()->Get(1)==0xff);
    }
  }
  for(bool choices:{false,true}) {
    wm::ManagementRequest r;r.action=wm::ManagementAction::AreaInspect;
    auto& a=r.area;a.kind=wm::AreaKind::Zone;a.locationSiteId=651;a.locationId=1;
    a.operation=choices?wm::AreaOperation::LocationNameChoices:wm::AreaOperation::LocationNameRead;
    if(choices){a.expectedRevision=17;a.nameQuery.emplace();a.nameQuery->component=6;a.nameQuery->cursor=37;}
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* q=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK_FALSE(wire::validateConstructionRequest(*q));
    if(choices)CHECK(q->area()->name_query()->cursor()==37);
  }
}

TEST_CASE("Location naming replies decode exact structured names and ordered forms") {
  flatbuffers::FlatBufferBuilder b;
  auto v=wire::CreateLocationNameValue(b,b.CreateVector(std::vector<uint8_t>{0x82,0xff}),
      b.CreateVector(std::vector<uint8_t>{}),b.CreateVector(std::vector<int32_t>(7,-1)),
      b.CreateVector(std::vector<int16_t>(7,8)),-1,-1,true);
  auto s=wire::CreateLocationNameSnapshot(b,651,1,1,245,0,9007199254740993ULL,v,b.CreateString("Native"),b.CreateString("English"));
  std::vector<flatbuffers::Offset<wire::LocationNameChoice>> choices;
  choices.push_back(wire::CreateLocationNameChoice(b,0,0,b.CreateString("abbey"),b.CreateString("kulet")));
  choices.push_back(wire::CreateLocationNameChoice(b,0,1,b.CreateString("abbeys"),b.CreateString("kulet")));
  auto p=wire::CreateLocationNamePage(b,s,6,b.CreateVector(std::vector<uint8_t>{0x82}),0,2,0,false,b.CreateVector(choices));
  wire::AreaStateBuilder a(b);a.add_operation(wire::AreaOperation::LocationNameChoices);a.add_location_name_page(p);b.Finish(a.Finish());
  const auto* encoded=flatbuffers::GetRoot<wire::AreaState>(b.GetBufferPointer());
  CHECK_FALSE(wire::validateLocationNamePage(*encoded->location_name_page()));
  auto decoded=codec::decodeArea(encoded);REQUIRE(decoded.locationNamePage);
  CHECK(decoded.locationNamePage->snapshot.revision==9007199254740993LL);
  CHECK(decoded.locationNamePage->snapshot.nativeHeader=="Native");
  CHECK(decoded.locationNamePage->snapshot.englishHeader=="English");
  CHECK(decoded.locationNamePage->snapshot.value.firstNameBytes==std::vector<uint8_t>{0x82,0xff});
  REQUIRE(decoded.locationNamePage->choices.size()==2);
  CHECK(decoded.locationNamePage->choices[0].part==0);CHECK(decoded.locationNamePage->choices[1].part==1);
  CHECK(decoded.locationNamePage->choices[1].translated=="kulet");
}

TEST_CASE("filtered settings counts preserve unknown legacy data and reject inconsistent pages") {
  for(int count:{-2,-1,0,1,128,300,301}) {
    flatbuffers::FlatBufferBuilder b;
    wire::AreaStateBuilder area(b);area.add_operation(wire::AreaOperation::SettingsPage);
    area.add_build_total(300);area.add_build_done(300);area.add_settings_count(count);
    area.add_next_cursor(128);const auto value=area.Finish();
    wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_area(value);b.Finish(root.Finish());
    const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*state)) == (count < -1 || (count>=0 && (count<128 || count>300))));
    CHECK(codec::decodeArea(state->area()).settingsCount==count);
  }
  flatbuffers::FlatBufferBuilder b;b.Finish(wire::CreateAreaState(b));
  CHECK(codec::decodeArea(flatbuffers::GetRoot<wire::AreaState>(b.GetBufferPointer())).settingsCount==-1);
}

TEST_CASE("animal display carries native split facts without inventing legacy data") {
  for(int mode=0;mode<13;++mode) {
    flatbuffers::FlatBufferBuilder b;
    flatbuffers::Offset<wire::AreaAnimalDisplay> display;
    if(mode!=0) {
      const auto color=mode==8?flatbuffers::Offset<wire::AreaNameColor>{}:wire::CreateAreaNameColor(b,mode==9?8:6,0,0,6,0,0,0);
      display=wire::CreateAreaAnimalDisplay(b,mode==3?2:27,b.CreateString(mode==10?std::string(385,'x'):""),
        b.CreateString("Shortened profession"),mode==7,b.CreateString(mode==6?"":"Grazer: requires pasture"),color);
    }
    const auto entity=mode==4?wire::AreaCandidateEntity::Item:wire::AreaCandidateEntity::Unit;
    const auto row=wire::CreateAreaCandidateRow(b,21,0,0,-1,0,mode!=5,false,-1,0,0,entity,display);
    const auto rows=b.CreateVector(std::vector{row});wire::AreaStateBuilder area(b);
    area.add_operation(mode==11?wire::AreaOperation::None:wire::AreaOperation::CandidateList);
    area.add_candidate_kind(mode==2?1:2);area.add_candidates(rows);const auto a=area.Finish();
    wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_area(a);b.Finish(root.Finish());
    const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*state))==(mode>=2 && mode<=11));
    const auto decoded=codec::decodeArea(state->area());REQUIRE(decoded.candidates.size()==1);
    const auto& facts=decoded.candidates[0].animalDisplay;CHECK(facts.has_value()==(mode!=0));
    if(mode==1 || mode==12) {REQUIRE(facts);CHECK(facts->columns==27);CHECK(facts->firstLine.empty());
      CHECK(facts->secondLine=="Shortened profession");CHECK_FALSE(facts->combinedFits);
      CHECK(facts->warning=="Grazer: requires pasture");CHECK(facts->nameColor.color[0]==6);}
  }
}

TEST_CASE("owner display preserves native lines and unknown legacy rows") {
  for(int mode=0;mode<7;++mode) {
    flatbuffers::FlatBufferBuilder b;
    flatbuffers::Offset<wire::AreaOwnerDisplay> display;
    if(mode!=0)display=wire::CreateAreaOwnerDisplay(b,mode==2?2:45,b.CreateString("Native name"),b.CreateString("Native profession"),b.CreateString(mode==3?"":"Has Quarters"),mode==4?-1:343);
    const auto row=wire::CreateAreaCandidateRow(b,21,b.CreateString("Legacy name"),0,-1,0,false,false,-1,display);
    const auto rows=b.CreateVector(std::vector{row});wire::AreaStateBuilder area(b);
    area.add_operation(wire::AreaOperation::CandidateList);area.add_candidate_kind(mode==5?2:1);area.add_candidates(rows);
    const auto a=area.Finish();wire::ManagementStateBuilder state(b);state.add_schema_version(wire::kManagementVersion-(mode==6?1:0));state.add_revision(1);state.add_area(a);
    b.Finish(state.Finish());const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(mode>=2));
    auto decoded=codec::decodeArea(value->area());REQUIRE(decoded.candidates.size()==1);
    CHECK(decoded.candidates[0].ownerDisplay.has_value()==(mode!=0));
    if(mode==1) {const auto& d=*decoded.candidates[0].ownerDisplay;CHECK(d.firstLine=="Native name");CHECK(d.secondLine=="Native profession");CHECK(d.status=="Has Quarters");CHECK(d.columns==45);CHECK(d.roomValue==343);}
  }
}

TEST_CASE("owner name color bounds effects and absent historical facts") {
  for(int mode=0;mode<13;++mode) {
    flatbuffers::FlatBufferBuilder b;
    flatbuffers::Offset<wire::AreaNameColor> color;
    const int effect=mode>=1 && mode<=4?mode-1:mode==11?4:1;
    if(mode!=0)color=wire::CreateAreaNameColor(b,mode==5?8:3,mode==6?8:3,mode==7?2:1,
      mode==8?8:effect==0?3:0,mode==9?8:3,mode==10?2:effect==0?1:0,effect);
    if(mode==12)color=wire::CreateAreaNameColor(b,3,3,1,0,3,0,0);
    const auto display=wire::CreateAreaOwnerDisplay(b,45,b.CreateString("Observed"),0,0,0,color);
    const auto row=wire::CreateAreaCandidateRow(b,21,0,0,-1,0,false,false,-1,display);
    const auto rows=b.CreateVector(std::vector{row});wire::AreaStateBuilder area(b);
    area.add_operation(wire::AreaOperation::CandidateList);area.add_candidate_kind(1);area.add_candidates(rows);
    const auto a=area.Finish();wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_area(a);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(mode>=5));
    const auto decoded=codec::decodeArea(value->area());const auto& name=decoded.candidates[0].ownerDisplay->nameColor;
    CHECK(name.has_value()==(mode!=0));
    if(mode>=1 && mode<=4) {REQUIRE(name);CHECK(name->effect==effect);CHECK(name->color[0]==3);CHECK(name->color[1]==3);CHECK(name->color[2]==1);
      CHECK(name->alternate[0]==(effect==0?3:0));CHECK(name->alternate[1]==3);CHECK(name->alternate[2]==(effect==0?1:0));}
  }
}

TEST_CASE("verified category default lists accept parent ordering") {
  for(const char* key:{"food/meat","furniture/type","refuse/type","stone/metal_ores","ammo/type","bars_blocks/bars_metal","gems/rough_gem","finished_goods/type","leather/type","cloth/thread_silk","weapons/weapons","armor/body","sheet/paper"}) {
    wm::ManagementRequest q;q.action=wm::ManagementAction::AreaInspect;
    q.area.operation=wm::AreaOperation::SettingsPage;q.area.id=39;
    q.area.listKey=key;q.area.categoryOpening=true;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
    const auto* r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK_FALSE(wire::validateConstructionRequest(*r).has_value());
  }
}

TEST_CASE("stockpile category opening context is read-only and scoped to the verified leaf") {
  for(int mode=0;mode<5;++mode) {
    wm::ManagementRequest q;q.action=wm::ManagementAction::AreaInspect;
    q.area.operation=wm::AreaOperation::SettingsPage;q.area.id=39;
    q.area.listKey="food/meat";q.area.categoryOpening=mode!=0;
    if(mode==2)q.area.listKey="food/fish";
    if(mode==3){q.action=wm::ManagementAction::AreaUpdate;q.area.operation=wm::AreaOperation::SettingsSet;q.area.scope=2;q.area.value=2;}
    if(mode==4)q.area.listKey="";
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
    const auto* r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    REQUIRE(r->area());CHECK(r->area()->category_opening()==(mode!=0));
    CHECK(wire::validateConstructionRequest(*r).has_value()==(mode>=2));
  }
}

TEST_CASE("world hover preserves native prose and rejects malformed tile replies") {
  for(int mode=0;mode<5;++mode) {
    flatbuffers::FlatBufferBuilder b;
    const wire::TilePos tile(mode==1?-1:118,45,165);
    const auto text=b.CreateString(mode==2?std::string(4097,'x'):"Smooth dolomite Floor");
    const auto entry=wire::CreateWorldHoverEntry(b,text,1,0,true,1);
    const auto hover=wire::CreateWorldHover(b,mode==3?nullptr:&tile,b.CreateVector(std::vector{entry}));
    wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_status(wire::ManagementStatus::Ok);
    root.add_action(mode==4?wire::ManagementAction::Catalog:wire::ManagementAction::WorldHover);
    root.add_world_hover(hover);b.Finish(root.Finish());
    const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(wire::validateManagementState(*state).has_value()==(mode!=0));
    if(mode==0) {
      const auto value=codec::decodeState(state);REQUIRE(value.worldHover);
      CHECK(value.worldHover->x==118);CHECK(value.worldHover->z==165);
      CHECK(value.worldHover->entries.at(0).text=="Smooth dolomite Floor");
    }
  }
  wm::ManagementRequest request;request.action=wm::ManagementAction::WorldHover;
  request.x=118;request.y=45;request.z=165;
  flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
  CHECK_FALSE(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer())));
  request.x=32768;b.Clear();codec::encodeRequest(b,request,1,3,3);
  CHECK(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer())).has_value());
}

TEST_CASE("world hover bounds fit the mailbox and retain ordered native entry metadata") {
  for(int mode=0;mode<7;++mode) {
    flatbuffers::FlatBufferBuilder b;
    const wire::TilePos tile(118,45,165);
    std::vector<flatbuffers::Offset<wire::WorldHoverEntry>> entries;
    const int count=mode==1?4097:4096;
    for(int i=0;i<count;++i) {
      const auto text=b.CreateString(std::string(mode==2?81:80,'a'+i%26));
      entries.push_back(wire::CreateWorldHoverEntry(b,text,mode==3?8:i%8,mode==4?8:7-i%8,
        i%2,mode==5?16:i%16,mode==6?-2:i));
    }
    const auto data=wire::CreateWorldHover(b,&tile,b.CreateVector(entries));
    wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_status(wire::ManagementStatus::Ok);
    root.add_action(wire::ManagementAction::WorldHover);root.add_world_hover(data);b.Finish(root.Finish());
    const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(wire::validateManagementState(*state).has_value()==(mode!=0));
    if(mode==0) {
      CHECK(b.GetSize()<wire::kManagementCapacity);
      const auto decoded=codec::decodeState(state);REQUIRE(decoded.worldHover);
      REQUIRE(decoded.worldHover->entries.size()==4096);
      for(int i=0;i<4096;++i) {
        const auto& e=decoded.worldHover->entries[i];
        CHECK(e.text==std::string(80,'a'+i%26));CHECK(e.foreground==i%8);
        CHECK(e.background==7-i%8);CHECK(e.bright==bool(i%2));CHECK(e.kind==i%16);CHECK(e.objectId==i);
      }
    }
  }
}

TEST_CASE("construction warnings are bounded advisory data independent of refusal status") {
  for(bool rejected:{false,true})for(size_t size:{size_t(0),size_t(512),size_t(513)}) {
    flatbuffers::FlatBufferBuilder b;
    const auto warning=b.CreateString(std::string(size,'x'));
    wire::ConstructionStateBuilder domain(b);domain.add_warnings(warning);auto c=domain.Finish();
    wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_construction(c);
    root.add_status(rejected?wire::ManagementStatus::Rejected:wire::ManagementStatus::Ok);b.Finish(root.Finish());
    const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(wire::validateManagementState(*state).has_value()==(size>512));
    if(size<=512) {wm::ManagementState decoded;codec::decodeConstruction(state,decoded);
      CHECK(decoded.construction.warnings==std::string(size,'x'));}
  }
}

TEST_CASE("building removal cancellation is explicit and isolated from older peers") {
  wm::ManagementRequest q;q.action=wm::ManagementAction::Remove;q.definition="Bed";q.buildingId=9;q.cancelRemoval=true;
  flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
  auto r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
  CHECK(r->cancel_removal());CHECK_FALSE(wire::validateConstructionRequest(*r).has_value());
  q.action=wm::ManagementAction::Inspect;b.Clear();codec::encodeRequest(b,q,1,3,3);
  r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
  CHECK(wire::validateConstructionRequest(*r).has_value());
}

TEST_CASE("standalone construction identities cannot substitute same-material items") {
  for(int mode=0;mode<5;++mode) {
    wm::ManagementRequest q;q.action=wm::ManagementAction::Place;q.definition="Chair";
    wm::ConstructionSelection s;s.filter=0;s.count=1;s.expectedListRevision=1;
    s.individualId=mode==4?-2:2;s.itemIds=std::vector<int32_t>{mode==1?3:2};
    if(mode==2)s.itemIds.reset();
    if(mode==3)s.count=2;
    q.selections={s};
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
    const auto* r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(wire::validateConstructionRequest(*r).has_value()==(mode!=0));
    CHECK(r->selections()->Get(0)->individual_id()==s.individualId);
  }
  for(int mode=0;mode<5;++mode) {
    flatbuffers::FlatBufferBuilder b;
    std::vector<flatbuffers::Offset<wire::ConstructionMaterial>> rows;
    for(int id=1;id<=3;++id) {
      auto item=wire::CreateConstructionMaterialCandidate(b,id,b.CreateString("fixture item"),2);
      auto items=b.CreateVector(std::vector{item});
      if(mode==2 && id==2)items={};
      rows.push_back(wire::CreateConstructionMaterial(b,0,-1,0,1,b.CreateString("fixture row"),{},1,items,
        id==1 || mode==3?-1:(mode==1?4:id),b.CreateString(mode==4?std::string(129,'x'):std::string("fixture generic history"))));
    }
    auto materials=b.CreateVector(rows);
    wire::ConstructionStateBuilder domain(b);domain.add_materials(materials);auto c=domain.Finish();
    wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_construction(c);b.Finish(root.Finish());
    const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(wire::validateManagementState(*state).has_value()==(mode!=0));
    if(mode==0){wm::ManagementState decoded;codec::decodeConstruction(state,decoded);
      REQUIRE(decoded.construction.materials.size()==3);CHECK(decoded.construction.materials[1].individualId==2);
      CHECK(decoded.construction.materials[1].lastName=="fixture generic history");}
  }
}

TEST_CASE("construction material anchor preserves gesture and validates volume corners") {
  wm::ManagementRequest base;base.action=wm::ManagementAction::ConstructionMaterials;
  base.definition="Construction:Stairs";base.filter=0;base.x=2;base.y=3;base.z=4;
  base.width=3;base.height=2;base.depth=3;base.materialAnchor=wm::TilePos{4,4,6};
  for(int mode=0;mode<9;++mode) {
    auto q=base;
    if(mode==1)q.materialAnchor=wm::TilePos{2,3,4};
    if(mode==2)q.action=wm::ManagementAction::Place,q.filter=-1;
    if(mode==3)q.materialAnchor.reset();
    if(mode==4)q.materialAnchor->z=5; // Interior, not a selected corner.
    if(mode==5)q.materialAnchor->x=-1;
    if(mode==6)q.definition="Chair";
    if(mode==7)q.retracting=true;
    if(mode==8)q.depth=257;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
    const auto* r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(wire::validateConstructionRequest(*r).has_value()==(mode>=4));
    CHECK(r->depth()==q.depth);CHECK(bool(r->material_anchor())==q.materialAnchor.has_value());
    if(r->material_anchor())CHECK(r->material_anchor()->z()==q.materialAnchor->z);
  }
}

TEST_CASE("reinforced area material requests preserve their selected corner") {
  for(const auto action : {wm::ManagementAction::Preview, wm::ManagementAction::Place,
                          wm::ManagementAction::ConstructionMaterials}) {
    wm::ManagementRequest q;q.action=action;q.definition="Construction:ReinforcedWall";
    q.x=2;q.y=3;q.z=4;q.width=2;q.height=2;q.depth=1;
    q.filter=action==wm::ManagementAction::ConstructionMaterials?1:-1;
    q.materialAnchor=wm::TilePos{3,4,4};
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
    const auto* r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK_FALSE(wire::validateConstructionRequest(*r).has_value());
    REQUIRE(r->material_anchor());CHECK(r->material_anchor()->x()==3);
  }
}

TEST_CASE("construction appearance is owned semantic data with strict optional bounds") {
  for(int mode=0;mode<11;++mode) {
    flatbuffers::FlatBufferBuilder b;
    auto material=b.CreateString(mode==2?"":mode==3?std::string(257,'x'):"INORGANIC:IRON");
    auto subtype=b.CreateString(mode==5?std::string(129,'x'):"ITEM_FIXTURE");
    auto color=b.CreateString(mode==4?std::string("\xff"):mode==10?std::string(129,'x'):"IRON_GRAY");
    auto appearance=wire::CreateConstructionItemAppearance(b,material,subtype,color,
      mode==6?0:mode==7?uint32_t(INT32_MAX)+1:7,mode==8?1:32);
    if(mode==1)appearance={};
    auto candidate=wire::CreateConstructionMaterialCandidate(b,10,b.CreateString("iron bars"),2,appearance);
    auto candidates=b.CreateVector(std::vector{candidate});
    auto row=wire::CreateConstructionMaterial(b,mode==9?-1:0,-1,0,3,b.CreateString("iron bars"),{},1,candidates);
    auto rows=b.CreateVector(std::vector{row});
    wire::ConstructionStateBuilder domain(b);domain.add_materials(rows);auto construction=domain.Finish();
    wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_construction(construction);
    root.add_action(wire::ManagementAction::ConstructionMaterials);root.add_status(wire::ManagementStatus::Ok);
    b.Finish(root.Finish());auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(wire::validateManagementState(*state).has_value()==(mode>=2));
    if(mode<2) {
      wm::ManagementState decoded;codec::decodeConstruction(state,decoded);b.Clear();
      REQUIRE(decoded.construction.materials.size()==1);
      const auto& item=decoded.construction.materials[0].candidates->at(0);
      CHECK(item.appearance.has_value()==(mode==0));
      if(item.appearance) { CHECK(item.appearance->materialToken=="INORGANIC:IRON");
        CHECK(item.appearance->subtypeRaw=="ITEM_FIXTURE");CHECK(item.appearance->colorToken=="IRON_GRAY");
        CHECK(item.appearance->stack==7);CHECK(item.appearance->flags==32); }
    }
  }
}

TEST_CASE("construction outcomes preserve confirmed effects and reject contradictory receipts") {
  for(int mode=0;mode<12;++mode) {
    const auto outcome=mode<5?wire::ConstructionOutcome(mode):mode==5?wire::ConstructionOutcome(5):
      mode==6?wire::ConstructionOutcome::Complete:mode==7?wire::ConstructionOutcome::Rejected:
      mode==8?wire::ConstructionOutcome::Partial:mode==9?wire::ConstructionOutcome::Unknown:wire::ConstructionOutcome::None;
    const uint32_t placed=(outcome==wire::ConstructionOutcome::Partial && mode!=8) || mode==7 ? 1:0;
    const uint32_t updated=mode==4 || mode==10?2:0;
    const int32_t failed=mode==11?0:(outcome==wire::ConstructionOutcome::Partial || outcome==wire::ConstructionOutcome::Unknown ? 3:-1);
    flatbuffers::FlatBufferBuilder b;
    wire::ConstructionStateBuilder domain(b);domain.add_outcome(outcome);domain.add_placed(placed);
    domain.add_updated(updated);domain.add_failed_index(failed);const auto c=domain.Finish();
    wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_construction(c);
    root.add_action(mode==9?wire::ManagementAction::Catalog:wire::ManagementAction::Place);
    root.add_status(mode==6 || outcome!=wire::ConstructionOutcome::Complete?wire::ManagementStatus::Rejected:wire::ManagementStatus::Ok);
    b.Finish(root.Finish());const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(wire::validateManagementState(*state).has_value()==(mode>=5));
    if(mode<5) { wm::ManagementState decoded;codec::decodeConstruction(state,decoded);
      CHECK(int(decoded.construction.outcome)==int(outcome));CHECK(decoded.construction.updated==updated);
      CHECK(decoded.construction.placed==placed);CHECK(decoded.construction.failedIndex==failed); }
  }
}

TEST_CASE("Construction candidate contract preserves identity and rejects incomplete or ambiguous rows") {
  for(int mode=0;mode<11;++mode) {
    flatbuffers::FlatBufferBuilder b;
    std::vector<flatbuffers::Offset<wire::ConstructionMaterialCandidate>> items;
    items.push_back(wire::CreateConstructionMaterialCandidate(b,mode==1?-1:10,b.CreateString(mode==2?"":"iron bars [7]"),2));
    items.push_back(wire::CreateConstructionMaterialCandidate(b,mode==3?10:11,b.CreateString(std::string(mode==4?129:9,'x')),mode==5?1:2));
    if(mode==10) { items.clear();for(int id=0;id<16385;++id)
      items.push_back(wire::CreateConstructionMaterialCandidate(b,id,b.CreateString("bars"),0)); }
    auto candidates=b.CreateVector(items);
    if(mode==7)candidates={}; // Aggregate-only source remains distinguishable.
    if(mode==8)candidates=b.CreateVector(std::vector<flatbuffers::Offset<wire::ConstructionMaterialCandidate>>{});
    const auto material=wire::CreateConstructionMaterial(b,0,-1,0,3,b.CreateString("iron bars"),{},mode==6?3:mode==10?16385:2,candidates);
    std::vector<flatbuffers::Offset<wire::ConstructionMaterial>> rows{material};
    if(mode==9)rows.push_back(wire::CreateConstructionMaterial(b,0,-1,0,4,b.CreateString("copper bars"),{},2,candidates));
    const auto materials=b.CreateVector(rows);
    const auto key=b.CreateString("Construction:Track");
    wire::ConstructionStateBuilder construction(b);construction.add_building_key(key);construction.add_materials(materials);
    const auto domain=construction.Finish();
    wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_status(wire::ManagementStatus::Ok);
    root.add_action(wire::ManagementAction::ConstructionMaterials);root.add_construction(domain);b.Finish(root.Finish());
    const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(bool(wire::validateManagementState(*state))==(mode!=0 && mode!=7));
    if(mode==0 || mode==7) {
      wm::ManagementState decoded;codec::decodeConstruction(state,decoded);
      REQUIRE(decoded.construction.materials.size()==1);
      const auto& row=decoded.construction.materials[0];
      CHECK(row.candidates.has_value()==(mode==0));
      if(row.candidates) { REQUIRE(row.candidates->size()==2);CHECK(row.candidates->at(0).id==10);
        CHECK(row.candidates->at(0).distance==2);CHECK(row.candidates->at(0).name=="iron bars [7]"); }
    }
  }
}

TEST_CASE("Connected Track preview validates complete geometry and preserves typed outcomes") {
  for(int mode=0;mode<16;++mode) {
    std::vector<wire::TilePos> path{{2,3,4},{1,3,4}};
    auto outcome=wire::ConnectedTrackStatus::Found;
    if(mode>=1 && mode<=5){outcome=wire::ConnectedTrackStatus(mode);path.clear();}
    if(mode==6)path.resize(1);
    if(mode==7)outcome=wire::ConnectedTrackStatus(6);
    if(mode==10)path[1]=wire::TilePos(-1,3,4);
    if(mode==11)path[1]=wire::TilePos(1,2,4);
    if(mode==12)path[1]=wire::TilePos(0,3,4);
    if(mode==13)path.push_back(path[0]);
    if(mode==14)outcome=wire::ConnectedTrackStatus::NoPath;
    if(mode==15)path.resize(wire::kConnectedTrackMaxTiles+1);
    flatbuffers::FlatBufferBuilder b;
    auto track=wire::CreateConnectedTrackPreview(b,outcome,b.CreateVectorOfStructs(path));
    const auto key=b.CreateString(mode==8?"Construction:Wall":"Construction:Track");
    wire::ConstructionStateBuilder construction(b);construction.add_building_key(key);construction.add_connected_track(track);
    const auto domain=construction.Finish();
    wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_status(wire::ManagementStatus::Ok);
    root.add_action(mode==9?wire::ManagementAction::Catalog:wire::ManagementAction::Preview);root.add_construction(domain);
    b.Finish(root.Finish());
    const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(bool(wire::validateManagementState(*state))==(mode>=6));
    if(mode<6) {
      wm::ManagementState decoded;codec::decodeConstruction(state,decoded);
      REQUIRE(decoded.construction.connectedTrack);
      CHECK(int(decoded.construction.connectedTrack->status)==mode);
      CHECK(decoded.construction.connectedTrack->path.size()==path.size());
      if(mode==0)CHECK(decoded.construction.connectedTrack->path==std::vector<wm::TilePos>{{2,3,4},{1,3,4}});
    }
  }
}

TEST_CASE("Connected Track keeps ordered endpoints and rejects ambiguous request geometry") {
  wm::ManagementRequest base;base.action=wm::ManagementAction::Preview;
  base.definition="Construction:Track";base.x=20;base.y=19;base.z=18;
  base.connectedTrackDestination=wm::TilePos{2,3,4};
  for(int mode=0;mode<13;++mode) {
    auto q=base;
    if(mode==1)q.action=wm::ManagementAction::Place;
    if(mode==2){q.action=wm::ManagementAction::ConstructionMaterials;q.filter=0;}
    if(mode==3)q.connectedTrackDestination=wm::TilePos{20,19,18}; // native stationary preview
    if(mode==4)q.connectedTrackDestination.reset();
    if(mode==5)q.connectedTrackDestination->x=-1;
    if(mode==6)q.definition="Construction:Wall";
    if(mode==7)q.action=wm::ManagementAction::Catalog;
    if(mode==8)q.width=2;
    if(mode==9)q.height=2;
    if(mode==10)q.depth=2;
    if(mode==11)q.direction=1;
    if(mode==12)q.retracting=true;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
    const auto* request=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CAPTURE(mode);
    CHECK(bool(wire::validateConstructionRequest(*request))==(mode>=4));
    if(mode<3) {
      REQUIRE(request->connected_track());REQUIRE(request->connected_track()->destination());
      CHECK(request->origin()->x()==20);CHECK(request->origin()->z()==18);
      CHECK(request->connected_track()->destination()->x()==2);
      CHECK(request->connected_track()->destination()->y()==3);
      CHECK(request->connected_track()->destination()->z()==4);
    }
  }
}

TEST_CASE("Staff edits require both receipts and reject unrelated fields") {
  wm::ManagementRequest base;base.action=wm::ManagementAction::AreaUpdate;
  auto& a=base.area;a.kind=wm::AreaKind::Zone;a.operation=wm::AreaOperation::LocationStaffEdit;
  a.locationSiteId=651;a.locationId=0;a.occupationId=87;
  a.expectedRevision=9007199254740993ULL;a.expectedListRevision=INT64_MAX;
  for(int mode=0;mode<24;++mode) {
    auto q=base;
    if(mode==1)q.area.unitId=0;
    if(mode==2)q.area.unitId=INT32_MAX;
    if(mode==3)q.area.expectedRevision=0;
    if(mode==4)q.area.expectedListRevision=0;
    if(mode==5)q.area.expectedRevision=uint64_t(INT64_MAX)+1;
    if(mode==6)q.area.expectedListRevision=uint64_t(INT64_MAX)+1;
    if(mode==7)q.area.locationSiteId=-1;
    if(mode==8)q.area.locationId=-1;
    if(mode==9)q.area.occupationId=-1;
    if(mode==10)q.area.unitId=-2;
    if(mode==11)q.area.id=0;
    if(mode==12)q.area.cursor=128;
    if(mode==13)q.area.query="fixture";
    if(mode==14)q.area.assign=1;
    if(mode==15)q.area.value=1;
    if(mode==16)q.area.kind=wm::AreaKind::Stockpile;
    if(mode==17)q.action=wm::ManagementAction::AreaInspect;
    if(mode==18)q.area.operation=wm::AreaOperation::LocationAccess;
    if(mode==19)q.area.locationKind=2;
    if(mode==20)q.area.countGeneration=1;
    if(mode==21)q.area.sort=1;
    if(mode==22)q.area.name="fixture";
    if(mode==23)q.area.operation=static_cast<wm::AreaOperation>(26);
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
    const auto* encoded=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(bool(wire::validateConstructionRequest(*encoded))==(mode>=3));
    CHECK(encoded->area()->unit_id()==q.area.unitId);
    CHECK(encoded->area()->expected_revision()==q.area.expectedRevision);
    CHECK(encoded->area()->expected_list_revision()==q.area.expectedListRevision);
  }
}

TEST_CASE("Staff candidate requests own occupation identity and paging receipt") {
  wm::ManagementRequest base;base.action=wm::ManagementAction::AreaInspect;
  auto& a=base.area;a.kind=wm::AreaKind::Zone;a.operation=wm::AreaOperation::LocationStaffCandidates;
  a.locationSiteId=651;a.locationId=0;a.occupationId=87;
  for(int mode=0;mode<17;++mode) {
    auto q=base;
    if(mode==1){q.area.cursor=128;q.area.expectedListRevision=INT64_MAX;}
    if(mode==2)q.area.locationSiteId=-1;
    if(mode==3)q.area.locationId=-1;
    if(mode==4)q.area.occupationId=-1;
    if(mode==5)q.area.id=0;
    if(mode==6)q.area.expectedRevision=1;
    if(mode==7)q.area.cursor=128;
    if(mode==8){q.area.cursor=1;q.area.expectedListRevision=1;}
    if(mode==9)q.area.query="fixture";
    if(mode==10)q.area.unitId=1;
    if(mode==11)q.action=wm::ManagementAction::AreaUpdate;
    if(mode==12)q.area.kind=wm::AreaKind::Stockpile;
    if(mode==13)q.area.operation=wm::AreaOperation::LocationDetails;
    if(mode==14)q.area.sort=1;
    if(mode==15)q.area.countGeneration=1;
    if(mode==16)q.area.occupationId=-2;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
    const auto* encoded=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(bool(wire::validateConstructionRequest(*encoded))==(mode>=2));
    CHECK(encoded->area()->occupation_id()==q.area.occupationId);
  }
}

TEST_CASE("Staff candidate replies reject malformed pages and preserve native facts") {
  for(int mode=0;mode<46;++mode) {
    flatbuffers::FlatBufferBuilder b;
    std::vector<flatbuffers::Offset<wire::LocationStaffCandidate>> rows;
    const int count=mode==17?129:mode==18?128:mode==19?0:2;
    for(int i=0;i<count;++i) {
      std::vector<flatbuffers::Offset<wire::LocationStaffSkill>> skills;
      skills.push_back(wire::CreateLocationStaffSkill(b,mode==10?-1:58,mode==11?-1:3,mode==12?-1:2000000,mode==13?0:1));
      if(mode==14)skills.push_back(wire::CreateLocationStaffSkill(b,58,3,0,1));
      if(mode==27)for(int j=0;j<10;++j)skills.push_back(wire::CreateLocationStaffSkill(b,j,0,0,1));
      rows.push_back(wire::CreateLocationStaffCandidate(b,mode==8?1:100+i,mode==9?-2:900+i,
          b.CreateString(std::string(mode==15?2049:mode==18?2048:5,'x')),mode==16?4:mode==26?i+2:3,b.CreateVector(skills),
          mode==32?flatbuffers::Offset<flatbuffers::String>{}:b.CreateString(std::string(mode==28?2049:mode==34?0:4,'b')),
          mode==33?flatbuffers::Offset<flatbuffers::String>{}:b.CreateString(std::string(mode==29?2049:mode==35?0:4,'p')),
          mode==30?-1:mode==31?16:7,i!=0,
          mode==36?-1:mode==37?0:mode==38?count:mode==45?1-i:i,mode==39?-1:809,mode==40?-1:100000,
          mode==41?flatbuffers::Offset<flatbuffers::Vector<uint8_t>>{}:b.CreateVector(std::vector<uint8_t>(mode==43?2049:2,255)),
          mode==42?flatbuffers::Offset<flatbuffers::Vector<uint8_t>>{}:b.CreateVector(std::vector<uint8_t>(mode==44?2049:2,128))));
    }
    const auto page=wire::CreateLocationStaffCandidates(b,mode==2?-1:651,0,mode==3?-1:87,mode==4?3:8,
        mode==5?0:INT64_MAX,mode==6?1:0,mode==7?128:0,mode==20?3:count,b.CreateVector(rows));
    wire::AreaStateBuilder area(b);area.add_operation(mode==21?wire::AreaOperation::None:wire::AreaOperation::LocationStaffCandidates);
    if(mode!=1 && mode!=22)area.add_location_staff_candidates(page);
    if(mode==23)area.add_next_cursor(128);
    const auto domain=area.Finish();wire::ManagementStateBuilder root(b);
    root.add_revision(1);root.add_world_epoch(7);root.add_action(mode==24?wire::ManagementAction::AreaUpdate:wire::ManagementAction::AreaInspect);
    root.add_status(mode==1 || mode==25?wire::ManagementStatus::Rejected:wire::ManagementStatus::Ok);root.add_area(domain);
    b.Finish(root.Finish());const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(bool(wire::validateManagementState(*state))==(mode!=0 && mode!=1 && mode!=19 && mode!=34 && mode!=35));
    if(mode==0) {
      const auto model=codec::decodeArea(state->area());REQUIRE(model.locationStaffCandidates);
      const auto& c=*model.locationStaffCandidates;CHECK(c.siteId==651);CHECK(c.locationId==0);CHECK(c.occupationId==87);
      CHECK(c.role==8);CHECK(c.revision==INT64_MAX);CHECK(c.cursor==0);CHECK(c.nextCursor==0);CHECK(c.total==2);
      REQUIRE(c.rows.size()==2);CHECK(c.rows[1].unitId==101);CHECK(c.rows[1].histfigId==901);
      CHECK(c.rows[1].sourceIndex==1);CHECK(c.rows[1].professionOrder==809);CHECK(c.rows[1].statusOrder==100000);
      CHECK(c.rows[1].nameSortKey==std::vector<uint8_t>{255,255});CHECK(c.rows[1].professionSortKey==std::vector<uint8_t>{128,128});
      CHECK(c.rows[1].baseName=="bbbb");CHECK(c.rows[1].professionName=="pppp");CHECK(c.rows[1].professionColor==7);
      CHECK_FALSE(c.rows[0].legendary);CHECK(c.rows[1].legendary); // unrelated skills can make the name legendary
      CHECK(c.rows[1].name=="xxxxx");CHECK(c.rows[1].score==3);REQUIRE(c.rows[1].skills.size()==1);
      CHECK(c.rows[1].skills[0].id==58);CHECK(c.rows[1].skills[0].rating==3);
      CHECK(c.rows[1].skills[0].experience==2000000);CHECK(c.rows[1].skills[0].weight==1);
    }
    if(mode==1)CHECK_FALSE(codec::decodeArea(state->area()).locationStaffCandidates);
  }
}

TEST_CASE("Location details requests require their own site and location identities") {
  wm::ManagementRequest request;request.action=wm::ManagementAction::AreaInspect;
  auto& a=request.area;a.kind=wm::AreaKind::Zone;a.operation=wm::AreaOperation::LocationDetails;
  a.locationSiteId=651;a.locationId=0;
  for(int mode=0;mode<11;++mode) {
    auto q=request;
    if(mode==1)q.area.locationSiteId=-1;
    if(mode==2)q.area.locationId=-1;
    if(mode==3)q.area.id=23;
    if(mode==4)q.area.expectedRevision=7;
    if(mode==5)q.area.cursor=1;
    if(mode==6)q.area.query="fixture";
    if(mode==7)q.area.expectedListRevision=7;
    if(mode==8)q.area.kind=wm::AreaKind::Stockpile;
    if(mode==9)q.action=wm::ManagementAction::AreaUpdate;
    if(mode==10){q.area.operation=wm::AreaOperation::LocationList;q.area.id=23;q.area.locationId=-2;}
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
    const auto* encoded=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(bool(wire::validateConstructionRequest(*encoded))==(mode!=0));
    if(mode==0){CHECK(encoded->area()->location_site_id()==651);CHECK(encoded->area()->location_id()==0);}
  }
}

TEST_CASE("Location details replies validate ownership and preserve raw facts") {
  for(int mode=0;mode<31;++mode) {
    const int appraisal=mode==12?-3:mode==13?-2:mode==14?-1:mode==15?0:mode==16?INT32_MAX:10;
    const int dx=mode==24?-2:mode==25?-1:mode==26?0:mode==27?-1:mode==28?0:mode==29?2:mode==30?INT32_MAX:7;
    const int dy=mode==25?-1:mode==26?0:mode==28?2:mode==29?0:8;
    flatbuffers::FlatBufferBuilder b;
    std::vector<flatbuffers::Offset<wire::LocationSupplyQuantity>> supplies;
    for(uint8_t i=0;i<(mode==2?9:10);++i)supplies.push_back(wire::CreateLocationSupplyQuantity(b,mode==3?0:i,INT32_MAX-i,15000+i));
    const auto zones=b.CreateVector(std::vector<int32_t>{23,mode==4?23:914});
    const auto facilities=wire::CreateLocationFacilities(b,mode==17?-1:3,7,1,1,17,1,2,mode==18?3:1);
    const auto detail=wire::CreateLocationDetails(b,mode==5?-1:651,0,mode==6?0:5,b.CreateString("Synthetic hospital"),
        mode==7?0:9007199254740993ULL,mode==8?3:0,true,true,false,-1,0,272,2,true,b.CreateVector(supplies),zones,appraisal,mode==19?0:facilities,mode==20?-2:mode==21?-1:mode==22?0:mode==23?INT32_MAX:6,dx,dy);
    wire::AreaStateBuilder area(b);area.add_operation(mode==9?wire::AreaOperation::None:wire::AreaOperation::LocationDetails);
    if(mode!=1 && mode!=10)area.add_location_details(detail);
    if(mode==11)area.add_next_cursor(1);
    const auto domain=area.Finish();wire::ManagementStateBuilder root(b);
    root.add_revision(1);root.add_world_epoch(7);root.add_action(wire::ManagementAction::AreaInspect);
    root.add_status(mode==1?wire::ManagementStatus::Rejected:wire::ManagementStatus::Ok);root.add_area(domain);
    b.Finish(root.Finish());const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(bool(wire::validateManagementState(*state))==((mode>=2 && mode<=12) || mode==17 || mode==18 || mode==20 || mode==24 || (mode>=27 && mode<=29)));
    if(mode==0 || (mode>=13 && mode!=17 && mode!=18 && mode!=20 && mode!=24 && !(mode>=27 && mode<=29))) {
      auto model=codec::decodeArea(state->area());REQUIRE(model.locationDetails);
      const auto& d=*model.locationDetails;CHECK(d.siteId==651);CHECK(d.id==0);CHECK(d.kind==5);
      CHECK(d.revision==9007199254740993LL);CHECK(d.name=="Synthetic hospital");CHECK(d.recognized);
      CHECK(d.visitors);CHECK(d.residents);CHECK_FALSE(d.members);CHECK(d.access==0);
      CHECK(d.profession==-1);CHECK(d.tier==0);CHECK(d.value==272);CHECK(d.desiredCopies==2);CHECK(d.appraisal==appraisal);
      CHECK(d.writtenObjects==(mode==21?-1:mode==22?0:mode==23?INT32_MAX:6));
      CHECK_FALSE(d.staff);
      CHECK(d.danceFloorX==dx);CHECK(d.danceFloorY==dy);
      REQUIRE(d.supplies.size()==10);CHECK(d.supplies[4].kind==4);CHECK(d.supplies[4].stored==INT32_MAX-4);CHECK(d.supplies[4].desired==15004);
      CHECK(d.zoneIds==std::vector<int32_t>{23,914});
      if(mode==19)CHECK_FALSE(d.facilities);
      else {REQUIRE(d.facilities);const auto& f=*d.facilities;
        CHECK(f.chests==3);CHECK(f.beds==7);CHECK(f.tables==1);CHECK(f.tractionBenches==1);
        CHECK(f.bookcases==17);CHECK(f.chairs==1);CHECK(f.rooms==2);CHECK(f.rentedRooms==1);}

    }
    if(mode==1)CHECK_FALSE(codec::decodeArea(state->area()).locationDetails);
  }
}

TEST_CASE("Location choice requests own only catalog selector and page receipt") {
  wm::ManagementRequest request;request.action=wm::ManagementAction::AreaInspect;
  request.area.kind=wm::AreaKind::Zone;request.area.operation=wm::AreaOperation::LocationChoices;request.area.locationKind=2;
  for(int mode=0;mode<12;++mode) {
    auto q=request;
    if(mode==1){q.area.locationKind=4;q.area.cursor=128;q.area.expectedListRevision=19;}
    if(mode==2)q.area.locationKind=1;
    if(mode==3)q.area.id=4;
    if(mode==4)q.area.expectedRevision=3;
    if(mode==5)q.area.cursor=128;
    if(mode==6){q.area.cursor=1;q.area.expectedListRevision=19;}
    if(mode==7)q.area.profession=41;
    if(mode==8)q.area.query="fixture";
    if(mode==9)q.area.kind=wm::AreaKind::Stockpile;
    if(mode==10)q.action=wm::ManagementAction::AreaUpdate;
    if(mode==11)q.area.countGeneration=5;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
    CAPTURE(mode);
    CHECK(bool(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer())))==(mode>=2));
  }
}

TEST_CASE("Typed location pages validate nested identities and preserve model metadata") {
  for(int mode=0;mode<10;++mode) {
    flatbuffers::FlatBufferBuilder b;
    auto deity=wire::CreateLocationDeity(b,7,b.CreateString("Synthetic deity"),b.CreateVector(std::vector<int32_t>{3,mode==2?130:8}));
    auto sentinel=wire::CreateLocationReligion(b,1,-1,b.CreateString(""),0,false);
    auto named=wire::CreateLocationReligion(b,2,mode==3?9:7,b.CreateString("Synthetic deity"),mode==4?-1:24,true,b.CreateVector(std::vector{deity}));
    auto rows=b.CreateVector(std::vector{sentinel,named});
    auto catalog=wire::CreateLocationCatalog(b,mode==5?4:2,mode==6?0:25,mode==7?1:0,mode==8?3:2,mode==9?128:0,rows);
    wire::AreaStateBuilder area(b);area.add_operation(mode==1?wire::AreaOperation::None:wire::AreaOperation::LocationChoices);area.add_location_catalog(catalog);
    const auto domain=area.Finish();wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_status(wire::ManagementStatus::Ok);root.add_area(domain);
    b.Finish(root.Finish());
    const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());const auto* wireArea=state->area();
    CAPTURE(mode);
    CHECK(bool(wire::validateLocationCatalog(*wireArea->location_catalog()))==(mode>=2));
    CHECK(bool(wire::validateManagementState(*state))==(mode>=1));
    if(mode==0) {
      const auto model=codec::decodeArea(wireArea);
      REQUIRE(model.locationCatalog);CHECK(model.locationCatalog->revision==25);
      REQUIRE(model.locationCatalog->religions.size()==2);
      const auto& row=model.locationCatalog->religions[1];CHECK(row.id==7);CHECK(row.worshippers==24);CHECK(row.hasTemple);
      REQUIRE(row.deities.size()==1);CHECK(row.deities[0].name=="Synthetic deity");CHECK(row.deities[0].spheres==std::vector<int32_t>{3,8});
    }
  }
}

TEST_CASE("management schema defaults match the versioned transport") {
  flatbuffers::FlatBufferBuilder b;
  b.Finish(wire::CreateConstructionRequest(b));
  CHECK(flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer())->schema_version()==wire::kManagementVersion);
  b.Clear();b.Finish(wire::CreateManagementState(b));
  CHECK(flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer())->schema_version()==wire::kManagementVersion);
}

TEST_CASE("Paint count requests preserve local geometry and reject mutation fields") {
  wm::ManagementRequest request;request.action=wm::ManagementAction::AreaInspect;
  auto& a=request.area;a.kind=wm::AreaKind::Zone;a.operation=wm::AreaOperation::PaintCounts;
  a.zoneType=92;a.paintZ=32767;a.countGeneration=INT64_MAX;
  for(int mode=0;mode<18;++mode) {
    auto q=request;auto& v=q.area;
    if(mode==1)v.paintPreview=wm::AreaPaintPreview{32767,32767,1,1};
    if(mode==2) {
      for(int y=0;y<128;++y)for(int x=0;x<256;++x)v.spans.push_back({int16_t(y),int16_t(x),1});
      v.paintPreview=wm::AreaPaintPreview{0,0,256,128};
    }
    if(mode==3)v.countGeneration=0;
    if(mode==4)v.countGeneration=-1;
    if(mode==5)v.id=1;
    if(mode==6)v.expectedRevision=1;
    if(mode==7)v.interactionId=1;
    if(mode==8)v.undoToken=1;
    if(mode==9)v.paintMode=1;
    if(mode==10)q.action=wm::ManagementAction::AreaCreate;
    if(mode==11)v.paintPreview=wm::AreaPaintPreview{32767,0,2,1};
    if(mode==12)v.paintPreview=wm::AreaPaintPreview{0,0,256,129};
    if(mode==13)v.spans={{1,0,2},{1,1,1}};
    if(mode==14)v.spans={{1,0,1},{0,0,1}};
    if(mode==15)v.spans={{0,0,1},{256,0,1}};
    if(mode==16)v.paintZ=-1;
    if(mode==17)v.kind=wm::AreaKind::Stockpile;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
    const auto* wireRequest=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(bool(wire::validateConstructionRequest(*wireRequest))==(mode>=3));
    if(mode<3) {
      CHECK(b.GetSize()<wire::kManagementCommandCapacity);
      CHECK(wireRequest->area()->count_generation()==uint64_t(INT64_MAX));
      CHECK(wireRequest->area()->paint_z()==32767);
      CHECK_FALSE(wireRequest->area()->origin());
      CHECK(bool(wireRequest->area()->paint_preview())==(mode!=0));
      if(mode==1)CHECK(wireRequest->area()->paint_preview()->x()==32767);
      if(mode==2)CHECK(wireRequest->area()->spans()->size()==32768);
    }
  }
  for(int field=0;field<2;++field) {
    auto q=request;q.action=wm::ManagementAction::AreaCreate;
    q.area.operation=wm::AreaOperation::Paint;q.area.paintMode=1;q.area.spans={{0,0,1}};
    q.area.countGeneration=field==0?1:0;
    if(field==1)q.area.paintPreview=wm::AreaPaintPreview{0,0,1,1};
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
    CHECK(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer())).has_value());
  }
}

TEST_CASE("Paint count replies distinguish unknown from zero and reject foreign fields") {
  for(int mode=0;mode<11;++mode) {
    flatbuffers::FlatBufferBuilder b;wire::AreaStateBuilder a(b);
    a.add_operation(mode==10?wire::AreaOperation::Paint:wire::AreaOperation::PaintCounts);
    a.add_count_generation(mode==3?0:mode==4?uint64_t(INT64_MAX)+1:uint64_t(INT64_MAX));
    a.add_painted_count(mode==0?-1:mode==1?0:mode==5?-2:mode==6?32769:32768);
    a.add_preview_count(mode==0?3:0);
    if(mode==7)a.add_interaction_id(1);
    if(mode==8)a.add_next_cursor(1);
    if(mode==9)a.add_area_id(1);
    const auto area=a.Finish();wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_area(area);
    b.Finish(root.Finish());const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(bool(wire::validateManagementState(*state))==(mode>=3));
    if(mode<3) {
      const auto result=codec::decodeArea(state->area());
      CHECK(result.countGeneration==INT64_MAX);CHECK(result.paintedCount==(mode==0?-1:mode==1?0:32768));
      CHECK(result.previewCount==(mode==0?3:0));CHECK(result.undoToken==0);
    }
  }
}

TEST_CASE("Multi requests carry selection and scoped Undo without area-page limits") {
  for(int op=16;op<=18;++op) {
    wm::ManagementRequest request;
    request.action=op==16?wm::ManagementAction::AreaCreate:wm::ManagementAction::AreaUpdate;
    auto& a=request.area;a.kind=wm::AreaKind::Zone;a.operation=wm::AreaOperation(op);a.interactionId=INT64_MAX;
    if(op==16){a.x=0;a.y=0;a.z=32767;a.width=32768;a.height=32768;a.roomFurniture=4;}
    if(op==17)a.undoToken=INT64_MAX;
    for(int defect=0;defect<8;++defect) {
      auto candidate=request;auto& v=candidate.area;
      if(defect==1)v.interactionId=0;
      if(defect==2)v.id=1;
      if(defect==3)v.expectedRevision=1;
      if(defect==4)v.kind=wm::AreaKind::Stockpile;
      if(defect==5){if(op==16)v.x=1;else v.roomFurniture=1;}
      if(defect==6){if(op==17)v.undoToken=0;else v.undoToken=1;}
      if(defect==7)v.interactionId=-1;
      flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,candidate,1,2,3);
      const auto* r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
      const auto error=wire::validateConstructionRequest(*r);CAPTURE(op);CAPTURE(defect);
      CHECK(bool(error)==(defect!=0));
      if(!defect) {
        CHECK(r->area()->interaction_id()==uint64_t(INT64_MAX));
        CHECK(r->area()->undo_token()==uint64_t(a.undoToken));
        CHECK(bool(r->area()->origin())==(op==16));
        if(op==16){CHECK(r->area()->width()==32768);CHECK(r->area()->room_furniture()==4);}
      }
    }
  }
}

TEST_CASE("Multi receipt replies carry native counts independently of area records") {
  for(int op=16;op<=18;++op)for(int defect=0;defect<7;++defect) {
    flatbuffers::FlatBufferBuilder b;
    wire::AreaStateBuilder a(b);a.add_operation(wire::AreaOperation(op));
    a.add_interaction_id(defect==1?0:INT64_MAX);
    a.add_room_outcome(defect==2?wire::AreaRoomOutcome::None:wire::AreaRoomOutcome::Completed);
    if(op==16){a.add_undo_token(defect==3?0:INT64_MAX);a.add_rooms_created(129);a.add_rooms_in_use(1000);a.add_rooms_unenclosed(2000);}
    else {if(defect==3)a.add_undo_token(1);if(op==17)a.add_rooms_removed(129);}
    if(defect==4)a.add_area_id(7);
    if(defect==5)a.add_next_cursor(1);
    a.add_rooms_dormitories(defect==6?130:op==16?7:0);
    const auto domain=a.Finish();wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_area(domain);
    b.Finish(root.Finish());const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CAPTURE(op);CAPTURE(defect);CHECK(bool(wire::validateManagementState(*state))==(defect!=0));
    if(!defect) {
      const auto result=codec::decodeArea(state->area());
      CHECK(result.interactionId==INT64_MAX);CHECK(result.areas.empty());
      CHECK(result.roomOutcome==wm::AreaRoomOutcome::Completed);
      CHECK(result.roomsDormitories==uint32_t(op==16?7:0));
      if(op==16){CHECK(result.undoToken==INT64_MAX);CHECK(result.roomsCreated==129);CHECK(result.roomsInUse==1000);CHECK(result.roomsUnenclosed==2000);}
      if(op==17)CHECK(result.roomsRemoved==129);
    }
  }
}

TEST_CASE("Multi request fields cannot leak into older area operations") {
  for(int field=0;field<3;++field) {
    wm::ManagementRequest request;request.action=wm::ManagementAction::AreaCreate;
    auto& a=request.area;a.operation=wm::AreaOperation::Paint;a.paintMode=1;a.paintZ=0;a.spans={{0,0,1}};
    if(field==0)a.roomFurniture=1;
    if(field==1)a.interactionId=1;
    if(field==2)a.undoToken=1;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    const auto* r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(wire::validateConstructionRequest(*r).has_value());
  }
  for(int op=16;op<=18;++op)for(int action=8;action<=14;++action) {
    wm::ManagementRequest request;request.action=wm::ManagementAction(action);
    auto& a=request.area;a.operation=wm::AreaOperation(op);a.kind=wm::AreaKind::Zone;a.interactionId=1;
    if(op==16)a.roomFurniture=1;
    if(op==17)a.undoToken=1;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    const auto* r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(bool(wire::validateConstructionRequest(*r))!=(action==(op==16?10:11)));
  }
}

TEST_CASE("Multi outcomes distinguish empty creation and uncertain partial removal") {
  for(int mode=0;mode<5;++mode) {
    flatbuffers::FlatBufferBuilder b;wire::AreaStateBuilder a(b);
    a.add_operation(mode==0?wire::AreaOperation::MultiCreate:wire::AreaOperation::MultiUndo);
    a.add_interaction_id(1);
    a.add_room_outcome(mode==0?wire::AreaRoomOutcome::Completed:
        mode==1?wire::AreaRoomOutcome::Unknown:mode==2?wire::AreaRoomOutcome::Rejected:wire::AreaRoomOutcome::Stale);
    if(mode==1 || mode==4)a.add_rooms_removed(2);
    const auto domain=a.Finish();wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_area(domain);
    b.Finish(root.Finish());const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*state))==(mode==4));
  }
}

TEST_CASE("area paint wire contract refuses retired replacement mode") {
  for(auto kind:{wm::AreaKind::Stockpile,wm::AreaKind::Zone}) {
    wm::ManagementRequest request;request.action=wm::ManagementAction::AreaUpdate;
    auto& a=request.area;a.kind=kind;a.id=7;a.expectedRevision=1;
    a.operation=wm::AreaOperation::Paint;a.paintMode=3;a.paintZ=0;a.spans={{0,0,1}};
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    const auto* r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(wire::validateConstructionRequest(*r).value_or("")=="invalid area paint");
  }
}

TEST_CASE("full paint fits one versioned management command") {
  wm::ManagementRequest request;request.action=wm::ManagementAction::AreaCreate;
  auto& a=request.area;a.operation=wm::AreaOperation::Paint;a.paintMode=1;a.paintZ=3;
  // Deliberately uncoalesced worst case: one span per supported footprint cell.
  for(int y=0;y<128;++y)for(int x=0;x<256;++x)a.spans.push_back({int16_t(y),int16_t(x),1});
  flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
  CHECK(b.GetSize()<wire::kManagementCommandCapacity);
  const auto* r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
  CHECK(wire::validateConstructionRequest(*r).value_or("")=="");
  CHECK(r->area()->spans()->size()==32768);
  a.spans.push_back({128,0,1});b.Clear();codec::encodeRequest(b,request,1,2,3);
  r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
  CHECK(wire::validateConstructionRequest(*r).value_or("")=="too many area spans");
}

TEST_CASE("area operation codecs preserve every selector and omit legacy origin") {
  const wm::ManagementAction actions[]{wm::ManagementAction::AreaInspect,wm::ManagementAction::AreaInspect,
      wm::ManagementAction::AreaUpdate,wm::ManagementAction::AreaUpdate,wm::ManagementAction::AreaUpdate,
      wm::ManagementAction::AreaCreate,wm::ManagementAction::AreaInspect,wm::ManagementAction::AreaUpdate,
      wm::ManagementAction::AreaUpdate,wm::ManagementAction::AreaUpdate,wm::ManagementAction::AreaInspect,
      wm::ManagementAction::AreaUpdate,wm::ManagementAction::AreaUpdate,wm::ManagementAction::AreaUpdate,
      wm::ManagementAction::AreaCandidates,wm::ManagementAction::AreaLink};
  for(int op=0;op<=15;++op) {
    CAPTURE(op);
    wm::ManagementRequest request;request.action=actions[op];auto& a=request.area;
    a.operation=wm::AreaOperation(op);a.id=7;a.expectedRevision=INT64_MAX;a.query="observed";a.cursor=128;
    a.kind=op==15?wm::AreaKind::Workshop:((op>=6 && op<=9) || op==11 || op==12 || op==14)?wm::AreaKind::Zone:wm::AreaKind::Stockpile;
    if(op==0){a.x=10;a.y=11;a.z=12;a.width=3;a.height=4;a.categories=3;a.changedCategories=1;a.barrels=2;a.bins=3;a.wheelbarrows=1;a.linksOnly=1;}
    if(op==1 || op==6 || op==10 || op==14)a.expectedListRevision=INT64_MAX;
    if(op==1 || op==2)a.listKey="food/meat";
    if(op==2){a.rowKey="material:4";a.scope=1;a.value=2;}
    if(op==3)a.preset=19;
    if(op==4)a.name="Native name";
    if(op==5){a.id=-1;a.paintZ=17;a.paintMode=1;a.spans={{14,15,128},{15,15,256}};a.zoneType=1;}
    if(op==7)a.locationId=-1;
    if(op==8){a.locationKind=2;a.deityKind=3;a.deityId=900;}
    if(op==9)a.zoneSettings={2,4,0,1,1,0,1};
    if(op==11){a.unitId=0;a.assign=0;}
    if(op==12){a.squadId=0;a.squadUse=0;}
    if(op==13){a.organic=0;a.inorganic=1;}
    if(op==14){a.candidateKind=3;a.sort=3;a.sortDescending=true;}
    if(op==15){a.linkId=8;a.give=false;a.unlink=true;}
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    const auto* r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(wire::validateConstructionRequest(*r).value_or("")=="");
    const auto* q=r->area();REQUIRE(q);CHECK(int(q->operation())==op);CHECK(q->id()==a.id);CHECK(int(q->kind())==int(a.kind));
    CHECK(q->expected_revision()==INT64_MAX);CHECK(q->expected_list_revision()==uint64_t(a.expectedListRevision));
    CHECK(q->query()->str()==a.query);CHECK(q->cursor()==a.cursor);
    CHECK((q->origin()!=nullptr)==(op==0));
    if(q->origin()){CHECK(q->origin()->x()==10);CHECK(q->origin()->y()==11);CHECK(q->origin()->z()==12);}
    CHECK(q->width()==a.width);CHECK(q->height()==a.height);CHECK(q->zone_type()==a.zoneType);
    CHECK(q->categories()==a.categories);CHECK(q->changed_categories()==a.changedCategories);
    CHECK(q->barrels()==a.barrels);CHECK(q->bins()==a.bins);CHECK(q->wheelbarrows()==a.wheelbarrows);
    CHECK(q->links_only()==a.linksOnly);CHECK(q->active()==a.active);CHECK(q->owner_id()==a.ownerId);
    CHECK(q->link_id()==a.linkId);CHECK(q->give()==a.give);CHECK(q->unlink()==a.unlink);
    CHECK(q->list_key()->str()==a.listKey);CHECK(q->row_key()->str()==a.rowKey);CHECK(q->name()->str()==a.name);
    CHECK(q->scope()==a.scope);CHECK(q->value()==a.value);CHECK(q->preset()==a.preset);
    CHECK(q->spans()->size()==a.spans.size());
    for(size_t i=0;i<a.spans.size();++i){CHECK(q->spans()->Get(i)->y()==a.spans[i].y);CHECK(q->spans()->Get(i)->x()==a.spans[i].x);CHECK(q->spans()->Get(i)->length()==a.spans[i].length);}
    CHECK(q->paint_mode()==a.paintMode);CHECK(q->paint_z()==a.paintZ);CHECK(q->location_id()==a.locationId);
    CHECK(q->location_kind()==a.locationKind);CHECK(q->profession()==a.profession);CHECK(q->deity_kind()==a.deityKind);CHECK(q->deity_id()==a.deityId);
    REQUIRE(q->zone_settings());const auto* z=q->zone_settings();
    CHECK(z->pond_mode()==a.zoneSettings.pondMode);CHECK(z->facing()==a.zoneSettings.facing);
    CHECK(z->tomb_citizens()==a.zoneSettings.tombCitizens);CHECK(z->tomb_pets()==a.zoneSettings.tombPets);
    CHECK(z->gather_trees()==a.zoneSettings.gatherTrees);CHECK(z->gather_shrubs()==a.zoneSettings.gatherShrubs);CHECK(z->gather_fallen()==a.zoneSettings.gatherFallen);
    CHECK(q->unit_id()==a.unitId);CHECK(q->assign()==a.assign);CHECK(q->squad_id()==a.squadId);CHECK(q->squad_use()==a.squadUse);
    CHECK(q->organic()==a.organic);CHECK(q->inorganic()==a.inorganic);CHECK(q->candidate_kind()==a.candidateKind);
    CHECK(q->sort()==a.sort);CHECK(q->sort_descending()==a.sortDescending);
    a.expectedRevision=0;
    flatbuffers::FlatBufferBuilder missing;codec::encodeRequest(missing,request,1,2,3);
    const bool mutation=request.action==wm::ManagementAction::AreaUpdate || request.action==wm::ManagementAction::AreaLink;
    CHECK(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(missing.GetBufferPointer())).value_or("") ==
        (mutation ? "area revision required" : ""));
  }
}

TEST_CASE("legacy area mutations and update paint require an inspection revision") {
  for(auto action:{wm::ManagementAction::AreaUpdate,wm::ManagementAction::AreaDelete,wm::ManagementAction::AreaLink}) {
    for(int64_t revision:{int64_t(0),int64_t(1),INT64_MAX}) {
      wm::ManagementRequest request;request.action=action;request.area.id=7;request.area.linkId=8;
      request.area.expectedRevision=revision;
      flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
      CHECK(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer())).value_or("") ==
          (revision ? "" : "area revision required"));
    }
  }
  wm::ManagementRequest paint;paint.action=wm::ManagementAction::AreaUpdate;
  paint.area.operation=wm::AreaOperation::Paint;paint.area.id=7;paint.area.paintMode=1;paint.area.spans={{1,1,1}};
  for(int64_t revision:{int64_t(0),INT64_MAX}) {
    paint.area.expectedRevision=revision;flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,paint,1,2,3);
    CHECK(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer())).value_or("") ==
        (revision ? "" : "area revision required"));
  }
}

TEST_CASE("legacy area choices cannot share a response with area records or new pages") {
  for(int family=0;family<5;++family) {
    CAPTURE(family);flatbuffers::FlatBufferBuilder b;
    const auto text=b.CreateString("observed");
    const auto choices=b.CreateVector(std::vector{wire::CreateAreaChoice(b,1,text,text)});
    wire::TilePos origin(1,2,3);
    wire::AreaInfoBuilder info(b);info.add_id(7);info.add_origin(&origin);info.add_width(1);info.add_height(1);
    const auto areas=b.CreateVector(std::vector{info.Finish()});
    const auto settings=b.CreateVector(std::vector{wire::CreateAreaSettingRow(b,text,0,text,1,1)});
    const auto locations=b.CreateVector(std::vector{wire::CreateAreaLocationRow(b,1,text,1)});
    const auto candidates=b.CreateVector(std::vector{wire::CreateAreaCandidateRow(b,1,text)});
    const auto links=b.CreateVector(std::vector{wire::CreateAreaLinkRow(b,1,wire::AreaKind::Stockpile,1,text)});
    wire::AreaStateBuilder area(b);area.add_choices(choices);
    if(family==0)area.add_areas(areas);
    if(family==1)area.add_settings(settings);
    if(family==2)area.add_locations(locations);
    if(family==3)area.add_candidates(candidates);
    if(family==4)area.add_links(links);
    const auto domain=area.Finish();wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_area(domain);b.Finish(root.Finish());
    CHECK(wire::validateManagementState(*flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer())).value_or("") == "area response mixes list families");
  }
}

TEST_CASE("work order choices reject area-only labels but retain legacy names") {
  for(int label=0;label<3;++label) {
    flatbuffers::FlatBufferBuilder b;const auto name=b.CreateString("native name");
    const auto areaLabel=label ? b.CreateString(label==1 ? "" : "area label") : flatbuffers::Offset<flatbuffers::String>{};
    const auto choices=b.CreateVector(std::vector{wire::CreateAreaChoice(b,1,name,areaLabel)});
    wire::WorkOrderStateBuilder work(b);work.add_choices(choices);const auto domain=work.Finish();
    wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_work_order(domain);b.Finish(root.Finish());
    CHECK(wire::validateManagementState(*flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer())).value_or("") ==
        (label==2 ? "invalid work order choice" : ""));
  }
}

TEST_CASE("area response codec carries list families and unknown sentinels") {
  for(int family=0;family<6;++family) {
    CAPTURE(family);flatbuffers::FlatBufferBuilder b;
    const auto text=b.CreateString("observed"),key=b.CreateString("food/meat");
    const auto zone=wire::CreateAreaZoneSettings(b,2,4,0,1,1,0,1);
    const auto extents=b.CreateVector(std::vector<uint8_t>{1});wire::TilePos origin(1,2,3);
    wire::AreaInfoBuilder info(b);info.add_id(7);info.add_origin(&origin);info.add_width(1);info.add_height(1);info.add_extents(extents);
    info.add_name(text);info.add_custom_name(key);info.add_revision(INT64_MAX);info.add_zone_label(text);info.add_location_id(99);info.add_location_site_id(651);info.add_location_name(text);
    info.add_religion(text);info.add_organic(0);info.add_inorganic(1);info.add_zone_settings(zone);info.add_tile_count(1);info.add_storage_limit(1);info.add_assigned_count(4);
    info.add_location_kind(2);info.add_owner_profession(text);info.add_owner_sex(1);
    const auto record=info.Finish();const auto areas=b.CreateVector(std::vector{record});
    const auto setting=wire::CreateAreaSettingRow(b,key,5,text,4,3,true);const auto settings=b.CreateVector(std::vector{setting});
    const auto location=wire::CreateAreaLocationRow(b,99,text,4,text,41,2,651);const auto locations=b.CreateVector(std::vector{location});
    const auto candidate=wire::CreateAreaCandidateRow(b,8,text,text,1,7,true,true,15);const auto candidates=b.CreateVector(std::vector{candidate});
    const auto link=wire::CreateAreaLinkRow(b,9,wire::AreaKind::Workshop,2,text);const auto links=b.CreateVector(std::vector{link});
    const auto choice=wire::CreateAreaChoice(b,1,text,text);const auto choices=b.CreateVector(std::vector{choice});
    wire::AreaStateBuilder area(b);area.add_operation(wire::AreaOperation::CandidateList);area.add_area_id(7);area.add_list_key(key);
    area.add_candidate_kind(3);area.add_sort(2);area.add_sort_descending(true);area.add_query(text);area.add_list_revision(INT64_MAX);
    area.add_build_phase(2);area.add_build_done(18);area.add_build_total(19);area.add_omitted(4);area.add_captured_tick(9876543210);
    area.add_next_cursor(128);area.add_truncated(true);
    if(family<4)area.add_areas(areas);
    if(family==0)area.add_settings(settings);
    if(family==1)area.add_locations(locations);
    if(family==2)area.add_candidates(candidates);
    if(family==3)area.add_links(links);
    if(family==4)area.add_choices(choices);
    const auto domain=area.Finish();wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_area(domain);b.Finish(root.Finish());
    const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    REQUIRE_FALSE(wire::validateManagementState(*state));const auto decoded=codec::decodeArea(state->area());
    CHECK(decoded.operation==wm::AreaOperation::CandidateList);CHECK(decoded.areaId==7);CHECK(decoded.listKey=="food/meat");
    CHECK(decoded.candidateKind==3);CHECK(decoded.sort==2);CHECK(decoded.sortDescending);CHECK(decoded.query=="observed");
    CHECK(decoded.listRevision==INT64_MAX);CHECK(decoded.buildPhase==2);CHECK(decoded.buildDone==18);CHECK(decoded.buildTotal==19);
    CHECK(decoded.omitted==4);CHECK(decoded.capturedTick==9876543210);CHECK(decoded.nextCursor==128);CHECK(decoded.truncated);
    if(family<4){REQUIRE(decoded.areas.size()==1);const auto& v=decoded.areas[0];CHECK(v.revision==INT64_MAX);CHECK(v.zoneLabel=="observed");
      CHECK(v.locationId==99);CHECK(v.locationSiteId==651);CHECK(v.locationName=="observed");CHECK(v.religion=="observed");CHECK(v.organic==0);CHECK(v.inorganic==1);
      CHECK(v.zoneSettings==wm::AreaZoneSettings{2,4,0,1,1,0,1});CHECK(v.tileCount==1);CHECK(v.storageLimit==1);CHECK(v.customName=="food/meat");CHECK(v.assignedCount==4);
      CHECK(v.locationKind==2);CHECK(v.ownerProfession=="observed");CHECK(v.ownerSex==1);}
    if(family==0){REQUIRE(decoded.settings.size()==1);const auto& v=decoded.settings[0];CHECK(v.key=="food/meat");CHECK(v.index==5);CHECK(v.label=="observed");CHECK(v.kind==4);CHECK(v.state==3);CHECK(v.estimated);}
    if(family==1){REQUIRE(decoded.locations.size()==1);const auto& v=decoded.locations[0];CHECK(v.id==99);CHECK(v.name=="observed");CHECK(v.locationKind==4);CHECK(v.religion=="observed");CHECK(v.guildProfession==41);CHECK(v.locationTier==2);CHECK(v.siteId==651);}
    if(family==2){REQUIRE(decoded.candidates.size()==1);const auto& v=decoded.candidates[0];CHECK(v.id==8);CHECK(v.name=="observed");CHECK(v.profession=="observed");CHECK(v.sex==1);CHECK(v.mood==7);CHECK(v.grazer);CHECK(v.assigned);CHECK(v.squadUse==15);}
    if(family==3){REQUIRE(decoded.links.size()==1);const auto& v=decoded.links[0];CHECK(v.id==9);CHECK(v.kind==wm::AreaKind::Workshop);CHECK(v.direction==2);CHECK(v.name=="observed");}
    if(family==4){REQUIRE(decoded.choices.size()==1);CHECK(decoded.choices[0].label=="observed");}
    if(family==5){CHECK(decoded.areas.empty());CHECK(decoded.candidates.empty());}
  }
  flatbuffers::FlatBufferBuilder b;b.Finish(wire::CreateAreaState(b));
  const auto empty=codec::decodeArea(flatbuffers::GetRoot<wire::AreaState>(b.GetBufferPointer()));
  CHECK(empty.areaId==-1);CHECK(empty.capturedTick==-1);CHECK(empty.listRevision==0);CHECK(empty.buildPhase==0);
  CHECK(wm::AreaRequest{}.locationId==-2);CHECK(wm::AreaRequest{}.deityKind==-1);CHECK(wm::AreaInfo{}.tileCount==-1);CHECK(wm::AreaInfo{}.storageLimit==-1);CHECK(wm::AreaInfo{}.locationSiteId==-1);CHECK(wm::AreaLocationRow{}.siteId==-1);
}

TEST_CASE("area metadata validates boundaries and preserves unknown values") {
  for(int variant=0;variant<10;++variant) {
    flatbuffers::FlatBufferBuilder b;wire::TilePos origin(1,2,3);
    const auto extents=b.CreateVector(std::vector<uint8_t>{1});
    const auto profession=b.CreateString(std::string(variant==4 ? 513 : 0,'x'));
    const auto custom=b.CreateString(std::string(variant==8 ? 513 : variant==9 ? 512 : 0,'n'));
    wire::AreaInfoBuilder info(b);info.add_id(7);info.add_origin(&origin);info.add_width(1);info.add_height(1);info.add_extents(extents);
    info.add_location_kind(variant==1 ? 6 : 0);info.add_owner_sex(variant==2 ? 2 : variant==3 ? -2 : -1);info.add_owner_profession(profession);
    info.add_custom_name(custom);
    if(variant==5)info.add_storage_limit(-2);
    if(variant==6)info.add_storage_limit(32768);
    if(variant==7){info.add_kind(wire::AreaKind::Zone);info.add_storage_limit(0);}
    const auto rows=b.CreateVector(std::vector{info.Finish()});
    const auto area=wire::CreateAreaState(b,rows);wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_area(area);b.Finish(root.Finish());
    const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(wire::validateManagementState(*state).has_value()==(variant!=0 && variant!=9));
    if(variant==0){const auto decoded=codec::decodeArea(state->area());REQUIRE(decoded.areas.size()==1);
      CHECK(decoded.areas[0].overlapping==-1);CHECK(decoded.areas[0].storageLimit==-1);CHECK(decoded.areas[0].locationKind==0);CHECK(decoded.areas[0].ownerSex==-1);CHECK(decoded.areas[0].ownerProfession.empty());}
  }
}

TEST_CASE("area overlap observation bounds and unknown defaults") {
  for(const auto kind:{wire::AreaKind::Stockpile,wire::AreaKind::Zone})for(int value=-2;value<=2;++value) {
    flatbuffers::FlatBufferBuilder b;wire::TilePos origin(1,2,3);
    const auto extents=b.CreateVector(std::vector<uint8_t>{1});
    wire::AreaInfoBuilder info(b);info.add_id(7);info.add_kind(kind);info.add_origin(&origin);
    info.add_width(1);info.add_height(1);info.add_extents(extents);info.add_overlapping(int8_t(value));
    const auto rows=b.CreateVector(std::vector{info.Finish()});
    const auto area=wire::CreateAreaState(b,rows);wire::ManagementStateBuilder root(b);
    root.add_revision(1);root.add_area(area);b.Finish(root.Finish());
    const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    const bool valid=value>=-1 && value<=1 && (kind==wire::AreaKind::Zone || value==-1);
    CHECK(wire::validateManagementState(*state).has_value()==!valid);
    if(valid)CHECK(codec::decodeArea(state->area()).areas[0].overlapping==value);
  }
}

TEST_CASE("work detail request boundaries and absent optional edits") {
  auto check=[](const wm::ManagementRequest& r,const std::string& expected) {
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,1,7);
    auto error=wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer()));
    CHECK(error.value_or("")==expected);
  };
  wm::ManagementRequest r;r.action=wm::ManagementAction::WorkDetailCreate;r.citizen.expectedRevision=INT64_MAX;
  check(r,"");r.citizen.name="";r.citizen.labors={};check(r,"");
  r.citizen.unitId=-2;check(r,"invalid citizen request");r.citizen.unitId=-1;
  r.citizen.detailIndex=-2;check(r,"invalid citizen request");r.citizen.detailIndex=-1;
  r.citizen.member=0;check(r,"unexpected citizen edit fields");r.citizen.member=-1;
  r.citizen.mode=0;check(r,"unexpected citizen edit fields");r.citizen.mode=-1;
  r.citizen.edit=1;check(r,"unexpected work detail edit");r.citizen.edit=0;
  r.citizen.onlyAssigned=0;check(r,"unexpected citizen work scope");r.citizen.onlyAssigned=-1;
  r.citizen.expectedRevision=uint64_t(INT64_MAX)+1;check(r,"invalid citizen request");r.citizen.expectedRevision=INT64_MAX;
  r.citizen.name="x";check(r,"unexpected work detail name");r.citizen.name="";
  r.citizen.unitId=0;check(r,"unexpected new work detail identity");r.citizen.unitId=-1;
  r.citizen.expectedRevision=0;check(r,"citizen receipt required");r.citizen.expectedRevision=1;
  for(auto action:{wm::ManagementAction::WorkDetailCreate,wm::ManagementAction::WorkDetailDelete,wm::ManagementAction::WorkDetailEdit,wm::ManagementAction::CitizenWorkScope}) {
    auto search=r;search.action=action;
    if(action==wm::ManagementAction::WorkDetailDelete || action==wm::ManagementAction::WorkDetailEdit)search.citizen.detailIndex=0;
    if(action==wm::ManagementAction::WorkDetailEdit)search.citizen.edit=1;
    if(action==wm::ManagementAction::CitizenWorkScope){search.citizen.unitId=0;search.citizen.onlyAssigned=0;}
    check(search,"");search.citizen.cursor=1;check(search,"unexpected citizen search");search.citizen.cursor=0;
    search.citizen.query="x";check(search,"unexpected citizen search");search.citizen.query="";check(search,"");
    search.citizen.expectedRevision=0;check(search,"citizen receipt required");
  }
  for(auto action:{wm::ManagementAction::WorkDetailDelete,wm::ManagementAction::WorkDetailEdit}) {
    r.action=action;r.citizen.edit=action==wm::ManagementAction::WorkDetailEdit?1:0;
    check(r,"work detail index required");r.citizen.detailIndex=0;check(r,"");
    r.citizen.detailIndex=127;check(r,"");r.citizen.detailIndex=128;check(r,"invalid citizen request");
    r.citizen.detailIndex=-1;
  }
  r.citizen.detailIndex=0;r.citizen.edit=1;
  r.citizen.name=std::string(160,'x');check(r,"");r.citizen.name+='x';check(r,"work detail name too long");
  r.citizen.name="";check(r,"");r.citizen.edit=0;check(r,"invalid work detail edit");
  r.citizen.edit=4;check(r,"invalid work detail edit");r.citizen.edit=2;
  for(int i=0;i<94;++i)r.citizen.labors.push_back(i);
  check(r,"");
  r.citizen.labors.push_back(94);check(r,"too many work detail labors");
  for(auto values:{std::vector<int16_t>{-1},std::vector<int16_t>{94},std::vector<int16_t>{0,0}}) {
    r.citizen.labors=values;check(r,"invalid work detail labor");
  }
  r.citizen.labors={};check(r,"");r.citizen.edit=3;check(r,"");
  r.citizen.name="x";check(r,"unexpected work detail name");r.citizen.name="";
  r.citizen.labors={1};check(r,"unexpected work detail labors");r.citizen.labors={};
  r.action=wm::ManagementAction::CitizenWorkScope;r.citizen.edit=0;r.citizen.detailIndex=-1;
  check(r,"invalid citizen work scope");r.citizen.unitId=0;
  for(int value:{0,1}) {r.citizen.onlyAssigned=value;check(r,"");}
  for(int value:{-1,2}) {r.citizen.onlyAssigned=value;check(r,"invalid citizen work scope");}
  r={};r.action=wm::ManagementAction::WorkDetailList;check(r,"");r.citizen.cursor=1;
  check(r,"work detail list revision required");r.citizen.expectedListRevision=INT64_MAX;check(r,"");
  r.citizen.expectedListRevision=uint64_t(INT64_MAX)+1;check(r,"invalid work detail list revision");
  r.citizen.expectedListRevision=1;r.action=wm::ManagementAction::CitizenList;check(r,"unexpected work detail list revision");
}

TEST_CASE("citizen codec preserves every appended state field and defaults") {
  for(bool populated:{false,true}) {
    flatbuffers::FlatBufferBuilder b;
    auto skill=b.CreateString(populated?"Legendary Miner":"");
    auto error=b.CreateString(populated?"Row exceeds name cap":"");
    wire::TilePos origin(0,0,0);
    wire::CitizenInfoBuilder person(b);person.add_id(0);person.add_origin(&origin);
    if(populated) {
      person.add_revision(INT64_MAX);person.add_detail_member(1);person.add_detail_skill(1);
      person.add_detail_skill_rating(15);person.add_detail_skill_name(skill);person.add_portrait_state(3);person.add_row_error(error);
    }
    auto u=person.Finish();
    wire::WorkDetailInfoBuilder detail(b);detail.add_index(0);
    if(populated){detail.add_icon(18);detail.add_row_error(error);}
    auto d=detail.Finish();auto people=b.CreateVector(std::vector{u});auto details=b.CreateVector(std::vector{d});
    auto recalc=b.CreateString(populated?"Native recalculation failed; labors may be stale":"");
    wire::CitizenStateBuilder state(b);state.add_outcome_unknown(populated);state.add_citizens(people);state.add_details(details);
    if(populated){state.add_recalc_done(1);state.add_recalc_total(5000);state.add_recalc_error(recalc);state.add_detail_list_revision(INT64_MAX);}
    b.Finish(state.Finish());auto decoded=codec::decodeCitizen(flatbuffers::GetRoot<wire::CitizenState>(b.GetBufferPointer()));
    CHECK(decoded.outcomeUnknown==populated);
    REQUIRE(decoded.citizens.size()==1);REQUIRE(decoded.details.size()==1);
    const auto& row=decoded.citizens[0];CHECK(row.revision==(populated?INT64_MAX:0));
    CHECK(row.detailMember==(populated?1:-1));CHECK(row.detailSkill==(populated?1:-1));
    CHECK(row.detailSkillRating==(populated?15:-1));CHECK(row.detailSkillName==(populated?"Legendary Miner":""));
    CHECK(row.portraitState==(populated?3:0));CHECK(row.rowError==(populated?"Row exceeds name cap":""));
    CHECK(decoded.details[0].icon==(populated?18:-2));CHECK(decoded.details[0].rowError==row.rowError);
    CHECK(decoded.recalcDone==(populated?1:0));CHECK(decoded.recalcTotal==(populated?5000:0));
    CHECK(decoded.detailListRevision==(populated?INT64_MAX:0));CHECK(decoded.recalcError==(populated?"Native recalculation failed; labors may be stale":""));
  }
}

TEST_CASE("management encoding isolates domain payloads while preserving envelope identity") {
  wm::ManagementRequest request;
  request.area.id = 0;
  request.area.ownerId = -2;
  request.workOrder.id = 37;
  request.workOrder.expectedRevision = (uint64_t(1) << 54) + 1;
  request.workOrder.query = "steel";
  for (auto action : {wm::ManagementAction::Catalog, wm::ManagementAction::AreaInspect,
                      wm::ManagementAction::WorkOrderInspect}) {
    request.action = action;
    flatbuffers::FlatBufferBuilder builder;
    codec::encodeRequest(builder, request, 123, (uint64_t(1) << 55) + 7, 456);
    flatbuffers::Verifier verifier(builder.GetBufferPointer(), builder.GetSize());
    REQUIRE(verifier.VerifyBuffer<wire::ConstructionRequest>(nullptr));
    const auto* encoded =
        flatbuffers::GetRoot<wire::ConstructionRequest>(builder.GetBufferPointer());
    CHECK(encoded->client_id() == 123);
    CHECK(encoded->seq() == (uint64_t(1) << 55) + 7);
    CHECK(encoded->world_epoch() == 456);
    CHECK(bool(encoded->area()) == (action == wm::ManagementAction::AreaInspect));
    CHECK(bool(encoded->work_order()) == (action == wm::ManagementAction::WorkOrderInspect));
    CHECK_FALSE(encoded->production());
    CHECK_FALSE(encoded->citizen());
    if (encoded->area()) {
      CHECK(encoded->area()->id() == 0);
      CHECK(encoded->area()->owner_id() == -2);
      CHECK(encoded->area()->active() == -1);
    }
    if (encoded->work_order()) {
      CHECK(encoded->work_order()->expected_revision() == request.workOrder.expectedRevision);
      CHECK(encoded->work_order()->query()->str() == "steel");
      CHECK(encoded->work_order()->remaining() == -1);
    }
  }
}

TEST_CASE("management domain decoding owns nested data independently of the wire buffer") {
  flatbuffers::FlatBufferBuilder builder;
  auto fact = wire::CreateCreatureFact(builder, builder.CreateString("age"),
                                       builder.CreateString("Twenty years"), 20, true);
  auto record = wire::CreateCreatureRecord(builder, 17, -1, builder.CreateString("Identity"),
                                           builder.CreateVector(std::vector{fact}));
  auto section = wire::CreateCreatureSection(builder, wire::CreatureSectionKind::Identity, true,
                                             false, {}, builder.CreateVector(std::vector{record}));
  const auto sections = builder.CreateVector(std::vector{section});
  const auto name = builder.CreateString("Cerol");
  const std::string nativeDescription(2048,'x');
  auto healthPage=wire::CreateCreatureHealthPage(builder,wire::CreatureHealthPageKind::Description,
      builder.CreateVector(std::vector{builder.CreateString(nativeDescription)}));
  auto healthPages=builder.CreateVector(std::vector{healthPage});
  auto skill=wire::CreateCreatureSkillRow(builder,12,-1,0,5,-4,builder.CreateString("Native skill"),builder.CreateString(""),109);
  auto knowledge=wire::CreateCreatureSkillRow(builder,-1,8,0x80000000u,0,0,builder.CreateString("Native topic"),builder.CreateString("Native category"));
  auto skillsPages=builder.CreateVector(std::vector{
      wire::CreateCreatureSkillsPage(builder,wire::CreatureSkillsPageKind::Labor,builder.CreateVector(std::vector{skill})),
      wire::CreateCreatureSkillsPage(builder,wire::CreatureSkillsPageKind::Knowledge,builder.CreateVector(std::vector{knowledge}))});
  wire::CreatureStateBuilder creature(builder);
  creature.add_unit_id(42);
  creature.add_name(name);
  creature.add_sections(sections);
  creature.add_health_pages(healthPages);
  creature.add_skills_pages(skillsPages);
  builder.Finish(creature.Finish());
  auto decoded =
      codec::decodeCreature(flatbuffers::GetRoot<wire::CreatureState>(builder.GetBufferPointer()));
  // The collector reuses this storage as soon as decode returns.
  std::fill_n(builder.GetBufferPointer(), builder.GetSize(), uint8_t(0));
  CHECK(decoded.unitId == 42);
  CHECK(decoded.name == "Cerol");
  CHECK(decoded.species.empty());
  REQUIRE(decoded.skillsPages.size()==2);
  CHECK(decoded.skillsPages[0].kind==wm::CreatureSkillsPageKind::Labor);
  REQUIRE(decoded.skillsPages[0].rows.size()==1);
  CHECK(decoded.skillsPages[0].rows[0].rustValue==-4);
  CHECK(decoded.skillsPages[0].rows[0].captionColor==109);
  CHECK(decoded.skillsPages[1].rows[0].captionColor==-1);
  CHECK(decoded.skillsPages[0].rows[0].caption=="Native skill");
  REQUIRE(decoded.skillsPages[1].rows.size()==1);
  CHECK(decoded.skillsPages[1].rows[0].knowledgeBits==0x80000000u);
  CHECK(decoded.skillsPages[1].rows[0].subtitle=="Native category");
  REQUIRE(decoded.healthPages.size()==1);
  CHECK(decoded.healthPages[0].kind==wm::CreatureHealthPageKind::Description);
  REQUIRE(decoded.healthPages[0].rows.size()==1);
  CHECK(decoded.healthPages[0].rows[0]==nativeDescription);
  REQUIRE(decoded.sections.size() == 1);
  REQUIRE(decoded.sections[0].records.size() == 1);
  const auto& row = decoded.sections[0].records[0];
  CHECK(row.relatedId == -1);
  REQUIRE(row.facts.size() == 1);
  CHECK(row.facts[0].text == "Twenty years");
  CHECK(row.facts[0].hasNumber);
  CHECK(row.facts[0].number == 20);
  decoded = codec::decodeCreature(nullptr);
  CHECK(decoded.unitId == -1);
  CHECK(decoded.sections.empty());
}

namespace {
namespace mm = df3d::mirror;
struct EncodedRequest {
  flatbuffers::FlatBufferBuilder b;
  bool invalid(const wm::ManagementRequest& r) {
    b.Clear();
    codec::encodeRequest(b, r, 1, 1, 7);
    return mm::validateConstructionRequest(*get()).has_value();
  }
  const mm::ConstructionRequest* get() const {
    return flatbuffers::GetRoot<mm::ConstructionRequest>(b.GetBufferPointer());
  }
};
}
TEST_CASE("trade exchange wire guards native receipts and whole-good selections") {
  EncodedRequest encoded;
  wm::ManagementRequest r;r.action=wm::ManagementAction::TradeExchangeSelect;r.trade.depotId=17;r.trade.itemId=55;r.trade.side=1;r.trade.selected=1;
  CHECK(encoded.invalid(r));
  r.trade.receipt=123;REQUIRE_FALSE(encoded.invalid(r));auto* q=encoded.get();REQUIRE(q->trade());CHECK(q->trade()->receipt()==123);CHECK(q->trade()->item_id()==55);CHECK(q->trade()->side()==1);CHECK(q->trade()->selected()==1);
  r.action=wm::ManagementAction::TradeExchangeSubmit;CHECK(encoded.invalid(r));
  r.trade.itemId=-1;r.trade.selected=-1;REQUIRE_FALSE(encoded.invalid(r));q=encoded.get();CHECK(q->trade()->receipt()==123);
  r.action=wm::ManagementAction::TradeExchangeClose;r.trade.receipt=0;REQUIRE_FALSE(encoded.invalid(r));q=encoded.get();CHECK(q->trade()->receipt()==0);
}
TEST_CASE("Stocks requests keep membership receipts separate from trade") {
  EncodedRequest encoded;
  wm::ManagementRequest r; r.action=wm::ManagementAction::StocksList; r.stocks.category=39;
  CHECK(encoded.invalid(r));
  r.stocks.receipt=12; r.stocks.cursor=512; r.stocks.query="iron";
  REQUIRE_FALSE(encoded.invalid(r)); auto* q=encoded.get();
  REQUIRE(q->stocks()); CHECK(q->trade()==nullptr); CHECK(q->stocks()->receipt()==12);
  CHECK(q->stocks()->category()==39); CHECK(q->stocks()->cursor()==512); CHECK(q->stocks()->query()->str()=="iron");
  r.action=wm::ManagementAction::StocksInspect; CHECK(encoded.invalid(r));
  r.stocks.itemId=0; REQUIRE_FALSE(encoded.invalid(r)); CHECK(encoded.get()->stocks()->item_id()==0);
}
TEST_CASE("Appointments require role identity and consumed-context receipts") {
  EncodedRequest encoded;
  wm::ManagementRequest r;r.action=wm::ManagementAction::AppointmentsAssign;r.appointments.unitId=5173;
  CHECK(encoded.invalid(r));
  r.appointments.entityId=483;r.appointments.positionId=10;r.appointments.assignmentId=6;r.appointments.receipt=25;
  REQUIRE_FALSE(encoded.invalid(r)); auto* q=encoded.get(); REQUIRE(q->appointments()); CHECK(q->stocks()==nullptr);CHECK(q->appointments()->receipt()==25);CHECK(q->appointments()->unit_id()==5173);CHECK(q->appointments()->assignment_id()==6);
  r.appointments.unitId=-1; REQUIRE_FALSE(encoded.invalid(r));CHECK(encoded.get()->appointments()->unit_id()==-1);
}
TEST_CASE("Kitchen requests carry exact ingredient tuples and reject malformed edits") {
  EncodedRequest encoded;
  wm::ManagementRequest r;r.action=wm::ManagementAction::KitchenSetPermission;
  r.kitchen.itemType=1;r.kitchen.matType=419;r.kitchen.matIndex=20;r.kitchen.permission=2;r.kitchen.allowed=0;
  CHECK(encoded.invalid(r));r.kitchen.receipt=7;r.kitchen.query="berries";
  REQUIRE_FALSE(encoded.invalid(r));auto* q=encoded.get();REQUIRE(q->kitchen());CHECK(q->appointments()==nullptr);
  CHECK(q->kitchen()->item_type()==1);CHECK(q->kitchen()->item_subtype()==-1);CHECK(q->kitchen()->mat_type()==419);CHECK(q->kitchen()->mat_index()==20);CHECK(q->kitchen()->permission()==2);CHECK(q->kitchen()->allowed()==0);CHECK(q->kitchen()->receipt()==7);CHECK(q->kitchen()->query()->str()=="berries");
  for(auto flag:{0,3}){r.kitchen.permission=uint8_t(flag);CHECK(encoded.invalid(r));}
  r.kitchen.permission=1;r.kitchen.allowed=-1;CHECK(encoded.invalid(r));
  r.kitchen.allowed=1;r.kitchen.matIndex=-2;CHECK(encoded.invalid(r));
  r.kitchen.matIndex=20;r.action=wm::ManagementAction::KitchenList;CHECK(encoded.invalid(r));
  r.kitchen={};r.kitchen.receipt=7;r.kitchen.cursor=4097;CHECK(encoded.invalid(r));
  r.kitchen.cursor=0;r.kitchen.query=std::string(129,'x');CHECK(encoded.invalid(r));
}
TEST_CASE("selection transport request payloads preserve ownership") {
  EncodedRequest encoded;
  wm::ManagementRequest request;request.action=wm::ManagementAction::Selection;
  request.selection.x=88;request.selection.y=71;request.selection.z=143;
  REQUIRE_FALSE(encoded.invalid(request));
  const auto* command=encoded.get();REQUIRE(command->selection());
  CHECK(command->selection()->tile()->x()==88);CHECK(command->selection()->tile()->z()==143);
  CHECK(command->selection()->receipt()==0);
  request.selection.receipt=77;REQUIRE_FALSE(encoded.invalid(request));
  CHECK(encoded.get()->selection()->receipt()==77); // replacement click carries ownership
}
TEST_CASE("selection artwork separates reads from guarded mutations") {
  EncodedRequest encoded;wm::ManagementRequest r;r.action=wm::ManagementAction::SelectionArtRead;
  auto& q=r.selectionArt;q.receipt=91;
  REQUIRE_FALSE(encoded.invalid(r));REQUIRE(encoded.get()->selection_art());
  CHECK(encoded.get()->selection_art()->receipt()==91);
  q.receipt=0;CHECK(encoded.invalid(r));q.receipt=91;
  q.art.page=1;q.art.cursor=128;CHECK(encoded.invalid(r));
  q.art.expectedListRevision=42;q.expectedRevision=19;REQUIRE_FALSE(encoded.invalid(r));
  q.art.hovered=300;q.art.previewColumns=80;REQUIRE_FALSE(encoded.invalid(r));
  r.action=wm::ManagementAction::SelectionArtApply;CHECK(encoded.invalid(r));
  q.art.cursor=0;q.art.hovered=-1;q.art.previewColumns=0;q.art.subject=300;
  REQUIRE_FALSE(encoded.invalid(r));CHECK(encoded.get()->selection_art()->art()->subject()==300);
  q.expectedRevision=0;CHECK(encoded.invalid(r));q.expectedRevision=19;
  q.art.expectedListRevision=0;CHECK(encoded.invalid(r));
  q.art.page=0;q.art.subject=-1;REQUIRE_FALSE(encoded.invalid(r));
  q.art.query="unexpected";CHECK(encoded.invalid(r));q.art.query.clear();
  q.art.draft.emplace();CHECK(encoded.invalid(r));
  q.art.page=6;q.art.draft->columns=98;
  q.art.draft->action=wm::WorkOrderArtDraftAction::GenerateName;
  REQUIRE_FALSE(encoded.invalid(r));
  r.action=wm::ManagementAction::SelectionArtRead;CHECK(encoded.invalid(r));
  q.art.draft->action=wm::WorkOrderArtDraftAction::Inspect;REQUIRE_FALSE(encoded.invalid(r));
  q.expectedRevision=0;CHECK(encoded.invalid(r));q.expectedRevision=19;
  q.art.cursor=128;CHECK(encoded.invalid(r));q.art.expectedListRevision=42;
  REQUIRE_FALSE(encoded.invalid(r));
}
TEST_CASE("selection artwork replies preserve receipts and reject malformed pages") {
  for(int fault=0;fault<6;++fault) {
    flatbuffers::FlatBufferBuilder b;
    const auto row=wire::CreateWorkOrderArtRow(b,320,b.CreateString("Site"));
    const auto rows=b.CreateVector(std::vector<flatbuffers::Offset<wire::WorkOrderArtRow>>{row});
    const auto art=wire::CreateWorkOrderArtState(b,2,b.CreateString("Image information for engraving"),rows,fault==2?0:92,1);
    const auto result=wire::CreateSelectionArtState(b,fault==1?0:91,INT64_C(9007199254740993),fault==3?0:art,fault==4);
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(fault==5?wire::ManagementAction::SelectionArtApply:wire::ManagementAction::SelectionArtRead);
    state.add_status(wire::ManagementStatus::Ok);state.add_selection_art(result);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(fault!=0));
    if(!fault){const auto decoded=codec::decodeState(value);REQUIRE(decoded.selectionArt);CHECK(decoded.selectionArt->receipt==91);
      CHECK(decoded.selectionArt->revision==UINT64_C(9007199254740993));REQUIRE(decoded.selectionArt->art);CHECK(decoded.selectionArt->art->rows[0].id==320);}
  }
}

TEST_CASE("empty work-order traits do not turn moves or details into another edit") {
  EncodedRequest encoded;
  wm::ManagementRequest r;r.action=wm::ManagementAction::WorkOrderUpdate;
  auto& w=r.workOrder;w.id=0;w.expectedRevision=1;w.move=1;
  w.expectedNeighbor=1;w.expectedListRevision=1;w.traits.emplace();
  REQUIRE_FALSE(encoded.invalid(r));CHECK(encoded.get()->work_order()->traits()==nullptr);
  w.traits->push_back("f1:0");CHECK(encoded.invalid(r));
  w.traits->clear();w.move=0;w.expectedNeighbor=-1;w.expectedListRevision=0;
  w.inputIndex=0;w.matType=0;w.matIndex=0;
  REQUIRE_FALSE(encoded.invalid(r));CHECK(encoded.get()->work_order()->traits()==nullptr);
  w.traits->push_back("f1:0");CHECK(encoded.invalid(r));
  // Condition edits retain an explicit empty replacement, distinct from absence.
  w={};w.id=0;w.expectedRevision=1;w.compare=0;w.threshold=0;w.traits.emplace();
  r.action=wm::ManagementAction::WorkOrderCondition;
  REQUIRE_FALSE(encoded.invalid(r));REQUIRE(encoded.get()->work_order()->traits());
  CHECK(encoded.get()->work_order()->traits()->size()==0);
  w={};r.action=wm::ManagementAction::WorkOrderCatalog;
  w.query=std::string(64,'q');REQUIRE_FALSE(encoded.invalid(r));
  w.query.push_back('q');CHECK(encoded.invalid(r));
}

TEST_CASE("maximal producer order page fits the management channel") {
  flatbuffers::FlatBufferBuilder b;
  std::vector<flatbuffers::Offset<mm::WorkOrderInfo>> orders;
  for(int id=0;id<16;++id) {
    std::vector<flatbuffers::Offset<mm::WorkOrderCondition>> conditions;
    std::vector<flatbuffers::Offset<mm::WorkOrderInput>> inputs;
    for(int index=0;index<8;++index) {
      std::vector<std::string> traits;
      for(int t=0;t<16;++t)traits.push_back("rc:"+std::string(59,'x')+char('a'+t)+char('a'+index));
      conditions.push_back(mm::CreateWorkOrderCondition(b,0,index,b.CreateString(std::string(256,'c')),
        true,0,1,-1,-1,-1,false,-1,-1,-1,b.CreateVectorOfStrings(traits),1,true,-1));
      // The producer currently emits empty input descriptions.
      inputs.push_back(mm::CreateWorkOrderInput(b,index,b.CreateString(""),-1,-1,true));
    }
    std::vector<int32_t> jobs;for(int j=0;j<128;++j)jobs.push_back(id*128+j);
    auto name=b.CreateString(std::string(512,'n')),reason=b.CreateString(std::string(1024,'r'));
    auto cs=b.CreateVector(conditions);auto ins=b.CreateVector(inputs);auto js=b.CreateVector(jobs);
    mm::WorkOrderInfoBuilder o(b);o.add_id(id);o.add_revision(1);o.add_name(name);o.add_reason(reason);
    o.add_total(10);o.add_remaining(10);o.add_conditions(cs);o.add_inputs(ins);o.add_generated_jobs(js);
    orders.push_back(o.Finish());
  }
  auto os=b.CreateVector(orders);
  mm::WorkOrderStateBuilder w(b);w.add_orders(os);w.add_list_revision(INT64_MAX);auto ws=w.Finish();
  auto citizen=mm::CreateCitizenState(b,
    b.CreateVector(std::vector<flatbuffers::Offset<mm::CitizenInfo>>{}),
    b.CreateVector(std::vector<flatbuffers::Offset<mm::WorkDetailInfo>>{}));
  mm::ManagementStateBuilder s(b);s.add_schema_version(mm::kManagementVersion);s.add_revision(1);
  s.add_action(mm::ManagementAction::WorkOrderList);s.add_status(mm::ManagementStatus::Ok);s.add_work_order(ws);s.add_citizen(citizen);
  b.Finish(s.Finish());
  CHECK(b.GetSize()<mm::kManagementCapacity);
  CHECK_FALSE(mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer())).has_value());
}

TEST_CASE("non-citizen replies reject populated citizen tables") {
  for(bool detail : {false,true}) {
    flatbuffers::FlatBufferBuilder b;
    std::vector<flatbuffers::Offset<mm::CitizenInfo>> people;
    std::vector<flatbuffers::Offset<mm::WorkDetailInfo>> details;
    if(detail) details.push_back(mm::CreateWorkDetailInfo(b));
    else people.push_back(mm::CreateCitizenInfo(b));
    auto citizens=mm::CreateCitizenState(b,b.CreateVector(people),b.CreateVector(details));
    mm::ManagementStateBuilder state(b);state.add_revision(1);
    state.add_action(mm::ManagementAction::WorkOrderList);state.add_citizen(citizens);
    b.Finish(state.Finish());
    auto error=mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer()));
    REQUIRE(error);CHECK(*error=="unexpected citizen state");
  }
}

TEST_CASE("work-order request fields and exclusive intents survive encoding") {
  EncodedRequest encoded;
  wm::ManagementRequest r;r.action=wm::ManagementAction::WorkOrderCondition;
  auto& w=r.workOrder;w.id=0;w.expectedRevision=1;w.compare=0;w.threshold=0;
  w.itemSubtype=2;w.matType=419;w.matIndex=7;w.traits=std::vector<std::string>{"f1:0","rc:X"};
  REQUIRE_FALSE(encoded.invalid(r));auto* q=encoded.get()->work_order();
  CHECK(q->item_subtype()==2);CHECK(q->mat_type()==419);CHECK(q->mat_index()==7);
  REQUIRE(q->traits());CHECK(q->traits()->Get(1)->str()=="rc:X");
  w.traits=std::vector<std::string>(256,std::string(64,'t'));CHECK_FALSE(encoded.invalid(r));
  w.traits->push_back("x");CHECK(encoded.invalid(r));w.traits->pop_back();
  w.traits->front().push_back('x');CHECK(encoded.invalid(r));
  w={};r.action=wm::ManagementAction::WorkOrderCatalog;
  w.groupType=0;w.groupSubtype=2;w.groupCustom=3;w.expectedListRevision=INT64_MAX;
  REQUIRE_FALSE(encoded.invalid(r));q=encoded.get()->work_order();
  CHECK(q->group_type()==0);CHECK(q->group_subtype()==2);CHECK(q->group_custom()==3);
  CHECK(q->expected_list_revision()==INT64_MAX);
  w={};r.action=wm::ManagementAction::WorkOrderUpdate;w.id=0;w.expectedRevision=1;
  w.move=1;w.expectedNeighbor=2;w.expectedListRevision=INT64_MAX;
  REQUIRE_FALSE(encoded.invalid(r));q=encoded.get()->work_order();
  CHECK(q->move()==1);CHECK(q->expected_neighbor()==2);CHECK(q->expected_list_revision()==INT64_MAX);
  w.move=-1;CHECK_FALSE(encoded.invalid(r));w.move=2;CHECK(encoded.invalid(r));
  w.move=-2;CHECK(encoded.invalid(r));w.move=1;
  const auto move=r;
  for(int missing=0;missing<5;++missing) {
    r=move;
    if(missing==0)r.action=wm::ManagementAction::WorkOrderDelete;
    if(missing==1)w.id=-1;
    if(missing==2)w.expectedRevision=0;
    if(missing==3)w.expectedNeighbor=-1;
    if(missing==4)w.expectedListRevision=0;
    CHECK(encoded.invalid(r));
  }
  r=move;w.move=0;w.expectedNeighbor=-1;w.expectedListRevision=0;
  w.inputIndex=0;w.matType=0;w.matIndex=0;w.encrustFlags=1092;
  REQUIRE_FALSE(encoded.invalid(r));q=encoded.get()->work_order();
  CHECK(q->input_index()==0);CHECK(q->mat_type()==0);CHECK(q->mat_index()==0);CHECK(q->encrust_flags()==1092);
  const auto input=r;
  for(int missing=0;missing<7;++missing) {
    r=input;
    if(missing==0)r.action=wm::ManagementAction::WorkOrderDelete;
    if(missing==1)w.id=-1;
    if(missing==2)w.expectedRevision=0;
    if(missing==3)w.expectedNeighbor=0;
    if(missing==4)w.expectedListRevision=1;
    if(missing==5)w.move=1;
    if(missing==6){w.matType=-1;w.matIndex=-1;w.encrustFlags=-1;}
    CHECK(encoded.invalid(r));
  }
  // New scalar identities retain -1 and zero, and refuse values below -1.
  for(int field=0;field<9;++field) for(int value:{-1,0,-2}) {
    r={};r.action=wm::ManagementAction::WorkOrderCatalog;
    switch(field) {
      case 0:w.expectedNeighbor=value;break;case 1:w.itemSubtype=value;break;
      case 2:w.matType=value;break;case 3:w.matIndex=value;break;
      case 4:w.groupType=value;break;case 5:w.groupSubtype=value;break;
      case 6:w.groupCustom=value;break;case 7:w.encrustFlags=value;break;
      case 8:w.inputIndex=value;if(value==0)r=input;break;
    }
    CHECK(encoded.invalid(r)==(value==-2));
  }
  r=move;w.expectedListRevision=-1;CHECK(encoded.invalid(r));
  // Every unrelated field must leave its default only in a separate intent.
  for(const auto& base:{move,input}) for(int field=0;field<25;++field) {
    r=base;
    switch(field) {
      case 0:w.remaining=0;break;case 1:w.frequency=0;break;
      case 2:w.workshopId=-1;break;case 3:w.maxWorkshops=0;break;
      case 4:w.recipe="x";break;case 5:w.query="x";break;case 6:w.cursor=1;break;
      case 7:w.conditionKind=1;break;case 8:w.conditionIndex=0;break;
      case 9:w.removeCondition=true;break;case 10:w.compare=0;break;
      case 11:w.threshold=0;break;case 12:w.itemType=0;break;
      case 13:w.targetOrder=1;break;case 14:w.dependency=0;break;
      case 15:w.candidateKind=1;break;case 16:w.itemSubtype=0;break;
      case 17:w.traits=std::vector<std::string>{"f1:0"};break;
      case 18:w.groupType=0;break;case 19:w.groupSubtype=0;break;case 20:w.groupCustom=0;break;
      case 21:if(base.workOrder.move)w.inputIndex=0;else w.inputIndex=-1;break;
      case 22:if(base.workOrder.move)w.matType=0;else w.move=1;break;
      case 23:if(base.workOrder.move)w.matIndex=0;else w.expectedNeighbor=0;break;
      case 24:if(base.workOrder.move)w.encrustFlags=0;else w.expectedListRevision=1;break;
    }
    CAPTURE(field);CHECK(encoded.invalid(r));
  }
}

TEST_CASE("work-order response fields decode with owned strings and absent defaults") {
  for(bool present:{false,true}) {
    flatbuffers::FlatBufferBuilder b;
    auto ts=b.CreateVectorOfStrings(std::vector<std::string>{"f5:31","rp:X"});
    mm::WorkOrderConditionBuilder c(b);
    if(present){c.add_item_subtype(3);c.add_mat_type(419);c.add_mat_index(7);c.add_traits(ts);
      c.add_satisfaction(2);c.add_estimated(true);c.add_estimate_count(42);}
    auto cs=b.CreateVector(std::vector{c.Finish()});
    auto in=mm::CreateWorkOrderInput(b,2,b.CreateString("input"),0,5,true);
    auto ins=b.CreateVector(std::vector{in});
    mm::WorkOrderInfoBuilder o(b);o.add_id(0);o.add_revision(1);o.add_conditions(cs);
    if(present){o.add_position(12);o.add_detail_kind(6);o.add_size_raw(17);o.add_encrust_flags(1092);
      o.add_mat_type(19);o.add_mat_index(8);o.add_material_category(4096);o.add_inputs(ins);}
    auto os=b.CreateVector(std::vector{o.Finish()});
    auto mat=mm::CreateWorkOrderMaterial(b,0,4,b.CreateString("material"));
    auto mats=b.CreateVector(std::vector{mat});
    auto trait=mm::CreateWorkOrderTrait(b,b.CreateString("rc:X"),b.CreateString("trait"));
    auto traits=b.CreateVector(std::vector{trait});
    auto type=mm::CreateWorkOrderItemType(b,3,2,b.CreateString("type"));
    auto types=b.CreateVector(std::vector{type});
    auto group=mm::CreateWorkOrderGroup(b,0,2,7,b.CreateString("group"),9);
    auto groups=b.CreateVector(std::vector{group});
    auto task=mm::CreateWorkOrderTask(b,b.CreateString("key"),b.CreateString("task"),11,b.CreateString("reaction"),3,2,419,7);
    auto tasks=b.CreateVector(std::vector{task});
    mm::WorkOrderStateBuilder state(b);state.add_orders(os);
    if(present){state.add_materials(mats);state.add_traits(traits);state.add_types(types);state.add_groups(groups);state.add_tasks(tasks);
      state.add_total(128);state.add_list_revision(INT64_MAX);state.add_build_phase(3);state.add_build_done(17);state.add_build_total(128);}
    b.Finish(state.Finish());auto decoded=codec::decodeWorkOrder(flatbuffers::GetRoot<mm::WorkOrderState>(b.GetBufferPointer()));
    std::fill_n(b.GetBufferPointer(),b.GetSize(),uint8_t(0));
    REQUIRE(decoded.orders.size()==1);const auto& order=decoded.orders[0];REQUIRE(order.conditions.size()==1);const auto& cond=order.conditions[0];
    CHECK(order.position==(present?12:-1));CHECK(order.detailKind==(present?6:0));CHECK(order.sizeRaw==(present?17:-1));
    CHECK(order.encrustFlags==(present?1092:0));CHECK(order.matType==(present?19:-1));CHECK(order.matIndex==(present?8:-1));CHECK(order.materialCategory==(present?4096:0));
    CHECK(cond.itemSubtype==(present?3:-1));CHECK(cond.matType==(present?419:-1));CHECK(cond.matIndex==(present?7:-1));
    CHECK(cond.satisfaction==(present?2:0));CHECK(cond.estimated==present);CHECK(cond.estimateCount==(present?42:-1));
    CHECK(decoded.total==(present?128:0));CHECK(decoded.listRevision==(present?INT64_MAX:0));
    CHECK(decoded.buildPhase==(present?3:0));CHECK(decoded.buildDone==(present?17:0));CHECK(decoded.buildTotal==(present?128:0));
    if(present) {
      CHECK(cond.traits==std::vector<std::string>{"f5:31","rp:X"});
      REQUIRE(order.inputs.size()==1);const auto& i=order.inputs[0];CHECK(i.index==2);CHECK(i.description=="input");CHECK(i.matType==0);CHECK(i.matIndex==5);CHECK(i.editable);
      REQUIRE(decoded.materials.size()==1);CHECK(decoded.materials[0].matType==0);CHECK(decoded.materials[0].matIndex==4);CHECK(decoded.materials[0].name=="material");
      REQUIRE(decoded.traits.size()==1);CHECK(decoded.traits[0].key=="rc:X");CHECK(decoded.traits[0].name=="trait");
      REQUIRE(decoded.types.size()==1);CHECK(decoded.types[0].itemType==3);CHECK(decoded.types[0].itemSubtype==2);CHECK(decoded.types[0].name=="type");
      REQUIRE(decoded.groups.size()==1);const auto& g=decoded.groups[0];CHECK(g.type==0);CHECK(g.subtype==2);CHECK(g.custom==7);CHECK(g.name=="group");CHECK(g.count==9);
      REQUIRE(decoded.tasks.size()==1);const auto& t=decoded.tasks[0];CHECK(t.key=="key");CHECK(t.name=="task");CHECK(t.jobType==11);CHECK(t.reaction=="reaction");CHECK(t.itemType==3);CHECK(t.itemSubtype==2);CHECK(t.matType==419);CHECK(t.matIndex==7);
    } else {
      CHECK(cond.traits.empty());CHECK(order.inputs.empty());CHECK(decoded.materials.empty());CHECK(decoded.traits.empty());CHECK(decoded.types.empty());CHECK(decoded.groups.empty());CHECK(decoded.tasks.empty());
    }
  }
}

namespace {
// One boundary changes per case; the valid baseline saturates every page cap.
struct WorkOrderPageBounds {
  int orders=16,conditions=128,traits=2048,jobs=2048,rows=128,keyBytes=64,nameBytes=128;
  int detailKind=6,satisfaction=2,phase=3,done=128,total=128;
  uint64_t revision=INT64_MAX;
  int list=-1; // -1: all catalogs; otherwise select one catalog for its boundary.
};
void workOrderPage(flatbuffers::FlatBufferBuilder& b,const WorkOrderPageBounds& n) {
  std::vector<flatbuffers::Offset<mm::WorkOrderInfo>> orders;
  for(int id=0;id<n.orders;++id) {
    std::vector<flatbuffers::Offset<mm::WorkOrderCondition>> conditions;
    const int count=n.conditions/n.orders+(id<n.conditions%n.orders);
    for(int index=0;index<count;++index) {
      const int ordinal=id*(n.conditions/n.orders)+std::min(id,n.conditions%n.orders)+index;
      const int traitCount=n.traits/n.conditions+(ordinal<n.traits%n.conditions);
      auto traits=b.CreateVectorOfStrings(std::vector<std::string>(traitCount,std::string(n.keyBytes,'t')));
      mm::WorkOrderConditionBuilder c(b);c.add_index(index);c.add_traits(traits);c.add_satisfaction(n.satisfaction);
      conditions.push_back(c.Finish());
    }
    std::vector<int32_t> jobs;
    for(int j=0;j<n.jobs/n.orders+(id<n.jobs%n.orders);++j)jobs.push_back(id*1024+j);
    auto cs=b.CreateVector(conditions);auto js=b.CreateVector(jobs);
    mm::WorkOrderInfoBuilder o(b);o.add_id(id);o.add_revision(1);o.add_detail_kind(n.detailKind);o.add_conditions(cs);o.add_generated_jobs(js);
    orders.push_back(o.Finish());
  }
  std::vector<flatbuffers::Offset<mm::WorkOrderMaterial>> mats;
  std::vector<flatbuffers::Offset<mm::WorkOrderTrait>> traits;
  std::vector<flatbuffers::Offset<mm::WorkOrderItemType>> types;
  std::vector<flatbuffers::Offset<mm::WorkOrderGroup>> groups;
  std::vector<flatbuffers::Offset<mm::WorkOrderTask>> tasks;
  for(int i=0;i<n.rows;++i) {
    if(n.list<0 || n.list==0)mats.push_back(mm::CreateWorkOrderMaterial(b,0,i,b.CreateString(std::string(n.nameBytes,'m'))));
    if(n.list<0 || n.list==1)traits.push_back(mm::CreateWorkOrderTrait(b,b.CreateString(std::string(n.keyBytes,'t')),b.CreateString(std::string(n.nameBytes,'t'))));
    if(n.list<0 || n.list==2)types.push_back(mm::CreateWorkOrderItemType(b,0,i,b.CreateString(std::string(n.nameBytes,'y'))));
    if(n.list<0 || n.list==3)groups.push_back(mm::CreateWorkOrderGroup(b,0,0,i,b.CreateString(std::string(n.nameBytes,'g')),1));
    if(n.list<0 || n.list==4)tasks.push_back(mm::CreateWorkOrderTask(b,b.CreateString(std::string(n.keyBytes,'k')),b.CreateString(std::string(n.nameBytes,'n')),0,b.CreateString(std::string(64,'r')),0,0,0,i));
  }
  auto os=b.CreateVector(orders);auto ms=b.CreateVector(mats);auto ts=b.CreateVector(traits);auto ys=b.CreateVector(types);auto gs=b.CreateVector(groups);auto ks=b.CreateVector(tasks);
  mm::WorkOrderStateBuilder w(b);w.add_orders(os);w.add_materials(ms);w.add_traits(ts);w.add_types(ys);w.add_groups(gs);w.add_tasks(ks);
  w.add_list_revision(n.revision);w.add_build_phase(n.phase);w.add_build_done(n.done);w.add_build_total(n.total);auto ws=w.Finish();
  mm::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(mm::ManagementAction::WorkOrderList);state.add_status(mm::ManagementStatus::Ok);state.add_work_order(ws);b.Finish(state.Finish());
}
}
TEST_CASE("maximal management page and individual state validator boundaries") {
  auto valid=[](const WorkOrderPageBounds& n) {
    flatbuffers::FlatBufferBuilder b;workOrderPage(b,n);
    flatbuffers::Verifier v(b.GetBufferPointer(),b.GetSize());REQUIRE(v.VerifyBuffer<mm::ManagementState>(nullptr));
    CHECK(b.GetSize()<mm::kManagementCapacity);
    return !mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer())).has_value();
  };
  CHECK(valid({}));
  for(int boundary=0;boundary<10;++boundary) {
    WorkOrderPageBounds n;CAPTURE(boundary);
    switch(boundary) {
      case 0:n.orders=17;break;case 1:n.conditions=129;break;case 2:n.traits=2049;break;
      case 3:n.jobs=2049;break;case 4:n.detailKind=7;break;case 5:n.satisfaction=3;break;
      case 6:n.phase=4;break;case 7:n.done=129;break;case 8:n.revision=uint64_t(INT64_MAX)+1;break;
      case 9:n.keyBytes=65;n.rows=0;break;
    }
    CHECK_FALSE(valid(n));
  }
  for(int list=0;list<5;++list) {
    WorkOrderPageBounds n;n.list=list;CHECK(valid(n));n.rows=129;CHECK_FALSE(valid(n));
    n.rows=128;n.nameBytes=129;CHECK_FALSE(valid(n));
    if(list==1 || list==4){n.nameBytes=128;n.traits=0;n.keyBytes=65;CHECK_FALSE(valid(n));}
  }
}

TEST_CASE("work-order default catalog identities and per-condition trait boundaries") {
  for(int size:{256,257}) {
    flatbuffers::FlatBufferBuilder b;
    auto ts=b.CreateVectorOfStrings(std::vector<std::string>(size,"f1:0"));
    mm::WorkOrderConditionBuilder c(b);c.add_traits(ts);auto cs=b.CreateVector(std::vector{c.Finish()});
    mm::WorkOrderInfoBuilder o(b);o.add_revision(1);o.add_conditions(cs);auto os=b.CreateVector(std::vector{o.Finish()});
    auto mat=mm::CreateWorkOrderMaterial(b);auto mats=b.CreateVector(std::vector{mat});
    auto type=mm::CreateWorkOrderItemType(b);auto types=b.CreateVector(std::vector{type});
    auto group=mm::CreateWorkOrderGroup(b);auto groups=b.CreateVector(std::vector{group});
    auto task=mm::CreateWorkOrderTask(b);auto tasks=b.CreateVector(std::vector{task});
    mm::WorkOrderStateBuilder w(b);w.add_orders(os);w.add_materials(mats);w.add_types(types);w.add_groups(groups);w.add_tasks(tasks);auto ws=w.Finish();
    mm::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(mm::ManagementAction::WorkOrderList);state.add_status(mm::ManagementStatus::Ok);state.add_work_order(ws);b.Finish(state.Finish());
    const auto* wire=flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer());
    CHECK(mm::validateManagementState(*wire).has_value()==(size==257));
    const auto decoded=codec::decodeWorkOrder(wire->work_order());
    CHECK(decoded.materials[0].matType==-1);CHECK(decoded.materials[0].matIndex==-1);
    CHECK(decoded.types[0].itemType==-1);CHECK(decoded.types[0].itemSubtype==-1);
    CHECK(decoded.groups[0].type==-1);CHECK(decoded.groups[0].subtype==-1);CHECK(decoded.groups[0].custom==-1);CHECK(decoded.groups[0].count==0);
    const auto& t=decoded.tasks[0];CHECK(t.jobType==-1);CHECK(t.itemType==-1);CHECK(t.itemSubtype==-1);CHECK(t.matType==-1);CHECK(t.matIndex==-1);
  }
}

TEST_CASE("native work-order state remains optional and rejects unknown observations") {
  for(int mode=0;mode<3;++mode) {
    flatbuffers::FlatBufferBuilder b;
    flatbuffers::Offset<mm::WorkOrderNativeState> native;
    if(mode)native=mm::CreateWorkOrderNativeState(b,mode==1?mm::WorkOrderPhase::Ready:mm::WorkOrderPhase::Unknown,true,true);
    mm::WorkOrderInfoBuilder row(b);row.add_revision(1);row.add_native_state(native);
    const auto rows=b.CreateVector(std::vector{row.Finish()});
    mm::WorkOrderStateBuilder work(b);work.add_orders(rows);const auto orders=work.Finish();
    mm::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(mm::ManagementAction::WorkOrderList);
    state.add_status(mm::ManagementStatus::Ok);state.add_work_order(orders);b.Finish(state.Finish());
    const auto* wire=flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer());
    CHECK(mm::validateManagementState(*wire).has_value()==(mode==2));
    const auto decoded=codec::decodeWorkOrder(wire->work_order());
    REQUIRE(decoded.orders.size()==1);
    CHECK(decoded.orders[0].nativeState.has_value()==(mode!=0));
    if(mode==1) {
      CHECK(decoded.orders[0].nativeState->phase==wm::WorkOrderPhase::Ready);
      CHECK(decoded.orders[0].nativeState->validationRequired);
      CHECK(decoded.orders[0].nativeState->detailsAvailable);
    }
  }
}

TEST_CASE("native condition suggestions preserve absence and captions") {
  for(int mode=0;mode<4;++mode) {
    flatbuffers::FlatBufferBuilder b;
    flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<mm::WorkOrderCondition>>> suggestions;
    if(mode) {
      const auto caption=mode==3?flatbuffers::Offset<flatbuffers::String>{}:b.CreateString("native item caption");
      mm::WorkOrderConditionBuilder condition(b);condition.add_compare(2);condition.add_threshold(10);condition.add_item_caption(caption);
      const auto value=condition.Finish();
      suggestions=b.CreateVector(mode==1?std::vector<flatbuffers::Offset<mm::WorkOrderCondition>>{}:std::vector{value});
    }
    mm::WorkOrderInfoBuilder row(b);row.add_revision(1);row.add_suggested_conditions(suggestions);
    const auto rows=b.CreateVector(std::vector{row.Finish()});
    mm::WorkOrderStateBuilder work(b);work.add_orders(rows);const auto orders=work.Finish();
    mm::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(mm::ManagementAction::WorkOrderInspect);
    state.add_status(mm::ManagementStatus::Ok);state.add_work_order(orders);b.Finish(state.Finish());
    const auto* wire=flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer());
    CHECK(mm::validateManagementState(*wire).has_value()==(mode==3));
    const auto decoded=codec::decodeWorkOrder(wire->work_order());
    REQUIRE(decoded.orders.size()==1);
    CHECK(decoded.orders[0].suggestedConditions.has_value()==(mode!=0));
    if(mode==1)CHECK(decoded.orders[0].suggestedConditions->empty());
    if(mode==2) {
      REQUIRE(decoded.orders[0].suggestedConditions->size()==1);
      CHECK(decoded.orders[0].suggestedConditions->front().itemCaption=="native item caption");
      CHECK(decoded.orders[0].suggestedConditions->front().threshold==10);
    }
  }
}

TEST_CASE("exact construction item identities survive encoding without aggregate fallback") {
  wm::ManagementRequest r;r.action=wm::ManagementAction::Place;r.definition="Chair";
  r.selections={{0,0,-1,0,1,2,42}};
  auto validate=[&]() {
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* q=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    const auto* ids=q->selections()->Get(0)->item_ids();
    CHECK(bool(ids)==r.selections[0].itemIds.has_value());
    if(ids) { CHECK(ids->size()==r.selections[0].itemIds->size());
      for(size_t i=0;i<ids->size();++i)CHECK(ids->Get(i)==(*r.selections[0].itemIds)[i]); }
    return wire::validateConstructionRequest(*q);
  };
  CHECK_FALSE(validate()); // Aggregate absence is preserved.
  r.selections[0].itemIds=std::vector<int32_t>{3225,3226};CHECK_FALSE(validate());
  r.selections[0].itemIds=std::vector<int32_t>{3226,3225};CHECK_FALSE(validate()); // User order preserved.
  r.selections[0].itemIds=std::vector<int32_t>{};CHECK(validate());
  r.selections[0].itemIds=std::vector<int32_t>{3225};CHECK(validate());
  r.selections[0].count=1;CHECK_FALSE(validate());
  for(int64_t rev:{int64_t(-1),int64_t(0)}){r.selections[0].expectedListRevision=rev;CHECK(validate());}
  r.selections[0].expectedListRevision=42;
  r.selections[0].itemIds=std::vector<int32_t>{-1};CHECK(validate());
  r.selections[0].count=2;r.selections[0].itemIds=std::vector<int32_t>{3225,3225};CHECK(validate());
  r.selections[0].count=1;r.selections[0].itemIds=std::vector<int32_t>{3225};
  r.selections.push_back({1,0,-1,0,1,1,42,std::vector<int32_t>{3225}});CHECK(validate());
  r.selections.back().itemIds=std::vector<int32_t>{3226};CHECK_FALSE(validate());
  r.selections.resize(1);r.selections[0].count=16384;r.selections[0].itemIds->resize(16384);
  for(int i=0;i<16384;++i)(*r.selections[0].itemIds)[i]=i;
  CHECK_FALSE(validate());
  r.selections[0].itemIds->push_back(16384);++r.selections[0].count;CHECK(validate());
}

TEST_CASE("construction selection revisions are optional signed int64 values per entry") {
  wm::ManagementRequest request;
  request.action=wm::ManagementAction::Place;request.definition="Chair";
  request.selections={{0,-1,-1,-1,-1,1},{1,-1,-1,-1,-1,1,42}};
  for (int64_t revision : {int64_t(-2),int64_t(-1),int64_t(0),int64_t(1),int64_t(INT64_MAX)}) {
    request.selections[0].expectedListRevision=revision;
    flatbuffers::FlatBufferBuilder builder;
    codec::encodeRequest(builder,request,1,2,3);
    const auto* encoded=flatbuffers::GetRoot<wire::ConstructionRequest>(builder.GetBufferPointer());
    CHECK(encoded->expected_list_revision()==0);
    CHECK(encoded->selections()->Get(0)->expected_list_revision()==revision);
    CHECK(encoded->selections()->Get(1)->expected_list_revision()==42);
    auto error=wire::validateConstructionRequest(*encoded);
    if(revision < -1) { REQUIRE(error);CHECK(*error=="invalid construction selection list revision"); }
    else CHECK_FALSE(error);
  }
  // The appended field is absent in an older selection buffer.
  flatbuffers::FlatBufferBuilder builder;
  builder.Finish(wire::CreateConstructionSelection(builder,0,-1,-1,-1,-1,1));
  CHECK(flatbuffers::GetRoot<wire::ConstructionSelection>(builder.GetBufferPointer())->expected_list_revision()==-1);
  request.selections.clear();
  builder.Clear();codec::encodeRequest(builder,request,1,2,3);
  CHECK_FALSE(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(builder.GetBufferPointer())));
}

TEST_CASE("construction native decisions survive request codecs and validation") {
  auto error=[](const wm::ManagementRequest& r) {
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* v=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(v->direction()==r.direction);CHECK(v->depth()==r.depth);
    CHECK(v->origin()->x()==r.x);CHECK(v->origin()->y()==r.y);CHECK(v->origin()->z()==r.z);
    if(!r.selections.empty())CHECK(v->selections()->Get(0)->count()==r.selections[0].count);
    return wire::validateConstructionRequest(*v);
  };
  wm::ManagementRequest r;r.action=wm::ManagementAction::Preview;r.definition="Construction:Stairs";
  REQUIRE(error(r));CHECK(*error(r)=="Must span multiple elevations");
  r.depth=2;CHECK_FALSE(error(r));r.depth=1;r.definition="SiegeEngine:Ballista";
  for(uint8_t d=0;d<8;++d){r.direction=d;CHECK_FALSE(error(r));}
  r.direction=8;REQUIRE(error(r));CHECK(*error(r)=="invalid dimensions or orientation");r.direction=0;
  r.action=wm::ManagementAction::Place;
  for(const char* key:{"Weapon","Trap:WeaponTrap"}) {
    r.definition=key;r.selections={{int16_t(r.definition=="Weapon" ? 0 : 1)}};
    CHECK(r.selections[0].count==1);CHECK_FALSE(error(r));
    r.selections[0].count=10;CHECK_FALSE(error(r));
    r.selections[0].count=11;REQUIRE(error(r));CHECK(*error(r)=="Weapon count must be between 1 and 10");
    r.selections[0].count=0;REQUIRE(error(r));CHECK(*error(r)=="invalid or duplicate construction selection");
    r.selections.clear();REQUIRE(error(r));CHECK(*error(r)=="Weapon count must be between 1 and 10");
  }
  r.action=wm::ManagementAction::ConstructionMaterials;r.definition="Chair";r.filter=0;
  r.x=10;r.y=20;r.z=3;CHECK_FALSE(error(r));
}

TEST_CASE("construction codec preserves eight facings and per-tile totals") {
  flatbuffers::FlatBufferBuilder b;
  std::vector<flatbuffers::Offset<wire::ConstructionFootprint>> footprints;
  for(uint8_t d=0;d<8;++d)footprints.push_back(wire::CreateConstructionFootprint(b,d,1,1,0,0));
  const auto fps=b.CreateVector(footprints);const auto key=b.CreateString("SiegeEngine:Ballista");
  wire::BuildingDefinitionBuilder def(b);def.add_key(key);def.add_width(1);def.add_height(1);
  def.add_orientations(255);def.add_footprints(fps);const auto definition=def.Finish();
  const auto catalog=b.CreateVector(std::vector{definition});
  const auto filter=wire::CreateConstructionFilter(b,0,-1,-1,0,0,1024);
  const auto filters=b.CreateVector(std::vector{filter});
  wire::ConstructionStateBuilder c(b);c.add_filters(filters);c.add_placed(1024);const auto construction=c.Finish();
  wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_catalog(catalog);
  state.add_required(1024);state.add_construction(construction);b.Finish(state.Finish());
  const auto* encoded=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
  CHECK_FALSE(wire::validateManagementState(*encoded));
  wm::ManagementState decoded;codec::decodeConstruction(encoded,decoded);
  REQUIRE(decoded.catalog.size()==1);CHECK(decoded.catalog[0].orientations==255);
  REQUIRE(decoded.catalog[0].footprints.size()==8);CHECK(decoded.catalog[0].footprints[7].direction==7);
  CHECK(decoded.required==1024);CHECK(decoded.construction.placed==1024);
  CHECK(decoded.construction.filters[0].quantity==1024);
}

TEST_CASE("material lists require a placement origin and eight footprints is the limit") {
  for(int missing=0;missing<3;++missing) {
    flatbuffers::FlatBufferBuilder b;
    const auto key=b.CreateString(missing==0 ? "" : "Chair");const wire::TilePos origin(0,0,0);
    wire::ConstructionRequestBuilder request(b);request.add_client_id(1);request.add_seq(1);request.add_world_epoch(1);
    request.add_action(wire::ManagementAction::ConstructionMaterials);request.add_definition(key);
    request.add_filter(missing==1 ? -1 : 0);if(missing!=2)request.add_origin(&origin);b.Finish(request.Finish());
    const auto error=wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer()));
    REQUIRE(error);CHECK(*error=="definition, filter and origin required");
  }
  flatbuffers::FlatBufferBuilder b;
  std::vector<flatbuffers::Offset<wire::ConstructionFootprint>> rows;
  for(uint8_t d=0;d<9;++d)rows.push_back(wire::CreateConstructionFootprint(b,d%8,1,1,0,0));
  const auto fps=b.CreateVector(rows);const auto key=b.CreateString("SiegeEngine:Ballista");
  wire::BuildingDefinitionBuilder definition(b);definition.add_key(key);definition.add_width(1);definition.add_height(1);
  definition.add_footprints(fps);const auto def=definition.Finish();const auto catalog=b.CreateVector(std::vector{def});
  wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_catalog(catalog);b.Finish(state.Finish());
  const auto error=wire::validateManagementState(*flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer()));
  REQUIRE(error);CHECK(*error=="too many construction footprints");
}


// These maximal wire fixtures exercise schema bounds, not recorded native labels.
// Producer fields: construction.lua definitions/filter_row/materials/placement.
namespace {
struct ConstructionWire {
  flatbuffers::FlatBufferBuilder b;
  const wire::ManagementState* state=nullptr;
  ConstructionWire(const std::string& field="", int64_t n=0, int page=0) {
    auto value=[&](const char* key,int64_t normal){return field==key?n:normal;};
    auto text=[&](const char* key,size_t normal){return b.CreateString(std::string(size_t(value(key,normal)),'x'));};
    std::vector<flatbuffers::Offset<wire::ConstructionFilter>> filters;
    for(int i=0;i<value("filters",8);++i)
      filters.push_back(wire::CreateConstructionFilter(b,int16_t(value("filter_index",i)),
        int16_t(value("filter_type",-1)),int16_t(value("filter_subtype",-1)),
        text("filter_caption",64),text("requirement",64),int32_t(value("quantity",-1))));
    auto fs=b.CreateVector(filters);
    std::vector<flatbuffers::Offset<wire::ConstructionFootprint>> footprints;
    for(int i=0;i<value("footprints",5);++i)
      footprints.push_back(wire::CreateConstructionFootprint(b,uint8_t(value("direction",i)),
        uint16_t(value("fp_width",31)),uint16_t(value("fp_height",31)),
        int16_t(value("center_x",field=="fp_width"?0:30)),int16_t(value("center_y",-1))));

    std::vector<flatbuffers::Offset<wire::BuildingDefinition>> catalog;
    if(page==0)for(int i=0;i<value("catalog",128);++i) {
      std::string key=std::to_string(i);key.resize(size_t(value("key",64)),'k');
      const auto k=b.CreateString(key),name=text("name",128),reason=text("reason",128),native=text("native_name",128),
        family=text("family",64),subtype=text("subtype_key",64),custom=text("custom_code",64);
      // No shared child vectors: model the producer's independently encoded rows.
      std::vector<flatbuffers::Offset<wire::ConstructionFilter>> ownFilters;
      for(int f=0;f<value("filters",8);++f)
        ownFilters.push_back(wire::CreateConstructionFilter(b,int16_t(value("filter_index",f)),
          int16_t(value("filter_type",-1)),int16_t(value("filter_subtype",-1)),
          text("filter_caption",64),text("requirement",64),int32_t(value("quantity",-1))));
      const auto ownFs=b.CreateVector(ownFilters);
      std::vector<flatbuffers::Offset<wire::ConstructionFootprint>> ownFootprints;
      for(int f=0;f<value("footprints",5);++f)
        ownFootprints.push_back(wire::CreateConstructionFootprint(b,uint8_t(value("direction",f)),
          uint16_t(value("fp_width",31)),uint16_t(value("fp_height",31)),
          int16_t(value("center_x",field=="fp_width"?0:30)),int16_t(value("center_y",-1))));
      const auto ownFps=b.CreateVector(ownFootprints);
      wire::BuildingDefinitionBuilder d(b);d.add_key(k);d.add_name(name);d.add_reason(reason);
      d.add_native_name(native);d.add_family(family);d.add_subtype_key(subtype);d.add_custom_code(custom);
      d.add_width(uint16_t(value("width",31)));d.add_height(uint16_t(value("height",31)));
      d.add_area_mode(uint8_t(value("area_mode",4)));d.add_orientations(31);
      d.add_max_width(uint16_t(value("max_width",31)));d.add_max_height(uint16_t(value("max_height",31)));
      d.add_max_depth(uint16_t(value("max_depth",256)));d.add_filters(ownFs);d.add_footprints(ownFps);
      catalog.push_back(d.Finish());
    }
    const auto cats=b.CreateVector(catalog);
    std::vector<flatbuffers::Offset<wire::ConstructionMaterial>> materials;
    if(page==1)for(int i=0;i<value("materials",field=="mat_index"?1:128);++i)
      materials.push_back(wire::CreateConstructionMaterial(b,int16_t(value("item_type",-1)),
        int16_t(value("item_subtype",-1)),int16_t(value("mat_type",-1)),int32_t(value("mat_index",i)),
        text("material_name",128),text("material_caption",64),uint32_t(value("count",1))));
    auto mats=b.CreateVector(materials);
    auto mask=b.CreateVector(std::vector<uint8_t>(size_t(value("mask_size",page==2?1024:0)),uint8_t(value("mask",1))));
    auto pieces=b.CreateVector(std::vector<uint8_t>(size_t(value("pieces_size",page==2?1024:0)),uint8_t(value("piece",3))));
    auto key=text("building_key",64);
    std::vector<flatbuffers::Offset<wire::PressureCreatureExample>> examples;
    if(page==0)for(int i=0;i<value("pressure_count",200);++i)
      examples.push_back(wire::CreatePressureCreatureExample(b,int32_t(value("pressure_size",(i+1)*1000)),
          int32_t(value("pressure_race",i)),text("pressure_name",128)));
    auto pressureExamples=b.CreateVector(examples);
    wire::ConstructionStateBuilder c(b);c.add_building_key(key);c.add_filter(int16_t(value("filter",7)));
    c.add_pressure_creatures(pressureExamples);
    c.add_filters(fs);c.add_materials(mats);c.add_total(128);c.add_list_revision(uint64_t(value("list_revision",INT64_MAX)));
    c.add_estimated(true);c.add_build_phase(uint8_t(value("build_phase",2)));
    c.add_build_done(uint32_t(value("build_done",128)));c.add_build_total(128);
    c.add_placed(uint32_t(value("placed",1024)));c.add_skipped(uint32_t(value("skipped",0)));
    c.add_first_building(int32_t(value("first_building",-1)));c.add_valid_mask(mask);c.add_pieces(pieces);
    if(!footprints.empty())c.add_footprint(footprints[0]);
    const auto construction=c.Finish();
    wire::ManagementStateBuilder s(b);s.add_revision(1);s.add_schema_version(uint32_t(value("version",wire::kManagementVersion)));
    s.add_catalog(cats);s.add_construction(construction);b.Finish(s.Finish());
    state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
  }
  std::optional<std::string> error() const {return wire::validateManagementState(*state);}
};
}

TEST_CASE("construction maximal pages and complete owned field decoding") {
  for(int page=0;page<3;++page) {
    ConstructionWire fixture("",0,page);
    REQUIRE_FALSE(fixture.error());CHECK(fixture.b.GetSize()<wire::kManagementCapacity);
    std::cout<<"CONSTRUCTION_MAX_PAGE "<<page<<" "<<fixture.b.GetSize()<<" bytes\n";
    wm::ManagementState s;codec::decodeConstruction(fixture.state,s);
    const auto& c=s.construction;
    CHECK(c.buildingKey==std::string(64,'x'));CHECK(c.filter==7);CHECK(c.filters.size()==8);
    CHECK(c.total==128);CHECK(c.listRevision==INT64_MAX);CHECK(c.estimated);CHECK(c.buildPhase==2);
    CHECK(c.buildDone==128);CHECK(c.buildTotal==128);CHECK(c.placed==1024);CHECK(c.skipped==0);CHECK(c.firstBuilding==-1);
    REQUIRE(c.footprint);CHECK(c.footprint->direction==0);CHECK(c.footprint->width==31);CHECK(c.footprint->height==31);
    CHECK(c.footprint->centerX==30);CHECK(c.footprint->centerY==-1);
    for(int i=0;i<8;++i) {const auto& f=c.filters[i];CHECK(f.index==i);CHECK(f.itemType==-1);CHECK(f.itemSubtype==-1);
      CHECK(f.caption==std::string(64,'x'));CHECK(f.requirement==std::string(64,'x'));CHECK(f.quantity==-1);}
    if(page==0) {
      REQUIRE(c.pressureCreatures.size()==200);
      for(int i=0;i<200;++i){CHECK(c.pressureCreatures[i].size==(i+1)*1000);CHECK(c.pressureCreatures[i].raceId==i);CHECK(c.pressureCreatures[i].name==std::string(128,'x'));}
      REQUIRE(s.catalog.size()==128);const auto& d=s.catalog[0];CHECK(d.key.size()==64);CHECK(d.name.size()==128);
      CHECK(d.reason.size()==128);CHECK(d.nativeName.size()==128);CHECK(d.family.size()==64);
      CHECK(d.subtypeKey.size()==64);CHECK(d.customCode.size()==64);CHECK(d.areaMode==4);CHECK(d.orientations==31);
      CHECK(d.maxWidth==31);CHECK(d.maxHeight==31);CHECK(d.maxDepth==256);CHECK(d.filters.size()==8);CHECK(d.footprints.size()==5);
    } else if(page==1) {
      REQUIRE(c.materials.size()==128);for(int i=0;i<128;++i) {const auto& m=c.materials[i];
        CHECK(m.itemType==-1);CHECK(m.itemSubtype==-1);CHECK(m.matType==-1);CHECK(m.matIndex==i);
        CHECK(m.name.size()==128);CHECK(m.caption.size()==64);CHECK(m.count==1);}
    } else {CHECK(c.validMask==std::vector<uint8_t>(1024,1));CHECK(c.pieces==std::vector<uint8_t>(1024,3));}
    std::fill_n(fixture.b.GetBufferPointer(),fixture.b.GetSize(),uint8_t(0));
    CHECK(c.buildingKey==std::string(64,'x'));CHECK(c.filters[0].requirement==std::string(64,'x'));
    if(page==0)CHECK(c.pressureCreatures[199].name==std::string(128,'x'));
  }
  flatbuffers::FlatBufferBuilder b;b.Finish(wire::CreateManagementState(b));
  wm::ManagementState defaults;codec::decodeConstruction(flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer()),defaults);
  CHECK(defaults.construction.filter==-1);CHECK(defaults.construction.firstBuilding==-1);CHECK(defaults.construction.listRevision==0);
  CHECK(defaults.construction.filters.empty());CHECK(defaults.construction.materials.empty());CHECK_FALSE(defaults.construction.footprint);
}

TEST_CASE("construction state rejects each over-limit field with exact messages") {
  for(const char* field:{"pressure_size","pressure_race"}) {
    ConstructionWire invalid(field,std::string(field)=="pressure_size"?1000:-1);
    REQUIRE(invalid.error());CHECK(*invalid.error()=="invalid pressure creature examples");
  }
  struct Case {const char* field;int64_t accept,reject;const char* error;int page=0;};
  for(const auto& c:std::initializer_list<Case>{
      {"pressure_count",200,199,"invalid pressure creature examples"},
      {"pressure_count",200,201,"invalid pressure creature examples"},
      {"pressure_name",128,129,"invalid pressure creature examples"},
      {"pressure_race",0,-2,"invalid pressure creature examples"},
      {"catalog",128,129,"catalog too large"},{"key",64,65,"invalid definition"},
      {"name",128,129,"invalid definition"},{"reason",128,129,"invalid definition"},
      {"native_name",128,129,"invalid definition"},{"family",64,65,"invalid definition"},
      {"subtype_key",64,65,"invalid definition"},{"custom_code",64,65,"invalid definition"},
      {"width",31,32,"invalid definition"},{"height",31,32,"invalid definition"},
      {"max_width",31,32,"invalid definition"},{"max_height",31,32,"invalid definition"},
      {"max_depth",256,257,"invalid definition"},{"area_mode",4,5,"invalid definition"},
      {"filter",7,8,"invalid construction result"},{"filter",-1,-2,"invalid construction result"},
      {"first_building",-1,-2,"invalid construction result"},{"build_phase",3,4,"invalid construction result"},
      {"build_done",128,129,"invalid construction result"},{"placed",1024,1025,"invalid construction result"},
      {"skipped",0,1,"invalid construction result"},{"list_revision",INT64_MAX,INT64_MIN,"invalid construction result"},
      {"building_key",64,65,"invalid construction result"},{"filters",8,9,"invalid construction result"},
      {"filter_caption",64,65,"invalid construction result"},{"requirement",64,65,"invalid construction result"},
      {"filter_type",-1,-2,"invalid construction result"},{"filter_subtype",-1,-2,"invalid construction result"},
      {"quantity",-1,-2,"invalid construction result"},{"fp_width",31,32,"invalid construction result"},
      {"fp_height",31,32,"invalid construction result"},{"center_x",30,31,"invalid construction result"},
      {"center_y",-1,-2,"invalid construction result"},{"footprints",8,9,"too many construction footprints"},
      {"mask_size",1024,1025,"construction mask too large",2},{"mask",1,2,"invalid construction mask",2},
      {"pieces_size",1024,1025,"construction pieces too large",2},{"piece",3,4,"invalid construction piece",2},
      {"materials",128,129,"construction materials page too large",1},{"count",1,0,"invalid construction material",1},
      {"item_type",-1,-2,"invalid construction material",1},{"item_subtype",-1,-2,"invalid construction material",1},
      {"mat_type",-1,-2,"invalid construction material",1},
      {"mat_index",-1,-2,"invalid construction material",1},
      {"width",1,0,"invalid definition"},{"height",1,0,"invalid definition"},
      {"fp_width",1,0,"invalid construction result"},{"fp_height",1,0,"invalid construction result"},
      {"center_x",-1,-2,"invalid construction result"},{"center_y",30,31,"invalid construction result"},
      {"material_name",128,129,"invalid construction material",1},{"material_caption",64,65,"invalid construction material",1},
      {"version",wire::kManagementVersion,wire::kManagementVersion-1,"invalid management version/revision"}}) {
    CAPTURE(c.field);ConstructionWire accepted(c.field,c.accept,c.page);CHECK_FALSE(accepted.error());
    ConstructionWire rejected(c.field,c.reject,c.page);REQUIRE(rejected.error());CHECK(*rejected.error()==c.error);
  }
  for(const char* key:{"name","reason","native_name","family","subtype_key","custom_code","filter_caption","requirement","building_key"})
    CHECK_FALSE(ConstructionWire(key,0).error());
  for(const char* key:{"catalog","filters","footprints","mask_size","pieces_size","materials"})
    CHECK_FALSE(ConstructionWire(key,0).error());
  for(const char* key:{"filter","first_building","build_phase","build_done","placed","list_revision","quantity","area_mode","max_width","max_height","max_depth"})
    CHECK_FALSE(ConstructionWire(key,0).error());
  for(const char* key:{"mask","piece"})CHECK_FALSE(ConstructionWire(key,0,2).error());
  CHECK_FALSE(ConstructionWire("mat_index",0,1).error());
  CHECK_FALSE(ConstructionWire("count",UINT32_MAX,1).error());
  CHECK_FALSE(ConstructionWire("first_building",INT32_MAX).error());
  ConstructionWire badDirection("direction",8);REQUIRE(badDirection.error());CHECK(*badDirection.error()=="invalid construction result");
  for(const char* key:{"filter_index","direction"}) {
    ConstructionWire duplicate(key,0);REQUIRE(duplicate.error());
    CHECK(*duplicate.error()==(std::string(key)=="direction"?"invalid or duplicate construction footprint":"invalid construction result"));
  }
}

TEST_CASE("construction request boundary and absent-field matrix") {
  auto check=[](const wm::ManagementRequest& r,const std::string& expected="") {
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* q=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(q->depth()==r.depth);CHECK(q->filter()==r.filter);CHECK(q->retracting()==r.retracting);
    CHECK(q->roller_speed()==r.rollerSpeed);
    REQUIRE(bool(q->track_stop())==bool(r.trackStop));
    if(r.trackStop){CHECK(q->track_stop()->friction()==r.trackStop->friction);CHECK(q->track_stop()->dump_direction()==r.trackStop->dumpDirection);}
    REQUIRE(bool(q->pressure_plate())==bool(r.pressurePlate));
    if(r.pressurePlate) {
      const auto* p=q->pressure_plate();const auto& v=*r.pressurePlate;
      CHECK(p->units()==v.units);CHECK(p->water()==v.water);CHECK(p->magma()==v.magma);
      CHECK(p->citizens()==v.citizens);CHECK(p->resets()==v.resets);CHECK(p->track()==v.track);
      CHECK(p->unit_min()==v.unitMin);CHECK(p->unit_max()==v.unitMax);
      CHECK(p->water_min()==v.waterMin);CHECK(p->water_max()==v.waterMax);
      CHECK(p->magma_min()==v.magmaMin);CHECK(p->magma_max()==v.magmaMax);
      CHECK(p->track_min()==v.trackMin);CHECK(p->track_max()==v.trackMax);
    }
    CHECK(q->expected_list_revision()==uint64_t(r.expectedListRevision));
    CHECK(wire::validateConstructionRequest(*q).value_or("")==expected);
  };
  wm::ManagementRequest r;r.action=wm::ManagementAction::Preview;r.definition="Construction:Stairs";
  r.definition="Rollers";
  for(auto speed:{0u,10000u,20000u,30000u,40000u,50000u}){r.rollerSpeed=speed;check(r);}
  for(auto speed:{1u,9999u,15000u,60000u,UINT32_MAX}){r.rollerSpeed=speed;check(r,"invalid roller speed intent");}
  r.rollerSpeed=10000;r.definition="Chair";check(r,"invalid roller speed intent");
  r.definition="Rollers";r.action=wm::ManagementAction::Catalog;check(r,"invalid roller speed intent");
  r.action=wm::ManagementAction::Place;check(r);
  r.rollerSpeed=0;r.action=wm::ManagementAction::Preview;r.definition="Construction:Stairs";
  r.definition="Trap:TrackStop";check(r,"track stop options required");
  r.trackStop=wm::ManagementRequest::TrackStopOptions{};
  for(auto friction:{10u,50u,500u,10000u,50000u})for(uint8_t dump=0;dump<=4;++dump){r.trackStop->friction=friction;r.trackStop->dumpDirection=dump;check(r);}
  r.trackStop->friction=0;check(r,"invalid track stop intent");r.trackStop->friction=50000;
  r.trackStop->dumpDirection=5;check(r,"invalid track stop intent");r.trackStop->dumpDirection=0;
  r.definition="Chair";check(r,"invalid track stop intent");r.definition="Trap:TrackStop";
  r.action=wm::ManagementAction::Catalog;check(r,"invalid track stop intent");
  r.action=wm::ManagementAction::Place;check(r);
  r.trackStop.reset();r.action=wm::ManagementAction::Preview;r.definition="Construction:Stairs";
  r.definition="Trap:PressurePlate";check(r,"pressure plate options required");
  r.pressurePlate=wm::ManagementRequest::PressurePlateOptions{};check(r);
  for(int bits=0;bits<64;++bits) {
    auto& p=*r.pressurePlate;p.units=bits&1;p.water=bits&2;p.magma=bits&4;p.citizens=bits&8;p.resets=bits&16;p.track=bits&32;check(r);
  }
  for(int lo=0;lo<=7;++lo)for(int hi=lo;hi<=7;++hi) {
    auto& p=*r.pressurePlate;p.waterMin=p.magmaMin=int8_t(lo);p.waterMax=p.magmaMax=int8_t(hi);check(r);
  }
  for(int lo=1000;lo<=200000;lo+=1000) {r.pressurePlate->unitMin=lo;r.pressurePlate->unitMax=lo+999;check(r);}
  r.pressurePlate->unitMax=200000999;check(r,"invalid pressure plate intent");
  r.pressurePlate=wm::ManagementRequest::PressurePlateOptions{};
  r.pressurePlate->unitMin=1500;check(r,"invalid pressure plate intent");r.pressurePlate->unitMin=5000;
  r.pressurePlate->waterMin=-1;check(r,"invalid pressure plate intent");r.pressurePlate->waterMin=1;
  r.pressurePlate->magmaMax=8;check(r,"invalid pressure plate intent");r.pressurePlate->magmaMax=7;
  r.pressurePlate->trackMax=2;check(r,"invalid pressure plate intent");r.pressurePlate->trackMax=2000;
  r.definition="Chair";check(r,"invalid pressure plate intent");r.definition="Trap:PressurePlate";
  r.action=wm::ManagementAction::Catalog;check(r,"invalid pressure plate intent");
  r.action=wm::ManagementAction::Place;check(r);
  r.pressurePlate.reset();r.action=wm::ManagementAction::Preview;r.definition="Construction:Stairs";
  r.width=4;r.depth=256;check(r);r.depth=257;check(r,"invalid construction depth or volume");
  r.depth=256;r.width=5;check(r,"invalid construction depth or volume");
  r.definition="Chair";r.width=1;r.depth=0;check(r,"invalid construction depth or volume");r.depth=1;check(r);
  r.retracting=true;check(r);r.direction=1;check(r,"invalid retracting orientation");r.direction=0;r.retracting=false;
  r.action=wm::ManagementAction::Catalog;r.depth=2;check(r,"unexpected construction placement fields");r.depth=1;
  r.retracting=true;check(r,"unexpected construction placement fields");r.retracting=false;
  for(auto rev:{int64_t(0),int64_t(INT64_MAX)}){r.expectedListRevision=rev;check(r);}
  r.expectedListRevision=INT64_MIN;check(r,"invalid construction list revision");r.expectedListRevision=0;
  for(auto f:{int16_t(-2),int16_t(-1),int16_t(0),int16_t(7),int16_t(8)}) {
    r.action=wm::ManagementAction::ConstructionMaterials;r.filter=f;
    check(r,f < -1 || f>7?"invalid construction filter":f==-1?"definition, filter and origin required":"");
  }
  r.filter=0;r.definition="";check(r,"definition, filter and origin required");r.definition="Chair";
  r.action=wm::ManagementAction::Catalog;check(r,"unexpected construction filter");r.filter=-1;
  r.action=wm::ManagementAction::Preview;r.expectedListRevision=1;check(r,"unexpected construction list revision");r.expectedListRevision=0;
  r.action=wm::ManagementAction::Place;
  for(int i=0;i<16;++i)r.selections.push_back({int16_t(i%8),-1,-1,-1,i,1,INT64_MAX});
  check(r);
  r.selections.push_back({0,-1,-1,-1,16,1,INT64_MAX});check(r,"too many construction selections");r.selections.pop_back();
  r.selections[1]=r.selections[0];check(r,"invalid or duplicate construction selection");r.selections.resize(1);
  for(auto f:{int16_t(-1),int16_t(0),int16_t(7),int16_t(8)}){r.selections[0].filter=f;check(r,f<0||f>7?"invalid or duplicate construction selection":"");}
  r.selections[0].filter=0;
  for(auto member:{&wm::ConstructionSelection::itemType,&wm::ConstructionSelection::itemSubtype,&wm::ConstructionSelection::matType}) {
    r.selections[0].*member=-1;check(r);r.selections[0].*member=0;check(r);
    r.selections[0].*member=-2;check(r,"invalid or duplicate construction selection");r.selections[0].*member=-1;
  }
  r.selections[0].matIndex=-2;check(r,"invalid or duplicate construction selection");r.selections[0].matIndex=-1;check(r);
  r.selections[0].count=0;check(r,"invalid or duplicate construction selection");r.selections[0].count=1;
  r.selections[0].count=UINT32_MAX;check(r);r.selections[0].count=1;
  r.action=wm::ManagementAction::Preview;check(r,"unexpected construction selections");r.selections.clear();check(r);
  r.action=wm::ManagementAction::Catalog;r.definition="";check(r);
}

#include "../../bridge/plugin/construction_effects.h"
TEST_CASE("construction committed chunks mark mutations and every intersecting block") {
  wire::TilePos origin(15,31,7);bool mutated=false;
  std::vector<std::tuple<int,int,int>> hints;
  auto hint=[&](int x,int y,int z){hints.emplace_back(x,y,z);};
  df3d_management::constructionEffects(0,&origin,2,2,2,mutated,hint);
  CHECK_FALSE(mutated);CHECK(hints.empty());
  // The helper receives committed count even when the Lua reply is Rejected.
  df3d_management::constructionEffects(1,&origin,2,2,2,mutated,hint);
  CHECK(mutated);
  const std::vector<std::tuple<int,int,int>> expected{
    {0,16,7},{16,16,7},{0,32,7},{16,32,7},
    {0,16,8},{16,16,8},{0,32,8},{16,32,8}};
  CHECK(hints==expected);
  df3d_management::constructionEffects(0,&origin,2,2,2,mutated,hint);
  CHECK(mutated);CHECK(hints==expected);
}


TEST_CASE("maximal area reply families fit the channel without truncation") {
  // Synthetic wire maxima, not claims about native captions or captured worlds.
  // InspectAtTile has 32768 extents and 8192 link IDs across its whole reply.
  for(int family=0;family<6;++family)for(bool overflow:{false,true}) {
    CAPTURE(family);CAPTURE(overflow);flatbuffers::FlatBufferBuilder b;
    auto caption=[&](){return b.CreateString(std::string(512,'x'));};
    std::vector<flatbuffers::Offset<wire::AreaInfo>> records;
    if(family!=4) {
      const int count=family==5?64:1,cells=32768/count,linkCount=family==5?64:1024;
      for(int i=0;i<count;++i) {
        // Keep family 5 exactly at the byte budget, including each site identity.
        auto name=family==5 ? b.CreateString(std::string(508,'x')) : caption();
        auto owner=caption(),zoneLabel=caption(),location=caption(),religion=caption();
        auto extents=b.CreateVector(std::vector<uint8_t>(cells,1));
        std::vector<int32_t> ids;for(int j=0;j<linkCount;++j)ids.push_back(100000+j);
        auto gives=b.CreateVector(ids),takes=b.CreateVector(ids);wire::TilePos origin(1,2,3);
        wire::AreaInfoBuilder info(b);info.add_id(i);info.add_origin(&origin);info.add_width(256);info.add_height(cells/256);
        info.add_extents(extents);info.add_name(name);info.add_owner_name(owner);info.add_zone_label(zoneLabel);
        info.add_location_name(location);info.add_religion(religion);info.add_gives(gives);info.add_takes(takes);
        records.push_back(info.Finish());
      }
    }
    std::vector<flatbuffers::Offset<wire::AreaSettingRow>> settings;
    std::vector<flatbuffers::Offset<wire::AreaLocationRow>> locations;
    std::vector<flatbuffers::Offset<wire::AreaCandidateRow>> candidates;
    std::vector<flatbuffers::Offset<wire::AreaLinkRow>> links;
    std::vector<flatbuffers::Offset<wire::AreaChoice>> choices;
    for(int i=0;i<(overflow?129:128) && family<5;++i) {
      auto text=caption();
      if(family==0){auto key=std::to_string(i);key.resize(64,'k');settings.push_back(wire::CreateAreaSettingRow(b,b.CreateString(key),i,text,4,3,true));}
      if(family==1)locations.push_back(wire::CreateAreaLocationRow(b,i,text,5,caption()));
      if(family==2)candidates.push_back(wire::CreateAreaCandidateRow(b,i,text,caption(),1,7,true,true,15));
      if(family==3)links.push_back(wire::CreateAreaLinkRow(b,i,wire::AreaKind::Workshop,2,text));
      if(family==4)choices.push_back(wire::CreateAreaChoice(b,i,text,caption()));
    }
    auto as=b.CreateVector(records);auto ss=b.CreateVector(settings);auto ls=b.CreateVector(locations);
    auto cs=b.CreateVector(candidates);auto ks=b.CreateVector(links);auto os=b.CreateVector(choices);
    auto query=b.CreateString(family==5 && overflow?"x":"");
    wire::AreaStateBuilder area(b);area.add_areas(as);area.add_settings(ss);area.add_locations(ls);
    area.add_candidates(cs);area.add_links(ks);area.add_choices(os);area.add_query(query);
    auto domain=area.Finish();wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_area(domain);b.Finish(root.Finish());
    flatbuffers::Verifier verifier(b.GetBufferPointer(),b.GetSize());REQUIRE(verifier.VerifyBuffer<wire::ManagementState>(nullptr));
    const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    auto error=wire::validateManagementState(*state);
    if(overflow)CHECK(error.value_or("")== (family==5?"area response exceeds bounded payload":"area response too large"));
    else {
      REQUIRE_FALSE(error);CHECK(b.GetSize()<wire::kManagementCapacity);
      const auto decoded=codec::decodeArea(state->area());
      CHECK(decoded.areas.size()==records.size());
      if(!decoded.areas.empty())CHECK(decoded.areas[0].extents.size()==size_t(family==5?512:32768));
      CHECK(decoded.settings.size()==settings.size());CHECK(decoded.locations.size()==locations.size());
      CHECK(decoded.candidates.size()==candidates.size());CHECK(decoded.links.size()==links.size());CHECK(decoded.choices.size()==choices.size());
      std::cout<<"AREA_PAGE_BYTES family="<<family<<" bytes="<<b.GetSize()<<'\n';
    }
  }
}


TEST_CASE("area validator checks the complete action operation matrix") {
  // The table is the approved semantic matrix, independent of implementation.
  const int actionFor[]{0,9,11,11,11,0,9,11,11,11,9,11,11,11,14,13};
  for(int action=7;action<=14;++action)for(int op=0;op<=15;++op) {
    CAPTURE(action);CAPTURE(op);wm::ManagementRequest request;
    request.action=wm::ManagementAction(action);auto& a=request.area;
    a.id=7;a.operation=wm::AreaOperation(op);a.expectedRevision=1;
    a.kind=op==15?wm::AreaKind::Workshop:((op>=6 && op<=9) || op==11 || op==12 || op==14)?wm::AreaKind::Zone:wm::AreaKind::Stockpile;
    if(op==0 && action==13)a.linkId=8;
    if(op==2){a.scope=1;a.value=1;a.rowKey="row";}
    if(op==3)a.preset=1;
    if(op==5){a.paintMode=1;a.paintZ=1;a.spans={{1,1,1}};}
    if(op==7)a.locationId=-1;
    if(op==8){a.locationKind=4;a.profession=0;}
    if(op==9)a.zoneSettings.pondMode=1;
    if(op==11){a.unitId=0;a.assign=0;}
    if(op==12){a.squadId=0;a.squadUse=0;}
    if(op==13)a.organic=0;
    if(op==14)a.candidateKind=1;
    if(op==15)a.linkId=8;
    const bool allowed=op==0 || (op==5?(action==10 || action==11):action==actionFor[op]);
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    CHECK(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer())).value_or("")==
        (allowed?"":"Area operation is not valid for this action"));
    if(allowed) {
      a.kind=op==15?wm::AreaKind::Stockpile:wm::AreaKind::Workshop;
      flatbuffers::FlatBufferBuilder wrong;codec::encodeRequest(wrong,request,1,2,3);
      CHECK(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(wrong.GetBufferPointer())).value_or("")==
          (op==10?"":"Workshop kind is only valid for workshop links"));
    }
  }
}

TEST_CASE("area appended fields reject legacy operations and empty values stay absent") {
  using Edit=void(*)(wm::AreaRequest&);
  const std::pair<const char*,Edit> fields[]{
    {"expected_list_revision",[](auto& a){a.expectedListRevision=1;}},
    {"list_key",[](auto& a){a.listKey="x";}},{"row_key",[](auto& a){a.rowKey="x";}},
    {"scope",[](auto& a){a.scope=1;}},{"value",[](auto& a){a.value=1;}},
    {"preset",[](auto& a){a.preset=1;}},{"name",[](auto& a){a.name="x";}},
    {"spans",[](auto& a){a.spans={{1,1,1}};}},{"paint_mode",[](auto& a){a.paintMode=1;}},
    {"paint_z",[](auto& a){a.paintZ=0;}},{"location_id",[](auto& a){a.locationId=-1;}},
    {"location_kind",[](auto& a){a.locationKind=1;}},{"profession",[](auto& a){a.profession=0;}},
    {"deity_kind",[](auto& a){a.deityKind=1;}},{"deity_id",[](auto& a){a.deityId=0;}},
    {"zone_settings",[](auto& a){a.zoneSettings.pondMode=1;}},{"unit_id",[](auto& a){a.unitId=0;}},
    {"assign",[](auto& a){a.assign=0;}},{"squad_id",[](auto& a){a.squadId=0;}},
    {"squad_use",[](auto& a){a.squadUse=0;}},{"organic",[](auto& a){a.organic=0;}},
    {"inorganic",[](auto& a){a.inorganic=0;}},{"candidate_kind",[](auto& a){a.candidateKind=1;}},
    {"sort",[](auto& a){a.sort=1;}},{"sort_descending",[](auto& a){a.sortDescending=true;}}
  };
  for(const auto& [name,edit]:fields) {
    CAPTURE(name);wm::ManagementRequest request;request.action=wm::ManagementAction::AreaInspect;request.area.id=7;
    flatbuffers::FlatBufferBuilder empty;codec::encodeRequest(empty,request,1,2,3);
    CHECK_FALSE(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(empty.GetBufferPointer())));
    edit(request.area);flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    CHECK(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer())).value_or("")==
        std::string("Field ")+name+" does not belong to this operation");
  }
}


TEST_CASE("area operations refuse each legacy field before producer dispatch") {
  for(int field=0;field<15;++field) {
    CAPTURE(field);flatbuffers::FlatBufferBuilder b;wire::TilePos origin(0,0,0);
    wire::AreaRequestBuilder area(b);area.add_operation(wire::AreaOperation::Rename);area.add_id(7);area.add_expected_revision(1);
    switch(field) {
      case 0:area.add_origin(&origin);break;case 1:area.add_width(2);break;case 2:area.add_height(2);break;
      case 3:area.add_zone_type(0);break;case 4:area.add_categories(1);break;case 5:area.add_changed_categories(1);break;
      case 6:area.add_barrels(0);break;case 7:area.add_bins(0);break;case 8:area.add_wheelbarrows(0);break;
      case 9:area.add_links_only(0);break;case 10:area.add_active(0);break;case 11:area.add_owner_id(-1);break;
      case 12:area.add_link_id(8);break;case 13:area.add_give(false);break;case 14:area.add_unlink(true);break;
    }
    b.Finish(area.Finish());
    CHECK(wire::validateAreaOperation(wire::ManagementAction::AreaUpdate,*flatbuffers::GetRoot<wire::AreaRequest>(b.GetBufferPointer())).value_or("")==
        "Legacy area fields cannot be combined with an operation");
  }
}

TEST_CASE("area required selectors distinguish absent sentinels from meaningful zero") {
  for(int field=0;field<6;++field)for(bool absent:{false,true}) {
    CAPTURE(field);CAPTURE(absent);wm::ManagementRequest request;request.action=wm::ManagementAction::AreaUpdate;
    auto& a=request.area;a.id=7;a.expectedRevision=1;a.kind=wm::AreaKind::Zone;
    const char* message="";
    if(field<2) {
      a.operation=wm::AreaOperation::AssignUnits;a.unitId=0;a.assign=0;
      if(absent){if(field==0)a.unitId=-1;else a.assign=-1;message="invalid area unit assignment";}
    } else if(field<4) {
      a.operation=wm::AreaOperation::SquadUse;a.squadId=0;a.squadUse=0;
      if(absent){if(field==2)a.squadId=-1;else a.squadUse=-1;message="invalid area squad use";}
    } else if(field==4) {
      a.operation=wm::AreaOperation::LocationCreate;a.locationKind=4;a.profession=absent?-1:0;
      if(absent)message="invalid area location creation";
    } else {
      a.operation=wm::AreaOperation::LocationCreate;a.locationKind=2;a.deityKind=2;a.deityId=absent?-1:0;
      if(absent)message="invalid area location creation";
    }
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    CHECK(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer())).value_or("")==message);
  }
  for(int deityKind:{-1,0,1,2,3,4}) {
    wm::ManagementRequest request;request.action=wm::ManagementAction::AreaUpdate;
    auto& a=request.area;a.id=7;a.expectedRevision=1;a.kind=wm::AreaKind::Zone;
    a.operation=wm::AreaOperation::LocationCreate;a.locationKind=2;a.deityKind=int8_t(deityKind);a.deityId=deityKind>=2?0:-1;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    CHECK(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer())).value_or("")==
        (deityKind>=1 && deityKind<=3?"":"invalid area location creation"));
  }
}


TEST_CASE("area validation stages reject malformed selectors fields identities and sizes") {
  const char* errors[]{"Unsupported area operation","Area operation is not valid for this action",
    "Workshop kind is only valid for workshop links","Area kind is not valid for this operation",
    "Legacy area fields cannot be combined with an operation","Field organic does not belong to this operation",
    "area id required","area name too long","invalid area revision"};
  for(int stage=0;stage<9;++stage) {
    CAPTURE(stage);flatbuffers::FlatBufferBuilder b;
    const auto name=b.CreateString(stage==7?std::string(513,'x'):"");
    wire::AreaRequestBuilder area(b);area.add_operation(stage==0?wire::AreaOperation(int(wire::AreaOperation::MAX)+1):stage==3?wire::AreaOperation::Preset:wire::AreaOperation::Rename);
    area.add_id(stage==6?-1:7);area.add_expected_revision(stage==8?uint64_t(INT64_MAX)+1:1);area.add_name(name);
    if(stage==2)area.add_kind(wire::AreaKind::Workshop);
    if(stage==3){area.add_kind(wire::AreaKind::Zone);area.add_preset(1);}
    if(stage==4)area.add_width(2);
    if(stage==5)area.add_organic(0);
    b.Finish(area.Finish());
    CHECK(wire::validateAreaOperation(stage==1?wire::ManagementAction::AreaInspect:wire::ManagementAction::AreaUpdate,
        *flatbuffers::GetRoot<wire::AreaRequest>(b.GetBufferPointer())).value_or("")==errors[stage]);
  }
}

TEST_CASE("Location staff transport preserves duplicates and unresolved holders and rejects bad identities") {
  for(int mode=0;mode<8;++mode) {
    flatbuffers::FlatBufferBuilder b;
    const auto names=wire::CreateLocationStaffNames(b,b.CreateString(""),b.CreateString("Fixture holder"),1,INT32_MAX);
    const auto row=wire::CreateLocationStaffRow(b,mode==1?2:0,mode==2?-1:17,mode==3?2:7,-2,INT32_MAX,mode==4?1:0,651,INT32_MAX,-1,-1,-1,mode==0?names:0);
    const auto staff=wire::CreateLocationStaffSnapshot(b,b.CreateVector(std::vector<flatbuffers::Offset<wire::LocationStaffRow>>{row,row}),
        b.CreateVector(std::vector<int32_t>{8,mode==5?8:mode==6?1:9}));
    std::vector<flatbuffers::Offset<wire::LocationSupplyQuantity>> supplies;
    for(uint8_t i=0;i<10;++i)supplies.push_back(wire::CreateLocationSupplyQuantity(b,i,0,0));
    const auto name=b.CreateString("Fixture");const auto quantities=b.CreateVector(supplies);
    wire::LocationDetailsBuilder detail(b);detail.add_site_id(651);detail.add_id(0);detail.add_kind(5);detail.add_name(name);
    detail.add_revision(1);detail.add_access(2);detail.add_tier(0);detail.add_supplies(quantities);
    if(mode!=7)detail.add_staff(staff);
    const auto d=detail.Finish();
    wire::AreaStateBuilder area(b);area.add_operation(wire::AreaOperation::LocationDetails);area.add_location_details(d);
    const auto a=area.Finish();b.Finish(a);
    const auto* encoded=flatbuffers::GetRoot<wire::AreaState>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(bool(wire::validateLocationDetails(*encoded->location_details()))==(mode>=1 && mode<=6));
    if(mode==0 || mode>=7) {
      const auto decoded=codec::decodeArea(encoded);REQUIRE(decoded.locationDetails);
      if(mode==7)CHECK_FALSE(decoded.locationDetails->staff);
      else {
        REQUIRE(decoded.locationDetails->staff);const auto& v=*decoded.locationDetails->staff;
        REQUIRE(v.rows.size()==2);
        if(mode==0) { REQUIRE(v.rows[0].names);CHECK(v.rows[0].names->holderName=="Fixture holder");CHECK(v.rows[0].names->positionName.empty());CHECK(v.rows[0].names->holderKind==1);CHECK(v.rows[0].names->holderId==INT32_MAX); }
        CHECK(v.rows[0].occupationId==17);CHECK(v.rows[1].occupationId==17);
        CHECK(v.rows[0].histfigId==-2);CHECK(v.rows[0].unitId==INT32_MAX);CHECK(v.rows[0].groupId==INT32_MAX);
        CHECK(v.missingRoles==std::vector<int32_t>{8,9});
      }
    }
  }
}

TEST_CASE("Location entry requires a mutation action, exact receipt and owned identities") {
  wm::ManagementRequest base;base.action=wm::ManagementAction::AreaUpdate;
  base.area.kind=wm::AreaKind::Zone;base.area.operation=wm::AreaOperation::LocationOpen;
  base.area.locationSiteId=651;base.area.locationId=0;base.area.expectedRevision=17;
  for(int mode=0;mode<8;++mode) {
    auto r=base;
    if(mode==1)r.action=wm::ManagementAction::AreaInspect;
    if(mode==2)r.area.expectedRevision=0;
    if(mode==3)r.area.locationSiteId=-1;
    if(mode==4)r.area.locationId=-1;
    if(mode==5)r.area.id=23;
    if(mode==6)r.area.query="foreign";
    if(mode==7)r.area.cursor=1;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    CAPTURE(mode);CHECK(bool(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer())))==(mode!=0));
  }
}
TEST_CASE("Stockpile target query owns coordinates direction and source receipt") {
  wm::ManagementRequest base;base.action=wm::ManagementAction::AreaInspect;
  base.area.operation=wm::AreaOperation::LinkTarget;base.area.id=7;
  base.area.expectedRevision=9007199254740993ull;base.area.x=12;base.area.y=34;base.area.z=56;base.area.give=false;
  for(int mode=0;mode<9;++mode) {
    auto r=base;
    if(mode==1)r.action=wm::ManagementAction::AreaUpdate;
    if(mode==2)r.area.expectedRevision=0;
    if(mode==3)r.area.kind=wm::AreaKind::Zone;
    if(mode==4)r.area.x=-1;
    if(mode==5)r.area.linkId=8;
    if(mode==6)r.area.unlink=true;
    if(mode==7)r.area.cursor=1;
    if(mode==8)r.area.query="foreign";
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* request=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(bool(wire::validateConstructionRequest(*request))==(mode!=0));
    if(mode==0) {
      REQUIRE(request->area()->origin());CHECK(request->area()->origin()->y()==34);
      CHECK_FALSE(request->area()->give());CHECK(request->area()->expected_revision()==9007199254740993ull);
    }
  }
}
TEST_CASE("Location access requests own an exact receipt and native mode") {
  wm::ManagementRequest base;base.action=wm::ManagementAction::AreaUpdate;
  base.area.kind=wm::AreaKind::Zone;base.area.operation=wm::AreaOperation::LocationAccess;
  base.area.locationSiteId=651;base.area.locationId=0;base.area.expectedRevision=9007199254740993ULL;
  for(int mode=0;mode<17;++mode) {
    auto r=base;r.area.value=mode<4?mode:0;
    if(mode==4)r.action=wm::ManagementAction::AreaInspect;
    if(mode==5)r.area.expectedRevision=0;
    if(mode==6)r.area.expectedRevision=uint64_t(INT64_MAX)+1;
    if(mode==7)r.area.value=4;
    if(mode==8)r.area.locationSiteId=-1;
    if(mode==9)r.area.locationId=-1;
    if(mode==10)r.area.id=23;
    if(mode==11)r.area.query="foreign";
    if(mode==12)r.area.cursor=1;
    if(mode==13)r.area.kind=wm::AreaKind::Stockpile;
    if(mode==14)r.area.scope=1;
    if(mode==15)r.area.expectedListRevision=1;
    if(mode==16)r.area.locationKind=2;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* encoded=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(bool(wire::validateConstructionRequest(*encoded))==(mode>=4));
    if(mode<4){CHECK(encoded->area()->value()==mode);CHECK(encoded->area()->expected_revision()==9007199254740993ULL);}
  }
}
TEST_CASE("Location edit outcomes require matching action operation status and snapshot") {
  for(auto operation:{wire::AreaOperation::LocationAccess,wire::AreaOperation::LocationStaffEdit,wire::AreaOperation::LocationQuantity})
  for(int mode=0;mode<11;++mode) {
    flatbuffers::FlatBufferBuilder b;
    std::vector<flatbuffers::Offset<wire::LocationSupplyQuantity>> supplies;
    for(uint8_t i=0;i<10;++i)supplies.push_back(wire::CreateLocationSupplyQuantity(b,i,0,0));
    const auto details=wire::CreateLocationDetails(b,651,0,2,b.CreateString("Synthetic temple"),17,2,false,false,false,-1,0,0,0,false,b.CreateVector(supplies));
    wire::AreaStateBuilder area(b);
    area.add_operation(mode==7?wire::AreaOperation::LocationDetails:operation);
    const auto outcome=mode<=4?mode:1;
    area.add_location_edit_outcome(static_cast<wire::LocationEditOutcome>(mode==10?5:outcome));
    if(mode==1 || mode>=5)area.add_location_details(details);
    if(mode==8)area.add_location_entry_outcome(wire::LocationEntryOutcome::Completed);
    auto a=area.Finish();wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_world_epoch(2);
    state.add_action(mode==6?wire::ManagementAction::AreaInspect:wire::ManagementAction::AreaUpdate);
    state.add_status(mode==1 || (mode>=5 && mode!=9)?wire::ManagementStatus::Ok:wire::ManagementStatus::Rejected);state.add_area(a);
    b.Finish(state.Finish());const auto* root=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(bool(wire::validateManagementState(*root))==(mode==0 || mode>=6));
    if(mode>=1 && mode<=5)CHECK(int(codec::decodeArea(root->area()).locationEditOutcome)==outcome);
  }
}
TEST_CASE("Location entry failure outcomes survive decoding without claiming success") {
  for(int outcome=0;outcome<=5;++outcome) {
    flatbuffers::FlatBufferBuilder b;
    wire::AreaStateBuilder area(b);area.add_operation(wire::AreaOperation::LocationOpen);
    area.add_location_entry_outcome(static_cast<wire::LocationEntryOutcome>(outcome));
    auto a=area.Finish();wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_world_epoch(2);
    state.add_action(wire::ManagementAction::AreaUpdate);state.add_status(wire::ManagementStatus::Rejected);state.add_area(a);
    b.Finish(state.Finish());const auto* root=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CAPTURE(outcome);CHECK(bool(wire::validateManagementState(*root))==(outcome<2 || outcome>4));
    if(outcome>=2 && outcome<=4)CHECK(int(codec::decodeArea(root->area()).locationEntryOutcome)==outcome);
  }
}

TEST_CASE("Details affiliation validates ownership and preserves legacy unknown") {
  for(int mode=0;mode<19;++mode) {
    flatbuffers::FlatBufferBuilder b;
    uint8_t kind=mode==1?1:mode==2?2:mode==3?3:4;
    int32_t id=mode==1 || mode==4?-1:383,count=mode==1 || mode==4?0:53,workers=mode>=4?12:-1;
    std::string name=mode==1 || mode==4?"":"Synthetic affiliation";
    if(mode==7)count=-1;
    if(mode==8)workers=-1;
    if(mode==9)kind=0;
    if(mode==10)name=std::string(513,'x');
    if(mode==11)id=-2;
    if(mode==12){kind=1;id=-1;count=1;workers=-1;name="";}
    if(mode==13){kind=1;id=-1;count=0;workers=0;name="";}
    if(mode==14){id=-1;name="Unexpected absent guild name";count=0;}
    if(mode==15){id=-1;name="";count=1;}
    if(mode==16){kind=2;workers=-1;id=-1;}
    if(mode==17){kind=3;workers=0;}
    const auto text=b.CreateString(name);
    const auto affiliation=wire::CreateLocationAffiliation(b,kind,id,mode==18?0:text,count,workers);
    std::vector<flatbuffers::Offset<wire::LocationSupplyQuantity>> quantities;
    for(uint8_t i=0;i<10;++i)quantities.push_back(wire::CreateLocationSupplyQuantity(b,i,0,0));
    const auto supplies=b.CreateVector(quantities);const auto title=b.CreateString("Synthetic location");
    wire::LocationDetailsBuilder builder(b);
    builder.add_site_id(651);builder.add_id(0);builder.add_kind(mode==6?5:kind==4?4:2);
    builder.add_name(title);builder.add_revision(1);builder.add_tier(0);builder.add_access(2);builder.add_supplies(supplies);
    if(mode!=0)builder.add_affiliation(affiliation);
    const auto details=builder.Finish();wire::AreaStateBuilder area(b);area.add_location_details(details);
    b.Finish(area.Finish());const auto* encoded=flatbuffers::GetRoot<wire::AreaState>(b.GetBufferPointer());
    CAPTURE(mode);CHECK(bool(wire::validateLocationDetails(*encoded->location_details()))==(mode>=6));
    if(mode<6) {
      const auto model=codec::decodeArea(encoded);REQUIRE(model.locationDetails);
      if(mode==0)CHECK_FALSE(model.locationDetails->affiliation);
      else {REQUIRE(model.locationDetails->affiliation);const auto& actual=*model.locationDetails->affiliation;
        CHECK(actual.kind==kind);CHECK(actual.id==id);CHECK(actual.name==name);CHECK(actual.count==count);CHECK(actual.workers==workers);}
    }
  }
}

TEST_CASE("Connected Track accepts a group per tile within command capacity") {
  for(int count:{17,16384}) {
    wm::ManagementRequest r;r.action=wm::ManagementAction::Place;r.definition="Construction:Track";
    r.x=1;r.y=1;r.z=1;r.connectedTrackDestination=wm::TilePos{17,1,1};
    for(int i=0;i<count;++i)r.selections.push_back({0,0,-1,0,i,1,42,std::vector<int32_t>{i}});
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    CHECK(b.GetSize()<wire::kManagementCommandCapacity);
    CHECK_FALSE(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer())));
  }
}

TEST_CASE("Reports tab requests preserve selectors and reject ambiguous cursors") {
  for(int mode=0;mode<7;++mode) {
    wm::ManagementRequest q;q.action=wm::ManagementAction::ReportList;
    q.report.view=wm::ReportView::Tab;q.report.tab=wm::ReportTab::World;q.report.afterId=0;q.report.expectedListRevision=17;
    if(mode==1)q.report.beforeId=10;
    if(mode==2)q.report.fromEnd=true;
    if(mode==3)q.report.tab=wm::ReportTab::Combat;
    if(mode==4)q.report.view=wm::ReportView::UnitLog;
    if(mode==5)q.action=wm::ManagementAction::ReportInspect;
    if(mode==6)q.report.query="fixture";
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
    const auto* request=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(wire::validateConstructionRequest(*request).has_value()==(mode!=0));
    CHECK(request->report()->after_id()==0);CHECK(request->report()->view()==wire::ReportView(q.report.view));
  }
}
TEST_CASE("Reports tab replies retain native row metadata and enforce page shape") {
  for(int mode=0;mode<9;++mode) {
    flatbuffers::FlatBufferBuilder b;std::vector<flatbuffers::Offset<wire::ReportInfo>> rows;
    for(int i=0;i<(mode==1?65:64);++i) {
      rows.push_back(wire::CreateReportInfo(b,i,b.CreateString("MIGRANT_ARRIVAL"),b.CreateString("Fixture"),106,0,0,false,true,
        -1,mode==5?-1:50,mode==5?-1:165,-1,-1,-1,mode!=5,false,wire::ReportTab::General,mode==4?16:3,true,
        wire::ReportZoom::Unit,wire::ReportZoom::None,true,false,mode==6?-2:17));
    }
    std::vector<uint32_t> counts(mode==2?24:25,0);counts[0]=counts[1]=uint32_t(rows.size());
    auto report=wire::CreateReportState(b,b.CreateVector(rows),-1,false,{},wire::ReportView::Tab,
      mode==3?wire::ReportTab(26):wire::ReportTab::General,0,false,b.CreateVector(counts),uint32_t(rows.size()),mode==7?-2:-1,0,true,-1,-1,0,0,mode==8?0:17);
    wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_world_epoch(7);
    root.add_action(wire::ManagementAction::ReportList);root.add_status(wire::ManagementStatus::Ok);root.add_report(report);b.Finish(root.Finish());
    const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(wire::validateManagementState(*state).has_value()==(mode!=0));
    if(mode==0) {
      const auto decoded=codec::decodeReport(state->report());
      CHECK(decoded.view==wm::ReportView::Tab);CHECK(decoded.tab==wm::ReportTab::General);CHECK(decoded.total==64);
      REQUIRE(decoded.reports.size()==64);const auto& row=decoded.reports[0];
      CHECK(row.x==-1);CHECK(row.positionVisible);CHECK(row.positionHidden);CHECK(row.color==3);CHECK(row.bright);
      CHECK(row.zoomType==wm::ReportZoom::Unit);CHECK(row.zoomType2==wm::ReportZoom::None);CHECK(row.speakerId==17);
    }
  }
}

TEST_CASE("Report unit requests preserve exact revision and reject foreign selectors") {
 for(int mode=0;mode<8;++mode) {
  wm::ManagementRequest q;q.action=wm::ManagementAction::ReportList;q.report.view=wm::ReportView::UnitList;
  q.report.unitCategory=1;q.report.cursor=64;q.report.expectedListRevision=INT64_MAX;
  if(mode==1)q.report.unitCategory=-1;
  if(mode==2)q.report.afterId=0;
  if(mode==3)q.report.tab=wm::ReportTab::Combat;
  if(mode==4)q.report.view=wm::ReportView::Entries;
  if(mode>=5){q.report.view=wm::ReportView::UnitLog;q.report.unitId=17;q.report.cursor=0;q.report.expectedListRevision=0;}
  if(mode==6)q.report.unitId=-1;
  if(mode==7)q.report.cursor=1;
  flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
  const auto* r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
  CHECK(bool(wire::validateConstructionRequest(*r))==(mode!=0 && mode!=5));
  CHECK(r->report()->expected_list_revision()==q.report.expectedListRevision);
 }
}
TEST_CASE("Report unit rows decode names counts and signed-safe revision") {
 for(int mode=0;mode<5;++mode) {
  flatbuffers::FlatBufferBuilder b;std::vector<flatbuffers::Offset<wire::ReportUnitInfo>> units;
  units.push_back(wire::CreateReportUnitInfo(b,17,mode==1?3:1,b.CreateString("Fixture profession"),b.CreateString(mode==2?std::string(513,'x'):"Fixture name"),true,999,b.CreateString("")));
  const auto encodedUnits=b.CreateVector(units);wire::ReportStateBuilder report(b);report.add_view(wire::ReportView::UnitList);report.add_unit_category(1);
  report.add_units(encodedUnits);report.add_total(1);report.add_list_revision(mode==3?0:INT64_MAX);report.add_next_cursor(mode==4?2:0);
  const auto r=report.Finish();wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_world_epoch(1);state.add_action(wire::ManagementAction::ReportList);state.add_report(r);b.Finish(state.Finish());
  const auto* root=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
  CHECK(bool(wire::validateManagementState(*root))==(mode!=0));
  if(mode==0){const auto decoded=codec::decodeReport(root->report());REQUIRE(decoded.units.size()==1);CHECK(decoded.units[0].unitId==17);CHECK(decoded.units[0].dead);CHECK(decoded.units[0].logCount==999);CHECK(decoded.listRevision==INT64_MAX);}
 }
}

TEST_CASE("Entries preserves duplicate references and rejects foreign fields") {
 for(int mode=0;mode<6;++mode) {
  wm::ManagementRequest q;q.action=wm::ManagementAction::ReportInspect;q.report.view=wm::ReportView::Entries;
  q.report.ids={41,0,41};q.report.units={{17,1},{17,1}};
  if(mode==1)q.report.ids[0]=-1;
  if(mode==2)q.report.units[0].category=3;
  if(mode==3)q.report.ids.resize(65,0);
  if(mode==4)q.report.unitId=17;
  if(mode==5)q.action=wm::ManagementAction::ReportList;
  flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
  const auto* r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
  CHECK(bool(wire::validateConstructionRequest(*r))==(mode!=0));
  if(mode==0){CHECK(r->report()->ids()->Get(2)==41);CHECK(r->report()->units()->size()==2);}
 }
}
TEST_CASE("Entries replies allow native repeated rows and retain missing IDs") {
 for(int mode=0;mode<3;++mode) {
  flatbuffers::FlatBufferBuilder b;
  auto row=wire::CreateReportInfo(b,41,b.CreateString("Fixture"),b.CreateString("Fixture"),106,1);
  auto unit=wire::CreateReportUnitInfo(b,17,1,b.CreateString("Fixture"),b.CreateString("Name"),false,2,b.CreateString(""));
  auto rows=b.CreateVector(std::vector<flatbuffers::Offset<wire::ReportInfo>>{row,row});
  auto units=b.CreateVector(std::vector<flatbuffers::Offset<wire::ReportUnitInfo>>{unit,unit});
  auto missing=b.CreateVector(std::vector<int32_t>{mode==2?-1:999,999});
  wire::ReportStateBuilder report(b);report.add_view(mode==1?wire::ReportView::Flat:wire::ReportView::Entries);report.add_reports(rows);report.add_units(units);report.add_missing_ids(missing);
  auto value=report.Finish();wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_world_epoch(1);state.add_action(wire::ManagementAction::ReportInspect);state.add_report(value);b.Finish(state.Finish());
  const auto* root=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
  CHECK(bool(wire::validateManagementState(*root))==(mode!=0));
  if(mode==0){auto decoded=codec::decodeReport(root->report());CHECK(decoded.reports.size()==2);CHECK(decoded.units.size()==2);CHECK(decoded.missingIds==std::vector<int32_t>{999,999});}
 }
}

TEST_CASE("Full report text requests require snapshot cursors and reject foreign selectors") {
 for(int mode=0;mode<12;++mode) {
  wm::ManagementRequest q;q.action=wm::ManagementAction::ReportInspect;q.report.view=wm::ReportView::Text;q.report.id=7;
  q.report.cursor=16383;q.report.expectedListRevision=INT64_MAX;
  if(mode==1)q.report.expectedListRevision=0;
  if(mode==2)q.report.cursor=33554433;
  if(mode==3)q.report.unitId=7;
  if(mode==4)q.report.tab=wm::ReportTab::Combat;
  if(mode==5)q.report.ids={7};
  if(mode==6)q.action=wm::ManagementAction::ReportList;
  if(mode==7)q.report.id=-1;
  if(mode==8)q.report.announcementsOnly=false;
  if(mode==9){q.report.cursor=0;q.report.expectedListRevision=0;}
  if(mode>=10)q.report.tab=wm::ReportTab::All;
  if(mode==11)q.report.expectedListRevision=0;
  flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
  const auto* r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
  CHECK(bool(wire::validateConstructionRequest(*r))==(mode!=0 && mode!=9 && mode!=10));
 }
}
TEST_CASE("Full report text replies enforce byte accounting and completeness") {
 for(int mode=0;mode<9;++mode) {
  flatbuffers::FlatBufferBuilder b;
  auto text=b.CreateString("tail");auto category=b.CreateString("Fixture");
  wire::ReportInfoBuilder row(b);row.add_id(7);row.add_text(text);row.add_category(category);row.add_text_complete(mode==4);
  auto value=row.Finish();auto rows=b.CreateVector(std::vector<flatbuffers::Offset<wire::ReportInfo>>(mode==5?2:1,value));
  wire::ReportStateBuilder report(b);report.add_view(wire::ReportView::Text);report.add_reports(rows);
  report.add_cursor(mode==1?101:96);report.add_total(mode==2?33554433:100);
  report.add_list_revision(mode==3?0:INT64_MAX);report.add_next_cursor(mode==6?100:0);
  if(mode==7)report.add_unit_id(7);
  if(mode==8)report.add_tab(wire::ReportTab::Combat);
  auto r=report.Finish();wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_world_epoch(1);state.add_action(wire::ManagementAction::ReportInspect);state.add_report(r);b.Finish(state.Finish());
  const auto* root=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
  CHECK(bool(wire::validateManagementState(*root))==(mode!=0));
  if(mode==0){const auto decoded=codec::decodeReport(root->report());CHECK(decoded.view==wm::ReportView::Text);CHECK(decoded.cursor==96);CHECK(decoded.total==100);CHECK(decoded.listRevision==INT64_MAX);}
 }
}

TEST_CASE("Retained unit-log refresh and text selectors are explicit") {
 for(int mode=0;mode<10;++mode) {
  wm::ManagementRequest q;q.action=wm::ManagementAction::ReportList;q.report.view=wm::ReportView::UnitLog;
  q.report.unitId=17;q.report.unitCategory=1;q.report.expectedListRevision=71;q.report.afterId=0;q.report.refresh=true;
  if(mode==1)q.report.expectedListRevision=0;
  if(mode==2){q.report.afterId=-1;q.report.fromEnd=true;}
  if(mode==3){q.report.afterId=-1;q.report.beforeId=4;}
  if(mode==4)q.report.view=wm::ReportView::UnitList;
  if(mode>=5){q.action=wm::ManagementAction::ReportInspect;q.report.view=wm::ReportView::Text;q.report.id=5;q.report.afterId=-1;q.report.refresh=false;}
  if(mode==6)q.report.expectedListRevision=0;
  if(mode==7)q.report.tab=wm::ReportTab::All;
  if(mode==8)q.report.unitCategory=-1;
  if(mode==9)q.report.refresh=true;
  flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
  const auto* r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
  CHECK(bool(wire::validateConstructionRequest(*r))==(mode!=0 && mode!=5));
  CHECK(r->report()->refresh()==q.report.refresh);
 }
}

TEST_CASE("Alert Group requests separate source selection from retained Text owners") {
 for(int mode=0;mode<14;++mode) {
  wm::ManagementRequest q;q.action=wm::ManagementAction::ReportList;q.report.view=wm::ReportView::Group;
  q.report.notificationCategory=20;
  if(mode==1){q.report.notificationCategory=-1;q.report.alertButton=true;}
  if(mode==2)q.report.notificationCategory=-1;
  if(mode==3)q.report.alertButton=true;
  if(mode==4)q.report.cursor=1;
  if(mode==5){q.report.cursor=64;q.report.expectedListRevision=17;}
  if(mode>=6){q.action=wm::ManagementAction::ReportInspect;q.report.view=wm::ReportView::Text;q.report.id=7;q.report.expectedListRevision=17;}
  if(mode==7)q.report.expectedListRevision=0;
  if(mode==8)q.report.tab=wm::ReportTab::All;
  if(mode==9){q.report.unitId=17;q.report.unitCategory=1;}
  if(mode==10)q.report.notificationCategory=37;
  if(mode==11)q.report.refresh=true;
  if(mode==12){q.report.view=wm::ReportView::Flat;q.report.expectedListRevision=0;}
  if(mode==13)q.report.ids={7};
  flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,q,1,2,3);
  const auto* r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
  CHECK(bool(wire::validateConstructionRequest(*r))==(mode!=0 && mode!=1 && mode!=5 && mode!=6));
  CHECK(r->report()->notification_category()==q.report.notificationCategory);
  CHECK(r->report()->alert_button()==q.report.alertButton);
 }
}
TEST_CASE("Alert Group pages preserve duplicates and enforce exact cursor progress") {
 for(int mode=0;mode<9;++mode) {
  flatbuffers::FlatBufferBuilder b;
  auto row=wire::CreateReportInfo(b,41,b.CreateString("Fixture"),b.CreateString("Fixture"),106,1);
  auto unit=wire::CreateReportUnitInfo(b,17,1,b.CreateString("Fixture"),b.CreateString("Name"),false,2,b.CreateString(""));
  auto rows=b.CreateVector(std::vector<flatbuffers::Offset<wire::ReportInfo>>{row,row});
  auto units=b.CreateVector(std::vector<flatbuffers::Offset<wire::ReportUnitInfo>>{unit,unit});
  wire::ReportStateBuilder report(b);report.add_view(wire::ReportView::Group);report.add_notification_category(mode==1?-1:20);
  report.add_reports(rows);report.add_units(units);report.add_total(mode==2?3:300);report.add_cursor(0);
  report.add_next_cursor(mode==3?5:4);report.add_list_revision(mode==4?0:17);
  if(mode==5)report.add_alert_button(true);
  if(mode==6)report.add_tab(wire::ReportTab::All);
  if(mode==7)report.add_unit_id(17);
  if(mode==8)report.add_total(65537);
  auto value=report.Finish();wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_world_epoch(1);state.add_action(wire::ManagementAction::ReportList);state.add_report(value);b.Finish(state.Finish());
  const auto* root=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
  CHECK(bool(wire::validateManagementState(*root))==(mode!=0));
  if(mode==0){auto decoded=codec::decodeReport(root->report());CHECK(decoded.notificationCategory==20);CHECK_FALSE(decoded.alertButton);CHECK(decoded.reports.size()==2);CHECK(decoded.units.size()==2);}
 }
}

TEST_CASE("construction bedding preserves owned values and rejects invalid contexts") {
  for(int mode=0;mode<5;++mode) {
    flatbuffers::FlatBufferBuilder b;
    auto bedding=wire::CreateBeddingFactsDirect(b,mode==1?2:1,mode==2?3:2,"CLEAR",mode==4?std::string(129,'x').c_str():"BLUE");
    auto appearance=wire::CreateConstructionItemAppearance(b,b.CreateString("INORGANIC:GRANITE"),{}, {},1,0,bedding);
    auto candidate=wire::CreateConstructionMaterialCandidate(b,10,b.CreateString("granite bed"),2,appearance);
    auto row=wire::CreateConstructionMaterial(b,mode==3?0:8,-1,0,3,b.CreateString("granite beds"),{},1,b.CreateVector(std::vector{candidate}));
    auto rows=b.CreateVector(std::vector{row});
    wire::ConstructionStateBuilder domain(b);domain.add_materials(rows);auto construction=domain.Finish();
    wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_construction(construction);
    root.add_action(wire::ManagementAction::ConstructionMaterials);root.add_status(wire::ManagementStatus::Ok);
    b.Finish(root.Finish());auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(wire::validateManagementState(*state).has_value()==(mode!=0));
    if(mode==0) {
      wm::ManagementState decoded;codec::decodeConstruction(state,decoded);b.Clear();
      const auto& facts=decoded.construction.materials[0].candidates->at(0).appearance->bedding;
      CHECK(facts.sheet==1);CHECK(facts.pillow==2);CHECK(facts.baseColor=="CLEAR");CHECK(facts.sheetColor=="BLUE");
    }
  }
}

TEST_CASE("construction instrument facts preserve absence and reject malformed pairs") {
 for(int family=-2;family<=4;++family)for(int placed=-2;placed<=2;++placed)for(int type:{8,13}) {
  flatbuffers::FlatBufferBuilder b;
  auto appearance=wire::CreateConstructionItemAppearance(b,b.CreateString("INORGANIC:IRON"),{}, {},1,0,{},int8_t(family),int8_t(placed));
  auto candidate=wire::CreateConstructionMaterialCandidate(b,10,b.CreateString("fixture instrument"),2,appearance);
  auto row=wire::CreateConstructionMaterial(b,type,-1,0,3,b.CreateString("fixture instruments"),{},1,b.CreateVector(std::vector{candidate}));
  auto rows=b.CreateVector(std::vector{row});
  wire::ConstructionStateBuilder domain(b);domain.add_materials(rows);auto construction=domain.Finish();
  wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_construction(construction);
  root.add_action(wire::ManagementAction::ConstructionMaterials);root.add_status(wire::ManagementStatus::Ok);
  b.Finish(root.Finish());const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
  const bool valid=(family==-1 && placed==-1) || (type==13 && family>=0 && family<=3 && placed>=0 && placed<=1);
  CHECK(wire::validateManagementState(*state).has_value()==!valid);
  if(valid) {
   wm::ManagementState decoded;codec::decodeConstruction(state,decoded);b.Clear();
   const auto& facts=*decoded.construction.materials[0].candidates->at(0).appearance;
   CHECK(facts.instrumentFamily==family);CHECK(facts.instrumentPlaced==placed);
  }
 }
}

TEST_CASE("construction slab engraving survives owned decoding and rejects wrong contexts") {
 for(int engraving=-3;engraving<=27;++engraving)for(int type:{8,87}) {
  flatbuffers::FlatBufferBuilder b;
  auto appearance=wire::CreateConstructionItemAppearance(b,b.CreateString("INORGANIC:GRANITE"),{}, {},1,0,{},-1,-1,int8_t(engraving));
  auto candidate=wire::CreateConstructionMaterialCandidate(b,10,b.CreateString("fixture slab"),2,appearance);
  auto row=wire::CreateConstructionMaterial(b,type,-1,0,3,b.CreateString("fixture slabs"),{},1,b.CreateVector(std::vector{candidate}));
  auto rows=b.CreateVector(std::vector{row});wire::ConstructionStateBuilder domain(b);domain.add_materials(rows);auto construction=domain.Finish();
  wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_construction(construction);root.add_action(wire::ManagementAction::ConstructionMaterials);root.add_status(wire::ManagementStatus::Ok);
  b.Finish(root.Finish());const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
  const bool valid=engraving==-2 || (type==87 && engraving>=-1 && engraving<=26);
  CHECK(wire::validateManagementState(*state).has_value()==!valid);
  if(valid){wm::ManagementState decoded;codec::decodeConstruction(state,decoded);b.Clear();CHECK(decoded.construction.materials[0].candidates->at(0).appearance->slabEngraving==engraving);}
 }
}

TEST_CASE("construction gem shape survives owned decoding and rejects wrong contexts") {
 for(const std::string shape:{std::string{},std::string("BAGUETTE_CUT_GEM"),std::string(129,'X')})for(int type:{1,8}) {
  flatbuffers::FlatBufferBuilder b;
  auto appearance=wire::CreateConstructionItemAppearance(b,b.CreateString("INORGANIC:GRANITE"),{}, {},1,0,{},-1,-1,-2,b.CreateString(shape));
  auto candidate=wire::CreateConstructionMaterialCandidate(b,10,b.CreateString("fixture slab"),2,appearance);
  auto row=wire::CreateConstructionMaterial(b,type,-1,0,3,b.CreateString("fixture slabs"),{},1,b.CreateVector(std::vector{candidate}));
  auto rows=b.CreateVector(std::vector{row});wire::ConstructionStateBuilder domain(b);domain.add_materials(rows);auto construction=domain.Finish();
  wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_construction(construction);root.add_action(wire::ManagementAction::ConstructionMaterials);root.add_status(wire::ManagementStatus::Ok);
  b.Finish(root.Finish());const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
  const bool valid=shape.empty() || (type==1 && shape.size()<=128);
  CHECK(wire::validateManagementState(*state).has_value()==!valid);
  if(valid){wm::ManagementState decoded;codec::decodeConstruction(state,decoded);b.Clear();CHECK(decoded.construction.materials[0].candidates->at(0).appearance->gemShapeRaw==shape);}
 }
}

TEST_CASE("fallen gathering flag preserves unknown and rejects invalid wire values") {
  for(int value:{-2,-1,0,1,2}) {
    flatbuffers::FlatBufferBuilder b;
    const auto settings=wire::CreateAreaZoneSettings(b,0,0,-1,-1,-1,-1,int8_t(value));
    b.Finish(settings);
    const auto* row=flatbuffers::GetRoot<wire::AreaZoneSettings>(b.GetBufferPointer());
    CHECK(wire::validAreaZoneSettings(row)==(value>=-1 && value<=1));
    CHECK(wire::areaZoneSettingsPresent(row)==(value!=-1));
  }
  flatbuffers::FlatBufferBuilder old;
  old.Finish(wire::CreateAreaZoneSettings(old,0,0,-1,-1,1,0));
  CHECK(flatbuffers::GetRoot<wire::AreaZoneSettings>(old.GetBufferPointer())->gather_fallen()==-1);
}

TEST_CASE("owner candidate appearance is optional scoped bounded and lossless") {
  for(int mode=0;mode<11;++mode) {
    flatbuffers::FlatBufferBuilder b;
    flatbuffers::Offset<wire::SelectionAppearance> icon;
    if(mode!=0) {
      std::vector<std::string> pages(mode==6?257:1,mode==7?std::string(257,'x'):"PAGE");
      std::vector<std::string> palettes(mode==9?256:1,mode==9?std::string(512,'p'):"PALETTE");
      std::vector<wire::AppearanceLayer> layers(mode==8?257:1,wire::AppearanceLayer(mode==2?1:0,2,3,mode==3?0:1,1,mode==4?1:0,4,5,-1,2));
      icon=wire::CreateSelectionAppearance(b,b.CreateVectorOfStrings(pages),b.CreateVectorOfStrings(palettes),b.CreateVectorOfStructs(layers));
    }
    const auto row=wire::CreateAreaCandidateRow(b,998,0,0,-1,0,false,false,-1,0,icon);
    const auto rows=b.CreateVector(std::vector(mode==9?2:1,row));
    wire::AreaStateBuilder area(b);area.add_operation(mode==10?wire::AreaOperation::None:wire::AreaOperation::CandidateList);
    area.add_candidate_kind(mode==5?2:1);area.add_candidates(rows);const auto a=area.Finish();
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_area(a);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(mode>=2));
    if(mode<2) {
      const auto decoded=codec::decodeArea(value->area());REQUIRE(decoded.candidates.size()==1);
      const auto& image=decoded.candidates[0].sheetIcon;CHECK(image.has_value()==(mode==1));
      if(image) {CHECK(image->tilePages==std::vector<std::string>{"PAGE"});CHECK(image->palettes==std::vector<std::string>{"PALETTE"});
        REQUIRE(image->layers.size()==1);CHECK(image->layers[0]==wm::AppearanceLayer{0,2,3,1,1,0,4,5,-1,2});}
    }
  }
}

TEST_CASE("animal selector appearance is restricted to typed units and items") {
  for(auto entity:{wire::AreaCandidateEntity::Unknown,wire::AreaCandidateEntity::Unit,wire::AreaCandidateEntity::Item,wire::AreaCandidateEntity::Squad}) {
    flatbuffers::FlatBufferBuilder b;
    const auto icon=wire::CreateSelectionAppearance(b,b.CreateVectorOfStrings(std::vector<std::string>{"PAGE"}),
      b.CreateVectorOfStrings(std::vector<std::string>{}),b.CreateVectorOfStructs(std::vector<wire::AppearanceLayer>{wire::AppearanceLayer(0,0,0,1,1,65535,-1,-1,0,0)}));
    const auto row=wire::CreateAreaCandidateRow(b,21,0,0,-1,0,false,false,-1,0,icon,entity);
    const auto rows=b.CreateVector(std::vector{row});wire::AreaStateBuilder area(b);area.add_candidates(rows);
    area.add_operation(wire::AreaOperation::CandidateList);area.add_candidate_kind(2);const auto a=area.Finish();
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_area(a);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(entity!=wire::AreaCandidateEntity::Unit && entity!=wire::AreaCandidateEntity::Item));
    if((entity==wire::AreaCandidateEntity::Unit || entity==wire::AreaCandidateEntity::Item))CHECK(codec::decodeArea(value->area()).candidates[0].sheetIcon.has_value());
  }
}

TEST_CASE("selector fact page limits are scoped and bounded") {
  for(int kind:{1,2})for(int mode=0;mode<8;++mode) {
    CAPTURE(mode);
    wm::ManagementRequest request;request.action=wm::ManagementAction::AreaCandidates;
    auto& a=request.area;a.operation=wm::AreaOperation::CandidateList;
    a.kind=wm::AreaKind::Zone;a.id=7;a.candidateKind=kind;
    a.candidateLimit=mode==0?0:mode==1?18:mode==2?128:mode==3?129:18;
    if(mode==4)a.candidateKind=3;
    if(mode==5)a.operation=wm::AreaOperation::None;
    if(mode==6)a.id=-1;
    if(mode==7)a.kind=wm::AreaKind::Stockpile;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    const auto* r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(r->area()->candidate_limit()==a.candidateLimit);
    CHECK(bool(wire::validateConstructionRequest(*r))==(mode>=3));
  }
}

TEST_CASE("selector raw query transport preserves absence empty and partial UTF-8") {
  for(int kind:{1,2})for(int mode=0;mode<10;++mode) {
    CAPTURE(mode);
    wm::ManagementRequest request;request.action=wm::ManagementAction::AreaCandidates;
    auto& a=request.area;a.operation=wm::AreaOperation::CandidateList;
    a.kind=wm::AreaKind::Zone;a.id=7;a.candidateKind=kind;
    if(mode>0)a.queryBytes=std::vector<uint8_t>(mode==1?0:mode==3?33:mode==4?34:1,195);
    if(mode==5)a.candidateKind=3;
    if(mode==6)a.operation=wm::AreaOperation::None;
    if(mode==7)a.id=-1;
    if(mode==8)a.query="mixed";
    if(mode==9)a.kind=wm::AreaKind::Stockpile;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    const auto* r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(bool(wire::validateConstructionRequest(*r))==(mode>=4));
    const auto* bytes=r->area()->query_bytes();CHECK(bool(bytes)==(mode!=0));
    if(bytes)CHECK(std::vector<uint8_t>(bytes->begin(),bytes->end())==*a.queryBytes);
  }
  for(int kind:{1,2})for(int mode=0;mode<9;++mode) {
    CAPTURE(mode);
    flatbuffers::FlatBufferBuilder b;
    auto bytes=mode?b.CreateVector(std::vector<uint8_t>(mode==1?0:mode==3?33:mode==4?34:1,195)):
      flatbuffers::Offset<flatbuffers::Vector<uint8_t>>{};
    const auto query=b.CreateString(mode==8?"mixed":"");
    wire::AreaStateBuilder area(b);area.add_operation(mode==6?wire::AreaOperation::None:wire::AreaOperation::CandidateList);
    area.add_area_id(mode==7?-1:7);area.add_candidate_kind(mode==5?3:kind);area.add_query_bytes(bytes);area.add_query(query);
    const auto result=area.Finish();wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_area(result);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(mode>=4));
    if(mode<4) {
      const auto decoded=codec::decodeArea(value->area());CHECK(decoded.queryBytes.has_value()==(mode!=0));
      if(decoded.queryBytes)CHECK(*decoded.queryBytes==std::vector<uint8_t>(mode==1?0:mode==3?33:1,195));
    }
  }
}

TEST_CASE("animal assignment identities are exclusive and preserve item IDs") {
  for(int mode=0;mode<7;++mode) {
    CAPTURE(mode);
    wm::ManagementRequest request;request.action=wm::ManagementAction::AreaUpdate;
    auto& a=request.area;a.operation=wm::AreaOperation::AssignUnits;
    a.kind=wm::AreaKind::Zone;a.id=7;a.expectedRevision=5;a.assign=1;
    a.unitId=mode==0 || mode==2?42:-1;
    a.itemId=mode==1 || mode==2 || mode==5?42:mode==4?-2:mode==6?INT32_MAX:-1;
    if(mode==5)a.operation=wm::AreaOperation::Rename;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    const auto* r=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(r->area()->item_id()==a.itemId);CHECK(r->area()->unit_id()==a.unitId);
    CHECK(bool(wire::validateConstructionRequest(*r))==(mode>=2 && mode<=5));
  }
}
TEST_CASE("area candidate typed identities preserve collisions and unknown legacy facts") {
  for(int mode=0;mode<5;++mode) {
    CAPTURE(mode);
    flatbuffers::FlatBufferBuilder b;
    const auto first=wire::CreateAreaCandidateRow(b,7,0,0,-1,0,false,false,-1,0,0,wire::AreaCandidateEntity::Unit);
    const auto second=wire::CreateAreaCandidateRow(b,7,0,0,-1,0,false,false,-1,0,0,
      mode==0?wire::AreaCandidateEntity::Item:mode==1?wire::AreaCandidateEntity::Unknown:
      mode==2?wire::AreaCandidateEntity::Squad:mode==3?wire::AreaCandidateEntity(255):wire::AreaCandidateEntity::Item);
    auto rows=b.CreateVector(std::vector{first,second});
    wire::AreaStateBuilder area(b);area.add_operation(wire::AreaOperation::CandidateList);
    area.add_candidate_kind(mode==4?1:2);area.add_candidates(rows);auto value=area.Finish();
    wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_area(value);b.Finish(root.Finish());
    const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*state))==(mode>=2));
    if(mode<2) {
      const auto decoded=codec::decodeArea(state->area());
      REQUIRE(decoded.candidates.size()==2);CHECK(decoded.candidates[0].id==decoded.candidates[1].id);
      CHECK(decoded.candidates[0].entity==wm::AreaCandidateEntity::Unit);
      CHECK(decoded.candidates[1].entity==(mode==0?wm::AreaCandidateEntity::Item:wm::AreaCandidateEntity::Unknown));
    }
  }
}

TEST_CASE("animal status transport preserves absence and rejects inconsistent subjects") {
  for(int entity=0;entity<4;++entity)for(int kind=-1;kind<=6;++kind)for(int relation=0;relation<=5;++relation)for(int item:{-1,17}) {
    flatbuffers::FlatBufferBuilder b;
    flatbuffers::Offset<wire::AreaAnimalStatus> status;
    if(kind>=0)status=wire::CreateAreaAnimalStatus(b,uint8_t(kind),uint8_t(relation),item);
    wire::AreaCandidateRowBuilder row(b);row.add_id(21);row.add_entity(wire::AreaCandidateEntity(entity));row.add_animal_status(status);
    const auto rows=b.CreateVector(std::vector{row.Finish()});
    wire::AreaStateBuilder area(b);area.add_candidates(rows);area.add_operation(wire::AreaOperation::CandidateList);area.add_candidate_kind(2);const auto a=area.Finish();
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_area(a);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    const bool expected=kind<0 ? entity!=3 : (entity==1 || entity==2) && kind<=5 && (entity!=2 || kind<=3) && relation<=4 &&
      (kind==4 ? relation>0 && item>=0 : relation==0 && item==-1);
    CHECK((!wire::validateManagementState(*value).has_value())==expected);
    if(expected) {
      const auto decoded=codec::decodeArea(value->area());const auto& decodedStatus=decoded.candidates[0].animalStatus;
      CHECK(decodedStatus.has_value()==(kind>=0));
      if(decodedStatus){CHECK(decodedStatus->kind==kind);CHECK(decodedStatus->containment==relation);CHECK(decodedStatus->itemId==item);}
    }
  }
}

TEST_CASE("animal container facts and occupant recipes retain identity and reject malformed combinations") {
  for(int family=0;family<4;++family)for(int entity=0;entity<4;++entity)for(int id:{-1,9})for(int recipe=0;recipe<3;++recipe) {
    flatbuffers::FlatBufferBuilder b;
    flatbuffers::Offset<wire::SelectionAppearance> appearance;
    if(recipe)appearance=wire::CreateSelectionAppearance(b,b.CreateVectorOfStrings(std::vector<std::string>{"TEST_PAGE"}),
      b.CreateVectorOfStrings(std::vector<std::string>{}),b.CreateVectorOfStructs(std::vector<wire::AppearanceLayer>{wire::AppearanceLayer(recipe==2?1:0,2,3,1,1,65535,0,0,-1,2)}));
    const auto container=wire::CreateAreaAnimalContainer(b,uint8_t(family),b.CreateString("TEST_COLOR"),uint8_t(entity),id,appearance);
    const auto status=wire::CreateAreaAnimalStatus(b,4,2,17);
    wire::AreaCandidateRowBuilder row(b);row.add_id(21);row.add_entity(wire::AreaCandidateEntity::Unit);row.add_animal_status(status);row.add_animal_container(container);
    const auto rows=b.CreateVector(std::vector{row.Finish()});
    wire::AreaStateBuilder area(b);area.add_candidates(rows);area.add_operation(wire::AreaOperation::CandidateList);area.add_candidate_kind(2);const auto a=area.Finish();
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_area(a);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    const bool expected=family<=2 && entity<=2 && recipe!=2 && (entity==0 ? id==-1 && recipe==0 : id>=0);
    CHECK((!wire::validateManagementState(*value).has_value())==expected);
    if(expected) {
      const auto decoded=codec::decodeArea(value->area());const auto& c=decoded.candidates[0].animalContainer;
      REQUIRE(c.has_value());CHECK(c->materialFamily==family);CHECK(c->solidColor=="TEST_COLOR");CHECK(c->occupantEntity==entity);CHECK(c->occupantId==id);
      CHECK(c->occupant.has_value()==(recipe!=0));
      if(c->occupant){CHECK(c->occupant->tilePages==std::vector<std::string>{"TEST_PAGE"});CHECK(c->occupant->layers[0].offsetX==-1);CHECK(c->occupant->layers[0].tileY==3);}
    }
  }
}

TEST_CASE("restraint facts require a container status and exclude cage recipes") {
  for(int mode=0;mode<6;++mode)for(bool rope:{false,true}) {
    flatbuffers::FlatBufferBuilder b;
    const auto restraint=wire::CreateAreaAnimalRestraint(b,rope,b.CreateString(mode==3?std::string(129,'x'):"TEST_COLOR"));
    const auto status=mode==1?flatbuffers::Offset<wire::AreaAnimalStatus>{}:wire::CreateAreaAnimalStatus(b,mode==2?0:4,mode==2?0:1,mode==2?-1:17);
    const auto container=mode==4?wire::CreateAreaAnimalContainer(b):flatbuffers::Offset<wire::AreaAnimalContainer>{};
    wire::AreaCandidateRowBuilder row(b);row.add_id(21);row.add_entity(mode==5?wire::AreaCandidateEntity::Item:wire::AreaCandidateEntity::Unit);
    row.add_animal_status(status);row.add_animal_restraint(restraint);row.add_animal_container(container);
    const auto rows=b.CreateVector(std::vector{row.Finish()});
    wire::AreaStateBuilder area(b);area.add_candidates(rows);area.add_operation(wire::AreaOperation::CandidateList);area.add_candidate_kind(2);const auto a=area.Finish();
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_area(a);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK((!wire::validateManagementState(*value).has_value())==(mode==0));
    if(mode==0){const auto decoded=codec::decodeArea(value->area());REQUIRE(decoded.candidates[0].animalRestraint);CHECK(decoded.candidates[0].animalRestraint->rope==rope);CHECK(decoded.candidates[0].animalRestraint->solidColor=="TEST_COLOR");CHECK_FALSE(decoded.candidates[0].animalContainer);}
  }
}

TEST_CASE("animal item colors retain optionality and reject invalid palettes or identities") {
  for(int mode=0;mode<6;++mode) {
    flatbuffers::FlatBufferBuilder b;
    const auto color=mode==5?flatbuffers::Offset<wire::AreaAnimalItemColor>{}:wire::CreateAreaAnimalItemColor(b,mode==1?8:2,mode==2?8:3,mode==3?2:1);
    wire::AreaCandidateRowBuilder row(b);row.add_id(21);row.add_entity(mode==4?wire::AreaCandidateEntity::Unit:wire::AreaCandidateEntity::Item);row.add_animal_item_color(color);
    const auto rows=b.CreateVector(std::vector{row.Finish()});
    wire::AreaStateBuilder area(b);area.add_candidates(rows);area.add_operation(wire::AreaOperation::CandidateList);area.add_candidate_kind(2);const auto a=area.Finish();
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_area(a);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK((!wire::validateManagementState(*value).has_value())==(mode==0 || mode==5));
    if(mode==0){const auto decoded=codec::decodeArea(value->area());REQUIRE(decoded.candidates[0].animalItemColor);CHECK((*decoded.candidates[0].animalItemColor==std::array<uint8_t,3>{2,3,1}));}
    if(mode==5)CHECK_FALSE(codec::decodeArea(value->area()).candidates[0].animalItemColor);
  }
}

TEST_CASE("squad symbols preserve RGB bytes and reject wrong ownership or indices") {
  for(int mode=0;mode<7;++mode) {
    flatbuffers::FlatBufferBuilder b;
    const auto symbol=mode==6?flatbuffers::Offset<wire::AreaSquadSymbol>{}:wire::CreateAreaSquadSymbol(b,mode==1?23:22,0,127,255,233,61,7);
    wire::AreaCandidateRowBuilder row(b);row.add_id(mode==2?-1:21);row.add_entity(mode==3?wire::AreaCandidateEntity::Unit:wire::AreaCandidateEntity::Squad);row.add_squad_symbol(symbol);
    const auto rows=b.CreateVector(std::vector{row.Finish()});
    wire::AreaStateBuilder area(b);area.add_candidates(rows);area.add_operation(mode==4?wire::AreaOperation::None:wire::AreaOperation::CandidateList);area.add_candidate_kind(mode==5?2:3);const auto a=area.Finish();
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_area(a);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK((!wire::validateManagementState(*value).has_value())==(mode==0 || mode==6));
    if(mode==0){const auto decoded=codec::decodeArea(value->area());REQUIRE(decoded.candidates[0].squadSymbol);CHECK((*decoded.candidates[0].squadSymbol==std::array<uint8_t,7>{22,0,127,255,233,61,7}));}
    if(mode==6)CHECK_FALSE(codec::decodeArea(value->area()).candidates[0].squadSymbol);
  }
}

TEST_CASE("Location quantity edits preserve exact intent and reject malformed payloads") {
  wm::ManagementRequest base;base.action=wm::ManagementAction::AreaUpdate;
  auto& a=base.area;a.kind=wm::AreaKind::Zone;a.operation=wm::AreaOperation::LocationQuantity;
  a.locationSiteId=651;a.locationId=0;a.expectedRevision=9007199254740993LL;a.quantityId=4;
  for(int variant=0;variant<21;++variant) {
    auto r=base;auto& q=r.area;
    if(variant<3){q.quantityMode=wm::LocationQuantityMode(variant);q.quantityValue=variant==0?999:0;}
    if(variant==3)q.quantityId=-1;
    if(variant==4)q.quantityId=11;
    if(variant==5)q.quantityMode=wm::LocationQuantityMode(3);
    if(variant==6)q.quantityValue=-1;
    if(variant==7)q.quantityValue=1000;
    if(variant==8){q.quantityMode=wm::LocationQuantityMode::Increase;q.quantityValue=1;}
    if(variant==9)q.expectedRevision=0;
    if(variant==10)q.expectedRevision=-1;
    if(variant==11)q.locationSiteId=-1;
    if(variant==12)q.locationId=-1;
    if(variant==13)q.id=23;
    if(variant==14)q.expectedListRevision=1;
    if(variant==15)q.kind=wm::AreaKind::Stockpile;
    if(variant==16)r.action=wm::ManagementAction::AreaInspect;
    if(variant==17)q.operation=wm::AreaOperation::LocationAccess;
    if(variant==18){q.operation=wm::AreaOperation::LocationAccess;q.quantityId=-1;q.quantityMode=wm::LocationQuantityMode::Decrease;}
    if(variant==19){q.operation=wm::AreaOperation::LocationAccess;q.quantityId=-1;q.quantityValue=1;}
    if(variant==20)q.value=1;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* encoded=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CAPTURE(variant);CHECK(bool(wire::validateConstructionRequest(*encoded))==(variant>=3));
    if(variant<3){CHECK(encoded->area()->quantity_id()==4);CHECK(int(encoded->area()->quantity_mode())==variant);
      CHECK(encoded->area()->quantity_value()==(variant==0?999:0));CHECK(encoded->area()->expected_revision()==9007199254740993ULL);}
  }
}

TEST_CASE("Recognition requests own target and revision without unrelated edit payloads") {
  for(bool apply:{false,true})for(int variant=0;variant<11;++variant) {
    wm::ManagementRequest r;r.action=apply?wm::ManagementAction::AreaUpdate:wm::ManagementAction::AreaInspect;
    auto& a=r.area;a.kind=wm::AreaKind::Zone;a.locationSiteId=651;a.locationId=0;
    a.operation=apply?wm::AreaOperation::LocationRecognize:wm::AreaOperation::LocationRecognitionRead;
    a.expectedRevision=apply?9007199254740993LL:0;
    if(variant==1)a.expectedRevision=apply?0:17;
    if(variant==2)a.locationSiteId=-1;
    if(variant==3)a.locationId=-1;
    if(variant==4)a.id=4;
    if(variant==5)a.kind=wm::AreaKind::Stockpile;
    if(variant==6)r.action=apply?wm::ManagementAction::AreaInspect:wm::ManagementAction::AreaUpdate;
    if(variant==7)a.nameEdit.emplace();
    if(variant==8)a.quantityId=0;
    if(variant==9)a.expectedListRevision=1;
    if(variant==10)a.expectedRevision=-1;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* q=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CAPTURE(apply);CAPTURE(variant);CHECK(bool(wire::validateConstructionRequest(*q))==(variant!=0));
    if(!variant && apply)CHECK(q->area()->expected_revision()==9007199254740993ULL);
  }
}
TEST_CASE("Recognition replies retain exact revisions and reject mixed or missing outcomes") {
  for(bool apply:{false,true})for(int variant=0;variant<10;++variant) {
    flatbuffers::FlatBufferBuilder b;
    auto receipt=wire::CreateLocationRecognition(b,651,0,383,variant==1?0:9007199254740993ULL,
        variant==2?3:2,1,53,10,25,wire::LocationRecognitionState::RecognizeHighPriest,
        b.CreateVector(std::vector<int32_t>{variant==3?-1:42}));
    wire::AreaStateBuilder a(b);
    a.add_operation(variant==4?wire::AreaOperation::LocationDetails:apply?wire::AreaOperation::LocationRecognize:wire::AreaOperation::LocationRecognitionRead);
    if(variant!=5)a.add_location_recognition(receipt);
    if(apply || variant==6)a.add_location_edit_outcome(variant==6?wire::LocationEditOutcome::Unknown:wire::LocationEditOutcome::Completed);
    if(variant==7)a.add_area_id(2);
    auto area=a.Finish();wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_area(area);
    root.add_action(variant==8?wire::ManagementAction::AreaDelete:apply?wire::ManagementAction::AreaUpdate:wire::ManagementAction::AreaInspect);
    root.add_status(variant==9?wire::ManagementStatus::Rejected:wire::ManagementStatus::Ok);b.Finish(root.Finish());
    const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CAPTURE(apply);CAPTURE(variant);CHECK(bool(wire::validateManagementState(*state))==(variant!=0));
    if(!variant) {
      const auto decoded=codec::decodeArea(state->area());REQUIRE(decoded.locationRecognition);
      CHECK(decoded.locationRecognition->revision==9007199254740993LL);
      CHECK(decoded.locationRecognition->continuingAgreements==std::vector<int32_t>{42});
      CHECK(decoded.locationRecognition->state==wm::LocationRecognitionState::RecognizeHighPriest);
    }
  }
  for(auto outcome:{wire::LocationEditOutcome::Rejected,wire::LocationEditOutcome::Stale,wire::LocationEditOutcome::Unknown}) {
    flatbuffers::FlatBufferBuilder b;wire::AreaStateBuilder a(b);a.add_operation(wire::AreaOperation::LocationRecognize);a.add_location_edit_outcome(outcome);
    auto area=a.Finish();wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_area(area);
    root.add_action(wire::ManagementAction::AreaUpdate);root.add_status(wire::ManagementStatus::Rejected);b.Finish(root.Finish());
    CHECK_FALSE(wire::validateManagementState(*flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer())));
  }
  flatbuffers::FlatBufferBuilder b;b.Finish(wire::CreateAreaState(b));
  CHECK_FALSE(codec::decodeArea(flatbuffers::GetRoot<wire::AreaState>(b.GetBufferPointer())).locationRecognition);
}

TEST_CASE("Religious staff requests bind assignment identity and removal revision") {
  for(bool apply:{false,true})for(int variant=0;variant<16;++variant) {
    wm::ManagementRequest r;r.action=apply?wm::ManagementAction::AreaUpdate:wm::ManagementAction::AreaInspect;
    auto& a=r.area;a.kind=wm::AreaKind::Zone;a.locationSiteId=651;a.locationId=0;
    a.religiousEntityId=383;a.religiousAssignmentId=2;a.religiousHolderId=apply?9375:-1;
    a.operation=apply?wm::AreaOperation::LocationReligiousStaffRemove:wm::AreaOperation::LocationReligiousStaffRead;
    a.expectedRevision=apply?9007199254740993LL:0;
    if(variant==1)a.expectedRevision=apply?0:17;
    if(variant==2)a.locationSiteId=-1;
    if(variant==3)a.locationId=-1;
    if(variant==4)a.id=4;
    if(variant==5)a.kind=wm::AreaKind::Stockpile;
    if(variant==6)r.action=apply?wm::ManagementAction::AreaInspect:wm::ManagementAction::AreaUpdate;
    if(variant==7)a.nameEdit.emplace();
    if(variant==8)a.quantityId=0;
    if(variant==9)a.expectedListRevision=1;
    if(variant==10)a.expectedRevision=-1;
    if(variant==11)a.religiousEntityId=-1;
    if(variant==12)a.religiousAssignmentId=-1;
    if(variant==13)a.religiousHolderId=apply?-1:9375;
    if(variant==14)a.occupationId=2;
    if(variant==15)a.operation=wm::AreaOperation::LocationRecognitionRead;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* q=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CAPTURE(apply);CAPTURE(variant);CHECK(bool(wire::validateConstructionRequest(*q))==(variant!=0));
    if(!variant) {CHECK(q->area()->religious_entity_id()==383);CHECK(q->area()->religious_assignment_id()==2);}
    if(!variant && apply)CHECK(q->area()->expected_revision()==9007199254740993ULL);
  }
}
TEST_CASE("Religious staff replies preserve receipts and reject invalid authority") {
  for(bool apply:{false,true})for(int variant=0;variant<13;++variant) {
    flatbuffers::FlatBufferBuilder b;
    auto receipt=wire::CreateLocationReligiousStaff(b,651,0,variant==1?-1:383,2,0,
        variant==2?-2:apply?-1:9375,apply?-1:5813,variant==3?0:9007199254740993ULL,variant==4?true:!apply);
    wire::AreaStateBuilder a(b);a.add_operation(variant==5?wire::AreaOperation::LocationDetails:apply?wire::AreaOperation::LocationReligiousStaffRemove:wire::AreaOperation::LocationReligiousStaffRead);
    if(variant!=6)a.add_location_religious_staff(receipt);
    if(apply || variant==7)a.add_location_edit_outcome(variant==7?wire::LocationEditOutcome::Unknown:wire::LocationEditOutcome::Completed);
    if(variant==8)a.add_area_id(2);
    if(variant==9)a.add_list_revision(3);
    auto area=a.Finish();wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_area(area);
    root.add_action(variant==10?wire::ManagementAction::AreaDelete:apply?wire::ManagementAction::AreaUpdate:wire::ManagementAction::AreaInspect);
    root.add_status(variant==11?wire::ManagementStatus::Rejected:wire::ManagementStatus::Ok);
    if(variant==12)root.add_schema_version(wire::kManagementVersion-1);
    b.Finish(root.Finish());const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CAPTURE(apply);CAPTURE(variant);const bool invalid=variant!=0 && !(variant==4 && !apply);
    CHECK(bool(wire::validateManagementState(*state))==invalid);
    if(!invalid) {const auto decoded=codec::decodeArea(state->area());REQUIRE(decoded.locationReligiousStaff);
      CHECK(decoded.locationReligiousStaff->revision==9007199254740993LL);CHECK(decoded.locationReligiousStaff->assignmentId==2);
      CHECK(decoded.locationReligiousStaff->removable==!apply);}
  }
  for(auto outcome:{wire::LocationEditOutcome::Rejected,wire::LocationEditOutcome::Stale,wire::LocationEditOutcome::Unknown}) {
    flatbuffers::FlatBufferBuilder b;wire::AreaStateBuilder a(b);a.add_operation(wire::AreaOperation::LocationReligiousStaffRemove);a.add_location_edit_outcome(outcome);
    auto area=a.Finish();wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_area(area);
    root.add_action(wire::ManagementAction::AreaUpdate);root.add_status(wire::ManagementStatus::Rejected);b.Finish(root.Finish());
    CHECK_FALSE(wire::validateManagementState(*flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer())));
  }
  flatbuffers::FlatBufferBuilder b;b.Finish(wire::CreateAreaState(b));
  CHECK_FALSE(codec::decodeArea(flatbuffers::GetRoot<wire::AreaState>(b.GetBufferPointer())).locationReligiousStaff);
}

TEST_CASE("Religious assignment requests require independent list and candidate authority") {
  for(int op=35;op<=37;++op)for(int variant=0;variant<15;++variant) {
    wm::ManagementRequest r;r.action=op==37?wm::ManagementAction::AreaUpdate:wm::ManagementAction::AreaInspect;
    auto& a=r.area;a.kind=wm::AreaKind::Zone;a.operation=static_cast<wm::AreaOperation>(op);
    a.locationSiteId=651;a.locationId=0;a.religiousEntityId=383;a.religiousAssignmentId=2;
    a.unitId=op==35?-1:7123;a.expectedListRevision=op==35?0:9007199254740993LL;
    a.expectedRevision=op==37?9007199254740995LL:0;
    if(variant==1)a.locationSiteId=-1;
    if(variant==2)a.locationId=-1;
    if(variant==3)a.religiousEntityId=-1;
    if(variant==4)a.religiousAssignmentId=-1;
    if(variant==5)a.occupationId=1;
    if(variant==6)a.unitId=op==35?1:-1;
    if(variant==7)a.expectedRevision=op==37?0:1;
    if(variant==8)a.cursor=1;
    if(variant==9)a.expectedListRevision=-1;
    if(variant==10)a.id=1;
    if(variant==11)a.kind=wm::AreaKind::Stockpile;
    if(variant==12)a.quantityId=1;
    if(variant==13)r.action=wm::ManagementAction::AreaDelete;
    if(variant==14){if(op==35)a.cursor=128;else a.expectedListRevision=0;}
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* q=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CAPTURE(op);CAPTURE(variant);CHECK(bool(wire::validateConstructionRequest(*q))==(variant!=0));
  }
}
TEST_CASE("Religious selection replies preserve wide receipts and reject mixed authority") {
  for(bool list:{false,true})for(int variant=0;variant<11;++variant) {
    flatbuffers::FlatBufferBuilder b;
    auto target=wire::CreateLocationReligiousStaff(b,651,0,383,2,0,-1,-1,variant==1?0:9007199254740994ULL,false);
    auto page=wire::CreateLocationReligiousCandidates(b,target,variant==2?0:9007199254740993ULL,variant==3?1:0);
    auto selected=wire::CreateLocationReligiousAssignment(b,target,variant==3?-1:7123,10379,7120,
        variant==2?0:9007199254740995ULL,variant==4?0:9007199254740993ULL,variant!=5);
    wire::AreaStateBuilder a(b);a.add_operation(list?wire::AreaOperation::LocationReligiousCandidates:wire::AreaOperation::LocationReligiousAssignmentRead);
    if(variant!=6){if(list)a.add_location_religious_candidates(page);else a.add_location_religious_assignment(selected);}
    if(variant==7)a.add_location_religious_staff(target);
    if(variant==8)a.add_location_edit_outcome(wire::LocationEditOutcome::Completed);
    auto area=a.Finish();wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_area(area);
    root.add_action(variant==9?wire::ManagementAction::AreaUpdate:wire::ManagementAction::AreaInspect);
    root.add_status(variant==10?wire::ManagementStatus::Rejected:wire::ManagementStatus::Ok);
    b.Finish(root.Finish());const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    const bool invalid=variant!=0 && !(list && (variant==4 || variant==5));
    CAPTURE(list);CAPTURE(variant);CHECK(bool(wire::validateManagementState(*state))==invalid);
    if(!invalid){const auto decoded=codec::decodeArea(state->area());
      if(list){REQUIRE(decoded.locationReligiousCandidates);CHECK(decoded.locationReligiousCandidates->revision==9007199254740993LL);}
      else {REQUIRE(decoded.locationReligiousAssignment);CHECK(decoded.locationReligiousAssignment->revision==9007199254740995LL);CHECK(decoded.locationReligiousAssignment->target.revision==9007199254740994LL);}
    }
  }
}
TEST_CASE("Specialization requests bind exactly one row identity and desired state") {
  for(bool occupation:{false,true})for(bool apply:{false,true})for(int variant=0;variant<13;++variant) {
    wm::ManagementRequest r;r.action=apply?wm::ManagementAction::AreaUpdate:wm::ManagementAction::AreaInspect;
    auto& a=r.area;a.kind=wm::AreaKind::Zone;a.operation=apply?wm::AreaOperation::LocationSpecializationSet:wm::AreaOperation::LocationSpecializationRead;
    a.locationSiteId=651;a.locationId=0;a.unitId=5813;
    if(occupation)a.occupationId=87;else {a.religiousEntityId=383;a.religiousAssignmentId=2;}
    a.expectedRevision=apply?9007199254740993LL:0;
    if(variant==1)a.locationSiteId=-1;
    if(variant==2)a.locationId=-1;
    if(variant==3)a.unitId=-1;
    if(variant==4){if(occupation)a.occupationId=-1;else a.religiousEntityId=-1;}
    if(variant==5){if(occupation)a.religiousEntityId=383;else a.occupationId=87;}
    if(variant==6)a.expectedRevision=apply?0:1;
    if(variant==7)a.value=2;
    if(variant==8)a.cursor=1;
    if(variant==9)a.expectedListRevision=1;
    if(variant==10)a.kind=wm::AreaKind::Stockpile;
    if(variant==11)a.religiousHolderId=9375;
    if(variant==12)r.action=wm::ManagementAction::AreaDelete;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* q=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CAPTURE(occupation);CAPTURE(apply);CAPTURE(variant);CHECK(bool(wire::validateConstructionRequest(*q))==(variant!=0));
  }
}
TEST_CASE("Specialization responses preserve wide revisions and reject malformed authority") {
  for(bool apply:{false,true})for(int variant=0;variant<12;++variant) {
    flatbuffers::FlatBufferBuilder b;
    auto r=wire::CreateLocationSpecialization(b,variant==1?-1:651,0,variant==2?87:-1,383,2,variant==3?-1:5813,9375,
        variant==4?0:9007199254740993ULL,true,false);
    wire::AreaStateBuilder a(b);a.add_operation(apply?wire::AreaOperation::LocationSpecializationSet:wire::AreaOperation::LocationSpecializationRead);
    if(variant!=5)a.add_location_specialization(r);
    if(apply || variant==6)a.add_location_edit_outcome(variant==7?wire::LocationEditOutcome::Unknown:wire::LocationEditOutcome::Completed);
    if(variant==8)a.add_area_id(1);
    if(variant==9)a.add_list_revision(1);
    auto area=a.Finish();wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_area(area);
    root.add_action(variant==10?wire::ManagementAction::AreaDelete:(apply?wire::ManagementAction::AreaUpdate:wire::ManagementAction::AreaInspect));
    root.add_status(variant==11?wire::ManagementStatus::Rejected:wire::ManagementStatus::Ok);
    b.Finish(root.Finish());const auto* s=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    const bool invalid=variant!=0 && !(apply && variant==6) && !(!apply && variant==7);
    CAPTURE(apply);CAPTURE(variant);CHECK(bool(wire::validateManagementState(*s))==invalid);
    if(!invalid){const auto decoded=codec::decodeArea(s->area());REQUIRE(decoded.locationSpecialization);CHECK(decoded.locationSpecialization->revision==9007199254740993LL);CHECK_FALSE(decoded.locationSpecialization->specialized);}
  }
}

TEST_CASE("Staff assignment read requests bind one row and carry no mutation fields") {
  for(bool occupation:{false,true})for(int variant=0;variant<10;++variant) {
    wm::ManagementRequest r;r.action=wm::ManagementAction::AreaInspect;
    auto& a=r.area;a.kind=wm::AreaKind::Zone;a.operation=wm::AreaOperation::LocationStaffAssignmentsRead;
    a.locationSiteId=651;a.locationId=0;a.unitId=5813;
    if(occupation)a.occupationId=87;else {a.religiousEntityId=383;a.religiousAssignmentId=2;}
    if(variant==1)a.unitId=-1;
    if(variant==2)a.locationSiteId=-1;
    if(variant==3)a.locationId=-1;
    if(variant==4){if(occupation)a.religiousEntityId=1;else a.occupationId=1;}
    if(variant==5)a.expectedRevision=1;
    if(variant==6)a.value=1;
    if(variant==7)a.expectedListRevision=1;
    if(variant==8)a.kind=wm::AreaKind::Stockpile;
    if(variant==9)r.action=wm::ManagementAction::AreaUpdate;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    CAPTURE(occupation);CAPTURE(variant);
    CHECK(bool(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer())))==(variant!=0));
  }
}
TEST_CASE("Staff assignment replies preserve order and distinguish empty from absent") {
  for(int variant=0;variant<17;++variant) {
    flatbuffers::FlatBufferBuilder b;
    std::vector<flatbuffers::Offset<wire::LocationStaffAssignment>> entries;
    if(variant!=1)for(int k=0;k<4;++k)entries.push_back(wire::CreateLocationStaffAssignment(b,
        wire::LocationStaffAssignmentKind(variant==2?4:variant==3?3-k:k),variant==4?-1:k,1,
        variant==5?2:-1,(k==1 || variant==16)?7:-1,b.CreateString(k==3 || variant==6?"Synthetic detail":""),
        b.CreateString(variant==14?"":variant==15?std::string(65,'X'):k==1?"SYNTHETIC_WORKSHOP":"")));
    auto r=wire::CreateLocationStaffAssignments(b,variant==7?-1:651,0,variant==8?87:-1,383,2,5813,9375,
        variant==9?0:9007199254740993ULL,variant==10?0:b.CreateVector(entries));
    wire::AreaStateBuilder a(b);a.add_operation(variant==11?wire::AreaOperation::LocationSpecializationRead:wire::AreaOperation::LocationStaffAssignmentsRead);
    if(variant!=12)a.add_location_staff_assignments(r);
    if(variant==13)a.add_location_edit_outcome(wire::LocationEditOutcome::Completed);
    auto area=a.Finish();wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_area(area);
    root.add_action(wire::ManagementAction::AreaInspect);root.add_status(wire::ManagementStatus::Ok);
    b.Finish(root.Finish());const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CAPTURE(variant);CHECK(bool(wire::validateManagementState(*state))==(variant>1));
    if(variant<2) {auto decoded=codec::decodeArea(state->area());REQUIRE(decoded.locationStaffAssignments);
      CHECK(decoded.locationStaffAssignments->revision==9007199254740993LL);
      CHECK(decoded.locationStaffAssignments->entries.size()==(variant==1?0:4));
      if(!variant) {CHECK(decoded.locationStaffAssignments->entries[3].name=="Synthetic detail");
        CHECK(decoded.locationStaffAssignments->entries[1].customCode=="SYNTHETIC_WORKSHOP");}
    }
  }
}

TEST_CASE("Tracker requests exclude history filters and inspection authority") {
  for(int variant=0;variant<6;++variant) {
    wm::ManagementRequest r;r.action=wm::ManagementAction::AgreementList;r.agreement.tracker=true;
    if(variant==1){r.action=wm::ManagementAction::AgreementInspect;r.agreement.id=1;}
    if(variant==2)r.agreement.beforeId=0;
    if(variant==3)r.agreement.query="filter";
    if(variant==4)r.agreement.pendingOnly=true;
    if(variant==5)r.agreement.id=1;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* q=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CAPTURE(variant);CHECK(q->agreement()->tracker());CHECK(bool(wire::validateConstructionRequest(*q))==(variant>1));
  }
}
TEST_CASE("Tracker replies distinguish empty success from absence and preserve blank slots") {
  for(int variant=0;variant<13;++variant) {
    flatbuffers::FlatBufferBuilder b;
    std::vector<flatbuffers::Offset<wire::ContinuingAgreementRow>> rows;
    if(variant!=1) {
      rows.push_back(wire::CreateContinuingAgreementRow(b,7,0,8,0,-1,-1,106,0,b.CreateString(""),b.CreateString(variant==8?"invented":""),b.CreateString("")));
      rows.push_back(wire::CreateContinuingAgreementRow(b,variant==9?-1:9,0,10,5,1,-1,106,variant==10?403200:0,b.CreateString("Synthetic heading"),b.CreateString(variant==11?std::string(4097,'x'):"Synthetic applicant"),variant==12?0:b.CreateString("Synthetic date")));
    }
    auto a=wire::CreateAgreementState(b,0,variant==6?1:-1,variant==7,b.CreateString(""),variant!=2,variant==3?0:b.CreateVector(rows));
    wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_agreement(a);
    root.add_action(variant==4?wire::ManagementAction::AgreementInspect:wire::ManagementAction::AgreementList);
    root.add_status(variant==5?wire::ManagementStatus::Rejected:wire::ManagementStatus::Ok);b.Finish(root.Finish());
    const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CAPTURE(variant);CHECK(bool(wire::validateManagementState(*state))==(variant>1));
    if(variant<2) {
      const auto decoded=codec::decodeAgreement(state->agreement());CHECK(decoded.tracker);
      REQUIRE(decoded.trackerRows.size()==(variant==1?0:2));
      if(!variant){CHECK(decoded.trackerRows[0].applicant.empty());CHECK(decoded.trackerRows[1].agreementId==9);CHECK(decoded.trackerRows[1].applicant=="Synthetic applicant");}
    }
  }
}

TEST_CASE("Tracker popup replies require one row and coherent location facts") {
  for(int variant=0;variant<15;++variant) {
    flatbuffers::FlatBufferBuilder b;
    const bool absent=variant==1 || variant==2 || variant==13;
    const bool blank=variant==2;
    auto row=wire::CreateContinuingAgreementRow(b,9,0,10,blank?0:5,2,-1,106,0,b.CreateString(""),b.CreateString(blank?"":"Synthetic applicant"),b.CreateString(blank?"":"Synthetic date"));
    std::vector<flatbuffers::Offset<wire::ContinuingAgreementRow>> rows;if(variant!=5)rows.push_back(row);
    auto details=wire::CreateContinuingAgreementDetails(b,blank?-1:10000,variant==6?-1:absent||variant==12?0:1,
        variant==7?-2:absent?-1:3,absent||variant==10?0:5675,absent?-1:1,!blank&&variant!=11,variant==9,
        variant==8?0:b.CreateString(!absent||variant==13?"Synthetic location":""));
    auto a=wire::CreateAgreementState(b,0,-1,false,b.CreateString(""),variant!=14,b.CreateVector(rows),variant==3?0:details);
    wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_agreement(a);
    root.add_action(variant==4?wire::ManagementAction::AgreementList:wire::ManagementAction::AgreementInspect);
    root.add_status(wire::ManagementStatus::Ok);b.Finish(root.Finish());
    const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CAPTURE(variant);CHECK(bool(wire::validateManagementState(*state))==(variant>=3));
    if(variant<3) {
      auto decoded=codec::decodeAgreement(state->agreement());REQUIRE(decoded.trackerDetails);
      CHECK(decoded.trackerRows.size()==1);CHECK(decoded.trackerDetails->locationId==(absent?-1:3));
      CHECK(decoded.trackerDetails->locationName==(absent?"":"Synthetic location"));
      CHECK(decoded.trackerDetails->requiredValue==(blank?-1:10000));
    }
  }
}

TEST_CASE("contents reads carry exact independent revisions and reject mixed intents") {
  for(int fault=0;fault<10;++fault) {
    CAPTURE(fault);wm::ManagementRequest request;request.action=wm::ManagementAction::ProductionInspect;
    auto& p=request.production;p.buildingId=968;p.contents=true;
    if(fault==1){p.cursor=64;p.expectedRevision=9007199254740993ULL;}
    if(fault==2)p.cursor=1;
    if(fault==3)p.expectedRevision=UINT64_MAX;
    if(fault==4)p.season=1;
    if(fault==5)request.action=wm::ManagementAction::FarmEdit;
    if(fault==6)p.cropId=2;
    if(fault==7)p.query="mixed";
    if(fault==8)p.cancel=true;
    if(fault==9)p.farmName="mixed";
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(bool(wire::validateConstructionRequest(*value))==(fault>1));
    CHECK(value->production()->contents());CHECK(value->production()->expected_revision()==p.expectedRevision);
  }
}
TEST_CASE("contents pages preserve native order and reject incomplete or ambiguous boundaries") {
  for(int fault=0;fault<17;++fault) {
    CAPTURE(fault);flatbuffers::FlatBufferBuilder b;
    std::vector<flatbuffers::Offset<wire::BuildingContentsItem>> rows;
    for(int i=0;i<(fault==8?65:2);++i)rows.push_back(wire::CreateBuildingContentsItem(b,fault==7?1:5-i,fault==9?-1:0,
      b.CreateString(fault==10?std::string(65537,'x'):"native caption"),true,false,false,true,true,false,true,true,fault==12?-1:fault==13?93:53,
      fault==14?0:b.CreateString(fault==15?std::string(257,'x'):"PLANT:POD_SWEET:SEED"),b.CreateString(fault==16?std::string(129,'x'):"")));
    auto page=wire::CreateBuildingContentsPage(b,968,fault==1?0:9007199254740993ULL,
      fault==2?4:0,fault==3?1:2,fault==4?1:3,true,false,b.CreateVector(rows));
    wire::ProductionStateBuilder p(b);p.add_selected_building(fault==5?969:968);p.add_contents(page);
    auto prod=p.Finish();wire::ManagementStateBuilder state(b);state.add_revision(1);
    state.add_action(fault==6?wire::ManagementAction::FarmEdit:wire::ManagementAction::ProductionInspect);
    state.add_status(fault==11?wire::ManagementStatus::Rejected:wire::ManagementStatus::Ok);state.add_production(prod);
    b.Finish(state.Finish());const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(fault!=0));
    if(!fault) {
      const auto result=codec::decodeProduction(value->production());REQUIRE(result.contents);
      CHECK(result.contents->revision==9007199254740993ULL);CHECK(result.contents->nextCursor==2);
      REQUIRE(result.contents->rows.size()==2);CHECK(result.contents->rows[0].id==5);CHECK(result.contents->rows[1].id==4);
      CHECK(result.contents->rows[0].forbid);CHECK(result.contents->rows[0].inBuilding);
      CHECK(result.contents->rows[0].itemType==53);CHECK(result.contents->rows[0].materialToken=="PLANT:POD_SWEET:SEED");CHECK(result.contents->rows[0].subtypeRaw.empty());
    }
  }
  flatbuffers::FlatBufferBuilder b;auto p=wire::CreateProductionState(b);b.Finish(p);
  CHECK_FALSE(codec::decodeProduction(flatbuffers::GetRoot<wire::ProductionState>(b.GetBufferPointer())).contents);
}

TEST_CASE("contained item wire intents require explicit values and independent revisions") {
  for(auto operation:{wm::FarmOperation::ItemForbid,wm::FarmOperation::ItemDump,wm::FarmOperation::ItemMelt,wm::FarmOperation::ItemHidden})
  for(int fault=0;fault<11;++fault) {
    CAPTURE(fault);wm::ManagementRequest request;request.action=wm::ManagementAction::FarmEdit;
    auto& p=request.production;p.buildingId=968;p.farmOperation=operation;p.itemId=47492;p.itemValue=1;p.expectedRevision=9007199254740993ULL;
    if(fault==1)p.itemId=-1;if(fault==2)p.itemValue=-1;if(fault==3)p.itemValue=2;
    if(fault==4)p.expectedRevision=0;if(fault==5)p.season=0;if(fault==6)p.cursor=1;
    if(fault==7)p.contents=true;if(fault==8)p.farmName="mixed";
    if(fault==9)request.action=wm::ManagementAction::ProductionInspect;
    if(fault==10)p.farmOperation=wm::FarmOperation::Crop;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(bool(wire::validateConstructionRequest(*value))==(fault!=0));
    if(!fault){CHECK(value->production()->item_id()==47492);CHECK(value->production()->item_value()==1);}
  }
}
TEST_CASE("contained item completion grants authority only for the observed target and value") {
  for(int fault=0;fault<12;++fault) {
    CAPTURE(fault);flatbuffers::FlatBufferBuilder b;
    auto row=wire::CreateBuildingContentsItem(b,47492,2,b.CreateString("native name"),fault!=1,false,false,false,true,false,false,true,53,b.CreateString("PLANT:POD_SWEET:SEED"),b.CreateString(""));
    auto page=wire::CreateBuildingContentsPage(b,968,17,0,0,1,fault!=10,fault==11,b.CreateVector(std::vector{row}));
    auto edit=wire::CreateBuildingItemReceipt(b,fault==2?47493:47492,
      fault==3?wire::FarmOperation::Crop:wire::FarmOperation::ItemForbid,fault==4?-1:1);
    wire::ProductionStateBuilder p(b);p.add_selected_building(968);
    if(fault!=5)p.add_contents(page);if(fault!=6)p.add_contents_edit(edit);
    p.add_farm_edit_outcome(fault==7?wire::FarmEditOutcome::Unknown:wire::FarmEditOutcome::Completed);
    auto prod=p.Finish();wire::ManagementStateBuilder state(b);state.add_revision(1);
    state.add_action(fault==8?wire::ManagementAction::ProductionInspect:wire::ManagementAction::FarmEdit);
    state.add_status(fault==9?wire::ManagementStatus::Rejected:wire::ManagementStatus::Ok);state.add_production(prod);
    b.Finish(state.Finish());const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(fault!=0 && fault!=10 && fault!=11));
    if(fault==0||fault==10||fault==11){const auto decoded=codec::decodeProduction(value->production());REQUIRE(decoded.contentsEdit);CHECK(decoded.contentsEdit->itemId==47492);CHECK(decoded.contentsEdit->value==1);REQUIRE(decoded.contents);CHECK(decoded.contents->completed==(fault!=10));}
  }
}

TEST_CASE("item inspection intent is independent of contents paging and edits") {
  for(int fault=0;fault<13;++fault) {
    CAPTURE(fault);wm::ManagementRequest request;request.action=wm::ManagementAction::ProductionInspect;
    auto& p=request.production;p.buildingId=968;p.itemId=47492;
    if(fault==1)p.itemId=-2;
    if(fault==2)p.itemValue=0;
    if(fault==3)p.contents=true;
    if(fault==4)p.season=0;
    if(fault==5)p.cursor=1;
    if(fault==6)p.expectedRevision=17;
    if(fault==7)p.cropId=2;
    if(fault==8)p.query="mixed";
    if(fault==9)p.cancel=true;
    if(fault==10)request.action=wm::ManagementAction::ProductionList;
    if(fault==11)p.farmOperation=wm::FarmOperation::ItemForbid;
    if(fault==12)p.buildingId=-1;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(bool(wire::validateConstructionRequest(*value))==(fault!=0));
    if(!fault)CHECK(value->production()->item_id()==47492);
  }
}
TEST_CASE("item inspection preserves native facts and rejects ambiguous authority") {
  for(int fault=0;fault<27;++fault) {
    CAPTURE(fault);flatbuffers::FlatBufferBuilder b;
    auto row=wire::CreateBuildingContentsItem(b,fault==5?-1:47492,fault==6?-1:2,
      fault==7?0:b.CreateString(fault==8?std::string(131073,'x'):"native caption"),true,false,false,true,true,false,false,true,
      fault==9?93:53,fault==10?0:b.CreateString("PLANT:POD_SWEET:SEED"),b.CreateString(fault==11?std::string(129,'x'):""));
    std::vector<wire::AppearanceLayer> layers;
    if(fault!=24)layers.emplace_back(fault==25?1:0,3,4,1,1,65535,-1,-1,0,0);
    const auto artwork=wire::CreateSelectionAppearance(b,b.CreateVectorOfStrings(std::vector<std::string>{"PAGE"}),
      b.CreateVectorOfStrings(std::vector<std::string>{}),b.CreateVectorOfStructs(layers));
    auto holder=wire::CreateItemBuildingHolder(b,fault==16?-1:968,fault==17?-1:4,
      fault==18?0:b.CreateString(fault==19?std::string(513,'x'):"Farm Plot"),fault==26?0:artwork);
    auto item=wire::CreateBuildingItemSnapshot(b,968,fault==1?0:fault==2?UINT64_MAX:9007199254740993ULL,
      true,false,fault==4?0:row,fault==12?0:b.CreateString(fault==13?std::string(129,'x'):"<1"),
      fault==14?0:b.CreateString(fault==15?std::string(32769,'x'):"native description"),fault==23?0:holder);
    auto page=wire::CreateBuildingContentsPage(b,968,17,0,0,1,true,false,b.CreateVector(std::vector{row}));
    wire::ProductionStateBuilder p(b);p.add_selected_building(fault==3?969:968);p.add_item(item);
    if(fault==20)p.add_contents(page);
    auto prod=p.Finish();wire::ManagementStateBuilder state(b);state.add_revision(1);
    state.add_action(fault==21?wire::ManagementAction::ProductionList:wire::ManagementAction::ProductionInspect);
    state.add_status(fault==22?wire::ManagementStatus::Rejected:wire::ManagementStatus::Ok);state.add_production(prod);
    b.Finish(state.Finish());const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(fault!=0 && fault!=23 && fault!=26));
    if(fault==0 || fault==23 || fault==26) {
      auto decoded=codec::decodeProduction(value->production());REQUIRE(decoded.item);
      CHECK(decoded.item->revision==9007199254740993ULL);CHECK(decoded.item->item.id==47492);
      CHECK(decoded.item->item.forbid);CHECK(decoded.item->item.materialToken=="PLANT:POD_SWEET:SEED");
      CHECK(decoded.item->description=="native description");CHECK(decoded.item->weight=="<1");
      CHECK(bool(decoded.item->holder)==(fault!=23));
      if(decoded.item->holder){CHECK(decoded.item->holder->id==968);CHECK(decoded.item->holder->name=="Farm Plot");CHECK(decoded.item->holder->appearance.has_value()==(fault!=26));if(fault!=26)CHECK(decoded.item->holder->appearance->tilePages==std::vector<std::string>{"PAGE"});}
    }
  }
  flatbuffers::FlatBufferBuilder b;b.Finish(wire::CreateProductionState(b));
  CHECK_FALSE(codec::decodeProduction(flatbuffers::GetRoot<wire::ProductionState>(b.GetBufferPointer())).item);
}

TEST_CASE("item position request excludes building and edit authority") {
  for(int fault=0;fault<10;++fault) {
    CAPTURE(fault);wm::ManagementRequest request;request.action=wm::ManagementAction::ProductionInspect;
    auto& p=request.production;p.locateItem=true;p.itemId=47492;
    if(fault==1)p.itemId=-1;
    if(fault==2)p.buildingId=968;
    if(fault==3)p.contents=true;
    if(fault==4)p.expectedRevision=1;
    if(fault==5)p.season=0;
    if(fault==6)p.itemValue=0;
    if(fault==7)p.query="mixed";
    if(fault==8)request.action=wm::ManagementAction::ProductionList;
    if(fault==9)p.locateItem=false;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(bool(wire::validateConstructionRequest(*value))==(fault!=0));
    if(!fault)CHECK(value->production()->locate_item());
  }
}
TEST_CASE("item position response is bounded and has no mixed authority") {
  for(int fault=0;fault<8;++fault) {
    CAPTURE(fault);flatbuffers::FlatBufferBuilder b;
    const wire::TilePos pos(fault==1?-1:123,fault==2?32768:456,17);
    auto target=wire::CreateItemPosition(b,fault==3?-1:47492,&pos);
    wire::ProductionStateBuilder p(b);p.add_item_position(target);
    if(fault==4)p.add_selected_building(968);
    if(fault==5)p.add_farm_edit_outcome(wire::FarmEditOutcome::Completed);
    auto prod=p.Finish();wire::ManagementStateBuilder state(b);state.add_revision(1);
    state.add_action(fault==6?wire::ManagementAction::ProductionList:wire::ManagementAction::ProductionInspect);
    state.add_status(fault==7?wire::ManagementStatus::Rejected:wire::ManagementStatus::Ok);state.add_production(prod);
    b.Finish(state.Finish());const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(fault!=0));
    if(!fault) {
      auto decoded=codec::decodeProduction(value->production());REQUIRE(decoded.itemPosition);
      CHECK(decoded.itemPosition->id==47492);CHECK(decoded.itemPosition->x==123);
      CHECK(decoded.itemPosition->y==456);CHECK(decoded.itemPosition->z==17);
    }
  }
  flatbuffers::FlatBufferBuilder b;b.Finish(wire::CreateProductionState(b));
  CHECK_FALSE(codec::decodeProduction(flatbuffers::GetRoot<wire::ProductionState>(b.GetBufferPointer())).itemPosition);
}

TEST_CASE("independent item requests exclude building authority and preserve exact revisions") {
  for(bool edit:{false,true})for(int fault=0;fault<10;++fault) {
    CAPTURE(edit);CAPTURE(fault);wm::ManagementRequest request;
    request.action=edit?wm::ManagementAction::FarmEdit:wm::ManagementAction::ProductionInspect;
    auto& p=request.production;p.independentItem=true;p.itemId=45;
    if(edit){p.farmOperation=wm::FarmOperation::ItemHidden;p.itemValue=1;p.expectedRevision=9007199254740993ULL;}
    if(fault==1)p.buildingId=227;if(fault==2)p.itemId=-1;if(fault==3)p.contents=true;
    if(fault==4)p.locateItem=true;if(fault==5)p.season=0;if(fault==6)p.query="mixed";
    if(fault==7)p.expectedRevision=edit?0:1;
    if(fault==8)request.action=wm::ManagementAction::ProductionList;
    if(fault==9)p.farmOperation=wm::FarmOperation::Rename;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(bool(wire::validateConstructionRequest(*value))==(fault!=0));
    if(!fault){CHECK(value->production()->independent_item());if(edit)CHECK(value->production()->expected_revision()==9007199254740993ULL);}
  }
}
TEST_CASE("independent item receipts reject mixed and unconfirmed authority") {
  for(bool editing:{false,true})for(int fault=0;fault<(editing?19:15);++fault) {
    CAPTURE(editing);CAPTURE(fault);flatbuffers::FlatBufferBuilder b;
    auto pile=wire::CreateItemBuildingHolder(b,fault==8?-1:121,fault==9?4:29,b.CreateString("native pile"));
    auto item=wire::CreateIndependentItemSnapshot(b,fault==1?-1:45,fault==2?0:fault==3?UINT64_MAX:9007199254740993ULL,
      fault==5?93:0,fault==4?0:b.CreateString("native item"),b.CreateString(fault==6?std::string(257,'x'):"POTASH"),b.CreateString(""),
      false,true,false,false,true,false,false,false,b.CreateString("weight"),b.CreateString(fault==7?std::string(32769,'x'):"description"),0,pile,0x1ffff);
    auto receipt=wire::CreateBuildingItemReceipt(b,fault==14?46:45,fault==18?wire::FarmOperation::Crop:wire::FarmOperation::ItemDump,fault==17?-1:fault==15?0:1);
    const auto outcome=editing?(fault==16?wire::FarmEditOutcome::Unknown:wire::FarmEditOutcome::Completed):
      (fault==14?wire::FarmEditOutcome::Completed:wire::FarmEditOutcome::None);
    auto independent=wire::CreateIndependentItemState(b,item,(editing&&fault!=13)||(!editing&&fault==13)?receipt:0,outcome);
    wire::ProductionStateBuilder prod(b);prod.add_independent_item(independent);if(fault==10)prod.add_selected_building(227);
    auto payload=prod.Finish();wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_production(payload);
    state.add_action(fault==12?wire::ManagementAction::ProductionList:editing?wire::ManagementAction::FarmEdit:wire::ManagementAction::ProductionInspect);
    state.add_status(fault==11?wire::ManagementStatus::Rejected:wire::ManagementStatus::Ok);
    b.Finish(state.Finish());const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(fault!=0));
    if(!fault) {
      auto decoded=codec::decodeProduction(value->production());REQUIRE(decoded.independentItem);REQUIRE(decoded.independentItem->snapshot);
      const auto& snapshot=*decoded.independentItem->snapshot;CHECK(snapshot.revision==9007199254740993ULL);CHECK(snapshot.id==45);
      REQUIRE(snapshot.stockpile);CHECK(snapshot.stockpileCategories==0x1ffff);CHECK(snapshot.stockpile->id==121);CHECK(snapshot.stockpile->name=="native pile");CHECK_FALSE(snapshot.holder);
      CHECK(bool(decoded.independentItem->edit)==editing);CHECK_FALSE(decoded.item);CHECK_FALSE(decoded.contents);
    }
  }
  for(auto outcome:{wire::FarmEditOutcome::Rejected,wire::FarmEditOutcome::Stale,wire::FarmEditOutcome::Unknown}) {
    flatbuffers::FlatBufferBuilder b;auto independent=wire::CreateIndependentItemState(b,0,0,outcome);
    wire::ProductionStateBuilder prod(b);prod.add_independent_item(independent);auto payload=prod.Finish();
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_production(payload);state.add_action(wire::ManagementAction::FarmEdit);state.add_status(wire::ManagementStatus::Rejected);
    b.Finish(state.Finish());CHECK_FALSE(wire::validateManagementState(*flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer())));
  }
}

TEST_CASE("independent item stockpile categories require matching relationship authority") {
  for(bool linked:{false,true})for(int categories:{-1,0,1,0x1ffff,0x20000}) {
    flatbuffers::FlatBufferBuilder b;
    auto pile=wire::CreateItemBuildingHolder(b,121,29,b.CreateString("pile"));
    auto text=b.CreateString("");
    auto item=wire::CreateIndependentItemSnapshot(b,45,1,0,text,text,text,false,false,false,false,true,false,false,false,text,text,0,linked?pile:0,categories);
    auto independent=wire::CreateIndependentItemState(b,item);
    wire::ProductionStateBuilder prod(b);prod.add_independent_item(independent);auto payload=prod.Finish();
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_production(payload);
    state.add_action(wire::ManagementAction::ProductionInspect);state.add_status(wire::ManagementStatus::Ok);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    const bool valid=linked?(categories>=0&&categories<=0x1ffff):categories==-1;
    CHECK(bool(wire::validateManagementState(*value))==!valid);
  }
}

TEST_CASE("independent item carrier codec preserves identity and rejects malformed authority") {
  for(int kind:{1,2})for(int fault=0;fault<14;++fault) {
    CAPTURE(kind);CAPTURE(fault);flatbuffers::FlatBufferBuilder b;
    flatbuffers::Offset<wire::ItemInspectionAppearance> appearance;
    if((kind==1&&fault!=8)||(kind==2&&fault>=8))appearance=wire::CreateItemInspectionAppearance(b,b.CreateString(fault==9?"":fault==10?std::string(257,'x'):"WOOD"),b.CreateString(fault==11?std::string(129,'x'):""),b.CreateString(""),fault==12?0:1,fault==13?1:0);
    auto carrier=wire::CreateItemCarrier(b,fault==1?0:kind,fault==2?-1:988,
      fault==3?(kind==1?-1:0):fault==4?93:(kind==1?30:-1),fault==5?0:b.CreateString(fault==6?std::string(513,'x'):"native carrier"),appearance);
    auto holder=fault==7?wire::CreateItemBuildingHolder(b,1,4,b.CreateString("farm")):flatbuffers::Offset<wire::ItemBuildingHolder>{};
    auto item=wire::CreateIndependentItemSnapshot(b,45,9007199254740993ULL,53,b.CreateString("seed"),b.CreateString(""),b.CreateString(""),false,false,false,false,true,false,false,false,b.CreateString(""),b.CreateString(""),holder,0,-1,carrier);
    auto independent=wire::CreateIndependentItemState(b,item);wire::ProductionStateBuilder p(b);p.add_independent_item(independent);auto payload=p.Finish();
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_production(payload);state.add_action(wire::ManagementAction::ProductionInspect);state.add_status(wire::ManagementStatus::Ok);b.Finish(state.Finish());
    auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(fault!=0));
    if(!fault){auto decoded=codec::decodeProduction(value->production());const auto& snapshot=*decoded.independentItem->snapshot;REQUIRE(snapshot.carrier);CHECK(snapshot.carrier->kind==kind);CHECK(snapshot.carrier->id==988);CHECK(snapshot.carrier->name=="native carrier");CHECK(snapshot.carrier->appearance.has_value()==(kind==1));if(kind==1)CHECK(snapshot.carrier->appearance->materialToken=="WOOD");}
  }
}

TEST_CASE("independent BOX appearance is required coherent and decoded") {
  for(int fault=0;fault<7;++fault) {
    CAPTURE(fault);flatbuffers::FlatBufferBuilder b;
    auto look=wire::CreateItemInspectionAppearance(b,b.CreateString(fault==2?"STONE":"WOOD"),b.CreateString(fault==3?"mismatch":""),b.CreateString(fault==6?std::string(129,'x'):"RED"),fault==4?0:2,fault==5?1:32);
    auto item=wire::CreateIndependentItemSnapshot(b,45,9007199254740993ULL,30,b.CreateString("chest"),b.CreateString("WOOD"),b.CreateString(""),false,false,false,false,true,false,false,false,b.CreateString("weight"),b.CreateString("description"),0,0,-1,0,fault==1?0:look);
    auto independent=wire::CreateIndependentItemState(b,item);wire::ProductionStateBuilder p(b);p.add_independent_item(independent);auto payload=p.Finish();
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_production(payload);state.add_action(wire::ManagementAction::ProductionInspect);state.add_status(wire::ManagementStatus::Ok);b.Finish(state.Finish());
    auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());CHECK(bool(wire::validateManagementState(*value))==(fault!=0));
    if(!fault){auto decoded=codec::decodeProduction(value->production());const auto& snapshot=*decoded.independentItem->snapshot;REQUIRE(snapshot.appearance);CHECK(snapshot.appearance->colorToken=="RED");CHECK(snapshot.appearance->stack==2);CHECK(snapshot.appearance->flags==32);}
  }
}

TEST_CASE("instrument inspection requires paired definition facts") {
  for(int family=-1;family<=4;++family)for(int placed=-1;placed<=2;++placed) {
    flatbuffers::FlatBufferBuilder b;
    auto look=wire::CreateItemInspectionAppearance(b,b.CreateString("WOOD"),b.CreateString("INSTRUMENT"),b.CreateString(""),1,0,family,placed);
    auto item=wire::CreateIndependentItemSnapshot(b,45,12,13,b.CreateString("instrument"),b.CreateString("WOOD"),b.CreateString("INSTRUMENT"),false,false,false,false,true,false,false,false,b.CreateString("weight"),b.CreateString("description"),0,0,-1,0,look);
    auto independent=wire::CreateIndependentItemState(b,item);wire::ProductionStateBuilder p(b);p.add_independent_item(independent);auto payload=p.Finish();
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_production(payload);state.add_action(wire::ManagementAction::ProductionInspect);state.add_status(wire::ManagementStatus::Ok);b.Finish(state.Finish());
    auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());const bool valid=family>=0&&family<=3&&placed>=0&&placed<=1;
    CHECK(bool(wire::validateManagementState(*value))!=valid);
    if(valid){auto decoded=codec::decodeProduction(value->production());const auto& a=*decoded.independentItem->snapshot->appearance;CHECK(a.instrumentFamily==family);CHECK(a.instrumentPlaced==placed);}
  }
}

TEST_CASE("building header requests preserve revisions and exclude unrelated intent") {
  for(bool edit:{false,true})for(int fault=0;fault<13;++fault) {
    CAPTURE(edit);CAPTURE(fault);wm::ManagementRequest r;
    r.action=edit?wm::ManagementAction::FarmEdit:wm::ManagementAction::ProductionInspect;
    auto& p=r.production;p.buildingHeader=true;p.buildingId=278;
    if(edit){p.farmOperation=wm::FarmOperation::Rename;p.farmName="name";p.expectedRevision=9007199254740993ULL;}
    if(fault==1)p.buildingId=-1;if(fault==2)p.independentItem=true;if(fault==3)p.contents=true;
    if(fault==4)p.locateItem=true;if(fault==5)p.season=0;if(fault==6)p.itemId=45;
    if(fault==7)p.expectedRevision=edit?0:1;if(fault==8)p.jobId=1;if(fault==9)p.cropId=1;
    if(fault==10)p.query="mixed";if(fault==11)r.action=wm::ManagementAction::ProductionList;
    if(fault==12){p.farmOperation=wm::FarmOperation::FertilizationToggle;p.farmName.clear();}
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(bool(wire::validateConstructionRequest(*value))==(fault!=0));
    if(!fault){CHECK(value->production()->building_header());if(edit)CHECK(value->production()->expected_revision()==9007199254740993ULL);}
  }
}
TEST_CASE("building header receipts preserve authority and reject malformed state") {
  for(int type:{0,1,2,5,8,10,11,12,13,14,15,51,52,54})for(bool edit:{false,true})for(int fault=0;fault<15;++fault) {
    CAPTURE(edit);CAPTURE(fault);flatbuffers::FlatBufferBuilder b;
    auto snapshot=wire::CreateBuildingHeaderSnapshot(b,fault==1?-1:278,fault==2?4:type,fault==3?0:9007199254740993ULL,
      fault==4?-1:1,1,b.CreateString("name"),b.CreateString("name"),fault==5?0:b.CreateString("Name"),false,fault==6,false,fault==13?-1:fault==14?2:1);
    auto header=wire::CreateBuildingHeaderState(b,fault==7?0:snapshot,
      edit?(fault==8?wire::FarmEditOutcome::Unknown:wire::FarmEditOutcome::Completed):(fault==8?wire::FarmEditOutcome::Completed:wire::FarmEditOutcome::None),
      fault==9?wire::FarmOperation::Remove:edit?wire::FarmOperation::Rename:wire::FarmOperation::Crop);
    wire::ProductionStateBuilder prod(b);prod.add_building_header(header);if(fault==10)prod.add_selected_building(278);
    auto payload=prod.Finish();wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_production(payload);
    state.add_action(fault==11?wire::ManagementAction::ProductionList:edit?wire::ManagementAction::FarmEdit:wire::ManagementAction::ProductionInspect);
    state.add_status(fault==12?wire::ManagementStatus::Rejected:wire::ManagementStatus::Ok);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(fault!=0));
    if(!fault){auto decoded=codec::decodeProduction(value->production());REQUIRE(decoded.buildingHeader);REQUIRE(decoded.buildingHeader->snapshot);
      CHECK(decoded.buildingHeader->snapshot->revision==9007199254740993ULL);CHECK(decoded.buildingHeader->snapshot->headerName=="Name");CHECK(decoded.buildingHeader->snapshot->forbidden==1);CHECK_FALSE(decoded.farm);}
  }
  for(auto outcome:{wire::FarmEditOutcome::Rejected,wire::FarmEditOutcome::Stale,wire::FarmEditOutcome::Unknown}) {
    flatbuffers::FlatBufferBuilder b;auto header=wire::CreateBuildingHeaderState(b,0,outcome);
    wire::ProductionStateBuilder prod(b);prod.add_building_header(header);auto payload=prod.Finish();
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_production(payload);state.add_action(wire::ManagementAction::FarmEdit);state.add_status(wire::ManagementStatus::Rejected);
    b.Finish(state.Finish());CHECK_FALSE(wire::validateManagementState(*flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer())));
  }
}

TEST_CASE("missing building identity is confirmed read authority only") {
  for(int id:{0,220})for(int fault=0;fault<8;++fault) {
    CAPTURE(id);CAPTURE(fault);flatbuffers::FlatBufferBuilder b;
    auto snapshot=wire::CreateBuildingHeaderSnapshot(b,220,10,1,1,1,
      b.CreateString(""),b.CreateString("native"),b.CreateString("Native"),false,false,false,0);
    auto header=wire::CreateBuildingHeaderState(b,fault==1?snapshot:0,
      fault==2?wire::FarmEditOutcome::Rejected:wire::FarmEditOutcome::None,
      fault==3?wire::FarmOperation::Remove:wire::FarmOperation::Crop,fault==4?-2:id);
    wire::ProductionStateBuilder prod(b);prod.add_building_header(header);auto payload=prod.Finish();
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_production(payload);
    state.add_action(fault==5?wire::ManagementAction::FarmEdit:wire::ManagementAction::ProductionInspect);
    state.add_status(fault==6?wire::ManagementStatus::Rejected:wire::ManagementStatus::Ok);
    if(fault==7)state.add_schema_version(224);
    b.Finish(state.Finish());const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(fault!=0));
    if(!fault){const auto decoded=codec::decodeProduction(value->production());REQUIRE(decoded.buildingHeader);
      CHECK(decoded.buildingHeader->missingBuildingId==id);CHECK_FALSE(decoded.buildingHeader->snapshot);}
  }
}

TEST_CASE("funerary bodies retain native facts and reject mixed identities") {
  for(int type:{3,46})for(int fault=0;fault<10;++fault) {
    flatbuffers::FlatBufferBuilder b;
    const auto empty=b.CreateString("");const bool coffin=type==3;
    std::vector<flatbuffers::Offset<flatbuffers::String>> notices;
    if(fault==6)for(int i=0;i<4;++i)notices.push_back(b.CreateString("notice"));
    const auto body=wire::CreateFuneraryBodySnapshot(b,fault==3?-2:fault==8?5577:-1,
      fault==4?17:coffin?-1:9636,coffin?228:-1,coffin?97:-1,
      coffin?empty:b.CreateString("This is a memorial to"),coffin?empty:b.CreateString("Ber"),
      coffin?b.CreateString("This furniture is a part of"):empty,
      fault==5?b.CreateString(std::string(1537,'x')):coffin?b.CreateString("Unnamed tomb"):empty,
      fault==9?b.CreateString("Deceased"):empty,fault==7?0:b.CreateVector(notices));
    const auto snapshot=wire::CreateBuildingHeaderSnapshot(b,220,fault==1?15:type,1,1,1,
      empty,b.CreateString("native"),b.CreateString("Native"),false,false,false,0,0,fault==2?0:body);
    auto header=wire::CreateBuildingHeaderState(b,snapshot);
    wire::ProductionStateBuilder prod(b);prod.add_building_header(header);auto payload=prod.Finish();
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(wire::ManagementAction::ProductionInspect);
    state.add_status(wire::ManagementStatus::Ok);state.add_production(payload);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    // A different valid memorial subject is permitted; coffin cannot carry it.
    const bool valid=fault==0 || (fault==4 && !coffin);
    CHECK(bool(wire::validateManagementState(*value))==!valid);
    if(valid) {
      const auto decoded=codec::decodeProduction(value->production());
      REQUIRE(decoded.buildingHeader);REQUIRE(decoded.buildingHeader->snapshot);
      REQUIRE(decoded.buildingHeader->snapshot->funerary);
      const auto& v=*decoded.buildingHeader->snapshot->funerary;
      CHECK(v.roomId==(coffin?228:-1));CHECK(v.name==(coffin?"":"Ber"));
      CHECK(v.historicalFigureId==(coffin?-1:fault==4?17:9636));CHECK(v.notices.empty());
      CHECK_FALSE(v.ownerAppearance);
    }
  }
}

TEST_CASE("creature header command retains exact revision and strict read/edit separation") {
  for(bool edit:{false,true})for(int fault=0;fault<5;++fault) {
    wm::ManagementRequest r;r.action=edit?wm::ManagementAction::CreatureHeaderEdit:wm::ManagementAction::CreatureHeaderRead;
    r.creatureHeader={86,false,edit?9007199254740993ULL:0,""};
    if(fault==1)r.creatureHeader.unitId=-1;
    if(fault==2)r.creatureHeader.expectedRevision=edit?0:1;
    if(fault==3)r.creatureHeader.name=edit?std::string(91,'X'):"unexpected";
    if(fault==4){if(edit)r.creatureHeader.name=std::string("x\0y",3);else r.creatureHeader.profession=true;}
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(bool(wire::validateConstructionRequest(*value))==(fault!=0));
    REQUIRE(value->creature_header());CHECK(value->creature_header()->expected_revision()==r.creatureHeader.expectedRevision);
  }
}
TEST_CASE("creature locate transports only confirmed bounded positions") {
  for(int id:{-1,86}) {
    wm::ManagementRequest r;r.action=wm::ManagementAction::CreatureLocate;r.creatureUnitId=id;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(bool(wire::validateConstructionRequest(*value))==(id<0));
    REQUIRE(value->creature());CHECK(value->creature()->unit_id()==id);CHECK_FALSE(value->creature_header());
  }
  for(int fault=0;fault<8;++fault) {
    flatbuffers::FlatBufferBuilder b;wire::TilePos tile(fault==1?-1:fault==2?32768:126,75,165);
    auto p=wire::CreateCreaturePosition(b,fault==3?-1:86,fault==4?nullptr:&tile);
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_world_epoch(7);
    state.add_action(fault==5?wire::ManagementAction::CreatureInspect:wire::ManagementAction::CreatureLocate);
    state.add_status(fault==6?wire::ManagementStatus::Rejected:wire::ManagementStatus::Ok);
    if(fault!=7)state.add_creature_position(p);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(fault!=0));
    if(!fault){const auto decoded=codec::decodeState(value);REQUIRE(decoded.creaturePosition);CHECK(decoded.creaturePosition->unitId==86);CHECK(decoded.creaturePosition->position.z==165);}
  }
  flatbuffers::FlatBufferBuilder b;wire::ManagementStateBuilder state(b);
  state.add_revision(1);state.add_action(wire::ManagementAction::CreatureLocate);state.add_status(wire::ManagementStatus::Rejected);
  b.Finish(state.Finish());CHECK_FALSE(wire::validateManagementState(*flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer())));
}
TEST_CASE("creature sheet locate has a separate identity and native sentinel rule") {
  wm::ManagementRequest request;request.action=wm::ManagementAction::CreatureSheetLocate;request.creatureUnitId=86;
  flatbuffers::FlatBufferBuilder encoded;codec::encodeRequest(encoded,request,1,2,3);
  const auto* wireRequest=flatbuffers::GetRoot<wire::ConstructionRequest>(encoded.GetBufferPointer());
  CHECK_FALSE(wire::validateConstructionRequest(*wireRequest));
  REQUIRE(wireRequest->creature());CHECK(wireRequest->creature()->unit_id()==86);
  CHECK(wireRequest->schema_version()==wire::kManagementVersion);
  for(int x:{126,-1,-30000,32768}) {
    flatbuffers::FlatBufferBuilder b;const wire::TilePos tile(x,75,165);
    const auto position=wire::CreateCreaturePosition(b,86,&tile);
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_action(wire::ManagementAction::CreatureSheetLocate);
    state.add_status(wire::ManagementStatus::Ok);state.add_creature_position(position);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(x==-30000 || x==32768));
    if(x==126){const auto decoded=codec::decodeState(value);REQUIRE(decoded.creaturePosition);CHECK(decoded.creaturePosition->unitId==86);}
  }
}
TEST_CASE("creature header result requires confirmed bounded authority") {
  for(int fault=0;fault<7;++fault) {
    flatbuffers::FlatBufferBuilder b;
    auto snapshot=wire::CreateCreatureHeaderSnapshot(b,86,102,true,9007199254740993ULL,b.CreateString("Nick"),b.CreateString(fault==1?std::string(1537,'X'):"Miner"),b.CreateString("Nick"));
    auto result=wire::CreateCreatureHeaderState(b,fault==2?wire::CreatureHeaderOutcome::Unknown:wire::CreatureHeaderOutcome::Completed,true,fault==3?0:snapshot);
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_world_epoch(7);
    state.add_action(fault==4?wire::ManagementAction::CreatureHeaderRead:fault==5?wire::ManagementAction::Catalog:wire::ManagementAction::CreatureHeaderEdit);
    state.add_status(fault==6?wire::ManagementStatus::Rejected:wire::ManagementStatus::Ok);state.add_creature_header(result);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(fault!=0));
    if(!fault){auto decoded=codec::decodeState(value);REQUIRE(decoded.creatureHeader);REQUIRE(decoded.creatureHeader->snapshot);CHECK(decoded.creatureHeader->snapshot->revision==9007199254740993ULL);CHECK(decoded.creatureHeader->snapshot->nickname=="Nick");}
  }
}

TEST_CASE("creature expel requests require an exact ordered selected group") {
  for(bool apply:{false,true})for(int fault=0;fault<7;++fault) {
    CAPTURE(apply);CAPTURE(fault);
    wm::ManagementRequest r;r.action=apply?wm::ManagementAction::CreatureExpelApply:wm::ManagementAction::CreatureExpelRead;
    r.creatureExpel={86,-1,apply?std::vector<int32_t>{86,102}:std::vector<int32_t>{}};
    if(fault==1)r.creatureExpel.unitId=-1;
    if(fault==2)r.creatureExpel.destinationId=apply?-2:1;
    if(fault==3)r.creatureExpel.expectedUnitIds={102};
    if(fault==4)r.creatureExpel.expectedUnitIds={86,86};
    if(fault==5)r.creatureExpel.expectedUnitIds={102,86};
    if(fault==6)r.creatureExpel.expectedUnitIds={-1,86};
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(bool(wire::validateConstructionRequest(*value))==(fault!=0));
    REQUIRE(value->creature_expel());CHECK(value->creature_expel()->unit_id()==r.creatureExpel.unitId);
  }
}
TEST_CASE("creature expel preview rejects malformed authority and decodes native rows") {
  for(int fault=0;fault<12;++fault) {
    CAPTURE(fault);flatbuffers::FlatBufferBuilder b;
    std::vector<flatbuffers::Offset<flatbuffers::String>> names{b.CreateString("PAGE")},palettes;
    std::vector<wire::AppearanceLayer> layers;
    auto icon=wire::CreateSelectionAppearance(b,b.CreateVector(names),b.CreateVector(palettes),b.CreateVectorOfStructs(layers));
    auto color=wire::CreateAreaNameColor(b,fault==1?8:7,0,1,7,0,1,0);
    auto row=wire::CreateCreatureExpelUnit(b,fault==2?-1:86,b.CreateString(fault==3?std::string(1537,'x'):"Urist"),color,icon);
    std::vector<flatbuffers::Offset<wire::CreatureExpelUnit>> units{row};if(fault==4)units.push_back(row);
    std::vector<flatbuffers::Offset<wire::CreatureExpelDestination>> sites;
    sites.push_back(wire::CreateCreatureExpelDestination(b,-1,b.CreateString(fault==5?"bad":"")));
    sites.push_back(wire::CreateCreatureExpelDestination(b,8,b.CreateString("Site")));
    auto preview=wire::CreateCreatureExpelPreview(b,86,fault!=6,fault==7?11:-1,b.CreateVector(units),b.CreateVector(sites));
    auto result=wire::CreateCreatureExpelState(b,fault==8?wire::CreatureExpelOutcome::Applied:wire::CreatureExpelOutcome::Ready,fault==9?0:preview);
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_world_epoch(7);
    state.add_action(fault==10?wire::ManagementAction::CreatureExpelApply:wire::ManagementAction::CreatureExpelRead);
    state.add_status(fault==11?wire::ManagementStatus::Rejected:wire::ManagementStatus::Ok);state.add_creature_expel(result);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(fault!=0));
    if(!fault) {const auto decoded=codec::decodeState(value);REQUIRE(decoded.creatureExpel);REQUIRE(decoded.creatureExpel->preview);
      const auto& p=*decoded.creatureExpel->preview;CHECK(p.unitId==86);CHECK(p.units[0].name=="Urist");CHECK(p.units[0].sheetIcon.tilePages[0]=="PAGE");CHECK(p.destinations[1].id==8);}
  }
}
TEST_CASE("creature expel result outcomes cannot invent successful previews or replay authority") {
  for(bool read:{false,true})for(auto outcome:{wire::CreatureExpelOutcome::Rejected,wire::CreatureExpelOutcome::Ready,
      wire::CreatureExpelOutcome::Applied,wire::CreatureExpelOutcome::Unsupported,wire::CreatureExpelOutcome::Unknown}) {
    flatbuffers::FlatBufferBuilder b;auto result=wire::CreateCreatureExpelState(b,outcome);
    wire::ManagementStateBuilder state(b);state.add_revision(1);
    state.add_action(read?wire::ManagementAction::CreatureExpelRead:wire::ManagementAction::CreatureExpelApply);
    state.add_status(outcome==wire::CreatureExpelOutcome::Applied?wire::ManagementStatus::Ok:wire::ManagementStatus::Rejected);
    state.add_creature_expel(result);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    const bool invalid=outcome==wire::CreatureExpelOutcome::Ready || (read && (outcome==wire::CreatureExpelOutcome::Applied || outcome==wire::CreatureExpelOutcome::Unknown));
    CHECK(bool(wire::validateManagementState(*value))==invalid);
  }
}

TEST_CASE("independent item owner codec validates separate ownership") {
  for(int fault=0;fault<5;++fault) {
    CAPTURE(fault);flatbuffers::FlatBufferBuilder b;
    auto owner=wire::CreateItemOwner(b,fault==1?-1:988,fault==2?0:b.CreateString(fault==3?std::string(513,'x'):"native owner"));
    auto carrier=wire::CreateItemCarrier(b,2,1017,-1,b.CreateString("native carrier"));
    auto item=wire::CreateIndependentItemSnapshot(b,45,1,53,b.CreateString("seed"),b.CreateString(""),b.CreateString(""),false,false,false,false,true,false,false,false,b.CreateString(""),b.CreateString(""),0,0,-1,carrier,0,fault==4?0:owner);
    auto independent=wire::CreateIndependentItemState(b,item);wire::ProductionStateBuilder p(b);p.add_independent_item(independent);auto payload=p.Finish();
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_production(payload);state.add_action(wire::ManagementAction::ProductionInspect);state.add_status(wire::ManagementStatus::Ok);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(fault>0&&fault<4));
    if(fault==0||fault==4){auto decoded=codec::decodeProduction(value->production());const auto& snapshot=*decoded.independentItem->snapshot;REQUIRE(snapshot.carrier);CHECK(snapshot.carrier->id==1017);CHECK(snapshot.owner.has_value()==(fault==0));if(snapshot.owner){CHECK(snapshot.owner->id==988);CHECK(snapshot.owner->name=="native owner");}}
  }
}

TEST_CASE("knowledge requests retain complete native entry identity") {
  for(int kind=13;kind<=18;++kind)for(int fault=0;fault<3;++fault) {
    wm::ManagementRequest r;r.action=wm::ManagementAction::CreatureKnowledgeRead;
    r.creatureKnowledge={fault==1?-1:86,kind,fault==2?-1:42};
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(bool(wire::validateConstructionRequest(*value))==(kind<14 || kind>17 || fault!=0));
    REQUIRE(value->creature_knowledge());CHECK(value->creature_knowledge()->unit_id()==r.creatureKnowledge.unitId);
    CHECK(value->creature_knowledge()->kind()==kind);CHECK(value->creature_knowledge()->id()==r.creatureKnowledge.id);
    CHECK_FALSE(value->creature());CHECK_FALSE(value->creature_expel());
  }
  for(bool unrelated:{false,true}) {
    flatbuffers::FlatBufferBuilder b;auto k=wire::CreateCreatureKnowledgeRequest(b,86,14,42);
    wire::ConstructionRequestBuilder r(b);r.add_client_id(1);r.add_seq(2);r.add_world_epoch(3);
    r.add_action(unrelated?wire::ManagementAction::Catalog:wire::ManagementAction::CreatureKnowledgeRead);
    if(unrelated)r.add_creature_knowledge(k);
    b.Finish(r.Finish());
    CHECK(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer())).has_value());
  }
}
TEST_CASE("knowledge replies validate identity outcome and UTF8 byte bounds") {
  for(int fault=0;fault<12;++fault) {
    flatbuffers::FlatBufferBuilder b;
    std::string text=fault==1?std::string(65537,'x'):fault==2?std::string("x\0y",3):"[B]Native text";
    auto k=wire::CreateCreatureKnowledgeState(b,fault==3?-1:86,fault==4?13:fault==5?18:14,
      fault==6?-1:42,fault==7?wire::CreatureKnowledgeOutcome(255):wire::CreatureKnowledgeOutcome::Ready,b.CreateString(text));
    wire::ManagementStateBuilder s(b);s.add_revision(1);s.add_world_epoch(3);
    s.add_action(fault==8?wire::ManagementAction::CreatureLocate:wire::ManagementAction::CreatureKnowledgeRead);
    s.add_status(fault==9?wire::ManagementStatus::Rejected:fault==10?wire::ManagementStatus::Pending:wire::ManagementStatus::Ok);
    if(fault!=11)s.add_creature_knowledge(k);
    b.Finish(s.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(fault!=0));
    if(!fault){const auto out=codec::decodeState(value);REQUIRE(out.creatureKnowledge);
      CHECK(out.creatureKnowledge->unitId==86);CHECK(out.creatureKnowledge->kind==14);CHECK(out.creatureKnowledge->id==42);
      CHECK(out.creatureKnowledge->text==text);CHECK(out.creatureKnowledge->outcome==wm::CreatureKnowledgeOutcome::Ready);}
  }
  for(auto outcome:{wire::CreatureKnowledgeOutcome::Rejected,wire::CreatureKnowledgeOutcome::Unavailable})
  for(int fault=0;fault<3;++fault) {
    flatbuffers::FlatBufferBuilder b;
    auto k=wire::CreateCreatureKnowledgeState(b,86,17,42,outcome,b.CreateString(fault==1?"stale text":""));
    wire::ManagementStateBuilder s(b);s.add_revision(1);s.add_world_epoch(3);s.add_action(wire::ManagementAction::CreatureKnowledgeRead);
    s.add_status(fault==2?wire::ManagementStatus::Ok:wire::ManagementStatus::Rejected);s.add_creature_knowledge(k);b.Finish(s.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(fault!=0));
    if(!fault){const auto out=codec::decodeState(value);REQUIRE(out.creatureKnowledge);CHECK(out.creatureKnowledge->text.empty());}
  }
  for(size_t count:{size_t(32768),size_t(32769)}) {
    std::string text;for(size_t i=0;i<count;++i)text+="\xc3\xa9";
    flatbuffers::FlatBufferBuilder b;auto k=wire::CreateCreatureKnowledgeState(b,86,15,42,wire::CreatureKnowledgeOutcome::Ready,b.CreateString(text));
    wire::ManagementStateBuilder s(b);s.add_revision(1);s.add_world_epoch(3);s.add_action(wire::ManagementAction::CreatureKnowledgeRead);
    s.add_status(wire::ManagementStatus::Ok);s.add_creature_knowledge(k);b.Finish(s.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(count==32769));
    if(count==32768)CHECK(codec::decodeState(value).creatureKnowledge->text==text);
  }
}

TEST_CASE("workshop removal carries target and current membership revision") {
  wm::ManagementRequest request;request.action=wm::ManagementAction::CreatureWorkshopRemove;
  request.creatureWorkshop={1017,3,42};
  flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
  const auto* wireRequest=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
  CHECK_FALSE(wire::validateConstructionRequest(*wireRequest));
  REQUIRE(wireRequest->creature_workshop());
  CHECK(wireRequest->creature_workshop()->unit_id()==1017);
  CHECK(wireRequest->creature_workshop()->building_id()==3);
  CHECK(wireRequest->creature_workshop()->expected_revision()==42);
  request.creatureWorkshop.expectedRevision=0;b.Clear();codec::encodeRequest(b,request,1,2,3);
  CHECK(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer())));
}
TEST_CASE("workshop removal acknowledges application only with a successful envelope") {
  for(bool accepted:{false,true}) {
    flatbuffers::FlatBufferBuilder b;
    auto payload=wire::CreateCreatureWorkshopState(b,1017,3,wire::CreatureWorkshopOutcome::Applied);
    wire::ManagementStateBuilder result(b);result.add_revision(1);result.add_world_epoch(3);
    result.add_action(wire::ManagementAction::CreatureWorkshopRemove);
    result.add_status(accepted?wire::ManagementStatus::Ok:wire::ManagementStatus::Rejected);
    result.add_creature_workshop(payload);b.Finish(result.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==!accepted);
    if(accepted){const auto decoded=codec::decodeState(value);REQUIRE(decoded.creatureWorkshop);
      CHECK(decoded.creatureWorkshop->unitId==1017);CHECK(decoded.creatureWorkshop->buildingId==3);
      CHECK(decoded.creatureWorkshop->outcome==wm::CreatureWorkshopOutcome::Applied);}
  }
}

TEST_CASE("location removal carries target and current membership revision") {
  wm::ManagementRequest request;request.action=wm::ManagementAction::CreatureLocationRemove;
  request.creatureLocation={1017,3,42};
  flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
  const auto* wireRequest=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
  CHECK_FALSE(wire::validateConstructionRequest(*wireRequest));
  REQUIRE(wireRequest->creature_location());
  CHECK(wireRequest->creature_location()->unit_id()==1017);
  CHECK(wireRequest->creature_location()->occupation_id()==3);
  CHECK(wireRequest->creature_location()->expected_revision()==42);
  request.creatureLocation.expectedRevision=0;b.Clear();codec::encodeRequest(b,request,1,2,3);
  CHECK(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer())));
}
TEST_CASE("location removal acknowledges application only with a successful envelope") {
  for(bool accepted:{false,true}) {
    flatbuffers::FlatBufferBuilder b;
    auto payload=wire::CreateCreatureLocationState(b,1017,3,wire::CreatureLocationOutcome::Applied);
    wire::ManagementStateBuilder result(b);result.add_revision(1);result.add_world_epoch(3);
    result.add_action(wire::ManagementAction::CreatureLocationRemove);
    result.add_status(accepted?wire::ManagementStatus::Ok:wire::ManagementStatus::Rejected);
    result.add_creature_location(payload);b.Finish(result.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==!accepted);
    if(accepted){const auto decoded=codec::decodeState(value);REQUIRE(decoded.creatureLocation);
      CHECK(decoded.creatureLocation->unitId==1017);CHECK(decoded.creatureLocation->occupationId==3);
      CHECK(decoded.creatureLocation->outcome==wm::CreatureLocationOutcome::Applied);}
  }
}

TEST_CASE("work animal edit carries target and current membership revision") {
  wm::ManagementRequest request;request.action=wm::ManagementAction::CreatureAnimalEdit;
  request.creatureAnimal={1017,3,42,true};
  flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
  const auto* wireRequest=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
  CHECK_FALSE(wire::validateConstructionRequest(*wireRequest));
  REQUIRE(wireRequest->creature_animal());
  CHECK(wireRequest->creature_animal()->unit_id()==1017);
  CHECK(wireRequest->creature_animal()->animal_id()==3);
  CHECK(wireRequest->creature_animal()->expected_revision()==42);
  CHECK(wireRequest->creature_animal()->assigned());
  request.creatureAnimal.expectedRevision=0;b.Clear();codec::encodeRequest(b,request,1,2,3);
  CHECK(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer())));
}
TEST_CASE("work animal edit acknowledges application only with a successful envelope") {
  for(bool accepted:{false,true}) {
    flatbuffers::FlatBufferBuilder b;
    auto payload=wire::CreateCreatureAnimalState(b,1017,3,wire::CreatureAnimalOutcome::Applied,true);
    wire::ManagementStateBuilder result(b);result.add_revision(1);result.add_world_epoch(3);
    result.add_action(wire::ManagementAction::CreatureAnimalEdit);
    result.add_status(accepted?wire::ManagementStatus::Ok:wire::ManagementStatus::Rejected);
    result.add_creature_animal(payload);b.Finish(result.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==!accepted);
    if(accepted){const auto decoded=codec::decodeState(value);REQUIRE(decoded.creatureAnimal);
      CHECK(decoded.creatureAnimal->unitId==1017);CHECK(decoded.creatureAnimal->animalId==3);CHECK(decoded.creatureAnimal->assigned);
      CHECK(decoded.creatureAnimal->outcome==wm::CreatureAnimalOutcome::Applied);}
  }
}

TEST_CASE("native work order list observations preserve absence and supplied names") {
  for(bool observed:{false,true}) {
    flatbuffers::FlatBufferBuilder b;
    const auto name=b.CreateString("Assigned workshop");
    const auto code=b.CreateString("SOAP_MAKER");
    const auto native=wire::CreateWorkOrderNativeState(b,wire::WorkOrderPhase::Ready,true,true,observed?name:0);
    wire::WorkOrderInfoBuilder row(b);row.add_id(1);row.add_revision(1);row.add_native_state(native);
    const auto order=row.Finish();
    const auto group=wire::CreateWorkOrderGroup(b,0,23,0,0,1,observed?code:0);
    const auto orders=b.CreateVector(std::vector{order});
    const auto groups=b.CreateVector(std::vector{group});
    const auto list=observed?wire::CreateWorkOrderListNativeState(b,true,true):flatbuffers::Offset<wire::WorkOrderListNativeState>();
    wire::WorkOrderStateBuilder state(b);state.add_orders(orders);state.add_groups(groups);state.add_native_state(list);
    b.Finish(state.Finish());
    const auto decoded=codec::decodeWorkOrder(flatbuffers::GetRoot<wire::WorkOrderState>(b.GetBufferPointer()));
    CHECK(decoded.nativeState.has_value()==observed);
    REQUIRE(decoded.orders.size()==1);REQUIRE(decoded.orders[0].nativeState);
    CHECK(decoded.orders[0].nativeState->workshopName.has_value()==observed);
    REQUIRE(decoded.groups.size()==1);CHECK(decoded.groups[0].customCode.has_value()==observed);
    if(observed) {
      CHECK(decoded.nativeState->managerAvailable);CHECK(decoded.nativeState->validationRequired);
      CHECK(*decoded.orders[0].nativeState->workshopName=="Assigned workshop");
      CHECK(*decoded.groups[0].customCode=="SOAP_MAKER");
    }
  }
}

TEST_CASE("native Details choices preserve revisions and reject mixed edits") {
  wm::ManagementRequest request;request.action=wm::ManagementAction::WorkOrderUpdate;
  auto& w=request.workOrder;w.id=37;w.expectedRevision=9007199254740993ULL;
  w.details=wm::WorkOrderDetailsRequest{1,2,9007199254740995ULL,"",0};
  for(bool mixed:{false,true}) {
    w.remaining=mixed?10:-1;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(wire::validateConstructionRequest(*value).has_value()==mixed);
    REQUIRE(value->work_order()->details());
    CHECK(value->work_order()->expected_revision()==9007199254740993ULL);
    CHECK(value->work_order()->details()->expected_choices_revision()==9007199254740995ULL);
    CHECK(value->work_order()->details()->choice()==2);
  }
}
TEST_CASE("native Details decoding distinguishes unobserved and empty choices") {
  for(bool selected:{false,true}) {
    flatbuffers::FlatBufferBuilder b;
    const auto caption=b.CreateString("Specify glass");
    const auto option=wire::CreateWorkOrderDetailsOption(b,0,1,caption);
    const auto options=b.CreateVector(std::vector{option});
    flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<wire::WorkOrderDetailsChoice>>> choices;
    if(selected)choices=b.CreateVector(std::vector<flatbuffers::Offset<wire::WorkOrderDetailsChoice>>{});
    const auto details=wire::CreateWorkOrderDetailsState(b,37,1,caption,options,selected?0:-1,choices,selected?2:0,0,0,0,selected?caption:0);
    wire::WorkOrderStateBuilder state(b);state.add_details(details);b.Finish(state.Finish());
    const auto decoded=codec::decodeWorkOrder(flatbuffers::GetRoot<wire::WorkOrderState>(b.GetBufferPointer()));
    REQUIRE(decoded.details);CHECK(decoded.details->choices.has_value()==selected);
    CHECK(decoded.details->currentValue.has_value()==selected);
    if(selected)CHECK(*decoded.details->currentValue=="Specify glass");
    REQUIRE(decoded.details->options.size()==1);CHECK(decoded.details->options[0].index==1);
  }
}
TEST_CASE("dye Details carry native swatches and explicit filter history") {
  wm::ManagementRequest request;request.action=wm::ManagementAction::WorkOrderInspect;
  request.workOrder.id=37;request.workOrder.workshopId=-2;request.workOrder.expectedRevision=9;
  request.workOrder.details.emplace();auto& intent=*request.workOrder.details;
  intent.option=0;intent.dyeTarget=18;intent.dyeFilterApplied=true;
  flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
  const auto* encoded=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
  CHECK_FALSE(wire::validateConstructionRequest(*encoded));
  CHECK(encoded->work_order()->details()->dye_target()==18);
  CHECK(encoded->work_order()->details()->dye_filter_applied());
  b.Clear();
  const auto caption=b.CreateString("Tint cloth cerulean (opens menu)");
  const wire::WorkOrderDyeColor color(0.0f,0.5f,1.0f);
  const auto choice=wire::CreateWorkOrderDetailsChoice(b,1,caption,b.CreateString("At least 21 cloth/dye available"),false,18,true,&color);
  const auto choices=b.CreateVector(std::vector{choice});
  const auto options=b.CreateVector(std::vector{wire::CreateWorkOrderDetailsOption(b,4,191,b.CreateString("Specify color"))});
  const auto details=wire::CreateWorkOrderDetailsState(b,37,9,caption,options,0,choices,10,1,0,0,0,b.CreateString("Choose dye color"));
  wire::WorkOrderStateBuilder state(b);state.add_details(details);b.Finish(state.Finish());
  const auto decoded=codec::decodeWorkOrder(flatbuffers::GetRoot<wire::WorkOrderState>(b.GetBufferPointer()));
  REQUIRE(decoded.details);REQUIRE(decoded.details->choices);REQUIRE(decoded.details->choices->size()==1);
  const auto& row=decoded.details->choices->front();REQUIRE(row.swatch);
  CHECK(row.dyeColor==18);CHECK(row.opensMenu);CHECK(row.swatch->green==0.5f);
  CHECK(decoded.details->settingHeading=="Choose dye color");CHECK(decoded.details->dyeTarget==-1);
}
TEST_CASE("artwork retains simulation IDs and guards separate selection authority") {
  wm::ManagementRequest request;request.action=wm::ManagementAction::WorkOrderUpdate;
  auto& w=request.workOrder;w.id=37;w.workshopId=-2;w.expectedRevision=9007199254740993ULL;
  w.details.emplace();w.details->option=0;w.details->art=wm::WorkOrderArtRequest{1,200000,9007199254740995ULL,"name",0};
  for(bool mixed:{false,true}) {
    w.details->choice=mixed?2:-1;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(wire::validateConstructionRequest(*value).has_value()==mixed);
    REQUIRE(value->work_order()->details()->art());
    CHECK(value->work_order()->details()->art()->subject()==200000);
    CHECK(value->work_order()->details()->art()->expected_list_revision()==9007199254740995ULL);
  }
  flatbuffers::FlatBufferBuilder b;
  const auto caption=b.CreateString("Fixture artwork");
  const auto rows=b.CreateVector(std::vector{wire::CreateWorkOrderArtRow(b,200000,caption,caption)});
  const auto preview=b.CreateVector(std::vector{caption});
  const auto art=wire::CreateWorkOrderArtState(b,1,caption,rows,9007199254740995ULL,1,0,200000,preview);
  const auto options=b.CreateVector(std::vector{wire::CreateWorkOrderDetailsOption(b,1,0,caption)});
  const auto details=wire::CreateWorkOrderDetailsState(b,37,1,caption,options,0,0,0,0,0,art);
  wire::WorkOrderStateBuilder state(b);state.add_details(details);b.Finish(state.Finish());
  const auto decoded=codec::decodeWorkOrder(flatbuffers::GetRoot<wire::WorkOrderState>(b.GetBufferPointer()));
  REQUIRE(decoded.details);REQUIRE(decoded.details->art);CHECK_FALSE(decoded.details->choices);
  REQUIRE(decoded.details->art->rows.size()==1);CHECK(decoded.details->art->rows[0].id==200000);
  CHECK(decoded.details->art->listRevision==9007199254740995ULL);
  CHECK(decoded.details->art->hovered==200000);REQUIRE(decoded.details->art->preview);
  CHECK(decoded.details->art->preview->at(0)=="Fixture artwork");
  CHECK(decoded.details->art->rows[0].badge==std::optional<std::string>("Fixture artwork"));
}
TEST_CASE("artwork previews require read-only revision and width authority") {
  wm::ManagementRequest request;request.action=wm::ManagementAction::WorkOrderInspect;
  auto& w=request.workOrder;w.id=37;w.workshopId=-2;w.expectedRevision=1;
  w.details.emplace();w.details->option=0;w.details->art=wm::WorkOrderArtRequest{5,-1,2,"",0,0,118};
  const auto error=[&](){flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);return wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer()));};
  CHECK_FALSE(error());w.details->art->previewColumns=0;CHECK(error());
  w.details->art->previewColumns=118;request.action=wm::ManagementAction::WorkOrderUpdate;w.details->art->subject=0;CHECK(error());
}
TEST_CASE("artwork drafts preserve compound choices and separate world writes") {
  wm::ManagementRequest request;request.action=wm::ManagementAction::WorkOrderInspect;
  auto& w=request.workOrder;w.id=37;w.workshopId=-2;w.expectedRevision=9007199254740993ULL;
  w.details.emplace();w.details->option=0;w.details->art.emplace();auto& art=*w.details->art;
  art.page=6;art.draft.emplace();auto& draft=*art.draft;draft.columns=118;
  draft.value.elements={{7,42,-1,1},{7,42,1,0}};
  draft.value.relationships={{3,true,0,1}};
  const auto error=[&](){
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    const auto* encoded=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    const auto* value=encoded->work_order()->details()->art()->draft()->value();
    CHECK(value->elements()->Get(1)->secondary()==1);
    CHECK(value->elements()->Get(1)->quantity()==0);
    CHECK(value->relationships()->Get(0)->target()==draft.value.relationships[0].target);
    return wire::validateConstructionRequest(*encoded);
  };
  CHECK_FALSE(error());
  draft.value.relationships[0].target=0;CHECK(error());
  draft.value.relationships[0].target=1;
  draft.action=wm::WorkOrderArtDraftAction::GenerateName;CHECK(error());
  request.action=wm::ManagementAction::WorkOrderUpdate;CHECK_FALSE(error());
  draft.action=wm::WorkOrderArtDraftAction::Commit;CHECK(error()); // A name has not been observed.
  draft.value.name.emplace();auto& name=*draft.value.name;
  name.words.assign(7,-1);name.parts.assign(7,0);name.type=11;
  CHECK_FALSE(error());
  name.parts.pop_back();CHECK(error());
  name.parts.push_back(0);
  art.page=18;draft.action=wm::WorkOrderArtDraftAction::EditName;
  draft.nameQuery=wm::LocationNameQuery{2,{'A'},0};
  draft.nameEdit=wm::LocationNameEdit{wm::LocationNameMode::SelectWord,2,2,42,2,{'A'}};
  CHECK(error()); // Selecting a component is local; randomization advances DF RNG.
  request.action=wm::ManagementAction::WorkOrderInspect;CHECK_FALSE(error());
  draft.nameEdit->mode=wm::LocationNameMode::RandomComponent;draft.nameEdit->word=-1;draft.nameEdit->part=-1;
  CHECK(error());request.action=wm::ManagementAction::WorkOrderUpdate;CHECK_FALSE(error());
  draft.nameQuery->cursor=128;CHECK(error());
}

TEST_CASE("Residents activity requests retain event identity and bounded width") {
  wm::ManagementRequest request;request.action=wm::ManagementAction::ResidentsActivityRead;
  request.residentsActivity={7049,50298,8,110};
  for(int fault=0;fault<6;++fault) {
    auto r=request;
    if(fault==1)r.residentsActivity.unitId=-1;
    if(fault==2)r.residentsActivity.activityId=-1;
    if(fault==3)r.residentsActivity.eventId=-1;
    if(fault==4)r.residentsActivity.columns=0;
    if(fault==5)r.residentsActivity.columns=1025;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(bool(wire::validateConstructionRequest(*value))==(fault!=0));
    REQUIRE(value->residents_activity());CHECK(value->residents_activity()->event_id()==r.residentsActivity.eventId);
  }
  CHECK(std::string(wm::managementDomain(request.action))=="residents_activity");
}
TEST_CASE("Job settings read preserves simulation identity and bounds") {
  wm::ManagementRequest request;request.action=wm::ManagementAction::JobSettingsRead;
  request.jobSettings={42,3,6534,0,"stone",0};
  for(int fault=0;fault<7;++fault) {
    auto r=request;
    if(fault==1)r.jobSettings.jobId=-1;
    if(fault==2)r.jobSettings.buildingId=-1;
    if(fault==3)r.jobSettings.unitId=-2;
    if(fault==4)r.jobSettings.option=65;
    if(fault==5)r.jobSettings.query=std::string(129,'x');
    if(fault==6)r.jobSettings.cursor=16385;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,r,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(bool(wire::validateConstructionRequest(*value))==(fault!=0));
    REQUIRE(value->job_settings());CHECK(value->job_settings()->unit_id()==r.jobSettings.unitId);
  }
  CHECK(std::string(wm::managementDomain(request.action))=="job_settings");
}
TEST_CASE("Job settings rejects foreign replies and inconsistent pagination") {
  for(int fault=0;fault<7;++fault) {
    flatbuffers::FlatBufferBuilder b;
    const auto option=wire::CreateWorkOrderDetailsOption(b,0,0,b.CreateString("Specify stone"));
    const auto choice=wire::CreateJobSettingsChoice(b,7,b.CreateString("Dolomite"),b.CreateString("200?"),true);
    const auto options=b.CreateVector(std::vector<flatbuffers::Offset<wire::WorkOrderDetailsOption>>{option});
    const auto choices=b.CreateVector(std::vector<flatbuffers::Offset<wire::JobSettingsChoice>>{choice});
    const auto page=wire::CreateJobSettingsState(b,42,3,6534,fault==1?0:91,b.CreateString("Make rock door"),options,0,choices,92,2,0,fault==2?0:1);
    wire::ManagementStateBuilder state(b);state.add_revision(1);
    state.add_action(fault==3?wire::ManagementAction::Catalog:wire::ManagementAction::JobSettingsRead);
    state.add_status(fault==4?wire::ManagementStatus::Rejected:fault==6?wire::ManagementStatus::Pending:wire::ManagementStatus::Ok);
    if(fault!=5)state.add_job_settings(page);
    b.Finish(state.Finish());const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(fault!=0));
    if(!fault){const auto decoded=codec::decodeState(value);REQUIRE(decoded.jobSettings);CHECK(decoded.jobSettings->choices[0].countCaption=="200?");CHECK(decoded.jobSettings->choices[0].estimated);CHECK(decoded.jobSettings->nextCursor==1);}
  }
  flatbuffers::FlatBufferBuilder b;wire::ManagementStateBuilder state(b);state.add_revision(2);state.add_action(wire::ManagementAction::JobSettingsRead);state.add_status(wire::ManagementStatus::Rejected);b.Finish(state.Finish());
  const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
  CHECK_FALSE(wire::validateManagementState(*value));CHECK_FALSE(codec::decodeState(value).jobSettings);
}
TEST_CASE("Residents activity markup rejects malformed or foreign results") {
  for(int fault=0;fault<9;++fault) {
    flatbuffers::FlatBufferBuilder b;
    const auto word=wire::CreateActivityDescriptionWord(b,b.CreateString(fault==1?std::string(131073,'x'):"Play"),18,254,207,fault==2?0:-1,fault==3?8:0,0,fault==4?3:0);
    const auto words=b.CreateVector(std::vector<flatbuffers::Offset<wire::ActivityDescriptionWord>>{word});
    const auto links=b.CreateVector(std::vector<flatbuffers::Offset<wire::ActivityDescriptionLink>>{});
    const auto description=wire::CreateResidentsActivityState(b,7049,50298,8,fault==5?0:110,2,words,links);
    wire::ManagementStateBuilder state(b);state.add_revision(1);
    state.add_action(fault==6?wire::ManagementAction::ResidentsRowsRead:wire::ManagementAction::ResidentsActivityRead);
    state.add_status(fault==7?wire::ManagementStatus::Rejected:wire::ManagementStatus::Ok);
    if(fault!=8)state.add_residents_activity(description);
    b.Finish(state.Finish());const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(fault!=0));
    if(fault==0){auto decoded=codec::decodeState(value);REQUIRE(decoded.residentsActivity);CHECK(decoded.residentsActivity->words[0].green==254);CHECK(decoded.residentsActivity->columns==110);CHECK(decoded.residentsActivity->eventId==8);}
  }
  flatbuffers::FlatBufferBuilder b;wire::ManagementStateBuilder state(b);state.add_revision(2);state.add_action(wire::ManagementAction::ResidentsActivityRead);state.add_status(wire::ManagementStatus::Rejected);b.Finish(state.Finish());
  const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
  CHECK_FALSE(wire::validateManagementState(*value));CHECK_FALSE(codec::decodeState(value).residentsActivity);
}

TEST_CASE("Work Details settings requests preserve authority and isolate toggles") {
  for(bool toggle:{false,true})for(int fault=0;fault<6;++fault) {
    wm::ManagementRequest request;request.action=toggle?wm::ManagementAction::WorkDetailSettingsToggle:wm::ManagementAction::WorkDetailSettingsRead;
    request.workDetailSettings={7,UINT64_C(9007199254740993),toggle?-2:-1};
    if(fault==1)request.workDetailSettings.detailIndex=128;
    if(fault==2)request.workDetailSettings.expectedRevision=0;
    if(fault==3)request.workDetailSettings.expectedRevision=uint64_t(INT64_MAX)+1;
    if(fault==4)request.workDetailSettings.settingId=toggle?-1:11;
    if(fault==5)request.workDetailSettings.settingId=94;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(bool(wire::validateConstructionRequest(*value))==(fault!=0));
    if(!fault)CHECK(value->work_detail_settings()->expected_revision()==UINT64_C(9007199254740993));
  }
}
TEST_CASE("Work Details settings reject partial catalogs and retire foreign results") {
  for(int fault=0;fault<9;++fault) {
    flatbuffers::FlatBufferBuilder b;std::vector<flatbuffers::Offset<wire::WorkDetailSetting>> entries;
    for(int id=-13;id<=-2;++id)entries.push_back(wire::CreateWorkDetailSetting(b,id,b.CreateString("Synthetic group")));
    for(int id=1;id<=79;++id)entries.push_back(wire::CreateWorkDetailSetting(b,fault==1 && id==79?1:id,b.CreateString(fault==2?"":"Synthetic labor")));
    if(fault==3)entries.pop_back();
    const auto settings=wire::CreateWorkDetailSettingsState(b,7,fault==4?0:UINT64_C(9007199254740993),true,false,
      b.CreateVector(std::vector<int16_t>{11,int16_t(fault==5?11:59)}),b.CreateVector(entries));
    wire::ManagementStateBuilder state(b);state.add_revision(1);
    state.add_action(fault==6?wire::ManagementAction::ResidentsQuery:wire::ManagementAction::WorkDetailSettingsRead);
    state.add_status(fault==7?wire::ManagementStatus::Rejected:wire::ManagementStatus::Ok);
    if(fault!=8)state.add_work_detail_settings(settings);
    b.Finish(state.Finish());const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(fault!=0));
    if(!fault){const auto decoded=codec::decodeState(value);REQUIRE(decoded.workDetailSettings);
      CHECK(decoded.workDetailSettings->revision==UINT64_C(9007199254740993));CHECK(decoded.workDetailSettings->catalog.size()==91);}
  }
  flatbuffers::FlatBufferBuilder b;wire::ManagementStateBuilder state(b);state.add_revision(2);
  state.add_action(wire::ManagementAction::WorkDetailSettingsToggle);state.add_status(wire::ManagementStatus::Rejected);b.Finish(state.Finish());
  const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
  CHECK_FALSE(wire::validateManagementState(*value));CHECK_FALSE(codec::decodeState(value).workDetailSettings);
}

TEST_CASE("Standing orders requests preserve expected values and reject invalid domains") {
  for(bool set:{false,true})for(int fault=0;fault<5;++fault){
    wm::ManagementRequest request;request.action=set?wm::ManagementAction::StandingOrdersSet:wm::ManagementAction::StandingOrdersRead;
    if(set)request.standingOrders={0,1,0,1};
    if(fault==1)request.standingOrders.category=5;
    if(fault==2)request.standingOrders.settingId=11;
    if(fault==3)request.standingOrders.expectedValue=2;
    if(fault==4)request.standingOrders.value=2;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    const auto* wireRequest=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(bool(wire::validateConstructionRequest(*wireRequest))==(fault!=0));
    if(!fault){REQUIRE(wireRequest->standing_orders());CHECK(wireRequest->standing_orders()->expected_value()==(set?0:-1));}
  }
}
TEST_CASE("Standing orders replies retire authority on uncertain writes") {
  for(bool unknown:{false,true})for(int fault=0;fault<5;++fault){
    flatbuffers::FlatBufferBuilder b;std::vector<flatbuffers::Offset<wire::StandingOrderSetting>> rows;
    if(!unknown || fault==1)for(int id=0;id<(fault==2?10:11);++id)rows.push_back(wire::CreateStandingOrderSetting(b,id,fault==3?3:0,id<8,id<8));
    auto outcome=unknown?wire::StandingOrdersOutcome::Unknown:wire::StandingOrdersOutcome::Applied;
    const auto standing=wire::CreateStandingOrdersState(b,fault==4?5:0,outcome,b.CreateVector(rows));
    wire::ManagementStateBuilder state(b);state.add_revision(2);state.add_standing_orders(standing);
    state.add_action(unknown && (fault==2 || fault==3)?wire::ManagementAction::StandingOrdersRead:wire::ManagementAction::StandingOrdersSet);
    state.add_status(unknown?wire::ManagementStatus::Rejected:wire::ManagementStatus::Ok);
    b.Finish(state.Finish());const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    const bool invalid=fault!=0 && (unknown || fault!=1);
    CHECK(bool(wire::validateManagementState(*value))==invalid);
    if(!invalid){auto decoded=codec::decodeState(value);REQUIRE(decoded.standingOrders);CHECK(decoded.standingOrders->settings.size()==(unknown?0:11));}
  }
}

TEST_CASE("Hunter ammunition edits retain full expected assignments and typed intent") {
  for(int operation=1;operation<=5;++operation)for(int fault=0;fault<3;++fault){
    wm::ManagementRequest request;request.action=wm::ManagementAction::HunterAmmunitionApply;
    auto& q=request.hunterAmmunition;q.operation=wm::HunterAmmunitionOperation(operation);
    q.expected.push_back({39,0,-1,-1,-1,100,3,{13119,27744}});q.index=0;
    if(operation==1)q.amount=125;
    if(operation==2)q.materialClass=3;
    if(operation==3){q.index=-1;q.itemType=39;q.itemSubtype=0;}
    if(operation==5)q.itemId=13119;
    if(fault==1)q.expected.front().assigned={27744,13119};
    if(fault==2)q.amount=5001;
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(bool(wire::validateConstructionRequest(*value))==(fault!=0));
    if(!fault){REQUIRE(value->hunter_ammunition());CHECK(value->hunter_ammunition()->expected()->Get(0)->assigned()->Get(1)==27744);}
  }
  for(auto action:{wm::ManagementAction::HunterAmmunitionRead,wm::ManagementAction::HunterAmmunitionCandidates}){
    wm::ManagementRequest request;request.action=action;
    if(action==wm::ManagementAction::HunterAmmunitionCandidates){request.hunterAmmunition.itemType=39;request.hunterAmmunition.itemSubtype=0;}
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK_FALSE(wire::validateConstructionRequest(*value));CHECK_FALSE(value->hunter_ammunition()->expected());
  }
}
TEST_CASE("Hunter ammunition read quantities agree with assigned stack receipts") {
  for(int fault=0;fault<6;++fault){
    flatbuffers::FlatBufferBuilder b;
    const auto spec=wire::CreateHunterAmmunitionSpec(b,39,0,-1,-1,-1,100,3,b.CreateVector(std::vector<int32_t>{13119}));
    const auto appearance=wire::CreateItemInspectionAppearance(b,b.CreateString(fault==3?"":"INORGANIC:SILVER"),b.CreateString("ITEM_AMMO_BOLTS"),b.CreateString(""),fault==4?31:30,fault==5?1:0);
    const auto item=wire::CreateHunterAmmunitionStack(b,fault==2?27744:13119,b.CreateString("fixture stack"),30,appearance);
    const auto rule=wire::CreateHunterAmmunitionRule(b,b.CreateString("fixture bolts"),fault==1?31:30,b.CreateVector(std::vector{item}));
    const auto hunter=wire::CreateHunterAmmunitionState(b,wire::HunterAmmunitionOutcome::None,-1,-1,
      b.CreateVector(std::vector{spec}),b.CreateVector(std::vector{rule}),
      b.CreateVector(std::vector<flatbuffers::Offset<wire::HunterAmmunitionType>>{}),b.CreateVector(std::vector<flatbuffers::Offset<wire::HunterAmmunitionMaterial>>{}));
    wire::ManagementStateBuilder state(b);state.add_revision(2);state.add_action(wire::ManagementAction::HunterAmmunitionRead);
    state.add_status(wire::ManagementStatus::Ok);state.add_hunter_ammunition(hunter);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(fault!=0));
    if(!fault){const auto decoded=codec::decodeState(value);REQUIRE(decoded.hunterAmmunition);CHECK(decoded.hunterAmmunition->rules.front().quantity==30);CHECK(decoded.hunterAmmunition->rules.front().items.front().appearance.materialToken=="INORGANIC:SILVER");}
  }
}

TEST_CASE("Stone use validates complete receipts and read-only requests") {
  for(bool apply:{false,true})for(int fault=0;fault<4;++fault){
    wm::ManagementRequest request;request.action=apply?wm::ManagementAction::StoneUseApply:wm::ManagementAction::StoneUseRead;
    auto& q=request.stoneUse;
    if(apply){q.category=0;q.index=1;q.expected=std::vector<uint8_t>{0,1,0};
      if(fault==1)q.expected.reset();if(fault==2)(*q.expected)[0]=2;if(fault==3)q.index=3;
    }else{if(fault==1)q.category=0;if(fault==2)q.index=0;if(fault==3)q.expected.emplace();}
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(bool(wire::validateConstructionRequest(*value))==(fault!=0));
    if(!fault){REQUIRE(value->stone_use());if(apply)CHECK(value->stone_use()->expected()->Get(1)==1);}
  }
}
TEST_CASE("Stone use rejects contradictory rows and uncertain authority") {
  for(bool unknown:{false,true})for(int fault=0;fault<4;++fault){
    flatbuffers::FlatBufferBuilder b;std::vector<flatbuffers::Offset<wire::StoneUseRow>> rows;std::vector<uint8_t> flags;
    if(!unknown || fault==1){flags={0,1,0};rows.push_back(wire::CreateStoneUseRow(b,0,1,fault!=2,b.CreateString("fixture stone"),b.CreateString("fixture use"),true,b.CreateString("INORGANIC:FIXTURE")));
      if(fault==1 && !unknown)rows.push_back(rows.front());if(fault==3)flags[0]=2;}
    const auto stone=wire::CreateStoneUseState(b,unknown?wire::StoneUseOutcome::Unknown:wire::StoneUseOutcome::None,b.CreateVector(rows),b.CreateVector(flags));
    wire::ManagementStateBuilder state(b);state.add_revision(2);state.add_stone_use(stone);
    state.add_action(unknown && fault!=2?wire::ManagementAction::StoneUseApply:wire::ManagementAction::StoneUseRead);
    state.add_status(unknown?wire::ManagementStatus::Rejected:wire::ManagementStatus::Ok);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    const bool invalid=unknown?(fault==1 || fault==2):(fault!=0);
    CHECK(bool(wire::validateManagementState(*value))==invalid);
    if(!invalid){const auto decoded=codec::decodeState(value);REQUIRE(decoded.stoneUse);
      CHECK(decoded.stoneUse->rows.size()==(unknown?0:1));if(!unknown){CHECK(decoded.stoneUse->rows[0].magmaSafe);CHECK(decoded.stoneUse->restrictions==flags);}}
  }
}
TEST_CASE("Kitchen queries and edits preserve independent owned receipts") {
  for(bool apply:{false,true})for(int fault=0;fault<5;++fault){
    wm::ManagementRequest request;request.action=apply?wm::ManagementAction::KitchenApply:wm::ManagementAction::KitchenRead;
    auto& q=request.kitchenMenu;
    if(apply){q.target=wm::KitchenFoodReceipt{{54,-1,419,0},12,3};q.permission=1;q.expected.emplace();
      q.expected->push_back({{53,-1,419,0},1});q.expected->push_back({{54,-1,419,0},2});
      if(fault==1)q.expected.reset();
      if(fault==2)q.query.emplace();
      if(fault==3)q.permission=3;
      if(fault==4)q.target->capabilities=2;
    }else{q.query.emplace();q.query->query="plump";q.query->sorts={{wm::KitchenSortColumn::Name,true},{wm::KitchenSortColumn::Number,false}};
      if(fault==1)q.query->sorts.push_back({wm::KitchenSortColumn::Name,false});
      if(fault==2)q.expected.emplace();
      if(fault==3)q.query->typeFilter=4;
      if(fault==4)q.query->sorts.clear();}
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(bool(wire::validateConstructionRequest(*value))==(fault!=0));
    if(!fault){REQUIRE(value->kitchen_menu());const auto* v=value->kitchen_menu();
      if(apply){CHECK(v->expected()->Get(0)->key()->item_type()==53);CHECK(v->expected()->Get(1)->flags()==2);CHECK(v->target()->count()==12);}
      else{CHECK(v->query()->query()->str()=="plump");CHECK(v->query()->sorts()->Get(0)->reverse());}}
  }
}
TEST_CASE("Kitchen priorities preserve repeats and bound request allocation") {
  wm::ManagementRequest request;request.action=wm::ManagementAction::KitchenRead;request.kitchenMenu.query.emplace();
  auto& sorts=request.kitchenMenu.query->sorts;sorts.clear();
  for(int i=0;i<8;++i)sorts.push_back({i%2?wm::KitchenSortColumn::Number:wm::KitchenSortColumn::Name,i%2==0});
  flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
  const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
  REQUIRE_FALSE(wire::validateConstructionRequest(*value));REQUIRE(value->kitchen_menu()->query()->sorts()->size()==8);
  for(unsigned i=0;i<8;++i){const auto* sort=value->kitchen_menu()->query()->sorts()->Get(i);CHECK(unsigned(sort->column())==unsigned(sorts[i].column));CHECK(sort->reverse()==sorts[i].reverse);}
  sorts.resize(65537,{wm::KitchenSortColumn::Name,true});b.Clear();codec::encodeRequest(b,request,1,2,3);
  CHECK(wire::validateConstructionRequest(*flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer())));
}
TEST_CASE("Kitchen unknown outcomes cannot publish authoritative rows") {
  for(bool unknown:{false,true})for(int fault=0;fault<3;++fault){
    flatbuffers::FlatBufferBuilder b;std::vector<flatbuffers::Offset<wire::KitchenMenuRow>> rows;
    if(!unknown || fault==1){const auto key=wire::CreateKitchenFoodKey(b,54,-1,419,0);const auto receipt=wire::CreateKitchenFoodReceipt(b,key,12,3);
      rows.push_back(wire::CreateKitchenMenuRow(b,receipt,b.CreateString("fixture food"),b.CreateString("12?"),true,2,b.CreateString("PLANT_MAT:MUSHROOM_HELMET_PLUMP:STRUCTURAL")));}
    const auto kitchen=wire::CreateKitchenMenuState(b,unknown?wire::KitchenMenuOutcome::Unknown:wire::KitchenMenuOutcome::None,
      b.CreateVector(rows),b.CreateVector(std::vector<flatbuffers::Offset<wire::KitchenExclusion>>{}));
    wire::ManagementStateBuilder state(b);state.add_revision(2);state.add_kitchen_menu(kitchen);
    state.add_action(unknown && fault!=2?wire::ManagementAction::KitchenApply:wire::ManagementAction::KitchenRead);
    state.add_status(unknown?wire::ManagementStatus::Rejected:wire::ManagementStatus::Ok);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    const bool invalid=unknown && fault!=0;CHECK(bool(wire::validateManagementState(*value))==invalid);
    if(!invalid){const auto decoded=codec::decodeState(value);REQUIRE(decoded.kitchenMenu);CHECK(decoded.kitchenMenu->rows.size()==(unknown?0:1));
      if(!unknown){CHECK(decoded.kitchenMenu->rows[0].receipt.count==12);CHECK(decoded.kitchenMenu->rows[0].countCaption=="12?");}}
  }
}
TEST_CASE("Chores requests carry full ordered receipts and validate targets") {
  for(int operation=0;operation<=3;++operation)for(int fault=0;fault<5;++fault){
    wm::ManagementRequest request;request.action=operation?wm::ManagementAction::ChoresApply:wm::ManagementAction::ChoresRead;
    auto& q=request.chores;q.operation=wm::ChoresOperation(operation);
    if(operation || fault==1){q.expected.emplace();q.expected->enabled=true;q.expected->children={42,7};q.expected->exempted={7};
      for(int id:{23,37,1,2,6,3,4,5,7,8,74,77,9,75})q.expected->labors.push_back({id,true});}
    q.id=operation==2?23:operation==3?42:-1;q.value=operation!=0;
    if(fault==1 && operation)q.expected.reset();
    if(fault==2)q.id=999;
    if(fault==3){if(operation)q.expected->children={42,42};else q.value=true;}
    if(fault==4){if(operation)q.expected->labors.front().id=0;else q.operation=wm::ChoresOperation::Enabled;}
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(bool(wire::validateConstructionRequest(*value))==(fault!=0));
    if(!fault){REQUIRE(value->chores());CHECK(bool(value->chores()->expected())==(operation!=0));}
  }
}
TEST_CASE("Chores unknown outcomes carry no authoritative state") {
  for(bool unknown:{false,true})for(int fault=0;fault<3;++fault){
    flatbuffers::FlatBufferBuilder b;flatbuffers::Offset<wire::ChoresSnapshot> snap;
    if(!unknown || fault==1){std::vector<flatbuffers::Offset<wire::ChoreLabor>> rows;
      for(int id:{23,37,1,2,6,3,4,5,7,8,74,77,9,75})rows.push_back(wire::CreateChoreLabor(b,id,true));
      snap=wire::CreateChoresSnapshot(b,true,b.CreateVector(std::vector<int32_t>{42}),b.CreateVector(std::vector<int32_t>{}),b.CreateVector(rows));}
    const auto empty=b.CreateVector(std::vector<flatbuffers::Offset<wire::ChoresCaption>>{});
    const auto chores=wire::CreateChoresState(b,unknown?wire::ChoresOutcome::Unknown:wire::ChoresOutcome::Applied,snap,empty,empty);
    wire::ManagementStateBuilder state(b);state.add_revision(2);state.add_chores(chores);
    state.add_action(fault==2?wire::ManagementAction::ChoresRead:wire::ManagementAction::ChoresApply);
    state.add_status(unknown?wire::ManagementStatus::Rejected:wire::ManagementStatus::Ok);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    const bool invalid=fault==2 || (unknown && fault==1);CHECK(bool(wire::validateManagementState(*value))==invalid);
    if(!invalid){const auto decoded=codec::decodeState(value);REQUIRE(decoded.chores);CHECK(bool(decoded.chores->snapshot)==!unknown);}
  }
}
TEST_CASE("Stocks requests distinguish reads from guarded group intents") {
  for(int mode=0;mode<3;++mode)for(int fault=0;fault<7;++fault){
    const bool apply=mode!=0;
    wm::ManagementRequest request;request.action=mode==2?wm::ManagementAction::StocksItemApply:apply?wm::ManagementAction::StocksGroupApply:wm::ManagementAction::StocksMenuRead;
    auto& q=request.stocksMenu;q.category=39;if(mode==2)q.itemId=17;if(fault==6)q.itemId=mode==2?-1:17;
    if(apply){q.target=wm::StocksGroupKey{39,0,0,0};q.expectedRevision=77;q.operation=wm::StocksFlagAction::Hidden;q.value=1;}
    else {q.query="iron";q.itemIds={42,17};}
    if(fault==1)q.category=93;
    if(fault==2){if(apply)q.expectedRevision=0;else q.itemIds={42,42};}
    if(fault==3){if(apply)q.target->type=0;else q.expectedRevision=77;}
    if(fault==4){if(apply)q.itemIds={42};else q.itemIds.resize(65,42);}
    if(fault==5){if(apply)q.value=2;else q.target=wm::StocksGroupKey{39,0,0,0};}
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);
    const auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(bool(wire::validateConstructionRequest(*value))==(fault!=0));
    if(!fault){REQUIRE(value->stocks_menu());CHECK(value->stocks_menu()->category()==39);CHECK(value->stocks_menu()->expected_revision()==(apply?77:0));}
  }
}
TEST_CASE("Stocks groups own unique membership and item rows belong to the selection") {
  for(int fault=0;fault<10;++fault){
    flatbuffers::FlatBufferBuilder b;
    std::vector<flatbuffers::Offset<wire::StocksCategoryRow>> categories;
    for(int i=0;i<93;++i)categories.push_back(wire::CreateStocksCategoryRow(b,int16_t(fault==1?0:i),b.CreateString("category"),b.CreateString("None"),b.CreateString(""),true));
    auto key=wire::CreateStocksGroupKey(b,39,0,0,0);
    auto group=wire::CreateStocksGroupRow(b,key,3,b.CreateString("group [3]"),true,true,240,fault==2?0:77,b.CreateVector(std::vector<int32_t>{42,17}));
    std::vector<flatbuffers::Offset<wire::StocksGroupRow>> groups{group};
    if(fault==3)groups.push_back(wire::CreateStocksGroupRow(b,wire::CreateStocksGroupKey(b,39,1,0,0),1,b.CreateString("other"),true,true,240,78,b.CreateVector(std::vector<int32_t>{42})));
    const auto appearance=wire::CreateItemInspectionAppearance(b,b.CreateString(fault==8?"INORGANIC:COPPER":"INORGANIC:IRON"),b.CreateString(""),b.CreateString("color"),fault==6?0:27,fault==7?1:32,fault==9?0:-1);
    const auto item=wire::CreateStocksItemRow(b,fault==4?99:17,39,b.CreateString("item"),0,true,true,b.CreateString("INORGANIC:IRON"),b.CreateString(""),appearance);
    const auto data=wire::CreateStocksMenuState(b,wire::StocksMenuOutcome::None,fault==5?-1:39,b.CreateVector(categories),b.CreateVector(groups),b.CreateVector(std::vector<flatbuffers::Offset<wire::StocksItemRow>>{item}));
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_world_epoch(3);state.add_action(wire::ManagementAction::StocksMenuRead);state.add_status(wire::ManagementStatus::Ok);state.add_stocks_menu(data);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());CHECK(bool(wire::validateManagementState(*value))==(fault!=0));
    if(!fault){const auto decoded=codec::decodeState(value);REQUIRE(decoded.stocksMenu);CHECK(decoded.stocksMenu->groups[0].itemIds==std::vector<int32_t>{42,17});CHECK(decoded.stocksMenu->items[0].id==17);REQUIRE(decoded.stocksMenu->items[0].appearance);CHECK(decoded.stocksMenu->items[0].appearance->stack==27);CHECK(decoded.stocksMenu->items[0].appearance->flags==32);CHECK(decoded.stocksMenu->items[0].appearance->colorToken=="color");CHECK(decoded.stocksMenu->groups[0].revision==77);}
  }
}

TEST_CASE("item ammunition assignment distinguishes absent facts and observed allocation") {
  for(int mode=0;mode<4;++mode)for(int fault=0;fault<5;++fault) {
    flatbuffers::FlatBufferBuilder b;
    auto assignment=wire::CreateItemAmmunitionAssignment(b,fault==2?3:mode==3?0:mode,fault==3?7:mode==2?120:-1,b.CreateString(fault==4?std::string(1025,'x'):mode==0||mode==3?"":"native assignment"));
    auto item=wire::CreateIndependentItemSnapshot(b,45,1,fault==1?53:39,b.CreateString("item"),b.CreateString(""),b.CreateString(""),false,false,false,false,true,false,false,false,b.CreateString(""),b.CreateString(""),0,0,-1,0,0,0,mode==3?0:assignment);
    auto independent=wire::CreateIndependentItemState(b,item);wire::ProductionStateBuilder p(b);p.add_independent_item(independent);auto payload=p.Finish();
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_production(payload);state.add_action(wire::ManagementAction::ProductionInspect);state.add_status(wire::ManagementStatus::Ok);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    const bool invalid=mode!=3 && fault!=0 && !(fault==3 && mode==2);
    CHECK(bool(wire::validateManagementState(*value))==invalid);
    if(!invalid){auto decoded=codec::decodeProduction(value->production());const auto& observed=decoded.independentItem->snapshot->ammunitionAssignment;CHECK(observed.has_value()==(mode!=3));if(observed){CHECK(observed->kind==mode);CHECK(observed->squadId==(mode==2?(fault==3?7:120):-1));}}
  }
}

TEST_CASE("carrier contents preserve absence and ordered complete facts") {
  for(int mode=0;mode<3;++mode)for(int fault=0;fault<5;++fault) {
    flatbuffers::FlatBufferBuilder b;
    std::vector<flatbuffers::Offset<wire::ItemContainerContentFacts>> entries;
    if(mode==2){entries.push_back(wire::CreateItemContainerContentFacts(b,fault==2?93:39,b.CreateString("INORGANIC:COPPER"),b.CreateString(fault==3?std::string(129,'x'):"COPPER"),0,true));
      entries.push_back(wire::CreateItemContainerContentFacts(b,-1,b.CreateString(""),b.CreateString("")));}
    auto contents=wire::CreateItemContainerContentsFacts(b,mode==2 && fault!=4,b.CreateVector(entries));
    auto appearance=wire::CreateItemInspectionAppearance(b,b.CreateString("PLANT:OAK:WOOD"),b.CreateString(""),b.CreateString("BROWN"),1,0,-1,-1,mode?contents:0);
    auto carrier=wire::CreateItemCarrier(b,1,7,fault==1?17:32,b.CreateString("container"),appearance);
    auto item=wire::CreateIndependentItemSnapshot(b,45,1,39,b.CreateString("item"),b.CreateString(""),b.CreateString(""),false,false,false,false,true,false,false,false,b.CreateString(""),b.CreateString(""),0,0,-1,carrier);
    auto independent=wire::CreateIndependentItemState(b,item);wire::ProductionStateBuilder p(b);p.add_independent_item(independent);auto payload=p.Finish();
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_production(payload);state.add_action(wire::ManagementAction::ProductionInspect);state.add_status(wire::ManagementStatus::Ok);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    const bool invalid=(mode && fault==1) || (mode==2 && fault>=2);
    CHECK(bool(wire::validateManagementState(*value))==invalid);
    if(!invalid){auto decoded=codec::decodeProduction(value->production());const auto& facts=decoded.independentItem->snapshot->carrier->appearance->contents;
      CHECK(facts.has_value()==bool(mode));if(facts){CHECK(facts->container==(mode==2));CHECK(facts->entries.size()==(mode==2?2:0));
        if(mode==2){CHECK(facts->entries[0].colorToken=="COPPER");CHECK(facts->entries[0].metal);CHECK(facts->entries[1].itemType==-1);}}}
  }
}

TEST_CASE("grate appearance preserves paired native orientation and open facts") {
  for(int type:{79,7})for(int wall:{-1,0,1,2})for(int open:{-1,0,1,2}) {
    flatbuffers::FlatBufferBuilder b;const auto material=b.CreateString("INORGANIC:DOLOMITE"),empty=b.CreateString("");
    wire::ItemInspectionAppearanceBuilder appearance(b);appearance.add_material_token(material);appearance.add_subtype_raw(empty);
    appearance.add_color_token(empty);appearance.add_stack(1);appearance.add_grate_wall(int8_t(wall));appearance.add_grate_open(int8_t(open));
    auto look=appearance.Finish();auto carrier=wire::CreateItemCarrier(b,1,7,type,b.CreateString("container"),look);
    auto item=wire::CreateIndependentItemSnapshot(b,45,1,39,b.CreateString("item"),empty,empty,false,false,false,false,true,false,false,false,empty,empty,0,0,-1,carrier);
    auto independent=wire::CreateIndependentItemState(b,item);wire::ProductionStateBuilder p(b);p.add_independent_item(independent);auto payload=p.Finish();
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_production(payload);state.add_action(wire::ManagementAction::ProductionInspect);state.add_status(wire::ManagementStatus::Ok);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    const bool valid=(wall==-1 && open==-1) || (type==79 && wall>=0 && wall<=1 && open>=0 && open<=1);
    CHECK(bool(wire::validateManagementState(*value))==!valid);
    if(valid){const auto a=codec::decodeProduction(value->production()).independentItem->snapshot->carrier->appearance;
      CHECK(a->grateWall==wall);CHECK(a->grateOpen==open);}
  }
}

TEST_CASE("floodgate appearance preserves unknown and linked open state") {
  for(int type:{7,6})for(int open:{-2,-1,0,1,2}) {
    flatbuffers::FlatBufferBuilder b;
    auto appearance=wire::CreateItemInspectionAppearance(b,b.CreateString("INORGANIC:DOLOMITE"),b.CreateString(""),b.CreateString(""),1,0,-1,-1,0,int8_t(open));
    auto carrier=wire::CreateItemCarrier(b,1,7,type,b.CreateString("container"),appearance);
    auto item=wire::CreateIndependentItemSnapshot(b,45,1,39,b.CreateString("item"),b.CreateString(""),b.CreateString(""),false,false,false,false,true,false,false,false,b.CreateString(""),b.CreateString(""),0,0,-1,carrier);
    auto independent=wire::CreateIndependentItemState(b,item);wire::ProductionStateBuilder p(b);p.add_independent_item(independent);auto payload=p.Finish();
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_production(payload);state.add_action(wire::ManagementAction::ProductionInspect);state.add_status(wire::ManagementStatus::Ok);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    const bool invalid=open < -1 || open>1 || (type!=7 && open!=-1);
    CHECK(bool(wire::validateManagementState(*value))==invalid);
    if(!invalid)CHECK(codec::decodeProduction(value->production()).independentItem->snapshot->carrier->appearance->floodgateOpen==open);
  }
}

TEST_CASE("door appearance requires complete typed facts and preserves absence") {
  for(int type:{6,7})for(int open:{-1,0,1,2})for(int forbidden:{-1,0,1,2})for(int wear:{-1,0,1,2,3,4}) {
    flatbuffers::FlatBufferBuilder b;
    auto appearance=wire::CreateItemInspectionAppearance(b,b.CreateString("INORGANIC:DOLOMITE"),b.CreateString(""),b.CreateString(""),1,0,-1,-1,0,-1,int8_t(open),int8_t(forbidden),int8_t(wear));
    auto carrier=wire::CreateItemCarrier(b,1,7,type,b.CreateString("container"),appearance);
    auto item=wire::CreateIndependentItemSnapshot(b,45,1,39,b.CreateString("item"),b.CreateString(""),b.CreateString(""),false,false,false,false,true,false,false,false,b.CreateString(""),b.CreateString(""),0,0,-1,carrier);
    auto independent=wire::CreateIndependentItemState(b,item);wire::ProductionStateBuilder p(b);p.add_independent_item(independent);auto payload=p.Finish();
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_production(payload);state.add_action(wire::ManagementAction::ProductionInspect);state.add_status(wire::ManagementStatus::Ok);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    const bool unknown=open==-1 && forbidden==-1 && wear==-1;
    const bool valid=unknown || (type==6 && open>=0 && open<=1 && forbidden>=0 && forbidden<=1 && wear>=0 && wear<=3);
    CHECK(bool(wire::validateManagementState(*value))==!valid);
    if(valid){const auto facts=*codec::decodeProduction(value->production()).independentItem->snapshot->carrier->appearance;CHECK(facts.doorOpen==open);CHECK(facts.doorForbidden==forbidden);CHECK(facts.doorWear==wear);}
  }
}

TEST_CASE("bucket liquid appearance preserves unknown empty and uncolored liquid") {
  for(int type:{18,32})for(int present:{-2,-1,0,1,2})for(const std::string color:std::vector<std::string>{"", "BLUE", std::string(129,'x')}) {
    flatbuffers::FlatBufferBuilder b;
    auto appearance=wire::CreateItemInspectionAppearance(b,b.CreateString("PLANT:OAK:WOOD"),b.CreateString(""),b.CreateString(""),1,0,-1,-1,0,-1,-1,-1,-1,int8_t(present),b.CreateString(color));
    auto carrier=wire::CreateItemCarrier(b,1,7,type,b.CreateString("container"),appearance);
    auto item=wire::CreateIndependentItemSnapshot(b,45,1,39,b.CreateString("item"),b.CreateString(""),b.CreateString(""),false,false,false,false,true,false,false,false,b.CreateString(""),b.CreateString(""),0,0,-1,carrier);
    auto independent=wire::CreateIndependentItemState(b,item);wire::ProductionStateBuilder p(b);p.add_independent_item(independent);auto payload=p.Finish();
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_production(payload);state.add_action(wire::ManagementAction::ProductionInspect);state.add_status(wire::ManagementStatus::Ok);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    const bool valid=present>=-1 && present<=1 && (type==18 || present==-1) && color.size()<=128 && (present==1 || color.empty());
    CHECK(bool(wire::validateManagementState(*value))==!valid);
    if(valid){const auto facts=*codec::decodeProduction(value->production()).independentItem->snapshot->carrier->appearance;CHECK(facts.bucketLiquid==present);CHECK(facts.bucketLiquidColor==color);}
  }
}

TEST_CASE("item contents preserve unknown empty and mixed ordered observations") {
  for(int mode=0;mode<3;++mode)for(int fault=0;fault<(mode==2?5:1);++fault) {
    flatbuffers::FlatBufferBuilder b;
    auto look=wire::CreateItemInspectionAppearance(b,b.CreateString("INORGANIC:IRON"),b.CreateString(""),b.CreateString(""),1,0);
    auto child=wire::CreateItemSheetContent(b,1,fault==1?-1:71,b.CreateString("bar"),0,0x1000000,true,true,fault==2?0:look);
    auto unit=wire::CreateItemSheetContent(b,fault==3?3:2,72,b.CreateString("creature"),-1,0,false,false,fault==4?look:0);
    std::vector<flatbuffers::Offset<wire::ItemSheetContent>> entries;
    if(mode==2)entries={child,unit,child};
    auto rows=b.CreateVector(entries);
    auto item=wire::CreateIndependentItemSnapshot(b,45,1,53,b.CreateString("seed"),b.CreateString(""),b.CreateString(""),false,false,false,false,true,false,false,false,b.CreateString(""),b.CreateString(""),0,0,-1,0,0,0,0,mode==0?0:rows);
    auto independent=wire::CreateIndependentItemState(b,item);wire::ProductionStateBuilder p(b);p.add_independent_item(independent);auto payload=p.Finish();
    wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_production(payload);state.add_action(wire::ManagementAction::ProductionInspect);state.add_status(wire::ManagementStatus::Ok);b.Finish(state.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*value))==(fault!=0));
    if(fault)continue;
    const auto decoded=codec::decodeProduction(value->production());const auto& contents=decoded.independentItem->snapshot->contents;
    CHECK(contents.has_value()==(mode!=0));
    if(mode==1)CHECK(contents->empty());
    if(mode==2){REQUIRE(contents->size()==3);CHECK((*contents)[0].id==71);CHECK((*contents)[1].kind==2);CHECK((*contents)[1].id==72);CHECK((*contents)[2].id==71);CHECK((*contents)[0].flags==0x1000000);REQUIRE((*contents)[0].appearance);CHECK((*contents)[0].appearance->materialToken=="INORGANIC:IRON");CHECK_FALSE((*contents)[1].appearance);}
  }
}

TEST_CASE("contained item intent keeps parent identity and exact revision") {
  for(int fault=0;fault<5;++fault){wm::ManagementRequest request;request.action=wm::ManagementAction::FarmEdit;
    auto& p=request.production;p.independentItem=true;p.itemId=45;p.contentsItemId=71;p.farmOperation=wm::FarmOperation::ItemHidden;p.itemValue=1;p.expectedRevision=9007199254740993ULL;
    if(fault==1)p.contentsItemId=-2;if(fault==2)p.contentsItemId=45;
    if(fault==3){request.action=wm::ManagementAction::ProductionInspect;p.farmOperation=wm::FarmOperation::Crop;p.itemValue=-1;p.expectedRevision=0;}
    if(fault==4){p.independentItem=false;p.buildingId=227;}
    flatbuffers::FlatBufferBuilder b;codec::encodeRequest(b,request,1,2,3);auto* value=flatbuffers::GetRoot<wire::ConstructionRequest>(b.GetBufferPointer());
    CHECK(bool(wire::validateConstructionRequest(*value))==(fault!=0));
    if(!fault){CHECK(value->production()->item_id()==45);CHECK(value->production()->contents_item_id()==71);CHECK(value->production()->expected_revision()==9007199254740993ULL);}
  }
}

TEST_CASE("cage appearance preserves unknown empty and selected occupant") {
 for(int mode=0;mode<10;++mode) {
  flatbuffers::FlatBufferBuilder b;int family=mode==0?-1:0,entity=mode==0?-1:mode==1?0:1,id=mode<2?-1:6960,type=16;std::string color=mode==0?"":"COPPER";
  if(mode==3)entity=2;if(mode==4)family=3;if(mode==5)entity=3;if(mode==6)id=-1;if(mode==7)type=32;if(mode==8)color=std::string(129,'x');if(mode==9)family=-1;
  auto appearance=wire::CreateItemInspectionAppearance(b,b.CreateString("INORGANIC:COPPER"),b.CreateString(""),b.CreateString(""),1,0,-1,-1,0,-1,-1,-1,-1,-1,0,int8_t(family),int8_t(entity),id,b.CreateString(color));
  auto carrier=wire::CreateItemCarrier(b,1,7,type,b.CreateString("container"),appearance);
  auto item=wire::CreateIndependentItemSnapshot(b,45,1,39,b.CreateString("item"),b.CreateString(""),b.CreateString(""),false,false,false,false,true,false,false,false,b.CreateString(""),b.CreateString(""),0,0,-1,carrier);
  auto independent=wire::CreateIndependentItemState(b,item);wire::ProductionStateBuilder p(b);p.add_independent_item(independent);auto payload=p.Finish();
  wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_production(payload);state.add_action(wire::ManagementAction::ProductionInspect);state.add_status(wire::ManagementStatus::Ok);b.Finish(state.Finish());
  const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());CHECK(bool(wire::validateManagementState(*value))==(mode>=4));
  if(mode<4){const auto facts=*codec::decodeProduction(value->production()).independentItem->snapshot->carrier->appearance;CHECK(facts.cageMaterialFamily==family);CHECK(facts.cageOccupantEntity==entity);CHECK(facts.cageOccupantId==id);CHECK(facts.cageSolidColor==color);}
 }
}

TEST_CASE("restraint appearance preserves native material classification") {
 for(int mode=0;mode<7;++mode) {
  flatbuffers::FlatBufferBuilder b;int rope=mode==0?-1:mode==1?0:1,type=10;std::string color=mode==0?"":"SILVER";
  if(mode==3)rope=2;if(mode==4)type=16;if(mode==5)color=std::string(129,'x');if(mode==6)rope=-1;
  auto appearance=wire::CreateItemInspectionAppearance(b,b.CreateString("INORGANIC:SILVER"),b.CreateString(""),b.CreateString(""),1,0,-1,-1,0,-1,-1,-1,-1,-1,0,-1,-1,-1,0,int8_t(rope),b.CreateString(color));
  auto carrier=wire::CreateItemCarrier(b,1,7,type,b.CreateString("container"),appearance);
  auto item=wire::CreateIndependentItemSnapshot(b,45,1,39,b.CreateString("item"),b.CreateString(""),b.CreateString(""),false,false,false,false,true,false,false,false,b.CreateString(""),b.CreateString(""),0,0,-1,carrier);
  auto independent=wire::CreateIndependentItemState(b,item);wire::ProductionStateBuilder p(b);p.add_independent_item(independent);auto payload=p.Finish();
  wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_production(payload);state.add_action(wire::ManagementAction::ProductionInspect);state.add_status(wire::ManagementStatus::Ok);b.Finish(state.Finish());
  const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());CHECK(bool(wire::validateManagementState(*value))==(mode>=3));
  if(mode<3){const auto facts=*codec::decodeProduction(value->production()).independentItem->snapshot->carrier->appearance;CHECK(facts.restraintRope==rope);CHECK(facts.restraintSolidColor==color);}
 }
}

TEST_CASE("item Uses preserves absent empty ordered rows and rejects malformed facts") {
 for(int mode=0;mode<6;++mode){
  flatbuffers::FlatBufferBuilder b;
  std::vector<flatbuffers::Offset<wire::ItemUseRow>> rows;
  if(mode>=2){rows.push_back(wire::CreateItemUseRow(b,b.CreateString(mode==4?std::string(16385,'x'):"Making furniture"),-1));
    rows.push_back(wire::CreateItemUseRow(b,b.CreateString("Native reaction"),mode==3?-2:84));}
  if(mode==5)rows.resize(4097,rows.front());
  auto uses=mode==0?flatbuffers::Offset<flatbuffers::Vector<flatbuffers::Offset<wire::ItemUseRow>>>{}:b.CreateVector(rows);
  auto name=b.CreateString("item"),empty=b.CreateString("");
  wire::IndependentItemSnapshotBuilder item(b);item.add_id(45);item.add_revision(1);item.add_item_type(0);
  item.add_name(name);item.add_material_token(empty);item.add_subtype_raw(empty);item.add_weight(empty);item.add_description(empty);item.add_uses(uses);
  auto independent=wire::CreateIndependentItemState(b,item.Finish());wire::ProductionStateBuilder p(b);p.add_independent_item(independent);auto payload=p.Finish();
  wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_production(payload);state.add_action(wire::ManagementAction::ProductionInspect);state.add_status(wire::ManagementStatus::Ok);b.Finish(state.Finish());
  const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());CHECK(bool(wire::validateManagementState(*value))==(mode>=3));
  if(mode<3){const auto decoded=*codec::decodeProduction(value->production()).independentItem->snapshot;
    CHECK(decoded.uses.has_value()==(mode!=0));if(mode==1)CHECK(decoded.uses->empty());
    if(mode==2){REQUIRE(decoded.uses->size()==2);CHECK(decoded.uses->at(0).reaction==-1);CHECK(decoded.uses->at(1).caption=="Native reaction");CHECK(decoded.uses->at(1).reaction==84);}}
 }
}

TEST_CASE("barrel contents codec preserves material and liquid facts and validates family bounds") {
 for(int mode=0;mode<7;++mode) {
  flatbuffers::FlatBufferBuilder b;
  const auto entry=wire::CreateItemContainerContentFacts(b,69,b.CreateString(""),b.CreateString("AMBER"),0,false,false,false,false,false,false,true,true);
  std::vector<flatbuffers::Offset<wire::ItemContainerContentFacts>> entries;
  if(mode!=0)entries.push_back(entry);if(mode==6)entries.push_back(entry);
  const auto contents=wire::CreateItemContainerContentsFacts(b,mode!=3,b.CreateVector(entries),mode==4?-1:1,b.CreateString(mode==5?std::string(129,'x'):"COPPER"));
  auto appearance=wire::CreateItemInspectionAppearance(b,b.CreateString("INORGANIC:COPPER"),b.CreateString(""),b.CreateString(""),1,0,-1,-1,contents);
  auto carrier=wire::CreateItemCarrier(b,1,7,mode==2?31:17,b.CreateString("container"),appearance);
  auto item=wire::CreateIndependentItemSnapshot(b,45,1,39,b.CreateString("item"),b.CreateString(""),b.CreateString(""),false,false,false,false,true,false,false,false,b.CreateString(""),b.CreateString(""),0,0,-1,carrier);
  auto independent=wire::CreateIndependentItemState(b,item);wire::ProductionStateBuilder p(b);p.add_independent_item(independent);auto payload=p.Finish();
  wire::ManagementStateBuilder state(b);state.add_revision(1);state.add_production(payload);state.add_action(wire::ManagementAction::ProductionInspect);state.add_status(wire::ManagementStatus::Ok);b.Finish(state.Finish());
  const auto* value=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());CHECK(bool(wire::validateManagementState(*value))==(mode>=2));
  if(mode<2){const auto facts=*codec::decodeProduction(value->production()).independentItem->snapshot->carrier->appearance->contents;
    CHECK(facts.materialInorganic==1);CHECK(facts.solidColor=="COPPER");CHECK(facts.entries.size()==size_t(mode));
    if(mode==1){CHECK(facts.entries[0].liquid);CHECK(facts.entries[0].subterraneanPlant);CHECK(facts.entries[0].colorToken=="AMBER");}}
 }
}

TEST_CASE("item portraits and cage occupants carry independent bounded recipes") {
  for(int mode=0;mode<8;++mode) {
    flatbuffers::FlatBufferBuilder b;
    const auto pages=b.CreateVector(std::vector<flatbuffers::Offset<flatbuffers::String>>{b.CreateString("SYNTHETIC_PORTRAIT")});
    const auto palettes=b.CreateVector(std::vector<flatbuffers::Offset<flatbuffers::String>>{});
    std::vector<wire::AppearanceLayer> layers;
    if(mode!=5)layers.emplace_back(mode==4?1:0,4,2,1,1,65535,-1,-1,0,0);
    const auto recipe=wire::CreateSelectionAppearance(b,pages,palettes,b.CreateVectorOfStructs(layers));
    const auto material=b.CreateString("CREATURE:TEST:BONE"),empty=b.CreateString("");
    wire::ItemInspectionAppearanceBuilder appearance(b);
    appearance.add_material_token(material);appearance.add_subtype_raw(empty);appearance.add_color_token(empty);appearance.add_stack(1);
    const bool cage=mode==1 || mode==3 || mode==6;
    if(cage) {
      appearance.add_cage_material_family(0);appearance.add_cage_occupant_entity(mode==3?0:2);
      appearance.add_cage_occupant_id(mode==3?-1:5969);appearance.add_cage_solid_color(empty);
      appearance.add_cage_occupant(recipe);
    } else if(mode!=7)appearance.add_portrait(recipe);
    b.Finish(appearance.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ItemInspectionAppearance>(b.GetBufferPointer());
    const int type=mode==2 || mode==6?0:cage?16:52;
    const bool valid=mode==0 || mode==1 || mode==7;
    CHECK(wire::validInspectionInstrument(*value,type)==valid);
    if(!valid)continue;
    auto decoded=codec::decodeInspectionAppearance(value);
    if(mode==7){CHECK_FALSE(decoded.portrait);CHECK_FALSE(decoded.cageOccupant);continue;}
    const auto& owned=cage?decoded.cageOccupant:decoded.portrait;
    REQUIRE(owned);REQUIRE(owned->layers.size()==1);
    CHECK(owned->tilePages[0]=="SYNTHETIC_PORTRAIT");CHECK(owned->layers[0].tileX==4);CHECK(owned->layers[0].tileY==2);
    // The decoded recipe owns strings and layers after the transport is retired.
    b.Clear();CHECK(owned->tilePages[0]=="SYNTHETIC_PORTRAIT");
  }
}

TEST_CASE("item slab engraving preserves unknown and validates type and range") {
 for(int mode=0;mode<6;++mode){
  flatbuffers::FlatBufferBuilder b;const auto material=b.CreateString("INORGANIC:DOLOMITE"),empty=b.CreateString("");
  const int engraving[]={-2,-1,0,26,27,0};
  wire::ItemInspectionAppearanceBuilder a(b);a.add_material_token(material);a.add_subtype_raw(empty);a.add_color_token(empty);a.add_stack(1);a.add_slab_engraving(int8_t(engraving[mode]));
  b.Finish(a.Finish());const auto* look=flatbuffers::GetRoot<wire::ItemInspectionAppearance>(b.GetBufferPointer());
  CHECK(wire::validInspectionInstrument(*look,mode==5?30:87)==(mode<4));
  if(mode<4)CHECK(codec::decodeInspectionAppearance(look).slabEngraving==engraving[mode]);
 }
}

TEST_CASE("corpse inspection recipes own their assets independently of map residency") {
  for(int mode=0;mode<7;++mode) {
    flatbuffers::FlatBufferBuilder b;
    const auto pages=b.CreateVector(std::vector<flatbuffers::Offset<flatbuffers::String>>{b.CreateString("SYNTHETIC_CORPSE")});
    const auto palettes=b.CreateVector(std::vector<flatbuffers::Offset<flatbuffers::String>>{});
    std::vector<wire::AppearanceLayer> layers;
    if(mode!=4)layers.emplace_back(mode==3?1:0,2,3,1,1,mode==6?0:65535,-1,-1,0,0);
    const auto recipe=wire::CreateSelectionAppearance(b,pages,palettes,b.CreateVectorOfStructs(layers));
    const auto material=b.CreateString("CREATURE:TEST:BONE"),empty=b.CreateString("");
    wire::ItemInspectionAppearanceBuilder a(b);
    a.add_material_token(material);a.add_subtype_raw(empty);a.add_color_token(empty);a.add_stack(1);
    if(mode!=5)a.add_corpse_selector(recipe);
    b.Finish(a.Finish());
    const auto* look=flatbuffers::GetRoot<wire::ItemInspectionAppearance>(b.GetBufferPointer());
    const bool valid=mode==0 || mode==1 || mode==5;
    CHECK(wire::validInspectionInstrument(*look,mode==1?46:mode==2?52:23)==valid);
    if(!valid)continue;
    const auto owned=codec::decodeInspectionAppearance(look);
    b.Clear();
    if(mode==5){CHECK_FALSE(owned.corpseSelector);continue;}
    REQUIRE(owned.corpseSelector);REQUIRE(owned.corpseSelector->layers.size()==1);
    CHECK(owned.corpseSelector->tilePages[0]=="SYNTHETIC_CORPSE");
    CHECK(owned.corpseSelector->layers[0].tileX==2);
    CHECK(owned.corpseSelector->layers[0].tileY==3);
  }
}

TEST_CASE("legwear selector recipes retain owned original asset references") {
  for(int mode=0;mode<6;++mode) {
    flatbuffers::FlatBufferBuilder b;
    const auto pages=b.CreateVector(std::vector<flatbuffers::Offset<flatbuffers::String>>{b.CreateString("SYNTHETIC_LEGWEAR")});
    const auto palettes=b.CreateVector(std::vector<flatbuffers::Offset<flatbuffers::String>>{});
    std::vector<wire::AppearanceLayer> layers;
    if(mode!=3)layers.emplace_back(mode==2?1:0,2,3,1,1,mode==4?0:65535,-1,-1,0,0);
    const auto recipe=wire::CreateSelectionAppearance(b,pages,palettes,b.CreateVectorOfStructs(layers));
    const auto material=b.CreateString("CREATURE:TEST:SILK"),empty=b.CreateString("");
    wire::ItemInspectionAppearanceBuilder a(b);
    a.add_material_token(material);a.add_subtype_raw(empty);a.add_color_token(empty);a.add_stack(1);
    if(mode!=5)a.add_legwear_selector(recipe);
    b.Finish(a.Finish());
    const auto* look=flatbuffers::GetRoot<wire::ItemInspectionAppearance>(b.GetBufferPointer());
    const bool valid=mode==0 || mode==5;
    CHECK(wire::validInspectionInstrument(*look,mode==1?25:60)==valid);
    if(!valid)continue;
    const auto owned=codec::decodeInspectionAppearance(look);b.Clear();
    if(mode==5){CHECK_FALSE(owned.legwearSelector);continue;}
    REQUIRE(owned.legwearSelector);REQUIRE(owned.legwearSelector->layers.size()==1);
    CHECK(owned.legwearSelector->tilePages[0]=="SYNTHETIC_LEGWEAR");
    CHECK(owned.legwearSelector->layers[0].tileX==2);
    CHECK(owned.legwearSelector->layers[0].tileY==3);
  }
}

TEST_CASE("craft gemstone color preserves unknown absence and native color") {
  for(int mode=0;mode<5;++mode) {
    flatbuffers::FlatBufferBuilder b;
    const auto material=b.CreateString("CREATURE:TEST:HAIR"),empty=b.CreateString("");
    const auto gem=mode==0?flatbuffers::Offset<flatbuffers::String>{}:b.CreateString(mode==1?"":mode==4?std::string(129,'X'):"CLEAR");
    wire::ItemInspectionAppearanceBuilder a(b);
    a.add_material_token(material);a.add_subtype_raw(empty);a.add_color_token(empty);a.add_stack(1);
    if(mode!=0)a.add_craft_gem_color(gem);
    b.Finish(a.Finish());
    const auto* look=flatbuffers::GetRoot<wire::ItemInspectionAppearance>(b.GetBufferPointer());
    CHECK(wire::validInspectionInstrument(*look,mode==3?39:42)==(mode<3));
    if(mode>=3)continue;
    for(int type:{36,37,38,40,41,42,43})CHECK(wire::validInspectionInstrument(*look,type));
    const auto owned=codec::decodeInspectionAppearance(look);b.Clear();
    CHECK(owned.craftGemColor.has_value()==(mode!=0));
    if(mode!=0)CHECK(*owned.craftGemColor==(mode==1?"":"CLEAR"));
  }
}

TEST_CASE("craft soft material preserves unknown and rejects invalid scope") {
  for(int value:{-2,-1,0,1,2}) {
    flatbuffers::FlatBufferBuilder b;
    const auto material=b.CreateString("CREATURE:TEST:HAIR"),empty=b.CreateString("");
    wire::ItemInspectionAppearanceBuilder a(b);
    a.add_material_token(material);a.add_subtype_raw(empty);a.add_color_token(empty);a.add_stack(1);
    a.add_craft_soft_material(int8_t(value));b.Finish(a.Finish());
    const auto* look=flatbuffers::GetRoot<wire::ItemInspectionAppearance>(b.GetBufferPointer());
    for(int type=0;type<91;++type) {
      const bool craft=type>=36 && type<=43 && type!=39;
      CHECK(wire::validInspectionInstrument(*look,type)==((value==-1 && type!=13) || (craft && value>=0 && value<=1)));
    }
    if(value>=-1 && value<=1)CHECK(codec::decodeInspectionAppearance(look).craftSoftMaterial==value);
  }
}

TEST_CASE("weapon mood appearance preserves unknown independently of artifact status") {
  for(int value:{-2,-1,0,1,2}) {
    flatbuffers::FlatBufferBuilder b;
    const auto material=b.CreateString("INORGANIC:TEST"),empty=b.CreateString("");
    wire::ItemInspectionAppearanceBuilder a(b);
    a.add_material_token(material);a.add_subtype_raw(empty);a.add_color_token(empty);a.add_stack(1);
    a.add_flags(32);a.add_artifact_mood(int8_t(value));b.Finish(a.Finish());
    const auto* look=flatbuffers::GetRoot<wire::ItemInspectionAppearance>(b.GetBufferPointer());
    for(int type=0;type<=92;++type)
      CHECK(wire::validInspectionInstrument(*look,type)==((value==-1 && type!=13) || (type==24 && value>=0 && value<=1)));
    if(value>=-1 && value<=1) {
      const auto owned=codec::decodeInspectionAppearance(look);b.Clear();
      CHECK(owned.artifactMood==value);CHECK(owned.flags==32);
    }
  }
}

TEST_CASE("coffin appearance preserves unknown and restricts unused state to coffins") {
  for(int value:{-2,-1,0,1,2}) {
    flatbuffers::FlatBufferBuilder b;
    const auto material=b.CreateString("INORGANIC:TEST"),empty=b.CreateString("");
    wire::ItemInspectionAppearanceBuilder a(b);
    a.add_material_token(material);a.add_subtype_raw(empty);a.add_color_token(empty);a.add_stack(1);
    a.add_coffin_unused(int8_t(value));b.Finish(a.Finish());
    const auto* look=flatbuffers::GetRoot<wire::ItemInspectionAppearance>(b.GetBufferPointer());
    for(int type=0;type<=92;++type)
      CHECK(wire::validInspectionInstrument(*look,type)==((value==-1 && type!=13) || (type==21 && value>=0 && value<=1)));
    if(value>=-1 && value<=1) {
      const auto owned=codec::decodeInspectionAppearance(look);b.Clear();CHECK(owned.coffinUnused==value);
    }
  }
}

TEST_CASE("selected zone owner rows preserve native order and reject malformed payloads") {
  for(int variant=0;variant<8;++variant) {
    flatbuffers::FlatBufferBuilder b;wire::TilePos origin(1,2,3);
    const auto extents=b.CreateVector(std::vector<uint8_t>{1});
    const auto caption=b.CreateString(std::string(variant==2?101:25,'x'));
    const auto status=b.CreateString(variant==3?std::string(33,'s'):std::string("Deceased"));
    const auto pages=b.CreateVectorOfStrings(std::vector<std::string>{"synthetic-owner"});
    const auto palettes=b.CreateVectorOfStrings(std::vector<std::string>{});
    const std::vector<wire::AppearanceLayer> layers{{uint16_t(variant==7?1:0),0,0,1,1,65535,0,0,0,0}};
    const auto icon=wire::CreateSelectionAppearance(b,pages,palettes,b.CreateVectorOfStructs(layers));
    std::vector<flatbuffers::Offset<wire::AreaOwnerRow>> owners;
    for(int i=0;i<(variant==1?3:2);++i)owners.push_back(wire::CreateAreaOwnerRow(b,variant==4?-1:variant==5?8:8+i,caption,status,icon));
    const auto ownerRows=b.CreateVector(owners);
    wire::AreaInfoBuilder info(b);info.add_id(7);info.add_origin(&origin);info.add_width(1);info.add_height(1);info.add_extents(extents);
    info.add_kind(variant==6?wire::AreaKind::Stockpile:wire::AreaKind::Zone);info.add_owner_rows(ownerRows);
    const auto areas=b.CreateVector(std::vector{info.Finish()});const auto area=wire::CreateAreaState(b,areas);
    wire::ManagementStateBuilder root(b);root.add_revision(1);root.add_area(area);b.Finish(root.Finish());
    const auto* state=flatbuffers::GetRoot<wire::ManagementState>(b.GetBufferPointer());
    CHECK(bool(wire::validateManagementState(*state))==(variant!=0));
    if(variant==0){const auto decoded=codec::decodeArea(state->area());REQUIRE(decoded.areas[0].ownerRows.size()==2);
      CHECK(decoded.areas[0].ownerRows[0].id==8);CHECK(decoded.areas[0].ownerRows[1].id==9);
      CHECK(decoded.areas[0].ownerRows[0].caption==std::string(25,'x'));CHECK(decoded.areas[0].ownerRows[0].status=="Deceased");
      REQUIRE(decoded.areas[0].ownerRows[1].sheetIcon);CHECK(decoded.areas[0].ownerRows[1].sheetIcon->tilePages[0]=="synthetic-owner");}
  }
}
TEST_CASE("item bedding preserves native variants and rejects malformed or non-bed facts") {
  for(int fault=0;fault<7;++fault) {
    flatbuffers::FlatBufferBuilder b;
    auto bed=wire::CreateBeddingFactsDirect(b,fault==1?-1:fault==2?2:1,fault==3?-1:fault==4?3:2,
      fault==5?std::string(129,'x').c_str():"BROWN","RED");
    auto material=b.CreateString("PLANT:OLIVE:WOOD"),empty=b.CreateString("");
    wire::ItemInspectionAppearanceBuilder a(b);a.add_material_token(material);a.add_subtype_raw(empty);a.add_color_token(empty);a.add_stack(1);a.add_bedding(bed);b.Finish(a.Finish());
    const auto* value=flatbuffers::GetRoot<wire::ItemInspectionAppearance>(b.GetBufferPointer());
    CHECK(wire::validInspectionInstrument(*value,fault==6?9:8)==(fault==0));
    if(!fault){auto decoded=codec::decodeInspectionAppearance(value);b.Clear();REQUIRE(decoded.bedding);CHECK(decoded.bedding->sheet==1);CHECK(decoded.bedding->pillow==2);CHECK(decoded.bedding->baseColor=="BROWN");CHECK(decoded.bedding->sheetColor=="RED");}
  }
}
