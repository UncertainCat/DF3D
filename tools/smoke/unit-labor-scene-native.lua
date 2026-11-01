-- Observe real semantic edits independently in the owned paused clone.
local unit,capture,out=...
local json=require('json');local observations={}
local frame=df.global.world.frame_counter
local function snapshot()
 local state={details={},labors={},only_assigned=unit.flags4.only_do_assigned_jobs}
 for _,detail in ipairs(df.global.plotinfo.labor_info.work_details)do
  local assigned={};for _,id in ipairs(detail.assigned_units)do assigned[#assigned+1]=id end
  state.details[#state.details+1]={name=detail.name,flags=detail.flags.whole,assigned=assigned}
 end
 for i=0,93 do state.labors[#state.labors+1]=unit.status.labors[i]end
 return state
end
local file=assert(io.open(out..'/unit-labor-native.json'));local native=json.decode(file:read('*a'));file:close()
local function service()
 local f=io.open(out..'/unit-labor-request.json');if not f then return end
 local request=json.decode(f:read('*a'));f:close();assert(os.remove(out..'/unit-labor-request.json'))
 assert(request.unit_id==unit.id and request.serial==#observations+1,'Invalid labor observation')
 assert(df.global.pause_state and df.global.world.frame_counter==frame,'Labor scene advanced simulation')
 local state=snapshot();local expected=native.actions[request.stage]
 assert(expected and json.encode(state)==json.encode(expected),'Semantic labor effects differ from native: '..request.stage)
 observations[#observations+1]={stage=request.stage,state=state}
 f=assert(io.open(out..'/unit-labor-ack.tmp','w'));f:write(json.encode({serial=request.serial}));f:close()
 assert(os.rename(out..'/unit-labor-ack.tmp',out..'/unit-labor-ack.json'))
end
capture('farm-item-carrier-unit-scene',service)
assert(#observations==5 and json.encode(snapshot())==json.encode(native.actions.before),'Labor scene did not restore baseline')
local result={success=true,observations=observations,restored=true}
file=assert(io.open(out..'/unit-labor-scene-native.json','w'));file:write(json.encode(result));file:close()
return result
