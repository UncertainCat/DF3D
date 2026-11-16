local view,b,unit,position,trade,added,click,select_map=...
local gui=require('gui');local json=require('json');local gps=df.global.gps
local caravans=df.global.plotinfo.caravans
assert(#added==2 and #caravans==2 and trade.open and trade.choosing_merchant)
local second=added[2];local state=second.trade_state;local flags=second.flags.whole
local result={cases={}}
local function probe(action,token,depot)
 local args={'df3d','trade-catalog-probe',action,tostring(depot or b.id)};if token then args[#args+1]=tostring(token)end
 local output,code=dfhack.run_command_silent(table.unpack(args));assert(code==0,output);return json.decode(output)
end
local function line(y)
 local chars={};for x=0,gps.dimx-1 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and string.char(ch) or ' 'end
 return dfhack.df2utf(table.concat(chars)):gsub('%s+$','')
end
local function compare(label)
 local row=probe('read');assert(row.available and #row.choices==#trade.merlist)
 for i,choice in ipairs(row.choices)do assert(choice.entity==trade.merlist[i-1].entity and choice.token>0)end
 if trade.choosing_merchant then
  assert(line(6):find(row.title,1,true))
  for i,choice in ipairs(row.choices)do assert(line(9+3*(i-1)):find(choice.race..row.from..choice.name,1,true),'Catalog caption differs')end
 end
 result.cases[#result.cases+1]={label=label,catalog=row};return row
end
local function reopen()
 if trade.open then gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())end
 unit.pos.x=position.x;unit.pos.y=position.y;unit.pos.z=position.z;select_map(b)
 unit.pos.x=b.centerx;unit.pos.y=b.centery;unit.pos.z=b.z;click(480,190);assert(trade.open)
end
local ok,err=xpcall(function()
 local row=compare('two-groups');assert(#row.choices==2 and row.choices[1].token~=row.choices[2].token)
 local old=row.choices[1].token;row=compare('refreshed')
 assert(not probe('choose',old).available)
 assert(not probe('choose',row.choices[2].token,b.id+1).available)
 assert(not probe('epoch',row.choices[2].token).available)
 local choice=probe('choose',row.choices[2].token);assert(choice.available and choice.entity==added[2].entity)
 assert(trade.open and trade.choosing_merchant and #trade.merlist==2,'Catalog choice changed native menu')
 assert(not probe('choose',row.choices[2].token).available)
 local output,code=dfhack.run_command_silent('df3d','trade-session-probe','close',tostring(choice.session));assert(code==0 and json.decode(output).status==3)
 click(100,154);assert(trade.open and not trade.choosing_merchant and trade.mer==added[2],'Native second-row selection differs')
 reopen();row=compare('before-reorder')
 caravans[0]=added[2];caravans[1]=added[1]
 assert(not probe('choose',row.choices[1].token).available)
 caravans[0]=added[1];caravans[1]=added[2]
 row=compare('before-eligibility-change');second.flags.tribute=true
 assert(not probe('choose',row.choices[2].token).available);second.flags.whole=flags
 for _,value in ipairs{0,1,3,4}do
  second.trade_state=value;reopen();assert(not trade.choosing_merchant and #trade.merlist==1)
  local single=compare('state-'..value);assert(#single.choices==1)
 end
 second.trade_state=state;second.flags.tribute=true;reopen();assert(#trade.merlist==1);compare('tribute-excluded')
 second.flags.whole=flags;reopen();compare('restored')
 result.token_refresh_rejected=true;result.consumed_once=true;result.reorder_rejected=true;result.eligibility_rejected=true;result.epoch_rejected=true
end,debug.traceback)
caravans[0]=added[1];caravans[1]=added[2];second.trade_state=state;second.flags.whole=flags
if not ok then error(err)end
return result
