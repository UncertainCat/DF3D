-- Cold typed transport acceptance: no native Stocks menu has been opened.
local out,probe=...
local json=require('json');local script=require('gui.script')
local function write(name,value)local f=assert(io.open(out..'/'..name,'w'));f:write(value);f:close()end
local reference={selection=probe('stocks-selection-probe','39',''),
 display=probe('stocks-display-probe').rows,order=probe('stocks-categories-probe','').types,
 matches=probe('stocks-categories-probe','iron').types}
local before={};for _,item in ipairs(df.global.world.items.other.IN_PLAY)do before[item.id]=item.flags.whole end
local members={};for _,id in ipairs(reference.selection.groups[1].ids)do members[id]=true end
local original=df.item.find(reference.selection.groups[1].ids[1]).flags.hidden
for id in pairs(members)do assert(df.item.find(id).flags.hidden==original,'Fixture needs uniform visibility')end
reference.original_hidden=original
write('stocks-wire-reference.json',json.encode(reference))
write('shot.tmp','stocks-wire');assert(os.rename(out..'/shot.tmp',out..'/shot'))
local checked=0;local deadline=dfhack.getTickCount()+25000
while true do
 local step=io.open(out..'/stocks-wire-step')
 if step then local index=tonumber(step:read('*a'));step:close()
  if index and index>checked then
   assert(index==checked+1 and index<=2,'Unexpected Stocks edit step')
   local desired
   if index==1 then desired=not original else desired=original end
   for id,flags in pairs(before)do
    local expected=flags
    if members[id]then if desired then expected=flags|0x1000000 else expected=flags&(~0x1000000)end end
    assert(df.item.find(id).flags.whole==expected,'Stocks wire changed wrong item flags '..id)
   end
   checked=index;write('stocks-wire-ack',tostring(index))
  end
 end
 local ack=io.open(out..'/ack-stocks-wire');if ack then ack:close();break end
 assert(dfhack.getTickCount()<deadline,'Stocks wire timeout');script.sleep(1,'frames')
end
assert(checked==2,'Stocks wire effects incomplete')
assert(not df.global.game.main_interface.stocks.open,'Typed Stocks opened native menu')
