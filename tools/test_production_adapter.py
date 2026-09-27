"""Asset-free tests for the fixed production adapter (requires test-only lupa)."""
from pathlib import Path
from lupa import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
local ordinary_ipairs=ipairs
function vec(values)
 local v={_dfvec=true,data=values or {}}
 return setmetatable(v,{__len=function(t)return #t.data end,__index=function(t,k)
  if type(k)=='number' then return t.data[k+1] end
  if k=='insert' then return function(self,_,x)table.insert(self.data,x)end end
  if k=='erase' then return function(self,i)table.remove(self.data,i+1)end end
  if k=='resize' then return function(self,n)while #self.data>n do table.remove(self.data)end end end
 end})
end
function ipairs(t)
 if type(t)=='table' and rawget(t,'_dfvec') then local i=-1;return function()i=i+1;if i<#t then return i,t[i]end end end
 return ordinary_ipairs(t)
end
function clone(t) if type(t)~='table' then return t end local r={};for k,v in pairs(t)do r[k]=clone(v)end;return r end
function assign(t,v)for k,x in pairs(v)do if type(x)=='table' and type(t[k])=='table' then assign(t[k],x)else t[k]=clone(x)end end end
local utils={clone=clone,assign=assign,call_with_string=function(o,m,...)return o[m](o,...)end}
recipes={input_filter_defaults={item_type=-1,item_subtype=-1,mat_type=-1,mat_index=-1,quantity=1,flags1={},flags2={},flags3={}},jobs_workshop={
 [1]={defaults={item_type=5,vector_id=5},{name='construct bed',items={{}},job_fields={job_type=27}}},
 -- workshops.lua:325-331: real Kitchen defaults and inputs; job_type.h:147.
 [2]={defaults={flags1={unrotten=true}},{name='prepare easy meal',items={{flags1={solid=true,cookable=true}},{flags1={cookable=true}}},job_fields={job_type=114,mat_type=2}}}
},jobs_furnace={}}
package.preload.utils=function()return utils end
package.preload['dfhack.workshops']=function()return recipes end
local jobs={}
local next_id=10
local filters_alive=0
local jobs_alive=0
local refs_alive=0
local function instance(k)return {is_instance=function(_,b)return b.kind==k end}end
df={building_workshopst=instance('workshop'),building_furnacest=instance('furnace'),building_farmplotst=instance('farm'),
 workshop_type={[1]='Carpenters',[2]='Kitchen',[3]='Still'},furnace_type={},item_type={[5]='WOOD',[-1]='NONE'},biome_type={[0]='SUBTERRANEAN_WATER'},
 job_type={CustomReaction=99},reaction={find=function()return nil end},historical_entity={find=function()return {id=7,entity_raw={workshops={permitted_reaction_id=vec{0}}}}end}}
-- DFHack LuaTypes.cpp:1161-1193 iterates bitfields by bit index, not Lua table order.
-- job_item_flags1.h:51,60,67: unrotten=4, cookable=13, solid=20.
local function input_flags()
 return setmetatable({},{__pairs=function(t)
  local names={'unrotten','cookable','solid'};local i=0
  return function()i=i+1;local name=names[i];if name then return name,t[name] or false end end
 end})
end
df.job_item={new=function()
 filters_alive=filters_alive+1
 local f={item_type=-1,quantity=1,mat_type=-1,mat_index=-1,flags1=input_flags(),flags2={},flags3={},reaction_class='',has_material_reaction_product='',reaction_id=-1,reagent_index=-1}
 f.assign=function(self,v)assign(self,v)end
 f.delete=function()filters_alive=filters_alive-1 end
 return f
end}
df.job={new=function()
 jobs_alive=jobs_alive+1
 local j={id=-1,job_type=-1,flags={},job_items={elements=vec()},items=vec(),general_refs=vec(),completion_timer=-1}
 j.assign=function(self,v)assign(self,v)end
 j.delete=function()jobs_alive=jobs_alive-1 end
 return j
end}
df.general_ref_building_holderst={new=function()refs_alive=refs_alive+1;return {delete=function()refs_alive=refs_alive-1 end}end}
function building(id,t,k)
 return {id=id,type=t,kind=k or 'workshop',centerx=5,centery=6,z=2,jobs=vec(),plant_id={[-0]=-1,[1]=-1,[2]=-1,[3]=-1},
 getBuildStage=function()return 3 end,getMaxBuildStage=function()return 3 end,getWorkshopProfile=function()return {permitted_workers=vec()}end,
 getType=function()return 0 end,getSubtype=function()return t end,getCustomType=function()return -1 end}
end
carp=building(0,1);kitchen=building(1,2);still=building(2,3);farm=building(3,0,'farm')
local buildings={[0]=carp,[1]=kitchen,[2]=still,[3]=farm}
df.building={find=function(id)return buildings[id]end}
reaction={index=0,code='BREW',name='brew drink',source_enid=7,flags={},building={type=vec{0},subtype=vec{3},custom=vec{-1}},reagents=vec{}}
reaction.reagents:insert('#',{contribute_to_job_req=function(_,target,ri,rx)
 assert(ri==0 and rx==0,'native reagent identity preserved')
 native_filter_calls=(native_filter_calls or 0)+1
 local f=df.job_item.new();f.item_type=5;target.elements:insert('#',f)
end})
df.global={plotinfo={civ_id=7},cur_season=0,cur_season_tick=9000,world={buildings={all=vec{carp,kitchen,still,farm}},
 raws={reactions={reactions=vec{reaction}},plants={all=vec{{name='allseason',growdur=100,flags={SEED=true,BIOME_SUBTERRANEAN_WATER=true,SPRING=true,SUMMER=true,AUTUMN=true,WINTER=true}},
 {name='spring only',growdur=200,flags={SEED=true,BIOME_SUBTERRANEAN_WATER=true,SPRING=true}}}}},items={other={SEEDS=vec()}}}}
dfhack={df2utf=function(s)return s end,buildings={getName=function(b)return (df.workshop_type[b.type] or 'Farm') end},
 maps={getTileFlags=function()return {subterranean=true}end},units={getReadableName=function()return 'Worker'end},matinfo={decode=function()return nil end},job={}}
local J=dfhack.job
J.getName=function(j)return 'job '..j.id end
J.getWorker=function(j)return j.worker end
J.getHolder=function(j)local ref=j.general_refs[0];return ref and buildings[ref.building_id]end
J.linkIntoWorld=function(j,newid)assert(newid);if force_link_failure then return false end;j.id=next_id;next_id=next_id+1;jobs[j.id]=j;return true end
J.checkBuildingsNow=function() checked=true end
J.removeWorker=function(j,cooldown)assert(cooldown==0);j.worker=nil;removed_worker=true end
J.removeJob=function(j)
 local b=J.getHolder(j);for i,v in ipairs(b.jobs)do if v==j then b.jobs:erase(i);break end end
 for _,f in ipairs(j.job_items.elements)do f:delete()end
 for _,ref in ipairs(j.general_refs)do ref:delete()end
 jobs[j.id]=nil;j:delete();return true
end
function counts()return filters_alive,jobs_alive,refs_alive end
''')
adapter = lua.execute((Path(__file__).resolve().parents[1] / 'bridge/plugin/production.lua').read_text())
lua.globals().adapter = adapter
lua.execute(r'''
local seq=0
local function req(action,p)
 seq=seq+1
 return adapter{action=action,seq=seq,production=p or {}}
end
local list=req(15,{cursor=0,query='#0'})
assert(list.ok and #list.buildings==1 and list.buildings[1].id==0,'ID zero and numeric search')
local state=req(16,{building_id=0})
assert(state.ok and #state.recipes==1 and state.recipes[1].requirements[1].description=='WOOD')
assert(counts()==0,'preview frees filters')
local recipe=state.recipes[1].key
force_link_failure=true
local bad=req(17,{building_id=0,recipe=recipe})
assert(not bad.ok and #carp.jobs==0 and counts()==0,'failed link fully rolls back')
force_link_failure=false
local queued=req(17,{building_id=0,recipe=recipe})
assert(queued.ok and queued.created_job==10 and #carp.jobs==1 and checked,'native queue links and wakes scheduler')
local j=carp.jobs[0];j.worker={id=7}
assert(j.material_category.wood,'carpenter job carries native wooden material category')
-- Current bridge pin, not native parity: e3/findings.md Work-order jobs; 06-B E2.
j.flags.by_manager=true
assert(not req(18,{building_id=0,job_id=j.id,cancel=true}).ok,'manager jobs are read-only')
j.flags.by_manager=false
assert(req(18,{building_id=1,job_id=j.id,repeat_job=-1,suspend=1}).ok==false,'wrong building rejected')
assert(req(18,{building_id=0,job_id=j.id,repeat_job=1,suspend=1}).ok and removed_worker and not j.worker and j.flags['repeat'],'suspend removes worker')
assert(req(18,{building_id=0,job_id=j.id,cancel=true}).ok and #carp.jobs==0,'native cancellation')
local still_state=req(16,{building_id=2})
assert(still_state.ok and #still_state.recipes==1 and native_filter_calls==1,'permitted reaction uses native input generation')
local kitchen_state=req(16,{building_id=1})
assert(kitchen_state.ok and #kitchen_state.recipes[1].requirements==2,'all kitchen ingredients retained')
local crops=req(16,{building_id=3})
assert(crops.ok and #crops.crops==1 and crops.crops[1].seeds==0,'harvest crosses season; zero-seed crop available')
assert(req(19,{building_id=3,season=2,crop_id=0}).ok and farm.plant_id[2]==0,'select future eligible season')
assert(not req(19,{building_id=3,season=0,crop_id=1}).ok,'late-season invalid crop rejected')
assert(req(19,{building_id=3,season=2,crop_id=-1}).ok and farm.plant_id[2]==-1,'fallow clears crop')
for n=1,600 do df.global.world.items.other.SEEDS:insert('#',{flags={},mat_index=0,getStackSize=function()return 1 end}) end
local scan=adapter{action=16,seq=999,production={building_id=3}}
assert(scan.ok and scan.pending,'seed scan is budgeted over updates')
scan=adapter{action=16,seq=999,production={building_id=3}}
assert(scan.ok and not scan.pending and scan.crops[1].seeds==600,'seed scan includes entries beyond first update budget')
local f,j,r=counts();assert(f==0 and j==0 and r==0,'read-only and canceled job allocations all freed')
''')
lua.execute(r"""
local seq=1000
local function req(action,p)
 seq=seq+1
 return adapter{action=action,seq=seq,production=p or {}}
end
local function refusal(action,p,message)
 local result=req(action,p)
 assert(not result.ok and result.message==message,message)
end
local function freed()
 local f,j,r=counts();assert(f==0 and j==0 and r==0,'all job, filter and holder allocations freed')
end
-- Paging is by stable building id, excludes hidden rows, and has both scan and row budgets.
local original=df.global.world.buildings.all
local flags=dfhack.maps.getTileFlags
local rows={}
for i=0,69 do local b=building(i*3,1);b.centerx=i;rows[#rows+1]=b end
local hidden=rows[2]
dfhack.maps.getTileFlags=function(p)return {subterranean=true,hidden=p.x==hidden.centerx}end
df.global.world.buildings.all=vec(rows)
local page=req(15,{cursor=0,query=''})
assert(page.ok and #page.buildings==64 and page.next_cursor==195)
for _,b in ipairs(page.buildings)do assert(b.id~=hidden.id)end
local tail=req(15,{cursor=page.next_cursor,query=''})
assert(tail.ok and #tail.buildings==5 and tail.buildings[1].id==195 and tail.next_cursor==0)
assert(req(15,{cursor=1,query='#3'}).buildings[1].id==30,'cursor is an id lower bound; hidden #3 excluded')
rows={};for i=0,519 do rows[#rows+1]=building(i*2,1)end
df.global.world.buildings.all=vec(rows)
local scan=req(15,{cursor=0,query='no match'})
assert(scan.ok and #scan.buildings==0 and scan.next_cursor==1024,'512-building scan budget')
df.global.world.buildings.all=original;dfhack.maps.getTileFlags=flags
local recipe=req(16,{building_id=0}).recipes[1].key
refusal(17,{building_id=0,recipe='builtin:999:-1'},'Recipe is no longer available at this building')
local stage=carp.getBuildStage;carp.getBuildStage=function()return 2 end
local unfinished=req(16,{building_id=0}).buildings[1]
assert(unfinished.build_stage==2 and unfinished.max_stage==3)
refusal(17,{building_id=0,recipe=recipe},'Building construction is unfinished');carp.getBuildStage=stage
force_link_failure=true
refusal(17,{building_id=0,recipe=recipe},'Native job linking rejected');freed();force_link_failure=false
-- Both queue repeat values, all three status paths, toggles, and cancellation allocation ownership.
for repeating=0,1 do
 local queued=req(17,{building_id=0,recipe=recipe,repeat_job=repeating})
 assert(queued.ok and queued.created_job>=0 and queued.production_jobs[1].repeat_job==(repeating==1))
 local j=carp.jobs[0]
 local row=req(16,{building_id=0}).production_jobs[1]
 assert(row.status=='Awaiting worker or inputs; native cause is not exposed' and not row.suspended and row.worker_id==-1)
 j.worker={id=7}
 row=req(16,{building_id=0}).production_jobs[1]
 assert(row.status=='Worker assigned' and not row.suspended and row.worker_id==7 and row.worker_name=='Worker')
 -- Current bridge pin: e3/findings.md Work-order jobs allows edits; escalated to 06-B E2.
 for _,flag in ipairs{'by_manager','special'}do
  j.flags[flag]=true
  assert(not req(16,{building_id=0}).production_jobs[1].editable)
  refusal(18,{building_id=0,job_id=j.id,cancel=true},'Job is not an editable production job in this building')
  refusal(17,{building_id=0,recipe=recipe},'Building has a special or unsupported job; queue unchanged')
  j.flags[flag]=false
 end
 local job_type=j.job_type;j.job_type=999
 assert(not req(16,{building_id=0}).production_jobs[1].editable)
 refusal(18,{building_id=0,job_id=j.id,cancel=true},'Job is not an editable production job in this building')
 refusal(17,{building_id=0,recipe=recipe},'Building has a special or unsupported job; queue unchanged')
 j.job_type=job_type
 for _,repeat_job in ipairs{1,0}do
  assert(req(18,{building_id=0,job_id=j.id,repeat_job=repeat_job,suspend=-1}).ok)
  assert(j.flags['repeat']==(repeat_job==1))
 end
 local suspended=req(18,{building_id=0,job_id=j.id,repeat_job=-1,suspend=1})
 row=suspended.production_jobs[1]
 assert(suspended.ok and row.suspended and row.worker_id==-1 and row.status=='Suspended by native state' and not j.worker)
 assert(req(18,{building_id=0,job_id=j.id,repeat_job=-1,suspend=0}).ok and not j.flags.suspend)
 assert(req(18,{building_id=0,job_id=j.id,cancel=true}).ok and #carp.jobs==0);freed()
end
for i=1,10 do assert(req(17,{building_id=0,recipe=recipe,repeat_job=0}).ok)end
refusal(17,{building_id=0,recipe=recipe},'Native workshop queue is full (10 jobs)')
assert(#carp.jobs==10)
while #carp.jobs>0 do assert(req(18,{building_id=0,job_id=carp.jobs[0].id,cancel=true}).ok)end
freed()
local profile=carp.getWorkshopProfile
local base=req(16,{building_id=0}).detail
assert(base=='Native workers select and haul inputs; queueing does not guarantee materials or labor. Work orders are not yet exposed.')
carp.getWorkshopProfile=function()return {permitted_workers=vec{7,8}}end
assert(req(16,{building_id=0}).detail==base..' Workshop restricts workers (2).')
carp.getWorkshopProfile=profile
-- Material text and reaction reagent text are taken from native description helpers.
local input=recipes.jobs_workshop[1][1].items[1]
input.mat_type=0;input.mat_index=5;input.quantity=2
input.reaction_class='WOOD_CLASS';input.has_material_reaction_product='PRODUCT'
dfhack.matinfo.decode=function(mt,mi)assert(mt==0 and mi==5);return {toString=function()return 'oak' end}end
local need=req(16,{building_id=0}).recipes[1].requirements[1]
assert(need.description=='WOOD, oak, WOOD_CLASS, PRODUCT' and need.quantity==2 and need.item_type==5)
input.mat_type=nil;input.mat_index=nil;input.quantity=nil;input.reaction_class=nil;input.has_material_reaction_product=nil
reaction.reagents[0].getDescription=function(_,id)assert(id==0);return 'native brew reagent' end
reaction.reagents[0].contribute_to_job_req=function(_,target,ri,rx)
 local f=df.job_item.new();f.reaction_id=rx;f.reagent_index=ri;f.quantity=3;f.item_type=5;target.elements:insert('#',f)
end
df.reaction.find=function(id)assert(id==0);return reaction end
need=req(16,{building_id=2}).recipes[1].requirements[1]
assert(need.description=='native brew reagent' and need.quantity==3 and need.item_type==5)
-- Reproduce the real Kitchen template; NONE requirement prose is a 06-B native gap.
local kitchen_state=req(16,{building_id=1})
assert(kitchen_state.recipes[1].key=='builtin:114:2' and kitchen_state.recipes[1].name=='prepare easy meal')
local descriptions={'NONE, unrotten, cookable, solid','NONE, unrotten, cookable'}
for i,need in ipairs(kitchen_state.recipes[1].requirements)do
 assert(need.description==descriptions[i] and need.quantity==1 and need.item_type==-1)
end
local queued=req(17,{building_id=1,recipe='builtin:114:2',repeat_job=1})
assert(queued.ok and queued.production_jobs[1].job_type==114 and #queued.production_jobs[1].requirements==2)
for i,need in ipairs(queued.production_jobs[1].requirements)do
 assert(need.description==descriptions[i] and need.quantity==1 and need.item_type==-1)
end
assert(req(18,{building_id=1,job_id=queued.created_job,cancel=true}).ok);freed()
-- Zero seeds do not gate any season; fallow works in all four seasons.
df.global.world.items.other.SEEDS=vec()
refusal(17,{building_id=3,recipe=recipe},'Select seasonal farm crops instead')
refusal(19,{building_id=0,season=0,crop_id=0},'A farm plot is required')
for season=0,3 do
 local selected=req(19,{building_id=3,season=season,crop_id=0})
 assert(selected.ok and selected.seasonal_crops[season+1]==0 and selected.crops[1].seeds==0)
 assert(req(19,{building_id=3,season=season,crop_id=-1}).ok and farm.plant_id[season]==-1)
end
refusal(19,{building_id=3,season=1,crop_id=1},'Crop is not eligible for this farm and growing season')
refusal(19,{building_id=3,season=0,crop_id=99},'Crop is not eligible for this farm and growing season')
df.global.cur_season_tick=0
local early=req(16,{building_id=3})
assert(early.ok and #early.crops==2 and early.crops[1].seasons==15 and early.crops[2].seasons==1)
assert(early.current_season==0 and #early.seasonal_crops==4 and #early.production_jobs==0 and #early.recipes==0)
farm.x1=4;farm.x2=5;farm.y1=6;farm.y2=6
for _,mode in ipairs{'hidden','mixed underground'}do
 dfhack.maps.getTileFlags=function(p)return {subterranean=p.x~=4 or mode=='hidden',hidden=p.x==4 and mode=='hidden'}end
 refusal(16,{building_id=3},'Mixed or hidden farm environment is not supported')
end
dfhack.maps.getTileFlags=function()return {subterranean=false}end
dfhack.maps.getTileBiomeRgn=function(p)return p.x end
dfhack.maps.getBiomeType=function(x)return x end
df.biome_type[4]='FOREST';df.biome_type[5]='GRASSLAND'
refusal(16,{building_id=3},'Mixed-biome farm is not supported')
-- Current bridge pin: e10/findings.md #10 has no size cap; escalated to 06-B E7.
dfhack.maps.getTileFlags=flags;farm.x2=35
refusal(16,{building_id=3},'Farm exceeds supported 31 by 31 inspector')
farm.x1=nil;farm.x2=nil;farm.y1=nil;farm.y2=nil
freed()
""")
print('PRODUCTION_ADAPTER PASS')
