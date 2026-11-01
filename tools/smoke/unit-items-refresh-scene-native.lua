-- Controlled live contents changes in an owned paused clone; no save is written.
local unit,capture,out=...
local json=require('json')
local parent,child=unit.inventory[0].item,unit.inventory[1].item
local count=#parent.general_refs;local flags,child_flags=parent.flags.whole,child.flags.whole
local frame=df.global.world.frame_counter
local ref=df.general_ref_contains_itemst:new();ref.item_id=child.id
local observations={}
local function restore()
 while #parent.general_refs>count do parent.general_refs:erase(#parent.general_refs-1)end
 parent.flags.whole=flags
end
local function service()
 local file=io.open(out..'/unit-items-refresh-request.json','r');if not file then return end
 local request=json.decode(file:read('*a'));file:close();assert(os.remove(out..'/unit-items-refresh-request.json'))
 assert(request.unit_id==unit.id and request.serial==#observations+1,'Invalid contents refresh request')
 assert(df.global.pause_state and df.global.world.frame_counter==frame,'Contents refresh advanced simulation')
 assert(request.op=='add' or request.op=='restore','Invalid contents operation')
 restore()
 if request.op=='add' then parent.flags.container=true;parent.general_refs:insert('#',ref)end
 local text,status=dfhack.run_command_silent('df3d','unit-items-description-probe',tostring(unit.id));assert(status==0,text)
 local result={serial=request.serial,op=request.op,native=json.decode(text)}
 observations[#observations+1]=result
 file=assert(io.open(out..'/unit-items-refresh-ack.tmp','w'));file:write(json.encode(result));file:close()
 assert(os.rename(out..'/unit-items-refresh-ack.tmp',out..'/unit-items-refresh-ack.json'))
end
local ok,err=xpcall(function()capture('farm-item-carrier-unit-scene',service)end,debug.traceback)
local restored=#observations==2 and observations[2].op=='restore'
local flags_ok=(parent.flags.whole==flags or parent.flags.whole==(flags|0x20000000)) and (child.flags.whole==child_flags or child.flags.whole==(child_flags|0x20000000))
restore();child.flags.whole=child_flags;df.delete(ref)
local result={success=ok and restored and flags_ok,restored=true,observations=observations,flags_unchanged_except_weight_cache=flags_ok}
local file=assert(io.open(out..'/unit-items-refresh-native.json','w'));file:write(json.encode(result));file:close()
assert(ok,err);assert(restored and flags_ok,'Contents refresh did not finish or altered flags');return result
