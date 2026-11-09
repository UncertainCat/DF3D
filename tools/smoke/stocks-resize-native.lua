-- Protected layout discovery; menu storage is never a runtime input.
local out,view,stocks=...
local script=require('gui.script');local gui=require('gui');local json=require('json')
local rows={};local g=df.global.gps
local function write(name,value)local f=assert(io.open(out..'/'..name,'w'));f:write(value);f:close()end
local function wait_file(name)
 local deadline=dfhack.getTickCount()+10000
 while true do local f=io.open(out..'/'..name);if f then f:close();break end;assert(dfhack.getTickCount()<deadline,'Stocks resize handshake timeout');script.sleep(1,'frames')end
end
for _,size in ipairs{'minimum','small','wide','default'}do
 write('owner-input-request.tmp','name-resize-'..size);assert(os.rename(out..'/owner-input-request.tmp',out..'/owner-input-request'))
 wait_file('owner-input-ack');assert(os.remove(out..'/owner-input-ack'))
 for _=1,5 do script.sleep(1,'frames');view:render(dfhack.getTickCount())end
 stocks.scroll_position_type=0;stocks.scroll_position_item=0
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=0;g.precise_mouse_y=0;g.mouse_x=0;g.mouse_y=0
 gui.simulateInput(view,{});view:render(dfhack.getTickCount())
 local row={name=size,columns=g.dimx,rows=g.dimy,category_scroll=stocks.scroll_position_type,item_scroll=stocks.scroll_position_item}
 rows[#rows+1]=row
 local name='stocks-resize-'..size
 write('shot.tmp',name);assert(os.rename(out..'/shot.tmp',out..'/shot'));wait_file('ack-'..name)
 g.precise_mouse_x=100;g.precise_mouse_y=130;g.mouse_x=12;g.mouse_y=10
 gui.simulateInput(view,'CONTEXT_SCROLL_PAGEDOWN');view:render(dfhack.getTickCount())
 g.precise_mouse_x=500;g.precise_mouse_y=130;g.mouse_x=62;g.mouse_y=10
 gui.simulateInput(view,'CONTEXT_SCROLL_PAGEDOWN');view:render(dfhack.getTickCount())
 row.category_page=stocks.scroll_position_type;row.item_page=stocks.scroll_position_item
end
stocks.scroll_position_type=0;stocks.scroll_position_item=0;view:render(dfhack.getTickCount())
write('stocks-resize.json',json.encode(rows));return rows
