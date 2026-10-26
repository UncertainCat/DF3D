-- Actual native picker input on the protected paused clone; never save.
local out,view,records=...
local gui=require('gui');local script=require('gui.script');local g=df.global.gps
local ui=df.global.game.main_interface.civzone
local function pixel(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//(g.screen_pixel_x//g.dimx);g.mouse_y=y//(g.screen_pixel_y//g.dimy)
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
end
local function mapclick(p)
 for y=0,g.dimy-1 do for x=0,g.dimx-1 do
  g.mouse_x=x;g.mouse_y=y;g.precise_mouse_x=x*(g.screen_pixel_x//g.dimx)+4;g.precise_mouse_y=y*(g.screen_pixel_y//g.dimy)+6
  local at=dfhack.gui.getMousePos(true)
  if at and at.x==p.x and at.y==p.y and at.z==p.z then pixel(g.precise_mouse_x,g.precise_mouse_y);return end
 end end
 error('owner fixture tile not visible')
end
local function capture(name)
 g.mouse_x=0;g.mouse_y=0
 for i=1,3 do view:render(dfhack.getTickCount());script.sleep(1,'frames')end
 local f=assert(io.open(out..'/shot.tmp','w'));f:write(name);f:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local limit=dfhack.getTickCount()+30000
 while not io.open(out..'/ack-'..name,'r')do assert(dfhack.getTickCount()<limit,'capture timed out');script.sleep(1,'frames')end
end
local function search(text)
 pixel(500,730)
 for byte in text:gmatch('.')do
  df.global.enabler.last_text_input[0]=byte:byte();df.global.enabler.last_text_input[1]=0
  gui.simulateInput(view,string.format('STRING_A%03d',byte:byte()))
  view:render(dfhack.getTickCount());script.sleep(2,'frames')
 end
end
local function count_owned(unit,id)
 local n=0;for _,b in ipairs(unit.owned_buildings)do if b.id==id then n=n+1 end end;return n
end
local base=assert(df.global.world.buildings.other.ANY_ZONE[0])
local function snapshot(name)
 local row={name=name,zones={},units={}}
 for _,z in ipairs(df.global.world.buildings.other.ANY_ZONE)do
  row.zones[#row.zones+1]={id=z.id,type=df.civzone_type[z.type],owner=z.assigned_unit_id,settings=z.zone_settings.whole.i1}
 end
 for _,u in ipairs(df.global.world.units.all)do
  if #u.owned_buildings>0 then
   local owned={};for _,b in ipairs(u.owned_buildings)do owned[#owned+1]=b.id end
   row.units[#row.units+1]={id=u.id,spouse=u.relationship_ids.Spouse,owned=owned}
  end
 end
 records[#records+1]=row
end
local p={x=base.centerx,y=base.centery,z=base.z}
df.global.game.main_interface.bottom_mode_selected=-1;gui.simulateInput(view,'D_CIVZONE')
dfhack.gui.revealInDwarfmodeMap(p,true);view:render(dfhack.getTickCount())
pixel(208,502);mapclick(p);mapclick(p)
local zone=assert(ui.cur_bld);assert(zone.type==df.civzone_type.Tomb)
pixel(304,114)
records[#records+1]={name='new-tomb',id=zone.id,owner=zone.assigned_unit_id,settings=zone.zone_settings.whole.i1}
pixel(336,154);capture('tomb-picker')
snapshot('before-assignment')
pixel(520,106)
assert(zone.assigned_unit_id>=0 and zone.zone_settings.whole.i1==3,'native tomb assignment failed')
local owner=zone.assigned_unit_id
snapshot('assigned');capture('tomb-assigned')
pixel(336,154);capture('tomb-picker-assigned');pixel(520,106)
assert(zone.assigned_unit_id>=0 and zone.assigned_unit_id~=owner,'current owner was not excluded')
snapshot('replacement-owner')
-- Tomb context skips the native Remove assignment entry; record its tail.
pixel(336,154)
for i=1,250 do pixel(944,678)end
capture('tomb-picker-bottom')

gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
pixel(208,502);mapclick(p);mapclick(p)
local second=assert(ui.cur_bld);assert(second~=zone and second.type==df.civzone_type.Tomb)
pixel(304,114);pixel(336,154);pixel(520,106)
assert(second.assigned_unit_id==owner,'native second tomb assignment failed')
-- The first tomb currently belongs to the mayor. Select her on the second
-- tomb to exercise removal of her existing tomb, regardless of other rooms.
pixel(336,154);search('mayor')
view:render(dfhack.getTickCount());capture('tomb-transfer-candidate');pixel(520,106)
snapshot('transfer-result')
assert(second.assigned_unit_id>=0 and zone.assigned_unit_id==-1,'native tomb transfer failed')
snapshot('transferred');capture('tomb-transferred')
local first_unit=assert(df.unit.find(owner));local spouse=assert(df.unit.find(second.assigned_unit_id))
local old_first,old_spouse=first_unit.relationship_ids.Spouse,spouse.relationship_ids.Spouse
first_unit.relationship_ids.Spouse=spouse.id;spouse.relationship_ids.Spouse=first_unit.id
local ok,why=pcall(function()
 pixel(55,320);mapclick(p);mapclick(p)
 local bedroom=assert(ui.cur_bld);assert(bedroom.type==df.civzone_type.Bedroom)
 pixel(304,114);pixel(336,154);capture('bedroom-picker')
 records[#records+1]={name='bedroom-created',id=bedroom.id,fixture_owner=owner,fixture_spouse=spouse.id}
 search('king');capture('bedroom-candidate');pixel(520,142)
 assert(bedroom.assigned_unit_id==owner,'native bedroom assignment failed')
 assert(count_owned(first_unit,bedroom.id)==1 and count_owned(spouse,bedroom.id)==1,'native spouse membership failed')
 snapshot('bedroom-assigned');capture('bedroom-assigned')
 pixel(336,154);capture('bedroom-picker-assigned');pixel(520,106)
 assert(bedroom.assigned_unit_id==-1,'native bedroom clear failed')
 assert(count_owned(first_unit,bedroom.id)==0 and count_owned(spouse,bedroom.id)==0,'native spouse clear failed')
 snapshot('bedroom-cleared');capture('bedroom-cleared')
end)
first_unit.relationship_ids.Spouse=old_first;spouse.relationship_ids.Spouse=old_spouse
assert(ok,why)
