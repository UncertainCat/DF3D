-- Owned, paused read-only transport acceptance; native providers were independently
-- compared to DF widgets in the retained discovery lanes.
local out,probe,bytes=...
local script=require('gui.script');local json=require('json');local base=dfhack.internal.getImageBase()
local expected={lists=probe('justice-cases-probe'),details={}}
expected.intelligence=probe('justice-intelligence-reports-probe',112)
expected.guard=probe('justice-guard-probe')
expected.convicts=probe('justice-convicts-probe')
for _,row in ipairs(expected.convicts)do row.name_color=probe('zone-owner-name-color-read',tostring(row.unit_id))end
expected.interrogation=probe('justice-interrogation-candidates-probe',{'9',''})
expected.candidates={}
for _,query in ipairs{'','dvn','zznomatch'}do
 expected.candidates[#expected.candidates+1]={query=query,rows=probe('justice-conviction-candidates-probe',{'9',query})}
end
-- Representative verified native sort scopes, including repeated priorities.
expected.sorts={}
for _,spec in ipairs{'1:1','0:0','0:1','2:0','2:1','3:0','3:1','1:1,3:0','1:1,3:0,1:1'}do
 local sorts={}
 for column,reverse in spec:gmatch('(%d):(%d)')do sorts[#sorts+1]={column=tonumber(column),reverse=reverse=='1'}end
 expected.sorts[#expected.sorts+1]={sorts=sorts,rows=probe('justice-conviction-candidates-probe',{'9','',spec})}
end
expected.presentation={}
for i=1,math.min(13,#expected.candidates[1].rows)do
 local id=expected.candidates[1].rows[i].unit_id
 expected.presentation[tostring(id)]=probe('justice-candidate-presentation-probe',{'9',tostring(id),'28'})
end
local mutating=os.getenv('DF3D_JUSTICE_WIRE_CONVICT')=='1'
local interrogating=os.getenv('DF3D_JUSTICE_WIRE_INTERROGATE')=='1'
local initial_reports=#df.crime.find(9).reports
local history_count=#df.global.world.history.events
for _,list in ipairs(expected.lists)do for _,row in ipairs(list)do
 expected.details[tostring(row.id)]={summary=probe('justice-summary-probe',row.id),witnesses=probe('justice-witness-text-probe',row.id)}
end end
local guards={}
local function guard(object)local n,p=df.sizeof(object);guards[#guards+1]={n=n,p=p,value=bytes(p,n)}end
if not mutating then guard(df.global.game.main_interface.info.justice)end
for _,crime in ipairs(df.global.world.crimes.all)do
 if interrogating and crime.id==9 then
  -- Add/cancel may retain vector capacity. Guard every other crime byte and
  -- all existing report objects; require the original count after cancellation.
  local n,p=df.sizeof(crime)
  guards[#guards+1]={n=0xc8,p=p,value=bytes(p,0xc8)}
  guards[#guards+1]={n=n-0xe0,p=p+0xe0,value=bytes(p+0xe0,n-0xe0)}
  for _,report in ipairs(crime.reports)do guard(report)end
 elseif not mutating or crime.id~=9 then guard(crime)end
 for _,report in ipairs(crime.witnesses)do guard(report)end
end
local rng=bytes(base+0x234e990,0x6180)
local f=assert(io.open(out..'/justice-wire-reference.json','w'));f:write(json.encode(expected));f:close()
f=assert(io.open(out..'/shot.tmp','w'));f:write('justice-wire');f:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
local deadline=dfhack.getTickCount()+120000
while true do local ack=io.open(out..'/ack-justice-wire');if ack then ack:close();break end
 assert(dfhack.getTickCount()<deadline,'Justice wire timeout');script.sleep(1,'frames')
end
for _,g in ipairs(guards)do assert(bytes(g.p,g.n)==g.value,'Justice reads changed native state')end
if not mutating then assert(bytes(base+0x234e990,0x6180)==rng,'Justice reads changed randomness')
else
 assert(df.crime.find(9).accused==5698,'Wire conviction did not apply')
 assert(#df.global.world.history.events==history_count+1,'Wire conviction history count differs')
 local event=df.global.world.history.events[history_count]
 assert(df.history_event_hf_convictedst:is_instance(event) and event.convicted_hf==9317 and event.convicter_entity==865,
  'Wire conviction history identity differs')
 assert(df.crime.find(9).accused_hf.historical_hfid==9317,'Wire conviction accused identity differs')
end

if interrogating then assert(#df.crime.find(9).reports==initial_reports,'Interrogation cancellation did not restore reports');assert(#df.global.world.history.events==history_count,'Interrogation changed history')end
