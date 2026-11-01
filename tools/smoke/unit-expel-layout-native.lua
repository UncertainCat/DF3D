-- Rendering-only oracle in an owned unsaved clone. Repeated real IDs deliberately
-- exercise overflow; they are not evidence of valid departure groups or sites.
-- Never confirm these diagnostic lists or expose them to a runtime reader.
local unit,view,capture,out=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local sheet=df.global.game.main_interface.view_sheets
local g=df.global.gps
local frame=df.global.world.frame_counter
local observations={}
local function vector(v)local r={}for _,id in ipairs(v)do r[#r+1]=id end return r end
local saved={units=vector(sheet.unit_overview_expel_total_unid),destinations=vector(sheet.unit_overview_expel_dest_stid),
 reason=sheet.unit_overview_expel_cannot_expel_reason,destination=sheet.unit_overview_expel_selected_dest_stid,
 first=sheet.scroll_position_unit_overview_expel,drag=sheet.scrolling_unit_overview_expel}
local function fill(v,values)v:resize(0);for _,id in ipairs(values)do v:insert('#',id)end end
local function pointer(x,y)
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 gui.simulateInput(view,{});view:render(dfhack.getTickCount())
end
local function resize(size)
 local file=assert(io.open(out..'/owner-input-request.tmp','w'));file:write('name-resize-'..size);file:close()
 assert(os.rename(out..'/owner-input-request.tmp',out..'/owner-input-request'))
 local deadline=dfhack.getTickCount()+30000
 while true do local ack=io.open(out..'/owner-input-ack');if ack then ack:close();break end
  assert(dfhack.getTickCount()<deadline,'Expel resize acknowledgement timed out');script.sleep(1,'frames')end
 assert(os.remove(out..'/owner-input-ack'));view:render(dfhack.getTickCount());script.sleep(2,'frames')
end
local function record(name,skip_capture)
 view:render(dfhack.getTickCount())
 local rows={}
 for y=0,g.dimy-1 do
  local chars={}
  for x=0,g.dimx-1 do local pen=dfhack.screen.readTile(x,y);chars[#chars+1]=pen.ch>=32 and string.char(pen.ch%256) or ' ' end
  local text=dfhack.df2utf(table.concat(chars)):gsub('%s+$','')
  if text~=''then rows[#rows+1]={y=y,text=text}end
 end
 observations[#observations+1]={name=name,grid={g.dimx,g.dimy},first=sheet.scroll_position_unit_overview_expel,
  dragging=sheet.scrolling_unit_overview_expel,rows=rows}
 if not skip_capture then capture('unit-expel-layout-'..name)end
 assert(df.global.pause_state and df.global.world.frame_counter==frame,'Layout oracle advanced simulation')
end
local ok,err=xpcall(function()
 assert(sheet.open and sheet.active_id==unit.id and not sheet.unit_overview_expelling)
 sheet.unit_overview_expelling=true;sheet.unit_overview_expel_cannot_expel_reason=-1
 sheet.unit_overview_expel_selected_dest_stid=-1;sheet.scrolling_unit_overview_expel=false
 local repeated={};for i=1,24 do repeated[i]=unit.id end
 for _,mode in ipairs{'group','destinations'}do
  fill(sheet.unit_overview_expel_total_unid,repeated)
  local destinations={};if mode=='destinations'then for i=1,24 do destinations[i]=-1 end end
  fill(sheet.unit_overview_expel_dest_stid,destinations)
  sheet.scroll_position_unit_overview_expel=0
  for _,size in ipairs{'small','medium','wide','default'}do resize(size);record(mode..'-'..size)end
  sheet.scroll_position_unit_overview_expel=23;record(mode..'-tail')
  for _,key in ipairs{'CONTEXT_SCROLL_UP','CURSOR_UP','STANDARDSCROLL_PAGEUP'}do
   gui.simulateInput(view,key);view:render(dfhack.getTickCount());record(mode..'-'..key)
  end
  if os.getenv('DF3D_UNIT_EXPEL_INPUT')=='1' then
   local e=df.global.enabler
   local function reset()
    e.mouse_lbut=0;e.mouse_lbut_down=0;e.mouse_lbut_lift=0
    sheet.scroll_position_unit_overview_expel=7;sheet.scrolling_unit_overview_expel=false;pointer(400,400)
   end
   local function release()
    e.mouse_lbut=0;e.mouse_lbut_down=0;e.mouse_lbut_lift=1
    gui.simulateInput(view,{});view:render(dfhack.getTickCount())
   end
   local bottom=mode=='group' and 694 or 730
   for _,case in ipairs{{'up-left',874,166},{'up-right',880,166},{'down-left',874,bottom},{'down-right',880,bottom},{'track',880,200}}do
    reset();pointer(case[2],case[3]);e.mouse_lbut_lift=0
    gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount());release();record(mode..'-input-'..case[1])
   end
   reset();pointer(880,400);e.mouse_lbut_lift=0
   -- Capture acknowledgement yields to native events and releases synthetic
   -- held buttons. Observe the continuous gesture before any such yield.
   gui.simulateInput(view,{'_MOUSE_L','_MOUSE_L_DOWN'});view:render(dfhack.getTickCount());record(mode..'-input-drag-start',true)
   g.precise_mouse_y=300;g.mouse_y=(300-4)//12
   gui.simulateInput(view,{'_MOUSE_L_DOWN'});view:render(dfhack.getTickCount());record(mode..'-input-drag-move',true)
   release();record(mode..'-input-drag-release')
   for _,key in ipairs{'CONTEXT_SCROLL_UP','CONTEXT_SCROLL_DOWN','CONTEXT_SCROLL_PAGEUP','CONTEXT_SCROLL_PAGEDOWN','STANDARDSCROLL_PAGEUP'}do
    reset();pointer(880,400);gui.simulateInput(view,key);view:render(dfhack.getTickCount());record(mode..'-input-'..key)
   end
   for _,case in ipairs{{'body',600,400},{'footer',600,730},{'outside',400,400}}do
    reset();pointer(case[2],case[3]);gui.simulateInput(view,'CONTEXT_SCROLL_DOWN');record(mode..'-input-wheel-'..case[1])
   end
   release();pointer(400,400)
  end
 end
end,debug.traceback)
fill(sheet.unit_overview_expel_total_unid,saved.units);fill(sheet.unit_overview_expel_dest_stid,saved.destinations)
sheet.unit_overview_expel_cannot_expel_reason=saved.reason;sheet.unit_overview_expel_selected_dest_stid=saved.destination
sheet.scroll_position_unit_overview_expel=saved.first;sheet.scrolling_unit_overview_expel=saved.drag
sheet.unit_overview_expelling=false
resize('default')
local result={success=ok,diagnostic_repeated_ids=true,unit_id=unit.id,observations=observations,error=not ok and err or nil}
local file=assert(io.open(out..'/unit-expel-layout-native.json','w'));file:write(json.encode(result));file:close()
assert(ok,err)
