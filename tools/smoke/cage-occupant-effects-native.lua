-- Compare the parent checkbox effects with independently owned semantic edits.
local out,view,cage,capture=...
local json=require('json');local g=df.global.gps
local function call(command,...)
 local text,code=dfhack.run_command_silent('df3d',command,tostring(cage.id),...)
 assert(code==0,text);return json.decode(text)
end
local function ids(v)local t={};for _,id in ipairs(v)do t[#t+1]=id end;return t end
local function refs(v)
 local t={};for _,r in ipairs(v)do t[#t+1]={type=r:getType(),id=r:getID()}end;return t
end
local initial=call('cage-state-probe');local unit
for _,row in ipairs(initial.rows)do if row.kind==0 and not row.assigned then unit=df.unit.find(row.id);break end end
assert(unit and #cage.assigned_units==0)
local body=call('cage-occupants-read');assert(#body.rows==1 and body.rows[1].entity==2 and body.rows[1].contained and body.rows[1].assigned)
local item=assert(df.item.find(body.rows[1].id))
local frame=df.global.world.frame_counter;local flags=cage.cage_flags.whole
local function state()
 return {units=ids(cage.assigned_units),items=ids(cage.assigned_items),flags=cage.cage_flags.whole,
  jobs=#cage.jobs,unit={flags1=unit.flags1.whole,flags2=unit.flags2.whole,flags3=unit.flags3.whole,
   flags4=unit.flags4.whole,job=unit.job.current_job and unit.job.current_job.id or -1,refs=refs(unit.general_refs)},
  item={flags=item.flags.whole,refs=refs(item.general_refs)}}
end
local original=state();local result={building_id=cage.id,unit_id=unit.id,item_id=item.id,native={},owned={}}
local function setup()
 local current=call('cage-state-probe')
 assert(call('cage-state-probe',tostring(current.revision),tostring(unit.id),'0','1').outcome==1)
 cage.cage_flags.whole=flags
end
local function click(y)
 g.precise_mouse_x=864;g.precise_mouse_y=y;g.mouse_x=108;g.mouse_y=(y-4)//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 require('gui').simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
end
local function owned(id,isitem,value)
 local before=call('cage-occupants-read');local guards={}
 for _,v in ipairs{g,df.global.game.main_interface}do
  local size,address=df.sizeof(v);local copy=df.new('uint8_t',size)
  dfhack.internal.memmove(copy,address,size);guards[#guards+1]={copy=copy,address=address,size=size}
 end
 local receipt=call('cage-occupants-probe',tostring(before.revision),tostring(id),isitem and '1'or'0',value and '1'or'0')
 for _,guard in ipairs(guards)do
  assert(dfhack.internal.memcmp(guard.copy,guard.address,guard.size)==0,'Parent edit changed native UI storage');df.delete(guard.copy)
 end
 assert(receipt.outcome==1 and receipt.effects_started,'Parent effect failed: '..json.encode(receipt))
 local after=state()
 local stale=call('cage-occupants-probe',tostring(before.revision),tostring(id),isitem and '1'or'0',value and '0'or'1')
 assert(stale.outcome==2 and not stale.effects_started and json.encode(after)==json.encode(state()))
 return {state=after,receipt=receipt,stale=stale}
end
setup();view:render(dfhack.getTickCount());result.before=state()
click(190);assert(#cage.assigned_units==0);result.native.unit_removed=state()
capture('cage-parent-effects-unit-removed')
click(154);result.blank_item_click=state()
assert(json.encode(result.blank_item_click)==json.encode(result.native.unit_removed),'Blank item row unexpectedly changed assignment')
-- Controlled assigned-only item: remove only the containing object's reference,
-- preserving its allocation for exact restoration after the comparison.
local container=cage.contained_items[0].item;local saved_refs={}
for _,ref in ipairs(container.general_refs)do saved_refs[#saved_refs+1]=ref end
for i=#container.general_refs-1,0,-1 do
 local ref=container.general_refs[i]
 if ref:getType()==df.general_ref_type.CONTAINS_ITEM and ref:getID()==item.id then container.general_refs:erase(i)end
end
view:render(dfhack.getTickCount());capture('cage-parent-effects-assigned-item')
click(154);result.native.item_removed=state()
assert(#cage.assigned_items==0,'Native assigned-only item checkbox did not remove assignment')
capture('cage-parent-effects-item-removed')
local function restore_item()
 local current=call('cage-state-probe')
 assert(call('cage-state-probe',tostring(current.revision),tostring(item.id),'1','1').outcome==1)
end
restore_item()
setup();assert(json.encode(result.before)==json.encode(state()),'Comparison setup differs')
result.owned.unit_removed=owned(unit.id,false,false)
result.owned.item_removed=owned(item.id,true,false)
for name,expected in pairs(result.native)do assert(json.encode(expected)==json.encode(result.owned[name].state),'Native/owned mismatch: '..name)end
restore_item()
for i=#container.general_refs-1,0,-1 do container.general_refs:erase(i)end
for _,ref in ipairs(saved_refs)do container.general_refs:insert('#',ref)end
cage.cage_flags.whole=flags
assert(json.encode(original)==json.encode(state()),'Parent effects did not restore simulation')
assert(frame==df.global.world.frame_counter)
result.success=true;result.restored=true
local f=assert(io.open(out..'/cage-occupant-effects-native.json','w'));f:write(json.encode(result));f:close()
