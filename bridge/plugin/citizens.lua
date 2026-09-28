-- Fixed citizen/work-detail domain. Native labor recalculation is authoritative.
local U,J=dfhack.units,dfhack.job
local steps,budget,list_revision=0,0,0
local recalc={active=false,cursor=0,unit_id=nil,done=0,total=0,error=''}
local function spend() if steps>=budget then return false end;steps=steps+1;return true end
local function fnv_byte(h,b)return (h ~ b)*0x100000001b3 end
local function fnv_int(h,n)for _=1,8 do h=fnv_byte(h,n & 255);n=n >> 8 end;return h end
local function fnv_text(h,s)h=fnv_int(h,#s);for i=1,#s do h=fnv_byte(h,s:byte(i)) end;return h end
local function revision(h)h=h & 0x7FFFFFFFFFFFFFFF;return h==0 and 1 or h end
local function finish(out)
 out.steps=steps;out.active_kinds=recalc.active and 16 or 0
 out.recalc_done=math.min(recalc.done,recalc.total);out.recalc_total=recalc.total
 out.recalc_error=recalc.error;out.detail_list_revision=list_revision
 return out
end
local function fail(message)return finish{ok=false,message=message}end
local function utf(s)return dfhack.df2utf(s or '')end
local function details()return df.global.plotinfo.labor_info.work_details end
local function external()return df.global.game.external_flag.automatic_professions_disabled end
local function citizen(u)return u and U.isCitizen(u,true) and U.isActive(u) and not U.isDead(u)end
local function eligibility(u)
 if not citizen(u) then return false,'Not an active surviving citizen' end
 if not U.isAlive(u) then return false,'Citizen is outside the supported living labor-assignment scope' end
 if not U.isCitizen(u) then return false,'Citizen is not eligible for ordinary labor' end
 if not U.isAdult(u) then return false,'Labor assignment requires an adult citizen' end
 return true,''
end
local function caption(id)
 local attr=df.unit_labor.attrs[id]
 return attr and attr.caption and attr.caption~='' and attr.caption or nil
end
local function enabled_labors(u)
 local out={}
 for i=0,df.unit_labor._last_item do if u.status.labors[i] and caption(i) then out[#out+1]=i end end
 return out
end
local function labor_names(ids)
 local names={}
 for _,id in ipairs(ids) do names[#names+1]=caption(id) end
 return names
end
-- Membership is stored sorted by unit id. Collect only explicit assignments,
-- in native work-detail definition order; everybody mode is not an assignment.
local function assigned_details(u,inspect)
 local out={}
 for index,d in ipairs(details()) do
  local lo,hi=0,#d.assigned_units
  while lo<hi do local mid=math.floor((lo+hi)/2);if d.assigned_units[mid]<u.id then lo=mid+1 else hi=mid end end
  if lo<#d.assigned_units and d.assigned_units[lo]==u.id then
   out[#out+1]={index=index,icon=d.icon,name=inspect and utf(d.name) or ''}
  end
 end
 return out
end
local function overflow(row,field)
 row.row_error='Row exceeds '..field..' cap'
 for k,v in pairs(row) do
  if type(v)=='string' and k~='row_error' then row[k]=''
  elseif type(v)=='table' then row[k]={} end
 end
 return row
end
local function check_row(row)
 for _,k in ipairs{'name','profession','job','reason'} do
  if row[k] and #row[k]>512 then return overflow(row,k) end
 end
 if row.detail_skill_name and #row.detail_skill_name>128 then return overflow(row,'detail_skill_name') end
 for _,k in ipairs{'labor_names','assigned_details','roles'} do
  for _,v in ipairs(row[k] or {}) do
   local name=type(v)=='table' and v.name or v
   if #name>(k=='labor_names' and 128 or 512) then return overflow(row,k) end
  end
 end
 return row
end
local function citizen_info(u,inspect,selected)
 local allowed,reason=eligibility(u)
 local age=U.getAge(u)
 if age~=age or age<0 or age>1000000 then age=-1 else age=math.floor(age) end
 local x,y,z=U.getPosition(u)
 local p={x=x,y=y,z=z}
 local valid=p and dfhack.maps.isValidTilePos(p)
 if valid then local d=dfhack.maps.getTileFlags(p);valid=d and not d.hidden end
 local soul=u.status.current_soul
 local row={only_assigned_jobs=u.flags4.only_do_assigned_jobs,assigned_details=assigned_details(u,inspect),profession_color=U.getProfessionColor(u),profession_id=u.profession,job_type=u.job.current_job and u.job.current_job.job_type or -1,id=u.id,name=utf(U.getReadableName(u,true)),profession=utf(U.getProfessionName(u)),
  job=u.job.current_job and utf(J.getName(u.job.current_job)) or 'No current job',age=age,
  stress=soul and soul.personality.stress or 0,has_stress=soul~=nil,
  x=valid and p.x or 0,y=valid and p.y or 0,z=valid and p.z or 0,can_focus=not not valid,
  eligible=allowed,reason=reason,labors={},labor_names={},roles={},offices={}}
 row.detail_member=-1;row.detail_skill=-1;row.detail_skill_rating=-1;row.detail_skill_name=''
 if not spend() then return nil,'Native labor recalculation is unavailable' end
 local h=fnv_int(0xcbf29ce484222325,u.id)
 h=fnv_int(h,row.only_assigned_jobs and 1 or 0)
 for _,d in ipairs(row.assigned_details) do h=fnv_int(h,d.index) end
 row.revision=revision(h)
 local all=details();local d=selected and selected>=0 and selected<#all and all[selected] or nil
 if d then
  row.detail_member=0
  for _,v in ipairs(row.assigned_details) do if v.index==selected then row.detail_member=1 end end
  local best_rating=-1
  for _,skill in ipairs(soul and soul.skills or {}) do
   local attr=df.job_skill.attrs[skill.id]
   local display_rating=math.min(skill.rating,20)
   local rating=df.skill_rating.attrs[display_rating]
   if attr and attr.labor and attr.labor>=0 and attr.caption_noun and attr.caption_noun~='' and rating and rating.caption and rating.caption~=''
      and d.allowed_labors[attr.labor] and (skill.rating>best_rating or
      (skill.rating==best_rating and skill.id<row.detail_skill)) then
    row.detail_skill=skill.id;row.detail_skill_rating=display_rating;best_rating=skill.rating
    row.detail_skill_name=rating.caption..' '..attr.caption_noun
   end
  end
 end
 if inspect then
  row.labors=enabled_labors(u);row.labor_names=labor_names(row.labors)
  for _,n in ipairs(U.getNoblePositions(u) or {}) do
   if n.entity.id==df.global.plotinfo.group_id then
    if #row.roles>=32 then return overflow(row,'roles') end
    row.roles[#row.roles+1]={name=utf(n.position.name[0]),required_office=n.position.required_office}
   end
  end
  for _,b in ipairs(u.owned_buildings or {}) do
   if df.building_civzonest:is_instance(b) and b.type==df.civzone_type.Office then
    if #row.offices>=64 then return overflow(row,'offices') end
    row.offices[#row.offices+1]=b.id
   end
  end
 end
 return check_row(row)
end
-- Each header is one budgeted step; membership is read only for returned targets.
local function receipt()
 local all=details()
 if #all>128 then return nil,'Work-detail vector exceeds 128 entries' end
 local h=fnv_int(0xcbf29ce484222325,#all)
 for _,d in ipairs(all) do
  if not spend() then return nil,'Native labor recalculation is unavailable' end
  h=fnv_text(h,d.name);h=fnv_int(h,d.flags.whole);h=fnv_int(h,d.icon)
  for i=0,93 do h=fnv_byte(h,d.allowed_labors[i] and 1 or 0) end
  h=fnv_int(h,#d.assigned_units)
 end
 list_revision=revision(h);return list_revision
end
local function detail_info(index,rev)
 local all=details();local d=index>=0 and index<#all and all[index] or nil
 if not d then return nil end
 local h=0xcbf29ce484222325
 local count=#d.assigned_units
 -- Over-cap rows retain the header/count identity without scanning an unbounded vector.
 for first=0,math.min(count,1024)-1,64 do
  if not spend() then return nil,'Native labor recalculation is unavailable' end
  for i=first,math.min(first+63,count-1,1023) do h=fnv_int(h,d.assigned_units[i]) end
 end
 local editable=not external()
 local row={index=index,revision=revision(fnv_int(fnv_int(0xcbf29ce484222325,rev),h)),
  name=utf(d.name),icon=d.icon,mode=d.flags.mode,no_modify=d.flags.no_modify,
  cannot_be_everybody=d.flags.cannot_be_everybody,editable=editable,mode_editable=editable,
  reason=external() and 'An external labor controller owns assignments' or '',labors={},labor_names={},assigned_units={}}
 if count>1024 then return overflow(row,'assigned_units') end
 for i=0,93 do if d.allowed_labors[i] and caption(i) then row.labors[#row.labors+1]=i end end
 row.labor_names=labor_names(row.labors)
 local previous=-1
 for _,id in ipairs(d.assigned_units) do
  if id<=previous then return nil,'Native work-detail membership is not sorted and unique' end
  previous=id;row.assigned_units[#row.assigned_units+1]=id
 end
 return check_row(row)
end
-- Captured native defaults, keyed by icon. SIEGE_OPERATORS has no captured set.
local defaults={
 MINERS={'MINE'},WOODCUTTERS={'CUTWOOD'},HUNTERS={'HUNT'},PLANTERS={'PLANT'},
 FISHERMEN={'FISH'},PLANT_GATHERERS={'HERBALIST'},STONECUTTERS={'STONECUTTER'},ENGRAVERS={'ENGRAVER'},
 HAULERS={'HAUL_STONE','HAUL_WOOD','HAUL_BODY','HAUL_FOOD','HAUL_REFUSE','HAUL_ITEM','HAUL_FURNITURE','HAUL_ANIMALS','HANDLE_VEHICLES','HAUL_TRADE','HAUL_WATER'},
 ORDERLIES={'SUTURING','DRESSING_WOUNDS','FEED_WATER_CIVILIANS','RECOVER_WOUNDED'},
}
local function queue_recalc()
 recalc={active=true,cursor=0,unit_id=nil,done=0,total=#df.global.world.units.all,error=''}
end
local function advance(rollback)
 local all=df.global.world.units.all
 local lo,hi=0,#all
 while lo<hi do local mid=(lo+hi)//2;if all[mid].id<recalc.cursor then lo=mid+1 else hi=mid end end
 local called={}
 while recalc.active and steps<budget do
  if recalc.unit_id then
   local u=df.unit.find(recalc.unit_id);recalc.unit_id=nil
   if u and eligibility(u) then
    spend();called[#called+1]=u.id
    if not pcall(U.setAutomaticProfessions,u) then
     recalc.active=false
     if rollback then
      rollback();local restored=true
      for _,id in ipairs(called) do local v=df.unit.find(id);if v then spend();if not pcall(U.setAutomaticProfessions,v) then restored=false end end end
      return restored and 'Native recalculation failed; mode restored' or 'Native recalculation failed; mode restored but labor refresh failed'
     end
     recalc.error='Native recalculation failed; labors may be stale';return recalc.error
    end
   end
   recalc.done=math.min(recalc.done+1,recalc.total)
  elseif lo<#all then
   spend();local u=all[lo];lo=lo+1;recalc.cursor=u.id+1;recalc.unit_id=u.id
  else recalc.active=false;recalc.done=recalc.total end
 end
 if lo>=#all and not recalc.unit_id then recalc.active=false;recalc.done=recalc.total end
end
local function result()
 return {ok=true,message='Citizens inspected',citizens={},details={},selected_unit=-1,selected_detail=-1,
  next_cursor=0,external_controller=external(),detail='Roles and office ownership are read-only; appointments are not exposed.'}
end
local function inspect_detail(index,unit_id,rev)
 local row,e=detail_info(index,rev);if not row then return fail(e or 'Work detail no longer exists') end
 local out=result();out.details={row};out.selected_detail=index
 if unit_id and unit_id>=0 then
  local u=df.unit.find(unit_id)
  if citizen(u) then local row,e=citizen_info(u,true,index);if not row then return fail(e) end;out.citizens={row};out.selected_unit=unit_id end
 end
 return out
end
return function(request)
 steps=0;budget=request.step or request.step_budget or 2048
 if request.restart_recalc then queue_recalc() end
 if request.step then
  if (request.builder_kind or request.kind)==4 and budget>0 then advance() end
  return finish(result())
 end
 local p=request.citizen
 if not p then return fail('Citizen request required') end
 local action=request.action
 local rev,err=receipt();if not rev then return fail(err) end
 local out=result()
 if action==28 then
  out.selected_detail=p.detail_index or -1
  local all=df.global.world.units.all
  local lo,hi=0,#all
  while lo<hi do local mid=(lo+hi)//2;if all[mid].id<p.cursor then lo=mid+1 else hi=mid end end
  local i=lo
  while i<#all and i<lo+512 and budget-steps>=2 do
   spend();local u=all[i]
   if citizen(u) then
    local matches=string.find(string.lower(utf(U.getReadableName(u,true))..' '..utf(U.getProfessionName(u))..' #'..u.id),string.lower(p.query),1,true)
    if matches then out.citizens[#out.citizens+1]=citizen_info(u,false,p.detail_index) end
   end
   i=i+1;if #out.citizens>=32 then break end
  end
  if i<#all then out.next_cursor=all[i].id end
  return finish(out)
 elseif action==29 then
  local u=df.unit.find(p.unit_id);if not citizen(u) then return fail('Citizen no longer available') end
  local row,e=citizen_info(u,true);if not row then return fail(e) end;out.citizens={row};out.selected_unit=u.id;return finish(out)
 elseif action==30 then
  if p.cursor>0 and (p.expected_list_revision or 0)~=rev then return fail('List changed; refresh') end
  local all=details();local i=p.cursor
  while i<#all do
   if string.find(string.lower(utf(all[i].name)),string.lower(p.query),1,true) then
    local row,e=detail_info(i,rev);if not row then return fail(e) end
    out.details[#out.details+1]=row
   end
   i=i+1;if #out.details>=16 then break end
  end
  if i<#all then out.next_cursor=i end
  return finish(out)
 elseif action==31 then return finish(inspect_detail(p.detail_index,p.unit_id,rev)) end
 if action~=32 and action~=33 and (action<64 or action>67) then return fail('Unsupported citizen action') end
 -- Reserve both bounded target hashes, two row hashes and rollback calls before any write.
 if budget-steps<#details()+39 then return fail('Native labor recalculation is unavailable') end
 if action==67 then
  local u=df.unit.find(p.unit_id);local valid,reason=eligibility(u)
  if not valid then return fail(reason) end
  local row=citizen_info(u,true)
  if p.expected_revision~=row.revision then return fail('Citizen changed; inspect again') end
  if external() then return fail('An external labor controller owns assignments') end
  if not df.global.unitst_set_automatic_professions then return fail('Native labor recalculation is unavailable') end
  local old=u.flags4.only_do_assigned_jobs
  u.flags4.only_do_assigned_jobs=p.only_assigned==1
  spend()
  if not pcall(U.setAutomaticProfessions,u) then
   u.flags4.only_do_assigned_jobs=old;spend();pcall(U.setAutomaticProfessions,u)
   return fail('Native recalculation failed; labors may be stale')
  end
  out.citizens={citizen_info(u,true)};out.selected_unit=u.id
 elseif action==64 then
  if p.expected_revision~=rev then return fail('Work-detail contents changed; refresh before editing') end
  if external() then return fail('An external labor controller owns assignments') end
  if #details()>=128 then return fail('Work-detail vector exceeds 128 entries') end
  local count=0;for _,d in ipairs(details()) do if not d.flags.no_modify then count=count+1 end end
  local d=df.work_detail:new();d.name=dfhack.utf2df('Custom Detail '..count)
  d.icon=df.work_detail_icon_type.CUSTOM_1+(count%8);d.flags.mode=1
  for i=0,93 do d.allowed_labors[i]=false end
  details():insert('#',d)
  rev=receipt();out=inspect_detail(#details()-1,-1,rev)
 else
  local row,e=detail_info(p.detail_index,rev)
  if not row then return fail(e or 'Work detail no longer exists') end
  if p.expected_revision~=row.revision then return fail('Work-detail contents changed; refresh before editing') end
  if external() then return fail('An external labor controller owns assignments') end
  local d=details()[p.detail_index]
  local full=false;local rollback=nil
  if action==65 then
   if d.flags.no_modify then return fail('Use Reset to default for built-in work details') end
   if (request.retire_capacity or 0)==0 then return fail('Deleted-detail capacity reached; restart DF') end
  elseif action==66 and p.edit==1 then
   local name=dfhack.utf2df(p.name or '')
   if #name>40 then return fail('Work-detail names are limited to 40 characters') end
   d.name=name
  elseif action==66 then
   local chosen={}
   if p.edit==3 then
    if not d.flags.no_modify then return fail('Reset to default applies to built-in work details') end
    local set=defaults[df.work_detail_icon_type[d.icon]]
    if not set then return fail('No native default recorded for this work detail') end
    for _,name in ipairs(set) do chosen[df.unit_labor[name]]=true end
   else
    for _,id in ipairs(p.labors or {}) do
     if id==0 or id==10 or id==44 then return fail('Labor '..id..' is not in the native labor picker') end
     if not caption(id) then return fail('Labor '..id..' has no native caption') end
     chosen[id]=true
    end
   end
   if not df.global.unitst_set_automatic_professions then return fail('Native labor recalculation is unavailable') end
   for i=0,93 do
    if p.edit==3 or (i~=0 and i~=10 and i~=44 and caption(i)) then d.allowed_labors[i]=not not chosen[i] end
   end
   full=true
  end
  -- Keep the existing mutation preflight refusals for optional unit inspection.
  -- Read-only inspection still returns a bounded error row, and rename can repair a detail.
  if (action==32 or action==33) and p.unit_id and p.unit_id>=0 then
   local u=df.unit.find(p.unit_id)
   if citizen(u) then
    local c=citizen_info(u,true)
    if c.row_error=='Row exceeds roles cap' then return fail('Citizen has too many roles for this inspector') end
    if c.row_error=='Row exceeds offices cap' then return fail('Citizen office list exceeds 64 entries') end
   end
  end
  if action==32 and #d.assigned_units>1024 then return fail('Work detail exceeds 1024 assigned units') end
  if action==32 or action==33 or action==65 then
   if not df.global.unitst_set_automatic_professions then return fail('Native labor recalculation is unavailable') end
   if action==32 then
    local u=df.unit.find(p.unit_id);local valid,reason=eligibility(u)
    if not valid then return fail(reason) end
    local at=0;while at<#d.assigned_units and d.assigned_units[at]<u.id do at=at+1 end
    local present=at<#d.assigned_units and d.assigned_units[at]==u.id
    if present==(p.member==1) then return finish(inspect_detail(p.detail_index,p.unit_id,rev)) end
    if p.member==1 then
     if #d.assigned_units>=1024 then return fail('Work-detail membership is full') end
     d.assigned_units:insert(at,u.id)
    else d.assigned_units:erase(at) end
    spend()
    if not pcall(U.setAutomaticProfessions,u) then
     if present then d.assigned_units:insert(at,u.id) else d.assigned_units:erase(at) end
     spend();local restored=pcall(U.setAutomaticProfessions,u)
     return fail(restored and 'Native recalculation failed; membership restored' or 'Native recalculation failed; membership restored but labor refresh failed')
    end
   elseif action==33 then
    if not row.mode_editable then return fail('Native work-detail mode is protected') end
    if p.mode==1 and d.flags.cannot_be_everybody then return fail('This work detail cannot be assigned to everybody') end
    if d.flags.mode==p.mode then return finish(inspect_detail(p.detail_index,p.unit_id,rev)) end
    local old,old_revision=d.flags.mode,rev;rollback=function()d.flags.mode=old;list_revision=old_revision end
    d.flags.mode=p.mode;full=true
   else
    details():erase(p.detail_index);out.retired={d};full=true
   end
  end
  rev=receipt()
  if action~=65 then out=inspect_detail(p.detail_index,p.unit_id,rev) end
  if full then
   queue_recalc();local failure=advance(rollback)
   if failure and rollback then
    local rejected=fail(failure);rejected.retired=out.retired;return rejected
   end
  end
 end
 if not out.ok then return finish(out) end
 out.message='Native work-detail change applied';return finish(out)
end
