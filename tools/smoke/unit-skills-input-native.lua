-- Native input oracle only; does not alter skill or knowledge records.
local unit,view,capture,out=...
local gui=require('gui');local json=require('json');local script=require('gui.script')
local sheet=df.global.game.main_interface.view_sheets;local g=df.global.gps;local e=df.global.enabler
local frame=df.global.world.frame_counter;local observations={}
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
local function select(name)
 local main=name=='Skills' or name=='Overview'
 for y=main and 15 or 17,main and 16 or 20 do
  local chars={};for x=0,g.dimx-1 do local p=dfhack.screen.readTile(x,y);chars[#chars+1]=p.ch>=32 and string.char(p.ch%256)or' 'end
  local x=table.concat(chars):find(name,1,true)
  if x then click((x-1)*8+4,y*12+10);return end
 end
 error('Missing Skills input tab '..name)
end
local function resize(size)
 local f=assert(io.open(out..'/owner-input-request.tmp','w'));f:write('name-resize-'..size);f:close()
 assert(os.rename(out..'/owner-input-request.tmp',out..'/owner-input-request'))
 local deadline=dfhack.getTickCount()+30000
 while true do local ack=io.open(out..'/owner-input-ack');if ack then ack:close();break end
  assert(dfhack.getTickCount()<deadline,'Skills resize acknowledgement timed out');script.sleep(1,'frames')end
 assert(os.remove(out..'/owner-input-ack'));view:render(dfhack.getTickCount());script.sleep(2,'frames')
end
local function record(name,shot)
 view:render(dfhack.getTickCount())
 observations[#observations+1]={name=name,first=sheet.scroll_position_unit_skill,dragging=sheet.scrolling_unit_skill,tab=sheet.unit_skill_active_tab,main_tab=sheet.active_sub_tab,grid={g.dimx,g.dimy}}
 if shot then capture('unit-skills-input-'..name)end
 assert(df.global.pause_state and df.global.world.frame_counter==frame,'Skills input advanced simulation')
end
local function reset()
 release();sheet.scroll_position_unit_skill=7;sheet.scrolling_unit_skill=false;pointer(400,400)
end
local ok,err=xpcall(function()
 select('Skills');select('Knowledge');assert(#sheet.unit_knowledge_type>21,'Skills input needs Knowledge overflow')
 for _,key in ipairs{'CONTEXT_SCROLL_UP','CONTEXT_SCROLL_DOWN','CONTEXT_SCROLL_PAGEUP','CONTEXT_SCROLL_PAGEDOWN'}do
  reset();pointer(600,400);gui.simulateInput(view,key);record(key)
 end
 for _,case in ipairs{{'up-left',874,238},{'up-right',880,238},{'down-left',874,730},{'down-right',880,730},{'track-above',880,250},{'track-below',880,680}}do
  reset();click(case[2],case[3]);record('input-'..case[1])
 end
 reset();pointer(880,400);e.mouse_lbut_lift=0
 gui.simulateInput(view,{'_MOUSE_L','_MOUSE_L_DOWN'});view:render(dfhack.getTickCount());record('drag-start')
 g.precise_mouse_y=500;g.mouse_y=(500-4)//12;gui.simulateInput(view,{'_MOUSE_L_DOWN'});view:render(dfhack.getTickCount());record('drag-move')
 release();pointer(400,400);record('drag-release',true)
 for _,case in ipairs{{'body',600,400},{'top',600,233},{'bottom-padding',600,746},{'footer',600,770},{'outside',400,400}}do
  reset();pointer(case[2],case[3]);gui.simulateInput(view,'CONTEXT_SCROLL_DOWN');record('wheel-'..case[1])
 end
 reset();select('Labor');record('labor-after-scroll',true);select('Knowledge');record('knowledge-return',true)
 reset();select('Combat');record('combat-after-scroll',true);select('Knowledge');record('knowledge-from-combat',true)
 reset();select('Overview');record('overview');select('Skills');record('skills-return',true)
 if os.getenv('DF3D_UNIT_SKILLS_RESIZE')=='1'then
  select('Knowledge');sheet.scroll_position_unit_skill=31
  for _,size in ipairs{'minimum','small','medium','wide','default'}do
   resize(size);pointer(0,0);record('resize-'..size,true)
  end
 end
end,debug.traceback)
release();if os.getenv('DF3D_UNIT_SKILLS_RESIZE')=='1'then resize('default')end;select('Skills');select('Labor');sheet.scroll_position_unit_skill=0;sheet.scrolling_unit_skill=false;pointer(400,400)
local result={success=ok,unit_id=unit.id,observations=observations,error=not ok and err or nil}
local f=assert(io.open(out..'/unit-skills-input-native.json','w'));f:write(json.encode(result));f:close()
assert(ok,err);return result
