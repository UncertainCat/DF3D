-- Protected discovery only. Native menu lists are observations, never runtime inputs.
local out,view,records=...
local gui=require('gui');local script=require('gui.script');local json=require('json');local g=df.global.gps
local function write(name,value)local f=assert(io.open(out..'/'..name,'w'));f:write(value);f:close()end
local function settle()for _=1,3 do script.sleep(1,'frames')end;view:render(dfhack.getTickCount())end
local function lines()
 local result={}
 for y=0,g.dimy-1 do
  local chars={};for x=0,g.dimx-1 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
  result[#result+1]={y=y,text=dfhack.df2utf(table.concat(chars)):gsub('%s+$','')}
 end
 return result
end
local function capture(name)
 write('shot.tmp',name);assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local deadline=dfhack.getTickCount()+10000
 while true do local ack=io.open(out..'/ack-'..name);if ack then ack:close();break end;assert(dfhack.getTickCount()<deadline,'Places capture timed out');script.sleep(1,'frames')end
end
gui.simulateInput(view,'D_LOCATIONS');settle()
local info=df.global.game.main_interface.info
assert(info.open and info.current_mode==df.info_interface_mode_type.BUILDINGS,'Places shortcut did not open native Buildings')
local result={initial_mode=info.buildings.mode,pages={}}
local function save()write('places-native.json',json.encode(result))end
for _,caption in ipairs{'Zones','Locations','Stockpiles','Workshops','Farm plots','Siege engines'}do
 local found=false
 for _,line in ipairs(lines())do
  if line.y>=4 and line.y<=12 then
   local x=line.text:find(caption,1,true)
   if x then
    g.precise_mouse_x=(x-1)*8+4;g.precise_mouse_y=line.y*12+6;g.mouse_x=x-1;g.mouse_y=line.y
    df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
    gui.simulateInput(view,'_MOUSE_L');df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
    settle();found=true;break
   end
  end
 end
 local page={caption=caption,found=found,mode=info.buildings.mode,lines=lines(),lists={}}
 for mode=0,5 do
  local entries={};for _,building in ipairs(info.buildings.list[mode])do entries[#entries+1]={id=building.id,type=building:getType(),position={building.centerx,building.centery,building.z}}end
  page.lists[#page.lists+1]={mode=mode,entries=entries,scroll=info.buildings.scrolling_position[mode]}
 end
 result.pages[#result.pages+1]=page;save();capture('places-'..caption:lower():gsub(' ','-'))
 assert(found,'Native Places tab missing: '..caption)
end
gui.simulateInput(view,'LEAVESCREEN');settle();assert(not info.open,'Places did not close')
result.closed=true;save();records[#records+1]={name='places-discovery',pages=#result.pages,closed=true}
