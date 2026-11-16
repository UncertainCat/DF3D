-- Native inventory/captures for completed building types still outside public routes.
local out,view,select_map,capture=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local sheet=df.global.game.main_interface.view_sheets
local kinds={6,7,16,17,18,19,20,21,22,24,25,26,27,28,31,32,45,47,48,49,53}
if os.getenv("DF3D_SIMPLE_BUILDING_SCENE")=="1" then kinds={19,32,45}end
if os.getenv("DF3D_DEPOT_NATIVE")=="1" then kinds={6}end
if os.getenv("DF3D_CAGE_NATIVE")=="1" then kinds={28}end
local wanted={};for _,kind in ipairs(kinds)do wanted[kind]=true end
local result={frame=df.global.world.frame_counter,inventory={},buildings={},missing={}}
local selected={}
for _,b in ipairs(df.global.world.buildings.all)do
 local kind=b:getType()
 if wanted[kind]then
  local d=dfhack.maps.getTileFlags(b.centerx,b.centery,b.z)
  local complete=b:getBuildStage()==b:getMaxBuildStage()
  result.inventory[#result.inventory+1]={id=b.id,type=kind,subtype=b:getSubtype(),complete=complete,revealed=d and not d.hidden or false}
  if complete and d and not d.hidden and not selected[kind]then selected[kind]=b end
 end
end
for _,kind in ipairs(kinds)do
 local b=selected[kind]
 if b then
  if sheet.open then gui.simulateInput(view,'LEAVESCREEN')end
  view:render(dfhack.getTickCount());select_map(b)
  local row={id=b.id,type=kind,subtype=b:getSubtype(),tile={b.centerx,b.centery,b.z},native_type=df.building_type[kind],custom_name=dfhack.df2utf(b.name),selected_sheet=sheet.active_sheet,selected_id=sheet.active_id,lines={}}
  capture('remaining-building-'..kind)
  if kind==28 and os.getenv('DF3D_CAGE_NATIVE')=='1' then
   local function ids(v)local t={};for _,id in ipairs(v)do t[#t+1]=id end;return t end
   local before={units=ids(b.assigned_units),items=ids(b.assigned_items),flags=b.cage_flags.whole,jobs=#b.jobs}
   g.precise_mouse_x=448;g.precise_mouse_y=406;g.mouse_x=56;g.mouse_y=33
   df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
   gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
   df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
   local picker=df.global.game.main_interface.unit_selector
   capture('cage-assignment-click')
   -- Native 3a5940 captures the cage pointer in widget callbacks; bld_id stays -1.
   assert(picker.context==df.unit_selector_context_type.CAGE_ASSIGNMENT and sheet.active_id==b.id,'Cage picker or parent selection did not open')
   capture('cage-assignment-open')
   result.cage_picker={context=picker.context,building_id=b.id,legacy_selector_building_id=picker.bld_id,before=before}
   if os.getenv('DF3D_CAGE_CANDIDATES')=='1'then
    local source=debug.getinfo(1,'S').source:sub(2):gsub('remaining%-buildings%-native.lua$','cage-candidates-native.lua')
    result.cage_picker.candidates=assert(loadfile(source))(view,b)
   end
   gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());capture('cage-assignment-closed')
   if os.getenv('DF3D_CAGE_WIRE')=='1'then
    local f=assert(io.open(out..'/cage-wire-expected.json','w'));f:write(json.encode({id=b.id,rows=result.cage_picker.candidates.owned}));f:close()
    local active=sheet.active_id;capture('cage-wire')
    f=assert(io.open(out..'/cage-wire-result.json'));result.cage_picker.wire=json.decode(f:read('*a'));f:close()
    assert(result.cage_picker.wire.success and sheet.active_id==active,'Cage wire failed or changed native selection')
   end
   result.cage_picker.after={units=ids(b.assigned_units),items=ids(b.assigned_items),flags=b.cage_flags.whole,jobs=#b.jobs}
   assert(json.encode(before)==json.encode(result.cage_picker.after),'Opening/cancelling cage assignment changed simulation')
   result.cage_picker.closed_context=picker.context
   if os.getenv('DF3D_CAGE_BODY')=='1'then
    local source=debug.getinfo(1,'S').source:sub(2):gsub('remaining%-buildings%-native.lua$','cage-body-native.lua')
    assert(loadfile(source))(out,view,b,capture)
    if os.getenv('DF3D_CAGE_OCCUPANT_EFFECTS')=='1'then
     source=source:gsub('cage%-body%-native.lua$','cage-occupant-effects-native.lua')
     assert(loadfile(source))(out,view,b,capture)
    end
   end
   if os.getenv('DF3D_CAGE_GLASS')=='1'then
    local source=debug.getinfo(1,'S').source:sub(2):gsub('remaining%-buildings%-native.lua$','cage-glass-native.lua')
    assert(loadfile(source))(out,view,b,capture)
   end
   select_map(b);view:render(dfhack.getTickCount())
  end
  if kind==6 and os.getenv('DF3D_DEPOT_NATIVE')=='1' then
   local source=debug.getinfo(1,'S').source:sub(2):gsub('remaining%-buildings%-native.lua$','depot-settings-native.lua')
   result.depot_settings=assert(loadfile(source))(out,view,b,capture,select_map)
  end
  for y=4,g.dimy-1 do
   local chars={};for x=52,112 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
   local text=dfhack.df2utf(table.concat(chars)):gsub('%s+$','');if text:find('%S')then row.lines[#row.lines+1]={y=y,text=text}end
  end
  if kind==28 and os.getenv('DF3D_CAGE_NATIVE')=='1' then
   local text,code=dfhack.run_command_silent('df3d','cage-room-read',tostring(b.id))
   assert(code==0,text);row.room_body=json.decode(text)
   local screen={};for _,line in ipairs(row.lines)do screen[#screen+1]=line.text end
   screen=table.concat(screen,'\n')
   local body=row.room_body
   assert(body.building_id==b.id)
   if body.room_id>=0 then
    assert(screen:find(body.introduction,1,true) and screen:find(body.name,1,true),'Cage room copy differs from native')
    local found=false;for _,zone in ipairs(b.relations)do if zone.id==body.room_id then found=true;assert(zone.type==body.room_type)end end
    assert(found,'Cage room absent from semantic relations')
   end
   for _,notice in ipairs(body.notices)do assert(screen:find(notice,1,true),'Cage room notice differs from native')end
  end
  if kind==18 and os.getenv('DF3D_WELL_PROVIDER')=='1' then
   local source=debug.getinfo(1,'S').source:sub(2):gsub('remaining%-buildings%-native.lua$','well-status-native.lua')
   result.well_status=assert(loadfile(source))(out,view,b,capture)
  end
  if os.getenv('DF3D_SIMPLE_BUILDING_SCENE')=='1' then
   local original=b.name;assert(#b.jobs==0)
   local function click(x,y)
    g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
    df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
    gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
    df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
   end
   local function shot(label)capture('remaining-building-'..kind..'-'..label)end
   click(800,82);gui.simulateInput(view,'STRING_A120');gui.simulateInput(view,'SELECT');assert(b.name==original..'x');shot('renamed')
   click(800,82);gui.simulateInput(view,'STRING_A000');gui.simulateInput(view,'SELECT');assert(b.name==original);shot('restored')
   click(832,82);assert(#b.jobs==1 and b.jobs[0].job_type==df.job_type.DestroyBuilding);shot('removing')
   click(520,202);assert(#b.jobs==0);shot('cancelled')
  end
  result.buildings[#result.buildings+1]=row
 else result.missing[#result.missing+1]=kind end
end
if os.getenv('DF3D_SIMPLE_BUILDING_SCENE')=='1' then
 local f=assert(io.open(out..'/simple-building-expected.json','w'));f:write(json.encode(result));f:close()
 local active=sheet.active_id;capture('simple-building-wire')
 f=assert(io.open(out..'/simple-building-wire-result.json'));result.viewer=json.decode(f:read('*a'));f:close()
 assert(result.viewer.success and sheet.active_id==active)
 for _,row in ipairs(result.buildings)do local b=assert(df.building.find(row.id));assert(#b.jobs==0 and dfhack.df2utf(b.name)==row.custom_name)end
end
if sheet.open then gui.simulateInput(view,'LEAVESCREEN')end
assert(df.global.world.frame_counter==result.frame)
result.success=true
local f=assert(io.open(out..'/remaining-buildings-native.json','w'));f:write(json.encode(result));f:close()
return result
