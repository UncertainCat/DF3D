-- Protected paused clone only. Compare native Tasks cancellation with public UI.
local out,view=...
local gui=require('gui');local json=require('json');local utils=require('utils');local script=require('gui.script')
local building=assert(df.building.find(3),'Demolition workshop fixture missing')
assert(building:getBuildStage()==building:getMaxBuildStage() and #building.jobs==0,
 'Demolition requires an idle completed workshop')
local id=building.id;local baseline={}
for _,job in utils.listpairs(df.global.world.jobs.list)do baseline[job.id]=true end
local function queue()
 building:queueDestroy()
 assert(#building.jobs==1 and building.jobs[0].job_type==df.job_type.DestroyBuilding)
 return building.jobs[0].id
end
local function verify(target)
 local current=assert(df.building.find(id),'Cancellation removed workshop')
 local jobs={};for _,job in ipairs(current.jobs)do jobs[#jobs+1]={id=job.id,type=df.job_type[job.job_type]}end
 local f=assert(io.open(out..'/tasks-demolition-observation.json','w'))
 f:write(json.encode{target=target,stage=current:getBuildStage(),max_stage=current:getMaxBuildStage(),jobs=jobs,
  hover=df.global.game.main_interface.current_hover,scroll=df.global.game.main_interface.info.jobs.scroll_position_cri_job});f:close()
 assert(#current.jobs==0 and current:getBuildStage()==current:getMaxBuildStage(),
  'Cancellation retained removal or changed construction stage')
 local remaining={}
 for _,job in utils.listpairs(df.global.world.jobs.list)do
  assert(job.id~=target and baseline[job.id],'Cancellation added/retained unexpected job')
  remaining[job.id]=true
 end
 for job_id in pairs(baseline)do assert(remaining[job_id],'Cancellation removed unrelated job')end
end
local native_id=queue()
gui.simulateInput(view,'D_JOBLIST');view:render(dfhack.getTickCount())
for _=1,3 do script.sleep(1,'frames')end
local info=df.global.game.main_interface.info;local index
assert(info.open and info.current_mode==df.info_interface_mode_type.JOBS)
for i,row in ipairs(info.jobs.cri_job)do if row.jb and row.jb.id==native_id then index=i;break end end
assert(index,'Native Tasks omitted demolition')
info.jobs.scroll_position_cri_job=math.min(index,math.max(0,#info.jobs.cri_job-17));view:render(dfhack.getTickCount())
for _=1,3 do script.sleep(1,'frames')end
local g=df.global.gps
local y=142+(index-info.jobs.scroll_position_cri_job)*36
assert(y>=142 and y<754,'Native demolition row is outside the list')
df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
g.precise_mouse_x=372;g.precise_mouse_y=y;g.mouse_x=46;g.mouse_y=(y-4)//12
gui.simulateInput(view,{});view:render(dfhack.getTickCount())
local f=assert(io.open(out..'/shot.tmp','w'));f:write('tasks-demolition-before');f:close()
assert(os.rename(out..'/shot.tmp',out..'/shot'))
local deadline=dfhack.getTickCount()+15000
while true do
 local ack=io.open(out..'/ack-tasks-demolition-before');if ack then ack:close();break end
 assert(dfhack.getTickCount()<deadline,'Demolition capture timed out');script.sleep(1,'frames')
end
df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
g.precise_mouse_x=372;g.precise_mouse_y=y;g.mouse_x=46;g.mouse_y=(y-4)//12
gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
verify(native_id)
gui.simulateInput(view,'LEAVESCREEN');assert(not info.open)
local target=queue()
return {job_id=target,building_id=id,native_job_id=native_id,checked=false,
 verify=function()
  verify(target)
  local f=assert(io.open(out..'/tasks-demolition-native-result.json','w'))
  f:write(json.encode{native_job_id=native_id,public_job_id=target,building_id=id,
   workshop_preserved=true,removal_cancelled=true,unrelated_jobs_preserved=true});f:close()
 end}
