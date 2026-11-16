-- Paused diagnostic oracle only. Temporary semantic/menu inputs are restored;
-- the product provider receives semantic records and its own dialogue state.
local view,trade,building=...
local json=require('json');local plot=df.global.plotinfo;local civ=trade.civ
local old={line=trade.talkline,animal=civ.resources.ethic.KILL_ANIMAL,plant=civ.resources.ethic.KILL_PLANT,
 race=civ.race,civ=plot.civ_id,king=plot.king_arrived,flags=trade.mer.flags.whole}
local result={cases={}}
local function normalized(text)return text:gsub('%s+',' '):match('^%s*(.-)%s*$')end
local function check(label,line)
 trade.talkline=line;view:render(dfhack.getTickCount())
 local lines={}
 for y=7,11 do
  local chars={}
  for x=0,df.global.gps.dimx-1 do
   local tile=dfhack.screen.readTile(x,y)
   chars[#chars+1]=(tile.fg==6 and (tile.bold==true or tile.bold==1) and tile.ch>=32 and tile.ch<=255)and string.char(tile.ch)or' '
  end
  lines[#lines+1]=table.concat(chars)
 end
 local expected=normalized(dfhack.df2utf(table.concat(lines,' ')))
 local output,code=dfhack.run_command_silent('df3d','trade-dialogue-probe',tostring(building.id),'0',tostring(line));assert(code==0,output)
 local actual=json.decode(output);assert(actual.available,output)
 assert(normalized(actual.dialogue)==expected,label..': '..actual.dialogue..' != '..expected)
 result.cases[#result.cases+1]={label=label,line=line,dialogue=actual.dialogue,native=expected}
end
local ok,err=xpcall(function()
 for line=0,28 do check('default-'..line,line)end
 civ.resources.ethic.KILL_ANIMAL=15;civ.resources.ethic.KILL_PLANT=1
 for _,line in ipairs{0,8,10,11,27,28}do check('ethical-'..line,line)end
 trade.mer.flags.greatly_offended=true;check('ethical-offended',27)
 civ.resources.ethic.KILL_ANIMAL=5;check('extreme-reason',0)
 civ.resources.ethic.KILL_ANIMAL=6;check('self-defense',0)
 civ.resources.ethic.KILL_ANIMAL=1;civ.resources.ethic.KILL_PLANT=15;check('plant-ethic',0)
 plot.civ_id=civ.id;plot.king_arrived=false;check('mountainhomes',0)
 plot.king_arrived=true;check('outer-lands',0)
 plot.civ_id=old.civ;civ.resources.ethic.KILL_ANIMAL=1;civ.resources.ethic.KILL_PLANT=1
 civ.race=plot.race_id;check('same-race',0);check('same-race-offer',17)
 for i,_ in ipairs(df.global.world.raws.creatures.all)do if i~=plot.race_id then civ.race=i;break end end
 check('other-race',0);check('other-race-offer',17)
end,debug.traceback)
trade.talkline=old.line;civ.resources.ethic.KILL_ANIMAL=old.animal;civ.resources.ethic.KILL_PLANT=old.plant
civ.race=old.race;plot.civ_id=old.civ;plot.king_arrived=old.king;trade.mer.flags.whole=old.flags
view:render(dfhack.getTickCount())
assert(ok,err);return result
