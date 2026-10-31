-- Diagnostic only: native UI state is never a runtime camera input.
local unit,view,capture,out=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local g=df.global.gps;local main=df.global.game.main_interface
local sheet=main.view_sheets;local plot=df.global.plotinfo
local saved={unit=plot.follow_unit,item=plot.follow_item,x=df.global.window_x,
 y=df.global.window_y,z=df.global.window_z,open=sheet.open,active_id=sheet.active_id,active_sheet=sheet.active_sheet}
local pos={x=unit.pos.x,y=unit.pos.y,z=unit.pos.z}
local block=assert(dfhack.maps.getTileBlock(pos.x,pos.y,pos.z))
local designation=block.designation[pos.x%16][pos.y%16]
local original_designation=designation.whole
local original_flags=unit.flags1.whole
local frame=df.global.world.frame_counter;local observations={}
local function probe()
 local output,status=dfhack.run_command_silent('df3d','unit-follow-position-probe',tostring(unit.id))
 assert(status==0,output) -- Warm semantic reference indices before byte guards.
 local guards={}
 for _,object in ipairs{unit,sheet,plot}do
  local size,address=df.sizeof(object);local bytes=df.new('uint8_t',size)
  dfhack.internal.memmove(bytes,address,size);guards[#guards+1]={size=size,address=address,bytes=bytes}
 end
 output,status=dfhack.run_command_silent('df3d','unit-follow-position-probe',tostring(unit.id))
 local unchanged=true
 for _,guard in ipairs(guards)do
  if dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)~=0 then unchanged=false end
  df.delete(guard.bytes)
 end
 assert(status==0,output);assert(unchanged,'follow reader changed warmed unit/menu state')
 return json.decode(output)
end
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
 local semantic=probe()
 if os.getenv('DF3D_UNIT_FOLLOW_WIRE')=='1' and
    (label=='enabled' or label=='terrain-hidden' or label=='inactive' or label=='active-restored') then
  local file=assert(io.open(out..'/unit-follow-wire-expected.json','w'));file:write(json.encode(semantic));file:close()
  capture('unit-follow-wire-'..label)
  file=assert(io.open(out..'/unit-follow-wire-result.json'));local result=json.decode(file:read('*a'));file:close()
  assert(result.success and result.valid==semantic.valid and result.unit_id==unit.id,'follow transport differs')
  assert(os.remove(out..'/unit-follow-wire-result.json'))
 end
 observations[#observations+1]={name=label,follow_unit=plot.follow_unit,follow_item=plot.follow_item,
  semantic=semantic,guards_unchanged=true,
  sheet_open=sheet.open,position={x=unit.pos.x,y=unit.pos.y,z=unit.pos.z},
  window={x=df.global.window_x,y=df.global.window_y,z=df.global.window_z},
  terrain_hidden=designation.hidden}
 if plot.follow_unit==unit.id then
  assert(semantic.valid and semantic.x==unit.pos.x and semantic.y==unit.pos.y and semantic.z==unit.pos.z,'semantic follow differs from native')
 end
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
 local until_hover=dfhack.getTickCount()+650
 while dfhack.getTickCount()<until_hover do pointer(872,82);script.sleep(1,'frames')end
 pointer(872,82)
 assert(main.last_displayed_hover_inst==df.main_hover_instruction.FOLLOW_UNIT,'unit camera help not displayed')
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
 local help_file=assert(io.open(out..'/unit-camera-help.json','w'));help_file:write(json.encode(help));help_file:close()
 click();record('enabled')
 assert(plot.follow_unit==unit.id and plot.follow_item==-1 and sheet.open,'unit camera did not enable follow')
 unit.pos.x=pos.x+1;unit.pos.y=pos.y-1;settle();record('moved')
 unit.pos.x=pos.x;unit.pos.y=pos.y;settle();record('position-restored')
 click();record('disabled');assert(plot.follow_unit==-1 and sheet.open,'second click did not disable follow')
 click();designation.hidden=true;settle();record('terrain-hidden')
 designation.whole=original_designation;settle();record('terrain-restored')
 unit.flags1.inactive=true;settle();record('inactive')
 assert(plot.follow_unit==-1 and not observations[#observations].semantic.valid,'inactive unit remained followable')
 unit.flags1.whole=original_flags;settle();record('active-restored')
 assert(plot.follow_unit==-1 and observations[#observations].semantic.valid,'restoration resumed follow or remained invalid')
 -- Inactive targets close the native sheet. Recreate the diagnostic fixture
 -- after restoring the unit; this is not a product input or reopening claim.
 sheet.active_sheet=saved.active_sheet;sheet.active_id=saved.active_id;sheet.open=true
 pointer(400,400)
 if plot.follow_unit~=unit.id then click()end
 assert(plot.follow_unit==unit.id,'explicit follow failed')
 gui.simulateInput(view,'_MOUSE_R');view:render(dfhack.getTickCount());settle();record('sheet-closed')
 assert(not sheet.open and plot.follow_unit==unit.id,'closing sheet lost unit follow')
 gui.simulateInput(view,'CURSOR_LEFT');view:render(dfhack.getTickCount());settle();record('manual-pan')
 assert(plot.follow_unit==-1,'manual pan retained unit follow')
end,debug.traceback)
unit.pos.x=pos.x;unit.pos.y=pos.y;unit.pos.z=pos.z
unit.flags1.whole=original_flags
designation.whole=original_designation
plot.follow_unit=saved.unit;plot.follow_item=saved.item
df.global.window_x=saved.x;df.global.window_y=saved.y;df.global.window_z=saved.z
sheet.active_sheet=saved.active_sheet;sheet.active_id=saved.active_id;sheet.open=saved.open;pointer(400,400)
local result={success=ok,restored=true,unit_id=unit.id,observations=observations,error=not ok and err or nil}
local file=assert(io.open(out..'/unit-camera-native.json','w'));file:write(json.encode(result));file:close()
assert(ok,err)
return result
