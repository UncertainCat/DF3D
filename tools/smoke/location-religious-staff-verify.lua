-- Protected paused clone diagnostics; observe world records independently of wire replies.
local out,index=...
local json=require('json')
local f=assert(io.open(out..'/request-'..index..'.json'));local request=json.decode(f:read('*a'));f:close()
assert(df.global.pause_state and df.global.world.frame_counter==0,'paused clone required')
local site=assert(dfhack.world.getCurrentSite());local temple
for _,v in ipairs(site.buildings)do if v.id==0 and df.abstract_building_templest:is_instance(v)then temple=v;break end end
assert(temple and temple.deity_type==df.religious_practice_type.RELIGION_ENID)
local entity=assert(df.historical_entity.find(temple.deity_data.Religion));local assignment
for _,a in ipairs(entity.positions.assignments)do if a.st_id==site.id then assert(not assignment);assignment=a end end
assert(assignment)
local result={status='passed',site_id=site.id,location_id=temple.id,entity_id=entity.id,assignment_id=assignment.id}
local function same_specialization(a,b)
 -- Godot serializes fixture numbers as floats; compare numeric values, not
 -- JSON spellings (1056 and1056.0 are the same captured bitfield).
 return a.flags4==b.flags4 and a.specialized==b.specialized and json.encode(a.labors)==json.encode(b.labors)
end
local function receipt()
 local text,code=dfhack.run_command_silent('df3d','location-religious-receipt',tostring(site.id),tostring(temple.id),tostring(entity.id),tostring(assignment.id))
 assert(code==0,text);local r=json.decode(text);assert(r.valid);return r
end
local function capture()
 local holder=assert(df.historical_figure.find(assert(_G.df3d_religious_holder)))
 local state={holder=assignment.histfig,holder2=assignment.histfig2,position=assignment.position_id,squad=assignment.squad_id,
  events=#df.global.world.history.events,positions=#entity.positions.own,assignments=#entity.positions.assignments,
  next_position=entity.positions.next_position_id,next_assignment=entity.positions.next_assignment_id,links={}}
 for _,link in ipairs(holder.entity_links)do
  state.links[#state.links+1]={type=link:getType(),entity=link.entity_id,strength=link.link_strength,position=link:getPosition(),start_year=link:getPositionStartYear(),end_year=link:getPositionEndYear()}
 end
 local unit=df.unit.find(holder.unit_id)
 if unit then state.unit={id=unit.id,profession=unit.profession,profession2=unit.profession2,squad=unit.military.squad_id,position=unit.military.squad_position,job=unit.job.current_job and unit.job.current_job.id or -1}end
 return state
end
if request.op=='religious_assignments' then
 local unit=assert(df.unit.find(request.unit_id));result.unit_id=unit.id;result.histfig_id=unit.hist_figure_id
 result.occupation_id=-1;result.entity_id=-1;result.assignment_id=-1
 if assignment.histfig==unit.hist_figure_id then result.entity_id=entity.id;result.assignment_id=assignment.id
 else for _,o in ipairs(temple.occupations)do if o.unit_id==unit.id then result.occupation_id=o.id end end;assert(result.occupation_id>=0)end
 result.entries={}
 local function add(kind,id,type,subtype,custom,name)
  result.entries[#result.entries+1]={kind=kind,id=id,type=type,subtype=subtype,custom=custom,name=name}
 end
 for _,o in ipairs(unit.occupations)do add(0,o.id,o.type,-1,-1,'')end
 for kind,key in ipairs{'WORKSHOP_ANY','FURNACE_ANY'}do
  for _,b in ipairs(df.global.world.buildings.other[key])do
   local profile=b:getWorkshopProfile()
   if profile then for _,id in ipairs(profile.permitted_workers)do
    if id==unit.id then add(kind,b.id,b:getType(),b:getSubtype(),b:getCustomType(),'')end
   end end
  end
 end
 for i,d in ipairs(df.global.plotinfo.labor_info.work_details)do
  for _,id in ipairs(d.assigned_units)do if id==unit.id then add(3,i,d.icon,-1,-1,dfhack.df2utf(d.name))end end
 end
elseif request.op=='religious_assignments_fixture' then
 if request.restore then
  for _,r in ipairs(assert(_G.df3d_assignments_restore))do
   r.vector:resize(0);for _,id in ipairs(r.before)do r.vector:insert('#',id)end
  end
  _G.df3d_assignments_restore=nil
 else
  assert(not _G.df3d_assignments_restore);_G.df3d_assignments_restore={}
  local function add(vector)
   local before={};for _,id in ipairs(vector)do before[#before+1]=id;assert(id~=6536)end
   _G.df3d_assignments_restore[#_G.df3d_assignments_restore+1]={vector=vector,before=before}
   local values={table.unpack(before)};values[#values+1]=6536;table.sort(values)
   vector:resize(0);for _,id in ipairs(values)do vector:insert('#',id)end
  end
  for _,key in ipairs{'WORKSHOP_ANY','FURNACE_ANY'}do
   local found=false
   for _,b in ipairs(df.global.world.buildings.other[key])do
    local p=b:getWorkshopProfile();if p then add(p.permitted_workers);found=true;break end
   end
   assert(found)
  end
  add(assert(df.global.plotinfo.labor_info.work_details[0]).assigned_units)
 end
elseif request.op=='religious_specialization_setup' then
 local unit=assert(df.unit.find(request.unit_id));result.unit_id=unit.id
 result.occupation_id=-1;result.entity_id=-1;result.assignment_id=-1
 local holder=assert(df.historical_figure.find(assignment.histfig))
 if holder.unit_id==unit.id then result.entity_id=entity.id;result.assignment_id=assignment.id
 else
  for _,o in ipairs(temple.occupations)do if o.unit_id==unit.id then assert(result.occupation_id==-1);result.occupation_id=o.id end end
  assert(result.occupation_id>=0)
 end
 local original={}
 for _,u in ipairs(df.global.world.units.active)do
  local labors={};for i=0,df.unit_labor._last_item do labors[#labors+1]=u.status.labors[i]end
  original[tostring(u.id)]={flags4=u.flags4.whole,specialized=u.flags4.only_do_assigned_jobs,labors=labors}
 end
 assert(same_specialization(original[tostring(unit.id)],request.expected),'native specialization initial state mismatch')
 _G.df3d_specialization_before=original
elseif request.op=='religious_specialization_check' then
 local original=assert(_G.df3d_specialization_before)
 for _,unit in ipairs(df.global.world.units.active)do
  local labors={};for i=0,df.unit_labor._last_item do labors[#labors+1]=unit.status.labors[i]end
  local actual={flags4=unit.flags4.whole,specialized=unit.flags4.only_do_assigned_jobs,labors=labors}
  local expected=unit.id==request.unit_id and request.expected or original[tostring(unit.id)]
  assert(same_specialization(actual,expected),'specialization native effects mismatch '..unit.id)
 end
elseif request.op=='religious_specialization_change' then
 local unit=assert(df.unit.find(request.unit_id))
 if request.restore then unit.profession=assert(_G.df3d_specialization_profession)
 else _G.df3d_specialization_profession=unit.profession;unit.profession=df.profession.BABY end
elseif request.op=='religious_setup' then
 if request.absent then
  local holder=assert(df.historical_figure.find(assignment.histfig));holder.unit_id=-1
 end
 assert(assignment.histfig>=0);_G.df3d_religious_holder=assignment.histfig;result.holder_id=assignment.histfig;result.before=capture()
 _G.df3d_religious_before=result.before
elseif request.op=='religious_guard' then
 local guards={}
 for _,object in ipairs{df.global.game.main_interface,df.global.gps}do
  local size,address=df.sizeof(object);local bytes=df.new('uint8_t',size);dfhack.internal.memmove(bytes,address,size)
  guards[#guards+1]={bytes=bytes,address=address,size=size}
 end
 _G.df3d_religious_guard={state=capture(),ui=guards}
elseif request.op=='religious_unchanged' or request.op=='religious_applied' or request.op=='religious_assignment_applied' then
 local guard=assert(_G.df3d_religious_guard);result.ui_changed={}
 for i,v in ipairs(guard.ui)do result.ui_changed[i]=dfhack.internal.memcmp(v.bytes,v.address,v.size)~=0;df.delete(v.bytes)end
 assert(not result.ui_changed[1],"religious request changed native main interface")
 _G.df3d_religious_guard=nil
 result.after=capture()
 if request.op=='religious_unchanged' then assert(json.encode(result.after)==json.encode(guard.state),'refusal changed native records')
 elseif request.op=='religious_assignment_applied' then
  local unit=assert(df.unit.find(request.unit_id));local figure=assert(df.historical_figure.find(request.histfig_id))
  assert(unit.hist_figure_id==figure.id and assignment.histfig==figure.id and assignment.histfig2==figure.id)
  assert(result.after.events==guard.state.events+1,'assignment event count')
  local links=0
  for _,link in ipairs(figure.entity_links)do
   if link:getType()==df.histfig_entity_link_type.POSITION and link.entity_id==entity.id and link:getPosition()==assignment.id then links=links+1 end
  end
  assert(links==1,'selected position link missing')
  local event=df.global.world.history.events[#df.global.world.history.events-1]
  assert(df.history_event_add_hf_entity_linkst:is_instance(event) and event.civ==entity.id and event.histfig==figure.id and event.position_id==assignment.position_id)
 else
  local before=assert(_G.df3d_religious_before);local after=result.after
  assert(after.holder==-1 and after.holder2==before.holder2 and after.events==before.events+1,'native removal effects missing')
  for _,key in ipairs{'position','squad','positions','assignments','next_position','next_assignment','unit'}do assert(json.encode(before[key])==json.encode(after[key]),'unrelated native field changed '..key)end
  assert(#before.links==#after.links,'unexpected link count')
  local former=0
  for _,link in ipairs(after.links)do
   if link.entity==entity.id and link.type==df.histfig_entity_link_type.POSITION then assert(link.position~=assignment.id,'active assignment link retained')end
   if link.entity==entity.id and link.type==df.histfig_entity_link_type.FORMER_POSITION and link.position==assignment.id then former=former+1;assert(link.end_year==df.global.cur_year)end
  end
  assert(former==1,'former-position link missing')
  local retained={}
  for _,link in ipairs(before.links)do
   if not (link.entity==entity.id and link.type==df.histfig_entity_link_type.POSITION and link.position==assignment.id)then retained[#retained+1]=link end
  end
  assert(#retained==#after.links-1)
  for i,link in ipairs(retained)do assert(json.encode(link)==json.encode(after.links[i]),'unrelated holder link changed')end
  local event=df.global.world.history.events[#df.global.world.history.events-1]
  assert(df.history_event_remove_hf_entity_linkst:is_instance(event))
  assert(event.civ==entity.id and event.histfig==before.holder and event.position_id==assignment.position_id)
  result.event={id=event.id,civ=event.civ,histfig=event.histfig,position_id=event.position_id,link_type=event.link_type,year=event.year,seconds=event.seconds}
 end
elseif request.op=='religious_candidates_readback' then
 local text,code=dfhack.run_command_silent('df3d','location-religious-candidate-rows',tostring(site.id),tostring(temple.id),tostring(entity.id),tostring(assignment.id))
 assert(code==0,text);local rows=json.decode(text).rows;assert(#rows==#request.rows)
 for i,row in ipairs(rows)do
  for _,key in ipairs{'unit_id','histfig_id','score','source_index','profession_order','status_order','skills'}do
   assert(json.encode(row[key])==json.encode(request.rows[i][key]),'candidate transport mismatch '..key)
  end
 end
elseif request.op=='religious_assignment_readback' then
 local text,code=dfhack.run_command_silent('df3d','location-religious-assignment-receipt',tostring(site.id),tostring(temple.id),tostring(entity.id),tostring(assignment.id),tostring(request.unit_id))
 assert(code==0,text);local r=json.decode(text)
 assert(r.valid and r.eligible and r.revision==request.revision and r.histfig_id==request.histfig_id and r.nemesis_id==request.nemesis_id,'selected receipt mismatch')
elseif request.op=='religious_assignment_change' then
 local unit=assert(df.unit.find(request.unit_id))
 if request.restore then unit.uniform.pickup_flags.whole=assert(_G.df3d_religious_pickup)
 else _G.df3d_religious_pickup=unit.uniform.pickup_flags.whole;unit.uniform.pickup_flags.whole=unit.uniform.pickup_flags.whole~1 end
elseif request.op=='religious_change' then
 if request.restore then assignment.histfig2=assert(_G.df3d_religious_original_holder2)
 else _G.df3d_religious_original_holder2=assignment.histfig2;assignment.histfig2=-1 end
elseif request.op=='religious_readback' then
 local current=receipt();assert(request.revision==current.revision,'revision precision lost')
 for _,key in ipairs{'holder_id','position_id','unit_id','removable'}do assert(request.snapshot[key]==current[key],'receipt mismatch '..key)end
 assert(request.snapshot.site_id==site.id and request.snapshot.location_id==temple.id and request.snapshot.entity_id==entity.id and request.snapshot.assignment_id==assignment.id)
else error('unknown religious operation')end
f=assert(io.open(out..'/response-'..index..'.json','w'));f:write(json.encode(result));f:close()
print('SEMANTIC_PASS '..index..' '..request.op)
