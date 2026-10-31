-- Diagnostic native navigation only; never a product source of UI state.
local unit,view,capture,out=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local g=df.global.gps;local main=df.global.game.main_interface
local sheet=main.view_sheets;local alert=main.announcement_alert
local frame=df.global.world.frame_counter
local observations={}
local added_ids={}
local original_log={}
for _,id in ipairs(unit.reports.log[0])do original_log[#original_log+1]=id end
local function shared(value,kind)
 local _,address=value:sizeof()
 return df.reinterpret_cast(kind,df.reinterpret_cast('uint64_t',address).value)
end
local function resize(size)
 local request=assert(io.open(out..'/owner-input-request.tmp','w'));request:write('name-resize-'..size);request:close()
 assert(os.rename(out..'/owner-input-request.tmp',out..'/owner-input-request'))
 local limit=dfhack.getTickCount()+30000
 while true do local ack=io.open(out..'/owner-input-ack');if ack then ack:close();break end
  assert(dfhack.getTickCount()<limit,'unit Reports resize timeout');script.sleep(1,'frames')end
 assert(os.remove(out..'/owner-input-ack'))
 view:render(dfhack.getTickCount());script.sleep(2,'frames')
end
local function geometry(w)
 local r=w.rect
 local row={name=w.name,rect={r.x1,r.y1,r.x2,r.y2},children={}}
 if df.widget_scroll_rows:is_instance(w)then
  row.scroll=w.scroll;row.num_visible=w.num_visible;row.maximum=w.scrollbar.sel_max
  row.bar={}
  for _,field in ipairs{'sel','sel_min','sel_max','page_size','print_sy','print_ey','scroller_sy','scroller_ey'}do row.bar[field]=w.scrollbar[field]end
 end
 if df.widget_container:is_instance(w)then
  for _,child in ipairs(dfhack.gui.getWidgetChildren(w))do row.children[#row.children+1]=geometry(child)end
 end
 return row
end
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
 if widget then
  row.geometry=geometry(widget)
  row.texts=geometry(shared(widget.texts,df.widget_scroll_rows))
  row.pause=geometry(shared(widget.pause_button,df.widget_better_button))
  row.explanation=geometry(shared(widget.explanation,df.widget_text_multiline))
  row.grid={g.dimx,g.dimy}
 end
 observations[#observations+1]=row;capture('unit-reports-'..label)
 assert(df.global.pause_state and df.global.world.frame_counter==frame,'reports advanced simulation')
end
local ok,err=xpcall(function()
 assert(not alert.open and sheet.open and sheet.active_id==unit.id,'reports fixture not ready')
 if os.getenv('DF3D_UNIT_REPORTS_POPULATED')=='1' then
  for i=1,22 do
   local flags=df.announcement_flags:new()
   local index=dfhack.gui.makeAnnouncement(df.announcement_type.COMBAT_STRIKE_DETAILS,flags,unit.pos,'Synthetic unit combat history row '..i,3,true)
   flags:delete()
   local report=assert(df.global.world.status.reports[index])
   added_ids[#added_ids+1]=report.id;unit.reports.log[0]:insert('#',report.id)
  end
 end
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
 if os.getenv('DF3D_UNIT_REPORTS_RESIZE')=='1' then
  for _,size in ipairs{'small','medium','wide','default'}do
   resize(size);pointer(400,400);record('resize-'..size)
   if size=='wide' then
    local texts=shared(widget.texts,df.widget_scroll_rows)
    local e=df.global.enabler;e.mouse_lbut=0;e.mouse_lbut_down=0;e.mouse_lbut_lift=1
    pointer((texts.rect.x2+1)*8+8,texts.rect.y1*12+6)
    gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
    local e=df.global.enabler;e.mouse_lbut=0;e.mouse_lbut_down=0;e.mouse_lbut_lift=1
    pointer(400,400)
    record('wide-arrow-up')
   end
  end
  local texts=shared(widget.texts,df.widget_scroll_rows)
  for _,key in ipairs{'CONTEXT_SCROLL_UP','CURSOR_UP','STANDARDSCROLL_PAGEUP'}do
   local before=texts.scroll
   gui.simulateInput(view,key);view:render(dfhack.getTickCount());record('input-'..key)
   assert(texts.scroll==before,'unexpected direct log keyboard/wheel scrolling')
  end
 end
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());script.sleep(2,'frames');record('back')
 assert(not popup(main.announcements.stack) and not sheet.open,'Back did not close report and leave unit sheet closed')
end,debug.traceback)
-- This probe runs after unit-sheet acceptance because native closes that sheet.
if popup(main.announcements.stack)then gui.simulateInput(view,'LEAVESCREEN')end
-- Synthetic reports exist only in this owned unsaved clone. Restore the unit
-- log before returning; global diagnostic announcements are discarded on exit.
if #added_ids>0 then
 unit.reports.log[0]:resize(0)
 for _,id in ipairs(original_log)do unit.reports.log[0]:insert('#',id)end
end
pointer(400,400)
local result={success=ok,unit_id=unit.id,observations=observations,synthetic_report_ids=added_ids,error=not ok and err or nil}
local f=assert(io.open(out..'/unit-reports-native.json','w'));f:write(json.encode(result));f:close()
assert(ok,err);return result
