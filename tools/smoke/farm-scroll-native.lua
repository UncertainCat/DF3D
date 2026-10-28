-- Native reference only, inside the protected owned/unsaved farm lane.
local out,view,records,b=...
local script=require('gui.script');local gui=require('gui');local json=require('json')
local g=df.global.gps;local sheet=df.global.game.main_interface.view_sheets
local original={};for i=0,3 do original[i+1]=b.plant_id[i]end
local frame=df.global.world.frame_counter
local changed={}
for x=b.x1,b.x2 do for y=b.y1,b.y2 do
 local block=assert(dfhack.maps.getTileBlock(x,y,b.z));local d=block.designation[x%16][y%16]
 changed[#changed+1]={x=x,y=y,z=b.z,before=d.whole}
 d.subterranean=false;d.light=true;d.outside=true
end end
local function pointer(x,y)
 g.mouse_x=x//8;g.mouse_y=(y-4)//12;g.precise_mouse_x=x;g.precise_mouse_y=y
end
local function settle()
 for i=1,5 do view:render(dfhack.getTickCount());script.sleep(1,'frames')end
 assert(sheet.open and sheet.active_id==b.id,'farm target lost')
 assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
 for i=0,3 do assert(b.plant_id[i]==original[i+1],'scroll changed crop')end
end
df.global.game.main_interface.bottom_mode_selected=-1
local point={x=b.centerx,y=b.centery,z=b.z};dfhack.gui.revealInDwarfmodeMap(point,true);view:render(dfhack.getTickCount())
local found=false
for y=0,g.dimy-1 do for x=0,g.dimx-1 do
 pointer(x*8+4,y*12+10)
 local p=dfhack.gui.getMousePos(true)
 if p and p.x==point.x and p.y==point.y and p.z==point.z then
  gui.simulateInput(view,'_MOUSE_L');found=true;break
 end
end if found then break end end
assert(found,'farm not visible');settle()
local text,code=dfhack.run_command_silent('df3d','farm-choices-read',tostring(b.id),tostring(sheet.active_sub_tab))
assert(code==0,text);local choices=json.decode(text)
assert(#choices.rows+1==#df.global.plotinfo.selected_farm_crops,'native/provider count differs')
for _,row in ipairs(choices.rows)do row.raw_id=df.plant_raw.find(row.crop_id).id end
assert(#choices.rows>7,'surface setup did not produce a scrolling list')
for index,row in ipairs(choices.rows)do assert(df.global.plotinfo.selected_farm_crops[index]==row.crop_id,'native/provider order differs')end
local function shot(name)
 pointer(0,4);settle()
 local positions={};for key,value in pairs(sheet)do if type(key)=='string' and key:find('scroll_position',1,true) then positions[key]=value end end
 local lines={};for y=0,g.dimy-1 do
  local row={};for x=0,g.dimx-1 do local t=dfhack.screen.readTile(x,y);row[#row+1]=t.ch>=32 and t.ch<127 and string.char(t.ch)or' 'end
  lines[#lines+1]=table.concat(row)
 end
 records[#records+1]={name=name,first=sheet.scroll_position_displayed_items,scrolling=sheet.scrolling_displayed_items,
  current_season=df.global.cur_season,current_fertilization=b.current_fertilization,max_fertilization=b.max_fertilization,seasonal_fertilization=b.farm_flags.seasonal_fertilize,positions=positions,count=#choices.rows+1,choices=choices,lines=lines,season=sheet.active_sub_tab,seasons=original,changed_tiles=changed}
 local f=assert(io.open(out..'/shot','w'));f:write(name);f:close()
 local limit=dfhack.getTickCount()+30000
 while true do local ack=io.open(out..'/ack-'..name);if ack then ack:close();break end
  assert(dfhack.getTickCount()<limit,'scroll capture timeout');script.sleep(1,'frames')end
end
shot('farm-scroll-initial')
for _,probe in ipairs{{'down','STANDARDSCROLL_DOWN'},{'up','STANDARDSCROLL_UP'},
 {'page-down','STANDARDSCROLL_PAGEDOWN'},{'page-up','STANDARDSCROLL_PAGEUP'},
 {'context-down','CONTEXT_SCROLL_DOWN'},{'context-up','CONTEXT_SCROLL_UP'},
 {'context-page-down','CONTEXT_SCROLL_PAGEDOWN'},{'context-page-up','CONTEXT_SCROLL_PAGEUP'}}do
 pointer(650,220);gui.simulateInput(view,probe[2]);shot('farm-scroll-'..probe[1])
end
for _,probe in ipairs{{'arrow-down',880,442},{'arrow-up',880,202},{'track-below',880,400},
 {'track-above',880,226}}do
 pointer(probe[2],probe[3]);gui.simulateInput(view,'_MOUSE_L');shot('farm-scroll-'..probe[1])
end
for _,probe in ipairs{{'bar-wheel','CONTEXT_SCROLL_DOWN'},{'bar-page','CONTEXT_SCROLL_PAGEDOWN'}}do
 pointer(880,250);gui.simulateInput(view,probe[2]);shot('farm-scroll-'..probe[1])
end
local old_lift=df.global.enabler.mouse_lbut_lift
for _,y in ipairs{184,208,220,280,400,436,460}do
 sheet.scroll_position_displayed_items=0;sheet.scrolling_displayed_items=false;settle()
 pointer(880,226);df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,{'_MOUSE_L','_MOUSE_L_DOWN'})
 pointer(880,y);gui.simulateInput(view,{'_MOUSE_L_DOWN'})
 df.global.enabler.mouse_lbut_lift=1;gui.simulateInput(view,{})
 shot('farm-scroll-drag-'..y)
end
df.global.enabler.mouse_lbut_lift=old_lift
pointer(20,20);gui.simulateInput(view,'CONTEXT_SCROLL_DOWN');shot('farm-scroll-outside')
for _,tile in ipairs(changed)do dfhack.maps.getTileBlock(tile.x,tile.y,tile.z).designation[tile.x%16][tile.y%16].whole=tile.before end
