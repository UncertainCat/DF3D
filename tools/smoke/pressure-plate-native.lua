-- Native screen discovery only, in the paused owned disposable clone.
local out,view,select_map,capture,click_label,read_worker_reference=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local sheet=df.global.game.main_interface.view_sheets
local result={states={},candidates={}}
local supplies={}
local function click(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
end
local provider=os.getenv('DF3D_PRESSURE_PLATE_PROVIDER')=='1'
local function owned(command,...)
 local before=json.encode{sheet.open,sheet.active_id,sheet.linking_lever,sheet.linking_lever_mech_lever_id,sheet.linking_lever_mech_target_id}
 local text,code=dfhack.run_command_silent('df3d',command,...)
 assert(before==json.encode{sheet.open,sheet.active_id,sheet.linking_lever,sheet.linking_lever_mech_lever_id,sheet.linking_lever_mech_target_id},'Plate provider changed native menu')
 return text,code
end
local plate
for _,b in ipairs(df.global.world.buildings.other.TRAP)do
 if b.trap_type==1 then
  local d=dfhack.maps.getTileFlags(b.centerx,b.centery,b.z)
  result.candidates[#result.candidates+1]={id=b.id,complete=b:getBuildStage()==b:getMaxBuildStage(),hidden=not d or d.hidden}
  if not plate and d and not d.hidden and b:getBuildStage()==b:getMaxBuildStage() and #b.jobs==0 then plate=b end
 end
end
local original_type
if not plate then
 plate=assert(df.building.find(61));assert(df.building_trapst:is_instance(plate) and #plate.jobs==0)
 original_type=plate.trap_type;plate.trap_type=1
 result.fixture='Paused existing trap61 with subtype temporarily changed to PressurePlate; no simulation ticks. Not a native construction-default reference.'
end
result.building_id=plate.id
local function persist()
 local f=assert(io.open(out..'/pressure-plate-native.json','w'));f:write(json.encode(result));f:close()
end
local function sample(label)
 local p=plate.plate_info
 local row={label=label,open=sheet.open,active_id=sheet.active_id,tab=sheet.active_sub_tab,linking=sheet.linking_lever,warning=sheet.need_accessible_mechanism_warning,flags=p.flags.whole,unit_min=p.unit_min,unit_max=p.unit_max,water_min=p.water_min,water_max=p.water_max,magma_min=p.magma_min,magma_max=p.magma_max,track_min=p.track_min,track_max=p.track_max,jobs=#plate.jobs,lines={}}
 for y=0,g.dimy-1 do
  local chars={};for x=52,112 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
  local text=dfhack.df2utf(table.concat(chars)):gsub('%s+$','');if text:find('%S')then row.lines[#row.lines+1]={y=y,text=text}end
 end
 row.job_details={}
 for _,job in ipairs(plate.jobs)do
  local j={id=job.id,type=job.job_type,flags=job.flags.whole,pos={job.pos.x,job.pos.y,job.pos.z},refs={},item_roles={},requirements=#job.job_items.elements,world_registered=job.list_link~=nil and job.list_link.item==job}
  for _,ref in ipairs(job.general_refs)do j.refs[#j.refs+1]={type=ref:getType(),building_id=ref:getBuilding() and ref:getBuilding().id or -1}end
  for _,item in ipairs(job.items)do j.item_roles[#j.item_roles+1]={id=item.item.id,role=item.role,flags=item.flags.whole,index=item.job_item_idx}end
  row.job_details[#row.job_details+1]=j
 end
 result.states[#result.states+1]=row;persist();capture('pressure-plate-'..label);return row
end
local ok,err=xpcall(function()
 if sheet.open then gui.simulateInput(view,'LEAVESCREEN')end
 view:render(dfhack.getTickCount());select_map(plate)
 assert(sheet.open and sheet.active_id==plate.id);sample('initial')
 if os.getenv('DF3D_PRESSURE_PLATE_ITEM_NAV')=='1'then
  local item=assert(plate.contained_items[0].item)
  click(772,562);assert(sheet.active_sheet==df.view_sheet_type.ITEM and sheet.active_id==item.id);sample('item-view')
  click(816,250);assert(sheet.active_sheet==df.view_sheet_type.BUILDING and sheet.active_id==plate.id);sample('item-returned')
 end
 if os.getenv('DF3D_PRESSURE_PLATE_EDITS')=='1'then
  local name=plate.name
  click(800,82);gui.simulateInput(view,'STRING_A120');gui.simulateInput(view,'SELECT');view:render(dfhack.getTickCount())
  assert(plate.name==name..'x');sample('renamed')
  click(800,82);gui.simulateInput(view,'STRING_A000');gui.simulateInput(view,'SELECT');view:render(dfhack.getTickCount())
  assert(plate.name==name);sample('name-restored')
  local item=assert(plate.contained_items[0].item)
  result.edits={name=dfhack.df2utf(name),item_id=item.id,flags={}}
  for _,control in ipairs{{'forbid',796},{'dump',820},{'hidden',868}}do
   local before=item.flags[control[1]];result.edits.flags[control[1]]=before
   click(control[2],562);assert(item.flags[control[1]]~=before);sample('item-'..control[1])
   click(control[2],562);assert(item.flags[control[1]]==before);sample('item-'..control[1]..'-restored')
  end
  click(832,82);assert(#plate.jobs==1 and plate.jobs[0].job_type==df.job_type.DestroyBuilding);sample('removing')
  assert(click_label('Cancel removal'));assert(#plate.jobs==0);sample('removal-cancelled')
 end
 if os.getenv('DF3D_PRESSURE_PLATE_CONNECTIONS')=='1'then
  result.connections={can_link=plate:canLinkToStockpile()}
  click(768,82);sample('connections-open')
  click(80,82);sample('connections-give')
  assert(click_label('Cancel'));sample('connections-give-cancel')
  click(112,82);sample('connections-take')
  assert(click_label('Cancel'));assert(click_label('Done'));sample('connections-done')
  do
   local links=assert(plate:getStockpileLinks())
   assert(#links.give_to_pile==0 and #links.take_from_pile==0)
   local pile
   for _,candidate in ipairs(df.global.world.buildings.other.STOCKPILE)do
    local d=dfhack.maps.getTileFlags(candidate.centerx,candidate.centery,candidate.z)
    if candidate.z==plate.z and d and not d.hidden then pile=candidate;break end
   end
   assert(pile);result.connections.pile_id=pile.id
   result.connections.pile_tile={x=pile.centerx,y=pile.centery,z=pile.z}
   local function has(rows,id)for _,row in ipairs(rows)do if row.id==id then return true end end;return false end
   for _,entry in ipairs{{'give',80,'give_to_pile','take_from_workshop'},{'take',112,'take_from_pile','give_to_workshop'}}do
    click(768,82);click(entry[2],82);select_map(pile)
    result.connections[entry[1]]={count=#links[entry[3]],reciprocal=has(pile.links[entry[4]],plate.id)}
    sample('connections-linked-'..entry[1])
    if #links[entry[3]]>0 then
     assert(#links[entry[3]]==1 and links[entry[3]][0].id==pile.id)
     click(360,154);assert(#links[entry[3]]==0 and not has(pile.links[entry[4]],plate.id))
     sample('connections-unlinked-'..entry[1])
    end
    assert(click_label('Done'))
   end
  end
 end
 for _,label in ipairs{'Workers','Work orders','Tasks'}do
  if click_label(label)then sample(label:gsub(' ','-'):lower())end
  if os.getenv('DF3D_PRESSURE_PLATE_PROFILE')=='1'then
   local profile=assert(plate:getWorkshopProfile())
   if label=='Workers' then
    assert(#profile.permitted_workers==0)
    click(448,154);result.worker_selector=read_worker_reference(plate,false);sample('worker-selector')
    click(80,106);assert(#profile.permitted_workers==1)
    local text,code=owned('workshop-workers-probe',tostring(plate.id));assert(code==0,text)
    result.assigned_worker=json.decode(text);assert(result.assigned_worker.assigned.id==profile.permitted_workers[0]);sample('worker-assigned')
    click(448,190);click(80,106);assert(#profile.permitted_workers==0)
    gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());sample('workers-restored')
   elseif label=='Work orders' then
    result.order_limit=profile.max_general_orders;assert(result.order_limit<99)
    click(840,478);assert(profile.max_general_orders==result.order_limit+1);sample('order-limit-plus')
    click(872,478);assert(profile.max_general_orders==result.order_limit);sample('order-limit-restored')
   end
  end
 end
 if click_label('Link')then
  sample('link')
  if provider then
   local text,code=owned('lever-mechanisms-probe',tostring(plate.id));assert(code==0,text)
   result.unavailable_provider=json.decode(text);assert(result.unavailable_provider.available==sheet.linking_lever)
  end
  gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());sample('link-cancel')
 end
 local worker
 for _,unit in ipairs(df.global.world.units.active)do if dfhack.units.isCitizen(unit)then worker=unit;break end end
 local original=assert(df.item.find(1617));result.supplies={}
 for index=1,2 do
  local created=dfhack.items.createItem(assert(worker),df.item_type.TRAPPARTS,-1,original:getMaterial(),original:getMaterialIndex())
  assert(#created==1);local item=created[1];supplies[#supplies+1]=item
  assert(dfhack.items.moveToGround(item,{x=plate.centerx,y=plate.centery,z=plate.z}))
  item.flags.forbid=false;result.supplies[#result.supplies+1]=item.id
 end
 select_map(plate);assert(click_label('Link plate'));assert(sheet.linking_lever);sample('supplied-link')
 local selected={sheet.linking_lever_mech_lever_id,sheet.linking_lever_mech_target_id}
 result.selected_mechanisms=selected
 if provider then
  local text,code=owned('lever-mechanisms-probe',tostring(plate.id));assert(code==0,text)
  result.selected_provider=json.decode(text)
  assert(result.selected_provider.lever_mechanism==selected[1] and result.selected_provider.target_mechanism==selected[2],'Plate mechanism order differs')
 end
 select_map(assert(df.building.find(16)))
 assert(#plate.jobs==1 and plate.jobs[0].job_type==df.job_type.LinkBuildingToTrigger);local native_job=sample('linked-job').job_details[1]
 g.precise_mouse_x=868;g.precise_mouse_y=154;g.mouse_x=108;g.mouse_y=12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
 assert(#plate.jobs==0,'Native Link cancellation failed')
 for _,id in ipairs(selected)do assert(not df.item.find(id).flags.in_job,'Native cancellation retained mechanism')end
 sample('job-cancelled')
 if provider then
  local target=assert(df.building.find(16))
  local args={tostring(plate.id),tostring(target.centerx),tostring(target.centery),tostring(target.z)}
  local text,code=owned('lever-target-probe',table.unpack(args));assert(code==0,text)
  result.target_provider=json.decode(text);assert(result.target_provider.target_id==target.id)
  text,code=owned('lever-link-probe',table.unpack({args[1],args[2],args[3],args[4],tostring(selected[1]),tostring(selected[2])}));assert(code==0,text)
  local actual=sample('provider-job').job_details[1]
  for _,key in ipairs{'type','flags','pos','refs','item_roles','requirements','world_registered'}do assert(json.encode(actual[key])==json.encode(native_job[key]),'Plate native/provider job differs: '..key)end
  text,code=owned('lever-link-probe',table.unpack({args[1],args[2],args[3],args[4],tostring(selected[1]),tostring(selected[2])}));assert(code~=0 and #plate.jobs==1,'Plate duplicate link accepted')
  text,code=owned('lever-pull-probe',tostring(plate.id));assert(code~=0 and #plate.jobs==1,'Pressure plate accepted Pull')
  result.provider_equal=true;result.pull_rejected=true;result.duplicate_rejected=true
  assert(dfhack.job.removeJob(plate.jobs[0]));sample('provider-cleaned')
 end
 if os.getenv('DF3D_PRESSURE_PLATE_WIRE')=='1'then
  assert(plate.id==61)
  local target=assert(df.building.find(16))
  local f=assert(io.open(out..'/pressure-plate-wire-expected.json','w'))
  f:write(json.encode{source_tile={plate.centerx,plate.centery,plate.z},source_mechanism=selected[1],target_mechanism=selected[2],target_id=target.id,x=target.centerx,y=target.centery,z=target.z});f:close()
  local menu=json.encode{sheet.open,sheet.active_id,sheet.linking_lever,sheet.linking_lever_mech_lever_id,sheet.linking_lever_mech_target_id}
  capture('workshop-wire')
  f=assert(io.open(out..'/workshop-wire-result.json'));result.wire=json.decode(f:read('*a'));f:close()
  assert(result.wire.success and #plate.jobs==1 and plate.jobs[0].id==result.wire.link_job,'Plate wire action failed')
  if result.order_limit then
   local profile=assert(plate:getWorkshopProfile())
   assert(#profile.permitted_workers==0 and profile.max_general_orders==result.order_limit,'Viewer did not restore plate profile')
  end
  if result.connections then
   local links=assert(plate:getStockpileLinks());local pile=assert(df.building.find(result.connections.pile_id))
   assert(#links.give_to_pile==0 and #links.take_from_pile==0,'Viewer retained plate stockpile links')
   for _,key in ipairs{'give_to_workshop','take_from_workshop'}do for _,b in ipairs(pile.links[key])do assert(b.id~=plate.id,'Viewer retained reciprocal plate link')end end
   result.connections.viewer_restored=true
  end
  if result.edits then
   assert(dfhack.df2utf(plate.name)==result.edits.name,'Viewer did not restore plate name')
   local item=assert(df.item.find(result.edits.item_id))
   for key,value in pairs(result.edits.flags)do assert(item.flags[key]==value,'Viewer did not restore plate item flag: '..key)end
  end
  assert(menu==json.encode{sheet.open,sheet.active_id,sheet.linking_lever,sheet.linking_lever_mech_lever_id,sheet.linking_lever_mech_target_id},'Plate wire changed native menu')
  local actual=sample('wire-job').job_details[1]
  for _,key in ipairs{'type','flags','pos','refs','item_roles','requirements','world_registered'}do assert(json.encode(actual[key])==json.encode(native_job[key]),'Plate wire/native job differs: '..key)end
  assert(dfhack.job.removeJob(plate.jobs[0]))
 end
end,debug.traceback)
if sheet.open then gui.simulateInput(view,'LEAVESCREEN')end
while #plate.jobs>0 do assert(dfhack.job.removeJob(plate.jobs[#plate.jobs-1]))end
for index=#supplies,1,-1 do assert(dfhack.items.remove(supplies[index]))end
if original_type then plate.trap_type=original_type end
assert(#plate.jobs==0,'Pressure plate discovery created jobs')
result.success=ok;result.error=not ok and tostring(err) or nil;persist();assert(ok,err)
return result
