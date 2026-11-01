-- Temporary reference graphs; never render cyclic inputs with native DF.
local unit,id,capture,out=...
local json=require('json');local content=assert(df.written_content.find(id))
local events=df.global.world.history.events;local count=#events
local refs,aux={},{};for _,ref in ipairs(content.refs)do refs[#refs+1]=ref end
for _,value in ipairs(content.ref_aux)do aux[#aux+1]=value end
local ref=df.general_ref_historical_eventst:new()
local first=df.history_event_masterpiece_lostst:new();local second=df.history_event_masterpiece_lostst:new()
local results={}
local ok,err=xpcall(function()
 local leaf
 for _,event in ipairs(events)do if event:getType()==df.history_event_type.CREATED_SITE then leaf=event;break end end
 assert(leaf,'Missing written-event leaf')
 first.id=events[#events-1].id+1;second.id=first.id+1
 for _,event in ipairs{first,second}do
  event.year=leaf.year;event.seconds=leaf.seconds;event.histfig=-1;event.site=-1;event.method=0;event.creation_event=leaf.id
  events:insert('#',event)
 end
 content.refs:resize(0);content.ref_aux:resize(0);content.refs:insert('#',ref);content.ref_aux:insert('#',0)
 local function observe(label,event_id)
  ref.event_id=event_id
  local text=capture('written-event-'..label)
  assert(text==capture('written-event-'..label..'-warm'),'Repeated written event differs')
  results[#results+1]={case=label,text=text,native_comparisons=2}
 end
 observe('leaf',leaf.id);observe('lost',first.id)
 first.creation_event=second.id;observe('nested-lost',first.id)
 observe('missing',second.id+1)
 local function reject(label)
  local guards={}
  for _,value in ipairs{content,ref,first,second,unit,df.global.game.main_interface.view_sheets,df.global.plotinfo}do
   local size,address=df.sizeof(value);local bytes=df.new('uint8_t',size);dfhack.internal.memmove(bytes,address,size)
   guards[#guards+1]={bytes=bytes,address=address,size=size}
  end
  local text,status=dfhack.run_command_silent('df3d','written-detail-probe',tostring(id))
  local unchanged=true
  for _,guard in ipairs(guards)do
   if dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)~=0 then unchanged=false end
   df.delete(guard.bytes)
  end
  assert(status~=0,'Written cycle accepted: '..text);assert(unchanged,'Rejected written graph changed source/UI')
  results[#results+1]={case=label,rejected=true,guards_unchanged=true}
 end
 ref.event_id=first.id;first.creation_event=first.id;reject('self-cycle')
 first.creation_event=second.id;second.creation_event=first.id;reject('two-event-cycle')
end,debug.traceback)
content.refs:resize(0);content.ref_aux:resize(0)
for _,value in ipairs(refs)do content.refs:insert('#',value)end
for _,value in ipairs(aux)do content.ref_aux:insert('#',value)end
while #events>count do events:erase(#events-1)end
df.delete(ref);df.delete(first);df.delete(second);assert(ok,err)
local f=assert(io.open(out..'/knowledge-written-event-validation.json','w'));f:write(json.encode(results));f:close()
return true
