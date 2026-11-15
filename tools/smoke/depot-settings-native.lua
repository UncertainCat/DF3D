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
 if os.getenv('DF3D_DEPOT_PROVIDER')=='1' then
  b.trade_flags.whole=original
  local sheet=df.global.game.main_interface.view_sheets
  local active=sheet.active_id
  local function probe(expected,mode,outcome)
   local args={'df3d','depot-settings-probe',tostring(b.id)}
   if expected~=nil then args[#args+1]=tostring(expected);args[#args+1]=tostring(mode)end
   local output,code=dfhack.run_command_silent(table.unpack(args));assert(code==0,output)
   local facts=json.decode(output)
   assert(facts.flags==b.trade_flags.whole and not facts.goods and not facts.trade and facts.worker==-1)
   if outcome~=nil then assert(facts.outcome==outcome,output)end
   assert(sheet.active_id==active)
   return facts
  end
  result.provider={baseline=probe(),cases={}}
  for _,step in ipairs({{'broker',0,0,1,1},{'anyone',1,1,3,1},{'broker-again',3,0,1,1},{'dismissed',1,2,0,0},{'anyone-fresh',0,1,3,1},{'dismissed-anyone',3,2,2,0}})do
   local previous=#b.jobs>0 and b.jobs[0].id or -1
   local facts=probe(step[2],step[3],1)
   record('provider-'..step[1],step[4],step[5])
   local actual=result.cases[#result.cases]
   local native
   for _,row in ipairs(result.cases)do if row.label==step[1]then native=row;break end end
   assert(native and #actual.jobs==#native.jobs)
   for i,job in ipairs(actual.jobs)do
    local reference=native.jobs[i]
    assert(job.type==reference.type and job.flags==reference.flags and json.encode(job.pos)==json.encode(reference.pos) and json.encode(job.refs)==json.encode(reference.refs))
   end
   if previous>=0 and step[5]==1 then assert(b.jobs[0].id==previous)end
   local count=#b.jobs;local id=count>0 and b.jobs[0].id or -1
   probe(step[4],step[3],1) -- exact duplicate must not allocate another job
   assert(#b.jobs==count and (count==0 or b.jobs[0].id==id))
   probe(99,step[3],0);probe(step[4],9,0)
   assert(#b.jobs==count and (count==0 or b.jobs[0].id==id))
   result.provider.cases[#result.provider.cases+1]=facts
  end
  result.provider.success=true
 end
end,debug.traceback)
if b.trade_flags.trader_requested then click(298)end
b.trade_flags.whole=original
assert(#b.jobs==0 and df.global.world.frame_counter==frame)
if not ok then error(err)end
result.restored=true;result.success=true
local f=assert(io.open(out..'/depot-settings-native.json','w'));f:write(json.encode(result));f:close()
return result
