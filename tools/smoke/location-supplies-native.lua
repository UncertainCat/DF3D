-- Owned paused native diagnostic. Numeric-entry state is never a runtime input.
local out,view,records=...
local gui=require('gui');local script=require('gui.script');local g=df.global.gps
local m=df.global.game.main_interface;local details=m.location_details
local function key(value)gui.simulateInput(view,value);view:render(dfhack.getTickCount())end
local function pixel(x,y)
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=y//12;key('_MOUSE_L')
end
local function capture(label,location)
 g.mouse_x=0;g.mouse_y=0;g.precise_mouse_x=0;g.precise_mouse_y=0
 view:render(dfhack.getTickCount());script.sleep(3,'frames')
 local contents=location:getContents();local _,base=df.sizeof(contents)
 local row={name=label,id=location.id,kind=df.abstract_building_type[location:getType()],open=details.open,
  text=details.desired_number_str,editing=details.entering_desired_number~=nil,values={},lines={}}
 local _,entry=df.sizeof(details:_field('entering_desired_number'));row.entry_rva=entry-dfhack.internal.getImageBase()
 local _,text_address=df.sizeof(details:_field('desired_number_str'));row.text_rva=text_address-dfhack.internal.getImageBase()
 if details.entering_desired_number then local _,address=df.sizeof(details.entering_desired_number);row.target_offset=address-base end
 for _,field in ipairs{'goblets','instruments','paper','splints','thread','cloth','crutches','powder','buckets','soap','copies'}do row.values[field]=contents['desired_'..field]end
 for y=0,g.dimy-1 do local bytes={};for x=0,g.dimx-1 do bytes[#bytes+1]=dfhack.screen.readTile(x,y).ch end;row.lines[#row.lines+1]=bytes end
 records[#records+1]=row
 local f=assert(io.open(out..'/shot.tmp','w'));f:write(label);f:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local limit=dfhack.getTickCount()+30000
 while true do local ack=io.open(out..'/ack-'..label);if ack then ack:close();break end;assert(dfhack.getTickCount()<limit,'capture timeout');script.sleep(1,'frames')end
 return row
end
local zone=assert(df.building.find(23))
m.bottom_mode_selected=-1;key('D_CIVZONE');m.civzone.cur_bld=zone;view:render(dfhack.getTickCount())
pixel(336,190)
local selector=m.location_selector;assert(selector.open,'native chooser did not open')
local choices={};for _,v in ipairs(selector.valid_ab)do choices[#choices+1]=v end
capture('chooser',assert(choices[1]))
for i,location in ipairs(choices)do
 local kind=df.abstract_building_type[location:getType()]
 local row_y=({INN_TAVERN=17,HOSPITAL=20,LIBRARY=20})[kind]
 if row_y then
  selector.scroll_position_location=0;view:render(dfhack.getTickCount())
  pixel(664,238+36*(i-1))
  if not details.open or details.selected_ab~=location then capture('unexpected-details',location)end
  assert(details.open and details.selected_ab==location,'native Details row did not open')
  capture(kind..'-baseline',location)
  local click_x
  for x=376,952,8 do
   pixel(x+4,row_y*12+6)
   if details.entering_desired_number then click_x=x+4;break end
   assert(details.open,'row probe closed Details')
  end
  assert(click_x,'no native numeric editor found: '..kind)
  local opened=capture(kind..'-edit-open',location);opened.pointer={click_x,row_y*12+6}
  key('STRING_A055');capture(kind..'-edit-digit',location)
  key('SELECT');capture(kind..'-edit-enter',location)
  pixel(click_x+32,row_y*12+6);capture(kind..'-plus',location)
  pixel(click_x+64,row_y*12+6);capture(kind..'-minus',location)
  pixel(click_x,row_y*12+6)
  key('STRING_A045');key('STRING_A097');capture(kind..'-invalid-input',location)
  for _,digit in ipairs{49,50,51,52,53,54,55,56,57,48}do key(string.format('STRING_A%03d',digit))end
  capture(kind..'-long-number',location)
  key('STRING_A000');capture(kind..'-backspace',location)
  key('_MOUSE_R');capture(kind..'-right-click',location)
  if not details.open then
   assert(selector.open,'numeric dismissal lost chooser')
   pixel(664,238+36*(i-1));assert(details.open and details.selected_ab==location)
  end
  pixel(click_x,row_y*12+6);key('STRING_A051');key('LEAVESCREEN');capture(kind..'-escape',location)
  if not details.open then pixel(664,238+36*(i-1));assert(details.open and details.selected_ab==location)end
  pixel(click_x,row_y*12+6)
  for n=1,3 do key('STRING_A057')end
  key('SELECT');pixel(click_x+32,row_y*12+6);capture(kind..'-plus-limit',location)
  pixel(click_x,row_y*12+6);key('STRING_A048');key('STRING_A000');capture(kind..'-empty-number',location)
  key('SELECT');pixel(click_x+64,row_y*12+6);capture(kind..'-minus-limit',location)
  key('LEAVESCREEN');assert(selector.open and not details.open,'Details did not return to chooser')
 end
end

assert(#records==43,"expected chooser and three complete numeric edit workflows")
