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
local recipes={input_filter_defaults={item_type=-1,item_subtype=-1,mat_type=-1,mat_index=-1,quantity=1,flags1={},flags2={},flags3={}},jobs_workshop={
 [1]={defaults={item_type=5,vector_id=5},{name='construct bed',items={{}},job_fields={job_type=27}}},
 [2]={{name='meal easy',items={{flags1={cookable=true,solid=true}},{flags1={cookable=true}}},job_fields={job_type=28,mat_type=2}}}
},jobs_furnace={}}
package.preload.utils=function()return utils end
package.preload['dfhack.workshops']=function()return recipes end
local jobs={}
local next_id=10
local filters_alive=0
local jobs_alive=0
local function instance(k)return {is_instance=function(_,b)return b.kind==k end}end
df={building_workshopst=instance('workshop'),building_furnacest=instance('furnace'),building_farmplotst=instance('farm'),
 workshop_type={[1]='Carpenters',[2]='Kitchen',[3]='Still'},furnace_type={},item_type={[5]='WOOD',[-1]='Any'},biome_type={[0]='SUBTERRANEAN_WATER'},
 job_type={CustomReaction=99},reaction={find=function()return nil end},historical_entity={find=function()return {id=7,entity_raw={workshops={permitted_reaction_id=vec{0}}}}end}}
df.job_item={new=function()
 filters_alive=filters_alive+1
 local f={item_type=-1,quantity=1,mat_type=-1,mat_index=-1,flags1={},flags2={},flags3={},reaction_class='',has_material_reaction_product='',reaction_id=-1,reagent_index=-1}
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
df.general_ref_building_holderst={new=function()return {delete=function()end}end}
local function building(id,t,k)
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
 jobs[j.id]=nil;j:delete();return true
end
function counts()return filters_alive,jobs_alive end
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
local f,j=counts();assert(f==0 and j==0,'read-only and canceled job allocations all freed')
''')
print('PRODUCTION_ADAPTER PASS')
