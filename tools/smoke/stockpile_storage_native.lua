-- Protected owned lane only: pause, disable autosave, preserve save manifests,
-- and close without saving. Mutates the first pile through native clicks.
-- Run with an output directory; result.json is published atomically.
local out=...
require('gui.script').start(function()
 local records={}
 local ok,why=pcall(function()
  local json=require('json');local gui=require('gui');local g=df.global.gps
  local view=dfhack.gui.getDFViewscreen(true)
  assert(df.global.pause_state);local frame=df.global.world.frame_counter
  assert(dfhack.run_command('disable','overlay')==0)
  local b=assert(df.global.world.buildings.other.STOCKPILE[0])
  local point={x=b.centerx,y=b.centery,z=b.z}
  gui.simulateInput(view,'D_STOCKPILES');df.global.game.main_interface.bottom_mode_selected=-1
  dfhack.gui.revealInDwarfmodeMap(point,true);view:render(dfhack.getTickCount())
  local function click(x,y)
   g.mouse_x=x;g.mouse_y=y;g.precise_mouse_x=x*(g.screen_pixel_x//g.dimx)+4;g.precise_mouse_y=y*(g.screen_pixel_y//g.dimy)+6
   gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
  end
  local found=false
  for y=0,g.dimy-1 do for x=0,g.dimx-1 do
   g.mouse_x=x;g.mouse_y=y;g.precise_mouse_x=x*(g.screen_pixel_x//g.dimx)+4;g.precise_mouse_y=y*(g.screen_pixel_y//g.dimy)+6
   local p=dfhack.gui.getMousePos(true)
   if p and p.x==point.x and p.y==point.y and p.z==point.z then click(x,y);found=true;break end
  end if found then break end end
  assert(found,'no pile pointer');require('gui.script').sleep(2,'frames');view:render(dfhack.getTickCount())
  local function capture(name)
   g.mouse_x=0;g.mouse_y=0;view:render(dfhack.getTickCount());require('gui.script').sleep(3,'frames')
   local lines={};for y=0,g.dimy-1 do local line={};for x=0,g.dimx-1 do local t=dfhack.screen.readTile(x,y);line[#line+1]=(t.ch>=32 and t.ch<127)and string.char(t.ch)or' ' end;lines[#lines+1]=table.concat(line)end
   local f=assert(io.open(out..'/'..name..'.txt','w'));f:write(table.concat(lines,'\n'));f:close()
   records[#records+1]={name=name,barrels=b.storage.max_barrels,bins=b.storage.max_bins,wheelbarrows=b.storage.max_wheelbarrows}
   f=assert(io.open(out..'/shot.tmp','w'));f:write(name);f:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
   local limit=dfhack.getTickCount()+30000
   while not io.open(out..'/ack-'..name,'r')do assert(dfhack.getTickCount()<limit,'capture timeout');require('gui.script').sleep(1,'frames')end
  end
  capture('pile')
  click(42,15) -- Storage/tool barrel icon observed in protected pile.png
  capture('storage')
  local ui=df.global.game.main_interface.stockpile_tools
  local tiles=dfhack.buildings.countExtentTiles(b,-1)
  local function observe(name,key,before)
   records[#records+1]={name=name,key=key,before=before,after=b.storage['max_'..key],tiles=tiles,open=ui.open,entering=ui['entering_'..key],text=ui.number_str}
  end
  for index,key in ipairs{'barrels','bins','wheelbarrows'}do
   local y=10+(index-1)*3
   local cap=tiles-(key=='wheelbarrows' and 1 or 0)
   for _,value in ipairs{0,cap-1,cap,cap+1,32767}do
    b.storage['max_'..key]=value;view:render(dfhack.getTickCount());click(80,y);observe('plus',key,value)
    b.storage['max_'..key]=value;view:render(dfhack.getTickCount());click(84,y);observe('minus',key,value)
   end
   for _,text in ipairs{'1',tostring(cap),tostring(cap+1),'99999','-1','abc',''}do
    b.storage['max_'..key]=7;view:render(dfhack.getTickCount());click(76,y)
    assert(ui['entering_'..key],'number field did not focus')
    observe('entry-open',key,7)
    for i=1,#text do df.global.enabler.last_text_input[0]=text:byte(i);df.global.enabler.last_text_input[1]=0;gui.simulateInput(view,string.format('STRING_A%03d',text:byte(i)))end
    observe('entry-typed-'..text,key,7)
    gui.simulateInput(view,'SELECT');view:render(dfhack.getTickCount());observe('entry-submit-'..text,key,7)
    if ui['entering_'..key] then gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())end
   end
   b.storage['max_'..key]=7;view:render(dfhack.getTickCount());click(76,y)
   for _,byte in ipairs{49,50}do df.global.enabler.last_text_input[0]=byte;df.global.enabler.last_text_input[1]=0;gui.simulateInput(view,string.format('STRING_A%03d',byte))end
   observe('before-escape',key,7);gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());observe('after-escape',key,7)
   if not ui.open then click(42,15)end
   click(76,y)
   for _,byte in ipairs{49,50}do df.global.enabler.last_text_input[0]=byte;df.global.enabler.last_text_input[1]=0;gui.simulateInput(view,string.format('STRING_A%03d',byte))end
   gui.simulateInput(view,'STRING_A000');observe('backspace-one',key,7)
   gui.simulateInput(view,'STRING_A000');observe('backspace-empty',key,7)
   gui.simulateInput(view,'SELECT')
  end
  capture('storage-after-input')
  assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
 end)
 local f=assert(io.open(out..'/result.json.tmp','w'));f:write(require('json').encode{success=ok,error=ok and '' or tostring(why),records=records});f:close();assert(os.rename(out..'/result.json.tmp',out..'/result.json'))
end)
print('STOCKPILE_STORAGE_STARTED')
