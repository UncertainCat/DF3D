-- Native action discovery in a paused, owned disposable clone only.
local out,view,select_map,capture,click_label=...
local gui=require('gui');local json=require('json')
local lever=assert(df.building.find(55));assert(df.building_trapst:is_instance(lever) and lever.trap_type==0)
assert(#lever.jobs==0 and df.global.pause_state)
local sheet=df.global.game.main_interface.view_sheets
local result={building_id=lever.id,frame=df.global.world.frame_counter,states={}}
local function persist()
 local f=assert(io.open(out..'/lever-native.json','w'));f:write(json.encode(result));f:close()
end
local function sample(label)
 local row={label=label,open=sheet.open,active_id=sheet.active_id,tab=sheet.active_sub_tab,linking=sheet.linking_lever,jobs={}}
 for _,job in ipairs(lever.jobs)do
  local refs={};for _,ref in ipairs(job.general_refs)do refs[#refs+1]={type=ref:getType(),building_id=ref:getBuilding() and ref:getBuilding().id or -1}end
  row.jobs[#row.jobs+1]={id=job.id,type=job.job_type,flags=job.flags.whole,pos={job.pos.x,job.pos.y,job.pos.z},refs=refs,items=#job.items,requirements=#job.job_items.elements,world_registered=job.list_link~=nil and job.list_link.item==job}
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
 assert(#lever.jobs==0 and df.global.world.frame_counter==result.frame)
end,debug.traceback)
while #lever.jobs>0 do assert(dfhack.job.removeJob(lever.jobs[#lever.jobs-1]))end
result.success=ok;result.error=ok and '' or tostring(err);persist();assert(ok,err)
