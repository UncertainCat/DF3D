-- Controlled native display fixtures only: no trap simulation or load completion.
local out,view,b,capture=...
local gui=require('gui');local json=require('json')
local refs={};local created;local job
local saved={state=b.state,ready=b.ready_timeout,fill=b.fill_timer,flags=b.stop_flags.whole}
local evidence={subtype=b.trap_type,building_id=b.id,scope='Paused controlled no-link, loaded-item and loading-job display. Not native construction or loading simulation.'}
local function shot(stage)
 view:render(dfhack.getTickCount());capture('trap-state-'..b.trap_type..'-'..stage)
end
local ok,err=xpcall(function()
 for _,held in ipairs(b.contained_items)do
  local list=held.item.general_refs
  for i=#list-1,0,-1 do
   local ref=list[i];local kind=ref:getType()
   if kind==df.general_ref_type.BUILDING_TRIGGER or kind==df.general_ref_type.BUILDING_TRIGGERTARGET then
    refs[#refs+1]={list=list,index=i,ref=ref};list:erase(i)
   end
  end
 end
 shot('unlinked')
 b.state=1;b.ready_timeout=10;b.fill_timer=10;b.stop_flags.whole=1
 shot('inactive')
 if b.trap_type<5 then
  local worker
  for _,unit in ipairs(df.global.world.units.active)do if dfhack.units.isCitizen(unit)then worker=unit;break end end
  local kind=({[2]=df.item_type.CAGE,[3]=df.item_type.BOULDER,[4]=df.item_type.WEAPON})[b.trap_type]
  local material=assert(b.contained_items[0].item)
  local mat_type,mat_index=material:getMaterial(),material:getMaterialIndex()
  if kind~=df.item_type.BOULDER then
   local iron=assert(dfhack.matinfo.find('INORGANIC:IRON'));mat_type=iron.type;mat_index=iron.index
  end
  local items=dfhack.items.createItem(assert(worker),kind,kind==df.item_type.WEAPON and 0 or -1,mat_type,mat_index)
  assert(#items==1);created=items[1];assert(dfhack.items.moveToBuilding(created,b,0,true))
  evidence.loaded_item=created.id;shot('loaded')
  job=df.job:new();job.job_type=({[2]=df.job_type.LoadCageTrap,[3]=df.job_type.LoadStoneTrap,[4]=df.job_type.LoadWeaponTrap})[b.trap_type]
  job.pos:assign{x=b.centerx,y=b.centery,z=b.z}
  local ref=df.general_ref_building_holderst:new();ref.building_id=b.id;job.general_refs:insert('#',ref)
  assert(dfhack.job.linkIntoWorld(job,true));b.jobs:insert('#',job)
  evidence.job_type=job.job_type;shot('loading')
 end
 local stage=b.trap_type<5 and 'loading' or 'inactive'
 local f=assert(io.open(out..'/trap-sheet-expected.json','w'))
 f:write(json.encode{id=b.id,tile={b.centerx,b.centery,b.z},observe_only=true,reference='trap-state-'..b.trap_type..'-'..stage});f:close()
 local label='trap-sheet-wire-state-'..b.trap_type;capture(label)
 f=assert(io.open(out..'/'..label..'-result.json'));evidence.viewer=json.decode(f:read('*a'));f:close()
 assert(evidence.viewer.success,'Trap state viewer failed')
end,debug.traceback)
if job then assert(dfhack.job.removeJob(job))end
if created then created.flags.in_building=false;assert(dfhack.items.remove(created))end
for i=#refs,1,-1 do local entry=refs[i];entry.list:insert(entry.index,entry.ref)end
b.state=saved.state;b.ready_timeout=saved.ready;b.fill_timer=saved.fill;b.stop_flags.whole=saved.flags
assert(ok,err)
return evidence
