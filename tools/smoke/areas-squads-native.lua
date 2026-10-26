-- Protected native diagnostic only. Selector state is never a product input.
local out,view,records=...
local gui=require('gui');local script=require('gui.script');local g=df.global.gps
local main=df.global.game.main_interface
local base_zone
local function pixel(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y
 g.mouse_x=x//(g.screen_pixel_x//g.dimx);g.mouse_y=y//(g.screen_pixel_y//g.dimy)
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
end
local function mapclick(p)
 for y=0,g.dimy-1 do for x=0,g.dimx-1 do
  g.mouse_x=x;g.mouse_y=y;g.precise_mouse_x=x*(g.screen_pixel_x//g.dimx)+4;g.precise_mouse_y=y*(g.screen_pixel_y//g.dimy)+6
  local at=dfhack.gui.getMousePos(true)
  if at and at.x==p.x and at.y==p.y and at.z==p.z then pixel(g.precise_mouse_x,g.precise_mouse_y);return end
 end end
 error('squad fixture tile not visible')
end
local function capture(name,b)
 g.mouse_x=0;g.mouse_y=0;g.precise_mouse_x=0;g.precise_mouse_y=0
 for i=1,3 do view:render(dfhack.getTickCount());script.sleep(1,'frames')end
 local ui=main.squad_selector
 local row={name=name,zone=b.id,zone_type=tostring(b.type),open=ui.open,context=ui.context,
  target=ui.bld_id,scroll=ui.scroll_position,ids={},zone_assignments={},squads={},lines={}}
 for _,id in ipairs(ui.squad_id)do row.ids[#row.ids+1]=id end
 for _,r in ipairs(b.squad_room_info)do row.zone_assignments[#row.zone_assignments+1]={id=r.squad_id,mode=r.mode.whole}end
 for _,s in ipairs(df.global.world.squads.all)do if s.entity_id==df.global.plotinfo.group_id then
  local squad={id=s.id,entity=s.entity_id,alias=dfhack.df2utf(s.alias),rooms={},rack_combat={},rack_training={}}
  for _,r in ipairs(s.rooms)do squad.rooms[#squad.rooms+1]={id=r.building_id,mode=r.mode.whole}end
  for _,id in ipairs(s.rack_combat)do squad.rack_combat[#squad.rack_combat+1]=id end
  for _,id in ipairs(s.rack_training)do squad.rack_training[#squad.rack_training+1]=id end
  row.squads[#row.squads+1]=squad
 end end
 local _,address=df.sizeof(ui);row.selector_rva=address-dfhack.internal.getImageBase()
 row.equipment_update_flags=df.reinterpret_cast('uint32_t',dfhack.internal.getImageBase()+0x2399858).value
 for y=0,g.dimy-1 do
  local bytes={};for x=0,g.dimx-1 do bytes[#bytes+1]=dfhack.screen.readTile(x,y).ch end
  row.lines[#row.lines+1]=bytes
 end
 records[#records+1]=row
 local f=assert(io.open(out..'/shot.tmp','w'));f:write(name);f:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local limit=dfhack.getTickCount()+30000
 while true do local ack=io.open(out..'/ack-'..name,'r');if ack then ack:close();break end
  assert(dfhack.getTickCount()<limit,'capture timed out');script.sleep(1,'frames')end
 return row
end
local function mode(b,id)
 for _,r in ipairs(b.squad_room_info)do if r.squad_id==id then return r.mode.whole end end
 return 0
end
local function toggle(name,b,id,x,y,bit)
 local expected=mode(b,id)~bit
 pixel(x,y)
 local row=capture(name,b)
 assert(mode(b,id)==expected,'native zone toggle differs: '..name)
 local squad=assert(df.squad.find(id));local found=false
 for _,r in ipairs(squad.rooms)do if r.building_id==b.id then
  assert(expected~=0 and r.mode.whole==expected,'native reciprocal mode differs: '..name);found=true
 end end
 assert(found==(expected~=0),'native reciprocal presence differs: '..name)
 if expected==0 then
  local retained=false
  for _,r in ipairs(b.squad_room_info)do if r.squad_id==id then retained=true end end
  assert(retained,'native zero zone record missing: '..name)
 end
 row.expected_mode=expected
end
for _,kind in ipairs{'Barracks','ArcheryRange'}do
 local b
 for _,v in ipairs(df.global.world.buildings.other.ANY_ZONE)do if v.type==df.civzone_type[kind]then b=v;break end end
 if not b and kind=='ArcheryRange' then
  assert(base_zone)
  main.bottom_mode_selected=-1;gui.simulateInput(view,'D_CIVZONE')
  local p={x=base_zone.centerx,y=base_zone.centery,z=base_zone.z}
  dfhack.gui.revealInDwarfmodeMap(p,true);view:render(dfhack.getTickCount())
  pixel(208,394);mapclick(p);mapclick(p)
  b=assert(main.civzone.cur_bld);assert(b.type==df.civzone_type.ArcheryRange,'wrong native range fixture')
  pixel(304,114)
 end
 assert(b,'missing native '..kind..' fixture');base_zone=b
 main.bottom_mode_selected=-1;gui.simulateInput(view,'D_CIVZONE')
 dfhack.gui.revealInDwarfmodeMap({x=b.centerx,y=b.centery,z=b.z},true)
 -- Diagnostic selection avoids ambiguous overlapping zones; opening uses native input.
 main.civzone.cur_bld=b;view:render(dfhack.getTickCount())
 capture(kind..'-zone',b)
 pixel(336,154)
 local opened=capture(kind..'-picker',b)
 assert(opened.open and opened.target==b.id,'native squad picker did not open')
 assert(#opened.ids>=2,'squad fixture needs two squads')
 local columns=kind=='Barracks' and {{'sleep',816,1},{'train',848,2},{'equipment',880,4},{'individual',912,8}} or {{'train',912,2}}
 for _,column in ipairs(columns)do
  for n=1,2 do toggle(kind..'-first-'..column[1]..'-'..n,b,opened.ids[1],column[2],118,column[3])end
 end
 for _,column in ipairs(columns)do
  toggle(kind..'-second-'..column[1]..'-on',b,opened.ids[2],column[2],154,column[3])
 end
 for _,column in ipairs(columns)do
  toggle(kind..'-second-'..column[1]..'-off',b,opened.ids[2],column[2],154,column[3])
 end
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
 capture(kind..'-closed',b)
end
