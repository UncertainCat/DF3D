-- Paused disposable oracle for semantic firing-job cleanup.
local engine,probe,click=...
local json=require('json');local world=df.global.world
local worker,item
for _,u in ipairs(world.units.active)do if dfhack.units.isCitizen(u) and not u.job.current_job then worker=u;break end end
for _,i in ipairs(world.items.all)do if not i.flags.in_job and #i.specific_refs==0 then item=i;break end end
assert(worker and item,'Siege fixture needs idle worker and unreserved item')
assert(#engine.jobs==0)
local original=engine.action
local load=df.job_type[({'LoadCatapult','LoadBallista','LoadBoltThrower'})[engine.type+1]]
local fire=df.job_type[({'FireCatapult','FireBallista','FireBoltThrower'})[engine.type+1]]
local function job(kind)
 local value=df.job:new();value.job_type=kind;value.posting_index=-1
 value.pos={x=engine.centerx,y=engine.centery,z=engine.z}
 local ref=df.general_ref_building_holderst:new();ref.building_id=engine.id;value.general_refs:insert('#',ref)
 assert(dfhack.job.linkIntoWorld(value,true));engine.jobs:insert('#',value);return value
end
local function exists(id)
 for _,value in require('utils').listpairs(world.jobs.list)do if value.id==id then return true end end
 return false
end
local function scenario(owned,action)
 engine.action=3
 local retained=job(load).id;local firing=job(fire);local cancelled=firing.id
 local second=job(fire).id
 assert(dfhack.job.addWorker(firing,worker))
 assert(dfhack.job.attachJobItem(firing,item,df.job_role_type.Hauled,-1,-1))
 if owned then
  local before=probe(engine);local edit=probe(engine,before.revision,action,false)
  assert(edit.outcome==1 and edit.effects_started)
 else click(action==1 and 852 or 876,154)end
 local result={action=engine.action,loading=exists(retained),firing=exists(cancelled),second=exists(second),
  jobs=#engine.jobs,worker_free=worker.job.current_job==nil,item_reserved=item.flags.in_job,item_refs=#item.specific_refs}
 assert(result.action==action and result.loading and not result.firing and not result.second and result.jobs==1)
 assert(result.worker_free and not result.item_reserved and result.item_refs==0)
 assert(dfhack.job.removeJob(engine.jobs[0]));return result
end
local ok,result=xpcall(function()
 local rows={}
 for _,action in ipairs{1,0}do
  local native=scenario(false,action);local owned=scenario(true,action)
  assert(json.encode(native)==json.encode(owned),'Siege job effects differ')
  rows[#rows+1]={native=native,owned=owned}
 end
 return rows
end,debug.traceback)
while #engine.jobs>0 do assert(dfhack.job.removeJob(engine.jobs[0]))end
engine.action=original
assert(ok,result);return result
