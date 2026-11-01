-- Native art initialization is a semantic effect. Test in an owned clone only.
local unit,form_id,capture,out=...
local json=require('json');local form=assert(df.dance_form.find(form_id))
local events=df.global.world.history.events;local artifacts=df.global.world.artifacts.all;local items=df.global.world.items.all
local original=form.event;local counts={#events,#artifacts,#items};local results={}
for _,variant in ipairs{'statue','figurine','statue-bands','figurine-bands','statue-worldgen','figurine-worldgen'}do
for _,mode in ipairs{'native-first','probe-first'}do
 local label=variant..'-'..mode
 local item=variant:find('figurine',1,true) and df.item_figurinest:new() or df.item_statuest:new();local artifact=df.artifact_record:new();local event=df.history_event_artifact_createdst:new()
 local improvement,backing
 local object_data=df.global.world.world_data.object_data
 local object_count=#object_data
 local ok,err=xpcall(function()
  item.id=items[#items-1].id+1;item.mat_type=0;item.mat_index=0;item.quality=0;item.maker=-1;item.maker_race=unit.race
  item.world_data_id=-1;item.world_data_subid=-1;item.image.id=-1;item.image.subid=-1;item.image.civ_id=-1;item.image.site_id=-1
  if variant:find('worldgen',1,true)then
   backing=df.world_object_data:new();backing.id=object_count>0 and object_data[object_count-1].id+1 or 0
   object_data:insert('#',backing);item.world_data_id=backing.id;item.world_data_subid=37;item.flags.from_worldgen=true
  end
  if variant:find('bands',1,true)then
   improvement=df.itemimprovement_bandsst:new();improvement.mat_type=0;improvement.mat_index=0;improvement.quality=5;improvement.maker=-1
   item.improvements:insert('#',improvement);item.quality=5
  end
  artifact.id=artifacts[#artifacts-1].id+1;artifact.item=item;artifact.name.has_name=false
  event.id=events[#events-1].id+1;event.year=df.global.cur_year;event.seconds=df.global.cur_year_tick
  event.artifact_id=artifact.id;event.creator_unit_id=-1;event.creator_hfid=-1;event.entity=-1;event.site=-1
  items:insert('#',item);artifacts:insert('#',artifact);events:insert('#',event);form.event=event.id
  local before={id=df.global.world.worldgen.next_art_image_chunk_id,offset=df.global.world.worldgen.next_art_image_chunk_offset}
  local cold
  if mode=='probe-first'then
   local guards={}
   for _,object in ipairs{df.global.game.main_interface.view_sheets,df.global.plotinfo}do
    local size,address=df.sizeof(object);local bytes=df.new('uint8_t',size);dfhack.internal.memmove(bytes,address,size)
    guards[#guards+1]={size=size,address=address,bytes=bytes}
   end
   local text,status=dfhack.run_command_silent('df3d','dance-detail-probe',tostring(form.id));assert(status==0,text);cold=json.decode(text).text
   local unchanged=true
   for _,g in ipairs(guards)do if dfhack.internal.memcmp(g.bytes,g.address,g.size)~=0 then unchanged=false end;df.delete(g.bytes)end
   assert(unchanged,'Cold artifact formatter changed native UI')
   assert(item.image.id>=0 and item.image.subid>=0,'Independent Knowledge description did not initialize image')
  end
  local native=capture('artifact-'..label)
  assert(item.image.id>=0 and item.image.subid>=0,'Native Knowledge panel did not initialize image')
  if cold then assert(cold==native,'Cold Knowledge description differs from native')end
  local after={id=df.global.world.worldgen.next_art_image_chunk_id,offset=df.global.world.worldgen.next_art_image_chunk_offset}
  assert(after.id~=before.id or after.offset~=before.offset,'No art allocation observed')
  local warm=capture('artifact-'..label..'-warm');assert(warm==native,'Warm artifact text changed')
  assert(after.id==df.global.world.worldgen.next_art_image_chunk_id and after.offset==df.global.world.worldgen.next_art_image_chunk_offset,'Warm description allocated art')
  local worldgen
  if backing then
   assert(item.world_data_id==-1 and not item.flags.from_worldgen,'Worldgen item marker not retired')
   assert(df.world_object_data.find(backing.id)==backing,'Native removed world object record')
   assert(#backing.altered_items==1 and backing.altered_items[0]==37,'Native altered-item ledger differs')
   worldgen={record_id=backing.id,record_retained=true,altered_items={backing.altered_items[0]},world_data_id=item.world_data_id,world_data_subid=item.world_data_subid,from_worldgen=item.flags.from_worldgen}
  end
  local art=assert(df.art_image_chunk.find(item.image.id).images[item.image.subid].art_image)
  results[#results+1]={case=label,variant=variant,mode=mode,worldgen=worldgen,improvements=#item.improvements,quality=item.quality,before=before,after=after,image={id=item.image.id,subid=item.image.subid},elements=#art.elements,properties=#art.properties,has_source=art.ref~=nil,text=native}
 end,debug.traceback)
 form.event=original
 while #events>counts[1]do events:erase(#events-1)end
 while #artifacts>counts[2]do artifacts:erase(#artifacts-1)end
 while #items>counts[3]do items:erase(#items-1)end
 while #object_data>object_count do object_data:erase(#object_data-1)end
 if backing then df.delete(backing)end
 artifact.item=nil;item.improvements:resize(0);if improvement then df.delete(improvement)end
 df.delete(event);df.delete(artifact);df.delete(item)
 assert(ok,err)
end
end
local f=assert(io.open(out..'/knowledge-artifact-native.json','w'));f:write(json.encode(results));f:close()
return true
