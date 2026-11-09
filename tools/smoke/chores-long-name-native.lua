-- Protected display discovery only; restore the owned clone's nickname even
-- when an observation fails. No naming action is exposed by this probe.
local out,view,panel,shot=...
local script=require('gui.script');local json=require('json');local g=df.global.gps
local unit=assert(panel.unit[0]);local original=unit.name.nickname
local result={unit_id=unit.id,nickname=string.rep('ABCDEFGHIJ',4),sizes={}}
local function resize(size)
 local f=assert(io.open(out..'/owner-input-request.tmp','w'));f:write('name-resize-'..size);f:close()
 assert(os.rename(out..'/owner-input-request.tmp',out..'/owner-input-request'))
 local deadline=dfhack.getTickCount()+5000
 while true do local ack=io.open(out..'/owner-input-ack');if ack then ack:close();break end;assert(dfhack.getTickCount()<deadline,'Long-name resize timed out');script.sleep(1,'frames')end
 assert(os.remove(out..'/owner-input-ack'));script.sleep(5,'frames');view:render(dfhack.getTickCount())
end
local ok,err=xpcall(function()
 unit.name.nickname=result.nickname
 local text,code=dfhack.run_command_silent('df3d','chores-captions-probe');assert(code==0)
 result.captions=json.decode(text)
 for _,size in ipairs{'default','minimum','wide'}do
  resize(size);local lines={}
  for y=14,g.dimy-4 do
   local chars={};for x=4,math.min(118,g.dimx-1)do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
   local line=dfhack.df2utf(table.concat(chars)):gsub('%s+$','');if line:find('%S')then lines[#lines+1]={y=y,text=line}end
  end
  result.sizes[#result.sizes+1]={size=size,columns=g.dimx,rows=g.dimy,text=lines}
  shot('chores-long-name-'..size)
 end
end,debug.traceback)
unit.name.nickname=original;resize('default')
assert(unit.name.nickname==original);assert(ok,err)
local file=assert(io.open(out..'/chores-long-name-native.json','w'));file:write(json.encode(result));file:close()
