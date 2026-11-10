-- Protected discovery only. Menu/widget storage is never a runtime provider.
local out,view,records=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local function write(name,value)
 local f=assert(io.open(out..'/'..name,'w'));f:write(value);f:close()
end
local function probe()
 local info=df.global.game.main_interface.info
 local _,address=df.sizeof(info.jobs.cri_job)
 local function snapshot()
  local rows={};for _,entry in ipairs(info.jobs.cri_job)do rows[#rows+1]={entry.jb and entry.jb.id or -1,entry.sort_name,entry.job_sort_name}end
  return json.encode{open=info.open,mode=info.current_mode,rows=rows,scroll=info.jobs.scroll_position_cri_job,
   first=df.reinterpret_cast('uint64_t',address).value,last=df.reinterpret_cast('uint64_t',address+8).value,
   capacity=df.reinterpret_cast('uint64_t',address+16).value}
 end
 local before=snapshot()
 local text,code=dfhack.run_command_silent('df3d','tasks-rows-probe')
 assert(code==0,'Owned Tasks provider failed: '..text)
 assert(before==snapshot(),'Owned Tasks provider changed native menu storage')
 return json.decode(text).rows
end
if os.getenv('DF3D_TASKS_CREATE')=='1' then
 local path=debug.getinfo(1,'S').source:sub(2):gsub('tasks%-native.lua$','residents-job-create-native.lua')
 assert(loadfile(path))(out,view);gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
end
local cold=probe()
if os.getenv('DF3D_TASKS_WIRE')=='1' then
 local job;for _,candidate in require('utils').listpairs(df.global.world.jobs.list)do if candidate.id==68196 then job=candidate;break end end
 assert(job and job.flags.suspend,'Expected suspended construction fixture')
 local original=job.flags.whole
 write('tasks-wire-reference.json',json.encode(cold))
 write('tasks-scene-reference.json',json.encode{rows=cold})
 write('shot.tmp','tasks-wire');assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local deadline=dfhack.getTickCount()+(os.getenv('DF3D_TASKS_SCENE')=='1' and 120000 or 30000);local checked=0
 while true do
  local step=io.open(out..'/tasks-wire-step')
  if step then local n=tonumber(step:read('*a'));step:close()
   if n and n>checked then assert(n==checked+1);assert(job.flags.whole==(n==1 and (original ~ 2) or original),'Tasks wire suspend effect differs');checked=n;write('tasks-wire-ack',tostring(n))end
  end
  local ack=io.open(out..'/ack-tasks-wire');if ack then ack:close();break end
  assert(dfhack.getTickCount()<deadline,'Tasks wire timed out');script.sleep(1,'frames')
 end
 assert(checked==2 and job.flags.whole==original,'Tasks wire did not restore suspension')
 assert(not df.global.game.main_interface.info.open,'Tasks transport opened native menu')
end

gui.simulateInput(view,'D_JOBLIST')
for _=1,3 do script.sleep(1,'frames')end
view:render(dfhack.getTickCount())
local info=df.global.game.main_interface.info
assert(info.open and info.current_mode==df.info_interface_mode_type.JOBS,'Tasks shortcut did not open Jobs')
local path=debug.getinfo(1,'S').source:sub(2):gsub('smoke/tasks%-native.lua$','ui_bake/capture_widgets.lua')
assert(loadfile(path))(out..'/tasks-widgets.json','templates')
local base=dfhack.internal.getImageBase()
local _,jobs_address=df.sizeof(info.jobs)
local _,vector_address=df.sizeof(info.jobs.cri_job)
local result={rows={},screen_rows={},simulation_jobs={},scroll=info.jobs.scroll_position_cri_job,
 jobs_rva=jobs_address-base,vector_rva=vector_address-base}
for _,job in require('utils').listpairs(df.global.world.jobs.list)do
 assert(#result.simulation_jobs<1048576,'Job list exceeded diagnostic bound')
 result.simulation_jobs[#result.simulation_jobs+1]={id=job.id,type=job.job_type,
  flags=job.flags.whole,position={job.pos.x,job.pos.y,job.pos.z}}
end
for _,entry in ipairs(info.jobs.cri_job)do
 result.rows[#result.rows+1]={job_id=entry.jb and entry.jb.id or -1,
  unit_id=entry.un and entry.un.id or -1,item_id=entry.it and entry.it.id or -1,
  flags=entry.flag.whole,sort_name=dfhack.df2utf(entry.sort_name),job_sort_name=dfhack.df2utf(entry.job_sort_name)}
end
local warm=probe()
local function identities(rows)
 local result={}
 for _,row in ipairs(rows)do result[#result+1]={job_id=row.job_id,unit_id=row.unit_id,item_id=row.item_id,
  flags=row.flags,sort_name=row.sort_name,job_sort_name=row.job_sort_name}end
 return result
end
assert(json.encode(identities(cold))==json.encode(result.rows),'Cold owned Tasks rows differ from native')
assert(json.encode(identities(warm))==json.encode(result.rows),'Warm owned Tasks rows differ from native')
assert(json.encode(cold)==json.encode(warm),'Tasks display text depends on menu initialization')
result.owned={cold=cold,warm=warm,native_menu_preserved=true}
local g=df.global.gps
local verified={}
local verified_controls={}
local verified_buildings={}
local verified_workers={}
local verified_artwork={}
local verified_destination_art={}
local function verify_captions()
 local first=info.jobs.scroll_position_cri_job
 for index=first,math.min(#warm-1,first+16)do
  local bytes=dfhack.utf2df(warm[index+1].caption)
  if #bytes>=24 then bytes=bytes:sub(1,20)..'...' end
  for i=1,#bytes do
   assert(dfhack.screen.readTile(5+i,11+(index-first)*3).ch==bytes:byte(i),'Tasks visible job caption differs '..index)
  end
  verified[warm[index+1].job_id]=true
  local row=warm[index+1]
  if row.unit_id>=0 then
   local bytes=dfhack.utf2df(row.worker_name)
   if #bytes>=31 then bytes=bytes:sub(1,27)..'...'end
   local color=assert(row.worker_color)
   for i=1,#bytes do
    local pen=dfhack.screen.readTile(56+i,11+(index-first)*3)
    assert(pen.ch==bytes:byte(i),'Tasks worker name differs '..row.job_id)
    local function matches(c)return pen.fg==c[1] and pen.bg==c[2] and (pen.bold and 1 or 0)==c[3]end
    assert(matches(color.color) or (color.effect~=0 and matches(color.alternate)),
     'Tasks worker color differs '..row.job_id)
   end
   verified_workers[row.job_id]=true
   local art=assert(row.worker_appearance,'Tasks worker selector recipe missing')
   assert(#art.pages>0 and #art.layers>0,'Tasks selector recipe empty')
   for _,layer in ipairs(art.layers)do
    assert(art.pages[layer[1]+1] and #layer==10,'Invalid Tasks selector layer')
    if layer[6]~=65535 then assert(art.palettes[layer[6]+1],'Invalid Tasks selector palette')end
   end
   verified_artwork[row.job_id]=true
  end
  if row.building_id>=0 then
   local bytes=dfhack.utf2df(row.building_caption)
   -- Native399512 clips against the scrollbar-adjusted right boundary.
   local right=g.dimx-1-30-(#warm>17 and 2 or 0)
   local length=right-95-8
   if #bytes>=length+1 and length>=0 then
    bytes=bytes:sub(1,length)
    if length>3 then bytes=bytes:sub(1,length-3)..'...'end
   end
   for i=1,#bytes do assert(dfhack.screen.readTile(101+i,11+(index-first)*3).ch==bytes:byte(i),
    'Tasks building caption differs '..row.job_id)end
   local holder=assert(df.building.find(row.building_id))
   assert(json.encode(row.building_position)==json.encode{holder.centerx,holder.centery,holder.z})
   verified_buildings[row.job_id]=true
   local art=assert(row.building_appearance,'Tasks destination icon missing')
   assert(#art.layers==1,'Expected original destination tile')
   local layer=art.layers[1];local tile
   for _,page in ipairs(df.global.texture.page)do
    if page.token==art.pages[layer[1]+1]then tile=page.texpos[layer[3]*page.page_dim_x+layer[2]];break end
   end
   assert(tile and tile>0,'Destination icon page not installed')
   local found=false
   for xx=95,99 do for yy=10+(index-first)*3,12+(index-first)*3 do
    local offset=xx*g.dimy+yy
    if g.screentexpos_anchored[offset]==tile or g.screentexpos_top_anchored[offset]==tile then found=true end
   end end
   assert(found,'Tasks destination icon differs '..row.job_id)
   verified_destination_art[row.job_id]=true
  end
  for _,control in ipairs{{'can_view_job',276,241},{'can_repeat',300,243},
    {'can_remove_worker',324,244},{'can_suspend',348,245},{'can_cancel',372,246}}do
   df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
   g.precise_mouse_x=control[2];g.precise_mouse_y=142+(index-first)*36
   g.mouse_x=control[2]//8;g.mouse_y=(g.precise_mouse_y-4)//12
   df.global.game.main_interface.current_hover=0
   gui.simulateInput(view,{});view:render(dfhack.getTickCount())
   assert((df.global.game.main_interface.current_hover==control[3])==row[control[1]],
     'Tasks control differs: '..row.job_id..' '..control[1])
  end
  verified_controls[row.job_id]=true
 end
end
verify_captions()
for y=0,g.dimy-1 do
 local row={};for x=0,g.dimx-1 do row[#row+1]=dfhack.screen.readTile(x,y).ch end
 result.screen_rows[#result.screen_rows+1]=row
end
local function capture(name)
 write('shot.tmp',name);assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local deadline=dfhack.getTickCount()+10000
 while true do
  local f=io.open(out..'/ack-'..name);if f then f:close();break end
  assert(dfhack.getTickCount()<deadline,'Tasks capture timeout');script.sleep(1,'frames')
 end
end
capture('tasks-root')
result.pages={}
for page=1,2 do
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=500;g.precise_mouse_y=300;g.mouse_x=62;g.mouse_y=25
 gui.simulateInput(view,'CONTEXT_SCROLL_PAGEDOWN');view:render(dfhack.getTickCount())
 verify_captions()
 local observed={scroll=info.jobs.scroll_position_cri_job,screen_rows={}}
 for y=0,g.dimy-1 do
  local row={};for x=0,g.dimx-1 do row[#row+1]=dfhack.screen.readTile(x,y).ch end
  observed.screen_rows[#observed.screen_rows+1]=row
 end
 result.pages[#result.pages+1]=observed;capture('tasks-page-'..page)
end
result.verified_caption_ids={}
for _,row in ipairs(warm)do if verified[row.job_id]then result.verified_caption_ids[#result.verified_caption_ids+1]=row.job_id end end
assert(#result.verified_caption_ids==#warm,'Not all Tasks captions were observed')
result.verified_control_ids={}
result.verified_building_ids={}
result.verified_worker_ids={}
result.verified_artwork_ids={}
result.verified_destination_art_ids={}
for _,row in ipairs(warm)do if verified_destination_art[row.job_id]then result.verified_destination_art_ids[#result.verified_destination_art_ids+1]=row.job_id end end
for _,row in ipairs(warm)do if verified_artwork[row.job_id]then result.verified_artwork_ids[#result.verified_artwork_ids+1]=row.job_id end end
for _,row in ipairs(warm)do if verified_workers[row.job_id]then result.verified_worker_ids[#result.verified_worker_ids+1]=row.job_id end end
for _,row in ipairs(warm)do if verified_buildings[row.job_id]then result.verified_building_ids[#result.verified_building_ids+1]=row.job_id end end
for _,row in ipairs(warm)do if verified_controls[row.job_id]then result.verified_control_ids[#result.verified_control_ids+1]=row.job_id end end
assert(#result.verified_control_ids==#warm,'Not all Tasks controls were observed')
if os.getenv('DF3D_TASKS_ACTIONS')=='1' then
 local source=debug.getinfo(1,'S').source:sub(2):gsub('tasks%-native.lua$','tasks-actions-native.lua')
 result.actions=assert(loadfile(source))(out,view,info,capture)
else
 result.navigation={}
 local function recenter(row,x,y,expected)
  g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
  gui.simulateInput(view,{});gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
  assert(not info.open,'Native Recenter did not close Tasks')
  local actual={}
  for axis=0,2 do actual[#actual+1]=df.reinterpret_cast('int16_t',base+0x18acefe+axis*2).value end
  assert(json.encode(actual)==json.encode(expected),'Native Recenter target differs')
  result.navigation[#result.navigation+1]={job_id=row.job_id,point={x,y},target=actual}
  gui.simulateInput(view,'D_JOBLIST');view:render(dfhack.getTickCount())
 end
 local first=info.jobs.scroll_position_cri_job
 recenter(warm[first+1],708,142,warm[first+1].worker_position)
 for _=1,2 do
  g.precise_mouse_x=500;g.precise_mouse_y=300;g.mouse_x=62;g.mouse_y=25
  gui.simulateInput(view,'CONTEXT_SCROLL_PAGEDOWN');view:render(dfhack.getTickCount())
 end
 local row=warm[#warm];local y=142+(#warm-1-info.jobs.scroll_position_cri_job)*36
 recenter(row,252,y,row.building_position)
end
write('tasks-native.json',json.encode(result))
gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
assert(not info.open,'Tasks did not close')
records[#records+1]={name='tasks-discovery',rows=#result.rows,closed=true}

if os.getenv('DF3D_TASKS_DETAILS')=='1' then
 local create_path=debug.getinfo(1,'S').source:sub(2):gsub('tasks%-native.lua$','residents-job-create-native.lua')
 local job=assert(loadfile(create_path))(out,view)
 gui.simulateInput(view,'LEAVESCREEN');gui.simulateInput(view,'D_JOBLIST')
 for _=1,3 do script.sleep(1,'frames')end
 local index
 for i,entry in ipairs(info.jobs.cri_job)do if entry.jb==job then index=i;break end end
 assert(index,'Created job missing from Tasks')
 info.jobs.scroll_position_cri_job=math.min(index,math.max(0,#info.jobs.cri_job-17))
 view:render(dfhack.getTickCount())
 local y=142+(index-info.jobs.scroll_position_cri_job)*36
 local function move(x)
  g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
  gui.simulateInput(view,{});view:render(dfhack.getTickCount())
 end
 local function click(x)
  move(x);gui.simulateInput(view,'_MOUSE_L')
  for _=1,3 do script.sleep(1,'frames')end;view:render(dfhack.getTickCount())
 end
 local evidence={job_id=job.id,hover={}}
 for _,target in ipairs{{'view-task',276},{'repeat',300}}do
  local deadline=dfhack.getTickCount()+650
  repeat move(target[2]);script.sleep(1,'frames')until dfhack.getTickCount()>=deadline
  local sample={kind=target[1],instruction=df.global.game.main_interface.current_hover,lines={}}
  for yy=0,17 do
   local chars={};for xx=g.dimx-24,g.dimx-1 do local ch=dfhack.screen.readTile(xx,yy).ch;chars[#chars+1]=ch>=32 and string.char(ch%256) or ' ' end
   sample.lines[#sample.lines+1]=dfhack.df2utf(table.concat(chars)):gsub('%s+$','')
  end
  while #sample.lines>0 and sample.lines[#sample.lines]==''do table.remove(sample.lines)end
  evidence.hover[#evidence.hover+1]=sample
 end
 local initial=job.flags.whole;click(300);evidence.repeat_before=initial;evidence.repeat_after=job.flags.whole
 assert(job.flags.whole==(initial ~ 1),'Native Repeat effect differs');click(300);assert(job.flags.whole==initial)
 click(276)
 local details=df.global.game.main_interface.job_details
 assert(details.open and details.jb==job and not details.wq,'Tasks View did not open job Details')
 evidence.context=details.context;evidence.building_id=details.bld and details.bld.id or -1;evidence.info_open=info.open;evidence.options={}
 for i,kind in ipairs(details.option)do evidence.options[#evidence.options+1]={kind=kind,index=details.option_index[i]}end
 capture('tasks-job-details')
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
 evidence.returned=not details.open and info.open and info.current_mode==df.info_interface_mode_type.JOBS
 assert(evidence.returned,'Details did not return to Tasks')
 write('tasks-details-native.json',json.encode(evidence))
 gui.simulateInput(view,'LEAVESCREEN')
end
