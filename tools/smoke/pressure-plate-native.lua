-- Native screen discovery only, in the paused owned disposable clone.
local out,view,select_map,capture,click_label=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local sheet=df.global.game.main_interface.view_sheets
local result={states={},candidates={}}
local supplies={}
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
 result.states[#result.states+1]=row;persist();capture('pressure-plate-'..label)
end
local ok,err=xpcall(function()
 if sheet.open then gui.simulateInput(view,'LEAVESCREEN')end
 view:render(dfhack.getTickCount());select_map(plate)
 assert(sheet.open and sheet.active_id==plate.id);sample('initial')
 for _,label in ipairs{'Workers','Work orders','Tasks'}do
  if click_label(label)then sample(label:gsub(' ','-'):lower())end
 end
 if click_label('Link')then sample('link');gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());sample('link-cancel')end
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
 select_map(assert(df.building.find(16)))
 assert(#plate.jobs==1 and plate.jobs[0].job_type==df.job_type.LinkBuildingToTrigger);sample('linked-job')
 g.precise_mouse_x=868;g.precise_mouse_y=154;g.mouse_x=108;g.mouse_y=12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
 assert(#plate.jobs==0,'Native Link cancellation failed')
 for _,id in ipairs(selected)do assert(not df.item.find(id).flags.in_job,'Native cancellation retained mechanism')end
 sample('job-cancelled')
end,debug.traceback)
if sheet.open then gui.simulateInput(view,'LEAVESCREEN')end
while #plate.jobs>0 do assert(dfhack.job.removeJob(plate.jobs[#plate.jobs-1]))end
for index=#supplies,1,-1 do assert(dfhack.items.remove(supplies[index]))end
if original_type then plate.trap_type=original_type end
assert(#plate.jobs==0,'Pressure plate discovery created jobs')
result.success=ok;result.error=not ok and tostring(err) or nil;persist();assert(ok,err)
return result
