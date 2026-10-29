-- Owned unsaved-clone oracle. Simulation advances only through viewer pause commands.
local out,index=...
local json=require('json')
local function write(path,value)local f=assert(io.open(out..'/'..path,'w'));f:write(json.encode(value));f:close()end
assert(df.global.pause_state,'hauling observations require a paused safe point')
local function position(item)
 local text,code=dfhack.run_command_silent('df3d','item-position-probe',string.format('%d',item.id))
 assert(code==0,text);return json.decode(text)
end
local function observe(item,unit)
 local p=position(item)
 local carried=false
 for _,held in ipairs(unit.inventory)do if held.item.id==item.id and held.mode==df.inv_item_role_type.Hauled then carried=true end end
 return {item_id=item.id,unit_id=unit.id,position=p,frame=df.global.world.frame_counter,
  item_type=df.item_type[item:getType()],stored_position={x=item.pos.x,y=item.pos.y,z=item.pos.z},
  carried_by_selected_unit=carried,on_ground=item.flags.on_ground,
  unit_position={x=unit.pos.x,y=unit.pos.y,z=unit.pos.z},in_inventory=item.flags.in_inventory,
  job_id=unit.job.current_job and unit.job.current_job.id or -1,
  job_type=unit.job.current_job and df.job_type[unit.job.current_job.job_type] or ''}
end
if not index then
 df.global.d_init.feature.autosave=df.d_init_autosave.NONE
 local candidates={}
 for _,unit in ipairs(df.global.world.units.active)do
  local job=unit.job.current_job
  if job and job.job_type==df.job_type.StoreItemInStockpile then
   for _,held in ipairs(unit.inventory)do
    if held.mode==df.inv_item_role_type.Hauled then
     local row=observe(held.item,unit)
     row.destination={x=job.pos.x,y=job.pos.y,z=job.pos.z}
     if row.position.valid then candidates[#candidates+1]=row end
    end
   end
  end
 end
 table.sort(candidates,function(a,b)return a.item_id<b.item_id end)
 _G.df3d_item_hauling={candidates=candidates,frame=df.global.world.frame_counter}
 write('fixture.json',{candidates=candidates,frame=df.global.world.frame_counter})
 print('FIXTURE_READY');return
end
local input=assert(io.open(out..'/request-'..index..'.json'));local request=json.decode(input:read('*a'));input:close()
local fixture=assert(_G.df3d_item_hauling)
local selected
for _,candidate in ipairs(fixture.candidates)do if candidate.item_id==request.item_id then selected=candidate;break end end
assert(selected,'unknown hauling target')
local item=assert(df.item.find(selected.item_id));local unit=assert(df.unit.find(selected.unit_id))
local result={status='passed',observation=observe(item,unit)}
local plot=df.global.plotinfo;local sheet=df.global.game.main_interface.view_sheets
local ui=json.encode({follow_item=plot.follow_item,follow_unit=plot.follow_unit,
 x=df.global.window_x,y=df.global.window_y,z=df.global.window_z,
 sheet_open=sheet.open,sheet_type=sheet.active_sheet,sheet_id=sheet.active_id})
if request.op=='verify' then
 local pos=result.observation.position
 assert(pos.valid and pos.x==request.x and pos.y==request.y and pos.z==request.z,'follow differs from paused native effective position')
 assert(fixture.ui==ui,'follow observation changed native camera or sheet state')
 assert(fixture.sample_frame==df.global.world.frame_counter,'position comparison advanced simulation')
 result.ui_unchanged=true
elseif request.op=='sample' then fixture.ui=ui;fixture.sample_frame=df.global.world.frame_counter
else error('unknown hauling request')end
write('response-'..index..'.json',result)
print('SEMANTIC_PASS hauling '..request.op)
