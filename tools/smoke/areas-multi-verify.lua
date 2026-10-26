-- Independent native readbacks for the protected region5 Multi protocol lane.
-- Native fixture edits are explicit stale-target setup/cleanup, never commands.
local out,index=...
local json=require('json')
local function read(path)local f=assert(io.open(path));local s=f:read('*a');f:close();return json.decode(s)end
local function write(path,v)local f=assert(io.open(path,'w'));f:write(json.encode(v));f:close()end
local request=read(out..'/request-'..index..'.json')
local function snapshot(b)
 local row={id=b.id,type=b.type,x=b.x1,y=b.y1,z=b.z,width=b.x2-b.x1+1,height=b.y2-b.y1+1,
  active=b.spec_sub_flag.active,owner=b.assigned_unit_id,location=b.location_id,name=b.name,flags=b.flags.whole,extents={}}
 for y=b.y1,b.y2 do for x=b.x1,b.x2 do row.extents[#row.extents+1]=b.room.extents[(y-b.room.y)*b.room.width+x-b.room.x] end end
 return row
end
local function inventory()
 local rows={}
 for _,b in ipairs(df.global.world.buildings.other.ANY_ZONE)do rows[tostring(b.id)]=snapshot(b)end
 return rows
end
local function furniture_links()
 local rows={}
 for _,b in ipairs(df.global.world.buildings.all)do
  if not df.building_civzonest:is_instance(b)then
   local links={};for _,zone in ipairs(b.relations)do links[#links+1]=zone.id end;table.sort(links)
   rows[tostring(b.id)]=links
  end
 end
 return rows
end
local function same(a,b)
 if type(a)~=type(b)then return false end
 if type(a)~='table'then return a==b end
 for k,v in pairs(a)do if not same(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end
 return true
end
local function native_fields(b)
 local contained={};for _,v in ipairs(b.contained_buildings)do contained[#contained+1]=v.id end;table.sort(contained)
 return {type=df.civzone_type[b.type],x1=b.x1,x2=b.x2,y1=b.y1,y2=b.y2,z=b.z,
  extents=snapshot(b).extents,contained=contained,flags=b.flags.whole,active=b.spec_sub_flag.whole,
  assigned=b.assigned_unit_id,owner_index=b.owner_unit_cached_index,site=b.site_id,location=b.location_id,
  race=b.race,tomb_no_pets=b.type==df.civzone_type.Tomb and b.zone_settings.tomb.flags.no_pets or false,
  tomb_no_citizens=b.type==df.civzone_type.Tomb and b.zone_settings.tomb.flags.no_citizens or false}
end
local result={status='passed'}
local ok,err=pcall(function()
 assert(df.global.pause_state,'fixture must remain paused')
 if request.op=='multi_search_begin' then
  assert(not _G.df3d_multi_search_guards,'search guard already active')
  local guards={};_G.df3d_multi_search_guards=guards
  for _,b in ipairs(df.global.world.map.map_blocks)do for _,field in ipairs{'path_cost','path_tag'}do
   local size,address=df.sizeof(b[field]);local copy=df.new('uint8_t',size)
   dfhack.internal.memmove(copy,address,size);guards[#guards+1]={copy=copy,address=address,size=size}
  end end
  result.scratch_guards=#guards
 elseif request.op=='multi_search_end' then
  local guards=assert(_G.df3d_multi_search_guards);local changed=0
  for _,g in ipairs(guards)do
   if dfhack.internal.memcmp(g.copy,g.address,g.size)~=0 then changed=changed+1 end
   df.delete(g.copy)
  end
  _G.df3d_multi_search_guards=nil;result.scratch_guards=#guards;result.changed_guards=changed
  assert(changed==0,'Multi operation changed map search scratch')
 elseif request.op=='multi_tiles_reference' then
  local reference=read(out..'/multi-tiles-reference.json')
  local saved={}
  for y=reference.y,reference.y+reference.height-1 do for x=reference.x,reference.x+reference.width-1 do
   local b=assert(dfhack.maps.getTileBlock({x=x,y=y,z=reference.z}))
   saved[#saved+1]={b=b,x=x%16,y=y%16,tile=b.tiletype[x%16][y%16],
    designation=b.designation[x%16][y%16].whole,occupancy=b.occupancy[x%16][y%16].whole}
  end end
  local function restore()
   for _,v in ipairs(saved)do
    v.b.tiletype[v.x][v.y]=v.tile;v.b.designation[v.x][v.y].whole=v.designation
    v.b.occupancy[v.x][v.y].whole=v.occupancy
   end
  end
  local passed={}
  local matched,why=pcall(function()
   for _,case in ipairs(reference.cases)do
    restore()
    for i,v in ipairs(saved)do
     v.b.tiletype[v.x][v.y]=reference.tiles[i];v.b.designation[v.x][v.y].hidden=false
    end
    local q=assert(dfhack.maps.getTileBlock({x=173,y=57,z=164}))
    for y=54,60 do q.tiletype[13][y%16]=reference.tiles[1] end
    assert(df.tiletype[case.tiletype]==case.tile_name,'native tile definition changed')
    q.tiletype[13][9]=case.tiletype
    local occupancy=case.name:match('^occ_(.+)$')
    if occupancy then
     local key=occupancy:sub(1,1):upper()..occupancy:sub(2)
     q.occupancy[13][9].building=assert(df.tile_building_occ[key])
    end
    local liquid,depth=case.name:match('^liquid_(%a+)_(%d)$')
    if liquid then
     q.designation[13][9].liquid_type=liquid=='magma' and df.tile_liquid.Magma or df.tile_liquid.Water
     q.designation[13][9].flow_size=tonumber(depth)
    end
    local output,status=dfhack.run_command_silent('df3d','room-read','172','57','164')
    assert(status==0,output);local observed=json.decode(output)
    assert(observed.status==0,'native tile reference did not complete: '..case.name)
    local count=0
    for i,v in ipairs(observed.extents)do if v~=0 then count=count+1 end end
    local expected=0
    for y=reference.y,reference.y+reference.height-1 do for x=reference.x,reference.x+reference.width-1 do
     local i=(y-reference.y)*reference.width+x-reference.x+1
     local value=tonumber(case.expected_mask:sub(i,i));expected=expected+value
     assert(observed.extents[(y-observed.y)*observed.width+x-observed.x+1]==value,'native tile mask differs: '..case.name..' at '..x..','..y)
    end end
    assert(count==expected,'native tile reference escaped bounds: '..case.name)
    passed[#passed+1]=case.name
   end
  end)
  restore()
  for _,v in ipairs(saved)do
   assert(v.b.tiletype[v.x][v.y]==v.tile and v.b.designation[v.x][v.y].whole==v.designation and
    v.b.occupancy[v.x][v.y].whole==v.occupancy,'tile reference restoration failed')
  end
  result.cases=passed;assert(matched,why)
 elseif request.op=='multi_begin' then
  local bed=assert(df.building.find(1310),'source bed missing')
  assert(df.building_bedst:is_instance(bed) and bed.centerx==172 and bed.centery==57 and bed.z==164,'source bed changed')
  for _,b in ipairs(df.global.world.buildings.other.BED)do assert(b.centerx~=0 or b.centery~=0 or b.z~=164,'empty selection contains a bed')end
  _G.df3d_multi_test={baseline=inventory(),links=furniture_links(),frame=df.global.world.frame_counter}
  write(out..'/multi-baseline.json',_G.df3d_multi_test.baseline)
  write(out..'/multi-links-baseline.json',_G.df3d_multi_test.links)
  result.origin={172,57,164}
 else
  local fixture=assert(_G.df3d_multi_test,'missing Multi fixture')
  assert(df.global.world.frame_counter==fixture.frame,'paused simulation advanced')
  local now=inventory();local created={}
  write(out..'/multi-observed-'..index..'.json',now)
  for id,row in pairs(now)do if not fixture.baseline[id]then created[#created+1]=row end end
  table.sort(created,function(a,b)return a.id<b.id end)
  if request.op=='multi_case_prepare' then
   assert(not fixture.current and same(fixture.baseline,now),'case must start from exact baseline')
   local reference=read(out..'/multi-reference.json')
   local case
   for _,v in ipairs(reference.cases)do if v.name==request.case then case=v;break end end
   assert(case,'unknown native reference case')
   local seed=assert(df.building.find(case.seed),'source furniture missing')
   fixture.current={reference=case}
   local current=fixture.current
   current.zones={}
   local release=case.release_zones or (case.release_zone and {case.release_zone} or {})
   for _,id in ipairs(release)do
    local zone=assert(df.building.find(id));current.zones[id]=zone.type
    zone.type=df.civzone_type.WaterSource
   end
   if case.opening then
    local p=case.opening;local block=assert(dfhack.maps.getTileBlock(p[1],p[2],p[3]))
    current.opening=p;current.tile=block.tiletype[p[1]%16][p[2]%16]
    current.occupancy=block.occupancy[p[1]%16][p[2]%16].whole
    current.designation=block.designation[p[1]%16][p[2]%16].whole
    local source=assert(dfhack.maps.getTileBlock(172,57,164))
    block.tiletype[p[1]%16][p[2]%16]=case.opening_tile and assert(df.tiletype[case.opening_tile]) or source.tiletype[172%16][57%16]
    if case.opening_occupancy then block.occupancy[p[1]%16][p[2]%16].building=assert(df.tile_building_occ[case.opening_occupancy]) end
    if case.opening_depth then
     block.designation[p[1]%16][p[2]%16].flow_size=case.opening_depth
     block.designation[p[1]%16][p[2]%16].liquid_type=case.opening_magma or false
    end
   end
   current.baseline=inventory()
   result.selection={furniture=case.furniture,x=seed.centerx,y=seed.centery,z=seed.z,width=case.width}
   result.count=#case.rooms;result.in_use=case.in_use;result.unenclosed=case.unenclosed;result.dormitories=0
   for _,room in ipairs(case.rooms)do if room.type=='Dormitory'then result.dormitories=result.dormitories+1 end end
  elseif request.op=='multi_case_check' then
   local current=assert(fixture.current,'missing native case')
   local expected=request.removed and {} or current.reference.rooms
   assert(#created==#expected,'native case room count differs')
   result.rooms={}
   for i,row in ipairs(created)do
    local b=assert(df.building.find(row.id));local fields=native_fields(b)
    result.rooms[i]=fields
    assert(same(expected[i],fields),'native reference fields differ for room '..i)
    for _,furniture in ipairs(b.contained_buildings)do
     local found=false;for _,zone in ipairs(furniture.relations)do if zone.id==b.id then found=true end end
     assert(found,'missing reverse furniture relation')
    end
   end
   for id,row in pairs(current.baseline)do assert(same(row,now[id]),'existing zone changed in native case '..id)end
   if request.removed then assert(same(fixture.links,furniture_links()),'Undo left changed furniture links')end
  elseif request.op=='multi_case_stale' then
   assert(fixture.current and #created==2,'stale-set fixture requires two rooms')
   df.building.find(created[2].id).name='native second-target stale fixture'
  elseif request.op=='multi_case_cleanup' then
   assert(fixture.current,'missing native case')
   for _,row in ipairs(created)do assert(dfhack.buildings.deconstruct(df.building.find(row.id)),'case cleanup failed')end
   assert(same(fixture.current.baseline,inventory()),'case cleanup changed existing zones')
   assert(same(fixture.links,furniture_links()),'case cleanup left changed furniture links')
  elseif request.op=='multi_case_restore' then
   local current=assert(fixture.current,'missing native case')
   assert(#created==0,'restore requires all created rooms already removed')
   for id,zone_type in pairs(current.zones)do df.building.find(id).type=zone_type end
   if current.opening then
    local p=current.opening;local block=assert(dfhack.maps.getTileBlock(p[1],p[2],p[3]))
    block.tiletype[p[1]%16][p[2]%16]=current.tile
    block.occupancy[p[1]%16][p[2]%16].whole=current.occupancy
    block.designation[p[1]%16][p[2]%16].whole=current.designation
    assert(block.tiletype[p[1]%16][p[2]%16]==current.tile,'terrain fixture not restored')
   end
   fixture.current=nil
   assert(same(fixture.baseline,inventory()),'native case did not restore original baseline')
   assert(same(fixture.links,furniture_links()),'native case did not restore furniture links')
  elseif request.op=='multi_check' then
   assert(#created==request.count,'unexpected native created count '..#created)
   for _,row in ipairs(created)do
    assert(row.type==df.civzone_type.Bedroom and row.x==169 and row.y==56 and row.z==164 and row.width==5 and row.height==5,'native room footprint/type differs from captured reference')
    assert(row.active and row.owner==-1 and row.location==-1,'native defaults differ')
    for _,extent in ipairs(row.extents)do assert(extent~=0,'native room has an unexpected hole')end
   end
  elseif request.op=='multi_stale' then
   assert(#created==1,'stale fixture needs one created room')
   df.building.find(created[1].id).name='native stale-target fixture'
  elseif request.op=='multi_cleanup' then
   for _,row in ipairs(created)do assert(dfhack.buildings.deconstruct(df.building.find(row.id)),'fixture cleanup failed')end
   assert(same(fixture.baseline,inventory()),'fixture cleanup did not restore native baseline')
   assert(same(fixture.links,furniture_links()),'fixture cleanup did not restore furniture links')
  elseif request.op=='multi_final' then
   assert(same(fixture.baseline,now),'native baseline changed')
   local links=furniture_links();write(out..'/multi-links-final.json',links)
   assert(same(fixture.links,links),'native furniture links changed')
  else error('unknown Multi verification operation')end
  result.created=created
 end
end)
if not ok then result.status='failed';result.reason=tostring(err)end
write(out..'/response-'..index..'.json',result)
if ok then print('SEMANTIC_PASS '..request.op)else error(result.reason)end
