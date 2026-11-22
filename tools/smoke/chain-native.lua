-- Protected native oracle only; no widget storage is used by the product.
local out,view,chain,capture=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local main=df.global.game.main_interface
local function snapshot()
 local jobs={};for _,job in ipairs(chain.jobs)do jobs[#jobs+1]={id=job.id,type=df.job_type[job.job_type]}end
 return {assigned=chain.assigned and chain.assigned.id or -1,chained=chain.chained and chain.chained.id or -1,flags=chain.chain_flags.whole,jobs=jobs}
end
local before=snapshot();assert(not chain:isJusticeRestraint(),'Chain discovery requires ordinary restraint')
local count=chain.assigned and 1 or 0;if chain.chained and chain.chained~=chain.assigned then count=count+1 end
local function click(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
end
click(448,154+36*count)
assert(main.unit_selector.context==df.unit_selector_context_type.CHAIN_ASSIGNMENT and main.view_sheets.active_id==chain.id,'Chain picker did not open')
capture('chain-assignment-click');view:render(dfhack.getTickCount());capture('chain-assignment-open')
local function find_list(widget,depth)
 assert(depth<10)
 if df.widget_unit_list:is_instance(widget)then return df.reinterpret_cast(df.widget_unit_list,widget)end
 if not df.widget_container:is_instance(widget)then return end
 local _,address=df.sizeof(df.reinterpret_cast(df.widget_container,widget).children)
 local first=df.reinterpret_cast('uint64_t',address).value;local last=df.reinterpret_cast('uint64_t',address+8).value
 assert(last>=first and (last-first)%16==0 and last-first<=65536)
 for at=first,last-1,16 do
  local ptr=df.reinterpret_cast('uint64_t',at).value
  if ptr~=0 then local list=find_list(df.reinterpret_cast(df.widget,ptr),depth+1);if list then return list end end
 end
end
local list=assert(find_list(main.unit_selector,0));local entries={}
for _,entry in ipairs(list.entry_list)do
 local row={kind=entry.t,id=entry.t==0 and entry.u and entry.u.id or entry.t==1 and entry.i and entry.i.id or -1}
 if entry.t==0 and entry.u then row.name=dfhack.df2utf(dfhack.units.getReadableName(entry.u));row.flags1=entry.u.flags1.whole;row.flags2=entry.u.flags2.whole end
 entries[#entries+1]=row
end
local function callback_at(address)
 local context=df.reinterpret_cast('uint64_t',address+56).value
 if context==0 then return {}end
 local vtable=df.reinterpret_cast('uint64_t',context).value
 return {invoke_rva=df.reinterpret_cast('uint64_t',vtable+16).value-dfhack.internal.getImageBase()}
end
local callbacks={}
for _,field in ipairs{'filter_func','always_sorting_by','partitions','on_select_change','preprocess_unit_func','postprocess_unit_func'}do
 local _,address=df.sizeof(list[field]);local first=df.reinterpret_cast('uint64_t',address).value;local last=df.reinterpret_cast('uint64_t',address+8).value
 assert(last>=first and (last-first)%64==0 and last-first<=65536)
 local rows={};for at=first,last-1,64 do rows[#rows+1]=callback_at(at)end;callbacks[field]=rows
end
local _,address=df.sizeof(list.is_selected);callbacks.is_selected=callback_at(address)
local visible={}
local function walk(widget,depth,active)
 assert(depth<10)
 active=active and (widget.flag.whole&1)~=0
 if active and df.widget_unit_name:is_instance(widget)then
  local name=df.reinterpret_cast(df.widget_unit_name,widget)
  visible[#visible+1]={id=name.u.id,x=widget.rect.x1,y=widget.rect.y1,x2=widget.rect.x2,y2=widget.rect.y2}
 end
 if not df.widget_container:is_instance(widget)then return end
 local _,address=df.sizeof(df.reinterpret_cast(df.widget_container,widget).children)
 local first=df.reinterpret_cast('uint64_t',address).value;local last=df.reinterpret_cast('uint64_t',address+8).value
 assert(last>=first and (last-first)%16==0 and last-first<=65536)
 for at=first,last-1,16 do local ptr=df.reinterpret_cast('uint64_t',at).value;if ptr~=0 then walk(df.reinterpret_cast(df.widget,ptr),depth+1,active)end end
end
walk(main.unit_selector,0,true)
local function read_owned()
 return dfhack.with_suspend(function()
  local guards={}
  for _,value in ipairs{g,main}do local size,address=df.sizeof(value);local copy=df.new('uint8_t',size);dfhack.internal.memmove(copy,address,size);guards[#guards+1]={size=size,address=address,copy=copy}end
  local text,code=dfhack.run_command_silent('df3d','chain-candidates-read',tostring(chain.id));assert(code==0,text)
  for _,guard in ipairs(guards)do assert(dfhack.internal.memcmp(guard.copy,guard.address,guard.size)==0,'Chain read changed native UI storage');df.delete(guard.copy)end
  return json.decode(text)
 end)
end
local owned=read_owned();local ids={};for _,row in ipairs(owned)do assert(not ids[row.id]);ids[row.id]=true end
assert(#owned==#visible and #visible>0,'Chain candidate count differs from visible native rows')
for _,row in ipairs(visible)do assert(ids[row.id],'Native chain row missing from owned candidates')end
local result={building_id=chain.id,before=before,context=main.unit_selector.context,legacy_selector_building_id=main.unit_selector.bld_id,entries=entries,callbacks=callbacks,visible=visible,owned=owned,ui_unchanged=true}
if os.getenv('DF3D_CHAIN_EFFECTS')=='1' then
 assert(before.assigned==-1 and before.chained==-1 and #before.jobs==0)
 local function contains(values,id)for _,v in ipairs(values)do if v==id then return true end end;return false end
 local function unassigned(unit)
  for _,b in ipairs(df.global.world.buildings.other.CAGE)do if contains(b.assigned_units,unit.id)then return false end end
  for _,b in ipairs(df.global.world.buildings.other.ANY_ZONE)do if contains(b.assigned_units,unit.id)then return false end end
  for _,b in ipairs(df.global.world.buildings.other.CHAIN)do if b.assigned==unit or b.chained==unit then return false end end
  return true
 end
 local chosen
 for _,row in ipairs(visible)do local unit=assert(df.unit.find(row.id));if unassigned(unit)then chosen=row;break end end
 assert(chosen,'No unassigned visible native chain candidate')
 local unit=assert(df.unit.find(chosen.id));local flags1,flags2=unit.flags1.whole,unit.flags2.whole
 click(200,(chosen.y-1)*12+6)
 assert(chain.assigned==unit and not chain.chained and #chain.jobs==0,'Chain native selection effect differs')
 capture('chain-assignment-selected')
 for _,row in ipairs(read_owned())do assert(row.id~=unit.id,'Assigned unit retained in chain picker candidates')end
 result.selection={unit_id=unit.id,after=snapshot()}
 click(864,154);assert(not chain.assigned and not chain.chained and #chain.jobs==0,'Chain native row removal differs')
 capture('chain-assignment-removed')
 assert(unit.flags1.whole==flags1 and unit.flags2.whole==flags2 and unassigned(unit),'Chain roundtrip changed original unit facts')
 result.selection.restored=true
 if os.getenv('DF3D_CHAIN_OWNED_EFFECTS')=='1' then
  local function probe(revision,id,toggle)
   return dfhack.with_suspend(function()
    local guards={}
    for _,value in ipairs{g,main}do local size,address=df.sizeof(value);local copy=df.new('uint8_t',size);dfhack.internal.memmove(copy,address,size);guards[#guards+1]={size=size,address=address,copy=copy}end
    local args={'df3d','chain-state-probe',tostring(chain.id)}
    if revision then args[#args+1]=revision;args[#args+1]=tostring(id);args[#args+1]=tostring(toggle)end
    local text,code=dfhack.run_command_silent(table.unpack(args));assert(code==0,text)
    for _,guard in ipairs(guards)do assert(dfhack.internal.memcmp(guard.copy,guard.address,guard.size)==0,'Chain edit changed native UI storage');df.delete(guard.copy)end
    return json.decode(text)
   end)
  end
  local initial=probe()
  local invalid=probe(initial.revision,-1,0);assert(invalid.outcome==0 and not invalid.effects_started)
  local selected=probe(initial.revision,unit.id,0)
  assert(selected.outcome==1 and selected.effects_started and selected.assigned_id==unit.id)
  assert(json.encode(snapshot())==json.encode(result.selection.after),'Owned chain selection differs from native')
  local stale=probe(initial.revision,unit.id,1);assert(stale.outcome==2 and not stale.effects_started and chain.assigned==unit)
  local removed=probe(selected.revision,unit.id,1)
  assert(removed.outcome==1 and removed.effects_started and removed.assigned_id==-1)
  assert(json.encode(snapshot())==json.encode(before),'Owned chain removal differs from native')
  assert(unit.flags1.whole==flags1 and unit.flags2.whole==flags2 and unassigned(unit),'Owned chain roundtrip changed original unit facts')
  result.owned_effects={initial=initial,invalid=invalid,selected=selected,stale=stale,removed=removed,ui_unchanged=true}
 end
else
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());capture('chain-assignment-closed')
end
result.after=snapshot();assert(json.encode(before)==json.encode(result.after),'Chain picker changed simulation')
result.success=true
local f=assert(io.open(out..'/chain-native.json','w'));f:write(json.encode(result));f:close()
return result
