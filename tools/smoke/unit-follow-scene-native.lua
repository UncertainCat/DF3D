-- Paused, owned-fixture mutations serviced while the composed viewer runs.
-- This file is diagnostic only and restores every changed field on failure.
local unit,capture,out=...
local json=require('json')
local original={x=unit.pos.x,y=unit.pos.y,z=unit.pos.z,flags=unit.flags1.whole}
local block=assert(dfhack.maps.getTileBlock(unit.pos))
local designation=block.designation[unit.pos.x%16][unit.pos.y%16]
local original_designation=designation.whole
local frame=df.global.world.frame_counter
local observations={}
local function service()
 local file=io.open(out..'/unit-follow-request.json','r');if not file then return end
 local request=json.decode(file:read('*a'));file:close()
 assert(os.remove(out..'/unit-follow-request.json'))
 assert(request.unit_id==unit.id and df.global.pause_state and df.global.world.frame_counter==frame,'invalid follow fixture request')
 if request.op=='move' then unit.pos.x=original.x+1;unit.pos.y=original.y-1
 elseif request.op=='restore' then unit.pos.x=original.x;unit.pos.y=original.y;unit.pos.z=original.z
 elseif request.op=='inactive' then unit.flags1.inactive=true
 elseif request.op=='active' then unit.flags1.whole=original.flags
 elseif request.op=='hidden' then designation.hidden=true
 elseif request.op=='visible' then designation.whole=original_designation
 else error('unknown follow fixture operation')end
 local text,status=dfhack.run_command_silent('df3d','unit-follow-position-probe',tostring(unit.id));assert(status==0,text)
 local result={serial=request.serial,op=request.op,position=json.decode(text)}
 observations[#observations+1]=result
 file=assert(io.open(out..'/unit-follow-ack.tmp','w'));file:write(json.encode(result));file:close()
 assert(os.rename(out..'/unit-follow-ack.tmp',out..'/unit-follow-ack.json'))
end
local ok,err=xpcall(function()capture('farm-item-carrier-unit-scene',service)end,debug.traceback)
local restored=unit.pos.x==original.x and unit.pos.y==original.y and unit.pos.z==original.z and
 unit.flags1.whole==original.flags and designation.whole==original_designation
unit.pos.x=original.x;unit.pos.y=original.y;unit.pos.z=original.z;unit.flags1.whole=original.flags
designation.whole=original_designation
local result={success=ok and restored,restored=restored,observations=observations}
local file=assert(io.open(out..'/unit-follow-motion-native.json','w'));file:write(json.encode(result));file:close()
assert(ok,err);assert(restored,'viewer did not request complete follow fixture restoration')
return result
