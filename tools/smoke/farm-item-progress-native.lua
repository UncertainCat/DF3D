-- Controlled supplies in an owned disposable clone; DF assigns and runs jobs.
local out,index=...
local json=require('json')
local function write(name,value)local f=assert(io.open(out..'/'..name,'w'));f:write(json.encode(value));f:close()end
assert(df.global.pause_state)
if not index then
 df.global.d_init.feature.autosave=df.d_init_autosave.NONE
 local farm=assert(df.global.world.buildings.other.FARM_PLOT[0]);assert(#farm.jobs==0)
 local worker
 for _,unit in ipairs(df.global.world.units.active)do if dfhack.units.isCitizen(unit) and not unit.job.current_job then worker=unit;break end end
 assert(worker,'no fixture worker')
 local items=dfhack.items.createItem(worker,df.item_type.BAR,-1,df.builtin_mats.POTASH,-1);assert(#items==1)
 local item=items[1];assert(dfhack.items.moveToGround(item,{x=farm.centerx,y=farm.centery,z=farm.z}))
 item.flags.forbid=false;worker.status.labors[df.unit_labor.PLANT]=true
 local text,code=dfhack.run_command_silent('df3d','farm-fertilize',tostring(farm.id),'toggle');assert(code==0,text)
 local fixture={building_id=farm.id,item_id=item.id,initial=farm.current_fertilization,frame=df.global.world.frame_counter}
 local marker=io.open(out..'/farm-item-action');if marker then fixture.action=marker:read('*a'):match('%S+');marker:close()end
 local progress=io.open(out..'/farm-item-action-progress');if progress then fixture.action_progress=true;progress:close();assert(fixture.action)end
 _G.df3d_farm_item_progress=fixture;write('fixture.json',fixture);print('FIXTURE_READY');return
end
local fixture=assert(_G.df3d_farm_item_progress)
local f=assert(io.open(out..'/request-'..index..'.json'));local request=json.decode(f:read('*a'));f:close()
local farm=assert(df.building.find(fixture.building_id));local item=df.item.find(fixture.item_id)
local contained=false
for _,held in ipairs(farm.contained_items)do if held.item.id==fixture.item_id then contained=true end end
local sheet=df.global.game.main_interface.view_sheets;local plot=df.global.plotinfo
local ui=json.encode{sheet.open,sheet.active_sheet,sheet.active_id,plot.follow_item,plot.follow_unit,df.global.window_x,df.global.window_y,df.global.window_z}
local result={status='passed',frame=df.global.world.frame_counter,present=item~=nil,contained=contained,
 current=farm.current_fertilization,job_count=#farm.jobs}
if fixture.assignment then
 local original_alive=false;local link=df.global.world.jobs.list.next
 while link do if link.item and link.item.id==fixture.assignment.job_id then original_alive=true;break end;link=link.next end
 result.original_job_alive=original_alive
end
if item then result.in_job=item.flags.in_job;result.forbid=item.flags.forbid;result.dump=item.flags.dump end
if request.op=='sample' then
 if contained then
  local text,code=dfhack.run_command_silent('df3d','farm-item-description-probe',tostring(farm.id),tostring(item.id));assert(code==0,text)
  fixture.expected=json.decode(text);fixture.frame=df.global.world.frame_counter;fixture.ui=ui
  if not fixture.assignment then
   for _,job in ipairs(farm.jobs)do for _,ref in ipairs(job.items)do if ref.item==item then
    fixture.assignment={job_id=job.id,worker_id=assert(dfhack.job.getWorker(job)).id}
   end end end
  end
 end
elseif request.op=='independent_transfer' then
 assert(item and not item.flags.in_job,'transfer requires unreserved potash')
 local destination
 for _,pile in ipairs(df.global.world.buildings.other.STOCKPILE)do
  if pile.z==farm.z then
   for y=pile.y1,pile.y2 do for x=pile.x1,pile.x2 do
    if (x<farm.x1 or x>farm.x2 or y<farm.y1 or y>farm.y2) and dfhack.buildings.containsTile(pile,x,y)then
     local designation=dfhack.maps.getTileFlags(x,y,pile.z)
     if designation and not designation.hidden then destination={x=x,y=y,z=pile.z};break end
    end
   end if destination then break end end
  end
  if destination then break end
 end
 assert(destination and dfhack.items.moveToGround(item,destination),'controlled transfer failed')
 for _,held in ipairs(farm.contained_items)do assert(held.item.id~=item.id,'transfer retained farm membership')end
 fixture.frame=df.global.world.frame_counter;fixture.ui=ui;result.destination=destination;result.controlled_transfer=true
elseif request.op=='independent_verify' then
 assert(item and fixture.frame==df.global.world.frame_counter and fixture.ui==ui,'independent request changed frame/native UI')
 local text,code=dfhack.run_command_silent('df3d','item-inspect-probe',tostring(item.id));assert(code==0,text)
 local expected=json.decode(text).snapshot;local actual=request.snapshot
 assert(actual.id==item.id and request.revision_text==expected.revision,'independent identity/revision differs')
 assert(actual.name==expected.caption and actual.weight==expected.weight and actual.description==expected.description,'independent native text differs')
 for _,field in ipairs{'forbid','dump','melt','hidden','can_dump','can_melt','item_type','material_token'}do assert(actual[field]==expected[field],field..' differs')end
 assert(actual.in_job==item.flags.in_job and actual.in_building==item.flags.in_building,'independent job/building flags differ')
 for _,field in ipairs{'holder','stockpile'}do
  local e=expected[field];local a=actual[field]
  if e and e~=json.null then assert(a and a.id==e.id and a.type==e.type and a.name==e.name,'independent '..field..' differs')
  else assert(not a or a==json.null,'invented independent '..field)end
 end
 result.snapshot=expected;result.ui_unchanged=true
elseif request.op=='verify' then
 assert(contained and fixture.expected,'potash target disappeared while paused')
 assert(fixture.frame==df.global.world.frame_counter and fixture.ui==ui,'inspection changed frame/native UI')
 local expected=fixture.expected;local actual=request.snapshot
 assert(actual.id==item.id and actual.building_id==farm.id and actual.item_type==0 and actual.material_token=='POTASH')
 assert(actual.name==expected.caption and actual.description==expected.description and actual.weight==expected.weight,'wire text differs')
 assert(request.revision_text==expected.contents_revision,'wire revision differs')
 assert(actual.in_job==item.flags.in_job and actual.in_building==item.flags.in_building and actual.hidden==item.flags.hidden,'wire flags differ')
 assert(actual.holder.id==farm.id and actual.holder.type==4 and actual.holder.name==expected.holder.name,'wire holder differs')
 result.inspection_equal=true;result.ui_unchanged=true
elseif request.op=='flags' then
 assert(contained and item.flags.hidden==request.hidden and item.flags.in_job,'visibility edit changed job participation')
 local reserved=false
 for _,job in ipairs(farm.jobs)do for _,ref in ipairs(job.items)do if ref.item==item and dfhack.job.getWorker(job)then reserved=true end end end
 assert(reserved,'visibility edit lost assigned fertilizer job');result.hidden=item.flags.hidden;result.reservation_preserved=true
elseif request.op=='item_action' then
 assert(fixture.action=='forbid' or fixture.action=='dump')
 assert(contained and item.flags[fixture.action]==request.value,'action flag differs')
 assert(fixture.frame==df.global.world.frame_counter and fixture.ui==ui,'item action changed frame/native UI')
 local assignment=assert(fixture.assignment);local job
 for _,candidate in ipairs(farm.jobs)do if candidate.id==assignment.job_id then job=candidate;break end end
 assert(job,'native retains the original farm job immediately after this action')
 local worker=assert(dfhack.job.getWorker(job));assert(worker.id==assignment.worker_id and worker.job.current_job==job,'assigned worker changed')
 local retained=fixture.action=='dump'
 assert(item.flags.in_job==retained and #job.items==(retained and 1 or 0),'native reservation cleanup differs')
 if retained then assert(job.items[0].item==item)end
 local job_refs=0;for _,ref in ipairs(item.specific_refs)do if ref.type==df.specific_ref_type.JOB then job_refs=job_refs+1 end end
 assert(job_refs==(retained and 1 or 0),'item job reference cleanup differs')
 result.action=fixture.action;result.value=item.flags[fixture.action];result.in_job=item.flags.in_job
 result.job_id=job.id;result.worker_id=worker.id;result.job_items=#job.items;result.job_refs=job_refs;result.ui_unchanged=true
else error('unknown progress request')end
write('response-'..index..'.json',result);print('SEMANTIC_PASS farm-item-progress '..request.op)
