-- Owned, paused read-only transport acceptance; native providers were independently
-- compared to DF widgets in the retained discovery lanes.
local out,probe,bytes=...
local script=require('gui.script');local json=require('json');local base=dfhack.internal.getImageBase()
local expected={lists=probe('justice-cases-probe'),details={}}
for _,list in ipairs(expected.lists)do for _,row in ipairs(list)do
 expected.details[tostring(row.id)]={summary=probe('justice-summary-probe',row.id),witnesses=probe('justice-witness-text-probe',row.id)}
end end
local guards={}
local function guard(object)local n,p=df.sizeof(object);guards[#guards+1]={n=n,p=p,value=bytes(p,n)}end
guard(df.global.game.main_interface.info.justice)
for _,crime in ipairs(df.global.world.crimes.all)do guard(crime);for _,report in ipairs(crime.witnesses)do guard(report)end end
local rng=bytes(base+0x234e990,0x6180)
local f=assert(io.open(out..'/justice-wire-reference.json','w'));f:write(json.encode(expected));f:close()
f=assert(io.open(out..'/shot.tmp','w'));f:write('justice-wire');f:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
local deadline=dfhack.getTickCount()+120000
while true do local ack=io.open(out..'/ack-justice-wire');if ack then ack:close();break end
 assert(dfhack.getTickCount()<deadline,'Justice wire timeout');script.sleep(1,'frames')
end
for _,g in ipairs(guards)do assert(bytes(g.p,g.n)==g.value,'Justice reads changed native state')end
assert(bytes(base+0x234e990,0x6180)==rng,'Justice reads changed randomness')
