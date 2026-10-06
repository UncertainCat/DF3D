#include "construction_track_route.h"
#include "wm/track_path.h"
#include "lua.h"
#include <limits>
#include <string>
#include <map>
#include <tuple>

namespace df3d_construction {
namespace {
bool integer(lua_State* L,int table,const char* key,int32_t& value) {
  lua_getfield(L,table,key);const bool typed=lua_isinteger(L,-1);int valid=0;const auto n=lua_tointegerx(L,-1,&valid);lua_pop(L,1);
  if(!typed || !valid || n<std::numeric_limits<int32_t>::min() || n>std::numeric_limits<int32_t>::max())return false;
  value=int32_t(n);return true;
}
bool position(lua_State* L,int table,wm::TilePos& p) {
  return lua_istable(L,table) && integer(L,table,"x",p.x) && integer(L,table,"y",p.y) && integer(L,table,"z",p.z);
}
std::optional<bool> boolean(lua_State* L,int table,const char* key) {
  lua_getfield(L,table,key);
  const auto result=lua_isboolean(L,-1)?std::optional<bool>{lua_toboolean(L,-1)!=0}:std::nullopt;
  lua_pop(L,1);return result;
}
std::string text(lua_State* L,int table,const char* key) {
  lua_getfield(L,table,key);const char* value=lua_type(L,-1)==LUA_TSTRING?lua_tostring(L,-1):nullptr;
  const std::string result=value?value:"";lua_pop(L,1);return result;
}
wm::TileShape shape(const std::string& name) {
  using S=wm::TileShape;
  if(name=="EMPTY" || name=="ENDLESS_PIT")return S::Empty;
  if(name=="FLOOR" || name=="BROOK_TOP")return S::Floor;
  if(name=="BOULDER")return S::Boulder;
  if(name=="PEBBLES")return S::Pebbles;
  if(name=="BRANCH" || name=="TWIG")return S::TreeBranch;
  if(name=="TRUNK_BRANCH" || name=="BROOK_BED")return S::TreeTrunk;
  if(name=="WALL")return S::Wall;
  if(name=="FORTIFICATION")return S::Fortification;
  if(name=="RAMP")return S::Ramp;
  if(name=="RAMP_TOP")return S::RampTop;
  if(name=="STAIR_UP")return S::StairUp;
  if(name=="STAIR_DOWN")return S::StairDown;
  if(name=="STAIR_UPDOWN")return S::StairUpDown;
  if(name=="SHRUB")return S::Shrub;
  if(name=="SAPLING")return S::Sapling;
  return S::Unknown;
}
void field(lua_State* L,const char* key,int32_t value){lua_pushinteger(L,value);lua_setfield(L,-2,key);}
void pushPosition(lua_State* L,wm::TilePos p){lua_newtable(L);field(L,"x",p.x);field(L,"y",p.y);field(L,"z",p.z);}
}
int routeTrack(lua_State* L) {
  wm::TilePos start,end,maximum;
  wm::TrackPathResult result{wm::TrackPathStatus::InvalidInput,{}};
  std::string reason;
  if(lua_isfunction(L,1) && position(L,2,start) && position(L,3,end) && position(L,4,maximum)) {
    bool readerFailed=false;
    result=wm::routeTrackConstruction(start,end,{0,0,0},maximum,[&](wm::TilePos p) {
      wm::TrackRoutingTile value;
      const int top=lua_gettop(L);
      lua_pushvalue(L,1);pushPosition(L,p);
      // Protect Lua failure without longjmp across the routing containers.
      if(lua_pcall(L,1,1,0)!=LUA_OK || !lua_istable(L,-1)) {
        readerFailed=true;lua_settop(L,top);return value;
      }
      const int table=lua_gettop(L);
      const auto loaded=boolean(L,table,"loaded");
      if(loaded && *loaded) {
        const auto hidden=boolean(L,table,"hidden"),magma=boolean(L,table,"magma");
        int32_t depth=0;
        if(!hidden || !magma || !integer(L,table,"liquid_depth",depth) || depth<0 || depth>7) {
          readerFailed=true;lua_settop(L,top);return value;
        }
        value.site.loaded=true;value.site.hidden=*hidden;value.site.magma=*magma;
        value.site.liquidDepth=uint8_t(depth);value.site.shape=shape(text(L,table,"native_shape"));
        if(text(L,table,"native_shape")=="TWIG") {
          const auto endpointOnly=boolean(L,table,"endpoint_only");
          if(!endpointOnly)readerFailed=true;
          else value.site.endpointOnly=*endpointOnly;
        }
        const auto occupancy=text(L,table,"occupancy");
        if(occupancy=="None")value.site.occupancy=wm::TrackSiteOccupancy::None;
        else if(occupancy=="PendingTrack")value.site.occupancy=wm::TrackSiteOccupancy::PendingTrack;
        else if(occupancy=="BlockingBuilding")value.site.occupancy=wm::TrackSiteOccupancy::BlockingBuilding;
        value.clearanceBlocked=boolean(L,table,"clearance_blocked");
        value.support=boolean(L,table,"support");value.open=boolean(L,table,"open");
        value.movementRamp=boolean(L,table,"movement_ramp");
        value.walkable=boolean(L,table,"walkable");
      } else if(!loaded)readerFailed=true;
      if(reason.empty() && (!value.site.loaded || value.site.shape==wm::TileShape::Unknown || value.site.occupancy==wm::TrackSiteOccupancy::Unknown))
        reason="unverified tile "+std::to_string(p.x)+","+std::to_string(p.y)+","+std::to_string(p.z)+" shape="+text(L,table,"native_shape")+" occupancy="+text(L,table,"occupancy");
      lua_settop(L,top);return value;
    });
    if(readerFailed && result.status!=wm::TrackPathStatus::InvalidInput)
      result={wm::TrackPathStatus::UnverifiedTerrain,{}};
  }
  lua_newtable(L);field(L,"status",int32_t(result.status));
  if(result.status==wm::TrackPathStatus::UnverifiedTerrain && !reason.empty()){lua_pushlstring(L,reason.data(),reason.size());lua_setfield(L,-2,"reason");}
  lua_newtable(L);int index=0;
  for(const auto p:result.tiles){pushPosition(L,p);lua_rawseti(L,-2,++index);}
  lua_setfield(L,-2,"path");return 1;
}
int planTrack(lua_State* L) {
  std::vector<wm::TilePos> path;
  std::vector<wm::PendingTrack> pending;
  std::vector<wm::TrackTerrain> terrain;
  std::map<std::tuple<int32_t,int32_t,int32_t>,bool> ramps;
  bool valid=lua_isfunction(L,1) && lua_istable(L,2);
  const auto count=valid?lua_rawlen(L,2):0;
  valid=valid && count>=2 && count<=16384;
  for(size_t i=1;valid && i<=count;++i) {
    const int top=lua_gettop(L);
    lua_rawgeti(L,2,i);wm::TilePos p;
    valid=position(L,lua_gettop(L),p) && p.x>=0 && p.y>=0 && p.z>=0;
    lua_settop(L,top);
    if(!valid)break;
    path.push_back(p);
    lua_pushvalue(L,1);pushPosition(L,p);
    if(lua_pcall(L,1,1,0)!=LUA_OK || !lua_istable(L,-1)) {
      valid=false;lua_settop(L,top);break;
    }
    const int table=lua_gettop(L);
    const auto loaded=boolean(L,table,"loaded");
    const auto nativeShape=shape(text(L,table,"native_shape"));
    const auto occupancy=text(L,table,"occupancy");
    valid=loaded && *loaded && nativeShape!=wm::TileShape::Unknown &&
        (occupancy=="None" || occupancy=="PendingTrack");
    valid=valid && ramps.emplace(std::make_tuple(p.x,p.y,p.z),nativeShape==wm::TileShape::Ramp).second;
    lua_getfield(L,table,"pending");
    if(occupancy=="PendingTrack") {
      int32_t id=-1,mask=0;
      const int entry=lua_gettop(L);
      if(!lua_istable(L,entry))valid=false;
      else {
        const auto ramp=boolean(L,entry,"ramp");
        if(!ramp || !integer(L,entry,"id",id) || id<0 ||
            !integer(L,entry,"connections",mask) || mask<1 || mask>15)valid=false;
        else pending.push_back({p,id,uint8_t(mask),*ramp});
      }
    } else if(!lua_isnil(L,-1))valid=false;
    lua_pop(L,1);
    lua_getfield(L,table,"terrain");
    if(!lua_isnil(L,-1)) {
      const int entry=lua_gettop(L);int32_t mask=0;
      if(!lua_istable(L,entry))valid=false;
      else {
        const auto ramp=boolean(L,entry,"ramp");const auto kind=text(L,entry,"kind");
        if(!ramp || !integer(L,entry,"connections",mask) || mask<1 || mask>15 ||
            (kind!="Carved" && kind!="Constructed"))valid=false;
        else terrain.push_back({p,uint8_t(mask),kind=="Carved"?wm::TrackTerrainKind::Carved:wm::TrackTerrainKind::Constructed,*ramp});
      }
    }
    lua_settop(L,top);
  }
  std::optional<wm::TrackConstructionPlan> plan;
  if(valid)plan=wm::planTrackConstruction(path,pending,terrain,[&](wm::TilePos p){return ramps.at({p.x,p.y,p.z});});
  lua_newtable(L);lua_pushboolean(L,plan.has_value());lua_setfield(L,-2,"verified");
  if(plan) {
    field(L,"new_count",int32_t(plan->newPieceCount));
    lua_newtable(L);int index=0;
    for(const auto& piece:plan->pieces) {
      pushPosition(L,piece.position);
      field(L,"action",int32_t(piece.action));field(L,"building_id",piece.buildingId);
      field(L,"connections",piece.connections);field(L,"expected_connections",piece.expectedConnections);
      field(L,"expected_terrain_connections",piece.expectedTerrainConnections);
      field(L,"expected_terrain_kind",int32_t(piece.expectedTerrainKind));
      lua_pushboolean(L,piece.ramp);lua_setfield(L,-2,"ramp");
      lua_pushboolean(L,piece.expectedJobRamp);lua_setfield(L,-2,"expected_job_ramp");
      lua_pushboolean(L,piece.expectedTerrainRamp);lua_setfield(L,-2,"expected_terrain_ramp");
      lua_rawseti(L,-2,++index);
    }
    lua_setfield(L,-2,"pieces");
  }
  return 1;
}
}
