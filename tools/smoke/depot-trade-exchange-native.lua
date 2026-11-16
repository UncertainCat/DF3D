-- Paused native reference. Empty selections cannot transfer fixture items.
local view,trade,click,capture=...
local gps=df.global.gps
local result={cases={},globals={}}
for _,entry in ipairs{{'display',gps,'force_full_display_count'}, {'history_suppression',df.global.world,'artifact_history_suppression_count'}, {'fortress_entity',df.global.plotinfo.main,'fortress_entity'}}do
 local _,address=df.sizeof(entry[2]:_field(entry[3]));result.globals[entry[1]]=address-dfhack.internal.getImageBase()
end
local mass=trade.mer.total_capacity;local whole,fraction=mass.whole,mass.fraction
local talkline=trade.talkline
local function snapshot(label)
 local row={label=label,talkline=trade.talkline,counter_offer=trade.counter_offer,lines={}}
 for side=0,1 do for _,flag in ipairs(trade.goodflag[side])do assert(not flag.selected,'Empty exchange selected an item')end end
 for y=5,11 do local text={};for x=5,120 do local ch=dfhack.screen.readTile(x,y).ch;text[#text+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end;row.lines[#row.lines+1]=dfhack.df2utf(table.concat(text)):gsub('%s+$','')end
 result.cases[#result.cases+1]=row;capture('depot-trade-empty-'..label)
end
local ok,err=xpcall(function()
 mass.whole=100000;mass.fraction=0;view:render(dfhack.getTickCount());snapshot('before')
 click(508,730);snapshot('trade')
 click(735,730);snapshot('gift')
end,debug.traceback)
mass.whole=whole;mass.fraction=fraction;trade.talkline=talkline
assert(ok,err);return result
