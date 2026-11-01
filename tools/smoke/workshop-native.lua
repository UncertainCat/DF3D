-- Diagnostic native workshop reference in the protected owned paused clone.
local out,view,records,original,capture,select_map=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local sheet=df.global.game.main_interface.view_sheets
local frame=df.global.world.frame_counter
local building
for _,b in ipairs(df.global.world.buildings.other.WORKSHOP_ANY)do
 if df.building_workshopst:is_instance(b) and b.type==df.workshop_type.Carpenters and b:getBuildStage()==b:getMaxBuildStage()then building=b;break end
end
assert(building,'Native workshop reference needs a completed carpenter workshop')
local jobs={};for _,job in ipairs(building.jobs)do jobs[#jobs+1]=job.id end
local result={building_id=building.id,type=df.workshop_type[building.type],position={building.centerx,building.centery,building.z},jobs=jobs,pages={}}
local function lines()
 local rows={};for y=0,g.dimy-1 do
  local text={};for x=0,g.dimx-1 do local ch=dfhack.screen.readTile(x,y).ch;text[#text+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
  rows[#rows+1]={y=y,text=dfhack.df2utf(table.concat(text)):gsub('%s+$','')}
 end;return rows
end
local function shot(name)
 local rows=lines();result.pages[#result.pages+1]={name=name,lines=rows,active_id=sheet.active_id,active_sub_tab=sheet.active_sub_tab}
 capture('workshop-'..name)
 local file=assert(io.open(out..'/workshop-native.json','w'));file:write(json.encode(result));file:close()
end
local function click_label(label)
 for _,row in ipairs(lines())do local x=row.text:lower():find(label:lower(),1,true);if x then
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
  g.precise_mouse_x=(x-1)*8+4;g.precise_mouse_y=row.y*12+10;g.mouse_x=x-1;g.mouse_y=row.y
  df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
  df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
  return true
 end end;return false
end
local ok,err=xpcall(function()
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());select_map(building)
 assert(sheet.open and sheet.active_sheet==df.view_sheet_type.BUILDING and sheet.active_id==building.id,'Native workshop selection missed')
 shot('jobs')
 assert(click_label('Add new task'),'Native Add new task control not found')
 shot('add-task')
 assert(click_label('Make bed'),'Native Make bed choice not found')
 assert(#building.jobs==#jobs+1,'Native Make bed did not create a task')
 local created=building.jobs[#building.jobs-1]
 local text,code=dfhack.run_command_silent('df3d','workshop-requirements-probe',tostring(building.id),tostring(created.id))
 local removed=dfhack.job.removeJob(created)
 assert(removed,'Native reference task cleanup failed')
 assert(code==0,text)
 result.requirements_reference=json.decode(text)
 shot('restored')
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
end,debug.traceback)
assert(#building.jobs==#jobs,'Workshop capture changed job count')
for i,id in ipairs(jobs)do assert(building.jobs[i-1].id==id,'Workshop capture changed job order')end
select_map(original)
assert(df.global.pause_state and df.global.world.frame_counter==frame,'Workshop capture advanced simulation')
assert(ok,err)
records[#records+1]={name='workshop-native-reference',building_id=building.id,jobs_unchanged=true}
return result
