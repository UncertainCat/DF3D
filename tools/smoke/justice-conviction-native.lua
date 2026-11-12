-- Owned paused clone only. Conviction is deliberately not rolled back: history
-- and thoughts are simulation effects. The lane must close DF without saving.
local out,view,settle,tab,capture=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local crime=assert(df.crime.find(9));local unit=assert(df.unit.find(5698))
assert(crime.accused==-1,'Conviction reference requires an unresolved case')
local function click(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=y//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1;settle()
end
local function identity(r)
 local ids={};for _,id in ipairs(r.all_witnessed_ident)do ids[#ids+1]=id end
 return {hfid=r.hfid,visual_hfid=r.visual_hfid,historical_hfid=r.historical_hfid,identities=ids}
end
local function emotions()
 local result={}
 for _,u in ipairs(df.global.world.units.all)do
  if u.status.current_soul then
   local rows={}
   for _,e in ipairs(u.status.current_soul.personality.emotions)do
    rows[#rows+1]={type=e.type,thought=e.thought,subthought=e.subthought,strength=e.strength,
     relative_strength=e.relative_strength,severity=e.severity,flags=e.flags.whole,
     next_overcome_timer=e.next_overcome_timer,year=e.year,year_tick=e.year_tick}
   end
   result[tostring(u.id)]=rows
  end
 end
 return result
end
local function state()
 local base=dfhack.internal.getImageBase()
 return {accused=crime.accused,accused_hf=identity(crime.accused_hf),flags=crime.flags.whole,
  hammerstrikes=crime.punishment.hammerstrikes,prison_time=crime.punishment.prison_time,
  punishment_flags=crime.punishment.flags.whole,history_count=#df.global.world.history.events,
  counters={df.reinterpret_cast('int32_t',base+0x2393410).value,df.reinterpret_cast('int32_t',base+0x2393440).value}}
end
tab('Open cases');click(100,202);click(100,166);click(652,190)
local before=state();local before_emotions=emotions()
capture('justice-conviction-before')
local provider=os.getenv('DF3D_JUSTICE_CONVICTION_PROVIDER')=='1'
if provider then
 -- The native effect legitimately sets Justice.do_init, so do not use the
 -- read-only probe's unchanged-menu guard or restore the notification.
 local text,rc=dfhack.run_command_silent('df3d','justice-conviction-probe','9','5698','-1')
 assert(rc==0 and json.decode(text)==2,'Native conviction effect adapter failed')
else click(600,190)end
local result={crime_id=crime.id,unit_id=unit.id,provider=provider,before=before,after=state(),changed_emotions={},new_events={}}
local after_emotions=emotions()
for id,rows in pairs(after_emotions)do
 if json.encode(rows)~=json.encode(before_emotions[id])then
  result.changed_emotions[#result.changed_emotions+1]={unit_id=tonumber(id),before=before_emotions[id],after=rows}
 end
end
table.sort(result.changed_emotions,function(a,b)return a.unit_id<b.unit_id end)
if provider then
 local text,rc=dfhack.run_command_silent('df3d','justice-conviction-probe','9','5698','-1')
 assert(rc==0 and json.decode(text)==1,'Stale repeated conviction was not rejected')
 assert(json.encode(state())==json.encode(result.after) and json.encode(emotions())==json.encode(after_emotions),
  'Rejected conviction changed simulation effects')
 result.stale_repeat_rejected=true
end
for i=before.history_count,#df.global.world.history.events-1 do
 local e=df.global.world.history.events[i]
 local row={id=e.id,type=e:getType(),year=e.year,seconds=e.seconds}
 if df.history_event_hf_convictedst:is_instance(e)then
  row.convicted_hf=e.convicted_hf;row.convicter_entity=e.convicter_entity;row.crime=e.crime
  row.hammerstrikes=e.punishment.hammerstrikes;row.prison_time=e.punishment.prison_time
  row.punishment_flags=e.punishment.flags.whole;row.plot_flags=e.plot_flags.whole
 end
 result.new_events[#result.new_events+1]=row
end
local f=assert(io.open(out..'/justice-conviction.json','w'));f:write(json.encode(result));f:close()
capture('justice-conviction-after')
assert(crime.accused==unit.id,'Native first-row click did not convict expected unit')
assert(#result.new_events==1,'Native conviction did not create one history event')
