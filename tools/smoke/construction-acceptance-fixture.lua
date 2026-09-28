-- Owned disposable clone only; fixture setup is paused and never saved.
local out=...
local json=require('json')
df.global.pause_state=true
local saved={autosave=df.global.d_init.feature.autosave,announcements={}}
for id,f in ipairs(df.global.d_init.announcements.flags) do saved.announcements[id]=f.whole;f.PAUSE=false;f.DO_MEGA=false end
df.global.d_init.feature.autosave=df.d_init_autosave.NONE
local state={prefs=saved,stock={},sites={},incomplete={},unavailable_types={},placed={}}
_G.df3d_construction_acceptance=state
local function missing(key,reason)
 state.incomplete[key]=reason;print('FIXTURE_INCOMPLETE '..key..': '..reason)
end
local function write(name,value)
 local f=assert(io.open(out..'/'..name,'w'));f:write(json.encode(value));f:close()
end
local unit
for _,u in ipairs(df.global.world.units.active) do
 if dfhack.units.isCitizen(u) and dfhack.units.isActive(u) and not dfhack.units.isDead(u) then unit=u;break end
end
if not unit then
 missing('all','no active citizen');write('fixture.json',state);print('FIXTURE_READY incomplete');return
end
state.origin={x=unit.pos.x,y=unit.pos.y,z=unit.pos.z}
_G.df3d_designation_acceptance={{tile=state.origin}}
-- Reuse real material/subtype identities. Failure to create a kind affects only
-- recipes needing that kind; no fabricated material or item definition is used.
local kinds={'BOULDER','WOOD','BLOCKS','TRAPPARTS','BALLISTAPARTS','BIN','BUCKET','CHAIN','PIPE_SECTION','TOOL','WEAPON'}
local seeds={}
for _,item in ipairs(df.global.world.items.all) do
 local kind=df.item_type[item:getType()]
 if not seeds[kind] then seeds[kind]=item end
end
for _,kind in ipairs(kinds) do
 local seed=seeds[kind];local ids={}
 -- Ballista parts have no subtype; borrow a real log's wood identity when
 -- the save has never produced this item kind. Keep the five-argument API.
 local seed_type=seed and seed:getType()
 local seed_subtype=seed and seed:getSubtype()
 if not seed and kind=='BALLISTAPARTS' and seeds.WOOD then
  seed=seeds.WOOD;seed_type=df.item_type.BALLISTAPARTS;seed_subtype=-1
 end
 if seed then
  for _=1,(kind=='BIN' and 1 or 24) do
   local ok,created=pcall(dfhack.items.createItem,unit,seed_type,seed_subtype,seed:getMaterial(),seed:getMaterialIndex())
   if not ok or type(created)~='table' then missing(kind,'item creation unavailable');break end
   -- DFHack Lua API.rst:2250; LuaApi.cpp:2617-2619 returns df::item* objects.
   for _,item in ipairs(created) do
    if item and dfhack.items.moveToGround(item,unit.pos) then item.flags.forbid=false;ids[#ids+1]=item.id end
   end
  end
 else missing(kind,'no material/subtype seed for item creation') end
 state.stock[kind]=ids
 if #ids==0 then
  if not state.incomplete[kind] then missing(kind,'no items created') end
  if df.item_type[kind] then state.unavailable_types[tostring(df.item_type[kind])]=state.incomplete[kind] end
 end
end
local bin=state.stock.BIN[1] and df.item.find(state.stock.BIN[1])
state.binned={}
if bin then
 for i=1,math.min(4,#state.stock.BLOCKS) do
  local item=df.item.find(state.stock.BLOCKS[i])
  local ok,moved=pcall(dfhack.items.moveToContainer,item,bin)
  if ok and moved then state.binned[#state.binned+1]=item.id end
 end
end
if #state.binned==0 then missing('bins','no blocks could be put in a bin') end
local forbidden=state.stock.BLOCKS[#state.stock.BLOCKS]
if forbidden then
 local item=df.item.find(forbidden);item.flags.forbid=true;state.forbidden=forbidden
 local ok=pcall(function() item.stack_size=4 end)
 if not ok then missing('forbidden_stack','block stack size could not be set') end
else missing('forbidden','no block stack to forbid') end
-- Footprints share origins only when the live script removes and verifies the
-- previous placement first. All preparation happens paused on the owned clone.
local used={[unit.pos.x..':'..unit.pos.y]=true}
local group=dfhack.maps.getWalkableGroup(unit.pos)
local function clear(p)
 local f,o=dfhack.maps.getTileFlags(p)
 return f and o and o.building==0 and f.flow_size==0 and not df.construction.find(p)
end
local function floor(p)
 local f=dfhack.maps.getTileFlags(p);local tt=dfhack.maps.getTileType(p)
 if not clear(p) or f.hidden or not tt then return false end
 local a=df.tiletype.attrs[tt]
 return df.tiletype_shape.attrs[a.shape].basic_shape==df.tiletype_shape_basic.Floor
  and group~=0 and dfhack.maps.getWalkableGroup(p)==group
end
local function set_tile(p,tt)
 local b=dfhack.maps.getTileBlock(p)
 if not b or not clear(p) then return false end
 b.tiletype[p.x%16][p.y%16]=tt
 b.designation[p.x%16][p.y%16].hidden=false
 df.global.world.reindex_pathfinding=true
 return true
end
local function carveable(p)
 if not clear(p) then return false end
 local tt=dfhack.maps.getTileType(p);local a=tt and df.tiletype.attrs[tt]
 return a and a.shape==df.tiletype_shape.WALL
  and (a.material==df.tiletype_material.STONE or a.material==df.tiletype_material.SOIL)
end
local function special_clear(p,name)
 if name=='well' then return clear{x=p.x,y=p.y,z=p.z-1} end
 if name=='stairs' then
  return clear{x=p.x,y=p.y,z=p.z+1} and clear{x=p.x,y=p.y,z=p.z+2}
 end
 return true
end
local function allocate(w,h,name)
 if group==0 then return nil end
 -- Prefer natural floor; otherwise extend it through solid rock/soil. A
 -- cardinal connection to an unreserved floor tile is required, never an
 -- isolated rectangle with an invented walkability id.
 for pass=1,2 do
 for radius=0,45 do for dx=-radius,radius do for dy=-radius,radius do
  if math.abs(dx)==radius or math.abs(dy)==radius then
   local p={x=unit.pos.x+dx,y=unit.pos.y+dy,z=unit.pos.z}
   local good=group~=0 and special_clear(p,name);local connected=false
   for x=p.x,p.x+w-1 do
    if not good then break end
    for y=p.y,p.y+h-1 do
    local q={x=x,y=y,z=p.z}
    if used[x..':'..y] or not (floor(q) or (pass==2 and carveable(q))) then good=false;break end
    for _,d in ipairs{{-1,0},{1,0},{0,-1},{0,1}} do
     local nx,ny=x+d[1],y+d[2]
     if (nx<p.x or nx>=p.x+w or ny<p.y or ny>=p.y+h)
      and not used[nx..':'..ny] and floor{x=nx,y=ny,z=p.z} then connected=true end
    end
   end end
   if good and connected then
    for x=p.x,p.x+w-1 do for y=p.y,p.y+h-1 do
     local q={x=x,y=y,z=p.z}
     if not floor(q) then
      assert(set_tile(q,df.tiletype.StoneFloorSmooth))
      -- The connected rectangle is now floor. Update the paused clone's
      -- cached group; DF recomputes pathing as simulation resumes.
      dfhack.maps.getTileBlock(q).walkable[x%16][y%16]=group
     end
     assert(floor(q),'prepared floor not visible/in citizen walkable group')
     used[x..':'..y]=true
    end end
    return p
   end
  end
 end end end
 end
end
-- Reserve the existing obstacle before allocating any placement sites.
for _,b in ipairs(df.global.world.buildings.all) do
 if b:getType()~=df.building_type.Stockpile and b:getType()~=df.building_type.Civzone and b.z==unit.pos.z then
  local p={x=b.x1-1,y=b.y1,z=b.z}
  if floor(p) and floor{x=b.x2+1,y=b.y1,z=b.z} and b.x2-b.x1<29 then
   for x=p.x,b.x2+1 do used[x..':'..p.y]=true end
   state.obstacle={x=p.x,y=p.y,z=p.z,width=b.x2-b.x1+3,id=b.id};break
  end
 end
end
if not state.obstacle then missing('obstacle','no building flanked by free floor') end
local plans={
 {'well',1,1},{'stairs',1,1},{'wall',1,1},{'trap',1,1},
 {'pump_ns',1,2},{'pump_ew',2,1},{'wheel',3,1},
 {'farm',3,3},{'bridge',3,3},{'retracting',3,3},{'press',3,3},{'siege',3,3},
}
state.site_plan={count=#plans,tiles=0,sites={}}
for _,plan in ipairs(plans) do
 local name,w,h=table.unpack(plan);local p=allocate(w,h,name)
 state.site_plan.tiles=state.site_plan.tiles+w*h
 state.site_plan.sites[#state.site_plan.sites+1]={name=name,width=w,height=h,origin=p}
 if p then state.sites[name]=p else missing(name,'no connected visible '..w..'x'..h..' floor or carveable rock/soil near citizen') end
end
local function alias(name,source)
 state.sites[name]=state.sites[source]
 if state.incomplete[source] then missing(name,state.incomplete[source]) end
end
-- Depot is a material query only; it never places a 5x5 building.
alias('depot','press')
for _,n in ipairs{0,1,10,11} do alias('trap'..n,'trap') end
for i=0,3 do alias('pump'..i,i%2==0 and 'pump_ns' or 'pump_ew') end
for _,family in ipairs{'ballista','catapult'} do
 for i=0,7 do alias(family..i,'siege') end
end
local soil
for id=0,df.tiletype._last_item do
 local a=df.tiletype.attrs[id]
 if a and a.material==df.tiletype_material.SOIL and a.shape==df.tiletype_shape.FLOOR then soil=id;break end
end
if state.sites.farm and soil then
 for dx=0,2 do for dy=0,2 do local p=state.sites.farm;set_tile({x=p.x+dx,y=p.y+dy,z=p.z},soil) end end
else missing('farm','no soil tile definition/site') end
if state.sites.well then
 local p=state.sites.well;local below={x=p.x,y=p.y,z=p.z-1}
 if dfhack.maps.getTileBlock(below) and set_tile(p,df.tiletype.OpenSpace) and set_tile(below,df.tiletype.StoneFloorSmooth) then
  local f=dfhack.maps.getTileFlags(below);f.flow_size=7;f.liquid_type=false
 else missing('well','no loaded open space/water level');state.sites.well=nil end
end
if state.sites.stairs then
 local p=state.sites.stairs
 for dz=1,2 do
  local q={x=p.x,y=p.y,z=p.z+dz}
  if not set_tile(q,df.tiletype.OpenSpace) then missing('stairs','no loaded unobstructed three-level space');state.sites.stairs=nil;break end
 end
end
write('fixture.json',{origin=state.origin,sites=state.sites,incomplete=state.incomplete,unavailable_types=state.unavailable_types,obstacle=state.obstacle,site_plan=state.site_plan,stock=state.stock,binned=state.binned,forbidden=state.forbidden})
print('FIXTURE_READY construction')
