-- Owned paused native oracle. Restore names/jobs before returning to item checks.
local out,view,records,building,capture,select_map=...
local gui=require('gui');local g=df.global.gps;local sheet=df.global.game.main_interface.view_sheets
local original=building.name;local frame=df.global.world.frame_counter
local function key(value)gui.simulateInput(view,value);view:render(dfhack.getTickCount())end
local function click(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12;key('_MOUSE_L')
end
local function text(value)for i=1,#value do key(('STRING_A%03d'):format(value:byte(i)))end end
local function shot(name)
 local row=capture('chest-header-'..name)
 row.custom_name=dfhack.df2utf(building.name);row.native_name=dfhack.df2utf(dfhack.buildings.getName(building))
 row.editing=sheet.building_entering_nickname;row.draft=dfhack.df2utf(sheet.building_entering_str)
 row.removing=dfhack.buildings.markedForRemoval(building);row.jobs={}
 local guards={}
 for _,object in ipairs{building,sheet,df.global.plotinfo}do
  local size,address=df.sizeof(object);local bytes=df.new('uint8_t',size);dfhack.internal.memmove(bytes,address,size)
  guards[#guards+1]={bytes=bytes,address=address,size=size}
 end
 for _,job in ipairs(building.jobs)do
  local size,address=df.sizeof(job);local bytes=df.new('uint8_t',size);dfhack.internal.memmove(bytes,address,size)
  guards[#guards+1]={bytes=bytes,address=address,size=size}
 end
 local text,status=dfhack.run_command_silent('df3d','building-header-read',tostring(building.id));assert(status==0,text)
 row.semantic=require('json').decode(text)
 for _,guard in ipairs(guards)do assert(dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)==0,'chest header changed building/job/UI');df.delete(guard.bytes)end
 assert(row.semantic.custom_name==row.custom_name and row.semantic.native_name==row.native_name and row.semantic.removing==row.removing,'chest semantic header differs')
 if sheet.open and sheet.active_sheet==df.view_sheet_type.BUILDING then
  local shown=row.lines[7]:sub(61,90):gsub('%s+$','')
  assert(shown==row.semantic.header_name or (row.editing and shown==row.semantic.header_name..'_'),'chest formatted caption differs')
 end
 assert(row.semantic.suspended==(row.removing and #building.jobs>0 and building.jobs[0].flags.suspend or false),'chest suspension state differs')
 row.guards_unchanged=true
 for _,job in ipairs(building.jobs)do row.jobs[#row.jobs+1]={id=job.id,type=job.job_type,suspended=job.flags.suspend}end
 assert(df.global.pause_state and df.global.world.frame_counter==frame,'chest header advanced simulation')
 return row
end
select_map(building)
click(800,82);text('lower chest');assert(building.name=='lower chest');shot('rename-draft')
key('SELECT');assert(not sheet.building_entering_nickname and sheet.open);shot('renamed')
click(800,82);text(' appended');key('LEAVESCREEN');assert(building.name=='lower chest appended' and not sheet.open);shot('rename-escape')
select_map(building);click(800,82);for i=1,100 do key('STRING_A000')end;text(string.rep('X',80))
assert(building.name==string.rep('X',30));shot('rename-limit');key('SELECT')
click(800,82);for i=1,100 do key('STRING_A000')end;text(original);key('SELECT');assert(building.name==original);shot('rename-restored')
assert(#building.jobs==0,'chest header fixture requires idle building')
click(832,82);assert(df.building.find(building.id)==building,'chest removed immediately')
assert(dfhack.buildings.markedForRemoval(building) and #building.jobs==1 and building.jobs[0].job_type==df.job_type.DestroyBuilding)
shot('remove');local job=building.jobs[0];local flags=job.flags.whole
click(772,526);local selected=capture('chest-header-removing-item-view')
selected.target_id=building.contained_items[0].item.id
selected.opened_item=sheet.open and sheet.active_sheet==df.view_sheet_type.ITEM and sheet.active_id==selected.target_id
if selected.opened_item then key('LEAVESCREEN');select_map(building)end
assert(sheet.open and sheet.active_sheet==df.view_sheet_type.BUILDING and sheet.active_id==building.id)

-- Native contents buttons remain visible while removal is queued. Observe their
-- actual effects before granting the presentation any additional edit authority.
local effects={}
for index=0,1 do
 local item=building.contained_items[index].item
 for _,control in ipairs{{'forbid',800},{'dump',824},{'hidden',872}}do
  local before=item.flags[control[1]]
  click(control[2],526+index*36)
  local changed=item.flags[control[1]]
  click(control[2],526+index*36)
  assert(item.flags[control[1]]==before,'native pending-removal item toggle did not restore')
  effects[#effects+1]={id=item.id,flag=control[1],before=before,after=changed,restored=item.flags[control[1]]}
 end
end
local observed=shot('removing-item-flags');observed.item_effects=effects
job.flags.suspend=true;shot('remove-suspended');job.flags.whole=flags
local cancelled=false
local row=shot('remove-restored')
for y,line in ipairs(row.lines)do
 local x=line:find('Cancel removal',1,true)
 if x then click((x+2)*8,(y-1)*12+10);cancelled=true;break end
end
assert(cancelled and #building.jobs==0 and not dfhack.buildings.markedForRemoval(building),'chest cancellation failed')
shot('cancel-removal');assert(building.name==original)

-- Compare native Cancel removal with the owned semantic entry, including worker
-- release and completed-building occupancy. These controlled jobs never tick.
local worker_source=debug.getinfo(1,'S').source:sub(2):gsub('chest%-header%-native.lua$','farm-worker-fixture.lua')
local fixture=assert(loadfile(worker_source))()
local json=require('json');local occupancy=fixture.occupancy(building);local native_after
for _,method in ipairs{'native','semantic'}do
 click(832,82)
 local identity=fixture.attach(building);local before=fixture.observe(building,identity)
 local assigned=shot('worker-'..method..'-assigned');assert(assigned.semantic.has_worker)
 if method=='native' then
  local clicked=false
  for y,line in ipairs(assigned.lines)do
   local x=line:find('Cancel removal',1,true)
   if x then click((x+2)*8,(y-1)*12+10);clicked=true;break end
  end
  assert(clicked,'native worker cancellation control missing')
 else
  local guards={}
  for _,object in ipairs{sheet,df.global.plotinfo}do
   local size,address=df.sizeof(object);local bytes=df.new('uint8_t',size);dfhack.internal.memmove(bytes,address,size)
   guards[#guards+1]={bytes=bytes,address=address,size=size}
  end
  local message,status=dfhack.run_command_silent('df3d','building-cancel-removal',tostring(building.id));assert(status==0,message)
  for _,guard in ipairs(guards)do assert(dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)==0,'semantic cancellation changed UI');df.delete(guard.bytes)end
 end
 local after=fixture.observe(building,identity)
 assert(after.current_job==-1 and #after.jobs==0 and not dfhack.buildings.markedForRemoval(building),'cancellation retained worker/job links')
 assert(json.encode(after.occupancy)==json.encode(occupancy),'cancellation changed completed chest occupancy')
 if method=='native' then native_after=after else assert(json.encode(after)==json.encode(native_after),'semantic worker cleanup differs from native')end
 local row=shot('worker-'..method..'-cancelled');row.worker_cancellation={identity=identity,before=before,after=after}
end
for _,id in ipairs{tostring(building.id),'2147483647','-1','not-an-id'}do
 local _,status=dfhack.run_command_silent('df3d','building-cancel-removal',id);assert(status~=0,'invalid cancellation accepted')
end
local _,wrong=dfhack.run_command_silent('df3d','farm-cancel-removal',tostring(building.id));assert(wrong~=0,'farm cancellation accepted chest')

-- Exercise the same guarded action transaction used by the future chest wire.
local function action(op,revision,name)
 local args={'df3d','building-header-action',tostring(building.id),revision or '0',op}
 if name~=nil then args[#args+1]=name end
 local guards={}
 for _,object in ipairs{sheet,df.global.plotinfo}do
  local size,address=df.sizeof(object);local bytes=df.new('uint8_t',size);dfhack.internal.memmove(bytes,address,size)
  guards[#guards+1]={bytes=bytes,address=address,size=size}
 end
 local message,status=dfhack.run_command_silent(table.unpack(args));assert(status==0,message)
 for _,guard in ipairs(guards)do assert(dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)==0,'guarded header action changed UI');df.delete(guard.bytes)end
 return json.decode(message)
end
local initial=action('read').snapshot
local renamed=action('rename',initial.revision,'lower chest');assert(renamed.outcome=='completed' and renamed.mutated and building.name=='lower chest')
local stale=action('rename',initial.revision,'stale');assert(stale.outcome=='stale' and not stale.mutated and not stale.snapshot and building.name=='lower chest')
local repeated=action('rename',renamed.snapshot.revision,'lower chest');assert(repeated.outcome=='completed' and not repeated.mutated)
local too_long=action('rename',renamed.snapshot.revision,string.rep('X',31));assert(too_long.outcome=='rejected' and not too_long.mutated and not too_long.snapshot)
local restored=action('rename',renamed.snapshot.revision,dfhack.df2utf(original));assert(restored.outcome=='completed' and building.name==original)
local removed=action('remove',restored.snapshot.revision);assert(removed.outcome=='completed' and removed.mutated and #building.jobs==1)
local identity=fixture.attach(building);local assigned=action('read').snapshot
assert(assigned.revision~=removed.snapshot.revision and assigned.has_worker)
local stale_cancel=action('cancel',removed.snapshot.revision);assert(stale_cancel.outcome=='stale' and not stale_cancel.mutated and dfhack.job.getWorker(building.jobs[0]).id==identity.worker_id)
local blocked_name=action('rename',assigned.revision,'wrong');assert(blocked_name.outcome=='rejected' and not blocked_name.mutated)
local cancelled=action('cancel',assigned.revision);assert(cancelled.outcome=='completed' and cancelled.mutated)
local after=fixture.observe(building,identity);assert(json.encode(after)==json.encode(native_after))
assert(cancelled.snapshot.revision==initial.revision and building.name==original)
local row=shot('guarded-actions');row.actions={initial=initial,renamed=renamed,stale=stale,repeated=repeated,too_long=too_long,restored=restored,removed=removed,assigned=assigned,stale_cancel=stale_cancel,blocked_name=blocked_name,cancelled=cancelled,worker_after=after}

local function wire(mode,stale)
 local expected={mode=mode,snapshot=action('read').snapshot,stale_revision=stale}
 local file=assert(io.open(out..'/chest-header-expected.json','w'));file:write(json.encode(expected));file:close()
 local row=capture('chest-header-wire-'..mode)
 local result=assert(io.open(out..'/chest-header-wire-result.json'));row.wire=json.decode(result:read('*a'));result:close();assert(row.wire.success)
 assert(building.name==original and #building.jobs==0 and not dfhack.buildings.markedForRemoval(building),'wire header did not restore chest')
 return row
end
wire('idle')
click(832,82);building.jobs[0].flags.suspend=true
wire('suspended')
click(832,82);local stale_revision=action('read').snapshot.revision
local wire_worker=fixture.attach(building)
local row=wire('worker',stale_revision);row.worker_after=fixture.observe(building,wire_worker)
assert(json.encode(row.worker_after)==json.encode(native_after),'wire worker cleanup differs from native')

local file=assert(io.open(out..'/chest-header-expected.json','w'));file:write(json.encode({mode='scene',snapshot=action('read').snapshot}));file:close()
local row=capture('chest-owner-wire')
local result=assert(io.open(out..'/chest-scene-result.json'));row.scene=json.decode(result:read('*a'));result:close();assert(row.scene.success)
assert(building.name==original and #building.jobs==0 and not dfhack.buildings.markedForRemoval(building),'main scene did not restore chest')
