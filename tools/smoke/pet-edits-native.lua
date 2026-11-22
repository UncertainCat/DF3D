-- Protected disposable oracle: viewport positioning is fixture setup. Gameplay
-- effects come from real native clicks; all targets are restored before return.
local out,view,list,samples,callbacks=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local cases={};local chosen={}
local training=os.getenv('DF3D_PET_TRAINING_EDITS')=='1'
local fixture_id
if training then
 local f=assert(io.open(out..'/pet-trainer-fixture.json'));fixture_id=json.decode(f:read('*a')).id;f:close()
end
for _,sample in ipairs(samples)do
 for _,action in ipairs(sample.provider.actions)do
  local key=sample.kind..':'..action
  if ((not training and action<=2) or (training and sample.id==fixture_id and (action==4 or action==5))) and not chosen[key] then cases[#cases+1]={kind=sample.kind,id=sample.id,action=action};chosen[key]=true end
 end
end
assert(training and chosen['0:4'] and chosen['0:5'] or not training and chosen['0:0'] and chosen['0:1'] and chosen['0:2'] and chosen['1:1'],'Pet edit fixture lacks an action family')
local function read(case,revision,desired)
 local args={'df3d','pet-edit-probe',tostring(case.kind),tostring(case.id)}
 if revision then args[#args+1]=revision;args[#args+1]=tostring(case.action);args[#args+1]=desired and '1' or '0'end
 local text,rc=dfhack.run_command_silent(table.unpack(args));assert(rc==0,text);return json.decode(text)
end
local function snapshot(target,kind)
 if training then
  local assignment=df.training_assignment.find(target.id)
  local result={flags={target.flags1.whole,target.flags2.whole,target.flags3.whole},assignment=assignment and {assignment.trainer_id,assignment.flags.whole} or false,traits={}}
  for _,unit in ipairs(df.global.world.units.active)do
   local row={id=unit.id,values={}}
   for _,trait in ipairs(unit.status.misc_traits)do row.values[#row.values+1]={trait.id,trait.value}end
   result.traits[#result.traits+1]=row
  end
  return result
 end
 if kind==0 then return {target.flags1.whole,target.flags2.whole,target.flags3.whole}end
 return {target.flags.whole,target.pet_flags.whole,target.owner_id}
end
local function restore(target,kind,value)
 if training then
  target.flags1.whole=value.flags[1];target.flags2.whole=value.flags[2];target.flags3.whole=value.flags[3]
  local assignment=df.training_assignment.find(target.id)
  if value.assignment then
   assert(assignment);assignment.trainer_id=value.assignment[1];assignment.flags.whole=value.assignment[2]
  elseif assignment then
   local assignments=df.global.plotinfo.training.training_assignments
   for index,entry in ipairs(assignments)do if entry.animal_id==target.id then assignments:erase(index);entry:delete();break end end
  end
  for _,row in ipairs(value.traits)do
   local traits=df.unit.find(row.id).status.misc_traits
   for index=#traits-1,0,-1 do if traits[index].id==df.misc_trait_type.AnimalTrainCheck then local old=traits[index];traits:erase(index);old:delete()end end
   for ordinal,entry in ipairs(row.values)do
    if entry[1]==df.misc_trait_type.AnimalTrainCheck then
     local trait=df.unit_misc_trait:new();trait.id=entry[1];trait.value=entry[2];traits:insert(ordinal-1,trait)
    end
   end
  end
  return
 end
 if kind==0 then target.flags1.whole=value[1];target.flags2.whole=value[2];target.flags3.whole=value[3]
 else target.flags.whole=value[1];target.pet_flags.whole=value[2];target.owner_id=value[3]end
end
local function position(case)
 local function find(widget)
  if df.widget_scroll_rows:is_instance(widget)then
   local rows=dfhack.gui.getWidgetChildren(widget)
   for ordinal,row in ipairs(rows)do
    for _,child in ipairs(dfhack.gui.getWidgetChildren(row))do
     if (case.kind==0 and df.widget_unit_portrait:is_instance(child) and child.u and child.u.id==case.id) or
        (case.kind==1 and df.widget_item_portrait:is_instance(child) and child.i and child.i.id==case.id) then
      widget.scroll=math.max(0,math.min(ordinal-1,#rows-widget.num_visible));return true
     end
    end
   end
  end
  if df.widget_container:is_instance(widget)then for _,child in ipairs(dfhack.gui.getWidgetChildren(widget))do if find(child)then return true end end end
 end
 assert(find(list),'Pet row not found')
 for _=1,3 do script.sleep(1,'frames')end
 view:render(dfhack.getTickCount())
end
local function button(case)
 local root
 local function find(widget)
  if (case.kind==0 and df.widget_unit_portrait:is_instance(widget) and widget.u and widget.u.id==case.id) or
     (case.kind==1 and df.widget_item_portrait:is_instance(widget) and widget.i and widget.i.id==case.id)then root=widget.parent end
  if df.widget_container:is_instance(widget)then for _,child in ipairs(dfhack.gui.getWidgetChildren(widget))do find(child)end end
 end
 find(list);assert(root)
 local wanted=case.kind==1 and 0x3d0a90 or ({[0]=0x3d0ca0,[1]=0x3d0e50,[2]=0x3d0c40,[4]=0x3d1460,[5]=0x3d1280})[case.action]
 local result
 local function find_action(widget)
  for _,target in ipairs(callbacks(widget.custom_activated,64))do if target==wanted then result=widget end end
  if df.widget_container:is_instance(widget)then for _,child in ipairs(dfhack.gui.getWidgetChildren(widget))do find_action(child)end end
 end
 find_action(root);return assert(result,'Pet native action missing')
end
local evidence={}
for _,case in ipairs(cases)do
 local target=case.kind==0 and df.unit.find(case.id) or df.item.find(case.id)
 local original=snapshot(target,case.kind)
 local ok,err=pcall(function()
  if training then
   -- Controlled cache fixture: prove the native global invalidation effect,
   -- including units other than the animal. Restore these entries before exit.
   for index=0,1 do
    local unit=df.global.world.units.active[index];assert(unit)
    local found=false
    for _,trait in ipairs(unit.status.misc_traits)do if trait.id==df.misc_trait_type.AnimalTrainCheck then found=true end end
    if not found then local trait=df.unit_misc_trait:new();trait.id=df.misc_trait_type.AnimalTrainCheck;trait.value=123+index;unit.status.misc_traits:insert('#',trait)end
   end
  end
  local directions={}
  for direction=1,(training and 3 or 2) do
   if training and direction==3 then
    local assignment=assert(df.training_assignment.find(case.id))
    assignment.flags.train_war=case.action==5;assignment.flags.train_hunt=case.action==4
   end
   position(case);local control=button(case);local before=snapshot(target,case.kind);local receipt=read(case)
   local desired=not receipt.values[case.action+1]
   local x=math.floor((control.rect.x1+control.rect.x2)/2);local y=math.floor((control.rect.y1+control.rect.y2)/2)
   local g=df.global.gps;g.precise_mouse_x=x*8+4;g.precise_mouse_y=y*12+6;g.mouse_x=x;g.mouse_y=y
   df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
   gui.simulateInput(view,'_MOUSE_L')
   df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
   for _=1,3 do script.sleep(1,'frames')end
   local native=snapshot(target,case.kind);assert(json.encode(native)~=json.encode(before),'Native pet click had no effect')
   restore(target,case.kind,before)
   local applied=read(case,receipt.revision,desired)
   assert(applied.outcome==0 and json.encode(snapshot(target,case.kind))==json.encode(native),'Pet edit differs from native')
   local stale=read(case,receipt.revision,not desired);assert(stale.outcome==2,'Stale pet edit accepted')
   local duplicate=read(case,applied.revision,desired);assert(duplicate.outcome==1,'Duplicate pet edit accepted')
   assert(json.encode(snapshot(target,case.kind))==json.encode(native),'Rejected pet edit changed target')
   directions[#directions+1]={before=before,native=native,provider=applied,stale=stale.outcome,duplicate=duplicate.outcome}
  end
  if training then restore(target,case.kind,original)end
  evidence[#evidence+1]={kind=case.kind,id=case.id,action=case.action,directions=directions,restored=json.encode(snapshot(target,case.kind))==json.encode(original)}
 end)
 restore(target,case.kind,original)
 assert(ok,err)
end
local f=assert(io.open(out..'/pet-edits-reference.json','w'));f:write(json.encode(evidence));f:close()
for _,case in ipairs(evidence)do assert(case.restored,'Pet toggle pair did not restore original state')end
