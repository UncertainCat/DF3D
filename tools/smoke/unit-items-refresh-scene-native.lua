-- Controlled live contents changes in an owned paused clone; no save is written.
local unit,capture,out=...
local json=require('json')
local parent,child=unit.inventory[0].item,unit.inventory[1].item
local count=#parent.general_refs;local flags,child_flags=parent.flags.whole,child.flags.whole
local frame=df.global.world.frame_counter
local ref=df.general_ref_contains_itemst:new();ref.item_id=child.id
local observations={}
local assigned=df.global.plotinfo.equipment.items_assigned[parent:getType()]
local work=df.global.plotinfo.equipment.work_weapons
local function copy(v)local r={};for _,x in ipairs(v)do r[#r+1]=x end;return r end
local old_assigned,old_work=copy(assigned),copy(work)
local function replace(v,rows)v:resize(0);for _,x in ipairs(rows)do v:insert('#',x)end end
local function membership(v,present)
 local rows={};for _,id in ipairs(v)do if id~=parent.id then rows[#rows+1]=id end end
 if present then rows[#rows+1]=parent.id end;table.sort(rows);replace(v,rows)
end
local function restore()
 while #parent.general_refs>count do parent.general_refs:erase(#parent.general_refs-1)end
 parent.flags.whole=flags
 replace(assigned,old_assigned);replace(work,old_work)
end
local function service()
 local file=io.open(out..'/unit-items-refresh-request.json','r');if not file then return end
 local request=json.decode(file:read('*a'));file:close();assert(os.remove(out..'/unit-items-refresh-request.json'))
 assert(request.unit_id==unit.id and request.serial==#observations+1,'Invalid contents refresh request')
 assert(df.global.pause_state and df.global.world.frame_counter==frame,'Contents refresh advanced simulation')
 assert(request.op=='add' or request.op=='restore' or request.op=='squad' or request.op=='tool','Invalid contents operation')
 restore()
 if request.op=='add' then parent.flags.container=true;parent.general_refs:insert('#',ref)end
 if request.op=='squad' or request.op=='tool' then membership(assigned,request.op=='squad');membership(work,request.op=='tool')end
 local text,status=dfhack.run_command_silent('df3d','unit-items-description-probe',tostring(unit.id));assert(status==0,text)
 local result={serial=request.serial,op=request.op,native=json.decode(text)}
 observations[#observations+1]=result
 file=assert(io.open(out..'/unit-items-refresh-ack.tmp','w'));file:write(json.encode(result));file:close()
 assert(os.rename(out..'/unit-items-refresh-ack.tmp',out..'/unit-items-refresh-ack.json'))
end
local ok,err=xpcall(function()capture('farm-item-carrier-unit-scene',service)end,debug.traceback)
local expected_count=os.getenv('DF3D_UNIT_ITEMS_ASSIGNMENT_REFRESH')=='1' and 5 or 2
local restored=#observations==expected_count and observations[#observations].op=='restore'
local flags_ok=(parent.flags.whole==flags or parent.flags.whole==(flags|0x20000000)) and (child.flags.whole==child_flags or child.flags.whole==(child_flags|0x20000000))
restore();child.flags.whole=child_flags;df.delete(ref)
local result={success=ok and restored and flags_ok,restored=true,observations=observations,flags_unchanged_except_weight_cache=flags_ok}
local file=assert(io.open(out..'/unit-items-refresh-native.json','w'));file:write(json.encode(result));file:close()
assert(ok,err);assert(restored and flags_ok,'Contents refresh did not finish or altered flags');return result
