-- Paused display variants; no claim of natural mechanism or pathing transitions.
local out,view,select_map,capture,rows=...
local gui=require('gui');local json=require('json')
local sheet=df.global.game.main_interface.view_sheets
local selected={};local before={};local created
for _,row in ipairs(rows)do
 local b=assert(df.building.find(row.id));selected[row.type]=b
 before[row.type]={flags=(row.type==35 and b.door_flags or b.gate_flags).whole,timer=row.type==35 and b.close_timer or 0}
end
local result={cases={}}
local ok,err=xpcall(function()
 local worker
 for _,u in ipairs(df.global.world.units.active)do if dfhack.units.isCitizen(u)then worker=u;break end end
 local iron=assert(dfhack.matinfo.find('INORGANIC:IRON'))
 local items=dfhack.items.createItem(assert(worker),df.item_type.GRATE,-1,iron.type,iron.index)
 assert(#items==1);created=items[1];assert(dfhack.items.moveToBuilding(created,selected[36],2,true))
 for step=1,2 do
  local expected={buildings={}}
  for kind=35,39 do
   local b=selected[kind]
   if kind==35 then b.door_flags.closed=step==1;b.door_flags.operated_by_mechanisms=true;b.close_timer=step==2 and 10 or 0
   else b.gate_flags.closed=step==1 end
   if sheet.open then gui.simulateInput(view,'LEAVESCREEN')end
   view:render(dfhack.getTickCount());select_map(b)
   assert(sheet.open and sheet.active_id==b.id)
   local reference='barrier-variant-'..step..'-'..kind;capture(reference)
   expected.buildings[#expected.buildings+1]={id=b.id,type=kind,tile={b.centerx,b.centery,b.z},reference=reference,grate_open=step==2}
  end
  local f=assert(io.open(out..'/barrier-variant-expected.json','w'));f:write(json.encode(expected));f:close()
  local active=sheet.active_id;local label='barrier-variant-wire-'..step;capture(label)
  f=assert(io.open(out..'/'..label..'-result.json'));local receipt=json.decode(f:read('*a'));f:close()
  assert(receipt.success and sheet.active_id==active)
  result.cases[#result.cases+1]={step=step,viewer=receipt,buildings=expected.buildings}
 end
end,debug.traceback)
if created then created.flags.in_building=false;assert(dfhack.items.remove(created))end
for kind,b in pairs(selected)do
 (kind==35 and b.door_flags or b.gate_flags).whole=before[kind].flags
 if kind==35 then b.close_timer=before[kind].timer end
end
assert(ok,err);result.restored=true
return result
