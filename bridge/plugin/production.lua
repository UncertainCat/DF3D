-- Fixed semantic production adapter. Native simulation owns input selection and work.
local B,J=dfhack.buildings,dfhack.job
local W=require('dfhack.workshops')
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
local function template_job(recipe)
 local j=df.job:new()
 j.item_type=-1;j.item_subtype=-1;j.mat_type=-1;j.mat_index=-1
 local ok,err=pcall(function()
  if recipe.reaction then
   local r=recipe.reaction
   j.job_type=df.job_type.CustomReaction;j.reaction_name=r.code
   for i,reagent in ipairs(r.reagents) do reagent:contribute_to_job_req(j.job_items,i,r.index) end
  else
   j:assign(recipe.fields)
   for _,input in ipairs(recipe.items) do
    local f=df.job_item:new();j.job_items.elements:insert('#',f)
    f:assign(input);f.flags2.allow_artifact=false
   end
  end
  if #j.job_items.elements>16 then error('Recipe exceeds 16 input requirements') end
 end)
 if not ok then delete_template(j);return nil,tostring(err) end
 return j
end
local function recipes(b)
 local out,keys={},{}
 local k=kind(b)
 -- Reuse pinned builtin templates only for validated initial families.
 if k=='Carpenters' or k=='Kitchen' or k=='WoodFurnace' then
  local source=(k=='WoodFurnace' and W.jobs_furnace or W.jobs_workshop)[b.type]
  for _,entry in ipairs(source or {}) do
   local inputs={}
   for _,item in ipairs(entry.items) do
    local f=utils.clone(W.input_filter_defaults,true)
    if source.defaults then utils.assign(f,source.defaults) end
    utils.assign(f,item);inputs[#inputs+1]=f
   end
   local fields=utils.clone(entry.job_fields,true)
   if k=='Carpenters' then fields.material_category={wood=true} end
   out[#out+1]={key='builtin:'..fields.job_type..':'..(fields.mat_type or -1),name=utf(entry.name),fields=fields,items=inputs}
  end
 end
 -- Reactions use native filters, including containers, and current civilization permissions.
 if k=='Still' then
  local entity=df.historical_entity.find(df.global.plotinfo.civ_id)
  local allowed={}
  if entity then for _,id in ipairs(entity.entity_raw.workshops.permitted_reaction_id) do allowed[id]=true end end
  for index,r in ipairs(df.global.world.raws.reactions.reactions) do
   if allowed[index] or (entity and r.source_enid==entity.id) then
    local matches=false
    for i,t in ipairs(r.building.type) do if t==b:getType() and r.building.subtype[i]==b:getSubtype() and (r.building.custom[i]==-1 or r.building.custom[i]==b:getCustomType()) then matches=true end end
    if matches and not r.flags.FUEL and #r.reagents<=16 then
     out[#out+1]={key='reaction:'..r.code,name=utf(r.name),reaction=r}
    end
   end
  end
 end
 for _,r in ipairs(out) do
  if keys[r.key] then return nil,'Ambiguous native recipe identity' end
  keys[r.key]=true
  local j,err=template_job(r)
  if not j then return nil,'Unsupported native recipe: '..err end
  local good,description=pcall(requirements,j)
  delete_template(j)
  if not good then return nil,'Native input description failed: '..tostring(description) end
  r.requirements=description
 end
 table.sort(out,function(a,c)return a.key<c.key end)
 if #out>128 then return nil,'Recipe catalog exceeds bounded 128 entries' end
 return out
end
local function editable(j,rs)
 if j.flags.special or j.flags.by_manager then return false end
 for _,r in ipairs(rs) do
  if r.reaction then
   if j.job_type==df.job_type.CustomReaction and j.reaction_name==r.reaction.code then return true end
  elseif j.job_type==r.fields.job_type and j.mat_type==(r.fields.mat_type or -1) then return true end
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
local function inspect(b,rs)
 local result={ok=true,message='Production inspected',buildings={info(b)},selected_building=b.id,
  recipes={},production_jobs={},crops={},seasonal_crops={},current_season=-1}
 if kind(b)=='FarmPlot' then local ok,err=farm_state(b,result);if not ok then return fail(err) end;return result end
 for _,r in ipairs(rs) do result.recipes[#result.recipes+1]={key=r.key,name=r.name,requirements=r.requirements} end
 if #b.jobs>64 then return fail('Workshop queue exceeds bounded inspector') end
 for _,j in ipairs(b.jobs) do
  local worker=J.getWorker(j)
  local status=j.flags.suspend and 'Suspended by native state' or (worker and 'Worker assigned' or 'Awaiting worker or inputs; native cause is not exposed')
  result.production_jobs[#result.production_jobs+1]={id=j.id,name=utf(J.getName(j)),job_type=j.job_type,
   repeat_job=j.flags['repeat'],suspended=j.flags.suspend,worker_id=worker and worker.id or -1,
   worker_name=worker and utf(dfhack.units.getReadableName(worker)) or '',completion_timer=j.completion_timer,
   attached_items=#j.items,editable=editable(j,rs),status=status,requirements=requirements(j)}
 end
 result.detail=(#rs==0 and 'Recipe creation for this building family is not supported yet. ' or '')..'Native workers select and haul inputs; queueing does not guarantee materials or labor. Work orders are not yet exposed.'
 local profile=b:getWorkshopProfile()
 if profile and #profile.permitted_workers>0 then result.detail=result.detail..' Workshop restricts workers ('..#profile.permitted_workers..').' end
 return result
end
return function(request)
 local p=request.production
 if not p then return fail('Production request required') end
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
 local rs,err=recipes(b);if not rs then return fail(err) end
 if request.action==16 then return inspect(b,rs) end
 if b:getBuildStage()~=b:getMaxBuildStage() then return fail('Building construction is unfinished') end
 local created=-1
 if request.action==17 then
  if kind(b)=='FarmPlot' then return fail('Select seasonal farm crops instead') end
  if #b.jobs>=10 then return fail('Native workshop queue is full (10 jobs)') end
  for _,j in ipairs(b.jobs) do if not editable(j,rs) then return fail('Building has a special or unsupported job; queue unchanged') end end
  local recipe
  for _,r in ipairs(rs) do if r.key==p.recipe then recipe=r end end
  if not recipe then return fail('Recipe is no longer available at this building') end
  local job,error=template_job(recipe);if not job then return fail(error) end
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
  if p.cancel then
   if not J.removeJob(job) then return fail('Native job cancellation rejected') end
  else
   if p.repeat_job~=-1 then job.flags['repeat']=p.repeat_job==1 end
   if p.suspend~=-1 then
    job.flags.suspend=p.suspend==1
    if p.suspend==1 then J.removeWorker(job,0) end
   end
  end
 elseif request.action==19 then
  if kind(b)~='FarmPlot' then return fail('A farm plot is required') end
  local current=inspect(b,rs);if not current.ok then return current end
  local valid=p.crop_id==-1
  for _,c in ipairs(current.crops) do if c.id==p.crop_id and math.floor(c.seasons/2^p.season)%2==1 then valid=true end end
  if not valid then return fail('Crop is not eligible for this farm and growing season') end
  b.plant_id[p.season]=p.crop_id
 else return fail('Unsupported production action') end
 local result=inspect(b,rs);result.created_job=created;result.message='Native production change applied';return result
end
