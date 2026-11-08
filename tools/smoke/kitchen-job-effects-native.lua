-- Controlled jobs in the paused, owned clone only. Never a runtime provider.
local out,view,panel,click,known=...
local script=require('gui.script');local json=require('json');local utils=require('utils')
assert(df.global.pause_state)
local target;for _,row in ipairs(known)do if row.name=='Plump helmets'then target=row end end;assert(target)
local item
for _,value in ipairs(df.global.world.items.other.ANY_COOKABLE)do
 if value:getType()==target.type and value:getSubtype()==target.subtype and value:getMaterial()==target.mat and value:getMaterialIndex()==target.matg and not value.flags.in_job and (value.flags.whole&0xe98f30)==0 then item=value;break end
end
assert(item,'No free native Kitchen ingredient')
local function exclusions()
 local k=df.global.plotinfo.kitchen;local rows={}
 for i,t in ipairs(k.item_types)do rows[#rows+1]={type=t,subtype=k.item_subtypes[i],mat=k.mat_types[i],matg=k.mat_indices[i],flags=k.exc_types[i].whole}end
 return rows
end
local function prohibited(flag)
 for _,row in ipairs(exclusions())do if row.type==target.type and row.subtype==target.subtype and row.mat==target.mat and row.matg==target.matg and (row.flags&flag)~=0 then return true end end
 return false
end
local original={prohibited(1),prohibited(2)}
panel.filter_type=-1;panel.filter_perm=0;panel.filter_str='plump';panel.sort_flags=panel.sort_flags|1
for _=1,3 do script.sleep(1,'frames');view:render(dfhack.getTickCount())end
local function native_toggle(flag)
 local y
 local function walk(widget)
  if df.widget_text:is_instance(widget) and dfhack.df2utf(widget.str)==target.name then y=widget.rect.y1 end
  if df.widget_container:is_instance(widget)then for _,child in ipairs(dfhack.gui.getWidgetChildren(widget))do walk(child)end end
 end
 walk(panel);assert(y);local before=prohibited(flag);click(flag==1 and 90 or 94,y);assert(prohibited(flag)~=before,'Native permission click missed')
end
local worker
for _,unit in ipairs(df.global.world.units.active)do if dfhack.units.isCitizen(unit) and not unit.job.current_job then worker=unit;break end end
assert(worker,'No idle worker for native cancellation check')
local function find_job(id)for _,job in utils.listpairs(df.global.world.jobs.list)do if job.id==id then return job end end end
local function make_job(flag,with_item,assigned)
 local job=df.job:new();job.job_type=flag==1 and df.job_type.PrepareMeal or df.job_type.CustomReaction;job.posting_index=-1
 job.pos:assign(item.pos)
 if flag==2 then
  job.reaction_name='BREW_DRINK_FROM_PLANT'
  local requirement=df.job_item:new();requirement.item_type=target.type;requirement.item_subtype=target.subtype
  requirement.mat_type=target.mat;requirement.mat_index=target.matg;requirement.quantity=1;requirement.reagent_index=0
  job.job_items.elements:insert('#',requirement)
 end
 assert(dfhack.job.linkIntoWorld(job,true))
 if with_item then assert(dfhack.job.attachJobItem(job,item,df.job_role_type.Hauled,0,-1))end
 if assigned then
  local holder
  for _,building in ipairs(df.global.world.buildings.all)do
   if df.building_workshopst:is_instance(building) and building.type==(flag==1 and df.workshop_type.Kitchen or df.workshop_type.Still) and building:getBuildStage()==building:getMaxBuildStage()then holder=building;break end
  end
  assert(holder,'No native kitchen/still workshop')
  local ref=df.general_ref_building_holderst:new();ref.building_id=holder.id;job.general_refs:insert('#',ref);holder.jobs:insert('#',job)
  assert(dfhack.job.addWorker(job,worker))
 end
 return job.id
end
local function state(id)local job=find_job(id);if not job then return {exists=false}end;return {exists=true,flags=job.flags.whole,item_lost=job.flags.item_lost,items=#job.items}end
local result={item_id=item.id,cases={}}
for flag=1,2 do
 for _,assigned in ipairs({false,true})do
 local reference
 for _,mode in ipairs({'native','provider'})do
  if prohibited(flag)then native_toggle(flag)end
  local affected=make_job(flag,true,assigned);local control=make_job(flag,false,false)
  local before={affected=state(affected),control=state(control)}
  if mode=='native'then native_toggle(flag)else
   local text,code=dfhack.run_command_silent('df3d','kitchen-edit-probe',tostring(flag),json.encode({target=target,exclusions=exclusions()}));assert(code==0)
   local reply=json.decode(text);assert(reply.outcome==1 and reply.write_started,'Owned job-effect edit failed')
  end
  local after={affected=state(affected),control=state(control),worker_has_job=worker.job.current_job~=nil,item_reserved=item.flags.in_job}
  result.cases[#result.cases+1]={flag=flag,mode=mode,assigned=assigned,before=before,after=after}
  local f=assert(io.open(out..'/kitchen-job-effects.json','w'));f:write(json.encode(result));f:close()
  assert(not after.control.item_lost,'Native edit changed empty control')
  if assigned then assert(not after.worker_has_job,'Native edit did not release worker')
  else assert(after.affected.item_lost,'Native edit did not invalidate ingredient job')end
  if reference then assert(json.encode(after)==json.encode(reference),'Owned job effect differs from native')else reference=after end
  local remaining=find_job(affected);if remaining then assert(dfhack.job.removeJob(remaining))end
  assert(dfhack.job.removeJob(assert(find_job(control))));assert(not item.flags.in_job)
 end
 end
 if prohibited(flag)~=original[flag]then native_toggle(flag)end
end
local f=assert(io.open(out..'/kitchen-job-effects.json','w'));f:write(json.encode(result));f:close()
panel.filter_str='';panel.sort_flags=panel.sort_flags|1
for _=1,3 do script.sleep(1,'frames');view:render(dfhack.getTickCount())end
