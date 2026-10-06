// Supported DF53.16 native material flood. Caller holds the DF core safe point.
#include "construction_material_native.h"
#include "lua.h"
#include <algorithm>
#include <limits>
#include "DataDefs.h"
#include "modules/Maps.h"
#include "df/buildreq.h"
#include "df/building_type.h"
#include "df/construction_type.h"
#include "df/map_block.h"
#include "df/world.h"
#include "df/global_objects.h"
#include <windows.h>
#undef min
#undef max
#include <cstring>
#include <memory>
#include <stdexcept>
#include <vector>

namespace df3d_construction {
namespace {
using Flood=void (*)(df::buildreq*);
static_assert(offsetof(df::buildreq,building_type)==0x38);
static_assert(offsetof(df::buildreq,building_subtype)==0x3c);
static_assert(offsetof(df::buildreq,custom_type)==0x40);
static_assert(offsetof(df::buildreq,tiles)==0x80);
static_assert(offsetof(df::buildreq,pos)==0x1034);
static_assert(offsetof(df::buildreq,selection_pos)==0x1042);
static_assert(offsetof(df::map_block,path_cost)==0xba0);
constexpr size_t scratchBytes=2*120000*12;
uint64_t fingerprint(const uint8_t* p,size_t n){uint64_t h=14695981039346656037ULL;while(n--){h^=*p++;h*=1099511628211ULL;}return h;}
uint8_t* verifiedBase(){
 auto* b=reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
 const auto* dos=reinterpret_cast<IMAGE_DOS_HEADER*>(b);
 if(!b || dos->e_magic!=IMAGE_DOS_SIGNATURE || dos->e_lfanew<=0 || dos->e_lfanew>4096)throw std::runtime_error("PE mismatch");
 const auto* pe=reinterpret_cast<IMAGE_NT_HEADERS64*>(b+dos->e_lfanew);
 if(pe->Signature!=IMAGE_NT_SIGNATURE || pe->FileHeader.Machine!=0x8664 || pe->FileHeader.TimeDateStamp!=0x6a70a6d9 || pe->OptionalHeader.SizeOfImage!=0x2711000 || fingerprint(b+0x8d4f20,0x1121)!=0x8d8eeab8e46d5b93ULL)throw std::runtime_error("native function mismatch");
 return b;
}
struct Restore {
 struct Block {df::map_block* block;decltype(df::map_block::path_cost) costs;};
 df::world* world;int32_t generation;int8_t clear;uint8_t* frontier;
 std::vector<uint8_t> scratch;std::vector<Block> blocks;
 Restore(df::world* w,uint8_t* b):world(w),generation(w->pathfinder.pathstart),clear(w->pathfinder.pathclear),frontier(b+0x1bb3700),scratch(frontier,frontier+scratchBytes){
  if(w->map.map_blocks.size()>250000)throw std::runtime_error("native scratch memory limit");
  blocks.reserve(w->map.map_blocks.size());for(auto* block:w->map.map_blocks)if(block)blocks.push_back({block,block->path_cost});
 }
 ~Restore(){for(auto& b:blocks)b.block->path_cost=b.costs;std::memcpy(frontier,scratch.data(),scratchBytes);world->pathfinder.pathstart=generation;world->pathfinder.pathclear=clear;}
};
}

namespace {
bool points(lua_State* L,int index,std::vector<df::coord>& out){
 if(!lua_istable(L,index))return false;
 const auto n=lua_rawlen(L,index);if(!n || n>16384)return false;
 for(size_t i=1;i<=n;++i){
  lua_rawgeti(L,index,i);if(!lua_istable(L,-1)){lua_pop(L,1);return false;}
  int v[3];int j=0;bool ok=true;
  for(auto key:{"x","y","z"}){lua_getfield(L,-1,key);auto x=lua_tointeger(L,-1);
   ok=ok && lua_isinteger(L,-1) && x>=0 && x<=32767;v[j++]=int(x);lua_pop(L,1);}
  lua_pop(L,1);if(!ok)return false;df::coord p(v[0],v[1],v[2]);
  if(!DFHack::Maps::getTileBlock(p))return false;out.push_back(p);
 }
 return true;
}
void number(lua_State* L,const char* k,lua_Integer v){lua_pushinteger(L,v);lua_setfield(L,-2,k);}
struct Distance {bool reached;int32_t value;};
}
int nativeMaterialDistances(lua_State* L){
 // Compute distances from semantic seeds/targets without Lua terrain callbacks.
 int status=1;std::string reason;std::vector<Distance> distances;
 try{
  auto* base=verifiedBase();auto* world=df::global::world;
  std::vector<df::coord> seeds,targets;
  if(!world || !DFHack::Maps::IsValid() || !points(L,2,seeds) || !points(L,3,targets))
   throw std::runtime_error("invalid native distance input");
  auto lo=seeds.front(),hi=lo;
  for(auto p:seeds){
   if(p.z!=lo.z)throw std::runtime_error("native seeds must share a level");
   lo.x=std::min(lo.x,p.x);lo.y=std::min(lo.y,p.y);hi.x=std::max(hi.x,p.x);hi.y=std::max(hi.y,p.y);
  }
  if(hi.x-lo.x>=31 || hi.y-lo.y>=31)throw std::runtime_error("native seed footprint exceeds mask");
  std::unique_ptr<df::buildreq> request(df::allocate<df::buildreq>());
  // Construction's native rectangle helper transports explicit semantic seeds.
  // Recipe-specific footprint/anchor selection remains with the caller. The flood
  // uses identical material movement flags for every recipe; it receives no UI state.
  request->building_type=df::building_type::Construction;
  int subtype=int(df::construction_type::Wall);
  if(!lua_isnoneornil(L,6)){
   if(!lua_isinteger(L,6))throw std::runtime_error("invalid construction subtype");
   const auto value=lua_tointeger(L,6);
   if(value<0 || value>int(df::construction_type::ReinforcedWall))throw std::runtime_error("invalid construction subtype");
   subtype=int(value);
  }
  request->building_subtype=int16_t(subtype);request->custom_type=-1;
  request->pos=lo;request->selection_pos=hi;request->direction=0;
  for(auto& row:request->tiles)row.fill(df::build_square_type::SKIP);
  for(auto p:seeds)request->tiles[p.x-lo.x][p.y-lo.y]=df::build_square_type::FINE;
  {
   Restore restore(world,base);
   // Every insertion writes coordinates. Touching the last slot of either
   // frontier conservatively rejects the result, including exact-capacity cases.
   constexpr size_t tail=(120000-1)*12;
   constexpr int16_t sentinel=std::numeric_limits<int16_t>::min();
   for(size_t offset:{tail,120000*12+tail})std::memcpy(restore.frontier+offset,&sentinel,sizeof(sentinel));
   reinterpret_cast<Flood>(base+0x8d4f20)(request.get());
   bool full=false;for(size_t offset:{tail,120000*12+tail}){int16_t value;std::memcpy(&value,restore.frontier+offset,sizeof(value));full|=value!=sentinel;}
   if(full){status=3;reason="native material frontier capacity";}
   else{
    const int64_t generation=world->pathfinder.pathstart;
    for(auto p:targets){const int64_t cost=DFHack::Maps::getTileBlock(p)->path_cost[p.x&15][p.y&15];
     const bool reached=cost>=generation && cost<generation+1250000;
     distances.push_back({reached,reached?int32_t(cost-generation):0});
    }
    status=0;
   }
  }
 }catch(const std::exception& e){reason=e.what();distances.clear();}
 // RAII objects are gone before Lua allocations (which can longjmp).
 lua_newtable(L);number(L,"status",status);
 // Keep developer reasons out of player-visible text. Only this native literal
 // has a source (DF53.16 RVA 0x16bebc8, reached from the flood overflow branch).
 if(status!=0){lua_pushstring(L,reason=="native material frontier capacity"?"Building Placement Distance Overflow":"");lua_setfield(L,-2,"native_message");}
 if(!reason.empty()){lua_pushlstring(L,reason.data(),reason.size());lua_setfield(L,-2,"reason");}
 lua_newtable(L);for(size_t i=0;i<distances.size();++i){lua_newtable(L);
  lua_pushboolean(L,distances[i].reached);lua_setfield(L,-2,"reachable");
  if(distances[i].reached)number(L,"distance",distances[i].value);lua_rawseti(L,-2,i+1);
 }
 lua_setfield(L,-2,"distances");return 1;
}
}
