-- Protected native hover evidence; never a runtime source of menu state.
local out,view,result=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local gps=df.global.gps;local main=df.global.game.main_interface
local observations={}
local function move(x,y)
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 gps.precise_mouse_x=x;gps.precise_mouse_y=y;gps.mouse_x=x//8;gps.mouse_y=(y-4)//12
 gui.simulateInput(view,{});view:render(dfhack.getTickCount())
end
local targets={{'group-forbid',844,130,207},{'group-dump',868,130,208},
 {'group-melt',892,130,209},{'group-visibility',916,130,210},
 {'recenter',796,166,205},{'view',820,166,206},{'forbid',844,166,207},
 {'dump',868,166,208},{'melt',892,166,209},{'visibility',916,166,210}}
for _,target in ipairs(targets)do
 local deadline=dfhack.getTickCount()+700
 repeat move(target[2],target[3]);script.sleep(1,'frames')until dfhack.getTickCount()>=deadline
 move(target[2],target[3])
 assert(main.hover_instructions_on and main.current_hover==target[4],'Unexpected Stocks hover '..target[1])
 local row={kind=target[1],x=target[2],y=target[3],instruction=main.current_hover,lines={}}
 for y=0,17 do local line={}
  for x=gps.dimx-24,gps.dimx-1 do local ch=dfhack.screen.readTile(x,y).ch
   line[#line+1]=ch>=32 and string.char(ch%256) or ' '
  end
  row.lines[#row.lines+1]=dfhack.df2utf(table.concat(line)):gsub('%s+$','')
 end
 while #row.lines>0 and row.lines[#row.lines]==''do table.remove(row.lines)end
 observations[#observations+1]=row
 local name='stocks-help-'..target[1]
 local f=assert(io.open(out..'/shot.tmp','w'));f:write(name);f:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
 deadline=dfhack.getTickCount()+10000
 while true do local ack=io.open(out..'/ack-'..name);if ack then ack:close();break end
  assert(dfhack.getTickCount()<deadline,'Stocks help capture timeout');script.sleep(1,'frames')end
end
move(500,130)
result.hover=observations
local f=assert(io.open(out..'/stocks-hover.json','w'));f:write(json.encode(observations));f:close()
