-- Native readback and guard; only pause is written here. Never writes labors.
local out,index=...
local json=require('json')
local function read(path)
 local f=assert(io.open(path,'r'));local s=f:read('*a');f:close();return json.decode(s)
end
local function write(path,v)
 local f=assert(io.open(path,'w'));f:write(json.encode(v));f:close()
end
if index=='pause' then
 print('FIXTURE_WRITE pause_state=true (teardown)');df.global.pause_state=true
 print('SEMANTIC_PASS pause');return
elseif index=='final' then
 assert(df.global.pause_state,'DF must be paused before Stop-Df3d')
 print('SEMANTIC_PASS final paused');return
end
local q=read(out..'/request-'..index..'.json')
local state=assert(df3d_work_details_acceptance)
local all=df.global.plotinfo.labor_info.work_details
local result={status='passed'}
local function labors(bits)
 local r={};for i=0,93 do if bits[i] then r[#r+1]=i end end;return r
end
local function ids(vector)local r={};for _,id in ipairs(vector) do r[#r+1]=id end;return r end
local function same(a,b)
 if type(a)~=type(b) then return false end
 if type(a)~='table' then return a==b end
 for k,v in pairs(a) do if not same(v,b[k]) then return false end end
 for k in pairs(b) do if a[k]==nil then return false end end
 return true
end
local function detail(i)
 assert(i and i>=0 and i<#all,'detail index out of range')
 local d=all[i]
 return {index=i,name=dfhack.df2utf(d.name),flags=d.flags.whole,mode=d.flags.mode,
  no_modify=d.flags.no_modify,cannot_be_everybody=d.flags.cannot_be_everybody,
  icon=d.icon,labors=labors(d.allowed_labors),assigned_units=ids(d.assigned_units)}
end
local function fingerprint()
 -- Exact canonical sequence, including every bit/member; avoids hash collision risk.
 local r={tostring(#all)}
 for i in ipairs(all) do
  local d=detail(i)
  r[#r+1]=#d.name..':'..d.name..':'..d.flags..':'..d.icon..':'..table.concat(d.labors,',')..':'..table.concat(d.assigned_units,',')
 end
 for _,u in ipairs(df.global.world.units.all) do
  r[#r+1]=u.id..':'..tostring(u.flags4.only_do_assigned_jobs)..':'..table.concat(labors(u.status.labors),',')
 end
 return table.concat(r,'\n')
end
local function paused()assert(df.global.pause_state,'expected paused native state')end
local ok,err=pcall(function()
 if q.op=='guard_before' then paused();state.guard=fingerprint()
 elseif q.op=='guard_after' then paused();assert(state.guard==fingerprint(),'refusal changed work details, scope or labors');state.guard=nil
 elseif q.op=='focus' then
  paused()
  local focus=dfhack.gui.getCurFocus()
  assert(type(focus)=='string' and focus~='','native focus unavailable')
  result.focus=focus
  -- Reject the whole Labor route, a conservative superset of Work Details.
  if focus:lower():find('labor',1,true) or focus:lower():find('workdetail',1,true) or focus:lower():find('work_detail',1,true) then
   result.status='incomplete';result.reason='native Labor/Work Details tab is open; deletion not issued'
  end
 elseif q.op=='builtins' then
  paused();local seen={}
  for _,r in ipairs(q.rows) do
   assert(not seen[r.index],'duplicate detail index');seen[r.index]=true
   local d=detail(r.index)
   if d.no_modify then
    for _,key in ipairs{'name','mode','no_modify','cannot_be_everybody','icon','labors','assigned_units'} do
     assert(same(d[key],r[key]),'built-in mismatch '..r.index..' '..key)
    end
   end
  end
  for i in ipairs(all) do assert(seen[i],'detail absent from complete model page') end
  result.details={};for i in ipairs(all) do result.details[#result.details+1]=detail(i) end
 elseif q.op=='detail' then
  paused();local d=detail(q.detail_index)
  for key,value in pairs(q.expected) do assert(same(d[key],value),'native detail mismatch '..key) end
  result.detail=d
 elseif q.op=='created' then
  paused();local d=detail(q.detail_index)
  assert(d.name=='Custom Detail '..state.custom_count,'Add name')
  assert(d.icon==10+state.custom_count%8 and d.mode==1,'Add icon/mode')
  assert(#d.labors==0 and #d.assigned_units==0,'Add labors/members')
  assert(not d.no_modify and not d.cannot_be_everybody,'Add flags')
  state.custom_index=q.detail_index;result.detail=d
 elseif q.op=='scope_before' then
  paused();local u=assert(df.unit.find(state.scope));assert(not u.flags4.only_do_assigned_jobs)
  state.scope_labors=labors(u.status.labors);result.labors=state.scope_labors
 elseif q.op=='scope' then
  paused();local u=assert(df.unit.find(state.scope))
  assert(u.flags4.only_do_assigned_jobs==(q.only_assigned==1),'failed step 4: scope flag')
  assert(same(labors(u.status.labors),q.only_assigned==1 and {} or state.scope_labors),
   'failed step 4: DF recalculation did not clear/restore exact pre-step labors')
 elseif q.op=='roster' then
  paused();local seen={};for _,id in ipairs(q.ids) do assert(not seen[id],'duplicate roster id');seen[id]=true end
  for _,id in ipairs(state.residents) do assert(not seen[id],'resident listed') end
  for _,id in ipairs(state.visitors) do assert(not seen[id],'visitor listed') end
 elseif q.op=='wait_start' then
  paused();state.start_tick=df.global.world.frame_counter;state.start_ms=dfhack.getTickCount()
  result.tick=state.start_tick
 elseif q.op=='wait_poll' then
  result.ticks=df.global.world.frame_counter-state.start_tick
  result.elapsed_ms=dfhack.getTickCount()-state.start_ms
  if result.ticks>=1200 or result.elapsed_ms>=120000 then
   result.status='incomplete';result.reason='recalculation tick/wall wait cap hit'
  end
 elseif q.op=='wait_finish' then
  paused();result.ticks=df.global.world.frame_counter-state.start_tick
 elseif q.op=='status' then result.counters=read(out..'/status-'..index..'.json')
 elseif q.op=='deleted' then
  paused();assert(#all==q.count,'delete did not erase one detail')
 elseif q.op=='rename_out_of_band' then paused();assert(state.renamed,'fixture rename absent')
 elseif q.op=='final' then paused()
 else error('unknown verification operation '..tostring(q.op)) end
end)
if not ok then result.status='failed';result.reason='step '..tostring(q.step)..': '..tostring(err) end
write(out..'/response-'..index..'.json',result)
print('SEMANTIC_'..(result.status=='incomplete' and 'INCOMPLETE' or result.status=='failed' and 'FAIL' or 'PASS')..' '..q.op..' '..json.encode(result))
