// Isolated fake producer for the Godot adapter contract test. Never attaches to DF.
#include "management_util.h"
#include "client_mailbox.h"
#include <chrono>
#include <iostream>
#include <fstream>
#include <thread>
#include <stdexcept>
namespace m=df3d::mirror;
namespace sh=df3d::shm;
constexpr uint64_t epoch=9007199254740993ULL;
void require(bool ok,const char* what){if(!ok)throw std::runtime_error(what);}
flatbuffers::Offset<m::WorkOrderState> workOrderFixture(flatbuffers::FlatBufferBuilder& b,bool progress=false) {
  if(progress) {
    // work_orders.lua:651-653,676: filtering progress never includes rows.
    m::WorkOrderStateBuilder domain(b);domain.add_build_phase(3);
    domain.add_build_done(17);domain.add_build_total(128);return domain.Finish();
  }
  // Field provenance: tools/test_work_orders_adapter.py fixture producibility table.
  auto countDescription=b.CreateString("BLOCKS LessThan 10; DF3D estimate: 6 matching (rule met)");
  auto conditionTraits=b.CreateVectorOfStrings(std::vector<std::string>{"f1:0","rc:X"});
  m::WorkOrderConditionBuilder count(b);count.add_kind(0);count.add_index(0);count.add_description(countDescription);
  count.add_editable(true);count.add_compare(3);count.add_threshold(10);count.add_item_type(2);count.add_item_subtype(3);count.add_mat_type(419);count.add_mat_index(7);
  count.add_traits(conditionTraits);count.add_satisfaction(2);count.add_satisfied(true);count.add_estimated(true);count.add_estimate_count(6);auto countRecord=count.Finish();
  auto depDescription=b.CreateString("Order #9 Completed; Satisfied for next check");
  m::WorkOrderConditionBuilder dependency(b);dependency.add_kind(1);dependency.add_index(0);
  dependency.add_description(depDescription);dependency.add_target_order(9);dependency.add_dependency(1);
  dependency.add_satisfaction(2);dependency.add_satisfied(true);dependency.add_editable(true);auto dependencyRecord=dependency.Finish();
  auto conditions=b.CreateVector(std::vector<flatbuffers::Offset<m::WorkOrderCondition>>{countRecord,dependencyRecord});
  auto generated=b.CreateVector(std::vector<int32_t>{555});auto name=b.CreateString("Make wooden bed");
  auto reason=b.CreateString("Finish outstanding jobs before editing");
  auto input=m::CreateWorkOrderInput(b,0,b.CreateString(""),0,5,false);
  auto inputs=b.CreateVector(std::vector{input});
  m::WorkOrderInfoBuilder order(b);order.add_id(0);order.add_revision(epoch);order.add_name(name);
  order.add_total(12);order.add_remaining(3);order.add_frequency(1);order.add_validated(true);order.add_active(false);
  order.add_finished_year(106);order.add_finished_tick(400000);order.add_workshop_id(4);order.add_max_workshops(2);
  order.add_generated_jobs(generated);order.add_conditions(conditions);order.add_editable(false);order.add_reason(reason);
  order.add_position(0);order.add_detail_kind(2);order.add_size_raw(42);order.add_encrust_flags(1092);
  order.add_mat_type(0);order.add_mat_index(5);order.add_material_category(2);order.add_inputs(inputs);
  auto orderRecord=order.Finish();
  auto offices=b.CreateVector(std::vector<int32_t>{1492,1493});auto managerName=b.CreateString("Urist");
  auto position=b.CreateString("Manager");auto job=b.CreateString("Validate work orders");
  m::ManagerRoleBuilder manager(b);manager.add_unit_id(42);manager.add_name(managerName);
  manager.add_position(position);manager.add_offices(offices);manager.add_job(job);auto managerRecord=manager.Finish();
  auto anyName=b.CreateString("Any shop order"), anyReason=b.CreateString("Your manager approves new or changed orders");
  m::WorkOrderInfoBuilder any(b);any.add_id(9);any.add_revision(17);any.add_name(anyName);
  any.add_total(0);any.add_remaining(0);any.add_frequency(4);any.add_active(true);
  any.add_workshop_id(-1);any.add_max_workshops(0);any.add_editable(true);any.add_reason(anyReason);
  any.add_position(1);auto anyRecord=any.Finish();
  auto recipe=m::CreateProductionRecipe(b,b.CreateString("Carpenters:10:-1"),b.CreateString("make bed"));
  auto recipes=b.CreateVector(std::vector<flatbuffers::Offset<m::ProductionRecipe>>{recipe});
  auto choice=m::CreateAreaChoice(b,4,b.CreateString("Carpenter's Workshop #4"));
  auto choices=b.CreateVector(std::vector<flatbuffers::Offset<m::AreaChoice>>{choice});
  auto detail=b.CreateString("Role and office presence are observations, not approval.");
  auto orders=b.CreateVector(std::vector<flatbuffers::Offset<m::WorkOrderInfo>>{orderRecord,anyRecord});
  auto managers=b.CreateVector(std::vector<flatbuffers::Offset<m::ManagerRole>>{managerRecord});
  auto mat=m::CreateWorkOrderMaterial(b,0,5,b.CreateString("material"));auto mats=b.CreateVector(std::vector{mat});
  auto trait=m::CreateWorkOrderTrait(b,b.CreateString("rc:X"),b.CreateString(""));auto traits=b.CreateVector(std::vector{trait});
  auto type=m::CreateWorkOrderItemType(b,2,3,b.CreateString("type"));auto types=b.CreateVector(std::vector{type});
  auto group=m::CreateWorkOrderGroup(b,0,0,-1,b.CreateString("Carpenter's Workshop"),1);auto groups=b.CreateVector(std::vector{group});
  auto task=m::CreateWorkOrderTask(b,b.CreateString("0:1:a0:0:0:1:/1:21:0"),b.CreateString("Bed order -1"),10,b.CreateString(""),-1,-1,-1,-1);auto tasks=b.CreateVector(std::vector{task});
  m::WorkOrderStateBuilder domain(b);domain.add_materials(mats);domain.add_traits(traits);domain.add_types(types);domain.add_groups(groups);domain.add_tasks(tasks);
  domain.add_total(128);domain.add_list_revision(INT64_MAX);domain.add_build_phase(0);domain.add_build_done(0);domain.add_build_total(0);
  domain.add_orders(orders);domain.add_managers(managers);
  domain.add_recipes(recipes);domain.add_choices(choices);domain.add_detail(detail);
  domain.add_next_cursor(71);return domain.Finish();
}
// Synthetic native records: two named definitions plus paging filler; no external controller.
flatbuffers::Offset<m::CitizenState> citizenFixture(flatbuffers::FlatBufferBuilder& b,
    const m::ConstructionRequest& request) {
  using A=m::ManagementAction;
  const auto action=request.action();const auto* q=request.citizen();
  // Explicit codec-only sentinel: citizens.lua does not emit unequal editability.
  // social_activity is bridge-produced (bridge/plugin/management.cpp:402-409 sets it
  // true and substitutes the social event name when a unit has no current job); this
  // fixture exercises that path via the codec-sentinel citizen.
  const bool codecSentinels=q->query() && q->query()->str()=="codec sentinels";
  std::vector<flatbuffers::Offset<m::WorkDetailInfo>> details;
  std::vector<flatbuffers::Offset<m::CitizenInfo>> people;
  auto detail=[&](int index) {
    auto name=b.CreateString(index==0?"Miners":index==1?"Custom":"Detail "+std::to_string(index));
    auto reason=b.CreateString(codecSentinels?"Native work-detail mode is protected":"");
    auto labors=b.CreateVector(index==0?std::vector<int16_t>{0}:std::vector<int16_t>{0,1});
    auto labels=b.CreateVectorOfStrings(index==0?std::vector<std::string>{"mine"}:std::vector<std::string>{"mine","haul stone"});
    std::vector<int32_t> memberIds=index==1?std::vector<int32_t>{0}:std::vector<int32_t>{};
    if(action==A::WorkDetailMembership && index==q->detail_index())
      memberIds=q->member()==1?std::vector<int32_t>{q->unit_id()}:std::vector<int32_t>{};
    auto members=b.CreateVector(memberIds);
    m::WorkDetailInfoBuilder d(b);d.add_index(index);d.add_revision(7);d.add_name(name);
    d.add_mode(action==A::WorkDetailMode && !(q->mode()==1 && index==0)?q->mode():index==1?1:3);d.add_no_modify(index==0);d.add_cannot_be_everybody(index==0);
    d.add_editable(true);d.add_mode_editable(!codecSentinels);d.add_reason(reason);
    d.add_labors(labors);d.add_labor_names(labels);d.add_assigned_units(members);
    details.push_back(d.Finish());
  };
  auto person=[&](int id,bool inspect) {
    auto name=b.CreateString("Citizen "+std::to_string(id));auto profession=b.CreateString(id==0?"Carpenter":"Miner");
    auto job=b.CreateString(codecSentinels?"Socialize":id==0?"Dig":"No current job");auto reason=b.CreateString("");
    auto labors=b.CreateVector(inspect?std::vector<int16_t>{0,1}:std::vector<int16_t>{});
    auto labels=b.CreateVectorOfStrings(inspect?std::vector<std::string>{"mine","haul stone"}:std::vector<std::string>{});
    std::vector<flatbuffers::Offset<m::CitizenRole>> roles;
    if(inspect)roles.push_back(m::CreateCitizenRole(b,b.CreateString("Manager"),250));
    auto roleRows=b.CreateVector(roles);
    std::vector<flatbuffers::Offset<m::CitizenWorkDetail>> assigned;
    if(action==A::WorkDetailMembership && id==q->unit_id()) {
      if(q->member()==1)assigned.push_back(m::CreateCitizenWorkDetail(b,q->detail_index(),9,
          b.CreateString(q->detail_index()==1?"Custom":"Detail "+std::to_string(q->detail_index()))));
    } else if(id==0)assigned.push_back(m::CreateCitizenWorkDetail(b,1,9,b.CreateString("Custom")));
    auto assignments=b.CreateVector(assigned);m::TilePos pos(1,2,3);
    m::CitizenInfoBuilder u(b);u.add_id(id);u.add_name(name);u.add_profession(profession);
    u.add_job(job);u.add_reason(reason);u.add_age(42);u.add_has_stress(true);u.add_stress(10);
    u.add_origin(&pos);u.add_can_focus(true);u.add_eligible(true);u.add_labors(labors);
    u.add_labor_names(labels);u.add_roles(roleRows);u.add_assigned_details(assignments);
    u.add_only_assigned_jobs(codecSentinels || id==1);u.add_profession_color(id==0?14:7);u.add_profession_id(id==0?2:0);
    u.add_social_activity(codecSentinels);u.add_job_type(codecSentinels?-1:id==0?5:-1);people.push_back(u.Finish());
  };
  uint32_t next=0;int selectedUnit=-1,selectedDetail=-1;
  if(action==A::WorkDetailList) {
    for(int i=q->cursor();i<18 && details.size()<16;++i)detail(i);
    if(q->cursor()+details.size()<18)next=q->cursor()+details.size();
  } else if(action==A::CitizenList) {
    for(int i=q->cursor();i<34 && people.size()<32;++i)person(i,false);
    if(q->cursor()+people.size()<34)next=q->cursor()+people.size();
  } else if(action==A::CitizenInspect) {person(q->unit_id(),true);selectedUnit=q->unit_id();}
  else {
    detail(q->detail_index());selectedDetail=q->detail_index();
    if(q->unit_id()>=0){person(q->unit_id(),true);selectedUnit=q->unit_id();}
  }
  auto rows=b.CreateVector(details);auto citizens=b.CreateVector(people);
  auto info=b.CreateString("Existing work details only. Roles and office ownership are read-only; appointments are not exposed.");
  m::CitizenStateBuilder c(b);c.add_details(rows);c.add_citizens(citizens);
  c.add_selected_unit(selectedUnit);c.add_selected_detail(selectedDetail);c.add_next_cursor(next);
  c.add_external_controller(false);c.add_detail(info);return c.Finish();
}
// Synthetic adapter-producible observations, using the Kitchen two-input template
// exercised in test_production_adapter.py; no native screen data is involved.
flatbuffers::Offset<m::ProductionState> productionFixture(flatbuffers::FlatBufferBuilder& b,const m::ConstructionRequest& request) {
  using A=m::ManagementAction;
  const auto action=request.action();const auto* q=request.production();
  const bool list=action==A::ProductionList;
  const bool farm=!list && q->building_id()==3;
  std::vector<flatbuffers::Offset<m::ProductionBuilding>> buildings;
  auto building=[&](int id,const char* name,const char* kind,int queue) {
    m::TilePos pos(5,6,2);
    buildings.push_back(m::CreateProductionBuilding(b,id,b.CreateString(name),b.CreateString(kind),&pos,(list || action==A::ProductionInspect)?2:3,3,queue));
  };
  // A scan of 512 buildings can yield two visible production rows, then resume
  // at id 1024; the intervening rows are hidden or not production buildings.
  if(list) {
    if(q->cursor()==1024)building(1024,"Carpenters","Carpenters",0);
    else {building(0,"Carpenters","Carpenters",0);building(3,"Farm","FarmPlot",0);}
  }
  else if(farm)building(3,"Farm","FarmPlot",0);
  else building(q->building_id(),"Kitchen","Kitchen",action==A::ProductionQueue?3:2);
  std::vector<flatbuffers::Offset<m::ProductionRecipe>> recipes;
  std::vector<flatbuffers::Offset<m::ProductionJob>> jobs;
  std::vector<flatbuffers::Offset<m::FarmCrop>> crops;
  std::vector<int32_t> seasons;
  std::string detail;
  if(!list && !farm) {
    // workshops.lua:325-331; production.lua:23-34; DFHack bitfields iterate by bit index.
    // NONE prose is a native gap escalated to 06-B; preserve the emitted text.
    auto first=m::CreateProductionRequirement(b,b.CreateString("NONE, unrotten, cookable, solid"),1,-1);
    auto second=m::CreateProductionRequirement(b,b.CreateString("NONE, unrotten, cookable"),1,-1);
    auto needs=b.CreateVector(std::vector{first,second});
    recipes.push_back(m::CreateProductionRecipe(b,b.CreateString("builtin:114:2"),b.CreateString("prepare easy meal"),needs));
    // Queue appends a new awaiting job; the existing assigned/suspended pair stays.
    for(int i=0;i<(action==A::ProductionQueue?3:2);++i) {
      const int jobId=action==A::ProductionJobEdit && !q->cancel() && i==0?q->job_id():10+i;
      auto name=b.CreateString("job "+std::to_string(jobId));
      const bool editing=action==A::ProductionJobEdit && !q->cancel() && i==0;
      const bool suspended=i==1 || (editing && q->suspend()==1);
      const bool assigned=i==0 && !suspended;
      const bool repeating=i==2?q->repeat()==1:i==0 && (!editing || q->repeat()!=0);
      auto worker=b.CreateString(assigned?"Worker":"");
      auto status=b.CreateString(suspended?"Suspended by native state":assigned?"Worker assigned":"Awaiting worker or inputs; native cause is not exposed");
      m::ProductionJobBuilder j(b);j.add_id(jobId);j.add_name(name);j.add_job_type(114);
      j.add_repeat(repeating);j.add_suspended(suspended);
      j.add_worker_id(assigned?7:-1);j.add_worker_name(worker);j.add_completion_timer(i==0?17:-1);
      j.add_attached_items(i==0?1:0);j.add_editable(true);j.add_status(status);j.add_requirements(needs);
      jobs.push_back(j.Finish());
    }
    detail="Native workers select and haul inputs; queueing does not guarantee materials or labor. Work orders are not yet exposed. Workshop restricts workers (2).";
  } else if(farm) {
    crops.push_back(m::CreateFarmCrop(b,0,b.CreateString("allseason"),15,600));
    crops.push_back(m::CreateFarmCrop(b,1,b.CreateString("spring only"),1,0));
    seasons={0,-1,0,-1};
    if(action==A::FarmSetCrop)seasons.at(q->season())=q->crop_id();
    detail="Seasonal crop selection; seed counts are informational. Fertilization and new farm placement are not yet exposed.";
  }
  auto bs=b.CreateVector(buildings);auto rs=b.CreateVector(recipes);auto js=b.CreateVector(jobs);
  auto cs=b.CreateVector(crops);auto ss=b.CreateVector(seasons);auto text=b.CreateString(detail);
  m::ProductionStateBuilder p(b);p.add_buildings(bs);p.add_recipes(rs);p.add_jobs(js);p.add_crops(cs);
  p.add_seasonal_crops(ss);p.add_current_season(farm?0:-1);p.add_selected_building(list?-1:q->building_id());
  p.add_created_job(action==A::ProductionQueue?12:-1);p.add_next_cursor(list && q->cursor()==0?1024:0);p.add_detail(text);
  return p.Finish();
}
int main(int argc,char** argv) {
  if(argc>1 && std::string(argv[1])=="--validate-production-fixtures") {
    try {
      int checked=0;
      for(int action=15;action<=19;++action)for(int variant=0;variant<(action==19?8:action==18?5:2);++variant) {
        flatbuffers::FlatBufferBuilder rb;
        auto payload=m::CreateProductionRequest(rb,action==15?-1:action==19 || (action==16 && variant==1)?3:1,
            action==18?(variant==4?12:10):-1,rb.CreateString(action==17?"builtin:114:2":""),rb.CreateString(action==15 && variant==1?"#1024":""),action==15 && variant==1?1024:0,
            action==17?variant:action==18 && variant<2?variant:-1,
            action==18 && variant>=2 && variant<4?variant-2:-1,action==18 && variant==4,
            action==19?variant/2:-1,action==19 && variant%2==0?0:-1);
        m::ConstructionRequestBuilder request(rb);request.add_schema_version(m::kManagementVersion);
        request.add_client_id(1);request.add_seq(1);request.add_world_epoch(epoch);
        request.add_action(static_cast<m::ManagementAction>(action));request.add_production(payload);rb.Finish(request.Finish());
        auto* q=flatbuffers::GetRoot<m::ConstructionRequest>(rb.GetBufferPointer());
        if(auto error=m::validateConstructionRequest(*q))throw std::runtime_error(*error);
        flatbuffers::FlatBufferBuilder b;auto fixture=productionFixture(b,*q);
        m::ManagementStateBuilder state(b);state.add_schema_version(m::kManagementVersion);state.add_revision(1);
        state.add_world_epoch(epoch);state.add_client_id(1);state.add_request_seq(1);state.add_action(q->action());
        state.add_status(m::ManagementStatus::Ok);state.add_production(fixture);b.Finish(state.Finish());
        flatbuffers::Verifier verifier(b.GetBufferPointer(),b.GetSize());
        require(verifier.VerifyBuffer<m::ManagementState>(nullptr),"production fixture shape");
        if(auto error=m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())))throw std::runtime_error(*error);
        ++checked;
      }
      std::cout<<"PRODUCTION_CONTRACT_FIXTURES_PASS "<<checked<<"\n";return 0;
    } catch(const std::exception& error) {std::cerr<<error.what()<<"\n";return 1;}
  }
  // Validate the same response builder without opening a shared-memory channel.
  if(argc>1 && std::string(argv[1])=="--validate-fixtures") {
    try {
      int checked=0;
      for(int action=28;action<=33;++action)for(int variant=0;variant<3;++variant) {
        flatbuffers::FlatBufferBuilder requestBuffer;
        auto payload=m::CreateCitizenRequest(requestBuffer,action==28 || action==30?-1:0,
            action==33 && variant==0?0:action>=31?1:-1,action>=32?7:0,
            action==28?variant*16:action==30?variant*8:0,
            requestBuffer.CreateString(action==31 && variant==2?"codec sentinels":""),action==32?variant%2:-1,action==33?variant+1:-1);
        m::ConstructionRequestBuilder request(requestBuffer);request.add_schema_version(m::kManagementVersion);
        request.add_client_id(1);request.add_seq(1);request.add_world_epoch(epoch);
        request.add_action(static_cast<m::ManagementAction>(action));request.add_citizen(payload);
        requestBuffer.Finish(request.Finish());
        auto* q=flatbuffers::GetRoot<m::ConstructionRequest>(requestBuffer.GetBufferPointer());
        if(auto error=m::validateConstructionRequest(*q))throw std::runtime_error(*error);
        flatbuffers::FlatBufferBuilder b;auto fixture=citizenFixture(b,*q);
        m::ManagementStateBuilder state(b);state.add_schema_version(m::kManagementVersion);
        state.add_revision(1);state.add_world_epoch(epoch);state.add_client_id(1);state.add_request_seq(1);
        state.add_action(q->action());state.add_status(m::ManagementStatus::Ok);state.add_citizen(fixture);
        b.Finish(state.Finish());
        if(auto error=m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())))
          throw std::runtime_error(*error);
        if(action==33 && variant==0)
          require(flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())->citizen()->details()->Get(0)->mode()==3,
              "cannot-be-everybody fixture preserves stored mode");
        ++checked;
      }
      for(int action=20;action<=27;++action) {
        flatbuffers::FlatBufferBuilder b;auto fixture=workOrderFixture(b,action==27);
        m::ManagementStateBuilder state(b);state.add_revision(1);state.add_world_epoch(epoch);
        state.add_action(static_cast<m::ManagementAction>(action));state.add_status(m::ManagementStatus::Ok);state.add_work_order(fixture);
        b.Finish(state.Finish());
        flatbuffers::Verifier verifier(b.GetBufferPointer(),b.GetSize());
        require(verifier.VerifyBuffer<m::ManagementState>(nullptr),"work-order fixture shape");
        if(auto error=m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())))
          throw std::runtime_error(*error);
      }
      std::cout<<"WORK_ORDER_CONTRACT_FIXTURES_PASS 8\n";
      std::cout<<"CITIZEN_CONTRACT_FIXTURES_PASS "<<checked<<"\n";return 0;
    } catch(const std::exception& error) {std::cerr<<error.what()<<"\n";return 1;}
  }
  auto signal=[&](const char* value){if(argc>1)std::ofstream(argv[1])<<value;};
#ifdef _WIN32
  const auto size=sh::regionSize(m::kManagementCapacity,m::kManagementCommandCapacity);
  HANDLE mapping=CreateFileMappingA(INVALID_HANDLE_VALUE,nullptr,PAGE_READWRITE,0,DWORD(size),m::kManagementRegionName);
  if(!mapping || GetLastError()==ERROR_ALREADY_EXISTS) {
    if(mapping)CloseHandle(mapping);
    signal("incomplete");std::cout<<"QA_INCOMPLETE: management channel already exists or cannot be created\n";return 77;
  }
  auto* region=static_cast<sh::RegionHeader*>(MapViewOfFile(mapping,FILE_MAP_ALL_ACCESS,0,0,0));
  if(!region){CloseHandle(mapping);return 1;}
  int result=0;
  try {
    sh::initRegion(region,m::kManagementVersion,m::kManagementCapacity,m::kManagementCommandCapacity);
    auto* owner=m::sessionOwner(region);
    sh::atomicStoreRelease(&owner->created,sh::processCreated(GetCurrentProcess()));
    sh::atomicStoreRelease(&owner->generation,1);
    sh::atomicStoreRelease(&owner->pid,GetCurrentProcessId());
    std::unique_ptr<sh::ClientMailbox> reply;
    auto publish=[&](uint64_t revision,const m::ConstructionRequest* request) {
      flatbuffers::FlatBufferBuilder b;
      auto text=b.CreateString("contract result");
      auto name=b.CreateString("contract area");auto empty=b.CreateString("");
      std::vector<uint8_t> mask{1};auto extent=b.CreateVector(mask);
      m::TilePos pos(11,12,13);
      m::AreaInfoBuilder area(b);area.add_id(2147483000);area.add_origin(&pos);
      area.add_kind(m::AreaKind::Zone);area.add_width(1);area.add_height(1);
      area.add_name(name);area.add_owner_name(empty);area.add_extents(extent);area.add_owner_id(-1);
      auto row=area.Finish();auto rows=b.CreateVector(std::vector<flatbuffers::Offset<m::AreaInfo>>{row});
      auto areas=m::CreateAreaState(b,rows,0,UINT32_MAX,false);
      flatbuffers::Offset<m::WorkOrderState> work;
      if(request && request->action()>=m::ManagementAction::WorkOrderList &&
          request->action()<=m::ManagementAction::WorkOrderCatalog)work=workOrderFixture(b,request->action()==m::ManagementAction::WorkOrderCatalog);
      flatbuffers::Offset<m::CitizenState> citizens;
      if(request && request->action()>=m::ManagementAction::CitizenList &&
          request->action()<=m::ManagementAction::WorkDetailMode)citizens=citizenFixture(b,*request);
      flatbuffers::Offset<m::ProductionState> production;
      if(request && request->action()>=m::ManagementAction::ProductionList &&
          request->action()<=m::ManagementAction::FarmSetCrop)production=productionFixture(b,*request);

      flatbuffers::Offset<m::ConstructionState> construction;
      if(request && (request->action()==m::ManagementAction::ConstructionMaterials || request->action()==m::ManagementAction::Preview)) {
        const auto key=b.CreateString(request->definition()->str());
        const auto f=m::CreateConstructionFilter(b,0,-1,-1,empty,empty,1);
        const auto fs=b.CreateVector(std::vector{f});
        const auto fp=m::CreateConstructionFootprint(b,request->retracting()?4:request->direction(),1,1,0,0);
        m::ConstructionStateBuilder c(b);c.add_building_key(key);c.add_filter(request->filter());
        c.add_filters(fs);c.add_list_revision(INT64_MAX);c.add_footprint(fp);construction=c.Finish();
      }
      m::ManagementStateBuilder state(b);state.add_production(production);state.add_construction(construction);state.add_citizen(citizens);state.add_work_order(work);state.add_schema_version(m::kManagementVersion);
      state.add_revision(revision);state.add_world_epoch(epoch);state.add_client_id(request?request->client_id():0);
      state.add_request_seq(request?request->seq():0);state.add_action(request?request->action():m::ManagementAction::Catalog);
      state.add_status(m::ManagementStatus::Ok);state.add_message(text);
      state.add_building_id(2147483000);state.add_build_stage(-1);state.add_max_stage(-1);state.add_area(areas);
      auto finished=state.Finish();b.Finish(finished);
      const auto* value=flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer());
      if(auto error=m::validateManagementState(*value))throw std::runtime_error(*error);
      require(sh::publishSnapshot(region,b.GetBufferPointer(),b.GetSize(),0),"publish");
      if(request){reply=sh::ClientMailbox::open(m::kManagementRegionName,1,request->client_id(),m::kManagementVersion,m::kManagementCapacity);
        require(bool(reply),"reply mailbox");require(sh::publishSnapshot(reply->region(),b.GetBufferPointer(),b.GetSize(),0),"reply publish");}
    };
    using A=m::ManagementAction;
    const std::vector<A> expectations{A::Catalog,A::AreaUpdate,A::Place,A::Catalog,A::Catalog,
        A::ProductionJobEdit,A::WorkOrderUpdate,A::WorkDetailMembership,A::ReportInspect,
        A::AgreementInspect,A::TradeUpdate,
        A::WorkOrderList,A::WorkOrderInspect,A::WorkOrderCreate,A::WorkOrderUpdate,
        A::WorkOrderDelete,A::WorkOrderCondition,A::WorkOrderCondition,A::WorkOrderCondition,
        A::WorkOrderCandidates,A::WorkOrderCandidates,A::WorkOrderCandidates,A::WorkOrderCatalog,A::WorkOrderList,
        A::WorkDetailList,A::WorkDetailList,A::WorkDetailInspect,A::WorkDetailInspect,
        A::CitizenList,A::CitizenList,A::CitizenInspect,A::WorkDetailMembership,A::WorkDetailMembership,
        A::WorkDetailMode,A::WorkDetailMode,A::WorkDetailMode,A::WorkDetailInspect,
        A::WorkOrderUpdate,A::WorkOrderUpdate,A::WorkOrderCondition,
        A::ConstructionMaterials,A::Preview,A::Preview,
        A::ProductionList,A::ProductionInspect,A::ProductionInspect,A::ProductionQueue,A::ProductionQueue,
        A::ProductionJobEdit,A::ProductionJobEdit,A::ProductionJobEdit,A::ProductionJobEdit,A::ProductionJobEdit,
        A::FarmSetCrop,A::FarmSetCrop,A::FarmSetCrop,A::FarmSetCrop,A::FarmSetCrop,A::FarmSetCrop,A::FarmSetCrop,A::FarmSetCrop,A::ProductionList};
    publish(1,nullptr);signal("ready");size_t received=0;
    const auto stop=std::chrono::steady_clock::now()+std::chrono::seconds(30);
    std::vector<uint8_t> bytes(m::kManagementCommandCapacity);
    while(std::chrono::steady_clock::now()<stop) {
      auto count=sh::popCommand(region,bytes.data(),bytes.size());
      if(count && count!=SIZE_MAX) {
        flatbuffers::Verifier verifier(bytes.data(),count);require(verifier.VerifyBuffer<m::ConstructionRequest>(nullptr),"request buffer");
        auto* r=flatbuffers::GetRoot<m::ConstructionRequest>(bytes.data());
        require(!m::validateConstructionRequest(*r),"request contract");
        require(received<expectations.size(),"malformed request reached transport");
        require(r->action()==expectations[received],"ordered request action");
        ++received;
        if(received>1)require(r->world_epoch()==epoch,"64-bit world identity");
        switch(r->action()) {
        case A::Catalog:
          require(r->building_id()==-1 && r->width()==1 && r->height()==1 && r->direction()==0 &&
              r->origin() && r->origin()->x()==0 && r->origin()->y()==0 && r->origin()->z()==0 &&
              r->cursor()==0 && (!r->items() || r->items()->size()==0) &&
              (!r->definition() || r->definition()->size()==0) &&
              !r->area() && !r->production() && !r->work_order() && !r->citizen() &&
              !r->report() && !r->agreement() && !r->trade(),"construction catalog defaults");
          break;
        case A::AreaUpdate: {
          auto* a=r->area();require(a && a->id()==2147483000 && a->owner_id()==-2 && a->barrels()==-1 && a->active()==-1,"area identity/sentinels");break;
        }
        case A::Place:
          require(r->selections() && r->selections()->size()==1 && r->selections()->Get(0)->filter()==0 && r->selections()->Get(0)->count()==1 && r->selections()->Get(0)->expected_list_revision()==INT64_MAX,"material selection");
          require(r->origin() && r->origin()->x()==11 && r->origin()->y()==12 && r->origin()->z()==13,"placement origin");
          require(r->definition() && r->definition()->str()=="Chair","definition");break;

        case A::ConstructionMaterials:
          require(r->definition()->str()=="Chair" && r->filter()==0 && r->expected_list_revision()==INT64_MAX,"construction materials request");break;
        case A::Preview:
          if(received==42)require(r->definition()->str()=="Construction:Stairs" && r->depth()==3 && !r->retracting(),"stair depth");
          else require(received==43 && r->definition()->str()=="Bridge" && r->depth()==1 && r->retracting() && r->direction()==0,"retracting bridge");
          break;
        case A::ProductionJobEdit: {
          auto* v=r->production();
          if(received>43) {
            int variant=int(received)-49;
            require(v && v->building_id()==1 && v->job_id()==(variant==4?12:10) &&
                v->repeat()==(variant<2?variant:-1) && v->suspend()==(variant>=2 && variant<4?variant-2:-1) &&
                v->cancel()==(variant==4),"production edit variants");break;
          }
          require(v && v->building_id()==2147483000 && v->job_id()==2147483001 && v->repeat()==1 && v->suspend()==-1 && !v->cancel(),"production payload");break;
        }
        case A::ProductionList:
          require(r->production()->query()->str()==(received==62?"#1024":"") && r->production()->cursor()==(received==62?1024:0),"production list payload");break;
        case A::ProductionInspect:
          require(r->production()->building_id()==(received==45?1:3),"production inspect payload");break;
        case A::ProductionQueue:
          require(r->production()->building_id()==1 && r->production()->recipe()->str()=="builtin:114:2" &&
              r->production()->repeat()==int(received)-47,"production queue payload");break;
        case A::FarmSetCrop:
          require(r->production()->building_id()==3 && r->production()->season()==int(received-54)/2 &&
              r->production()->crop_id()==(received%2==0?0:-1),"farm crop payload");break;
        case A::WorkOrderUpdate: {
          auto* v=r->work_order();
          if(received==38){require(v && v->id()==0 && v->expected_revision()==epoch && v->move()==-1 && v->expected_neighbor()==9 && v->expected_list_revision()==INT64_MAX && !v->traits(),"move fields");break;}
          if(received==39){require(v && v->id()==0 && v->expected_revision()==epoch && v->input_index()==0 && v->mat_type()==0 && v->mat_index()==5 && v->encrust_flags()==1092 && !v->traits(),"input fields");break;}
          require(v && v->id()==2147483000 && v->expected_revision()==epoch && v->remaining()==12 && v->workshop_id()==-2 && (received==7 || (v->frequency()==4 && v->max_workshops()==3)),"work order payload");break;
        }
        case A::WorkOrderList: {
          auto* v=r->work_order();
          if(received==24)require(v && v->query()->str()==std::string(64,'x') && v->cursor()==0,"64-byte query");
          else require(v && v->query()->str()=="bed" && v->cursor()==71,"list paging");
          break;
        }
        case A::WorkOrderInspect:
          require(r->work_order()->id()==0,"inspect identity");break;
        case A::WorkOrderCreate: {
          auto* v=r->work_order();require(v && v->recipe()->str()=="Carpenters:10:-1" &&
              v->remaining()==0 && v->frequency()==2 && v->workshop_id()==4 && v->max_workshops()==3,"create fields");break;
        }
        case A::WorkOrderDelete:
          require(r->work_order()->id()==0 && r->work_order()->expected_revision()==epoch,"delete identity");break;
        case A::WorkOrderCondition: {
          auto* v=r->work_order();require(v && v->id()==0 && v->expected_revision()==epoch,"condition identity");
          if(received==40){require(v->traits() && v->traits()->size()==0 && v->item_type()==-1 && v->compare()==0 && v->threshold()==0,"explicit empty traits");break;}
          if(received==17)require(v->condition_kind()==0 && v->condition_index()==-1 && !v->remove_condition() &&
              v->compare()==3 && v->threshold()==10 && v->item_type()==2 && v->item_subtype()==3 && v->mat_type()==419 && v->mat_index()==7 &&
              v->traits() && v->traits()->size()==2 && v->traits()->Get(0)->str()=="f1:0" && v->traits()->Get(1)->str()=="rc:X","item condition");
          else if(received==18)require(v->condition_kind()==1 && v->condition_index()==0 && !v->remove_condition() &&
              v->target_order()==9 && v->dependency()==1,"order condition");
          else require(received==19 && v->condition_index()==0 && v->remove_condition(),"condition removal");
          break;
        }
        case A::WorkOrderCandidates: {
          auto* v=r->work_order();require(v && v->candidate_kind()==received-20 &&
              v->cursor()==4 && v->query()->str()=="bed","candidate fields");break;
        }
        case A::WorkOrderCatalog:
          require(r->work_order()->id()==-1 && r->work_order()->expected_revision()==0 && r->work_order()->group_type()==0 &&
              r->work_order()->group_subtype()==0 && r->work_order()->group_custom()==-1 &&
              r->work_order()->expected_list_revision()==INT64_MAX,"catalog identities");break;
        case A::WorkDetailMembership: {
          auto* v=r->citizen();if(received>24){require(v && v->mode()==-1 && v->unit_id()==0 && v->detail_index()==1 && v->expected_revision()==7 && v->member()==(received==32?1:0),"membership payload");break;}require(v && v->unit_id()==2147483000 && v->detail_index()==127 && v->expected_revision()==epoch && v->member()==1 && v->mode()==-1,"citizen payload");break;
        }
        case A::WorkDetailList: case A::CitizenList: {
          auto* v=r->citizen();require(v->query()->str()==(r->action()==A::CitizenList?"Citizen":"") &&
              v->cursor()==(received==26?16:received==30?32:0),"citizen paging payload");break;
        }
        case A::CitizenInspect: require(r->citizen()->unit_id()==0,"citizen inspect");break;
        case A::WorkDetailInspect: require(r->citizen()->detail_index()==1 &&
            r->citizen()->unit_id()==(received==27?-1:0) &&
            (received!=37 || r->citizen()->query()->str()=="codec sentinels"),"detail inspect");break;
        case A::WorkDetailMode: require(r->citizen()->detail_index()==1 &&
            r->citizen()->expected_revision()==7 && r->citizen()->mode()==int(received)-33,"mode payload");break;
        case A::ReportInspect: require(r->report() && r->report()->id()==2147483000 && r->report()->before_id()==-1,"report payload");break;
        case A::AgreementInspect: require(r->agreement() && r->agreement()->id()==2147483000 && r->agreement()->before_id()==-1 && !r->agreement()->pending_only(),"agreement payload");break;
        case A::TradeUpdate: {
          auto* v=r->trade();require(v && v->depot_id()==2147483000 && v->expected_revision()==epoch && v->requested()==1 && v->anyone()==-1 && v->item_id()==-1,"trade payload");break;
        }
        default: throw std::runtime_error("unexpected action");
        }
        publish(received+1,r);
        if(received==expectations.size())signal("passed");
        if(received==expectations.size())std::cout<<"MANAGEMENT_CONTRACT_HOST_PASS\n"<<std::flush;
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(2));
    }
    require(received==expectations.size(),"adapter requests did not finish");
  } catch(const std::exception& error) {signal("failed");std::cerr<<"CONTRACT_HOST_FAILURE: "<<error.what()<<"\n";result=1;}
  UnmapViewOfFile(region);CloseHandle(mapping);return result;
#else
  std::cout<<"QA_INCOMPLETE: Windows shared memory required\n";return 77;
#endif
}
