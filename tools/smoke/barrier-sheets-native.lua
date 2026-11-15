-- Native reference capture on the lane's paused disposable fortress.
local out,view,select_map,capture=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local sheet=df.global.game.main_interface.view_sheets
local result={buildings={},frame=df.global.world.frame_counter}
local fixtures={}
local function close()if sheet.open then gui.simulateInput(view,'LEAVESCREEN')end end
local ok,err=xpcall(function()
 for _,name in ipairs{'Hatch','GrateWall','GrateFloor','BarsVertical','BarsFloor'}do
  local kind=assert(df.building_type[name]);local b
  for _,candidate in ipairs(df.global.world.buildings.all)do
   local d=dfhack.maps.getTileFlags(candidate.centerx,candidate.centery,candidate.z)
   if candidate:getType()==kind and candidate:getBuildStage()==candidate:getMaxBuildStage() and d and not d.hidden and #candidate.jobs==0 then b=candidate;break end
  end
  local fixture=false
  if not b then
   for y=80,140,4 do for x=80,160,4 do
    local pos={x=x,y=y,z=165};local d,o=dfhack.maps.getTileFlags(pos)
    if d and not d.hidden and o and not o.item and not o.unit and not o.unit_grounded and not dfhack.buildings.findAtTile(pos)then
     local success,placed=pcall(dfhack.buildings.constructBuilding,{type=kind,pos=pos,full_rectangle=true})
     if success and placed then b=placed;break end
    end
   end;if b then break end end
   assert(b,'No fixture site for '..name)
   while #b.jobs>0 do assert(dfhack.job.removeJob(b.jobs[0]))end
   b:setBuildStage(b:getMaxBuildStage());b.flags.exists=true
   -- Same owned per-tile virtual used by native cancel-removal54c1f2.
   b:updateOccupancy(b.centerx,b.centery)
   fixtures[#fixtures+1]=b;fixture=true
  end
  close();view:render(dfhack.getTickCount());select_map(b)
  assert(sheet.open and sheet.active_sheet==df.view_sheet_type.BUILDING and sheet.active_id==b.id)
  local row={id=b.id,type=kind,name=name,tile={b.centerx,b.centery,b.z},fixture=fixture,lines={},items={}}
  for _,held in ipairs(b.contained_items)do row.items[#row.items+1]={id=held.item.id,type=held.item:getType(),use_mode=held.use_mode}end
  for y=4,g.dimy-1 do
   local chars={};for x=52,112 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
   local text=dfhack.df2utf(table.concat(chars)):gsub('%s+$','');if text:find('%S')then row.lines[#row.lines+1]={y=y,text=text}end
  end
  row.flags=(kind==df.building_type.Hatch and b.door_flags or b.gate_flags).whole
  capture('barrier-sheet-'..kind);result.buildings[#result.buildings+1]=row
  if kind==df.building_type.Hatch then
   local original=b.door_flags.whole
   local reindex=df.global.world.reindex_pathfinding
   local _,occupancy=dfhack.maps.getTileFlags(b.centerx,b.centery,b.z)
   local occupancy_before=occupancy.whole
   row.occupancy=occupancy_before
   row.controls={}
   local function click(x)
    g.precise_mouse_x=x;g.precise_mouse_y=154;g.mouse_x=x//8;g.mouse_y=12
    df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
    gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
    df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
   end
   local success,why=xpcall(function()
    for _,forbidden in ipairs{true,false}do
     df.global.world.reindex_pathfinding=false
     click(forbidden and 852 or 876)
     assert(b.door_flags.forbidden==forbidden and occupancy.whole==occupancy_before and df.global.world.reindex_pathfinding)
     row.controls[#row.controls+1]={forbidden=forbidden,flags=b.door_flags.whole,occupancy=occupancy.whole,reindex=df.global.world.reindex_pathfinding}
     capture(forbidden and 'barrier-hatch-forbidden' or 'barrier-hatch-passable')
    end
   end,debug.traceback)
   b.door_flags.whole=original;df.global.world.reindex_pathfinding=reindex
   assert(success,why);assert(occupancy.whole==occupancy_before)
   row.controls_restored=true
  end
 end
 if os.getenv('DF3D_BARRIER_WIRE')=='1' or os.getenv('DF3D_BARRIER_SCENE')=='1'then
  local f=assert(io.open(out..'/barrier-wire-expected.json','w'));f:write(json.encode(result));f:close()
  local labels={}
  if os.getenv('DF3D_BARRIER_WIRE')=='1'then labels[#labels+1]='barrier-wire'end
  if os.getenv('DF3D_BARRIER_SCENE')=='1'then labels[#labels+1]='barrier-scene'end
  for _,label in ipairs(labels)do
  local active_id=sheet.active_id
  local reindex=df.global.world.reindex_pathfinding;df.global.world.reindex_pathfinding=false
  capture(label)
  f=assert(io.open(out..'/'..label..'-result.json'));result[label]=json.decode(f:read('*a'));f:close()
  assert(result[label].success and sheet.active_id==active_id)
  for _,row in ipairs(result.buildings)do
   local b=assert(df.building.find(row.id));assert(#b.jobs==0)
   assert((row.type==35 and b.door_flags or b.gate_flags).whole==row.flags)
   if row.type==35 then
    local _,occupancy=dfhack.maps.getTileFlags(b.centerx,b.centery,b.z)
    assert(occupancy.whole==row.occupancy and df.global.world.reindex_pathfinding)
   end
  end
  df.global.world.reindex_pathfinding=reindex
  end
 end
end,debug.traceback)
close()
for _,b in ipairs(fixtures)do b:setBuildStage(0);b.flags.exists=false;assert(dfhack.buildings.deconstruct(b))end
assert(ok,err);assert(df.global.world.frame_counter==result.frame)
result.success=true
local f=assert(io.open(out..'/barrier-sheets-native.json','w'));f:write(json.encode(result));f:close()
return result
