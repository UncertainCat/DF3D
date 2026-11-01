-- Native Health page oracle in the owned unsaved clone.
local unit,view,capture,out=...
local gui=require('gui');local json=require('json')
local g=df.global.gps;local sheet=df.global.game.main_interface.view_sheets
local frame=df.global.world.frame_counter;local original=sheet.active_sub_tab
local function row(y)
 local text={};for x=0,g.dimx-1 do local p=dfhack.screen.readTile(x,y);text[#text+1]=p.ch>=32 and string.char(p.ch%256) or ' ' end
 return table.concat(text)
end
local function click(x,y)
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
end
local base=dfhack.internal.getImageBase()
local entity=assert(df.global.plotinfo.main.fortress_entity)
local _,entity_address=df.sizeof(entity)
assert(df.reinterpret_cast('uint64_t',base+0x239a1e8).value==entity_address,'Health fortress entity global differs')
local function native_string(value)
 if type(value)=='string'then return dfhack.df2utf(value)end
 local _,address=df.sizeof(value)
 local size=df.reinterpret_cast('uint64_t',address+16).value
 local capacity=df.reinterpret_cast('uint64_t',address+24).value
 assert(size>=0 and size<=65536 and capacity>=size,'Invalid native Health string')
 local data=capacity<16 and address or df.reinterpret_cast('uint64_t',address).value
 local bytes=df.new('uint8_t',math.max(1,size));dfhack.internal.memmove(bytes,data,size)
 local text={};for i=0,size-1 do text[#text+1]=string.char(bytes[i])end;df.delete(bytes)
 return dfhack.df2utf(table.concat(text))
end
local function probe(sample,name)
   local guards={}
   local function guard(address,size)
    if size==0 then return end;assert(size>0 and size<1048576,'Invalid Health guard size')
    local bytes=df.new('uint8_t',size);dfhack.internal.memmove(bytes,address,size)
    guards[#guards+1]={bytes=bytes,address=address,size=size}
   end
   for _,object in ipairs{unit,sheet,df.global.plotinfo,unit.health}do
    if object then local size,address=df.sizeof(object);guard(address,size)end
   end
   local vectors={unit.body.components.body_part_status,unit.body.wounds,unit.enemy.motor_nervenet,unit.enemy.sensory_nervenet,unit.enemy.body_part_useable}
   for _,vector in ipairs{unit.appearance.body_modifiers,unit.appearance.bp_modifiers,
    unit.appearance.tissue_style,unit.appearance.tissue_style_civ_id,unit.appearance.tissue_style_id,
    unit.appearance.tissue_style_type,unit.appearance.tissue_length,unit.appearance.colors,
    unit.uwss_body_modifier,unit.uwss_bp_modifer}do vectors[#vectors+1]=vector end
   for _,field in ipairs{'uwss_att_change','ghost_info'}do
    if unit[field]then local size,address=df.sizeof(unit[field]);guard(address,size)end
   end
   if unit.health then vectors[#vectors+1]=unit.health.body_part_flags end
   for _,vector in ipairs(vectors)do
    local _,address=df.sizeof(vector);local first=df.reinterpret_cast('uint64_t',address).value
    guard(first,df.reinterpret_cast('uint64_t',address+8).value-first)
   end
   for _,wound in ipairs(unit.body.wounds)do
    local size,address=df.sizeof(wound);guard(address,size)
    local _,vector_address=df.sizeof(wound.parts);local first=df.reinterpret_cast('uint64_t',vector_address).value
    guard(first,df.reinterpret_cast('uint64_t',vector_address+8).value-first)
    for _,part in ipairs(wound.parts)do
     size,address=df.sizeof(part);guard(address,size)
     for _,vector in ipairs{part.effect_perc1,part.effect_perc2,part.effect_type}do
      local _,va=df.sizeof(vector);local start=df.reinterpret_cast('uint64_t',va).value
      guard(start,df.reinterpret_cast('uint64_t',va+8).value-start)
     end
    end
   end
   if unit.health then
    for _,field in ipairs{'op_history','syndrome_diagnosis'}do
     for _,event in ipairs(unit.health[field])do
      local size,address=df.sizeof(event);guard(address,size)
      local worker=df.unit.find(field=='op_history' and event.doctor_id or event.worker_unid)
      if worker then size,address=df.sizeof(worker);guard(address,size)end
     end
    end
   end
   for _,range in ipairs{{0x234e990,0x6180},{0x2131b30,40},{0x2159084,2},{0x18adf98,8}}do guard(base+range[1],range[2])end
   local text,status=dfhack.run_command_silent('df3d','unit-health-page-probe',tostring(unit.id),name=='Status' and '0' or name=='Wounds' and '1' or name=='Treatment' and '2' or name=='History' and '3' or '4')
   local unchanged=true
   for _,g in ipairs(guards)do if dfhack.internal.memcmp(g.bytes,g.address,g.size)~=0 then unchanged=false end;df.delete(g.bytes)end
   assert(status==0,text);assert(unchanged,'Health probe changed guarded source/UI/random state')
   sample.probe=json.decode(text);sample.probe_guards_unchanged=unchanged
   assert(json.encode(sample.probe.rows)==json.encode(sample.tagged_rows),'Owned Health output differs: '..name)
end
local pages={}
local history_cases={}
local ok,err=xpcall(function()
 assert(sheet.open and sheet.active_id==unit.id,'Expected creature sheet')
 click(616,196)
 for _,name in ipairs{'Status','Wounds','Treatment','History','Description'}do
  local found=false
  for y=17,20 do
   local first,last=row(y):find(name,1,true)
   if first then click((first-1)*8+4,y*12+10);found=true;break end
  end
  assert(found,'Missing Health tab '..name)
  local sample={name=name,lines={},tagged_rows={}}
  for _,text in ipairs(sheet.unit_health_raw_str)do sample.tagged_rows[#sample.tagged_rows+1]=native_string(text)end
  sample.color_box_count=#sheet.unit_health_box
  if os.getenv('DF3D_UNIT_HEALTH_PROBE')=='1'then probe(sample,name)end
  for y=18,g.dimy-1 do local text=dfhack.df2utf(row(y)):gsub('%s+$','');if text~=''then sample.lines[#sample.lines+1]={y=y,text=text}end end
  pages[#pages+1]=sample
  capture('unit-health-page-'..name:lower())
 end
 if os.getenv('DF3D_UNIT_HEALTH_HISTORY_CASES')=='1'then
  local health=assert(unit.health);local operations={};local diagnoses={};local workers={}
  for _,event in ipairs(health.op_history)do
   operations[#operations+1]={event=event,year=event.year,time=event.year_time,worker=event.doctor_id}
  end
  for _,event in ipairs(health.syndrome_diagnosis)do
   diagnoses[#diagnoses+1]={event=event,year=event.year,time=event.season_count,worker=event.worker_unid}
  end
  for _,records in ipairs{operations,diagnoses}do for _,record in ipairs(records)do
   local worker=df.unit.find(record.worker)
   if worker and not workers[worker.id]then workers[worker.id]={unit=worker,cache=worker.enemy.histfig_vector_idx}end
  end end
  local function restore()
   health.op_history:resize(0);health.syndrome_diagnosis:resize(0)
   for _,r in ipairs(operations)do r.event.year=r.year;r.event.year_time=r.time;r.event.doctor_id=r.worker;health.op_history:insert('#',r.event)end
   for _,r in ipairs(diagnoses)do r.event.year=r.year;r.event.season_count=r.time;r.event.worker_unid=r.worker;health.syndrome_diagnosis:insert('#',r.event)end
   for _,r in pairs(workers)do r.unit.enemy.histfig_vector_idx=r.cache end
  end
  local function select(name)
   for y=17,20 do local first=row(y):find(name,1,true);if first then click((first-1)*8+4,y*12+10);return end end
   error('Missing Health case tab '..name)
  end
  local cases_ok,cases_error=xpcall(function()
   assert(#operations>1,'History variants require multiple operations')
   for _,case in ipairs{'empty','missing-caregivers','equal-timestamps','cold-caregiver-caches'}do
    restore()
    if case=='empty'then health.op_history:resize(0);health.syndrome_diagnosis:resize(0)
    elseif case=='missing-caregivers'then
     for _,r in ipairs(operations)do r.event.doctor_id=-1 end
     for _,r in ipairs(diagnoses)do r.event.worker_unid=-1 end
    elseif case=='equal-timestamps'then
     for _,r in ipairs(operations)do r.event.year=operations[1].year;r.event.year_time=operations[1].time end
     for _,r in ipairs(diagnoses)do r.event.year=operations[1].year;r.event.season_count=operations[1].time end
    end
    select('Status');select('History')
    local sample={name=case,tagged_rows={}}
    for _,text in ipairs(sheet.unit_health_raw_str)do sample.tagged_rows[#sample.tagged_rows+1]=native_string(text)end
    if case=='cold-caregiver-caches'then for _,r in pairs(workers)do r.unit.enemy.histfig_vector_idx=-1 end end
    probe(sample,'History');history_cases[#history_cases+1]=sample
   end
  end,debug.traceback)
  restore();select('Status');select('History')
  assert(cases_ok,cases_error)
 end
end,debug.traceback)
click(464,196)
assert(sheet.active_sub_tab==original,'Health reference did not return to Overview')
assert(df.global.pause_state and df.global.world.frame_counter==frame,'Health reference advanced simulation')
local result={success=ok,unit_id=unit.id,fortress_entity_global_verified=true,pages=pages,history_cases=history_cases,error=not ok and err or nil}
local file=assert(io.open(out..'/unit-health-pages-native.json','w'));file:write(json.encode(result));file:close()
assert(ok,err);return result
