-- Protected native UI discovery only; runtime must not borrow these widgets.
local out,view,records=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local g=df.global.gps
gui.simulateInput(view,'D_LABOR')
for _=1,3 do script.sleep(1,'frames')end;view:render(dfhack.getTickCount())
local info=df.global.game.main_interface.info
assert(info.open,'Native Labor did not open')
local path=debug.getinfo(1,'S').source:sub(2):gsub('smoke/work%-details%-native.lua$','ui_bake/capture_widgets.lua')
assert(loadfile(path))(out..'/work-details-widgets.json','templates')
local result={mode=info.current_mode,rows={},details={},callbacks={}}
local base=dfhack.internal.getImageBase()
local function walk(widget,depth)
 assert(depth<24,'Work Details widget depth exceeded')
 if (widget.flag.whole&1)==0 then return end
 local _,address=df.sizeof(widget.custom_activated)
 local first=df.reinterpret_cast('uint64_t',address).value;local last=df.reinterpret_cast('uint64_t',address+8).value
 assert(last>=first and (last-first)%64==0 and last-first<=65536)
 for at=first,last-1,64 do
  local context=df.reinterpret_cast('uint64_t',at+56).value
  if context~=0 then
   local vt=df.reinterpret_cast('uint64_t',context).value
   result.callbacks[#result.callbacks+1]={name=widget.name,rect={widget.rect.x1,widget.rect.y1,widget.rect.x2,widget.rect.y2},rva=df.reinterpret_cast('uint64_t',vt+16).value-base}
  end
 end
 if df.widget_container:is_instance(widget)then for _,child in ipairs(dfhack.gui.getWidgetChildren(widget))do walk(child,depth+1)end end
end
walk(info.labor,0)
for y=0,g.dimy-1 do
 local chars={};for x=0,g.dimx-1 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
 result.rows[#result.rows+1]={y=y,text=dfhack.df2utf(table.concat(chars)):gsub('%s+$','')}
end
for i,d in ipairs(df.global.plotinfo.labor_info.work_details)do
 local labors={};for j,value in ipairs(d.allowed_labors)do if value then labors[#labors+1]=j end end
 result.details[#result.details+1]={index=i,name=dfhack.df2utf(d.name),icon=d.icon,flags=d.flags.whole,labors=labors,assigned_count=#d.assigned_units}
end
local function shot(name)
 local file=assert(io.open(out..'/work-details-native.json','w'));file:write(json.encode(result));file:close()
 file=assert(io.open(out..'/shot.tmp','w'));file:write(name);file:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local deadline=dfhack.getTickCount()+10000
 while true do local ack=io.open(out..'/ack-'..name);if ack then ack:close();break end;assert(dfhack.getTickCount()<deadline,'Work Details capture timeout');script.sleep(1,'frames')end
end
shot('work-details-root')
g.precise_mouse_x=15*8+4;g.precise_mouse_y=13*12+6;g.mouse_x=15;g.mouse_y=13
df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
gui.simulateInput(view,'_MOUSE_L')
df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
for _=1,3 do script.sleep(1,'frames')end;view:render(dfhack.getTickCount())
local all=df.global.plotinfo.labor_info.work_details
assert(#all==#result.details+1,'Native Add new work detail did not append one detail')
local d=all[#all-1];local labors={};for j,value in ipairs(d.allowed_labors)do if value then labors[#labors+1]=j end end
result.created={index=#all-1,name=dfhack.df2utf(d.name),icon=d.icon,flags=d.flags.whole,labors=labors,assigned_count=#d.assigned_units}
shot('work-details-created')
records[#records+1]={name='work-details-native',count=#result.details,mode=result.mode}
