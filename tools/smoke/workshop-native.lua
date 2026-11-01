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
-- Diagnostic oracle only; runtime worker reads never traverse widgets.
local function worker_list(container,depth)
 assert(depth<8,'Native worker widget tree too deep')
 if df.widget_unit_list:is_instance(container)then return df.reinterpret_cast(df.widget_unit_list,container)end
 if not df.widget_container:is_instance(container)then return end
 container=df.reinterpret_cast(df.widget_container,container)
 local _,address=df.sizeof(container.children)
 local first=df.reinterpret_cast('uint64_t',address).value
 local finish=df.reinterpret_cast('uint64_t',address+8).value
 assert(finish>=first and (finish-first)%16==0 and finish-first<=65536,'Invalid native worker widget children')
 for at=first,finish-1,16 do
  local ptr=df.reinterpret_cast('uint64_t',at).value
  if ptr~=0 then local found=worker_list(df.reinterpret_cast(df.widget,ptr),depth+1);if found then return found end end
 end
end
local function worker_names(widget,ids,depth,visible)
 assert(depth<10);visible=visible and (widget.flag.whole&1)==1
 if df.widget_unit_name:is_instance(widget) and visible then
  ids[#ids+1]=df.reinterpret_cast(df.widget_unit_name,widget).u.id
 end
 if not df.widget_container:is_instance(widget)then return end
 local _,address=df.sizeof(df.reinterpret_cast(df.widget_container,widget).children)
 local first=df.reinterpret_cast('uint64_t',address).value;local finish=df.reinterpret_cast('uint64_t',address+8).value
 assert(finish>=first and (finish-first)%16==0 and finish-first<=65536,'Invalid native worker row children')
 for at=first,finish-1,16 do local ptr=df.reinterpret_cast('uint64_t',at).value;if ptr~=0 then worker_names(df.reinterpret_cast(df.widget,ptr),ids,depth+1,visible)end end
end
local function worker_geometry(widget,rows,depth)
 assert(depth<12)
 if (widget.flag.whole&1)==0 then return end
 local r=widget.rect
 if r.y1>=0 and r.y1<64 and r.y2>=r.y1 then
  rows[#rows+1]={name=widget.name,type=tostring(widget._type),rect={r.x1,r.y1,r.x2,r.y2},depth=depth}
  if df.widget_columns_container:is_instance(widget)then rows[#rows].padding=df.reinterpret_cast(df.widget_columns_container,widget).padding end
 end
 if not df.widget_container:is_instance(widget)then return end
 local _,address=df.sizeof(df.reinterpret_cast(df.widget_container,widget).children)
 local first=df.reinterpret_cast('uint64_t',address).value;local finish=df.reinterpret_cast('uint64_t',address+8).value
 assert(finish>=first and (finish-first)%16==0 and finish-first<=65536)
 for at=first,finish-1,16 do local ptr=df.reinterpret_cast('uint64_t',at).value;if ptr~=0 then worker_geometry(df.reinterpret_cast(df.widget,ptr),rows,depth+1)end end
end
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
local function read_worker_reference(target)
 local native_ids={};local nonunit={}
 local list=assert(worker_list(df.global.game.main_interface.unit_selector,0))
 for _,entry in ipairs(list.entry_list)do
  if entry.t==0 and entry.u then -- Raw source list also contains filtered-out units.
  else nonunit[#nonunit+1]={kind=entry.t,null=not entry.u}end
 end
 worker_names(list,native_ids,0,true)
 local geometry={};worker_geometry(list,geometry,0)
 local worker_text,worker_code=dfhack.run_command_silent('df3d','workshop-workers-probe',tostring(target.id))
 assert(worker_code==0,worker_text)
 local semantic=json.decode(worker_text);local actual_ids=semantic.ids;local sorted_ids={table.unpack(native_ids)}
 local native_skills={}
 for skill=0,df.job_skill._last_item do if list.skills[skill]~=0 then native_skills[#native_skills+1]={skill=skill,weight=list.skills[skill]}end end
 assert(json.encode(native_skills)==json.encode(semantic.skills),'Workshop native skill weights differ')
 table.sort(sorted_ids);table.sort(actual_ids)
 local comparison=assert(io.open(out..'/workshop-workers-comparison-'..target.id..'.json','w'))
 comparison:write(json.encode({native_ids=native_ids,actual_ids=actual_ids,nonunit=nonunit}));comparison:close()
 assert(#sorted_ids==#actual_ids,'Workshop native worker membership count differs: '..#sorted_ids..' native / '..#actual_ids..' semantic')
 for i,id in ipairs(sorted_ids)do assert(actual_ids[i]==id,'Workshop native worker membership differs')end
 return {building_id=target.id,native_order=native_ids,member_ids=actual_ids,skills=native_skills,rows=semantic.rows,geometry=geometry,all_equal=true}
end
local ok,err=xpcall(function()
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());select_map(building)
 assert(sheet.open and sheet.active_sheet==df.view_sheet_type.BUILDING and sheet.active_id==building.id,'Native workshop selection missed')
 shot('jobs')
 assert(click_label('Workers'),'Native Workers tab not found')
 shot('workers')
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=448;g.precise_mouse_y=154;g.mouse_x=56;g.mouse_y=12
 df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
 shot('worker-selector')
 result.worker_candidates_reference=read_worker_reference(building)
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());select_map(building)
 assert(click_label('Work orders'),'Native Work orders tab not found')
 shot('work-orders')
 assert(click_label('Tasks'),'Native Tasks tab not found')
 assert(click_label('Add new task'),'Native Add new task control not found')
 shot('add-task')
 assert(click_label('Make bed'),'Native Make bed choice not found')
 assert(#building.jobs==#jobs+1,'Native Make bed did not create a task')
 local created=building.jobs[#building.jobs-1]
 shot('queued')
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
 assert(sheet.active_id==still.id,'Native Still selection missed')
 assert(click_label('Workers'),'Native Still Workers tab not found')
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=448;g.precise_mouse_y=154;g.mouse_x=56;g.mouse_y=12
 df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
 shot('still-worker-selector')
 result.still_worker_reference=read_worker_reference(still)
 -- Observe the assigned row through native input, then restore the restriction.
 local function worker_click(x,y)
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
  g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=math.floor(x/8);g.mouse_y=math.floor(y/12)
  df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
  df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
 end
 local profile=still:getWorkshopProfile()
 assert(#profile.permitted_workers==0,'Native worker reference must start unrestricted')
 worker_click(80,106)
 assert(#profile.permitted_workers==1,'Native worker click did not assign')
 result.assigned_worker_reference={building_id=still.id,unit_id=profile.permitted_workers[0]}
 shot('still-worker-assigned')
 local assigned=df.unit.find(profile.permitted_workers[0]);local specialized=assigned.flags4.only_do_assigned_jobs
 local text,code=dfhack.run_command_silent('df3d','workshop-workers-probe',tostring(still.id))
 assert(code==0,text);result.assigned_worker_reference.semantic=json.decode(text).assigned
 worker_click(448,250)
 assert(assigned.flags4.only_do_assigned_jobs~=specialized,'Native workshop specialization did not toggle')
 shot('still-worker-specialized')
 worker_click(448,250)
 assert(assigned.flags4.only_do_assigned_jobs==specialized,'Native workshop specialization did not restore')
 worker_click(448,190)
 result.assigned_worker_selector=read_worker_reference(still)
 shot('still-worker-selector-assigned')
 worker_click(80,106)
 assert(#profile.permitted_workers==0,'Native worker reselect did not restore unrestricted profile')
 shot('still-workers-restored')
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());select_map(still)
 assert(click_label('Tasks'),'Native Still Tasks tab not found')
 shot('still-jobs')
 assert(click_label('Add new task'),'Native Still picker did not open')
 local rows={};local utils=require('utils')
 for _,button in ipairs(df.global.game.main_interface.building.button)do
  if df.interface_button_building_new_jobst:is_instance(button) and button.jobtype==df.job_type.CustomReaction then
   local raw_index=-1;for index,reaction in ipairs(df.global.world.raws.reactions.reactions)do if reaction.code==button.mstring then raw_index=index;break end end
   rows[#rows+1]={raw_index=raw_index,code=dfhack.df2utf(button.mstring),caption=dfhack.df2utf(utils.call_with_string(button,'text')),
    objection=dfhack.df2utf(button.objection),available=not button.show_help_instead}
  end
 end
 local tasks={}
 for _,button in ipairs(df.global.game.main_interface.building.filtered_button)do
  assert(df.interface_button_building_new_jobst:is_instance(button),'Unexpected Still task category')
  local key=button.jobtype==df.job_type.CustomReaction and 'reaction:'..dfhack.df2utf(button.mstring) or 'builtin:'..button.jobtype..':'..button.material
  tasks[#tasks+1]={key=key,name=dfhack.df2utf(utils.call_with_string(button,'text')),availability={available=not button.show_help_instead,objection=dfhack.df2utf(button.objection)}}
  assert(button.list_priority==1000 and button.alpha_order==0,'Still ordering metadata changed')
 end
 result.task_reference={building_id=still.id,rows=tasks}
 local order=function(a,b)return a.code<b.code end;table.sort(rows,order)
 local permission_text,permission_code=dfhack.run_command_silent('df3d','workshop-reactions-probe',tostring(still.id))
 assert(permission_code==0,permission_text)
 local actual=json.decode(permission_text);table.sort(actual,order)
 assert(#rows>0 and #rows==#actual,'Native Still reaction membership differs')
 for i,row in ipairs(rows)do for key,value in pairs(row)do assert(actual[i][key]==value,'Native Still '..row.code..' '..key..' differs: '..tostring(actual[i][key])..' ~= '..tostring(value))end end
 local codes={};for _,row in ipairs(rows)do codes[#codes+1]=row.code end
 result.reaction_reference={building_id=still.id,codes=codes,rows=rows,all_equal=true}
 local contents={};for _,held in ipairs(still.contained_items)do contents[#contents+1]={id=held.item.id,role=held.use_mode}end
 result.sheet_reference={id=still.id,type=still:getType(),stage=still:getBuildStage(),max_stage=still:getMaxBuildStage(),custom_name=dfhack.df2utf(still.name),native_name=dfhack.df2utf(utils.call_with_string(still,'getName')),contents=contents}
 shot('still-add-task')
 local function search_text(value)
  if not sheet.entering_building_job_filter then
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
  g.precise_mouse_x=600;g.precise_mouse_y=154;g.mouse_x=75;g.mouse_y=12
  df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L')
  df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
  end
  assert(sheet.entering_building_job_filter,'Native workshop search did not focus')
  for i=1,#sheet.building_job_filter_str do gui.simulateInput(view,'STRING_A000')end
  for i=1,#value do gui.simulateInput(view,('STRING_A%03d'):format(value:byte(i)))end
  view:render(dfhack.getTickCount())
 end
 result.search_reference={cases={}}
 for _,query in ipairs{'BREW','fruit','Requires','zzzzz'}do
  search_text(query)
  local names={};for _,button in ipairs(df.global.game.main_interface.building.filtered_button)do names[#names+1]=dfhack.df2utf(utils.call_with_string(button,'text'))end
  result.search_reference.cases[#result.search_reference.cases+1]={query=query,names=names}
 end
 search_text(string.rep('x',100));result.search_reference.max_bytes=#sheet.building_job_filter_str
 search_text('BREW');gui.simulateInput(view,'SELECT');view:render(dfhack.getTickCount())
 result.search_reference.enter_releases_focus=not sheet.entering_building_job_filter
 shot('still-search')
 search_text('');gui.simulateInput(view,'SELECT');view:render(dfhack.getTickCount())
 local file=assert(io.open(out..'/workshop-native.json','w'));file:write(json.encode(result));file:close()
 local before_jobs={};for _,job in ipairs(still.jobs)do before_jobs[#before_jobs+1]=job.id end
 local original_workers={};for _,id in ipairs(still:getWorkshopProfile().permitted_workers)do original_workers[#original_workers+1]=id end
 capture('workshop-wire')
 local restored=still:getWorkshopProfile().permitted_workers
 assert(#restored==#original_workers,'Worker workflow did not restore native restriction')
 for i,id in ipairs(original_workers)do assert(restored[i-1]==id,'Worker workflow changed native restriction')end
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
