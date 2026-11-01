-- Native Items navigation in an owned paused clone. No item actions are applied.
local unit,view,capture,out=...
local gui=require('gui');local json=require('json')
local g=df.global.gps;local main=df.global.game.main_interface;local sheet=main.view_sheets
local frame=df.global.world.frame_counter
local original_tab=sheet.active_sub_tab
local function pointer(x,y)
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 gui.simulateInput(view,{});view:render(dfhack.getTickCount())
end
local function click(x,y)
 pointer(x,y);df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
end
local function inventory()
 local rows={}
 for _,entry in ipairs(unit.inventory)do
  rows[#rows+1]={id=entry.item.id,mode=entry.mode,body_part_id=entry.body_part_id,flags=entry.item.flags.whole}
 end
 return rows
end
local before=inventory()
local result={unit_id=unit.id,inventory=before,original_tab=original_tab,rows={},hovers={}}
local ok,err=xpcall(function()
 assert(sheet.open and sheet.active_id==unit.id,'Expected unit Overview')
 click(548,196);pointer(400,400)
 assert(sheet.open and sheet.active_id==unit.id and sheet.active_sub_tab~=original_tab,'Items tab did not open')
 result.items_tab=sheet.active_sub_tab;capture('unit-items-open')
 for y=0,g.dimy-1 do
  local chars={}
  for x=0,g.dimx-1 do local pen=dfhack.screen.readTile(x,y);chars[#chars+1]=pen.ch>=32 and string.char(pen.ch%256) or ' ' end
  local text=dfhack.df2utf(table.concat(chars)):gsub('%s+$','')
  if text~=''then result.rows[#result.rows+1]={y=y,text=text}end
 end
 local seen={}
 for y=208,460,12 do for x=424,888,8 do
  pointer(x,y);local hover=main.current_hover
  if hover>=0 and not seen[hover]then seen[hover]=true;result.hovers[#result.hovers+1]={id=hover,name=df.main_hover_instruction[hover],x=x,y=y}end
 end end
 assert(json.encode(inventory())==json.encode(before),'Items navigation changed inventory')
 assert(df.global.pause_state and df.global.world.frame_counter==frame,'Items navigation advanced simulation')
end,debug.traceback)
click(464,196);pointer(400,400)
result.restored=sheet.open and sheet.active_id==unit.id and sheet.active_sub_tab==original_tab
result.success=ok and result.restored;result.error=not ok and err or nil
local file=assert(io.open(out..'/unit-items-native.json','w'));file:write(json.encode(result));file:close()
assert(result.success,err or 'Items did not restore Overview')
return result
