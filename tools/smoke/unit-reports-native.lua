-- Diagnostic native navigation only; never a product source of UI state.
local unit,view,capture,out=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local g=df.global.gps;local main=df.global.game.main_interface
local sheet=main.view_sheets;local alert=main.announcement_alert
local frame=df.global.world.frame_counter
local observations={}
local function popup(w)
 if df.widget_report_popup:is_instance(w)then return w end
 if df.widget_container:is_instance(w)then
  for _,child in ipairs(dfhack.gui.getWidgetChildren(w))do local value=popup(child);if value then return value end end
 end
end
local function pointer(x,y)
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 gui.simulateInput(view,{});view:render(dfhack.getTickCount())
end
local function record(label)
 local widget=popup(main.announcements.stack)
 local row={name=label,sheet_open=sheet.open,sheet_id=sheet.active_id,
  alert_open=alert.open,unit_id=alert.viewing_unit and alert.viewing_unit.id or -1,
  category=alert.viewing_unit_uac,scroll=alert.scroll_position_uac,list_size=alert.uac_list_size,
  report_lines={},log_counts={},valid_combat_ids={},popup=widget and {unit_id=widget.unid,category=widget.uac,pause_on_new=widget.pause_on_new,last_length=widget.last_length} or nil}
 for _,report in ipairs(alert.uac_zoom_line_ann)do row.report_lines[#row.report_lines+1]=report and report.id or -1 end
 for i=0,2 do row.log_counts[#row.log_counts+1]=#unit.reports.log[i]end
 for _,id in ipairs(unit.reports.log[0])do if df.report.find(id)then row.valid_combat_ids[#row.valid_combat_ids+1]=id end end
 observations[#observations+1]=row;capture('unit-reports-'..label)
 assert(df.global.pause_state and df.global.world.frame_counter==frame,'reports advanced simulation')
end
local ok,err=xpcall(function()
 assert(not alert.open and sheet.open and sheet.active_id==unit.id,'reports fixture not ready')
 record('before');pointer(808,82)
 assert(main.current_hover==df.main_hover_instruction.UNIT_SHEET_REPORTS,'reports hitbox mismatch')
 local deadline=dfhack.getTickCount()+650
 while dfhack.getTickCount()<deadline do pointer(808,82);script.sleep(1,'frames')end
 pointer(808,82)
 local help={lines={},cells={}}
 for y=0,17 do
  local bytes={}
  for x=g.dimx-24,g.dimx-1 do
   local pen=dfhack.screen.readTile(x,y);bytes[#bytes+1]=pen.ch>=32 and string.char(pen.ch%256) or ' '
   if pen.ch>=33 and pen.ch<=255 then help.cells[#help.cells+1]={x=x,y=y,ch=pen.ch,color=pen.fg+(pen.bold and 8 or 0)}end
  end
  help.lines[#help.lines+1]=dfhack.df2utf(table.concat(bytes)):gsub('%s+$','')
 end
 while #help.lines>0 and help.lines[#help.lines]==''do table.remove(help.lines)end
 assert(main.last_displayed_hover_inst==df.main_hover_instruction.UNIT_SHEET_REPORTS)
 local f=assert(io.open(out..'/unit-reports-help.json','w'));f:write(json.encode(help));f:close()
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount());script.sleep(2,'frames');pointer(400,400)
 record('opened')
 local widget=assert(popup(main.announcements.stack),'unit report popup absent')
 assert(widget.unid==unit.id and widget.uac==0 and not sheet.open,'unit Reports did not open Combat log')
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());script.sleep(2,'frames');record('back')
 assert(not popup(main.announcements.stack) and not sheet.open,'Back did not close report and leave unit sheet closed')
end,debug.traceback)
-- This probe runs after unit-sheet acceptance because native closes that sheet.
if popup(main.announcements.stack)then gui.simulateInput(view,'LEAVESCREEN')end
pointer(400,400)
local result={success=ok,unit_id=unit.id,observations=observations,error=not ok and err or nil}
local f=assert(io.open(out..'/unit-reports-native.json','w'));f:write(json.encode(result));f:close()
assert(ok,err);return result
