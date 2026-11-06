-- Diagnostic native screen observation in the protected owned, unsaved lane.
-- Runtime providers must never use this screen's widget or list storage.
local out,view,records=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
df.global.enabler.gfps=30
df.global.enabler.fps_per_gfps=df.global.enabler.fps/30
gui.simulateInput(view,'D_UNITLIST')
for _=1,3 do script.sleep(1,'frames')end
view:render(dfhack.getTickCount())
local info=df.global.game.main_interface.info
assert(info.open and info.current_mode==df.info_interface_mode_type.CREATURES)
local source=debug.getinfo(1,'S').source:sub(2):gsub('smoke/residents%-native.lua$','ui_bake/capture_widgets.lua')
assert(loadfile(source))(out..'/residents-widgets.json','templates')
local lists={};local active_list;local headers={}
local base=dfhack.internal.getImageBase()
local function callbacks(value,stride)
 local _,address=df.sizeof(value)
 local first=df.reinterpret_cast('uint64_t',address).value
 local last=df.reinterpret_cast('uint64_t',address+8).value
 assert(last>=first and (last-first)%stride==0 and last-first<=65536)
 local result={}
 for at=first,last-1,stride do
  local context=df.reinterpret_cast('uint64_t',at+56).value
  if context~=0 then
   local vt=df.reinterpret_cast('uint64_t',context).value
   result[#result+1]=df.reinterpret_cast('uint64_t',vt+16).value-base
  end
 end
 return result
end
local function walk(widget)
 if df.widget_unit_list:is_instance(widget) then
  local row={name=widget.name,filter=widget.filter_str,options={},ids={},sorting={},sort_flags=widget.sort_flags.whole}
  for _,option in ipairs(widget.options)do row.options[#row.options+1]=df.unit_list_options[option]end
  for _,entry in ipairs(widget.entry_list)do
   row.ids[#row.ids+1]={kind=entry.t,id=entry.t==0 and entry.u and entry.u.id or -1}
  end
  for _,entry in ipairs(widget.sorting_by)do row.sorting[#row.sorting+1]=entry.ident end
  row.filter_callbacks=#widget.filter_func;row.partitions=#widget.partitions;row.always_sorting=#widget.always_sorting_by
  row.callbacks={filter=callbacks(widget.filter_func,64),partitions=callbacks(widget.partitions,64),always=callbacks(widget.always_sorting_by,64)}
  active_list=widget
  lists[#lists+1]=row
 end
 if widget.rect.y1==12 and widget.rect.y2==12 then headers[widget.name]=widget end
 if df.widget_container:is_instance(widget)then
  for index,child in ipairs(dfhack.gui.getWidgetChildren(widget))do
   if not df.widget_tabs:is_instance(widget) or index-1==widget.cur_idx then walk(child)end
  end
 end
end
walk(info.creatures)
assert(#lists>0,'Native Residents unit list missing')
local snapshots={}
local function observe(name)
 local ids={}
 local function collect(widget,active)
  active=active and (widget.flag.whole&1)==1
  if active and df.widget_unit_portrait:is_instance(widget) and widget.u then ids[#ids+1]=widget.u.id end
  if df.widget_container:is_instance(widget)then for _,child in ipairs(dfhack.gui.getWidgetChildren(widget))do collect(child,active)end end
 end
 collect(active_list,true)
 local sorting={};for _,entry in ipairs(active_list.sorting_by)do sorting[#sorting+1]=entry.ident end
 snapshots[#snapshots+1]={name=name,ids=ids,sorting=sorting,callbacks=callbacks(active_list.sorting_by,96)}
end
observe('initial')
for _,name in ipairs{'Name','Cat','Prof','Job','Stress'}do
 local header=assert(headers[name],'Missing sort header '..name)
 for direction=1,2 do
  local g=df.global.gps
  g.precise_mouse_x=header.rect.x1*8+4;g.precise_mouse_y=header.rect.y1*12+6
  g.mouse_x=header.rect.x1;g.mouse_y=header.rect.y1
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
  df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L')
  df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
  for _=1,3 do script.sleep(1,'frames')end
  view:render(dfhack.getTickCount());observe(name..'-'..direction)
 end
end
local file=assert(io.open(out..'/residents-list-reference.json','w'))
file:write(json.encode({mode=info.creatures.current_mode,lists=lists,snapshots=snapshots}));file:close()
file=assert(io.open(out..'/shot.tmp','w'));file:write('residents-root');file:close()
assert(os.rename(out..'/shot.tmp',out..'/shot'))
local deadline=dfhack.getTickCount()+30000
while true do
 local ack=io.open(out..'/ack-residents-root');if ack then ack:close();break end
 assert(dfhack.getTickCount()<deadline,'Residents capture timeout');script.sleep(1,'frames')
end
records[#records+1]={name='residents-native-discovery',lists=#lists,mode=info.creatures.current_mode}
