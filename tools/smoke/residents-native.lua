-- Diagnostic native screen observation in the protected owned, unsaved lane.
-- Runtime providers must never use this screen's widget or list storage.
local out,view,records=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
df.global.enabler.gfps=30
df.global.enabler.fps_per_gfps=df.global.enabler.fps/30
local activity_provider
if os.getenv('DF3D_RESIDENTS_ACTIVITY')=='1' then
 local text,code=dfhack.run_command_silent('df3d','residents-activity-probe')
 assert(code==0,'Cold Residents Activity provider failed: '..text)
 activity_provider=json.decode(text).rows
end
gui.simulateInput(view,'D_UNITLIST')
for _=1,3 do script.sleep(1,'frames')end
view:render(dfhack.getTickCount())
local info=df.global.game.main_interface.info
assert(info.open and info.current_mode==df.info_interface_mode_type.CREATURES)
local source=debug.getinfo(1,'S').source:sub(2):gsub('smoke/residents%-native.lua$','ui_bake/capture_widgets.lua')
assert(loadfile(source))(out..'/residents-widgets.json','templates')
local lists={};local active_list;local headers={};local filter_box
local base=dfhack.internal.getImageBase()
local function callbacks(value,stride)
 local _,address=df.sizeof(value)
 local first=df.reinterpret_cast('uint64_t',address).value
 local last=df.reinterpret_cast('uint64_t',address+8).value
 assert(last>=first and (last-first)%stride==0 and last-first<=65536)
 local result={}
 for at=first,last-1,stride do
  local context=df.reinterpret_cast('uint64_t',at+56).value
  if context~=0 then
   local vt=df.reinterpret_cast('uint64_t',context).value
   result[#result+1]=df.reinterpret_cast('uint64_t',vt+16).value-base
  end
 end
 return result
end
local function walk(widget)
 if df.widget_unit_list:is_instance(widget) then
  local row={name=widget.name,filter=widget.filter_str,options={},ids={},sorting={},sort_flags=widget.sort_flags.whole}
  for _,option in ipairs(widget.options)do row.options[#row.options+1]=df.unit_list_options[option]end
  for _,entry in ipairs(widget.entry_list)do
   row.ids[#row.ids+1]={kind=entry.t,id=entry.t==0 and entry.u and entry.u.id or -1}
  end
  for _,entry in ipairs(widget.sorting_by)do row.sorting[#row.sorting+1]=entry.ident end
  row.filter_callbacks=#widget.filter_func;row.partitions=#widget.partitions;row.always_sorting=#widget.always_sorting_by
  row.callbacks={filter=callbacks(widget.filter_func,64),partitions=callbacks(widget.partitions,64),always=callbacks(widget.always_sorting_by,64)}
  active_list=widget
  lists[#lists+1]=row
 end
 if widget.rect.y1==12 and widget.rect.y2==12 then headers[widget.name]=widget end
 if widget.name=='Filter box' then filter_box=widget end
 if df.widget_container:is_instance(widget)then
  for index,child in ipairs(dfhack.gui.getWidgetChildren(widget))do
   if not df.widget_tabs:is_instance(widget) or index-1==widget.cur_idx then walk(child)end
  end
 end
end
walk(info.creatures)
assert(#lists>0,'Native Residents unit list missing')
if os.getenv('DF3D_RESIDENTS_ASSIGNMENTS')=='1' then
 local samples={}
 local occupation_codes={[0]=387,[1]=388,[2]=391,[3]=389,[4]=390,[5]=392,[7]=393,[8]=393,[9]=393,[10]=393}
 local function collect(widget,active)
  active=active and (widget.flag.whole&1)==1
  if active and df.widget_unit_name:is_instance(widget) and widget.u then
   local text,rc=dfhack.run_command_silent('df3d','residents-assignments-read',tostring(widget.u.id));assert(rc==0,text)
   local provider=json.decode(text);local expected={}
   for _,entry in ipairs(provider.entries)do
    if entry.kind==0 and occupation_codes[entry.type] then expected[#expected+1]={kind='indicator',value=occupation_codes[entry.type]}
    elseif entry.kind==1 or entry.kind==2 then expected[#expected+1]={kind='building'}
    elseif entry.kind==3 and entry.type>=0 and entry.type<=18 then expected[#expected+1]={kind='indicator',value=entry.type==18 and 374 or 364+entry.type+(entry.type>=10 and 1 or 0)}end
   end
   local container
   for _,child in ipairs(dfhack.gui.getWidgetChildren(widget.parent))do if child.name=='Occupations/Work Details' then container=child;break end end
   assert(container,'Native assignment container missing')
   local children=dfhack.gui.getWidgetChildren(container);assert(#children==#expected,'Native assignment count differs '..widget.u.id)
   local observed={}
   for i,child in ipairs(children)do
    local _,address=df.sizeof(child);local vtable=df.reinterpret_cast('uint64_t',address).value-base
    local kind=vtable==0x162e208 and 'indicator' or vtable==0x17860d0 and 'building' or 'unknown'
    local value=df.reinterpret_cast('int32_t',address+0x150).value
    assert(kind==expected[i].kind and (kind=='building' or value==expected[i].value),'Native assignment order/art differs '..widget.u.id..' expected '..json.encode(expected[i])..' observed '..kind..':'..value)
    observed[#observed+1]={kind=kind,value=value,rect={child.rect.x1,child.rect.y1,child.rect.x2,child.rect.y2}}
   end
   samples[#samples+1]={id=widget.u.id,provider=provider.entries,indicators=observed,padding=container.padding,container={container.rect.x1,container.rect.y1,container.rect.x2,container.rect.y2}}
  end
  if df.widget_container:is_instance(widget)then for _,child in ipairs(dfhack.gui.getWidgetChildren(widget))do collect(child,active)end end
 end
 collect(active_list,true);assert(#samples>0,'No Residents assignment rows observed')
 local file=assert(io.open(out..'/residents-assignments-reference.json','w'));file:write(json.encode(samples));file:close()
end
local function capture_resident_rows()
 if os.getenv('DF3D_RESIDENTS_ROWS')~='1' then return end
 local samples={}
 local function collect(widget,active)
  active=active and (widget.flag.whole&1)==1
  if active and (widget.flag.whole&2)~=0 and df.widget_unit_name:is_instance(widget) and widget.u then
   local g=df.global.gps;local width=math.min(widget.rect.x2-widget.rect.x1+1,widget.min_w)
   if widget.rect.y1>=14 and widget.rect.y1<g.dimy-8 and width>=3 then
    assert(widget.show_profession and not widget.one_line_only,'Unexpected Residents name mode')
    local text,code=dfhack.run_command_silent('df3d','residents-row-read',tostring(widget.u.id),tostring(width),widget.show_gender and '1' or '0')
    assert(code==0,text);local row=json.decode(text)
    local grazer=widget.u.enemy.caste_flags[df.caste_raw_flags.GRAZER]
    local lines={row.first_line,row.second_line};local observed={}
    for line=1,2 do
     local y=widget.rect.y1+line-2
     if grazer and row.second_line~='' then y=y-1 end
     local expected=dfhack.utf2df(lines[line]);local bytes={}
     for x=1,width do
      local tile=dfhack.screen.readTile(widget.rect.x1+x-1,y)
      bytes[#bytes+1]=tile.ch
      -- A grazer warning occupies the otherwise empty second line.
      if not (grazer and line==2 and expected=='') then
       assert(tile.ch==(expected:byte(x) or 0),'Residents name mismatch '..widget.u.id..' line '..line..' cell '..x)
      end
     end
     observed[#observed+1]=bytes
    end
    local indicator
    for _,child in ipairs(dfhack.gui.getWidgetChildren(widget.parent))do
     if child.name=="Happiness indicator" then indicator=child;break end
    end
    assert(indicator,"Native happiness indicator missing")
    local _,address=df.sizeof(indicator)
    local happiness=df.reinterpret_cast("int32_t",address+0x150).value-6
    assert(row.happiness==happiness,"Residents happiness differs "..widget.u.id)
    local sample={happiness=happiness,happiness_rect={indicator.rect.x1,indicator.rect.y1,indicator.rect.x2,indicator.rect.y2},id=widget.u.id,width=width,show_gender=widget.show_gender,grazer=grazer,provider=row,screen=observed}
    for _,child in ipairs(dfhack.gui.getWidgetChildren(widget.parent))do
     if child.name=='Recenter button' then
      local _,address=df.sizeof(child)
      sample.position={}
      for i=0,2 do sample.position[i+1]=df.reinterpret_cast('int16_t',address+0x150+i*2).value end
      assert(sample.position[1]==widget.u.pos.x and sample.position[2]==widget.u.pos.y and sample.position[3]==widget.u.pos.z,'Residents captured position differs')
     end
    end
    assert(sample.position,'Residents Recenter button missing')
    if os.getenv('DF3D_RESIDENTS_PORTRAITS')=='1' then
     local portrait
     for _,child in ipairs(dfhack.gui.getWidgetChildren(widget.parent))do
      if df.widget_unit_portrait:is_instance(child)then portrait=child;break end
     end
     assert(portrait,'Residents portrait widget missing')
     local at=portrait.rect.x1*g.dimy+portrait.rect.y1
     local texture=g.screentexpos_anchored[at]
     assert(texture>0,'Residents anchored portrait missing')
     sample.portrait_prefix='resident-portrait-'..widget.u.id
     local dump,rc=dfhack.run_command_silent('df3d','appearance','texture',tostring(texture),out..'/'..sample.portrait_prefix)
     assert(rc==0 and dump:find('DF3D_TEXTURE_DUMP_PASS',1,true),dump)
    end
    samples[#samples+1]=sample
   end
  end
  if df.widget_container:is_instance(widget)then for _,child in ipairs(dfhack.gui.getWidgetChildren(widget))do collect(child,active)end end
 end
 collect(active_list,true)
 assert(#samples>0,'No visible Residents names compared')
 local file=assert(io.open(out..'/residents-row-reference.json','w'));file:write(json.encode({samples=samples}));file:close()
end
if os.getenv('DF3D_RESIDENTS_ASSIGNMENTS')~='1' then capture_resident_rows()end
local activity_reference
if activity_provider then
 local function byte(at)return df.reinterpret_cast('uint8_t',at).value end
 local function word(at)return df.reinterpret_cast('uint64_t',at).value end
 local function native_string(at)
  local length,capacity=word(at+16),word(at+24)
  assert(length<=capacity and length<=4096,'Invalid native Activity string')
  local start=capacity>15 and word(at) or at
  local bytes={};for i=0,length-1 do bytes[#bytes+1]=string.char(byte(start+i))end
  return dfhack.df2utf(table.concat(bytes))
 end
 local function observe_activity()
  -- Diagnostic-only native cache observation. XML's pointer key omits the
  -- variant tag: native nodes contain a 16-byte key and string at +0x20.
  local _,address=df.sizeof(active_list);local head=word(address+0x338)
  local node=word(head);local keys={};local count=0
  while node~=head do
   count=count+1;assert(count<=10000,'Native Activity map cycle')
   if byte(node+24)==0 then keys[df.reinterpret_cast(df.unit,word(node+16)).id]=native_string(node+32)end
   node=word(node)
  end
  local rows={}
  local function collect(widget,active)
   active=active and (widget.flag.whole&1)==1
   if active and df.widget_unit_portrait:is_instance(widget) and widget.u then
    local job
    for _,child in ipairs(dfhack.gui.getWidgetChildren(widget.parent))do if child.name=='Job' then job=child;break end end
    assert(job,'Native Activity row missing')
    local label=dfhack.gui.getWidgetChildren(job)[1]
    assert(label and df.widget_text:is_instance(label),'Native Activity text missing')
    rows[#rows+1]={id=widget.u.id,caption=dfhack.df2utf(label.str),key=assert(keys[widget.u.id]),fg=label.fg,bg=label.bg,bright=label.bright}
   end
   if df.widget_container:is_instance(widget)then for _,child in ipairs(dfhack.gui.getWidgetChildren(widget))do collect(child,active)end end
  end
  collect(active_list,true);return rows
 end
 activity_reference=observe_activity()
 local function equal_rows(left,right)
  if #left~=#right then return false end
  local by_id={};for _,row in ipairs(right)do by_id[row.id]=row end
  for _,row in ipairs(left)do
   local other=by_id[row.id];if not other then return false end
   for _,key in ipairs{'caption','key','fg','bg','bright'}do if row[key]~=other[key]then return false end end
  end
  return true
 end
 local repeated,code=dfhack.run_command_silent('df3d','residents-activity-probe')
 assert(code==0,'Repeated Residents Activity provider failed: '..repeated)
 local repeat_rows=json.decode(repeated).rows
 local evidence={native=activity_reference,cold=activity_provider,repeated=repeat_rows,
  cold_matches=equal_rows(activity_reference,activity_provider),repeated_matches=equal_rows(activity_reference,repeat_rows),
  native_unchanged=equal_rows(activity_reference,observe_activity())}
 local file=assert(io.open(out..'/residents-activity-reference.json','w'));file:write(json.encode(evidence));file:close()
 assert(evidence.cold_matches and evidence.repeated_matches and evidence.native_unchanged,'Native Residents Activity differs')
end
local snapshots={}
local function observe(name,query)
 local ids={}
 local function collect(widget,active)
  active=active and (widget.flag.whole&1)==1
  if active and df.widget_unit_portrait:is_instance(widget) and widget.u then ids[#ids+1]=widget.u.id end
  if df.widget_container:is_instance(widget)then for _,child in ipairs(dfhack.gui.getWidgetChildren(widget))do collect(child,active)end end
 end
 collect(active_list,true)
 local sorting={};for _,entry in ipairs(active_list.sorting_by)do sorting[#sorting+1]=entry.ident end
 local observed={name=name,ids=ids,sorting=sorting,callbacks=callbacks(active_list.sorting_by,96),filter_bytes={active_list.filter_str:byte(1,#active_list.filter_str)},query=query}
 if os.getenv('DF3D_RESIDENTS_PROVIDER')=='1' then
  local kind=name:match('^([^%-]+)')
  local sorts={initial=0,Cat=0,Name=1,Prof=2,Stress=3,Job=4}
  if sorts[kind] then
   local text,code=dfhack.run_command_silent('df3d','residents-order-probe',tostring(sorts[kind]),name:find('%-2$') and '1' or '0',query or '')
   assert(code==0,'Residents provider failed: '..text)
   observed.provider=json.decode(text).ids
   observed.matches=json.encode(observed.provider)==json.encode(ids)
  end
 end
 snapshots[#snapshots+1]=observed
end
observe('initial')
for _,name in ipairs{'Name','Cat','Prof','Job','Stress'}do
 local header=assert(headers[name],'Missing sort header '..name)
 for direction=1,2 do
  local g=df.global.gps
  g.precise_mouse_x=header.rect.x1*8+4;g.precise_mouse_y=header.rect.y1*12+6
  g.mouse_x=header.rect.x1;g.mouse_y=header.rect.y1
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
  df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L')
  df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
  for _=1,3 do script.sleep(1,'frames')end
  view:render(dfhack.getTickCount());observe(name..'-'..direction)
 end
end
if os.getenv('DF3D_RESIDENTS_ASSIGNMENTS')=='1' then capture_resident_rows()end
if os.getenv('DF3D_RESIDENTS_SPECIALIZATION')=='1' then
 local targets={}
 local function collect(widget,active)
  active=active and (widget.flag.whole&1)==1
  if active and df.widget_unit_name:is_instance(widget) and widget.u and widget.rect.y1>=14 and widget.rect.y1<df.global.gps.dimy-8 then
   local kind=widget.u.profession==df.profession.CHILD and 'child' or widget.u.profession==df.profession.BABY and 'baby' or 'adult'
   for _,child in ipairs(dfhack.gui.getWidgetChildren(widget.parent))do
    if child.name=='Specialization button' and not targets[kind] then targets[kind]={unit=widget.u,button=child}end
   end
  end
  if df.widget_container:is_instance(widget)then for _,child in ipairs(dfhack.gui.getWidgetChildren(widget))do collect(child,active)end end
 end
 collect(active_list,true)
 local function snapshot(unit)
  local labors={};for i=0,#unit.status.labors-1 do labors[#labors+1]=unit.status.labors[i]end
  local _,address=df.sizeof(unit)
  return {only_assigned=unit.flags4.only_do_assigned_jobs,labors=labors,pickup_flags=df.reinterpret_cast('uint32_t',address+0x280).value}
 end
 local function restore(unit,value)
  unit.flags4.only_do_assigned_jobs=value.only_assigned
  local _,address=df.sizeof(unit);df.reinterpret_cast('uint32_t',address+0x280).value=value.pickup_flags
  for i,value in ipairs(value.labors)do unit.status.labors[i-1]=value end
 end
 local function read(unit,revision,value)
  local args={'df3d','residents-specialization',tostring(unit.id)}
  if revision then args[#args+1]=revision;args[#args+1]=value and '1' or '0'end
  local text,rc=dfhack.run_command_silent(table.unpack(args));assert(rc==0,text);return json.decode(text)
 end
 local evidence={}
 for _,kind in ipairs{'adult','child','baby'}do
  local target=assert(targets[kind],'Missing native specialization target '..kind)
  local unit,button=target.unit,target.button;local original=snapshot(unit)
  assert(not unit.job.current_job or unit.job.current_job.job_type~=51,'Equipment pickup cancellation requires a separate effect reference')
  local cases={}
  for direction=1,2 do
   local before=snapshot(unit);local receipt=read(unit)
   local g=df.global.gps;g.precise_mouse_x=button.rect.x1*8+12;g.precise_mouse_y=button.rect.y1*12+12
   g.mouse_x=button.rect.x1+1;g.mouse_y=button.rect.y1+1
   df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
   df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L')
   df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
   local native=snapshot(unit)
   assert(native.only_assigned~=before.only_assigned,'Native specialization click had no effect '..kind)
   restore(unit,before)
   local actual=read(unit,receipt.revision,native.only_assigned)
   assert(actual.outcome==0 and json.encode(snapshot(unit))==json.encode(native),'Native specialization effects differ '..kind)
   cases[#cases+1]={before=before,native=native,provider=actual}
  end
  restore(unit,original)
  evidence[#evidence+1]={kind=kind,id=unit.id,cases=cases,restored=json.encode(snapshot(unit))==json.encode(original)}
 end
 local file=assert(io.open(out..'/residents-specialization-reference.json','w'));file:write(json.encode(evidence));file:close()
end
if os.getenv('DF3D_RESIDENTS_QUERY')=='1' then
 assert(filter_box,'Native Residents filter missing')
 local function click(widget)
  local x=math.floor((widget.rect.x1+widget.rect.x2)/2);local y=math.floor((widget.rect.y1+widget.rect.y2)/2)
  local g=df.global.gps;g.precise_mouse_x=x*8+4;g.precise_mouse_y=y*12+6
  g.mouse_x=x;g.mouse_y=y
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
  df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L')
  df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
 end
 -- Returning from Stress restores Job's previous descending direction; a
 -- second click on the active Job header then switches it to ascending.
 click(headers.Job)
 for _=1,3 do script.sleep(1,'frames')end
 view:render(dfhack.getTickCount())
 click(headers.Job)
 for _=1,3 do script.sleep(1,'frames')end
 view:render(dfhack.getTickCount())
 local first=df.unit.find(snapshots[1].ids[1]);local first_name=first.name.first_name
 local queries={'PLAY',dfhack.df2utf(first_name),'Tâmol','tamol','no-matching-resident-zzq',''}
 for index,query in ipairs(queries)do
  click(filter_box)
  -- Native textbox editing consumes window events, not legacy STRING_A000.
  -- The protected host sends only to this lane's owned hidden DF window.
  local file=assert(io.open(out..'/residents-search-input.json','w'))
  file:write(json.encode({clear_count=#filter_box.str,text=query}));file:close()
  file=assert(io.open(out..'/owner-input-request.tmp','w'));file:write('residents-search');file:close()
  assert(os.rename(out..'/owner-input-request.tmp',out..'/owner-input-request'))
  local deadline=dfhack.getTickCount()+30000
  while true do
   local ack=io.open(out..'/owner-input-ack','r');if ack then ack:close();break end
   assert(dfhack.getTickCount()<deadline,'Residents native input timeout');script.sleep(1,'frames')
  end
  assert(os.remove(out..'/owner-input-ack'))
  for _=1,3 do script.sleep(1,'frames')end
  assert(filter_box.str==query,'Native filter did not receive typed query')
  view:render(dfhack.getTickCount());observe('Job-search'..index,query)
 end
end
local file=assert(io.open(out..'/residents-list-reference.json','w'))
file:write(json.encode({mode=info.creatures.current_mode,lists=lists,snapshots=snapshots}));file:close()
for _,snapshot in ipairs(snapshots)do assert(snapshot.matches~=false,'Residents order differs: '..snapshot.name)end
file=assert(io.open(out..'/shot.tmp','w'));file:write('residents-root');file:close()
assert(os.rename(out..'/shot.tmp',out..'/shot'))
local deadline=dfhack.getTickCount()+30000
while true do
 local ack=io.open(out..'/ack-residents-root');if ack then ack:close();break end
 assert(dfhack.getTickCount()<deadline,'Residents capture timeout');script.sleep(1,'frames')
end
records[#records+1]={name='residents-native-discovery',lists=#lists,mode=info.creatures.current_mode}
