-- Owned paused-clone setup, shared by native-button and semantic-wire oracles.
local M={}
local function coord(p)return{x=p.x,y=p.y,z=p.z}end
function M.occupancy(farm)
 local cells={}
 for y=farm.y1,farm.y2 do for x=farm.x1,farm.x2 do
  local block=assert(dfhack.maps.getTileBlock(x,y,farm.z))
  cells[#cells+1]=block.occupancy[x%16][y%16].whole
 end end
 return cells
end
function M.attach(farm)
 assert(df.global.pause_state and #farm.jobs==1)
 local job=farm.jobs[0];assert(job.job_type==df.job_type.DestroyBuilding)
 local worker
 for _,unit in ipairs(df.global.world.units.active)do
  if dfhack.units.isCitizen(unit) and not dfhack.units.isDead(unit) and not unit.job.current_job then worker=unit;break end
 end
 assert(worker,'no idle citizen for controlled destruction worker')
 assert(dfhack.job.addWorker(job,worker),'could not attach destruction worker')
 job.flags.working=true
 assert(worker.job.current_job==job and dfhack.job.getWorker(job)==worker)
 return{worker_id=worker.id,job_id=job.id,setup='Paused fixture uses addWorker and working=true; no AI ticks advanced.'}
end
function M.observe(farm,identity)
 local worker=assert(df.unit.find(identity.worker_id));local jobs={}
 for _,job in ipairs(farm.jobs)do
  local unit=dfhack.job.getWorker(job)
  jobs[#jobs+1]={id=job.id,type=df.job_type[job.job_type],worker_id=unit and unit.id or -1,working=job.flags.working}
 end
 return{worker_id=worker.id,current_job=worker.job.current_job and worker.job.current_job.id or -1,
  position=coord(worker.pos),destination=coord(worker.path.dest),path_goal=worker.path.goal,
  job_counter=worker.counters.job_counter,jobs=jobs,occupancy=M.occupancy(farm)}
end
return M
