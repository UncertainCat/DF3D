-- Native effect oracle in the protected, paused, unsaved clone only.
-- No runtime code may consume this menu storage.
local out,view,probe=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local g=df.global.gps;local info=df.global.game.main_interface.info
local function settle()for _=1,3 do script.sleep(1,'frames')end;view:render(dfhack.getTickCount())end
local function click(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=y//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1;settle()
end
assert(df.global.pause_state and df.global.world.frame_counter==0 and not info.open)
local semantic=os.getenv('DF3D_NOBLES_COMMIT')=='1'
local wire=os.getenv('DF3D_NOBLES_APPOINTMENT_WIRE')=='1'
local result={cases={},semantic_commit=semantic}
local reference
if semantic or wire then
 local path=debug.getinfo(1,'S').source:sub(2):gsub('tools/smoke/nobles%-appointment%-native%.lua$','fixtures/production/native_nobles.json')
 local f=assert(io.open(path));reference=json.decode(f:read('*a')).appointment_effect_reference.cases;f:close()
 assert(reference and #reference==3)
end
local function write()
 local f=assert(io.open(out..'/nobles-appointment-native.json','w'));f:write(json.encode(result));f:close()
end
local function state(entity,assignment,figures)
 local value={holder=assignment.histfig,holder2=assignment.histfig2,assignment=assignment.id,
  position=assignment.position_id,assignments=#entity.positions.assignments,
  next_assignment=entity.positions.next_assignment_id,events=#df.global.world.history.events,figures={}}
 for _,id in ipairs(figures)do
  local hf=assert(df.historical_figure.find(id));local row={id=id,links={}}
  for _,link in ipairs(hf.entity_links)do
   row.links[#row.links+1]={type=link:getType(),entity=link.entity_id,strength=link.link_strength,
    position=link:getPosition(),start_year=link:getPositionStartYear(),end_year=link:getPositionEndYear()}
  end
  local unit=df.unit.find(hf.unit_id)
  if unit then row.unit={id=unit.id,profession=unit.profession,profession2=unit.profession2,
   squad=unit.military.squad_id,position=unit.military.squad_position,
   job=unit.job.current_job and unit.job.current_job.id or -1}end
  value.figures[#value.figures+1]=row
 end
 return value
end
if wire then
 local f=assert(io.open(out..'/nobles-appointment-reference.json','w'));f:write(json.encode(reference));f:close()
 local function await_marker(name)
  local deadline=dfhack.getTickCount()+15000
  while true do
   local f=io.open(out..'/'..name);if f then f:close();return end
   assert(dfhack.getTickCount()<deadline,'Appointment client timeout: '..name);script.sleep(1,'frames')
  end
 end
 for _,oracle in ipairs(reference)do
  local entity=assert(df.historical_entity.find(oracle.entity_id));local assignment
  for _,row in ipairs(entity.positions.assignments)do if row.id==oracle.assignment_id then assignment=row;break end end
  assert(assignment)
  local figures={};for _,figure in ipairs(oracle.before.figures)do figures[#figures+1]=figure.id end
  assert(json.encode(state(entity,assignment,figures))==json.encode(oracle.before),'Typed appointment initial state differs')
  for _,step in ipairs{'staged','applied'}do
   local marker='appointment-'..oracle.operation..'-'..step
   await_marker(marker)
   local observed=state(entity,assignment,figures)
   assert(json.encode(observed)==json.encode(step=='staged' and oracle.before or oracle.applied),'Typed appointment effects differ: '..marker)
   assert(not info.open and df.global.pause_state and df.global.world.frame_counter==0,'Typed appointment changed native navigation or advanced simulation')
   local f=assert(io.open(out..'/ack-'..marker,'w'));f:write('ok');f:close()
  end
  result.cases[#result.cases+1]={operation=oracle.operation,selected_unit=oracle.selected_unit,native_effects_match=true,staged_without_effects=true}
 end
 result.typed_pointer=true;result.closed=true;result.status='passed';write();return
end
for _,operation in ipairs{'appoint','replace','vacate'}do
 gui.simulateInput(view,'D_NOBLES');settle()
 assert(info.open and info.current_mode==df.info_interface_mode_type.ADMINISTRATORS)
 local menu=info.administrators;local target,index
 for i,row in ipairs(menu.noblelist)do
  if row.ep.name[0]=='manager' then assert(not target);target=row;index=i end
 end
 assert(target and target.epp,'Expected existing manager office')
 assert((operation=='appoint')==(target.un==nil),'Unexpected manager occupancy')
 local entity=assert(df.historical_entity.find(target.enid));local assignment=target.epp
 local prior=assignment.histfig
 click(232,178+index*36);assert(menu.choosing_candidate)
 local chosen,selected
 for i,candidate in ipairs(menu.candidate)do
  if (operation=='vacate' and not candidate.un) or
     (operation~='vacate' and candidate.un and candidate.un.hist_figure_id~=prior and candidate.un.military.squad_position~=0)then
   chosen=i;selected=candidate.un;break
  end
 end
 assert(chosen and chosen<15,'Expected visible native candidate')
 local expected=selected and selected.hist_figure_id or -1
 local figures={};if prior>=0 then figures[#figures+1]=prior end;if selected then figures[#figures+1]=expected end
 local case={operation=operation,entity_id=entity.id,assignment_id=assignment.id,
  selected_unit=selected and selected.id or -1,selected_figure=expected,before=state(entity,assignment,figures)}
 local command={'nobles-draft-probe',tostring(entity.id),tostring(target.ep.id),tostring(assignment.id),tostring(target.un and target.un.id or -1),tostring(case.selected_unit)}
 local owned=probe(command)
 assert(json.encode(case.before)==json.encode(state(entity,assignment,figures)),'Owned draft changed simulation')
 result.cases[#result.cases+1]=case;write()
 if semantic then
  local oracle=reference[#result.cases]
  assert(oracle.operation==operation and oracle.selected_unit==case.selected_unit and
   json.encode(oracle.before)==json.encode(case.before),'Semantic scenario differs from native reference')
  gui.simulateInput(view,'LEAVESCREEN');settle();assert(not menu.choosing_candidate)
  gui.simulateInput(view,'LEAVESCREEN');settle();assert(not info.open)
  local size,address=df.sizeof(menu)
  local function menu_bytes()
   local bytes={};for offset=0,size-1 do bytes[#bytes+1]=string.char(df.reinterpret_cast('uint8_t',address+offset).value)end
   return table.concat(bytes)
  end
  local before=menu_bytes();command[1]='nobles-commit-probe'
  local output,rc=dfhack.run_command_silent('df3d',table.unpack(command))
  case.outcome=tonumber(output);case.applied=state(entity,assignment,figures);write()
  assert(rc==0 and case.outcome==2,'Semantic appointment did not apply: '..output)
  assert(before==menu_bytes(),'Semantic commit changed native menu')
  assert(json.encode(case.applied)==json.encode(oracle.applied),'Semantic appointment effects differ from native reference')
  local repeated,repeat_rc=dfhack.run_command_silent('df3d',table.unpack(command))
  assert(repeat_rc==0 and tonumber(repeated)==1,'Stale original holder was accepted twice')
  assert(json.encode(case.applied)==json.encode(state(entity,assignment,figures)),'Rejected stale choice changed effects')
  case.native_effects_match=true;case.menu_preserved=true;case.stale_rejected=true
 else
 click(200,142+chosen*36)
 assert(not menu.choosing_candidate and info.open,'Candidate did not return to overview')
 case.staged=state(entity,assignment,figures);case.staged_holder=menu.spec_hfid[index]
 local native={}
 for i,row in ipairs(menu.noblelist)do native[#native+1]={entity_id=row.enid,position_id=row.ep.id,
  assignment_id=row.epp and row.epp.id or -1,unit_id=row.un and row.un.id or -1,
  nemesis_id=row.nem and row.nem.id or -1,histfig_id=menu.spec_hfid[i]}end
 local warm=probe(command)
 assert(json.encode(owned)==json.encode(native) and json.encode(warm)==json.encode(native),'Owned draft differs from native staging')
 case.owned_draft={rows=owned,cold_warm_match=true,menu_rng_caches_preserved=true}
 write()
 assert(case.staged_holder==expected,'Native staged wrong holder')
 assert(json.encode(case.before)==json.encode(case.staged),'Candidate click committed simulation effects early')
 gui.simulateInput(view,'LEAVESCREEN');settle();assert(not info.open)
 case.applied=state(entity,assignment,figures);write()
 end
 assert(assignment.histfig==expected and assignment.histfig2==(selected and expected or prior),'Native close did not apply appointment')
 assert(df.global.pause_state and df.global.world.frame_counter==0,'Appointment advanced simulation')
 case.passed=true;write()
end
result.closed=true;result.status='passed';write()
