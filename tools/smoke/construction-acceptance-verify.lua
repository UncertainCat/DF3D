-- Native readback only, except explicit fixture cleanup/pause; no DF3D commands.
local out,index=...
local json=require('json')
local state=df3d_construction_acceptance
if index=='pause' then df.global.pause_state=true;print('SEMANTIC_PASS paused');return end
if index=='final' then assert(df.global.pause_state,'DF not paused');if state then assert(df.global.d_init.feature.autosave==df.d_init_autosave.NONE) end;print('SEMANTIC_PASS final paused');return end
if index=='restore_prefs' then
 assert(df.global.pause_state,'DF must be paused before restoring fixture preferences')
 if not state then print('SEMANTIC_PASS restored fixture preferences (fixture not started)');return end
 df.global.d_init.feature.autosave=state.prefs.autosave
 for id,value in pairs(state.prefs.announcements) do df.global.d_init.announcements.flags[id].whole=value end
 print('SEMANTIC_PASS restored fixture preferences');return
end
assert(state,'fixture state absent')
local function read(path) local f=assert(io.open(path));local s=f:read('*a');f:close();return s end
local request=json.decode(read(out..'/request-'..index..'.json'))
local result={status='passed'}
local function incomplete(reason) result.status='incomplete';result.reason=reason end
local function tick() return df.global.cur_year*403200+df.global.cur_year_tick end
local function fingerprint()
 local rows={}
 for _,b in ipairs(df.global.world.buildings.all) do rows[#rows+1]={id=b.id,type=b:getType(),subtype=b:getSubtype()} end
 table.sort(rows,function(a,b)return a.id<b.id end)
 local parts={};for _,row in ipairs(rows) do parts[#parts+1]=row.id..':'..row.type..':'..row.subtype end
 return table.concat(parts,'|')
end
local function definition(key)
 local family,subtype,code=key:match('^([^:]+):?([^:]*):?(.*)$')
 local enums={Workshop=df.workshop_type,Furnace=df.furnace_type,Trap=df.trap_type,SiegeEngine=df.siegeengine_type,Construction=df.construction_type}
 local custom=-1
 if code~='' then for _,v in ipairs(df.global.world.raws.buildings.all) do if v.code==code then custom=v.id;break end end end
 return df.building_type[family],enums[family] and enums[family][subtype] or -1,custom,family
end
local function key(item) return table.concat({item:getType(),item:getSubtype(),item:getMaterial(),item:getMaterialIndex()},':') end
local function row_key(r) return table.concat({r.item_type,r.item_subtype,r.mat_type,r.mat_index},':') end
-- Independent Trade depot readback: its building-material filter accepts blocks,
-- boulders, wood and bars. Compare every eligible identity/count and nearest
-- distance, including the fixture's binned and forbidden stacks.
local function materials()
 local groups={}
 for _,u in ipairs(df.global.world.units.active) do
  if dfhack.units.isActive(u) and not dfhack.units.isDead(u) and (dfhack.units.isCitizen(u) or dfhack.units.isResident(u)) then groups[dfhack.maps.getWalkableGroup(xyz2pos(dfhack.units.getPosition(u)))]=true end
 end
 groups[0]=nil
 local typ,sub,custom=definition(request.definition)
 local raw=assert(dfhack.buildings.getFiltersByType({},typ,sub,custom)[request.filter+1])
 local j=df.job_item:new();j:assign(raw)
 local expected,eligible={},{}
 local function excluded(item)
  for _,flag in ipairs{'dump','forbid','garbage_collect','hostile','on_fire','rotten','trader','in_building','construction','in_job','owned','removed','encased','spider_web'} do if item.flags[flag] then return true end end
  return false
 end
 local ok,err=pcall(function()
 for _,item in ipairs(df.global.world.items.all) do
  -- Lua API.rst:2179 / LuaApi.cpp:2583-2584 returns x,y,z, not a coord.
  local x,y,z=dfhack.items.getPosition(item);local p=x and {x=x,y=y,z=z}
  local flags=p and dfhack.maps.getTileFlags(p)
  local container=dfhack.items.getContainer(item);local ground=container or item;local depth=0
  local cart=container and container:getType()==df.item_type.TOOL and container:hasToolUse(df.tool_uses.HEAVY_OBJECT_HAULING)
  while container and depth<16 do ground=container;container=dfhack.items.getContainer(container);depth=depth+1 end
  local mi=dfhack.matinfo.decode(item);local token=mi and mi:getToken() or ''
  local badbar=item:getType()==df.item_type.BAR and (token:match('^COAL:') or token=='ASH' or (mi and mi.material.flags.SOAP))
  if not cart and not container and flags and not flags.hidden and groups[dfhack.maps.getWalkableGroup(p)]
   and not excluded(item) and not excluded(ground) and ground.flags.on_ground and not item:isAssignedToStockpile()
   and item:isBuildMat() and not badbar and mi and mi:toString()~=''
   and dfhack.job.isSuitableItem(j,item:getType(),item:getSubtype())
   and dfhack.job.isSuitableMaterial(j,item:getMaterial(),item:getMaterialIndex(),item:getType()) then
   local k=key(item);local r=expected[k] or {count=0,distance=math.huge};expected[k]=r
   r.count=r.count+1;r.distance=math.min(r.distance,(p.x-request.origin.x)^2+(p.y-request.origin.y)^2+(p.z-request.origin.z)^2)
   eligible[item.id]=true
  end
 end
 end);j:delete();assert(ok,err)
 local previous=-1;local previous_tuple
 for _,r in ipairs(request.rows) do
  local k=row_key(r);local e=assert(expected[k],'unexpected material '..k)
  assert(r.count==e.count,'material count mismatch '..k)
  assert(e.distance>=previous,'materials not distance-sorted')
  local tuple={r.item_type,r.item_subtype,r.mat_type,r.mat_index}
  if e.distance==previous and previous_tuple then
   for i=1,4 do if tuple[i]~=previous_tuple[i] then assert(tuple[i]>previous_tuple[i],'distance tie ordering');break end end
  end
  previous=e.distance;previous_tuple=tuple;expected[k]=nil
 end
 assert(next(expected)==nil,'eligible material group omitted')
 if state.forbidden then assert(not eligible[state.forbidden],'forbidden stack included') else incomplete('forbidden stack unavailable') end
 if state.incomplete.forbidden_stack then incomplete(state.incomplete.forbidden_stack) end
 if #state.binned==0 then incomplete('binned items unavailable') end
 for _,id in ipairs(state.binned) do assert(eligible[id],'binned block excluded') end
end
local function verify()
 local op=request.op
 if op=='guard_before' then assert(df.global.pause_state);state.guard=fingerprint()
 elseif op=='guard_after' then assert(df.global.pause_state and state.guard==fingerprint(),'refusal changed sorted building ids/types')
 elseif op=='status' then assert(df.global.pause_state)
 elseif op=='materials' then materials()
 elseif op=='mask' then
  local p=request.origin;local mask={};local skipped=0
  for dz=0,request.depth-1 do for dy=0,request.height-1 do for dx=0,request.width-1 do
   local q={x=p.x+dx,y=p.y+dy,z=p.z+dz};local _,occ=dfhack.maps.getTileFlags(q)
   local valid=occ and occ.building==0 and 1 or 0;mask[#mask+1]=valid;skipped=skipped+1-valid
  end end end
  assert(#mask==#request.mask,'Preview mask length disagrees with native occupancy')
  for i,value in ipairs(mask) do assert(value==request.mask[i],'Preview mask disagrees with native occupancy') end
  state.expected_mask=mask;result.skipped=skipped
 elseif op=='placed' then
  local p=request.origin;local typ,sub,custom,family=definition(request.definition)
  local count=0;local skipped=0;local ids={}
  local mode=request.mode
  for dz=0,request.depth-1 do for dy=0,request.height-1 do for dx=0,request.width-1 do
   if mode>=3 or (dx==0 and dy==0 and dz==0) then
    local q={x=p.x+dx,y=p.y+dy,z=p.z+dz};local b=dfhack.buildings.findAtTile(q)
    local ordinal=dx+request.width*(dy+request.height*dz)+1
    if request.mask[ordinal]==0 then skipped=skipped+1
    else
     assert(b and b:getType()==typ,'placed type missing')
     local expected=sub
     if request.definition=='Construction:Stairs' then expected=({df.construction_type.UpStair,df.construction_type.UpDownStair,df.construction_type.DownStair})[dz+1] end
     assert(b:getSubtype()==expected,'placed subtype/stair level mismatch')
     if custom>=0 then assert(b:getCustomType()==custom,'custom building mismatch') end
     -- df-structures df.building.xml:1319,1369: direction (enum screw_pump_direction).
     if family=='ScrewPump' or family=='Rollers' then assert(b.direction==request.direction,'pump/roller direction') end
     if family=='WaterWheel' or family=='AxleHorizontal' then assert(b.is_vertical==(request.direction==1),'wheel direction') end
     if family=='Bridge' then assert(b.direction==(request.retracting and -1 or request.direction),'bridge direction') end
     if family=='SiegeEngine' then assert(b.facing==request.direction and b.resting_orientation==request.direction,'eight-facing siege orientation') end
     if request.weapon_count then
      local raw=assert(dfhack.buildings.getFiltersByType({},typ,sub,custom)[2])
      local filter=df.job_item:new();filter:assign(raw)
      local n,seen=0,{}
      local function count_item(item)
       if item and not seen[item.id] and dfhack.job.isSuitableItem(filter,item:getType(),item:getSubtype())
        and dfhack.job.isSuitableMaterial(filter,item:getMaterial(),item:getMaterialIndex(),item:getType()) then
        seen[item.id]=true;n=n+1
       end
      end
      local ok,err=pcall(function()
       for _,entry in ipairs(b.contained_items) do count_item(entry.item) end
       for _,job in ipairs(b.jobs) do for _,ref in ipairs(job.items) do count_item(ref.item) end end
      end)
      filter:delete();assert(ok,err)
      assert(n==request.weapon_count,'trap selected weapon count')
     end
     count=count+1;ids[#ids+1]=b.id;state.placed[b.id]=request.definition
    end
   end
  end end end
  assert(count==request.placed and skipped==request.skipped,'Place counts disagree with native buildings')
  result.ids=ids
 elseif op=='exists' then
  -- Independent world-vector and tile probes distinguish deletion from an ID
  -- lookup failure. Record coordinates even when the bridge cannot inspect.
  local by_id=df.building.find(request.id);local in_world
  for _,b in ipairs(df.global.world.buildings.all) do if b.id==request.id then in_world=b;break end end
  local at_tile=dfhack.buildings.findAtTile(request.origin)
  result.id=request.id;result.phase=request.phase
  result.found_by_id=by_id~=nil;result.found_in_world=in_world~=nil
  result.tile_id=at_tile and at_tile.id or -1
  local b=in_world or by_id
  if b then
   result.custom_type=b:getCustomType()
   result.bounds={x1=b.x1,y1=b.y1,x2=b.x2,y2=b.y2,z=b.z}
   result.center={x=b.centerx,y=b.centery,z=b.z}
   local flags=dfhack.maps.getTileFlags(result.center)
   result.center_loaded=flags~=nil;result.center_hidden=flags and flags.hidden or false
  end
 elseif op=='removed' then
  local b=df.building.find(request.id)
  assert(not b or dfhack.buildings.markedForRemoval(b),'deconstruct did not act immediately')
 elseif op=='site_clear' then
  assert(df.global.pause_state,'site reuse must remain paused')
  result.clear=true
  for dx=0,request.width-1 do for dy=0,request.height-1 do
   local p={x=request.origin.x+dx,y=request.origin.y+dy,z=request.origin.z}
   local _,occ=dfhack.maps.getTileFlags(p)
   if not occ or occ.building~=0 or dfhack.buildings.findAtTile(p) then result.clear=false end
  end end
  if not result.clear then incomplete('sequential site still occupied after removal') end
 elseif op=='removed_construction' then
  local f=dfhack.maps.getTileFlags(request.origin)
  assert(f.dig~=df.tile_dig_designation.No,'RemoveConstruction did not designate removal')
 elseif op=='wait_start' then
  assert(df.global.pause_state and df.global.d_init.feature.autosave==df.d_init_autosave.NONE)
  local top=dfhack.gui.getCurViewscreen(true)
  local focus=dfhack.gui.getFocusStrings(top)
  local popups=df.global.world.status.popups
  if #popups>0 then
   incomplete('wait requires no announcement popups (count='..#popups..', first='..dfhack.df2utf(popups[0].text)..')');return
  end
  if not (df.viewscreen_dwarfmodest:is_instance(top) and #focus==1 and focus[1]=='dwarfmode/Default') then
   incomplete('wait requires default fortress screen; screen='..table.concat(focus,','));return
  end
  state.wait={origin=request.origin,tick=tick(),wall=dfhack.getTickCount()};result.waiting=true
 elseif op=='wait_poll' then
  local w=assert(state.wait);local c=dfhack.constructions.findAtTile(w.origin)
  result.ticks=tick()-w.tick;result.wall_ms=dfhack.getTickCount()-w.wall
  result.waiting=not c
  if not c and df.global.pause_state then
   local focus=dfhack.gui.getFocusStrings(dfhack.gui.getCurViewscreen(true))
   result.waiting=false;incomplete('game paused mid-wait; screen='..table.concat(focus,',')..'; popup count='..#df.global.world.status.popups)
  elseif not c and (result.ticks<0 or result.ticks>=12000 or result.wall_ms>=900000) then result.waiting=false;incomplete('construction completion wait cap/interruption') end
 elseif op=='wait_finish' then assert(df.global.pause_state,'wait must re-pause')
 elseif op=='final' then assert(df.global.pause_state,'final pause missing')
 else error('unknown verification operation '..tostring(op)) end
end
local ok,err=pcall(verify)
if not ok then df.global.pause_state=true;result.status='failed';result.reason=tostring(err) end
local f=assert(io.open(out..'/response-'..index..'.json','w'));f:write(json.encode(result));f:close()
print((result.status=='failed' and 'SEMANTIC_FAIL ' or result.status=='incomplete' and 'SEMANTIC_INCOMPLETE ' or 'SEMANTIC_PASS ')..request.op..' '..json.encode(result))
