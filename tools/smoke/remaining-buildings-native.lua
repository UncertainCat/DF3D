-- Native inventory/captures for completed building types still outside public routes.
local out,view,select_map,capture=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local sheet=df.global.game.main_interface.view_sheets
local kinds={6,7,16,17,18,19,20,21,22,24,25,26,27,28,31,32,45,47,48,49,53}
if os.getenv("DF3D_SIMPLE_BUILDING_SCENE")=="1" then kinds={19,32,45}end
if os.getenv("DF3D_DEPOT_NATIVE")=="1" then kinds={6}end
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
  if kind==6 and os.getenv('DF3D_DEPOT_NATIVE')=='1' then
   local source=debug.getinfo(1,'S').source:sub(2):gsub('remaining%-buildings%-native.lua$','depot-settings-native.lua')
   result.depot_settings=assert(loadfile(source))(out,view,b,capture,select_map)
  end
  for y=4,g.dimy-1 do
   local chars={};for x=52,112 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
   local text=dfhack.df2utf(table.concat(chars)):gsub('%s+$','');if text:find('%S')then row.lines[#row.lines+1]={y=y,text=text}end
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
