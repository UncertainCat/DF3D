-- Paused simulation-field variants; no claim of natural freeze or power transitions.
local out,view,select_map,capture,selected=...
local gui=require('gui');local json=require('json')
local sheet=df.global.game.main_interface.view_sheets
local pump=assert(selected[df.building_type.ScrewPump])
local gear=assert(selected[df.building_type.GearAssembly])
local wheel=assert(selected[df.building_type.WaterWheel])
local info=wheel:getMachineInfo();local machine=assert(df.machine.find(info.machine_id))
local before={direction=pump.direction,gear=gear.gear_flags.whole,info=info.flags.whole,machine=machine.flags.whole}
local result={cases={}}
local ok,err=xpcall(function()
 for step=1,3 do
  pump.direction=step;gear.gear_flags.disengaged=step==1
  machine.flags.active=false;machine.flags.frozen=step>1;info.flags.frozen=step==3
  local row={buildings={}}
  for _,b in ipairs{pump,gear,wheel}do
   if sheet.open then gui.simulateInput(view,'LEAVESCREEN')end
   view:render(dfhack.getTickCount());select_map(b)
   assert(sheet.open and sheet.active_id==b.id)
   local reference='machinery-variant-'..step..'-'..b:getType()
   capture(reference)
   local text,code=dfhack.run_command_silent('df3d','machinery-body-probe',tostring(b.id));assert(code==0,text)
   row.buildings[#row.buildings+1]={id=b.id,type=b:getType(),reference=reference,semantic=json.decode(text)}
  end
  local f=assert(io.open(out..'/machinery-variant-expected.json','w'));f:write(json.encode(row));f:close()
  local active_id=sheet.active_id;local label='machinery-variant-wire-'..step
  capture(label)
  f=assert(io.open(out..'/'..label..'-result.json'));row.viewer=json.decode(f:read('*a'));f:close()
  assert(row.viewer.success and sheet.active_id==active_id)
  assert(pump.direction==step and gear.gear_flags.disengaged==(step==1))
  assert(not machine.flags.active and machine.flags.frozen==(step>1) and info.flags.frozen==(step==3))
  result.cases[#result.cases+1]=row
 end
end,debug.traceback)
pump.direction=before.direction;gear.gear_flags.whole=before.gear
info.flags.whole=before.info;machine.flags.whole=before.machine
assert(ok,err);result.restored=true
return result
