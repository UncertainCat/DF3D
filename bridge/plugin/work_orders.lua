-- Fixed work-order domain. DF alone authorizes orders and schedules their jobs.
local U,J,B=dfhack.units,dfhack.job,dfhack.buildings
local W=require('dfhack.workshops')
local receipts={};local receipt_counter=0
local request_jobs
local request_order_indices
local list_scan
local function fail(message)return {ok=false,message=message}end
local function utf(s)return dfhack.df2utf(s or '')end
local function all()return df.global.world.manager_orders.all end
local function find(id)
 if not request_order_indices then
  request_order_indices={};for i,o in ipairs(all())do request_order_indices[o.id]=i end
  for cached in pairs(receipts)do if request_order_indices[cached]==nil then receipts[cached]=nil end end
 end
 local index=request_order_indices[id];return index~=nil and all()[index] or nil
end
local function visible(b)
 local d=dfhack.maps.getTileFlags{x=b.centerx,y=b.centery,z=b.z};return d and not d.hidden
end
local function family(b)
 if df.building_workshopst:is_instance(b)then return df.workshop_type[b.type]end
 if df.building_furnacest:is_instance(b)then return df.furnace_type[b.type]end
end
local function catalog()
 local result={}
 for _,group in ipairs{'Carpenters','Kitchen','WoodFurnace'}do
  local source=group=='WoodFurnace' and W.jobs_furnace[df.furnace_type.WoodFurnace] or W.jobs_workshop[df.workshop_type[group]]
  for _,entry in ipairs(source or {})do
   -- Explicit manager fields; never copy workshop job input filters/items.
   local f=entry.job_fields;local supported=true
   for key in pairs(f)do if key~='job_type' and key~='mat_type'then supported=false end end
   if supported then result[#result+1]={key=group..':'..f.job_type..':'..(f.mat_type or -1),name=utf(entry.name),family=group,
    job_type=f.job_type,mat_type=f.mat_type or -1,wood=group=='Carpenters'}end
  end
 end
 local entity=df.historical_entity.find(df.global.plotinfo.civ_id);local allowed={}
 if entity then for _,i in ipairs(entity.entity_raw.workshops.permitted_reaction_id)do allowed[i]=true end end
 for index,r in ipairs(df.global.world.raws.reactions.reactions)do
  if allowed[index] or (entity and r.source_enid==entity.id)then
   local matches=false
   for i,t in ipairs(r.building.type)do if t==df.building_type.Workshop and r.building.subtype[i]==df.workshop_type.Still and r.building.custom[i]==-1 then matches=true end end
   if matches and not r.flags.FUEL then result[#result+1]={key='reaction:'..r.code,name=utf(r.name),family='Still',job_type=df.job_type.CustomReaction,mat_type=-1,reaction=r.code}end
  end
 end
 table.sort(result,function(a,b)return a.key<b.key end)
 if #result>128 then return nil,'Work-order catalog exceeds 128 recipes'end
 return result
end
local function recipe_for(o,rs)
 for _,r in ipairs(rs)do if o.job_type==r.job_type and o.mat_type==r.mat_type and
   (o.reaction_name or '')==(r.reaction or '') and (not r.wood or o.material_category.wood)then return r end end
end
local function jobs(o)
 if not request_jobs then
  request_jobs={};local link=df.global.world.jobs.list.next
  while link do local j=link.item;if j and j.order_id>=0 then
   request_jobs[j.order_id]=request_jobs[j.order_id] or {};local ids=request_jobs[j.order_id];ids[#ids+1]=j.id
  end;link=link.next end
  for _,ids in pairs(request_jobs)do table.sort(ids)end
 end
 return request_jobs[o.id] or {}
end
local function simple(c)
 return c.item_type>=0 and c.item_subtype==-1 and c.mat_type==-1 and c.mat_index==-1 and
 c.flags1.whole==0 and c.flags2.whole==0 and c.flags3.whole==0 and c.flags4==0 and c.flags5==0 and
 c.reaction_class=='' and c.has_material_reaction_product=='' and #c.contains==0 and
 c.metal_ore==-1 and c.min_dimension==-1 and c.reaction_id==-1 and c.has_tool_use==-1 and c.dye_color==-1
end
-- Collision-free content receipt within an epoch. Retain strings and IDs only.
local function revision(o)
 local parts={}
 local function add(v)local s=tostring(v);parts[#parts+1]=#s..':'..s end
 for _,key in ipairs{'id','job_type','item_type','item_subtype','reaction_name','mat_type','mat_index','amount_left','amount_total','frequency','finished_year','finished_year_tick','workshop_id','max_workshops'}do add(o[key])end
 add(o.status.whole);add(o.material_category.whole);add(o.specflag.whole);add(o.specdata.hist_figure_id)
 for _,key in ipairs{'type','id','subid'}do add(o.art_spec[key])end
 add(#o.item_conditions)
 for _,c in ipairs(o.item_conditions)do
  for _,key in ipairs{'compare_type','compare_val','item_type','item_subtype','mat_type','mat_index','flags4','flags5','reaction_class','has_material_reaction_product','metal_ore','min_dimension','reaction_id','has_tool_use','dye_color'}do add(c[key])end
  add(c.flags1.whole);add(c.flags2.whole);add(c.flags3.whole)
  add(#c.contains);for _,v in ipairs(c.contains)do add(v)end
 end
 add(#o.order_conditions)
 for _,c in ipairs(o.order_conditions)do add(c.order_id);add(c.condition);add(c.flags.whole)end
 add(o.items~=nil)
 if o.items then
  add(#o.items.elements)
  for _,f in ipairs(o.items.elements)do
   for _,key in ipairs{'item_type','item_subtype','mat_type','mat_index','quantity','vector_id','flags4','flags5','metal_ore','reaction_class','has_material_reaction_product','min_dimension','reagent_index','reaction_id','has_tool_use','dye_color','job_details_mat_type','job_details_mat_index'}do add(f[key])end
   add(f.flags1.whole);add(f.flags2.whole);add(f.flags3.whole);add(f.job_details_flags.whole);add(f.job_details_item_flags2.whole)
   add(#f.contains);for _,v in ipairs(f.contains)do add(v)end
  end
 end
 local text=table.concat(parts);local old=receipts[o.id]
 if old and old.content==text then return old.revision end
 receipt_counter=receipt_counter+1;receipts[o.id]={content=text,revision=receipt_counter};return receipt_counter
end
local function inspect(o)
 if #o.item_conditions+#o.order_conditions>64 then return nil,'Order exceeds 64-condition inspector'end
 if o.items and #o.items.elements>64 then return nil,'Order exceeds 64-input inspector'end
 local generated=jobs(o);if #generated>1024 then return nil,'Order exceeds 1024-job inspector'end
 local conditions={}
 for i,c in ipairs(o.item_conditions)do
  local editable=simple(c) and c.compare_type>=0 and c.compare_type<=5
  conditions[#conditions+1]={kind=0,index=i,description=(df.item_type[c.item_type] or 'Any item')..' '..(df.logic_condition_type[c.compare_type] or '?')..' '..c.compare_val..(editable and '' or ' (custom filters preserved; read only)'),
   editable=editable,compare=c.compare_type,threshold=c.compare_val,item_type=c.item_type,target_order=-1,dependency=-1}
 end
 for i,c in ipairs(o.order_conditions)do
  conditions[#conditions+1]={kind=1,index=i,description='Order #'..c.order_id..' '..(df.workquota_order_condition_type[c.condition] or '?'),
   editable=c.condition>=0 and c.condition<=1,compare=-1,threshold=-1,item_type=-1,target_order=c.order_id,dependency=c.condition,satisfied=c.flags.satisfied}
 end
 local editable=#generated==0 and (o.amount_total==0 or o.amount_total==o.amount_left)
 local reason=#generated>0 and 'Finish outstanding jobs before editing' or (editable and 'Your manager approves new or changed orders' or 'This batch has started; settings are read only to preserve completed work')
 return {id=o.id,revision=revision(o),name=utf(J.getManagerOrderName(o)),total=o.amount_total,remaining=o.amount_left,
  frequency=o.frequency,validated=o.status.validated,active=o.status.active,finished_year=o.finished_year,finished_tick=o.finished_year_tick,
  workshop_id=o.workshop_id,max_workshops=o.max_workshops,generated_jobs=generated,conditions=conditions,editable=editable,reason=reason}
end
local function managers()
 local out={}
 local offices_by_unit={}
 for _,b in ipairs(df.global.world.buildings.other.ACTIVITY_ZONE)do if b.type==df.civzone_type.Office and b.assigned_unit_id>=0 then
  local ids=offices_by_unit[b.assigned_unit_id] or {};ids[#ids+1]=b.id;offices_by_unit[b.assigned_unit_id]=ids
 end end
 for _,u in ipairs(df.global.world.units.active)do if U.isCitizen(u) and U.isActive(u) and not U.isDead(u)then
  for _,n in ipairs(U.getNoblePositions(u) or {})do
   if n.entity.id==df.global.plotinfo.group_id and n.position.responsibilities[df.entity_position_responsibility.MANAGE_PRODUCTION]then
    local offices=offices_by_unit[u.id] or {}
    if #offices>64 or #out>=32 then return nil,'Manager role inspector exceeds bounds'end
    out[#out+1]={unit_id=u.id,name=utf(U.getReadableName(u)),position=utf(n.position.name[0]),offices=offices,job=u.job.current_job and utf(J.getName(u.job.current_job)) or 'No current job'}
    break
   end
  end
 end end
 return out
end
local function reply(o,message)
 local v,err=inspect(o);if not v then return fail(err)end
 return {ok=true,message=message or 'Observed native work order',orders={v}}
end
local function workshop_valid(id,r)
 if id==-1 then return true end
 local b=df.building.find(id)
 return b and visible(b) and b:getBuildStage()==b:getMaxBuildStage() and r and family(b)==r.family
end
local function cycles(from,to)
 local seen={};local stack={to};local count=0
 while #stack>0 do
  local id=table.remove(stack);if id==from then return true end
  if not seen[id]then
   seen[id]=true;count=count+1;if count>4096 then return true end
   local o=find(id);if o then for _,c in ipairs(o.order_conditions)do stack[#stack+1]=c.order_id end end
  end
 end
 return false
end
return function(r)
 request_jobs=nil
 request_order_indices=nil
 local a=r.work_order;if not a then return fail('Work order request missing')end
 -- DF can retain borrowed order/condition pointers. Until there is a verified
 -- engine retirement API, never free them from this independent client. This
 -- capability is unavailable regardless of native panel state.
 if r.action==24 or (r.action==25 and a.remove_condition)then
  return fail('Removal is unavailable until safe work-order retirement is supported')
 end
 if r.action==27 then
  local rs,err=catalog();if not rs then return fail(err)end
  local ms,why=managers();if not ms then return fail(why)end
  return {ok=true,message='Work orders require native manager authorization',recipes=rs,managers=ms,detail='Role and office presence are observations, not approval. DF authorizes orders and chooses workers/materials.'}
 end
 if r.action==20 or r.action==26 then
  if not list_scan or list_scan.seq~=r.seq then
   local ids={}
   if r.action==20 or a.candidate_kind==0 then for _,o in ipairs(all())do if o.id>=a.cursor then ids[#ids+1]=o.id end end
   elseif a.candidate_kind==1 then for _,b in ipairs(df.global.world.buildings.all)do if b.id>=a.cursor and family(b)then ids[#ids+1]=b.id end end
   else for i=math.max(0,a.cursor),df.item_type._last_item do ids[#ids+1]=i end end
   table.sort(ids);list_scan={seq=r.seq,ids=ids,index=1,matches={}}
  end
  local scan=list_scan;local limit=r.action==20 and 16 or 128
  local finish=math.min(#scan.ids,scan.index+511)
  for index=scan.index,finish do
   local id=scan.ids[index];local name
   if r.action==20 or a.candidate_kind==0 then local o=find(id);if o then name=utf(J.getManagerOrderName(o))end
   elseif a.candidate_kind==1 then local b=df.building.find(id);if b and visible(b) and b:getBuildStage()==b:getMaxBuildStage()then name=utf(B.getName(b))end
   else name=df.item_type[id]end
   scan.index=index+1
   if name and (name:lower():find(a.query:lower(),1,true) or tostring(id)==a.query)then
    scan.matches[#scan.matches+1]={id=id,name=name..' #'..id}
    if #scan.matches>limit then break end
   end
  end
  if scan.index<=#scan.ids and #scan.matches<=limit then return {ok=true,pending=true,message='Searching native identities'}end
  local rows,choices={},{};local cursor=0;local condition_count,job_count=0,0
  for _,v in ipairs(scan.matches)do
   if r.action==20 then
    local native=find(v.id);local o,err;if native then o,err=inspect(native)end
    if err then list_scan=nil;return fail(err)end
    if o then
     if #rows==limit or condition_count+#o.conditions>128 or job_count+#o.generated_jobs>2048 then cursor=v.id;break end
     rows[#rows+1]=o;condition_count=condition_count+#o.conditions;job_count=job_count+#o.generated_jobs
    end
   else
    if #choices==limit then cursor=v.id;break end
    choices[#choices+1]=v
   end
  end
  list_scan=nil
  return {ok=true,message='Observed work-order identities',orders=rows,choices=choices,next_cursor=cursor}
 end
 if r.action==22 then
  local rs,err=catalog();if not rs then return fail(err)end
  local recipe;for _,v in ipairs(rs)do if v.key==a.recipe then recipe=v end end
  if not recipe then return fail('Recipe changed or is unavailable')end
  if not workshop_valid(a.workshop_id==-2 and -1 or a.workshop_id,recipe)then return fail('Selected workshop cannot service this recipe')end
  local o=df.manager_order:new()
  o:assign{job_type=recipe.job_type,item_type=-1,item_subtype=-1,mat_type=recipe.mat_type,mat_index=-1,
   reaction_name=recipe.reaction or '',frequency=a.frequency<0 and df.workquota_frequency_type.OneTime or a.frequency,
   amount_left=a.remaining,amount_total=a.remaining,workshop_id=a.workshop_id==-2 and -1 or a.workshop_id,
   max_workshops=a.max_workshops<0 and 0 or a.max_workshops}
  if recipe.wood then o.material_category.wood=true end
  o.status.validated=false;o.status.active=false
  o.id=df.global.world.manager_orders.manager_order_next_id
  df.global.world.manager_orders.manager_order_next_id=o.id+1
  all():insert('#',o)
  return reply(o,'Queued unvalidated work order; DF owns authorization')
 end
 local o=find(a.id);if not o then return fail('Work order no longer exists')end
 if r.action==21 then return reply(o)end
 local observed,err=inspect(o);if not observed then return fail(err)end
 if a.expected_revision~=observed.revision then return fail('Work order changed; inspect again before editing')end
 if (r.action==23 or r.action==25) and not observed.editable then return fail(observed.reason)end
 if r.action==23 then
  if a.remaining<0 and a.frequency<0 and a.workshop_id==-2 and a.max_workshops<0 then return reply(o,'No work-order fields changed')end
  local total=o.amount_total
  if a.remaining>=0 then
   if #observed.generated_jobs>0 then return fail('Finish generated jobs before changing remaining work')end
   if (a.remaining==0 or o.amount_total==0) and o.amount_total~=o.amount_left then return fail('Cannot change finite/indefinite mode after work completed')end
   total=a.remaining==0 and 0 or o.amount_total-o.amount_left+a.remaining
   if total>32767 then return fail('Total quantity would overflow native int16')end
  end
  if a.workshop_id~=-2 then local rs,why=catalog();if not rs then return fail(why)end;if not workshop_valid(a.workshop_id,recipe_for(o,rs))then return fail('Workshop restriction unsupported for this order')end end
  if a.remaining>=0 then o.amount_total=total;o.amount_left=a.remaining end
  if a.frequency>=0 then o.frequency=a.frequency end
  if a.workshop_id~=-2 then o.workshop_id=a.workshop_id end
  if a.max_workshops>=0 then o.max_workshops=a.max_workshops end
 elseif r.action==25 then
  local conditions=a.condition_kind==0 and o.item_conditions or o.order_conditions
  local existing=a.condition_index>=0 and conditions[a.condition_index] or nil
  if a.condition_index>=0 and not existing then return fail('Condition identity changed')end
  if existing and ((a.condition_kind==0 and not simple(existing)) or (a.condition_kind==1 and (existing.condition<0 or existing.condition>1)))then return fail('Unsupported custom condition is read only')end
  do
   if not existing and #o.item_conditions+#o.order_conditions>=64 then return fail('Condition limit reached')end
   if a.condition_kind==0 then
    if a.item_type<0 or a.item_type>df.item_type._last_item then return fail('Unknown native item type')end
    if existing and not simple(existing)then return fail('Custom condition filters are read only and remain unchanged')end
    local c=existing or df.manager_order_condition_item:new()
    if not existing then
     c:assign{item_subtype=-1,mat_type=-1,mat_index=-1,metal_ore=-1,min_dimension=-1,reaction_id=-1,has_tool_use=-1,dye_color=-1}
    end
    c.item_type=a.item_type;c.compare_type=a.compare;c.compare_val=a.threshold
    if not existing then conditions:insert('#',c)end
   else
    if not find(a.target_order) or cycles(o.id,a.target_order)then return fail('Dependency target missing or would form a cycle')end
    for i,c in ipairs(conditions)do if i~=a.condition_index and c.order_id==a.target_order then return fail('Duplicate order dependency')end end
    local c=existing or df.manager_order_condition_order:new();c.order_id=a.target_order;c.condition=a.dependency;c.flags.satisfied=false
    if not existing then conditions:insert('#',c)end
   end
  end
 else return fail('Unsupported work-order action')end
 -- Preserve outstanding jobs/counters/filters; only DF may reauthorize edited intent.
 o.status.validated=false;o.status.active=false
 return reply(o,'Order changed; awaiting native reevaluation and authorization')
end
