-- Controlled references for the actual viewer workflow in an owned unsaved clone.
local unit,capture,out=...
local json=require('json')
local parent,child=unit.inventory[0].item,unit.inventory[1].item
local count=#parent.general_refs;local flags,child_flags=parent.flags.whole,child.flags.whole
local frame=df.global.world.frame_counter
local item_ref=df.general_ref_contains_itemst:new();item_ref.item_id=child.id
local unit_ref=df.general_ref_contains_unitst:new();unit_ref.unit_id=unit.id
local missing=df.general_ref_contains_itemst:new();missing.item_id=2147483647
local ok,err=xpcall(function()
 parent.flags.container=true
 for _,ref in ipairs{item_ref,unit_ref,missing}do parent.general_refs:insert('#',ref)end
 local text,status=dfhack.run_command_silent('df3d','unit-items-description-probe',tostring(unit.id));assert(status==0,text)
 local file=assert(io.open(out..'/unit-items-wire-expected.json','w'));file:write(text);file:close()
 capture('farm-item-carrier-unit-scene')
 assert(df.global.pause_state and df.global.world.frame_counter==frame,'Contained scene advanced simulation')
 assert(parent.flags.whole==(flags|0x40) or parent.flags.whole==(flags|0x40|0x20000000),'Contained scene changed parent flags')
 assert(child.flags.whole==child_flags or child.flags.whole==(child_flags|0x20000000),'Contained scene changed child flags')
end,debug.traceback)
while #parent.general_refs>count do parent.general_refs:erase(#parent.general_refs-1)end
parent.flags.whole=flags;child.flags.whole=child_flags
for _,ref in ipairs{item_ref,unit_ref,missing}do df.delete(ref)end
local result={success=ok,restored=true,unit_id=unit.id,parent_id=parent.id,child_id=child.id,error=not ok and err or nil}
local file=assert(io.open(out..'/unit-items-contained-scene-native.json','w'));file:write(json.encode(result));file:close()
assert(ok,err);return result
