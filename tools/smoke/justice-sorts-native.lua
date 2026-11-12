-- Protected oracle only: native list/widgets describe the expected sort input.
local out,view,probe,settle,tab,capture=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local function click(x,y,controlled_modifier)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=y//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 local flags=df.reinterpret_cast('uint8_t',dfhack.internal.getImageBase()+0x238d0b8);local previous=flags.value
 if controlled_modifier~=nil then flags.value=controlled_modifier end
 local ok,err=pcall(gui.simulateInput,view,'_MOUSE_L');flags.value=previous
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
 assert(ok,err);settle()
end
tab('Open cases');click(100,202);click(100,166);click(652,190)
local records={};local columns={Cat=0,Name=1,Prof=2,Crime=3}
local function modifier(name,down)
 local f=assert(io.open(out..'/owner-input-request.tmp','w'));f:write('kitchen-'..name..(down and'-down'or'-up'));f:close()
 assert(os.rename(out..'/owner-input-request.tmp',out..'/owner-input-request'))
 local deadline=dfhack.getTickCount()+30000
 while true do local ack=io.open(out..'/owner-input-ack');if ack then ack:close();break end
  assert(dfhack.getTickCount()<deadline,'Sort modifier input timeout');require('gui.script').sleep(1,'frames')end
 assert(os.remove(out..'/owner-input-ack'));settle()
end
local function observe(label)
 local list
 local function walk(w)
  if (w.flag.whole&1)==0 then return end
  if df.widget_unit_list:is_instance(w)then assert(not list);list=w end
  if df.widget_container:is_instance(w)then for index,child in ipairs(dfhack.gui.getWidgetChildren(w))do
   if not df.widget_tabs:is_instance(w)or index-1==w.cur_idx then walk(child)end
  end end
 end
 walk(df.global.game.main_interface.info.justice);assert(list,'No active candidate list')
 local _,address=df.sizeof(list);local map=address+0x1c0
 local head=df.reinterpret_cast('uint64_t',map+8).value;local count=df.reinterpret_cast('uint64_t',map+16).value
 assert(count<=16,'Unexpected direction map size')
 local node=df.reinterpret_cast('uint64_t',head).value;local directions={}
 for _=1,count do
  assert(node~=head);local length=df.reinterpret_cast('uint64_t',node+32).value
  local capacity=df.reinterpret_cast('uint64_t',node+40).value;assert(length<=15 and capacity==15)
  local key='';for i=0,length-1 do key=key..string.char(df.reinterpret_cast('uint8_t',node+16+i).value)end
  directions[key]=df.reinterpret_cast('uint8_t',node+48).value~=0
  node=df.reinterpret_cast('uint64_t',node).value
 end
 assert(node==head)
 local sorts,spec={},{}
 for _,entry in ipairs(list.sorting_by)do
  assert(columns[entry.ident]~=nil,'Unknown sort '..entry.ident)
  sorts[#sorts+1]=entry.ident
  spec[#spec+1]=tostring(columns[entry.ident])..':'..(directions[entry.ident]and'1'or'0')
 end
 local ids={}
 local function names(w)
  if df.widget_unit_name:is_instance(w)and w.u then ids[#ids+1]=w.u.id end
  if df.widget_container:is_instance(w)then for _,child in ipairs(dfhack.gui.getWidgetChildren(w))do names(child)end end
 end
 names(list)
 local supplied=probe('justice-conviction-candidates-probe',{'9','',table.concat(spec,',')});local owned={}
 for _,row in ipairs(supplied)do owned[#owned+1]=row.unit_id end
 records[#records+1]={label=label,priorities=sorts,directions=directions,native_ids=ids,owned_ids=owned}
 local f=assert(io.open(out..'/justice-sorts.json','w'));f:write(json.encode(records));f:close()
 assert(json.encode(ids)==json.encode(owned),'Candidate sort mismatch: '..label)
end
observe('default')
for _,header in ipairs{{'Name',592},{'Cat',668},{'Prof',744},{'Crime',808}}do
 for pass=1,2 do click(header[2],154);observe(header[1]..'-'..pass)end
end
for _,step in ipairs{{'shift-name','shift',592},{'shift-name-again','shift',592},
 {'control-crime','control',808},{'control-name','control',592},
 {'shift-profession','shift',744},{'control-category','control',668}}do
 modifier(step[2],true);click(step[3],154);modifier(step[2],false);observe(step[1])
end
-- The Windows-message Shift path is inconclusive. Native SDL8eba80 maps Shift
-- to bit0; feed3c6300 consumes this byte. Restore it immediately after input,
-- following the existing Work Details oracle, never in runtime code.
for _,step in ipairs{{'name',592,0},{'append-crime',808,1},{'append-category',668,1},
 {'repeat-name',592,1},{'repeat-name-again',592,1},{'remove-name',592,2},
 {'remove-crime',808,2},{'remove-category',668,2}}do
 click(step[2],154,step[3]);observe('controlled-'..step[1])
end
capture('justice-sorts')
if os.getenv('DF3D_JUSTICE_ARTWORK_DIAG')=='1' then
 -- Protected diagnostic only; never supply native texture caches to runtime.
 for _,id in ipairs{5815,2459}do
  local unit=df.unit.find(id);local caste=df.global.world.raws.creatures.all[unit.race].caste[unit.caste];local colors={}
  for i,cm in ipairs(caste.color_modifiers)do
   local choice=unit.appearance.colors[i]
   if choice and choice>=0 and choice<#cm.pattern_index then
    local pattern=cm.pattern_index[choice];local raw=df.global.world.raws.descriptors.patterns[pattern];local values={}
    for _,color in ipairs(raw.colors)do values[#values+1]=color end
    colors[#colors+1]={modifier=i,pattern=pattern,pattern_name=raw.id,colors=values,start_date=cm.start_date,end_date=cm.end_date}
   end
  end
  local f=assert(io.open(out..'/justice-artwork-'..id..'-patterns.json','w'));f:write(json.encode(colors));f:close()
  for _,args in ipairs{{'appearance',tostring(id)},{'appearance',tostring(id),'trace','*'},
   {'appearance',tostring(id),'trace','*tissue'},
   {'appearance','layersets',tostring(id),'500'}}do
   local text,rc=dfhack.run_command_silent('df3d',table.unpack(args));assert(rc==0,text)
   local suffix=args[2]=='layersets'and'layers'or(args[4]=='*tissue'and'tissue'or(args[3]or'facts'))
   local f=assert(io.open(out..'/justice-artwork-'..id..'-'..suffix..'.txt','w'));f:write(text);f:close()
  end
 end
 local saved={}
 for _,id in ipairs{5815,2459}do local unit=df.unit.find(id);saved[#saved+1]={unit=unit,texpos=unit.sheet_icon_texpos};unit.sheet_icon_texpos=-1 end
 settle();capture('justice-sorts-fresh-icons')
 gui.simulateInput(view,'LEAVESCREEN');settle()
 if not df.global.game.main_interface.info.open then gui.simulateInput(view,'D_JUSTICE');settle()end
 if df.global.game.main_interface.help.open then click(711,430);assert(not df.global.game.main_interface.help.open)end
 tab('Open cases');click(100,202);click(100,166);click(652,190)
 click(668,154);click(668,154);observe('rebuilt-artwork');capture('justice-sorts-rebuilt-icons')
 -- Native6d76a6 only rebuilds the underlying full-body composite when
 -- unit.flags4 bit9 is set. Rebuilding the widget icon alone cannot test it.
 if os.getenv('DF3D_JUSTICE_ARTWORK_REFRESH')=='1' then
  local flags={}
  for _,entry in ipairs(saved)do flags[#flags+1]=entry.unit.flags4.whole;entry.unit.flags4.any_texture_must_be_refreshed=true;entry.unit.sheet_icon_texpos=-1 end
  local refreshed,refresh_error=pcall(function()
   gui.simulateInput(view,'LEAVESCREEN');settle()
   if not df.global.game.main_interface.info.open then gui.simulateInput(view,'D_JUSTICE');settle()end
   if df.global.game.main_interface.help.open then click(711,430)end
   tab('Open cases');click(100,202);click(100,166);click(652,190)
   click(668,154);click(668,154);observe('refreshed-body-artwork');capture('justice-sorts-refreshed-body')
   local state={}
   for _,entry in ipairs(saved)do state[#state+1]={unit_id=entry.unit.id,refresh_pending=entry.unit.flags4.any_texture_must_be_refreshed,sheet_icon=entry.unit.sheet_icon_texpos}end
   local f=assert(io.open(out..'/justice-artwork-refresh.json','w'));f:write(json.encode(state));f:close()
  end)
  for i,entry in ipairs(saved)do entry.unit.flags4.whole=flags[i];entry.unit.sheet_icon_texpos=entry.texpos end
  assert(refreshed,refresh_error)
 end
 for _,entry in ipairs(saved)do entry.unit.sheet_icon_texpos=entry.texpos end
end
gui.simulateInput(view,'LEAVESCREEN');settle()
if not df.global.game.main_interface.info.open then gui.simulateInput(view,'D_JUSTICE');settle()end
