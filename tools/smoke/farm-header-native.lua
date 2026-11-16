-- Protected native oracle; mutations remain in the owned unsaved process.
local out,view,records,b=...
local script=require('gui.script');local gui=require('gui');local g=df.global.gps
local sheet=df.global.game.main_interface.view_sheets
local id=b.id;local original=b.name;local frame=df.global.world.frame_counter
local seasons={};for i=0,3 do seasons[i+1]=b.plant_id[i]end
local function pointer(x,y)
 g.mouse_x=x//8;g.mouse_y=(y-4)//12;g.precise_mouse_x=x;g.precise_mouse_y=y
end
local function key(event)gui.simulateInput(view,event);view:render(dfhack.getTickCount())end
local function click(x,y)pointer(x,y);key('_MOUSE_L')end
local function text(value)for i=1,#value do key(('STRING_A%03d'):format(value:byte(i)))end end
local function lines()
 local rows={};for y=0,g.dimy-1 do
  local row={};for x=0,g.dimx-1 do local t=dfhack.screen.readTile(x,y);row[#row+1]=t.ch>=32 and t.ch<127 and string.char(t.ch)or' 'end
  rows[#rows+1]=table.concat(row)
 end return rows
end
local function shot(name,keep_pointer)
 if not keep_pointer then pointer(0,4)end
 local mouse={g.precise_mouse_x,g.precise_mouse_y}
 local function restore_pointer()
  if not keep_pointer then return end
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
  pointer(mouse[1],mouse[2]);gui.simulateInput(view,{})
 end
 for i=1,5 do
  restore_pointer()
  view:render(dfhack.getTickCount());script.sleep(1,'frames')
 end
 if keep_pointer then restore_pointer();view:render(dfhack.getTickCount())end
 assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
 local live=df.building.find(id);local jobs={}
 if live then
  for i=0,3 do assert(live.plant_id[i]==seasons[i+1],'header action changed crops')end
  for _,job in ipairs(live.jobs)do jobs[#jobs+1]={id=job.id,type=df.job_type[job.job_type]}end
 end
 local guards={}
 local function guard(object)
  local size,address=df.sizeof(object);local bytes=df.new('uint8_t',size)
  dfhack.internal.memmove(bytes,address,size);guards[#guards+1]={bytes=bytes,address=address,size=size}
 end
 if live then
  guard(live);for _,job in ipairs(live.jobs)do guard(job);for _,ref in ipairs(job.general_refs)do guard(ref)end end
 end
 guard(sheet);guard(df.global.plotinfo)
 local before_name=live.name;local before_draft=sheet.building_entering_str
 local result,code=dfhack.run_command_silent('df3d','farm-header-read',tostring(id))
 assert(code==0,result);assert(live.name==before_name and sheet.building_entering_str==before_draft,'header read changed string storage');local semantic=require('json').decode(result)
 for _,entry in ipairs(guards)do
  assert(dfhack.internal.memcmp(entry.bytes,entry.address,entry.size)==0,'header read changed guarded state')
  df.delete(entry.bytes)
 end
 assert(semantic.custom_name==dfhack.df2utf(live.name) and semantic.native_name==dfhack.df2utf(dfhack.buildings.getName(live)),'header names differ')
 if not sheet.building_entering_nickname then
  assert(lines()[7]:sub(61,90):gsub('%s+$','')==semantic.header_name,'native formatted header differs')
 end
 assert(semantic.removing==dfhack.buildings.markedForRemoval(live),'header removal differs')
 records[#records+1]={name=name,building_id=id,present=live~=nil,custom_name=live and live.name or '',
  native_name=live and dfhack.buildings.getName(live)or'',editing=sheet.building_entering_nickname,
  draft=sheet.building_entering_str,sheet_open=sheet.open,active_id=sheet.active_id,
  semantic=semantic,guards_unchanged=true,removing=live and dfhack.buildings.markedForRemoval(live)or false,jobs=jobs,lines=lines(),
  hover=df.global.game.main_interface.current_hover,hover_enabled=df.global.game.main_interface.hover_instructions_on,
  mouse={g.precise_mouse_x,g.precise_mouse_y}}
 if keep_pointer then
  local row=records[#records];row.help_cells={};row.help_frame={}
  for y=0,17 do for x=g.dimx-25,g.dimx-1 do
   local pen=dfhack.screen.readTile(x,y)
   row.help_frame[#row.help_frame+1]={x=x,y=y,tile=pen.tile}
   if pen.ch>=33 and pen.ch<=255 then row.help_cells[#row.help_cells+1]={x=x,y=y,ch=pen.ch,fg=pen.fg,bg=pen.bg,bold=pen.bold}end
  end end
 end
 local f=assert(io.open(out..'/shot','w'));f:write(name);f:close()
 local limit=dfhack.getTickCount()+30000
 while true do local ack=io.open(out..'/ack-'..name);if ack then ack:close();break end
  if keep_pointer then restore_pointer();view:render(dfhack.getTickCount())end
  assert(dfhack.getTickCount()<limit,'header capture timeout');script.sleep(1,'frames')end
end
local function reopen()
 if sheet.open then return end
 for y=0,g.dimy-1 do for x=0,g.dimx-1 do
  pointer(x*8+4,y*12+10)
  local p=dfhack.gui.getMousePos(true)
  if p and p.x==b.centerx and p.y==b.centery and p.z==b.z then click(x*8+4,y*12+10);return end
 end end
 error('farm not visible after sheet closed')
end
for _,probe in ipairs{{'rename',800,82},{'remove',832,82},{'title',600,82},{'spring',480,124}}do
 local deadline=dfhack.getTickCount()+900
 repeat
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
  pointer(probe[2],probe[3]);gui.simulateInput(view,{});view:render(dfhack.getTickCount());script.sleep(1,'frames')
 until dfhack.getTickCount()>=deadline
 pointer(probe[2],probe[3])
 shot('farm-header-hover-'..probe[1],true)
 local observed=records[#records];local expected=({rename=301,remove=302})[probe[1]] or -1
 assert(observed.hover==expected and (expected==-1 or observed.hover_enabled),'farm hover probe differs')
end
click(800,82);shot('farm-header-rename-empty')
text('Farm test');assert(b.name=='Farm test','rename did not apply while typing');shot('farm-header-rename-draft')
key('LEAVESCREEN');assert(b.name=='Farm test' and not sheet.open,'Escape did not retain name and close sheet');shot('farm-header-rename-escape');reopen();shot('farm-header-reopened')
click(800,82);for i=1,100 do key('STRING_A000')end;text('Farm test');key('SELECT');shot('farm-header-renamed')
click(800,82);text(' appended');key('_MOUSE_R');assert(b.name=='Farm test appended' and not sheet.open,'Right click did not retain name and close sheet');shot('farm-header-rename-right');reopen()
click(800,82);for i=1,100 do key('STRING_A000')end
text(string.rep('X',80));assert(b.name==string.rep('X',30),'native name limit differs');shot('farm-header-name-limit')
key('SELECT');assert(not sheet.building_entering_nickname and sheet.open,'Enter did not end rename');shot('farm-header-long-name')
click(800,82);for i=1,100 do key('STRING_A000')end;text('lower farm');key('SELECT');shot('farm-header-lower-name')
assert(records[#records].semantic.custom_name=='lower farm' and records[#records].semantic.header_name=='Lower farm','native name formatter differs')
-- Editing renders the draft through the same native caption formatter. Keep
-- punctuation/bracket cases as evidence for the local presentation editor.
local captions={'lower farm','two WORDS','[tag]lower farm','  lower farm','"lower farm',"'lower farm",'123 lower farm','-lower farm','[tag] lower farm','[[tag]]lower farm',']lower farm'}
for index,value in ipairs(captions)do
 click(800,82);for i=1,100 do key('STRING_A000')end;text(value)
 assert(b.name==value,'caption input differs')
 shot('farm-header-caption-'..index)
 key('SELECT')
end
click(800,82);for i=1,100 do key('STRING_A000')end;key('SELECT');shot('farm-header-name-cleared')
assert(b.name==original,'empty name did not restore fixture')
click(832,82);shot('farm-header-remove')
assert(df.building.find(id),'farm removed immediately; cancellation unavailable')
assert(dfhack.buildings.markedForRemoval(b) and #b.jobs==1 and b.jobs[0].job_type==df.job_type.DestroyBuilding,'removal job differs')
local job=b.jobs[0];local old_flags=job.flags.whole
job.flags.suspend=true;shot('farm-header-remove-suspended')
assert(records[#records].semantic.suspended and not records[#records].semantic.has_worker,'suspended header differs')
job.flags.whole=old_flags
local ref=df.general_ref_unit_workerst:new();ref.unit_id=df.global.world.units.active[0].id
job.general_refs:insert('#',ref);shot('farm-header-remove-worker')
assert(not records[#records].semantic.suspended and records[#records].semantic.has_worker,'worker header differs')
job.flags.suspend=true;shot('farm-header-remove-suspended-worker')
assert(records[#records].semantic.suspended and records[#records].semantic.has_worker,'suspended-worker header differs')
job.flags.whole=old_flags;job.general_refs:erase(#job.general_refs-1);df.delete(ref)
shot('farm-header-remove-restored')
assert(not records[#records].semantic.suspended and not records[#records].semantic.has_worker,'restored header differs')
local found=false
for y,line in ipairs(lines())do
 local x=line:find('Cancel removal',1,true)
 if x then click((x+2)*8,(y-1)*12+10);found=true;break end
end
assert(found,'native cancellation control missing');shot('farm-header-cancel-removal')
assert(not dfhack.buildings.markedForRemoval(b),'native removal cancellation failed')

local worker_source=debug.getinfo(1,'S').source:sub(2):gsub('farm%-header%-native.lua$','farm-worker-fixture.lua')
local worker_fixture=assert(loadfile(worker_source))()
local original_occupancy=worker_fixture.occupancy(b)
click(832,82)
local worker_identity=worker_fixture.attach(b)
local worker_before=worker_fixture.observe(b,worker_identity)
shot('farm-header-assigned-worker')
assert(records[#records].semantic.has_worker,'assigned worker absent from native header')
local cancelled=false
for y,line in ipairs(lines())do
 local x=line:find('Cancel removal',1,true)
 if x then click((x+2)*8,(y-1)*12+10);cancelled=true;break end
end
assert(cancelled,'worker cancellation button missing')
local worker_after=worker_fixture.observe(b,worker_identity)
assert(worker_after.current_job==-1 and #worker_after.jobs==0,'native cancellation retained worker/job links')
assert(require('json').encode(worker_after.occupancy)==require('json').encode(original_occupancy),'native cancellation changed footprint occupancy')
shot('farm-header-assigned-worker-cancelled')
records[#records].worker_cancellation={identity=worker_identity,before=worker_before,after=worker_after}

for _,bad in ipairs{'-1','2147483647','not-an-id'}do
 local _,code=dfhack.run_command_silent('df3d','farm-header-read',bad);assert(code~=0,'invalid header target accepted')
end

local nonfarm
for _,candidate in ipairs(df.global.world.buildings.all)do
 if not df.building_farmplotst:is_instance(candidate)then nonfarm=candidate.id;break end
end
assert(nonfarm,'nonfarm refusal fixture missing')
local _,code=dfhack.run_command_silent('df3d','farm-header-read',tostring(nonfarm));assert(code~=0,'nonfarm target accepted')
local designation=dfhack.maps.getTileBlock(b.centerx,b.centery,b.z).designation[b.centerx%16][b.centery%16]
local old=designation.whole;designation.hidden=true
local _,hidden_code=dfhack.run_command_silent('df3d','farm-header-read',tostring(id));designation.whole=old
assert(hidden_code~=0,'hidden farm header disclosed')

-- Selection is diagnostic UI observation only, never a runtime data source.
local function selection_shot(name,while_waiting)
 pointer(0,4);for i=1,5 do view:render(dfhack.getTickCount());script.sleep(1,'frames')end
 local tabs={};for index,kind in ipairs(sheet.tab)do tabs[#tabs+1]={kind=df.view_sheet_type[kind],id=sheet.tab_id[index]}end
 local units={};for _,value in ipairs(sheet.viewing_unid)do units[#units+1]=value end
 local items={};for _,value in ipairs(sheet.viewing_itid)do items[#items+1]=value end
 local row={name=name,open=sheet.open,active_sheet=df.view_sheet_type[sheet.active_sheet],active_id=sheet.active_id,
  season=sheet.active_sub_tab,tabs=tabs,units=units,items=items,building=sheet.viewing_bldid,
  tile={x=sheet.viewing_x,y=sheet.viewing_y,z=sheet.viewing_z},lines=lines()}
 records[#records+1]=row
 local f=assert(io.open(out..'/shot','w'));f:write(name);f:close()
 -- Controlled blink phases pace GPU readbacks instead of synchronizing every frame.
 local health_case=os.getenv('DF3D_UNIT_HEALTH_CASE')
 local blink=name=='farm-item-carrier-unit-scene' and (health_case=='blink' or health_case=='bleeding')
 -- Live contents refresh waits for two automatic semantic publications.
 local contents_refresh=name=='farm-item-carrier-unit-scene' and (os.getenv('DF3D_UNIT_ITEMS_REFRESH')=='1' or os.getenv('DF3D_UNIT_ITEMS_LIFECYCLE')=='1')
 local lifecycle=name=='farm-item-carrier-unit-scene' and (os.getenv('DF3D_UNIT_ITEMS_LIFECYCLE')=='1' or os.getenv('DF3D_UNIT_HEALTH_LIFECYCLE')=='1')
 -- Combined Labor visits multiple creature/zone sheets and waits for fresh receipts.
 local labor_navigation=name=='farm-item-carrier-unit-scene' and os.getenv('DF3D_UNIT_LABOR_ANIMALS')=='1'
 -- Match the launcher's90-second rendered-client budget at the30 FPS cap.
 local rendered_carrier=name=='farm-item-carrier-scene' or name=='farm-item-carrier-unit-scene' or name=='cage-scene' or name=='simple-building-wire' or (name=='special-building-wire' and os.getenv('DF3D_SPECIAL_BUILDINGS_SCENE')=='1')
 local furniture=name=='workshop-wire' and os.getenv('DF3D_FURNITURE_RUNTIME')=='1'
 -- The four furniture workflows may use the launcher's full45-second budget.
 local limit=dfhack.getTickCount()+(furniture and os.getenv('DF3D_FURNITURE_GENERIC_DISCOVERY')=='1' and 95000 or furniture and 60000 or rendered_carrier and 95000 or lifecycle and 85000 or (blink or contents_refresh or labor_navigation) and 60000 or 30000)
 while true do local ack=io.open(out..'/ack-'..name);if ack then ack:close();break end
  assert(dfhack.getTickCount()<limit,'selection capture timeout')
  if while_waiting then while_waiting()end
  script.sleep(1,'frames')end
 assert(df.global.pause_state and df.global.world.frame_counter==frame,'selection advanced simulation')
 for i=0,3 do assert(b.plant_id[i]==seasons[i+1],'selection changed crops')end
 return row
end
local selected=selection_shot('farm-selection-initial')
assert(selected.open and selected.active_sheet=='BUILDING' and selected.active_id==b.id)
local farm_tab
for index,tab in ipairs(selected.tabs)do if tab.kind=='BUILDING' and tab.id==b.id then farm_tab=index-1 end end
assert(farm_tab,'farm alternative missing')
for index,tab in ipairs(selected.tabs)do
 click(920,70+(index-1)*36)
 local observed=selection_shot('farm-selection-alternative-'..index)
 assert(observed.active_sheet==tab.kind and observed.active_id==tab.id,'native alternative click differs')
end
click(920,70+farm_tab*36)
click(448,124) -- Spring is local sheet state before leaving the selected tile.
local before=selection_shot('farm-selection-spring')
assert(before.season==0,'spring selection fixture differs')
for index,tab in ipairs(selected.tabs)do if tab.kind~='BUILDING' then
 click(920,70+(index-1)*36);selection_shot('farm-selection-spring-away')
 click(920,70+farm_tab*36);selection_shot('farm-selection-spring-return');break
end end
local function select_map(building)
 dfhack.gui.revealInDwarfmodeMap({x=building.centerx,y=building.centery,z=building.z},true)
 -- Keep the target on exposed map, not underneath the open sheet.
 df.global.window_x=math.max(0,building.centerx-8)
 df.global.window_y=math.max(0,building.centery-10)
 view:render(dfhack.getTickCount())
 for y=0,g.dimy-1 do for x=0,g.dimx-1 do
  pointer(x*8+4,y*12+10);local pos=dfhack.gui.getMousePos(true)
  if x*8+4<400 and y*12+10>48 and y*12+10<760 and pos and pos.x==building.centerx and pos.y==building.centery and pos.z==building.z then
   click(x*8+4,y*12+10);return
  end
 end end
 error('selection fixture target not visible')
end
local other
for _,candidate in ipairs(df.global.world.buildings.other.FARM_PLOT)do if candidate.id~=b.id then other=candidate;break end end
assert(other,'second farm missing')
select_map(other);local second=selection_shot('farm-selection-other')
assert(second.open and second.active_sheet=='BUILDING' and second.active_id==other.id,'second farm not selected')
select_map(b);selection_shot('farm-selection-return')
select_map(other)
local contents_source=debug.getinfo(1,'S').source:sub(2):gsub('farm%-header%-native.lua$','farm-contents-native.lua')
assert(loadfile(contents_source))(out,view,records,other,selection_shot,select_map)
