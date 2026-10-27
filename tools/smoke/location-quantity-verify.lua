-- Owned paused clone diagnostics: independent scalar readback and stale seeding.
local out,index=...
local json=require('json')
local f=assert(io.open(out..'/request-'..index..'.json'));local request=json.decode(f:read('*a'));f:close()
assert(df.global.pause_state and df.global.world.frame_counter==0,'paused clone required')
local site=assert(dfhack.world.getCurrentSite());local result={status='passed'}
local names={'goblets','instruments','paper','splints','thread','cloth','crutches','powder','buckets','soap','copies'}
if request.op=='quantity_locations' then
 result.locations={}
 for _,location in ipairs(site.buildings)do
  result.locations[#result.locations+1]={site_id=site.id,id=location.id}
 end
else
 local location
 for _,v in ipairs(site.buildings)do if v.id==request.location_id then location=v;break end end
 local contents=assert(location):getContents();assert(contents)
 local name=assert(names[request.quantity_id+1]);local key='desired_'..name
 if request.op=='quantity_seed' then contents[key]=request.value
 elseif request.op=='quantity_check' then assert(contents[key]==request.value,'quantity readback mismatch')
 else error('unexpected quantity operation')end
 result.value=contents[key]
end
f=assert(io.open(out..'/response-'..index..'.json','w'));f:write(json.encode(result));f:close()
print('SEMANTIC_PASS '..index..' '..request.op)
