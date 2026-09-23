-- Fixed citizen/work-detail domain. Native labor recalculation is authoritative.
local U,J=dfhack.units,dfhack.job
local signature_cache,revision='',0
local function fail(message)return {ok=false,message=message}end
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
local function enabled_labors(u)
 local out={}
 for i=0,df.unit_labor._last_item do if u.status.labors[i] then out[#out+1]=i end end
 return out
end
local function labor_names(ids)
 local names={}
 for _,id in ipairs(ids) do names[#names+1]=tostring(df.unit_labor[id] or id):gsub('_',' '):lower() end
 return names
end
-- Membership is stored sorted by unit id. Collect only explicit assignments,
-- in native work-detail definition order; everybody mode is not an assignment.
local function assigned_details(u)
 local out={}
 for index,d in ipairs(details()) do
  local lo,hi=0,#d.assigned_units
  while lo<hi do local mid=math.floor((lo+hi)/2);if d.assigned_units[mid]<u.id then lo=mid+1 else hi=mid end end
  if lo<#d.assigned_units and d.assigned_units[lo]==u.id then
   out[#out+1]={index=index,icon=d.icon,name=utf(d.name)}
  end
 end
 return out
end
local function citizen_info(u,inspect)
 local allowed,reason=eligibility(u)
 local age=U.getAge(u)
 if age~=age or age<0 or age>1000000 then age=-1 else age=math.floor(age) end
 local x,y,z=U.getPosition(u)
 local p={x=x,y=y,z=z}
 local valid=p and dfhack.maps.isValidTilePos(p)
 if valid then local d=dfhack.maps.getTileFlags(p);valid=d and not d.hidden end
 local soul=u.status.current_soul
 local row={only_assigned_jobs=u.flags4.only_do_assigned_jobs,assigned_details=assigned_details(u),profession_color=U.getProfessionColor(u),profession_id=u.profession,job_type=u.job.current_job and u.job.current_job.job_type or -1,id=u.id,name=utf(U.getReadableName(u,true)),profession=utf(U.getProfessionName(u)),
  job=u.job.current_job and utf(J.getName(u.job.current_job)) or 'No current job',age=age,
  stress=soul and soul.personality.stress or 0,has_stress=soul~=nil,
  x=valid and p.x or 0,y=valid and p.y or 0,z=valid and p.z or 0,can_focus=not not valid,
  eligible=allowed,reason=reason,labors={},labor_names={},roles={},offices={}}
 if inspect then
  row.labors=enabled_labors(u);row.labor_names=labor_names(row.labors)
  for _,n in ipairs(U.getNoblePositions(u) or {}) do
   if n.entity.id==df.global.plotinfo.group_id then
    if #row.roles>=32 then return nil,'Citizen has too many roles for this inspector' end
    row.roles[#row.roles+1]={name=utf(n.position.name[0]),required_office=n.position.required_office}
   end
  end
  local zones=df.global.world.buildings.other.ACTIVITY_ZONE
  if #zones>4096 then return nil,'Office inspector exceeds 4096 zones' end
  for _,b in ipairs(zones) do
   if b.type==df.civzone_type.Office and b.assigned_unit_id==u.id then
    if #row.offices>=64 then return nil,'Citizen office list exceeds 64 entries' end
    row.offices[#row.offices+1]=b.id
   end
  end
 end
 return row
end
-- Full ordered contents guard index identities against removal/reordering and edits.
-- Only strings/counters are retained; no native pointer survives an update.
local function receipt()
 local all=details()
 if #all>128 then return nil,'Work-detail vector exceeds 128 entries' end
 local total=0
 local parts,signatures={},{}
 local function add(out,v)local s=tostring(v);out[#out+1]=#s..':'..s end
 add(parts,#all)
 for index,d in ipairs(all) do
  if #d.assigned_units>1024 then return nil,'Work detail exceeds 1024 assigned units' end
  total=total+#d.assigned_units
  if total>8192 then return nil,'Work-detail assignments exceed bounded inspector' end
  local row={};add(row,d.name);add(row,d.flags.whole);add(row,d.icon)
  for i=0,df.unit_labor._last_item do add(row,d.allowed_labors[i]) end
  add(row,#d.assigned_units)
  local previous=-1
  for _,id in ipairs(d.assigned_units) do
   if id<=previous then return nil,'Native work-detail membership is not sorted and unique' end
   previous=id;add(row,id)
  end
  local signature=table.concat(row)
  signatures[index]=signature;add(parts,signature)
 end
 local signature=table.concat(parts)
 if signature~=signature_cache then signature_cache=signature;revision=revision+1 end
 local duplicates={};local seen={}
 for i=0,#all-1 do local v=signatures[i];if seen[v]~=nil then duplicates[i]=true;duplicates[seen[v]]=true else seen[v]=i end end
 return revision,nil,duplicates,total
end
local function detail_info(index,rev,duplicates)
 local d=details()[index]
 if not d then return nil end
 local editable=not external() and not duplicates[index]
 local reason=external() and 'An external labor controller owns assignments' or
  (duplicates[index] and 'Identical work-detail definitions have ambiguous identity' or '')
 local row={index=index,revision=rev,name=utf(d.name),mode=d.flags.mode,no_modify=d.flags.no_modify,
  cannot_be_everybody=d.flags.cannot_be_everybody,editable=editable,mode_editable=editable,reason=reason,labors={},assigned_units={}}
 for i=0,df.unit_labor._last_item do if d.allowed_labors[i] then row.labors[#row.labors+1]=i end end
 row.labor_names=labor_names(row.labors)
 for _,id in ipairs(d.assigned_units) do row.assigned_units[#row.assigned_units+1]=id end
 return row
end
local function result()
 return {ok=true,message='Citizens inspected',citizens={},details={},selected_unit=-1,selected_detail=-1,
  next_cursor=0,external_controller=external(),detail='Existing work details only. Roles and office ownership are read-only; appointments are not exposed.'}
end
local function inspect_detail(index,unit_id)
 local rev,err,duplicates=receipt();if not rev then return fail(err) end
 local row=detail_info(index,rev,duplicates);if not row then return fail('Work detail no longer exists') end
 local out=result();out.details={row};out.selected_detail=index
 if unit_id and unit_id>=0 then
  local u=df.unit.find(unit_id)
  if citizen(u) then local c,e=citizen_info(u,true);if not c then return fail(e) end;out.citizens={c};out.selected_unit=unit_id end
 end
 return out
end
return function(request)
 local p=request.citizen
 if not p then return fail('Citizen request required') end
 if request.action==28 then
  if #details()>128 then return fail('Work-detail vector exceeds 128 entries') end
  local out=result();local all=df.global.world.units.all
  local lo,hi=0,#all
  while lo<hi do local mid=math.floor((lo+hi)/2);if all[mid].id<p.cursor then lo=mid+1 else hi=mid end end
  local i=lo
  while i<#all and i<lo+512 do
   local u=all[i]
   if citizen(u) then
    local row=citizen_info(u,false)
    if string.find(string.lower(row.name..' '..row.profession..' #'..row.id),string.lower(p.query),1,true) then out.citizens[#out.citizens+1]=row end
   end
   i=i+1;if #out.citizens>=32 then break end
  end
  if i<#all then out.next_cursor=all[i].id end
  return out
 elseif request.action==29 then
  local u=df.unit.find(p.unit_id);if not citizen(u) then return fail('Citizen no longer available') end
  local c,e=citizen_info(u,true);if not c then return fail(e) end
  local out=result();out.citizens={c};out.selected_unit=u.id;return out
 elseif request.action==30 then
  local rev,err,duplicates=receipt();if not rev then return fail(err) end
  local out=result();local all=details();local i=p.cursor
  while i<#all do
   local d=all[i]
   if string.find(string.lower(utf(d.name)),string.lower(p.query),1,true) then out.details[#out.details+1]=detail_info(i,rev,duplicates) end
   i=i+1;if #out.details>=16 then break end
  end
  if i<#all then out.next_cursor=i end
  return out
 elseif request.action==31 then return inspect_detail(p.detail_index,p.unit_id) end
 if request.action~=32 and request.action~=33 then return fail('Unsupported citizen action') end
 local rev,err,duplicates,total=receipt();if not rev then return fail(err) end
 if p.expected_revision~=rev then return fail('Work-detail contents changed; refresh before editing') end
 local row=detail_info(p.detail_index,rev,duplicates)
 if not row then return fail('Work detail no longer exists') end
 if not row.editable then return fail(row.reason) end
 local d=details()[p.detail_index]
 if not df.global.unitst_set_automatic_professions then return fail('Native labor recalculation is unavailable') end
 -- Validate all optional inspection limits before changing native state.
 local before=inspect_detail(p.detail_index,p.unit_id)
 if not before.ok then return before end
 if request.action==32 then
  local u=df.unit.find(p.unit_id);local valid,reason=eligibility(u)
  if not valid then return fail(reason) end
  local at=0
  while at<#d.assigned_units and d.assigned_units[at]<u.id do at=at+1 end
  local present=at<#d.assigned_units and d.assigned_units[at]==u.id
  if present==(p.member==1) then return inspect_detail(p.detail_index,u.id) end
  if p.member==1 then
   if total>=8192 then return fail('Work-detail assignments exceed bounded inspector') end
   if #d.assigned_units>=1024 then return fail('Work-detail membership is full') end
   d.assigned_units:insert(at,u.id)
  else d.assigned_units:erase(at) end
  local ok=pcall(U.setAutomaticProfessions,u)
  if not ok then
   if present then d.assigned_units:insert(at,u.id) else d.assigned_units:erase(at) end
   local restored=pcall(U.setAutomaticProfessions,u)
   return fail(restored and 'Native recalculation failed; membership restored' or 'Native recalculation failed; membership restored but labor refresh failed')
  end
 elseif request.action==33 then
  if not row.mode_editable then return fail('Native work-detail mode is protected') end
  if d.flags.mode==p.mode then return inspect_detail(p.detail_index,p.unit_id) end
  if p.mode==1 and d.flags.cannot_be_everybody then return fail('This work detail cannot be assigned to everybody') end
  if not df.global.pause_state then return fail('Pause before changing a work-detail mode') end
  local affected={};local all=df.global.world.units.active
  if #all>8192 then return fail('Active-unit roster exceeds bounded mode preflight') end
  for _,u in ipairs(all) do
   if eligibility(u) then affected[#affected+1]=u.id;if #affected>256 then return fail('Mode changes currently support at most 256 eligible living sane adults') end end
  end
  -- One bounded safe point: never expose half-recalculated membership across ticks.
  local old_mode=d.flags.mode
  d.flags.mode=p.mode
  local ok=pcall(function()for _,id in ipairs(affected) do U.setAutomaticProfessions(df.unit.find(id)) end end)
  if not ok then
   d.flags.mode=old_mode
   local restored=pcall(function()for _,id in ipairs(affected) do U.setAutomaticProfessions(df.unit.find(id)) end end)
   return fail(restored and 'Native recalculation failed; mode restored' or 'Native recalculation failed; mode restored but labor refresh failed')
  end
 end
 local out=inspect_detail(p.detail_index,p.unit_id);out.message='Native work-detail change applied';return out
end
