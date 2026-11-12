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
local activation={}
local function activate()
 if os.getenv('DF3D_JUSTICE_SELECT')=='1' then
  local gui=require('gui')
  df.global.enabler.mouse_focus=true
  if os.getenv('DF3D_JUSTICE_SELECT_FOCUSED')=='1' then gui.simulateInput(view,'FILTER');settle()end
  local focused=df.global.gview.cur_textbox~=nil
  gui.simulateInput(view,'SELECT');settle()
  activation[#activation+1]={focused_before=focused,focused_after=df.global.gview.cur_textbox~=nil,selected_after=selected()}
 else click(808,190)end
end
activate();assert(selected(),'Native interrogation activation did not schedule')
local native_on=reports();assert(#native_on==#before+1,'Native interrogation did not add exactly one report')
capture('justice-interrogation-selected')
activate();assert(not selected(),'Native interrogation activation did not cancel')
local native_off=reports();assert(json.encode(native_off)==json.encode(before),'Native interrogation did not restore reports')
assert(probe('justice-interrogation-probe',{'9',tostring(unit_id),'0'},true)==2,'Owned interrogation scheduling failed')
local owned_on=reports();assert(selected(),'Owned interrogation was not selected')
assert(json.encode(owned_on)==json.encode(native_on),'Owned interrogation report differs from native')
assert(probe('justice-interrogation-probe',{'9',tostring(unit_id),'0'},true)==1,'Stale repeated interrogation was not rejected')
assert(json.encode(reports())==json.encode(owned_on),'Rejected interrogation changed reports')
assert(probe('justice-interrogation-probe',{'9',tostring(unit_id),'1'},true)==2,'Owned interrogation cancellation failed')
local owned_off=reports();assert(not selected(),'Owned interrogation stayed selected')
assert(json.encode(owned_off)==json.encode(before),'Owned interrogation did not restore reports')
local result={crime_id=9,unit_id=unit_id,before=before,native_on=native_on,native_off=native_off,owned_on=owned_on,owned_off=owned_off,stale_toggle_rejected=true,keyboard_activation=activation}
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
if os.getenv('DF3D_JUSTICE_INTERROGATION_IDENTITY')=='1' then
 local unit=assert(df.unit.find(unit_id));local hf=assert(df.historical_figure.find(unit.hist_figure_id))
 assert(hf.info,'Controlled subject has no figure info')
 local identity=assert(df.global.world.identities.all[0],'No existing identity for controlled probe')
 local original=hf.info.reputation;local reputation=original or df.reputation_profilest:new()
 local previous=reputation.cur_identity;local report_count=#crime.reports
 hf.info.reputation=reputation;reputation.cur_identity=identity.id
 local ok,err=xpcall(function()
  assert(dfhack.units.getIdentity(unit).id==identity.id)
  assert(not selected(),'Assumed identity unexpectedly selected')
  click(808,190);local native=reports();assert(selected(),'Native assumed-identity scheduling failed')
  assert(#native==report_count+1 and native[#native].historical_hfid==-1 and native[#native].visual_hfid==hf.id and json.encode(native[#native].identities)==json.encode({identity.id}),'Native assumed-identity record differs')
  crime.reports[#crime.reports-1].visual_hfid=-1
  assert(selected(),'Identity-only native record was not recognized')
  click(808,190);assert(not selected() and json.encode(reports())==json.encode(before),'Native assumed-identity cancellation failed')
  assert(probe('justice-interrogation-probe',{'9',tostring(unit_id),'0'},true)==2)
  local owned=reports();assert(selected() and json.encode(owned)==json.encode(native),'Owned assumed-identity scheduling differs')
  crime.reports[#crime.reports-1].visual_hfid=-1
  assert(selected(),'Identity-only owned record was not recognized')
  assert(probe('justice-interrogation-probe',{'9',tostring(unit_id),'1'},true)==2)
  assert(not selected() and json.encode(reports())==json.encode(before),'Owned assumed-identity cancellation differs')
  result.assumed_identity={identity_id=identity.id,historical_figure=hf.id,native_on=native,owned_on=owned,reports_restored=true,identity_only_cancellation=true}
 end,debug.traceback)
 while #crime.reports>report_count do local report=crime.reports[#crime.reports-1];crime.reports:erase(#crime.reports-1);report:delete()end
 reputation.cur_identity=previous;hf.info.reputation=original
 if not original then reputation:delete()end
 assert(ok,err)
 result.assumed_identity.original_reputation_restored=true
 local original_hfid=unit.hist_figure_id;unit.hist_figure_id=-1
 local missing_ok,missing_err=xpcall(function()
  click(808,190)
  assert(json.encode(reports())==json.encode(before),'Native missing-figure click changed reports')
  local outcome=probe('justice-interrogation-probe',{'9',tostring(unit_id),'0'},true)
  assert(outcome==1 and json.encode(reports())==json.encode(before),'Owned missing-figure edit was not rejected without effects')
  result.missing_historical_figure={native_reports_unchanged=true,owned_outcome=outcome,owned_reports_unchanged=true}
 end,debug.traceback)
 unit.hist_figure_id=original_hfid
 assert(missing_ok,missing_err)
end
return result
