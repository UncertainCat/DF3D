-- Valid coin-caption branches only; never pass malformed native indices.
local unit,form_id,capture,out=...
local json=require('json');local form=assert(df.dance_form.find(form_id))
local world=df.global.world;local events=world.history.events;local artifacts=world.artifacts.all;local items=world.items.all;local batches=world.coin_batches.all
local issuer=assert(df.historical_entity.find(unit.civ_id));local raw=assert(issuer.entity_raw)
local flag=raw.flags.CURRENCY_BY_YEAR;local original=form.event
local counts={#events,#artifacts,#items,#batches};assert(#batches<32767)
local results={};local rejections={}
for _,variant in ipairs{'no-batch','no-issuer','year','no-year','ruler','missing-ruler'}do
 local item=df.item_coinst:new();local batch=df.coin_batch:new();local artifact=df.artifact_record:new();local event=df.history_event_artifact_createdst:new()
 local ok,err=xpcall(function()
  item.id=items[#items-1].id+1;item.mat_type=0;item.mat_index=0;item.quality=0;item.maker=-1;item.maker_race=unit.race
  item.world_data_id=-1;item.world_data_subid=-1;item.coin_batch=variant=='no-batch'and -1 or #batches
  batch.entity=variant=='no-issuer'and -1 or issuer.id;batch.year=variant=='no-year'and -1 or 123
  batch.mat_type=0;batch.mat_index=0;batch.ruler=-1
  if variant=='ruler'then batch.ruler=unit.hist_figure_id;assert(df.historical_figure.find(batch.ruler))end
  if variant=='missing-ruler'then batch.ruler=world.history.figures[#world.history.figures-1].id+1;assert(not df.historical_figure.find(batch.ruler))end
  raw.flags.CURRENCY_BY_YEAR=variant=='year'or variant=='no-year'
  batches:insert('#',batch)
  artifact.id=artifacts[#artifacts-1].id+1;artifact.item=item;artifact.name.has_name=false
  event.id=events[#events-1].id+1;event.year=df.global.cur_year;event.seconds=df.global.cur_year_tick
  event.artifact_id=artifact.id;event.creator_unit_id=-1;event.creator_hfid=-1;event.entity=-1;event.site=-1
  items:insert('#',item);artifacts:insert('#',artifact);events:insert('#',event);form.event=event.id
  local before={id=world.worldgen.next_art_image_chunk_id,offset=world.worldgen.next_art_image_chunk_offset}
  local native=capture('coin-'..variant);local warm=capture('coin-'..variant..'-warm')
  assert(native==warm,'Repeated coin description differs')
  assert(before.id==world.worldgen.next_art_image_chunk_id and before.offset==world.worldgen.next_art_image_chunk_offset,'Coin caption allocated art')
  results[#results+1]={case=variant,text=native,batch_index=item.coin_batch,issuer=batch.entity,year=batch.year,ruler=batch.ruler,currency_by_year=raw.flags.CURRENCY_BY_YEAR,no_art_allocation=true}
  if variant=='year'then
   local index=item.coin_batch
   local function reject(label,extra)
    local guards={}
    local values={item,batch,artifact,df.history_event.find(form.event),unit,issuer,df.global.game.main_interface.view_sheets,df.global.plotinfo}
    for _,value in ipairs(extra or {})do values[#values+1]=value end
    for _,value in ipairs(values)do
     local size,address=df.sizeof(value);local bytes=df.new('uint8_t',size);dfhack.internal.memmove(bytes,address,size)
     guards[#guards+1]={bytes=bytes,address=address,size=size}
    end
    local text,status=dfhack.run_command_silent('df3d','dance-detail-probe',tostring(form.id))
    local unchanged=true
    for _,guard in ipairs(guards)do
     if dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)~=0 then unchanged=false end
     df.delete(guard.bytes)
    end
    assert(status~=0,'Malformed coin source accepted: '..label..' '..text);assert(unchanged,'Rejected coin changed source/UI')
    rejections[#rejections+1]={case=label,rejected=true,guards_unchanged=true}
   end
   item.coin_batch=-2;reject('negative-batch')
   item.coin_batch=#batches;reject('past-end-batch');item.coin_batch=index
   batches[index]=nil;reject('null-batch');batches[index]=batch
   batch.entity=2147483647;assert(not df.historical_entity.find(batch.entity));reject('missing-issuer');batch.entity=issuer.id
   issuer.entity_raw=nil;reject('missing-issuer-raw');issuer.entity_raw=raw
   artifact.item=nil;reject('missing-artifact-item');artifact.item=item
   artifact.name.has_name=true
   local empty_name=capture('coin-empty-name-flag');assert(empty_name==native,'Empty name flag changed native caption')
   assert(empty_name==capture('coin-empty-name-flag-warm'))
   results[#results+1]={case='empty-name-flag',text=empty_name}
   item.coin_batch=-2;reject('empty-name-flag-invalid-coin');item.coin_batch=index
   artifact.name.has_name=false
   local classes={'artifact_claim_formed','artifact_copied','artifact_destroyed','artifact_dropped','artifact_found','artifact_given','artifact_hidden','artifact_lost','artifact_possessed','artifact_recovered','artifact_stored','hf_act_on_artifact','hf_learns_secret','artifact_transformed'}
   for _,kind in ipairs(classes)do
    local dependency=df['history_event_'..kind..'st']:new()
    local dependency_ok,dependency_error=xpcall(function()
     dependency.id=events[#events-1].id+1;dependency.year=event.year;dependency.seconds=event.seconds
     if kind=='artifact_transformed'then dependency.new_artifact=artifact.id
     else dependency.artifact=artifact.id end
     events:insert('#',dependency);form.event=dependency.id
     item.coin_batch=-2;reject(kind..'-invalid-coin');item.coin_batch=index
     if kind=='artifact_lost'then
      dependency.site=-1;dependency.site_property_id=-1;dependency.subregion_id=-1;dependency.layer_id=-1
     elseif kind=='artifact_transformed'then
      dependency.unit=-1;dependency.histfig=-1;dependency.site=-1
      dependency.new_artifact=-1;dependency.old_artifact:insert('#',-1);dependency.old_artifact:insert('#',artifact.id)
      item.coin_batch=-2;reject(kind..'-old-invalid-coin');item.coin_batch=index
     end
     if kind=='artifact_lost'or kind=='artifact_transformed'then
      local text=capture('coin-'..kind);assert(text==capture('coin-'..kind..'-warm'))
      results[#results+1]={case=kind,text=text}
     end
    end,debug.traceback)
    form.event=event.id;item.coin_batch=index
    if #events>counts[1]+1 then events:erase(#events-1)end
    df.delete(dependency);assert(dependency_ok,dependency_error)
   end
   for _,variant in ipairs{'formed-plot','formed-retrieve','concluded-retrieve'}do
    local concluded=variant=='concluded-retrieve';local plot=variant=='formed-plot'
    local dependency=concluded and df.history_event_agreement_concludedst:new()or df.history_event_agreement_formedst:new()
    local agreement=df.agreement:new();local detail=df.agreement_details:new()
    local data=plot and df.agreement_details_data_plot_steal_artifact:new()or df.agreement_details_data_retrieve_artifact:new()
    local member=df.agreement_party:new();local party=df.agreement_party:new()
    local agreements=world.agreements.all;local agreement_count=#agreements
    local slot=plot and 'PlotStealArtifact'or 'RetrieveArtifact'
    local dependency_ok,dependency_error=xpcall(function()
     agreement.id=agreement_count>0 and agreements[agreement_count-1].id+1 or 0
     member.id=0;member.histfig_ids:insert('#',unit.hist_figure_id)
     party.id=1;party.entity_ids:insert('#',unit.civ_id)
     agreement.parties:insert('#',member);agreement.parties:insert('#',party)
     detail.id=0;detail.type=df.agreement_details_type[slot];detail.data[slot]=data
     if plot then
      data.actor_index=0;data.influencer_index=1;data.intermediary_index=-1;data.artifact_id=artifact.id
     else
      data.retrieving_party=0;data.requesting_party=1;data.artifact=artifact.id;data.artifact_site=-1;data.receiving_entity=-1
     end
     agreement.details:insert('#',detail);agreements:insert('#',agreement)
     dependency.id=events[#events-1].id+1;dependency.year=event.year;dependency.seconds=event.seconds;dependency.agreement_id=agreement.id
     if concluded then dependency.subject_id=-1;dependency.reason=-1;dependency.concluder_hf=-1 end
     events:insert('#',dependency);form.event=dependency.id
     if concluded then agreement.parties:resize(0)end
     local label='agreement-'..variant
     local text=capture('coin-'..label);assert(text==capture('coin-'..label..'-warm'))
     results[#results+1]={case=label,text=text}
     local extra={agreement,detail,data,member,party}
     item.coin_batch=-2;reject(label..'-invalid-coin',extra);item.coin_batch=index
     detail.data[slot]=nil;reject(label..'-null-payload',extra);detail.data[slot]=data
     agreement.details[0]=nil;reject(label..'-null-detail',extra);agreement.details[0]=detail
    end,debug.traceback)
    form.event=event.id;item.coin_batch=index
    if #events>counts[1]+1 then events:erase(#events-1)end
    while #agreements>agreement_count do agreements:erase(#agreements-1)end
    agreement.parties:resize(0);agreement.details:resize(0);detail.data[slot]=nil
    df.delete(dependency);df.delete(agreement);df.delete(detail);df.delete(data);df.delete(member);df.delete(party)
    assert(dependency_ok,dependency_error)
   end
   for _,kind in ipairs{'artifact_claim_formed','artifact_given','artifact_possessed','entity_dissolved','hf_gains_secret_goal','item_stolen'}do
    local dependency=df['history_event_'..kind..'st']:new()
    local dependency_ok,dependency_error=xpcall(function()
     dependency.id=events[#events-1].id+1;dependency.year=event.year;dependency.seconds=event.seconds
     if kind:sub(1,9)=='artifact_'then dependency.artifact=-1 end
     if kind=='artifact_given'then
      dependency.giver_hf=-1;dependency.giver_entity=-1;dependency.receiver_hf=-1;dependency.receiver_entity=-1
     end
     dependency.reason.type=-1
     events:insert('#',dependency);form.event=dependency.id
     for _,thought in ipairs{'AcquireArtifact','GaveArtifact'}do
      dependency.circumstance.type=df.unit_thought_type[thought];dependency.circumstance.data.Death=artifact.id
      item.coin_batch=-2;reject(kind..'-'..thought..'-invalid-coin');item.coin_batch=index
      if kind=='artifact_given'then
       local label='circumstance-'..thought
       local text=capture('coin-'..label);assert(text==capture('coin-'..label..'-warm'))
       results[#results+1]={case=label,text=text}
      end
     end
    end,debug.traceback)
    form.event=event.id;item.coin_batch=index
    if #events>counts[1]+1 then events:erase(#events-1)end
    df.delete(dependency);assert(dependency_ok,dependency_error)
   end
  end
 end,debug.traceback)
 form.event=original;raw.flags.CURRENCY_BY_YEAR=flag;issuer.entity_raw=raw
 while #events>counts[1]do events:erase(#events-1)end
 while #artifacts>counts[2]do artifacts:erase(#artifacts-1)end
 while #items>counts[3]do items:erase(#items-1)end
 while #batches>counts[4]do batches:erase(#batches-1)end
 artifact.item=nil;df.delete(event);df.delete(artifact);df.delete(item);df.delete(batch)
 assert(ok,err)
end
local f=assert(io.open(out..'/knowledge-coin-native.json','w'));f:write(json.encode(results));f:close()
local f=assert(io.open(out..'/knowledge-coin-validation.json','w'));f:write(json.encode(rejections));f:close()
return true
