-- Read-only completed machinery discovery in the owned paused clone.
local out,view,select_map,capture=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local sheet=df.global.game.main_interface.view_sheets
local result={buildings={},inventory={},frame=df.global.world.frame_counter}
local selected={};local fixtures={}
local function click(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
end
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
   placed.flags.exists=true -- Match the completed entity state used by normal map routing.
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
 local function read_semantics()
  local text,code=dfhack.run_command_silent('df3d','machinery-body-probe',tostring(b.id));assert(code==0,text)
  return json.decode(text)
 end
 if kind~=df.building_type.Workshop and os.getenv('DF3D_MACHINERY_PROVIDER')=='1'then
  row.semantic=read_semantics();local s=row.semantic
  assert(s.machine_id==(machine and machine.id or -1))
  assert(s.produced==(machine and machine.cur_power or 0) and s.required==(machine and machine.min_power or 0))
  local labels={[1]='Active',[2]='Inactive',[3]='Frozen Here',[4]='Frozen Elsewhere'}
  local found_foundation,found_status=false,s.status==0
  for _,line in ipairs(row.lines)do
   local text=line.text:match('^%s*(.-)%s*$')
   if text==(s.stable_foundation and 'Stable Foundation' or 'Hanging')then found_foundation=true end
   if text==labels[s.status]then found_status=true end
  end
  assert(found_foundation and found_status,'Native machinery body differs from owned semantic inputs')
  assert(sheet.open and sheet.active_sheet==df.view_sheet_type.BUILDING and sheet.active_id==b.id)
 end
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
   if os.getenv('DF3D_MACHINERY_PROVIDER')=='1'then assert(read_semantics().pump_manual==(expected and 1 or 0))end
   capture('machinery-pump-manual-'..step)
  end
  row.manual_toggle={initial=initial,restored=b.pump_manually,jobs=jobs,frame_unchanged=df.global.world.frame_counter==result.frame}
 end
 if kind~=df.building_type.Workshop and os.getenv('DF3D_MACHINERY_WORKFLOW')=='1'then
  local name=b.name;assert(#b.jobs==0)
  local function shot(label)view:render(dfhack.getTickCount());capture('machinery-sheet-'..kind..'-'..label)end
  click(800,82);gui.simulateInput(view,'STRING_A120');gui.simulateInput(view,'SELECT');assert(b.name==name..'x');shot('renamed')
  click(800,82);gui.simulateInput(view,'STRING_A000');gui.simulateInput(view,'SELECT');assert(b.name==name);shot('restored')
  click(832,82);assert(#b.jobs==1 and b.jobs[0].job_type==df.job_type.DestroyBuilding);shot('removing')
  click(520,202);assert(#b.jobs==0);shot('removal-cancelled')
 end
end
if os.getenv('DF3D_MACHINERY_SCENE')=='1'then
 local f=assert(io.open(out..'/machinery-wire-expected.json','w'));f:write(json.encode(result));f:close()
 local active_id=sheet.active_id
 capture('machinery-scene')
 f=assert(io.open(out..'/machinery-scene-result.json'));result.scene=json.decode(f:read('*a'));f:close()
 assert(result.scene.success and sheet.active_id==active_id)
 for _,b in ipairs(fixtures)do if b:getType()==df.building_type.ScrewPump then assert(not b.pump_manually and #b.jobs==0)end end
end
if os.getenv('DF3D_MACHINERY_WIRE')=='1'then
 local f=assert(io.open(out..'/machinery-wire-expected.json','w'));f:write(json.encode(result));f:close()
 local active_id=sheet.active_id
 capture('machinery-wire')
 f=assert(io.open(out..'/machinery-wire-result.json'));result.wire=json.decode(f:read('*a'));f:close()
 assert(result.wire.success and sheet.active_id==active_id)
 for _,b in ipairs(fixtures)do if b:getType()==df.building_type.ScrewPump then assert(not b.pump_manually and #b.jobs==0)end end
end
if os.getenv('DF3D_MACHINERY_VARIANTS')=='1'then
 local source=debug.getinfo(1,'S').source:sub(2):gsub('machinery%-sheets%-native.lua$','machinery-variants-native.lua')
 result.variants=assert(loadfile(source))(out,view,select_map,capture,selected)
end
if sheet.open then gui.simulateInput(view,'LEAVESCREEN')end
for _,b in ipairs(fixtures)do b:setBuildStage(0);b.flags.exists=false;assert(dfhack.buildings.deconstruct(b))end
if os.getenv('DF3D_MACHINERY_CONTRACT')=='1'then
 local lever=assert(df.building.find(61));local name=lever.name;local jobs=#lever.jobs
 capture('machinery-contract-wire')
 local f=assert(io.open(out..'/machinery-contract-wire-result.json'));result.contract=json.decode(f:read('*a'));f:close()
 assert(result.contract.success and lever.name==name and #lever.jobs==jobs)
end
assert(df.global.world.frame_counter==result.frame)
result.success=true
local f=assert(io.open(out..'/machinery-sheets-native.json','w'));f:write(json.encode(result));f:close()
return result
