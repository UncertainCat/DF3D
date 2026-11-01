-- Controlled recursive references in an owned, paused clone; always restored.
-- Synthetic events establish formatter coverage, not natural-world occurrence.
local form_id,capture=...
local form=assert(df.dance_form.find(form_id))
local leaf
for _,value in ipairs(df.global.world.history.events)do
 if value:getType()==df.history_event_type.CREATED_SITE then leaf=value;break end
end
assert(leaf,'Missing leaf event test source')
local owner=assert(df.global.world.entities.all[0])
local events=df.global.world.history.events
local count=#events;local last=events[count-1].id
local lost=df.history_event_masterpiece_lostst:new()
local performance=df.history_event_performancest:new()
local info=df.entity_occasion_info:new()
local occasion=df.entity_occasion:new()
local schedule=df.entity_occasion_schedule:new()
local original_event,original_info=form.event,owner.occasion_info
local ok,err=xpcall(function()
 lost.id=last+1;lost.year=leaf.year;lost.seconds=leaf.seconds;lost.creation_event=leaf.id;lost.histfig=-1;lost.site=leaf.site;lost.method=0
 performance.id=last+2;performance.year=leaf.year;performance.seconds=leaf.seconds
 performance.entity=owner.id;performance.occasion=0;performance.schedule=0;performance.site=-1;performance.region=-1;performance.layer=-1
 occasion.id=0;occasion.site=-1;occasion.structure=-1
 schedule.type=3;schedule.reference=leaf.id
 occasion.schedule:insert('#',schedule);info.occasions:insert('#',occasion);owner.occasion_info=info
 events:insert('#',lost);events:insert('#',performance)
 form.event=lost.id;capture('lost-existing-event')
 lost.creation_event=2147483647;capture('lost-missing-event')
 lost.creation_event=leaf.id;form.event=performance.id;capture('performance-existing-event')
 schedule.reference=2147483647;capture('performance-missing-event')
 schedule.reference=lost.id;capture('performance-nested-lost-event')
 performance.entity=2147483647;capture('performance-missing-entity');performance.entity=owner.id
 performance.occasion=2147483647;capture('performance-missing-occasion');performance.occasion=0
 performance.schedule=2147483647;capture('performance-missing-schedule')
end,debug.traceback)
form.event=original_event;owner.occasion_info=original_info
while #events>count do events:erase(#events-1)end
occasion.schedule:resize(0);info.occasions:resize(0)
df.delete(schedule);df.delete(occasion);df.delete(info);df.delete(performance);df.delete(lost)
assert(ok,err)
return true
