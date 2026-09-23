// Live command-guard client for tools/smoke/designation_acceptance.ps1 -GuardProbe.
// Run only inside an owned unsaved lane; never against a save worth keeping.
#include "command_util.h"
#include "client_mailbox.h"
#include <cstdio>
#include <map>
#include <string>
#include <vector>
#include <thread>
#include <chrono>
#include <cstdlib>
namespace m=df3d::mirror;
namespace s=df3d::shm;
int main(int argc,char** argv){
 for(int k=int(m::CommandPayload::MIN);k<=int(m::CommandPayload::MAX);++k){
  flatbuffers::FlatBufferBuilder b;b.Finish(m::CreateCommand(b,42,m::CommandPayload(k),0,123));
  if(m::parseCommand(b.GetBufferPointer(),b.GetSize())){std::puts("FAIL standalone nullable discriminator");return 1;}
 }
 std::puts("PASS standalone all nullable discriminators");
 if(argc<4)return 0;
 const int x=std::atoi(argv[1]),y=std::atoi(argv[2]),z=std::atoi(argv[3]);
 HANDLE mapping=OpenFileMappingA(FILE_MAP_ALL_ACCESS,FALSE,s::kDefaultRegionName);
 if(!mapping){std::puts("FAIL bridge missing");return 1;}
 auto* region=static_cast<s::RegionHeader*>(MapViewOfFile(mapping,FILE_MAP_ALL_ACCESS,0,0,0));
 if(!region || s::checkRegion(region,uint32_t(m::SchemaVersion::Current))){std::puts("FAIL mapping schema");return 1;}
 const auto epoch=s::atomicLoadAcquire(&region->terrainEpoch);if(!epoch)return 1;
 char name[128];s::terrainRegionName(epoch,name,sizeof(name));
 HANDLE terrainMap=OpenFileMappingA(FILE_MAP_READ,FALSE,name);
 auto* terrain=terrainMap?static_cast<s::TerrainHeader*>(MapViewOfFile(terrainMap,FILE_MAP_READ,0,0,0)):nullptr;
 if(!terrain || terrain->sizeZ<z+2)return 1;
 const int width=terrain->sizeX-2,height=terrain->sizeY-2;
 const int layers=int(65536/(int64_t(width)*height))+1;
 if(z+layers>terrain->sizeZ)return 1;
 s::CommandWriter writer;if(!writer.open(s::kDefaultRegionName))return 1;
 struct Expected{std::string name;int status;};std::map<uint64_t,Expected> pending;
 auto push=[&](uint64_t seq,const std::vector<uint8_t>& bytes,const char* label,int status){
  if(!writer.push(region,bytes.data(),uint32_t(bytes.size()))){std::puts("FAIL command ring busy");std::exit(1);}
  if(status>=0)pending.emplace(seq,Expected{label,status});
 };
 auto seq=s::nextCommandSequence(region);
 flatbuffers::FlatBufferBuilder bad;bad.Finish(m::CreateCommand(bad,seq,m::CommandPayload::SetPause,0,epoch));
 push(seq,{bad.GetBufferPointer(),bad.GetBufferPointer()+bad.GetSize()},"null payload",-1);
 seq=s::nextCommandSequence(region);push(seq,m::buildSetPauseCommand(seq,false,0),"zero epoch pause",1);
 seq=s::nextCommandSequence(region);push(seq,m::buildSetPauseCommand(seq,false,epoch-1),"stale epoch pause",1);
 seq=s::nextCommandSequence(region);push(seq,m::buildDesignateDigCommand(seq,m::TileRect(x,y,x,y,z),m::DigKind::Dig,2,true,0,-1,epoch-1),"stale epoch dig",1);
 seq=s::nextCommandSequence(region);push(seq,m::buildDesignateDigCommand(seq,m::TileRect(1,1,width,height,z),m::DigKind::Dig,2,true,0,z+layers-1,epoch),"oversized designation volume",1);
 seq=s::nextCommandSequence(region);push(seq,m::buildSetPauseCommand(seq,true,epoch),"valid pause after rejections",0);
 std::printf("SENT 6 commands, oversized volume=%lld, layers=%d\n",static_cast<long long>(int64_t(width)*height*layers),layers);
 std::vector<uint8_t> buffer(region->snapshotCapacity);
 const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(15);
 while(!pending.empty() && std::chrono::steady_clock::now()<deadline){
  const auto size=s::readLatestSnapshot(region,buffer.data(),buffer.size());
  if(size){flatbuffers::Verifier verifier(buffer.data(),size);if(m::VerifySizePrefixedSnapshotBuffer(verifier)){
   const auto* snap=m::GetSizePrefixedSnapshot(buffer.data());
   if(auto* results=snap->command_results())for(auto* result:*results){
    auto it=pending.find(result->seq());if(it==pending.end())continue;
    std::printf("%s %s status=%d reason=%s\n",int(result->status())==it->second.status?"PASS":"FAIL",it->second.name.c_str(),int(result->status()),result->message()?result->message()->c_str():"");
    if(int(result->status())!=it->second.status)return 1;pending.erase(it);
   }
  }}
  std::this_thread::sleep_for(std::chrono::milliseconds(5));
 }
 if(!pending.empty()){std::printf("FAIL missing %zu receipts\n",pending.size());return 1;}
 std::puts("COMMAND_GUARD_LIVE_PASS");
 UnmapViewOfFile(terrain);CloseHandle(terrainMap);UnmapViewOfFile(region);CloseHandle(mapping);return 0;
}
