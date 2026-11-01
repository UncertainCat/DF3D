-- Read-only semantic creature facts. No viewscreen, widget, or input access.
local U,J=dfhack.units,dfhack.job
local utils=require('utils')
local diagnostics={}
local function utf(s)
 if type(s)=='userdata' then s=s.value end
 return dfhack.df2utf(tostring(s or ''))
end
local function enum(e,id)return tostring(e[id] or id):gsub('(%l)(%u)','%1 %2'):gsub('_',' '):lower()end
local function fail(s)return {ok=false,message=s}end
-- Preference reasons use this local seeded hash, matching the native creature
-- sheet formatter in DF 53.16. Do not call the native helpers: they reseed
-- DF's shared random generator.
local function preference_reason(raw,seed)
 if not raw or #raw.prefstring==0 then return nil end
 local z=(seed&0xffffffff)+0x9e3779b97f4a7c15
 z=(z~(z>>30))*0xbf58476d1ce4e5b9
 z=(z~(z>>27))*0x94d049bb133111eb
 return raw.prefstring[((z>>32)~(z>>63))%#raw.prefstring]
end
return function(request)
 local u=df.unit.find(request.unit_id)
 if not u or not U.isActive(u) then return fail('Creature is no longer active') end
 local x,y,z=U.getPosition(u)
 local p={x=x,y=y,z=z}
 if not x or not dfhack.maps.isValidTilePos(p) then return fail('Creature position unavailable') end
 local tile=dfhack.maps.getTileFlags(p)
 if not tile or tile.hidden then return fail('Creature position is hidden') end
 -- Matches the native creature sheet formatter in DF 53.16: biological age
 -- includes birth-date biases and freezes at the curse date; Units.getAge() does not.
 local age_year=u.curse_year~=-1 and u.curse_year or df.global.cur_year
 local age_tick=u.curse_year~=-1 and u.curse_time or df.global.cur_year_tick
 local age=age_year-u.birth_year_bias-u.birth_year
 if u.birth_time~=-1 and age_tick~=-1 and df.global.gamemode<=df.game_mode.ADVENTURE then
  local delta=age_tick-u.birth_time_bias-u.birth_time
  if delta<0 then age=age-math.floor((403200-delta)/403200)end
 end
 if age~=age or age<0 or age>1000000 then age=-1 else age=math.floor(age) end
 local caste=U.getCasteRaw(u)
 local result={ok=true,message='Creature facts observed',unit_id=u.id,x=x,y=y,z=z,
  captured_tick=df.global.world.frame_counter,name=utf(U.getReadableName(u)),
  species=utf(caste.caste_name[0]),profession=utf(U.getProfessionName(u)),
  job=u.job.current_job and utf(J.getName(u.job.current_job)) or 'No current job',
  age=age,sex=u.sex,complete=true,sections={}}
 local total,bytes,facts=0,0,0
 local function bounded(s,limit,section)
  s=utf(s)
  if #s>limit or bytes+#s>120000 then
   s=s:sub(1,math.max(0,math.min(limit,120000-bytes)))
   section.truncated=true;result.complete=false
  end
  bytes=bytes+#s;return s
 end
 local function record(section,id,name,related)
  if #section.records>=256 or total>=2048 then section.truncated=true;result.complete=false;section.reason=#section.records>=256 and 'Section record limit reached' or 'Creature record limit reached';return nil end
  total=total+1
  local row={id=id or -1,related_id=related or -1,name=bounded(name,512,section),facts={}}
  section.records[#section.records+1]=row;return row
 end
 local function fact(section,row,key,value)
  if not row then return end
  if #row.facts>=12 or facts>=8192 then section.truncated=true;result.complete=false;section.reason=#row.facts>=12 and 'Record fact limit reached' or 'Creature fact limit reached';return end
  facts=facts+1
  local number=type(value)=='number'
  row.facts[#row.facts+1]={key=key,text=number and '' or bounded(value,1024,section),number=number and value or 0,has_number=number}
 end
 local function thought_subject(s,r,v)
   if v.thought==df.unit_thought_type.NeedsUnfulfilled and v.subthought==2 and v.severity>=0 then
    local deity=df.historical_figure.find(v.severity)
    if deity then fact(s,r,'thought_subject',dfhack.translation.translateName(deity.name,true))end
   elseif v.thought==df.unit_thought_type.Syndrome and v.subthought>=0 then
    local syndromes=df.global.world.raws.mat_table.syndromes.all
    local syndrome=v.subthought<#syndromes and syndromes[v.subthought] or nil
    if syndrome then fact(s,r,'thought_subject',syndrome.syn_name)end
   elseif v.thought==df.unit_thought_type.Perform or v.thought==df.unit_thought_type.WatchPerform then
    -- Both native branches resolve this incident's performance event.
    local incident=df.incident.find(v.subthought)
    local performance=incident and incident.data.Performance
    fact(s,r,'performance_event',performance and performance.performance_event or -1)
   elseif v.thought==df.unit_thought_type.DefendedSiteAgainstInvaders then
    local entity=df.historical_entity.find(v.subthought)
    local site=df.world_site.find(v.severity)
    if entity then fact(s,r,'thought_subject',dfhack.translation.translateName(entity.name,true))end
    if site then fact(s,r,'thought_location',dfhack.translation.translateName(site.name,true))end
   elseif v.thought==df.unit_thought_type.SawDeadBody then
    local incident=df.incident.find(v.subthought)
    if incident then
     local hf=df.historical_figure.find(incident.victim_hf.hfid)
     if not hf and incident.victim_race>=0 then
      local raw=df.global.world.raws.creatures.all[incident.victim_race]
      local victim_caste=raw and raw.caste[incident.victim_caste]
      if victim_caste then fact(s,r,'thought_subject',victim_caste.caste_name[0]);fact(s,r,'thought_subject_kind','anonymous_species')end
     elseif hf then
      -- Matches the native creature sheet formatter in DF 53.16: historical id,
      -- otherwise first witnessed identity. Same-race named cases need no race-title prefix.
      local name_id=incident.victim_hf.historical_hfid
      if name_id<0 and #incident.victim_hf.all_witnessed_ident>0 then name_id=incident.victim_hf.all_witnessed_ident[0]end
      local known=df.historical_figure.find(name_id)
      if hf.race==u.race and known and known.name.has_name then
       fact(s,r,'thought_subject',dfhack.translation.translateName(known.name,true));fact(s,r,'thought_subject_kind','named_same_species')
      else fact(s,r,'thought_subject_kind','unresolved_historical_identity')end
     end
    else fact(s,r,'thought_subject_kind','unknown')end
   end
 end
 local function section(kind,fn)
  local s={kind=kind,available=true,truncated=false,reason='',records={}}
  result.sections[#result.sections+1]=s
  local ok,err=pcall(fn,s)
  if not ok then
   s.available=false;s.records={};s.reason='These facts are unavailable for this creature';result.complete=false
   if diagnostics[kind]~=tostring(err)then diagnostics[kind]=tostring(err);dfhack.printerr('DF3D creature section '..kind..': '..tostring(err))end
  end
  if s.truncated and s.reason=='' then s.reason='Collection limit reached; additional facts omitted' end
 end
 local soul=u.status.current_soul
 local hf=u.hist_figure_id>=0 and df.historical_figure.find(u.hist_figure_id) or nil
 -- Pets and other unit kinds legitimately lack a soul or historical figure;
 -- those sections stay empty with a reason instead of raising an error.
 local function absent(s,reason)s.reason=reason;return nil end
 local function personality(s)if not soul then return absent(s,'Creature has no current soul')end;return soul.personality end
 local function each(section,source,fn)
  local n=math.min(#source,256)
  for i=0,n-1 do fn(source[i],i) end
  if #source>n then section.truncated=true;result.complete=false end
 end
 section(0,function(s)
  local r=record(s,u.id,result.name)
  fact(s,r,'species',result.species);fact(s,r,'age',age);fact(s,r,'sex',u.sex)
  fact(s,r,'alive',U.isAlive(u) and 'yes' or 'no');fact(s,r,'citizen',U.isCitizen(u) and not U.isAnimal(u) and 'yes' or 'no')
  fact(s,r,'civilization_id',u.civ_id);fact(s,r,'historical_figure_id',u.hist_figure_id)
  fact(s,r,'birth_year',u.birth_year);fact(s,r,'birth_time',u.birth_time)
  fact(s,r,'caste_description',caste.description)
  if request.overview_status then
   local eligible,needs,squad,assigned,focus,color=request.overview_status(u.id)
   fact(s,r,'personality_summary_eligible',eligible and 'yes' or 'no')
   local summary=record(s,-4,'')
   fact(s,summary,'record_type','overview_status')
   fact(s,summary,'needs_summary_eligible',needs and 'yes' or 'no')
   fact(s,summary,'squad_text',squad);fact(s,summary,'squad_assigned',assigned and 'yes' or 'no')
   fact(s,summary,'focus_text',focus);fact(s,summary,'focus_color',color)
  end
  if request.hauling_summary then
   local id,text=request.hauling_summary(u.id)
   local task=record(s,id,'')
   fact(s,task,'record_type','overview_hauling');fact(s,task,'native_text',text)
  end
  local room_warning=''
  if request.room_requirements then
   local rooms=record(s,-5,'')
   fact(s,rooms,'record_type','overview_room_requirements')
   local required,actual,warning,color=request.room_requirements(u.id)
   room_warning=warning
   for i,key in ipairs{'office','bedroom','dining','tomb'}do fact(s,rooms,key,required[i]);fact(s,rooms,'actual_'..key,actual[i])end
   fact(s,rooms,'warning',warning);fact(s,rooms,'warning_color',color)
  end
  local office_count=0
  if request.header_activity then
   local text,color,background=request.header_activity(u.id)
   local activity=record(s,-9,'')
   fact(s,activity,'record_type','header_activity');fact(s,activity,'text',text)
   fact(s,activity,'color',color);fact(s,activity,'background',background)
  end
  if request.header_name then
   local name=request.header_name(u.id)
   local header=record(s,-8,'')
   fact(s,header,'record_type','header_name')
   fact(s,r,'translated_name',name.translated_name)
   for _,key in ipairs{'combined','name','profession','effect','source','foreground','background','bright','alternate_foreground','alternate_background','alternate_bright'}do fact(s,header,key,name[key])end
  end
  if request.customize_captions then
   local name,profession=request.customize_captions(u.id)
   local captions=record(s,-10,'')
   fact(s,captions,'record_type','customize_captions')
   fact(s,captions,'name',name);fact(s,captions,'profession',profession)
  end
  if request.expel_eligible then
   local eligible=request.expel_eligible(u.id)
   if eligible~=nil then
    local controls=record(s,-11,'')
    fact(s,controls,'record_type','expel_eligibility');fact(s,controls,'eligible',eligible and 1 or 0)
   end
  end
  if request.header_status then
   local text,color=request.header_status(u.id)
   local header=record(s,-7,'')
   fact(s,header,'record_type','header_status');fact(s,header,'text',text);fact(s,header,'color',color)
  end
  if request.office_titles then
   for _,title in ipairs(request.office_titles(u.id))do
    office_count=office_count+1
    local office=record(s,title.id,title.text,title.entity_id)
    fact(s,office,'record_type','overview_office');fact(s,office,'spouse',title.spouse and 'yes' or 'no')
   end
  end
  if office_count==0 and room_warning=='' and request.office_fallback then
   local status,position,color=request.office_fallback(u.id)
   if status~='' then
    local fallback=record(s,-6,'')
    fact(s,fallback,'record_type','overview_office_fallback');fact(s,fallback,'status',status)
    fact(s,fallback,'position',position);fact(s,fallback,'color',color)
   end
  end
  local dates=record(s,-3,'')
  fact(s,dates,'record_type','age_inputs');fact(s,dates,'current_year',df.global.cur_year)
  fact(s,dates,'birth_year_bias',u.birth_year_bias);fact(s,dates,'birth_time_bias',u.birth_time_bias)
  fact(s,dates,'curse_year',u.curse_year);fact(s,dates,'curse_time',u.curse_time)
  if soul then
   local focus=record(s,-2,'')
   fact(s,focus,'record_type','focus')
   fact(s,focus,'current_focus',soul.personality.current_focus)
   fact(s,focus,'undistracted_focus',soul.personality.undistracted_focus)
  end
  local owner_id=u.relationship_ids[df.unit_relationship_type.PetOwner]
  if owner_id>=0 or hf then
   local family=record(s,-1,'Family',owner_id)
   if owner_id>=0 then
    local owner=df.unit.find(owner_id)
    fact(s,family,'pet_owner_id',owner_id)
    if owner then fact(s,family,'pet_owner',U.getReadableName(owner))end
   end
   if hf then
    local children=0;local limit=math.min(#hf.histfig_links,4096)
    for i=0,limit-1 do if hf.histfig_links[i]:getType()==df.histfig_hf_link_type.CHILD then children=children+1 end end
    fact(s,family,'children_count',children)
    if #hf.histfig_links>limit then s.truncated=true;result.complete=false;fact(s,family,'children_count_complete','no')end
   end
  end
 end)
 section(1,function(s)
  if not soul then return absent(s,'Creature has no current soul')end
  each(s,soul.skills,function(v)
   local attrs=df.job_skill.attrs[v.id]
   local name=attrs.caption_noun
   if not name or name=='' then name=attrs.caption end
   if not name or name=='' then name=enum(df.job_skill,v.id) end
   local r=record(s,v.id,name);fact(s,r,'rating',v.rating);fact(s,r,'experience',v.experience)
   -- Native rank labels stop at Legendary; retain the uncapped numeric rating.
   fact(s,r,'rank',df.skill_rating.attrs[math.max(0,math.min(v.rating,df.skill_rating.Legendary))].caption)
   fact(s,r,'rusty',v.rusty)
   fact(s,r,'skill_class',enum(df.job_skill_class,attrs.type))
   if request.skill_profession then fact(s,r,'native_profession',request.skill_profession(v.id))end
   -- Raw profession-name overrides provide species-specific skill nouns
   -- (e.g. swordsdwarf); do not substitute generic profession captions.
   if attrs.profession>=0 then
    local custom=caste.caste_profession_name.singular[attrs.profession]
    if custom=='' then custom=df.global.world.raws.creatures.all[u.race].profession_name.singular[attrs.profession]end
    if custom~='' then fact(s,r,'profession_name',custom)end
   end
  end)
 end)
 section(2,function(s)
  -- Native Overview compares against the soul caste's median, including when
  -- the body has been transformed. Keep the numeric inputs in resident data.
  local baseline=soul and U.getCasteRaw(soul.race,soul.caste) or nil
  for i=0,df.physical_attribute_type._last_item do local v=u.body.physical_attrs[i]
   local r=record(s,i,enum(df.physical_attribute_type,i));fact(s,r,'category','physical');fact(s,r,'value',v.value);fact(s,r,'maximum',v.max_value)
   fact(s,r,'soft_demotion',v.soft_demotion);fact(s,r,'effective_value',U.getPhysicalAttrValue(u,i))
   if baseline then fact(s,r,'caste_median',baseline.attributes.phys_att_range[i][3])end
   fact(s,r,'body_caste_median',caste.attributes.phys_att_range[i][3])
  end
  if soul then for i=0,df.mental_attribute_type._last_item do local v=soul.mental_attrs[i]
   local r=record(s,100+i,enum(df.mental_attribute_type,i));fact(s,r,'category','mental');fact(s,r,'value',v.value);fact(s,r,'maximum',v.max_value)
   fact(s,r,'soft_demotion',v.soft_demotion);fact(s,r,'effective_value',U.getMentalAttrValue(u,i))
   if baseline then fact(s,r,'caste_median',baseline.attributes.ment_att_range[i][3])end
  end end
 end)
 section(3,function(s)
  if request.overview_health then
   for i,status in ipairs(request.overview_health(u.id))do
    local r=record(s,-100-i,status.text);fact(s,r,'record_type','overview_health')
    fact(s,r,'color',status.color);fact(s,r,'flash',status.flash)
   end
  end
  local r=record(s,-1,'Body condition');fact(s,r,'record_type','status');fact(s,r,'blood',u.body.blood_count);fact(s,r,'blood_maximum',u.body.blood_max)
  fact(s,r,'infection',u.body.infection_level);fact(s,r,'body_size',u.body.size_info.size_cur)
  each(s,u.body.wounds,function(v)
   local w=record(s,v.id,'Wound',v.attacker_unit_id);fact(s,w,'record_type','wound');fact(s,w,'age',v.age);fact(s,w,'pain',v.pain)
   fact(s,w,'nausea',v.nausea);fact(s,w,'dizziness',v.dizziness);fact(s,w,'paralysis',v.paralysis)
   fact(s,w,'numbness',v.numbness);fact(s,w,'fever',v.fever);fact(s,w,'affected_layers',#v.parts)
   fact(s,w,'diagnosed',v.flags.diagnosed and 'yes' or 'no')
  end)
  each(s,u.body.components.body_part_status,function(v,i)
   local part=u.body.body_plan.body_parts[i]
   local r=record(s,100000+i,part and part.name_singular[0] or 'Body part')
   fact(s,r,'record_type','body_part');fact(s,r,'body_part_id',i)
   for name,value in pairs(v)do if type(name)=='string' and value==true then fact(s,r,name,'yes')end end
  end)
  s.reason='Observed body, wound and body-part facts; native anatomical narrative is not reproduced'
 end)
 section(4,function(s)
  assert(request.inventory_rows,'Native Items provider unavailable')
  local rows=request.inventory_rows(u.id)
  for i,v in ipairs(rows)do
   local item_row=v.kind==0 or v.kind==1
   local r=record(s,item_row and v.id or -i,v.caption,v.id)
   if not r then break end
   fact(s,r,'row_kind',v.kind);fact(s,r,'native_role',v.role);fact(s,r,'parent_item_id',v.parent)
   fact(s,r,'assignment_indicator',v.indicator)
   local it=item_row and v.id>=0 and df.item.find(v.id) or nil
   if it then
   fact(s,r,'stack',it:getStackSize())
   fact(s,r,'item_type',it:getType())
   local subtype=dfhack.items.getSubtypeDef(it:getType(),it:getSubtype())
   if subtype then fact(s,r,'subtype_raw',subtype.id)end
   local material=dfhack.matinfo.decode(it:getMaterial(),it:getMaterialIndex())
   if material then fact(s,r,'material_token',material:getToken())end
   local color_id=it:getColorWhetherDyedOrNot()
   fact(s,r,'color',color_id)
   local colors=df.global.world.raws.descriptors.colors
   if color_id>=0 and color_id<#colors then fact(s,r,'color_token',colors[color_id].id)end
   end
  end
 end)
 section(5,function(s)
  if not request.relations then return end
  for i,value in ipairs(request.relations(u.id))do
   local r=record(s,i-1,value.caption,value.hf_id)
   fact(s,r,'unit_id',value.unit_id);fact(s,r,'native_description',value.description)
   fact(s,r,'description_color',value.description_color);fact(s,r,'family_type',value.family_type)
   fact(s,r,'social_type',value.social_type);fact(s,r,'priority',value.priority)
   if value.x then fact(s,r,'x',value.x);fact(s,r,'y',value.y);fact(s,r,'z',value.z)end
   if value.name_color then fact(s,r,'name_color',require('json').encode(value.name_color,{pretty=false}))end
  end
 end)
 section(6,function(s)
  local p=personality(s);if not p then return end
  for i=0,df.personality_facet_type._last_item do
   local r=record(s,i,enum(df.personality_facet_type,i));fact(s,r,'value',p.traits[i])
   fact(s,r,'temporary_change',p.temporary_trait_changes and p.temporary_trait_changes.traits[i] or 0)
  end
  local context=record(s,1000,'Personality context')
  fact(s,context,'record_type','personality_context')
  fact(s,context,'likes_outdoors',p.likes_outdoors);fact(s,context,'combat_hardened',p.combat_hardened)
  for _,v in ipairs(u.status.misc_traits)do
   if v.id==df.misc_trait_type.WantsDrink then fact(s,context,'alcohol_timer',v.value);break end
  end
  each(s,p.mannerism,function(v,i)
   local r=record(s,2000+i,enum(df.mannerism_type,v.type))
   fact(s,r,'record_type','mannerism');fact(s,r,'mannerism_type',v.type);fact(s,r,'situation',v.situation)
  end)
 end)
 section(7,function(s)
  local p=personality(s);if not p then return end
  local culture=p.cultural_identity>=0 and df.cultural_identity.find(p.cultural_identity)
  local civ=p.civ_id>=0 and df.historical_entity.find(p.civ_id)
  local baseline=culture and culture.values or civ and civ.resources.values
  local raws=df.global.world.raws.creatures.all
  local race=soul and soul.race or u.race
  local raw=race>=0 and race<#raws and raws[race] or nil
  local craftsman=raw and raw.profession_name.singular[df.profession.CRAFTSMAN] or ''
  each(s,p.values,function(v,i)
   local r=record(s,i,enum(df.value_type,v.type));fact(s,r,'strength',v.strength);fact(s,r,'value_id',v.type)
   fact(s,r,'record_type','personal_value')
   if baseline and v.type>=0 and v.type<#baseline then fact(s,r,'cultural_strength',baseline[v.type])end
   if v.type==df.value_type.CRAFTSMANSHIP then fact(s,r,'craftsman_term',craftsman)end
  end)
  if baseline then each(s,baseline,function(value,i)
   local r=record(s,1000+i,enum(df.value_type,i));fact(s,r,'record_type','cultural_value')
   fact(s,r,'value_id',i);fact(s,r,'strength',value)
   if i==df.value_type.CRAFTSMANSHIP then fact(s,r,'craftsman_term',craftsman)end
  end)end
 end)
 section(8,function(s)
  local p=personality(s);if not p then return end
  each(s,p.needs,function(v,i)local r=record(s,i,enum(df.need_type,v.id),v.deity_id)
   fact(s,r,'focus',v.focus_level);fact(s,r,'need_level',v.need_level)
   fact(s,r,'need_id',v.id);fact(s,r,'deity_id',v.deity_id)
   local deity=v.deity_id>=0 and df.historical_figure.find(v.deity_id)
   if deity then fact(s,r,'deity_name',dfhack.translation.translateName(deity.name,true))end
  end)
 end)
 section(9,function(s)
  local p=personality(s);if not p then return end
  each(s,p.dreams,function(v)local r=record(s,v.local_id,enum(df.goal_type,v.type),v.id);fact(s,r,'goal_type',v.type);fact(s,r,'accomplished',v.flags.accomplished and 'yes' or 'no')end)
 end)
 section(10,function(s)
  local p=personality(s);if not p then return end
  each(s,p.emotions,function(v,i)
   local r=record(s,i,enum(df.emotion_type,v.type))
   fact(s,r,'emotion_id',v.type);fact(s,r,'thought_id',v.thought);fact(s,r,'mood_flags',v.flags.whole)
   fact(s,r,'thought',enum(df.unit_thought_type,v.thought));fact(s,r,'strength',v.strength);fact(s,r,'relative_strength',v.relative_strength)
   fact(s,r,'severity',v.severity);fact(s,r,'year',v.year);fact(s,r,'year_tick',v.year_tick);fact(s,r,'subthought_id',v.subthought)
   thought_subject(s,r,v)
  end)
  s.reason='Native base emotion recipes use numeric facts; historical identity and causal modifiers remain partial'
 end)
 section(11,function(s)
  if not soul then return absent(s,'Creature has no current soul')end
  each(s,soul.preferences,function(v,i)
   local r=record(s,i,enum(df.unitpref_type,v.type))
   fact(s,r,'material_type',v.mattype);fact(s,r,'material_index',v.matindex)
   fact(s,r,'preference_type',v.type);fact(s,r,'visible',v.flags.visible and 'yes' or 'no')
   fact(s,r,'item_type',v.item_type);fact(s,r,'item_subtype',v.item_subtype)
   fact(s,r,'creature_name',dfhack.translation.translateName(U.getVisibleName(u)))
   local subject,reason,complete=nil,nil,true
   if v.type==df.unitpref_type.LikeMaterial or v.type==df.unitpref_type.LikeFood then
    local mat=dfhack.matinfo.decode(v.mattype,v.matindex)
    if mat and mat.material then
     -- Matches the native creature sheet formatter in DF 53.16: food is routed
     -- through item naming, and DRINK and LIQUID_MISC pass Liquid rather than
     -- the preference's mat_state.
     local state=v.mat_state
     if v.type==df.unitpref_type.LikeFood and (v.item_type==df.item_type.DRINK or v.item_type==df.item_type.LIQUID_MISC)then state=df.matter_state.Liquid end
     subject=mat.material.state_name[state]
     if mat.material.prefix~='' then subject=mat.material.prefix..' '..subject end
     if v.type==df.unitpref_type.LikeMaterial and v.mat_state==df.matter_state.Solid and mat.mode=='plant' then
      if mat.material.flags.WOOD then fact(s,r,'material_suffix','wood')
      elseif mat.material.flags.THREAD_PLANT then fact(s,r,'material_suffix','fabric')end
     end
    end
    -- Other food item classes use native item-description rules not yet traced.
    if v.type==df.unitpref_type.LikeFood and v.item_type~=df.item_type.DRINK and v.item_type~=df.item_type.LIQUID_MISC then complete=false end
   elseif v.type==df.unitpref_type.LikeCreature or v.type==df.unitpref_type.HateCreature then local raw=df.global.world.raws.creatures.all[v.creature_id];subject=raw and raw.name[1];if v.type==df.unitpref_type.LikeCreature then reason=preference_reason(raw,v.prefstring_seed)end
   elseif v.type==df.unitpref_type.LikePlant or v.type==df.unitpref_type.LikeTree then local raw=df.global.world.raws.plants.all[v.plant_id];subject=raw and raw.name_plural;reason=preference_reason(raw,v.prefstring_seed)
   elseif v.type==df.unitpref_type.LikeItem then
    local raw=dfhack.items.getSubtypeDef(v.item_type,v.item_subtype)
    if raw then local ok,name=pcall(function()return raw.name_plural end);if ok then subject=name end end
    if not subject then subject=enum(df.item_type,v.item_type);complete=false end
   elseif v.type==df.unitpref_type.LikeColor then local raw=df.global.world.raws.descriptors.colors[v.color_id];subject=raw and raw.name
   elseif v.type==df.unitpref_type.LikeShape then local raw=df.global.world.raws.descriptors.shapes[v.shape_id];subject=raw and raw.name_plural
   elseif v.type==df.unitpref_type.LikePoeticForm then local form=df.poetic_form.find(v.poetic_form_id);subject=form and dfhack.translation.translateName(form.name,true)
   elseif v.type==df.unitpref_type.LikeMusicalForm then local form=df.musical_form.find(v.musical_form_id);subject=form and dfhack.translation.translateName(form.name,true)
   elseif v.type==df.unitpref_type.LikeDanceForm then local form=df.dance_form.find(v.dance_form_id);subject=form and dfhack.translation.translateName(form.name,true)
   end
   if reason then fact(s,r,'reason',reason)end
   fact(s,r,'native_subject_complete',complete and 'yes' or 'no')
   if subject then fact(s,r,'subject',subject)else s.truncated=true;result.complete=false;s.reason='Some preference subjects could not be resolved'end
  end)
 end)
 section(12,function(s)
  if not request.military_squad then return end
  local value=request.military_squad(u.id)
  local r=record(s,value.id,value.caption,value.id)
  for _,key in ipairs{'short_name','order','order_color','symbol','foreground_r','foreground_g','foreground_b','background_r','background_g','background_b'}do
   fact(s,r,key,value[key])
  end
 end)
 section(13,function(s)
  -- Match ordinary labor eligibility; "everybody" is not every creature.
  if U.isAnimal(u) or not U.isCitizen(u) or not U.isAlive(u) or not U.isAdult(u) then return end
  local all=df.global.plotinfo.labor_info.work_details
  each(s,all,function(detail,i)
   local assigned=false
   for _,id in ipairs(detail.assigned_units)do if id==u.id then assigned=true;break end end
   local r=record(s,i,detail.name);fact(s,r,'mode',detail.flags.mode);fact(s,r,'explicitly_assigned',assigned and 'yes' or 'no')
   fact(s,r,'assigned',(assigned or detail.flags.mode==1) and 'yes' or 'no')
  end)
 end)
 section(14,function(s)
  if request.room_list then
   for i,v in ipairs(request.room_list(u.id))do
    if i>256 then s.truncated=true;result.complete=false;break end
    local r=record(s,v.id,v.caption,v.id>=0 and v.id or nil)
    fact(s,r,'zone_type',enum(df.civzone_type,v.subtype));fact(s,r,'room_kind',v.kind);fact(s,r,'room_value',v.value)
    fact(s,r,'custom_name',v.name);fact(s,r,'requirement',v.requirement);fact(s,r,'room_status',v.status)
    local room=v.id>=0 and df.building.find(v.id)or nil
    if room then fact(s,r,'x',room.centerx);fact(s,r,'y',room.centery);fact(s,r,'z',room.z)end
   end
   return
  end
  each(s,u.owned_buildings,function(v)
   local r=record(s,v.id,dfhack.buildings.getName(v),v.id)
   fact(s,r,'zone_type',enum(df.civzone_type,v.type));fact(s,r,'x',v.centerx);fact(s,r,'y',v.centery);fact(s,r,'z',v.z)
  end)
 end)
 section(15,function(s)
  if not request.groups then return end
  for i,value in ipairs(request.groups(u.id))do
   local r=record(s,i-1,value.caption,value.entity_id)
   fact(s,r,'native_type',value.type_caption);fact(s,r,'native_role',value.role)
   fact(s,r,'link_type',value.link_type);fact(s,r,'position_id',value.position_id)
   fact(s,r,'assignment_id',value.assignment_id);fact(s,r,'spouse',value.spouse)
   fact(s,r,'reputation',value.reputation);fact(s,r,'reputation_level',value.reputation_level)
  end
 end)
 section(16,function(s)
  local p=personality(s);if not p then return end
  local memories=p.memories;if not memories then return end
  local function memory(v,i,category)
   if v.type<0 or v.thought<0 or (category~='core' and not v.flags.has_remembered)then return end
   local r=record(s,i,enum(df.emotion_type,v.type));fact(s,r,'memory_category',category)
   fact(s,r,'emotion_id',v.type);fact(s,r,'thought_id',v.thought);fact(s,r,'subthought_id',v.subthought);fact(s,r,'severity',v.severity)
   fact(s,r,'year',v.year);fact(s,r,'year_tick',v.year_tick)
   fact(s,r,'created_year',v.created_year);fact(s,r,'created_tick',v.created_tick)
   fact(s,r,'has_remembered',v.flags.has_remembered and 'yes' or 'no')
   thought_subject(s,r,v)
  end
  for i=0,7 do if memories.shortterm[i].year>=0 then memory(memories.shortterm[i],i,'short term') end end
  for i=0,7 do if memories.longterm[i].year>=0 then memory(memories.longterm[i],8+i,'long term') end end
  -- Traits/Values use the last matching core, including unremembered cores.
  -- Keep those winners plus remembered history, not unrelated dormant cores.
  local facet_causes,value_causes,needed={},{},{}
  for i,v in ipairs(memories.core_memories)do
   if v.changed_facet>=0 then facet_causes[v.changed_facet]=i end
   if v.changed_value>=0 then value_causes[v.changed_value]=i end
  end
  for _,i in pairs(facet_causes)do needed[i]=true end
  for _,i in pairs(value_causes)do needed[i]=true end
  each(s,memories.core_memories,function(v,i)
   if not v.memory.flags.has_remembered and not needed[i]then return end
   memory(v.memory,16+i,'core')
   if v.memory.type>=0 and v.memory.thought>=0 and (v.changed_facet>=0 or v.changed_value>=0)then
    local r=record(s,100000+i,'Memory effect',16+i)
    fact(s,r,'record_type','memory_effect');fact(s,r,'changed_facet',v.changed_facet)
    fact(s,r,'facet_old',v.facet_old);fact(s,r,'facet_new',v.facet_new)
    fact(s,r,'changed_value',v.changed_value);fact(s,r,'value_old',v.value_old);fact(s,r,'value_new',v.value_new)
   end
  end)
 end)
 section(17,function(s)
  if not u.health then return end
  for name,value in pairs(u.health.flags) do if type(name)=='string' and value==true then
   local r=record(s,-1,name:gsub('_',' '))
   fact(s,r,'native_treatment',(name=='rq_diagnosis' or name=='rq_crutch') and 'yes' or 'no')
  end end
  each(s,u.health.body_part_flags,function(v,i)
   for name,value in pairs(v)do if type(name)=='string' and value==true then
    local r=record(s,i,name:gsub('_',' '));fact(s,r,'body_part_id',i)
    fact(s,r,'native_treatment',(name:sub(1,3)=='rq_' or name=='inoperable_rot') and 'yes' or 'no')
   end end
  end)
 end)
 section(18,function(s)
  if not u.health then return end
  each(s,u.health.op_history,function(v,i)local r=record(s,i,enum(df.job_type,v.job_type),v.doctor_id)
   fact(s,r,'year',v.year);fact(s,r,'year_tick',v.year_time)
  end)
  each(s,u.health.syndrome_diagnosis,function(v,i)local r=record(s,1000+i,'Syndrome diagnosis',v.worker_unid)
   fact(s,r,'syndrome_id',v.syndrome_ind);fact(s,r,'year',v.year);fact(s,r,'year_tick',v.season_count)
  end)
 end)
 section(19,function(s)
  if not hf or not hf.info or not hf.info.known_info then return end
  local known=hf.info.known_info;local k=known.knowledge
  if k then
   for _,category in ipairs{'philosophy','philosophy2','math','math2','history','astronomy','naturalist','chemistry','geography','medicine','medicine2','medicine3','engineering','engineering2'}do
    for name,value in pairs(k[category])do if type(name)=='string' and value==true then local r=record(s,-1,name:gsub('_',' '));fact(s,r,'category',category)end end
   end
  end
  for _,source in ipairs{{known.known_poetic_forms,df.poetic_form,'Poetic form'},
                         {known.known_musical_forms,df.musical_form,'Musical form'},
                         {known.known_dance_forms,df.dance_form,'Dance form'}}do
   each(s,source[1],function(id)
    local form=source[2].find(id)
    if form then local r=record(s,#s.records,dfhack.translation.translateName(form.name,true),id);fact(s,r,'category',source[3])end
   end)
  end
  each(s,known.known_written_contents,function(id)
   local content=df.written_content.find(id)
   if content then
    local r=record(s,#s.records,content.title,id)
    fact(s,r,'category',enum(df.written_content_type,content.type));fact(s,r,'author_id',content.author)
   end
  end)
 end)
 section(20,function(s)
  if not request.military_uniform then return end
  local has_squad,rows=request.military_uniform(u.id)
  if not has_squad then local r=record(s,-1,'');fact(s,r,'no_squad',1);return end
  for _,value in ipairs(rows)do
   local r=record(s,value.id,value.caption,value.id)
   fact(s,r,'native_role',value.role);fact(s,r,'resolved',value.resolved);fact(s,r,'carried',value.carried)
   fact(s,r,'item_type',value.item_type)
   if value.appearance then fact(s,r,'appearance',require('json').encode(value.appearance,{pretty=false}))end
   fact(s,r,'x',value.x);fact(s,r,'y',value.y);fact(s,r,'z',value.z)
  end
 end)
 section(21,function(s)
  if not request.military_kills then return end
  local text=request.military_kills(u.id)
  -- Raw DF text is single-byte; convert each bounded chunk once, then join in
  -- the presentation before parsing native paragraph/color tags.
  for first=1,#text,256 do
   local r=record(s,(first-1)//256,'')
   fact(s,r,'native_text',text:sub(first,first+255))
  end
 end)
 section(22,function(s)
  if not request.workshop_list then return end
  for i,v in ipairs(request.workshop_list(u.id))do
   if i>256 then s.truncated=true;result.complete=false;break end
   local r=record(s,v.id,utf(v.caption),v.id)
   fact(s,r,'building_type',v.type);fact(s,r,'building_subtype',v.subtype)
   fact(s,r,'assignment_revision',v.revision)
   fact(s,r,'x',v.x);fact(s,r,'y',v.y);fact(s,r,'z',v.z)
   local raw=v.custom>=0 and df.global.world.raws.buildings.all[v.custom] or nil
   if raw then fact(s,r,'custom_code',raw.code)end
  end
 end)
 section(23,function(s)
  if not request.location_list then return end
  for i,v in ipairs(request.location_list(u.id))do
   if i>256 then s.truncated=true;result.complete=false;break end
   local r=record(s,v.id,utf(v.role),v.location_id)
   fact(s,r,'location_id',v.location_id);fact(s,r,'site_id',v.site_id)
   fact(s,r,'occupation_type',v.type);fact(s,r,'location_type',v.location_type)
   fact(s,r,'location_tier',v.tier);fact(s,r,'location_name',utf(v.name))
   fact(s,r,'removable',v.removable);fact(s,r,'assignment_revision',v.revision)
   fact(s,r,'zone_id',v.zone_id);fact(s,r,'x',v.x);fact(s,r,'y',v.y);fact(s,r,'z',v.z)
  end
 end)
 section(24,function(s)
  if not request.work_animal_list then return end
  for i,v in ipairs(request.work_animal_list(u.id))do
   if i>256 then s.truncated=true;result.complete=false;break end
   local r=record(s,v.id,v.caption,v.owner_id)
   fact(s,r,'animal_id',v.id);fact(s,r,'owner_id',v.owner_id);fact(s,r,'assigned',v.assigned);fact(s,r,'assignment_revision',v.revision)
   fact(s,r,'x',v.x);fact(s,r,'y',v.y);fact(s,r,'z',v.z)
  end
 end)
 return result
end
