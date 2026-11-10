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
local cold=probe()
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
local function verify_captions()
 local first=info.jobs.scroll_position_cri_job
 for index=first,math.min(#warm-1,first+16)do
  local bytes=dfhack.utf2df(warm[index+1].caption)
  if #bytes>=24 then bytes=bytes:sub(1,20)..'...' end
  for i=1,#bytes do
   assert(dfhack.screen.readTile(5+i,11+(index-first)*3).ch==bytes:byte(i),'Tasks visible job caption differs '..index)
  end
  verified[warm[index+1].job_id]=true
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
if os.getenv('DF3D_TASKS_ACTIONS')=='1' then
 local source=debug.getinfo(1,'S').source:sub(2):gsub('tasks%-native.lua$','tasks-actions-native.lua')
 result.actions=assert(loadfile(source))(out,view,info,capture)
end
write('tasks-native.json',json.encode(result))
gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
assert(not info.open,'Tasks did not close')
records[#records+1]={name='tasks-discovery',rows=#result.rows,closed=true}
