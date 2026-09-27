#include "doctest.h"
#include "wm/management_client.h"
#include "management_util.h"
#include "client_mailbox.h"
#include <memory>
#include <iostream>
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif

TEST_CASE("citizen appended state validation boundaries") {
  namespace m=df3d::mirror;
  auto validate=[](int member,int skill,int rating,int portrait,uint64_t revision,
                   int icon,size_t skillBytes,size_t errorBytes,uint32_t done,uint32_t total,
                   uint32_t version=m::kManagementVersion,const std::string& defect="") {
    flatbuffers::FlatBufferBuilder b;
    auto empty=b.CreateString("");auto skillName=b.CreateString(std::string(skillBytes,'x'));
    auto rowError=b.CreateString(std::string(errorBytes,'x'));
    std::vector<int16_t> laborIds;
    if(defect=="labors_over")for(int i=0;i<95;++i)laborIds.push_back(i);
    if(defect=="labor_name_over")laborIds.push_back(0);
    auto labors=b.CreateVector(laborIds);
    auto names=b.CreateVectorOfStrings(std::vector<std::string>(laborIds.size(),std::string(defect=="labor_name_over"?129:0,'x')));
    m::TilePos origin(0,0,0);
    std::vector<flatbuffers::Offset<m::CitizenWorkDetail>> assigned;
    if(defect=="assignments_over")for(int i=0;i<129;++i)assigned.push_back(m::CreateCitizenWorkDetail(b,i,0,empty));
    else if(defect.starts_with("assigned_"))assigned.push_back(m::CreateCitizenWorkDetail(b,0,
        defect=="assigned_unknown"?-2:defect=="assigned_over"?19:-1,empty));
    auto over=b.CreateString(std::string(513,'x'));
    if(defect=="assignment_name_over")assigned.push_back(m::CreateCitizenWorkDetail(b,0,0,over));
    auto assignments=b.CreateVector(assigned);
    std::vector<flatbuffers::Offset<m::CitizenRole>> roles;
    if(defect=="roles_over")for(int i=0;i<33;++i)roles.push_back(m::CreateCitizenRole(b,empty,0));
    if(defect=="role_name_over")roles.push_back(m::CreateCitizenRole(b,over,0));
    auto roleRows=b.CreateVector(roles);std::vector<int32_t> officeIds;
    if(defect=="offices_over")for(int i=0;i<65;++i)officeIds.push_back(i);
    auto offices=b.CreateVector(officeIds);
    flatbuffers::Offset<m::SelectionAppearance> sheetIcon;
    if(defect.starts_with("portrait_")) {
      auto pages=b.CreateVectorOfStrings(std::vector<std::string>(defect=="portrait_pages_over"?257:1,std::string(defect=="portrait_page_over"?257:256,'x')));
      auto palettes=b.CreateVectorOfStrings(std::vector<std::string>(defect=="portrait_palettes_over"?257:1,std::string(defect=="portrait_palette_over"?513:512,'x')));
      auto layers=b.CreateVectorOfStructs(std::vector<m::AppearanceLayer>(defect=="portrait_layers_over"?257:1,m::AppearanceLayer(0,0,0,1,1,0,0,0,0,0)));
      sheetIcon=m::CreateSelectionAppearance(b,pages,palettes,layers);
    }
    m::CitizenInfoBuilder u(b);u.add_id(0);u.add_name(defect=="name_over"?over:empty);
    u.add_profession(defect=="profession_over"?over:empty);u.add_job(defect=="job_over"?over:empty);
    u.add_reason(defect=="reason_over"?over:empty);if(defect!="origin")u.add_origin(&origin);
    u.add_roles(roleRows);u.add_offices(offices);
    if(sheetIcon.o)u.add_sheet_icon(sheetIcon);
    if(defect!="labors")u.add_labors(labors);
    if(defect!="labor_names")u.add_labor_names(names);
    u.add_assigned_details(assignments);
    u.add_detail_member(member);u.add_detail_skill(skill);u.add_detail_skill_rating(rating);
    u.add_portrait_state(portrait);u.add_revision(revision);u.add_detail_skill_name(skillName);u.add_row_error(rowError);
    auto person=u.Finish();std::vector<int32_t> memberIds;
    if(defect=="members_over")for(int i=0;i<1025;++i)memberIds.push_back(i);
    auto members=b.CreateVector(memberIds);
    auto detailError=b.CreateString(std::string(defect=="detail_error_over"?257:256,'x'));
    m::WorkDetailInfoBuilder d(b);d.add_index(0);d.add_revision(defect=="detail_revision"?0:1);
    d.add_name(defect=="detail_name_over"?over:empty);d.add_reason(defect=="detail_reason_over"?over:empty);
    d.add_row_error(detailError);
    d.add_labors(labors);d.add_labor_names(names);d.add_assigned_units(members);d.add_icon(icon);
    auto detail=d.Finish();auto people=b.CreateVector(std::vector{person});auto details=b.CreateVector(std::vector{detail});
    auto recalcError=b.CreateString(std::string(defect=="recalc_error_over"?257:256,'x'));
    auto info=b.CreateString(std::string(defect=="info_over"?2049:0,'x'));
    m::CitizenStateBuilder c(b);c.add_citizens(people);c.add_details(details);c.add_recalc_done(done);c.add_recalc_total(total);
    c.add_recalc_error(recalcError);c.add_detail_list_revision(defect=="list_revision"?uint64_t(INT64_MAX)+1:INT64_MAX);
    c.add_detail(info);
    auto citizens=c.Finish();auto message=b.CreateString(std::string(defect=="message_over"?8193:0,'x'));
    m::ManagementStateBuilder s(b);s.add_schema_version(version);s.add_revision(1);s.add_message(message);
    s.add_action(m::ManagementAction::CitizenInspect);s.add_status(m::ManagementStatus::Ok);s.add_citizen(citizens);
    b.Finish(s.Finish());return m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())).value_or("");
  };
  for(int member:{-1,0,1})for(int icon:{-2,-1,0,18})
    CHECK(validate(member,INT16_MAX,20,3,INT64_MAX,icon,128,256,UINT32_MAX,UINT32_MAX)=="");
  CHECK(validate(-1,-1,-1,0,0,-2,0,0,0,0)=="");
  CHECK(validate(-2,0,0,0,0,0,0,0,0,0)=="invalid citizen detail fields");
  CHECK(validate(2,0,0,0,0,0,0,0,0,0)=="invalid citizen detail fields");
  CHECK(validate(0,-2,0,0,0,0,0,0,0,0)=="invalid citizen detail fields");
  for(int rating:{-2,21})CHECK(validate(0,0,rating,0,0,0,0,0,0,0)=="invalid citizen detail fields");
  CHECK(validate(0,0,0,4,0,0,0,0,0,0)=="invalid citizen detail fields");
  CHECK(validate(0,0,0,0,uint64_t(INT64_MAX)+1,0,0,0,0,0)=="invalid citizen detail fields");
  for(int icon:{-3,19})CHECK(validate(0,0,0,0,0,icon,0,0,0,0)=="invalid work detail fields");
  CHECK(validate(0,0,0,0,0,0,129,0,0,0)=="invalid citizen detail fields");
  CHECK(validate(0,0,0,0,0,0,0,257,0,0)=="invalid citizen detail fields");
  CHECK(validate(0,0,0,0,0,0,0,0,1,0)=="invalid citizen recalculation state");
  CHECK(validate(0,0,0,0,0,0,0,0,0,0,m::kManagementVersion-1)=="invalid management version/revision");
  for(const auto& pair:std::vector<std::pair<std::string,std::string>>{
      {"origin","invalid citizen row"},{"labors","invalid citizen row"},{"labor_names","invalid citizen row"},
      {"detail_revision","invalid work detail"},{"detail_error_over","invalid work detail fields"},
      {"recalc_error_over","invalid citizen recalculation state"},{"list_revision","invalid citizen recalculation state"},
      {"assigned_none",""},{"assigned_unknown","invalid citizen work detail"},{"assigned_over","invalid citizen work detail"},
      {"labors_over","invalid citizen row"},{"labor_name_over","invalid citizen row"},
      {"roles_over","invalid citizen row"},{"offices_over","invalid citizen row"},{"members_over","invalid work detail"},
      {"assignments_over","too many citizen work details"},{"name_over","invalid citizen row"},
      {"profession_over","invalid citizen row"},{"job_over","invalid citizen row"},{"reason_over","invalid citizen row"},
      {"role_name_over","invalid citizen role"},{"assignment_name_over","invalid citizen work detail"},
      {"detail_name_over","invalid work detail"},{"detail_reason_over","invalid work detail"},
      {"info_over","invalid citizen state"},{"message_over","message too long"},
      {"portrait_pages_over","invalid citizen sheet icon references"},{"portrait_palettes_over","invalid citizen sheet icon references"},
      {"portrait_layers_over","invalid citizen sheet icon references"},{"portrait_page_over","invalid citizen sheet icon page"},
      {"portrait_palette_over","invalid citizen sheet icon palette"}})
    CHECK(validate(0,0,0,0,0,0,0,0,0,0,m::kManagementVersion,pair.first)==pair.second);
}

TEST_CASE("maximal citizen R D I pages fit the management channel") {
  namespace m=df3d::mirror;
  auto portrait=[](flatbuffers::FlatBufferBuilder& b,int paletteCount,int finalBytes) {
    auto pages=b.CreateVectorOfStrings(std::vector<std::string>(paletteCount==256?256:1,std::string(256,'p')));
    std::vector<std::string> paletteNames(paletteCount,std::string(512,'a'));
    paletteNames.back()=std::string(finalBytes,'a');auto palettes=b.CreateVectorOfStrings(paletteNames);
    auto layers=b.CreateVectorOfStructs(std::vector<m::AppearanceLayer>(paletteCount==256?256:1,m::AppearanceLayer(0,0,0,1,1,0,0,0,0,0)));
    return m::CreateSelectionAppearance(b,pages,palettes,layers);
  };
  // Match management.cpp's independently encoded portrait accounting, including 8 B slack.
  int finalBytes=-1;
  for(int size=0;size<=512;++size) {
    flatbuffers::FlatBufferBuilder b;b.Finish(portrait(b,15,size));
    if(b.GetSize()+8==8192){finalBytes=size;break;}
  }
  REQUIRE(finalBytes>=0);
  for(auto action:{m::ManagementAction::CitizenList,m::ManagementAction::WorkDetailList,m::ManagementAction::CitizenInspect}) {
    for(bool namedRoster:{false,true}) {
      if(namedRoster && action!=m::ManagementAction::CitizenList)continue;
      flatbuffers::FlatBufferBuilder b;
      auto text=[&](size_t n){return b.CreateString(std::string(n,'x'));};
      auto laborSet=[&](bool populated){std::vector<int16_t> ids;if(populated)for(int i=0;i<94;++i)ids.push_back(i);return b.CreateVector(ids);};
      auto laborNames=[&](bool populated){return b.CreateVectorOfStrings(std::vector<std::string>(populated?94:0,std::string(128,'x')));};
      const bool roster=action==m::ManagementAction::CitizenList;
      const int personCount=roster?32:action==m::ManagementAction::CitizenInspect?1:0;
      const int detailCount=action==m::ManagementAction::WorkDetailList?16:action==m::ManagementAction::CitizenInspect?1:0;
      std::vector<flatbuffers::Offset<m::CitizenInfo>> people;
      for(int id=0;id<personCount;++id) {
        auto name=text(512),profession=text(512),job=text(512),reason=text(512),skill=text(128),error=text(256);
        auto labors=laborSet(!roster);auto labels=laborNames(!roster);
        std::vector<flatbuffers::Offset<m::CitizenWorkDetail>> assignments;
        for(int i=0;i<128;++i)assignments.push_back(m::CreateCitizenWorkDetail(b,i,18,text(roster?(namedRoster?1:0):512)));
        auto assigned=b.CreateVector(assignments);
        std::vector<flatbuffers::Offset<m::CitizenRole>> roles;
        if(!roster)for(int i=0;i<32;++i)roles.push_back(m::CreateCitizenRole(b,text(512),250));
        auto roleRows=b.CreateVector(roles);std::vector<int32_t> officeIds;
        if(!roster)for(int i=0;i<64;++i)officeIds.push_back(i);
        auto offices=b.CreateVector(officeIds);
        auto icon=portrait(b,roster?15:256,roster?finalBytes:512);
        m::TilePos origin(1,2,3);m::CitizenInfoBuilder u(b);u.add_id(id);u.add_origin(&origin);
        u.add_name(name);u.add_profession(profession);u.add_job(job);u.add_reason(reason);u.add_labors(labors);u.add_labor_names(labels);
        u.add_roles(roleRows);u.add_offices(offices);u.add_assigned_details(assigned);u.add_sheet_icon(icon);
        u.add_revision(INT64_MAX);u.add_detail_member(1);u.add_detail_skill(INT16_MAX);u.add_detail_skill_rating(20);
        u.add_detail_skill_name(skill);u.add_row_error(error);u.add_portrait_state(1);people.push_back(u.Finish());
      }
      std::vector<flatbuffers::Offset<m::WorkDetailInfo>> details;
      for(int index=0;index<detailCount;++index) {
        auto name=text(512),reason=text(512),error=text(256);auto labors=laborSet(true);auto labels=laborNames(true);
        std::vector<int32_t> ids;for(int i=0;i<1024;++i)ids.push_back(i);auto members=b.CreateVector(ids);
        m::WorkDetailInfoBuilder d(b);d.add_index(index);d.add_revision(INT64_MAX);d.add_name(name);d.add_reason(reason);
        d.add_row_error(error);d.add_icon(18);d.add_mode(3);d.add_labors(labors);d.add_labor_names(labels);d.add_assigned_units(members);
        details.push_back(d.Finish());
      }
      auto us=b.CreateVector(people);auto ds=b.CreateVector(details);auto info=text(2048),error=text(256);
      m::CitizenStateBuilder c(b);c.add_citizens(us);c.add_details(ds);c.add_detail(info);c.add_recalc_error(error);
      c.add_recalc_done(UINT32_MAX);c.add_recalc_total(UINT32_MAX);c.add_detail_list_revision(INT64_MAX);
      auto citizens=c.Finish();auto message=text(8192);m::ManagementStateBuilder s(b);s.add_revision(1);s.add_world_epoch(7);
      s.add_action(action);s.add_status(m::ManagementStatus::Ok);s.add_message(message);s.add_citizen(citizens);b.Finish(s.Finish());
      auto result=m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer()));
      CHECK(result.value_or("")==(namedRoster?"unexpected citizen roster detail names":""));
      if(!namedRoster) {
        CHECK(b.GetSize()<m::kManagementCapacity);
        std::cout<<"CITIZEN_MAX_PAGE "<<(roster?'R':detailCount==16?'D':'I')<<" "<<b.GetSize()<<" bytes\n";
      }
    }
  }
}

TEST_CASE("citizen page shapes reject surplus and cross-domain rows before decoding") {
  namespace m=df3d::mirror;
  auto check=[](m::ManagementAction action,int people,int details,const char* expected) {
    flatbuffers::FlatBufferBuilder b;
    auto person=m::CreateCitizenInfo(b);auto detail=m::CreateWorkDetailInfo(b);
    auto us=b.CreateVector(std::vector<flatbuffers::Offset<m::CitizenInfo>>(people,person));
    auto ds=b.CreateVector(std::vector<flatbuffers::Offset<m::WorkDetailInfo>>(details,detail));
    auto c=m::CreateCitizenState(b,us,ds);m::ManagementStateBuilder s(b);s.add_revision(1);s.add_action(action);
    s.add_status(m::ManagementStatus::Ok);s.add_citizen(c);b.Finish(s.Finish());
    CHECK(m::validateManagementState(*flatbuffers::GetRoot<m::ManagementState>(b.GetBufferPointer())).value_or("")==expected);
  };
  check(m::ManagementAction::CitizenList,0,0,"");
  check(m::ManagementAction::WorkDetailList,0,0,"");
  check(m::ManagementAction::CitizenInspect,0,0,"");
  check(m::ManagementAction::CitizenList,33,0,"invalid citizen state");
  check(m::ManagementAction::WorkDetailList,0,17,"invalid citizen state");
  check(m::ManagementAction::CitizenList,0,1,"invalid citizen roster page");
  check(m::ManagementAction::WorkDetailList,1,0,"invalid work detail list page");
  check(m::ManagementAction::CitizenInspect,2,0,"invalid citizen inspection page");
  check(m::ManagementAction::CitizenInspect,0,2,"invalid citizen inspection page");
}
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
namespace {
namespace mm = df3d::mirror;
namespace shm = df3d::shm;
struct ManagementPublisher {
  HANDLE mapping=nullptr;
  shm::RegionHeader* region=nullptr;
  std::string name="Local\\df3d_management_test_"+std::to_string(GetCurrentProcessId());
  std::vector<uint8_t> bytes=std::vector<uint8_t>(mm::kManagementCommandCapacity);
  ManagementPublisher() {
    mapping=CreateFileMappingA(INVALID_HANDLE_VALUE,nullptr,PAGE_READWRITE,0,
      DWORD(shm::regionSize(mm::kManagementCapacity,mm::kManagementCommandCapacity)),name.c_str());
    REQUIRE(mapping);
    REQUIRE(GetLastError()!=ERROR_ALREADY_EXISTS);  // a stale publisher would alias this test
    region=static_cast<shm::RegionHeader*>(MapViewOfFile(mapping,FILE_MAP_ALL_ACCESS,0,0,0));
    REQUIRE(region);
    shm::initRegion(region,mm::kManagementVersion,mm::kManagementCapacity,mm::kManagementCommandCapacity);
    FILETIME c{},e{},k{},u{}; REQUIRE(GetProcessTimes(GetCurrentProcess(),&c,&e,&k,&u));
    auto* owner=mm::sessionOwner(region);
    shm::atomicStoreRelease(&owner->created,(uint64_t(c.dwHighDateTime)<<32)|c.dwLowDateTime);
    shm::atomicStoreRelease(&owner->generation,1);
    shm::atomicStoreRelease(&owner->pid,GetCurrentProcessId());
  }
  ~ManagementPublisher(){if(region)UnmapViewOfFile(region);if(mapping)CloseHandle(mapping);}
  const mm::ConstructionRequest* pop() {
    auto n=shm::popCommand(region,bytes.data(),bytes.size()); REQUIRE(n>0);
    flatbuffers::Verifier v(bytes.data(),n); REQUIRE(v.VerifyBuffer<mm::ConstructionRequest>(nullptr));
    auto* r=flatbuffers::GetRoot<mm::ConstructionRequest>(bytes.data());
    REQUIRE_FALSE(mm::validateConstructionRequest(*r).has_value()); return r;
  }
  bool write(const uint8_t* bytes,size_t size) {
    auto* state=flatbuffers::GetRoot<mm::ManagementState>(bytes);
    const auto generation=shm::atomicLoadAcquire(&mm::sessionOwner(region)->generation);
    auto reply=shm::ClientMailbox::open(name,generation,state->client_id(),mm::kManagementVersion,mm::kManagementCapacity);
    if(reply)REQUIRE(shm::publishSnapshot(reply->region(),bytes,size,0));
    return shm::publishSnapshot(region,bytes,size,0);
  }
  void publish(uint64_t revision,uint64_t client=0,uint64_t seq=0,uint64_t epoch=7,
               mm::ManagementAction action=mm::ManagementAction::Catalog,
               mm::ManagementStatus status=mm::ManagementStatus::Ok) {
    flatbuffers::FlatBufferBuilder b;
    std::vector<flatbuffers::Offset<mm::BuildingDefinition>> catalog;
    if(action==mm::ManagementAction::Catalog)
      catalog.push_back(mm::CreateBuildingDefinition(b,b.CreateString("Chair"),b.CreateString("Chair"),1,1,true));
    auto s=mm::CreateManagementState(b,mm::kManagementVersion,revision,epoch,client,seq,action,status,
      b.CreateString("test result"),b.CreateVector(catalog));b.Finish(s);
    REQUIRE_FALSE(mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer())).has_value());
    REQUIRE(write(b.GetBufferPointer(),b.GetSize()));
  }
};
// Fixture preamble: a publisher at revision 1 and a polled client; claim()
// performs the read-only catalog claim (revision 2) every mutation needs.
std::unique_ptr<wm::ManagementClient> openClient(ManagementPublisher& p) {
  std::string error;auto c=wm::ManagementClient::open(error,p.name);REQUIRE(c);REQUIRE(c->poll());return c;
}
struct Claim { uint64_t seq; uint64_t id; };
Claim claim(ManagementPublisher& p,wm::ManagementClient& c) {
  const auto seq=c.send({});REQUIRE(seq>0);const auto id=p.pop()->client_id();p.publish(2,id,seq);REQUIRE(c.poll());return {seq,id};
}
}
TEST_CASE("every retired management action is refused before and after catalog claim") {
  ManagementPublisher p;p.publish(1);auto c=openClient(p);
  auto checkRetired=[&] {
    for (auto action : mm::EnumValuesManagementAction()) {
      if (mm::runtimeManagementAction(action)) continue;
      wm::ManagementRequest r;r.action=static_cast<wm::ManagementAction>(action);
      CHECK(c->send(r)==0);
      CHECK(c->lastError()=="Retired management action");
      CHECK(shm::popCommand(p.region,p.bytes.data(),p.bytes.size())==0);
    }
  };
  checkRetired();
  claim(p,*c);
  checkRetired();
  // The retired gate also precedes pending-request admission.
  REQUIRE(c->send({})>0);p.pop();
  checkRetired();
}
TEST_CASE("management claims catalog before mutations and preserves pending ownership") {
  ManagementPublisher p;p.publish(1);auto c=openClient(p);
  wm::ManagementRequest place;place.action=wm::ManagementAction::Place;place.definition="Chair";place.selections={{0,-1,-1,-1,-1,1,42}};
  CHECK(c->send(place)==0);
  CHECK(c->lastError()=="Refresh the management catalog first");
  auto seq=c->send({}); REQUIRE(seq>0);auto* r=p.pop();const auto id=r->client_id();CHECK(r->seq()==seq);
  CHECK(c->send({})==0);
  CHECK(c->lastError()=="Wait for the current management request");
  p.publish(2,id,seq-1);REQUIRE(c->poll());CHECK(c->state().status==wm::ManagementStatus::Pending);
  CHECK(c->send(place)==0);
  p.publish(3,id,seq);REQUIRE(c->poll());CHECK(c->state().catalog.size()==1);
  auto next=c->send(place);REQUIRE(next>seq);r=p.pop();CHECK(r->world_epoch()==7);CHECK(r->selections()->Get(0)->count()==1);CHECK(r->selections()->Get(0)->expected_list_revision()==42);
  p.publish(4,id,next,7,mm::ManagementAction::Place,mm::ManagementStatus::Rejected);
  REQUIRE(c->poll());CHECK(c->state().status==wm::ManagementStatus::Rejected);
  CHECK(c->send(place)>next);
}
TEST_CASE("management world change cancels pending and requires a new read-only claim") {
  ManagementPublisher p;p.publish(1);auto c=openClient(p);
  auto [seq,id]=claim(p,*c);
  wm::ManagementRequest r;r.action=wm::ManagementAction::Preview;r.definition="Chair";
  REQUIRE(c->send(r)>0);p.pop();
  p.publish(3,0,seq,8,mm::ManagementAction::Catalog,mm::ManagementStatus::Idle);REQUIRE(c->poll());
  CHECK(c->state().worldEpoch==8);CHECK(c->send(r)==0);CHECK(c->send({})>0);
}
TEST_CASE("management follows reload after unloaded epoch despite an old private reply") {
  ManagementPublisher p;p.publish(1);auto client=openClient(p);
  const auto seq=client->send({});REQUIRE(seq);const auto id=p.pop()->client_id();
  p.publish(2,id,seq);REQUIRE(client->poll());CHECK(client->state().worldEpoch==7);
  p.publish(3,0,0,0,mm::ManagementAction::Catalog,mm::ManagementStatus::Idle);
  REQUIRE(client->poll());CHECK(client->state().worldEpoch==0);
  // The old epoch7 receipt remains durable, but must not mask public epoch8.
  p.publish(4,0,0,8,mm::ManagementAction::Catalog,mm::ManagementStatus::Idle);
  REQUIRE(client->poll());CHECK(client->state().worldEpoch==8);
  CHECK_FALSE(client->poll());
  wm::ManagementRequest remove;remove.action=wm::ManagementAction::Remove;remove.buildingId=12;
  CHECK(client->send(remove)==0); // Fresh catalog is still required after reload.
  const auto next=client->send({});REQUIRE(next>seq);p.pop();
  p.publish(5,id,next,8);REQUIRE(client->poll());CHECK(client->send(remove)>next);
}
TEST_CASE("management clients preserve independent ownership; generation prevents stale mutations") {
  ManagementPublisher p;p.publish(1);auto c=openClient(p);std::string error;
  CHECK(c->transportAlive());
  auto [seq,id]=claim(p,*c);
  p.publish(3,id+1,seq+5);CHECK_FALSE(c->poll());CHECK(c->state().status==wm::ManagementStatus::Ok);
  wm::ManagementRequest remove;remove.action=wm::ManagementAction::Remove;remove.buildingId=12;CHECK(c->send(remove)>seq);p.pop();
  shm::atomicStoreRelease(&mm::sessionOwner(p.region)->generation,2);
  CHECK_FALSE(c->transportAlive());
  CHECK_FALSE(c->poll());CHECK(c->send({})==0);CHECK_FALSE(c->lastError().empty());
  auto reconnect=wm::ManagementClient::open(error,p.name);REQUIRE(reconnect);CHECK(reconnect->send(remove)==0);
  CHECK(reconnect->transportAlive());
}
TEST_CASE("management new claim ignores a predating response for the previous viewer") {
  ManagementPublisher p;p.publish(1,123,9);std::string error;
  auto c=wm::ManagementClient::open(error,p.name);REQUIRE(c);c->poll();
  auto seq=c->send({});REQUIRE(seq>0);const auto id=p.pop()->client_id();
  p.publish(2,123,9);c->poll();
  CHECK(c->state().status==wm::ManagementStatus::Pending);
  CHECK(c->send({})==0);
  p.publish(3,id,seq);REQUIRE(c->poll());CHECK(c->state().status==wm::ManagementStatus::Ok);
}
TEST_CASE("management owner replacement requires a fresh private catalog and never replays") {
  ManagementPublisher p;p.publish(1);auto old=openClient(p);std::string error;
  REQUIRE(old->transportAlive());
  const auto claim=old->send({});const auto oldId=p.pop()->client_id();
  p.publish(2,oldId,claim);REQUIRE(old->poll());
  wm::ManagementRequest remove;remove.action=wm::ManagementAction::Remove;remove.buildingId=12;
  const auto uncertain=old->send(remove);REQUIRE(uncertain);p.pop();
  shm::atomicStoreRelease(&mm::sessionOwner(p.region)->generation,2);
  CHECK_FALSE(old->transportAlive());CHECK_FALSE(old->poll());
  CHECK(old->state().worldEpoch==0);CHECK_FALSE(old->lastError().empty());
  auto fresh=wm::ManagementClient::open(error,p.name);REQUIRE(fresh);REQUIRE(fresh->transportAlive());
  REQUIRE(fresh->poll());CHECK(fresh->state().worldEpoch==7);
  CHECK(fresh->send(remove)==0);
  const auto freshClaim=fresh->send({});REQUIRE(freshClaim==claim);
  const auto newId=p.pop()->client_id();CHECK(newId!=oldId);
  CHECK(shm::popCommand(p.region,p.bytes.data(),p.bytes.size())==0);
  // A receipt for the dead client's operation cannot resolve the fresh claim.
  p.publish(3,oldId,uncertain,7,mm::ManagementAction::Remove);
  CHECK_FALSE(fresh->poll());CHECK(fresh->state().status==wm::ManagementStatus::Pending);
  p.publish(4,newId,freshClaim);REQUIRE(fresh->poll());
  CHECK(fresh->state().status==wm::ManagementStatus::Ok);
  const auto requested=fresh->send(remove);REQUIRE(requested>freshClaim);
  CHECK(p.pop()->seq()==requested);
}
TEST_CASE("management unchanged and malformed replies preserve transport ownership") {
  ManagementPublisher p;p.publish(1);auto client=openClient(p);
  CHECK_FALSE(client->poll());CHECK(client->transportAlive());
  const auto seq=client->send({});const auto id=p.pop()->client_id();
  auto mailbox=shm::ClientMailbox::open(p.name,1,id,mm::kManagementVersion,mm::kManagementCapacity);
  REQUIRE(mailbox);
  const uint8_t malformed[]={0xff,0xff,0xff,0xff};
  REQUIRE(shm::publishSnapshot(mailbox->region(),malformed,sizeof(malformed),0));
  CHECK_FALSE(client->poll());CHECK(client->transportAlive());
  CHECK_FALSE(client->lastError().empty());CHECK(client->send({})==0);
  p.publish(2,id,seq);REQUIRE(client->poll());
  CHECK(client->state().status==wm::ManagementStatus::Ok);CHECK(client->lastError().empty());
}
TEST_CASE("two management clients keep durable replies and independent sequence spaces") {
  ManagementPublisher p;p.publish(1);std::string error;
  auto a=wm::ManagementClient::open(error,p.name),b=wm::ManagementClient::open(error,p.name);
  REQUIRE(a);REQUIRE(b);REQUIRE(a->poll());REQUIRE(b->poll());
  REQUIRE(a->send({})==1);const auto aid=p.pop()->client_id();
  REQUIRE(b->send({})==1);const auto bid=p.pop()->client_id();REQUIRE(aid!=bid);
  p.publish(2,aid,1);p.publish(3,bid,1);
  REQUIRE(a->poll());REQUIRE(b->poll());CHECK(a->state().status==wm::ManagementStatus::Ok);CHECK(b->state().status==wm::ManagementStatus::Ok);
  wm::ManagementRequest request;request.action=wm::ManagementAction::Remove;request.buildingId=12;
  REQUIRE(b->send(request)==2);p.pop();p.publish(4,bid,2,7,mm::ManagementAction::Remove,mm::ManagementStatus::Rejected);
  REQUIRE(b->poll());CHECK_FALSE(a->poll());CHECK(a->state().requestSeq==1);
  CHECK(a->send(request)==2);
}
TEST_CASE("management validators reject malformed input identity and inspection ids") {
  for(int which=0;which<5;++which) {
    flatbuffers::FlatBufferBuilder b;mm::TilePos origin(1,2,3);
    std::vector<int32_t> items=which==3?std::vector<int32_t>{8,8}:std::vector<int32_t>{8};
    auto r=mm::CreateConstructionRequest(b,which==0?99:mm::kManagementVersion,1,1,which==1?0:7,
      which==4?mm::ManagementAction::Inspect:mm::ManagementAction::Place,
      b.CreateString("Chair"),&origin,which==2?0:1,1,0,b.CreateVector(items));b.Finish(r);
    CHECK(mm::validateConstructionRequest(*flatbuffers::GetRoot<mm::ConstructionRequest>(b.GetBufferPointer())).has_value());
  }
}
TEST_CASE("area edits preserve requested fields and share construction ownership") {
  ManagementPublisher p;p.publish(1);auto c=openClient(p);
  wm::ManagementRequest edit;edit.action=wm::ManagementAction::AreaUpdate;
  edit.area.id=31;edit.area.categories=4;edit.area.changedCategories=12;
  edit.area.bins=3;
  CHECK(c->send(edit)==0);
  auto seq=c->send({});const auto id=p.pop()->client_id();
  p.publish(2,id,seq);REQUIRE(c->poll());
  seq=c->send(edit);REQUIRE(seq>0);auto* r=p.pop();REQUIRE(r->area());
  CHECK(r->action()==mm::ManagementAction::AreaUpdate);
  CHECK(r->area()->id()==31);CHECK(r->area()->categories()==4);
  CHECK(r->area()->changed_categories()==12);CHECK(r->area()->bins()==3);
  CHECK(r->area()->barrels()==-1);CHECK(r->area()->owner_id()==-2);
  CHECK(r->area()->active()==-1);CHECK(r->world_epoch()==7);
  CHECK(c->send({})==0);
  p.publish(3,id,seq,7,mm::ManagementAction::AreaUpdate);REQUIRE(c->poll());
  wm::ManagementRequest candidates;candidates.action=wm::ManagementAction::AreaCandidates;
  candidates.area.kind=wm::AreaKind::Zone;candidates.area.cursor=128;candidates.area.query="Urist";
  seq=c->send(candidates);REQUIRE(seq>0);r=p.pop();
  CHECK(r->area()->cursor()==128);CHECK(r->area()->query()->str()=="Urist");
  p.publish(4,0,seq,8,mm::ManagementAction::Catalog,mm::ManagementStatus::Idle);
  REQUIRE(c->poll());CHECK(c->send(edit)==0);CHECK(c->send({})>seq);
}
TEST_CASE("area request rejects invalid masks identities and destructive self links") {
  ManagementPublisher p;p.publish(1);auto c=openClient(p);
  auto [seq,id]=claim(p,*c);
  for(int which=0;which<9;++which) {
    wm::ManagementRequest r;r.action=wm::ManagementAction::AreaUpdate;r.area.id=12;
    if(which==0)r.area.changedCategories=0x20000;
    if(which==1)r.area.categories=0x20000;
    if(which==2)r.area.id=-1;
    if(which==3){r.action=wm::ManagementAction::AreaLink;r.area.linkId=12;}
    if(which==4)r.area.ownerId=-3;
    if(which==5)r.area.active=2;
    if(which==6)r.area.query=std::string(129,'x');
    if(which==7)r.area.width=0;
    if(which==8)r.area.x=-1;
    CHECK(c->send(r)==0);CHECK_FALSE(c->lastError().empty());
  }
  wm::ManagementRequest valid;valid.action=wm::ManagementAction::AreaUpdate;valid.area.id=12;
  valid.area.ownerId=-1;CHECK(c->send(valid)>seq);CHECK(p.pop()->area()->owner_id()==-1);
}
TEST_CASE("area response keeps overlapping identities extents links and later candidates") {
  ManagementPublisher p;p.publish(1);auto c=openClient(p);
  auto [seq,id]=claim(p,*c);
  wm::ManagementRequest req;req.action=wm::ManagementAction::AreaInspectAtTile;
  seq=c->send(req);REQUIRE(seq>0);p.pop();
  flatbuffers::FlatBufferBuilder b;mm::TilePos pos(40,50,9);
  auto extents=b.CreateVector(std::vector<uint8_t>{1,0,1,1});
  auto links=b.CreateVector(std::vector<int32_t>{300,900});
  auto label=b.CreateString("Dining room");auto owner=b.CreateString("Urist");
  mm::AreaInfoBuilder first(b);first.add_id(24);first.add_kind(mm::AreaKind::Zone);
  first.add_origin(&pos);first.add_width(2);first.add_height(2);first.add_extents(extents);
  first.add_zone_type(2);first.add_name(label);first.add_owner_id(1024);
  first.add_owner_name(owner);first.add_owner_allowed(true);first.add_active(true);
  auto zone=first.Finish();
  mm::AreaInfoBuilder second(b);second.add_id(25);second.add_origin(&pos);
  second.add_width(2);second.add_height(2);second.add_extents(extents);
  second.add_categories(3);second.add_gives(links);second.add_bins(2);
  auto pile=second.Finish();
  auto choice=mm::CreateAreaChoice(b,4096,b.CreateString("Later citizen"));
  auto area=mm::CreateAreaState(b,b.CreateVector(std::vector<flatbuffers::Offset<mm::AreaInfo>>{zone,pile}),
    b.CreateVector(std::vector<flatbuffers::Offset<mm::AreaChoice>>{choice}),4097,true);
  mm::ManagementStateBuilder result(b);result.add_schema_version(mm::kManagementVersion);
  result.add_revision(3);result.add_world_epoch(7);result.add_client_id(id);result.add_request_seq(seq);
  result.add_action(mm::ManagementAction::AreaInspectAtTile);result.add_status(mm::ManagementStatus::Ok);
  result.add_area(area);b.Finish(result.Finish());
  REQUIRE_FALSE(mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer())).has_value());
  REQUIRE(p.write(b.GetBufferPointer(),b.GetSize()));REQUIRE(c->poll());
  const auto& a=c->state().area;REQUIRE(a.areas.size()==2);CHECK(a.areas[0].id==24);
  CHECK(a.areas[0].kind==wm::AreaKind::Zone);CHECK(a.areas[0].ownerId==1024);
  CHECK(a.areas[0].ownerName=="Urist");CHECK(a.areas[0].ownerAllowed);CHECK(a.areas[0].active);
  CHECK(a.areas[0].x==40);CHECK(a.areas[0].y==50);CHECK(a.areas[0].z==9);
  CHECK(a.areas[0].extents==std::vector<uint8_t>{1,0,1,1});
  CHECK(a.areas[1].gives==std::vector<int32_t>{300,900});CHECK(a.areas[1].bins==2);
  REQUIRE(a.choices.size()==1);CHECK(a.choices[0].id==4096);CHECK(a.nextCursor==4097);CHECK(a.truncated);
  // A later non-area response must not retain stale selection data.
  seq=c->send({});REQUIRE(seq>0);p.pop();p.publish(4,id,seq);REQUIRE(c->poll());
  CHECK(c->state().area.areas.empty());CHECK(c->state().area.choices.empty());
}
TEST_CASE("area response rejects corrupt footprints and ambiguous identities") {
  for(int which=0;which<5;++which) {
    flatbuffers::FlatBufferBuilder b;mm::TilePos pos(which==0?-1:2,3,4);
    auto extents=b.CreateVector(which==1?std::vector<uint8_t>{1}:std::vector<uint8_t>{1,which==2?uint8_t(2):uint8_t(0)});
    auto links=b.CreateVector(which==3?std::vector<int32_t>{7,7}:std::vector<int32_t>{7});
    mm::AreaInfoBuilder info(b);info.add_id(12);info.add_origin(&pos);
    info.add_width(2);info.add_height(1);info.add_extents(extents);info.add_gives(links);
    auto one=info.Finish();std::vector<flatbuffers::Offset<mm::AreaInfo>> entries{one};
    if(which==4)entries.push_back(one);
    auto area=mm::CreateAreaState(b,b.CreateVector(entries));
    mm::ManagementStateBuilder result(b);result.add_schema_version(mm::kManagementVersion);
    result.add_revision(1);result.add_world_epoch(7);result.add_action(mm::ManagementAction::AreaInspect);
    result.add_status(mm::ManagementStatus::Ok);result.add_area(area);b.Finish(result.Finish());
    CHECK(mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer())).has_value());
  }
}
TEST_CASE("production requests retain job identity sentinels and shared ownership") {
  ManagementPublisher p;p.publish(1);auto c=openClient(p);
  wm::ManagementRequest queue;queue.action=wm::ManagementAction::ProductionQueue;
  queue.production.buildingId=72;queue.production.recipe="builtin:12:-1";queue.production.repeat=1;
  CHECK(c->send(queue)==0);
  auto [seq,id]=claim(p,*c);
  seq=c->send(queue);REQUIRE(seq>0);auto* r=p.pop();REQUIRE(r->production());CHECK(r->area()==nullptr);
  CHECK(r->production()->building_id()==72);CHECK(r->production()->recipe()->str()=="builtin:12:-1");
  CHECK(r->production()->repeat()==1);CHECK(r->production()->suspend()==-1);CHECK(r->world_epoch()==7);
  CHECK(c->send(queue)==0);p.publish(3,id,seq,7,mm::ManagementAction::ProductionQueue);REQUIRE(c->poll());
  wm::ManagementRequest edit;edit.action=wm::ManagementAction::ProductionJobEdit;
  edit.production.buildingId=72;edit.production.jobId=504;edit.production.suspend=1;
  seq=c->send(edit);REQUIRE(seq>0);r=p.pop();CHECK(r->production()->job_id()==504);
  CHECK(r->production()->repeat()==-1);CHECK(r->production()->suspend()==1);CHECK_FALSE(r->production()->cancel());
  p.publish(4,id,seq,7,mm::ManagementAction::ProductionJobEdit);REQUIRE(c->poll());
  wm::ManagementRequest farm;farm.action=wm::ManagementAction::FarmSetCrop;
  farm.production.buildingId=80;farm.production.season=3;farm.production.cropId=-1;
  seq=c->send(farm);REQUIRE(seq>0);r=p.pop();CHECK(r->production()->season()==3);CHECK(r->production()->crop_id()==-1);
  p.publish(5,0,seq,8,mm::ManagementAction::Catalog,mm::ManagementStatus::Idle);REQUIRE(c->poll());
  CHECK(c->send(queue)==0);CHECK(c->send(edit)==0);CHECK(c->send({})>seq);
}
TEST_CASE("production validation rejects ambiguous job edits and invalid crop narrowing") {
  ManagementPublisher p;p.publish(1);auto c=openClient(p);
  auto [seq,id]=claim(p,*c);
  for(int which=0;which<8;++which) {
    wm::ManagementRequest r;r.action=wm::ManagementAction::ProductionJobEdit;
    r.production.buildingId=72;r.production.jobId=504;r.production.cancel=true;
    if(which==0)r.production.buildingId=-1;
    if(which==1)r.production.jobId=-1;
    if(which==2)r.production.repeat=1;
    if(which==3){r.production.cancel=false;r.production.suspend=2;}
    if(which==4){r.action=wm::ManagementAction::ProductionQueue;r.production.recipe="";}
    if(which==5){r.action=wm::ManagementAction::FarmSetCrop;r.production.season=-1;}
    if(which==6){r.action=wm::ManagementAction::FarmSetCrop;r.production.season=0;r.production.cropId=32768;}
    if(which==7)r.production.query=std::string(129,'x');
    CHECK(c->send(r)==0);CHECK_FALSE(c->lastError().empty());
  }
  wm::ManagementRequest list;list.action=wm::ManagementAction::ProductionList;
  list.production.query="Carpenters";list.production.cursor=128;
  CHECK(c->send(list)>seq);const auto* r=p.pop();CHECK(r->production()->cursor()==128);
  CHECK(r->production()->query()->str()=="Carpenters");
}
TEST_CASE("production response preserves native job progress and recipe requirements") {
  ManagementPublisher p;p.publish(1);auto c=openClient(p);
  auto [seq,id]=claim(p,*c);
  wm::ManagementRequest req;req.action=wm::ManagementAction::ProductionInspect;req.production.buildingId=72;
  seq=c->send(req);REQUIRE(seq>0);p.pop();
  flatbuffers::FlatBufferBuilder b;mm::TilePos pos(2,3,4);
  auto need=mm::CreateProductionRequirement(b,b.CreateString("Wood"),1,5);
  auto needs=b.CreateVector(std::vector<flatbuffers::Offset<mm::ProductionRequirement>>{need});
  auto recipe=mm::CreateProductionRecipe(b,b.CreateString("builtin:12:-1"),b.CreateString("Construct bed"),needs);
  auto name=b.CreateString("Construct bed"),worker=b.CreateString("Urist"),status=b.CreateString("Worker assigned");
  mm::ProductionJobBuilder job(b);job.add_id(504);job.add_job_type(12);job.add_name(name);
  job.add_worker_id(42);job.add_worker_name(worker);job.add_completion_timer(17);job.add_attached_items(1);
  job.add_repeat(true);job.add_editable(true);job.add_status(status);job.add_requirements(needs);
  auto jobRecord=job.Finish();
  auto waitingName=b.CreateString("Construct bed"),emptyWorker=b.CreateString(""),suspendedStatus=b.CreateString("Suspended by native state");
  auto emptyNeeds=b.CreateVector(std::vector<flatbuffers::Offset<mm::ProductionRequirement>>{});
  mm::ProductionJobBuilder suspended(b);suspended.add_id(505);suspended.add_job_type(12);suspended.add_name(waitingName);
  suspended.add_suspended(true);suspended.add_worker_name(emptyWorker);suspended.add_status(suspendedStatus);suspended.add_requirements(emptyNeeds);
  auto suspendedRecord=suspended.Finish();
  auto building=mm::CreateProductionBuilding(b,72,b.CreateString("Carpenters #72"),b.CreateString("Carpenters"),&pos,2,3,2);
  auto buildings=b.CreateVector(std::vector<flatbuffers::Offset<mm::ProductionBuilding>>{building});
  auto recipes=b.CreateVector(std::vector<flatbuffers::Offset<mm::ProductionRecipe>>{recipe});
  auto jobs=b.CreateVector(std::vector<flatbuffers::Offset<mm::ProductionJob>>{jobRecord,suspendedRecord});
  auto detail=b.CreateString("Native workers select and haul inputs; queueing does not guarantee materials or labor. Work orders are not yet exposed.");
  mm::ProductionStateBuilder state(b);state.add_buildings(buildings);state.add_recipes(recipes);
  state.add_jobs(jobs);state.add_detail(detail);state.add_next_cursor(80);state.add_selected_building(72);state.add_created_job(504);auto production=state.Finish();
  mm::ManagementStateBuilder result(b);result.add_schema_version(mm::kManagementVersion);result.add_revision(3);
  result.add_world_epoch(7);result.add_client_id(id);result.add_request_seq(seq);
  result.add_action(mm::ManagementAction::ProductionInspect);result.add_status(mm::ManagementStatus::Ok);
  result.add_production(production);b.Finish(result.Finish());
  REQUIRE_FALSE(mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer())).has_value());
  REQUIRE(p.write(b.GetBufferPointer(),b.GetSize()));REQUIRE(c->poll());
  const auto& v=c->state().production;REQUIRE(v.jobs.size()==2);REQUIRE(v.recipes.size()==1);REQUIRE(v.buildings.size()==1);
  CHECK(v.selectedBuilding==72);CHECK(v.createdJob==504);CHECK(v.buildings[0].z==4);
  CHECK(v.jobs[0].id==504);CHECK(v.jobs[0].workerId==42);CHECK(v.jobs[0].workerName=="Urist");
  CHECK(v.jobs[0].completionTimer==17);CHECK(v.jobs[0].attachedItems==1);CHECK(v.jobs[0].repeat);CHECK(v.jobs[0].editable);
  REQUIRE(v.jobs[0].requirements.size()==1);CHECK(v.jobs[0].requirements[0].quantity==1);
  CHECK(v.recipes[0].requirements[0].description=="Wood");
  CHECK(v.nextCursor==80);CHECK(v.currentSeason==-1);CHECK(v.crops.empty());CHECK(v.seasonalCrops.empty());
  CHECK(v.detail=="Native workers select and haul inputs; queueing does not guarantee materials or labor. Work orders are not yet exposed.");
  const auto& buildingValue=v.buildings[0];
  CHECK(buildingValue.id==72);CHECK(buildingValue.name=="Carpenters #72");CHECK(buildingValue.kind=="Carpenters");
  CHECK(buildingValue.x==2);CHECK(buildingValue.y==3);CHECK(buildingValue.buildStage==2);CHECK(buildingValue.maxStage==3);CHECK(buildingValue.queueSize==2);
  CHECK(v.recipes[0].key=="builtin:12:-1");CHECK(v.recipes[0].name=="Construct bed");
  REQUIRE(v.recipes[0].requirements.size()==1);CHECK(v.recipes[0].requirements[0].quantity==1);CHECK(v.recipes[0].requirements[0].itemType==5);
  CHECK(v.jobs[0].name=="Construct bed");CHECK(v.jobs[0].jobType==12);CHECK_FALSE(v.jobs[0].suspended);CHECK(v.jobs[0].status=="Worker assigned");
  CHECK(v.jobs[0].requirements[0].description=="Wood");CHECK(v.jobs[0].requirements[0].itemType==5);
  CHECK(v.jobs[1].id==505);CHECK(v.jobs[1].name=="Construct bed");CHECK(v.jobs[1].jobType==12);
  CHECK_FALSE(v.jobs[1].repeat);CHECK(v.jobs[1].suspended);CHECK_FALSE(v.jobs[1].editable);CHECK(v.jobs[1].workerId==-1);
  CHECK(v.jobs[1].workerName.empty());CHECK(v.jobs[1].completionTimer==-1);CHECK(v.jobs[1].attachedItems==0);
  CHECK(v.jobs[1].status=="Suspended by native state");CHECK(v.jobs[1].requirements.empty());
  req.production.buildingId=80;seq=c->send(req);REQUIRE(seq>0);p.pop();
  flatbuffers::FlatBufferBuilder fb;
  auto crop0=mm::CreateFarmCrop(fb,0,fb.CreateString("allseason"),15,600);
  auto crop1=mm::CreateFarmCrop(fb,1,fb.CreateString("spring only"),1,0);
  auto crops=fb.CreateVector(std::vector{crop0,crop1});auto seasons=fb.CreateVector(std::vector<int32_t>{0,-1,1,-1});
  auto farmDetail=fb.CreateString("Seasonal crop selection; seed counts are informational. Fertilization and new farm placement are not yet exposed.");
  mm::ProductionStateBuilder farm(fb);farm.add_crops(crops);farm.add_seasonal_crops(seasons);farm.add_current_season(2);
  farm.add_selected_building(80);farm.add_detail(farmDetail);auto farmRecord=farm.Finish();
  mm::ManagementStateBuilder farmResult(fb);farmResult.add_schema_version(mm::kManagementVersion);farmResult.add_revision(4);
  farmResult.add_world_epoch(7);farmResult.add_client_id(id);farmResult.add_request_seq(seq);
  farmResult.add_action(mm::ManagementAction::ProductionInspect);farmResult.add_status(mm::ManagementStatus::Ok);
  farmResult.add_production(farmRecord);fb.Finish(farmResult.Finish());
  REQUIRE_FALSE(mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(fb.GetBufferPointer())).has_value());
  REQUIRE(p.write(fb.GetBufferPointer(),fb.GetSize()));REQUIRE(c->poll());
  const auto& f=c->state().production;REQUIRE(f.crops.size()==2);
  CHECK(f.crops[0].id==0);CHECK(f.crops[0].name=="allseason");CHECK(f.crops[0].seasons==15);CHECK(f.crops[0].seeds==600);
  CHECK(f.crops[1].id==1);CHECK(f.crops[1].name=="spring only");CHECK(f.crops[1].seasons==1);CHECK(f.crops[1].seeds==0);
  CHECK(f.seasonalCrops==std::vector<int32_t>{0,-1,1,-1});CHECK(f.currentSeason==2);CHECK(f.selectedBuilding==80);
  CHECK(f.nextCursor==0);CHECK(f.createdJob==-1);CHECK(f.jobs.empty());CHECK(f.recipes.empty());CHECK(f.buildings.empty());
  CHECK(f.detail=="Seasonal crop selection; seed counts are informational. Fertilization and new farm placement are not yet exposed.");
  seq=c->send({});REQUIRE(seq>0);p.pop();p.publish(5,id,seq);REQUIRE(c->poll());
  CHECK(c->state().production.jobs.empty());CHECK(c->state().production.createdJob==-1);
}
TEST_CASE("work orders share ownership and retain revision and unchanged-field sentinels") {
  ManagementPublisher p;p.publish(1);auto c=openClient(p);
  wm::ManagementRequest create;create.action=wm::ManagementAction::WorkOrderCreate;
  create.workOrder.recipe="builtin:69:-1";create.workOrder.remaining=32767;create.workOrder.frequency=1;
  CHECK(c->send(create)==0);
  auto [seq,client]=claim(p,*c);
  seq=c->send(create);REQUIRE(seq>0);auto* request=p.pop();REQUIRE(request->work_order());
  CHECK(request->area()==nullptr);CHECK(request->production()==nullptr);
  CHECK(request->work_order()->remaining()==32767);CHECK(request->work_order()->frequency()==1);
  CHECK(request->work_order()->recipe()->str()=="builtin:69:-1");
  CHECK(c->send(create)==0);p.publish(3,client,seq,7,mm::ManagementAction::WorkOrderCreate);REQUIRE(c->poll());
  wm::ManagementRequest update;update.action=wm::ManagementAction::WorkOrderUpdate;
  update.workOrder.id=0;update.workOrder.expectedRevision=(uint64_t(1)<<40)+7;update.workOrder.frequency=2;
  seq=c->send(update);REQUIRE(seq>0);request=p.pop();
  CHECK(request->work_order()->id()==0);CHECK(request->work_order()->expected_revision()==(uint64_t(1)<<40)+7);
  CHECK(request->work_order()->remaining()==-1);CHECK(request->work_order()->workshop_id()==-2);
  CHECK(request->work_order()->max_workshops()==-1);
  p.publish(4,client,seq,7,mm::ManagementAction::WorkOrderUpdate);REQUIRE(c->poll());
  wm::ManagementRequest condition;condition.action=wm::ManagementAction::WorkOrderCondition;
  condition.workOrder.id=0;condition.workOrder.expectedRevision=19;
  condition.workOrder.conditionKind=1;condition.workOrder.targetOrder=9;condition.workOrder.dependency=1;
  seq=c->send(condition);REQUIRE(seq>0);request=p.pop();
  CHECK(request->work_order()->condition_index()==-1);CHECK(request->work_order()->target_order()==9);
  CHECK(request->work_order()->dependency()==1);CHECK_FALSE(request->work_order()->remove_condition());
  p.publish(5,0,seq,8,mm::ManagementAction::Catalog,mm::ManagementStatus::Idle);REQUIRE(c->poll());
  CHECK(c->send(update)==0);CHECK(c->send(condition)==0);CHECK(c->send({})>seq);
}
TEST_CASE("work order inputs reject narrowing overflow and ambiguous condition edits") {
  ManagementPublisher p;p.publish(1);auto c=openClient(p);
  auto [seq,client]=claim(p,*c);
  for(int which=0;which<11;++which){
    wm::ManagementRequest r;r.action=wm::ManagementAction::WorkOrderCreate;
    r.workOrder.recipe="builtin:69:-1";r.workOrder.remaining=1;r.workOrder.frequency=0;
    if(which==0)r.workOrder.remaining=32768;
    if(which==1)r.workOrder.remaining=-2;
    if(which==2)r.workOrder.frequency=5;
    if(which==3)r.workOrder.workshopId=-3;
    if(which==4)r.workOrder.maxWorkshops=-2;
    if(which==5)r.workOrder.recipe="";
    if(which==6)r.workOrder.query=std::string(129,'x');
    if(which==7){r.action=wm::ManagementAction::WorkOrderDelete;r.workOrder.id=0;r.workOrder.expectedRevision=0;}
    if(which>=8){r.action=wm::ManagementAction::WorkOrderCondition;r.workOrder.id=0;r.workOrder.expectedRevision=9;
      r.workOrder.conditionKind=which==8?2:0;r.workOrder.conditionIndex=which==9?-2:-1;
      r.workOrder.compare=3;r.workOrder.threshold=1;r.workOrder.itemType=2;
      if(which==10){r.workOrder.conditionKind=1;r.workOrder.targetOrder=0;r.workOrder.dependency=1;}}

    CHECK(c->send(r)==0);CHECK_FALSE(c->lastError().empty());
  }
  wm::ManagementRequest forever;forever.action=wm::ManagementAction::WorkOrderCreate;
  forever.workOrder.recipe="builtin:69:-1";forever.workOrder.remaining=0;forever.workOrder.frequency=0;
  REQUIRE(c->send(forever)>seq);CHECK(p.pop()->work_order()->remaining()==0);
}
TEST_CASE("work order response keeps native authorization conditions and manager observations") {
  ManagementPublisher p;p.publish(1);auto c=openClient(p);
  auto [seq,client]=claim(p,*c);
  wm::ManagementRequest inspect;inspect.action=wm::ManagementAction::WorkOrderInspect;inspect.workOrder.id=0;
  seq=c->send(inspect);REQUIRE(seq>0);p.pop();
  flatbuffers::FlatBufferBuilder b;
  auto countDescription=b.CreateString("BLOCKS LessThan 10");
  mm::WorkOrderConditionBuilder count(b);count.add_kind(0);count.add_index(0);count.add_description(countDescription);
  count.add_editable(true);count.add_compare(3);count.add_threshold(10);count.add_item_type(2);auto countRecord=count.Finish();
  auto depDescription=b.CreateString("Order #9 Completed");
  mm::WorkOrderConditionBuilder dependency(b);dependency.add_kind(1);dependency.add_index(0);
  dependency.add_description(depDescription);dependency.add_target_order(9);dependency.add_dependency(1);
  dependency.add_satisfied(true);dependency.add_editable(true);auto dependencyRecord=dependency.Finish();
  auto conditions=b.CreateVector(std::vector<flatbuffers::Offset<mm::WorkOrderCondition>>{countRecord,dependencyRecord});
  auto generated=b.CreateVector(std::vector<int32_t>{555});auto name=b.CreateString("Make wooden bed");
  auto reason=b.CreateString("Finish outstanding jobs before editing");
  mm::WorkOrderInfoBuilder order(b);order.add_id(0);order.add_revision((uint64_t(1)<<40)+7);order.add_name(name);
  order.add_total(12);order.add_remaining(3);order.add_frequency(1);order.add_validated(true);order.add_active(false);
  order.add_finished_year(106);order.add_finished_tick(400000);order.add_workshop_id(4);order.add_max_workshops(2);
  order.add_generated_jobs(generated);order.add_conditions(conditions);order.add_editable(false);order.add_reason(reason);
  auto orderRecord=order.Finish();
  auto offices=b.CreateVector(std::vector<int32_t>{1492,1493});auto managerName=b.CreateString("Urist");
  auto position=b.CreateString("Manager");auto job=b.CreateString("Validate work orders");
  mm::ManagerRoleBuilder manager(b);manager.add_unit_id(42);manager.add_name(managerName);
  manager.add_position(position);manager.add_offices(offices);manager.add_job(job);auto managerRecord=manager.Finish();
  auto orders=b.CreateVector(std::vector<flatbuffers::Offset<mm::WorkOrderInfo>>{orderRecord});
  auto managers=b.CreateVector(std::vector<flatbuffers::Offset<mm::ManagerRole>>{managerRecord});
  auto recipe=mm::CreateProductionRecipe(b,b.CreateString("Carpenters:10:-1"),b.CreateString("make bed"));
  auto recipes=b.CreateVector(std::vector<flatbuffers::Offset<mm::ProductionRecipe>>{recipe});
  auto choice=mm::CreateAreaChoice(b,4,b.CreateString("Carpenter's Workshop #4"));
  auto choices=b.CreateVector(std::vector<flatbuffers::Offset<mm::AreaChoice>>{choice});
  auto detail=b.CreateString("Manager observations");
  mm::WorkOrderStateBuilder domain(b);domain.add_orders(orders);domain.add_managers(managers);
  domain.add_recipes(recipes);domain.add_choices(choices);domain.add_detail(detail);
  domain.add_next_cursor(71);auto workOrder=domain.Finish();
  mm::ManagementStateBuilder state(b);state.add_schema_version(mm::kManagementVersion);state.add_revision(3);
  state.add_world_epoch(7);state.add_client_id(client);state.add_request_seq(seq);
  state.add_action(mm::ManagementAction::WorkOrderInspect);state.add_status(mm::ManagementStatus::Ok);
  state.add_work_order(workOrder);b.Finish(state.Finish());
  REQUIRE_FALSE(mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer())).has_value());
  REQUIRE(p.write(b.GetBufferPointer(),b.GetSize()));REQUIRE(c->poll());
  const auto& value=c->state().workOrder;REQUIRE(value.orders.size()==1);REQUIRE(value.managers.size()==1);
  CHECK(value.nextCursor==71);const auto& observed=value.orders[0];CHECK(observed.id==0);
  CHECK(observed.revision==(uint64_t(1)<<40)+7);CHECK(observed.total==12);CHECK(observed.remaining==3);
  CHECK(observed.validated);CHECK_FALSE(observed.active);CHECK(observed.finishedYear==106);CHECK(observed.finishedTick==400000);
  CHECK(observed.workshopId==4);REQUIRE(observed.generatedJobs.size()==1);CHECK(observed.generatedJobs[0]==555);
  REQUIRE(observed.conditions.size()==2);CHECK(observed.conditions[0].threshold==10);
  CHECK(observed.name=="Make wooden bed");CHECK(observed.reason=="Finish outstanding jobs before editing");
  CHECK(observed.frequency==1);CHECK(observed.maxWorkshops==2);CHECK_FALSE(observed.editable);
  const auto& item=observed.conditions[0];CHECK(item.kind==0);CHECK(item.index==0);
  CHECK(item.description=="BLOCKS LessThan 10");CHECK(item.editable);CHECK(item.compare==3);
  CHECK(item.itemType==2);CHECK(item.targetOrder==-1);CHECK(item.dependency==-1);CHECK_FALSE(item.satisfied);
  const auto& dep=observed.conditions[1];CHECK(dep.kind==1);CHECK(dep.index==0);
  CHECK(dep.description=="Order #9 Completed");CHECK(dep.editable);CHECK(dep.compare==-1);
  CHECK(dep.threshold==-1);CHECK(dep.itemType==-1);CHECK(dep.targetOrder==9);CHECK(dep.dependency==1);CHECK(dep.satisfied);
  REQUIRE(value.recipes.size()==1);CHECK(value.recipes[0].key=="Carpenters:10:-1");
  CHECK(value.recipes[0].name=="make bed");CHECK(value.recipes[0].requirements.empty());
  REQUIRE(value.choices.size()==1);CHECK(value.choices[0].id==4);CHECK(value.choices[0].name=="Carpenter's Workshop #4");
  CHECK(value.detail=="Manager observations");
  CHECK(value.managers[0].unitId==42);CHECK(value.managers[0].name=="Urist");
  CHECK(value.managers[0].position=="Manager");CHECK(value.managers[0].job=="Validate work orders");
  REQUIRE(value.managers[0].offices.size()==2);CHECK(value.managers[0].offices[0]==1492);CHECK(value.managers[0].offices[1]==1493);
  seq=c->send({});REQUIRE(seq>0);p.pop();p.publish(4,client,seq);REQUIRE(c->poll());
  CHECK(c->state().workOrder.orders.empty());CHECK(c->state().workOrder.managers.empty());
  CHECK(c->state().workOrder.recipes.empty());CHECK(c->state().workOrder.choices.empty());
  CHECK(c->state().workOrder.detail.empty());CHECK(c->state().workOrder.nextCursor==0);
}
TEST_CASE("citizen commands retain stable unit identity and guarded detail index zero") {
  ManagementPublisher p;p.publish(1);auto c=openClient(p);
  wm::ManagementRequest r;r.action=wm::ManagementAction::WorkDetailMembership;
  r.citizen.unitId=0;r.citizen.detailIndex=0;r.citizen.expectedRevision=(uint64_t(1)<<40)+3;r.citizen.member=1;
  CHECK(c->send(r)==0);
  auto [seq,client]=claim(p,*c);
  seq=c->send(r);REQUIRE(seq>0);const auto* wire=p.pop();REQUIRE(wire->citizen());
  CHECK(wire->citizen()->unit_id()==0);CHECK(wire->citizen()->detail_index()==0);
  CHECK(wire->citizen()->expected_revision()==(uint64_t(1)<<40)+3);
  CHECK(wire->citizen()->member()==1);CHECK(wire->citizen()->mode()==-1);
  CHECK(wire->work_order()==nullptr);CHECK(wire->production()==nullptr);CHECK(c->send(r)==0);
  p.publish(3,client,seq,7,mm::ManagementAction::WorkDetailMembership);REQUIRE(c->poll());
  r.action=wm::ManagementAction::WorkDetailMode;r.citizen.unitId=-1;r.citizen.member=-1;r.citizen.mode=0;
  seq=c->send(r);REQUIRE(seq>0);wire=p.pop();CHECK(wire->citizen()->mode()==0);CHECK(wire->citizen()->member()==-1);
  p.publish(4,0,seq,8,mm::ManagementAction::Catalog,mm::ManagementStatus::Idle);REQUIRE(c->poll());
  CHECK(c->send(r)==0);CHECK(c->send({})>seq);
}
TEST_CASE("citizen command validation rejects ambiguous edits and stale receipt sentinels") {
  ManagementPublisher p;p.publish(1);auto c=openClient(p);
  auto [seq,client]=claim(p,*c);
  for(int which=0;which<10;++which){
    wm::ManagementRequest r;r.action=wm::ManagementAction::WorkDetailMembership;
    r.citizen.unitId=42;r.citizen.detailIndex=0;r.citizen.expectedRevision=9;r.citizen.member=1;
    if(which==0)r.citizen.unitId=-1;
    if(which==1)r.citizen.detailIndex=-1;
    if(which==2)r.citizen.detailIndex=128;
    if(which==3)r.citizen.expectedRevision=0;
    if(which==4)r.citizen.member=2;
    if(which==5)r.citizen.mode=1;
    if(which==6){r.action=wm::ManagementAction::WorkDetailMode;r.citizen.member=-1;r.citizen.mode=4;}
    if(which==7)r.citizen.query=std::string(129,'x');
    if(which==8)r.citizen.expectedRevision=uint64_t(1)<<63;
    if(which==9)r.action=wm::ManagementAction::CitizenList;
    CHECK(c->send(r)==0);CHECK_FALSE(c->lastError().empty());
  }
  wm::ManagementRequest list;list.action=wm::ManagementAction::CitizenList;list.citizen.query="Urist";list.citizen.cursor=64;
  REQUIRE(c->send(list)>seq);const auto* wire=p.pop();CHECK(wire->citizen()->cursor()==64);CHECK(wire->citizen()->query()->str()=="Urist");
}
TEST_CASE("citizen response preserves native labor roles and built-in definition flags") {
 for(bool extended : {false,true}) {
  ManagementPublisher p;p.publish(1);auto c=openClient(p);
  auto [seq,client]=claim(p,*c);
  wm::ManagementRequest request;request.action=wm::ManagementAction::CitizenInspect;request.citizen.unitId=0;
  seq=c->send(request);REQUIRE(seq>0);p.pop();
  flatbuffers::FlatBufferBuilder b;mm::TilePos pos(17,29,128);
  auto labors=b.CreateVector(std::vector<int16_t>{0,1});
  auto laborNames=b.CreateVector(std::vector<flatbuffers::Offset<flatbuffers::String>>{b.CreateString("mine"),b.CreateString("haul stone")});
  auto role=mm::CreateCitizenRole(b,b.CreateString("Manager"),250);
  auto roles=b.CreateVector(std::vector<flatbuffers::Offset<mm::CitizenRole>>{role});
  auto offices=b.CreateVector(std::vector<int32_t>{2348});
  auto name=b.CreateString("Urist"),profession=b.CreateString("Carpenter"),job=b.CreateString("Construct bed");
  auto emptyReason=b.CreateString("");
  auto iconPages=b.CreateVectorOfStrings(std::vector<std::string>{"DWARF"});
  auto iconPalettes=b.CreateVectorOfStrings(std::vector<std::string>{"graphics/images/palette.png"});
  auto iconLayers=b.CreateVectorOfStructs(std::vector<mm::AppearanceLayer>{mm::AppearanceLayer(0,2,3,1,1,0,4,0,0,0)});
  auto sheetIcon=mm::CreateSelectionAppearance(b,iconPages,iconPalettes,iconLayers);
  auto assignment=mm::CreateCitizenWorkDetail(b,2,10,b.CreateString("Millers"));
  auto assignments=b.CreateVector(std::vector<flatbuffers::Offset<mm::CitizenWorkDetail>>{assignment});
  mm::CitizenInfoBuilder unit(b);unit.add_id(0);unit.add_name(name);unit.add_profession(profession);unit.add_job(job);
  unit.add_reason(emptyReason);
  if(extended){unit.add_social_activity(true);unit.add_sheet_icon(sheetIcon);unit.add_only_assigned_jobs(true);unit.add_assigned_details(assignments);unit.add_profession_color(13);unit.add_profession_id(17);unit.add_job_type(32);}
  unit.add_age(42);unit.add_stress(-10000);unit.add_has_stress(true);unit.add_origin(&pos);unit.add_can_focus(true);
  unit.add_eligible(true);unit.add_labors(labors);unit.add_labor_names(laborNames);unit.add_roles(roles);unit.add_offices(offices);auto person=unit.Finish();
  auto groupName=b.CreateString("Woodworkers");auto assigned=b.CreateVector(std::vector<int32_t>{0,42});
  // The extended case deliberately distinguishes codec flags; the base case matches citizens.lua.
  auto detailReason=b.CreateString(extended?"Native work-detail mode is protected":"An external labor controller owns assignments");
  mm::WorkDetailInfoBuilder detail(b);detail.add_index(0);detail.add_revision((uint64_t(1)<<40)+3);
  detail.add_reason(detailReason);
  detail.add_name(groupName);detail.add_mode(3);detail.add_no_modify(true);detail.add_cannot_be_everybody(false);
  detail.add_editable(extended);detail.add_mode_editable(false);detail.add_labors(labors);detail.add_labor_names(laborNames);detail.add_assigned_units(assigned);
  auto group=detail.Finish();
  auto citizens=b.CreateVector(std::vector<flatbuffers::Offset<mm::CitizenInfo>>{person});
  auto groups=b.CreateVector(std::vector<flatbuffers::Offset<mm::WorkDetailInfo>>{group});
  mm::CitizenStateBuilder domain(b);domain.add_citizens(citizens);domain.add_details(groups);domain.add_next_cursor(64);
  domain.add_external_controller(!extended);domain.add_selected_unit(0);domain.add_selected_detail(0);auto data=domain.Finish();
  mm::ManagementStateBuilder state(b);state.add_schema_version(mm::kManagementVersion);state.add_revision(3);
  state.add_world_epoch(7);state.add_client_id(client);state.add_request_seq(seq);
  state.add_action(mm::ManagementAction::CitizenInspect);state.add_status(mm::ManagementStatus::Ok);state.add_citizen(data);
  b.Finish(state.Finish());
  REQUIRE_FALSE(mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer())).has_value());
  REQUIRE(p.write(b.GetBufferPointer(),b.GetSize()));REQUIRE(c->poll());
  const auto& result=c->state().citizen;REQUIRE(result.citizens.size()==1);REQUIRE(result.details.size()==1);
  CHECK(result.selectedUnit==0);CHECK(result.selectedDetail==0);CHECK(result.nextCursor==64);
  const auto& u=result.citizens[0];CHECK(u.professionColor==(extended?13:-1));CHECK(u.professionId==(extended?17:-1));CHECK(u.jobType==(extended?32:-1));CHECK(u.id==0);CHECK(u.name=="Urist");CHECK(u.age==42);CHECK(u.stress==-10000);
  CHECK(u.socialActivity==extended);CHECK(u.onlyAssignedJobs==extended);CHECK(u.assignedDetails.size()==(extended?1:0));CHECK(u.sheetIcon.layers.size()==(extended?1:0));
  if(extended){CHECK(u.assignedDetails[0].index==2);CHECK(u.assignedDetails[0].icon==10);CHECK(u.assignedDetails[0].name=="Millers");CHECK(u.sheetIcon.tilePages[0]=="DWARF");CHECK(u.sheetIcon.palettes[0]=="graphics/images/palette.png");CHECK(u.sheetIcon.layers[0].tileX==2);CHECK(u.sheetIcon.layers[0].paletteRow==4);}
  CHECK(u.hasStress);CHECK(u.canFocus);CHECK(u.z==128);CHECK(u.eligible);REQUIRE(u.labors.size()==2);CHECK(u.labors[1]==1);
  REQUIRE(u.laborNames.size()==2);CHECK(u.laborNames[0]=="mine");
  REQUIRE(u.roles.size()==1);CHECK(u.roles[0].name=="Manager");CHECK(u.roles[0].requiredOffice==250);
  REQUIRE(u.offices.size()==1);CHECK(u.offices[0]==2348);
  const auto& d=result.details[0];CHECK(d.index==0);CHECK(d.revision==(uint64_t(1)<<40)+3);
  CHECK(d.noModify);CHECK(d.editable==extended);CHECK_FALSE(d.modeEditable);CHECK_FALSE(d.cannotBeEverybody);CHECK(d.mode==3);
  CHECK(d.name=="Woodworkers");CHECK(d.reason==(extended?"Native work-detail mode is protected":"An external labor controller owns assignments"));
  CHECK(d.labors==std::vector<int16_t>{0,1});
  CHECK(d.laborNames==std::vector<std::string>{"mine","haul stone"});
  CHECK(d.assignedUnits==std::vector<int32_t>{0,42});
  CHECK(u.reason.empty());CHECK(u.profession=="Carpenter");
  CHECK(u.laborNames==std::vector<std::string>{"mine","haul stone"});
  seq=c->send({});REQUIRE(seq>0);p.pop();p.publish(4,client,seq);REQUIRE(c->poll());
  CHECK(c->state().citizen.citizens.empty());CHECK(c->state().citizen.details.empty());CHECK(c->state().citizen.selectedUnit==-1);
 }
}
TEST_CASE("citizen validator rejects ambiguous membership and misaligned labor labels") {
  for(int which=0;which<5;++which){
    flatbuffers::FlatBufferBuilder b;
    auto labors=b.CreateVector(std::vector<int16_t>{0,which==0?int16_t(0):int16_t(93)});
    std::vector<flatbuffers::Offset<flatbuffers::String>> names{b.CreateString("Mining")};
    if(which!=1)names.push_back(b.CreateString("Last labor"));
    auto labels=b.CreateVector(names);auto name=b.CreateString("Work detail"),reason=b.CreateString("");
    auto members=b.CreateVector(std::vector<int32_t>{0,which==2?0:42});
    mm::WorkDetailInfoBuilder detail(b);detail.add_index(0);detail.add_revision(which==3?0:1);detail.add_name(name);
    detail.add_reason(reason);detail.add_mode(which==4?4:3);detail.add_labors(labors);detail.add_labor_names(labels);
    detail.add_assigned_units(members);auto row=detail.Finish();
    auto rows=b.CreateVector(std::vector<flatbuffers::Offset<mm::WorkDetailInfo>>{row});
    mm::CitizenStateBuilder domain(b);domain.add_details(rows);auto data=domain.Finish();
    mm::ManagementStateBuilder state(b);state.add_schema_version(mm::kManagementVersion);state.add_revision(1);
    state.add_world_epoch(7);state.add_action(mm::ManagementAction::WorkDetailInspect);state.add_status(mm::ManagementStatus::Ok);
    state.add_citizen(data);b.Finish(state.Finish());
    CHECK(mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer())).has_value());
  }
}
TEST_CASE("report requests preserve native ID zero pagination and management ownership") {
  ManagementPublisher p;p.publish(1);auto c=openClient(p);
  wm::ManagementRequest inspect;inspect.action=wm::ManagementAction::ReportInspect;inspect.report.id=0;
  CHECK(c->send(inspect)==0);CHECK(c->lastError()=="Refresh the management catalog first");
  auto [seq,client]=claim(p,*c);
  seq=c->send(inspect);REQUIRE(seq>0);auto* wire=p.pop();REQUIRE(wire->report());
  CHECK(wire->report()->id()==0);CHECK(wire->report()->before_id()==-1);CHECK(wire->report()->announcements_only());
  CHECK(wire->citizen()==nullptr);CHECK(wire->work_order()==nullptr);CHECK(c->send(inspect)==0);CHECK(c->lastError()=="Wait for the current management request");
  p.publish(3,client,seq,7,mm::ManagementAction::ReportInspect);REQUIRE(c->poll());
  wm::ManagementRequest list;list.action=wm::ManagementAction::ReportList;
  list.report.beforeId=91;list.report.query="cancelled";list.report.announcementsOnly=false;
  seq=c->send(list);REQUIRE(seq>0);wire=p.pop();CHECK(wire->report()->before_id()==91);
  CHECK(wire->report()->query()->str()=="cancelled");CHECK_FALSE(wire->report()->announcements_only());
  p.publish(4,client,seq,7,mm::ManagementAction::ReportList);REQUIRE(c->poll());
  for(int which=0;which<4;++which){
    auto bad=list;
    if(which==0)bad.report.beforeId=-2;
    if(which==1)bad.report.query=std::string(129,'x');
    if(which==2)bad.report.id=0;
    if(which==3){bad.action=wm::ManagementAction::ReportInspect;bad.report.id=-1;}
    CHECK(c->send(bad)==0);CHECK(c->lastError()==(which<2?"invalid report request":which==2?"unexpected report identity":"invalid report inspection"));
  }
  p.publish(5,0,seq,8,mm::ManagementAction::Catalog,mm::ManagementStatus::Idle);REQUIRE(c->poll());
  CHECK(c->send(inspect)==0);CHECK(c->lastError()=="Refresh the management catalog first");
  CHECK(c->send(list)==0);CHECK(c->lastError()=="Refresh the management catalog first");
}
TEST_CASE("report response preserves every list field and both focus positions") {
  ManagementPublisher p;p.publish(1);auto c=openClient(p);
  auto [seq,client]=claim(p,*c);
  wm::ManagementRequest request;request.action=wm::ManagementAction::ReportList;
  seq=c->send(request);REQUIRE(seq>0);p.pop();
  flatbuffers::FlatBufferBuilder b;
  std::vector<flatbuffers::Offset<mm::ReportInfo>> records;
  // reports.lua:11-23,57-63; 16 rows and last scanned ID, not an invented cursor.
  // build/evidence/native/e7/findings.md:36: pin bridge newest-first pending 08-B.
  for(int id=1099;id>=1084;--id) {
    auto category=b.CreateString("CANCEL_JOB"),text=b.CreateString(id==1099?std::string(16384,'x'):"Native text");
    mm::ReportInfoBuilder row(b);row.add_id(id);row.add_category(category);row.add_text(text);
    row.add_year(106);row.add_year_tick(139200);row.add_repeat_count(2);row.add_continuation(true);row.add_text_complete(id!=1099);
    row.add_x(2);row.add_y(3);row.add_z(4);row.add_position_visible(true);
    row.add_x2(5);row.add_y2(6);row.add_z2(7);row.add_position2_visible(true);records.push_back(row.Finish());
  }
  auto rows=b.CreateVector(records);auto empty=b.CreateString("");
  mm::ReportStateBuilder domain(b);domain.add_reports(rows);domain.add_next_before_id(1084);domain.add_detail(empty);domain.add_announcements_only(true);auto data=domain.Finish();
  mm::ManagementStateBuilder state(b);state.add_schema_version(mm::kManagementVersion);state.add_revision(3);
  state.add_world_epoch(7);state.add_client_id(client);state.add_request_seq(seq);state.add_action(mm::ManagementAction::ReportList);
  state.add_status(mm::ManagementStatus::Ok);state.add_report(data);b.Finish(state.Finish());
  REQUIRE_FALSE(mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer())).has_value());
  REQUIRE(p.write(b.GetBufferPointer(),b.GetSize()));REQUIRE(c->poll());
  const auto& r=c->state().report;REQUIRE(r.reports.size()==16);CHECK(r.nextBeforeId==1084);CHECK(r.announcementsOnly);CHECK(r.detail.empty());
  for(size_t i=0;i<r.reports.size();++i) {
    const auto& v=r.reports[i];CHECK(v.id==1099-int(i));CHECK(v.year==106);CHECK(v.yearTick==139200);CHECK(v.repeatCount==2);
    CHECK(v.continuation);CHECK(v.textComplete==(i!=0));CHECK(v.category=="CANCEL_JOB");CHECK(v.text==(i==0?std::string(16384,'x'):"Native text"));
    CHECK(v.positionVisible);CHECK(v.x==2);CHECK(v.y==3);CHECK(v.z==4);
    CHECK(v.position2Visible);CHECK(v.x2==5);CHECK(v.y2==6);CHECK(v.z2==7);
  }
  seq=c->send({});REQUIRE(seq>0);p.pop();p.publish(4,client,seq);REQUIRE(c->poll());CHECK(c->state().report.reports.empty());
}
TEST_CASE("report inspection preserves ID zero false source and hidden second position") {
  ManagementPublisher p;p.publish(1);auto c=openClient(p);auto [seq,client]=claim(p,*c);
  wm::ManagementRequest request;request.action=wm::ManagementAction::ReportInspect;request.report.id=0;request.report.announcementsOnly=false;
  seq=c->send(request);REQUIRE(seq>0);p.pop();
  flatbuffers::FlatBufferBuilder b;auto category=b.CreateString("CANCEL_JOB"),text=b.CreateString(std::string(16384,'x'));
  mm::ReportInfoBuilder row(b);row.add_id(0);row.add_category(category);row.add_text(text);
  row.add_year(106);row.add_year_tick(139200);row.add_repeat_count(2);row.add_continuation(true);row.add_text_complete(false);
  row.add_x(2);row.add_y(3);row.add_z(4);row.add_position_visible(true);auto record=row.Finish();
  auto report=mm::CreateReportState(b,b.CreateVector(std::vector{record}),-1,false,b.CreateString(""));
  mm::ManagementStateBuilder state(b);state.add_schema_version(mm::kManagementVersion);state.add_revision(3);
  state.add_world_epoch(7);state.add_client_id(client);state.add_request_seq(seq);state.add_action(mm::ManagementAction::ReportInspect);
  state.add_status(mm::ManagementStatus::Ok);state.add_report(report);b.Finish(state.Finish());
  REQUIRE_FALSE(mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer())).has_value());
  REQUIRE(p.write(b.GetBufferPointer(),b.GetSize()));REQUIRE(c->poll());
  const auto& r=c->state().report;REQUIRE(r.reports.size()==1);CHECK(r.nextBeforeId==-1);CHECK_FALSE(r.announcementsOnly);CHECK(r.detail.empty());
  const auto& v=r.reports[0];CHECK(v.id==0);CHECK(v.year==106);CHECK(v.yearTick==139200);CHECK(v.repeatCount==2);
  CHECK(v.continuation);CHECK_FALSE(v.textComplete);CHECK(v.category=="CANCEL_JOB");CHECK(v.text==std::string(16384,'x'));
  CHECK(v.positionVisible);CHECK(v.x==2);CHECK(v.y==3);CHECK(v.z==4);
  CHECK_FALSE(v.position2Visible);CHECK(v.x2==-1);CHECK(v.y2==-1);CHECK(v.z2==-1);
}
TEST_CASE("report validation bounds total text and rejects hidden or malformed focus coordinates") {
  // Intentional malformed-wire fixtures exercise rejection beyond reports.lua output.
  for(int which=0;which<6;++which){
    flatbuffers::FlatBufferBuilder b;std::vector<flatbuffers::Offset<mm::ReportInfo>> rows;
    const int count=which==0?9:which==1?2:1;
    for(int i=0;i<count;++i){
      auto category=b.CreateString("CANCEL_JOB"),text=b.CreateString(which==0?std::string(16384,'x'):"Native text");
      mm::ReportInfoBuilder row(b);row.add_id(which==1?0:i);row.add_category(category);row.add_text(text);
      if(which==2)row.add_x(1);
      if(which==3)row.add_position_visible(true);
      if(which==4)row.add_repeat_count(-1);
      if(which==5)row.add_year_tick(403200);
      rows.push_back(row.Finish());
    }
    auto records=b.CreateVector(rows);mm::ReportStateBuilder domain(b);domain.add_reports(records);auto data=domain.Finish();
    mm::ManagementStateBuilder state(b);state.add_schema_version(mm::kManagementVersion);state.add_revision(1);
    state.add_world_epoch(7);state.add_action(mm::ManagementAction::ReportList);state.add_status(mm::ManagementStatus::Ok);
    state.add_report(data);b.Finish(state.Finish());
    const auto error=mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer()));
    REQUIRE(error.has_value());
    CHECK(*error==(which==0?"report text budget exceeded":which==2 || which==3?"invalid report location":"invalid report row"));
  }
}
TEST_CASE("report wire bounds accept limits and reject over limits with exact reasons") {
  // Intentional malformed-wire over-limit variants; reports.lua cannot emit these.
  for(int which=0;which<8;++which)for(bool over:{false,true}) {
    flatbuffers::FlatBufferBuilder b;std::vector<flatbuffers::Offset<mm::ReportInfo>> rows;
    const int count=which==0?(over?17:16):which==1?(over?9:8):1;
    for(int i=0;i<count;++i) {
      auto category=b.CreateString("CANCEL_JOB");
      auto text=b.CreateString(which==1 || which==2?std::string(16384+(which==2 && over?1:0),'x'):"");
      mm::ReportInfoBuilder row(b);row.add_id(count-1-i);row.add_category(category);row.add_text(text);
      row.add_year_tick(which==3?(over?403200:403199):0);
      row.add_repeat_count(which==4 && over?-1:0);
      row.add_year(which==5 && over?-1:0);
      if(which==6 && over)row.add_id(-1);
      rows.push_back(row.Finish());
    }
    auto report=mm::CreateReportState(b,b.CreateVector(rows),which==7 && over?-2:-1,true,b.CreateString(""));
    mm::ManagementStateBuilder state(b);state.add_schema_version(mm::kManagementVersion);state.add_revision(1);
    state.add_world_epoch(7);state.add_action(mm::ManagementAction::ReportList);state.add_status(mm::ManagementStatus::Ok);
    state.add_report(report);b.Finish(state.Finish());
    const auto error=mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer()));
    REQUIRE(error.has_value()==over);
    if(over)CHECK(*error==(which==0 || which==7?"invalid report state":which==1?"report text budget exceeded":"invalid report row"));
  }
}
TEST_CASE("agreement requests retain ID zero pending filter and exclusive cursor ownership") {
  ManagementPublisher p;p.publish(1);auto c=openClient(p);
  wm::ManagementRequest inspect;inspect.action=wm::ManagementAction::AgreementInspect;inspect.agreement.id=0;
  CHECK(c->send(inspect)==0);CHECK(c->lastError()=="Refresh the management catalog first");
  auto [seq,client]=claim(p,*c);
  seq=c->send(inspect);REQUIRE(seq>0);auto* wire=p.pop();REQUIRE(wire->agreement());
  CHECK(wire->agreement()->id()==0);CHECK(wire->agreement()->before_id()==-1);
  CHECK(wire->report()==nullptr);CHECK(wire->citizen()==nullptr);CHECK(c->send(inspect)==0);CHECK(c->lastError()=="Wait for the current management request");
  p.publish(3,client,seq,7,mm::ManagementAction::AgreementInspect);REQUIRE(c->poll());
  wm::ManagementRequest list;list.action=wm::ManagementAction::AgreementList;
  list.agreement.beforeId=0;list.agreement.pendingOnly=true;list.agreement.query="guild";
  seq=c->send(list);REQUIRE(seq>0);wire=p.pop();CHECK(wire->agreement()->before_id()==0);
  CHECK(wire->agreement()->pending_only());CHECK(wire->agreement()->query()->str()=="guild");
  p.publish(4,client,seq,7,mm::ManagementAction::AgreementList);REQUIRE(c->poll());
  for(int which=0;which<5;++which){
    auto bad=list;
    if(which==0)bad.agreement.beforeId=-2;
    if(which==1)bad.agreement.query=std::string(129,'x');
    if(which==2)bad.agreement.id=0;
    if(which==3){bad.action=wm::ManagementAction::AgreementInspect;bad.agreement.id=-1;}
    if(which==4){bad=inspect;bad.agreement.beforeId=0;}
    CHECK(c->send(bad)==0);CHECK(c->lastError()==(which<2?"invalid agreement request":which==2?"unexpected agreement identity":"invalid agreement inspection"));
  }
  p.publish(5,0,seq,8,mm::ManagementAction::Catalog,mm::ManagementStatus::Idle);REQUIRE(c->poll());
  CHECK(c->send(inspect)==0);CHECK(c->lastError()=="Refresh the management catalog first");CHECK(c->send(list)==0);CHECK(c->lastError()=="Refresh the management catalog first");
}
TEST_CASE("agreement response preserves party identities native approval flags and typed terms") {
  ManagementPublisher p;p.publish(1);auto c=openClient(p);
  auto [seq,client]=claim(p,*c);
  wm::ManagementRequest request;request.action=wm::ManagementAction::AgreementInspect;request.agreement.id=0;
  seq=c->send(request);REQUIRE(seq>0);p.pop();
  flatbuffers::FlatBufferBuilder b;
  auto applicant=mm::CreateAgreementParty(b,3,b.CreateVector(std::vector<int32_t>{0}),b.CreateVector(std::vector<int32_t>{42}),b.CreateString("Blacksmiths, Urist Lorbamoth"));
  auto government=mm::CreateAgreementParty(b,7,b.CreateVector(std::vector<int32_t>{1930}),b.CreateVector(std::vector<int32_t>{}),b.CreateString("Fortress government"));
  auto parties=b.CreateVector(std::vector<flatbuffers::Offset<mm::AgreementParty>>{applicant,government});
  // e8/findings.md Native wording and e12/findings.md items 2,4: pin enum descriptions pending 07-B native captions.
  auto description=b.CreateString("GUILDHALL tier 2 for MASON");
  mm::AgreementDetailBuilder term(b);term.add_id(0);term.add_kind(12);term.add_site_id(55);
  term.add_year(117);term.add_year_tick(94234);term.add_applicant_party(3);term.add_government_party(7);
  term.add_location_type(11);term.add_tier(2);term.add_profession(9);term.add_description(description);
  auto location=term.Finish();auto residencyName=b.CreateString("Residency");
  mm::AgreementDetailBuilder residency(b);residency.add_id(1);residency.add_kind(2);residency.add_site_id(55);
  residency.add_year(117);residency.add_year_tick(94234);residency.add_applicant_party(3);residency.add_government_party(7);residency.add_description(residencyName);
  auto details=b.CreateVector(std::vector<flatbuffers::Offset<mm::AgreementDetail>>{location,residency.Finish()});
  auto summary=b.CreateString("GUILDHALL tier 2 for MASON"),reason=b.CreateString("Partial record: some native subject terms are not yet displayed");
  mm::AgreementInfoBuilder row(b);row.add_id(0);row.add_status(mm::AgreementStatus::Accepted);
  row.add_continuing(true);row.add_complete(false);row.add_details(details);row.add_parties(parties);row.add_summary(summary);row.add_reason(reason);
  auto records=b.CreateVector(std::vector<flatbuffers::Offset<mm::AgreementInfo>>{row.Finish()});
  auto explanation=b.CreateString("Pending means a native unapproved petition. Accepted and concluded are native states; no denial or expiry is inferred.");
  mm::AgreementStateBuilder domain(b);domain.add_detail(explanation);domain.add_agreements(records);auto data=domain.Finish();
  mm::ManagementStateBuilder state(b);state.add_schema_version(mm::kManagementVersion);state.add_revision(3);
  state.add_world_epoch(7);state.add_client_id(client);state.add_request_seq(seq);state.add_action(mm::ManagementAction::AgreementInspect);
  state.add_status(mm::ManagementStatus::Ok);state.add_agreement(data);b.Finish(state.Finish());
  REQUIRE_FALSE(mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer())).has_value());
  REQUIRE(p.write(b.GetBufferPointer(),b.GetSize()));REQUIRE(c->poll());
  const auto& domainState=c->state().agreement;REQUIRE(domainState.agreements.size()==1);CHECK(domainState.nextBeforeId==-1);
  const auto& v=domainState.agreements[0];CHECK(v.id==0);CHECK(v.status==1);CHECK_FALSE(v.notApproved);CHECK_FALSE(v.concluded);
  CHECK(v.continuing);CHECK_FALSE(v.complete);CHECK(v.reason=="Partial record: some native subject terms are not yet displayed");
  REQUIRE(v.parties.size()==2);CHECK(v.parties[0].id==3);CHECK(v.parties[0].entityIds==std::vector<int32_t>{0});
  CHECK(v.parties[0].histfigIds==std::vector<int32_t>{42});CHECK(v.parties[1].id==7);
  REQUIRE(v.details.size()==2);const auto& d=v.details[0];CHECK(d.id==0);CHECK(d.kind==12);CHECK(d.siteId==55);
  CHECK(d.applicantParty==3);CHECK(d.governmentParty==7);CHECK(d.year==117);CHECK(d.yearTick==94234);
  CHECK(d.tier==2);CHECK(d.profession==9);CHECK(d.deityId==-1);CHECK(d.description=="GUILDHALL tier 2 for MASON");
  seq=c->send({});REQUIRE(seq>0);p.pop();p.publish(4,client,seq);REQUIRE(c->poll());CHECK(c->state().agreement.agreements.empty());
}
TEST_CASE("agreement list preserves every field with producible pending and unapproved pages") {
  // agreements.lua:116 and :21 cannot emit Unapproved with pending_only=true.
  // Test both producible pages. 16 rows (1099..1084) precede more native records.
  for(bool pendingOnly:{false,true}) {
    ManagementPublisher p;p.publish(1);auto c=openClient(p);auto [seq,client]=claim(p,*c);
    wm::ManagementRequest request;request.action=wm::ManagementAction::AgreementList;request.agreement.pendingOnly=pendingOnly;
    seq=c->send(request);REQUIRE(seq>0);p.pop();flatbuffers::FlatBufferBuilder b;
    std::vector<flatbuffers::Offset<mm::AgreementInfo>> records;
    const std::string explanation="Pending means a native unapproved petition. Accepted and concluded are native states; no denial or expiry is inferred.";
    for(int id=1099;id>=1084;--id) {
      auto applicant=mm::CreateAgreementParty(b,0,b.CreateVector(std::vector<int32_t>{2210}),b.CreateVector(std::vector<int32_t>{5120}),b.CreateString("The Bejeweled Creed, Urist Lorbamoth"));
      auto government=mm::CreateAgreementParty(b,1,b.CreateVector(std::vector<int32_t>{483}),b.CreateVector(std::vector<int32_t>{}),b.CreateString("The Iron Realm"));
      auto parties=b.CreateVector(std::vector{applicant,government});
      // e8/findings.md Native wording and e12/findings.md items 2,4: pin enum descriptions pending 07-B native captions.
      auto description=b.CreateString("TEMPLE tier 1 / The Bejeweled Creed");
      mm::AgreementDetailBuilder d(b);d.add_id(0);d.add_kind(12);d.add_site_id(378);d.add_year(106);d.add_year_tick(168260);
      d.add_applicant_party(0);d.add_government_party(1);d.add_location_type(2);d.add_tier(1);d.add_profession(-1);d.add_deity_type(1);d.add_deity_id(2210);d.add_description(description);
      auto details=b.CreateVector(std::vector{d.Finish()});
      const bool pending=pendingOnly || id!=1098;
      auto reason=b.CreateString(pending?"Pending native petition; response controls are not yet verified":"");
      mm::AgreementInfoBuilder row(b);row.add_id(id);row.add_status(pending?mm::AgreementStatus::Pending:mm::AgreementStatus::Unapproved);
      row.add_not_approved(true);row.add_concluded(false);row.add_continuing(id==1097);row.add_complete(true);
      row.add_summary(description);row.add_reason(reason);row.add_details(details);row.add_parties(parties);records.push_back(row.Finish());
    }
    auto domain=mm::CreateAgreementState(b,b.CreateVector(records),1084,pendingOnly,b.CreateString(explanation));
    auto message=b.CreateString("Native agreements");
    mm::ManagementStateBuilder state(b);state.add_schema_version(mm::kManagementVersion);state.add_revision(3);
    state.add_world_epoch(7);state.add_client_id(client);state.add_request_seq(seq);state.add_action(mm::ManagementAction::AgreementList);
    state.add_status(mm::ManagementStatus::Ok);state.add_message(message);state.add_agreement(domain);b.Finish(state.Finish());
    REQUIRE_FALSE(mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer())).has_value());
    REQUIRE(p.write(b.GetBufferPointer(),b.GetSize()));REQUIRE(c->poll());
    const auto& a=c->state().agreement;REQUIRE(a.agreements.size()==16);CHECK(a.nextBeforeId==1084);CHECK(a.pendingOnly==pendingOnly);CHECK(a.detail==explanation);
    for(size_t i=0;i<a.agreements.size();++i) {
      const auto& v=a.agreements[i];CHECK(v.id==1099-int(i));CHECK(v.status==(pendingOnly || i!=1?0:2));
      CHECK(v.notApproved);CHECK_FALSE(v.concluded);CHECK(v.continuing==(i==2));CHECK(v.complete);
      CHECK(v.summary=="TEMPLE tier 1 / The Bejeweled Creed");
      CHECK(v.reason==(pendingOnly || i!=1?"Pending native petition; response controls are not yet verified":""));
      REQUIRE(v.parties.size()==2);
      for(size_t j=0;j<2;++j){const auto& party=v.parties[j];CHECK(party.id==int(j));
        CHECK(party.name==(j==0?"The Bejeweled Creed, Urist Lorbamoth":"The Iron Realm"));
        CHECK(party.entityIds==std::vector<int32_t>{j==0?2210:483});CHECK(party.histfigIds==(j==0?std::vector<int32_t>{5120}:std::vector<int32_t>{}));}
      REQUIRE(v.details.size()==1);const auto& d=v.details[0];CHECK(d.id==0);CHECK(d.kind==12);CHECK(d.siteId==378);CHECK(d.year==106);CHECK(d.yearTick==168260);
      CHECK(d.applicantParty==0);CHECK(d.governmentParty==1);CHECK(d.locationType==2);CHECK(d.tier==1);CHECK(d.profession==-1);
      CHECK(d.deityType==1);CHECK(d.deityId==2210);CHECK(d.description==v.summary);
    }
    seq=c->send({});REQUIRE(seq>0);p.pop();p.publish(4,client,seq);REQUIRE(c->poll());CHECK(c->state().agreement.agreements.empty());
  }
}
TEST_CASE("agreement validators bound nested terms and enforce identity integrity") {
  // Intentionally malformed wire, not native reply fixtures.
  for(int which=-1;which<10;++which){
    flatbuffers::FlatBufferBuilder b;std::vector<flatbuffers::Offset<mm::AgreementInfo>> records;
    const int count=which==0?2:which==7?9:1;
    for(int n=0;n<count;++n){
      auto memberIds=b.CreateVector(std::vector<int32_t>{which==5?-1:0});
      auto party=mm::CreateAgreementParty(b,3,memberIds,b.CreateVector(std::vector<int32_t>{}),b.CreateString("Group"));
      auto parties=b.CreateVector(which==1?std::vector<flatbuffers::Offset<mm::AgreementParty>>{party,party}:std::vector<flatbuffers::Offset<mm::AgreementParty>>{party});
      std::vector<flatbuffers::Offset<mm::AgreementDetail>> terms;
      const int termCount=which==4?9:which==7?8:1;
      for(int j=0;j<termCount;++j){
        auto description=b.CreateString(which==7?"TEMPLE tier 1 / "+std::string(2032,'x'):"GUILDHALL tier 1 for MASON");
        mm::AgreementDetailBuilder term(b);term.add_id(j);term.add_kind(12);term.add_description(description);
        term.add_applicant_party(which==2?99:3);term.add_site_id(378);term.add_location_type(which==7?2:11);term.add_tier(1);term.add_profession(which==7?-1:9);term.add_deity_type(which==7?1:-1);term.add_deity_id(which==7?2210:-1);
        term.add_year(which==8?-2:-1);term.add_year_tick(which==3?403200:which==9?-2:-1);terms.push_back(term.Finish());
      }
      auto details=b.CreateVector(terms);auto summary=b.CreateString(which==7?"TEMPLE tier 1 / "+std::string(2032,'x'):"GUILDHALL tier 1 for MASON"),reason=b.CreateString("");
      mm::AgreementInfoBuilder row(b);row.add_id(which==0?0:n);row.add_status(which==6?static_cast<mm::AgreementStatus>(4):mm::AgreementStatus::Accepted);
      row.add_details(details);row.add_parties(parties);row.add_summary(summary);row.add_reason(reason);records.push_back(row.Finish());
    }
    auto rows=b.CreateVector(records);mm::AgreementStateBuilder domain(b);domain.add_agreements(rows);auto data=domain.Finish();
    mm::ManagementStateBuilder state(b);state.add_schema_version(mm::kManagementVersion);state.add_revision(1);state.add_world_epoch(7);
    state.add_action(mm::ManagementAction::AgreementList);state.add_status(mm::ManagementStatus::Ok);state.add_agreement(data);b.Finish(state.Finish());
    auto error=mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer()));
    REQUIRE(error.has_value()==(which>=0));
    if(error)CHECK(*error==(which==1?"invalid agreement party":which==2?"missing agreement party":
        which==3 || which==8 || which==9?"invalid agreement detail":which==5?"invalid agreement member":
        which==7?"agreement text budget exceeded":"invalid agreement row"));
  }
}

TEST_CASE("agreement wire bounds and integrity reject exact malformed variants") {
  // Accepted controls use agreements.lua:33-90 shapes. Over-limit and inconsistent
  // variants intentionally corrupt the wire; they are not claimed Lua replies.
  for(int which=0;which<13;++which)for(bool bad:{false,true}) {
    flatbuffers::FlatBufferBuilder b;std::vector<flatbuffers::Offset<mm::AgreementInfo>> records;
    int rowCount=which==0?(bad?17:16):which==12?2:1;
    for(int i=0;i<rowCount;++i) {
      std::vector<flatbuffers::Offset<mm::AgreementParty>> parties;
      int partyCount=which==1?(bad?9:8):which==8?2:1;
      for(int j=0;j<partyCount;++j) {
        std::vector<int32_t> members;
        int memberCount=which==3 || which==4?(bad?33:32):0;
        for(int k=0;k<memberCount;++k)members.push_back(k);
        auto entity=b.CreateVector(which==4?std::vector<int32_t>{}:members);
        auto histfig=b.CreateVector(which==4?members:std::vector<int32_t>{});
        parties.push_back(mm::CreateAgreementParty(b,which==8 && bad?0:j,entity,histfig,b.CreateString(memberCount?"Entity 0, Entity 1, Entity 2, Entity 3, Entity 4, Entity 5, Entity 6, Entity 7":"")));
      }
      auto ps=b.CreateVector(parties);std::vector<flatbuffers::Offset<mm::AgreementDetail>> terms;
      int termCount=which==2?(bad?9:8):which==9?2:1;
      for(int j=0;j<termCount;++j) {
        // A TEMPLE name can fill the entire 2048-byte description (:50-57).
        auto description=b.CreateString(which==5?"TEMPLE tier 1 / "+std::string(2032+(bad?1:0),'x'):"GUILDHALL tier 1 for MASON");
        mm::AgreementDetailBuilder d(b);d.add_id(which==9 && bad?0:j);d.add_kind(12);d.add_site_id(378);d.add_year(106);
        d.add_year_tick(which==6?(bad?403200:403199):0);d.add_location_type(which==5?2:11);d.add_tier(1);
        d.add_profession(which==5?-1:9);d.add_deity_type(which==5?1:-1);d.add_deity_id(which==5?2210:-1);
        d.add_applicant_party(which==10 && bad?99:0);d.add_government_party(0);d.add_description(description);terms.push_back(d.Finish());
      }
      auto ds=b.CreateVector(terms);auto summary=b.CreateString(which==5?"TEMPLE tier 1 / "+std::string(2032,'x'):"GUILDHALL tier 1 for MASON");
      auto reason=b.CreateString(which==3 || which==4?"Partial record: native data, names or text are unavailable or exceed display limits":"");
      mm::AgreementInfoBuilder row(b);row.add_id(which==12 && bad?0:i);
      row.add_status(which==7?mm::AgreementStatus::Unapproved:which==11?mm::AgreementStatus::Concluded:mm::AgreementStatus::Accepted);
      row.add_not_approved(which==7 && !bad);row.add_concluded(which==11 && !bad);
      row.add_complete(which!=3 && which!=4);row.add_summary(summary);row.add_reason(reason);row.add_parties(ps);row.add_details(ds);records.push_back(row.Finish());
    }
    auto domain=mm::CreateAgreementState(b,b.CreateVector(records),-1,false,b.CreateString(""));
    mm::ManagementStateBuilder state(b);state.add_schema_version(mm::kManagementVersion);state.add_revision(1);state.add_world_epoch(7);
    state.add_action(mm::ManagementAction::AgreementList);state.add_status(mm::ManagementStatus::Ok);state.add_agreement(domain);b.Finish(state.Finish());
    auto error=mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer()));
    REQUIRE(error.has_value()==bad);
    if(error)CHECK(*error==(which==0?"invalid agreement state":which==1 || which==2 || which==12?"invalid agreement row":
        which==3 || which==4?"invalid agreement members":which==5 || which==6 || which==9?"invalid agreement detail":
        which==7 || which==11?"inconsistent agreement status":which==8?"invalid agreement party":"missing agreement party"));
  }
}

TEST_CASE("agreement aggregate wire text accepts its limit and rejects one extra byte") {
  // Defensive wire boundary, deliberately beyond the Lua page search budget.
  // Both accepted and rejected cases are synthetic wire, not producible Lua replies.
  for(bool over:{false,true}) {
    flatbuffers::FlatBufferBuilder b;std::vector<flatbuffers::Offset<mm::AgreementInfo>> rows;
    for(int i=0;i<8;++i) {
      auto text=b.CreateString("TEMPLE tier 1 / "+std::string(2032,'x'));
      std::vector<flatbuffers::Offset<mm::AgreementDetail>> terms;
      for(int j=0;j<7;++j){mm::AgreementDetailBuilder d(b);d.add_id(j);d.add_kind(12);d.add_description(text);terms.push_back(d.Finish());}
      auto ds=b.CreateVector(terms);auto ps=b.CreateVector(std::vector<flatbuffers::Offset<mm::AgreementParty>>{});
      auto reason=b.CreateString(over && i==0?"x":"");
      mm::AgreementInfoBuilder row(b);row.add_id(i);row.add_status(mm::AgreementStatus::Accepted);
      row.add_details(ds);row.add_parties(ps);row.add_summary(text);row.add_reason(reason);rows.push_back(row.Finish());
    }
    auto domain=mm::CreateAgreementState(b,b.CreateVector(rows));
    mm::ManagementStateBuilder state(b);state.add_schema_version(mm::kManagementVersion);state.add_revision(1);state.add_world_epoch(7);
    state.add_action(mm::ManagementAction::AgreementList);state.add_status(mm::ManagementStatus::Ok);state.add_agreement(domain);b.Finish(state.Finish());
    auto error=mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer()));
    REQUIRE(error.has_value()==over);if(error)CHECK(*error=="agreement text budget exceeded");
  }
}

TEST_CASE("trade requests preserve depot identity and reject stale-shaped edits") {
  ManagementPublisher p;p.publish(1);auto c=openClient(p);
  auto [seq,owner]=claim(p,*c);
  wm::ManagementRequest r;r.action=wm::ManagementAction::TradeUpdate;r.trade.depotId=17;r.trade.requested=1;
  CHECK(c->send(r)==0); // An observed depot revision is mandatory.
  r.trade.expectedRevision=289;seq=c->send(r);REQUIRE(seq>0);
  auto* q=p.pop();REQUIRE(q->trade());CHECK(q->trade()->depot_id()==17);CHECK(q->trade()->requested()==1);CHECK(q->trade()->expected_revision()==289);CHECK(q->agreement()==nullptr);
  p.publish(3,owner,seq,7,mm::ManagementAction::TradeUpdate);REQUIRE(c->poll());
  r.action=wm::ManagementAction::TradeBring;CHECK(c->send(r)==0);
  r.trade={};r.trade.depotId=17;r.trade.itemId=55;seq=c->send(r);REQUIRE(seq>0);q=p.pop();CHECK(q->trade()->item_id()==55);
  p.publish(4,owner,seq,7,mm::ManagementAction::TradeBring);REQUIRE(c->poll());
  r.action=wm::ManagementAction::TradeGoods;r.trade.itemId=-1;r.trade.cursor=512;r.trade.query="wood";
  seq=c->send(r);REQUIRE(seq>0);q=p.pop();CHECK(q->trade()->cursor()==512);CHECK(q->trade()->query()->str()=="wood");
}
TEST_CASE("trade states validate identities and arrive through the world model") {
  ManagementPublisher p;p.publish(1);auto c=openClient(p);
  auto [seq,owner]=claim(p,*c);
  wm::ManagementRequest request;request.action=wm::ManagementAction::TradeList;seq=c->send(request);REQUIRE(seq>0);p.pop();
  for(int bad=-1;bad<4;++bad) {
    flatbuffers::FlatBufferBuilder b;mm::TilePos pos(10,20,3);
    auto depot=mm::CreateTradeDepot(b,17,&pos,bad==0?0:289,true,false,true,true,b.CreateString("Broker"),2,8);
    auto good=mm::CreateTradeGood(b,bad==1?-1:55,b.CreateString("wooden bin"),bad==2?0:1);
    auto data=mm::CreateTradeState(b,b.CreateVector(std::vector{depot}),b.CreateVector(std::vector<flatbuffers::Offset<mm::TradeCaravan>>{}),b.CreateVector(bad==3?std::vector{good,good}:std::vector{good}),512,17,b.CreateString("Native depot"));
    mm::ManagementStateBuilder state(b);state.add_schema_version(mm::kManagementVersion);state.add_revision(3);state.add_world_epoch(7);state.add_client_id(owner);state.add_request_seq(seq);state.add_action(mm::ManagementAction::TradeList);state.add_status(mm::ManagementStatus::Ok);state.add_trade(data);b.Finish(state.Finish());
    CHECK(mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer())).has_value()==(bad>=0));
    if(bad<0){REQUIRE(p.write(b.GetBufferPointer(),b.GetSize()));REQUIRE(c->poll());REQUIRE(c->state().trade.depots.size()==1);CHECK(c->state().trade.depots[0].id==17);CHECK(c->state().trade.depots[0].requested);CHECK(c->state().trade.depots[0].hauling==2);CHECK(c->state().trade.goods[0].id==55);CHECK(c->state().trade.nextCursor==512);}
  }
}

TEST_CASE("trade exchange state validates native readiness bounds") {
  for(int bad=-1;bad<5;++bad) {
    flatbuffers::FlatBufferBuilder b;
    auto ex=mm::CreateTradeExchange(b,true,bad==0?0:12,bad==1?2:0,true,80,12,1,bad==2?13:1,8,9,10,b.CreateString("Trade: Native response"),b.CreateString("Whole ordinary goods"),bad==3?4:1);
    auto good=mm::CreateTradeGood(b,55,b.CreateString("Native good"),1,true,true,b.CreateString(bad==4?std::string(513,'x'):""));
    auto data=mm::CreateTradeState(b,b.CreateVector(std::vector<flatbuffers::Offset<mm::TradeDepot>>{}),b.CreateVector(std::vector<flatbuffers::Offset<mm::TradeCaravan>>{}),b.CreateVector(std::vector{good}),0,17,b.CreateString("Native trade"),ex);
    mm::ManagementStateBuilder state(b);state.add_schema_version(mm::kManagementVersion);state.add_revision(1);state.add_world_epoch(7);state.add_action(mm::ManagementAction::TradeExchangeInspect);state.add_status(mm::ManagementStatus::Ok);state.add_trade(data);b.Finish(state.Finish());
    CHECK(mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer())).has_value()==(bad>=0));
  }
}

TEST_CASE("Stocks knowledge, bounded pages, and locations validate through world model") {
  ManagementPublisher p;p.publish(1);auto client=openClient(p);
  auto [seq,owner]=claim(p,*client);
  for(int bad=-1;bad<6;++bad) {
    flatbuffers::FlatBufferBuilder b;
    auto available=mm::CreateStockCount(b,60,bad==0?mm::StockAccuracy::Unavailable:mm::StockAccuracy::Approximate);
    auto unavailable=mm::CreateStockCount(b,90,mm::StockAccuracy::Approximate);
    auto category=mm::CreateStockCategory(b,39,b.CreateString("Ammunition"),available,unavailable);
    auto item=mm::CreateStockItem(b,0,39,b.CreateString("iron bolts"),bad==1?0:6,bad==2?1:-1,-1,-1,false);
    std::vector<flatbuffers::Offset<mm::StockItem>> items(bad==3?17:bad==4?2:1,item);
    auto data=mm::CreateStocksState(b,true,bad==5?0:12,b.CreateVector(std::vector{category}),b.CreateVector(items),512,39,b.CreateString("Native bookkeeping"));
    mm::ManagementStateBuilder state(b); state.add_schema_version(mm::kManagementVersion); state.add_revision(3); state.add_world_epoch(7);
    state.add_client_id(owner); state.add_request_seq(seq); state.add_action(mm::ManagementAction::StocksOpen); state.add_status(mm::ManagementStatus::Ok); state.add_stocks(data); b.Finish(state.Finish());
    CHECK(mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer())).has_value()==(bad>=0));
    if(bad<0) {
      REQUIRE(p.write(b.GetBufferPointer(),b.GetSize())); REQUIRE(client->poll());
      const auto& s=client->state().stocks; REQUIRE(s.categories.size()==1); REQUIRE(s.items.size()==1);
      CHECK(s.receipt==12); CHECK(s.categories[0].available.amount==60); CHECK(s.categories[0].available.accuracy==2);
      CHECK(s.items[0].id==0); CHECK(s.items[0].quantity==6); CHECK_FALSE(s.items[0].canFocus); CHECK(s.nextCursor==512);
    }
  }
}

TEST_CASE("Native administrator role requirements and candidate eligibility survive transport") {
  ManagementPublisher p;p.publish(1);auto client=openClient(p);
  auto [seq,owner]=claim(p,*client);
  for(int bad=-1;bad<5;++bad) {
    flatbuffers::FlatBufferBuilder b;
    auto role=mm::CreateAppointmentRole(b,483,10,6,4805,b.CreateString("manager"),b.CreateString("Melbil"),bad==0?-1:1,0,0,0,0,0,0,0,true,b.CreateString(""));
    auto candidate=mm::CreateAppointmentCandidate(b,5173,b.CreateString("Tulon"),b.CreateString("Skilled Organizer"),true,b.CreateString(""));
    std::vector<flatbuffers::Offset<mm::AppointmentCandidate>> candidates(bad==1?257:bad==2?2:1,candidate);
    auto data=mm::CreateAppointmentsState(b,bad!=3,true,bad==4?0:25,b.CreateVector(std::vector{role}),b.CreateVector(candidates),b.CreateString("Native administrator candidates"));
    mm::ManagementStateBuilder state(b);state.add_schema_version(mm::kManagementVersion);state.add_revision(3);state.add_world_epoch(7);state.add_client_id(owner);state.add_request_seq(seq);state.add_action(mm::ManagementAction::AppointmentsOpen);state.add_status(mm::ManagementStatus::Ok);state.add_appointments(data);b.Finish(state.Finish());
    CHECK(mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer())).has_value()==(bad>=0));
    if(bad<0){REQUIRE(p.write(b.GetBufferPointer(),b.GetSize()));REQUIRE(client->poll());const auto& a=client->state().appointments;REQUIRE(a.roles.size()==1);REQUIRE(a.candidates.size()==1);CHECK(a.receipt==25);CHECK(a.roles[0].office==1);CHECK(a.roles[0].assignmentId==6);CHECK(a.candidates[0].unitId==5173);CHECK(a.candidates[0].skill=="Skilled Organizer");CHECK(a.choosing);}
  }
}

TEST_CASE("Kitchen transport preserves material identity and capability distinctions") {
  ManagementPublisher p;p.publish(1);auto c=openClient(p);
  auto [seq,owner]=claim(p,*c);
  for(int bad=-1;bad<8;++bad){
    flatbuffers::FlatBufferBuilder b;
    auto one=mm::CreateKitchenIngredient(b,1,-1,419,20,b.CreateString("berries"),4,true,true,false,true);
    auto two=mm::CreateKitchenIngredient(b,1,-1,419,bad==0?20:21,b.CreateString(bad==1?std::string(513,'x'):"berries"),4,false,true,bad==2,true);
    std::vector<flatbuffers::Offset<mm::KitchenIngredient>> rows{one,two};if(bad==3)rows.resize(17,one);
    auto data=mm::CreateKitchenState(b,bad!=4,bad==5?0:22,b.CreateVector(rows),bad==6?41:16,bad==7?1:40,b.CreateString("Native Kitchen"));
    mm::ManagementStateBuilder state(b);state.add_schema_version(mm::kManagementVersion);state.add_revision(3);state.add_world_epoch(7);state.add_client_id(owner);state.add_request_seq(seq);state.add_action(mm::ManagementAction::KitchenOpen);state.add_status(mm::ManagementStatus::Ok);state.add_kitchen(data);b.Finish(state.Finish());
    CHECK(mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer())).has_value()==(bad>=0));
    if(bad<0){REQUIRE(p.write(b.GetBufferPointer(),b.GetSize()));REQUIRE(c->poll());const auto& k=c->state().kitchen;REQUIRE(k.ingredients.size()==2);CHECK(k.receipt==22);CHECK(k.ingredients[0].matIndex==20);CHECK(k.ingredients[1].matIndex==21);CHECK(k.ingredients[0].canCook);CHECK_FALSE(k.ingredients[1].canCook);CHECK_FALSE(k.ingredients[0].cookAllowed);CHECK(k.ingredients[0].brewAllowed);CHECK(k.total==40);}
  }
}

TEST_CASE("native alerts require bounded identities and preserve semantic pages") {
  for(int bad=-1;bad<5;++bad) {
    flatbuffers::FlatBufferBuilder b;
    auto request=mm::CreateAlertRequest(b,bad==0?mm::AlertOperation(99):mm::AlertOperation::OpenUnit,bad==1?37:35,bad==2?0:8,bad==3?512:0,-1,bad==4?33:0);
    mm::ConstructionRequestBuilder command(b);command.add_schema_version(mm::kManagementVersion);command.add_client_id(1);command.add_seq(2);command.add_world_epoch(3);command.add_action(mm::ManagementAction::Alert);command.add_alert(request);b.Finish(command.Finish());
    CHECK(mm::validateConstructionRequest(*flatbuffers::GetRoot<mm::ConstructionRequest>(b.GetBufferPointer())).has_value()==(bad>=0));
  }
  for(int bad=-1;bad<4;++bad) {
    flatbuffers::FlatBufferBuilder b;
    auto entry=mm::CreateAlertEntry(b,b.CreateString(bad==0?std::string(8193,'x'):"Native unit report"),-1,107,bad==1?3:1,false);
    std::vector<flatbuffers::Offset<mm::AlertEntry>> entries{entry};if(bad==2)entries.resize(513,entry);
    std::vector<flatbuffers::Offset<flatbuffers::String>> tabs;
    auto alert=mm::CreateAlertState(b,mm::AlertView::Category,bad==3?0:9,35,-1,-1,b.CreateVector(entries),b.CreateVector(tabs));
    mm::ManagementStateBuilder state(b);state.add_schema_version(mm::kManagementVersion);state.add_revision(1);state.add_world_epoch(3);state.add_action(mm::ManagementAction::Alert);state.add_status(mm::ManagementStatus::Ok);state.add_alert(alert);b.Finish(state.Finish());
    CHECK(mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer())).has_value()==(bad>=0));
  }
}

TEST_CASE("selection transport preserves native identity order and clears closed pages") {
  ManagementPublisher p;p.publish(1);auto client=openClient(p);
  auto [seq,owner]=claim(p,*client);
  flatbuffers::FlatBufferBuilder b;
  auto unit=mm::CreateSelectionIdentity(b,mm::SelectionKind::Unit,4085,b.CreateString("Cerol"));
  auto door=mm::CreateSelectionIdentity(b,mm::SelectionKind::Building,1037,b.CreateString("Gabbro Door"));
  auto overview=mm::CreateSelectionText(b,mm::SelectionSection::AgeSex,b.CreateString("5 Years Old"));
  std::vector<flatbuffers::Offset<mm::SelectionItem>> items;
  std::vector<mm::AppearanceLayer> layers{mm::AppearanceLayer(0,2,3,1,1,65535,-1,-1,0,0)};
  auto portrait=mm::CreateSelectionAppearance(b,b.CreateVector(std::vector{b.CreateString("PORTRAIT_TEST")}),
      b.CreateVector(std::vector<flatbuffers::Offset<flatbuffers::String>>{}),b.CreateVectorOfStructs(layers));
  const auto empty=b.CreateString("");const auto title=b.CreateString("Cerol");
  const auto choices=b.CreateVector(std::vector{unit,door});const auto contents=b.CreateVector(items);
  const auto sections=b.CreateVector(std::vector{overview});
  mm::SelectionStateBuilder page(b);page.add_open(true);page.add_receipt(77);
  page.add_kind(mm::SelectionKind::Unit);page.add_id(4085);page.add_title(title);
  page.add_subtitle(empty);page.add_job(empty);page.add_description(empty);
  page.add_alternatives(choices);page.add_items(contents);page.add_overview(sections);page.add_portrait(portrait);
  auto selection=page.Finish();
  mm::ManagementStateBuilder state(b);state.add_schema_version(mm::kManagementVersion);state.add_revision(3);
  state.add_world_epoch(7);state.add_client_id(owner);state.add_request_seq(seq);
  state.add_action(mm::ManagementAction::Selection);state.add_status(mm::ManagementStatus::Ok);state.add_selection(selection);
  b.Finish(state.Finish());
  REQUIRE_FALSE(mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer())).has_value());
  REQUIRE(p.write(b.GetBufferPointer(),b.GetSize()));REQUIRE(client->poll());
  const auto& selected=client->state().selection;
  REQUIRE(selected.alternatives.size()==2);CHECK(selected.alternatives[0].id==4085);CHECK(selected.alternatives[1].id==1037);
  CHECK(selected.kind==wm::SelectionKind::Unit);CHECK(selected.receipt==77);
  REQUIRE(selected.overview.size()==1);CHECK(selected.overview[0].text=="5 Years Old");
  REQUIRE(selected.portrait.layers.size()==1);CHECK(selected.portrait.layers[0].tileX==2);CHECK(selected.portrait.tilePages[0]=="PORTRAIT_TEST");
  p.publish(4,owner,seq);REQUIRE(client->poll());
  CHECK_FALSE(client->state().selection.open);CHECK(client->state().selection.alternatives.empty());
  CHECK(client->state().selection.portrait.layers.empty());
}

TEST_CASE("selection rejects missing receipts, invalid tiles and unbounded indexes") {
  for (int invalid=-1;invalid<4;++invalid) {
    flatbuffers::FlatBufferBuilder b;
    const mm::TilePos tile(invalid==2?-1:88,71,143);
    auto selection=mm::CreateSelectionRequest(b,
      invalid==2?mm::SelectionOperation::OpenTile:mm::SelectionOperation::SelectAlternative,
      &tile,invalid==0?0:77,invalid==1?256:invalid==3?-1:0);
    mm::ConstructionRequestBuilder command(b);command.add_schema_version(mm::kManagementVersion);
    command.add_client_id(1);command.add_seq(1);command.add_world_epoch(7);
    command.add_action(mm::ManagementAction::Selection);command.add_selection(selection);b.Finish(command.Finish());
    CHECK(mm::validateConstructionRequest(*flatbuffers::GetRoot<mm::ConstructionRequest>(b.GetBufferPointer())).has_value()==(invalid>=0));
  }
}

TEST_CASE("CreatureInspect round trip and bounded semantic records") {
  ManagementPublisher p;p.publish(1);auto client=openClient(p);
  auto [seq,owner]=claim(p,*client);
  wm::ManagementRequest request;request.action=wm::ManagementAction::CreatureInspect;request.creatureUnitId=86;
  seq=client->send(request);REQUIRE(seq);const auto* sent=p.pop();REQUIRE(sent->creature());CHECK(sent->creature()->unit_id()==86);
  for(int bad=-1;bad<4;++bad){
    flatbuffers::FlatBufferBuilder b;std::vector<flatbuffers::Offset<mm::CreatureSection>> sections;
    auto fact=mm::CreateCreatureFact(b,b.CreateString(bad==0?std::string(65,'x'):"rating"),b.CreateString(""),5,true);
    auto row=mm::CreateCreatureRecord(b,1,-1,b.CreateString("Mining"),b.CreateVector(std::vector{fact}));
    for(int i=0;i<25;++i)sections.push_back(mm::CreateCreatureSection(b,mm::CreatureSectionKind(bad==1?0:i),true,bad==2,b.CreateString(""),b.CreateVector(std::vector{row})));
    std::vector<mm::AppearanceLayer> layers;layers.emplace_back(bad==3?1:0,0,0,1,1,65535,0,0,0,0);
    auto portrait=mm::CreateSelectionAppearance(b,b.CreateVectorOfStrings(std::vector<std::string>{"PORTRAIT_TEST"}),b.CreateVectorOfStrings(std::vector<std::string>{}),b.CreateVectorOfStructs(layers));
    mm::TilePos pos(1,2,3);auto creature=mm::CreateCreatureState(b,86,100,b.CreateString("Dwarf"),b.CreateString("dwarf"),0,0,20,1,&pos,true,b.CreateVector(sections),portrait);
    mm::ManagementStateBuilder state(b);state.add_schema_version(mm::kManagementVersion);state.add_revision(3);state.add_world_epoch(7);state.add_client_id(owner);state.add_request_seq(seq);state.add_action(mm::ManagementAction::CreatureInspect);state.add_status(mm::ManagementStatus::Ok);state.add_creature(creature);b.Finish(state.Finish());
    CHECK(mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer())).has_value()==(bad>=0));
    if(bad<0){REQUIRE(p.write(b.GetBufferPointer(),b.GetSize()));REQUIRE(client->poll());CHECK(client->state().creature.unitId==86);REQUIRE(client->state().creature.sections.size()==25);CHECK(client->state().creature.sections[0].records[0].facts[0].number==5);REQUIRE(client->state().creature.portrait.layers.size()==1);CHECK(client->state().creature.portrait.tilePages[0]=="PORTRAIT_TEST");}
  }
}
TEST_CASE("CreatureInspect retains long emotion histories within the shared fact budget") {
  for (const int count : {4600,8192,8193}) {
    flatbuffers::FlatBufferBuilder b;
    const auto fact=mm::CreateCreatureFact(b,b.CreateString("v"),b.CreateString(""),1,true);
    std::vector<flatbuffers::Offset<mm::CreatureSection>> sections;
    int remaining=count;
    for(int section=0;section<25;++section) {
      std::vector<flatbuffers::Offset<mm::CreatureRecord>> rows;
      for(int row=0;row<32 && remaining>0;++row) {
        const int size=std::min(12,remaining);remaining-=size;
        rows.push_back(mm::CreateCreatureRecord(b,row,-1,b.CreateString(""),b.CreateVector(std::vector<flatbuffers::Offset<mm::CreatureFact>>(size,fact))));
      }
      sections.push_back(mm::CreateCreatureSection(b,mm::CreatureSectionKind(section),true,false,b.CreateString(""),b.CreateVector(rows)));
    }
    REQUIRE(remaining==0);
    mm::TilePos pos(1,2,3);
    const auto creature=mm::CreateCreatureState(b,86,100,b.CreateString("Dwarf"),b.CreateString("dwarf"),0,0,20,1,&pos,true,b.CreateVector(sections));
    mm::ManagementStateBuilder state(b);
    state.add_schema_version(mm::kManagementVersion);state.add_revision(1);
    state.add_action(mm::ManagementAction::CreatureInspect);state.add_status(mm::ManagementStatus::Ok);state.add_creature(creature);
    b.Finish(state.Finish());
    CHECK(mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer())).has_value()==(count>8192));
  }
}

TEST_CASE("management transport rejects replaced producer identity before sending") {
  ManagementPublisher p;
  std::string error; auto c=wm::ManagementClient::open(error,p.name); REQUIRE(c);
  auto* owner=mm::sessionOwner(p.region);
  SUBCASE("process id") { shm::atomicStoreRelease(&owner->pid,GetCurrentProcessId()+1); }
  SUBCASE("creation time") { shm::atomicStoreRelease(&owner->created,1); }
  SUBCASE("generation") { shm::atomicStoreRelease(&owner->generation,99); }
  CHECK(c->send({})==0);
  CHECK(shm::popCommand(p.region,p.bytes.data(),p.bytes.size())==0);
  CHECK_FALSE(c->poll()); CHECK(c->state().status==wm::ManagementStatus::Rejected);
}

TEST_CASE("management refuses an older-version work-order reply without replacing accepted state") {
  ManagementPublisher p;p.publish(1);auto c=openClient(p);auto owner=claim(p,*c);
  wm::ManagementRequest request;request.action=wm::ManagementAction::WorkOrderCatalog;
  auto seq=c->send(request);REQUIRE(seq>0);p.pop();
  flatbuffers::FlatBufferBuilder b;
  auto work=mm::CreateWorkOrderState(b);
  mm::ManagementStateBuilder state(b);state.add_schema_version(mm::kManagementVersion-1);state.add_revision(3);
  state.add_world_epoch(7);state.add_client_id(owner.id);state.add_request_seq(seq);
  state.add_action(mm::ManagementAction::WorkOrderCatalog);state.add_status(mm::ManagementStatus::Ok);
  state.add_work_order(work);b.Finish(state.Finish());
  CHECK(mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer())).has_value());
  REQUIRE(p.write(b.GetBufferPointer(),b.GetSize()));CHECK_FALSE(c->poll());
  CHECK(c->state().revision==2);CHECK_FALSE(c->lastError().empty());
  // A later valid reply resolves the same request, without sending it again.
  p.publish(4,owner.id,seq,7,mm::ManagementAction::WorkOrderCatalog);REQUIRE(c->poll());
  CHECK(c->state().revision==4);CHECK(shm::popCommand(p.region,p.bytes.data(),p.bytes.size())==0);
}

TEST_CASE("older-version construction replies cannot resolve a current materials request") {
  ManagementPublisher p;p.publish(1);auto c=openClient(p);const auto owner=claim(p,*c);
  wm::ManagementRequest request;request.action=wm::ManagementAction::ConstructionMaterials;
  request.definition="Chair";request.filter=0;request.expectedListRevision=INT64_MAX;
  auto seq=c->send(request);REQUIRE(seq>0);const auto* sent=p.pop();
  CHECK(sent->filter()==0);CHECK(sent->expected_list_revision()==INT64_MAX);
  flatbuffers::FlatBufferBuilder b;const auto construction=mm::CreateConstructionState(b);
  mm::ManagementStateBuilder state(b);state.add_schema_version(mm::kManagementVersion-1);state.add_revision(3);
  state.add_world_epoch(7);state.add_client_id(owner.id);state.add_request_seq(seq);
  state.add_action(mm::ManagementAction::ConstructionMaterials);state.add_status(mm::ManagementStatus::Ok);
  state.add_construction(construction);b.Finish(state.Finish());
  auto error=mm::validateManagementState(*flatbuffers::GetRoot<mm::ManagementState>(b.GetBufferPointer()));
  REQUIRE(error);CHECK(*error=="invalid management version/revision");
  REQUIRE(p.write(b.GetBufferPointer(),b.GetSize()));CHECK_FALSE(c->poll());CHECK(c->state().revision==2);
  p.publish(4,owner.id,seq,7,mm::ManagementAction::ConstructionMaterials);REQUIRE(c->poll());
  CHECK(c->state().revision==4);CHECK(shm::popCommand(p.region,p.bytes.data(),p.bytes.size())==0);
}
#endif
