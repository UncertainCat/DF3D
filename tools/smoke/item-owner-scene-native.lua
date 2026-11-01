-- Owned paused-clone reference changes while the real main scene remains open.
local unit,capture,out=...
local json=require('json')
local item=assert(unit.inventory[0].item);local refs={}
for _,ref in ipairs(item.general_refs)do refs[#refs+1]=ref end
local other
for _,candidate in ipairs(df.global.world.units.active)do
 if candidate.id~=unit.id and dfhack.units.isCitizen(candidate)then other=candidate;break end
end
assert(other,'Owner refresh fixture requires another citizen')
local temp=df.general_ref_unit_itemownerst:new()
local frame=df.global.world.frame_counter;local flags=item.flags.whole
local observations={};local last='initial'
local function restore()
 item.general_refs:resize(0);for _,ref in ipairs(refs)do item.general_refs:insert('#',ref)end
end
local function service()
 local file=io.open(out..'/item-owner-request.json','r');if not file then return end
 local request=json.decode(file:read('*a'));file:close();assert(os.remove(out..'/item-owner-request.json'))
 assert(request.item_id==item.id and request.serial==#observations+1,'Invalid owner refresh request')
 assert(df.global.pause_state and df.global.world.frame_counter==frame,'Owner refresh advanced simulation')
 restore()
 if request.op~='restore'then
  assert(request.op=='other'or request.op=='none'or request.op=='unresolved','Unknown owner refresh operation')
  for i=#item.general_refs-1,0,-1 do if item.general_refs[i]:getType()==df.general_ref_type.UNIT_ITEMOWNER then item.general_refs:erase(i)end end
  if request.op~='none'then temp.unit_id=request.op=='other'and other.id or 2147483647;temp.cached_index=-1;item.general_refs:insert('#',temp)end
 end
 local text,status=dfhack.run_command_silent('df3d','item-owner-probe',tostring(item.id));assert(status==0,text)
 local snapshot_text,snapshot_status=dfhack.run_command_silent('df3d','item-inspect-probe',tostring(item.id));assert(snapshot_status==0,snapshot_text)
 local snapshot=json.decode(snapshot_text).snapshot
 assert(snapshot.carrier.kind==2 and snapshot.carrier.id==unit.id,'Owner change altered carrier')
 local result={serial=request.serial,op=request.op,owner=json.decode(text),revision=snapshot.revision,carrier_id=unit.id}
 observations[#observations+1]=result;last=request.op
 file=assert(io.open(out..'/item-owner-ack.tmp','w'));file:write(json.encode(result));file:close()
 assert(os.rename(out..'/item-owner-ack.tmp',out..'/item-owner-ack.json'))
end
local ok,err=xpcall(function()capture('farm-item-carrier-unit-scene',service)end,debug.traceback)
local restored=last=='restore';restore();df.delete(temp)
local flags_ok=item.flags.whole==flags or item.flags.whole==(flags|0x20000000)
local result={success=ok and restored and flags_ok,restored=restored,flags_unchanged_except_weight_cache=flags_ok,observations=observations}
local file=assert(io.open(out..'/item-owner-refresh-native.json','w'));file:write(json.encode(result));file:close()
assert(ok,err);assert(restored and flags_ok,'Owner refresh fixture did not restore references or changed flags')
return result
