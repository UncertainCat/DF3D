-- Read-only completed machinery discovery in the owned paused clone.
local out,view,select_map,capture=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local sheet=df.global.game.main_interface.view_sheets
local result={buildings={},inventory={},frame=df.global.world.frame_counter}
local selected={};local fixtures={}
for _,b in ipairs(df.global.world.buildings.all)do
 local info=b:getMachineInfo()
 if info then
  local tile=dfhack.maps.getTileFlags(b.centerx,b.centery,b.z)
  local complete=b:getBuildStage()==b:getMaxBuildStage()
  result.inventory[#result.inventory+1]={id=b.id,type=b:getType(),complete=complete,revealed=tile and not tile.hidden or false}
  if complete and tile and not tile.hidden and not selected[b:getType()]then selected[b:getType()]=b end
 end
end
if os.getenv('DF3D_MACHINERY_FIXTURES')=='1'then
 for _,name in ipairs{'GearAssembly','AxleHorizontal','AxleVertical','Rollers','ScrewPump','Windmill'}do
  local kind=assert(df.building_type[name])
  if not selected[kind]then
   local placed
   for y=80,140,4 do for x=80,160,4 do
    local pos={x=x,y=y,z=165};local tile=dfhack.maps.getTileFlags(pos)
    local clear=true
    for yy=y,y+2 do for xx=x,x+2 do
     local d,o=dfhack.maps.getTileFlags(xx,yy,pos.z)
     if not d or d.hidden or not o or o.item or o.unit or o.unit_grounded or dfhack.buildings.findAtTile{x=xx,y=yy,z=pos.z}then clear=false end
    end end
    if clear and tile and not tile.hidden and not dfhack.buildings.findAtTile(pos)then
     local ok,b=pcall(dfhack.buildings.constructBuilding,{type=kind,pos=pos,direction=0,full_rectangle=true})
     if ok and b then placed=b;break end
    end
   end;if placed then break end end
   assert(placed,'No machinery fixture site for '..name)
   while #placed.jobs>0 do assert(dfhack.job.removeJob(placed.jobs[0]))end
   placed:setBuildStage(placed:getMaxBuildStage())
   selected[kind]=placed;fixtures[#fixtures+1]=placed
  end
 end
end
local kinds={};for kind in pairs(selected)do kinds[#kinds+1]=kind end;table.sort(kinds)
for _,kind in ipairs(kinds)do
 local b=selected[kind];local info=b:getMachineInfo();local machine=df.machine.find(info.machine_id)
 local power=df.power_info:new();b:getPowerInfo(power)
 local row={id=b.id,type=kind,name=dfhack.df2utf(b.name),tile={b.centerx,b.centery,b.z},machine_id=info.machine_id,machine_flags=info.flags.whole,power={},lines={}}
 for _,fixture in ipairs(fixtures)do if fixture==b then row.fixture='DFHack construction completed by diagnostic; no construction simulation, contents or network.' end end
 for key,value in pairs(power)do if type(value)=='number' or type(value)=='boolean'then row.power[key]=value end end
 power:delete()
 if machine then row.network={produced=machine.cur_power,required=machine.min_power,flags=machine.flags.whole}end
 if sheet.open then gui.simulateInput(view,'LEAVESCREEN')end
 view:render(dfhack.getTickCount());select_map(b)
 assert(sheet.open and sheet.active_sheet==df.view_sheet_type.BUILDING and sheet.active_id==b.id,'Machinery selection missed type '..kind..' id '..b.id..'; selected '..tostring(sheet.active_sheet)..' '..sheet.active_id)
 for y=4,g.dimy-1 do
  local chars={};for x=52,112 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
  local text=dfhack.df2utf(table.concat(chars)):gsub('%s+$','');if text:find('%S')then row.lines[#row.lines+1]={y=y,text=text}end
 end
 capture('machinery-sheet-'..kind);result.buildings[#result.buildings+1]=row
 if kind==df.building_type.ScrewPump and os.getenv('DF3D_MACHINERY_ACTIONS')=='1'then
  local initial=b.pump_manually;local jobs=#b.jobs
  -- Without a network, native puts the 3x3 checkbox immediately below foundation.
  assert(not machine)
  for step=1,2 do
   g.precise_mouse_x=444;g.precise_mouse_y=166;g.mouse_x=55;g.mouse_y=13
   df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
   gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
   df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
   local expected=initial;if step==1 then expected=not initial end
   assert(b.pump_manually==expected and #b.jobs==jobs)
   capture('machinery-pump-manual-'..step)
  end
  row.manual_toggle={initial=initial,restored=b.pump_manually,jobs=jobs,frame_unchanged=df.global.world.frame_counter==result.frame}
 end
end
if sheet.open then gui.simulateInput(view,'LEAVESCREEN')end
for _,b in ipairs(fixtures)do b:setBuildStage(0);assert(dfhack.buildings.deconstruct(b))end
assert(df.global.world.frame_counter==result.frame)
result.success=true
local f=assert(io.open(out..'/machinery-sheets-native.json','w'));f:write(json.encode(result));f:close()
return result
