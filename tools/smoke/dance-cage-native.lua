-- Observe cold contained-unit caches on the disposable paused world.
local unit,form_id,capture,out=...
local json=require('json');local form=assert(df.dance_form.find(form_id))
local world=df.global.world;local events=world.history.events;local artifacts=world.artifacts.all;local items=world.items.all
local original=form.event;local counts={#events,#artifacts,#items};local results={}
local saved={flags2=unit.flags2.whole,flags3=unit.flags3.whole,glow=unit.cache.cached_glowtile_type}
local copies={}
for _,vector in ipairs{unit.body.components.body_part_status,unit.enemy.motor_nervenet,unit.enemy.sensory_nervenet,unit.enemy.body_part_useable}do
 local _,address=df.sizeof(vector);local first=df.reinterpret_cast('uint64_t',address).value
 local last=df.reinterpret_cast('uint64_t',address+8).value;local size=last-first
 if size>0 then
  local bytes=df.new('uint8_t',size);dfhack.internal.memmove(bytes,first,size)
  copies[#copies+1]={header=address,address=first,size=size,bytes=bytes}
 end
end
local function restore()
 unit.flags2.whole=saved.flags2;unit.flags3.whole=saved.flags3;unit.cache.cached_glowtile_type=saved.glow
 for _,v in ipairs(copies)do
  assert(df.reinterpret_cast('uint64_t',v.header).value==v.address and df.reinterpret_cast('uint64_t',v.header+8).value==v.address+v.size,'Cache refresh replaced vector storage')
  dfhack.internal.memmove(v.address,v.bytes,v.size)
 end
end
local item=df.item_cagest:new();local artifact=df.artifact_record:new();local event=df.history_event_artifact_createdst:new();local ref=df.general_ref_contains_unitst:new()
local function snapshot()
 local ranges={}
 local function add(label,address,size)
  if size==0 then return end
  local bytes=df.new('uint8_t',size);dfhack.internal.memmove(bytes,address,size)
  ranges[#ranges+1]={label=label,address=address,size=size,bytes=bytes}
 end
 for _,entry in ipairs{{'unit',unit},{'reference',ref},{'item',item}}do
  local size,address=df.sizeof(entry[2]);add(entry[1],address,size)
 end
 for index,v in ipairs(copies)do add('body-vector-'..index,v.address,v.size)end
 local base=dfhack.internal.getImageBase()
 for index,range in ipairs{{0x234e990,0x6180},{0x2131b30,40},{0x2159084,2},{0x18adf98,8}}do add('random-'..index,base+range[1],range[2])end
 return ranges
end
local function differences(ranges)
 local result={}
 for _,range in ipairs(ranges)do
  local changes={}
  for index=0,range.size-1 do
   local before=range.bytes[index];local after=df.reinterpret_cast('uint8_t',range.address+index).value
   if before~=after then changes[#changes+1]={index,before,after}end
  end
  result[#result+1]={range=range.label,changes=changes}
  df.delete(range.bytes)
 end
 return result
end
local ok,err=xpcall(function()
 item.id=items[#items-1].id+1;item.mat_type=0;item.mat_index=0;item.quality=0;item.maker=-1;item.maker_race=unit.race;item.world_data_id=-1;item.world_data_subid=-1
 ref.unit_id=unit.id;ref.cached_index=-1;item.general_refs:insert('#',ref)
 artifact.id=artifacts[#artifacts-1].id+1;artifact.item=item;artifact.name.has_name=false
 event.id=events[#events-1].id+1;event.year=df.global.cur_year;event.seconds=df.global.cur_year_tick
 event.artifact_id=artifact.id;event.creator_unit_id=-1;event.creator_hfid=-1;event.entity=-1;event.site=-1
 items:insert('#',item);artifacts:insert('#',artifact);events:insert('#',event);form.event=event.id
 for _,mode in ipairs{'native-first','probe-first'}do
  restore();unit.flags2.calculated_nerves=false;unit.flags2.calculated_bodyparts=false;ref.cached_index=-1
  local cold,cold_state,effects
  local before=snapshot()
  if mode=='probe-first'then
   local text,status=dfhack.run_command_silent('df3d','dance-detail-probe',tostring(form.id));assert(status==0,text);cold=json.decode(text).text
   cold_state={calculated_nerves=unit.flags2.calculated_nerves,calculated_bodyparts=unit.flags2.calculated_bodyparts,cached_index=ref.cached_index}
   assert(cold_state.calculated_nerves and cold_state.calculated_bodyparts and cold_state.cached_index>=0,'Cold cage probe did not refresh expected caches')
   effects=differences(before)
  end
  local text=capture('cage-'..mode)
  if not effects then effects=differences(before)end
  if cold then assert(cold==text,'Cold cage caption differs from native')end
  assert(text==capture('cage-'..mode..'-warm'),'Repeated cage description differs')
  results[#results+1]={case=mode,text=text,cold_probe_state=cold_state,effects=effects,calculated_nerves=unit.flags2.calculated_nerves,calculated_bodyparts=unit.flags2.calculated_bodyparts,cached_index=ref.cached_index}
 end
 assert(results[1].text==results[2].text,'Native-first and probe-first cage captions differ')
 assert(json.encode(results[1].effects)==json.encode(results[2].effects),'Native and diagnostic cold cage effects differ')
 for _,effect in ipairs(results[2].effects)do
  if effect.range:find('random-',1,true)==1 then assert(#effect.changes==0,'Cage caption changed random state')end
 end
end,debug.traceback)
form.event=original;restore();for _,v in ipairs(copies)do df.delete(v.bytes)end
while #events>counts[1]do events:erase(#events-1)end
while #artifacts>counts[2]do artifacts:erase(#artifacts-1)end
while #items>counts[3]do items:erase(#items-1)end
artifact.item=nil;item.general_refs:resize(0);df.delete(ref);df.delete(event);df.delete(artifact);df.delete(item)
assert(ok,err)
local f=assert(io.open(out..'/knowledge-cage-native.json','w'));f:write(json.encode(results));f:close()
return true
