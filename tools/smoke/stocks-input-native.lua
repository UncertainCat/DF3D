-- Protected input discovery only; native menu fields are observations, never
-- runtime adapter inputs. Keep the original query/offsets after the probe.
local view,stocks=...
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
 for _,binding in ipairs{'STANDARDSCROLL_DOWN','STANDARDSCROLL_PAGEDOWN','CURSOR_DOWN'}do
  stocks.scroll_position_type=0;stocks.scroll_position_item=0
  position(region[2],region[3]);key(binding);observe(region[1]..'-'..binding)
 end
end
stocks.scroll_position_type=first_type;stocks.scroll_position_item=first_item
stocks.entering_item_filter=original_focus;view:render(dfhack.getTickCount())
assert(stocks.item_filter==original_query,'Input probe did not restore query')
return result
