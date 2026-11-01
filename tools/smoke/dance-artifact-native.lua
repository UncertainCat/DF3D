-- Native art initialization is a semantic effect. Test in an owned clone only.
local unit,form_id,capture,out=...
local json=require('json');local form=assert(df.dance_form.find(form_id))
local events=df.global.world.history.events;local artifacts=df.global.world.artifacts.all;local items=df.global.world.items.all
local original=form.event;local counts={#events,#artifacts,#items};local results={}
for _,mode in ipairs{'native-first','probe-first'}do
 local item=df.item_statuest:new();local artifact=df.artifact_record:new();local event=df.history_event_artifact_createdst:new()
 local ok,err=xpcall(function()
  item.id=items[#items-1].id+1;item.mat_type=0;item.mat_index=0;item.quality=0;item.maker=-1;item.maker_race=unit.race
  item.world_data_id=-1;item.world_data_subid=-1;item.image.id=-1;item.image.subid=-1;item.image.civ_id=-1;item.image.site_id=-1
  artifact.id=artifacts[#artifacts-1].id+1;artifact.item=item;artifact.name.has_name=false
  event.id=events[#events-1].id+1;event.year=df.global.cur_year;event.seconds=df.global.cur_year_tick
  event.artifact_id=artifact.id;event.creator_unit_id=-1;event.creator_hfid=-1;event.entity=-1;event.site=-1
  items:insert('#',item);artifacts:insert('#',artifact);events:insert('#',event);form.event=event.id
  local before={id=df.global.world.worldgen.next_art_image_chunk_id,offset=df.global.world.worldgen.next_art_image_chunk_offset}
  local cold
  if mode=='probe-first'then
   local text,status=dfhack.run_command_silent('df3d','dance-detail-probe',tostring(form.id));assert(status==0,text);cold=json.decode(text).text
   assert(item.image.id>=0 and item.image.subid>=0,'Independent Knowledge description did not initialize image')
  end
  local native=capture('artifact-'..mode)
  assert(item.image.id>=0 and item.image.subid>=0,'Native Knowledge panel did not initialize image')
  if cold then assert(cold==native,'Cold Knowledge description differs from native')end
  local after={id=df.global.world.worldgen.next_art_image_chunk_id,offset=df.global.world.worldgen.next_art_image_chunk_offset}
  assert(after.id~=before.id or after.offset~=before.offset,'No art allocation observed')
  local warm=capture('artifact-'..mode..'-warm');assert(warm==native,'Warm artifact text changed')
  assert(after.id==df.global.world.worldgen.next_art_image_chunk_id and after.offset==df.global.world.worldgen.next_art_image_chunk_offset,'Warm description allocated art')
  local art=assert(df.art_image_chunk.find(item.image.id).images[item.image.subid].art_image)
  results[#results+1]={case=mode,before=before,after=after,image={id=item.image.id,subid=item.image.subid},elements=#art.elements,properties=#art.properties,has_source=art.ref~=nil,text=native}
 end,debug.traceback)
 form.event=original
 while #events>counts[1]do events:erase(#events-1)end
 while #artifacts>counts[2]do artifacts:erase(#artifacts-1)end
 while #items>counts[3]do items:erase(#items-1)end
 artifact.item=nil;df.delete(event);df.delete(artifact);df.delete(item)
 assert(ok,err)
end
local f=assert(io.open(out..'/knowledge-artifact-native.json','w'));f:write(json.encode(results));f:close()
return true
