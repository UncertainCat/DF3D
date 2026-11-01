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
 assert(result.requirements_reference.caption=='Make bed','Native task caption differs from visible picker')
 shot('restored')
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
 local still
 for _,candidate in ipairs(df.global.world.buildings.other.WORKSHOP_ANY)do
  if df.building_workshopst:is_instance(candidate) and candidate.type==df.workshop_type.Still and candidate:getBuildStage()==candidate:getMaxBuildStage()then still=candidate;break end
 end
 assert(still,'Workshop reference needs a completed Still')
 select_map(still)
 assert(sheet.active_id==still.id and click_label('Add new task'),'Native Still picker did not open')
 local rows={};local utils=require('utils')
 for _,button in ipairs(df.global.game.main_interface.building.button)do
  if df.interface_button_building_new_jobst:is_instance(button) and button.jobtype==df.job_type.CustomReaction then
   local raw_index=-1;for index,reaction in ipairs(df.global.world.raws.reactions.reactions)do if reaction.code==button.mstring then raw_index=index;break end end
   rows[#rows+1]={raw_index=raw_index,code=dfhack.df2utf(button.mstring),caption=dfhack.df2utf(utils.call_with_string(button,'text')),
    objection=dfhack.df2utf(button.objection),available=not button.show_help_instead}
  end
 end
 local order=function(a,b)return a.code<b.code end;table.sort(rows,order)
 local permission_text,permission_code=dfhack.run_command_silent('df3d','workshop-reactions-probe',tostring(still.id))
 assert(permission_code==0,permission_text)
 local actual=json.decode(permission_text);table.sort(actual,order)
 assert(#rows>0 and #rows==#actual,'Native Still reaction membership differs')
 for i,row in ipairs(rows)do for key,value in pairs(row)do assert(actual[i][key]==value,'Native Still '..row.code..' '..key..' differs: '..tostring(actual[i][key])..' ~= '..tostring(value))end end
 local codes={};for _,row in ipairs(rows)do codes[#codes+1]=row.code end
 result.reaction_reference={building_id=still.id,codes=codes,rows=rows,all_equal=true}
 shot('still-add-task')
 local before_jobs={};for _,job in ipairs(still.jobs)do before_jobs[#before_jobs+1]=job.id end
 capture('workshop-wire')
 assert(#still.jobs==#before_jobs,'Rejected workshop task changed native queue size')
 for i,id in ipairs(before_jobs)do assert(still.jobs[i-1].id==id,'Rejected workshop task changed native queue order')end
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
end,debug.traceback)
assert(#building.jobs==#jobs,'Workshop capture changed job count')
for i,id in ipairs(jobs)do assert(building.jobs[i-1].id==id,'Workshop capture changed job order')end
select_map(original)
assert(df.global.pause_state and df.global.world.frame_counter==frame,'Workshop capture advanced simulation')
assert(ok,err)
records[#records+1]={name='workshop-native-reference',building_id=building.id,jobs_unchanged=true}
return result
