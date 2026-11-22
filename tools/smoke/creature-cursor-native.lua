-- Observe native local cursor/navigation; never invoke gameplay controls.
local out,view,list,tab=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local scroll
local function find(widget)
 if df.widget_scroll_rows:is_instance(widget)then scroll=widget;return end
 if df.widget_container:is_instance(widget)then for _,child in ipairs(dfhack.gui.getWidgetChildren(widget))do find(child)end end
end
find(list);assert(scroll,'Creature scroll rows missing')
local original={cursor=list.cursor_idx,scroll=scroll.scroll}
local g=df.global.gps;local mouse={g.precise_mouse_x,g.precise_mouse_y,g.mouse_x,g.mouse_y}
local en=df.global.enabler;local focus,tracking=en.mouse_focus,en.tracking_on
local observations={}
local function settle()script.sleep(3,'frames');view:render(dfhack.getTickCount())end
local function record(key)observations[#observations+1]={key=key,cursor=list.cursor_idx,scroll=scroll.scroll}end
local function reset()list.cursor_idx=original.cursor;scroll.scroll=original.scroll;settle()end
local ok,err=pcall(function()
 record('initial')
 -- Keep keyboard trials away from controls and the filter.
 en.mouse_focus=true;en.tracking_on=1;g.precise_mouse_x=900;g.precise_mouse_y=690;g.mouse_x=112;g.mouse_y=57
 for _,key in ipairs{'STANDARDSCROLL_DOWN','STANDARDSCROLL_UP','CURSOR_DOWN','CURSOR_UP','STANDARDSCROLL_PAGEDOWN','STANDARDSCROLL_PAGEUP'}do
  reset();gui.simulateInput(view,key);settle();record(key)
 end
 reset()
 for _=1,20 do gui.simulateInput(view,'STANDARDSCROLL_DOWN');settle()end
 record('down_twenty')
 for _=1,20 do gui.simulateInput(view,'STANDARDSCROLL_UP');settle()end
 record('up_twenty')
 reset()
 local rows=dfhack.gui.getWidgetChildren(scroll);local row=assert(rows[math.min(#rows,original.scroll+2)])
 local x=500;local y=(row.rect.y1+1)*12+4
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=math.floor(x/8);g.mouse_y=math.floor((y-4)/12)
 gui.simulateInput(view,{});settle();record('move_second_visible')
 en.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');en.mouse_lbut=0;en.mouse_lbut_down=0;en.mouse_lbut_lift=1
 settle();record('click_second_visible')
end)
list.cursor_idx=original.cursor;scroll.scroll=original.scroll
g.precise_mouse_x=mouse[1];g.precise_mouse_y=mouse[2];g.mouse_x=mouse[3];g.mouse_y=mouse[4];en.mouse_focus=focus;en.tracking_on=tracking
settle()
local f=assert(io.open(out..'/creature-cursor-'..tab..'.json','w'));f:write(json.encode({ok=ok,error=not ok and tostring(err)or nil,count=#dfhack.gui.getWidgetChildren(scroll),page=scroll.num_visible,observations=observations,restored=list.cursor_idx==original.cursor and scroll.scroll==original.scroll}));f:close()
assert(ok,err)
