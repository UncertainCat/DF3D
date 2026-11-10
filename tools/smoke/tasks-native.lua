-- Protected discovery only. Menu/widget storage is never a runtime provider.
local out,view,records=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local function write(name,value)
 local f=assert(io.open(out..'/'..name,'w'));f:write(value);f:close()
end
gui.simulateInput(view,'D_JOBLIST')
for _=1,3 do script.sleep(1,'frames')end
view:render(dfhack.getTickCount())
local info=df.global.game.main_interface.info
assert(info.open and info.current_mode==df.info_interface_mode_type.JOBS,'Tasks shortcut did not open Jobs')
local path=debug.getinfo(1,'S').source:sub(2):gsub('smoke/tasks%-native.lua$','ui_bake/capture_widgets.lua')
assert(loadfile(path))(out..'/tasks-widgets.json','templates')
local result={rows={},screen_rows={},scroll=info.jobs.scroll_position_cri_job}
for _,entry in ipairs(info.jobs.cri_job)do
 result.rows[#result.rows+1]={job_id=entry.jb and entry.jb.id or -1,
  unit_id=entry.un and entry.un.id or -1,item_id=entry.it and entry.it.id or -1,
  flags=entry.flag.whole,sort_name=entry.sort_name,job_sort_name=entry.job_sort_name}
end
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
