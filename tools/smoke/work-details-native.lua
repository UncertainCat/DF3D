-- Protected native UI discovery only; runtime must not borrow these widgets.
local out,view,records=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local g=df.global.gps
local defaults=os.getenv('DF3D_WORK_DETAILS_DEFAULTS')=='1'
local query_provider=os.getenv('DF3D_WORK_DETAILS_QUERY_PROVIDER')=='1'
local row_provider=os.getenv('DF3D_WORK_DETAILS_ROW_PROVIDER')=='1'
if row_provider then
 -- Controlled mixed-labor input, confined to the unsaved owned clone.
 for i=0,93 do df.global.plotinfo.labor_info.work_details[0].allowed_labors[i]=true end
end
local cold_query
if query_provider then
 local text,code=dfhack.run_command_silent('df3d','work-detail-query-probe','0','3','0','')
 assert(code==0,'Cold Work Details query failed: '..text);cold_query=json.decode(text).ids
end
if defaults then
 local changed=false
 for _,detail in ipairs(df.global.plotinfo.labor_info.work_details)do
  if not detail.flags.no_modify then detail.name='Custom Detail 1';detail.icon=17;changed=true;break end
 end
 assert(changed,'Defaults fixture requires an existing custom detail')
end
gui.simulateInput(view,'D_LABOR')
for _=1,3 do script.sleep(1,'frames')end;view:render(dfhack.getTickCount())
local info=df.global.game.main_interface.info
assert(info.open,'Native Labor did not open')
local path=debug.getinfo(1,'S').source:sub(2):gsub('smoke/work%-details%-native.lua$','ui_bake/capture_widgets.lua')
assert(loadfile(path))(out..'/work-details-widgets.json','templates')
local result={mode=info.current_mode,rows={},details={},callbacks={},worker_skill_rows={}}
local base=dfhack.internal.getImageBase()
local function callbacks(vector,stride)
 stride=stride or 64
 local _,address=df.sizeof(vector);local first=df.reinterpret_cast('uint64_t',address).value;local last=df.reinterpret_cast('uint64_t',address+8).value
 assert(last>=first and (last-first)%stride==0 and last-first<=65536)
 local values={}
 for at=first,last-1,stride do
  local context=df.reinterpret_cast('uint64_t',at+56).value
  if context~=0 then local vt=df.reinterpret_cast('uint64_t',context).value;values[#values+1]=df.reinterpret_cast('uint64_t',vt+16).value-base end
 end
 return values
end
local active_list,filter_box;local headers={}
local function walk(widget,depth)
 assert(depth<24,'Work Details widget depth exceeded')
 if (widget.flag.whole&1)==0 then return end
 if widget.name=='Filter box' then filter_box=widget end
 if (widget.flag.whole&2)~=0 and widget.rect.y1==21 and (widget.name=='Name' or widget.name=='Cat' or widget.name=='Prof' or widget.name=='Skills')then headers[widget.name]=widget end
 if df.widget_unit_name:is_instance(widget) and widget.u and (widget.flag.whole&2)~=0 and widget.rect.y1>=23 then
  if row_provider then
   local native={}
   for _,child in ipairs(dfhack.gui.getWidgetChildren(widget.parent))do
    if df.widget_rows_container:is_instance(child) and child.rect.x1==widget.parent.rect.x1+36 then
     for _,line in ipairs(dfhack.gui.getWidgetChildren(child))do
      if df.widget_text:is_instance(line)then native[#native+1]=dfhack.df2utf(line.str)end
     end
    end
   end
   local text,code=dfhack.run_command_silent('df3d','work-detail-row-probe','0',tostring(widget.u.id))
   assert(code==0,'Work Details skill provider failed: '..text)
   local provider=json.decode(text).skills
   assert(#native==#provider,'Work Details skill count differs for '..widget.u.id)
   for i,line in ipairs(native)do assert(line==provider[i].caption,'Work Details skill caption/order differs: '..line)end
   local member=false;for _,id in ipairs(df.global.plotinfo.labor_info.work_details[0].assigned_units)do if id==widget.u.id then member=true end end
   result.worker_skill_rows[#result.worker_skill_rows+1]={unit_id=widget.u.id,native=native,provider=provider,member=member}
  end
  for _,child in ipairs(dfhack.gui.getWidgetChildren(widget.parent))do
   if child.name=='Selected' and (not result.first_visible or child.rect.y1<result.first_visible.y)then
    result.first_visible={unit_id=widget.u.id,x=child.rect.x1+1,y=child.rect.y1+1}
   end
  end
 end
 if df.widget_unit_list:is_instance(widget)then
  active_list=widget
  local list={ids={},options={},skills={},sorting={},sort_callbacks=callbacks(widget.sorting_by,96),sort_flags=widget.sort_flags.whole,filter=callbacks(widget.filter_func),partitions=callbacks(widget.partitions),always=callbacks(widget.always_sorting_by),select=callbacks(widget.on_select_change)}
  for _,entry in ipairs(widget.entry_list)do list.ids[#list.ids+1]={kind=entry.t,id=entry.t==0 and entry.u and entry.u.id or -1}end
  for _,option in ipairs(widget.options)do list.options[#list.options+1]=df.unit_list_options[option]end
  for _,sort in ipairs(widget.sorting_by)do list.sorting[#list.sorting+1]=sort.ident end
  for skill,weight in ipairs(widget.skills)do if weight~=0 then list.skills[#list.skills+1]={skill=skill,weight=weight}end end
  result.worker_list=list
 end
 local _,address=df.sizeof(widget.custom_activated)
 local first=df.reinterpret_cast('uint64_t',address).value;local last=df.reinterpret_cast('uint64_t',address+8).value
 assert(last>=first and (last-first)%64==0 and last-first<=65536)
 for at=first,last-1,64 do
  local context=df.reinterpret_cast('uint64_t',at+56).value
  if context~=0 then
   local vt=df.reinterpret_cast('uint64_t',context).value
   result.callbacks[#result.callbacks+1]={name=widget.name,rect={widget.rect.x1,widget.rect.y1,widget.rect.x2,widget.rect.y2},rva=df.reinterpret_cast('uint64_t',vt+16).value-base}
  end
 end
 if df.widget_container:is_instance(widget)then
  for index,child in ipairs(dfhack.gui.getWidgetChildren(widget))do
   if not df.widget_tabs:is_instance(widget) or index-1==widget.cur_idx then walk(child,depth+1)end
  end
 end
end
walk(info.labor,0)
for y=0,g.dimy-1 do
 local chars={};for x=0,g.dimx-1 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
 result.rows[#result.rows+1]={y=y,text=dfhack.df2utf(table.concat(chars)):gsub('%s+$','')}
end
for i,d in ipairs(df.global.plotinfo.labor_info.work_details)do
 local labors={};for j,value in ipairs(d.allowed_labors)do if value then labors[#labors+1]=j end end
 result.details[#result.details+1]={index=i,name=dfhack.df2utf(d.name),icon=d.icon,flags=d.flags.whole,labors=labors,assigned_count=#d.assigned_units}
end
local function shot(name)
 local file=assert(io.open(out..'/work-details-native.json','w'));file:write(json.encode(result));file:close()
 file=assert(io.open(out..'/shot.tmp','w'));file:write(name);file:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local deadline=dfhack.getTickCount()+10000
 while true do local ack=io.open(out..'/ack-'..name);if ack then ack:close();break end;assert(dfhack.getTickCount()<deadline,'Work Details capture timeout');script.sleep(1,'frames')end
end
shot('work-details-root')
if row_provider then
 assert(#result.worker_skill_rows>0,'No visible skill rows')
 local multiple=false;for _,row in ipairs(result.worker_skill_rows)do if #row.native>1 then multiple=true end end
 assert(multiple,'Mixed-labor oracle did not include multiple skills')
 records[#records+1]={name='work-details-root'};return
end
if os.getenv('DF3D_WORK_DETAILS_QUERY')=='1' then
 local function displayed()
  local ids={}
  local function collect(widget,active)
   active=active and (widget.flag.whole&1)~=0
   if active and df.widget_unit_portrait:is_instance(widget) and widget.u then ids[#ids+1]=widget.u.id end
   if df.widget_container:is_instance(widget)then for _,child in ipairs(dfhack.gui.getWidgetChildren(widget))do collect(child,active)end end
  end
  collect(active_list,true);return ids
 end
 result.worker_list.displayed_ids=displayed()
 if query_provider then
  result.cold_query=cold_query;assert(json.encode(cold_query)==json.encode(displayed()),'Cold Work Details order differs')
  result.queries={}
  local function observe(name,sort,direction,query)
   local before=displayed();local prior_filter=active_list.filter_str
   local text,code=dfhack.run_command_silent('df3d','work-detail-query-probe','0',tostring(sort),tostring(direction),query or '')
   assert(code==0,'Work Details query failed: '..text)
   local ids=json.decode(text).ids
   result.queries[#result.queries+1]={name=name,sort=sort,direction=direction,query=query or '',native=before,provider=ids}
   assert(json.encode(ids)==json.encode(before),'Work Details order differs: '..name)
   assert(json.encode(displayed())==json.encode(before) and active_list.filter_str==prior_filter,'Provider changed native menu')
  end
  local function click(widget)
   assert(widget,'Missing native query control')
   local x=widget.rect.x1+1;local y=widget.rect.y1
   if widget==filter_box then x=(widget.rect.x1+widget.rect.x2)//2;y=(widget.rect.y1+widget.rect.y2)//2 end
   g.precise_mouse_x=x*8+4;g.precise_mouse_y=y*12+6;g.mouse_x=x;g.mouse_y=y
   df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L')
   df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
   for _=1,3 do script.sleep(1,'frames')end;view:render(dfhack.getTickCount())
  end
  observe('initial',3,0)
  for sort,name in ipairs{'Cat','Name','Prof','Skills'}do
   for direction=0,1 do click(headers[name]);observe(name..'-'..direction,sort-1,direction)end
  end
  for _,query in ipairs{'MINER','Tâmol','tamol','no-matching-worker-zzq',''}do
   click(filter_box)
   local file=assert(io.open(out..'/residents-search-input.json','w'));file:write(json.encode({clear_count=#filter_box.str,text=query}));file:close()
   file=assert(io.open(out..'/owner-input-request.tmp','w'));file:write('residents-search');file:close();assert(os.rename(out..'/owner-input-request.tmp',out..'/owner-input-request'))
   local deadline=dfhack.getTickCount()+30000
   while true do local ack=io.open(out..'/owner-input-ack');if ack then ack:close();break end;assert(dfhack.getTickCount()<deadline,'Work Details search timeout');script.sleep(1,'frames')end
   assert(os.remove(out..'/owner-input-ack'))
   for _=1,3 do script.sleep(1,'frames')end;assert(filter_box.str==query,'Native search input differs: '..filter_box.str);view:render(dfhack.getTickCount())
   observe('search-'..query,3,1,query)
  end
 end
 shot('work-details-query');records[#records+1]={name='work-details-query'};return
end
if os.getenv('DF3D_WORK_DETAILS_MEMBERSHIP')=='1' then
 local visible=assert(result.first_visible,'No visible membership checkbox')
 local unit_id=visible.unit_id;local unit=assert(df.unit.find(unit_id))
 local all=df.global.plotinfo.labor_info.work_details
 local function snapshot()
  local value={details={},labors={}}
  for _,detail in ipairs(all)do
   local ids={};for _,id in ipairs(detail.assigned_units)do ids[#ids+1]=id end
   value.details[#value.details+1]={flags=detail.flags.whole,ids=ids}
  end
  for labor,enabled in ipairs(unit.status.labors)do if enabled then value.labors[#value.labors+1]=labor end end
  value.profession=unit.profession;value.profession2=unit.profession2;return value
 end
 local before=snapshot()
 local present=false;for _,id in ipairs(before.details[1].ids)do if id==unit_id then present=true end end
 assert(present,'Membership fixture first selected unit differs')
 g.precise_mouse_x=visible.x*8+4;g.precise_mouse_y=visible.y*12+6;g.mouse_x=visible.x;g.mouse_y=visible.y
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L')
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
 for _=1,3 do script.sleep(1,'frames')end;view:render(dfhack.getTickCount())
 result.membership={unit_id=unit_id,before=before,native=snapshot()}
 assert(#result.membership.native.details[1].ids==#before.details[1].ids-1,'Native membership removal failed')
 for _,id in ipairs(result.membership.native.details[1].ids)do assert(id~=unit_id,'Native checkbox removed another unit')end
 for i,saved in ipairs(before.details)do
  local detail=all[i-1];detail.flags.whole=saved.flags
  detail.assigned_units:resize(0);for _,id in ipairs(saved.ids)do detail.assigned_units:insert('#',id)end
 end
 for _,active in ipairs(df.global.world.units.active)do dfhack.units.setAutomaticProfessions(active)end
 assert(json.encode(snapshot())==json.encode(before),'Membership fixture restoration failed')
 shot('work-details-membership-wire')
 result.membership.semantic=snapshot()
 assert(json.encode(result.membership.semantic)==json.encode(result.membership.native),'Native membership effect differs')
 shot('work-details-membership-result')
 records[#records+1]={name='work-details-membership',unit_id=unit_id};return
end
g.precise_mouse_x=15*8+4;g.precise_mouse_y=13*12+6;g.mouse_x=15;g.mouse_y=13
df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
gui.simulateInput(view,'_MOUSE_L')
df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
for _=1,3 do script.sleep(1,'frames')end;view:render(dfhack.getTickCount())
local all=df.global.plotinfo.labor_info.work_details
assert(#all==#result.details+1,'Native Add new work detail did not append one detail')
local d=all[#all-1];local labors={};for j,value in ipairs(d.allowed_labors)do if value then labors[#labors+1]=j end end
result.created={index=#all-1,name=dfhack.df2utf(d.name),icon=d.icon,flags=d.flags.whole,labors=labors,assigned_count=#d.assigned_units}
shot('work-details-created')
local function click_handler(rva)
  local target
  local function find(widget)
   if (widget.flag.whole&1)==0 then return end
   if (widget.flag.whole&2)~=0 then
    for _,value in ipairs(callbacks(widget.custom_activated))do if value==rva then assert(not target,'Ambiguous action');target=widget end end
   end
   if df.widget_container:is_instance(widget)then for _,child in ipairs(dfhack.gui.getWidgetChildren(widget))do find(child)end end
  end
  find(info.labor);assert(target,'Native action missing: '..rva)
  local x=(target.rect.x1+target.rect.x2)//2;local y=(target.rect.y1+target.rect.y2)//2
  g.precise_mouse_x=x*8+4;g.precise_mouse_y=y*12+6;g.mouse_x=x;g.mouse_y=y
  df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L')
  df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
  for _=1,3 do script.sleep(1,'frames')end;view:render(dfhack.getTickCount())
 end
if os.getenv('DF3D_WORK_DETAILS_DELETE')=='1' then
 local function snapshot()
  local state={details={},units={}}
  for index,detail in ipairs(all)do
   local allowed,members={},{}
   for id,value in ipairs(detail.allowed_labors)do if value then allowed[#allowed+1]=id end end
   for _,id in ipairs(detail.assigned_units)do members[#members+1]=id end
   state.details[#state.details+1]={index=index,name=dfhack.df2utf(detail.name),icon=detail.icon,flags=detail.flags.whole,labors=allowed,members=members}
  end
  for _,unit in ipairs(df.global.world.units.active)do
   local allowed={};for id,value in ipairs(unit.status.labors)do if value then allowed[#allowed+1]=id end end
   state.units[#state.units+1]={id=unit.id,labors=allowed,profession=unit.profession,profession2=unit.profession2}
  end
  return state
 end
 -- Assign a real worker and multiple labors so deleting the definition has
 -- observable effects. All changes are confined to the paused unsaved clone.
 local unit=assert(df.unit.find(result.first_visible.unit_id))
 d.flags.mode=3;d.allowed_labors[11]=true;d.allowed_labors[59]=true;d.assigned_units:insert('#',unit.id)
 for _,active in ipairs(df.global.world.units.active)do dfhack.units.setAutomaticProfessions(active)end
 local restored=df.work_detail:new();restored:assign(d)
 result.deletion={index=#all-1,unit_id=unit.id,before=snapshot()}
 click_handler(0x468880);shot('work-details-delete-before')
 click_handler(0x468b60)
 assert(#all==#result.details,'Native Delete did not remove one definition')
 result.deletion.after=snapshot()
 result.deletion.changed_units={}
 for i,after in ipairs(result.deletion.after.units)do
  if json.encode(after)~=json.encode(result.deletion.before.units[i])then result.deletion.changed_units[#result.deletion.changed_units+1]=after.id end
 end
 assert(#result.deletion.changed_units>0,'Delete fixture did not exercise worker effects')
 assert(loadfile(path))(out..'/work-details-delete-widgets.json','templates')
 shot('work-details-delete-after')
 if os.getenv('DF3D_WORK_DETAILS_DELETE_WIRE')=='1' then
  all:insert('#',restored)
  for _,active in ipairs(df.global.world.units.active)do dfhack.units.setAutomaticProfessions(active)end
  assert(json.encode(snapshot())==json.encode(result.deletion.before),'Delete fixture restoration differs')
  shot('work-details-delete-wire')
  result.deletion.semantic=snapshot()
  assert(json.encode(result.deletion.semantic)==json.encode(result.deletion.after),'Semantic Delete effects differ')
  shot('work-details-delete-result')
 else restored:delete()end
 records[#records+1]={name='work-details-delete',changed_units=#result.deletion.changed_units};return
end
if os.getenv('DF3D_WORK_DETAILS_EDITS')=='1' then
 local unit=assert(df.unit.find(result.first_visible.unit_id))
 d.allowed_labors[11]=true;d.assigned_units:insert('#',unit.id);d.flags.mode=3
 local function snapshot()
  local labors={};for id,value in ipairs(d.allowed_labors)do if value then labors[#labors+1]=id end end
  local units={}
  for _,active in ipairs(df.global.world.units.active)do
   local enabled={};for id,value in ipairs(active.status.labors)do if value then enabled[#enabled+1]=id end end
   units[#units+1]={id=active.id,labors=enabled,profession=active.profession,profession2=active.profession2}
  end
  return {flags=d.flags.whole,labors=labors,units=units}
 end
 for _,active in ipairs(df.global.world.units.active)do dfhack.units.setAutomaticProfessions(active)end
 local before=snapshot()
 result.edits={index=#all-1,unit_id=unit.id,before=before,modes={}}
 for _,step in ipairs{{2,0x468560},{1,0x468760},{3,0x468660}}do
  click_handler(step[2]);assert(d.flags.mode==step[1],'Native mode click failed')
  result.edits.modes[#result.edits.modes+1]={mode=step[1],snapshot=snapshot()}
 end
 -- Reset a disposable definition as Siege Operators, which the former Lua
 -- default table did not cover. Keep the live selected detail object stable.
 d.flags.no_modify=true;d.icon=18
 result.edits.before_reset=snapshot()
 click_handler(0x468880);shot('work-details-reset-before');click_handler(0x468940)
 result.edits.reset_snapshot=snapshot()
 assert(json.encode(result.edits.reset_snapshot.units)==json.encode(result.edits.before_reset.units),'Native Reset unexpectedly recalculated workers')
 shot('work-details-reset-after')
 result.edits.reset_labors={};for id,value in ipairs(d.allowed_labors)do if value then result.edits.reset_labors[#result.edits.reset_labors+1]=id end end
 assert(#result.edits.reset_labors==1 and result.edits.reset_labors[1]==58,'Native Siege Operators defaults differ')
 d.flags.whole=before.flags;d.icon=result.created.icon
 for id=0,93 do d.allowed_labors[id]=false end;for _,id in ipairs(before.labors)do d.allowed_labors[id]=true end
 for _,active in ipairs(df.global.world.units.active)do dfhack.units.setAutomaticProfessions(active)end
 assert(json.encode(snapshot())==json.encode(before),'Edit fixture restoration failed')
 -- The client and oracle alternate at each step, so full active-unit effects
 -- are compared before the next command. No mutation is replayed on timeout.
 for i,step in ipairs(result.edits.modes)do
  result.edits.step=i;shot('work-details-edit-'..i..'-wire')
  step.semantic=snapshot();assert(json.encode(step.semantic)==json.encode(step.snapshot),'Native mode effects differ')
 end
 d.flags.no_modify=true;d.icon=18
 result.edits.step=4;shot('work-details-edit-4-wire')
 result.edits.semantic_reset_labors={};for id,value in ipairs(d.allowed_labors)do if value then result.edits.semantic_reset_labors[#result.edits.semantic_reset_labors+1]=id end end
 assert(json.encode(result.edits.semantic_reset_labors)==json.encode(result.edits.reset_labors),'Native reset defaults differ')
 result.edits.semantic_reset_snapshot=snapshot()
 assert(json.encode(result.edits.semantic_reset_snapshot)==json.encode(result.edits.reset_snapshot),'Native Reset full worker effects differ')
 shot('work-details-edits-result');records[#records+1]={name='work-details-edits'};return
end
if defaults then
 -- Retain the removed object until process exit: native widgets may hold it.
 all:erase(#all-1)
 shot('work-details-defaults-wire')
 assert(#all==#result.details+1,'Semantic creation did not append one detail')
 local actual=all[#all-1];local active={};for j,value in ipairs(actual.allowed_labors)do if value then active[#active+1]=j end end
 result.semantic_created={index=#all-1,name=dfhack.df2utf(actual.name),icon=actual.icon,flags=actual.flags.whole,labors=active,assigned_count=#actual.assigned_units}
 assert(json.encode(result.semantic_created)==json.encode(result.created),'Semantic work-detail defaults differ from native')
 shot('work-details-defaults-result')
end
if os.getenv('DF3D_WORK_DETAILS_SETTINGS')=='1' then
 local settings_effects=os.getenv('DF3D_WORK_DETAILS_SETTINGS_EFFECTS')=='1'
 local function snapshot()
  local labors={};for id,value in ipairs(d.allowed_labors)do if value then labors[#labors+1]=id end end
  local units={}
  for _,unit in ipairs(df.global.world.units.active)do
   local enabled={};for id,value in ipairs(unit.status.labors)do if value then enabled[#enabled+1]=id end end
   units[#units+1]={id=unit.id,labors=enabled,profession=unit.profession,profession2=unit.profession2}
  end
  return {labors=labors,units=units}
 end
 if settings_effects then
  d.flags.mode=3;d.assigned_units:insert('#',result.first_visible.unit_id)
  for _,unit in ipairs(df.global.world.units.active)do dfhack.units.setAutomaticProfessions(unit)end
  result.settings_effects={index=#all-1,unit_id=result.first_visible.unit_id,before=snapshot(),steps={}}
  if os.getenv('DF3D_WORK_DETAILS_SETTINGS_PROVIDER')=='1' then
   local text,code=dfhack.run_command_silent('df3d','work-detail-settings-probe',tostring(#all-1),'11','-2','-2','11')
   assert(code==0,'Owned settings provider failed: '..text)
   result.settings_effects.provider=json.decode(text)
   assert(result.settings_effects.provider.source_unchanged and json.encode(snapshot())==json.encode(result.settings_effects.before),'Settings probe changed source')
  end
 end
 g.precise_mouse_x=85*8+4;g.precise_mouse_y=13*12+6;g.mouse_x=85;g.mouse_y=13
 df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L')
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
 for _=1,3 do script.sleep(1,'frames')end;view:render(dfhack.getTickCount())
 assert(loadfile(path))(out..'/work-details-settings-widgets.json','templates')
 result.settings_rows={}
 for y=0,g.dimy-1 do
  local chars={};for x=0,g.dimx-1 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
  result.settings_rows[#result.settings_rows+1]={y=y,text=dfhack.df2utf(table.concat(chars)):gsub('%s+$','')}
 end
 shot('work-details-settings')
 if settings_effects then
  local function click(rva,id)
   local target
   local caption=id==11 and 'Carpentry' or id==-2 and 'Woodworking' or 'Done'
   local function find(widget)
    if (widget.flag.whole&1)==0 then return end
    if (widget.flag.whole&2)~=0 and df.widget_text:is_instance(widget) and widget.str==caption then
     assert(not target,'Ambiguous settings label');target=widget
    end
    if df.widget_container:is_instance(widget)then
     for index,child in ipairs(dfhack.gui.getWidgetChildren(widget))do
      if not df.widget_tabs:is_instance(widget) or index-1==widget.cur_idx then find(child)end
     end
    end
   end
   find(info.labor)
   local x,y
   if target then x=(target.rect.x1+target.rect.x2)//2;y=(target.rect.y1+target.rect.y2)//2
   else
    -- The settings list's derived type is not exposed by this DFHack XML.
    -- Resolve its actual rendered label rather than casting an unknown widget.
    for row=0,g.dimy-1 do
     local chars={};for column=0,g.dimx-1 do local ch=dfhack.screen.readTile(column,row).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
     local first=table.concat(chars):find(caption,1,true)
     if first then assert(not x,'Ambiguous rendered settings label');x=first-1+#caption//2;y=row end
    end
   end
   assert(x and y,'Missing native settings label '..caption)
   g.precise_mouse_x=x*8+4;g.precise_mouse_y=y*12+6;g.mouse_x=x;g.mouse_y=y
   df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L')
   df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
   local step={rva=rva,id=id,immediate=snapshot()}
   for _=1,3 do script.sleep(1,'frames')end;view:render(dfhack.getTickCount())
   step.after_frames=snapshot();result.settings_effects.steps[#result.settings_effects.steps+1]=step
  end
  click(0x468ec0,11);assert(d.allowed_labors[11],'Carpentry toggle failed')
  click(0x469020,-2);assert(d.allowed_labors[11] and d.allowed_labors[59],'Woodworking group enable failed')
  click(0x469020,-2);assert(not d.allowed_labors[11] and not d.allowed_labors[59],'Woodworking group disable failed')
  click(0x468ec0,11)
  click(0x468d20)
  if result.settings_effects.provider then
   for i,step in ipairs(result.settings_effects.provider.steps)do
    assert(step.id==result.settings_effects.steps[i].id and json.encode(step.labors)==json.encode(result.settings_effects.steps[i].immediate.labors),'Owned native toggle differs from actual settings click')
   end
  end
  gui.simulateInput(view,'LEAVESCREEN')
  for _=1,3 do script.sleep(1,'frames')end;view:render(dfhack.getTickCount())
  result.settings_effects.after_leave=snapshot()
  if os.getenv('DF3D_WORK_DETAILS_SETTINGS_WIRE')=='1' then
   assert(result.settings_effects.provider,'Wire reference requires owned provider')
   for id=0,93 do d.allowed_labors[id]=false end
   for _,id in ipairs(result.settings_effects.before.labors)do d.allowed_labors[id]=true end
   result.settings_wire_phase='normal';shot('work-details-settings-wire-normal')
   local after=snapshot()
   assert(json.encode(after.labors)==json.encode(result.settings_effects.after_leave.labors),'Wire final definition differs from native')
   assert(json.encode(after.units)==json.encode(result.settings_effects.before.units),'Wire settings forced worker recalculation')
   result.settings_effects.wire_snapshot=after
   local prior=df.global.game.external_flag.automatic_professions_disabled
   df.global.game.external_flag.automatic_professions_disabled=true
   result.settings_wire_phase='locked';shot('work-details-settings-wire-locked')
   df.global.game.external_flag.automatic_professions_disabled=prior
   assert(json.encode(snapshot())==json.encode(after),'External controller rejection changed simulation')
   result.settings_effects.wire_external_rejected=true
  end
  if os.getenv('DF3D_WORK_DETAILS_SETTINGS_SIMULATION')=='1' then
   assert(df.global.pause_state,'Settings simulation reference must start paused')
   local start=df.global.world.frame_counter
   result.settings_effects.simulation={start_tick=start,samples={}}
   df.global.pause_state=false
   for frame=1,60 do
    script.sleep(1,'frames')
    local elapsed=df.global.world.frame_counter-start
    if elapsed>0 and (#result.settings_effects.simulation.samples==0 or elapsed>=10)then
     result.settings_effects.simulation.samples[#result.settings_effects.simulation.samples+1]={elapsed_ticks=elapsed,snapshot=snapshot()}
    end
    if elapsed>=10 then break end
   end
   df.global.pause_state=true
   assert(df.global.world.frame_counter-start>=10,'Normal simulation did not advance ten ticks')
   result.settings_effects.simulation.end_tick=df.global.world.frame_counter
   records[#records+1]={name='work-details-simulation',start_tick=start,end_tick=df.global.world.frame_counter}
  end
  for _,unit in ipairs(df.global.world.units.active)do dfhack.units.setAutomaticProfessions(unit)end
  result.settings_effects.after_explicit_recalculation=snapshot()
  shot('work-details-settings-effects')
 end
end
records[#records+1]={name='work-details-native',count=#result.details,mode=result.mode}
