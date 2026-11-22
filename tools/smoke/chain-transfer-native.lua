-- Disposable, paused native oracle. Never used by runtime assignment code.
local target,animal,probe,native_select=...
local json=require('json')
local world=df.global.world
local cage=assert(world.buildings.other.CAGE[0])
local zone=assert(world.buildings.other.ANY_ZONE[0])
local worker,item
for _,u in ipairs(world.units.active)do if dfhack.units.isCitizen(u) and not u.job.current_job then worker=u;break end end
for _,i in ipairs(world.items.all)do if not i.flags.in_job and #i.specific_refs==0 then item=i;break end end
assert(worker and item,'Transfer fixture needs idle worker and unreserved item')
local source=df.building_chainst:new()
source.id=df.global.building_next_id;df.global.building_next_id=source.id+1
source.centerx=target.centerx;source.centery=target.centery;source.z=target.z
source.x1=target.x1;source.x2=target.x2;source.y1=target.y1;source.y2=target.y2
world.buildings.all:insert('#',source);world.buildings.other.CHAIN:insert('#',source)
local function remove_id(values,id)
 for i=#values-1,0,-1 do if values[i]==id then values:erase(i)end end
end
local function contains(values,id)for _,v in ipairs(values)do if v==id then return true end end;return false end
local function job(holder,kind)
 local j=df.job:new();j.job_type=kind;j.posting_index=-1
 local ref=df.general_ref_building_holderst:new();ref.building_id=holder.id;j.general_refs:insert('#',ref)
 assert(dfhack.job.linkIntoWorld(j,true));holder.jobs:insert('#',j);return j
end
local function exists(id)
 for _,value in require('utils').listpairs(world.jobs.list)do if value.id==id then return true end end
 return false
end
local function zone_refs()
 local count=0
 for _,ref in ipairs(animal.general_refs)do
  if ref:getType()==df.general_ref_type.BUILDING_CIVZONE_ASSIGNED and ref:getBuilding()==zone then count=count+1 end
 end
 return count
end
local function reset()
 while #source.jobs>0 do assert(dfhack.job.removeJob(source.jobs[0]))end
 while #target.jobs>0 do assert(dfhack.job.removeJob(target.jobs[0]))end
 source.assigned=nil;source.chained=nil;target.assigned=nil;target.chained=nil
 remove_id(cage.assigned_units,animal.id);remove_id(zone.assigned_units,animal.id)
 for i=#animal.general_refs-1,0,-1 do local ref=animal.general_refs[i]
  if ref:getType()==df.general_ref_type.BUILDING_CIVZONE_ASSIGNED and ref:getBuilding()==zone then animal.general_refs:erase(i);ref:delete()end
 end
end
local function scenario(owned)
 assert(not contains(cage.assigned_units,animal.id) and not contains(zone.assigned_units,animal.id) and zone_refs()==0)
 source.assigned=animal;source.chained=animal;target.chained=animal
 cage.assigned_units:insert('#',animal.id);zone.assigned_units:insert('#',animal.id)
 local ref=df.general_ref_building_civzone_assignedst:new();ref.building_id=zone.id;animal.general_refs:insert('#',ref)
 local cancelled=job(source,df.job_type.ChainAnimal);local cancelled_id=cancelled.id
 local retained=job(source,df.job_type.UnchainAnimal).id
 local unchain=job(target,df.job_type.UnchainAnimal).id
 assert(dfhack.job.addWorker(cancelled,worker))
 assert(dfhack.job.attachJobItem(cancelled,item,df.job_role_type.Hauled,-1,-1))
 if owned then
  local before=probe();local edit=probe(before.revision,animal.id,0)
  assert(edit.outcome==1 and edit.effects_started)
  assert(#edit.occupants==1 and edit.occupants[1].assigned and edit.occupants[1].contained and edit.occupants[1].status=='Assigned and chained')
 else native_select()end
 local result={assigned=target.assigned and target.assigned.id or -1,chained=target.chained and target.chained.id or -1,
  source_assigned=source.assigned and source.assigned.id or -1,source_chained=source.chained and source.chained.id or -1,
  cage_member=contains(cage.assigned_units,animal.id),zone_member=contains(zone.assigned_units,animal.id),zone_refs=zone_refs(),
  cancelled_exists=exists(cancelled_id),retained_exists=exists(retained),unchain_exists=exists(unchain),
  source_jobs=#source.jobs,target_jobs=#target.jobs,worker_job=worker.job.current_job and worker.job.current_job.id or -1,
  item_in_job=item.flags.in_job,item_refs=#item.specific_refs}
 assert(result.assigned==animal.id and result.chained==animal.id and result.source_assigned==-1 and result.source_chained==animal.id)
 assert(not result.cage_member and not result.zone_member and result.zone_refs==0)
 assert(not result.cancelled_exists and result.retained_exists and not result.unchain_exists)
 assert(result.source_jobs==1 and result.target_jobs==0 and result.worker_job==-1 and not result.item_in_job and result.item_refs==0)
 reset();return result
end
local ok,result=xpcall(function()
 local native=scenario(false);local owned=scenario(true)
 assert(json.encode(native)==json.encode(owned),'Owned transfer differs from native effects')
 return {native=native,owned=owned,success=true}
end,debug.traceback)
reset()
for _,values in ipairs{world.buildings.all,world.buildings.other.CHAIN}do
 for i=#values-1,0,-1 do if values[i]==source then values:erase(i)end end
end
source:delete()
assert(ok,result)
return result
