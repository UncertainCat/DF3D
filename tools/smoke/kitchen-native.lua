-- Protected discovery only. Runtime adapters must own their inputs and storage.
local out,view,shot=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local g=df.global.gps;local base=dfhack.internal.getImageBase()
local function click(x,y)
 g.precise_mouse_x=x*8+4;g.precise_mouse_y=y*12+6;g.mouse_x=x;g.mouse_y=y
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L')
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
 for _=1,3 do script.sleep(1,'frames')end;view:render(dfhack.getTickCount())
end
local cold
if os.getenv('DF3D_KITCHEN_PROVIDER')=='1' then
 local text,code=dfhack.run_command_silent('df3d','kitchen-probe');assert(code==0,'Cold owned Kitchen provider rejected');cold=json.decode(text)
end
click(45,10)
local result={vtable={},callbacks={},rows={}}
local panel
local function find(widget)
 if df.labor_kitchen_interfacest:is_instance(widget) then panel=widget;return end
 if df.widget_container:is_instance(widget) then for _,child in ipairs(dfhack.gui.getWidgetChildren(widget))do find(child)end end
end
find(df.global.game.main_interface.info.labor)
assert(panel and (panel.flag.whole&3)==3,'Kitchen tab did not open')
local _,address=df.sizeof(panel);local vt=df.reinterpret_cast('uint64_t',address).value
for slot=0,7 do result.vtable[#result.vtable+1]=df.reinterpret_cast('uint64_t',vt+slot*8).value-base end
-- MSVC unordered_map's native list, observed in aggregation42af10 and renderer431ea0.
-- This is diagnostic menu evidence only; runtime must populate its own map.
result.known={}
local head=df.reinterpret_cast('uint64_t',address+0x188).value
local count=df.reinterpret_cast('uint64_t',address+0x190).value
assert(count<=65536 and head~=0,'Kitchen map bounds')
local node=df.reinterpret_cast('uint64_t',head).value
local visited={}
while node~=head do
 assert(node~=0 and not visited[node] and #result.known<count,'Kitchen map linkage')
 visited[node]=true
 local entry=df.reinterpret_cast(df.labor_kitchen_interface_food_entry,node+0x10)
 result.known[#result.known+1]={type=entry.first.type,subtype=entry.first.subtype,mat=entry.first.mat,matg=entry.first.matg,count=entry.second.num,capabilities=entry.second.canrest,name=dfhack.df2utf(entry.second.name)}
 node=df.reinterpret_cast('uint64_t',node).value
end
assert(#result.known==count,'Kitchen map count differs')
if cold then
 local function key(row)return table.concat({row.type,row.subtype,row.mat,row.matg},':')end
 local expected={};for _,row in ipairs(result.known)do expected[key(row)]=row end
 assert(#cold==#result.known,'Owned Kitchen row count differs')
 for _,row in ipairs(cold)do local native=assert(expected[key(row)],'Owned Kitchen unexpected material');assert(json.encode(row)==json.encode(native),'Owned Kitchen aggregate differs');expected[key(row)]=nil end
 assert(next(expected)==nil,'Owned Kitchen missing material')
 result.provider={rows=#cold,cold=true,matched=true}
end

result.category=panel.current_category;result.type_filter=panel.filter_type;result.perm_filter=panel.filter_perm
result.filter=dfhack.df2utf(panel.filter_str);result.cursor=panel.cursor_idx;result.sorts={}
for _,entry in ipairs(panel.sorting_by)do result.sorts[#result.sorts+1]=entry.ident end
local function callbacks(widget,name,vector,stride)
 local _,at=df.sizeof(vector);local first=df.reinterpret_cast('uint64_t',at).value;local last=df.reinterpret_cast('uint64_t',at+8).value
 assert(last>=first and (last-first)%stride==0 and last-first<=262144,'Kitchen callback vector bounds')
 for ptr=first,last-1,stride do
  local context=df.reinterpret_cast('uint64_t',ptr+56).value
  if context~=0 then
   local table=df.reinterpret_cast('uint64_t',context).value
   result.callbacks[#result.callbacks+1]={name=widget.name,kind=name,rect={widget.rect.x1,widget.rect.y1,widget.rect.x2,widget.rect.y2},rva=df.reinterpret_cast('uint64_t',table+16).value-base}
  end
 end
end
local function walk(widget,depth)
 assert(depth<32,'Kitchen widget recursion bound')
 if (widget.flag.whole&1)==0 then return end
 for _,kind in ipairs({'custom_activated','custom_feed','custom_logic','custom_render'})do callbacks(widget,kind,widget[kind],64)end
 if df.widget_text:is_instance(widget) and (widget.flag.whole&2)~=0 then
  result.rows[#result.rows+1]={text=dfhack.df2utf(widget.str),rect={widget.rect.x1,widget.rect.y1,widget.rect.x2,widget.rect.y2},color={widget.fg,widget.bg,widget.bright}}
 end
 if df.widget_container:is_instance(widget)then
  for index,child in ipairs(dfhack.gui.getWidgetChildren(widget))do
   if not df.widget_tabs:is_instance(widget) or index-1==widget.cur_idx then walk(child,depth+1)end
  end
 end
end
walk(panel,0)
callbacks(panel,'sorting_by',panel.sorting_by,96)
callbacks(panel,'filter_func',panel.filter_func,64)
local capture=debug.getinfo(1,'S').source:sub(2):gsub('smoke/kitchen%-native.lua$','ui_bake/capture_widgets.lua')
assert(loadfile(capture))(out..'/kitchen-widgets.json','templates')
local file=assert(io.open(out..'/kitchen-native.json','w'));file:write(json.encode(result));file:close()
shot('kitchen-root')
if os.getenv('DF3D_KITCHEN_SORT')=='1' then
 local observations={}
 local function observe(label)
  local known={};for _,row in ipairs(result.known)do known[row.name]=true end
  local names={}
  local function collect(widget)
   if df.widget_text:is_instance(widget)then local name=dfhack.df2utf(widget.str);if known[name]then names[#names+1]=name end end
   if df.widget_container:is_instance(widget)then for _,child in ipairs(dfhack.gui.getWidgetChildren(widget))do collect(child)end end
  end
  collect(panel)
  assert(#names==#result.known,'Sort capture must include every constructed row')
  local sorts={}
  local _,vector=df.sizeof(panel.sorting_by);local first=df.reinterpret_cast('uint64_t',vector).value
  for i,entry in ipairs(panel.sorting_by)do
   local context=df.reinterpret_cast('uint64_t',first+i*96+56).value
   local vt=df.reinterpret_cast('uint64_t',context).value
   sorts[#sorts+1]={name=entry.ident,rva=df.reinterpret_cast('uint64_t',vt+16).value-base}
  end
  local directions={};local head=df.reinterpret_cast('uint64_t',address+0x1e0).value
  local node=df.reinterpret_cast('uint64_t',head).value;local n=0
  while node~=head do
   assert(n<5,'Sort direction bounds');n=n+1
   local length=df.reinterpret_cast('uint64_t',node+0x20).value
   assert(length<=15,'Sort identifier must fit native inline string')
   local chars={};for i=0,length-1 do chars[#chars+1]=string.char(df.reinterpret_cast('uint8_t',node+0x10+i).value)end
   local key=table.concat(chars)
   directions[key]=df.reinterpret_cast('int8_t',node+0x30).value
   node=df.reinterpret_cast('uint64_t',node).value
  end
  observations[#observations+1]={label=label,names=names,sorts=sorts,directions=directions}
  if os.getenv('DF3D_KITCHEN_SORT_PROVIDER')=='1' then
   assert(#sorts==1,'Single-column provider diagnostic')
   local columns={Type=0,Name=1,Number=2,Cook=3,Brew=4};local name=sorts[1].name
   local text,code=dfhack.run_command_silent('df3d','kitchen-probe','-1','0','',tostring(columns[name]),tostring(directions[name]));assert(code==0,'Owned sort rejected')
   local rows=json.decode(text);local actual={};for _,row in ipairs(rows)do actual[#actual+1]=row.name end
   assert(json.encode(actual)==json.encode(names),'Owned Kitchen sort differs: '..label)
   observations[#observations].provider_matched=true
  end
 end
 observe('initial')
 for _,column in ipairs({{'Name',28},{'Number',80},{'Cook',90},{'Brew',94},{'Type',18}})do
  click(column[2],15);observe(column[1]..' first')
  click(column[2],15);observe(column[1]..' second')
 end
 local f=assert(io.open(out..'/kitchen-sort.json','w'));f:write(json.encode(observations));f:close()
end
if os.getenv('DF3D_KITCHEN_EDITS')=='1' then
 local function snapshot()
  local k=df.global.plotinfo.kitchen;local exclusions={};local jobs={}
  for i,t in ipairs(k.item_types)do exclusions[#exclusions+1]={type=t,subtype=k.item_subtypes[i],mat=k.mat_types[i],matg=k.mat_indices[i],flags=k.exc_types[i].whole}end
  for _,job in require('utils').listpairs(df.global.world.jobs.list)do
   local items={};for _,ref in ipairs(job.items)do items[#items+1]={id=ref.item.id,role=ref.role,job_item_idx=ref.job_item_idx}end
   jobs[#jobs+1]={id=job.id,type=job.job_type,flags=job.flags.whole,items=items}
  end
  return {exclusions=exclusions,jobs=jobs}
 end
 local edits={before=snapshot(),steps={}}
 panel.filter_type=-1;panel.filter_perm=0;panel.filter_str='plump';panel.sort_flags=panel.sort_flags|1
 -- The redraw builds replacement rows; a later layout pass places them.
 for _=1,3 do script.sleep(1,'frames');view:render(dfhack.getTickCount())end
 for _,step in ipairs({{'Plump helmet spawn',1},{'Plump helmets',2},{'Plump helmets',1},{'Plump helmets',1},{'Plump helmets',2},{'Plump helmet spawn',1}})do
  local y
  local function locate(widget)
   if df.widget_text:is_instance(widget) and dfhack.df2utf(widget.str)==step[1]then y=widget.rect.y1 end
   if df.widget_container:is_instance(widget)then for _,child in ipairs(dfhack.gui.getWidgetChildren(widget))do locate(child)end end
  end
  locate(panel);assert(y,'Native Kitchen edit row missing')
  click(step[2]==1 and 90 or 94,y)
  edits.steps[#edits.steps+1]={name=step[1],flag=step[2],state=snapshot()}
 end
 local f=assert(io.open(out..'/kitchen-edits.json','w'));f:write(json.encode(edits));f:close()
 local function membership(values)local rows={};for _,row in ipairs(values)do rows[#rows+1]=json.encode(row)end;table.sort(rows);return json.encode(rows)end
 assert(membership(edits.before.exclusions)==membership(edits.steps[#edits.steps].state.exclusions),'Kitchen exclusion membership not restored')
 if os.getenv('DF3D_KITCHEN_EDIT_PROVIDER')=='1' then
  edits.provider={}
  for index,step in ipairs(edits.steps)do
   local target;for _,row in ipairs(result.known)do if row.name==step.name then target=row end end;assert(target,'Owned edit target missing')
   local receipt=json.encode({target=target,exclusions=snapshot().exclusions})
   local text,code=dfhack.run_command_silent('df3d','kitchen-edit-probe',tostring(step.flag),receipt);assert(code==0,'Owned edit command rejected')
   local reply=json.decode(text);assert(reply.outcome==1 and reply.write_started,'Owned edit did not apply')
   local current=snapshot()
   assert(membership(current.exclusions)==membership(step.state.exclusions),'Owned edit permissions differ')
   assert(json.encode(current.jobs)==json.encode(step.state.jobs),'Owned edit job state differs')
   if index==1 then
    local stale,stale_code=dfhack.run_command_silent('df3d','kitchen-edit-probe',tostring(step.flag),receipt);assert(stale_code==0,'Stale edit diagnostic failed')
    stale=json.decode(stale);assert(stale.outcome==2 and not stale.write_started,'Stale Kitchen receipt accepted')
    assert(json.encode(snapshot())==json.encode(current),'Stale Kitchen edit changed simulation')
   end
   edits.provider[#edits.provider+1]={name=step.name,flag=step.flag,matched=true}
  end
  local f=assert(io.open(out..'/kitchen-edits.json','w'));f:write(json.encode(edits));f:close()
 end
 panel.filter_str='';panel.sort_flags=panel.sort_flags|1
 for _=1,3 do script.sleep(1,'frames')end;view:render(dfhack.getTickCount())
end
if os.getenv('DF3D_KITCHEN_FILTER')=='1' then
 local cases={{-1,0,'plump'},{0,0,'plump'},{1,0,'PLUMP'},{2,0,'plump'},{3,0,'plump'},{-1,1,'plump'},{-1,2,'plump'},{-1,3,'plump'},{-1,0,'no matching kitchen entry'}}
 local results={}
 for _,case in ipairs(cases)do
  -- Controlled native redraw; input-widget behavior is a separate acceptance.
  panel.filter_type=case[1];panel.filter_perm=case[2];panel.filter_str=case[3]:lower();panel.sort_flags=panel.sort_flags|1
  for _=1,3 do script.sleep(1,'frames')end;view:render(dfhack.getTickCount())
  local names={}
  local function collect(widget)
   if (widget.flag.whole&3)~=3 then return end
   if df.widget_text:is_instance(widget) and widget.rect.x1==15 and widget.rect.y1>=16 then names[#names+1]=dfhack.df2utf(widget.str)end
   if df.widget_container:is_instance(widget)then for _,child in ipairs(dfhack.gui.getWidgetChildren(widget))do collect(child)end end
  end
  collect(panel);table.sort(names)
  local text,code=dfhack.run_command_silent('df3d','kitchen-probe',tostring(case[1]),tostring(case[2]),case[3]);assert(code==0,'Owned filter rejected')
  local rows=json.decode(text);assert(#rows<13,'Filter comparison must fit visible native rows')
  local actual={};for _,row in ipairs(rows)do actual[#actual+1]=row.name end;table.sort(actual)
  assert(json.encode(actual)==json.encode(names),'Owned Kitchen filter differs from native redraw: '..json.encode(case)..' '..json.encode(actual)..' '..json.encode(names))
  results[#results+1]={type=case[1],capabilities=case[2],query=case[3],names=names}
 end
 local f=assert(io.open(out..'/kitchen-filter.json','w'));f:write(json.encode(results));f:close()
 panel.filter_type=-1;panel.filter_perm=0;panel.filter_str='';panel.sort_flags=panel.sort_flags|1
 for _=1,3 do script.sleep(1,'frames')end;view:render(dfhack.getTickCount())
end
if os.getenv('DF3D_KITCHEN_JOB_EFFECTS')=='1' then
 local path=debug.getinfo(1,'S').source:sub(2):gsub('kitchen%-native.lua$','kitchen-job-effects-native.lua')
 assert(loadfile(path))(out,view,panel,click,result.known)
end
click(30,10)
return {rows=#result.rows,callbacks=#result.callbacks}
