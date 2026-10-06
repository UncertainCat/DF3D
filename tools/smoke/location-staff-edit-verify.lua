-- Protected clone readback only; never a runtime source of native UI state.
local out,index=...
local json=require('json')
local function read(path)local f=assert(io.open(path));local s=f:read('*a');f:close();return json.decode(s)end
local function write(path,v)local f=assert(io.open(path,'w'));f:write(json.encode(v));f:close()end
local request=index=='cleanup' and {op='staff_edit_cleanup'} or read(out..'/request-'..index..'.json')
assert(df.global.pause_state and df.global.world.frame_counter==0,'paused clone required')
local site=assert(dfhack.world.getCurrentSite())
local result={status='passed'}
local function occupations(vector)
 local rows={}
 for _,v in ipairs(vector)do rows[#rows+1]={v.id,v.type,v.histfig_id,v.unit_id,v.location_id,v.site_id,v.group_id}end
 return rows
end
local function facts(unit)
 local hf=assert(df.historical_figure.find(unit.hist_figure_id))
 local labor={};for k,v in pairs(unit.status.labors)do if type(v)=='boolean' then labor[tostring(k)]=v end end
 return {unit=unit.id,profession=unit.profession,profession2=unit.profession2,hf_profession=hf.profession,
  profile_profession=hf.info and hf.info.skills and hf.info.skills.profession or -1,
  labors=labor,links=occupations(unit.occupations),all=occupations(df.global.world.occupations.all),
  next_id=df.global.occupation_next_id,events=#df.global.world.history.events}
end
local function restore_failure_control()
 local c=_G.df3d_staff_edit_failure
 if not c then return end
 assert(df.global.occupation_next_id==2147483647,'unexpected allocation during exhaustion control')
 c.location.occupations:resize(0)
 for _,v in ipairs(c.local_rows)do c.location.occupations:insert('#',v)end
 df.global.occupation_next_id=c.next_id
 _G.df3d_staff_edit_failure=nil
end
if request.op=='staff_edit_locations' then
 result.locations={}
 for _,location in ipairs(site.buildings)do
  local kind=df.abstract_building_type[location:getType()]
  if kind=='INN_TAVERN' or kind=='TEMPLE' or kind=='LIBRARY' or kind=='HOSPITAL' then
   result.locations[#result.locations+1]={site_id=site.id,id=location.id}
  end
 end
elseif request.op=='staff_edit_prepare' then
 local target=assert(df.occupation.find(request.occupation_id))
 assert(target.site_id==site.id and target.location_id==request.location_id and target.unit_id==-1 and target.histfig_id==-1)
 local chosen
 for _,id in ipairs(request.candidates)do local u=assert(df.unit.find(id));if #u.occupations==0 then chosen=u;break end end
 assert(chosen,'unassigned native control missing')
 _G.df3d_staff_edit_control={unit=chosen,target=target,before=facts(chosen)}
 result.unit_id=chosen.id;result.histfig_id=chosen.hist_figure_id
elseif request.op=='staff_edit_unchanged' then
 local c=assert(_G.df3d_staff_edit_control)
 assert(json.encode(facts(c.unit))==json.encode(c.before),'refused/replayed command changed native facts')
elseif request.op=='staff_edit_exhaustion' then
 local c=assert(_G.df3d_staff_edit_control);local target=c.target
 assert(target.unit_id==-1 and target.histfig_id==-1 and #c.unit.occupations==0)
 local place;for _,v in ipairs(site.buildings)do if v.id==target.location_id then place=v end end
 local failure={location=assert(place),local_rows={},next_id=df.global.occupation_next_id}
 for _,v in ipairs(place.occupations)do failure.local_rows[#failure.local_rows+1]=v end
 _G.df3d_staff_edit_failure=failure
 -- Leave the selected slot as the only empty one of this role. Other slots
 -- remain in the global registry and are restored by the protected teardown.
 for i=#place.occupations-1,0,-1 do
  local v=place.occupations[i]
  if v~=target and v.type==target.type and v.unit_id==-1 and v.histfig_id==-1 then place.occupations:erase(i)end
 end
 df.global.occupation_next_id=2147483647
 c.before=facts(c.unit)
 result.site_id=site.id;result.location_id=place.id;result.occupation_id=target.id;result.unit_id=c.unit.id
 write(out..'/staff-edit-exhaustion-before.json',c.before)
elseif request.op=='staff_edit_unknown_check' then
 local c=assert(_G.df3d_staff_edit_control);local failure=assert(_G.df3d_staff_edit_failure)
 assert(c.target.unit_id==c.unit.id and c.target.histfig_id==c.unit.hist_figure_id,'unknown must contain published holder effects')
 assert(#c.unit.occupations==1 and c.unit.occupations[0]==c.target,'unknown lost published unit link')
 for _,v in ipairs(failure.location.occupations)do
  assert(v.type~=c.target.type or v.unit_id~=-1 or v.histfig_id~=-1,'exhausted role unexpectedly refilled')
 end
 assert(df.global.occupation_next_id==2147483647 and #df.global.world.occupations.all==#c.before.all,'exhausted allocation changed registry')
 c.assigned=facts(c.unit);c.before=c.assigned
 write(out..'/staff-edit-exhaustion-unknown.json',c.before)
elseif request.op=='staff_edit_restore_exhaustion' or request.op=='staff_edit_cleanup' then
 restore_failure_control()
 local c=_G.df3d_staff_edit_control;if c then c.before=facts(c.unit)end
elseif request.op=='staff_edit_check' then
 local c=assert(_G.df3d_staff_edit_control);local u,t=c.unit,c.target
 local actual=facts(u)
 if request.assigned then
  assert(t.unit_id==u.id and t.histfig_id==u.hist_figure_id,'target holder differs')
  assert(#u.occupations==1 and u.occupations[0]==t,'unit assignment link differs')
  local place;for _,v in ipairs(site.buildings)do if v.id==t.location_id then place=v end end
  local empty=false;for _,v in ipairs(assert(place).occupations)do if v.type==t.type and v.unit_id==-1 and v.histfig_id==-1 then empty=true end end
  assert(empty,'native empty role refill missing')
  c.assigned=actual
 else
  assert(t.unit_id==-1 and t.histfig_id==-1 and #u.occupations==0,'removal left holder/link')
  assert(json.encode(actual.labors)==json.encode(assert(c.assigned).labors),'removal unexpectedly recomputed labors')
 end
 c.before=actual
 write(out..'/staff-edit-'..t.location_id..'-'..t.type..(request.assigned and '-assigned' or '-removed')..(request.evidence_suffix or '')..'.json',actual)
 result.unit_id=t.unit_id;result.histfig_id=t.histfig_id
else error('unexpected staff verifier operation')end
write(out..'/response-'..index..'.json',result)
print('SEMANTIC_PASS '..index..' '..request.op)
