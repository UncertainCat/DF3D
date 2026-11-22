-- Native inventory/captures for completed building types still outside public routes.
local out,view,select_map,capture=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local sheet=df.global.game.main_interface.view_sheets
local kinds={6,7,16,17,18,19,20,21,22,24,25,26,27,28,31,32,45,47,48,49,53}
if os.getenv("DF3D_SIMPLE_BUILDING_SCENE")=="1" then kinds={19,32,45}end
local default_families=os.getenv('DF3D_DEFAULT_BUILDINGS_NATIVE')=='1'
if default_families then kinds={16,17,20,21,25,31};if os.getenv('DF3D_ARCHERY_TARGET_SCENE')=='1' then kinds={26}end end
local legacy_families=os.getenv('DF3D_LEGACY_BUILDINGS_NATIVE')=='1'
if legacy_families then default_families=true;kinds={7,47}end
local specialized_families=os.getenv('DF3D_SPECIAL_BUILDINGS_NATIVE')=='1'
if specialized_families then kinds={22,24,26,27,48,49,53}end
if os.getenv("DF3D_DEPOT_NATIVE")=="1" then kinds={6}end
if os.getenv("DF3D_CAGE_NATIVE")=="1" then kinds={28}end
if os.getenv('DF3D_CHAIN_NATIVE')=='1' then kinds={27}end
if os.getenv('DF3D_SIEGE_NATIVE')=='1' then kinds={22}end
if os.getenv('DF3D_DISPLAY_NATIVE')=='1' then kinds={53}end
local wanted={};for _,kind in ipairs(kinds)do wanted[kind]=true end
local result={frame=df.global.world.frame_counter,inventory={},buildings={},missing={}}
local selected={}
local scene_claim=nil
for _,b in ipairs(df.global.world.buildings.all)do
 local kind=b:getType()
 if wanted[kind]then
  local d=dfhack.maps.getTileFlags(b.centerx,b.centery,b.z)
  local complete=b:getBuildStage()==b:getMaxBuildStage()
  result.inventory[#result.inventory+1]={id=b.id,type=kind,subtype=b:getSubtype(),complete=complete,revealed=d and not d.hidden or false}
  if complete and d and not d.hidden and not selected[kind]then selected[kind]=b end
 end
end
local fixtures={};local fixture_items={};local fixture_ids={}
local ok,err=xpcall(function()
if default_families or specialized_families then
 for _,kind in ipairs(kinds)do
  if not selected[kind]then
   local b,last_error
   for y=80,140,4 do for x=80,160,4 do
    local pos={x=x,y=y,z=165};local clear=true;local extent=kind==7 and 4 or kind==22 and 2 or 0
    for dy=0,extent do for dx=0,extent do
     local tile={x=x+dx,y=y+dy,z=165};local d,o=dfhack.maps.getTileFlags(tile)
     if not d or d.hidden or not o or o.item or o.unit or o.unit_grounded or dfhack.buildings.findAtTile(tile)then clear=false end
    end end
    if clear then
     -- DFHack has no default Shop/Nest recipe. Explicit block filters
     -- create only a disposable selection oracle, not a product build route.
     local success,placed,reason=pcall(dfhack.buildings.constructBuilding,{type=kind,subtype=(kind==7 or kind==22) and 0 or -1,pos=pos,full_rectangle=true,filters=legacy_families and {{item_type=df.item_type.BLOCKS,quantity=1}} or nil})
     if success and placed then b=placed;break end
     last_error=success and reason or placed
    end
   end;if b then break end end
   assert(b,'No fixture site for '..df.building_type[kind]..': '..tostring(last_error))
   fixtures[#fixtures+1]=b
   fixture_ids[b.id]=true
   while #b.jobs>0 do assert(dfhack.job.removeJob(b.jobs[0]))end
   b:setBuildStage(b:getMaxBuildStage());b.flags.exists=true;b:updateOccupancy(b.centerx,b.centery)
   local token=kind==16 and 'GLASS_GREEN' or kind==17 and 'INORGANIC:RUBY' or kind==22 and 'PLANT:OAK:WOOD' or (kind==24 or kind==27 or kind==31) and 'INORGANIC:IRON' or 'INORGANIC:GRANITE'
   local material=assert(dfhack.matinfo.find(token));b.mat_type=material.type;b.mat_index=material.index
   if kind~=20 and kind~=7 and kind~=47 then
    local worker
    for _,u in ipairs(df.global.world.units.active)do if dfhack.units.isCitizen(u)then worker=u;break end end
    local item_type=kind==16 and df.item_type.WINDOW or kind==17 and df.item_type.SMALLGEM or kind==22 and df.item_type.CATAPULTPARTS or kind==24 and df.item_type.ANIMALTRAP or kind==27 and df.item_type.CHAIN or kind==31 and df.item_type.TRAPCOMP or (kind==48 or kind==49 or kind==53) and df.item_type.TOOL or df.item_type.BLOCKS
    local subtype=-1
    if kind==31 then
     for i,raw in ipairs(df.global.world.raws.itemdefs.trapcomps)do if raw.id=='ITEM_TRAPCOMP_MENACINGSPIKE'then subtype=i;break end end
     assert(subtype>=0,'Missing spike definition')
    end
    if item_type==df.item_type.TOOL then
     local raw_id=kind==48 and 'ITEM_TOOL_NEST_BOX' or kind==49 and 'ITEM_TOOL_HIVE' or 'ITEM_TOOL_PEDESTAL'
     for i,raw in ipairs(df.global.world.raws.itemdefs.tools)do if raw.id==raw_id then subtype=i;break end end
     assert(subtype>=0,'Missing tool definition '..raw_id)
    end
    for index=1,kind==22 and 3 or 1 do
     local items=dfhack.items.createItem(assert(worker),item_type,subtype,material.type,material.index)
     assert(#items==1);fixture_items[#fixture_items+1]=items[1]
     assert(dfhack.items.moveToBuilding(items[1],b,2,true))
    end
   end
   selected[kind]=b
  end
 end
end
for _,kind in ipairs(kinds)do
 local b=selected[kind]
 if b then
  if sheet.open then gui.simulateInput(view,'LEAVESCREEN')end
  if kind==48 and os.getenv('DF3D_SPECIAL_BUILDINGS_SCENE')=='1' then scene_claim={building=b,claimed_by=b.claimed_by};b.claimed_by=6960 end
  view:render(dfhack.getTickCount());select_map(b)
  assert(sheet.open and sheet.active_sheet==df.view_sheet_type.BUILDING and sheet.active_id==b.id,'Native building selection missed '..kind)
  local row={id=b.id,type=kind,subtype=b:getSubtype(),tile={b.centerx,b.centery,b.z},native_type=df.building_type[kind],custom_name=dfhack.df2utf(b.name),selected_sheet=sheet.active_sheet,selected_id=sheet.active_id,lines={}}
  row.temporary_fixture=fixture_ids[b.id] or false
  capture('remaining-building-'..kind)
  if kind==53 and os.getenv('DF3D_DISPLAY_NATIVE')=='1' then
   local source=debug.getinfo(1,'S').source:sub(2):gsub('remaining%-buildings%-native.lua$','display-building-native.lua')
   result.display=assert(loadfile(source))(out,view,b,capture,select_map)
  end
  if specialized_families then
   row.items={}
   for _,held in ipairs(b.contained_items)do row.items[#row.items+1]={id=held.item.id,type=held.item:getType(),use_mode=held.use_mode}end
  end
  if kind==22 and os.getenv('DF3D_SIEGE_NATIVE')=='1' then
   local source=debug.getinfo(1,'S').source:sub(2):gsub('remaining%-buildings%-native.lua$','siege-building-native.lua')
   result.siege=assert(loadfile(source))(out,view,b,select_map,capture)
   select_map(b);view:render(dfhack.getTickCount())
  end
  if kind==27 and os.getenv('DF3D_CHAIN_NATIVE')=='1' then
   local source=debug.getinfo(1,'S').source:sub(2):gsub('remaining%-buildings%-native.lua$','chain-native.lua')
   result.chain=assert(loadfile(source))(out,view,b,capture)
  end
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
    local body,code=dfhack.run_command_silent('df3d','cage-occupants-read',tostring(b.id));assert(code==0,body)
    local f=assert(io.open(out..'/cage-wire-expected.json','w'));f:write(json.encode({id=b.id,rows=result.cage_picker.candidates.owned,occupants=json.decode(body)}));f:close()
    local active=sheet.active_id;capture('cage-wire')
    f=assert(io.open(out..'/cage-wire-result.json'));result.cage_picker.wire=json.decode(f:read('*a'));f:close()
    assert(result.cage_picker.wire.success and sheet.active_id==active,'Cage wire failed or changed native selection')
    result.cage_picker.parent_effect_flags=b.cage_flags.whole
    assert(b.cage_flags.whole==(before.flags|4),'Parent wire removal did not set CHECKOCCUPANTS')
    b.cage_flags.whole=before.flags
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
   if os.getenv('DF3D_CAGE_SCENE')=='1'then
    local f=assert(io.open(out..'/cage-scene-expected.json','w'));f:write(json.encode(row));f:close()
    capture('cage-scene')
    f=assert(io.open(out..'/cage-scene-result.json'));result.cage_scene=json.decode(f:read('*a'));f:close()
    assert(result.cage_scene.success,'Cage main scene failed')
    assert(b.cage_flags.whole==(before.flags|4),'Cage scene removal flag differs')
    b.cage_flags.whole=before.flags
    assert(json.encode(before.units)==json.encode(ids(b.assigned_units)) and json.encode(before.items)==json.encode(ids(b.assigned_items)))
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
  if specialized_families and os.getenv('DF3D_SPECIAL_BUILDINGS_CONTROLS')=='1' and (kind==24 or kind==48 or kind==49)then
   local source=debug.getinfo(1,'S').source:sub(2):gsub('remaining%-buildings%-native.lua$','special-building-controls-native.lua')
   row.controls=assert(loadfile(source))(out,view,b,capture)
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
  if (kind==27 and os.getenv('DF3D_CHAIN_SCENE')=='1') or os.getenv('DF3D_SIMPLE_BUILDING_SCENE')=='1' or default_families or (os.getenv('DF3D_SPECIAL_BUILDINGS_SCENE')=='1' and (kind==24 or kind==48 or kind==49))then
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
  if kind==27 and os.getenv('DF3D_CHAIN_SCENE')=='1' then
   row.unit_id=result.chain.selection.unit_id
   local f=assert(io.open(out..'/chain-scene-expected.json','w'));f:write(json.encode(row));f:close()
   capture('chain-scene')
   f=assert(io.open(out..'/chain-scene-result.json'));result.chain_scene=json.decode(f:read('*a'));f:close()
   assert(result.chain_scene.success and not b.assigned and not b.chained and #b.jobs==0 and dfhack.df2utf(b.name)==row.custom_name)
  end
  result.buildings[#result.buildings+1]=row
 else result.missing[#result.missing+1]=kind end
end
if os.getenv('DF3D_SPECIAL_BUILDINGS_WIRE')=='1' or os.getenv('DF3D_SPECIAL_BUILDINGS_SCENE')=='1' then
 local expected={buildings={}};local nest,claim
 for _,row in ipairs(result.buildings)do
  if row.type==24 or row.type==48 or row.type==49 then
   local b=assert(df.building.find(row.id))
   if row.type==48 then nest=b;claim=b.claimed_by;b.claimed_by=6960 end
   local text,code=dfhack.run_command_silent('df3d','special-building-read',tostring(b.id));assert(code==0,text)
   expected.buildings[#expected.buildings+1]={id=b.id,type=row.type,tile=row.tile,custom_name=row.custom_name,body=json.decode(text)}
  end
 end
 local f=assert(io.open(out..'/special-building-expected.json','w'));f:write(json.encode(expected));f:close()
 local active=sheet.active_id;capture('special-building-wire')
 f=assert(io.open(out..'/special-building-wire-result.json'));result.viewer=json.decode(f:read('*a'));f:close()
 assert(result.viewer.success and sheet.active_id==active)
 for _,row in ipairs(expected.buildings)do
  local b=assert(df.building.find(row.id));assert(#b.jobs==0)
  if row.type==24 then assert(b.bait_type==row.body.bait_type)end
  if row.type==49 then assert(b.hive_flags.whole==row.body.flags)end
 end
 if nest then nest.claimed_by=claim end
end
if os.getenv('DF3D_SIMPLE_BUILDING_SCENE')=='1' or os.getenv('DF3D_DEFAULT_BUILDINGS_SCENE')=='1' then
 local f=assert(io.open(out..'/simple-building-expected.json','w'));f:write(json.encode(result));f:close()
 local active=sheet.active_id;capture('simple-building-wire')
 f=assert(io.open(out..'/simple-building-wire-result.json'));result.viewer=json.decode(f:read('*a'));f:close()
 assert(result.viewer.success and sheet.active_id==active)
 for _,row in ipairs(result.buildings)do local b=assert(df.building.find(row.id));assert(#b.jobs==0 and dfhack.df2utf(b.name)==row.custom_name)end
end
end,debug.traceback)
if scene_claim then scene_claim.building.claimed_by=scene_claim.claimed_by end
if sheet.open then gui.simulateInput(view,'LEAVESCREEN')end
for _,item in ipairs(fixture_items)do item.flags.in_building=false;assert(dfhack.items.remove(item))end
for _,b in ipairs(fixtures)do b:setBuildStage(0);b.flags.exists=false;assert(dfhack.buildings.deconstruct(b))end
assert(ok,err)
if os.getenv('DF3D_DISPLAY_HAUL')=='1' then
 assert(result.display.success and result.display.delivered and result.display.start_tick==result.frame and result.display.end_tick==df.global.world.frame_counter and df.global.pause_state,'Missing bounded display hauling evidence')
else assert(df.global.world.frame_counter==result.frame)end
result.success=true
local f=assert(io.open(out..'/remaining-buildings-native.json','w'));f:write(json.encode(result));f:close()
return result
