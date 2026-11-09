-- Protected reference only: native item-list layout and input discovery.
local out,view=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local g=df.global.gps;local sheet=df.global.game.main_interface.view_sheets;local records={}
local function write(name,value)local f=assert(io.open(out..'/'..name,'w'));f:write(value);f:close()end
local function wait(name)
 local deadline=dfhack.getTickCount()+10000
 while true do local f=io.open(out..'/'..name);if f then f:close();return end
  assert(dfhack.getTickCount()<deadline,'Contents scroll handshake timeout');script.sleep(1,'frames')end
end
local function move(x,y)
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
end
local function shot(name)
 move(20,20)
 for _=1,5 do view:render(dfhack.getTickCount());script.sleep(1,'frames')end
 records[#records+1]={name=name,columns=g.dimx,rows=g.dimy,first=sheet.scroll_position_item_contents}
 write('shot.tmp','contents-scroll-'..name);assert(os.rename(out..'/shot.tmp',out..'/shot'));wait('ack-contents-scroll-'..name)
end
local function resize(size)
 write('owner-input-request.tmp','name-resize-'..size);assert(os.rename(out..'/owner-input-request.tmp',out..'/owner-input-request'))
 wait('owner-input-ack');assert(os.remove(out..'/owner-input-ack'))
 for _=1,5 do view:render(dfhack.getTickCount());script.sleep(1,'frames')end
end
resize('small');sheet.scroll_position_item_contents=0;shot('small')
for _,probe in ipairs{{'down','CONTEXT_SCROLL_DOWN',450,310},{'page','CONTEXT_SCROLL_PAGEDOWN',450,310},
 {'up','CONTEXT_SCROLL_UP',450,310},{'outside','CONTEXT_SCROLL_DOWN',20,20},
 {'arrow','_MOUSE_L',648,522}}do
 move(probe[3],probe[4]);gui.simulateInput(view,probe[2]);shot(probe[1])
end
resize('wide');shot('wide');resize('default');shot('default')
write('contents-scroll-native.json',json.encode(records));return records
