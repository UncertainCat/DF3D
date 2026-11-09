-- Native Stocks shared item-selector reference; discovery only.
local out,view,stocks=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local rows={};local g=df.global.gps
local kinds=os.getenv('DF3D_STOCKS_EQUIPMENT_ART')=='1' and {24,25,26,27,28,29,60} or {0,2,4,5,30,32}
for _,kind in ipairs(kinds)do
 local found=false
 for index,value in ipairs(stocks.filtered_type_list)do if value==kind then stocks.scroll_position_type=index;found=true;break end end
 assert(found,'Missing Stocks art category '..kind);view:render(dfhack.getTickCount())
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=100;g.precise_mouse_y=94;g.mouse_x=12;g.mouse_y=7
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 assert(stocks.current_type==kind,'Stocks art category click failed')
 stocks.scroll_position_type=0;stocks.scroll_position_item=0
 g.precise_mouse_x=0;g.precise_mouse_y=0;g.mouse_x=0;g.mouse_y=0
 gui.simulateInput(view,{});view:render(dfhack.getTickCount())
 local ids={};for _,item in ipairs(stocks.current_type_i_list)do ids[#ids+1]=item.id end
 rows[#rows+1]={category=kind,ids=ids}
 local name='stocks-art-'..kind
 local f=assert(io.open(out..'/shot.tmp','w'));f:write(name);f:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local deadline=dfhack.getTickCount()+10000
 while true do local ack=io.open(out..'/ack-'..name);if ack then ack:close();break end;assert(dfhack.getTickCount()<deadline,'Stocks art capture timeout');script.sleep(1,'frames')end
end
return rows
