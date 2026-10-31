-- Diagnostic only: native UI state is never a runtime camera input.
local unit,view,capture,out=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local g=df.global.gps;local main=df.global.game.main_interface
local sheet=main.view_sheets;local plot=df.global.plotinfo
local saved={unit=plot.follow_unit,item=plot.follow_item,x=df.global.window_x,
 y=df.global.window_y,z=df.global.window_z,open=sheet.open}
local pos={x=unit.pos.x,y=unit.pos.y,z=unit.pos.z}
local block=assert(dfhack.maps.getTileBlock(pos.x,pos.y,pos.z))
local designation=block.designation[pos.x%16][pos.y%16]
local original_designation=designation.whole
local frame=df.global.world.frame_counter;local observations={}
local function pointer(x,y)
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 gui.simulateInput(view,{});view:render(dfhack.getTickCount())
end
local function settle()
 script.sleep(2,'frames');pointer(400,400)
end
local function record(label)
 capture('unit-camera-'..label)
 observations[#observations+1]={name=label,follow_unit=plot.follow_unit,follow_item=plot.follow_item,
  sheet_open=sheet.open,position={x=unit.pos.x,y=unit.pos.y,z=unit.pos.z},
  window={x=df.global.window_x,y=df.global.window_y,z=df.global.window_z},
  terrain_hidden=designation.hidden}
 assert(df.global.pause_state and df.global.world.frame_counter==frame,'camera advanced simulation')
end
local function click()
 pointer(872,82);gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount());settle()
end
local ok,err=xpcall(function()
 assert(sheet.open and sheet.active_sheet==df.view_sheet_type.UNIT and sheet.active_id==unit.id)
 plot.follow_unit=-1;plot.follow_item=-1
 record('before');pointer(872,82)
 observations[#observations+1]={name='hover',instruction=main.current_hover}
 assert(main.current_hover==df.main_hover_instruction.FOLLOW_UNIT,'unit camera hitbox mismatch')
 click();record('enabled')
 assert(plot.follow_unit==unit.id and plot.follow_item==-1 and sheet.open,'unit camera did not enable follow')
 unit.pos.x=pos.x+1;unit.pos.y=pos.y-1;settle();record('moved')
 unit.pos.x=pos.x;unit.pos.y=pos.y;settle();record('position-restored')
 click();record('disabled');assert(plot.follow_unit==-1 and sheet.open,'second click did not disable follow')
 click();designation.hidden=true;settle();record('terrain-hidden')
 designation.whole=original_designation;settle();record('terrain-restored')
 -- Record visibility behavior before imposing an implementation policy.
 if plot.follow_unit~=unit.id then click()end
 assert(plot.follow_unit==unit.id,'explicit follow failed')
 gui.simulateInput(view,'_MOUSE_R');view:render(dfhack.getTickCount());settle();record('sheet-closed')
 assert(not sheet.open and plot.follow_unit==unit.id,'closing sheet lost unit follow')
 gui.simulateInput(view,'CURSOR_LEFT');view:render(dfhack.getTickCount());settle();record('manual-pan')
 assert(plot.follow_unit==-1,'manual pan retained unit follow')
end,debug.traceback)
unit.pos.x=pos.x;unit.pos.y=pos.y;unit.pos.z=pos.z
designation.whole=original_designation
plot.follow_unit=saved.unit;plot.follow_item=saved.item
df.global.window_x=saved.x;df.global.window_y=saved.y;df.global.window_z=saved.z
sheet.open=saved.open;pointer(400,400)
local result={success=ok,restored=true,unit_id=unit.id,observations=observations,error=not ok and err or nil}
local file=assert(io.open(out..'/unit-camera-native.json','w'));file:write(json.encode(result));file:close()
assert(ok,err)
return result
