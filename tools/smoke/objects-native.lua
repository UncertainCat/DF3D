-- Protected native discovery only; menu lists are not runtime inputs.
local out,view,records=...
local gui=require('gui');local script=require('gui.script');local json=require('json');local g=df.global.gps
local function write(name,value)local f=assert(io.open(out..'/'..name,'w'));f:write(value);f:close()end
local function settle()for _=1,3 do script.sleep(1,'frames')end;view:render(dfhack.getTickCount())end
local function click(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=y//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1;settle()
end
local function capture(name)
 write('shot.tmp',name);assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local deadline=dfhack.getTickCount()+10000
 while true do local ack=io.open(out..'/ack-'..name);if ack then ack:close();break end;assert(dfhack.getTickCount()<deadline,'Objects capture timed out');script.sleep(1,'frames')end
end
local function lines()
 local result={}
 for y=0,g.dimy-1 do
  local chars={};for x=0,g.dimx-1 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
  result[#result+1]={y=y,text=dfhack.df2utf(table.concat(chars)):gsub('%s+$','')}
 end
 return result
end
local function bytes(address,size)
 local chars={};for offset=0,size-1 do chars[#chars+1]=string.char(df.reinterpret_cast('uint8_t',address+offset).value)end
 return table.concat(chars)
end
local function probe(command)
 local menu=df.global.game.main_interface.info.artifacts;local size,address=df.sizeof(menu)
 local before=bytes(address,size);local backing={}
 for mode=0,3 do
  local _,vector=df.sizeof(menu.list[mode]);local data=df.reinterpret_cast('uint64_t',vector).value
  backing[mode]=bytes(data,#menu.list[mode]*8)
 end
 local base=dfhack.internal.getImageBase();local rng=bytes(base+0x234e990,0x6180)
 local text,rc=dfhack.run_command_silent('df3d',command or 'objects-lists-probe');assert(rc==0,'Owned Objects provider failed: '..text)
 assert(bytes(address,size)==before,'Owned Objects provider changed menu')
 for mode=0,3 do
  local _,vector=df.sizeof(menu.list[mode]);local data=df.reinterpret_cast('uint64_t',vector).value
  assert(bytes(data,#menu.list[mode]*8)==backing[mode],'Owned Objects provider changed menu backing')
 end
 assert(bytes(base+0x234e990,0x6180)==rng,'Owned Objects provider advanced randomness')
 return json.decode(text)
end
local cold=probe()
local native_names=probe('objects-names-probe')
local ownership=probe('objects-ownership-probe')
local destinations=probe('objects-destinations-probe')
local appearances={}
for mode,rows in ipairs(ownership)do
 appearances[mode]={}
 for _,row in ipairs(rows)do
  local item=assert(df.item.find(row.item_id))
  local facts={item_type=item:getType(),artifact=item.flags.artifact,artifact_mood=item.flags.artifact_mood}
  if item:getType()==df.item_type.COFFIN then
   local holder=dfhack.items.getHolderBuilding(item)
   facts.holder_id=holder and holder.id or -1
   facts.holder_type=holder and holder:getType()or -1
   facts.holder_count=holder and #holder.contained_items or -1
  end
  appearances[mode][#appearances[mode]+1]=facts
 end
end
write('objects-appearance-facts.json',json.encode(appearances))
if os.getenv('DF3D_OBJECTS_WIRE')=='1' then
 local size,address=df.sizeof(df.global.game.main_interface.info.artifacts)
 local menu_before=bytes(address,size);local base=dfhack.internal.getImageBase()
 local rng_before=bytes(base+0x234e990,0x6180)
 local window_before={df.global.window_x,df.global.window_y,df.global.window_z}
 write('objects-wire-reference.json',json.encode{ownership=ownership,destinations=destinations,appearances=appearances})
 write('shot.tmp','objects-wire');assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local deadline=dfhack.getTickCount()+30000
 while true do local ack=io.open(out..'/ack-objects-wire');if ack then ack:close();break end
  assert(dfhack.getTickCount()<deadline,'Objects wire timed out');script.sleep(1,'frames')
 end
 assert(bytes(address,size)==menu_before,'Objects wire changed native menu')
 assert(bytes(base+0x234e990,0x6180)==rng_before,'Objects wire advanced randomness')
 assert(json.encode(window_before)==json.encode{df.global.window_x,df.global.window_y,df.global.window_z},'Objects wire moved native camera')
end
gui.simulateInput(view,'D_NOBLES');settle();click(310,100)
local info=df.global.game.main_interface.info
assert(info.open and info.current_mode==df.info_interface_mode_type.ARTIFACTS,'Objects header failed')
local menu=info.artifacts
local size,address=df.sizeof(menu)
local result={ownership=ownership,native_names=native_names,owned_cold=cold,owned_warm=probe(),mode=menu.mode,menu_rva=address-dfhack.internal.getImageBase(),menu_size=size,lists={},lines=lines()}
for mode=0,3 do
 local rows={}
 for _,artifact in ipairs(menu.list[mode])do
  rows[#rows+1]={id=artifact.id,item_id=artifact.item and artifact.item.id or -1,name=dfhack.df2utf(dfhack.translation.translateName(artifact.name,true))}
 end
 result.lists[#result.lists+1]={mode=mode,rows=rows,scroll=menu.scroll_position[mode],drag=menu.scrolling[mode]}
end
for mode=0,3 do
 local ids={};for _,row in ipairs(result.lists[mode+1].rows)do ids[#ids+1]=row.id end
 assert(json.encode(ids)==json.encode(result.owned_cold[mode+1]) and json.encode(ids)==json.encode(result.owned_warm[mode+1]),'Owned Objects list differs from native')
end
result.tabs={}
for mode,x in ipairs{90,184,296,443}do
 click(x,124);assert(menu.mode==mode-1,'Objects category click failed')
 local screen=lines()
 for index,row in ipairs(native_names[mode])do
  assert(row.artifact_id==result.lists[mode].rows[index].id,'Objects names order differs')
  if index<=16 then
   local name_line=screen[14+(index-1)*3].text;local translated_line=screen[15+(index-1)*3].text
   assert(name_line:find(row.native_name,1,true),'Native Objects name differs: '..row.native_name)
   assert(translated_line:find(row.translated_name,1,true),'Native Objects translated name differs: '..row.translated_name)
   local caption=ownership[mode][index].ownership
   assert(name_line:find(caption,1,true),'Native Objects ownership differs: '..caption)
  end
 end
 result.tabs[#result.tabs+1]={mode=menu.mode,lines=screen};capture('objects-tab-'..tostring(mode-1))
 assert(json.encode(probe())==json.encode(cold),'Owned Objects lists depend on native tab')
end
result.owned_lists_match=true
result.destinations=destinations
-- Actual native controls, not synthesized calls to the item-sheet opener.
click(90,124)
local available,unavailable
for index,row in ipairs(destinations[1])do
 if index<=16 then
  if row.available and not available then available=index end
  if not row.available and not unavailable then unavailable=index end
 end
end
assert(available and unavailable,'Need local and nonlocal artifact destinations')
result.hover={}
for _,target in ipairs{{'recenter',540,available,236},{'view',564,available,237},{'unavailable-recenter',540,unavailable,-1},{'unavailable-view',564,unavailable,-1}}do
 local x,y=target[2],166+(target[3]-1)*36
 local function point()
  g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
  df.global.game.main_interface.current_hover=0
  gui.simulateInput(view,{});view:render(dfhack.getTickCount())
 end
 local deadline=dfhack.getTickCount()+650
 repeat point();script.sleep(1,'frames')until dfhack.getTickCount()>=deadline
 point()
 local sample={kind=target[1],instruction=df.global.game.main_interface.current_hover,lines={}}
 assert(sample.instruction==target[4],'Objects hover instruction differs: '..target[1])
 for yy=0,17 do
  local chars={};for xx=g.dimx-24,g.dimx-1 do local ch=dfhack.screen.readTile(xx,yy).ch;chars[#chars+1]=ch>=32 and string.char(ch%256)or' 'end
  sample.lines[#sample.lines+1]=dfhack.df2utf(table.concat(chars)):gsub('%s+$','')
 end
 while #sample.lines>0 and sample.lines[#sample.lines]==''do table.remove(sample.lines)end
 result.hover[#result.hover+1]=sample
 write('objects-hover.json',json.encode(result.hover))
end
local sheet=df.global.game.main_interface.view_sheets
local function observed()
 return {objects=info.open,sheet=sheet.open,sheet_type=sheet.active_sheet,sheet_id=sheet.active_id,
  window={df.global.window_x,df.global.window_y,df.global.window_z},
  follow_item=df.global.plotinfo.follow_item,follow_unit=df.global.plotinfo.follow_unit}
end
result.navigation={before=observed(),unavailable=destinations[1][unavailable],target=destinations[1][available]}
for _,x in ipairs{540,564}do
 click(x,166+(unavailable-1)*36)
 assert(info.open and not sheet.open,'Nonlocal artifact control navigated')
end
local target=destinations[1][available]
local x,y,z=dfhack.items.getPosition(df.item.find(target.item_id))
assert(json.encode({x,y,z})==json.encode(target.position),'Owned destination differs from effective item position')
click(540,166+(available-1)*36)
result.navigation.recenter=observed()
assert(not info.open and not sheet.open and df.global.window_z==z,'Objects recenter failed')
gui.simulateInput(view,'D_NOBLES');settle();click(310,100);click(90,124)
click(564,166+(available-1)*36)
result.navigation.view=observed()
assert(not info.open and sheet.open and sheet.active_sheet==df.view_sheet_type.ITEM and sheet.active_id==target.item_id,'Objects View opened wrong item')
gui.simulateInput(view,'LEAVESCREEN');settle();assert(not sheet.open,'Objects destination sheet did not close')
write('objects-native.json',json.encode(result))
assert(not info.open,'Objects did not close')
records[#records+1]={name='objects-discovery',closed=true}

