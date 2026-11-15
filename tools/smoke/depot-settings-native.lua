-- Paused native depot settings reference; no runtime menu inputs are exposed.
local out,view,b,capture=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local original=b.trade_flags.whole;local frame=df.global.world.frame_counter
assert(not b.trade_flags.trader_requested and #b.jobs==0,'Expected idle depot')
local result={id=b.id,original_flags=original,frame=frame,cases={}}
local function click(y)
 g.precise_mouse_x=520;g.precise_mouse_y=y;g.mouse_x=65;g.mouse_y=(y-4)//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
end
local function record(label,flags,count)
 assert(b.trade_flags.whole==flags and #b.jobs==count,label..' unexpected flags/jobs')
 local row={label=label,flags=b.trade_flags.whole,jobs={}}
 for _,j in ipairs(b.jobs)do
  assert(j.job_type==df.job_type.TradeAtDepot)
  local job={id=j.id,type=j.job_type,flags=j.flags.whole,pos={j.pos.x,j.pos.y,j.pos.z},refs={}}
  for _,r in ipairs(j.general_refs)do job.refs[#job.refs+1]={type=r:getType(),building_id=r:getBuilding() and r:getBuilding().id or -1}end
  row.jobs[#row.jobs+1]=job
 end
 capture('depot-settings-'..label);result.cases[#result.cases+1]=row
end
local ok,err=xpcall(function()
 record('idle',original,0)
 click(226);record('broker',1,1);local job=b.jobs[0].id
 click(262);record('anyone',3,1);assert(b.jobs[0].id==job)
 click(226);record('broker-again',1,1);assert(b.jobs[0].id==job)
 click(298);record('dismissed',0,0)
 click(262);record('anyone-fresh',3,1);assert(b.jobs[0].id~=job)
 click(298);record('dismissed-anyone',2,0)
end,debug.traceback)
if b.trade_flags.trader_requested then click(298)end
b.trade_flags.whole=original
assert(#b.jobs==0 and df.global.world.frame_counter==frame)
if not ok then error(err)end
result.restored=true;result.success=true
local f=assert(io.open(out..'/depot-settings-native.json','w'));f:write(json.encode(result));f:close()
return result
