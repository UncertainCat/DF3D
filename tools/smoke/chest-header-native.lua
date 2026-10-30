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

job.flags.suspend=true;shot('remove-suspended');job.flags.whole=flags
local cancelled=false
local row=shot('remove-restored')
for y,line in ipairs(row.lines)do
 local x=line:find('Cancel removal',1,true)
 if x then click((x+2)*8,(y-1)*12+10);cancelled=true;break end
end
assert(cancelled and #building.jobs==0 and not dfhack.buildings.markedForRemoval(building),'chest cancellation failed')
shot('cancel-removal');assert(building.name==original)
