-- Native effect oracle in the protected, paused, unsaved clone only.
-- No runtime code may consume this menu storage.
local out,view=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local g=df.global.gps;local info=df.global.game.main_interface.info
local function settle()for _=1,3 do script.sleep(1,'frames')end;view:render(dfhack.getTickCount())end
local function click(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=y//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1;settle()
end
assert(df.global.pause_state and df.global.world.frame_counter==0 and not info.open)
local result={cases={}}
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
 result.cases[#result.cases+1]=case;write()
 click(200,142+chosen*36)
 assert(not menu.choosing_candidate and info.open,'Candidate did not return to overview')
 case.staged=state(entity,assignment,figures);case.staged_holder=menu.spec_hfid[index]
 write()
 assert(case.staged_holder==expected,'Native staged wrong holder')
 assert(json.encode(case.before)==json.encode(case.staged),'Candidate click committed simulation effects early')
 gui.simulateInput(view,'LEAVESCREEN');settle();assert(not info.open)
 case.applied=state(entity,assignment,figures);write()
 assert(assignment.histfig==expected and assignment.histfig2==(selected and expected or prior),'Native close did not apply appointment')
 assert(df.global.pause_state and df.global.world.frame_counter==0,'Appointment advanced simulation')
 case.passed=true;write()
end
result.closed=true;result.status='passed';write()
