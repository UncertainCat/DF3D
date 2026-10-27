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
if request.op=='religious_setup' then
 assert(assignment.histfig>=0);_G.df3d_religious_holder=assignment.histfig;result.holder_id=assignment.histfig;result.before=capture()
 _G.df3d_religious_before=result.before
elseif request.op=='religious_guard' then
 local guards={}
 for _,object in ipairs{df.global.game.main_interface,df.global.gps}do
  local size,address=df.sizeof(object);local bytes=df.new('uint8_t',size);dfhack.internal.memmove(bytes,address,size)
  guards[#guards+1]={bytes=bytes,address=address,size=size}
 end
 _G.df3d_religious_guard={state=capture(),ui=guards}
elseif request.op=='religious_unchanged' or request.op=='religious_applied' then
 local guard=assert(_G.df3d_religious_guard);result.ui_changed={}
 for i,v in ipairs(guard.ui)do result.ui_changed[i]=dfhack.internal.memcmp(v.bytes,v.address,v.size)~=0;df.delete(v.bytes)end
 assert(not result.ui_changed[1],"religious request changed native main interface")
 _G.df3d_religious_guard=nil
 result.after=capture()
 if request.op=='religious_unchanged' then assert(json.encode(result.after)==json.encode(guard.state),'refusal changed native records')
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
