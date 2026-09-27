-- Native assertions only; DF3D work-order intents belong to the Godot driver.
local out,index=...
local json=require('json')
local function read(path)
 local f=io.open(path,'r');if not f then return nil end
 local s=f:read('*a');f:close();return s
end
if index=='pause' then df.global.pause_state=true;print('SEMANTIC_PASS paused');return end
if index=='final' then assert(df.global.d_init.feature.autosave==df.d_init_autosave.NONE,'autosave must remain disabled');assert(df.global.pause_state,'DF must be paused before teardown');print('SEMANTIC_PASS final paused');return end
if index=='restore_prefs' then
 local saved=_G.df3d_work_orders_acceptance_prefs
 if saved then
  assert(df.global.pause_state,'DF must be paused before restoring fixture preferences')
  df.global.d_init.feature.autosave=saved.autosave
  for id,whole in pairs(saved.announcements)do df.global.d_init.announcements.flags[id].whole=whole end
  _G.df3d_work_orders_acceptance_prefs=nil
 end
 print('SEMANTIC_PASS restored fixture preferences');return
end
local state=assert(df3d_work_orders_acceptance,'fixture missing')
local request=json.decode(assert(read(out..'/request-'..index..'.json')))
local result={status='passed'}
local function incomplete(reason) result.status='incomplete';result.reason=reason end
local function orders() return df.global.world.manager_orders.all end
local function order(id)
 for _,o in ipairs(orders()) do if o.id==id then return o end end
end
local function jobs(id)
 local rows={};local link=df.global.world.jobs.list.next
 while link do local j=link.item
  if j and j.order_id==id then rows[#rows+1]=j.id end
  link=link.next
 end
 return rows
end
local function fingerprint()
 -- Length-delimited scalar serialization, preserving vector order and every
 -- mutable order/condition/input field used by the adapter's revision contract.
 local parts={}
 local function add(v) local s=tostring(v);parts[#parts+1]=#s..':'..s end
 local function fields(o,names) for name in names:gmatch('%S+') do add(o[name]) end end
 add(df.global.world.manager_orders.manager_order_next_id);add(#orders())
 for _,o in ipairs(orders()) do
  fields(o,'id job_type item_type item_subtype reaction_name mat_type mat_index amount_left amount_total frequency finished_year finished_year_tick workshop_id max_workshops')
  add(o.status.whole);add(o.material_category.whole);add(o.specflag.whole);add(o.specdata.hist_figure_id)
  fields(o.art_spec,'type id subid')
  add(#o.item_conditions)
  for _,c in ipairs(o.item_conditions) do
   fields(c,'compare_type compare_val item_type item_subtype mat_type mat_index flags4 flags5 reaction_class has_material_reaction_product metal_ore min_dimension reaction_id has_tool_use dye_color')
   add(c.flags1.whole);add(c.flags2.whole);add(c.flags3.whole)
   add(#c.contains);for _,v in ipairs(c.contains) do add(v) end
  end
  add(#o.order_conditions)
  for _,c in ipairs(o.order_conditions) do fields(c,'order_id condition');add(c.flags.whole) end
  add(o.items~=nil)
  if o.items then
   add(#o.items.elements)
   for _,f in ipairs(o.items.elements) do
    fields(f,'item_type item_subtype mat_type mat_index quantity vector_id flags4 flags5 metal_ore reaction_class has_material_reaction_product min_dimension reagent_index reaction_id has_tool_use dye_color job_details_mat_type job_details_mat_index')
    add(f.flags1.whole);add(f.flags2.whole);add(f.flags3.whole);add(f.job_details_flags.whole);add(f.job_details_item_flags2.whole)
    add(#f.contains);for _,v in ipairs(f.contains) do add(v) end
   end
  end
  local ids=jobs(o.id);add(#ids);for _,id in ipairs(ids) do add(id) end
 end
 return table.concat(parts)
end
local function tick() return df.global.cur_year*403200+df.global.cur_year_tick end
local function catalog()
 local dump=read(out..'/../evidence/native/work_orders/f_new_order_list.txt')
 local actual=read(out..'/tasks.tsv')
 local fixture=json.decode(assert(read(out..'/fixture.json')))
 local source=read(out..'/source-save-id.txt') or ''
 local differences={}
 if not dump then differences[#differences+1]='missing f_new_order_list.txt' end
 if not actual then differences[#differences+1]='missing tasks.tsv' end
 if source~='region5' or not fixture.fort:lower():find('baldmirror',1,true) then
  differences[#differences+1]='catalog provenance is not exact region5 source / Baldmirror'
 end
 local function split(line) local cells={};for cell in (line..'\t'):gmatch('(.-)\t') do cells[#cells+1]=cell end;return cells end
 local function key(name,job,reaction,item,sub,mt,mi)
  return table.concat({name,tostring(job),reaction,tostring(item),tostring(sub),tostring(mt),tostring(mi)},'\t')
 end
 local counts={}
 if dump and actual then
  local expected_count,actual_count=0,0
  for line in dump:gmatch('[^\r\n]+') do
   if line:match('^%d+\t') then
    local c=split(line);local item,sub=c[6]:match('^(.-)/(-?%d+)$');local mt,mi=c[7]:match('^(-?%d+)/(-?%d+)$')
    assert(item and mt,'unrecognized native dump row')
    local job=df.job_type[c[4]];local typ=df.item_type[item]
    assert(job and typ,'unrecognized native dump enum')
    local k=key(c[3],job,c[5],typ,tonumber(sub),tonumber(mt),tonumber(mi))
    counts[k]=(counts[k] or 0)+1;expected_count=expected_count+1
   end
  end
  for line in actual:gmatch('[^\r\n]+') do
   local c=split(line)
   assert(#c==7,'unrecognized tasks.tsv row')
   local k=key(c[1],tonumber(c[2]),c[3],tonumber(c[4]),tonumber(c[5]),tonumber(c[6]),tonumber(c[7]))
   counts[k]=(counts[k] or 0)-1;actual_count=actual_count+1
  end
  if expected_count==0 or actual_count==0 then differences[#differences+1]='empty catalog input' end
  local keys={};for k,n in pairs(counts) do if n~=0 then keys[#keys+1]=k end end;table.sort(keys)
  for _,k in ipairs(keys) do differences[#differences+1]=string.format('%+d\t%s',counts[k],k) end
  result.expected_count=expected_count;result.actual_count=actual_count
 end
 local f=assert(io.open(out..'/catalog-diff.txt','w'));f:write(table.concat(differences,'\n'));f:close()
 if #differences>0 then incomplete('step 11 catalog: '..#differences..' differences/prerequisites; see catalog-diff.txt') end
end
local function verify()
 local op=request.op
 if op=='status' then
  local s=json.decode(assert(read(out..'/status-'..index..'.json')))
  result.holding=s.holding;result.steps=s.steps;assert(s.steps<=2048,'builder exceeded 2048 steps')
 elseif op=='create' then
  local o=assert(order(request.id),'created order absent')
  assert(o.amount_total==10 and o.amount_left==10 and o.frequency==df.workquota_frequency_type.OneTime and not o.status.validated,'create defaults differ')
  assert(orders()[#orders()-1].id==o.id,'created order not appended')
  state.created=state.created or {};state.created[o.id]={remaining=o.amount_left,tick=tick()}
 elseif op=='item' then
  local o=assert(order(request.id));local c=assert(o.item_conditions[0])
  assert(o.frequency==df.workquota_frequency_type.Daily,'first item condition must switch Daily')
  assert(c.mat_type==request.mat_type and c.mat_index==request.mat_index,'condition material mismatch')
  local actual={}
  for word=1,5 do
   local flags=math.tointeger(word<=3 and c['flags'..word].whole or c['flags'..word])
   for bit=0,31 do if (flags & (1 << bit))~=0 then actual[#actual+1]='f'..word..':'..bit end end
  end
  for _,v in ipairs{{'rc:',c.reaction_class},{'rp:',c.has_material_reaction_product}}do
   if v[2]~='' then actual[#actual+1]=v[1]..v[2]end
  end
  for _,v in ipairs{{'ore:',c.metal_ore},{'tool:',c.has_tool_use},{'dye:',c.dye_color}}do
   if v[2]>=0 then actual[#actual+1]=v[1]..v[2]end
  end
  table.sort(actual);table.sort(request.traits)
  assert(table.concat(actual,'\n')==table.concat(request.traits,'\n'),'native condition traits mismatch')
 elseif op=='removed' then
  local o=assert(order(request.id));assert(#(request.kind==0 and o.item_conditions or o.order_conditions)==0,'condition remains')
 elseif op=='dependency' then
  local o=assert(order(request.id));assert(#o.order_conditions==1 and o.order_conditions[0].order_id==request.target,'dependency mismatch')
  assert(o.order_conditions[0].flags.satisfied==request.satisfied,'native dependency satisfaction mismatch')
 elseif op=='guard_before' then
  assert(df.global.pause_state);state.guard=fingerprint()
 elseif op=='guard_after' then
  assert(df.global.pause_state and state.guard==fingerprint(),'refused request mutated manager orders/jobs')
 elseif op=='move_before' then
  local o=assert(order(request.id));assert(o.status.active and #jobs(o.id)>0,'move requires active order with jobs')
  for i,v in ipairs(orders()) do if v.id==o.id then state.move={id=o.id,position=i,status=o.status.whole};break end end
 elseif op=='move_after' then
  local m=assert(state.move);local o=assert(order(m.id))
  assert(o.status.whole==m.status and orders()[m.position+request.direction].id==o.id,'move changed flags or wrong position')
 elseif op=='details' then
  local o=assert(order(request.id));local f=assert(o.items.elements[request.input_index])
  assert(f.job_details_mat_type==request.mat_type and f.job_details_mat_index==request.mat_index and f.job_details_flags.have_set_job_details,'native material input not edited')
 elseif op=='delete_before' then
  local o=assert(order(request.id));state.dead_jobs=jobs(o.id);state.dead_id=o.id;state.dead_order=o;state.dead_remaining=o.amount_left
  assert(#state.dead_jobs>0,'delete requires outstanding jobs')
  local dependent=assert(order(request.dependent))
  assert(#dependent.order_conditions==1 and dependent.order_conditions[0].order_id==o.id,'delete dependency absent')
  state.dependent_items=#dependent.item_conditions
 elseif op=='delete_after' then
  assert(not order(state.dead_id),'deleted order remains')
  assert(state.dead_order.amount_left==state.dead_remaining,'delete changed held order remaining')
  local dependent=assert(order(request.dependent));assert(#dependent.order_conditions==0 and #dependent.item_conditions==state.dependent_items,'dependent cleanup mismatch')
  local retained=jobs(state.dead_id);assert(#retained==#state.dead_jobs,'delete canceled generated jobs')
  for i,id in ipairs(retained) do assert(id==state.dead_jobs[i],'delete changed generated job identity') end
 elseif op=='wait_start' then
  result.dispatch=state.dispatch_diagnostics(order(request.id))
  assert(df.global.d_init.feature.autosave==df.d_init_autosave.NONE,'autosave must be disabled before ticks advance')
  local top=dfhack.gui.getCurViewscreen(true)
  local focus=dfhack.gui.getFocusStrings(top)
  local popups=df.global.world.status.popups
  if #popups>0 then
   incomplete('wait requires no announcement popups (count='..#popups..', first='..dfhack.df2utf(popups[0].text)..')');return
  end
  if not (df.viewscreen_dwarfmodest:is_instance(top) and #focus==1 and focus[1]=='dwarfmode/Default')then
   incomplete('wait requires default fortress screen; screen='..table.concat(focus,','));return
  end
  assert(df.global.pause_state,'wait must start paused')
  local kind=request.kind
  assert(kind=='validated' or kind=='jobs' or kind=='completed')
  if kind=='validated' then
   state.prepare_dispatch(assert(order(request.id),'dispatch order missing'))
   result.dispatch=state.dispatch_diagnostics(order(request.id))
   local d=result.dispatch
   if d.workshop.jobs~=0 or not d.worker.available or not d.worker.carpentry or not d.worker.reachable
    or d.material_count<d.required_materials or not d.manager.available or not d.manager.reachable
    or not d.office.active or d.office.owner~=state.manager then
    incomplete('dispatch prerequisites unavailable; see dispatch diagnostics');return
   end
  end
  state.wait={kind=kind,id=request.id,tick=tick(),wall=dfhack.getTickCount(),ticks=kind~='completed' and 3600 or 12000,ms=kind~='completed' and 600000 or 900000}
  result.waiting=true
 elseif op=='wait_poll' then
  local w=assert(state.wait);local o=order(w.id);local done=false
  if w.kind=='validated' then done=o and o.status.validated
  elseif w.kind=='jobs' then done=o and o.status.active and #jobs(w.id)>0
  else for _,id in ipairs(state.dead_jobs or {}) do
   local event=state.completed[id]
   if event and event.order_id==state.dead_id and event.tick>=w.tick then
    done=true;result.completed_job=id;break end
  end end
  result.ticks=tick()-w.tick;result.wall_ms=dfhack.getTickCount()-w.wall
  if done then
   result.waiting=false
  elseif df.global.pause_state then
   result.dispatch=state.dispatch_diagnostics(o)
   local focus=dfhack.gui.getFocusStrings(dfhack.gui.getCurViewscreen(true))
   result.waiting=false;incomplete('game paused mid-wait; screen='..table.concat(focus,',')..'; popup count='..#df.global.world.status.popups)
  elseif result.ticks<0 or result.ticks>=w.ticks or result.wall_ms>=w.ms then
   result.dispatch=state.dispatch_diagnostics(o)
   result.waiting=false;incomplete(w.kind..' wait cap hit ('..result.ticks..' ticks, '..result.wall_ms..' ms)')
  else result.waiting=true end
 elseif op=='wait_finish' then
  assert(df.global.pause_state,'wait assertions require semantic pause')
  local w=assert(state.wait);local o=order(w.id)
  if request.passed then
   if w.kind=='completed' then assert(state.dead_order.amount_left==state.dead_remaining,'completed detached job changed remaining')end
   if w.kind=='jobs' then
    local initial=assert(state.created[w.id],'dispatch requires recorded create state')
    local completed=false
    for _,event in pairs(state.completed)do if event.order_id==w.id and event.tick>=initial.tick then completed=true end end
    if completed then incomplete('dispatch remaining assertion obscured by completed jobs')
    else assert(o.amount_left==initial.remaining,'dispatch decremented remaining before completion')end
   end
  end
 elseif op=='catalog' then
  local ok,err=pcall(catalog)
  if not ok then
   local f=assert(io.open(out..'/catalog-diff.txt','w'));f:write('catalog input could not be compared: '..tostring(err));f:close()
   incomplete('step 11 catalog input could not be compared; see catalog-diff.txt')
  end
 elseif op=='final' then assert(df.global.d_init.feature.autosave==df.d_init_autosave.NONE,'autosave must remain disabled');assert(df.global.pause_state,'DF not paused at final verification')
 else error('unknown verification operation: '..tostring(op)) end
end
local ok,err=pcall(verify)
if not ok then df.global.pause_state=true;result.status='failed';result.reason=tostring(err) end
local f=assert(io.open(out..'/response-'..index..'.json','w'));f:write(json.encode(result));f:close()
print((result.status=='failed' and 'SEMANTIC_FAIL ' or result.status=='incomplete' and 'SEMANTIC_INCOMPLETE ' or 'SEMANTIC_PASS ')..request.op..' '..json.encode(result))
