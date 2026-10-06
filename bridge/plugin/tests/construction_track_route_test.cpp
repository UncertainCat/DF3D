#include "../construction_track_route.h"
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include <iostream>

int main(int argc,char** argv) {
  auto* L=luaL_newstate();if(!L)return 2;
  luaL_openlibs(L);lua_pushcfunction(L,df3d_construction::routeTrack);lua_setglobal(L,"route");
  lua_pushcfunction(L,df3d_construction::planTrack);lua_setglobal(L,"plan");
  const char* checks=R"LUA(
local start,goal,bounds={x=0,y=0,z=0},{x=2,y=0,z=0},{x=2,y=1,z=0}
local calls={}
local function floor(p)
 local key=p.x..':'..p.y..':'..p.z;calls[key]=(calls[key]or 0)+1
 return {loaded=true,native_shape='FLOOR',occupancy='None',hidden=false,
         liquid_depth=0,magma=false,walkable=true,clearance_blocked=false,support=false,open=false}
end
local r=route(floor,start,goal,bounds)
assert(r.status==0 and #r.path==3 and r.path[1].x==0 and r.path[3].x==2)
for _,n in pairs(calls)do assert(n==1,'reader sampled coordinate twice')end
r=route(floor,goal,start,bounds)
assert(r.status==0 and r.path[1].x==2 and r.path[3].x==0)
assert(route(floor,start,start,bounds).status==1)
assert(route(floor,start,{x=-1,y=0,z=0},bounds).status==2)
assert(route(false,start,goal,bounds).status==2)
assert(route(floor,{x=0.5,y=0,z=0},goal,bounds).status==2)
local function unknown(fn)
 local value=route(fn,start,goal,bounds)
 assert(value.status==4 and #value.path==0,'unknown facts produced a route/refusal')
end
unknown(function()error('synthetic reader error')end)
unknown(function()return false end)
unknown(function()return {loaded=false}end)
unknown(function(p)local t=floor(p);t.liquid_depth=9;return t end)
unknown(function(p)local t=floor(p);t.hidden=nil;return t end)
unknown(function(p)local t=floor(p);t.native_shape='UNRECOGNIZED';return t end)
unknown(function(p)local t=floor(p);t.native_shape='TWIG';return t end)
unknown(function(p)local t=floor(p);t.occupancy='Unknown';return t end)
local blocked=route(function(p)local t=floor(p);if p.x==1 then t.occupancy='BlockingBuilding'end;return t end,start,goal,{x=2,y=0,z=0})
assert(blocked.status==1 and #blocked.path==0)
-- A failed reader call must leave the Lua stack usable for another request.
assert(route(floor,start,goal,bounds).status==0)
for _,case in ipairs{{status=4},{value=false,status=1},{value=true,status=0},{value=1,status=4}}do
 local reader=function(q)
  local t=floor(q)
  t.native_shape=q.z==0 and (q.x==0 and 'RAMP' or 'WALL') or (q.x==0 and 'RAMP_TOP' or 'FLOOR')
  t.support=q.z==0 and q.x==1
  t.movement_ramp=q.z==0 and q.x==0 and case.value or false
  if q.z==0 and q.x==0 then t.movement_ramp=case.value end
  return t
 end
 local value=route(reader,{x=0,y=0,z=0},{x=1,y=0,z=1},{x=1,y=0,z=1})
 assert(value.status==case.status,'native ramp fact did not distinguish true/false/unknown')
end
for _,case in ipairs{{status=4},{value=false,status=1},{value=true,status=0},{value=1,status=4}}do
 local reader=function(q)
  local t=floor(q)
  t.native_shape=q.z==0 and (q.x==0 and 'FLOOR' or q.x==1 and 'RAMP' or 'WALL') or (q.x==1 and 'RAMP_TOP' or q.x==2 and 'FLOOR' or 'WALL')
  t.support=t.native_shape=='WALL';t.movement_ramp=t.native_shape=='RAMP'
  t.walkable=case.value
  return t
 end
 local a,b,bounds={x=0,y=0,z=0},{x=2,y=0,z=1},{x=2,y=0,z=1}
 assert(route(reader,a,b,bounds).status==case.status,'walkability false/unknown distinction')
 assert(route(reader,{x=1,y=0,z=0},b,bounds).status==0,'start must skip source walkability')
end
local path={start,{x=1,y=0,z=0},goal}
local p=plan(floor,path)
assert(p.verified and p.new_count==3 and #p.pieces==3)
assert(p.pieces[1].connections==4 and p.pieces[2].connections==12 and p.pieces[3].connections==8)
local function joining(q)
 local v=floor(q)
 if q.x==1 then v.occupancy='PendingTrack';v.pending={id=8,connections=3,ramp=false}end
 return v
end
p=plan(joining,path)
assert(p.verified and p.new_count==2 and p.pieces[2].action==1 and p.pieces[2].building_id==8 and p.pieces[2].connections==15)
assert(p.pieces[2].expected_connections==3)
for _,kind in ipairs{'Carved','Constructed'}do
 p=plan(function(q)local v=floor(q);v.terrain={connections=12,ramp=false,kind=kind};return v end,path)
 assert(p.verified and p.new_count==3 and p.pieces[1].connections==12)
end
p=plan(function(q)local v=floor(q);v.occupancy='PendingTrack';v.pending={id=q.x,connections=12,ramp=false};return v end,path)
assert(p.verified and p.new_count==0 and p.pieces[1].action==2)
for _,bad in ipairs{
 function()error('reader failure')end,
 function(q)local v=floor(q);v.occupancy='PendingTrack';return v end,
 function(q)local v=joining(q);if v.pending then v.pending.connections=16 end;return v end,
 function(q)local v=joining(q);if v.pending then v.pending.id='8' end;return v end,
 function(q)local v=floor(q);v.terrain={connections=12,ramp=false,kind='Unknown'};return v end,
 function(q)local v=floor(q);v.terrain=false;return v end,
 function(q)local v=floor(q);v.occupancy='Unknown';return v end
}do assert(not plan(bad,path).verified)end
assert(not plan(floor,{start,start}).verified)
assert(not plan(floor,{start,goal}).verified)
assert(plan(floor,path).verified,'failed planning corrupted Lua stack')
)LUA";
  int code=luaL_dostring(L,checks);
  if(code==LUA_OK && argc>=2) {
    code=luaL_loadfile(L,argv[1]);
    if(code==LUA_OK)code=lua_pcall(L,0,1,0);
    if(code==LUA_OK) {
      lua_setglobal(L,"native_reader");
      code=luaL_dostring(L,R"LUA(
df={tiletype_shape={[0]='FLOOR'},tiletype_material={CONSTRUCTION=1},
    construction_type={[21]='TrackEW'},building_type={[0]='Construction',[1]='Support'},
    tiletype={[43]='StoneFloorSmooth',OpenSpace=32,Chasm=19,EeriePit=21,attrs={[43]={shape=0,material=0}}}}
local block={tiletype={},designation={},occupancy={},walkable={}}
for x=0,15 do
 block.tiletype[x]={};block.designation[x]={};block.occupancy[x]={};block.walkable[x]={}
 for y=0,15 do
  block.tiletype[x][y]=43;block.designation[x][y]={hidden=false,flow_size=0,liquid_type=false}
  block.occupancy[x][y]={building=0};block.walkable[x][y]=1
 end
end
local pending={id=8,getType=function()return 0 end,getSubtype=function()return 21 end,
 getBuildStage=function()return 0 end,getMaxBuildStage=function()return 1 end}
local building
dfhack={maps={getTileBlock=function()return block end},
 buildings={findAtTile=function(p)return p.x==1 and building or nil end,markedForRemoval=function()return false end}}
local a,b,max={x=0,y=0,z=0},{x=2,y=0,z=0},{x=2,y=0,z=0}
assert(route(native_reader,a,b,max).status==0)
building=pending;block.occupancy[1][0].building=1
local value=route(native_reader,a,b,max)
assert(value.status==0 and #value.path==3,'native reader pending job blocked route')
local planned=plan(native_reader,value.path)
assert(planned.verified and planned.new_count==2 and planned.pieces[2].action==2)
pending.getType=function()return 1 end
assert(route(native_reader,a,b,max).status==1,'native reader support failed to block route')
pending.getType=function()return 0 end
pending.getBuildStage=function()return 1 end
assert(route(native_reader,a,b,max).status==4,'unverified transient construction stage became a refusal')
)LUA");
    }
  }
  if(code==LUA_OK && argc>=3)code=luaL_dofile(L,argv[2]);
  if(code!=LUA_OK)std::cerr<<lua_tostring(L,-1)<<'\n';
  lua_close(L);
  if(code!=LUA_OK)return 1;
  std::cout<<"TRACK_CALLBACK_PASS\n";return 0;
}
