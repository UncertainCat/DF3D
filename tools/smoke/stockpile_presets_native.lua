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
  local lines={}
  for y=0,g.dimy-1 do local chars={};for x=0,g.dimx-1 do local t=dfhack.screen.readTile(x,y);chars[#chars+1]=(t.ch>=32 and t.ch<127)and string.char(t.ch)or' ' end;lines[#lines+1]=table.concat(chars)end
  local f=assert(io.open(out..'/screen.txt','w'));f:write(table.concat(lines,'\n'));f:close()
  local labels={'All','Animals','Food','Furniture','Corpses','Refuse','Stone','Ammo','Coins','Bars and','Gem','Finished','Leather','Cloth','Wood','Weapons','Armor','Sheets','None'}
  for preset,label in ipairs(labels)do
   local guards={}
   local function guard(address,size)
    local copy=df.new('uint8_t',size);dfhack.internal.memmove(copy,address,size)
    guards[#guards+1]={copy=copy,address=address,size=size}
   end
   local base=dfhack.internal.getImageBase()
   for _,range in ipairs{{0x234e990,0x6180},{0x2131b30,40},{0x2159084,2},{0x18adf98,8}}do guard(base+range[1],range[2])end
   local size,address=df.sizeof(df.global.game.main_interface);guard(address,size)
   size,address=df.sizeof(b);guard(address,size)
   local text,code=dfhack.run_command_silent('df3d','stockpile-preset-read',tostring(b.id),tostring(preset));assert(code==0,text)
   for _,g in ipairs(guards)do assert(dfhack.internal.memcmp(g.copy,g.address,g.size)==0,'RNG/UI/source guard changed');df.delete(g.copy)end
   local predicted=json.decode(text);local px,py
   for y,line in ipairs(lines)do local x=line:find(label,1,true);if x and x>=6 and x<=40 and y>=7 then px=x-1;py=y-1;break end end
   assert(px,'No label '..label)
   click(px-2,py)
   local errors={}
   if b.settings.flags.whole~=predicted.flags then errors[#errors+1]='flags '..b.settings.flags.whole..' vs '..predicted.flags end
   for kind,fields in pairs{vectors=predicted.vectors,fixed=predicted.fixed}do for key,values in pairs(fields)do
    local category,name=key:match('^([^%.]+)%.(.+)$');local actual=b.settings[category][name]
    if kind=='vectors' then
     if #actual~=#values then errors[#errors+1]=key..' length '..#actual..' vs '..#values else for i,v in ipairs(values)do if actual[i-1]~=v then errors[#errors+1]=key..' value '..i;break end end end
    elseif #values==1 then if actual~=values[1]then errors[#errors+1]=key end
    else for i,v in ipairs(values)do if actual[i-1]~=v then errors[#errors+1]=key..' value '..i;break end end end
   end end
   records[#records+1]={preset=preset,label=label,pointer={x=px-2,y=py},errors=errors,predicted=predicted,storage={barrels=b.storage.max_barrels,bins=b.storage.max_bins,wheelbarrows=b.storage.max_wheelbarrows}}
   assert(#errors==0,label..': '..table.concat(errors,', '))
  end
  assert(frame==df.global.world.frame_counter,'simulation advanced')
 end)
 local f=assert(io.open(out..'/result.tmp','w'));f:write(require('json').encode{success=ok,error=tostring(why),records=records});f:close();assert(os.rename(out..'/result.tmp',out..'/result.json'))
end)
print('STOCKPILE_PRESETS_STARTED')




