-- Temporary competition reached through the native event circumstance phrase.
local unit,form_id,capture,out=...
local json=require('json');local world=df.global.world
local form=assert(df.dance_form.find(form_id));local owner=assert(df.historical_entity.find(unit.civ_id))
local events=world.history.events;local collections=world.history.event_collections.all
local counts={#events,#collections};local original_event,original_info=form.event,owner.occasion_info
local event=df.history_event_artifact_givenst:new();local collection=df.history_event_collection_competitionst:new()
local info=df.entity_occasion_info:new();local occasion=df.entity_occasion:new();local schedule=df.entity_occasion_schedule:new()
local results,rejections={},{}
local ok,err=xpcall(function()
 collection.id=#collections>0 and collections[#collections-1].id+1 or 0
 collection.parent_collection=-1;collection.civ=owner.id;collection.occasion=0;collection.schedule=0;collection.ordinal=1
 occasion.id=0;occasion.site=-1;occasion.structure=-1;occasion.name:assign(owner.name)
 schedule.type=df.occasion_schedule_type.FOOT_RACE
 occasion.schedule:insert('#',schedule);info.occasions:insert('#',occasion);owner.occasion_info=info
 collections:insert('#',collection)
 event.id=events[#events-1].id+1;event.year=df.global.cur_year;event.seconds=df.global.cur_year_tick
 event.artifact=-1;event.giver_hf=-1;event.giver_entity=-1;event.receiver_hf=-1;event.receiver_entity=-1;event.reason.type=-1
 event.circumstance.type=df.unit_thought_type.HistEventCollection;event.circumstance.data.HistEventCollection=collection.id
 events:insert('#',event);form.event=event.id
 local function compare(label)
  local text=capture('collection-'..label);assert(text==capture('collection-'..label..'-warm'))
  results[#results+1]={case=label,text=text}
 end
 compare('foot-race');collection.ordinal=2;compare('second-foot-race');collection.ordinal=1
 event.circumstance.data.HistEventCollection=2147483647;assert(not df.history_event_collection.find(2147483647));compare('missing-collection');event.circumstance.data.HistEventCollection=collection.id
 collection.civ=2147483647;assert(not df.historical_entity.find(2147483647));compare('missing-entity');collection.civ=owner.id
 owner.occasion_info=nil;compare('missing-info');owner.occasion_info=info
 collection.occasion=2147483647;compare('missing-occasion');collection.occasion=0
 occasion.schedule[0]=nil;compare('null-schedule');occasion.schedule[0]=schedule
 local function reject(label)
  local guards={}
  for _,value in ipairs{form,event,collection,owner,info,occasion,schedule,unit,df.global.game.main_interface.view_sheets,df.global.plotinfo}do
   local size,address=df.sizeof(value);local bytes=df.new('uint8_t',size);dfhack.internal.memmove(bytes,address,size)
   guards[#guards+1]={bytes=bytes,address=address,size=size}
  end
  local text,status=dfhack.run_command_silent('df3d','dance-detail-probe',tostring(form.id))
  local unchanged=true
  for _,guard in ipairs(guards)do
   if dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)~=0 then unchanged=false end
   df.delete(guard.bytes)
  end
  assert(status~=0,'Invalid collection accepted: '..label..' '..text);assert(unchanged,'Rejected collection changed source/UI')
  rejections[#rejections+1]={case=label,rejected=true,guards_unchanged=true}
 end
 collection.schedule=-1;reject('minus-one-schedule')
 collection.schedule=-2;reject('negative-schedule')
 collection.schedule=1;reject('past-end-schedule');collection.schedule=0
 occasion.schedule:resize(0);reject('empty-schedule');occasion.schedule:insert('#',schedule)
 info.occasions[0]=nil;reject('null-occasion');info.occasions[0]=occasion
end,debug.traceback)
form.event=original_event;owner.occasion_info=original_info
while #events>counts[1]do events:erase(#events-1)end
while #collections>counts[2]do collections:erase(#collections-1)end
info.occasions:resize(0);occasion.schedule:resize(0)
df.delete(event);df.delete(collection);df.delete(info);df.delete(occasion);df.delete(schedule)
assert(ok,err)
local f=assert(io.open(out..'/knowledge-collection-native.json','w'));f:write(json.encode(results));f:close()
local f=assert(io.open(out..'/knowledge-collection-validation.json','w'));f:write(json.encode(rejections));f:close()
return true
