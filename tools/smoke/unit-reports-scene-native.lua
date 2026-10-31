-- Diagnostic reports in an owned paused clone, never product data or copy.
local unit,capture,out=...
local json=require('json')
local original={};for _,id in ipairs(unit.reports.log[0])do original[#original+1]=id end
local frame=df.global.world.frame_counter
local ids={}
local ok,err=xpcall(function()
 for i=1,22 do
  local flags=df.announcement_flags:new()
  local index=dfhack.gui.makeAnnouncement(df.announcement_type.COMBAT_STRIKE_DETAILS,flags,unit.pos,'Synthetic unit combat history row '..i,3,true)
  flags:delete()
  local report=assert(df.global.world.status.reports[index]);report.speaker_id=unit.id
  ids[#ids+1]=report.id;unit.reports.log[0]:insert('#',report.id)
 end
 local file=assert(io.open(out..'/unit-reports-scene-expected.json','w'))
 file:write(json.encode({unit_id=unit.id,report_ids=ids,position={unit.pos.x,unit.pos.y,unit.pos.z}}));file:close()
 capture('farm-item-carrier-unit-scene')
 assert(df.global.pause_state and df.global.world.frame_counter==frame,'reports scene advanced simulation')
end,debug.traceback)
unit.reports.log[0]:resize(0);for _,id in ipairs(original)do unit.reports.log[0]:insert('#',id)end
local result={success=ok,unit_id=unit.id,report_ids=ids,restored_log=true,error=not ok and err or nil}
local file=assert(io.open(out..'/unit-reports-scene-native.json','w'));file:write(json.encode(result));file:close()
assert(ok,err);return result
