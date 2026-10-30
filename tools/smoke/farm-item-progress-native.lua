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
if request.op=='sample' then
 if contained then
  local text,code=dfhack.run_command_silent('df3d','farm-item-description-probe',tostring(farm.id),tostring(item.id));assert(code==0,text)
  fixture.expected=json.decode(text);fixture.frame=df.global.world.frame_counter;fixture.ui=ui
 end
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
else error('unknown progress request')end
write('response-'..index..'.json',result);print('SEMANTIC_PASS farm-item-progress '..request.op)
