-- Protected input discovery only; native menu fields are observations, never
-- runtime adapter inputs. Keep the original query/offsets after the probe.
local view,stocks,out=...
local gui=require('gui')
local result={}
local first_type,first_item=stocks.scroll_position_type,stocks.scroll_position_item
local original_query=stocks.item_filter
assert(original_query=='','Input fixture requires an empty filter')
local function position(x,y)
 local g=df.global.gps;g.precise_mouse_x=x;g.precise_mouse_y=y
 g.mouse_x=math.floor(x/8);g.mouse_y=math.floor(y/12)
end
local function key(value)gui.simulateInput(view,value);view:render(dfhack.getTickCount())end
local function click(x,y)position(x,y);key('_MOUSE_L')end
local function observe(name)
 result[#result+1]={name=name,focused=stocks.entering_item_filter,query=stocks.item_filter,
  category=stocks.current_type,category_scroll=stocks.scroll_position_type,item_scroll=stocks.scroll_position_item}
end
local original_focus=stocks.entering_item_filter
observe('initial')
click(500,94);observe('filter-click')
click(500,94);observe('filter-second-click')
key('STRING_A097');observe('unfocused-a')
if not stocks.entering_item_filter then click(500,94)end
key('STRING_A097');observe('focused-a')
key('SELECT');observe('enter')
click(350,70);observe('blank-click')
if not stocks.entering_item_filter then click(500,94)end
while #stocks.item_filter>0 do key('STRING_A000')end
if stocks.entering_item_filter then click(500,94)end
for _,region in ipairs{{'category',100,130},{'items',600,130},{'outside',20,20}}do
 for _,binding in ipairs{'STANDARDSCROLL_DOWN','STANDARDSCROLL_PAGEDOWN','CURSOR_DOWN','CONTEXT_SCROLL_DOWN','CONTEXT_SCROLL_PAGEDOWN'}do
  stocks.scroll_position_type=0;stocks.scroll_position_item=0
  position(region[2],region[3]);key(binding);observe(region[1]..'-'..binding)
 end
end
if os.getenv('DF3D_STOCKS_WHEEL')=='1' then
 local json=require('json');local script=require('gui.script')
 for _,region in ipairs{{'category',100,130},{'category-bar',328,250},{'items',600,130},{'item-bar',960,250},{'filter',500,94},{'outside',20,20}}do
  for _,step in ipairs{{'down',-120,false},{'up',120,false},{'shift-down',-120,true},{'shift-up',120,true}}do
   position(region[2],region[3]);df.global.enabler.mouse_focus=true;view:render(dfhack.getTickCount())
   local f=assert(io.open(out..'/kitchen-wheel.json','w'));f:write(json.encode({x=region[2],y=region[3],delta=step[2],shift=step[3]}));f:close()
   f=assert(io.open(out..'/owner-input-request.tmp','w'));f:write('stocks-wheel');f:close();assert(os.rename(out..'/owner-input-request.tmp',out..'/owner-input-request'))
   local deadline=dfhack.getTickCount()+10000
   while true do local ack=io.open(out..'/owner-input-ack');if ack then ack:close();break end;assert(dfhack.getTickCount()<deadline,'Stocks wheel timeout');script.sleep(1,'frames')end
   assert(os.remove(out..'/owner-input-ack'))
   for _=1,5 do script.sleep(1,'frames');view:render(dfhack.getTickCount())end
   observe('physical-'..region[1]..'-'..step[1])
  end
 end
end
stocks.scroll_position_type=first_type;stocks.scroll_position_item=first_item
stocks.entering_item_filter=original_focus;view:render(dfhack.getTickCount())
assert(stocks.item_filter==original_query,'Input probe did not restore query')
return result
