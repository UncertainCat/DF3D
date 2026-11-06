-- Protected native UI discovery only; runtime must not borrow these widgets.
local out,view,records=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local g=df.global.gps
local defaults=os.getenv('DF3D_WORK_DETAILS_DEFAULTS')=='1'
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
local result={mode=info.current_mode,rows={},details={},callbacks={}}
local base=dfhack.internal.getImageBase()
local function callbacks(vector)
 local _,address=df.sizeof(vector);local first=df.reinterpret_cast('uint64_t',address).value;local last=df.reinterpret_cast('uint64_t',address+8).value
 assert(last>=first and (last-first)%64==0 and last-first<=65536)
 local values={}
 for at=first,last-1,64 do
  local context=df.reinterpret_cast('uint64_t',at+56).value
  if context~=0 then local vt=df.reinterpret_cast('uint64_t',context).value;values[#values+1]=df.reinterpret_cast('uint64_t',vt+16).value-base end
 end
 return values
end
local function walk(widget,depth)
 assert(depth<24,'Work Details widget depth exceeded')
 if (widget.flag.whole&1)==0 then return end
 if df.widget_unit_name:is_instance(widget) and widget.u and (widget.flag.whole&2)~=0 and widget.rect.y1>=23 then
  for _,child in ipairs(dfhack.gui.getWidgetChildren(widget.parent))do
   if child.name=='Selected' and (not result.first_visible or child.rect.y1<result.first_visible.y)then
    result.first_visible={unit_id=widget.u.id,x=child.rect.x1+1,y=child.rect.y1+1}
   end
  end
 end
 if df.widget_unit_list:is_instance(widget)then
  local list={ids={},options={},skills={},sorting={},sort_flags=widget.sort_flags.whole,filter=callbacks(widget.filter_func),partitions=callbacks(widget.partitions),always=callbacks(widget.always_sorting_by),select=callbacks(widget.on_select_change)}
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
 if df.widget_container:is_instance(widget)then for _,child in ipairs(dfhack.gui.getWidgetChildren(widget))do walk(child,depth+1)end end
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
end
records[#records+1]={name='work-details-native',count=#result.details,mode=result.mode}
