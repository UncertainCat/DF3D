// Supported DF53.16 native material flood. Caller holds the DF core safe point.
#include "construction_material_native.h"
#include "lua.h"
#include <algorithm>
#include <limits>
#include "DataDefs.h"
#include "modules/Maps.h"
#include "df/buildreq.h"
#include "df/ui_build_item_req.h"
#include "df/job_item_filter.h"
#include "df/items_other_id.h"
#include "df/item.h"
#include <map>
#include "df/building_type.h"
#include "df/construction_type.h"
#include "df/workshop_type.h"
#include "df/furnace_type.h"
#include "df/trap_type.h"
#include "df/siegeengine_type.h"
#include "df/building_def.h"
#include "df/building_def_item.h"
#include "df/building_def_workshopst.h"
#include "df/building_def_furnacest.h"
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
  if(!world || !DFHack::Maps::IsValid() || !points(L,1,seeds) || !points(L,2,targets))
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
  if(!lua_isnoneornil(L,3)){
   if(!lua_isinteger(L,3))throw std::runtime_error("invalid construction subtype");
   const auto value=lua_tointeger(L,3);
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

int nativeMaterialRequirements(lua_State* L){
 // Semantic type/subtype/custom-ID and optional eligible road tile count.
 // Never use final configured pressure flags or collect candidates here.
 lua_settop(L,4);
 lua_pushinteger(L,0);lua_insert(L,4);
 lua_pushboolean(L,false);lua_insert(L,3);
 lua_pushboolean(L,false);lua_insert(L,4);
 return nativeMaterialRecipe(L);
}

int nativeMaterialCandidates(lua_State* L){
 // Semantic type/subtype/custom-ID input; native recipe API keeps diagnostic
 // collection/cache controls separate from the optional raw definition ID.
 lua_settop(L,3);
 lua_pushboolean(L,true);lua_insert(L,3);
 lua_pushboolean(L,false);lua_insert(L,4);
 return nativeMaterialRecipe(L);
}

// Owned native recipe/candidate collection. Cold-cache instrumentation is
// diagnostic only; product callers use the ordinary restored-cache path.
int nativeMaterialRecipe(lua_State* L){
 int status=1;std::string reason;
 using Fields=std::map<std::string,int64_t>;std::vector<Fields> rows;
 std::vector<std::vector<int32_t>> candidates;
 const bool collect=lua_toboolean(L,3);
 const bool cold_cache=lua_toboolean(L,4);int64_t cache_insertions=0;
 try{
  auto* base=verifiedBase();auto* world=df::global::world;
  if(!world || !DFHack::Maps::IsValid() || !lua_isinteger(L,1) || !lua_isinteger(L,2))throw std::runtime_error("invalid recipe input");
  auto type=lua_tointeger(L,1),subtype=lua_tointeger(L,2);
  int32_t eligible_tiles=-1;
  if(!lua_isnoneornil(L,7)){
   const auto count=lua_tointeger(L,7);
   if(!lua_isinteger(L,7) || count<-1 || count>961 ||
      (count>=0 && (type!=int(df::building_type::RoadPaved) || subtype!=-1 || collect || cold_cache)))
    throw std::runtime_error("invalid paved road quantity input");
   eligible_tiles=int32_t(count);
  }
  uint32_t plate_flags=0;
  if(!lua_isnoneornil(L,6)){
   const auto flags=lua_tointeger(L,6);
   if(!lua_isinteger(L,6) || flags<0 || flags>63 ||
      (flags!=0 && (type!=int(df::building_type::Trap) || subtype!=int(df::trap_type::PressurePlate))))
    throw std::runtime_error("invalid pressure plate recipe flags");
   plate_flags=uint32_t(flags);
  }
  const bool furniture=type==int(df::building_type::Bed) || type==int(df::building_type::Chair) ||
   type==int(df::building_type::Table) || type==int(df::building_type::Coffin) || type==int(df::building_type::Cabinet) ||
   type==int(df::building_type::Box) || type==int(df::building_type::Statue) || type==int(df::building_type::Slab) ||
   type==int(df::building_type::Cage) || type==int(df::building_type::Chain) ||
   type==int(df::building_type::Door) ||
   type==int(df::building_type::Hatch) ||
   type==int(df::building_type::GrateWall) ||
   type==int(df::building_type::GrateFloor) ||
   type==int(df::building_type::Floodgate) ||
   type==int(df::building_type::Armorstand) ||
   type==int(df::building_type::Weaponrack) ||
   type==int(df::building_type::TractionBench) ||
   type==int(df::building_type::Bookcase) ||
   type==int(df::building_type::DisplayFurniture) ||
   type==int(df::building_type::OfferingPlace) ||
   type==int(df::building_type::Instrument) ||
   type==int(df::building_type::NestBox) ||
   type==int(df::building_type::Hive) ||
   type==int(df::building_type::AnimalTrap) ||
   type==int(df::building_type::WindowGlass) ||
   type==int(df::building_type::Well) ||
   type==int(df::building_type::ScrewPump) ||
   type==int(df::building_type::WaterWheel) ||
   type==int(df::building_type::Windmill) ||
   type==int(df::building_type::GearAssembly) ||
   type==int(df::building_type::AxleVertical) ||
   type==int(df::building_type::AxleHorizontal) ||
   type==int(df::building_type::Rollers) ||
   type==int(df::building_type::BarsVertical) || type==int(df::building_type::BarsFloor) ||
   type==int(df::building_type::WindowGem) || type==int(df::building_type::Support) ||
   type==int(df::building_type::ArcheryTarget) || type==int(df::building_type::TradeDepot) ||
   type==int(df::building_type::Weapon) || type==int(df::building_type::Bridge) ||
   type==int(df::building_type::RoadPaved);
  const bool standard_workshop=type==int(df::building_type::Workshop) &&
   subtype>=int(df::workshop_type::Carpenters) && subtype<=int(df::workshop_type::Millstone);
  const bool standard_furnace=type==int(df::building_type::Furnace) &&
   subtype>=int(df::furnace_type::WoodFurnace) && subtype<=int(df::furnace_type::MagmaKiln);
  const bool trap=type==int(df::building_type::Trap) &&
   subtype>=int(df::trap_type::Lever) && subtype<=int(df::trap_type::TrackStop);
  const bool siege=type==int(df::building_type::SiegeEngine) &&
   subtype>=int(df::siegeengine_type::Catapult) && subtype<=int(df::siegeengine_type::BoltThrower);
  int32_t custom=-1;
  if(!lua_isnoneornil(L,5)){
   if(!lua_isinteger(L,5) || lua_tointeger(L,5)<-1 || lua_tointeger(L,5)>INT32_MAX)
    throw std::runtime_error("invalid custom recipe ID");
   custom=int32_t(lua_tointeger(L,5));
  }
  const bool custom_workshop=type==int(df::building_type::Workshop) && subtype==int(df::workshop_type::Custom);
  const bool custom_furnace=type==int(df::building_type::Furnace) && subtype==int(df::furnace_type::Custom);
  if(custom_workshop || custom_furnace){
   df::building_def* definition=nullptr;
   if(custom>=0){
    if(custom_workshop){for(auto* raw:world->raws.buildings.workshops)if(raw && raw->id==custom){definition=raw;break;}}
    else{for(auto* raw:world->raws.buildings.furnaces)if(raw && raw->id==custom){definition=raw;break;}}
   }
   if(!definition || definition->build_items.empty() || definition->build_items.size()>32)
    throw std::runtime_error("custom recipe unavailable");
   // Raw-defined recipes can introduce arbitrary filter branches. Admit only
   // the already reviewed context-free set before native initialization.
   for(auto* item:definition->build_items){
    if(!item || !item->reaction_class.empty() || !item->has_material_reaction_product.empty() ||
       (item->flags1.whole & ~uint32_t(0x400)) || (item->flags2.whole & ~uint32_t(0x80029e0)) ||
       item->flags3.whole || item->flags4 || item->flags5 || item->metal_ore!=-1)
     throw std::runtime_error("custom recipe filter not admitted");
   }
   if(fingerprint(base+0x6f8d0,0x100)!=0xc1227c6274219d29ULL)
    throw std::runtime_error("native custom recipe copy mismatch");
  }else if(custom!=-1)throw std::runtime_error("unexpected custom recipe ID");
  if(!(trap || siege || custom_workshop || custom_furnace || standard_workshop || standard_furnace || (furniture && subtype==-1) ||
       (type==int(df::building_type::Construction) && subtype>=0 && subtype<=int(df::construction_type::ReinforcedWall))))
   throw std::runtime_error("recipe family not admitted");
  if(fingerprint(base+0xaae4b0,0x1860)!=0x7291e6a95178bf46ULL ||
     fingerprint(base+0xa69bf0,0x78)!=0x3782ceddb0f6f9edULL ||
     fingerprint(base+0x1fb050,0x123)!=0x3ea393db12f2c677ULL)throw std::runtime_error("native recipe function mismatch");
  struct OwnedRequest {
   std::unique_ptr<df::buildreq> request{df::allocate<df::buildreq>()};
   ~OwnedRequest(){if(request){
    for(auto* r:request->requirements)delete r;request->requirements.clear();
    for(auto* e:request->errors)delete e;request->errors.clear();
   }}
  } owned;
  auto* request=owned.request.get();
  if(!request || !request->requirements.empty())throw std::runtime_error("invalid owned recipe request");
  request->building_type=static_cast<df::building_type>(type);request->building_subtype=int16_t(subtype);request->custom_type=custom;
  request->plate_info.flags.whole=plate_flags;
  request->pos=df::coord(-30000,-30000,-30000);request->selection_pos=request->pos;
  reinterpret_cast<void (*)(df::buildreq*)>(base+0xaae4b0)(request);
  if(eligible_tiles>=0){
   // RoadPaved alone takes the owned total_sq/total_sq_level_map branch.
   // Empty owned groups deliberately skip candidate enablement. Reserve the
   // single native "No access" error slot so no native vector growth occurs.
   static_assert(offsetof(df::buildreq,total_sq)==0x104c);
   static_assert(offsetof(df::buildreq,total_sq_level_map)==0x1050);
   static_assert(offsetof(df::buildreq,errors)==0x50);
   if(fingerprint(base+0xaafd10,0x1394)!=0x93009d7cb317779dULL ||
      fingerprint(base+0xab3380,0x23a)!=0x51b7f5fe855db938ULL ||
      fingerprint(base+0x3c1e60,0x7b7)!=0xfcbc3593568b4f03ULL ||
      fingerprint(base+0x6f750,0x5c)!=0x181cd460420a0890ULL ||
      fingerprint(base+0xba940,0x180)!=0xaf685149f97c1b81ULL ||
      fingerprint(base+0x6f8d0,0x100)!=0xc1227c6274219d29ULL)
    throw std::runtime_error("native road quantity function mismatch");
   if(request->requirements.size()!=1 || !request->total_sq_level_map.empty() || !request->errors.empty())
    throw std::runtime_error("unexpected owned road request");
   request->total_sq=eligible_tiles;request->errors.reserve(1);
   reinterpret_cast<void (*)(df::buildreq*)>(base+0xaafd10)(request);
   if(request->errors.size()!=1 || *request->errors.front()!="No access")
    throw std::runtime_error("unexpected owned road quantity branch");
  }
  if(request->requirements.size()>32)throw std::runtime_error("native recipe size limit");
  for(auto* r:request->requirements){
   if(!r)throw std::runtime_error("missing native recipe");
   auto& f=r->filter;
   const auto cache_digest=[&](){
    const auto& cache=world->raws.creatures.hist_fig_to_creature_map;
    uint64_t h=fingerprint(reinterpret_cast<const uint8_t*>(&cache),sizeof(cache));
    for(const auto& node:cache){h^=reinterpret_cast<uintptr_t>(&node);h*=1099511628211ULL;
     h^=uint32_t(node.first);h*=1099511628211ULL;h^=uint32_t(node.second);h*=1099511628211ULL;}
    return h;
   };
   const auto original_cache=cold_cache?cache_digest():0;
   if(collect){
    // Context-free collection only. These guards exclude the native lazy
    // navigation/burrow/stockpile branches; caller never supplies raw filters.
    if(f.pos.x!=-30000 || f.pos.y!=-30000 || f.pos.z!=-30000 || f.unit || f.job || f.building || f.site ||
       f.take_from || f.use_burrows || !f.burrows.empty() || f.use_contains || !f.contains.empty() ||
       (f.flags1.whole & ~uint32_t(0x400)) || (f.flags3.whole & ~uint32_t(0x100)) || f.flags4 || f.flags5 ||
       !f.reaction_class.empty() || !f.has_material_reaction_product.empty())throw std::runtime_error("contextual recipe not admitted");
    if(fingerprint(base+0xa29630,0x177b)!=0xd483c9c32e4f7fc5ULL ||
       fingerprint(base+0xa27c60,0x19c4)!=0x2810b30401cba53eULL ||
       fingerprint(base+0xc93380,0x98)!=0x9455ba082ba604c4ULL ||
       fingerprint(base+0x14add70,0x12f)!=0x01f897b15772d540ULL ||
       fingerprint(base+0x701e70,0x20e)!=0xead0193006374e44ULL ||
       fingerprint(base+0x28a180,0x4a)!=0xa68334b43d827766ULL ||
       fingerprint(base+0xec0d0,0xaf)!=0x902a36a40afea771ULL ||
       fingerprint(base+0xc620d0,0x22)!=0xaf8bd6ff260358adULL ||
       fingerprint(base+0xc91b60,0x693)!=0xd45facefaf059541ULL ||
       fingerprint(base+0x6b8af0,0x96)!=0x8f67f7a1b9d42698ULL ||
       fingerprint(base+0xcb1ec0,0x35)!=0xd10428f757fbaac1ULL ||
       fingerprint(base+0xcb1f00,0x35)!=0xa16ae741945b6f88ULL ||
       fingerprint(base+0x149ef80,0x128)!=0x955b881c6987504aULL)throw std::runtime_error("native collector function mismatch");
    // Material resolution can lazily populate the historical-figure lookup.
    // Preserve its original nodes/buckets, let DF use a private copy at this
    // safe point, then restore the original before any Lua allocation.
    struct RestoreMaterialCache {
     decltype(world->raws.creatures.hist_fig_to_creature_map)& target;
     decltype(world->raws.creatures.hist_fig_to_creature_map) saved;
     explicit RestoreMaterialCache(decltype(target) value):target(value),saved(value){target.swap(saved);}
     ~RestoreMaterialCache(){target.swap(saved);}
    } restore_cache(world->raws.creatures.hist_fig_to_creature_map);
    if(cold_cache)restore_cache.target.clear(); // Diagnostic: only clear the private copy.
    const auto cache_size=restore_cache.target.size();
    reinterpret_cast<void (*)(df::job_item_filter*,std::vector<df::item*>*)>(base+0xa29630)(&f,&r->candidates);
    cache_insertions+=int64_t(restore_cache.target.size())-int64_t(cache_size);
   }
   if(cold_cache && original_cache!=cache_digest())throw std::runtime_error("material cache restoration mismatch");
   std::vector<int32_t> ids;
   if(r->candidates.size()>65536)throw std::runtime_error("native candidate size limit");
   for(auto* item:r->candidates){if(!item)throw std::runtime_error("missing native candidate");ids.push_back(item->id);}
   candidates.push_back(std::move(ids));
   Fields row{{"item_type",int(f.item_type)},{"item_subtype",f.item_subtype},{"mat_type",f.mat_type},{"mat_index",f.mat_index},
    {"flags1",f.flags1.whole},{"flags2",f.flags2.whole},{"flags3",f.flags3.whole},{"flags4",f.flags4},{"flags5",f.flags5},
    {"use_mat_index",f.use_mat_index},{"use_flags2",f.use_flags2},{"use_flags3",f.use_flags3},{"use_flags4",f.use_flags4},{"use_flags5",f.use_flags5},
    {"use_metal_ore",f.use_metal_ore},{"use_reaction_class",f.use_reaction_class},{"use_reaction_product",f.use_reaction_product},{"use_contains",f.use_contains},
    {"metal_ore",f.metal_ore},{"min_dimension",f.min_dimension},{"reaction_id",f.reaction_id},{"has_tool_use",int(f.has_tool_use)},
    {"dye_color",f.dye_color},{"has_melee_skill",int(f.has_melee_skill)},{"can_steal_haul_items",f.can_steal_haul_items},
    {"x",f.pos.x},{"y",f.pos.y},{"z",f.pos.z},{"unit_present",f.unit!=nullptr},{"job_present",f.job!=nullptr},
    {"building_present",f.building!=nullptr},{"site_present",f.site!=nullptr},{"take_from_present",f.take_from!=nullptr},
    {"use_burrows",f.use_burrows},{"burrow_count",int64_t(f.burrows.size())},{"contains_count",int64_t(f.contains.size())},
    {"total_dim_count",f.total_dim_count},{"count_required",r->count_required},{"count_max",r->count_max},{"count_provided",r->count_provided},
    {"candidate_count",int64_t(r->candidates.size())},{"vector_index",-1}};
   for(int i=0;i<=df::enum_traits<df::items_other_id>::last_item_value;++i)
    if(f.item_vector==&world->items.other[static_cast<df::items_other_id>(i)])row["vector_index"]=i;
   rows.push_back(std::move(row));
  }
  status=0;
 }catch(const std::exception& e){reason=e.what();rows.clear();}
 lua_newtable(L);number(L,"status",status);
 if(!reason.empty()){lua_pushlstring(L,reason.data(),reason.size());lua_setfield(L,-2,"reason");}
 lua_newtable(L);for(size_t i=0;i<rows.size();++i){lua_newtable(L);for(const auto& field:rows[i])number(L,field.first.c_str(),field.second);lua_rawseti(L,-2,i+1);}
 lua_setfield(L,-2,"recipes");
 if(cold_cache)number(L,"cache_insertions",cache_insertions);
 if(status==0 && collect){lua_newtable(L);for(size_t i=0;i<candidates.size();++i){lua_newtable(L);
  for(size_t j=0;j<candidates[i].size();++j){lua_pushinteger(L,candidates[i][j]);lua_rawseti(L,-2,j+1);}lua_rawseti(L,-2,i+1);
 }lua_setfield(L,-2,"candidates");}return 1;
}
}
