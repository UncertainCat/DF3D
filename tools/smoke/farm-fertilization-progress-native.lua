-- Disposable owned-clone discovery. Supplies are controlled; DF executes jobs.
local out,view,records,farm=...
local script=require('gui.script')
local action_marker=io.open(out..'/farm-item-action')
local action
if action_marker then action=action_marker:read('*a'):match('%S+');action_marker:close();assert(action=='forbid' or action=='dump')end
local progress_marker=io.open(out..'/farm-item-action-progress')
local action_progress=progress_marker~=nil
if progress_marker then progress_marker:close();assert(action)end
local transfer_marker=io.open(out..'/farm-item-transfer')
local transfer=transfer_marker~=nil
if transfer_marker then transfer_marker:close();assert(action_progress and action=='forbid')end
local capture_final
local original_job_id
local retired_at
assert(df.global.pause_state and #farm.jobs==0)
df.global.d_init.feature.autosave=df.d_init_autosave.NONE
local worker
for _,unit in ipairs(df.global.world.units.active)do
 if dfhack.units.isCitizen(unit) and not unit.job.current_job then worker=unit;break end
end
assert(worker,'no idle citizen for disposable potash creation')
local created=dfhack.items.createItem(worker,df.item_type.BAR,-1,df.builtin_mats.POTASH,-1)
assert(#created==1,'potash fixture creation failed')
local potash=created[1];local potash_id=potash.id
assert(dfhack.items.moveToGround(potash,{x=farm.centerx,y=farm.centery,z=farm.z}))
potash.flags.forbid=false
worker.status.labors[df.unit_labor.PLANT]=true
local initial=farm.current_fertilization
local row={name='farm-fertilization-progress',farm_id=farm.id,potash_id=potash_id,
 initial=initial,maximum=farm.max_fertilization,fixture_supplies=true,fixture_worker_id=worker.id,
 samples={},contents_types={}}
records[#records+1]=row
local text,code=dfhack.run_command_silent('df3d','farm-fertilize',tostring(farm.id),'toggle')
assert(code==0,text)
assert(#farm.jobs>0,'native scheduler created no fertilizer jobs')
local start=df.global.world.frame_counter
-- Allow bounded slow native startup before delivery.
local deadline=dfhack.getTickCount()+180000
local last_signature
local function inspect_delivered_item(item)
 df.global.pause_state=true
 local gui=require('gui');local g=df.global.gps;local sheet=df.global.game.main_interface.view_sheets
 local function click(x,y)
  g.mouse_x=x//8;g.mouse_y=(y-4)//12;g.precise_mouse_x=x;g.precise_mouse_y=y
  gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 end
 df.global.game.main_interface.bottom_mode_selected=-1
 dfhack.gui.revealInDwarfmodeMap({x=farm.centerx,y=farm.centery,z=farm.z},true)
 view:render(dfhack.getTickCount())
 local found=false
 for y=0,g.dimy-1 do for x=0,g.dimx-1 do
  g.mouse_x=x;g.mouse_y=y;g.precise_mouse_x=x*8+4;g.precise_mouse_y=y*12+6
  local p=dfhack.gui.getMousePos(true)
  if p and p.x==farm.centerx and p.y==farm.centery and p.z==farm.z then
   gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount());found=true;break
  end
 end if found then break end end
 assert(found and sheet.active_sheet==df.view_sheet_type.BUILDING and sheet.active_id==farm.id,'delivered farm not selected')
 local function capture(name,keep_pointer)
  if not keep_pointer then g.mouse_x=0;g.mouse_y=0;g.precise_mouse_x=0;g.precise_mouse_y=0 end
  for i=1,5 do view:render(dfhack.getTickCount());script.sleep(1,'frames')end
  local shot={name=name,item_id=potash_id,building_id=farm.id,frame=df.global.world.frame_counter,lines={}}
  for y=0,g.dimy-1 do
   local line={}
   for x=0,g.dimx-1 do local ch=dfhack.screen.readTile(x,y).ch;line[#line+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
   shot.lines[#shot.lines+1]=dfhack.df2utf(table.concat(line)):gsub('%s+$','')
  end
  records[#records+1]=shot
  local f=assert(io.open(out..'/shot','w'));f:write(name);f:close()
  local limit=dfhack.getTickCount()+30000
  while true do local ack=io.open(out..'/ack-'..name);if ack then ack:close();break end
   assert(dfhack.getTickCount()<limit,'potash capture timeout');script.sleep(1,'frames')end
  return shot
 end
 capture_final=capture
 local contents=capture('farm-delivered-potash-contents')
 local text,code=dfhack.run_command_silent('df3d','farm-contents-read',tostring(farm.id))
 assert(code==0,text);contents.semantic=require('json').decode(text)
 -- This one-row native panel has no scrollbar, so View is at772 (not756).
 click(772,526)
 assert(sheet.open and sheet.active_sheet==df.view_sheet_type.ITEM and sheet.active_id==item.id,'native potash View failed')
 local native=capture('farm-delivered-potash-item')
 native.description=dfhack.df2utf(sheet.raw_description);native.description_width=sheet.description_width
 local header,header_code=dfhack.run_command_silent('df3d','farm-item-header-read',tostring(farm.id),tostring(item.id))
 assert(header_code==0,header);native.header=require('json').decode(header)
 local guards={}
 for _,object in ipairs{item,farm,sheet,df.global.plotinfo,df.global.world.raws.interactions.all}do
  local size,address=df.sizeof(object);local bytes=df.new('uint8_t',size)
  dfhack.internal.memmove(bytes,address,size);guards[#guards+1]={bytes=bytes,address=address,size=size}
 end
 local description,description_code=dfhack.run_command_silent('df3d','farm-item-description-probe',tostring(farm.id),tostring(item.id))
 assert(description_code==0,description)
 native.description_provider=require('json').decode(description)
 assert(native.description_provider.description==native.description,'owned potash description differs from native')
 for _,guard in ipairs(guards)do
  assert(dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)==0,'potash description changed guarded item/farm/UI/raws')
  df.delete(guard.bytes)
 end
 native.description_provider_accepted=true;native.description_guards_unchanged=true
 local hover_deadline=dfhack.getTickCount()+3000
 repeat
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
  g.mouse_x=756//8;g.mouse_y=(76-4)//12;g.precise_mouse_x=756;g.precise_mouse_y=76
  gui.simulateInput(view,{});view:render(dfhack.getTickCount());script.sleep(1,'frames')
 until dfhack.getTickCount()>=hover_deadline
 local hover=capture('farm-potash-item-task-hover',true)
 hover.hover=df.global.game.main_interface.current_hover
 hover.enabled=df.global.game.main_interface.hover_instructions_on
 click(756,76)
 local clicked=capture('farm-potash-item-task-click')
 clicked.sheet=df.view_sheet_type[sheet.active_sheet];clicked.active_id=sheet.active_id;clicked.open=sheet.open
 if action then
  local action_frame=df.global.world.frame_counter
  local function action_state(label)
   local captured=capture('farm-potash-'..action..'-'..label)
   captured.item_flags=item.flags.whole;captured.forbid=item.flags.forbid;captured.dump=item.flags.dump
   captured.in_job=item.flags.in_job;captured.in_building=item.flags.in_building
   captured.sheet={open=sheet.open,type=df.view_sheet_type[sheet.active_sheet],id=sheet.active_id}
   captured.contents={};captured.jobs={};captured.refs={}
   for _,held in ipairs(farm.contained_items)do captured.contents[#captured.contents+1]={id=held.item.id,role=held.use_mode}end
   for _,job in ipairs(farm.jobs)do
    local unit=dfhack.job.getWorker(job);local ids={}
    for _,ref in ipairs(job.items)do if ref.item then ids[#ids+1]=ref.item.id end end
    captured.jobs[#captured.jobs+1]={id=job.id,worker=unit and unit.id or -1,items=ids}
   end
   for _,ref in ipairs(item.general_refs)do captured.refs[#captured.refs+1]=df.general_ref_type[ref:getType()]end
   assert(df.global.pause_state and df.global.world.frame_counter==action_frame,'item action advanced simulation')
  end
  for _,job in ipairs(farm.jobs)do for _,ref in ipairs(job.items)do
   if ref.item==item then original_job_id=job.id end
  end end
  assert(original_job_id,'no assigned potash job before native action')
  row.original_job_id=original_job_id
  action_state('before')
  for _,label in ipairs{'enabled','disabled'}do
   if not sheet.open or sheet.active_sheet~=df.view_sheet_type.ITEM or sheet.active_id~=item.id then break end
   click(action=='forbid' and 804 or 828,76);action_state(label)
  end
  row.delivered_item_inspected=true
  if not action_progress then row.action_only=action;return end
  row.action_progress=action
  df.global.pause_state=false;deadline=dfhack.getTickCount()+60000;return
 end
 -- Keep the native item sheet open while DF consumes its target.
 assert(sheet.open and sheet.active_sheet==df.view_sheet_type.ITEM and sheet.active_id==item.id)
 row.delivered_item_inspected=true
 df.global.pause_state=false
 deadline=dfhack.getTickCount()+60000
end
local ok,why=pcall(function()
 df.global.pause_state=false
 while dfhack.getTickCount()<deadline and df.global.world.frame_counter-start<10000 do
  local item=df.item.find(potash_id)
  local sample={frame=df.global.world.frame_counter,current=farm.current_fertilization,
   contents={},jobs={},potash_present=item~=nil,potash_removed=item and item.flags.removed or false}
  local sheet=df.global.game.main_interface.view_sheets
  sample.sheet={open=sheet.open,type=df.view_sheet_type[sheet.active_sheet],id=sheet.active_id}
  for _,held in ipairs(farm.contained_items)do
   sample.contents[#sample.contents+1]={id=held.item.id,type=df.item_type[held.item:getType()],role=held.use_mode}
   row.contents_types[df.item_type[held.item:getType()]]=true
  end
  for _,job in ipairs(farm.jobs)do
   local entry={id=job.id,type=df.job_type[job.job_type],items={}}
   local unit=dfhack.job.getWorker(job);entry.worker=unit and unit.id or -1
   for _,ref in ipairs(job.items)do if ref.item then entry.items[#entry.items+1]=ref.item.id end end
   sample.jobs[#sample.jobs+1]=entry
  end
  if item then
   sample.item={forbid=item.flags.forbid,dump=item.flags.dump,in_job=item.flags.in_job,
    on_ground=item.flags.on_ground,in_building=item.flags.in_building,refs={}}
   for _,ref in ipairs(item.general_refs)do sample.item.refs[#sample.item.refs+1]=df.general_ref_type[ref:getType()]end
  end
  local original_alive=false
  if original_job_id then
   local link=df.global.world.jobs.list.next
   while link do if link.item and link.item.id==original_job_id then original_alive=true;break end;link=link.next end
   sample.original_job_alive=original_alive
  end
  local signature=require('json').encode{sample.current,sample.contents,sample.jobs,sample.potash_present,sample.potash_removed,sample.sheet,sample.item,sample.original_job_alive}
  if signature~=last_signature then row.samples[#row.samples+1]=sample;last_signature=signature end
  if not row.delivered_item_inspected then
   for _,held in ipairs(farm.contained_items)do if held.item.id==potash_id then inspect_delivered_item(held.item);break end end
  end
  if row.action_only then break end
  if row.action_progress then
   if sample.original_job_alive==false and not retired_at then retired_at=df.global.world.frame_counter end
   if retired_at and df.global.world.frame_counter-retired_at>=600 then row.progress_observed=true;break end
  elseif farm.current_fertilization>initial then row.completed=true;break end
  script.sleep(1,'frames')
 end
end)
row.observation_pause_state=df.global.pause_state
df.global.pause_state=true
row.final=farm.current_fertilization;row.elapsed_ticks=df.global.world.frame_counter-start
assert(ok,why)
if row.action_only then assert(row.delivered_item_inspected);return end
if row.action_progress then
 assert(row.progress_observed,'original job did not retire with 600 later ticks inside observation bound')
 row.original_job_retired_at=retired_at
 row.followup_ticks=df.global.world.frame_counter-retired_at
 local final=capture_final('farm-potash-'..action..'-progress-final')
 local sheet=df.global.game.main_interface.view_sheets
 final.sheet={open=sheet.open,type=df.view_sheet_type[sheet.active_sheet],id=sheet.active_id}
 final.potash_present=df.item.find(potash_id)~=nil
 final.fertilization=farm.current_fertilization
 if transfer then
  local item=assert(df.item.find(potash_id));assert(not item.flags.in_job)
  local destination
  for _,unit in ipairs(df.global.world.units.active)do
   if dfhack.units.isCitizen(unit) and unit.pos.z==farm.z and
    (unit.pos.x<farm.x1 or unit.pos.x>farm.x2 or unit.pos.y<farm.y1 or unit.pos.y>farm.y2)then
    local designation=dfhack.maps.getTileFlags(unit.pos)
    if designation and not designation.hidden then destination={x=unit.pos.x,y=unit.pos.y,z=unit.pos.z};break end
   end
  end
  assert(destination,'no visible occupied tile outside farm for controlled transfer')
  assert(dfhack.items.moveToGround(item,destination),'controlled transfer failed')
  for _,held in ipairs(farm.contained_items)do assert(held.item.id~=potash_id,'transfer retained farm contents membership')end
  local gui=require('gui');local gps=df.global.gps;local frame=df.global.world.frame_counter
  local function observe(label)
   local captured=capture_final('farm-potash-transfer-'..label)
   captured.controlled_transfer=true;captured.destination=destination
   captured.sheet={open=sheet.open,type=df.view_sheet_type[sheet.active_sheet],id=sheet.active_id}
   captured.item={id=item.id,hidden=item.flags.hidden,forbid=item.flags.forbid,dump=item.flags.dump,
    in_job=item.flags.in_job,on_ground=item.flags.on_ground,position={x=item.pos.x,y=item.pos.y,z=item.pos.z},refs={}}
   for _,ref in ipairs(item.general_refs)do captured.item.refs[#captured.item.refs+1]=df.general_ref_type[ref:getType()]end
   captured.description=dfhack.df2utf(sheet.raw_description)
   local _,code=dfhack.run_command_silent('df3d','farm-item-description-probe',tostring(farm.id),tostring(potash_id))
   captured.farm_bound_provider_rejected=code~=0
   local text,position_code=dfhack.run_command_silent('df3d','item-position-probe',tostring(potash_id));assert(position_code==0,text)
   captured.position_provider=require('json').decode(text)
   assert(sheet.open and sheet.active_sheet==df.view_sheet_type.ITEM and sheet.active_id==potash_id,'native lost transferred item sheet')
   assert(df.global.pause_state and df.global.world.frame_counter==frame,'controlled transfer observation advanced simulation')
   return captured
  end
  observe('ground')
  for _,hidden in ipairs{true,false}do
   gps.mouse_x=876//8;gps.mouse_y=(76-4)//12;gps.precise_mouse_x=876;gps.precise_mouse_y=76
   gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
   assert(item.flags.hidden==hidden,'native transferred-item visibility click failed')
   observe(hidden and 'hidden' or 'visible')
  end
  local has_stockpile_link=false
  for _,line in ipairs(records[#records].lines)do if line:find('View stockpile',1,true)then has_stockpile_link=true end end
  if has_stockpile_link then
   gps.mouse_x=816//8;gps.mouse_y=(250-4)//12;gps.precise_mouse_x=816;gps.precise_mouse_y=250
   gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
   local linked=capture_final('farm-potash-transfer-stockpile-link')
   local selected=assert(df.global.game.main_interface.stockpile.cur_bld,'stockpile View selected no stockpile')
   assert(not sheet.open and selected:getType()==df.building_type.Stockpile,'stockpile View did not leave the item sheet for stockpile controls')
   linked.sheet={open=sheet.open,type=df.view_sheet_type[sheet.active_sheet],id=sheet.active_id}
   linked.stockpile_id=selected.id;linked.stockpile_number=selected.stockpile_number
   linked.bottom_mode_selected=df.global.game.main_interface.bottom_mode_selected
  end
 end
 return
end
assert(row.completed,'fertilizer job did not complete within the observation bound')
assert(row.delivered_item_inspected,'delivered potash never reached farm contents')
local reserved=false
for _,sample in ipairs(row.samples)do for _,job in ipairs(sample.jobs)do
 for _,id in ipairs(job.items)do if id==potash_id and job.worker>=0 then reserved=true end end
end end
assert(reserved,'DF never assigned a worker with the supplied potash')
assert(not df.item.find(potash_id),'completed fertilizer job retained supplied potash')
row.reservation_observed=true;row.supplied_potash_consumed=true
for i=1,15 do view:render(dfhack.getTickCount());script.sleep(1,'frames')end
local sheet=df.global.game.main_interface.view_sheets
assert(not sheet.open,'native item sheet remained open after consumption and redraw')
records[#records+1]={name='farm-consumed-potash-item',frame=df.global.world.frame_counter,
 item_id=potash_id,sheet={open=sheet.open,type=df.view_sheet_type[sheet.active_sheet],id=sheet.active_id}}
local f=assert(io.open(out..'/shot','w'));f:write('farm-consumed-potash-item');f:close()
local limit=dfhack.getTickCount()+30000
while true do local ack=io.open(out..'/ack-farm-consumed-potash-item');if ack then ack:close();break end
 assert(dfhack.getTickCount()<limit,'consumed item capture timeout');script.sleep(1,'frames')end
