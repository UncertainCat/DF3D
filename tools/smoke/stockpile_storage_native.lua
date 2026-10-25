-- Protected owned lane only: pause, disable autosave, preserve save manifests,
-- and close without saving. Mutates the first pile through native clicks.
-- Run with an output directory; result.json is published atomically.
local out,repaint=...
require('gui.script').start(function()
 local records={}
 local ok,why=pcall(function()
  local json=require('json');local gui=require('gui');local g=df.global.gps
  local view=dfhack.gui.getDFViewscreen(true)
  assert(df.global.pause_state);local frame=df.global.world.frame_counter
  assert(dfhack.run_command('disable','overlay')==0)
  local b=assert(df.global.world.buildings.other.STOCKPILE[0])
  local pile_id=b.id
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
   local alive=df.building.find(pile_id)
   records[#records+1]=alive and {name=name,barrels=alive.storage.max_barrels,bins=alive.storage.max_bins,wheelbarrows=alive.storage.max_wheelbarrows} or {name=name,removed=true}
   f=assert(io.open(out..'/shot.tmp','w'));f:write(name);f:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
   local limit=dfhack.getTickCount()+30000
   while not io.open(out..'/ack-'..name,'r')do assert(dfhack.getTickCount()<limit,'capture timeout');require('gui.script').sleep(1,'frames')end
  end
  capture('pile')
  if repaint then
   click(38,9) -- Native pile repaint icon at304,118 in pile.png.
   local paint=df.global.game.main_interface.stockpile
   assert(paint.repainting,'repaint did not open')
   capture('repaint')
   local cells={}
   for y=b.y1,b.y2 do for x=b.x1,b.x2 do
    if not b.room.extents or b.room.extents[(y-b.room.y)*b.room.width+x-b.room.x]~=0 then cells[#cells+1]={x=x,y=y,z=b.z}end
   end end
   assert(#cells==dfhack.buildings.countExtentTiles(b,-1) and #cells>3)
   local function mapclick(p)
    dfhack.gui.revealInDwarfmodeMap(p,true);view:render(dfhack.getTickCount())
    for y=0,g.dimy-1 do for x=0,g.dimx-1 do
     g.mouse_x=x;g.mouse_y=y;g.precise_mouse_x=x*(g.screen_pixel_x//g.dimx)+4;g.precise_mouse_y=y*(g.screen_pixel_y//g.dimy)+6
     local hit=dfhack.gui.getMousePos(true)
     if hit and hit.x==p.x and hit.y==p.y and hit.z==p.z then click(x,y);return end
    end end
    error('repaint tile is not visible')
   end
   local function record(name)
    b=assert(df.building.find(pile_id),'pile unexpectedly removed before '..name)
    records[#records+1]={name=name,tiles=dfhack.buildings.countExtentTiles(b,-1),barrels=b.storage.max_barrels,bins=b.storage.max_bins,wheelbarrows=b.storage.max_wheelbarrows,
     bounds={b.x1,b.y1,b.x2,b.y2},repainting=paint.repainting,erasing=paint.erasing}
   end
   for _,key in ipairs{'barrels','bins','wheelbarrows'}do b.storage['max_'..key]=#cells end
   record('before-shrink')
   click(84,61) -- Eraser at678,742 in protected repaint.png (1200x800).
   assert(paint.erasing and paint.doing_rectangle,'rectangle erase did not activate')
   for index=#cells,2,-1 do
    mapclick(cells[index]);mapclick(cells[index])
    assert(dfhack.buildings.countExtentTiles(b,-1)==index-1,'erase did not remove exactly one tile')
    record('erase-'..index)
   end
   capture('one-tile')
   click(84,61);assert(not paint.erasing,'erase did not toggle off')
   mapclick(cells[2]);mapclick(cells[2]);record('regrow-two')
   capture('regrown')
   b.storage.max_barrels=0;b.storage.max_bins=2;b.storage.max_wheelbarrows=0
   record('mixed-limits-two')
   click(84,61);assert(paint.erasing)
   mapclick(cells[2]);mapclick(cells[2]);record('mixed-limits-one')
   mapclick(cells[1]);mapclick(cells[1]);record('erased-all')
   capture('empty')
   click(84,61);assert(not paint.erasing)
   mapclick(cells[1]);mapclick(cells[1]);record('regrow-empty')
   click(84,61);assert(paint.erasing)
   mapclick(cells[1]);mapclick(cells[1]);record('empty-before-accept')
   click(38,6) -- Accept at310,82, observed in repaint.png.
   records[#records+1]={name='accept-empty',exists=df.building.find(pile_id)~=nil,repainting=paint.repainting,current=paint.cur_bld and paint.cur_bld.id or -1}
   capture('accepted-empty')
   gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
   records[#records+1]={name='escape-empty',exists=df.building.find(pile_id)~=nil,repainting=paint.repainting,current=paint.cur_bld and paint.cur_bld.id or -1}
   capture('escaped-empty')
   assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
   return
  end
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
