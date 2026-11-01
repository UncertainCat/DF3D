-- Actual detail input in the protected paused clone. No content edits.
local unit,view,capture,out,reopen=...
local gui=require('gui');local json=require('json')
local g=df.global.gps;local e=df.global.enabler;local sheet=df.global.game.main_interface.view_sheets
local frame=df.global.world.frame_counter;local observations={}
local camera={x=df.global.window_x,y=df.global.window_y,z=df.global.window_z}
local function pointer(x,y)
 e.mouse_focus=true;e.tracking_on=1;g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 gui.simulateInput(view,{});view:render(dfhack.getTickCount())
end
local function release()
 e.mouse_lbut=0;e.mouse_lbut_down=0;e.mouse_lbut_lift=1;gui.simulateInput(view,{});view:render(dfhack.getTickCount())
end
local function click(x,y)
 pointer(x,y);e.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount());release()
end
local function record(name,shot)
 view:render(dfhack.getTickCount());local lines=0;for _,box in ipairs(sheet.skill_description_box)do lines=lines+#box.line end
 observations[#observations+1]={name=name,first=sheet.scroll_position_skill_description,list_first=sheet.scroll_position_unit_skill,dragging=sheet.scrolling_skill_description,open=sheet.open,raw_count=#sheet.skill_description_raw_str,line_count=lines,tab=sheet.unit_skill_active_tab,main_tab=sheet.active_sub_tab}
 if shot then capture('knowledge-input-'..name)end
 assert(df.global.pause_state and df.global.world.frame_counter==frame,'Knowledge input advanced simulation')
end
local function reset()
 release();sheet.scroll_position_skill_description=7;sheet.scrolling_skill_description=false;pointer(400,400)
end
local ok,err=xpcall(function()
 assert(#sheet.skill_description_raw_str>0,'Expected open native Knowledge detail');record('opened')
 for _,key in ipairs{'CONTEXT_SCROLL_UP','CONTEXT_SCROLL_DOWN','CONTEXT_SCROLL_PAGEUP','CONTEXT_SCROLL_PAGEDOWN'}do
  reset();pointer(600,400);gui.simulateInput(view,key);record(key)
 end
 for _,case in ipairs{{'up-left',874,250},{'up-right',880,250},{'down-left',874,730},{'down-right',880,730},{'track-above',880,260},{'track-below',880,680}}do
  reset();click(case[2],case[3]);record('input-'..case[1])
 end
 reset();pointer(880,400);e.mouse_lbut_lift=0;gui.simulateInput(view,{'_MOUSE_L','_MOUSE_L_DOWN'});view:render(dfhack.getTickCount());record('drag-start')
 g.precise_mouse_y=500;g.mouse_y=(500-4)//12;gui.simulateInput(view,{'_MOUSE_L_DOWN'});view:render(dfhack.getTickCount());record('drag-move')
 release();pointer(400,400);record('drag-release',true)
 for _,case in ipairs{{'body',600,400},{'top-padding',600,238},{'bottom-padding',600,746},{'footer',600,770},{'outside',400,400}}do
  reset();pointer(case[2],case[3]);gui.simulateInput(view,'CONTEXT_SCROLL_DOWN');record('wheel-'..case[1])
 end
 reset();gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());record('escape',true)
 if not sheet.open then
  dfhack.gui.revealInDwarfmodeMap({x=unit.pos.x+8,y=unit.pos.y,z=unit.pos.z},true);view:render(dfhack.getTickCount())
  local found=false
  for y=0,g.dimy-1 do for x=0,49 do
   g.mouse_x=x;g.mouse_y=y;g.precise_mouse_x=x*8+4;g.precise_mouse_y=y*12+6
   local pos=dfhack.gui.getMousePos(true)
   if pos and pos.x==unit.pos.x and pos.y==unit.pos.y and pos.z==unit.pos.z then click(g.precise_mouse_x,g.precise_mouse_y);found=true;break end
  end if found then break end end
  assert(found and sheet.open and sheet.active_id==unit.id,'Knowledge Escape reopen failed')
 end
 reopen();record('reopened',true)
end,debug.traceback)
release();df.global.window_x=camera.x;df.global.window_y=camera.y;df.global.window_z=camera.z;view:render(dfhack.getTickCount())
local result={success=ok,unit_id=unit.id,observations=observations,error=not ok and err or nil}
local f=assert(io.open(out..'/knowledge-input-native.json','w'));f:write(json.encode(result));f:close()
assert(ok,err);return result
