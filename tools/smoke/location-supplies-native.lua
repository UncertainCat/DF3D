-- Owned paused native diagnostic. Numeric-entry state is never a runtime input.
local out,view,records=...
local gui=require('gui');local script=require('gui.script');local g=df.global.gps
local m=df.global.game.main_interface;local details=m.location_details
local function key(value)gui.simulateInput(view,value);view:render(dfhack.getTickCount())end
local function pixel(x,y)
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=y//12;key('_MOUSE_L')
end
local function capture(label,location,keep_pointer)
 if not keep_pointer then g.mouse_x=0;g.mouse_y=0;g.precise_mouse_x=0;g.precise_mouse_y=0 end
 view:render(dfhack.getTickCount());if not keep_pointer then script.sleep(3,'frames')end
 local contents=location:getContents();local _,base=df.sizeof(contents)
 local row={name=label,id=location.id,kind=df.abstract_building_type[location:getType()],open=details.open,
  text=details.desired_number_str,editing=details.entering_desired_number~=nil,values={},lines={}}
 local _,entry=df.sizeof(details:_field('entering_desired_number'));row.entry_rva=entry-dfhack.internal.getImageBase()
 local _,text_address=df.sizeof(details:_field('desired_number_str'));row.text_rva=text_address-dfhack.internal.getImageBase()
 if details.entering_desired_number then local _,address=df.sizeof(details.entering_desired_number);row.target_offset=address-base end
 for _,field in ipairs{'goblets','instruments','paper','splints','thread','cloth','crutches','powder','buckets','soap','copies'}do row.values[field]=contents['desired_'..field]end
 for y=0,g.dimy-1 do local bytes={};for x=0,g.dimx-1 do bytes[#bytes+1]=dfhack.screen.readTile(x,y).ch end;row.lines[#row.lines+1]=bytes end
 if keep_pointer then
  row.hover=m.current_hover;row.hover_name=df.main_hover_instruction[m.current_hover]
  row.hover_enabled=m.hover_instructions_on;row.displayed_hover=m.last_displayed_hover_inst
 end
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

local fields={
 INN_TAVERN={{'goblets',17,1},{'instruments',20,1}},
 TEMPLE={{'instruments',23,1}},
 LIBRARY={{'copies',20,1},{'paper',26,1}},
 HOSPITAL={{'thread',20,15000},{'cloth',23,10000},{'splints',26,1},{'crutches',29,1},
  {'powder',32,150},{'buckets',35,1},{'soap',38,150}},
}
local field_cases=0
for i,location in ipairs(choices)do
 local kind=df.abstract_building_type[location:getType()]
 if fields[kind]then
  pixel(664,238+36*(i-1));assert(details.open and details.selected_ab==location,'field Details identity')
  local contents=location:getContents()
  for _,field in ipairs(fields[kind])do
   field_cases=field_cases+1
   local name,row_y,scale=table.unpack(field);local key_name='desired_'..name
   local saved=contents[key_name];local prefix=kind..'-'..location.id..'-'..name
   local click_x
   for x=376,952,8 do pixel(x+4,row_y*12+6);if details.entering_desired_number then click_x=x+4;break end end
   assert(click_x,'field editor absent: '..prefix)
   local size,address=df.sizeof(contents);local _,target=df.sizeof(contents:_field(key_name))
   local _,actual=df.sizeof(details.entering_desired_number);assert(actual==target,'numeric icon selected wrong field')
   local opened=capture(prefix..'-open',location);opened.field=name;opened.scale=scale;opened.pointer={click_x,row_y*12+6}
   local quantities={goblets=0,instruments=1,paper=2,splints=3,thread=4,cloth=5,crutches=6,powder=7,buckets=8,soap=9,copies=10}
   local function bridge_compare(observed,before_value,mode,value)
    local expected=df.new('uint8_t',size);dfhack.internal.memmove(expected,address,size)
    contents[key_name]=before_value
    local guards={}
    for _,object in ipairs{m,g}do
     local n,at=df.sizeof(object);local bytes=df.new('uint8_t',n);dfhack.internal.memmove(bytes,at,n)
     guards[#guards+1]={bytes=bytes,address=at,size=n}
    end
    local site=dfhack.world.getCurrentSite().id
    local text,code=dfhack.run_command_silent('df3d','location-details-read',tostring(site),tostring(location.id));assert(code==0,text)
    local read=require('json').decode(text);assert(read.valid and type(read.revision)=='string','missing quantity revision')
    text,code=dfhack.run_command_silent('df3d','location-quantity-edit',tostring(site),tostring(location.id),tostring(quantities[name]),tostring(mode),tostring(value),read.revision)
    assert(code==0,text);local result=require('json').decode(text);assert(result.outcome==1,'bridge quantity edit refused')
    assert(dfhack.internal.memcmp(expected,address,size)==0,'bridge/native contents differ: '..observed.name)
    for _,guard in ipairs(guards)do
     assert(dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)==0,'quantity edit changed native UI/gps')
     df.delete(guard.bytes)
    end
    df.delete(expected);observed.bridge={outcome=result.outcome,contents_match=true,ui_gps_unchanged=true}
   end
   key('STRING_A054');local set=capture(prefix..'-set-six',location);key('SELECT')
   assert(contents[key_name]==6*scale,'native field scale differs')
   bridge_compare(set,saved,0,6)
   -- Rejected/stale semantic intents must leave both simulation and UI bytes alone.
   local site=dfhack.world.getCurrentSite().id
   local text,code=dfhack.run_command_silent('df3d','location-details-read',tostring(site),tostring(location.id))
   assert(code==0,text);local revision=require('json').decode(text).revision
   local rejected={}
   local function reject(label,q,mode,value,rev,expected,site_id,location_id)
    local guards={}
    for _,object in ipairs{contents,m,g}do
     local n,at=df.sizeof(object);local bytes=df.new('uint8_t',n);dfhack.internal.memmove(bytes,at,n)
     guards[#guards+1]={bytes=bytes,address=at,size=n}
    end
    local output,status=dfhack.run_command_silent('df3d','location-quantity-edit',tostring(site_id or site),tostring(location_id or location.id),tostring(q),tostring(mode),tostring(value),rev)
    assert(status==0,output);assert(require('json').decode(output).outcome==expected,label)
    for _,guard in ipairs(guards)do
     assert(dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)==0,'rejection mutated bytes: '..label);df.delete(guard.bytes)
    end
    rejected[#rejected+1]={name=label,outcome=expected,contents_ui_gps_unchanged=true}
   end
   local q=quantities[name]
   reject('negative',q,0,-1,revision,0)
   reject('too-large',q,0,1000,revision,0)
   reject('step-payload',q,1,1,revision,0)
   reject('zero-revision',q,0,6,'0',0)
   reject('wrong-kind',kind=='HOSPITAL' and 0 or 3,0,6,revision,0)
   reject('missing-site',q,0,6,revision,0,-1)
   reject('missing-location',q,0,6,revision,0,nil,2147483647)
   contents[key_name]=7*scale
   reject('stale',q,0,6,revision,2)
   contents[key_name]=6*scale;set.rejections=rejected
   local before=df.new('uint8_t',size);dfhack.internal.memmove(before,address,size)
   local function action(label,value,delta)
    -- Owned diagnostic scalar seeding isolates partial raw-unit behavior.
    contents[key_name]=value
    pixel(click_x+(delta>0 and 32 or 64),row_y*12+6)
    local observed=capture(prefix..'-'..label,location)
    observed.field=name;observed.scale=scale;observed.before_raw=value;observed.delta=delta
    observed.other_byte_changes={}
    for offset=0,size-1 do
     if (offset<target-address or offset>=target-address+4) and before[offset]~=df.reinterpret_cast('uint8_t',address+offset).value then
      observed.other_byte_changes[#observed.other_byte_changes+1]=offset
     end
    end
    bridge_compare(observed,value,delta>0 and 1 or 2,0)
   end
   action('partial-plus',2*scale+(scale>1 and 1 or 0),1)
   action('partial-minus',2*scale+(scale>1 and 1 or 0),-1)
   action('near-upper-plus',999*scale-1,1)
   action('near-zero-minus',1,-1)
   df.delete(before);contents[key_name]=saved
  end
  key('LEAVESCREEN');assert(selector.open and not details.open)
 end
end
assert(field_cases==13 and #records==121,'incomplete all-field numeric coverage')

-- Numeric focus behavior used by the viewer-owned entry component.
local tavern
local index
for i,location in ipairs(choices)do if df.abstract_building_type[location:getType()]=='INN_TAVERN' then tavern=location;index=i;break end end
assert(tavern);pixel(664,238+36*(index-1));assert(details.open and details.selected_ab==tavern)
local function point(field)
 for _,row in ipairs(records)do if row.name=='INN_TAVERN-'..tavern.id..'-'..field..'-open' then return table.unpack(row.pointer)end end
 error('missing numeric pointer reference')
end
local x,y=point('goblets');local ix,iy=point('instruments')
local function record(name)capture('editor-'..name,tavern)end
pixel(x,y);key('STRING_A049');key('STRING_A050');record('twelve')
pixel(x,y);record('same-number-icon')
key('STRING_A051');pixel(x+32,y);record('plus-during-entry')
key('STRING_A052');record('digit-after-plus')
pixel(x+64,y);record('minus-during-entry')
pixel(ix,iy);record('different-number-icon')
key('STRING_A053');pixel(900,190);record('blank-panel-click')
key('STRING_A054');record('digit-after-blank')
key('CURSOR_LEFT');key('STRING_A055');record('left-then-digit')
key('SELECT');record('enter-finishes')
key('LEAVESCREEN');assert(selector.open and not details.open)
assert(#records==131,'incomplete numeric focus reference')

-- Hover is read only after the ordinary native cold delay; no runtime scratch use.
local hover_cases=0
for i,location in ipairs(choices)do
 local kind=df.abstract_building_type[location:getType()]
 if fields[kind]then
  pixel(664,238+36*(i-1));assert(details.open and details.selected_ab==location)
  for _,field in ipairs(fields[kind])do
   local prefix=kind..'-'..location.id..'-'..field[1]
   local position
   for _,row in ipairs(records)do if row.name==prefix..'-open' then position=row.pointer;break end end
   assert(position)
   for action=0,2 do
    local hx,hy=position[1]+12+32*action,position[2]
    local deadline=dfhack.getTickCount()+900
    repeat
     df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
     g.precise_mouse_x=hx;g.precise_mouse_y=hy;g.mouse_x=hx//8;g.mouse_y=hy//12
     gui.simulateInput(view,{});view:render(dfhack.getTickCount());script.sleep(1,'frames')
    until dfhack.getTickCount()>=deadline
    local row=capture(prefix..'-hover-'..action,location,true)
    row.pointer={hx,hy};row.field=field[1];row.action=action
    row.hover_text={}
    for y=1,18 do
     local chars={};for x=g.dimx-24,g.dimx-1 do local ch=row.lines[y][x+1];chars[#chars+1]=ch>=33 and ch<=255 and string.char(ch) or ' 'end
     row.hover_text[#row.hover_text+1]=table.concat(chars):gsub('%s+$','')
    end
    hover_cases=hover_cases+1
   end
  end
  key('LEAVESCREEN');assert(selector.open and not details.open)
 end
end
assert(hover_cases==39 and #records==170,'incomplete quantity hover reference')

pixel(664,238+36*(index-1));assert(details.open and details.selected_ab==tavern)
local deadline=dfhack.getTickCount()+900
repeat
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=944;g.precise_mouse_y=82;g.mouse_x=118;g.mouse_y=6
 gui.simulateInput(view,{});view:render(dfhack.getTickCount());script.sleep(1,'frames')
until dfhack.getTickCount()>=deadline
-- Reapply after the frame wait: SDL can reset the hidden-desktop pointer.
g.precise_mouse_x=944;g.precise_mouse_y=82;g.mouse_x=118;g.mouse_y=6
gui.simulateInput(view,{})
local control=capture('hover-rename-positive-control',tavern,true)
assert(control.hover==279 and control.hover_enabled,'native rename hover positive control failed')

pixel(x,y);key('STRING_A052');key('STRING_A050')
capture('physical-escape-before',tavern)
local f=assert(io.open(out..'/owner-input-request.tmp','w'));f:write('escape');f:close()
assert(os.rename(out..'/owner-input-request.tmp',out..'/owner-input-request'))
local limit=dfhack.getTickCount()+30000
while true do
 local ack=io.open(out..'/owner-input-ack','r');if ack then ack:close();break end
 assert(dfhack.getTickCount()<limit,'window Escape timeout');script.sleep(1,'frames')
end
assert(os.remove(out..'/owner-input-ack'));script.sleep(5,'frames')
local escaped=capture('physical-escape-after',tavern)
escaped.top_screen=tostring(dfhack.gui.getCurViewscreen()._type)
escaped.selector_open=selector.open
assert(tavern:getContents().desired_goblets==42,'Escape changed typed quantity')
assert(#records==173,'incomplete hover and window Escape reference')
