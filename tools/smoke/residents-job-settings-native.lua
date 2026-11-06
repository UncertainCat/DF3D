-- Native oracle only. No runtime provider may read this menu/widget state.
local out,view,info=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local button,owner,scroller,row_index
local controlled,prior_job,controlled_unit,provider
local function find(widget,unit,scroll,index)
 if (widget.flag.whole&1)==0 or button then return end
 if df.widget_job_details_button:is_instance(widget) and widget.jb then
  button=widget;owner=unit;scroller=scroll;row_index=index;return
 end
 if not df.widget_container:is_instance(widget) then return end
 local children=dfhack.gui.getWidgetChildren(widget)
 for _,child in ipairs(children)do if df.widget_unit_name:is_instance(child) then unit=child.u;break end end
 for i,child in ipairs(children)do
  if df.widget_scroll_rows:is_instance(widget) then find(child,unit,widget,i-1)
  else find(child,unit,scroll,index)end
 end
end
find(info.creatures)
if not button then
 -- The paused reference fortress has no natural editable resident task.
 -- Give a visible resident an unstarted, unlinked rock-door job for the
 -- diagnostic only. The simulation stays paused and the pointer is restored.
 local function resident(widget)
  if controlled_unit or (widget.flag.whole&3)~=3 then return end
  if df.widget_unit_name:is_instance(widget) and widget.u then controlled_unit=widget.u;return end
  if df.widget_container:is_instance(widget)then for _,child in ipairs(dfhack.gui.getWidgetChildren(widget))do resident(child)end end
 end
 resident(info.creatures);assert(controlled_unit,'No visible resident for job-settings fixture')
 local building
 for _,b in ipairs(df.global.world.buildings.other.WORKSHOP_ANY)do
  if b:getBuildStage()==b:getMaxBuildStage() then building=b;break end
 end
 assert(building,'No completed workshop for job-settings fixture')
 controlled=df.job:new();controlled.id=2000000000;controlled.job_type=df.job_type.ConstructDoor
 controlled.completion_timer=-1;controlled.mat_type=0;controlled.mat_index=-1
 local holder=df.general_ref_building_holderst:new();holder.building_id=building.id;controlled.general_refs:insert('#',holder)
 local input=df.job_item:new();input.item_type=df.item_type.BOULDER;input.mat_type=0;input.mat_index=-1;input.quantity=1
 controlled.job_items.elements:insert('#',input)
 prior_job=controlled_unit.job.current_job;controlled_unit.job.current_job=controlled
 gui.simulateInput(view,'LEAVESCREEN');gui.simulateInput(view,'D_UNITLIST')
 for _=1,3 do script.sleep(1,'frames')end
 find(info.creatures)
 -- Restore the simulation record now; the native button retains its captured
 -- job pointer. Keep the unlinked diagnostic job alive until the lane exits.
 controlled_unit.job.current_job=prior_job
end
assert(button and owner,'No natural Residents job-settings button; a controlled job fixture is needed')
if os.getenv('DF3D_RESIDENTS_JOB_SETTINGS_PROVIDER')=='1' then
 local menu=df.global.game.main_interface.job_details
 local function menu_state()
  local _,at=df.sizeof(menu.material)
  return {open=menu.open,context=menu.context,option=menu.current_option,index=menu.current_option_index,
   material_size=#menu.material,material_storage=tostring(df.reinterpret_cast('uint64_t',at).value)}
 end
 local before=json.encode(menu_state())
 local original=owner.job.current_job;owner.job.current_job=button.jb
 local ok,text,rc=pcall(dfhack.run_command_silent,'df3d','residents-job-settings-probe',tostring(owner.id))
 owner.job.current_job=original
 assert(ok and rc==0,'Owned job settings read failed: '..tostring(text));provider=json.decode(text)
 assert(json.encode(menu_state())==before,'Owned job settings changed native menu storage')
end
-- Position the native diagnostic viewport, then click the real visible button.
-- This is fixture setup, not a claim about wheel/scrollbar input acceptance.
local previous_scroll=scroller and scroller.scroll
if scroller then scroller.scroll=row_index end
for _=1,3 do script.sleep(1,'frames')end
view:render(dfhack.getTickCount())
assert((button.flag.whole&2)~=0,'Job-settings button did not become visible')
local job=button.jb
local evidence={unit_id=owner.id,job_id=job.id,job_type=job.job_type,button_context=button.context,
 button={button.rect.x1,button.rect.y1,button.rect.x2,button.rect.y2},options={}}
evidence.controlled_job=controlled~=nil
local g=df.global.gps
local x=button.rect.x1+1;local y=button.rect.y1+1
g.precise_mouse_x=x*8+4;g.precise_mouse_y=y*12+6;g.mouse_x=x;g.mouse_y=y
df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
gui.simulateInput(view,'_MOUSE_L')
df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
for _=1,3 do script.sleep(1,'frames')end
local details=df.global.game.main_interface.job_details
assert(details.open and details.jb==job and not details.wq,'Residents did not open job-backed Details')
evidence.context=details.context;evidence.current_option=details.current_option;evidence.current_option_index=details.current_option_index
evidence.building_id=details.bld and details.bld.id or -1
evidence.search={details.search.x,details.search.y,details.search.z}
for i,kind in ipairs(details.option)do evidence.options[#evidence.options+1]={kind=kind,index=details.option_index[i]}end
evidence.materials={}
for i,kind in ipairs(details.material)do evidence.materials[#evidence.materials+1]={type=kind,index=details.matgloss[i],count=details.material_count[i]}end
if provider then
 assert(provider.job_id==job.id and provider.building_id==evidence.building_id and json.encode(provider.search)==json.encode(evidence.search),'Owned job settings identity/location differs')
 assert(#provider.options==#evidence.options and #provider.materials==#evidence.materials,'Owned job settings list sizes differ')
 for i,option in ipairs(evidence.options)do assert(provider.options[i].kind==option.kind and provider.options[i].index==option.index,'Owned job option differs')end
 for i,row in ipairs(evidence.materials)do
  local actual=provider.materials[i];assert(actual.type==row.type and actual.index==row.index and actual.count==row.count,'Owned job material/count/order differs at '..i)
 end
 evidence.provider=provider
end
view:render(dfhack.getTickCount());evidence.lines={}
for row=0,g.dimy-1 do
 local chars={};for col=0,g.dimx-1 do local ch=dfhack.screen.readTile(col,row).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch) or ' 'end
 evidence.lines[#evidence.lines+1]={y=row,text=dfhack.df2utf(table.concat(chars)):gsub('%s+$','')}
end
local file=assert(io.open(out..'/residents-job-settings-reference.json','w'));file:write(json.encode(evidence));file:close()
local wire_original=owner.job.current_job
if os.getenv('DF3D_RESIDENTS_JOB_SETTINGS_WIRE')=='1' then owner.job.current_job=job end
file=assert(io.open(out..'/shot.tmp','w'));file:write('residents-job-settings');file:close()
assert(os.rename(out..'/shot.tmp',out..'/shot'))
local deadline=dfhack.getTickCount()+10000
while true do
 local ack=io.open(out..'/ack-residents-job-settings');if ack then ack:close();break end
 assert(dfhack.getTickCount()<deadline,'Job settings capture timeout');script.sleep(1,'frames')
end
owner.job.current_job=wire_original
if os.getenv('DF3D_RESIDENTS_JOB_SETTINGS_EFFECTS')=='1' then
 assert(controlled and job==controlled,'Effect oracle requires the disposable unlinked job')
 local function observation()
  local result={job_id=job.id,mat_type=job.mat_type,mat_index=job.mat_index,inputs={}}
  for _,item in ipairs(job.job_items.elements)do
   result.inputs[#result.inputs+1]={item_type=item.item_type,item_subtype=item.item_subtype,mat_type=item.mat_type,mat_index=item.mat_index,
    quantity=item.quantity,flags1=item.flags1.whole,flags2=item.flags2.whole,flags3=item.flags3.whole,
    details_flags=item.job_details_flags.whole,saved_type=item.job_details_mat_type,saved_index=item.job_details_mat_index,saved_flags2=item.job_details_item_flags2.whole}
  end
  return result
 end
 local effect={before=observation(),choice={type=evidence.materials[2].type,index=evidence.materials[2].index}}
 local choice_y
 for _,line in ipairs(evidence.lines)do if line.text:find('Dolomite',1,true)then choice_y=line.y;break end end
 assert(choice_y and provider and provider.materials[2].caption=='Dolomite','Expected visible Dolomite material')
 local function click_at(cx,cy)
  g.precise_mouse_x=cx*8+4;g.precise_mouse_y=cy*12+6;g.mouse_x=cx;g.mouse_y=cy
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
  gui.simulateInput(view,'_MOUSE_L')
  df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
  for _=1,3 do script.sleep(1,'frames')end
 end
 click_at(10,choice_y)
 effect.after=observation();effect.details_open=details.open;effect.info_open=info.open
 assert(effect.after.mat_type==effect.choice.type and effect.after.mat_index==effect.choice.index,'Native job material selection did not update job')
 assert(effect.after.inputs[1].mat_type==effect.choice.type and effect.after.inputs[1].mat_index==effect.choice.index,'Native selection did not update requirement')
 assert(not details.open and info.open,'Native selection did not return to Residents')
 evidence.material_effect=effect
 -- The job remains unlinked and is discarded with this unsaved process. Reopen
 -- the actual captured button to retain the independent Escape observation.
 click_at(button.rect.x1+1,button.rect.y1+1)
 assert(details.open and details.jb==job,'Native job button did not reopen after selection')
end
gui.simulateInput(view,'LEAVESCREEN')
for _=1,3 do script.sleep(1,'frames')end
evidence.escape_details_open=details.open;evidence.escape_info_open=info.open
file=assert(io.open(out..'/residents-job-settings-reference.json','w'));file:write(json.encode(evidence));file:close()
if not info.open then gui.simulateInput(view,'D_UNITLIST');for _=1,3 do script.sleep(1,'frames')end
elseif scroller then scroller.scroll=previous_scroll end
