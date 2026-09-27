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
 if seed then
  for _=1,(kind=='BIN' and 1 or 24) do
   local ok,created=pcall(dfhack.items.createItem,unit,seed:getType(),seed:getSubtype(),seed:getMaterial(),seed:getMaterialIndex())
   if not ok or type(created)~='table' then missing(kind,'item creation unavailable');break end
   for _,id in ipairs(created) do
    local item=df.item.find(id)
    if item and dfhack.items.moveToGround(item,unit.pos) then item.flags.forbid=false;ids[#ids+1]=id end
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
-- Allocate separate 5x5 sites on existing visible walkable floor, near the
-- citizen. Do not overwrite any building, construction, or hidden tile.
local used={}
local function floor(p)
 local flags,occ=dfhack.maps.getTileFlags(p);local tt=dfhack.maps.getTileType(p)
 if not flags or flags.hidden or flags.flow_size>0 or not tt or occ.building~=0 or df.construction.find(p) then return false end
 local a=df.tiletype.attrs[tt]
 return df.tiletype_shape.attrs[a.shape].basic_shape==df.tiletype_shape_basic.Floor
  and dfhack.maps.getWalkableGroup(p)==dfhack.maps.getWalkableGroup(unit.pos)
end
local function allocate()
 for radius=0,45 do for dx=-radius,radius do for dy=-radius,radius do
  if math.abs(dx)==radius or math.abs(dy)==radius then
   local p={x=unit.pos.x+dx,y=unit.pos.y+dy,z=unit.pos.z};local good=true
   for x=p.x,p.x+4 do for y=p.y,p.y+4 do
    if used[x..':'..y] or not floor{x=x,y=y,z=p.z} then good=false;break end
   end;if not good then break end end
   if good then
    for x=p.x,p.x+4 do for y=p.y,p.y+4 do used[x..':'..y]=true end end
    return p
   end
  end
 end end end
end
local names={'depot','well','wheel','farm','bridge','retracting','press','wall','stairs','trap1','trap10','trap0','trap11','partial_bridge','partial_road'}
for i=0,3 do names[#names+1]='pump'..i end
for i=0,7 do names[#names+1]='ballista'..i end
for _,name in ipairs(names) do
 local p=allocate();if p then state.sites[name]=p else missing(name,'no free visible 5x5 floor near citizen') end
end
local function set_tile(p,tt)
 local b=dfhack.maps.getTileBlock(p)
 if not b or b.occupancy[p.x%16][p.y%16].building~=0 then return false end
 b.tiletype[p.x%16][p.y%16]=tt
 b.designation[p.x%16][p.y%16].hidden=false
 return true
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
-- A real existing building supplies the wall-drag obstacle and partial footprint.
for _,b in ipairs(df.global.world.buildings.all) do
 if b:getType()~=df.building_type.Stockpile and b:getType()~=df.building_type.Civzone and b.z==unit.pos.z then
  local p={x=b.x1-1,y=b.y1,z=b.z}
  if floor(p) and floor{x=b.x2+1,y=b.y1,z=b.z} and b.x2-b.x1<29 then
   state.obstacle={x=p.x,y=p.y,z=p.z,width=b.x2-b.x1+3,id=b.id};break
  end
 end
end
if not state.obstacle then missing('obstacle','no building flanked by free floor') end
write('fixture.json',{origin=state.origin,sites=state.sites,incomplete=state.incomplete,unavailable_types=state.unavailable_types,obstacle=state.obstacle,stock=state.stock,binned=state.binned,forbidden=state.forbidden})
print('FIXTURE_READY construction')
