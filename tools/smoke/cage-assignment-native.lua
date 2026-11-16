-- Compare ordinary unit/critter toggles in independent disposable native/owned runs.
local view,cage,list,mode=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local function contains(v,id)for _,value in ipairs(v)do if value==id then return true end end;return false end
local function snapshot(kind,id)
 local object=assert(kind==0 and df.unit.find(id)or df.item.find(id))
 local result={id=id,kind=kind,cages={},zones={},chains={},refs={}}
 for _,b in ipairs(df.global.world.buildings.other.CAGE)do
  if contains(kind==0 and b.assigned_units or b.assigned_items,id)then result.cages[#result.cages+1]=b.id end
 end
 for _,b in ipairs(df.global.world.buildings.other.ANY_ZONE)do
  if contains(kind==0 and b.assigned_units or b.assigned_items,id)then result.zones[#result.zones+1]=b.id end
 end
 for _,ref in ipairs(object.general_refs)do
  local row={kind=df.general_ref_type[ref:getType()]}
  if df.general_ref_building:is_instance(ref)then row.building_id=df.reinterpret_cast(df.general_ref_building,ref).building_id end
  result.refs[#result.refs+1]=row
 end
 if kind==0 then
  result.flags1=object.flags1.whole;result.flags2=object.flags2.whole
  result.job=object.job.current_job and object.job.current_job.id or -1
  for _,b in ipairs(df.global.world.buildings.other.CHAIN)do
   if b.assigned==object or b.chained==object then
    local jobs={};for _,job in ipairs(b.jobs)do jobs[#jobs+1]={id=job.id,type=df.job_type[job.job_type]}end
    result.chains[#result.chains+1]={id=b.id,assigned=b.assigned and b.assigned.id or -1,chained=b.chained and b.chained.id or -1,jobs=jobs}
   end
  end
 else result.flags=object.flags.whole end
 return result
end
local function row_y(widget,kind,id,depth)
 assert(depth<10)
 if kind==0 and df.widget_unit_name:is_instance(widget)and df.reinterpret_cast(df.widget_unit_name,widget).u.id==id then return widget.rect.y1 end
 if kind==1 and df.widget_item_name:is_instance(widget)and df.reinterpret_cast(df.widget_item_name,widget).it.id==id then return widget.rect.y1 end
 if not df.widget_container:is_instance(widget)then return end
 local _,address=df.sizeof(df.reinterpret_cast(df.widget_container,widget).children)
 local first=df.reinterpret_cast('uint64_t',address).value;local last=df.reinterpret_cast('uint64_t',address+8).value
 assert(last>=first and (last-first)%16==0 and last-first<=65536)
 for at=first,last-1,16 do
  local ptr=df.reinterpret_cast('uint64_t',at).value
  if ptr~=0 then local y=row_y(df.reinterpret_cast(df.widget,ptr),kind,id,depth+1);if y then return y end end
 end
end
local unit_id
for _,entry in ipairs(list.entry_list)do if entry.t==0 then
 local state=snapshot(0,entry.u.id)
 if #state.cages==0 and #state.zones==0 and #state.chains==0 then unit_id=entry.u.id;break end
end end
assert(unit_id,'No unassigned native candidate for cage effect fixture')
local item_id=assert(cage.assigned_items[0],'No assigned cage critter')
local function apply(kind,id,value)
 if mode=='native'then
  local y=assert(row_y(df.global.game.main_interface.unit_selector,kind,id,0),'Visible cage row absent')
  g.precise_mouse_x=344;g.precise_mouse_y=(y-1)*12+6;g.mouse_x=43;g.mouse_y=(g.precise_mouse_y-4)//12
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
  gui.simulateInput(view,'_MOUSE_L')
  df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
 else
  local function request(...)
   local text,code=dfhack.run_command_silent('df3d','cage-state-probe',tostring(cage.id),...)
   assert(code==0,text);return json.decode(text)
  end
  local before=request()
  local function edit(revision,desired)
   return request(tostring(revision),tostring(id),tostring(kind),desired and '1'or'0')
  end
  local response=edit(before.revision,value)
  assert(response.outcome==1 and response.effects_started,'Revisioned cage edit failed')
  assert(response.revision~=before.revision,'Cage edit did not change authority')
  local stale=edit(before.revision,not value)
  assert(stale.outcome==2 and not stale.effects_started,'Stale cage edit entered effects')
  local duplicate=edit(response.revision,value)
  assert(duplicate.outcome==1 and not duplicate.effects_started and duplicate.revision==response.revision,'Idempotent cage edit entered effects')
 end
 view:render(dfhack.getTickCount())
 assert(contains(kind==0 and cage.assigned_units or cage.assigned_items,id)==value,'Cage assignment effect differs')
 return snapshot(kind,id)
end
local result={unit_before=snapshot(0,unit_id),item_before=snapshot(1,item_id)}
result.unit_assigned=apply(0,unit_id,true)
result.unit_removed=apply(0,unit_id,false)
result.item_removed=apply(1,item_id,false)
result.item_assigned=apply(1,item_id,true)
assert(json.encode(result.unit_before)==json.encode(result.unit_removed),'Unit toggle did not restore fixture state')
assert(json.encode(result.item_before)==json.encode(result.item_assigned),'Item toggle did not restore fixture state')
return result
