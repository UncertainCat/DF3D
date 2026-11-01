-- Native layout/input oracle only. Repeated existing inventory entries create
-- overflow in an owned paused clone; never submit equip/move actions on them.
local unit,view,capture,out=...
local gui=require('gui');local script=require('gui.script')
local sheet=df.global.game.main_interface.view_sheets;local g=df.global.gps;local e=df.global.enabler
local original={};for _,entry in ipairs(unit.inventory)do original[#original+1]=entry end
local saved={first=sheet.scroll_position_inventory,drag=sheet.scrolling_inventory,tab=sheet.active_sub_tab}
local frame=df.global.world.frame_counter;local observations={}
local function pointer(x,y)
 e.mouse_focus=true;e.tracking_on=1;g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 gui.simulateInput(view,{});view:render(dfhack.getTickCount())
end
local function resize(size)
 local file=assert(io.open(out..'/owner-input-request.tmp','w'));file:write('name-resize-'..size);file:close()
 assert(os.rename(out..'/owner-input-request.tmp',out..'/owner-input-request'))
 local deadline=dfhack.getTickCount()+30000
 while true do local ack=io.open(out..'/owner-input-ack');if ack then ack:close();break end
  assert(dfhack.getTickCount()<deadline,'Items resize acknowledgement timed out');script.sleep(1,'frames')end
 assert(os.remove(out..'/owner-input-ack'));view:render(dfhack.getTickCount());script.sleep(2,'frames')
end
local function record(name,skip_capture)
 view:render(dfhack.getTickCount())
 local rows={}
 for y=0,g.dimy-1 do
  local text={};for x=0,g.dimx-1 do local p=dfhack.screen.readTile(x,y);text[#text+1]=p.ch>=32 and string.char(p.ch%256)or' 'end
  text=dfhack.df2utf(table.concat(text)):gsub('%s+$','');if text~=''then rows[#rows+1]={y=y,text=text}end
 end
 observations[#observations+1]={name=name,grid={g.dimx,g.dimy},first=sheet.scroll_position_inventory,dragging=sheet.scrolling_inventory,tab=sheet.active_sub_tab,rows=rows}
 if not skip_capture then capture('unit-items-layout-'..name)end
 assert(df.global.pause_state and df.global.world.frame_counter==frame,'Items layout advanced simulation')
end
local function release()
 e.mouse_lbut=0;e.mouse_lbut_down=0;e.mouse_lbut_lift=1;gui.simulateInput(view,{});view:render(dfhack.getTickCount())
end
local function reset()
 release();sheet.scroll_position_inventory=7;sheet.scrolling_inventory=false;pointer(400,400)
end
local function click(x,y)
 pointer(x,y);e.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount());release()
end
local ok,err=xpcall(function()
 unit.inventory:resize(0);for i=1,33 do unit.inventory:insert('#',original[(i-1)%#original+1])end
 sheet.scroll_position_inventory=0;sheet.scrolling_inventory=false
 for _,size in ipairs{'small','medium','wide','default'}do resize(size);pointer(400,400);record(size)end
 sheet.scroll_position_inventory=100;record('tail')
 for _,case in ipairs{{'up-left',874,214},{'up-right',880,214},{'down-left',874,706},{'down-right',880,706},{'track',880,260},{'track-below',880,600}}do
  reset();click(case[2],case[3]);record('input-'..case[1])
 end
 reset();pointer(880,400);e.mouse_lbut_lift=0
 gui.simulateInput(view,{'_MOUSE_L','_MOUSE_L_DOWN'});view:render(dfhack.getTickCount());record('drag-start',true)
 g.precise_mouse_y=300;g.mouse_y=(300-4)//12;gui.simulateInput(view,{'_MOUSE_L_DOWN'});view:render(dfhack.getTickCount());record('drag-move',true)
 release();record('drag-release')
 for _,key in ipairs{'CONTEXT_SCROLL_UP','CONTEXT_SCROLL_DOWN','CONTEXT_SCROLL_PAGEUP','CONTEXT_SCROLL_PAGEDOWN','STANDARDSCROLL_PAGEUP','CURSOR_UP'}do
  reset();pointer(600,400);gui.simulateInput(view,key);record(key)
 end
 for _,case in ipairs{{'body',600,400},{'padding',600,730},{'footer',600,770},{'outside',400,400}}do
  reset();pointer(case[2],case[3]);gui.simulateInput(view,'CONTEXT_SCROLL_DOWN');record('wheel-'..case[1])
 end
 reset();sheet.scroll_position_inventory=0;pointer(600,400);gui.simulateInput(view,'CONTEXT_SCROLL_PAGEDOWN');record('page-from-zero')
 reset();sheet.scroll_position_inventory=20;resize('wide');record('tail-wide');resize('default')
 reset();click(464,196);record('overview');click(548,196);record('return-items')
 reset();resize('small');record('scrolled-small');resize('default');record('scrolled-default')
end,debug.traceback)
release();unit.inventory:resize(0);for _,entry in ipairs(original)do unit.inventory:insert('#',entry)end
sheet.scroll_position_inventory=saved.first;sheet.scrolling_inventory=saved.drag;sheet.active_sub_tab=saved.tab
resize('default');pointer(400,400)
local result={success=ok,diagnostic_repeated_entries=true,unit_id=unit.id,inventory_count=33,observations=observations,error=not ok and err or nil}
local file=assert(io.open(out..'/unit-items-layout-native.json','w'));file:write(require('json').encode(result));file:close()
assert(ok,err);return result
