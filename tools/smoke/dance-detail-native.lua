-- Compare the owned formatter with an already-open native Knowledge detail.
local unit,detail=...
local json=require('json')
local form=assert(df.dance_form.find(detail.id))
local guards={}
local function guard(address,size)
 if size==0 then return end
 assert(size>0 and size<1048576)
 local bytes=df.new('uint8_t',size);dfhack.internal.memmove(bytes,address,size)
 guards[#guards+1]={bytes=bytes,address=address,size=size}
end
local function object(value)if value then local size,address=df.sizeof(value);guard(address,size)end end
local function vector(value)
 local _,address=df.sizeof(value);local first=df.reinterpret_cast('uint64_t',address).value
 guard(first,df.reinterpret_cast('uint64_t',address+8).value-first)
end
local function string_backing(address)
  local size=df.reinterpret_cast('uint64_t',address+16).value
  local capacity=df.reinterpret_cast('uint64_t',address+24).value
  if capacity>=16 then guard(df.reinterpret_cast('uint64_t',address).value,size+1)end
end
local function name(value)
 object(value)
 for _,field in ipairs{'first_name','nickname'}do
  local _,address=df.sizeof(value:_field(field));string_backing(address)
 end
end
local figures={}
local function figure(id)
 if id<0 or figures[id]then return end;figures[id]=true
 local value=df.historical_figure.find(id)
 if value then object(value);name(value.name);object(value.info)end
end
local function string_field(value,field)
 local _,address=df.sizeof(value:_field(field));string_backing(address)
end
local function entity(id)
 local value=df.historical_entity.find(id);if not value then return end
 object(value);name(value.name);vector(value.positions.own)
 for _,position in ipairs(value.positions.own)do object(position)end
end
local function site(id)
 local value=df.world_site.find(id);if not value then return end
 object(value);name(value.name);vector(value.buildings)
 for _,building in ipairs(value.buildings)do object(building)end
end
local function coin_artifact(id)
   local artifact=df.artifact_record.find(id)
   if artifact then
    object(artifact);name(artifact.name);local item=assert(artifact.item);object(item)
    assert(df.item_coinst:is_instance(item),'Add guards for this artifact item')
    vector(item.general_refs)
    for _,ref in ipairs(item.general_refs)do assert(df.general_ref_is_artifactst:is_instance(ref));object(ref)end
    vector(item.improvements);assert(#item.improvements==0)
    vector(df.global.world.coin_batches.all)
    if item.coin_batch~=-1 then
     local batch=assert(df.global.world.coin_batches.all[item.coin_batch]);object(batch)
     if batch.entity~=-1 then
      local issuer=assert(df.historical_entity.find(batch.entity));entity(batch.entity);object(assert(issuer.entity_raw))
      local _,address=df.sizeof(issuer.entity_raw:_field('flags'))
      guard(df.reinterpret_cast('uint64_t',address).value,df.reinterpret_cast('int32_t',address+8).value)
      figure(batch.ruler)
     end
    end
   end
end
local function competition_collection(id)
 vector(df.global.world.history.event_collections.all)
 local value=df.history_event_collection.find(id);if not value then return end
 assert(df.history_event_collection_competitionst:is_instance(value),'Add collection source guards')
 object(value);vector(value.events);vector(value.collections)
 local owner=df.historical_entity.find(value.civ);if not owner then return end
 entity(value.civ);object(owner.occasion_info);if not owner.occasion_info then return end
 vector(owner.occasion_info.occasions)
 for _,occasion in ipairs(owner.occasion_info.occasions)do
  object(occasion)
  if occasion.id==value.occasion then
   name(occasion.name);vector(occasion.schedule)
   assert(value.schedule>=0 and value.schedule<#occasion.schedule)
   local schedule=occasion.schedule[value.schedule];object(schedule)
   if schedule then
    vector(schedule.features);assert(#schedule.features==0)
    local function strings(value)
     local size,address=df.sizeof(value);local stride=size/#value
     for i=0,#value-1 do string_backing(address+i*stride)end
    end
    if schedule.type==df.occasion_schedule_type.MOUNTED_RACE then
     local raws=df.global.world.raws.creatures.all;vector(raws)
     if schedule.reference>=0 and schedule.reference<#raws then
      local raw=assert(raws[schedule.reference]);object(raw);strings(raw.name);vector(raw.caste)
      if schedule.reference2>=0 and schedule.reference2<#raw.caste then
       local caste=assert(raw.caste[schedule.reference2]);object(caste);strings(caste.caste_name)
      end
     end
    elseif schedule.type==df.occasion_schedule_type.THROWING_COMPETITION then
     assert(schedule.reference==df.item_type.COIN and schedule.reference2==-1 and schedule.reference3==0 and schedule.reference4==0,'Add throwing source guards')
     vector(df.global.world.raws.inorganics.all);local inorganic=assert(df.global.world.raws.inorganics.all[0]);object(inorganic);object(inorganic.material)
     strings(inorganic.material.state_name)
     strings(inorganic.material.state_adj);string_field(inorganic.material,'prefix')
    end
   end
  end
 end
end
local visited={}
local function event(id)
 if id<0 then return end
 if visited[id]then return end;visited[id]=true
 local value=df.history_event.find(id);if not value then return end;object(value)
 local _,address=df.sizeof(value:_field('flags'))
 guard(df.reinterpret_cast('uint64_t',address).value,df.reinterpret_cast('int32_t',address+8).value)
 local kind=value:getType()
 if kind==df.history_event_type.CHANGE_HF_STATE then
  figure(value.hfid);site(value.site)
 elseif kind==df.history_event_type.ADD_HF_ENTITY_LINK then
  figure(value.histfig);figure(value.appointer_hfid);figure(value.promise_to_hfid);entity(value.civ)
 elseif kind==df.history_event_type.CREATED_SITE or kind==df.history_event_type.CREATED_BUILDING then
  figure(value.builder_hf);entity(value.civ);entity(value.site_civ);site(value.site)
 elseif kind==df.history_event_type.ITEM_STOLEN or kind==df.history_event_type.HIST_FIGURE_DIED then
  local ids
  if kind==df.history_event_type.ITEM_STOLEN then
   ids={value.item};figure(value.histfig);entity(value.entity);site(value.site);site(value.stash_site)
   assert(value.reason.type==-1 and value.circumstance.type==-1,'Add theft circumstance guards')
  else
   ids={value.weapon.item,value.weapon.shooter_item};figure(value.victim_hf);figure(value.slayer_hf);site(value.site)
  end
  for _,id in ipairs(ids)do
   local item=df.item.find(id)
   if item then
    object(item);vector(item.general_refs)
    for _,ref in ipairs(item.general_refs)do
     object(ref);assert(df.general_ref_is_artifactst:is_instance(ref),'Add guards for this reference')
     coin_artifact(ref.artifact_id)
    end
   end
  end
 elseif kind==df.history_event_type.ARTIFACT_LOST or kind==df.history_event_type.ARTIFACT_TRANSFORMED or kind==df.history_event_type.ARTIFACT_GIVEN then
  if kind~=df.history_event_type.ARTIFACT_GIVEN then site(value.site)end
  local ids={}
  if kind==df.history_event_type.ARTIFACT_TRANSFORMED then
   ids={value.new_artifact};vector(value.old_artifact);figure(value.histfig)
   for _,id in ipairs(value.old_artifact)do ids[#ids+1]=id end
  else ids={value.artifact}end
  if kind==df.history_event_type.ARTIFACT_GIVEN then
   figure(value.giver_hf);entity(value.giver_entity);figure(value.receiver_hf);entity(value.receiver_entity)
   assert(value.reason.type==-1,'Add guards for this reason')
   local thought=value.circumstance.type
   if thought==df.unit_thought_type.HistEventCollection then competition_collection(value.circumstance.data.HistEventCollection)
   else
    assert(thought==df.unit_thought_type.AcquireArtifact or thought==df.unit_thought_type.GaveArtifact,'Add guards for this circumstance')
    ids[#ids+1]=value.circumstance.data.Death
   end
  end
  for _,id in ipairs(ids)do coin_artifact(id)end
 elseif kind==df.history_event_type.ARTIFACT_CREATED then
  figure(value.creator_hfid);entity(value.entity);site(value.site)
  local artifact=df.artifact_record.find(value.artifact_id)
  if artifact then
   object(artifact);name(artifact.name);local item=artifact.item;object(item)
   local corpse=item and df.item_corpsest:is_instance(item)
   assert(item and (corpse or df.item_statuest:is_instance(item) or df.item_figurinest:is_instance(item) or df.item_coinst:is_instance(item) or df.item_cagest:is_instance(item)),'Add guards for this artifact item')
   vector(item.general_refs)
   for _,ref in ipairs(item.general_refs)do object(ref)end
   if not corpse then vector(item.improvements);for _,improvement in ipairs(item.improvements)do
    assert(df.itemimprovement_bandsst:is_instance(improvement),'Add guards for this decoration');object(improvement)
   end end
   if corpse then
    figure(item.hist_figure_id);figure(item.hist_figure_id2)
    local owner=df.unit.find(item.unit_id);object(owner)
    if owner then name(owner.name);figure(owner.hist_figure_id)end
    vector(item.body.wounds);assert(#item.body.wounds==0,'Add corpse wound guards')
    for _,field in ipairs{'body_part_status','numbered_masks','nonsolid_remaining','layer_status','layer_wound_area','layer_cut_fraction','layer_dent_fraction','layer_effect_fraction'}do vector(item.body.components[field])end
   elseif df.item_cagest:is_instance(item) then
    for _,ref in ipairs(item.general_refs)do
     assert(df.general_ref_contains_unitst:is_instance(ref),'Cage probe expects contained unit')
     local contained=assert(df.unit.find(ref.unit_id));object(contained)
     for _,value in ipairs{contained.body.components.body_part_status,contained.enemy.motor_nervenet,contained.enemy.sensory_nervenet,contained.enemy.body_part_useable}do vector(value)end
    end
   elseif df.item_coinst:is_instance(item) then
    vector(df.global.world.coin_batches.all)
    if item.coin_batch~=-1 then
     assert(item.coin_batch>=0 and item.coin_batch<#df.global.world.coin_batches.all,'Invalid coin batch')
     local batch=assert(df.global.world.coin_batches.all[item.coin_batch]);object(batch)
     if batch.entity~=-1 then
      local issuer=assert(df.historical_entity.find(batch.entity));entity(batch.entity)
      object(assert(issuer.entity_raw))
      local _,address=df.sizeof(issuer.entity_raw:_field('flags'))
      guard(df.reinterpret_cast('uint64_t',address).value,df.reinterpret_cast('int32_t',address+8).value)
      figure(batch.ruler)
     end
    end
   else
   string_field(item,'description')
   assert(item.image.id>=0,'Artifact probe expects initialized image')
   local chunk=assert(df.art_image_chunk.find(item.image.id));local art=assert(chunk.images[item.image.subid].art_image)
   object(art);vector(art.elements);vector(art.properties);object(art.ref)
   for _,entry in ipairs(art.elements)do object(entry)end
   for _,entry in ipairs(art.properties)do object(entry)end
   end
  end
 elseif kind==df.history_event_type.AGREEMENT_FORMED or kind==df.history_event_type.AGREEMENT_CONCLUDED then
  if kind==df.history_event_type.AGREEMENT_CONCLUDED then figure(value.concluder_hf);assert(value.reason==-1)end
  vector(df.global.world.agreements.all);vector(df.global.world.identities.all)
  local agreement=df.agreement.find(value.agreement_id)
  if agreement then
   object(agreement);vector(agreement.parties);vector(agreement.details)
   for _,party in ipairs(agreement.parties)do
    object(party);vector(party.histfig_ids);vector(party.entity_ids);vector(party.complaint)
    for _,id in ipairs(party.histfig_ids)do figure(id)end
    for _,id in ipairs(party.entity_ids)do entity(id)end
   end
   for _,detail in ipairs(agreement.details)do
    object(detail)
    if detail.type==df.agreement_details_type.RetrieveArtifact then
     local data=assert(detail.data.RetrieveArtifact);object(data);coin_artifact(data.artifact);site(data.artifact_site);entity(data.receiving_entity)
    elseif detail.type==df.agreement_details_type.PlotStealArtifact then
     local data=assert(detail.data.PlotStealArtifact);object(data);coin_artifact(data.artifact_id)
    else
    assert(detail.type==df.agreement_details_type.JoinParty,'Add guards for this agreement detail')
    local data=assert(detail.data.JoinParty);object(data)
    assert((data.reason==24 or data.reason==2)and data.figure==-1,'Probe expects identity-bearing JoinParty')
    local identity=df.identity.find(data.entity)
    if identity then
     object(identity);name(identity.name);figure(identity.impersonated_hf);entity(identity.entity_id)
     vector(identity.entity_profile);vector(identity.cultural_identity_profile)
    end
    end
   end
  end
 elseif kind==df.history_event_type.ASSUME_IDENTITY then
  figure(value.trickster);entity(value.target);vector(df.global.world.identities.all)
  local identity=df.identity.find(value.identity)
  if identity then
   object(identity);name(identity.name);figure(identity.impersonated_hf);entity(identity.entity_id)
   vector(identity.entity_profile);vector(identity.cultural_identity_profile)
  end
 elseif kind==df.history_event_type.MASTERPIECE_LOST then
  figure(value.histfig);site(value.site);event(value.creation_event)
 elseif kind==df.history_event_type.PERFORMANCE then
  entity(value.entity);site(value.site)
  local owner=df.historical_entity.find(value.entity)
  if owner and owner.occasion_info then
   object(owner.occasion_info);vector(owner.occasion_info.occasions)
   for _,occasion in ipairs(owner.occasion_info.occasions)do
    if occasion.id==value.occasion then
     object(occasion);name(occasion.name);vector(occasion.schedule)
     if value.schedule>=0 and value.schedule<#occasion.schedule then
      local schedule=occasion.schedule[value.schedule];object(schedule)
      assert(schedule.type==3,'Recursive performance probe expects storytelling')
      event(schedule.reference)
     end
     break
    end
   end
  end
 else error('Add source guards before probing this event type')end
end
local ok,result=xpcall(function()
 object(form);name(form.name);figure(form.original_author);figure(form.hfid);entity(form.originating_entity)
 for _,field in ipairs{'partner_changes','move_type','move_modifier','move_parameter','move_location','sections','moves'}do vector(form[field])end
 event(form.event)
 for _,value in ipairs(form.sections)do
  object(value);figure(value.acts_out_hf_story);event(value.acts_out_event)
  for _,field in ipairs{'partner_changes','type','modifier','parameter','location'}do vector(value[field])end
 end
 for _,value in ipairs(form.moves)do
  object(value);string_field(value,'name')
  for _,field in ipairs{'type','modifier','parameter','location'}do vector(value[field])end
 end
 local music=df.musical_form.find(form.musical_form_id);if music then object(music);name(music.name)end
 local content=df.written_content.find(form.music_written_content_id);if content then object(content);string_field(content,'title')end
 object(unit);object(df.global.game.main_interface.view_sheets);object(df.global.plotinfo)
 local base=dfhack.internal.getImageBase()
 for _,range in ipairs{{0x234e990,0x6180},{0x2131b30,40},{0x2159084,2},{0x18adf98,8}}do guard(base+range[1],range[2])end
 local text,status=dfhack.run_command_silent('df3d','dance-detail-probe',tostring(form.id))
 assert(status==0,text);local probe=json.decode(text)
 assert(#detail.tagged_rows==1 and probe.text==detail.tagged_rows[1],'Dance description differs from native')
 return probe
end,debug.traceback)
local unchanged=true
for _,entry in ipairs(guards)do
 if dfhack.internal.memcmp(entry.bytes,entry.address,entry.size)~=0 then unchanged=false end
 df.delete(entry.bytes)
end
assert(ok,result);assert(unchanged,'Dance probe changed guarded source/UI/random state')
result.guards_unchanged=true
return result
