-- Development fixture: owned disposable clone, paused, never saved. No UI inputs.
local out=...
local json=require('json')
df.global.pause_state=true
-- The lane module stages init.txt only. Stage d_init in memory, never on disk;
-- preserve the original even if fixture setup fails or is retried.
if not _G.df3d_work_orders_acceptance_prefs then
 local saved={autosave=df.global.d_init.feature.autosave,announcements={}}
 for id,flags in ipairs(df.global.d_init.announcements.flags)do saved.announcements[id]=flags.whole end
 _G.df3d_work_orders_acceptance_prefs=saved
end
df.global.d_init.feature.autosave=df.d_init_autosave.NONE
for _,flags in ipairs(df.global.d_init.announcements.flags)do flags.PAUSE=false;flags.DO_MEGA=false end
local function incomplete(reason) print('FIXTURE_INCOMPLETE '..reason) end
local function center(b) return {x=b.centerx,y=b.centery,z=b.z} end
local function available(u)
 return dfhack.units.isCitizen(u) and dfhack.units.isActive(u) and not dfhack.units.isDead(u)
  and dfhack.units.isAdult(u) and dfhack.units.isSane(u) and dfhack.units.isJobAvailable(u)
end
local function free_log(item)
 local f=item.flags
 return f.on_ground and not (f.in_job or f.in_building or f.in_inventory or f.removed
  or f.garbage_collect or f.trader or f.owned or f.dump)
end
local function setup()
 local world=df.global.world
 local entity=df.historical_entity.find(df.global.plotinfo.group_id)
 if not entity then return 'no fortress entity' end
 local responsibility=df.entity_position_responsibility.MANAGE_PRODUCTION
 local position
 for _,p in ipairs(entity.positions.own) do
  if p.responsibilities[responsibility] then position=p;break end
 end
 if not position then return 'no MANAGE_PRODUCTION position' end
 local assignment
 for _,a in ipairs(entity.positions.assignments) do
  if a.position_id==position.id then assignment=a;break end
 end
 if not assignment then return 'no MANAGE_PRODUCTION position assignment' end
 local unit
 for _,u in ipairs(world.units.active) do
  if available(u)
   and df.historical_figure.find(u.hist_figure_id) then
   unit=unit or u
   if u.hist_figure_id==assignment.histfig then unit=u;break end
  end
 end
 if not unit then return 'no free adult citizen with a histfig for manager' end
 local office,chair
 for _,b in ipairs(world.buildings.other.ACTIVITY_ZONE) do
  if b.type==df.civzone_type.Office then
   for _,c in ipairs(b.contained_buildings) do
    if df.building_chairst:is_instance(c) and c:getBuildStage()==c:getMaxBuildStage()
     and dfhack.maps.canWalkBetween(unit.pos,center(c)) then office=b;chair=c;break end
   end
   if office then break end
  end
 end
 if not office then return 'no reachable Office with a built chair' end
 local by_type=entity.assignments_by_type[responsibility]
 if not by_type then return 'no MANAGE_PRODUCTION assignment index' end
 local hf=df.historical_figure.find(unit.hist_figure_id)
 if assignment.histfig>=0 and assignment.histfig~=hf.id then
  local old=df.historical_figure.find(assignment.histfig)
  if old then for i=#old.entity_links-1,0,-1 do
   local link=old.entity_links[i]
   if df.histfig_entity_link_positionst:is_instance(link) and link.entity_id==entity.id
    and link.assignment_id==assignment.id then old.entity_links:erase(i);link:delete() end
  end end
 end
 assignment.histfig=hf.id
 local indexed=false
 for _,a in ipairs(by_type) do if a.id==assignment.id then indexed=true;break end end
 if not indexed then by_type:insert('#',assignment) end
 local linked=false
 for _,link in ipairs(hf.entity_links) do
  if df.histfig_entity_link_positionst:is_instance(link) and link.entity_id==entity.id
   and link.assignment_id==assignment.id then linked=true;break end
 end
 if not linked then
  local link=df.histfig_entity_link_positionst:new()
  link.entity_id=entity.id;link.assignment_id=assignment.id
  link.start_year=df.global.cur_year;link.link_strength=100
  hf.entity_links:insert('#',link)
 end
 dfhack.buildings.setOwner(office,unit)
 office.spec_sub_flag.active=true
 if office.assigned_unit_id~=unit.id then return 'Office ownership could not be assigned' end
 local manager=false
 for _,n in ipairs(dfhack.units.getNoblePositions(unit) or {}) do
  if n.entity.id==entity.id and n.position.responsibilities[responsibility] then manager=true end
 end
 if not manager then return 'manager noble position did not resolve after assignment' end
 -- Keep the administrator off hauling; do not fabricate validated/active flags.
 -- E6/E10: only_do_assigned_jobs and effective labors are distinct state.
 unit.flags4.only_do_assigned_jobs=true
 for labor in pairs(unit.status.labors) do unit.status.labors[labor]=false end
 local shop,worker
 for _,b in ipairs(world.buildings.all) do
  if df.building_workshopst:is_instance(b) and b.type==df.workshop_type.Carpenters
   and b:getBuildStage()==b:getMaxBuildStage() and not b.flags.almost_deleted then
   local targeted=false
   for _,o in ipairs(world.manager_orders.all) do if o.workshop_id==b.id then targeted=true;break end end
   if not targeted then
    for _,u in ipairs(world.units.active) do
     if u.id~=unit.id and available(u) and dfhack.maps.canWalkBetween(u.pos,center(b)) then
      shop=b;worker=u;break
     end
    end
   end
   if shop then break end
  end
 end
 if not shop then return 'no built untargeted Carpenter workshop with a free reachable worker' end
 -- Remove clone-only backlog through DFHack (releases worker/item references).
 for i=#shop.jobs-1,0,-1 do
  if not dfhack.job.removeJob(shop.jobs[i]) then return 'could not clear Carpenter workshop jobs' end
 end
 local profile=shop.profile
 profile.permitted_workers:resize(0);profile.permitted_workers:insert('#',worker.id)
 profile.min_level=0;profile.max_level=3000
 profile.blocked_labors[df.unit_labor.CARPENTER]=false
 -- Reserve capacity for the explicitly targeted test order. Older general bed/bin
 -- orders otherwise refill it before the new order (pass 4 had both in flight).
 profile.max_general_orders=0;profile.flags.block_general_orders=true
 local function unlink_source(links)
  for i=#links.give_to_workshop-1,0,-1 do
   if links.give_to_workshop[i].id==shop.id then links.give_to_workshop:erase(i) end
  end
 end
 for _,b in ipairs(profile.links.take_from_pile) do unlink_source(b.links) end
 for _,b in ipairs(profile.links.take_from_workshop) do unlink_source(b.profile.links) end
 profile.links.take_from_pile:resize(0);profile.links.take_from_workshop:resize(0)
 worker.flags4.only_do_assigned_jobs=true
 for labor in pairs(worker.status.labors) do worker.status.labors[labor]=false end
 worker.status.labors[df.unit_labor.CARPENTER]=true
 local materials={}
 for _,item in ipairs(world.items.other.WOOD) do
  if free_log(item) and dfhack.maps.canWalkBetween(item.pos,center(shop)) then
   item.flags.forbid=false
   assert(dfhack.items.moveToGround(item,center(shop)),'could not stage reachable log')
   materials[#materials+1]=item.id
   if #materials==10 then break end
  end
 end
 if #materials<10 then return 'need 10 free reachable logs; found '..#materials end
 local state={out=out,completed={},native_ids={},manager=unit.id,office=office.id,
  workshop=shop.id,worker=worker.id,materials=materials}
 -- df.workquota.xml: status has validated/active; is_validated is orders JSON,
 -- not a manager_order member (orders.cpp export/import; workorder.lua:278-279
 -- deliberately ignores those JSON flags when creating fresh orders).
 -- df.plotinfo.xml exposes manager_timer (quota_checktime) and nobles.manager_cooldown
 -- (0..1008), not a proven dispatch interval. Leave both and the 3600-tick cap alone:
 -- insertion of an unvalidated order lets DF schedule its own office validation.
 function state.prepare_dispatch(o)
  assert(o.job_type==df.job_type.ConstructBed and o.mat_type==-1 and o.mat_index==-1,
   'dispatch fixture requires an unrestricted bed order')
  assert(#o.item_conditions==0 and #o.order_conditions==0,'dispatch fixture requires no conditions')
  -- This is fixture routing, not validation or job creation. DF must set both flags
  -- and produce real jobs. Explicit orders are independent of general-order limits.
  o.workshop_id=shop.id
 end
 function state.dispatch_diagnostics(o)
  local d={blockers={},order=o and {id=o.id,status=o.status.whole,validated=o.status.validated,
   active=o.status.active,remaining=o.amount_left,frequency=o.frequency,workshop_id=o.workshop_id,
   item_conditions=#o.item_conditions,order_conditions=#o.order_conditions,
   finished_year=o.finished_year,finished_year_tick=o.finished_year_tick} or {missing=true},
   manager_timer=df.global.plotinfo.manager_timer,manager_cooldown=df.global.plotinfo.nobles.manager_cooldown,
   workshop={id=shop.id,type=shop.type,jobs=#shop.jobs,max_general_orders=profile.max_general_orders,
    block_general_orders=profile.flags.block_general_orders,blocked_labor=profile.blocked_labors[df.unit_labor.CARPENTER]},
   material_count=0,required_materials=10,popup_count=#world.status.popups}
  local function unit_state(u,target)
   local j=u.job.current_job
   return {id=u.id,job_id=j and j.id or -1,job_type=j and j.job_type or -1,
    available=dfhack.units.isJobAvailable(u),only_assigned=u.flags4.only_do_assigned_jobs,
    carpentry=u.status.labors[df.unit_labor.CARPENTER],reachable=dfhack.maps.canWalkBetween(u.pos,target)}
  end
  d.worker=unit_state(worker,center(shop));d.manager=unit_state(unit,center(chair))
  d.office={id=office.id,owner=office.assigned_unit_id,active=office.spec_sub_flag.active,chair=chair.id}
  for _,item in ipairs(world.items.other.WOOD) do
   if free_log(item) and not item.flags.forbid and dfhack.maps.canWalkBetween(item.pos,center(shop)) then
    d.material_count=d.material_count+1
   end
  end
  local function blocked(test,text) if test then d.blockers[#d.blockers+1]=text end end
  blocked(not o,'order missing')
  if o then
   blocked(not o.status.validated,'order not validated');blocked(not o.status.active,'order not active')
   blocked(o.workshop_id~=shop.id,'order not routed to reserved workshop')
  end
  blocked(#shop.jobs>0,'workshop has jobs; inspect job order ids')
  d.workshop.jobs_detail={}
  for _,j in ipairs(shop.jobs) do
   local u=dfhack.job.getWorker(j)
   d.workshop.jobs_detail[#d.workshop.jobs_detail+1]={id=j.id,order_id=j.order_id,
    suspended=j.flags.suspend,worker=u and u.id or -1}
  end
  blocked(not d.worker.available,'candidate worker unavailable')
  blocked(not d.worker.carpentry,'candidate carpentry disabled')
  blocked(not d.worker.reachable,'candidate cannot reach workshop')
  blocked(d.material_count<10,'fewer than 10 free reachable unforbidden logs')
  blocked(not d.manager.reachable or not d.office.active or d.office.owner~=unit.id,'manager office inaccessible/inactive/unowned')
  blocked(not d.manager.available,'manager busy; inspect current job')
  blocked(d.popup_count>0,'announcement popup blocks simulation')
  return d
 end
 for _,o in ipairs(world.manager_orders.all) do
  if o.items and #o.items.elements>0 then state.native_ids[#state.native_ids+1]=o.id end
 end
 -- Reuse the designation guard's read-only map fingerprint without its fixture.
 _G.df3d_designation_acceptance={{tile={x=unit.pos.x,y=unit.pos.y,z=unit.pos.z}}}
 local eventful=require('plugins.eventful')
 eventful.enableEvent(eventful.eventType.JOB_COMPLETED,1)
 eventful.onJobCompleted.df3d_work_orders_acceptance=function(job)
  if job.order_id>=0 then state.completed[job.id]={order_id=job.order_id,tick=df.global.cur_year*403200+df.global.cur_year_tick} end
 end
 _G.df3d_work_orders_acceptance=state
 local site=df.world_site.find(df.global.plotinfo.site_id)
 local fixture={native_ids=state.native_ids,manager=unit.id,office=office.id,
  preferred_job=df.job_type.ConstructBed,fort=site and dfhack.translation.translateName(site.name,true) or ''}
 local f=assert(io.open(out..'/fixture.json','w'));f:write(json.encode(fixture));f:close()
 print('FIXTURE_READY manager='..unit.id..' office='..office.id..' workshop='..shop.id..' worker='..worker.id..' logs='..#materials)
end
local ok,reason=pcall(setup)
if not ok then incomplete('manager/office/event prerequisite: '..tostring(reason))
elseif reason then incomplete(reason) end
