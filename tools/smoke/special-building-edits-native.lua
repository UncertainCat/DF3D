-- Compare owned semantic effects with clicks on the temporary native fixtures.
local out,view,b,click=...
local json=require('json');local kind=b:getType();local result={type=kind,cases={}}
local function call(command,...)
 local args={...};for i,v in ipairs(args)do args[i]=tostring(v)end
 local guards={}
 for _,v in ipairs{df.global.gps,df.global.game.main_interface}do
  local size,address=df.sizeof(v);local copy=df.new('uint8_t',size)
  dfhack.internal.memmove(copy,address,size);guards[#guards+1]={copy=copy,address=address,size=size}
 end
 local text,code=dfhack.run_command_silent('df3d',command,tostring(b.id),table.unpack(args))
 for _,g in ipairs(guards)do
  assert(dfhack.internal.memcmp(g.copy,g.address,g.size)==0,'Owned edit changed native UI storage');df.delete(g.copy)
 end
 assert(code==0,text);return json.decode(text)
end
local function read()return call('special-building-controls-read')end
local function edit(revision,op,value)return call('special-building-controls-probe',revision,op,value)end
local function stale(revision,op,value)
 local r=edit(revision,op,value);assert(r.outcome==2 and not r.effects_started and not r.revision);return r
end
local function job(kind,item)
 local j=df.job:new();j.job_type=kind;j.item_type=item;j.posting_index=-1
 j.pos:assign{x=b.centerx,y=b.centery,z=b.z}
 local ref=df.general_ref_building_holderst:new();ref.building_id=b.id;j.general_refs:insert('#',ref)
 assert(dfhack.job.linkIntoWorld(j,true));b.jobs:insert('#',j);return j.id
end
local function find_job(id)
 for _,value in require('utils').listpairs(df.global.world.jobs.list)do if value.id==id then return value end end
end
local function clear_jobs()
 while #b.jobs>0 do assert(dfhack.job.removeJob(b.jobs[#b.jobs-1]))end
end
if kind==24 then
 local original=b.bait_type
 for i,bait in ipairs{48,49,44,-1}do
  b.bait_type=original;local before=read();click(444+(i-1)*24,202);local native=b.bait_type
  b.bait_type=original;local owned=edit(before.revision,0,bait)
  assert(owned.outcome==1 and owned.bait_type==native and #owned.jobs==0)
  if bait~=original then stale(before.revision,0,original)end
  result.cases[#result.cases+1]={bait=bait,native=native,owned=owned}
 end
 -- Native also cancels mismatched jobs when the chosen bait is unchanged.
 local function jobs_fixture()
  b.bait_type=48
  return {job(df.job_type.BaitTrap,49),job(df.job_type.BaitTrap,48),job(df.job_type.CleanTrap,-1)}
 end
 local native_ids=jobs_fixture();click(444,202)
 assert(#b.jobs==2 and b.jobs[0].id==native_ids[2] and b.jobs[1].id==native_ids[3])
 assert(not find_job(native_ids[1]));clear_jobs()
 local owned_ids=jobs_fixture();local before=read();local owned=edit(before.revision,0,48)
 assert(owned.outcome==1 and owned.effects_started and #owned.jobs==2)
 assert(owned.jobs[1].id==owned_ids[2] and owned.jobs[2].id==owned_ids[3] and not find_job(owned_ids[1]))
 stale(before.revision,0,49)
 result.jobs={native_removed=native_ids[1],owned_removed=owned_ids[1],owned=owned}
 clear_jobs();b.bait_type=original
elseif kind==49 then
 local original=b.hive_flags.whole
 -- Include ready-split and an unrelated bit to verify precise preservation.
 for _,base in ipairs{original,original|4|8}do
  for _,mask in ipairs{1,2}do
   b.hive_flags.whole=base;local before=read();click(444,mask==1 and 148 or 184)
   local native=b.hive_flags.whole;b.hive_flags.whole=base
   local owned=edit(before.revision,mask,(native&mask)~=0 and 1 or 0)
   assert(owned.outcome==1 and owned.flags==native and native==(base~mask))
   stale(before.revision,mask,(base&mask)~=0 and 1 or 0)
   result.cases[#result.cases+1]={before=base,mask=mask,native=native,owned=owned}
  end
 end
 b.hive_flags.whole=original
end
-- Demolition blocks both edit routes without effects.
local removing=job(df.job_type.DestroyBuilding,-1);local before=read();assert(before.removing)
local rejected=edit(before.revision,kind==24 and 0 or 1,kind==24 and 48 or 1)
assert(rejected.outcome==0 and not rejected.effects_started and #b.jobs==1 and b.jobs[0].id==removing)
clear_jobs();result.removing_rejected=true;result.restored=true
local f=assert(io.open(out..'/special-building-'..kind..'-edits.json','w'));f:write(json.encode(result));f:close()
return result
