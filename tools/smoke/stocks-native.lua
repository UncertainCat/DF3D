-- Protected discovery only. Native UI storage is evidence, never runtime input.
local out,view,records=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
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
for _,item in ipairs(stocks.current_type_i_list)do result.individual_ids[#result.individual_ids+1]=item.id end
for index,subtype in ipairs(stocks.current_type_a_subtype)do
 result.groups[#result.groups+1]={subtype=subtype,subcat1=stocks.current_type_a_subcat1[index],
  subcat2=stocks.current_type_a_subcat2[index],amount=stocks.current_type_a_amount[index],
  expanded=stocks.current_type_a_expanded[index],on=stocks.current_type_a_on[index],flags=stocks.current_type_a_flag[index].whole}
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
