-- Native action discovery in a paused, owned disposable clone only.
local out,view,select_map,capture,click_label=...
local gui=require('gui');local json=require('json')
local lever=assert(df.building.find(55));assert(df.building_trapst:is_instance(lever) and lever.trap_type==0)
assert(#lever.jobs==0 and df.global.pause_state)
local sheet=df.global.game.main_interface.view_sheets
local result={building_id=lever.id,frame=df.global.world.frame_counter,states={}}
local supplies={}
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
 local row={label=label,open=sheet.open,active_id=sheet.active_id,tab=sheet.active_sub_tab,linking=sheet.linking_lever,need_mechanisms=sheet.need_accessible_mechanism_warning,link_source=sheet.linking_lever_bld_id,lever_mechanism=sheet.linking_lever_mech_lever_id,target_mechanism=sheet.linking_lever_mech_target_id,jobs={}}
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
 for index=1,2 do
  assert(click_label('Pull lever'),'Native Pull lever control missing')
  assert(#lever.jobs==index and lever.jobs[index-1].job_type==df.job_type.PullLever)
  sample('pull-'..index)
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
   local native=result.states[index+1]
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
 assert(click_label('Work orders'));sample('work-orders')
 assert(click_label('Tasks'));sample('tasks-return')
 assert(click_label('Link lever'));sample('link-open')
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
  assert(sheet.linking_lever,'Native Link did not accept accessible fixture mechanisms')
  if os.getenv('DF3D_LEVER_LINK_DETAIL')=='1'then
   local function reopen_link()
    if sheet.open then gui.simulateInput(view,'LEAVESCREEN')end
    view:render(dfhack.getTickCount());select_map(lever);assert(click_label('Link lever'));assert(sheet.linking_lever)
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
   if os.getenv('DF3D_LEVER_LINK_PROVIDER')=='1'then result.target_pending=target_probe();assert(result.target_pending.target_id==-1)end
   assert(dfhack.job.removeJob(lever.jobs[0]));view:render(dfhack.getTickCount());sample('link-job-cleaned')
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
 assert(#lever.jobs==0 and df.global.world.frame_counter==result.frame)
end,debug.traceback)
while #lever.jobs>0 do assert(dfhack.job.removeJob(lever.jobs[#lever.jobs-1]))end
for index=#supplies,1,-1 do assert(dfhack.items.remove(supplies[index]))end
result.success=ok;result.error=ok and '' or tostring(err);persist();assert(ok,err)
