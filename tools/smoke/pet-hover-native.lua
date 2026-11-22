-- Native-only diagnostic. Hover existing pet controls without activating them.
local out,view,list=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local g=df.global.gps;local main=df.global.game.main_interface
local scroll_rows
local function find_scroll(widget)
 if df.widget_scroll_rows:is_instance(widget)then assert(not scroll_rows,'Multiple pet scroll lists');scroll_rows=widget;return end
 if df.widget_container:is_instance(widget)then for _,child in ipairs(dfhack.gui.getWidgetChildren(widget))do find_scroll(child)end end
end
find_scroll(list);list=assert(scroll_rows,'Pet scroll rows missing')
local old_scroll=list.scroll
local old_mouse={g.precise_mouse_x,g.precise_mouse_y,g.mouse_x,g.mouse_y}
local old_focus,old_tracking=df.global.enabler.mouse_focus,df.global.enabler.tracking_on
local probes={}
local function buttons(widget,result)
 if df.widget_interface_pets_livestock_button:is_instance(widget)then result[#result+1]=widget end
 if df.widget_container:is_instance(widget)then for _,child in ipairs(dfhack.gui.getWidgetChildren(widget))do buttons(child,result)end end
end
local ok,err=pcall(function()
 local selected,controls
 for index,row in ipairs(dfhack.gui.getWidgetChildren(list))do
  local candidates={};buttons(row,candidates)
  if not controls or #candidates>#controls then selected=index;controls=candidates end
 end
 assert(controls and #controls>=6,'Pet hover fixture requires six native controls')
 list.scroll=math.min(selected-1,math.max(0,#dfhack.gui.getWidgetChildren(list)-list.num_visible))
 gui.simulateInput(view,{});script.sleep(2,'frames');view:render(dfhack.getTickCount())
 for _,widget in ipairs(controls)do
  local x=math.floor((widget.rect.x1+widget.rect.x2)/2)*8+4
  local y=math.floor((widget.rect.y1+widget.rect.y2)/2)*12+10
  local function move()
   df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
   g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=math.floor(x/8);g.mouse_y=math.floor((y-4)/12)
   gui.simulateInput(view,{});view:render(dfhack.getTickCount())
  end
  local deadline=dfhack.getTickCount()+750
  repeat move();script.sleep(1,'frames')until dfhack.getTickCount()>=deadline
  move();script.sleep(2,'frames')
  local lines,cells={},{}
  for row=0,17 do
   local chars={}
   for col=g.dimx-24,g.dimx-1 do
    local tile=dfhack.screen.readTile(col,row);local ch=tile.ch
    chars[#chars+1]=ch>=32 and ch<127 and string.char(ch)or' '
    if ch>32 and ch<127 then cells[#cells+1]={x=col,y=row,ch=ch,fg=tile.fg,bg=tile.bg,bold=tile.bold}end
   end
   lines[#lines+1]=table.concat(chars):gsub('%s+$','')
  end
  while #lines>0 and lines[#lines]==''do table.remove(lines)end
  probes[#probes+1]={button=widget.which_button,instruction=main.current_hover,displayed=main.last_displayed_hover_inst,
   rect={widget.rect.x1,widget.rect.y1,widget.rect.x2,widget.rect.y2},lines=lines,text_cells=cells}
 end
 local seen={}
 for _,probe in ipairs(probes)do seen[probe.displayed]=true end
 for _,id in ipairs{247,249,250,251,270,271}do assert(seen[id],'Pet help missing hover ID '..id)end
end)
list.scroll=old_scroll
g.precise_mouse_x=old_mouse[1];g.precise_mouse_y=old_mouse[2];g.mouse_x=old_mouse[3];g.mouse_y=old_mouse[4]
gui.simulateInput(view,{});script.sleep(2,'frames')
df.global.enabler.mouse_focus=old_focus;df.global.enabler.tracking_on=old_tracking
local f=assert(io.open(out..'/pet-hover-reference.json','w'));f:write(json.encode({ok=ok,error=not ok and tostring(err) or nil,probes=probes}));f:close()
assert(ok,err)
