-- Read-only Expel navigation in an owned paused fixture; never confirms expulsion.
local unit,view,capture,out=...
local gui=require('gui')
local json=require('json')
local g=df.global.gps
local main=df.global.game.main_interface
local sheet=main.view_sheets
local frame=df.global.world.frame_counter
local observations={}
local changed_positions={}
local function restore_positions()
 for _,saved in ipairs(changed_positions)do saved.position.flags.ELECTED=saved.elected;saved.position.flags.SUCCESSION_BY_HEIR=saved.hereditary end
end
local function pointer(x,y)
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.mouse_x=x//8;g.mouse_y=(y-4)//12;g.precise_mouse_x=x;g.precise_mouse_y=y
 gui.simulateInput(view,{});view:render(dfhack.getTickCount())
end
local function vector(v)local r={}for _,x in ipairs(v)do r[#r+1]=x end return r end
local function record(name)
 pointer(400,400);capture('unit-expel-'..name)
 local rows={}
 for y=0,g.dimy-1 do
  local chars={}
  for x=0,g.dimx-1 do local pen=dfhack.screen.readTile(x,y);chars[#chars+1]=pen.ch>=32 and pen.ch<=255 and string.char(pen.ch) or ' ' end
  local text=dfhack.df2utf(table.concat(chars)):gsub('%s+$','')
  if text~=''then rows[#rows+1]={y=y,text=text}end
 end
 observations[#observations+1]={name=name,open=sheet.open,active_id=sheet.active_id,
  expelling=sheet.unit_overview_expelling,reason=sheet.unit_overview_expel_cannot_expel_reason,
  selected_destination=sheet.unit_overview_expel_selected_dest_stid,
  destinations=vector(sheet.unit_overview_expel_dest_stid),units=vector(sheet.unit_overview_expel_total_unid),rows=rows}
 assert(df.global.pause_state and df.global.world.frame_counter==frame,'Expel navigation advanced simulation')
end
local ok,err=xpcall(function()
 assert(sheet.open and sheet.active_id==unit.id,'Expected native unit sheet')
 local hit
 for y=64,136,12 do for x=792,888,8 do
  pointer(x,y)
  if main.current_hover==df.main_hover_instruction.EXPEL_UNIT then hit={x,y};break end
 end if hit then break end end
 assert(hit,'Expel hitbox not found')
 observations[#observations+1]={name='hitbox',mouse=hit}
 df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
 assert(sheet.unit_overview_expelling,'Expel did not open')
 record('open')
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
 assert(not sheet.unit_overview_expelling and sheet.open and sheet.active_id==unit.id,'Expel cancel did not restore Overview')
 record('cancel')
 if os.getenv('DF3D_UNIT_EXPEL_REFUSALS')=='1' then
  local positions=dfhack.units.getNoblePositions(unit)
  assert(positions and #positions>0,'Refusal fixture needs an existing native office')
  local position=positions[1].position
  changed_positions[1]={position=position,elected=position.flags.ELECTED,hereditary=position.flags.SUCCESSION_BY_HEIR}
  for _,case in ipairs{{'elected',true,false,1},{'hereditary',false,true,0},{'both',true,true,1}}do
   position.flags.ELECTED=case[2];position.flags.SUCCESSION_BY_HEIR=case[3]
   pointer(856,100);df.global.enabler.mouse_lbut_lift=0
   gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
   df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
   assert(sheet.unit_overview_expelling and sheet.unit_overview_expel_cannot_expel_reason==case[4],'Native office refusal differs')
   record(case[1])
   gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
   assert(not sheet.unit_overview_expelling and sheet.open and sheet.active_id==unit.id,'Refusal cancel lost unit')
  end
  restore_positions()
 end
end,debug.traceback)
restore_positions()
if sheet.unit_overview_expelling then gui.simulateInput(view,'LEAVESCREEN')end
pointer(400,400)
local result={success=ok,unit_id=unit.id,observations=observations,error=not ok and err or nil}
local f=assert(io.open(out..'/unit-expel-native.json','w'));f:write(json.encode(result));f:close()
assert(ok,err);return result
