-- Owned disposable clone only. Native prerequisite setup, never command effects.
local out,mode=...
local json=require('json')
local B,U=dfhack.buildings,dfhack.units
df.global.pause_state=true
if not _G.df3d_areas_acceptance_prefs then
 local saved={autosave=df.global.d_init.feature.autosave,announcements={}}
 for id,flags in ipairs(df.global.d_init.announcements.flags) do saved.announcements[id]=flags.whole end
 _G.df3d_areas_acceptance_prefs=saved
end
df.global.d_init.feature.autosave=df.d_init_autosave.NONE
for _,flags in ipairs(df.global.d_init.announcements.flags) do flags.PAUSE=false;flags.DO_MEGA=false end
print('FIXTURE_WRITE memory autosave disabled; announcement pauses disabled; paused')
-- Multi exercises furniture already present in region5. The broader Areas
-- fixture creates overlapping zones whose collision flags can settle later,
-- contaminating an otherwise exact before/after comparison during Undo.
if mode=='multi' or mode=='location' then
 local state={zones={},missing={}}
 if mode=='location' then
  -- The location lane's terrain fixture is anchored here. The shared guard
  -- only reads this region; it does not run a designation fixture.
  _G.df3d_designation_acceptance={{tile={x=170,y=57,z=164}}}
 end
 _G.df3d_areas_acceptance=state
 local file=assert(io.open(out..'/fixture.json','w'));file:write(json.encode(state));file:close()
 print('FIXTURE_READY')
 return
end
local state={zones={},missing={},pile=-1,workshop=-1,grazer=-1,caged=-1,squad=-1,tavern=-1,owner=-1}
local function missing(key,why)
 state.missing[key]=why;print('FIXTURE_INCOMPLETE '..key..': '..why)
end
local function shown(b)
 local d=dfhack.maps.getTileFlags{x=b.centerx,y=b.centery,z=b.z}
 return d and not d.hidden
end
for _,u in ipairs(df.global.world.units.active) do
 if U.isActive(u) and not U.isDead(u) then
  if U.isCitizen(u) and state.owner<0 then state.owner=u.id end
  if not U.isCitizen(u) and (U.isTame(u) or u.flags1.caged) then
   if U.isGrazer(u) and state.grazer<0 then state.grazer=u.id end
   if u.flags1.caged and state.caged<0 then state.caged=u.id end
  end
 end
end
for _,b in ipairs(df.global.world.buildings.all) do
 if b:canLinkToStockpile() and not df.building_stockpilest:is_instance(b) and shown(b) then state.workshop=b.id;state.workshop_origin={x=b.x1,y=b.y1,z=b.z};break end
end
for _,s in ipairs(df.global.world.squads.all) do
 if s.entity_id==df.global.plotinfo.group_id then state.squad=s.id;break end
end
for _,key in ipairs{'owner','grazer','caged','workshop','squad'} do
 if state[key]<0 then missing(key,'no eligible native '..key..' in clone') end
end
-- Give the caged-animal command observable work at both cage endpoints.
-- Physical containment remains untouched; assigning a hauling destination is
-- distinct from moving the animal out of its current cage.
state.cage_assignments={}
if state.caged>=0 then
 for _,cage in ipairs(df.global.world.buildings.other.CAGE) do
  local found=false
  for _,unit_id in ipairs(cage.assigned_units) do if unit_id==state.caged then found=true end end
  if not found then cage.assigned_units:insert('#',state.caged);print('FIXTURE_WRITE cage '..cage.id..' assigned animal '..state.caged) end
  state.cage_assignments[#state.cage_assignments+1]=cage.id
  if #state.cage_assignments==2 then break end
 end
 if #state.cage_assignments<2 then missing('cage_endpoints','fewer than two native cages for multi-cage removal evidence') end
end
-- Select a genuinely free 24x24 floor. No terrain, occupancy, items or existing
-- buildings are erased to make room. The 20x20 paint test and fixture pile use
-- disjoint portions of this footprint; zones may overlap one another.
local function free(x,y,z)
 local block=dfhack.maps.getTileBlock(x,y,z)
 if not block then return false end
 local tx,ty=x%16,y%16
 local d,o=block.designation[tx][ty],block.occupancy[tx][ty]
 if d.hidden or d.flow_size~=0 or o.building~=0 then return false end
 local attr=df.tiletype.attrs[block.tiletype[tx][ty]]
 if attr.shape~=df.tiletype_shape.FLOOR then return false end
 for _,b in ipairs(df.global.world.buildings.other.STOCKPILE) do
  if b.z==z and x>=b.x1 and x<=b.x2 and y>=b.y1 and y<=b.y2 then return false end
 end
 return true
end
local origin
local mx,my,mz=dfhack.maps.getTileSize()
local wall=dfhack.getTickCount()+15000
-- One pass per loaded elevation, preferring the citizen's elevation.
local levels={};local citizen=df.unit.find(state.owner)
if citizen then levels[1]=citizen.pos.z end
for z=0,mz-1 do if not citizen or z~=citizen.pos.z then levels[#levels+1]=z end end
for _,z in ipairs(levels) do
 local heights={}
 for y=1,my-2 do
  local run=0
  for x=1,mx-2 do
   heights[x]=free(x,y,z) and (heights[x] or 0)+1 or 0
   run=heights[x]>=24 and run+1 or 0
   if run>=24 then origin={x=x-23,y=y-23,z=z};break end
  end
  if origin or dfhack.getTickCount()>=wall then break end
 end
 if origin or dfhack.getTickCount()>=wall then break end
end
if not origin then
 missing('footprint','no free visible 24x24 floor found within 15 second fixture scan')
else
 state.origin=origin
 -- The shared guard reads this anchor; it does not run the designation fixture.
 _G.df3d_designation_acceptance={{tile={x=origin.x,y=origin.y,z=origin.z}}}
 local pos={x=origin.x+21,y=origin.y+21,z=origin.z}
 local pile,err=B.constructBuilding{type=df.building_type.Stockpile,abstract=true,pos=pos,width=2,height=2}
 if not pile then missing('pile',tostring(err)) else
  state.pile=pile.id;pile.name='DF3D acceptance pile'
  pile.storage.max_barrels=2;pile.storage.max_bins=1;pile.storage.max_wheelbarrows=1
  pile.stockpile_flag.use_links_only=true
  print('FIXTURE_WRITE created pile '..pile.id..' containers=2/1/1 links_only=true')
 end
 local types={'MeetingHall','Bedroom','DiningHall','Office','Dormitory','Pen','Pond','WaterSource',
  'FishingArea','SandCollection','ClayCollection','Dump','AnimalTraining','PlantGathering','Tomb','Barracks','ArcheryRange','Dungeon'}
 for _,key in ipairs(types) do
  local zone,problem=B.constructBuilding{type=df.building_type.Civzone,subtype=df.civzone_type[key],
   abstract=true,pos={x=origin.x+21,y=origin.y,z=origin.z},width=2,height=2}
  if not zone then missing(key,tostring(problem)) else
   zone.spec_sub_flag.active=true;zone.name='DF3D acceptance '..key
   state.zones[key]=zone.id;print('FIXTURE_WRITE created zone '..key..' '..zone.id)
  end
 end
end
local site=dfhack.world.getCurrentSite()
if site then
 for _,v in ipairs(site.buildings) do
  if df.abstract_building_inn_tavernst:is_instance(v) then state.tavern=v.id;break end
 end
end
-- Existing taverns are sufficient prerequisites; a native allocation is made
-- only when absent. This record is not attached to any existing zone.
if site and state.tavern<0 then
 local tavern=df.abstract_building_inn_tavernst:new()
 tavern.id=site.next_building_id;tavern.site_id=site.id;tavern.pos:assign(site.pos)
 tavern.name.first_name='DF3D acceptance tavern';tavern.name.has_name=true
 tavern.name.type=df.language_name_type.FoodStore
 tavern.flags.VISITORS_ALLOWED=true;tavern.flags.NON_CITIZENS_ALLOWED=true
 tavern.contents.desired_goblets=10;tavern.contents.desired_instruments=5
 tavern.contents.need_more.goblets=true;tavern.contents.need_more.instruments=true
 for _,link in ipairs(site.entity_links) do
  local entity=df.historical_entity.find(link.entity_id)
  if entity and entity.type==df.historical_entity_type.SiteGovernment then tavern.site_owner_id=entity.id;break end
 end
 site.buildings:insert('#',tavern);site.next_building_id=site.next_building_id+1
 state.tavern=tavern.id;print('FIXTURE_WRITE created unattached tavern '..tavern.id)
end
if state.tavern<0 then missing('tavern','no current site') end
-- Native captures233937/235437 establish retained wall/fortification extents.
-- Observe the same region5 tiles; never alter terrain to make this case pass.
local wall_sample={x=171,y=56,z=164}
local shapes={FLOOR=0,WALL=0}
local observed=true
for y=56,58 do for x=171,173 do
 local block=dfhack.maps.getTileBlock{x=x,y=y,z=164}
 if not block or block.designation[x%16][y%16].hidden then observed=false
 else
  local shape=df.tiletype_shape[df.tiletype.attrs[block.tiletype[x%16][y%16]].shape]
  shapes[shape]=(shapes[shape]or 0)+1
 end
end end
local fort=dfhack.maps.getTileBlock{x=102,y=71,z=165}
if observed and shapes.FLOOR==5 and shapes.WALL==4 and fort and not fort.designation[6][7].hidden and
 df.tiletype.attrs[fort.tiletype[6][7]].shape==df.tiletype_shape.FORTIFICATION then
 state.zone_wall_origin=wall_sample
 state.zone_fortification={x=102,y=71,z=165}
else missing('zone wall paint','native reference terrain is unavailable or changed') end
_G.df3d_areas_acceptance=state
local file=assert(io.open(out..'/fixture.json','w'));file:write(json.encode(state));file:close()
print('FIXTURE_READY')
