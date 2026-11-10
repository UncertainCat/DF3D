-- Native actions in the disposable paused clone only. No runtime menu adapter.
local out,view,info,capture=...
local gui=require('gui');local script=require('gui.script')
local g=df.global.gps;local main=df.global.game.main_interface
local result={hover={},suspension={}}
local function move(x,y)
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 gui.simulateInput(view,{});view:render(dfhack.getTickCount())
end
local function click(x,y)
 move(x,y);gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
end
local function job_by_id(id)
 for _,job in require('utils').listpairs(df.global.world.jobs.list)do if job.id==id then return job end end
end
local function row_y(id)
 for index,entry in ipairs(info.jobs.cri_job)do
  if entry.jb and entry.jb.id==id then
   local row=index-info.jobs.scroll_position_cri_job
   assert(row>=0 and row<17,'Task target is not visible');return 142+row*36
  end
 end
 error('Task target missing')
end
local y=row_y(372039)
for _,target in ipairs{{'job-recenter',252,y},{'suspend',348,y},{'remove',372,y},
 {'worker-recenter',708,142},{'worker-view',732,142},{'hauling-cancel',324,250}}do
 local deadline=dfhack.getTickCount()+700
 repeat move(target[2],target[3]);script.sleep(1,'frames')until dfhack.getTickCount()>=deadline
 move(target[2],target[3])
 local row={kind=target[1],point={target[2],target[3]},instruction=main.current_hover,
  active=main.hover_instructions_on,lines={}}
 for yy=0,17 do
  local line={}
  for xx=g.dimx-24,g.dimx-1 do
   local ch=dfhack.screen.readTile(xx,yy).ch;line[#line+1]=ch>=32 and string.char(ch%256) or ' '
  end
  row.lines[#row.lines+1]=dfhack.df2utf(table.concat(line)):gsub('%s+$','')
 end
 while #row.lines>0 and row.lines[#row.lines]==''do table.remove(row.lines)end
 result.hover[#result.hover+1]=row
end
for _,id in ipairs{68196,372039}do
 local job=assert(job_by_id(id));assert(job.job_type==df.job_type.ConstructBuilding)
 local before=job.flags.whole;local suspended=job.flags.suspend
 local yy=row_y(id);click(348,yy)
 assert(job.flags.suspend~=suspended,'Native Suspend did not toggle')
 local after=job.flags.whole;capture('tasks-suspended-'..id)
 click(348,yy);assert(job.flags.whole==before,'Native resume changed other flags')
 result.suspension[#result.suspension+1]={job_id=id,before=before,after=after,restored=job.flags.whole}
end
-- Last action: remove the unstarted Well and end this clone without saving.
local job=assert(job_by_id(372039));local building
for _,ref in ipairs(job.general_refs)do
 if ref:getType()==df.general_ref_type.BUILDING_HOLDER then building=ref:getBuilding();break end
end
assert(building and building:getBuildStage()==0,'Removal fixture must be unstarted')
local id=building.id;local before_ids={}
for _,value in require('utils').listpairs(df.global.world.jobs.list)do before_ids[#before_ids+1]=value.id end
local yy=row_y(job.id);click(372,yy)
assert(not job_by_id(372039) and not df.building.find(id),'Native Remove retained unstarted building/job')
for _,other in ipairs(before_ids)do if other~=372039 then assert(job_by_id(other),'Remove lost unrelated job')end end
result.removal={job_id=372039,building_id=id,stage_before=0,job_removed=true,building_removed=true,other_jobs_preserved=true}
capture('tasks-after-remove')
return result
