-- Protected discovery only. Native UI storage is evidence, never runtime input.
local out,view,records=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local function scratch()
 local values={}
 for _,item in ipairs(df.global.world.items.other.IN_PLAY)do values[#values+1]={item.id,item.base_uniform_score}end
 return json.encode(values)
end
local function probe(command)
 local before=scratch();local menu=df.global.game.main_interface.stocks
 local open=menu.open;local selected=menu.current_type;local query=menu.item_filter
 local text,code=dfhack.run_command_silent('df3d',command)
 assert(code==0,'Stocks inventory failed: '..text)
 assert(before==scratch(),'Inventory probe changed item temporary_32')
 assert(open==menu.open and selected==menu.current_type and query==menu.item_filter,'Inventory probe changed menu state')
 return json.decode(text)
end
local cold,cold_groups,cold_totals,cold_display
if os.getenv('DF3D_STOCKS_DISPLAY')=='1' then cold_display=probe('stocks-display-probe').rows end
if os.getenv('DF3D_STOCKS_PROVIDER')=='1' then cold=probe('stocks-inventory-probe').ids end
if os.getenv('DF3D_STOCKS_GROUPS')=='1' then cold_groups=probe('stocks-groups-probe').groups end
if os.getenv('DF3D_STOCKS_TOTALS')=='1' then cold_totals=probe('stocks-totals-probe')end
gui.simulateInput(view,'D_STOCKS')
for _=1,3 do script.sleep(1,'frames')end
view:render(dfhack.getTickCount())
local stocks=df.global.game.main_interface.stocks;assert(stocks.open,'Stocks did not open')
local function values(vector)
 local result={};for _,value in ipairs(vector)do result[#result+1]=value end;return result
end
local _,address=df.sizeof(stocks)
local result={stocks_rva=address-dfhack.internal.getImageBase(),current_type=stocks.current_type,
 types=values(stocks.type_list),filtered_types=values(stocks.filtered_type_list),
 stored=values(stocks.storeamount),unavailable=values(stocks.badamount),
 scroll_type=stocks.scroll_position_type,scroll_item=stocks.scroll_position_item,
 item_filter=stocks.item_filter,individual_ids={},groups={},screen_rows={}}
if cold_totals then
 local warm=probe('stocks-totals-probe')
 for _,field in ipairs{'stored','unavailable'}do
  assert(json.encode(cold_totals[field])==json.encode(result[field]),'Cold '..field..' totals differ')
  assert(json.encode(warm[field])==json.encode(result[field]),'Warm '..field..' totals differ')
 end
 result.totals_provider={cold=cold_totals,warm=warm,scratch_preserved=true}
end
for _,item in ipairs(stocks.current_type_i_list)do result.individual_ids[#result.individual_ids+1]=item.id end
if cold then
 local warm=probe('stocks-inventory-probe').ids;local native={}
 for _,item in ipairs(stocks.master_i_list.l_item)do native[#native+1]=item.id end
 table.sort(cold);table.sort(warm);table.sort(native)
 assert(json.encode(cold)==json.encode(native),'Cold inventory membership differs from native')
 assert(json.encode(warm)==json.encode(native),'Warm inventory membership differs from native')
 local _,address=df.sizeof(df.global.world.items.other.IN_PLAY)
 result.inventory={cold=cold,warm=warm,native=native,scratch_preserved=true,in_play_rva=address-dfhack.internal.getImageBase()}
end
if cold_groups then
 local warm=probe('stocks-groups-probe').groups;local native={};local master=stocks.master_a_list
 for index,kind in ipairs(master.type)do
  native[#native+1]={type=kind,subtype=master.subtype[index],subcat1=master.subcat1[index],subcat2=master.subcat2[index],amount=master.amount[index],expanded=master.expanded[index]}
 end
 local function equal(actual,label)
  assert(#actual==#native,label..' group count differs')
  for i,row in ipairs(native)do for key,value in pairs(row)do assert(actual[i][key]==value,label..' group differs at '..i..'/'..key)end end
 end
 equal(cold_groups,'Cold');equal(warm,'Warm')
 result.group_provider={cold=cold_groups,warm=warm,native=native,scratch_preserved=true}
end
for index,subtype in ipairs(stocks.current_type_a_subtype)do
 result.groups[#result.groups+1]={subtype=subtype,subcat1=stocks.current_type_a_subcat1[index],
  subcat2=stocks.current_type_a_subcat2[index],amount=stocks.current_type_a_amount[index],
  expanded=stocks.current_type_a_expanded[index],on=stocks.current_type_a_on[index],flags=stocks.current_type_a_flag[index].whole}
end
if cold_display then
 local warm=probe('stocks-display-probe').rows
 assert(json.encode(cold_display)==json.encode(warm),'Cold/warm category display differs')
 local original=stocks.scroll_position_type;local captured={}
 local function text_at(x,y,length)
  local text=''
  for column=x,x+length-1 do
   local ch=dfhack.screen.readTile(column,y).ch
   text=text..(ch>=32 and ch<127 and string.char(ch) or ' ')
  end
  return text:gsub('%s+$','')
 end
 for index,kind in ipairs(stocks.filtered_type_list)do
  stocks.scroll_position_type=index
  view:render(dfhack.getTickCount())
  local row=cold_display[kind+1];assert(row.type==kind)
  local native={type=kind,caption=text_at(8,7,24),stored=text_at(32,7,8),unavailable=text_at(32,8,8)}
  for _,field in ipairs{'caption','stored','unavailable'}do
   assert(native[field]==row[field],('Display differs for %d/%s: [%s] vs [%s]'):format(kind,field,native[field],row[field]))
  end
  captured[#captured+1]=native
 end
 stocks.scroll_position_type=original;view:render(dfhack.getTickCount())
 result.display_provider={cold=cold_display,warm=warm,native=captured,scratch_preserved=true}
end
for y=0,df.global.gps.dimy-1 do
 local row={};for x=0,df.global.gps.dimx-1 do row[#row+1]=dfhack.screen.readTile(x,y).ch end
 result.screen_rows[#result.screen_rows+1]=row
end
local f=assert(io.open(out..'/stocks-native.json','w'));f:write(json.encode(result));f:close()
f=assert(io.open(out..'/shot.tmp','w'));f:write('stocks-root');f:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
local deadline=dfhack.getTickCount()+10000
while true do local ack=io.open(out..'/ack-stocks-root');if ack then ack:close();break end
 assert(dfhack.getTickCount()<deadline,'Stocks capture timeout');script.sleep(1,'frames')end
records[#records+1]={name='stocks-root',types=#result.types,groups=#result.groups}
gui.simulateInput(view,'LEAVESCREEN');assert(not stocks.open,'Stocks did not close')
