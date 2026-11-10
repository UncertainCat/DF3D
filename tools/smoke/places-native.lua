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
local info=df.global.game.main_interface.info
local function menu_snapshot()
 local result={open=info.open,mode=info.current_mode,places_mode=info.buildings.mode,lists={}}
 for mode=0,5 do
  local ids={};for _,building in ipairs(info.buildings.list[mode])do ids[#ids+1]=building.id end
  local _,address=df.sizeof(info.buildings.list[mode]);local allocation={}
  for offset=0,16,8 do allocation[#allocation+1]=tostring(df.reinterpret_cast('uint64_t',address+offset).value)end
  result.lists[#result.lists+1]={ids=ids,allocation=allocation,scroll=info.buildings.scrolling_position[mode],drag=info.buildings.scrolling[mode]}
 end
 return json.encode(result)
end
local function probe(command)
 local before=menu_snapshot();local text,rc=dfhack.run_command_silent('df3d',command or 'places-lists-probe')
 assert(rc==0,'Owned Places provider failed: '..text);assert(menu_snapshot()==before,'Owned Places provider changed native menu storage')
 return json.decode(text)
end
local secondary_fixture
if os.getenv('DF3D_PLACES_SECONDARY')=='1' then
 local path=debug.getinfo(1,'S').source:sub(2):gsub('places%-native.lua$','residents-job-create-native.lua')
 local first=assert(loadfile(path))(out,view);gui.simulateInput(view,'LEAVESCREEN');settle()
 local second=assert(loadfile(path))(out,view);gui.simulateInput(view,'LEAVESCREEN');settle()
 local holder;for _,ref in ipairs(first.general_refs)do if ref:getType()==df.general_ref_type.BUILDING_HOLDER then holder=ref:getBuilding();break end end
 assert(holder and #holder.jobs==2 and holder.jobs[1]==second,'Places two-job fixture missing')
 local profile=assert(holder:getWorkshopProfile());local workers={};for _,id in ipairs(profile.permitted_workers)do workers[#workers+1]=id end
 assert(df.unit.find(5697),'Places worker fixture missing');profile.permitted_workers:resize(0);profile.permitted_workers:insert('#',5697)
 local farm=assert(df.global.world.buildings.other.FARM_PLOT[0]);local season=df.global.cur_season;local crop=farm.plant_id[season];farm.plant_id[season]=-1
 secondary_fixture={building_id=holder.id,worker_id=5697,job_ids={first.id,second.id},farm_id=farm.id,season=season,original_crop=crop,original_workers=workers}
end
local pen_fixture
if os.getenv('DF3D_PLACES_PEN')=='1' then
 local zone=assert(df.building.find(244));assert(zone.type==88,'Places pen fixture changed')
 local animal;for _,unit in ipairs(df.global.world.units.active)do
  if dfhack.units.isAnimal(unit) and not unit.flags1.caged and not unit.flags1.inactive and unit.pos.x>=0 then animal=unit;break end
 end
 assert(animal,'No live uncaged animal for Places pen fixture')
 local ids={};for _,id in ipairs(zone.assigned_units)do ids[#ids+1]=id end
 pen_fixture={zone_id=zone.id,unit_id=animal.id,assigned=ids,position={animal.pos.x,animal.pos.y,animal.pos.z}}
 local target;for y=0,zone.room.height-1 do for x=0,zone.room.width-1 do if zone.room.extents[y*zone.room.width+x]~=0 then target={x=zone.room.x+x,y=zone.room.y+y,z=zone.z};break end end;if target then break end end
 assert(target,'Pen has no included tile');zone.assigned_units:resize(0);zone.assigned_units:insert('#',animal.id);animal.pos=target
end
local cold=probe()
local cold_rows=probe('places-building-rows-probe')
gui.simulateInput(view,'D_LOCATIONS');settle()
assert(info.open and info.current_mode==df.info_interface_mode_type.BUILDINGS,'Places shortcut did not open native Buildings')
local warm=probe()
local warm_rows=probe('places-building-rows-probe')
assert(json.encode(cold_rows)==json.encode(warm_rows),'Places building rows depend on menu initialization')
for mode=0,5 do
 local ids={};for _,building in ipairs(info.buildings.list[mode])do ids[#ids+1]=building.id end
 assert(json.encode(ids)==json.encode(cold[mode+1]) and json.encode(ids)==json.encode(warm[mode+1]),'Owned Places order differs in mode '..mode)
 for i,building in ipairs(info.buildings.list[mode])do
  local row=cold_rows[mode+1][i+1]
  assert(row.id==building.id and json.encode(row.position)==json.encode({building.centerx,building.centery,building.z}),'Places building identity/position mismatch')
 end
end
local result={initial_mode=info.buildings.mode,pages={},owned={cold=cold,warm=warm,menu_preserved=true},building_rows={rows=cold_rows,cold_warm_equal=true,visible_names={}}}
result.secondary_fixture=secondary_fixture
result.pen_fixture=pen_fixture
result.zone_subtitle_sources={}
for _,row in ipairs(cold_rows[1])do
 local zone=assert(df.building.find(row.id));local kind='none'
 if zone.site_id~=-1 and zone.location_id~=-1 then kind='location'
 elseif zone.assigned_unit_id~=-1 then kind=df.unit.find(zone.assigned_unit_id) and 'present_owner' or 'absent_owner'
 elseif #zone.squad_room_info>1 then kind='multiple_squads'
 elseif #zone.squad_room_info==1 then kind='one_squad' end
 result.zone_subtitle_sources[#result.zone_subtitle_sources+1]={id=row.id,kind=kind}
end
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
 assert(json.encode(probe())==json.encode(cold),'Owned Places lists depend on selected tab')
 assert(found,'Native Places tab missing: '..caption)
 do
  local mode=page.mode;local rows=cold_rows[mode+1];local checked={}
  -- Discovery oracle only: page the native list to observe every existing name.
  -- Runtime row production never reads this menu or its scroll position.
  for first=0,#rows-1,15 do
   info.buildings.scrolling_position[mode]=math.min(first,math.max(0,#rows-15));settle()
   local actual=info.buildings.scrolling_position[mode]
   for visible=0,math.min(14,#rows-actual-1)do
    local index=actual+visible+1;local name=dfhack.utf2df(rows[index].name)
    local chars={};for x=13,13+#name-1 do chars[#chars+1]=string.char(dfhack.screen.readTile(x,15+visible*3).ch)end
    if table.concat(chars)~=name then
     result.name_mismatch={caption=caption,index=index,requested_first=first,actual_first=actual,expected=rows[index].name,observed=dfhack.df2utf(table.concat(chars)),lines=lines()};save()
     error('Native Places name mismatch: '..caption..' row '..index)
    end
    if mode<=4 then
     local secondary={};for x=13,g.dimx-1 do local ch=dfhack.screen.readTile(x,16+visible*3).ch;secondary[#secondary+1]=ch>=32 and ch<=255 and string.char(ch) or ' ' end
     local subtitle=dfhack.utf2df(rows[index].subtitle)
     assert(table.concat(secondary):sub(1,#subtitle)==subtitle,'Places subtitle mismatch: '..caption..' row '..index)
     if rows[index].secondary_status~='' then assert(table.concat(secondary):find(dfhack.utf2df(rows[index].secondary_status),1,true),'Places secondary status mismatch: '..caption..' row '..index)end
     local status=mode==3 and rows[index].job_caption or rows[index].status_caption
     if status~='' then
      local primary={};for x=13,g.dimx-1 do local ch=dfhack.screen.readTile(x,15+visible*3).ch;primary[#primary+1]=ch>=32 and ch<=255 and string.char(ch) or ' ' end
      assert(table.concat(primary):find(dfhack.utf2df(status),1,true),'Places status caption mismatch: '..caption..' row '..index)
     end
    end
    checked[index]=true
   end
  end
  for i=1,#rows do assert(checked[i],'Places name was not observed: '..caption..' row '..i)end
  result.building_rows.visible_names[#result.building_rows.visible_names+1]={mode=mode,count=#rows}
  info.buildings.scrolling_position[mode]=0;settle();save()
 end
end
gui.simulateInput(view,'LEAVESCREEN');settle();assert(not info.open,'Places did not close')
if secondary_fixture then
 local profile=df.building.find(secondary_fixture.building_id):getWorkshopProfile();profile.permitted_workers:resize(0)
 for _,id in ipairs(secondary_fixture.original_workers)do profile.permitted_workers:insert('#',id)end
 df.building.find(secondary_fixture.farm_id).plant_id[secondary_fixture.season]=secondary_fixture.original_crop
end
if pen_fixture then
 local zone=df.building.find(pen_fixture.zone_id);zone.assigned_units:resize(0);for _,id in ipairs(pen_fixture.assigned)do zone.assigned_units:insert('#',id)end
 local p=pen_fixture.position;df.unit.find(pen_fixture.unit_id).pos={x=p[1],y=p[2],z=p[3]}
end
result.closed=true;save();records[#records+1]={name='places-discovery',pages=#result.pages,closed=true}
