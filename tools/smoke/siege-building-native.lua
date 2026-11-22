-- Protected building-sheet oracle for all three siege engine variants.
local out,view,first,select_map,capture=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local sheet=df.global.game.main_interface.view_sheets
local created,items={},{}
local engines={first};local result={engines={}}
local function probe(engine,revision,value,resting)
 return dfhack.with_suspend(function()
  local guards={}
  for _,storage in ipairs{g,df.global.game.main_interface}do
   local size,address=df.sizeof(storage);local copy=df.new('uint8_t',size)
   dfhack.internal.memmove(copy,address,size);guards[#guards+1]={size=size,address=address,copy=copy}
  end
  local args={'df3d','siege-state-probe',tostring(engine.id)}
  if revision then args[#args+1]=revision;args[#args+1]=tostring(value);args[#args+1]=resting and '1' or '0'end
  local text,code=dfhack.run_command_silent(table.unpack(args))
  local unchanged=true
  for _,guard in ipairs(guards)do
   unchanged=unchanged and dfhack.internal.memcmp(guard.copy,guard.address,guard.size)==0;df.delete(guard.copy)
  end
  assert(code==0,text);assert(unchanged,'Siege provider changed native UI storage')
  return json.decode(text)
 end)
end
local function click(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
end
local function lines()
 local rows={}
 for y=10,39 do local chars={}
  for x=54,110 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
  local text=dfhack.df2utf(table.concat(chars)):gsub('%s+$','');if text:find('%S')then rows[#rows+1]={y=y,text=text}end
 end
 return rows
end
local ok,err=xpcall(function()
 local worker
 for _,u in ipairs(df.global.world.units.active)do if dfhack.units.isCitizen(u)then worker=u;break end end
 local material=assert(dfhack.matinfo.find('PLANT:OAK:WOOD'))
 for subtype=1,2 do
  local building
  for y=80,140,4 do for x=80,160,4 do
   local clear=true
   for dy=0,2 do for dx=0,2 do
    local pos={x=x+dx,y=y+dy,z=165};local d,o=dfhack.maps.getTileFlags(pos)
    if not d or d.hidden or not o or o.item or o.unit or o.unit_grounded or dfhack.buildings.findAtTile(pos)then clear=false end
   end end
   if clear then local success,b=pcall(dfhack.buildings.constructBuilding,{type=df.building_type.SiegeEngine,subtype=subtype,pos={x=x,y=y,z=165},full_rectangle=true});if success and b then building=b;break end end
  end;if building then break end end
  assert(building,'No siege fixture site');created[#created+1]=building;engines[#engines+1]=building
  while #building.jobs>0 do assert(dfhack.job.removeJob(building.jobs[0]))end
  building:setBuildStage(building:getMaxBuildStage());building.flags.exists=true;building:updateOccupancy(building.centerx,building.centery)
  building.mat_type=material.type;building.mat_index=material.index
  for _=1,3 do
   local produced=dfhack.items.createItem(assert(worker),subtype==1 and df.item_type.BALLISTAPARTS or df.item_type.BOLT_THROWER_PARTS,-1,material.type,material.index)
   assert(#produced==1);items[#items+1]=produced[1];assert(dfhack.items.moveToBuilding(produced[1],building,2,true))
  end
 end
 for _,engine in ipairs(engines)do
  if sheet.open then gui.simulateInput(view,'LEAVESCREEN')end
  select_map(engine);view:render(dfhack.getTickCount())
  assert(sheet.open and sheet.active_id==engine.id,'Siege sheet selected wrong target')
  local before={action=engine.action,facing=engine.facing,resting=engine.resting_orientation,jobs=#engine.jobs}
  local row={id=engine.id,type=engine.type,tile={engine.centerx,engine.centery,engine.z},before=before,actions={}}
  capture('siege-'..engine.type..'-initial');row.lines=lines()
  if engine.type==2 then
   local source=debug.getinfo(1,'S').source:sub(2):gsub('siege%-building%-native.lua$','siege-ammunition-native.lua')
   row.ammunition=assert(loadfile(source))(engine,probe,view,lines,capture,worker,material)
  end
  for slot,action in ipairs{3,4,2,1,0}do
   local owned_before=probe(engine)
   click(780+(slot-1)*24,154)
   assert(engine.action==action and #engine.jobs==before.jobs,'Siege sheet action mapping differs')
   capture('siege-'..engine.type..'-action-'..action)
   local native_lines=lines()
   engine.action=owned_before.action
   local owned=probe(engine,owned_before.revision,action,false)
   assert(owned.outcome==1 and owned.effects_started and owned.action==action and owned.facing==before.facing and owned.resting==before.resting,'Owned siege mode differs')
   local stale=probe(engine,owned_before.revision,action,false)
   assert(stale.outcome==2 and not stale.effects_started,'Old siege revision accepted')
   row.actions[#row.actions+1]={action=action,lines=native_lines,owned=owned,stale=stale.outcome}
  end
  if engine.type==2 then
   row.orientations={}
   for _,direction in ipairs{1,2,3,4,5,6,7,0}do
    local owned_before=probe(engine)
    click(448+32*direction,226)
    assert(engine.resting_orientation==direction and engine.facing==before.facing and engine.action==0,'Native resting orientation differs')
    engine.resting_orientation=owned_before.resting
    local owned=probe(engine,owned_before.revision,direction,true)
    assert(owned.outcome==1 and owned.resting==direction and owned.facing==before.facing and owned.action==0,'Owned resting orientation differs')
    row.orientations[#row.orientations+1]=owned
   end
  end
  local source=debug.getinfo(1,'S').source:sub(2):gsub('siege%-building%-native.lua$','siege-jobs-native.lua')
  row.job_effects=assert(loadfile(source))(engine,probe,click)
  engine.action=before.action
  assert(engine.facing==before.facing and engine.resting_orientation==before.resting and #engine.jobs==before.jobs)
  result.engines[#result.engines+1]=row
 end
end,debug.traceback)
if sheet.open then gui.simulateInput(view,'LEAVESCREEN')end
for _,item in ipairs(items)do item.flags.in_building=false;assert(dfhack.items.remove(item))end
for _,b in ipairs(created)do b:setBuildStage(0);b.flags.exists=false;assert(dfhack.buildings.deconstruct(b))end
assert(ok,err)
result.success=true
local file=assert(io.open(out..'/siege-building-native.json','w'));file:write(json.encode(result));file:close()
return result
