-- Fixed semantic production adapter. Native simulation owns input selection and work.
local B,J=dfhack.buildings,dfhack.job
local utils=require('utils')
local function fail(s) return {ok=false,message=s} end
local function utf(s) return dfhack.df2utf(s or '') end
local function kind(b)
 if df.building_workshopst:is_instance(b) then return df.workshop_type[b.type] end
 if df.building_furnacest:is_instance(b) then return df.furnace_type[b.type] end
 if df.building_farmplotst:is_instance(b) then return 'FarmPlot' end
end
local function visible(b)
 local d=dfhack.maps.getTileFlags{x=b.centerx,y=b.centery,z=b.z}
 return d and not d.hidden
end
local function info(b)
 return {id=b.id,name=utf(B.getName(b)),kind=kind(b),x=b.centerx,y=b.centery,z=b.z,
  build_stage=b:getBuildStage(),max_stage=b:getMaxBuildStage(),queue_size=#b.jobs}
end
local function requirements(job)
 local r={}
 for _,f in ipairs(job.job_items.elements) do
  local names={df.item_type[f.item_type] or 'Any item'}
  for _,flags in ipairs{f.flags1,f.flags2,f.flags3} do
   for name,value in pairs(flags) do if type(name)=='string' and value==true then names[#names+1]=name end end
  end
  if f.mat_type>=0 then local m=dfhack.matinfo.decode(f.mat_type,f.mat_index);if m then names[#names+1]=utf(m:toString()) end end
  if f.reaction_class~='' then names[#names+1]=f.reaction_class end
  if f.has_material_reaction_product~='' then names[#names+1]=f.has_material_reaction_product end
  if f.reaction_id>=0 and f.reagent_index>=0 then
   local react=df.reaction.find(f.reaction_id)
   if react and react.reagents[f.reagent_index] then names={utf(utils.call_with_string(react.reagents[f.reagent_index],'getDescription',f.reaction_id))} end
  end
  r[#r+1]={description=table.concat(names,', '),quantity=f.quantity,item_type=f.item_type}
 end
 return r
end
local function delete_template(j)
 for _,f in ipairs(j.job_items.elements) do f:delete() end
 j.job_items.elements:resize(0);j:delete()
end
local function template_job(recipe,b,native_requirements)
 local j=df.job:new()
 j.item_type=-1;j.item_subtype=-1;j.mat_type=-1;j.mat_index=-1
 local ok,err=pcall(function()
  if recipe.reaction then
   local r=recipe.reaction
   j.job_type=df.job_type.CustomReaction;j.reaction_name=r.code
  else
   j:assign(recipe.fields)
  end
  native_requirements(j,b.id)
  if #j.job_items.elements>16 then error('Recipe exceeds 16 input requirements') end
 end)
 if not ok then delete_template(j);return nil,tostring(err) end
 return j
end
local function recipes(b,native_requirements,native_caption,native_reactions,native_less,native_templates,native_categories,category,native_forge)
 local out,keys={},{}
 local k=kind(b)
 local forge=k=='MetalsmithsForge' or k=='MagmaForge'
 local ordinary=k=='Carpenters' or k=='Kitchen' or k=='WoodFurnace' or k=='Farmers' or k=='Millstone' or k=='Tanners' or k=='Leatherworks'
 local supported=forge or ordinary or k=='Still'
 if category~='' and not supported then return nil,'Unsupported workshop category' end
 if supported then
  out.category=category;out.categories={}
  if not forge or category=='' or category:sub(1,9)=='reaction:' then out.categories=native_categories(b.id,category) end
  out.editable_templates=native_templates(b.id)
  for i=2,#out.categories do
   local row=out.categories[i];local at=i
   while at>1 and native_less(row.caption,out.categories[at-1].caption)do out.categories[at]=out.categories[at-1];at=at-1 end
   out.categories[at]=row
  end
 end
 local reaction_page=not forge or category=='' or category:sub(1,9)=='reaction:'
 if forge and (category=='' or not reaction_page) then
  local group,material=-1,nil
  if category~='' then
   local a,c=category:match('^forge:(%d+):(%d+)$')
   if not a then a=category:match('^forge:(%d+)$')end
   if not a then return nil,'Invalid forge category' end
   group=tonumber(a);material=c and tonumber(c)or nil
   if tostring(group)~=a or (c and tostring(material)~=c) or group<0 or group>6 or (material and material>2147483647) or (group==6 and material)then return nil,'Invalid forge category' end
   out.parent=material and ('forge:'..group)or ''
  end
  local page=native_forge(b.id,group,material)
  local categories=page.categories or {}
  for _,row in ipairs(out.categories)do categories[#categories+1]=row end
  out.categories=categories
  for _,fields in ipairs(page.templates or {})do
   local key='forge-task:'..fields.job_type..':'..fields.item_subtype..':'..fields.mat_type..':'..fields.mat_index
   out[#out+1]={key=key,fields=fields,available=true,objection=''}
  end
 end
 -- Native owned templates supply the audited builtin branches. The order
 -- classifier alone is not sufficient evidence for additional families.
 if category=='' and ordinary then
  for _,fields in ipairs(out.editable_templates) do
   if fields.job_type~=df.job_type.CustomReaction then
   local key='builtin:'..fields.job_type..':'..(fields.mat_type or -1)
   if (fields.item_subtype or -1)>=0 then key=key..':subtype:'..fields.item_subtype end
   out[#out+1]={key=key,fields=fields,available=true,objection=''}
   end
  end
 end
 -- Root reaction choices and current objections come from the native reader.
 if k=='Still' and category=='' then
  -- Native8cb3c9..8cb3e9: root category adds ExtractFromPlants directly.
  -- Constructor8b169e leaves show_help_instead false; no inventory veto is
  -- applied to this builtin. Native input generation still owns its filters.
  out[#out+1]={key='builtin:'..df.job_type.ExtractFromPlants..':-1',fields={job_type=df.job_type.ExtractFromPlants},available=true,objection=''}
 end
 if supported and reaction_page then
  for _,row in ipairs(native_reactions(b.id,category)) do
   local r=df.global.world.raws.reactions.reactions[row.raw_index]
   if not r or r.code~=row.code then return nil,'Native reaction identity changed' end
   out[#out+1]={key='reaction:'..r.code,reaction=r,available=row.available,objection=utf(row.objection)}
  end
 end
 for _,r in ipairs(out) do
  if keys[r.key] then return nil,'Ambiguous native recipe identity' end
  keys[r.key]=true
  local j,err=template_job(r,b,native_requirements)
  if not j then return nil,'Unsupported native recipe: '..err end
  local good,description,caption=pcall(function()return requirements(j),native_caption(j)end)
  delete_template(j)
  if not good then return nil,'Native input description failed: '..tostring(description) end
  r.requirements=description;r.native_caption=caption;r.name=utf(caption)
 end
 -- Match native insertion order for equal captions instead of Lua's unstable
 -- table.sort. Compare DF-encoded captions before presentation UTF-8 conversion.
 for i=2,#out do
  local row=out[i];local at=i
  while at>1 and native_less(row.native_caption,out[at-1].native_caption) do out[at]=out[at-1];at=at-1 end
  out[at]=row
 end
 if #out>128 then return nil,'Recipe catalog exceeds bounded 128 entries' end
 return out
end
local function editable(j,rs)
 if j.flags.special or j.flags.by_manager then return false end
 for _,fields in ipairs(rs.editable_templates or {})do
  if fields.job_type==df.job_type.CustomReaction then
   if j.job_type==fields.job_type and j.reaction_name==fields.reaction_name then return true end
  elseif j.job_type==fields.job_type and j.item_subtype==(fields.item_subtype or -1) and
   ((fields.mat_type or -1)==-1 or j.mat_type==fields.mat_type)then return true end
 end
 for _,r in ipairs(rs) do
  if r.reaction then
   if j.job_type==df.job_type.CustomReaction and j.reaction_name==r.reaction.code then return true end
  elseif j.job_type==r.fields.job_type and j.item_subtype==(r.fields.item_subtype or -1) and
   ((r.fields.mat_type or -1)==-1 or j.mat_type==r.fields.mat_type) then return true end
 end
 return false
end
local season_names={'SPRING','SUMMER','AUTUMN','WINTER'}
local seed_scan={seq=-1,cursor=0,counts={}}
local function farm_state(b,result)
 local des=dfhack.maps.getTileFlags{x=b.centerx,y=b.centery,z=b.z}
 local biome
 if des.subterranean then biome='SUBTERRANEAN_WATER'
 else local region=dfhack.maps.getTileBiomeRgn{x=b.centerx,y=b.centery,z=b.z};biome=df.biome_type[dfhack.maps.getBiomeType(region)] end
 -- Existing plots must have one consistent growing environment in this slice.
 if b.x1 and b.x2 then
  if b.x2-b.x1>=31 or b.y2-b.y1>=31 then return false,'Farm exceeds supported 31 by 31 inspector' end
  for y=b.y1,b.y2 do for x=b.x1,b.x2 do
   local p={x=x,y=y,z=b.z};local d=dfhack.maps.getTileFlags(p)
   if not d or d.hidden or d.subterranean~=des.subterranean then return false,'Mixed or hidden farm environment is not supported' end
   if not d.subterranean then
    local region=dfhack.maps.getTileBiomeRgn(p)
    if df.biome_type[dfhack.maps.getBiomeType(region)]~=biome then return false,'Mixed-biome farm is not supported' end
   end
  end end
 end
 result.seasonal_crops={};for s=0,3 do result.seasonal_crops[#result.seasonal_crops+1]=b.plant_id[s] end
 result.current_season=df.global.cur_season
 result.crops={}
 -- Inventory counts are informational: crop legality does not require current seeds.
 local seeds=seed_scan.counts
 for id,p in ipairs(df.global.world.raws.plants.all) do
  if id<=32767 and p.flags.SEED and not p.flags.TREE and p.flags['BIOME_'..biome] then
   local mask=0
   for s=0,3 do
    local valid=p.flags[season_names[s+1]]
    local duration=p.growdur*10
    if duration<0 or duration>40320 then valid=false end
    -- Current-season selection accounts for the remaining growing window.
    local elapsed=(s==df.global.cur_season) and df.global.cur_season_tick or 0
    local nexts=s
    while valid and elapsed+duration>=10080 do
     duration=duration-10080;nexts=(nexts+1)%4
     valid=p.flags[season_names[nexts+1]]
    end
    if valid then mask=mask+2^s end
   end
   if mask>0 then result.crops[#result.crops+1]={id=id,name=utf(p.name),seasons=mask,seeds=seeds[id] or 0} end
  end
 end
 if #result.crops>256 then return false,'Farm crop catalog exceeds 256 entries' end
 result.detail='Seasonal crop selection; seed counts are informational. Fertilization and new farm placement are not yet exposed.'
 return true
end
local function inspect(b,rs,native_caption,native_active)
 local result={ok=true,message='Production inspected',buildings={info(b)},selected_building=b.id,
  recipes={},production_jobs={},crops={},seasonal_crops={},current_season=-1}
 if kind(b)=='FarmPlot' then local ok,err=farm_state(b,result);if not ok then return fail(err) end;return result end
 if rs.category~=nil then
  result.task_category=rs.category;result.task_categories={}
  result.task_parent=rs.parent
  for _,row in ipairs(rs.categories)do result.task_categories[#result.task_categories+1]={key=row.key,name=utf(row.caption)}end
 end
 for _,r in ipairs(rs) do
  local row={key=r.key,name=r.name,requirements=r.requirements}
  if r.available~=nil then row.availability={available=r.available,objection=r.objection} end
  result.recipes[#result.recipes+1]=row
 end
 if #b.jobs>64 then return fail('Workshop queue exceeds bounded inspector') end
 for _,j in ipairs(b.jobs) do
  local worker=J.getWorker(j)
  local status=j.flags.suspend and 'Suspended by native state' or (worker and 'Worker assigned' or 'Awaiting worker or inputs; native cause is not exposed')
  result.production_jobs[#result.production_jobs+1]={id=j.id,name=utf(native_caption(j)),job_type=j.job_type,
   active=native_active and (native_active(j) and 1 or 0) or nil,repeat_job=j.flags['repeat'],suspended=j.flags.suspend,priority=j.flags.do_now and 1 or 0,worker_id=worker and worker.id or -1,
   worker_name=worker and utf(dfhack.units.getReadableName(worker)) or '',completion_timer=j.completion_timer,
   attached_items=#j.items,editable=editable(j,rs),can_move_up=(editable(j,rs) and #result.production_jobs>0) and 1 or 0,status=status,requirements=requirements(j)}
 end
 result.detail=(#rs==0 and 'Recipe creation for this building family is not supported yet. ' or '')..'Native workers select and haul inputs; queueing does not guarantee materials or labor. Work orders are not yet exposed.'
 local profile=b:getWorkshopProfile()
 if profile and #profile.permitted_workers>0 then result.detail=result.detail..' Workshop restricts workers ('..#profile.permitted_workers..').' end
 return result
end
return function(request)
 local p=request.production
 if not p then return fail('Production request required') end
 -- Crop edits belong exclusively to the revision-checked native transaction.
 if request.action==19 then return fail('') end
 if request.action==15 then
  local result={ok=true,message='Production buildings',buildings={},next_cursor=0}
  local all=df.global.world.buildings.all
  local lo,hi=0,#all
  while lo<hi do local mid=math.floor((lo+hi)/2);if all[mid].id<p.cursor then lo=mid+1 else hi=mid end end
  local i=lo
  while i<#all and i<lo+512 do
   local b=all[i]
   if kind(b) and visible(b) and string.find(string.lower(utf(B.getName(b))..' '..kind(b)..' #'..b.id),string.lower(p.query),1,true) then
    result.buildings[#result.buildings+1]=info(b)
   end
   i=i+1
   if #result.buildings==64 then break end
  end
  if i<#all then result.next_cursor=all[i].id end
  return result
 end
 local b=df.building.find(p.building_id)
 if not b or not kind(b) or not visible(b) then return fail('Production building no longer available') end
 if kind(b)=='FarmPlot' then
  if seed_scan.seq~=request.seq then seed_scan={seq=request.seq,cursor=0,counts={}} end
  local all=df.global.world.items.other.SEEDS
  local finish=math.min(#all,seed_scan.cursor+512)
  for n=seed_scan.cursor,finish-1 do
   local i=all[n]
   if not (i.flags.forbid or i.flags.dump or i.flags.garbage_collect or i.flags.hostile or i.flags.on_fire or i.flags.rotten or i.flags.trader) then
    seed_scan.counts[i.mat_index]=(seed_scan.counts[i.mat_index] or 0)+i:getStackSize()
   end
  end
  seed_scan.cursor=finish
  if finish<#all then return {ok=true,pending=true,message='Counting available seeds'} end
 end
 local rs,err=recipes(b,request.workshop_requirements,request.workshop_caption,request.workshop_reactions,request.workshop_caption_less,request.workshop_task_templates,request.workshop_task_categories,p.task_category or '',request.workshop_forge_page);if not rs then return fail(err) end
 if request.action==16 then
  local result=inspect(b,rs,request.workshop_caption,request.workshop_job_active)
  if kind(b)~='FarmPlot' and p.query and p.query~='' then
   local query=dfhack.utf2df(p.query);local filtered={}
   for i,recipe in ipairs(rs) do
    if request.workshop_caption_matches(recipe.native_caption,query) then filtered[#filtered+1]=result.recipes[i] end
   end
   result.recipes=filtered
   if result.task_categories then
    local categories={}
    for i,row in ipairs(rs.categories)do if request.workshop_caption_matches(row.caption,query)then categories[#categories+1]=result.task_categories[i]end end
    result.task_categories=categories
   end
  end
  return result
 end
 if b:getBuildStage()~=b:getMaxBuildStage() then return fail('Building construction is unfinished') end
 local created=-1
 if request.action==17 then
  if kind(b)=='FarmPlot' then return fail('Select seasonal farm crops instead') end
  if #b.jobs>=10 then return fail('Native workshop queue is full (10 jobs)') end
  for _,j in ipairs(b.jobs) do if not editable(j,rs) then return fail('Building has a special or unsupported job; queue unchanged') end end
  local recipe
  for _,r in ipairs(rs) do if r.key==p.recipe then recipe=r end end
  if not recipe then return fail('Recipe is no longer available at this building') end
  if recipe.available==false then return fail(recipe.objection) end
  local job,error=template_job(recipe,b,request.workshop_requirements);if not job then return fail(error) end
  job.pos={x=b.centerx,y=b.centery,z=b.z}
  local ref=df.general_ref_building_holderst:new();ref.building_id=b.id
  job.general_refs:insert('#',ref)
  job.flags['repeat']=p.repeat_job==1
  b.jobs:insert('#',job)
  if not J.linkIntoWorld(job,true) then
   b.jobs:erase(#b.jobs-1);job.general_refs:resize(0);ref:delete();delete_template(job)
   return fail('Native job linking rejected')
  end
  J.checkBuildingsNow()
  created=job.id
 elseif request.action==18 then
  local job
  for _,candidate in ipairs(b.jobs) do if candidate.id==p.job_id then job=candidate;break end end
  if not job or J.getHolder(job)~=b or not editable(job,rs) then return fail('Job is not an editable production job in this building') end
  if p.expected_previous_job_id~=nil and p.expected_previous_job_id>=0 then
   if not request.workshop_move_up(b.id,job.id,p.expected_previous_job_id) then return fail('') end
  elseif p.priority~=nil and p.priority>=0 then
   if not request.workshop_priority(b.id,job.id,p.expected_priority==1,p.priority==1) then return fail('') end
  elseif p.cancel then
   if not J.removeJob(job) then return fail('Native job cancellation rejected') end
  else
   if p.repeat_job~=-1 then job.flags['repeat']=p.repeat_job==1 end
   if p.suspend~=-1 then
    job.flags.suspend=p.suspend==1
    if p.suspend==1 then J.removeWorker(job,0) end
   end
  end
 else return fail('Unsupported production action') end
 local result=inspect(b,rs,request.workshop_caption,request.workshop_job_active);result.created_job=created;result.message='Native production change applied';return result
end
