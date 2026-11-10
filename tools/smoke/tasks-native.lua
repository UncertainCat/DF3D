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
assert(json.encode(cold)==json.encode(result.rows),'Cold owned Tasks rows differ from native')
assert(json.encode(warm)==json.encode(result.rows),'Warm owned Tasks rows differ from native')
result.owned={cold=cold,warm=warm,native_menu_preserved=true}
local g=df.global.gps
for y=0,g.dimy-1 do
 local row={};for x=0,g.dimx-1 do row[#row+1]=dfhack.screen.readTile(x,y).ch end
 result.screen_rows[#result.screen_rows+1]=row
end
write('tasks-native.json',json.encode(result))
write('shot.tmp','tasks-root');assert(os.rename(out..'/shot.tmp',out..'/shot'))
local deadline=dfhack.getTickCount()+10000
while true do
 local f=io.open(out..'/ack-tasks-root');if f then f:close();break end
 assert(dfhack.getTickCount()<deadline,'Tasks capture timeout');script.sleep(1,'frames')
end
gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
assert(not info.open,'Tasks did not close')
records[#records+1]={name='tasks-discovery',rows=#result.rows,closed=true}
