-- Observe local navigation through native input on the protected clone.
local out,view,result=...
local gui=require('gui');local json=require('json')
local stocks=df.global.game.main_interface.stocks;local gps=df.global.gps
local observations={}
local function record(label)
 local expanded,types,on={},{},{}
 for _,v in ipairs(stocks.current_type_a_expanded)do expanded[#expanded+1]=v end
 for _,v in ipairs(stocks.filtered_type_list)do types[#types+1]=v end
 for _,v in ipairs(stocks.current_type_a_on)do on[#on+1]=v end
 observations[#observations+1]={label=label,type=stocks.current_type,query=stocks.item_filter,
  expanded=expanded,types=types,on=on,first_type=stocks.scroll_position_type,first_item=stocks.scroll_position_item}
end
local function key(value)gui.simulateInput(view,value);view:render(dfhack.getTickCount())end
local function click(x,y)gps.precise_mouse_x=x;gps.precise_mouse_y=y;gps.mouse_x=x//8;gps.mouse_y=(y-4)//12;key('_MOUSE_L')end
record('initial')
click(500,130);record('collapsed-first')
click(100,130);record('second-category')
click(100,94);record('first-category-return')
click(500,130);record('collapsed-before-search')
click(500,94);assert(stocks.entering_item_filter)
for c in ('silver'):gmatch('.')do key(('STRING_A%03d'):format(string.byte(c)));record('silver-keystroke')end
assert(stocks.item_filter=='SILVER','Search did not type');record('search-silver')
for _=1,#stocks.item_filter do key('STRING_A000');record('backspace')end
record('clear-search')
for c in ('zzzznotstock'):gmatch('.')do key(('STRING_A%03d'):format(string.byte(c)));record('no-match-keystroke')end
assert(stocks.item_filter=='ZZZZNOTSTOCK','No-match search did not type');record('search-no-match')
for _=1,#stocks.item_filter do key('STRING_A000');record('backspace')end
record('clear-no-match')
result.navigation=observations
local f=assert(io.open(out..'/stocks-navigation.json','w'));f:write(json.encode(observations));f:close()
