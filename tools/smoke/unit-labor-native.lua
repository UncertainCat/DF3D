-- Native creature Labor pages in an owned paused clone.
local unit,view,capture,out=...
local gui=require('gui');local json=require('json')
local g=df.global.gps;local sheet=df.global.game.main_interface.view_sheets
local frame=df.global.world.frame_counter
local function row(y)
 local text={};for x=0,g.dimx-1 do local ch=dfhack.screen.readTile(x,y).ch;text[#text+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
 return table.concat(text)
end
local function click(x,y)
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
end
local function select(name,first,last)
 for y=first,last do local x=row(y):lower():find(name:lower(),1,true);if x then
  click((x-1)*8+4,y*12+10)
  return
 end end
 error('Missing native Labor tab '..name)
end
assert(sheet.open and sheet.active_id==unit.id,'Expected creature sheet')
select('Labor',15,16)
local result={unit_id=unit.id,pages={}}
for _,name in ipairs{'Work details','Workshops','Locations','Work animals'}do
 select(name,17,20)
 local page={name=name,tab=sheet.unit_labor_active_tab,first=sheet.scroll_position_unit_labor,lines={},vectors={}}
 for _,field in ipairs{'unit_workshop_id','unit_labor_assigned_animal_unid','unit_labor_assignable_animal_unid'}do
  local values={};for _,value in ipairs(sheet[field])do values[#values+1]=value end;page.vectors[field]=values
 end
 for y=17,g.dimy-1 do local text=dfhack.df2utf(row(y)):gsub('%s+$','');if text~=''then page.lines[#page.lines+1]={y=y,text=text}end end
 result.pages[#result.pages+1]=page;capture('unit-labor-'..name:lower():gsub(' ','-'))
end
if os.getenv('DF3D_UNIT_LABOR_ACTIONS')=='1'then
 select('Work details',17,20)
 local function snapshot()
  local state={details={},labors={},only_assigned=unit.flags4.only_do_assigned_jobs}
  for _,detail in ipairs(df.global.plotinfo.labor_info.work_details)do
   local assigned={};for _,id in ipairs(detail.assigned_units)do assigned[#assigned+1]=id end
   state.details[#state.details+1]={name=detail.name,flags=detail.flags.whole,assigned=assigned}
  end
  for i=0,93 do state.labors[#state.labors+1]=unit.status.labors[i]end
  return state
 end
 local function member(state,index)
  for _,id in ipairs(state.details[index].assigned)do if id==unit.id then return true end end;return false
 end
 local before=snapshot();assert(not member(before,1) and not member(before,2),'Labor action reference requires unassigned first two details')
 result.actions={before=before}
 click(864,286);result.actions.miner=snapshot();assert(member(result.actions.miner,1),'Miner assignment failed')
 capture('unit-labor-miner')
 click(864,322);result.actions.woodcutter=snapshot()
 assert(member(result.actions.woodcutter,2) and not member(result.actions.woodcutter,1),'Native specialized-detail exclusion missing')
 capture('unit-labor-woodcutter')
 click(864,322);assert(json.encode(snapshot())==json.encode(before),'Unassign did not restore baseline labor state')
 click(448,250);result.actions.scope=snapshot();assert(result.actions.scope.only_assigned~=before.only_assigned,'Work scope did not toggle')
 capture('unit-labor-scope')
 click(448,250);assert(json.encode(snapshot())==json.encode(before),'Scope toggle did not restore baseline')
 result.actions.restored=true
end
if os.getenv('DF3D_UNIT_LABOR_ELIGIBILITY')=='1'then
 select('Work details',17,20)
 local position
 for _,role in ipairs(dfhack.units.getNoblePositions(unit))do
  if role.entity.id==df.global.plotinfo.group_id then position=role.position;break end
 end
 assert(position and not position.flags.MENIAL_WORK_EXEMPTION,'Expected non-exempt local office')
 local ok,err=xpcall(function()
  position.flags.MENIAL_WORK_EXEMPTION=true;view:render(dfhack.getTickCount())
  result.exempt={lines={}}
  for y=19,g.dimy-1 do local text=dfhack.df2utf(row(y)):gsub('%s+$','');if text~=''then result.exempt.lines[#result.exempt.lines+1]={y=y,text=text}end end
  capture('unit-labor-exempt')
 end,debug.traceback)
 position.flags.MENIAL_WORK_EXEMPTION=false;view:render(dfhack.getTickCount());assert(ok,err)
end
if os.getenv('DF3D_UNIT_LABOR_WORKSHOP')=='1'then
 local building,profile
 for _,candidate in ipairs(df.global.world.buildings.other.WORKSHOP_ANY)do
  local p=candidate:getWorkshopProfile()
  if p then building=candidate;profile=p;break end
 end
 assert(building,'Expected workshop with worker profile')
 local old={};for _,id in ipairs(profile.permitted_workers)do old[#old+1]=id end
 local ok,err=xpcall(function()
  local ids={};for _,id in ipairs(old)do if id~=unit.id then ids[#ids+1]=id end end
  ids[#ids+1]=unit.id;table.sort(ids);profile.permitted_workers:resize(0)
  for _,id in ipairs(ids)do profile.permitted_workers:insert('#',id)end
  select('Workshops',17,20)
  local data={building_id=building.id,building_type=building:getType(),subtype=building:getSubtype(),position={building.centerx,building.centery,building.z},ids={},lines={}}
  for _,id in ipairs(sheet.unit_workshop_id)do data.ids[#data.ids+1]=id end
  assert(#data.ids>0,'Native workshop list omitted dedicated worker')
  for y=19,g.dimy-1 do local text=dfhack.df2utf(row(y)):gsub('%s+$','');if text~=''then data.lines[#data.lines+1]={y=y,text=text}end end
  result.workshop_fixture=data;capture('unit-labor-workshop-assigned')
  local labors={};for i=0,93 do labors[#labors+1]=unit.status.labors[i]end
  click(864,286)
  for _,id in ipairs(profile.permitted_workers)do assert(id~=unit.id,'Native workshop Remove retained selected worker')end
  for _,id in ipairs(sheet.unit_workshop_id)do assert(id~=building.id,'Native workshop Remove retained row')end
  for i=0,93 do assert(unit.status.labors[i]==labors[i+1],'Native workshop Remove changed labor flags')end
  data.remove={worker_removed=true,row_removed=true,labors_unchanged=true,remaining_workers={}}
  for _,id in ipairs(profile.permitted_workers)do data.remove.remaining_workers[#data.remove.remaining_workers+1]=id end
  capture('unit-labor-workshop-removed')
 end,debug.traceback)
 profile.permitted_workers:resize(0);for _,id in ipairs(old)do profile.permitted_workers:insert('#',id)end
 assert(ok,err)
end
if os.getenv('DF3D_UNIT_LABOR_LOCATIONS')=='1'then
 local target
 for _,candidate in ipairs(df.global.world.units.active)do
  for _,role in ipairs(candidate.occupations)do
   if role.location_id>=0 and role.site_id==df.global.plotinfo.site_id then target=candidate;break end
  end
  if target then break end
 end
 assert(target,'Expected active creature with a local location occupation')
 local original=sheet.active_id
 local ok,err=xpcall(function()
  sheet.active_id=target.id;view:render(dfhack.getTickCount())
  select('Labor',15,16);select('Locations',17,20)
  local data={unit_id=target.id,occupations={},lines={}}
  for _,role in ipairs(target.occupations)do
   data.occupations[#data.occupations+1]={id=role.id,type=role.type,location_id=role.location_id,site_id=role.site_id,unit_id=role.unit_id}
  end
  for y=19,g.dimy-1 do local text=dfhack.df2utf(row(y)):gsub('%s+$','');if text~=''then data.lines[#data.lines+1]={y=y,text=text}end end
  result.location_fixture=data;capture('unit-labor-location-assigned')
 end,debug.traceback)
 sheet.active_id=original;view:render(dfhack.getTickCount());assert(ok,err)
end
select('Overview',15,16)
assert(df.global.pause_state and df.global.world.frame_counter==frame,'Labor capture advanced simulation')
local file=assert(io.open(out..'/unit-labor-native.json','w'));file:write(json.encode(result));file:close()
return result
