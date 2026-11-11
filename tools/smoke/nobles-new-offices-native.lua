-- Protected native oracle only: repeated NEW rows and military reassignment.
local out,view=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local info=df.global.game.main_interface.info;local g=df.global.gps
local function settle()for _=1,3 do script.sleep(1,'frames')end;view:render(dfhack.getTickCount())end
local function click(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=y//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1;settle()
end
local function snapshot(entity)
 local result={assignments={},next_assignment=entity.positions.next_assignment_id,events=#df.global.world.history.events,units={},squads={}}
 for _,a in ipairs(entity.positions.assignments)do result.assignments[#result.assignments+1]={id=a.id,position=a.position_id,holder=a.histfig,holder2=a.histfig2,squad=a.squad_id}end
 for _,u in ipairs(df.global.world.units.active)do
  local row={id=u.id,profession=u.profession,profession2=u.profession2,squad=u.military.squad_id,position=u.military.squad_position,job=u.job.current_job and u.job.current_job.id or -1,links={}}
  local hf=df.historical_figure.find(u.hist_figure_id)
  if hf then for _,link in ipairs(hf.entity_links)do row.links[#row.links+1]={type=link:getType(),entity=link.entity_id,strength=link.link_strength,position=link:getPosition(),start_year=link:getPositionStartYear(),end_year=link:getPositionEndYear()}end end
  result.units[#result.units+1]=row
 end
 for _,squad in ipairs(df.global.world.squads.all)do
  local row={id=squad.id,occupants={}}
  for _,slot in ipairs(squad.positions)do row.occupants[#row.occupants+1]=slot.occupant end
  result.squads[#result.squads+1]=row
 end
 return result
end
assert(not info.open and df.global.pause_state and df.global.world.frame_counter==0)
if os.getenv('DF3D_NOBLES_NEW_OFFICES_WIRE')=='1' then
 local path=debug.getinfo(1,'S').source:sub(2):gsub('tools/smoke/nobles%-new%-offices%-native%.lua$','fixtures/production/native_nobles.json')
 local f=assert(io.open(path));local reference=json.decode(f:read('*a')).new_offices_reference;f:close()
 f=assert(io.open(out..'/nobles-new-offices-reference.json','w'));f:write(json.encode(reference));f:close()
 local entity=assert(df.historical_entity.find(reference.choices[1].entity_id))
 local function compare(expected)
  local observed=snapshot(entity);local units={};local ids={}
  for _,id in ipairs(reference.unit_scope)do ids[id]=true end
  for _,row in ipairs(observed.units)do if ids[row.id]then units[#units+1]=row end end
  observed.units=units
  local squads={};ids={}
  for _,id in ipairs(reference.squad_scope)do ids[id]=true end
  for _,row in ipairs(observed.squads)do if ids[row.id]then squads[#squads+1]=row end end
  observed.squads=squads
  assert(json.encode(observed)==json.encode(expected),'Typed NEW office effects differ')
  assert(not info.open and df.global.pause_state and df.global.world.frame_counter==0)
 end
 compare(reference.before)
 for _,step in ipairs{'1','2','3','applied'}do
  local name='new-offices-'..step;local deadline=dfhack.getTickCount()+15000
  while true do
   local marker=io.open(out..'/'..name);if marker then marker:close();break end
   assert(dfhack.getTickCount()<deadline,'NEW office client timeout: '..name);script.sleep(1,'frames')
  end
  compare(step=='applied' and reference.applied or reference.before)
  f=assert(io.open(out..'/ack-'..name,'w'));f:write('ok');f:close()
 end
 f=assert(io.open(out..'/nobles-new-offices-wire.json','w'));f:write(json.encode({status='passed',native_effects_match=true,staged_without_effects=true}));f:close();return
end
gui.simulateInput(view,'D_NOBLES');settle()
local menu=info.administrators;local entity=df.historical_entity.find(df.global.plotinfo.group_id)
assert(entity)
local result={before=snapshot(entity),choices={},drafts={}}
local used={}
for _,kind in ipairs{'messenger','messenger','militia captain'}do
 local target,index
 for i,row in ipairs(menu.noblelist)do
  if row.ep.name[0]==kind and not row.epp and not row.un then target=row;index=i;break end
 end
 assert(target and index<16,'Expected visible NEW '..kind)
 local identity={entity_id=target.enid,position_id=target.ep.id,assignment_id=-1,expected_unit_id=-1}
 click(232,178+index*36);assert(menu.choosing_candidate,'NEW control did not open picker')
 local chosen,selected
 for i,row in ipairs(menu.candidate)do
  if row.un and not used[row.un.id] and ((kind=='messenger' and row.un.military.squad_position~=0) or (kind~='messenger' and row.un.military.squad_position==0))then chosen=i;selected=row.un;break end
 end
 assert(chosen,'Missing candidate for '..kind)
 while chosen-menu.scroll_position_candidate>=16 do
  local prior=menu.scroll_position_candidate
  g.precise_mouse_x=300;g.precise_mouse_y=300;g.mouse_x=37;g.mouse_y=25
  gui.simulateInput(view,'STANDARDSCROLL_DOWN');settle()
  assert(menu.scroll_position_candidate>prior,'Candidate scrolling stalled')
 end
 identity.unit_id=selected.id;identity.kind=kind;identity.prior_squad=selected.military.squad_id;identity.prior_squad_position=selected.military.squad_position
 used[selected.id]=true;result.choices[#result.choices+1]=identity
 click(200,142+(chosen-menu.scroll_position_candidate)*36)
 assert(not menu.choosing_candidate and info.open)
 assert(json.encode(snapshot(entity))==json.encode(result.before),'NEW selection committed effects early')
 local rows={}
 for i,row in ipairs(menu.noblelist)do rows[#rows+1]={entity_id=row.enid,position_id=row.ep.id,assignment_id=row.epp and row.epp.id or -1,unit_id=row.un and row.un.id or -1,histfig_id=menu.spec_hfid[i]}end
 result.drafts[#result.drafts+1]=rows
end
gui.simulateInput(view,'LEAVESCREEN');settle();assert(not info.open)
result.applied=snapshot(entity)
assert(#result.applied.assignments==#result.before.assignments+3,'NEW assignment allocation differs')
assert(result.applied.next_assignment==result.before.next_assignment+3,'NEW assignment counter differs')
assert(df.global.pause_state and df.global.world.frame_counter==0)
result.status='passed';result.closed=true
local f=assert(io.open(out..'/nobles-new-offices-native.json','w'));f:write(json.encode(result));f:close()
