-- Native Rooms reference in a protected paused clone; no runtime menu inputs.
local unit,view,capture,out=...
local gui=require('gui');local json=require('json')
local g=df.global.gps;local sheet=df.global.game.main_interface.view_sheets
local frame=df.global.world.frame_counter
local function row(y)
 local text={};for x=0,g.dimx-1 do local p=dfhack.screen.readTile(x,y);text[#text+1]=p.ch>=32 and p.ch<=255 and string.char(p.ch)or' 'end
 return table.concat(text)
end
local function select(name)
 for y=15,16 do local x=row(y):find(name,1,true);if x then
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
  g.precise_mouse_x=(x-1)*8+4;g.precise_mouse_y=y*12+10;g.mouse_x=x-1;g.mouse_y=y
  df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
  df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
  return
 end end
 error('Missing native tab '..name)
end
assert(sheet.open and sheet.active_id==unit.id,'Expected creature sheet')
select('Rooms')
local result={unit_id=unit.id,tab=sheet.active_sub_tab,first=sheet.scroll_position_unit_room,rooms={},values={},lines={},offsets={}}
for _,id in ipairs(sheet.unit_room_civzone_id)do result.rooms[#result.rooms+1]=id end
for _,value in ipairs(sheet.unit_room_curval)do result.values[#result.values+1]=value end
local _,address=df.sizeof(sheet)
for _,field in ipairs{'unit_room_civzone_id','unit_room_curval','scroll_position_unit_room'}do local _,p=df.sizeof(sheet:_field(field));result.offsets[field]=p-address end
for y=17,g.dimy-1 do local text=dfhack.df2utf(row(y)):gsub('%s+$','');if text~=''then result.lines[#result.lines+1]={y=y,text=text}end end
capture('unit-rooms-native')
if os.getenv('DF3D_UNIT_ROOMS_VIEW')=='1' and result.rooms[1]>=0 then
 local room=assert(df.building.find(result.rooms[1]))
 local window={df.global.window_x,df.global.window_y,df.global.window_z}
 g.precise_mouse_x=868;g.precise_mouse_y=226;g.mouse_x=108;g.mouse_y=18
 df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
 result.recenter={room_id=room.id,target={x=room.centerx,y=room.centery,z=room.z},closed=not sheet.open,
  window={x=df.global.window_x,y=df.global.window_y,z=df.global.window_z}}
 assert(not sheet.open and df.global.window_z==room.z,'Room recenter did not close sheet and change level')
 capture('unit-rooms-recenter-native')
 -- Diagnostic restoration; product recenter owns only the viewer camera.
 df.global.window_x=window[1];df.global.window_y=window[2];df.global.window_z=window[3]
 sheet.open=true;view:render(dfhack.getTickCount())
end
select('Overview')
assert(df.global.pause_state and df.global.world.frame_counter==frame,'Rooms capture advanced simulation')
local file=assert(io.open(out..'/unit-rooms-native.json','w'));file:write(json.encode(result));file:close()
return result
