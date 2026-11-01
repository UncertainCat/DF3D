-- Diagnostic-only overflow in an owned paused clone. Repeated operation
-- pointers are restored before returning; no treatment or simulation runs.
local unit,view,capture,out=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local sheet=df.global.game.main_interface.view_sheets;local g=df.global.gps;local e=df.global.enabler
local health=assert(unit.health);local original={};for _,entry in ipairs(health.op_history)do original[#original+1]=entry end
assert(#original>0,'Health overflow needs an existing operation')
local frame=df.global.world.frame_counter;local observations={}
local camera={x=df.global.window_x,y=df.global.window_y,z=df.global.window_z}
local function pointer(x,y)
 e.mouse_focus=true;e.tracking_on=1;g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 gui.simulateInput(view,{});view:render(dfhack.getTickCount())
end
local function click(x,y)
 pointer(x,y);e.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 e.mouse_lbut=0;e.mouse_lbut_down=0;e.mouse_lbut_lift=1
end
local function select(name)
 for y=13,20 do
  local chars={};for x=0,g.dimx-1 do local p=dfhack.screen.readTile(x,y);chars[#chars+1]=p.ch>=32 and string.char(p.ch%256)or' 'end
  local first=table.concat(chars):find(name,1,true)
  if first then click((first-1)*8+4,y*12+10);return end
 end
 error('Missing Health tab '..name)
end
local function resize(size)
 local file=assert(io.open(out..'/owner-input-request.tmp','w'));file:write('name-resize-'..size);file:close()
 assert(os.rename(out..'/owner-input-request.tmp',out..'/owner-input-request'))
 local deadline=dfhack.getTickCount()+30000
 while true do local ack=io.open(out..'/owner-input-ack');if ack then ack:close();break end
  assert(dfhack.getTickCount()<deadline,'Health resize acknowledgement timed out');script.sleep(1,'frames')end
 assert(os.remove(out..'/owner-input-ack'));view:render(dfhack.getTickCount());script.sleep(2,'frames')
end
local function record(name,skip_capture)
 view:render(dfhack.getTickCount());local rows={};local count=0
 for _,box in ipairs(sheet.unit_health_box)do count=count+#box.line end
 for y=0,g.dimy-1 do
  local text={};for x=0,g.dimx-1 do local p=dfhack.screen.readTile(x,y);text[#text+1]=p.ch>=32 and string.char(p.ch%256)or' 'end
  text=dfhack.df2utf(table.concat(text)):gsub('%s+$','');if text~=''then rows[#rows+1]={y=y,text=text}end
 end
 observations[#observations+1]={name=name,grid={g.dimx,g.dimy},first=sheet.scroll_position_unit_health,dragging=sheet.scrolling_unit_health,open=sheet.open,unit_id=sheet.active_id,main_tab=sheet.active_sub_tab,tab=sheet.unit_health_active_tab,width=sheet.unit_health_width,line_count=count,rows=rows}
 if not skip_capture then capture('unit-health-layout-'..name)end
 assert(df.global.pause_state and df.global.world.frame_counter==frame,'Health layout advanced simulation')
end
local ok,err=xpcall(function()
 health.op_history:resize(0);for i=1,33 do health.op_history:insert('#',original[(i-1)%#original+1])end
 select('Status');select('History');sheet.scroll_position_unit_health=0;sheet.scrolling_unit_health=false
 for _,size in ipairs{'small','medium','wide','default'}do resize(size);pointer(400,400);record(size)end
 for _,key in ipairs{'CONTEXT_SCROLL_UP','CONTEXT_SCROLL_DOWN','CONTEXT_SCROLL_PAGEUP','CONTEXT_SCROLL_PAGEDOWN'}do
  sheet.scroll_position_unit_health=7;pointer(600,400);gui.simulateInput(view,key);record(key)
 end
 local function release()
  e.mouse_lbut=0;e.mouse_lbut_down=0;e.mouse_lbut_lift=1;gui.simulateInput(view,{});view:render(dfhack.getTickCount())
 end
 local function reset()
  release();sheet.scroll_position_unit_health=7;sheet.scrolling_unit_health=false;pointer(400,400)
 end
 for _,case in ipairs{{'up-left',874,250},{'up-right',880,250},{'down-left',874,730},{'down-right',880,730},{'track-above',880,270},{'track-below',880,680}}do
  reset();click(case[2],case[3]);record('input-'..case[1])
 end
 reset();pointer(880,400);e.mouse_lbut_lift=0
 gui.simulateInput(view,{'_MOUSE_L','_MOUSE_L_DOWN'});view:render(dfhack.getTickCount());record('drag-start',true)
 g.precise_mouse_y=500;g.mouse_y=(500-4)//12;gui.simulateInput(view,{'_MOUSE_L_DOWN'});view:render(dfhack.getTickCount());record('drag-move',true)
 release();record('drag-release')
 for _,case in ipairs{{'body',600,400},{'top-padding',600,238},{'bottom-padding',600,746},{'footer',600,770},{'outside',400,400}}do
  reset();pointer(case[2],case[3]);gui.simulateInput(view,'CONTEXT_SCROLL_DOWN');record('wheel-'..case[1])
 end
 sheet.scroll_position_unit_health=7;select('Status');record('status-after-scroll');select('History');record('history-return')
 sheet.scroll_position_unit_health=7;select('Overview');record('overview');select('Health');record('health-return')
 select('History');sheet.scroll_position_unit_health=7
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());record('closed')
 assert(not sheet.open,'Native Health Escape did not close sheet')
 local point={x=unit.pos.x,y=unit.pos.y,z=unit.pos.z}
 dfhack.gui.revealInDwarfmodeMap(point,true);view:render(dfhack.getTickCount())
 local found=false
 for y=0,g.dimy-1 do for x=0,g.dimx-1 do
  g.mouse_x=x;g.mouse_y=y;g.precise_mouse_x=x*8+4;g.precise_mouse_y=y*12+6
  local p=dfhack.gui.getMousePos(true)
  if p and p.x==point.x and p.y==point.y and p.z==point.z then click(g.precise_mouse_x,g.precise_mouse_y);found=true;break end
 end if found then break end end
 assert(found and sheet.open and sheet.active_sheet==df.view_sheet_type.UNIT and sheet.active_id==unit.id,'Native map reopen did not select same creature')
 record('reopened');select('Health');record('reopened-health')
 if os.getenv('DF3D_UNIT_HEALTH_IDENTITY')=='1'then
  local other
  for _,candidate in ipairs(df.global.world.units.active)do
   if candidate.id~=unit.id and candidate.pos.z==unit.pos.z and dfhack.units.isCitizen(candidate)and candidate.profession~=df.profession.CHILD and candidate.profession~=df.profession.BABY and(candidate.pos.x~=unit.pos.x or candidate.pos.y~=unit.pos.y)then other=candidate;break end
  end
  assert(other,'Health identity needs another adult citizen')
  local function map_select(target)
   dfhack.gui.revealInDwarfmodeMap({x=target.pos.x+8,y=target.pos.y,z=target.pos.z},true);view:render(dfhack.getTickCount())
   local found=false
   for y=0,g.dimy-1 do for x=0,49 do
    g.mouse_x=x;g.mouse_y=y;g.precise_mouse_x=x*8+4;g.precise_mouse_y=y*12+6
    local p=dfhack.gui.getMousePos(true)
    if p and p.x==target.pos.x and p.y==target.pos.y and p.z==target.pos.z then click(g.precise_mouse_x,g.precise_mouse_y);found=true;break end
   end if found then break end end
   assert(found and sheet.open and sheet.active_sheet==df.view_sheet_type.UNIT and sheet.active_id==target.id,'Native exposed-map selection did not select creature '..target.id)
  end
  select('History');sheet.scroll_position_unit_health=7
  map_select(other);record('identity-other');select('Health');record('identity-other-health')
  map_select(unit);record('identity-return');select('Health');record('identity-return-health')
 end


end,debug.traceback)
e.mouse_lbut=0;e.mouse_lbut_down=0;e.mouse_lbut_lift=1
health.op_history:resize(0);for _,entry in ipairs(original)do health.op_history:insert('#',entry)end
resize('default');select('Health');select('Status');select('Description');sheet.scrolling_unit_health=false;pointer(400,400)
df.global.window_x=camera.x;df.global.window_y=camera.y;df.global.window_z=camera.z;view:render(dfhack.getTickCount())
local result={success=ok,diagnostic_repeated_operations=true,unit_id=unit.id,operation_count=33,observations=observations,error=not ok and err or nil}
local file=assert(io.open(out..'/unit-health-layout-native.json','w'));file:write(json.encode(result));file:close()
assert(ok,err);return result
