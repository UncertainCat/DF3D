-- Protected paused-clone diagnostic. Raw mutations never enter product code.
local out,view,click,shot,values,rows=...
local json=require('json')
assert(df.global.pause_state,'Automatic reaction discovery requires paused DF')
local reaction
for _,candidate in ipairs(df.global.world.raws.reactions.reactions)do
 if candidate.flags.AUTOMATIC then reaction=candidate;break end
end
assert(reaction,'No existing automatic reaction for controlled discovery')
local building=reaction.building;local lengths={}
for _,name in ipairs({'type','subtype','custom','hotkey'})do lengths[name]=#building[name]end
local original=values()
local function provider(...)
 local text,code=dfhack.run_command_silent('df3d','standing-workshops-probe',...)
 assert(code==0,'Workshop provider failed');return json.decode(text)
end
local result={reaction=reaction.code,before=provider(),cycles={}}
local ok,err=xpcall(function()
 for _,target in ipairs({{5,3},{5,1},{13,23}})do
  building.type:insert('#',target[1]);building.subtype:insert('#',target[2])
  building.custom:insert('#',-1);building.hotkey:insert('#',0)
 end
 -- Re-enter the native category so availability is independently recomputed.
 click(25,12);click(10,12)
 result.enabled=provider();result.rows=rows()
 for _,row in ipairs(result.enabled.settings)do assert(row.available,'Controlled automatic setting not available')end
 shot('standing-automation-enabled')
 for id=8,10 do
  local cycle={id=id,states={}};local key
  for attempt=1,2 do
   click(75,15+3*(id-8));local after=values()
   for name,value in pairs(after)do if value~=original[name]then assert(not key or key==name,'Unrelated native scalar changed');key=name end end
   cycle.states[#cycle.states+1]={values=after,rows=rows()}
  end
  assert(key and json.encode(values())==json.encode(original),'Native automation cycle did not restore')
  cycle.key=key
  for _,state in ipairs(cycle.states)do
   local before=df.global[key];local reply=provider(tostring(id),tostring(before),tostring(state.values[key]))
   assert(reply.outcome==2 and json.encode(values())==json.encode(state.values),'Automation adapter differs from native')
   local stale=provider(tostring(id),tostring(before),tostring(state.values[key]))
   assert(stale.outcome==1 and json.encode(values())==json.encode(state.values),'Stale automation edit changed state')
  end
  result.cycles[#result.cycles+1]=cycle
 end
 if os.getenv('DF3D_STANDING_AUTOMATION_WIRE')=='1' then
  local f=assert(io.open(out..'/standing-automation-native.json','w'));f:write(json.encode(result));f:close()
  local checked=0
  shot('standing-automation-wire',function()
   local step=io.open(out..'/automation-wire-step');if not step then return end
   local index=tonumber(step:read('*a'));step:close()
   if index and index>checked then
    assert(index==checked+1 and index<=6,'Unexpected automation wire step')
    local expected=result.cycles[(index-1)//2+1].states[(index-1)%2+1].values
    assert(json.encode(values())==json.encode(expected),'Automation wire changed unexpected scalar')
    checked=index;local ack=assert(io.open(out..'/automation-wire-ack','w'));ack:write(tostring(index));ack:close()
   end
  end)
  assert(checked==6 and json.encode(values())==json.encode(original),'Automation wire did not restore all settings')
  result.wire_steps=checked
 end
end,debug.traceback)
for name,length in pairs(lengths)do while #building[name]>length do building[name]:erase(#building[name]-1)end end
for name,value in pairs(original)do df.global[name]=value end
assert(ok,err)
click(25,12);click(10,12);result.restored=provider()
assert(json.encode(result.before)==json.encode(result.restored),'Raw availability did not restore')
assert(json.encode(values())==json.encode(original),'Automation scalars did not restore')
local f=assert(io.open(out..'/standing-automation-native.json','w'));f:write(json.encode(result));f:close()
