-- Read-only Expel navigation in an owned paused fixture; never confirms expulsion.
local unit,view,capture,out=...
local gui=require('gui')
local json=require('json')
local g=df.global.gps
local main=df.global.game.main_interface
local sheet=main.view_sheets
local frame=df.global.world.frame_counter
local observations={}
local changed_positions={}
local family
local cold_saved={}
local function restore_cold()
 for _,v in ipairs(cold_saved)do v.object[v.key]=v.value end
 cold_saved={}
end
local function restore_family()
 if not family then return end
 family.relative.flags1.whole=family.flags
 family.relative.profession=family.profession
 family.relative.relationship_ids[0]=family.owner
 family.related_hf.died_year=family.died_year
 if family.where then family.where.state=family.where_state;family.where.site_id=family.where_site end
 family.hf.histfig_links:resize(0)
 for _,link in ipairs(family.links)do family.hf.histfig_links:insert('#',link)end
 for _,link in ipairs(family.created)do link:delete()end
 family=nil
end
local function restore_positions()
 for _,saved in ipairs(changed_positions)do saved.position.flags.ELECTED=saved.elected;saved.position.flags.SUCCESSION_BY_HEIR=saved.hereditary end
end
local function pointer(x,y)
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.mouse_x=x//8;g.mouse_y=(y-4)//12;g.precise_mouse_x=x;g.precise_mouse_y=y
 gui.simulateInput(view,{});view:render(dfhack.getTickCount())
end
local function vector(v)local r={}for _,x in ipairs(v)do r[#r+1]=x end return r end
local function record(name)
 pointer(400,400);capture('unit-expel-'..name)
 local rows={}
 for y=0,g.dimy-1 do
  local chars={}
  for x=0,g.dimx-1 do local pen=dfhack.screen.readTile(x,y);chars[#chars+1]=pen.ch>=32 and pen.ch<=255 and string.char(pen.ch) or ' ' end
  local text=dfhack.df2utf(table.concat(chars)):gsub('%s+$','')
  if text~=''then rows[#rows+1]={y=y,text=text}end
 end
 observations[#observations+1]={name=name,open=sheet.open,active_id=sheet.active_id,
  expelling=sheet.unit_overview_expelling,reason=sheet.unit_overview_expel_cannot_expel_reason,
  selected_destination=sheet.unit_overview_expel_selected_dest_stid,
  destinations=vector(sheet.unit_overview_expel_dest_stid),units=vector(sheet.unit_overview_expel_total_unid),rows=rows}
 if sheet.unit_overview_expelling and os.getenv('DF3D_UNIT_EXPEL_READER')=='1' then
  local cold_seen={}
  local function invalidate(object,key)
   local _,address=df.sizeof(object);local identity=tostring(address)..key
   if cold_seen[identity]then return end;cold_seen[identity]=true
   cold_saved[#cold_saved+1]={object=object,key=key,value=object[key]};object[key]=-1
  end
  if os.getenv('DF3D_UNIT_EXPEL_COLD')=='1' then
   for _,candidate in ipairs{unit,family and family.relative or unit}do
    invalidate(candidate.enemy,'histfig_vector_idx')
    local hf=df.historical_figure.find(candidate.hist_figure_id)
    if hf then for _,link in ipairs(hf.entity_links)do
     invalidate(link,'entity_vector_idx')
     if link:getType()==df.histfig_entity_link_type.POSITION then invalidate(link,'assignment_vector_idx')end
    end end
    for _,office in ipairs(dfhack.units.getNoblePositions(candidate) or {})do invalidate(office.assignment,'position_vector_idx')end
   end
  end
  local guards,seen={},{}
  local function protect(object)
   if not object then return end
   local size,address=df.sizeof(object)
   if seen[address]then return end;seen[address]=true
   local bytes=df.new('uint8_t',size);dfhack.internal.memmove(bytes,address,size)
   guards[#guards+1]={bytes=bytes,address=address,size=size}
  end
  protect(sheet);protect(df.global.plotinfo)
  for _,candidate in ipairs{unit,family and family.relative or unit}do
   protect(candidate)
   local hf=df.historical_figure.find(candidate.hist_figure_id);protect(hf)
   if hf then
    for _,link in ipairs(hf.histfig_links)do protect(link)end
    for _,link in ipairs(hf.entity_links)do protect(link)end
   end
   for _,office in ipairs(dfhack.units.getNoblePositions(candidate) or {})do protect(office.assignment);protect(office.position)end
  end
  local output,status=dfhack.run_command_silent('df3d','unit-expel-group-probe',tostring(unit.id))
  local unchanged=true
  for _,guard in ipairs(guards)do
   if dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)~=0 then unchanged=false end
   df.delete(guard.bytes)
  end
  local cold_count=#cold_saved;restore_cold()
  observations[#observations].cold_cache_count=cold_count
  assert(status==0,output);assert(unchanged,'Expel reader changed guarded unit/family/office/menu state')
  local result=json.decode(output)
  observations[#observations].reader=result;observations[#observations].reader_guards_unchanged=true
  assert(result.reason==sheet.unit_overview_expel_cannot_expel_reason,'Expel reader refusal differs')
  assert(json.encode(result.units)==json.encode(vector(sheet.unit_overview_expel_total_unid)),'Expel reader affected group differs')
 end
 assert(df.global.pause_state and df.global.world.frame_counter==frame,'Expel navigation advanced simulation')
end
local ok,err=xpcall(function()
 assert(sheet.open and sheet.active_id==unit.id,'Expected native unit sheet')
 local hit
 for y=64,136,12 do for x=792,888,8 do
  pointer(x,y)
  if main.current_hover==df.main_hover_instruction.EXPEL_UNIT then hit={x,y};break end
 end if hit then break end end
 assert(hit,'Expel hitbox not found')
 observations[#observations+1]={name='hitbox',mouse=hit}
 df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
 assert(sheet.unit_overview_expelling,'Expel did not open')
 record('open')
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
 assert(not sheet.unit_overview_expelling and sheet.open and sheet.active_id==unit.id,'Expel cancel did not restore Overview')
 record('cancel')
 if os.getenv('DF3D_UNIT_EXPEL_REFUSALS')=='1' then
  local positions=dfhack.units.getNoblePositions(unit)
  assert(positions and #positions>0,'Refusal fixture needs an existing native office')
  local position=positions[1].position
  changed_positions[1]={position=position,elected=position.flags.ELECTED,hereditary=position.flags.SUCCESSION_BY_HEIR}
  for _,case in ipairs{{'elected',true,false,1},{'hereditary',false,true,0},{'both',true,true,1}}do
   position.flags.ELECTED=case[2];position.flags.SUCCESSION_BY_HEIR=case[3]
   pointer(856,100);df.global.enabler.mouse_lbut_lift=0
   gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
   df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
   assert(sheet.unit_overview_expelling and sheet.unit_overview_expel_cannot_expel_reason==case[4],'Native office refusal differs')
   record(case[1])
   gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
   assert(not sheet.unit_overview_expelling and sheet.open and sheet.active_id==unit.id,'Refusal cancel lost unit')
  end
  restore_positions()
 end
 if os.getenv('DF3D_UNIT_EXPEL_FAMILY')=='1' then
  local relative
  for _,candidate in ipairs(df.global.world.units.active)do
   local positions=dfhack.units.getNoblePositions(candidate)
   if candidate.id~=unit.id and dfhack.units.isCitizen(candidate) and dfhack.units.getAge(candidate)>18 and not candidate.flags1.inactive and (not positions or #positions==0) then relative=candidate;break end
  end
  assert(relative,'Family fixture needs another adult citizen without office')
  local hf=assert(df.historical_figure.find(unit.hist_figure_id))
  local related_hf=assert(df.historical_figure.find(relative.hist_figure_id))
  family={hf=hf,relative=relative,flags=relative.flags1.whole,profession=relative.profession,owner=relative.relationship_ids[0],related_hf=related_hf,died_year=related_hf.died_year,where=related_hf.info and related_hf.info.whereabouts,links=vector(hf.histfig_links),created={}}
  if family.where then family.where_state=family.where.state;family.where_site=family.where.site_id end
  local spouse=df.histfig_hf_link_spousest:new();family.created[#family.created+1]=spouse
  local child=df.histfig_hf_link_childst:new();family.created[#family.created+1]=child
  for _,link in ipairs(family.created)do link.target_hf=related_hf.id;link.link_strength=100 end
  for _,case in ipairs{{'spouse-present',spouse,false,false,-1,true},{'spouse-absent',spouse,true,false,3,false},{'child-present',child,false,true,-1,true},{'child-absent',child,true,true,7,false},{'adult-child',child,false,false,-1,false},{'missing-spouse',spouse,false,false,-1,false,'missing'},{'dead-spouse',spouse,false,false,-1,false,'dead'},{'offsite-spouse',spouse,false,false,-1,false,'offsite'},{'companion-active',spouse,false,false,-1,true,'companion'},{'companion-inactive',spouse,true,false,-1,false,'companion'},{'companion-incoming',spouse,true,false,-1,true,'incoming'},{'spouse-companion',spouse,false,false,-1,true,'duplicate'}}do
   hf.histfig_links:resize(0);hf.histfig_links:insert('#',case[2])
   spouse.target_hf=related_hf.id;related_hf.died_year=family.died_year
   relative.flags1.whole=family.flags;relative.relationship_ids[0]=family.owner
   if family.where then family.where.state=family.where_state;family.where.site_id=family.where_site end
   if case[7]=='missing' then spouse.target_hf=-1 end
   if case[7]=='dead' then related_hf.died_year=0 end
   if case[7]=='offsite' then assert(family.where,'Expected relative whereabouts');family.where.state=df.whereabouts_type.settler;family.where.site_id=-1 end
   if case[7]=='companion' or case[7]=='incoming' then hf.histfig_links:resize(0)end
   if case[7]=='companion' or case[7]=='incoming' or case[7]=='duplicate' then relative.relationship_ids[0]=unit.id end
   if case[7]=='incoming' then relative.flags1.incoming=true end
   relative.flags1.inactive=case[3];relative.profession=case[4] and df.profession.CHILD or family.profession
   pointer(856,100);df.global.enabler.mouse_lbut_lift=0
   gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
   df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
   record(case[1]);observations[#observations].relative_id=relative.id
   assert(sheet.unit_overview_expelling and sheet.unit_overview_expel_cannot_expel_reason==case[5],'Native family refusal differs: '..case[1])
   local included=false;for _,id in ipairs(sheet.unit_overview_expel_total_unid)do if id==relative.id then included=true end end
   assert(included==case[6],'Native affected family list differs: '..case[1])
   gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
   assert(not sheet.unit_overview_expelling and sheet.open and sheet.active_id==unit.id,'Family cancel lost unit')
  end
  restore_family()
 end
end,debug.traceback)
restore_cold()
restore_family()
restore_positions()
if sheet.unit_overview_expelling then gui.simulateInput(view,'LEAVESCREEN')end
pointer(400,400)
local result={success=ok,unit_id=unit.id,observations=observations,error=not ok and err or nil}
local f=assert(io.open(out..'/unit-expel-native.json','w'));f:write(json.encode(result));f:close()
assert(ok,err);return result
