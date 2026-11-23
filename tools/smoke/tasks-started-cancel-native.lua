-- Protected disposable fixture. Never set construction stage or worker pointers.
-- Native102105 preserves stage1 and replaces construction with a removal job.
local out,view,records=...
local script=require('gui.script');local json=require('json');local utils=require('utils')
assert(df.global.pause_state and not df.global.game.main_interface.info.open)
local result={samples={}}
local function save()
 local f=assert(io.open(out..'/tasks-started-cancel-native.json','w'));f:write(json.encode(result));f:close()
end
  local anchor=assert(df.building.find(3));local building
  for y=anchor.y1-20,anchor.y2+20 do for x=anchor.x1-20,anchor.x2+20 do
   local clear=true
   for dy=0,2 do for dx=0,2 do
    local pos={x=x+dx,y=y+dy,z=anchor.z};local d,o=dfhack.maps.getTileFlags(pos)
    local tile=dfhack.maps.getTileType(pos)
    if not d or d.hidden or not o or o.building~=0 or dfhack.buildings.findAtTile(pos) or not tile or df.tiletype.attrs[tile].shape~=df.tiletype_shape.FLOOR then clear=false end
   end end
   if clear then
    local success,b=pcall(dfhack.buildings.constructBuilding,{type=df.building_type.Workshop,subtype=df.workshop_type.Masons,pos={x=x,y=y,z=anchor.z},full_rectangle=true,filters={{item_type=df.item_type.BOULDER,quantity=1}}})
    if success and b then building=b;break end
   end
  end;if building then break end end
  assert(building and #building.jobs>0,'No workshop fixture site')
  local building_id=building.id
  result.created={id=building_id,stage=building:getBuildStage(),max=building:getMaxBuildStage(),x=building.x1,y=building.y1,z=building.z}
  save()
  local start=df.global.world.frame_counter;local deadline=dfhack.getTickCount()+180000;local next_sample=0
  df.global.pause_state=false
  while df.global.world.frame_counter-start<12000 and dfhack.getTickCount()<deadline do
   script.sleep(1,'frames')
   local b=df.building.find(building_id);assert(b,'Building disappeared')
   local elapsed=df.global.world.frame_counter-start;local stage=b:getBuildStage()
   if elapsed>=next_sample or stage>0 then
    local jobs={};for _,job in ipairs(b.jobs)do jobs[#jobs+1]={id=job.id,type=df.job_type[job.job_type],flags=job.flags.whole,items=#job.items,timer=job.completion_timer}end
    result.samples[#result.samples+1]={elapsed=elapsed,stage=stage,max=b:getMaxBuildStage(),jobs=jobs};next_sample=elapsed+100;save()
   end
   if stage>0 then result.started=stage<b:getMaxBuildStage();break end
   if df.global.pause_state then result.pause_count=(result.pause_count or 0)+1;assert(result.pause_count<=3,'Repeated native pause');df.global.pause_state=false end
  end
  df.global.pause_state=true
  result.elapsed=df.global.world.frame_counter-start
  assert(result.started,'No naturally started incomplete construction')
  local function snapshot()
   local b=df.building.find(building_id);local facts={exists=b~=nil,world_jobs={}}
   if b then
    facts.stage=b:getBuildStage();facts.max=b:getMaxBuildStage();facts.jobs={}
    for _,job in ipairs(b.jobs)do
     local worker=-1;for _,ref in ipairs(job.general_refs)do if ref:getType()==df.general_ref_type.UNIT_WORKER then worker=ref:getUnit().id end end
     facts.jobs[#facts.jobs+1]={id=job.id,type=df.job_type[job.job_type],flags=job.flags.whole,worker=worker}
    end
   end
   for _,job in utils.listpairs(df.global.world.jobs.list)do facts.world_jobs[#facts.world_jobs+1]=job.id end
   return facts
  end
  result.before_cancel=snapshot();local target_id=result.before_cancel.jobs[1].id

  assert(#result.before_cancel.jobs==1 and result.before_cancel.jobs[1].type=='ConstructBuilding')
  return {job_id=target_id,building_id=building_id,checked=false,verify=function()
   assert(df.global.pause_state and df.global.world.frame_counter==start+result.elapsed,'Cancellation advanced simulation')
   local after=snapshot();result.after_cancel=after;save()
   assert(after.exists and after.stage==result.before_cancel.stage and after.max==result.before_cancel.max,'Cancellation removed or advanced partial building')
   assert(#after.jobs==1 and after.jobs[1].id~=target_id and after.jobs[1].type=='DestroyBuilding' and after.jobs[1].worker==-1 and after.jobs[1].flags==0,'Native removal job transition differs')
   local removal=after.jobs[1].id;local remaining={};local before={}
   for _,id in ipairs(result.before_cancel.world_jobs)do before[id]=true end
   for _,id in ipairs(after.world_jobs)do assert(id~=target_id and (before[id] or id==removal),'Unexpected world job after cancellation');remaining[id]=true end
   for id in pairs(before)do assert((remaining[id]==true)==(id~=target_id),'Unrelated job removed')end
   assert(remaining[removal],'Removal job absent from world')
   result.success=true;save()
   records[#records+1]={name='tasks-started-cancel-simulation',start_tick=start,end_tick=df.global.world.frame_counter,elapsed=result.elapsed,transition_verified=true}
  end}
