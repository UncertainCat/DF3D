-- Native parent-body oracle, with reversible assignment through the owned API.
local out,view,cage,capture=...
local json=require('json');local g=df.global.gps
local frame=df.global.world.frame_counter;local flags=cage.cage_flags.whole
local function ids(v)local t={};for _,id in ipairs(v)do t[#t+1]=id end;return t end
local before={units=ids(cage.assigned_units),items=ids(cage.assigned_items)}
local result={id=cage.id,contained={},rooms={},cases={}}
assert(#cage.contained_items>0)
for _,ref in ipairs(cage.contained_items[0].item.general_refs)do
 if ref:getType()==df.general_ref_type.CONTAINS_UNIT then
  local u=ref:getUnit();result.contained[#result.contained+1]={entity=1,id=u and u.id or -1}
 elseif ref:getType()==df.general_ref_type.CONTAINS_ITEM then
  local item=ref:getItem();if item and item:isLiveAnimal()then result.contained[#result.contained+1]={entity=2,id=item.id}end
 end
end
for _,zone in ipairs(cage.relations)do
 local row={id=zone.id,type=zone.type,site_id=zone.site_id,location_id=zone.location_id}
 local site=df.world_site.find(zone.site_id)
 if site then for _,location in ipairs(site.buildings)do if location.id==zone.location_id then
  row.location_type=location:getType();local contents=location:getContents();row.location_tier=contents and contents.location_tier or -1
 end end end
 result.rooms[#result.rooms+1]=row
end
local function record(label)
 view:render(dfhack.getTickCount());capture('cage-body-'..label)
 local row={label=label,units=ids(cage.assigned_units),items=ids(cage.assigned_items),lines={}}
 if os.getenv('DF3D_CAGE_OCCUPANTS')=='1'then
  local guards={}
  for _,value in ipairs{df.global.gps,df.global.game.main_interface}do
   local size,address=df.sizeof(value);local copy=df.new('uint8_t',size)
   dfhack.internal.memmove(copy,address,size);guards[#guards+1]={copy=copy,address=address,size=size}
  end
  local text,code=dfhack.run_command_silent('df3d','cage-occupants-read',tostring(cage.id));assert(code==0,text)
  row.provider=json.decode(text)
  for _,guard in ipairs(guards)do
   assert(dfhack.internal.memcmp(guard.copy,guard.address,guard.size)==0,'Occupant provider changed native UI storage')
   df.delete(guard.copy)
  end
  assert(row.provider.building_id==cage.id and row.provider.revision>0)
  assert(#row.provider.rows==#result.contained+#row.units)
  for i,contained in ipairs(result.contained)do
   local actual=row.provider.rows[i]
   assert(actual.id==contained.id and actual.entity==contained.entity and actual.contained and actual.resolved)
   assert(actual.assigned and actual.status=='Occupant' and actual.status_color==10)
  end
  for i,unit in ipairs(row.units)do
   local actual=row.provider.rows[#result.contained+i]
   assert(actual.id==unit and actual.entity==1 and not actual.contained and actual.assigned and actual.resolved)
   assert(actual.status=='Assigned' and actual.status_color==15 and actual.name:find('Stray Drake',1,true))
  end
 end
 for y=8,31 do
  local chars={};for x=54,110 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
  local text=dfhack.df2utf(table.concat(chars)):gsub('%s+$','');if text:find('%S')then row.lines[#row.lines+1]={y=y,text=text}end
 end
 result.cases[#result.cases+1]=row
end
local function request(...)
 local text,code=dfhack.run_command_silent('df3d','cage-state-probe',tostring(cage.id),...);assert(code==0,text);return json.decode(text)
end
local state=request();local id
for _,row in ipairs(state.rows)do if row.kind==0 and not row.assigned then id=row.id;break end end
assert(id,'Missing unassigned candidate')
local function edit(value)
 local current=request();local receipt=request(tostring(current.revision),tostring(id),'0',value and '1'or'0')
 assert(receipt.outcome==1,'Cage body setup effect failed')
end
record('contained-item')
local ok,err=xpcall(function()
 edit(true);record('assigned-unit')
 if os.getenv('DF3D_CAGE_OCCUPANTS')=='1'then
  local unit=assert(df.unit.find(id))
  local function unit_state()
   local refs={};for _,ref in ipairs(unit.general_refs)do refs[#refs+1]={type=ref:getType(),id=ref:getID()}end
   return {flags1=unit.flags1.whole,flags2=unit.flags2.whole,flags3=unit.flags3.whole,flags4=unit.flags4.whole,job=unit.job.current_job and unit.job.current_job.id or -1,refs=refs}
  end
  local original=unit_state()
  g.precise_mouse_x=864;g.precise_mouse_y=190;g.mouse_x=108;g.mouse_y=15
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
  require('gui').simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
  df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
  assert(#cage.assigned_units==0 and cage.cage_flags.whole&4~=0,'Native parent assignment removal failed')
  assert(json.encode(original)==json.encode(unit_state()),'Native parent removal changed unit state')
  capture('cage-body-parent-removed')
  result.parent_remove={id=id,before=original,after=unit_state(),flags=cage.cage_flags.whole}
 end
end,debug.traceback)
edit(false);cage.cage_flags.whole=flags
assert(json.encode(before)==json.encode({units=ids(cage.assigned_units),items=ids(cage.assigned_items)}))
assert(df.global.world.frame_counter==frame)
assert(ok,err)
record('restored');result.success=true;result.restored=true
if result.cases[1].provider then
 assert(result.cases[1].provider.revision~=result.cases[2].provider.revision)
 assert(json.encode(result.cases[1].provider)==json.encode(result.cases[3].provider),'Occupant facts did not restore')
end
local f=assert(io.open(out..'/cage-body-native.json','w'));f:write(json.encode(result));f:close()
