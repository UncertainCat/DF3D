-- Protected paused-clone oracle: exercise native and owned toggles, restore all
-- pending reports before returning. Optional controlled jobs never advance simulation.
local view,probe,settle,click,capture,unit_id=...
local json=require('json');local crime=df.crime.find(9)
local function reports()
 local rows={}
 for _,r in ipairs(crime.reports)do
  local identities={};for _,id in ipairs(r.all_witnessed_ident)do identities[#identities+1]=id end
  rows[#rows+1]={hfid=r.hfid,visual_hfid=r.visual_hfid,historical_hfid=r.historical_hfid,identities=identities}
 end
 return rows
end
local function selected()
 for _,r in ipairs(probe('justice-candidate-facts-probe',9))do if r.unit_id==unit_id then return (r.flags&1)~=0 end end
 error('Interrogation unit vanished')
end
local before=reports();assert(not selected(),'Fixture requires unselected first candidate')
click(808,190);assert(selected(),'Native interrogation checkbox did not schedule')
local native_on=reports();assert(#native_on==#before+1,'Native interrogation did not add exactly one report')
capture('justice-interrogation-selected')
click(808,190);assert(not selected(),'Native interrogation checkbox did not cancel')
local native_off=reports();assert(json.encode(native_off)==json.encode(before),'Native interrogation did not restore reports')
assert(probe('justice-interrogation-probe',{'9',tostring(unit_id),'0'},true)==2,'Owned interrogation scheduling failed')
local owned_on=reports();assert(selected(),'Owned interrogation was not selected')
assert(json.encode(owned_on)==json.encode(native_on),'Owned interrogation report differs from native')
assert(probe('justice-interrogation-probe',{'9',tostring(unit_id),'0'},true)==1,'Stale repeated interrogation was not rejected')
assert(json.encode(reports())==json.encode(owned_on),'Rejected interrogation changed reports')
assert(probe('justice-interrogation-probe',{'9',tostring(unit_id),'1'},true)==2,'Owned interrogation cancellation failed')
local owned_off=reports();assert(not selected(),'Owned interrogation stayed selected')
assert(json.encode(owned_off)==json.encode(before),'Owned interrogation did not restore reports')
local result={crime_id=9,unit_id=unit_id,before=before,native_on=native_on,native_off=native_off,owned_on=owned_on,owned_off=owned_off,stale_toggle_rejected=true}
if os.getenv('DF3D_JUSTICE_INTERROGATION_JOBS')=='1' then
 local utils=require('utils');assert(df.global.pause_state)
 local worker,other
 for _,u in ipairs(df.global.world.units.active)do
  if u.id~=unit_id and dfhack.units.isCitizen(u) and not u.job.current_job then
   if not worker then worker=u elseif not other then other=u;break end
  end
 end
 assert(worker and other,'Need two idle citizens for controlled interview jobs')
 local function find(id)for _,job in utils.listpairs(df.global.world.jobs.list)do if job.id==id then return job end end end
 local original_ids={};for _,job in utils.listpairs(df.global.world.jobs.list)do
  original_ids[#original_ids+1]=job.id
  assert(job.job_type~=df.job_type.InterrogateSubject,'Fixture already has an interview job')
 end
 local next_id=df.global.job_next_id;local created={}
 local function make(kind,subjects,assigned)
  local job=df.job:new();job.job_type=kind;job.posting_index=-1;job.pos:assign(worker.pos)
  for _,id in ipairs(subjects)do local ref=df.general_ref_unit_interrogateest:new();ref.unit_id=id;job.general_refs:insert('#',ref)end
  assert(dfhack.job.linkIntoWorld(job,true));created[#created+1]=job.id
  if assigned then assert(dfhack.job.addWorker(job,worker))end
  return job.id
 end
 local function remaining(ids)local values={};for _,id in ipairs(ids)do values[#values+1]=find(id)~=nil end;return values end
 local ok,err=xpcall(function()
  result.jobs={worker=worker.id,other_subject=other.id,cases={}}
  local reference
  for _,mode in ipairs{'native','owned'}do
   -- Rebuild native selection for both arms; only cancellation differs.
   click(808,190);assert(selected())
   local ids={make(df.job_type.InterrogateSubject,{unit_id},true),
    make(df.job_type.InterrogateSubject,{other.id},false),
    make(df.job_type.InterrogateSubject,{other.id,unit_id},false),
    make(df.job_type.InterrogateSubject,{unit_id,other.id},false),
    make(df.job_type.ReportCrime,{unit_id},false)}
   assert(worker.job.current_job and worker.job.current_job.id==ids[1])
   if mode=='native' then click(808,190)
   else assert(probe('justice-interrogation-probe',{'9',tostring(unit_id),'1'},true)==2)end
   local after={remaining=remaining(ids),worker_released=worker.job.current_job==nil,selected=selected(),reports=reports()}
   result.jobs.cases[#result.jobs.cases+1]={mode=mode,after=after}
   assert(json.encode(after.remaining)==json.encode({false,true,true,false,true}),'Wrong interview jobs cancelled')
   assert(after.worker_released and not after.selected and json.encode(after.reports)==json.encode(before),'Interview cancellation did not release state')
   if reference then assert(json.encode(reference)==json.encode(after),'Owned running-job cleanup differs from native')else reference=after end
   for _,id in ipairs(ids)do local job=find(id);if job then assert(dfhack.job.removeJob(job))end end
  end
 end,debug.traceback)
 for _,id in ipairs(created)do local job=find(id);if job then assert(dfhack.job.removeJob(job))end end
 df.global.job_next_id=next_id
 assert(ok,err)
 local final_ids={};for _,job in utils.listpairs(df.global.world.jobs.list)do final_ids[#final_ids+1]=job.id end
 assert(json.encode(original_ids)==json.encode(final_ids),'Interview fixture changed original job membership')
 result.jobs.original_jobs_preserved=true;result.jobs.job_id_counter_restored=true
end
return result
