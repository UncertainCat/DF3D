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
select('Overview',15,16)
assert(df.global.pause_state and df.global.world.frame_counter==frame,'Labor capture advanced simulation')
local file=assert(io.open(out..'/unit-labor-native.json','w'));file:write(json.encode(result));file:close()
return result
