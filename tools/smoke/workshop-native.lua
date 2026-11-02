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
local function resize_worker(size)
 local script=require('gui.script')
 local f=assert(io.open(out..'/owner-input-request.tmp','w'));f:write('name-resize-'..size);f:close()
 assert(os.rename(out..'/owner-input-request.tmp',out..'/owner-input-request'))
 local limit=dfhack.getTickCount()+30000
 while true do local ack=io.open(out..'/owner-input-ack');if ack then ack:close();break end
  assert(dfhack.getTickCount()<limit,'worker resize timeout');script.sleep(1,'frames')end
 assert(os.remove(out..'/owner-input-ack'));script.sleep(2,'frames');view:render(dfhack.getTickCount())
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
 local limit_before=building:getWorkshopProfile().max_general_orders
 local function order_click(x)
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
  g.precise_mouse_x=x;g.precise_mouse_y=478;g.mouse_x=math.floor(x/8);g.mouse_y=39
  df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
  df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
 end
 assert(limit_before>=0 and limit_before<99,'Reference needs a reversible general-order increment')
 order_click(840);assert(building:getWorkshopProfile().max_general_orders==limit_before+1,'Native general-order increase failed')
 order_click(872);assert(building:getWorkshopProfile().max_general_orders==limit_before,'Native general-order decrease failed')
 result.general_order_steps={before=limit_before,increased=limit_before+1,restored=limit_before}
 -- Numeric entry applies each changed draft; SELECT only ends editing.
 order_click(808)
 local numeric={}
 local function number_key(key)
  gui.simulateInput(view,key);view:render(dfhack.getTickCount())
  numeric[#numeric+1]={key=key,draft=sheet.gen_work_order_num_str,editing=sheet.entering_gen_work_order_num,value=building:getWorkshopProfile().max_general_orders}
 end
 assert(sheet.entering_gen_work_order_num and sheet.gen_work_order_num_str=='','Native number editor did not start empty')
 number_key('STRING_A049');assert(building:getWorkshopProfile().max_general_orders==1,'Native first digit did not apply')
 number_key('STRING_A050');assert(building:getWorkshopProfile().max_general_orders==12,'Native second digit did not apply')
 number_key('SELECT');assert(not sheet.entering_gen_work_order_num,'Native number Enter did not release editing')
 order_click(808)
 for digit in tostring(limit_before):gmatch('.')do number_key(('STRING_A%03d'):format(digit:byte()))end
 number_key('SELECT');assert(building:getWorkshopProfile().max_general_orders==limit_before,'Native number editor failed to restore limit')
 result.general_order_numeric=numeric
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
 local order_text,order_code=dfhack.run_command_silent('df3d','workshop-orders-probe',tostring(still.id))
 assert(order_code==0,order_text);result.still_orders_reference=json.decode(order_text)
 assert(result.still_orders_reference.general_order_limit==still:getWorkshopProfile().max_general_orders,'Order limit reader differs')
 assert(result.still_orders_reference.manager_available==(#df.global.plotinfo.main.fortress_entity.assignments_by_type[df.entity_position_responsibility.MANAGE_PRODUCTION]>0),'Manager prerequisite reader differs')
 local expected_orders={};for _,order in ipairs(df.global.world.manager_orders.all)do if order.workshop_id==still.id then expected_orders[#expected_orders+1]=order.id end end
 assert(json.encode(result.still_orders_reference.order_ids)==json.encode(expected_orders),'Workshop order membership differs')
 assert(click_label('Workers'),'Native Still Workers tab not found')
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=448;g.precise_mouse_y=154;g.mouse_x=56;g.mouse_y=12
 df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
 shot('still-worker-selector')
 result.still_worker_reference=read_worker_reference(still)
 resize_worker('small')
 result.small_worker_reference=read_worker_reference(still)
 shot('still-worker-selector-small')
 resize_worker('default')
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
 -- Controlled clone fixture: grant an occupied fortress office the manager
 -- responsibility, as in the existing petition panel oracle. Restore it after
 -- opening/cancelling the real native picker; no orders are created here.
 local fortress=assert(df.global.plotinfo.main.fortress_entity)
 local responsibility=df.entity_position_responsibility.MANAGE_PRODUCTION
 local position,assignment
 for _,a in ipairs(fortress.positions.assignments)do
  if a.histfig>=0 then
   local present=false;for _,u in ipairs(df.global.world.units.active)do if u.hist_figure_id==a.histfig then present=true;break end end
   if present then for _,p in ipairs(fortress.positions.own)do if p.id==a.position_id then position=p;assignment=a;break end end end
  end
  if position then break end
 end
 assert(position,'Order picker reference needs an occupied fortress office')
 local indexed=fortress.assignments_by_type[responsibility];local prior_index={}
 for _,a in ipairs(indexed)do prior_index[#prior_index+1]=a end
 local prior_responsibility=position.responsibilities[responsibility]
 position.responsibilities[responsibility]=true;indexed:insert('#',assignment)
 local orders_before=#df.global.world.manager_orders.all
 local prior_order_ids={};for _,o in ipairs(df.global.world.manager_orders.all)do prior_order_ids[#prior_order_ids+1]=o.id end
 local picker=df.global.game.main_interface.create_work_order
 local function read_rows(rows)
  local values={}
  for _,r in ipairs(rows)do values[#values+1]={job_type=r.job_type,reaction=r.reaction_name,item_type=r.item_type,item_subtype=r.item_subtype,mat_type=r.mat_type,mat_index=r.mat_index,caption=dfhack.df2utf(r.name),compare=dfhack.df2utf(r.compare_str)}end
  return values
 end
 local function catalog(target)
  select_map(target);assert(click_label('Work orders'));shot('order-picker-entry-'..target.id)
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
  g.precise_mouse_x=880;g.precise_mouse_y=154;g.mouse_x=110;g.mouse_y=12
  df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
  df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
  assert(picker.open and picker.forced_bld_id==target.id,'Native forced workshop picker did not open')
  local text,code=dfhack.run_command_silent('df3d','work-orders-catalog-probe');assert(code==0,text)
  local global=json.decode(text).rows;local native_global=read_rows(picker.jminfo_master)
  assert(json.encode(global)==json.encode(native_global),'Owned global order catalog differs from native picker')
  assert(#picker.building==1,'Forced workshop picker should have one group')
  text,code=dfhack.run_command_silent('df3d','work-orders-catalog-probe',tostring(target.id));assert(code==0,text)
  local filtered=json.decode(text).rows;local native_filtered=read_rows(picker.building[0].jminfo)
  local comparison=assert(io.open(out..'/work-order-catalog-'..target.id..'.json','w'))
  comparison:write(json.encode({native=native_filtered,owned=filtered}));comparison:close()
  assert(json.encode(filtered)==json.encode(native_filtered),'Owned workshop order catalog differs from native picker')
  result.order_catalogs=result.order_catalogs or {};result.order_catalogs[#result.order_catalogs+1]={building_id=target.id,global_count=#global,filtered_count=#filtered,rows=filtered}
  shot('order-picker-'..target.id)
  gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());assert(not picker.open)
  gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
 end
 local function order_values(order)
  return {job_type=order.job_type,reaction=order.reaction_name,item_type=order.item_type,item_subtype=order.item_subtype,
   mat_type=order.mat_type,mat_index=order.mat_index,specflag=order.specflag.whole,specdata=order.specdata.hist_figure_id,
   material_category=order.material_category.whole,art_type=order.art_spec.type,art_id=order.art_spec.id,art_subid=order.art_spec.subid,
   amount_left=order.amount_left,amount_total=order.amount_total,status=order.status.whole,frequency=order.frequency,
   finished_year=order.finished_year,finished_tick=order.finished_year_tick,workshop_id=order.workshop_id,max_workshops=order.max_workshops,
   item_conditions=#order.item_conditions,order_conditions=#order.order_conditions,items=order.items~=nil}
 end
 local catalog_ok,catalog_err=xpcall(function()
  catalog(building);catalog(still)
  assert(#df.global.world.manager_orders.all==orders_before,'Opening/cancelling picker created an order')
  select_map(still);assert(click_label('Work orders'))
  local function mouse(x,y)
   df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
   g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=math.floor(x/8);g.mouse_y=math.floor(y/12)
   df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
   df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
  end
  mouse(880,154);assert(picker.open)
  local chosen=picker.building[0].jminfo[2];assert(chosen.name=='Extract from plants')
  mouse(600,94)
  for char in ('extract'):gmatch('.')do gui.simulateInput(view,('STRING_A%03d'):format(char:byte()))end
  view:render(dfhack.getTickCount())
  local matches={};for _,row in ipairs(picker.building[0].jminfo)do if row.on then matches[#matches+1]=dfhack.df2utf(row.name)end end
  assert(#matches==1 and matches[1]=='Extract from plants','Native order search changed')
  shot('order-search-native')
  gui.simulateInput(view,'SELECT');view:render(dfhack.getTickCount());assert(picker.open,'Search Enter unexpectedly closed picker')
  local next_id=df.global.world.manager_orders.manager_order_next_id
  mouse(600,130);assert(not picker.open,'Native recipe click did not close picker')
  assert(#df.global.world.manager_orders.all==orders_before+1)
  local native=df.global.world.manager_orders.all[orders_before];assert(native.id==next_id)
  local expected={building_id=still.id,choice=0,query='extract',search_names=matches,caption='Extract from plants',native=order_values(native),native_id=native.id}
  shot('orders-created-native')
  mouse(775,190)
  gui.simulateInput(view,'STRING_A049');view:render(dfhack.getTickCount())
  assert(native.amount_left==1 and native.amount_total==1,'Native order quantity first digit differs')
  gui.simulateInput(view,'STRING_A050');view:render(dfhack.getTickCount())
  assert(native.amount_left==12 and native.amount_total==12,'Native order quantity second digit differs')
  shot('order-quantity-native')
  gui.simulateInput(view,'SELECT');view:render(dfhack.getTickCount())
  expected.quantity_native=order_values(native)
  mouse(808,190)
  local conditions=df.global.game.main_interface.info.work_orders.conditions
  assert(conditions.open and conditions.wq.id==next_id,'Native work-order conditions did not open')
  result.order_conditions={order_id=next_id,frequency=native.frequency,suggested_count=#conditions.suggested_item_condition}
  shot('order-conditions-native')
  -- The supported XML declares value elements here, but native stores pointers.
  -- This raw diagnostic observation never supplies runtime UI state.
  local _,condition_address=df.sizeof(conditions)
  local first=df.reinterpret_cast('uint64_t',condition_address+0x58).value
  local finish=df.reinterpret_cast('uint64_t',condition_address+0x60).value
  assert(finish>=first and (finish-first)%8==0 and finish-first<=1024)
  local native_suggestions={}
  for at=first,finish-1,8 do
   local pointer=df.reinterpret_cast('uint64_t',at).value
   local c=df.reinterpret_cast(df.manager_order_condition_item,pointer)
   local contained={};for _,value in ipairs(c.contains)do contained[#contained+1]=value end
   native_suggestions[#native_suggestions+1]={compare=c.compare_type,threshold=c.compare_val,item_type=c.item_type,item_subtype=c.item_subtype,
    mat_type=c.mat_type,mat_index=c.mat_index,flags1=c.flags1.whole,flags2=c.flags2.whole,flags3=c.flags3.whole,flags4=c.flags4,flags5=c.flags5,
    reaction_class=c.reaction_class,material_product=c.has_material_reaction_product,metal_ore=c.metal_ore,min_dimension=c.min_dimension,
    reaction_id=c.reaction_id,tool_use=c.has_tool_use,dye_color=c.dye_color,contains=contained}
  end
  local function context_bytes()
   local values={};for i=0,0x6f do values[#values+1]=df.reinterpret_cast('uint8_t',condition_address+i).value end;return table.concat(values,',')
  end
  local before_context=context_bytes();local before_order=json.encode(order_values(native))
  local text,code=dfhack.run_command_silent('df3d','work-order-suggestions-probe',tostring(next_id));assert(code==0,text)
  local owned=json.decode(text).rows
  assert(#owned==#native_suggestions,'Owned native suggestion count differs')
  for i,c in ipairs(native_suggestions)do for key,value in pairs(c)do
   if key=='contains' then assert(json.encode(value)==json.encode(owned[i][key]),'Suggestion contained identities differ')
   else assert(value==owned[i][key],'Suggestion '..i..' '..key..' differs')end
  end end
  assert(before_context==context_bytes() and before_order==json.encode(order_values(native)),'Owned suggestions changed source order or native context')
  result.order_conditions.suggested_count=#native_suggestions
  result.order_conditions.suggestions=native_suggestions
  result.order_conditions.owned_suggestions=owned
  result.order_conditions.source_unchanged=true

  result.order_conditions.frequency_steps={}
  for i=1,5 do
   mouse(880,142)
   result.order_conditions.frequency_steps[#result.order_conditions.frequency_steps+1]={frequency=native.frequency,status=native.status.whole,finished_year=native.finished_year,finished_tick=native.finished_year_tick,lines=lines()}
  end
  shot('order-conditions-frequency-native')
  assert(native.frequency==expected.native.frequency,'Frequency cycle did not return to original value')
  gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());assert(not conditions.open)
  if df.global.game.main_interface.info.open then gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())end
  select_map(still);assert(click_label('Work orders'))
  mouse(840,190)
  assert(df.global.game.main_interface.job_details.open,'Native order Details did not open')
  shot('order-details-native')
  gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
  select_map(still);assert(click_label('Work orders'))
  local dependent=assert(df.global.world.manager_orders.all[0]);assert(dependent.id~=next_id)
  local prior_dependencies=#dependent.order_conditions
  local function dependency(target)
   local c=df.manager_order_condition_order:new();c.order_id=target;c.condition=0;c.flags.whole=0
   dependent.order_conditions:insert('#',c)
  end
  dependency(next_id)
  mouse(872,190)
  assert(#df.global.world.manager_orders.all==orders_before,'Native remove retained order')
  assert(#dependent.order_conditions==prior_dependencies,'Native remove retained incoming dependency')
  shot('order-removed-native')
  -- The new viewer order will receive the next identity. Keep this paused
  -- diagnostic dependency so removal is checked against an independent record.
  dependency(next_id+1)

  local file=assert(io.open(out..'/workshop-order-expected.json','w'));file:write(json.encode(expected));file:close()
  gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
  capture('workshop-order-wire')
  assert(#df.global.world.manager_orders.all==orders_before,'Viewer removal did not restore order count')
  for i,id in ipairs(prior_order_ids)do assert(df.global.world.manager_orders.all[i-1].id==id,'Viewer removal changed unrelated order sequence')end
  assert(#dependent.order_conditions==prior_dependencies,'Viewer removal retained incoming dependency')
  local comparison=assert(io.open(out..'/workshop-order-removal-comparison.json','w'))
  comparison:write(json.encode({native_removed=next_id,viewer_removed=next_id+1,remaining_ids=prior_order_ids,dependencies_restored=true}));comparison:close()
  assert(df.global.plotinfo.nobles.manager_cooldown==0,'Viewer creation did not reset manager cooldown')
  result.order_removal={native_id=next_id,viewer_id=next_id+1,unrelated_ids_unchanged=true,dependencies_restored=true}

 end,debug.traceback)
 position.responsibilities[responsibility]=prior_responsibility;indexed:resize(0)
 for _,a in ipairs(prior_index)do indexed:insert('#',a)end
 assert(catalog_ok,catalog_err)
end,debug.traceback)
assert(#building.jobs==#jobs,'Workshop capture changed job count')
for i,id in ipairs(jobs)do assert(building.jobs[i-1].id==id,'Workshop capture changed job order')end
select_map(original)
assert(df.global.pause_state and df.global.world.frame_counter==frame,'Workshop capture advanced simulation')
assert(ok,err)
records[#records+1]={name='workshop-native-reference',building_id=building.id,jobs_unchanged=true}
return result
