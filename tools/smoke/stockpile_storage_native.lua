-- Protected owned lane only: pause, disable autosave, preserve save manifests,
-- and close without saving. Mutates the first pile (or ZoneRename zone) through native clicks.
-- Run with an output directory; result.json is published atomically.
local out,repaint,gestures,eligibility_case,test_predicates,test_links,test_rename,test_tooltips,test_rename_text,test_zone_rename,test_zone_gather,test_zone_defaults,test_multi_discovery,test_zone_owner,test_zone_animals,test_zone_squads,test_location_supplies,test_location_names=...
require('gui.script').start(function()
 local records={}
 local ok,why=pcall(function()
  local json=require('json');local gui=require('gui');local g=df.global.gps
  local view=dfhack.gui.getDFViewscreen(true)
  assert(df.global.pause_state);local frame=df.global.world.frame_counter
  assert(dfhack.run_command('disable','overlay')==0)
  if os.getenv('DF3D_JUSTICE_NATIVE')=='1' then
   local source=debug.getinfo(1,'S').source:sub(2):gsub('stockpile_storage_native.lua$','justice-native.lua')
   assert(loadfile(source))(out,view,records)
   assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
   return
  end
  if os.getenv('DF3D_OBJECTS_NATIVE')=='1' then
   local source=debug.getinfo(1,'S').source:sub(2):gsub('stockpile_storage_native.lua$','objects-native.lua')
   assert(loadfile(source))(out,view,records)
   assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
   return
  end
  if os.getenv('DF3D_NOBLES_NATIVE')=='1' then
   local source=debug.getinfo(1,'S').source:sub(2):gsub('stockpile_storage_native.lua$','nobles-native.lua')
   assert(loadfile(source))(out,view,records)
   assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
   return
  end
  if os.getenv('DF3D_PLACES_NATIVE')=='1' then
   local source=debug.getinfo(1,'S').source:sub(2):gsub('stockpile_storage_native.lua$','places-native.lua')
   assert(loadfile(source))(out,view,records)
   assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
   return
  end
  if os.getenv('DF3D_TASKS_NATIVE')=='1' then
   local source=debug.getinfo(1,'S').source:sub(2):gsub('stockpile_storage_native.lua$','tasks-native.lua')
   assert(loadfile(source))(out,view,records)
   assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
   return
  end
  if os.getenv('DF3D_STOCKS_NATIVE')=='1' then
   local source=debug.getinfo(1,'S').source:sub(2):gsub('stockpile_storage_native.lua$','stocks-native.lua')
   assert(loadfile(source))(out,view,records)
   assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
   return
  end
  if os.getenv('DF3D_STANDING_ORDERS_NATIVE')=='1' then
   local source=debug.getinfo(1,'S').source:sub(2):gsub('stockpile_storage_native.lua$','standing-orders-native.lua')
   assert(loadfile(source))(out,view,records)
   assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
   return
  end
  if os.getenv('DF3D_RESIDENTS_REFERENCE')=='1' then
   local source=debug.getinfo(1,'S').source:sub(2):gsub('stockpile_storage_native.lua$','residents-native.lua')
   assert(loadfile(source))(out,view,records)
   if os.getenv('DF3D_WORK_DETAILS_NATIVE')=='1' and os.getenv('DF3D_WORK_DETAILS_SETTINGS')=='1' and os.getenv('DF3D_WORK_DETAILS_SETTINGS_EFFECTS')=='1' and os.getenv('DF3D_WORK_DETAILS_SETTINGS_SIMULATION')=='1' then
    local evidence
    for _,record in ipairs(records)do if record.name=='work-details-simulation' then assert(not evidence);evidence=record end end
    assert(evidence and evidence.start_tick==frame and evidence.end_tick==df.global.world.frame_counter,'Missing bounded settings simulation evidence')
    assert(df.global.pause_state and evidence.end_tick-frame>=10 and evidence.end_tick-frame<=60,'Settings simulation outside its bounded interval')
   else
    assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
   end
   return
  end
  if os.getenv('DF3D_WORK_ORDER_ARTWORK_REFERENCE')=='1' then
   local source=debug.getinfo(1,'S').source:sub(2):gsub('stockpile_storage_native.lua$','work-order-artwork-native.lua')
   assert(loadfile(source))(out,view,records)
   assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
   return
  end
  if os.getenv('DF3D_WORK_ORDER_DYE_REFERENCE')=='1' then
   local source=debug.getinfo(1,'S').source:sub(2):gsub('stockpile_storage_native.lua$','work-order-dye-native.lua')
   assert(loadfile(source))(out,view,records)
   assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
   return
  end
  local farm_marker=io.open(out..'/farm-discovery')
  if farm_marker then
   farm_marker:close()
   local source=debug.getinfo(1,'S').source:sub(2):gsub('stockpile_storage_native.lua$','farm-native.lua')
   assert(loadfile(source))(out,view,records)
   local progress=io.open(out..'/farm-fertilization-progress')
   if progress then progress:close();assert(df.global.pause_state,'progress scope did not pause')
   else assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')end
   return
  end
  if test_location_names then
   local source=debug.getinfo(1,'S').source:sub(2):gsub('stockpile_storage_native.lua$','location-names-native.lua')
   assert(loadfile(source))(out,view,records)
   assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
   return
  end
  if test_location_supplies then
   local source=debug.getinfo(1,'S').source:sub(2):gsub('stockpile_storage_native.lua$','location-supplies-native.lua')
   assert(loadfile(source))(out,view,records)
   assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
   return
  end
  if test_zone_squads then
   local source=debug.getinfo(1,'S').source:sub(2):gsub('stockpile_storage_native.lua$','areas-squads-native.lua')
   assert(loadfile(source))(out,view,records)
   assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
   return
  end
  if test_zone_animals then
   local source=debug.getinfo(1,'S').source:sub(2):gsub('stockpile_storage_native.lua$','areas-animals-native.lua')
   assert(loadfile(source))(out,view,records)
   assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
   return
  end
  if test_zone_owner then
   local source=debug.getinfo(1,'S').source:sub(2):gsub('stockpile_storage_native.lua$','areas-owner-native.lua')
   assert(loadfile(source))(out,view,records)
   assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
   return
  end
  if test_multi_discovery then
   local source=debug.getinfo(1,'S').source:sub(2):gsub('stockpile_storage_native.lua$','areas-multi-discovery-native.lua')
   assert(loadfile(source))(out,view,records)
   assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
   return
  end
  local b=assert((test_zone_rename or test_zone_gather or test_zone_defaults) and df.global.world.buildings.other.ANY_ZONE[0] or df.global.world.buildings.other.STOCKPILE[0])
  local pile_id=b.id
  if test_predicates then
   local guards={}
   local function guard(address,size)
    local copy=df.new('uint8_t',size);dfhack.internal.memmove(copy,address,size)
    guards[#guards+1]={copy=copy,address=address,size=size}
   end
   local base=dfhack.internal.getImageBase()
   for _,range in ipairs{{0x234e990,0x6180},{0x2131b30,40},{0x2159084,2},{0x18adf98,8}}do guard(base+range[1],range[2])end
   local size,address=df.sizeof(df.global.game.main_interface);guard(address,size)
   size,address=df.sizeof(b);guard(address,size)
   local allowed={}
   for first=0,65535,1024 do
    local text,code=dfhack.run_command_silent('df3d','stockpile-tile-types-read',tostring(first),'1024');assert(code==0,text)
    local result=json.decode(text);assert(result.first==first and #result.allowed==1024)
    for index,value in ipairs(result.allowed)do assert(type(value)=='boolean');if value then allowed[#allowed+1]=first+index-1 end end
   end
   for _,args in ipairs{{'-1','1'},{'65536','1'},{'0','0'},{'0','1025'},{'65535','2'}}do
    local _,code=dfhack.run_command_silent('df3d','stockpile-tile-types-read',args[1],args[2]);assert(code~=0,'invalid range accepted')
   end
   for _,g in ipairs(guards)do assert(dfhack.internal.memcmp(g.copy,g.address,g.size)==0,'predicate changed RNG/UI/source');df.delete(g.copy)end
   records[#records+1]={name='native-tile-predicates',tested=65536,allowed=allowed,guards_unchanged=true}
  end
  local point={x=b.centerx,y=b.centery,z=b.z}
  if test_zone_rename or test_zone_gather or test_zone_defaults then df.global.game.main_interface.bottom_mode_selected=-1;gui.simulateInput(view,'D_CIVZONE')
  else gui.simulateInput(view,'D_STOCKPILES');df.global.game.main_interface.bottom_mode_selected=-1 end
  dfhack.gui.revealInDwarfmodeMap(point,true);view:render(dfhack.getTickCount())
  local function click(x,y)
   g.mouse_x=x;g.mouse_y=y;g.precise_mouse_x=x*(g.screen_pixel_x//g.dimx)+4;g.precise_mouse_y=y*(g.screen_pixel_y//g.dimy)+6
   gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
  end
  local found=false;local map_x,map_y
  for y=0,g.dimy-1 do for x=0,g.dimx-1 do
   g.mouse_x=x;g.mouse_y=y;g.precise_mouse_x=x*(g.screen_pixel_x//g.dimx)+4;g.precise_mouse_y=y*(g.screen_pixel_y//g.dimy)+6
   local p=dfhack.gui.getMousePos(true)
   if p and p.x==point.x and p.y==point.y and p.z==point.z then map_x=x;map_y=y;click(x,y);found=true;break end
  end if found then break end end
  assert(found,'no pile pointer');require('gui.script').sleep(2,'frames');view:render(dfhack.getTickCount())
  if test_zone_rename or test_zone_gather or test_zone_defaults then b=assert(df.global.game.main_interface.civzone.cur_bld,'no selected zone');pile_id=b.id end
  local function capture(name,keep_pointer)
   if not keep_pointer then g.mouse_x=0;g.mouse_y=0 end
   for i=1,3 do if keep_pointer then keep_pointer()end;view:render(dfhack.getTickCount());require('gui.script').sleep(1,'frames')end
   if keep_pointer then keep_pointer();view:render(dfhack.getTickCount())end
   local lines={};for y=0,g.dimy-1 do local line={};for x=0,g.dimx-1 do local t=dfhack.screen.readTile(x,y);line[#line+1]=(t.ch>=32 and t.ch<127)and string.char(t.ch)or' ' end;lines[#lines+1]=table.concat(line)end
   local f=assert(io.open(out..'/'..name..'.txt','w'));f:write(table.concat(lines,'\n'));f:close()
   local alive=df.building.find(pile_id)
   records[#records+1]=alive and ((test_zone_rename or test_zone_gather or test_zone_defaults) and {name=name,id=alive.id,zone_type=df.civzone_type[alive.type]} or {name=name,barrels=alive.storage.max_barrels,bins=alive.storage.max_bins,wheelbarrows=alive.storage.max_wheelbarrows}) or {name=name,removed=true}
   -- Tooltip text/state is sampled immediately after native render. The hidden
   -- desktop's next SDL poll can replace the pointer before a GPU screenshot.
   if test_tooltips and keep_pointer then return end
   f=assert(io.open(out..'/shot.tmp','w'));f:write(name);f:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
   local limit=dfhack.getTickCount()+30000
   while not io.open(out..'/ack-'..name,'r')do assert(dfhack.getTickCount()<limit,'capture timeout');if keep_pointer then keep_pointer();view:render(dfhack.getTickCount())end;require('gui.script').sleep(1,'frames')end
  end
  capture('pile')
  if test_zone_defaults then
   local ui=df.global.game.main_interface.civzone
   local resize_marker=io.open(out..'/picker-resize','r')
   if resize_marker then
    resize_marker:close()
    for _,size in ipairs{'small','wide','default'}do
     local f=assert(io.open(out..'/owner-input-request.tmp','w'));f:write('name-resize-'..size);f:close()
     assert(os.rename(out..'/owner-input-request.tmp',out..'/owner-input-request'))
     local limit=dfhack.getTickCount()+30000
     while true do
      local ack=io.open(out..'/owner-input-ack','r');if ack then ack:close();break end
      assert(dfhack.getTickCount()<limit,'palette resize timeout');require('gui.script').sleep(1,'frames')
     end
     assert(os.remove(out..'/owner-input-ack'));require('gui.script').sleep(5,'frames')
     capture('zone-palette-'..size)
     records[#records+1]={name='zone-palette-resize',size=size,dimx=g.dimx,dimy=g.dimy,
      pixel_width=g.screen_pixel_x,pixel_height=g.screen_pixel_y,selected_zone_id=ui.cur_bld and ui.cur_bld.id or -1}
    end
    assert(df.global.pause_state and df.global.world.frame_counter==frame,'palette resize advanced simulation')
    return
   end
   for _,entry in ipairs{{'Pen',7,33,1},{'Pond',7,36,2},{'Tomb',26,42,1},{'PlantGathering',26,45,7},{'ArcheryRange',26,33,1}} do
    click(entry[2],entry[3]);click(map_x,map_y);click(map_x,map_y)
    b=assert(ui.cur_bld,'no created zone');pile_id=b.id
    assert(b.type==df.civzone_type[entry[1]],'wrong created zone type '..entry[1])
    click(38,9)
    local raw=b.zone_settings.whole
    assert(raw.i1==entry[4],entry[1]..' default mismatch: '..raw.i1)
    records[#records+1]={name='defaults-'..entry[1],id=b.id,type=entry[1],first=raw.i1,second=raw.i2,
     active=b.spec_sub_flag.active,frame=df.global.world.frame_counter}
    assert(df.global.pause_state and df.global.world.frame_counter==frame)
    capture('defaults-'..entry[1])
    if os.getenv('DF3D_ZONE_SETTINGS_AUDIT')=='1'then
     local original_first,original_second=raw.i1,raw.i2
     local function memberships()
      local rows={}
      for _,building in ipairs(df.global.world.buildings.all)do
       local related={};for _,parent in ipairs(building.relations)do related[#related+1]=parent.id end
       local contained={};if df.building_civzonest:is_instance(building)then for _,child in ipairs(building.contained_buildings)do contained[#contained+1]=child.id end end
       rows[#rows+1]={id=building.id,related=related,contained=contained}
      end
      return json.encode(rows)
     end
     local before=memberships()
     local cases=entry[1]=='Pond'and {34,38,34}
      or entry[1]=='Tomb'and {34,34,38,38}
      or entry[1]=='ArcheryRange'and {7,11,15,19}or{}
     for _,x in ipairs(cases)do
      local before_first,before_second=raw.i1,raw.i2
      click(x,12)
      assert(memberships()==before,'Native zone setting changed room membership')
      records[#records+1]={name='setting-'..entry[1],x=x,before_first=before_first,before_second=before_second,first=raw.i1,second=raw.i2,memberships_unchanged=true}
     end
     raw.i1=original_first;raw.i2=original_second
    end
    if entry[1]=='Tomb'and os.getenv('DF3D_TOMB_OWNER_SETTINGS_AUDIT')=='1'then
     local owner,first,second=b.assigned_unit_id,raw.i1,raw.i2
     local unit=assert(df.global.world.units.active[0])
     assert(owner==-1,'Tomb fixture already assigned')
     b.assigned_unit_id=unit.id
     capture('tomb-assigned-settings')
     click(34,12);click(38,12)
     assert(raw.i1==first and raw.i2==second,'Assigned Tomb burial permissions changed')
     records[#records+1]={name='tomb-assigned-settings',owner=unit.id,first=raw.i1,second=raw.i2,unchanged=true}
     if os.getenv('DF3D_TOMB_OWNER_ACCESS_AUDIT')=='1'then
      local flags=unit.flags1.whole
      unit.flags1.inactive=true
      capture('tomb-inactive-owner')
      local selector=df.global.game.main_interface.unit_selector
      assert(not selector.flag.VISIBILITY_ACTIVE,'Owner selector already open')
      click(42,12)
      assert(not selector.flag.VISIBILITY_ACTIVE,'Inactive Tomb owner opened assignment')
      records[#records+1]={name='tomb-inactive-owner',owner=unit.id,flags=unit.flags1.whole,selector_open=false}
      unit.flags1.whole=flags
      capture('tomb-owner-restored')
     end
     if os.getenv('DF3D_ZONE_OWNER_ROWS_AUDIT')=='1'then
      local old_type,flags,spouse=b.type,unit.flags1.whole,unit.relationship_ids.Spouse
      local other=assert(df.global.world.units.active[1]);assert(other.id~=unit.id)
      local function observe(label)
       view:render(dfhack.getTickCount())
       local text,code=dfhack.run_command_silent('df3d','zone-selected-owners-read',tostring(b.id));assert(code==0,text)
       local rows=json.decode(text)
       for index,row in ipairs(rows)do
        for col=1,25 do
         assert(dfhack.screen.readTile(10+col,12+3*(index-1)).ch==(row.caption[col] or 32),'Selected owner caption differs '..label)
        end
        if index==1 then
         local status={};for col=1,8 do status[col]=dfhack.screen.readTile(10+col,13).ch end
         local shown=table.concat(status,',')==table.concat({68,101,99,101,97,115,101,100},',')
         assert(shown==(#row.status>0),'Selected owner status differs '..label)
        end
       end
       records[#records+1]={name='selected-owners-'..label,rows=rows,type=df.civzone_type[b.type]}
       capture('selected-owners-'..label)
      end
      unit.flags1.whole=flags&(~0x502);observe('living')
      for _,bits in ipairs{2,0x102,0x402}do unit.flags1.whole=(flags&(~0x502))|bits;observe('flags-'..bits)end
      unit.flags1.whole=flags;unit.relationship_ids.Spouse=other.id
      for _,kind in ipairs{'Bedroom','Office','DiningHall'}do b.type=df.civzone_type[kind];observe(kind..'-spouse')end
      b.type=old_type;unit.flags1.whole=flags;unit.relationship_ids.Spouse=spouse
      observe('restored')
     end
     b.assigned_unit_id=owner
     capture('tomb-unassigned-settings')
    end
    if os.getenv('DF3D_ZONE_ACTIVE_AUDIT')=='1'then
     local original_first,original_second=raw.i1,raw.i2
     local function active_snapshot(label)
      local children={};for _,child in ipairs(b.contained_buildings)do children[#children+1]=child.id end
      records[#records+1]={name='active-'..entry[1]..'-'..label,id=b.id,type=entry[1],active=b.spec_sub_flag.active,first=raw.i1,second=raw.i2,children=children}
     end
     active_snapshot('before');click(38,9);assert(not b.spec_sub_flag.active,'Native suspend did not disable zone');active_snapshot('off')
     click(38,9);assert(b.spec_sub_flag.active,'Native suspend did not restore zone');active_snapshot('on')
     raw.i1=original_first;raw.i2=original_second
    end
   end
   -- Controlled native oracle: only the target-center list is provisioned.
   -- Rectangle creation and direction selection still run through actual clicks.
   local targets=df.global.world.buildings.other.ARCHERY_TARGET
   local _,target_address=df.sizeof(targets)
   assert(target_address==dfhack.internal.getImageBase()+0x23eec60,'native target list identity changed')
   local target=df.building_archerytargetst:new()
   targets:insert('#',target)
   local function map_click(tx,ty)
    for sy=0,g.dimy-1 do for sx=0,g.dimx-1 do
     g.mouse_x=sx;g.mouse_y=sy;g.precise_mouse_x=sx*(g.screen_pixel_x//g.dimx)+4;g.precise_mouse_y=sy*(g.screen_pixel_y//g.dimy)+6
     local p=dfhack.gui.getMousePos(true)
     if p and p.x==tx and p.y==ty and p.z==point.z then click(sx,sy);return end
    end end
    error('archery map corner not visible')
   end
   for _,entry in ipairs{{'east',1,0,1,0},{'west',-1,0,-1,0},{'north',0,-1,0,-1},{'south',0,1,0,1},
     {'center',0,0,-1,0},{'diagonal',1,1,1,0},{'outside',3,0,1,0}} do
    target.x1=point.x+entry[2];target.x2=target.x1;target.centerx=target.x1
    target.y1=point.y+entry[3];target.y2=target.y1;target.centery=target.y1;target.z=point.z
    click(26,33);map_click(point.x-2,point.y-2);map_click(point.x+2,point.y+2)
    b=assert(ui.cur_bld);pile_id=b.id;assert(b.type==df.civzone_type.ArcheryRange)
    click(38,9)
    local range=b.zone_settings.archery
    records[#records+1]={name='archery-'..entry[1],target_x=target.centerx,target_y=target.centery,
     x1=b.x1,x2=b.x2,y1=b.y1,y2=b.y2,z=b.z,dir_x=range.dir_x,dir_y=range.dir_y}
    assert(range.dir_x==entry[4] and range.dir_y==entry[5],'archery direction differs: '..entry[1])
    capture('archery-'..entry[1])
   end
   targets:erase(#targets-1);target:delete()
   local site
   for dy=-15,15 do for dx=-15,15 do
    local x,y=point.x+dx,point.y+dy
    local tt=dfhack.maps.getTileType(x,y,point.z)
    local flags,occ=dfhack.maps.getTileFlags(x,y,point.z)
    local free=flags and not flags.hidden and occ.building==0 and tt and df.tiletype.attrs[tt].shape==df.tiletype_shape.FLOOR
    if free then for _,zone in ipairs(df.global.world.buildings.other.ANY_ZONE)do
     if zone.z==point.z and dfhack.buildings.containsTile(zone,x,y)then free=false;break end
    end end
    if free then site={x=x,y=y,z=point.z};break end
   end if site then break end end
   assert(site,'no free overlap fixture tile')
   dfhack.gui.revealInDwarfmodeMap(site,true);view:render(dfhack.getTickCount())
   local block=dfhack.maps.getTileBlock(site.x,site.y,site.z)
   local tx,ty=site.x%16,site.y%16;local original_tile=block.tiletype[tx][ty]
   local function make_zone(x,y)
    click(x,y);map_click(site.x,site.y);map_click(site.x,site.y)
    local zone=assert(ui.cur_bld);click(38,9);return zone
   end
   for _,case in ipairs{{'floor',7,24,true},{'gather',26,45,false},{'tomb',26,42,true},{'wall',7,24,false},{'door',7,24,false}}do
    local door
    if case[1]=='wall' then block.tiletype[tx][ty]=df.tiletype.StoneWall end
    if case[1]=='door' then
     door=df.building_doorst:new();door.centerx=site.x;door.centery=site.y;door.z=site.z
     df.global.world.buildings.other.DOOR:insert('#',door)
    end
    local first=make_zone(7,27)
    local second=make_zone(case[2],case[3]);b=second;pile_id=b.id
    records[#records+1]={name='overlap-'..case[1],first_type=df.civzone_type[first.type],second_type=df.civzone_type[second.type],
     first_collision=first.flags.room_collision,second_collision=second.flags.room_collision,x=site.x,y=site.y,z=site.z}
    assert(first.flags.room_collision==case[4] and second.flags.room_collision==case[4],'native overlap mismatch '..case[1])
    capture('overlap-'..case[1])
    if case[1]=='floor' then
     local site_owner=assert(dfhack.world.getCurrentSite())
     local location=df.abstract_building_inn_tavernst:new()
     location.id=(#site_owner.buildings>0 and site_owner.buildings[#site_owner.buildings-1].id or -1)+1
     location.site_id=site_owner.id;site_owner.buildings:insert('#',location)
     local old_site,old_location=second.site_id,second.location_id
     second.site_id=site_owner.id;second.location_id=location.id
     location.contents.building_ids:insert('#',second.id)
     local function poison_location()
      location.contents.location_value=654321;location.contents.count_goblets=123
      location.contents.update_timer=13;location.contents.update_count=19
     end
     local function observe_location(phase)
      local c=location.contents
      records[#records+1]={name='zone-location-'..phase,value=c.location_value,goblets=c.count_goblets,
       update_timer=c.update_timer,update_count=c.update_count}
      assert(c.location_value~=654321 and c.count_goblets~=123 and c.update_timer==100 and c.update_count==0,'native location repaint did not refresh')
     end
     click(34,9);capture('zone-repaint-before');poison_location()
     click(14,12);map_click(site.x,site.y);map_click(site.x,site.y)
     records[#records+1]={name='zone-erased-overlap',first_collision=first.flags.room_collision,second_collision=second.flags.room_collision,
      second_tiles=dfhack.buildings.countExtentTiles(second,-1),exists=df.building.find(second.id)~=nil}
     observe_location('erase');capture('zone-erased-overlap');poison_location()
     assert(not first.flags.room_collision and not second.flags.room_collision and dfhack.buildings.countExtentTiles(second,-1)==0,'erase did not refresh overlap')
     click(14,12);map_click(site.x,site.y);map_click(site.x,site.y)
     assert(first.flags.room_collision and second.flags.room_collision,'regrow did not restore overlap')
     records[#records+1]={name='zone-regrown-overlap',first_collision=first.flags.room_collision,second_collision=second.flags.room_collision}
     observe_location('regrow');capture('zone-regrown-overlap');click(38,9)
     second.site_id=old_site;second.location_id=old_location
     assert(site_owner.buildings[#site_owner.buildings-1]==location);site_owner.buildings:erase(#site_owner.buildings-1);location:delete()
     local second_id=second.id;click(42,9);assert(not df.building.find(second_id),'native Remove retained zone')
     records[#records+1]={name='zone-remove-overlap',first_collision=first.flags.room_collision}
     b=first;pile_id=b.id;map_click(site.x,site.y);capture('zone-remove-overlap')
    else assert(dfhack.buildings.deconstruct(second))end
    assert(dfhack.buildings.deconstruct(first))
    if door then local doors=df.global.world.buildings.other.DOOR;doors:erase(#doors-1);door:delete()end
    block.tiletype[tx][ty]=original_tile
   end
   b=make_zone(7,24);pile_id=b.id
   local original_members={};for _,member in ipairs(b.contained_buildings)do original_members[#original_members+1]=member end
   local samples={coffin=df.building_coffinst:new(),slab=df.building_slabst:new(),statue=df.building_statuest:new(),
    cage=df.building_cagest:new(),chain=df.building_chainst:new(),display=df.building_display_furniturest:new()}
   for _,case in ipairs{{'empty','meeting hall',{}},{'coffin','memorial hall',{'coffin'}},{'slab','memorial hall',{'slab'}},
    {'statue','sculpture garden',{'statue'}},{'cage','zoo',{'cage'}},{'chain','zoo',{'chain'}},{'display','museum',{'display'}},
    {'statue-cage-tie','zoo',{'statue','cage'}},{'statue-display-tie','museum',{'statue','display'}},
    {'cage-display-tie','museum',{'cage','display'}},{'memorial-priority','memorial hall',{'coffin','statue','statue','cage','display'}}}do
    b.contained_buildings:resize(0);for _,key in ipairs(case[3])do b.contained_buildings:insert('#',samples[key])end
    view:render(dfhack.getTickCount())
    local chars={};for x=6,39 do local tile=dfhack.screen.readTile(x,6);chars[#chars+1]=tile.ch>=32 and tile.ch<127 and string.char(tile.ch) or ' ' end
    local heading=table.concat(chars):gsub('%s+$','')
    assert(heading=='Unnamed '..case[2],'native heading mismatch '..case[1]..': '..heading)
    records[#records+1]={name='meeting-name-'..case[1],heading=heading,members=case[3]}
    capture('meeting-name-'..case[1])
   end
   b.contained_buildings:resize(0);for _,member in ipairs(original_members)do b.contained_buildings:insert('#',member)end
   for _,sample in pairs(samples)do sample:delete()end
   return
  end
  if test_zone_gather then
   local ui=df.global.game.main_interface.civzone
   click(26,45) -- Gather Fruit in the observed native chooser.
   click(map_x,map_y);click(map_x,map_y)
   b=assert(ui.cur_bld,'Gather Fruit creation did not select a zone');pile_id=b.id
   assert(b.type==df.civzone_type.PlantGathering,'Gather Fruit selected another type')
   capture('gather-paint');click(38,9)
   local function state(name)
    local flags=b.zone_settings.gather.flags
    records[#records+1]={name=name,id=b.id,type=df.civzone_type[b.type],flags=flags.whole,
     trees=flags.pick_trees,shrubs=flags.pick_shrubs,fallen=flags.gather_fallen,
     active=b.spec_sub_flag.active,frame=df.global.world.frame_counter}
    assert(df.global.pause_state and df.global.world.frame_counter==frame,'gather simulation advanced')
    capture(name)
   end
   state('gather-created')
   for _,entry in ipairs{{'trees',34,'pick_trees'},{'shrubs',38,'pick_shrubs'},{'fallen',42,'gather_fallen'}}do
    local before=b.zone_settings.gather.flags.whole
    click(entry[2],12);assert(not b.zone_settings.gather.flags[entry[3]],'native toggle did not disable '..entry[1]);state('gather-'..entry[1]..'-off')
    click(entry[2],12);assert(b.zone_settings.gather.flags[entry[3]] and b.zone_settings.gather.flags.whole==before,'native toggle did not restore '..entry[1]);state('gather-'..entry[1]..'-on')
   end
   return
  end
  if test_rename_text then return end
  if test_tooltips then
   local function hover(name,x,y)
    local function move()
     df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
     g.mouse_x=x;g.mouse_y=y;g.precise_mouse_x=x*8+4;g.precise_mouse_y=y*12+6
     gui.simulateInput(view,{})
    end
    local deadline=dfhack.getTickCount()+900
    repeat move();view:render(dfhack.getTickCount());require('gui.script').sleep(1,'frames') until dfhack.getTickCount()>=deadline
    move();view:render(dfhack.getTickCount())
    local ui=df.global.game.main_interface
    records[#records+1]={name='hover-state-'..name,hover=df.main_hover_instruction[ui.current_hover],enabled=ui.hover_instructions_on,left=ui.current_hover_left_x,bottom=ui.current_hover_bot_y}
    local expected={rename='NONE',repaint='STOCKPILE_REPAINT',remove='STOCKPILE_REMOVE_EXISTING',
     ['links-only']='STOCKPILE_TAKE_FROM_ANYWHERE_OR_LINKS',links='STOCKPILE_SET_CONNECTIONS',containers='STOCKPILE_TOOL_SETTINGS',
     ['preset-all']='NONE',['preset-custom']='NONE',rectangle='STOCKPILE_PAINT_RECTANGLE',brush='STOCKPILE_PAINT_FREE',erase='STOCKPILE_ERASE',['paint-remove']='STOCKPILE_PAINT_REMOVE'}
    assert(df.main_hover_instruction[ui.current_hover]==expected[name],'unexpected native hover: '..name)
    capture('hover-'..name,move)
    assert(df.global.pause_state and df.global.world.frame_counter==frame,'tooltip simulation advanced')
   end
   for _,v in ipairs{{'rename',42,6},{'repaint',38,9},{'remove',42,9},{'links-only',38,12},{'links',42,12},{'containers',42,15},{'preset-all',7,9},{'preset-custom',21,36}}do hover(table.unpack(v))end
   click(38,9)
   for _,v in ipairs{{'rectangle',77,61},{'brush',81,61},{'erase',85,61},{'paint-remove',89,61}}do hover(table.unpack(v))end
   return
  end
  if test_rename then
   local original=b.name
   local ui=df.global.game.main_interface
   local _,name_address=df.sizeof(b:_field('name'))
   local _,building_address=df.sizeof(b)
   local _,entry_address=df.sizeof(ui:_field('entering_building_name'))
   local _,pile_pointer_address=df.sizeof((test_zone_rename and ui.civzone or ui.stockpile):_field('cur_bld'))
   records[#records+1]={name='rename-native-layout',name_offset=name_address-building_address,
    entering_name_rva=entry_address-dfhack.internal.getImageBase(),pile_pointer_rva=pile_pointer_address-dfhack.internal.getImageBase()}
   local function state(name)
    local bytes={};for i=1,#b.name do bytes[#bytes+1]=b.name:byte(i)end
    records[#records+1]={name='rename-state-'..name,custom_name=dfhack.df2utf(b.name),name_bytes=bytes,
     entering=ui.entering_building_name,bottom_mode=ui.bottom_mode_selected,paused=df.global.pause_state,frame=df.global.world.frame_counter}
    assert(df.global.pause_state and df.global.world.frame_counter==frame,'rename simulation advanced')
    capture('rename-'..name)
   end
   state('before');b.name='';click(42,6);state('opened')
   for _,byte in ipairs{65,97,49,32,66}do gui.simulateInput(view,string.format('STRING_A%03d',byte))end
   state('typed');assert(b.name=='Aa1 B');gui.simulateInput(view,'SELECT');state('enter')
   gui.simulateInput(view,'STRING_A090');state('after-enter-input')
   click(42,6);state('reopened')
   gui.simulateInput(view,'STRING_A088');state('append-existing')
   gui.simulateInput(view,'STRING_A000');state('backspace')
   click(42,6);state('quill-again')
   gui.simulateInput(view,'STRING_A089');state('after-quill-input')
   click(42,6)
   for i=1,150 do gui.simulateInput(view,'STRING_A097')end
   state('length-limit');assert(b.name=='Aa1 BY'..string.rep('a',14),'native rename limit differs')
   for i=1,20 do gui.simulateInput(view,'STRING_A000')end
   state('cleared');assert(b.name=='','native backspace differs')
   for _,byte in ipairs{33,45,46,95,126,128,130,255}do
    gui.simulateInput(view,string.format('STRING_A%03d',byte))
   end
   state('punctuation-and-high-bytes')
   gui.simulateInput(view,'_MOUSE_R');state('right-click')
   if test_zone_rename then
    ui.bottom_mode_selected=-1;gui.simulateInput(view,'D_CIVZONE')
    dfhack.gui.revealInDwarfmodeMap(point,true);view:render(dfhack.getTickCount())
    for y=0,g.dimy-1 do for x=0,g.dimx-1 do
     g.mouse_x=x;g.mouse_y=y;g.precise_mouse_x=x*8+4;g.precise_mouse_y=y*12+6
     local p=dfhack.gui.getMousePos(true)
     if p and p.x==point.x and p.y==point.y and p.z==point.z then click(x,y);break end
    end if ui.civzone.cur_bld then break end end
    assert(ui.civzone.cur_bld==b,'zone reopen selected a different building')
    click(42,6);state('reopened-after-right')
    gui.simulateInput(view,'STRING_A069');state('before-escape')
    local before=b.name;gui.simulateInput(view,'LEAVESCREEN');state('escape')
    assert(ui.bottom_mode_selected==-1 and b.name==before,'Escape changed name or did not close')
   else
    click(42,6);state('after-right-quill')
    gui.simulateInput(view,'LEAVESCREEN');state('escape')
   end
   b.name=original
   return
  end
  if test_links then
   local ui=df.global.game.main_interface.stockpile_link
   local vectors={name='target-vector-identities',vectors={}}
   for key,value in pairs{all=df.global.world.buildings.all,IN_PLAY=df.global.world.buildings.other.IN_PLAY,STOCKPILE=df.global.world.buildings.other.STOCKPILE}do
    local size,address=df.sizeof(value)
    vectors.vectors[key]={rva=address-dfhack.internal.getImageBase(),size=size,count=#value}
   end
   records[#records+1]=vectors
   local function snapshot(name,target)
    local function endpoint(building)
     local ls=building:getStockpileLinks();local r={id=building.id}
     if ls then for _,key in ipairs{'give_to_pile','take_from_pile','give_to_workshop','take_from_workshop'}do
      r[key]={};for _,other in ipairs(ls[key])do r[key][#r[key]+1]=other.id end
     end end
     return r
    end
    local _,address=df.sizeof(ui)
    records[#records+1]={name=name,source=endpoint(b),target=target and endpoint(target) or false,
     open=ui.open,adding=ui.adding_new_link,direction=ui.adding_new_link_type,context=ui.context,
     selected=ui.bld_id,ui_rva=address-dfhack.internal.getImageBase()}
   end
   local function mapclick(target,expected)
    local p={x=target.centerx,y=target.centery,z=target.z}
    if expected~=nil then
     local size,address=df.sizeof(df.global.game.main_interface)
     local copy=df.new('uint8_t',size);dfhack.internal.memmove(copy,address,size)
     local text,code=dfhack.run_command_silent('df3d','stockpile-link-target-read',tostring(b.id),tostring(p.x),tostring(p.y),tostring(p.z),ui.adding_new_link_type==1 and '1' or '0')
     assert(code==0,text);local prediction=json.decode(text)
     assert(prediction.id==expected,'semantic target differs: '..prediction.id..' / '..expected)
     assert(dfhack.internal.memcmp(copy,address,size)==0,'semantic target changed native UI');df.delete(copy)
     records[#records+1]={name='target-service',x=p.x,y=p.y,z=p.z,give=ui.adding_new_link_type==1,id=prediction.id,ui_unchanged=true}
    end
    dfhack.gui.revealInDwarfmodeMap(p,true);view:render(dfhack.getTickCount())
    for y=16,g.dimy-4 do for x=45,g.dimx-25 do
     g.mouse_x=x;g.mouse_y=y;g.precise_mouse_x=x*(g.screen_pixel_x//g.dimx)+4;g.precise_mouse_y=y*(g.screen_pixel_y//g.dimy)+6
     local hit=dfhack.gui.getMousePos(true)
     if hit and hit.x==p.x and hit.y==p.y and hit.z==p.z then click(x,y);return end
    end end
    error('link target not exposed '..target.id)
   end
   click(42,12);assert(ui.open and ui.bld_id==b.id)
   capture('links');snapshot('initial')
   click(48,6);assert(ui.adding_new_link)
   capture('links-give-pick');mapclick(b,-1);snapshot('give-self',b)
   assert(ui.adding_new_link,'self-selection closed picker')
   local empty
   for y=b.y1-8,b.y2+8 do for x=b.x1-8,b.x2+8 do
    local block=dfhack.maps.getTileBlock(x,y,b.z)
    if block and not block.designation[x%16][y%16].hidden and
       not block.designation[x%16][y%16].pile and block.occupancy[x%16][y%16].building==0 and
       not dfhack.buildings.findAtTile{x=x,y=y,z=b.z} then empty={id=-1,centerx=x,centery=y,z=b.z};break end
   end if empty then break end end
   assert(empty,'missing empty ground');mapclick(empty,-1);snapshot('give-empty')
   assert(ui.adding_new_link,'empty target closed picker');capture('links-empty-pick')
   local invalid
   for _,candidate in ipairs(df.global.world.buildings.all)do
    if candidate.z==b.z and candidate:getType()==df.building_type.Door and not candidate:canLinkToStockpile() then invalid=candidate;break end
   end
   assert(invalid,'missing non-linkable door');mapclick(invalid,-1);snapshot('give-nonlinkable',invalid)
   assert(ui.adding_new_link,'non-linkable target closed picker');capture('links-nonlinkable-pick')
   gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
   capture('links-give-escape');snapshot('escape')
   local other
   for _,candidate in ipairs(df.global.world.buildings.other.STOCKPILE)do
    if candidate.id~=b.id and candidate.z==b.z and candidate.room.extents[(candidate.centery-candidate.room.y)*candidate.room.width+candidate.centerx-candidate.room.x]~=0 then other=candidate;break end
   end
   assert(other,'missing other pile')
   local workshop
   for _,candidate in ipairs(df.global.world.buildings.all)do
    if candidate:getType()~=df.building_type.Stockpile and candidate.z==b.z and candidate:canLinkToStockpile() then workshop=candidate;break end
   end
   assert(workshop,'missing workshop')
   for _,target in ipairs{other,workshop}do
    for _,direction in ipairs{'give','take'}do
     local x=direction=='give' and 48 or 52
     for repeat_index=1,2 do
      if ui.adding_new_link then click(79,6)end
      click(x,6);assert(ui.adding_new_link)
      mapclick(target,repeat_index==1 and target.id or -1);snapshot(direction..'-'..target.id..'-'..repeat_index,target)
      local stock=df.building_stockpilest:is_instance(target)
      local suffix=stock and '_pile' or '_workshop'
      local function has(v,id)for _,entry in ipairs(v)do if entry.id==id then return true end end;return false end
      local forward=direction=='give' and 'give_to' or 'take_from'
      local opposite=direction=='give' and 'take_from' or 'give_to'
      assert(has(b.links[forward..suffix],target.id),'forward link missing')
      assert(not has(b.links[opposite..suffix],target.id),'opposite link retained')
      local reverse=target:getStockpileLinks()
      assert(has(reverse[opposite..'_pile'],b.id),'reciprocal link missing')
      assert(not has(reverse[forward..'_pile'],b.id),'opposite reciprocal retained')
      assert(ui.adding_new_link==(repeat_index==2),'duplicate picker lifecycle differs')

      capture('links-'..direction..'-'..target.id..'-'..repeat_index)
     end
    end
   end
   if ui.adding_new_link then click(79,6)end
   for i=1,4 do click(83,12);snapshot('remove-'..i,other);snapshot('remove-workshop-'..i,workshop);capture('links-remove-'..i)end
   for _,key in ipairs{'give_to_pile','take_from_pile','give_to_workshop','take_from_workshop'}do assert(#b.links[key]==0,'source removal incomplete')end
   for _,target in ipairs{other,workshop}do for _,key in ipairs{'give_to_pile','take_from_pile'}do
    for _,entry in ipairs(target:getStockpileLinks()[key])do assert(entry.id~=b.id,'reciprocal removal incomplete')end
   end end
   -- Distinct endpoints preserve native one-direction-per-pair semantics.
   -- Reverse insertion and distinct names separate ID ordering from click/name order.
   local order_piles,order_workshops={},{}
   for _,candidate in ipairs(df.global.world.buildings.all)do
    local stock=df.building_stockpilest:is_instance(candidate)
    local group=stock and order_piles or order_workshops
    local block=dfhack.maps.getTileBlock(candidate.centerx,candidate.centery,candidate.z)
    if candidate.id~=b.id and candidate.z==b.z and #group<4 and block and
       not block.designation[candidate.centerx%16][candidate.centery%16].hidden and
       (stock or candidate:canLinkToStockpile()) and
       (not candidate.room.extents or candidate.room.extents[(candidate.centery-candidate.room.y)*candidate.room.width+candidate.centerx-candidate.room.x]~=0) then
     group[#group+1]=candidate
    end
   end
   assert(#order_piles==4 and #order_workshops==4,'four piles and workshops required for ordering oracle')
   local saved_names={};local expected_order={}
   for group_index,group in ipairs{order_workshops,order_piles}do
    for index,target in ipairs(group)do
     saved_names[target.id]=target.name
     target.name='Order'..tostring(group_index)..tostring(5-index)
     expected_order[#expected_order+1]={id=target.id,name=target.name,kind=group_index==1 and 2 or 0,direction=index<=2 and 2 or 1}
    end
   end
   for _,group in ipairs{order_piles,order_workshops}do for index=4,1,-1 do
    click(index<=2 and 52 or 48,6);mapclick(group[index],group[index].id)
    assert(not ui.adding_new_link,'ordered target did not create link')
   end end
   capture('links-four-group-order')
   local visible={}
   for index,expected in ipairs(expected_order)do
    local chars={}
    for x=54,80 do local tile=dfhack.screen.readTile(x,12+(index-1)*3);chars[#chars+1]=tile.ch>=32 and tile.ch<127 and string.char(tile.ch) or ' ' end
    local label=table.concat(chars):match('^%s*(.-)%s*$')
    assert(label==expected.name,'native group/within-vector order: '..label..' / '..expected.name)
    visible[#visible+1]={id=expected.id,name=label,kind=expected.kind,direction=expected.direction}
   end
   records[#records+1]={name='four-group-order',rows=visible,scroll=ui.scroll_position_link_list,insertion='reverse ID order; pile groups before workshop groups'}
   for _,expected in ipairs(expected_order)do
    click(83,12)
    local key=(expected.direction==1 and 'give_to' or 'take_from')..(expected.kind==0 and '_pile' or '_workshop')
    for _,target in ipairs(b.links[key])do assert(target.id~=expected.id,'first-row removal selected wrong endpoint')end
   end
   for id,name in pairs(saved_names)do df.building.find(id).name=name end
   -- Valid reciprocal links are fixture prerequisites for observing a long
   -- native list. Actual scrolling/removal below is driven through native UI.
   local scroll_targets={};local scroll_names={}
   for _,target in ipairs(df.global.world.buildings.all)do
    if not df.building_stockpilest:is_instance(target) and target:canLinkToStockpile() then
     scroll_targets[#scroll_targets+1]=target;scroll_names[target.id]=target.name
     target.name=string.format('Scroll%02d',#scroll_targets)
     require('utils').insert_sorted(b.links.take_from_workshop,target,'id')
     require('utils').insert_sorted(target:getStockpileLinks().give_to_pile,b,'id')
     if #scroll_targets==20 then break end
    end
   end
   assert(#scroll_targets==20,'twenty workshop endpoints required')
   ui.scroll_position_link_list=0;view:render(dfhack.getTickCount());capture('links-scroll-top')
   local function scroll_point(x,y)
    g.mouse_x=x;g.mouse_y=y;g.precise_mouse_x=x*(g.screen_pixel_x//g.dimx)+4;g.precise_mouse_y=y*(g.screen_pixel_y//g.dimy)+6
    df.global.enabler.tracking_on=1
   end
   local function scroll_probe(label,start,x,y,keys)
    ui.scroll_position_link_list=start;ui.scrolling_link_list=false
    scroll_point(x,y);gui.simulateInput(view,{});view:render(dfhack.getTickCount())
    gui.simulateInput(view,keys);view:render(dfhack.getTickCount())
    records[#records+1]={name='link-scroll',label=label,start=start,x=x,y=y,after=ui.scroll_position_link_list,dragging=ui.scrolling_link_list}
   end
   for _,key in ipairs{'STANDARDSCROLL_UP','STANDARDSCROLL_DOWN','STANDARDSCROLL_PAGEUP','STANDARDSCROLL_PAGEDOWN',
     'CONTEXT_SCROLL_UP','CONTEXT_SCROLL_DOWN','CONTEXT_SCROLL_PAGEUP','CONTEXT_SCROLL_PAGEDOWN'}do
    scroll_probe(key,5,60,20,key)
   end
   -- Arrow/track positions are sampled over the full native scrollbar column.
   for y=11,37 do scroll_probe('column-from-top',0,85,y,'_MOUSE_L')end
   for y=11,37 do scroll_probe('column-from-middle',5,85,y,'_MOUSE_L')end
   local enabler=df.global.enabler;local old_lift=enabler.mouse_lbut_lift
   for destination=10,38 do
    ui.scroll_position_link_list=0;ui.scrolling_link_list=false;scroll_point(85,15)
    enabler.mouse_lbut_lift=0;gui.simulateInput(view,{'_MOUSE_L','_MOUSE_L_DOWN'})
    scroll_point(85,destination);gui.simulateInput(view,{'_MOUSE_L_DOWN'})
    records[#records+1]={name='link-scroll-drag',start=0,y=destination,after=ui.scroll_position_link_list}
    enabler.mouse_lbut_lift=1;gui.simulateInput(view,{})
   end
   for _,y in ipairs{11,37}do
    ui.scroll_position_link_list=5;ui.scrolling_link_list=false;scroll_point(85,y)
    enabler.mouse_lbut_lift=0;gui.simulateInput(view,{'_MOUSE_L','_MOUSE_L_DOWN'})
    local values={ui.scroll_position_link_list}
    for i=1,12 do gui.simulateInput(view,{'_MOUSE_L_DOWN'});values[#values+1]=ui.scroll_position_link_list end
    records[#records+1]={name='link-scroll-held',y=y,values=values}
    enabler.mouse_lbut_lift=1;gui.simulateInput(view,{})
   end
   -- Separate wall-clock probe: immediate feeds do not establish repeat
   -- behavior. Keep feeding the held input across actual rendered frames.
   for _,y in ipairs{11,37}do
    ui.scroll_position_link_list=5;ui.scrolling_link_list=false;scroll_point(85,y)
    enabler.mouse_lbut_lift=0;gui.simulateInput(view,{'_MOUSE_L','_MOUSE_L_DOWN'})
    local started=dfhack.getTickCount()
    local samples={{ms=0,first=ui.scroll_position_link_list}}
    while dfhack.getTickCount()-started<2200 do
     require('gui.script').sleep(1,'frames')
     scroll_point(85,y);enabler.mouse_lbut_lift=0
     gui.simulateInput(view,{'_MOUSE_L_DOWN'});view:render(dfhack.getTickCount())
     samples[#samples+1]={ms=dfhack.getTickCount()-started,first=ui.scroll_position_link_list}
    end
    enabler.mouse_lbut_lift=1;gui.simulateInput(view,{})
    records[#records+1]={name='link-scroll-held-elapsed',y=y,start=5,samples=samples,
     elapsed_ms=dfhack.getTickCount()-started,after=ui.scroll_position_link_list}
   end
   enabler.mouse_lbut_lift=old_lift
   for first=0,11 do
    ui.scroll_position_link_list=first;ui.scrolling_link_list=false;scroll_point(0,0);view:render(dfhack.getTickCount())
    local cells={}
    for y=11,37 do cells[#cells+1]={left=dfhack.screen.readTile(84,y).tile,right=dfhack.screen.readTile(85,y).tile}end
    records[#records+1]={name='link-scroll-art',first=first,cells=cells,base=df.global.init.scrollbar_texpos[0]}
   end
   local row_art={name='link-row-art',samples={},styles={}}
   for y=11,13 do for _,x in ipairs{47,48,49,50,51,52,55,70,79,80,81,82,83}do
    row_art.samples[#row_art.samples+1]={x=x,y=y,tile=dfhack.screen.readTile(x,y).tile}
   end end
   for _,key in ipairs{'texpos_button_rectangle','texpos_button_rectangle_dark','texpos_button_rectangle_light','texpos_button_category_rectangle'}do
    local values={};for _,row in ipairs(g.graphical_interface[key])do for _,value in ipairs(row)do values[#values+1]=value end end
    row_art.styles[key]=values
   end
   local sampled={};for _,sample in ipairs(row_art.samples)do sampled[sample.tile]=true end
   row_art.matches={}
   local function match_art(path,value,depth)
    if type(value)=='number' and sampled[value]then row_art.matches[#row_art.matches+1]={field=path,tile=value}
    elseif type(value)=='userdata' and depth<3 then
     for key,child in pairs(value)do if tostring(key):sub(1,1)~='_' then match_art(path..'.'..tostring(key),child,depth+1)end end
    end
   end
   match_art('graphical_interface',g.graphical_interface,0)
   records[#records+1]=row_art
   ui.scroll_position_link_list=11;ui.scrolling_link_list=false;capture('links-scroll-bottom')
   for _,target in ipairs(scroll_targets)do
    ui.scroll_position_link_list=0;view:render(dfhack.getTickCount());click(81,12)
    for _,entry in ipairs(b.links.take_from_workshop)do assert(entry.id~=target.id,'scroll fixture first-row removal')end
    target.name=scroll_names[target.id]
   end
   ui.scroll_position_link_list=0;ui.scrolling_link_list=false
   -- Controlled overlap is confined to this disposable paused oracle. Native
   -- map target selection uses building bounds/extents, not drawn occupancy.
   local overlaps={}
   for _,candidate in ipairs(df.global.world.buildings.other.STOCKPILE)do
    if candidate.id~=b.id and candidate.room.extents then overlaps[#overlaps+1]=candidate end
    if #overlaps==2 then break end
   end
   assert(#overlaps==2)
   local inputs={name='overlap-inputs',stockpiles={},workshop=workshop.id,x=workshop.centerx,y=workshop.centery,z=workshop.z}
   for _,candidate in ipairs(overlaps)do
    candidate.x1=workshop.centerx;candidate.x2=workshop.centerx;candidate.centerx=workshop.centerx
    candidate.y1=workshop.centery;candidate.y2=workshop.centery;candidate.centery=workshop.centery;candidate.z=workshop.z
    candidate.room.x=candidate.x1;candidate.room.y=candidate.y1;candidate.room.width=1;candidate.room.height=1;candidate.room.extents[0]=1
    inputs.stockpiles[#inputs.stockpiles+1]=candidate.id
   end
   records[#records+1]=inputs
   for index=1,4 do
    click(48,6);assert(ui.adding_new_link);mapclick(workshop,index<=2 and overlaps[index].id or index==3 and workshop.id or -1)
    snapshot('overlap-'..index,workshop)
    assert(ui.adding_new_link==(index==4),'overlap picker progression')
    assert(#b.links.give_to_pile==math.min(index,2),'overlap pile progression')
    for i=1,math.min(index,2)do assert(b.links.give_to_pile[i-1].id==overlaps[i].id,'native overlap order')end
    assert(#b.links.give_to_workshop==(index>=3 and 1 or 0),'workshop pass precedence')
    capture('links-overlap-'..index)
   end
   assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
   return
  end
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
   local assigned_ids={}
   for _,id in ipairs(b.storage.container_item_id)do assigned_ids[#assigned_ids+1]=id end
   local function assignments(name)
    local rows,items={},{}
    local alive=df.building.find(pile_id)
    if alive then
     for i,id in ipairs(alive.storage.container_item_id)do
      rows[#rows+1]={id=id,type=alive.storage.container_type[i],x=alive.storage.container_x[i],y=alive.storage.container_y[i]}
     end
    end
    for _,id in ipairs(assigned_ids)do
     local item=df.item.find(id);local ref=item and item:getStockpile2()
     items[#items+1]={id=id,exists=item~=nil,assignment=ref and {id=ref.id,x=ref.x,y=ref.y} or false}
    end
    records[#records+1]={name=name,containers=rows,items=items}
   end
   local function mapclick(p,phase)
    dfhack.gui.revealInDwarfmodeMap(p,true);view:render(dfhack.getTickCount())
    for y=0,g.dimy-1 do for x=0,g.dimx-1 do
     g.mouse_x=x;g.mouse_y=y;g.precise_mouse_x=x*(g.screen_pixel_x//g.dimx)+4;g.precise_mouse_y=y*(g.screen_pixel_y//g.dimy)+6
     local hit=dfhack.gui.getMousePos(true)
     if hit and hit.x==p.x and hit.y==p.y and hit.z==p.z then
      if phase then
       local e=df.global.enabler;local lift=e.mouse_lbut_lift
       e.mouse_lbut_lift=phase=='release' and 1 or 0
       local ok,why=pcall(function()
        gui.simulateInput(view,phase=='press' and {'_MOUSE_L','_MOUSE_L_DOWN'} or phase=='hold' and {'_MOUSE_L_DOWN'} or {})
        view:render(dfhack.getTickCount())
       end)
       e.mouse_lbut_lift=lift;assert(ok,why)
      else click(x,y)end
      return
     end
    end end
    error('repaint tile is not visible')
   end
   local function record(name)
    b=assert(df.building.find(pile_id),'pile unexpectedly removed before '..name)
    records[#records+1]={name=name,tiles=dfhack.buildings.countExtentTiles(b,-1),barrels=b.storage.max_barrels,bins=b.storage.max_bins,wheelbarrows=b.storage.max_wheelbarrows,
     bounds={b.x1,b.y1,b.x2,b.y2},repainting=paint.repainting,erasing=paint.erasing,
     current=paint.cur_bld and paint.cur_bld.id or -1,bottom_mode=df.global.game.main_interface.bottom_mode_selected,
     corner={df.global.selection_rect.start_x,df.global.selection_rect.start_y,df.global.selection_rect.start_z}}
   end
   if gestures=='transfer-partial' or gestures=='transfer-full' or gestures=='transfer-create-partial' or gestures=='transfer-create-full' or gestures=='transfer-erase-partial' or gestures=='transfer-erase-full' then
    local creating=gestures:find('create',1,true)~=nil
    local donor
    for _,candidate in ipairs(df.global.world.buildings.other.STOCKPILE)do
     if candidate.id~=b.id and candidate.z==b.z and #candidate.storage.container_item_id>0 and
      math.max(candidate.x2,b.x2)-math.min(candidate.x1,b.x1)<128 and math.max(candidate.y2,b.y2)-math.min(candidate.y1,b.y1)<128 then donor=candidate;break end
    end
    assert(donor,'no nearby stocked donor')
    local donor_id=donor.id;local donor_cells,items={},{}
    for y=donor.y1,donor.y2 do for x=donor.x1,donor.x2 do
     if dfhack.buildings.containsTile(donor,x,y)then donor_cells[#donor_cells+1]={x=x,y=y,z=donor.z}end
    end end
    for _,id in ipairs(donor.storage.container_item_id)do items[#items+1]=id end
    local first,last
    if gestures:find('partial',1,true) then
     first={x=donor.storage.container_x[0],y=donor.storage.container_y[0],z=donor.z};last=first
    else first={x=donor.x1,y=donor.y1,z=donor.z};last={x=donor.x2,y=donor.y2,z=donor.z}end
    local function donor_record(name)
     local current=df.building.find(donor_id);local assignments={}
     for _,id in ipairs(items)do
      local item=assert(df.item.find(id));local ref=item:getStockpile2()
      assignments[#assignments+1]={id=id,assignment=ref and {id=ref.id,x=ref.x,y=ref.y} or false}
     end
     local transferred,retained=0,0
     for _,p in ipairs(donor_cells)do
      if dfhack.buildings.containsTile(b,p.x,p.y)then transferred=transferred+1 end
      if current and dfhack.buildings.containsTile(current,p.x,p.y)then retained=retained+1 end
     end
     records[#records+1]={name=name,donor_id=donor_id,donor_exists=current~=nil,first=first,last=last,
      donor_tiles=current and dfhack.buildings.countExtentTiles(current,-1) or 0,transferred=transferred,retained=retained,
      donor_containers=current and #current.storage.container_item_id or 0,items=assignments,
      donor_limits=current and {current.storage.max_barrels,current.storage.max_bins,current.storage.max_wheelbarrows} or false}
    end
    if creating then
     first={x=donor.x1-1,y=donor.y1,z=donor.z}
     local block=assert(dfhack.maps.getTileBlock(first));assert(not block.designation[first.x%16][first.y%16].pile and block.occupancy[first.x%16][first.y%16].building==0,'creation anchor occupied')
    end
    donor_record('donor-before');record('recipient-before')
    local next_id=df.global.building_next_id
    if creating then gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());gui.simulateInput(view,'D_STOCKPILES');view:render(dfhack.getTickCount())end
    if gestures:find('erase',1,true)then click(84,61);assert(paint.erasing)end
    mapclick(first);mapclick(last)
    if creating then b=assert(df.building.find(next_id),'transfer creation failed')end
    donor_record('donor-after')
    if creating then records[#records+1]={name='created-recipient',id=b.id,tiles=dfhack.buildings.countExtentTiles(b,-1),bounds={b.x1,b.y1,b.x2,b.y2}} else record('recipient-after')end
    capture(gestures)
    assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
    return
   end
   if gestures=='eligibility-grow' then
    assert(eligibility_case=='floor' or eligibility_case=='wall-left' or eligibility_case=='wall-right' or eligibility_case=='all-wall')
    local first,last
    for ty=b.y1,b.y2 do
     local free=true
     for tx=b.x2+1,b.x2+3 do
      local block=dfhack.maps.getTileBlock(tx,ty,b.z)
      if not block or block.designation[tx%16][ty%16].pile or block.occupancy[tx%16][ty%16].building~=0 then free=false;break end
     end
     if free then first={x=b.x2+1,y=ty,z=b.z};last={x=b.x2+3,y=ty,z=b.z};break end
    end
    assert(first,'no free growth span along right edge')
    local saved={}
    for tx=first.x,last.x do
     local block=assert(dfhack.maps.getTileBlock(tx,first.y,first.z));local x,y=tx%16,first.y%16
     assert(not block.designation[x][y].pile and block.occupancy[x][y].building==0,'growth fixture overlaps existing building')
     saved[#saved+1]={block=block,x=x,y=y,tile=block.tiletype[x][y],designation=block.designation[x][y].whole}
     block.tiletype[x][y]=(eligibility_case=='all-wall' or eligibility_case=='wall-left' and tx==first.x or eligibility_case=='wall-right' and tx==last.x) and df.tiletype.StoneWall or df.tiletype.StoneFloor1
     block.designation[x][y].hidden=false;block.designation[x][y].flow_size=0
    end
    record('before-grow')
    mapclick(first);mapclick(last)
    record('after-grow')
    local mask={};for tx=first.x,last.x do mask[#mask+1]=dfhack.buildings.containsTile(b,tx,first.y)end
    records[#records+1]={name='grow-cells',case=eligibility_case,first=first,last=last,mask=mask}
    capture('eligibility-grow-'..eligibility_case)
    for _,s in ipairs(saved)do
     s.block.tiletype[s.x][s.y]=s.tile
     local pile=s.block.designation[s.x][s.y].pile
     s.block.designation[s.x][s.y].whole=s.designation;s.block.designation[s.x][s.y].pile=pile
    end
    assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
    return
   end
   if gestures=='eligibility' or gestures=='eligibility-create' or gestures=='eligibility-erase' then
    local first,last
    for _,p in ipairs(cells)do
     if dfhack.buildings.containsTile(b,p.x+1,p.y) and dfhack.buildings.containsTile(b,p.x+2,p.y)then
      first=p;last={x=p.x+2,y=p.y,z=p.z};break
     end
    end
    assert(first,'no three-cell eligibility span')
    local middle={x=first.x+1,y=first.y,z=first.z}
    if eligibility_case=='wall-left' then middle=first elseif eligibility_case=='wall-right' then middle=last end
    local block=assert(dfhack.maps.getTileBlock(middle));local x,y=middle.x%16,middle.y%16
    local tile=block.tiletype[x][y];local designation=block.designation[x][y].whole;local occupancy=block.occupancy[x][y].whole
    local function restore()
     block.tiletype[x][y]=tile;block.designation[x][y].whole=designation;block.occupancy[x][y].whole=occupancy
    end
    local cases={{name='floor'},{name='wall',tile='StoneWall'},{name='water1',depth=1},{name='water2',depth=2},
     {name='water7',depth=7},{name='magma1',depth=1,magma=true},{name='building1',building=1},{name='building2',building=2},
     {name='hidden',hidden=true},{name='ramp',tile='StoneRamp'},{name='open',tile='OpenSpace'},{name='all-wall',tile='StoneWall',all_wall=true}}
    if eligibility_case=='wall-left' or eligibility_case=='wall-right' then cases={{name=eligibility_case,tile='StoneWall'}}end
    if eligibility_case and eligibility_case~='all' then
     local filtered={};for _,case in ipairs(cases)do if case.name==eligibility_case then filtered[1]=case end end
     assert(#filtered==1,'unknown eligibility case');cases=filtered
    end
    for _,case in ipairs(cases)do
     restore()
     if paint.erasing then click(84,61)end
     mapclick(first);mapclick(last)
     if gestures~='eligibility-erase' then
      click(84,61);assert(paint.erasing and paint.doing_rectangle)
      mapclick(first);mapclick(last)
      assert(not dfhack.buildings.containsTile(b,first.x,first.y) and not dfhack.buildings.containsTile(b,last.x,last.y),'erase setup failed')
     end
     block.tiletype[x][y]=assert(df.tiletype[case.tile or 'StoneFloor1'])
     block.designation[x][y].hidden=case.hidden or false
     block.designation[x][y].flow_size=case.depth or 0;block.designation[x][y].liquid_type=case.magma or false
     block.occupancy[x][y].building=case.building or 0
     if case.all_wall then
      for _,p in ipairs{first,last}do local cell=assert(dfhack.maps.getTileBlock(p));cell.tiletype[p.x%16][p.y%16]=df.tiletype.StoneWall end
     end
     if test_predicates then
      local text,code=dfhack.run_command_silent('df3d','stockpile-tile-types-read',tostring(block.tiletype[x][y]),'1');assert(code==0,text)
      case.native_tile_eligible=json.decode(text).allowed[1]
     end
     local created
     if gestures=='eligibility-create' then
      gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
      gui.simulateInput(view,'D_STOCKPILES');view:render(dfhack.getTickCount())
      local next_id=df.global.building_next_id
      mapclick(first);mapclick(last)
      for _,candidate in ipairs(df.global.world.buildings.other.STOCKPILE)do if candidate.id>=next_id then assert(not created,'multiple piles created');created=candidate end end
      if case.all_wall then
       assert(not created,'all-wall rectangle unexpectedly created a pile')
       records[#records+1]={name=case.name,setup=case,created=false,first=first,middle=middle,last=last,bottom_mode=df.global.game.main_interface.bottom_mode_selected}
       capture('eligibility-created-none')
       assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
       return
      end
      assert(created,'native created no pile for mixed rectangle')
     else
      click(84,61);assert(paint.erasing==(gestures=='eligibility-erase'))
      mapclick(first);mapclick(last)
     end
     local observed=created or b
     records[#records+1]={name=case.name,first=first,middle=middle,last=last,setup=case,
      tiletype=df.tiletype[block.tiletype[x][y]],designation=block.designation[x][y].whole,occupancy=block.occupancy[x][y].whole,
      start_present=dfhack.buildings.containsTile(observed,first.x,first.y),middle_present=dfhack.buildings.containsTile(observed,middle.x,middle.y),
      end_present=dfhack.buildings.containsTile(observed,last.x,last.y),tiles=dfhack.buildings.countExtentTiles(observed,-1),
      id=observed.id,bounds={observed.x1,observed.y1,observed.x2,observed.y2}}
     if test_predicates then
      local expected=case.native_tile_eligible and not case.hidden and (not case.building or case.building==0)
      assert(dfhack.buildings.containsTile(observed,middle.x,middle.y)==expected,'native UI disagrees with owned scalar predicate and occupancy/visibility')
     end
     if created then
      capture('eligibility-created-'..case.name)
      assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
      return
     end
    end
    restore();capture('eligibility-completed')
    assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
    return
   end
   if gestures=='brush' then
    click(81,61);click(84,61);assert(paint.erasing and not paint.doing_rectangle)
    local first,last
    for _,p in ipairs(cells)do
     if dfhack.buildings.containsTile(b,p.x+1,p.y) and dfhack.buildings.containsTile(b,p.x+2,p.y)then
      first=p;last={x=p.x+2,y=p.y,z=p.z};break
     end
    end
    assert(first,'no three-cell brush span')
    record('brush-before');mapclick(first,'press');record('brush-press')
    mapclick(last,'hold');record('brush-held-jump');mapclick(last,'release');record('brush-release')
    records[#records+1]={name='brush-cells',first=first,last=last,
     start_present=dfhack.buildings.containsTile(b,first.x,first.y),
     middle_present=dfhack.buildings.containsTile(b,first.x+1,first.y),
     end_present=dfhack.buildings.containsTile(b,last.x,last.y)}
    capture('brush-completed')
    assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
    return
   end
   if gestures then
    click(84,61);assert(paint.erasing and paint.doing_rectangle)
    record('gesture-before')
    mapclick(cells[#cells]);record('first-corner')
    mapclick(cells[#cells]);record('completed-erase')
    capture('gesture-committed')
    if gestures:find('partial',1,true)then
     mapclick(cells[#cells-1]);record('partial-before-exit')
    end
    local key=gestures:find('right',1,true)and '_MOUSE_R' or 'LEAVESCREEN'
    gui.simulateInput(view,key);view:render(dfhack.getTickCount());record(gestures)
    capture(gestures)
    assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
    return
   end
   for _,key in ipairs{'barrels','bins','wheelbarrows'}do b.storage['max_'..key]=#cells end
   record('before-shrink')
   assignments('assignments-before')
   click(84,61) -- Eraser at678,742 in protected repaint.png (1200x800).
   assert(paint.erasing and paint.doing_rectangle,'rectangle erase did not activate')
   for index=#cells,2,-1 do
    mapclick(cells[index]);mapclick(cells[index])
    assert(dfhack.buildings.countExtentTiles(b,-1)==index-1,'erase did not remove exactly one tile')
    record('erase-'..index)
    if index==#cells or index==2 then assignments('assignments-after-erase-'..index)end
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
   assignments('assignments-empty')
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
   assignments('assignments-after-exit')
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
