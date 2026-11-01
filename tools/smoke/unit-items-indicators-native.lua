-- Controlled indicator inputs in an owned paused clone, restored before return.
-- This observes native rendering; it is not a product classification algorithm.
local unit,pointer,capture=...
local script=require('gui.script')
local item=assert(unit.inventory[0].item)
local equipment=df.global.plotinfo.equipment
local assigned=equipment.items_assigned[item:getType()]
local work=equipment.work_weapons
local function copy(vector)local values={};for _,v in ipairs(vector)do values[#values+1]=v end;return values end
local old_assigned,old_work,old_refs=copy(assigned),copy(work),copy(item.general_refs)
local flags=item.flags.whole
local frame=df.global.world.frame_counter
local figure=assert(df.historical_figure.find(unit.hist_figure_id))
local entity,assignment
for _,link in ipairs(figure.entity_links)do
 if link:getType()==df.histfig_entity_link_type.POSITION then
  local candidate=df.historical_entity.find(link.entity_id)
  if candidate then for _,position in ipairs(candidate.positions.assignments)do
   if position.id==link.assignment_id then entity=candidate;assignment=position;break end
  end end
 end
 if entity then break end
end
assert(entity and assignment,'Symbol indicator fixture requires an existing position')
local artifact=assert(df.global.world.artifacts.all[0],'Symbol fixture requires an artifact')
local old_claims=copy(entity.artifact_claims)
local artifact_ref=df.general_ref_is_artifactst:new();artifact_ref.artifact_id=artifact.id
local claim=df.artifact_claim:new();claim.artifact_id=artifact.id;claim.claim_type=0
claim.symbol_claim_id=assignment.id;claim.renounce_event=-1
local function replace(vector,values)vector:resize(0);for _,v in ipairs(values)do vector:insert('#',v)end end
local function restore()
 replace(assigned,old_assigned);replace(work,old_work);replace(item.general_refs,old_refs);item.flags.whole=flags
 replace(entity.artifact_claims,old_claims)
end
local function membership(vector,present)
 local values={};for _,id in ipairs(vector)do if id~=item.id then values[#values+1]=id end end
 if present then values[#values+1]=item.id end
 table.sort(values);replace(vector,values)
end
local cases={}
local ok,err=xpcall(function()
 for _,case in ipairs{
  {'clothing',false,false,true,false,294},
  {'squad',true,false,true,false,291},
  {'squad-before-work',true,true,true,false,291},
  {'work-before-clothing',false,true,true,false,292},
  {'unassigned',false,false,false,false,-1},
  {'artifact-work-without-claim',false,true,true,true,-1},
  {'artifact-position-symbol',false,true,true,true,293,true},
  {'squad-before-symbol',true,true,true,true,291,true},
  {'renounced-symbol',false,true,true,true,-1,true,true},
 }do
  restore();membership(assigned,case[2]);membership(work,case[3]);item.flags.artifact=case[5]
  if case[7]then
   item.general_refs:insert('#',artifact_ref)
   claim.renounce_event=case[8]and 1 or -1
   -- Isolate this existing entity's claims to the controlled symbol input.
   replace(entity.artifact_claims,{claim})
  end
  if not case[4]then
   for i=#item.general_refs-1,0,-1 do
    if item.general_refs[i]:getType()==df.general_ref_type.UNIT_ITEMOWNER then item.general_refs:erase(i)end
   end
  end
  pointer(400,400)
  local until_hover=dfhack.getTickCount()+650
  while dfhack.getTickCount()<until_hover do pointer(836,226);script.sleep(1,'frames')end
  pointer(836,226)
  local main=df.global.game.main_interface
  assert(main.current_hover==case[6],case[1]..' indicator hover differs: '..main.current_hover)
  local row={name=case[1],hover=main.current_hover,lines={}}
  if case[6]>=0 then
   assert(main.hover_instructions_on,'Indicator help did not activate')
   local g=df.global.gps
   for y=0,17 do
    local text={}
    for x=g.dimx-24,g.dimx-1 do local pen=dfhack.screen.readTile(x,y);text[#text+1]=pen.ch>=32 and string.char(pen.ch%256) or ' 'end
    row.lines[#row.lines+1]=dfhack.df2utf(table.concat(text)):gsub('%s+$','')
   end
   while #row.lines>0 and row.lines[#row.lines]==''do table.remove(row.lines)end
  end
  capture('unit-items-indicator-'..case[1])
  assert(df.global.pause_state and df.global.world.frame_counter==frame,'Indicator probe advanced simulation')
  cases[#cases+1]=row
 end
end,debug.traceback)
restore();pointer(400,400)
df.delete(claim);df.delete(artifact_ref)
assert(ok,err)
return {cases=cases,restored=true,limitations='Synthetic membership/reference/claim cases; no equipment assignment or artifact claim gameplay action.'}
