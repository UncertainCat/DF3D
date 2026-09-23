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
int main(int argc,char** argv) {
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
      m::ManagementStateBuilder state(b);state.add_schema_version(m::kManagementVersion);
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
    publish(1,nullptr);signal("ready");unsigned received=0;
    const auto stop=std::chrono::steady_clock::now()+std::chrono::seconds(30);
    std::vector<uint8_t> bytes(m::kManagementCommandCapacity);
    while(std::chrono::steady_clock::now()<stop) {
      auto count=sh::popCommand(region,bytes.data(),bytes.size());
      if(count && count!=SIZE_MAX) {
        flatbuffers::Verifier verifier(bytes.data(),count);require(verifier.VerifyBuffer<m::ConstructionRequest>(nullptr),"request buffer");
        auto* r=flatbuffers::GetRoot<m::ConstructionRequest>(bytes.data());
        require(!m::validateConstructionRequest(*r),"request contract");
        ++received;require(received<=3,"malformed request reached transport");
        if(received==1)require(r->action()==m::ManagementAction::Catalog,"catalog first");
        else {require(r->world_epoch()==epoch,"64-bit world identity");
          if(received==2){require(r->action()==m::ManagementAction::AreaUpdate,"area action");
            auto* a=r->area();require(a && a->id()==2147483000 && a->owner_id()==-2 && a->barrels()==-1 && a->active()==-1,"area identity/sentinels");}
          else {require(r->action()==m::ManagementAction::Place,"place action");
            require(r->items() && r->items()->size()==1 && r->items()->Get(0)==2147483001,"item identity");
            require(r->origin() && r->origin()->x()==11 && r->origin()->y()==12 && r->origin()->z()==13,"placement origin");
            require(r->definition() && r->definition()->str()=="Chair","definition");}}
        publish(received+1,r);
        if(received==3)signal("passed");
        if(received==3)std::cout<<"MANAGEMENT_CONTRACT_HOST_PASS\n"<<std::flush;
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(2));
    }
    require(received==3,"adapter requests did not finish");
  } catch(const std::exception& error) {signal("failed");std::cerr<<"CONTRACT_HOST_FAILURE: "<<error.what()<<"\n";result=1;}
  UnmapViewOfFile(region);CloseHandle(mapping);return result;
#else
  std::cout<<"QA_INCOMPLETE: Windows shared memory required\n";return 77;
#endif
}
