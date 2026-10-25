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
  for i=1,4 do gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())end
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
  local function label_click(label,offset,column)
   local screen={};local px,py
   for y=0,g.dimy-1 do
    local chars={};for x=0,g.dimx-1 do local t=dfhack.screen.readTile(x,y);chars[#chars+1]=(t.ch>=32 and t.ch<127)and string.char(t.ch)or' ' end
    local line=table.concat(chars);screen[#screen+1]=line
    local x=line:find(label,column==3 and 75 or column==2 and 40 or 1,true)
    local in_column=x and (column==3 and x>=75 or column==2 and x>=40 and x<75 or not column and x<40)
    if in_column and not px then px=x-1+(offset or 0);py=y end
   end
   if px then
    if column==3 then
     local f=assert(io.open(out..'/bulk-screen.txt','w'));f:write(table.concat(screen,'\n'));f:close()
    end
    click(px,py);return {x=px,y=py}
   end
   local custom=df.global.game.main_interface.custom_stockpile
   if not column and custom.open and custom.scroll_position_main==0 then
    -- Oracle-only viewport setup; selection itself still uses the native click.
    custom.scroll_position_main=4;view:render(dfhack.getTickCount())
    return label_click(label,offset,column)
   end
   local f=assert(io.open(out..'/missing-'..label..'.txt','w'));f:write(table.concat(screen,'\n'));f:close()
   error('Native label absent: '..label)
  end

  label_click('Custom',-2)
  local c=df.global.game.main_interface.custom_stockpile
  require('gui.script').sleep(5,'frames')
  view:render(dfhack.getTickCount())
  local lines={}
  for y=0,g.dimy-1 do
   local chars={}
   for x=0,g.dimx-1 do local t=dfhack.screen.readTile(x,y);chars[#chars+1]=(t.ch>=32 and t.ch<127)and string.char(t.ch)or' ' end
   lines[#lines+1]=table.concat(chars)
  end
  records[#records+1]={grid={g.dimx,g.dimy},pixels={g.screen_pixel_x,g.screen_pixel_y},lines=lines,
   percentage=df.global.init.display.interface_scaling_percentage,auto=df.global.init.display.flag.INTERFACE_SCALING_TO_DESIRED_HEIGHT_WIDTH,main=c.cur_main_mode,sub=c.cur_sub_mode,main_scroll=c.scroll_position_main,sub_scroll=c.scroll_position_sub}
  local f=assert(io.open(out..'/screen.txt','w'));f:write(table.concat(lines,'\n'));f:close()
  label_click('Food')
  c.scroll_position_spec=0;view:render(dfhack.getTickCount())
  g.mouse_x=80;g.mouse_y=10;g.precise_mouse_x=80*(g.screen_pixel_x//g.dimx)+4;g.precise_mouse_y=10*(g.screen_pixel_y//g.dimy)+6
  df.global.enabler.tracking_on=1
  gui.simulateInput(view,'CONTEXT_SCROLL_PAGEDOWN');view:render(dfhack.getTickCount())
  local page=(g.dimy-16)//3
  assert(c.scroll_position_spec==page,'native page size differs: '..c.scroll_position_spec..' vs '..page)
  records[#records+1]={probe='leaf_page_down',page=page,observed=c.scroll_position_spec,count=c.cur_spec_item_sz}
  label_click('Ammo');view:render(dfhack.getTickCount())
  assert(frame==df.global.world.frame_counter,'simulation advanced')
 end)
 local f=assert(io.open(out..'/result.tmp','w'));f:write(require('json').encode{success=ok,error=tostring(why),records=records});f:close();assert(os.rename(out..'/result.tmp',out..'/result.json'))
end)
print('STOCKPILE_LAYOUT_STARTED')
