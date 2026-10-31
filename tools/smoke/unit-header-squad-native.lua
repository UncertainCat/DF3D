-- Paused disposable fixture. Replace one slot temporarily, never run an order.
local unit,view=...
local json=require('json')
local squad
for _,candidate in ipairs(df.global.world.squads.all)do if #candidate.positions>0 then squad=candidate;break end end
assert(squad,'squad activity fixture requires a squad')
local original=squad.positions[0]
local old_id,old_position,old_job=unit.military.squad_id,unit.military.squad_position,unit.job.current_job
local position=df.squad_position:new()
local order=df.squad_order_trainst:new()
position.occupant=unit.hist_figure_id;position.orders:insert('#',order)
local missing=2147483000
assert(not df.activity_entry.find(missing),'fixture activity ID must be absent')
local function seed()
 for i=0,2 do position.activities[i]=missing;position.events[i]=missing end
end
local function cleared()
 for i=0,2 do if position.activities[i]~=-1 or position.events[i]~=-1 then return false end end
 return true
end
local result
local ok,err=xpcall(function()
 squad.positions[0]=position;unit.military.squad_id=squad.id;unit.military.squad_position=0;unit.job.current_job=nil
 seed()
 local copies={}
 for _,object in ipairs{df.global.game.main_interface.view_sheets,df.global.plotinfo}do
  local size,address=df.sizeof(object);local bytes=df.new('uint8_t',size)
  dfhack.internal.memmove(bytes,address,size);copies[#copies+1]={size=size,address=address,bytes=bytes}
 end
 local text,status=dfhack.run_command_silent('df3d','unit-header-activity-probe',tostring(unit.id))
 local unchanged=true
 for _,copy in ipairs(copies)do
  if dfhack.internal.memcmp(copy.bytes,copy.address,copy.size)~=0 then unchanged=false end
  df.delete(copy.bytes)
 end
 assert(status==0,text);assert(unchanged,'activity reader changed native UI')
 local direct=json.decode(text);assert(cleared(),'direct reader did not retire stale squad references')
 seed();view:render(0);assert(cleared(),'native sheet did not retire stale squad references')
 local chars,colors={},{}
 for x=66,98 do local pen=dfhack.screen.readTile(x,9);chars[#chars+1]=pen.ch>=32 and string.char(pen.ch) or ' ';colors[#colors+1]=pen.fg+(pen.bold and 8 or 0)end
 local native=table.concat(chars):gsub('%s+$','')
 assert(dfhack.df2utf(native)==direct.text,'squad activity caption differs')
 for i=1,#native do assert(colors[i]==direct.color,'squad activity color differs')end
 result={squad_id=squad.id,unit_id=unit.id,activity=direct,native_text=dfhack.df2utf(native),native_foreground=colors[1],ui_unchanged=unchanged,direct_stale_ids_cleared=true,native_stale_ids_cleared=true}
end,debug.traceback)
unit.job.current_job=old_job;unit.military.squad_id=old_id;unit.military.squad_position=old_position
squad.positions[0]=original
position.orders:erase(0);df.delete(order);df.delete(position)
view:render(dfhack.getTickCount())
assert(ok,err)
return result
