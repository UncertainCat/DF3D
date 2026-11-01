-- Valid coin-caption branches only; never pass malformed native indices.
local unit,form_id,capture,out=...
local json=require('json');local form=assert(df.dance_form.find(form_id))
local world=df.global.world;local events=world.history.events;local artifacts=world.artifacts.all;local items=world.items.all;local batches=world.coin_batches.all
local issuer=assert(df.historical_entity.find(unit.civ_id));local raw=assert(issuer.entity_raw)
local flag=raw.flags.CURRENCY_BY_YEAR;local original=form.event
local counts={#events,#artifacts,#items,#batches};assert(#batches<32767)
local results={}
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
 end,debug.traceback)
 form.event=original;raw.flags.CURRENCY_BY_YEAR=flag
 while #events>counts[1]do events:erase(#events-1)end
 while #artifacts>counts[2]do artifacts:erase(#artifacts-1)end
 while #items>counts[3]do items:erase(#items-1)end
 while #batches>counts[4]do batches:erase(#batches-1)end
 artifact.item=nil;df.delete(event);df.delete(artifact);df.delete(item);df.delete(batch)
 assert(ok,err)
end
local f=assert(io.open(out..'/knowledge-coin-native.json','w'));f:write(json.encode(results));f:close()
return true
