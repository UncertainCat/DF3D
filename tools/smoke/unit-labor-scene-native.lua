-- Observe real semantic edits independently in the owned paused clone.
local unit,capture,out=...
local json=require('json');local observations={}
local frame=df.global.world.frame_counter
local exemption,old_exemption,cache_before
local function caches()
 local values={unit.enemy.histfig_vector_idx}
 local hf=df.historical_figure.find(unit.hist_figure_id)
 for _,link in ipairs(hf.entity_links)do
  values[#values+1]=link.entity_vector_idx
  if link:getType()==df.histfig_entity_link_type.POSITION then
   values[#values+1]=link.assignment_vector_idx
   local entity=df.historical_entity.find(link.entity_id)
   if entity then for _,assignment in ipairs(entity.positions.assignments)do values[#values+1]=assignment.position_vector_idx end end
  end
 end
 return values
end
local function exemption_probe(enabled)
 if not exemption then
  local roles=dfhack.units.getNoblePositions(unit)
  for _,role in ipairs(roles)do if role.entity.id==df.global.plotinfo.group_id then exemption=role.position;break end end
  assert(exemption,'Eligibility fixture requires a local office')
  old_exemption=exemption.flags.MENIAL_WORK_EXEMPTION;assert(not old_exemption,'Baseline already exempt')
 end
 if not enabled then assert(json.encode(caches())==json.encode(cache_before),'Eligibility query altered native lookup caches')end
 exemption.flags.MENIAL_WORK_EXEMPTION=enabled
 local gui=require('gui');local view=dfhack.gui.getDFViewscreen();local g=df.global.gps
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
 for y=15,16 do local x=row(y):find('Labor',1,true);if x then click((x-1)*8+4,y*12+10);break end end
 view:render(dfhack.getTickCount())
 local scope=row(20);assert((scope:find('Will ',1,true)~=nil)==not enabled,'Native scope eligibility disagrees')
 if enabled then
  local before=unit.flags4.only_do_assigned_jobs;click(448,250)
  assert(unit.flags4.only_do_assigned_jobs==before,'Native exempt unit accepted scope edit')
 end
 for y=15,16 do local x=row(y):find('Overview',1,true);if x then click((x-1)*8+4,y*12+10);break end end
 cache_before=caches()
 return scope
end
local function snapshot()
 local state={details={},labors={},only_assigned=unit.flags4.only_do_assigned_jobs}
 for _,detail in ipairs(df.global.plotinfo.labor_info.work_details)do
  local assigned={};for _,id in ipairs(detail.assigned_units)do assigned[#assigned+1]=id end
  state.details[#state.details+1]={name=detail.name,flags=detail.flags.whole,assigned=assigned}
 end
 for i=0,93 do state.labors[#state.labors+1]=unit.status.labors[i]end
 return state
end
local file=assert(io.open(out..'/unit-labor-native.json'));local native=json.decode(file:read('*a'));file:close()
local workshop_profile,workshop_workers
local function workshop_fixture(enabled)
 if not workshop_profile then
  local building=assert(df.building.find(native.workshop_fixture.building_id))
  workshop_profile=assert(building:getWorkshopProfile());workshop_workers={}
  for _,id in ipairs(workshop_profile.permitted_workers)do workshop_workers[#workshop_workers+1]=id end
 end
 local ids={};for _,id in ipairs(workshop_workers)do ids[#ids+1]=id end
 if enabled then
  for _,id in ipairs(ids)do assert(id~=unit.id,'Workshop fixture already assigned')end
  ids[#ids+1]=unit.id;table.sort(ids)
 end
 workshop_profile.permitted_workers:resize(0);for _,id in ipairs(ids)do workshop_profile.permitted_workers:insert('#',id)end
end
local function service()
 local f=io.open(out..'/unit-labor-request.json');if not f then return end
 local request=json.decode(f:read('*a'));f:close();assert(os.remove(out..'/unit-labor-request.json'))
 assert(request.unit_id==unit.id and request.serial==#observations+1,'Invalid labor observation')
 assert(df.global.pause_state and df.global.world.frame_counter==frame,'Labor scene advanced simulation')
 if request.stage=='workshop_on' or request.stage=='workshop_off' then
  if request.stage=='workshop_off' then
   local workers={};for _,id in ipairs(workshop_profile.permitted_workers)do workers[#workers+1]=id end
   assert(json.encode(workers)==json.encode(native.workshop_fixture.remove.remaining_workers),'Workshop remove differs from native')
   assert(json.encode(snapshot())==json.encode(native.actions.before),'Workshop remove changed labor assignments')
  end
  workshop_fixture(request.stage=='workshop_on');observations[#observations+1]={stage=request.stage}
 elseif request.stage=='eligibility_on' or request.stage=='eligibility_off' then
  observations[#observations+1]={stage=request.stage,native_scope=exemption_probe(request.stage=='eligibility_on')}
 else
  local state=snapshot();local expected=native.actions[request.stage]
  assert(expected and json.encode(state)==json.encode(expected),'Semantic labor effects differ from native: '..request.stage)
  observations[#observations+1]={stage=request.stage,state=state}
 end
 f=assert(io.open(out..'/unit-labor-ack.tmp','w'));f:write(json.encode({serial=request.serial}));f:close()
 assert(os.rename(out..'/unit-labor-ack.tmp',out..'/unit-labor-ack.json'))
end
local ok,err=xpcall(function()capture('farm-item-carrier-unit-scene',service)end,debug.traceback)
if exemption then exemption.flags.MENIAL_WORK_EXEMPTION=old_exemption end
if workshop_profile then workshop_fixture(false)end
assert(ok,err)
local count=os.getenv('DF3D_UNIT_LABOR_WORKSHOP_WIRE')=='1' and 9 or os.getenv('DF3D_UNIT_LABOR_ELIGIBILITY')=='1' and 7 or 5
assert(#observations==count and json.encode(snapshot())==json.encode(native.actions.before),'Labor scene did not restore baseline')
local result={success=true,observations=observations,restored=true}
file=assert(io.open(out..'/unit-labor-scene-native.json','w'));file:write(json.encode(result));file:close()
return result
