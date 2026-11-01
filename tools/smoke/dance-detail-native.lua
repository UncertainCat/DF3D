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
 elseif kind==df.history_event_type.ARTIFACT_CREATED then
  figure(value.creator_hfid);entity(value.entity);site(value.site)
  local artifact=df.artifact_record.find(value.artifact_id)
  if artifact then
   object(artifact);name(artifact.name);local item=artifact.item;object(item)
   assert(item and (df.item_statuest:is_instance(item) or df.item_figurinest:is_instance(item) or df.item_coinst:is_instance(item)),'Artifact probe expects a statue, figurine or coin')
   vector(item.general_refs);vector(item.improvements)
   for _,ref in ipairs(item.general_refs)do object(ref)end
   for _,improvement in ipairs(item.improvements)do
    assert(df.itemimprovement_bandsst:is_instance(improvement),'Add guards for this decoration');object(improvement)
   end
   if df.item_coinst:is_instance(item) then
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
 elseif kind==df.history_event_type.AGREEMENT_FORMED then
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
    object(detail);assert(detail.type==df.agreement_details_type.JoinParty,'Add guards for this agreement detail')
    local data=assert(detail.data.JoinParty);object(data)
    assert((data.reason==24 or data.reason==2)and data.figure==-1,'Probe expects identity-bearing JoinParty')
    local identity=df.identity.find(data.entity)
    if identity then
     object(identity);name(identity.name);figure(identity.impersonated_hf);entity(identity.entity_id)
     vector(identity.entity_profile);vector(identity.cultural_identity_profile)
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
