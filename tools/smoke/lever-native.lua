-- Native action discovery in a paused, owned disposable clone only.
local out,view,select_map,capture,click_label,read_worker_reference,resize_worker=...
local gui=require('gui');local json=require('json')
local lever=assert(df.building.find(55));assert(df.building_trapst:is_instance(lever) and lever.trap_type==0)
assert(#lever.jobs==0 and df.global.pause_state)
local sheet=df.global.game.main_interface.view_sheets
local result={building_id=lever.id,frame=df.global.world.frame_counter,states={}}
local supplies={}
local restore_manager
local function click(x,y)
 local g=df.global.gps
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
end
local function persist()
 local f=assert(io.open(out..'/lever-native.json','w'));f:write(json.encode(result));f:close()
end
local function sample(label)
 local row={label=label,custom_name=dfhack.df2utf(lever.name),stage=lever:getBuildStage(),max_stage=lever:getMaxBuildStage(),open=sheet.open,active_id=sheet.active_id,tab=sheet.active_sub_tab,linking=sheet.linking_lever,need_mechanisms=sheet.need_accessible_mechanism_warning,link_source=sheet.linking_lever_bld_id,lever_mechanism=sheet.linking_lever_mech_lever_id,target_mechanism=sheet.linking_lever_mech_target_id,jobs={}}
 for _,job in ipairs(lever.jobs)do
  local refs={};for _,ref in ipairs(job.general_refs)do refs[#refs+1]={type=ref:getType(),building_id=ref:getBuilding() and ref:getBuilding().id or -1}end
  row.jobs[#row.jobs+1]={id=job.id,type=job.job_type,flags=job.flags.whole,pos={job.pos.x,job.pos.y,job.pos.z},refs=refs,items=#job.items,requirements=#job.job_items.elements,world_registered=job.list_link~=nil and job.list_link.item==job}
  local values={};for _,item in ipairs(job.items)do values[#values+1]={id=item.item.id,role=item.role,flags=item.flags.whole,index=item.job_item_idx}end
  row.jobs[#row.jobs].item_roles=values
 end
 if os.getenv('DF3D_LEVER_MECHANISMS_PROVIDER')=='1' and (row.linking or label=='link-open')then
  local before=json.encode{sheet.open,sheet.active_id,sheet.linking_lever,sheet.linking_lever_bld_id,sheet.linking_lever_mech_lever_id,sheet.linking_lever_mech_target_id}
  local text,code=dfhack.run_command_silent('df3d','lever-mechanisms-probe',tostring(lever.id));assert(code==0,text)
  row.provider=json.decode(text)
  assert(before==json.encode{sheet.open,sheet.active_id,sheet.linking_lever,sheet.linking_lever_bld_id,sheet.linking_lever_mech_lever_id,sheet.linking_lever_mech_target_id},'Owned mechanism read changed native menu')
  assert(row.provider.available==row.linking,'Mechanism provider availability differs')
  if row.linking then assert(row.provider.lever_mechanism==row.lever_mechanism and row.provider.target_mechanism==row.target_mechanism,'Mechanism provider order differs')end
 end
 result.states[#result.states+1]=row;persist();capture('lever-'..label);return row
end
local ok,err=xpcall(function()
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());select_map(lever)
 assert(sheet.open and sheet.active_id==lever.id);sample('initial')
 if os.getenv('DF3D_LEVER_ITEM_NAV')=='1'then
  local item=assert(lever.contained_items[0].item)
  click(772,562);assert(sheet.active_sheet==df.view_sheet_type.ITEM and sheet.active_id==item.id);sample('item-view')
  click(816,250);assert(sheet.active_sheet==df.view_sheet_type.BUILDING and sheet.active_id==lever.id);sample('item-returned')
 end
 if os.getenv('DF3D_LEVER_RESIZE')=='1'then
  for _,size in ipairs{'minimum','wide','default'}do resize_worker(size);sample('resize-'..size)end
 end
 if os.getenv('DF3D_LEVER_NAVIGATION')=='1'then
  click(540,520);sample('linked-buildings')
  click(868,562);assert(not sheet.open);sample('linked-recenter')
  select_map(lever);assert(not sheet.show_linked_buildings);sample('linked-reopened')
 end
 if os.getenv('DF3D_LEVER_ITEMS')=='1'then
  local item=assert(lever.contained_items[0].item)
  result.item_controls={item_id=item.id,states={}}
  local function item_state(label)
   local row={label=label,forbid=item.flags.forbid,dump=item.flags.dump,melt=item.flags.melt,hidden=item.flags.hidden}
   result.item_controls.states[#result.item_controls.states+1]=row;sample(label)
  end
  item_state('item-initial')
  for _,control in ipairs{{'forbid',796},{'dump',820},{'hidden',868}}do
   click(control[2],562);item_state('item-'..control[1])
   click(control[2],562);item_state('item-'..control[1]..'-restored')
  end
 end
 if os.getenv('DF3D_LEVER_CONNECTIONS')=='1'then
  result.connections={can_link=lever:canLinkToStockpile()}
  click(768,82);sample('connections-open')
  click(80,82);sample('connections-give')
  assert(click_label('Cancel'));sample('connections-give-cancel')
  click(112,82);sample('connections-take')
  assert(click_label('Cancel'));assert(click_label('Done'));sample('connections-done')
  if os.getenv('DF3D_LEVER_CONNECTION_EFFECTS')=='1'then
   local links=assert(lever:getStockpileLinks())
   assert(#links.give_to_pile==0 and #links.take_from_pile==0)
   local pile
   for _,candidate in ipairs(df.global.world.buildings.other.STOCKPILE)do
    local d=dfhack.maps.getTileFlags(candidate.centerx,candidate.centery,candidate.z)
    if candidate.z==lever.z and d and not d.hidden then pile=candidate;break end
   end
   assert(pile);result.connections.pile_id=pile.id
   result.connections.pile_tile={x=pile.centerx,y=pile.centery,z=pile.z}
   local function has(rows,id)for _,row in ipairs(rows)do if row.id==id then return true end end;return false end
   for _,entry in ipairs{{'give',80,'give_to_pile','take_from_workshop'},{'take',112,'take_from_pile','give_to_workshop'}}do
    click(768,82);click(entry[2],82);select_map(pile)
    result.connections[entry[1]]={count=#links[entry[3]],reciprocal=has(pile.links[entry[4]],lever.id)}
    sample('connections-linked-'..entry[1])
    if #links[entry[3]]>0 then
     assert(#links[entry[3]]==1 and links[entry[3]][0].id==pile.id)
     click(360,154);assert(#links[entry[3]]==0 and not has(pile.links[entry[4]],lever.id))
     sample('connections-unlinked-'..entry[1])
    end
    assert(click_label('Done'))
   end
  end
 end
 if os.getenv('DF3D_LEVER_HEADER')=='1'then
  local original=lever.name
  local function key(value)gui.simulateInput(view,value);view:render(dfhack.getTickCount())end
  click(800,82);key('STRING_A120');key('SELECT');assert(lever.name==original..'x');sample('header-renamed')
  click(800,82);key('STRING_A000');key('SELECT');assert(lever.name==original);sample('header-restored')
  click(832,82);assert(#lever.jobs==1 and lever.jobs[0].job_type==df.job_type.DestroyBuilding);sample('header-removing')
  if os.getenv('DF3D_LEVER_NAVIGATION')=='1'then
   local item=lever.contained_items[0].item;local original_forbid=item.flags.forbid
   click(796,562);assert(item.flags.forbid~=original_forbid);sample('header-removing-forbid')
   click(796,562);assert(item.flags.forbid==original_forbid)
  end
  assert(click_label('Cancel removal'));assert(#lever.jobs==0 and lever:getBuildStage()==lever:getMaxBuildStage());sample('header-cancelled')
 end
 for index=1,2 do
  assert(click_label('Pull lever'),'Native Pull lever control missing')
  assert(#lever.jobs==index and lever.jobs[index-1].job_type==df.job_type.PullLever)
  sample('pull-'..index)
 end
 if os.getenv('DF3D_LEVER_QUEUED_REMOVE')=='1'then
  local first,second=lever.jobs[0].id,lever.jobs[1].id
  click(540,520);sample('queued-linked')
  click(832,82)
  assert(#lever.jobs==1 and lever.jobs[0].job_type==df.job_type.DestroyBuilding)
  local link=df.global.world.jobs.list.next
  while link do
   assert(not link.item or (link.item.id~=first and link.item.id~=second),'Native removal retained Pull jobs')
   link=link.next
  end
  sample('queued-removing')
  assert(click_label('Cancel removal'));assert(#lever.jobs==0);sample('queued-cancelled')
  click(720,520);sample('queued-items-restored')
 end
 if os.getenv('DF3D_LEVER_TASK_CONTROLS')=='1'then
  local first,second=lever.jobs[0],lever.jobs[1]
  click(748,154);assert(first.flags['repeat']);sample('pull-repeat')
  click(748,154);assert(not first.flags['repeat'])
  click(844,190);assert(second.flags.suspend);sample('pull-suspended')
  click(844,190);assert(not second.flags.suspend)
  click(796,190);assert(lever.jobs[0]==second and lever.jobs[1]==first);sample('pull-moved')
  click(772,190);assert(first.flags.do_now and lever.jobs[0]==first);sample('pull-priority')
  click(772,154);assert(not first.flags.do_now)
  click(868,190);assert(#lever.jobs==1 and lever.jobs[0]==first);sample('pull-cancel-second')
  click(868,154);assert(#lever.jobs==0);sample('pull-cancel-all')
 end
 -- Cleanup is deliberately separate from native cancellation acceptance.
 while #lever.jobs>0 do assert(dfhack.job.removeJob(lever.jobs[#lever.jobs-1]))end
 view:render(dfhack.getTickCount());sample('pull-cleaned')
 if os.getenv('DF3D_LEVER_PROVIDER')=='1'then
  for index=1,2 do
   local text,code=dfhack.run_command_silent('df3d','lever-pull-probe',tostring(lever.id))
   assert(code==0,text);local receipt=json.decode(text)
   assert(#lever.jobs==index and receipt.job_id==lever.jobs[index-1].id)
   view:render(dfhack.getTickCount());local observed=sample('provider-pull-'..index)
   local native;for _,state in ipairs(result.states)do if state.label=='pull-'..index then native=state;break end end
   assert(native,'Missing native Pull reference')
   for j,job in ipairs(observed.jobs)do
    assert(job.id~=native.jobs[j].id,'Provider reused a retired native job')
    for _,key in ipairs{'type','flags','pos','refs','items','requirements','world_registered'}do
     assert(json.encode(job[key])==json.encode(native.jobs[j][key]),'Native/provider Pull differs: '..key)
    end
   end
  end
  while #lever.jobs>0 do assert(dfhack.job.removeJob(lever.jobs[#lever.jobs-1]))end
  view:render(dfhack.getTickCount());sample('provider-cleaned')
 end
 assert(click_label('Workers'));sample('workers')
 if os.getenv('DF3D_LEVER_WORKERS')=='1'then
  click(448,154)
  result.worker_selector=read_worker_reference(lever,os.getenv('DF3D_LEVER_WORKERS_PROVIDER')~='1');sample('worker-selector')
  assert(#result.worker_selector.native_order>0,'Lever worker selector is empty')
  if os.getenv('DF3D_LEVER_WORKERS_PROVIDER')=='1'then
   local profile=assert(lever:getWorkshopProfile());assert(#profile.permitted_workers==0)
   click(80,106);assert(#profile.permitted_workers==1,'Lever worker selection did not assign')
   local text,code=dfhack.run_command_silent('df3d','workshop-workers-probe',tostring(lever.id));assert(code==0,text)
   result.assigned_worker=json.decode(text)
   assert(result.assigned_worker.assigned.id==profile.permitted_workers[0],'Assigned worker provider differs')
   sample('worker-assigned')
   click(448,190);click(80,106);assert(#profile.permitted_workers==0,'Lever worker reselect did not clear')
   gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
   sample('workers-restored')
  else
   gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());sample('worker-selector-cancel')
  end
 end
 assert(click_label('Work orders'));sample('work-orders')
 if os.getenv('DF3D_LEVER_ORDER_CATALOG')=='1'then
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
  assert(position,'Lever picker requires occupied fortress office')
  local indexed=fortress.assignments_by_type[responsibility];local prior={}
  for _,a in ipairs(indexed)do prior[#prior+1]=a end
  local previous=position.responsibilities[responsibility]
  restore_manager=function()
   position.responsibilities[responsibility]=previous;indexed:resize(0)
   for _,a in ipairs(prior)do indexed:insert('#',a)end
  end
  position.responsibilities[responsibility]=true;indexed:insert('#',assignment)
  view:render(dfhack.getTickCount());sample('orders-manager')
  local before=#df.global.world.manager_orders.all
  click(880,154)
  local picker=df.global.game.main_interface.create_work_order
  assert(picker.open and picker.forced_bld_id==lever.id,'Forced lever order picker did not open')
  result.order_catalog={groups=#picker.building,global_count=#picker.jminfo_master,orders_before=before,rows={}}
  assert(#picker.building==1)
  for _,r in ipairs(picker.building[0].jminfo)do
   result.order_catalog.rows[#result.order_catalog.rows+1]={job_type=r.job_type,reaction=r.reaction_name,item_type=r.item_type,item_subtype=r.item_subtype,mat_type=r.mat_type,mat_index=r.mat_index,caption=dfhack.df2utf(r.name),compare=dfhack.df2utf(r.compare_str)}
  end
  sample('order-picker')
  if os.getenv('DF3D_LEVER_ORDER_VIEWER')=='1'then
   local text,code=dfhack.run_command_silent('df3d','work-orders-catalog-probe',tostring(lever.id));assert(code==0,text)
   result.order_catalog.owned=json.decode(text).rows
   assert(json.encode(result.order_catalog.rows)==json.encode(result.order_catalog.owned),'Lever catalog differs from native')
  end
  gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());assert(not picker.open)
  assert(#df.global.world.manager_orders.all==before,'Opening lever picker created orders')
  if os.getenv('DF3D_LEVER_ORDER_VIEWER')~='1'then restore_manager();restore_manager=nil end
 end
 if os.getenv('DF3D_LEVER_WORKERS_PROVIDER')=='1'then
  local profile=lever:getWorkshopProfile();local before=profile.max_general_orders
  assert(before<99);click(840,478);assert(profile.max_general_orders==before+1);sample('order-limit-plus')
  click(872,478);assert(profile.max_general_orders==before);sample('order-limit-restored')
 end
 if os.getenv('DF3D_LEVER_WORKERS_PROVIDER')=='1'then
  local text,code=dfhack.run_command_silent('df3d','workshop-orders-probe',tostring(lever.id));assert(code==0,text)
  result.order_profile=json.decode(text)
  assert(result.order_profile.general_order_limit==lever:getWorkshopProfile().max_general_orders)
  local ids={};for _,order in ipairs(df.global.world.manager_orders.all)do if order.workshop_id==lever.id then ids[#ids+1]=order.id end end
  assert(json.encode(ids)==json.encode(result.order_profile.order_ids),'Lever order membership differs')
 end
 assert(click_label('Tasks'));sample('tasks-return')
 assert(click_label('Link lever'));sample('link-open')
 if os.getenv('DF3D_LEVER_WARNING_VIEWER')=='1'then
  assert(not sheet.linking_lever and sheet.need_accessible_mechanism_warning and #lever.jobs==0)
  local menu=json.encode{sheet.open,sheet.active_id,sheet.linking_lever,sheet.need_accessible_mechanism_warning}
  capture('lever-warning-wire')
  local f=assert(io.open(out..'/lever-warning-wire-result.json'));local receipt=json.decode(f:read('*a'));f:close()
  assert(receipt.success and #lever.jobs==0,'Warning viewer created jobs or failed')
  assert(menu==json.encode{sheet.open,sheet.active_id,sheet.linking_lever,sheet.need_accessible_mechanism_warning},'Warning viewer changed native UI')
  result.warning_viewer=receipt
 end
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());sample('link-cancel')
 if os.getenv('DF3D_LEVER_LINK')=='1'then
  local worker
  for _,unit in ipairs(df.global.world.units.active)do if dfhack.units.isCitizen(unit)then worker=unit;break end end
  local original=assert(df.item.find(1617));result.supplies={}
  for index=1,2 do
   local created=dfhack.items.createItem(assert(worker),df.item_type.TRAPPARTS,-1,original:getMaterial(),original:getMaterialIndex())
   assert(#created==1);local item=created[1];supplies[#supplies+1]=item
   assert(dfhack.items.moveToGround(item,{x=lever.centerx,y=lever.centery,z=lever.z}))
   item.flags.forbid=false;result.supplies[#result.supplies+1]=item.id
  end
  select_map(lever);assert(click_label('Link lever'));sample('link-with-supplies')
  if os.getenv('DF3D_LEVER_RESIZE')=='1'then
   for _,size in ipairs{'minimum','wide','default'}do resize_worker(size);sample('prompt-resize-'..size)end
  end
  assert(sheet.linking_lever,'Native Link did not accept accessible fixture mechanisms')
  if os.getenv('DF3D_LEVER_LINK_DETAIL')=='1'then
   local function reopen_link()
    if sheet.open then gui.simulateInput(view,'LEAVESCREEN')end
    view:render(dfhack.getTickCount());select_map(lever);assert(click_label('Link lever'));assert(sheet.linking_lever)
   end
   if os.getenv('DF3D_LEVER_TARGET_FAMILIES')=='1'then
    local allowed={[0]=true,[8]=true,[9]=true,[19]=true,[23]=true,[25]=true,[27]=true,[28]=true,[31]=true,[35]=true,[36]=true,[37]=true,[38]=true,[39]=true,[40]=true}
    local candidates,seen={},{}
    for _,candidate in ipairs(df.global.world.buildings.all)do
     local kind=candidate:getType();local key=tostring(kind)..':'..tostring(candidate:getSubtype())
     local tile=dfhack.maps.getTileFlags(candidate.centerx,candidate.centery,candidate.z)
     if allowed[kind] and candidate.id~=lever.id and candidate.z==lever.z and candidate:getBuildStage()==candidate:getMaxBuildStage() and tile and not tile.hidden and not seen[key]then
      candidates[#candidates+1]=candidate;seen[key]=true
     end
    end
    result.target_families={}
    for _,candidate in ipairs(candidates)do
     reopen_link()
     local ids={sheet.linking_lever_mech_lever_id,sheet.linking_lever_mech_target_id}
     local args={tostring(lever.id),tostring(candidate.centerx),tostring(candidate.centery),tostring(candidate.z)}
     local text,code=dfhack.run_command_silent('df3d','lever-target-probe',table.unpack(args));assert(code==0,text)
     local prediction=json.decode(text)
     select_map(candidate)
     local label='target-family-'..candidate:getType()..'-'..candidate:getSubtype()
     local observed=sample(label)
     local entry={id=candidate.id,type=candidate:getType(),subtype=candidate:getSubtype(),prediction=prediction,native_jobs=observed.jobs}
     result.target_families[#result.target_families+1]=entry
     assert(#lever.jobs==(prediction.target_id>=0 and 1 or 0),'Target eligibility differs from native')
     if prediction.target_id>=0 then
      local target_id=-1;for _,ref in ipairs(observed.jobs[1].refs)do if ref.type==33 then target_id=ref.building_id end end
      assert(target_id==prediction.target_id,'Native chose a different target')
      click(868,154);assert(#lever.jobs==0,'Native target-family cancellation failed')
      for _,id in ipairs(ids)do assert(not df.item.find(id).flags.in_job,'Cancellation retained mechanism')end
      text,code=dfhack.run_command_silent('df3d','lever-link-probe',table.unpack({args[1],args[2],args[3],args[4],tostring(ids[1]),tostring(ids[2])}));assert(code==0,text)
      local produced=sample(label..'-provider');entry.provider_jobs=produced.jobs
      for _,key in ipairs{'type','flags','pos','refs','items','item_roles','requirements','world_registered'}do
       assert(json.encode(produced.jobs[1][key])==json.encode(observed.jobs[1][key]),'Target-family job differs: '..key)
      end
      assert(dfhack.job.removeJob(lever.jobs[0]))
     end
    end
    reopen_link();persist()
   end
   if os.getenv('DF3D_LEVER_MECHANISMS_PROVIDER')=='1'then
    local first=assert(df.item.find(sheet.linking_lever_mech_lever_id));local forbidden=first.flags.forbid
    first.flags.forbid=true;reopen_link();sample('link-forbid-first')
    assert(sheet.linking_lever_mech_lever_id~=first.id and sheet.linking_lever_mech_target_id~=first.id)
    first.flags.forbid=forbidden;reopen_link();sample('link-restored-first')
    assert(sheet.linking_lever_mech_lever_id==first.id)
   end
   click(200,142);sample('source-mechanism-row-click')
   reopen_link();click(200,178);sample('target-mechanism-row-click')
   reopen_link()
   local target
   for _,candidate in ipairs(df.global.world.buildings.all)do
    if candidate:getType()==df.building_type.Door and candidate.z==lever.z and candidate:getBuildStage()==candidate:getMaxBuildStage()then
     local tile=dfhack.maps.getTileFlags(candidate.centerx,candidate.centery,candidate.z)
     if tile and not tile.hidden then target=candidate;break end
    end
   end
   assert(target,'No revealed completed door for link probe');result.link_target=target.id
   local function target_probe()
    local text,code=dfhack.run_command_silent('df3d','lever-target-probe',tostring(lever.id),tostring(target.centerx),tostring(target.centery),tostring(target.z))
    assert(code==0,text);return json.decode(text)
   end
   local mechanism_ids={sheet.linking_lever_mech_lever_id,sheet.linking_lever_mech_target_id}
   if os.getenv('DF3D_LEVER_LINK_PROVIDER')=='1'then result.target_before=target_probe();assert(result.target_before.target_id==target.id)end
   select_map(target);local native_link=sample('link-target-click')
   assert(#lever.jobs==1 and lever.jobs[0].job_type==df.job_type.LinkBuildingToTrigger,'Native target click did not create link job')
   if os.getenv('DF3D_LEVER_TASK_CONTROLS')=='1'then
    local job=lever.jobs[0]
    click(748,154);assert(job.flags['repeat']);sample('link-repeat')
    click(748,154);assert(not job.flags['repeat'])
    click(844,154);assert(job.flags.suspend);sample('link-suspended')
    click(844,154);assert(not job.flags.suspend)
   end
   if os.getenv('DF3D_LEVER_LINK_PROVIDER')=='1'then result.target_pending=target_probe();assert(result.target_pending.target_id==-1)end
   if os.getenv('DF3D_LEVER_TASK_CONTROLS')=='1'then
    click(868,154);assert(#lever.jobs==0,'Native Link cancellation retained job')
    for _,id in ipairs(mechanism_ids)do assert(not df.item.find(id).flags.in_job,'Native Link cancellation retained mechanism reservation')end
   else assert(dfhack.job.removeJob(lever.jobs[0]))end
   view:render(dfhack.getTickCount());sample('link-job-cleaned')
   if os.getenv('DF3D_LEVER_LINK_PROVIDER')=='1'then
    local text,code=dfhack.run_command_silent('df3d','lever-link-probe',tostring(lever.id),tostring(target.centerx),tostring(target.centery),tostring(target.z),tostring(mechanism_ids[1]),tostring(mechanism_ids[2]))
    assert(code==0,text);result.link_receipt=json.decode(text)
    assert(#lever.jobs==1 and lever.jobs[0].id==result.link_receipt.job_id)
    view:render(dfhack.getTickCount());local observed=sample('provider-link-target')
    for _,key in ipairs{'type','flags','pos','refs','items','item_roles','requirements','world_registered'}do
     assert(json.encode(observed.jobs[1][key])==json.encode(native_link.jobs[1][key]),'Native/provider Link differs: '..key)
    end
    local duplicate,duplicate_code=dfhack.run_command_silent('df3d','lever-link-probe',tostring(lever.id),tostring(target.centerx),tostring(target.centery),tostring(target.z),tostring(mechanism_ids[1]),tostring(mechanism_ids[2]))
    assert(duplicate_code~=0 and #lever.jobs==1,'Duplicate pending Link was accepted')
    result.duplicate_rejected=true
    assert(dfhack.job.removeJob(lever.jobs[0]));view:render(dfhack.getTickCount());sample('provider-link-cleaned')
   end
   if sheet.open then gui.simulateInput(view,'LEAVESCREEN')end
   select_map(lever);assert(click_label('Link lever'));sample('link-reopened')
  end
  gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());sample('link-with-supplies-cancel')
 end
 if os.getenv('DF3D_LEVER_WIRE')=='1'then
  local target=assert(df.building.find(result.link_target))
  local expected={target_id=target.id,x=target.centerx,y=target.centery,z=target.z,
   source_mechanism=sheet.linking_lever_mech_lever_id,target_mechanism=sheet.linking_lever_mech_target_id}
  local file=assert(io.open(out..'/lever-wire-expected.json','w'));file:write(json.encode(expected));file:close()
  local menu=json.encode{sheet.open,sheet.active_id,sheet.linking_lever,sheet.linking_lever_mech_lever_id,sheet.linking_lever_mech_target_id}
  capture('workshop-wire')
  file=assert(io.open(out..'/workshop-wire-result.json'));local wire=json.decode(file:read('*a'));file:close()
  assert(wire.success and #lever.jobs==2,'Lever wire action count mismatch');result.wire=wire
  if os.getenv('DF3D_LEVER_CONNECTION_VIEWER')=='1'then
   local links=lever:getStockpileLinks();local pile=df.building.find(result.connections.pile_id)
   assert(#links.give_to_pile==0 and #links.take_from_pile==0,'Viewer retained lever stockpile links')
   for _,field in ipairs{'take_from_workshop','give_to_workshop'}do
    for _,target in ipairs(pile.links[field])do assert(target.id~=lever.id,'Viewer retained reciprocal link')end
   end
   result.connections.viewer_restored=true
  end
  assert(menu==json.encode{sheet.open,sheet.active_id,sheet.linking_lever,sheet.linking_lever_mech_lever_id,sheet.linking_lever_mech_target_id},'Wire borrowed native menu state')
  local observed=sample('wire-jobs')
  for index,kind in ipairs{'pull-1','link-target-click'}do
   local reference;for _,state in ipairs(result.states)do if state.label==kind then reference=state.jobs[1]end end
   assert(reference,'Missing native job reference')
   local job=observed.jobs[index];assert(job.id==(index==1 and wire.pull_job or wire.link_job),'Wire job identity mismatch')
   for _,key in ipairs{'type','flags','pos','refs','items','item_roles','requirements','world_registered'}do
    assert(json.encode(job[key])==json.encode(reference[key]),'Wire/native job differs: '..key)
   end
  end
  while #lever.jobs>0 do assert(dfhack.job.removeJob(lever.jobs[#lever.jobs-1]))end
 end
 assert(#lever.jobs==0 and df.global.world.frame_counter==result.frame)
end,debug.traceback)
while #lever.jobs>0 do assert(dfhack.job.removeJob(lever.jobs[#lever.jobs-1]))end
for index=#supplies,1,-1 do assert(dfhack.items.remove(supplies[index]))end
if restore_manager then
 restore_manager()
 assert(#df.global.world.manager_orders.all==result.order_catalog.orders_before,'Lever picker viewer changed orders')
end
result.success=ok;result.error=ok and '' or tostring(err);persist();assert(ok,err)
