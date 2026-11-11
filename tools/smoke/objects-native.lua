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
gui.simulateInput(view,'D_NOBLES');settle();click(310,100)
local info=df.global.game.main_interface.info
assert(info.open and info.current_mode==df.info_interface_mode_type.ARTIFACTS,'Objects header failed')
local menu=info.artifacts
local size,address=df.sizeof(menu)
local result={native_names=native_names,owned_cold=cold,owned_warm=probe(),mode=menu.mode,menu_rva=address-dfhack.internal.getImageBase(),menu_size=size,lists={},lines=lines()}
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
  end
 end
 result.tabs[#result.tabs+1]={mode=menu.mode,lines=screen};capture('objects-tab-'..tostring(mode-1))
 assert(json.encode(probe())==json.encode(cold),'Owned Objects lists depend on native tab')
end
result.owned_lists_match=true
write('objects-native.json',json.encode(result))
gui.simulateInput(view,'LEAVESCREEN');settle();assert(not info.open,'Objects did not close')
records[#records+1]={name='objects-discovery',closed=true}

