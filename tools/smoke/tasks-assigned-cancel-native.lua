-- Protected disposable oracle: let DF assign real labor and reserve real inputs.
local out,view,records=...
local initial_frame=df.global.world.frame_counter
local gui=require('gui');local script=require('gui.script');local json=require('json');local utils=require('utils')
local root=debug.getinfo(1,'S').source:sub(2):gsub('tasks%-assigned%-cancel%-native.lua$','')
local observations={}
local function write()
 local f=assert(io.open(out..'/tasks-assigned-cancel-native.json','w'));f:write(json.encode(observations));f:close()
end
local function find(id)
 for _,job in utils.listpairs(df.global.world.jobs.list)do if job.id==id then return job end end
end
local function prepare()
 local target=assert(loadfile(root..'residents-job-create-native.lua'))(out,view)
 gui.simulateInput(view,'LEAVESCREEN')
 assert(not df.global.game.main_interface.info.open)
 local id=target.id;local start=df.global.world.frame_counter;local deadline=dfhack.getTickCount()+180000
 local worker
 df.global.pause_state=false
 while find(id) and df.global.world.frame_counter-start<12000 and dfhack.getTickCount()<deadline do
  script.sleep(1,'frames')
  target=find(id);if not target then break end
  for _,ref in ipairs(target.general_refs)do if ref:getType()==df.general_ref_type.UNIT_WORKER then worker=ref:getUnit() end end
  if worker and #target.items>0 then break end
  assert(not df.global.pause_state,'Native paused before assignment')
 end
 df.global.pause_state=true
 assert(find(id) and worker and worker.job.current_job==target and #target.items>0,'No naturally assigned job with reserved inputs')
 local holder
 for _,ref in ipairs(target.general_refs)do if ref:getType()==df.general_ref_type.BUILDING_HOLDER then holder=ref:getBuilding() end end
 assert(holder)
 local record={job_id=id,worker_id=worker.id,building_id=holder.id,elapsed=df.global.world.frame_counter-start,end_tick=df.global.world.frame_counter,inputs={},world_jobs={},holder_jobs={}}
 for _,ref in ipairs(target.items)do
  local item=assert(ref.item);assert(item.flags.in_job,'Input not reserved')
  record.inputs[#record.inputs+1]={id=item.id,flags=item.flags.whole}
 end
 for _,job in utils.listpairs(df.global.world.jobs.list)do record.world_jobs[tostring(job.id)]=true end
 for _,job in ipairs(holder.jobs)do record.holder_jobs[tostring(job.id)]=true end
 observations[#observations+1]=record;write()
 return record
end
local function verify(record)
 assert(df.global.pause_state and df.global.world.frame_counter==record.end_tick,
  'Cancellation advanced simulation')
 assert(not find(record.job_id),'Cancelled job retained')
 local worker=assert(df.unit.find(record.worker_id));assert(worker.job.current_job==nil,'Worker retained cancelled job')
 local holder=assert(df.building.find(record.building_id));local remaining={}
 for _,job in utils.listpairs(df.global.world.jobs.list)do assert(record.world_jobs[tostring(job.id)],'Cancellation added job');remaining[tostring(job.id)]=true end
 for id in pairs(record.world_jobs)do assert((remaining[id]==true)==(tonumber(id)~=record.job_id),'Unrelated world job changed')end
 remaining={}
 for _,job in ipairs(holder.jobs)do assert(record.holder_jobs[tostring(job.id)],'Cancellation added holder job');remaining[tostring(job.id)]=true end
 for id in pairs(record.holder_jobs)do assert((remaining[id]==true)==(tonumber(id)~=record.job_id),'Unrelated holder job changed')end
 for _,input in ipairs(record.inputs)do
  local item=assert(df.item.find(input.id));assert(not item.flags.in_job,'Input reservation retained')
  input.after_flags=item.flags.whole
 end
 record.worker_released=true;record.inputs_released=true;record.other_jobs_preserved=true;write()
end
local native=prepare()
gui.simulateInput(view,'D_JOBLIST');view:render(dfhack.getTickCount())
for _=1,3 do script.sleep(1,'frames')end
local info=df.global.game.main_interface.info;local index
for i,row in ipairs(info.jobs.cri_job)do if row.jb and row.jb.id==native.job_id then index=i;break end end
assert(index,'Native omitted assigned task')
info.jobs.scroll_position_cri_job=math.min(index,math.max(0,#info.jobs.cri_job-17));view:render(dfhack.getTickCount())
for _=1,3 do script.sleep(1,'frames')end
local g=df.global.gps;local y=142+(index-info.jobs.scroll_position_cri_job)*36
assert(y>=142 and y<754)
df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
g.precise_mouse_x=372;g.precise_mouse_y=y;g.mouse_x=46;g.mouse_y=(y-4)//12
gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
verify(native)
gui.simulateInput(view,'LEAVESCREEN')
local public=prepare()
return {job_id=public.job_id,building_id=public.building_id,checked=false,verify=function()
 verify(public)
 local elapsed=native.elapsed+public.elapsed
 assert(elapsed==df.global.world.frame_counter-initial_frame and native.elapsed>0 and public.elapsed>0)
 records[#records+1]={name='tasks-assigned-cancel-simulation',start_tick=initial_frame,
  end_tick=df.global.world.frame_counter,elapsed=elapsed,native_released=true,public_released=true}
end}
