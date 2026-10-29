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
local function shot(name)
 pointer(0,4);for i=1,5 do view:render(dfhack.getTickCount());script.sleep(1,'frames')end
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
  semantic=semantic,guards_unchanged=true,removing=live and dfhack.buildings.markedForRemoval(live)or false,jobs=jobs,lines=lines()}
 local f=assert(io.open(out..'/shot','w'));f:write(name);f:close()
 local limit=dfhack.getTickCount()+30000
 while true do local ack=io.open(out..'/ack-'..name);if ack then ack:close();break end
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
