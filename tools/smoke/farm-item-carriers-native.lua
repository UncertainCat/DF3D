-- Paused disposable diagnostic. Reciprocal temporary relationships are restored.
local out,view,records,b,capture,select_map=...
local gui=require('gui');local json=require('json')
local g=df.global.gps;local sheet=df.global.game.main_interface.view_sheets
local entry=assert(b.contained_items[0]);local item=entry.item
local saved={flags=item.flags.whole,x=item.pos.x,y=item.pos.y,z=item.pos.z,refs={}}
local overview_case=os.getenv('DF3D_UNIT_OVERVIEW_CASE') or 'child'
for _,ref in ipairs(item.general_refs)do saved.refs[#saved.refs+1]=ref end
local container,unit
for _,candidate in ipairs(df.global.world.items.other.BOX)do
 local x,y,z=dfhack.items.getPosition(candidate)
 if not candidate.flags.removed and x and x>=0 and z==b.z then container=candidate;break end
end
for _,candidate in ipairs(df.global.world.units.active)do
 local adult=candidate.profession~=df.profession.CHILD and candidate.profession~=df.profession.BABY
 local hauling=false;for _,held in ipairs(candidate.inventory)do if held.mode==df.inv_item_role_type.Hauled then hauling=true end end
 if dfhack.units.isCitizen(candidate) and candidate.pos.z==b.z and
  (overview_case=='child' or (adult and not hauling and candidate.military.squad_id<0))then unit=candidate;break end
end
assert(container and unit,'carrier fixture requires a box and citizen on the farm level')
local description_case=os.getenv('DF3D_BOX_DESCRIPTION_CASE') or 'none'
assert(description_case=='none' or description_case=='image' or description_case=='masterpiece','unknown box description case')
local extra_image,box_saved
local overview_saved
local function focus_state(p)
 return {flags=p.flags.whole,current=p.current_focus,baseline=p.undistracted_focus,year=p.slack_end_year,tick=p.slack_end_year_tick}
end
local function erase_pointer(vector,value)
 for i=#vector-1,0,-1 do if vector[i]==value then vector:erase(i);return end end
end
local ref,reciprocal,inventory,detached,prior_revision
local function restore()
 if overview_saved then
  local old=overview_saved;local p=unit.status.current_soul.personality
  for _,saved in ipairs(old.assignment_indices or {})do saved.assignment.position_vector_idx=saved.index end
  if old.spouse_link then erase_pointer(old.hf.histfig_links,old.spouse_link);df.delete(old.spouse_link)end
  for i=#(old.offices or {}),1,-1 do
   local extra=old.offices[i]
   erase_pointer(extra.hf.entity_links,extra.link);erase_pointer(extra.entity.positions.assignments,extra.assignment);erase_pointer(extra.entity.positions.own,extra.position)
   df.delete(extra.link);df.delete(extra.assignment);df.delete(extra.position)
  end
  unit.profession=old.profession;unit.military.squad_id=old.squad_id
  p.flags.whole=old.focus.flags;p.current_focus=old.focus.current;p.undistracted_focus=old.focus.baseline
  p.slack_end_year=old.focus.year;p.slack_end_year_tick=old.focus.tick
  for i,value in ipairs(old.needs)do p.needs[i-1].focus_level=value end
  if old.squad then old.squad.alias=old.alias end
  overview_saved=nil
 end
 if box_saved then
  assert(container.improvements[#container.improvements-1]==extra_image)
  container.improvements:erase(#container.improvements-1);df.delete(extra_image);extra_image=nil
  container.quality=box_saved.quality;container.maker=box_saved.maker;container.maker_race=box_saved.maker_race
  container.flags.whole=box_saved.flags;container.weight.whole=box_saved.whole;container.weight.fraction=box_saved.fraction
  box_saved=nil
 end
 if not detached then return end
 if reciprocal then assert(container.general_refs[#container.general_refs-1]==reciprocal);container.general_refs:erase(#container.general_refs-1);df.delete(reciprocal);reciprocal=nil end
 if inventory then assert(unit.inventory[#unit.inventory-1]==inventory);unit.inventory:erase(#unit.inventory-1);df.delete(inventory);inventory=nil end
 while #item.general_refs>0 do item.general_refs:erase(#item.general_refs-1)end
 if ref then df.delete(ref);ref=nil end
 for _,original in ipairs(saved.refs)do item.general_refs:insert('#',original)end
 b.contained_items:insert(0,entry)
 item.flags.whole=saved.flags;item.pos.x=saved.x;item.pos.y=saved.y;item.pos.z=saved.z
 detached=false
end
local function move(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 gui.simulateInput(view,{});view:render(dfhack.getTickCount())
end
local ok,err=xpcall(function()
 local kinds=os.getenv('DF3D_UNIT_CARRIER_ONLY')=='1' and {'unit'} or {'container','unit'}
 for _,kind in ipairs(kinds)do
  select_map(b);move(756,526);gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
  assert(sheet.open and sheet.active_sheet==df.view_sheet_type.ITEM and sheet.active_id==item.id)
  b.contained_items:erase(0);detached=true
  for index=#item.general_refs-1,0,-1 do if item.general_refs[index]:getType()==df.general_ref_type.BUILDING_HOLDER then item.general_refs:erase(index)end end
  item.flags.in_building=false;item.flags.in_inventory=true;item.flags.on_ground=false
  local target
  if kind=='container' then
   target=container;ref=df.general_ref_contained_in_itemst:new();ref.item_id=target.id
   reciprocal=df.general_ref_contains_itemst:new();reciprocal.item_id=item.id;container.general_refs:insert('#',reciprocal)
  else
   target=unit;ref=df.general_ref_unit_holderst:new();ref.unit_id=target.id
   inventory=df.unit_inventory_item:new();inventory.item=item;inventory.mode=df.inv_item_role_type.Hauled;inventory.body_part_id=-1;unit.inventory:insert('#',inventory)
  end
  item.general_refs:insert('#',ref);item.pos:assign(target.pos);move(0,4)
  local row=capture('farm-item-carrier-'..kind);row.item_id=item.id;row.target_id=target.id;row.description=dfhack.df2utf(sheet.raw_description)
  local text,code=dfhack.run_command_silent('df3d','item-inspect-probe',tostring(item.id));assert(code==0,text);row.independent=json.decode(text).snapshot
  local guards={}
  for _,object in ipairs{sheet,df.global.plotinfo}do
   local size,address=df.sizeof(object);local bytes=df.new('uint8_t',size)
   dfhack.internal.memmove(bytes,address,size);guards[#guards+1]={bytes=bytes,address=address,size=size}
  end
  local semantic,status=dfhack.run_command_silent('df3d','item-carrier-probe',tostring(item.id));assert(status==0,semantic)
  row.carrier=json.decode(semantic)
  assert(row.carrier.kind==(kind=='container' and 1 or 2) and row.carrier.id==target.id,'semantic carrier differs from native navigation')
  local native_name=dfhack.utf2df(row.carrier.name):gsub('[^ -~]',' '):sub(1,18)
  local matched=false;for _,line in ipairs(row.lines)do if line:find(native_name,1,true)then matched=true end end
  assert(matched,'semantic carrier name differs from native row')
  for _,guard in ipairs(guards)do
   local bytes=df.new('uint8_t',guard.size);dfhack.internal.memmove(bytes,guard.address,guard.size)
   for index=0,guard.size-1 do assert(bytes[index]==guard.bytes[index],'carrier reader changed native UI state')end
   df.delete(bytes);df.delete(guard.bytes)
  end
  row.native_ui_unchanged=true
  assert(row.independent.carrier and row.independent.carrier.id==target.id and row.independent.carrier.name==row.carrier.name)
  if prior_revision then assert(prior_revision~=row.independent.revision,'carrier change retained old revision')end
  local expected={snapshot=row.independent,prior_revision=prior_revision,overview_case=overview_case}
  local f=assert(io.open(out..'/carrier-expected.json','w'));f:write(json.encode(expected));f:close()
  capture('farm-item-carrier-'..kind..'-wire')
  local result=assert(io.open(out..'/carrier-wire-result.json'));row.wire=json.decode(result:read('*a'));result:close()
  assert(row.wire.success and item.flags.hidden==false,'carrier wire verification failed or changed final flag')
  if kind=='container' then
   capture('farm-item-carrier-scene')
   local scene_result=assert(io.open(out..'/carrier-scene-result.json'));row.scene=json.decode(scene_result:read('*a'));scene_result:close()
   assert(row.scene.success,'container main-scene navigation failed')
  end
  prior_revision=row.independent.revision
  local cold_probe
  if kind=='container' and description_case~='none' then
   assert(target.world_data_id==-1,'cold image fixture must not retire worldgen backing')
   box_saved={quality=target.quality,maker=target.maker,maker_race=target.maker_race,flags=target.flags.whole,whole=target.weight.whole,fraction=target.weight.fraction}
   extra_image=df.itemimprovement_art_imagest:new()
   extra_image.mat_type=target:getMaterial();extra_image.mat_index=target:getMaterialIndex();extra_image.quality=3;extra_image.maker=-1
   extra_image.image.id=-1;extra_image.image.subid=-1;extra_image.image.civ_id=-1;extra_image.image.site_id=-1
   target.improvements:insert('#',extra_image)
   if description_case=='masterpiece' then
    assert(unit.hist_figure_id>=0);target.quality=5;target.maker=unit.hist_figure_id;target.maker_race=unit.race
    extra_image.quality=5;extra_image.maker=unit.hist_figure_id
   end
   local copies={}
   for _,object in ipairs{sheet,df.global.plotinfo}do
    local size,address=df.sizeof(object);local bytes=df.new('uint8_t',size);dfhack.internal.memmove(bytes,address,size)
    copies[#copies+1]={size=size,address=address,bytes=bytes}
   end
   local before={id=df.global.world.worldgen.next_art_image_chunk_id,offset=df.global.world.worldgen.next_art_image_chunk_offset}
   local text,status=dfhack.run_command_silent('df3d','item-inspect-probe',tostring(target.id))
   local unchanged=true
   for _,copy in ipairs(copies)do
    local current=df.new('uint8_t',copy.size);dfhack.internal.memmove(current,copy.address,copy.size)
    for i=0,copy.size-1 do if current[i]~=copy.bytes[i]then unchanged=false end end
    df.delete(current);df.delete(copy.bytes)
   end
   assert(status==0,text);assert(unchanged,'cold image description changed native UI')
   cold_probe=json.decode(text).snapshot;cold_probe.case=description_case;cold_probe.native_ui_unchanged=true;cold_probe.before=before
   cold_probe.after={id=df.global.world.worldgen.next_art_image_chunk_id,offset=df.global.world.worldgen.next_art_image_chunk_offset}
   cold_probe.image={id=extra_image.image.id,subid=extra_image.image.subid}
   assert(cold_probe.image.id>=0 and cold_probe.image.subid>=0,'native description did not initialize image')
   local chunk=assert(df.art_image_chunk.find(cold_probe.image.id));local art=assert(chunk.images[cold_probe.image.subid].art_image)
   cold_probe.art={id=art.id,subid=art.subid,elements=#art.elements,properties=#art.properties,quality=art.quality,artist=art.artist,has_source=art.ref~=nil}
   assert(cold_probe.art.elements>0 and cold_probe.art.has_source,'native art record incomplete')
  end
  if kind=='unit' then
   if overview_case~='child' then
    local ratios={focused=150,['focused-mild']=130,distracted=50,['distracted-mild']=70,neutral=100,['fresh-focused']=150,['fresh-distracted']=50,squad=100,['squad-alias']=100,offices=100,['office-spouse']=100,['office-requirements']=100}
    local ratio=assert(ratios[overview_case],'unknown Overview fixture case')
    local p=assert(unit.status.current_soul).personality
    overview_saved={profession=unit.profession,squad_id=unit.military.squad_id,focus=focus_state(p),needs={}}
    for _,need in ipairs(p.needs)do overview_saved.needs[#overview_saved.needs+1]=need.focus_level;need.focus_level=overview_case=='fresh-focused' and 300 or overview_case=='fresh-distracted' and -100000 or 0 end
    assert(#p.needs>0,'focus fixture needs at least one existing need')
    p.flags.distraction_calculated=not overview_case:find('^fresh%-');p.current_focus=ratio;p.undistracted_focus=100
    if overview_case=='squad' or overview_case=='squad-alias' then
     local squad=assert(df.global.world.squads.all[0],'assigned-squad fixture needs an existing squad')
     overview_saved.squad=squad;overview_saved.alias=squad.alias;unit.military.squad_id=squad.id
     if overview_case=='squad-alias' then squad.alias='Native squad alias' end
    end
    if overview_case=='offices' or overview_case=='office-spouse' or overview_case=='office-requirements' then
     local hf=assert(df.historical_figure.find(unit.hist_figure_id));overview_saved.hf=hf;overview_saved.offices={}
     local entity=assert(df.historical_entity.find(df.global.plotinfo.group_id))
     local function add_position(holder,label)
      local position=df.entity_position:new();local assignment=df.entity_position_assignment:new();local link=df.histfig_entity_link_positionst:new()
      overview_saved.offices[#overview_saved.offices+1]={hf=holder,entity=entity,position=position,assignment=assignment,link=link}
      position.id=#entity.positions.own>0 and entity.positions.own[#entity.positions.own-1].id+1 or 0
      assignment.id=#entity.positions.assignments>0 and entity.positions.assignments[#entity.positions.assignments-1].id+1 or 0
      position.name[0]=label;position.name_male[0]=label;position.name_female[0]=label
      position.precedence=0 -- Deliberately differs from the existing bookkeeper's precedence.
      assignment.histfig=holder.id;assignment.position_id=position.id
      link.entity_id=entity.id;link.assignment_id=assignment.id;link.link_strength=100
      entity.positions.own:insert('#',position);entity.positions.assignments:insert('#',assignment);holder.entity_links:insert('#',link)
      return position
     end
     if overview_case=='offices' or overview_case=='office-requirements' then
      for i,label in ipairs{'second office','third office','fourth office'}do
       local position=add_position(hf,label)
       if overview_case=='office-requirements' then
        position.required_office=i*100;position.required_bedroom=(4-i)*200
        position.required_dining=i==2 and 1000 or 0;position.required_tomb=i==3 and 10000 or 0
       end
      end
     else
      local other
      for _,candidate in ipairs(df.global.world.units.active)do
       if candidate.id~=unit.id and dfhack.units.isCitizen(candidate) and candidate.profession~=df.profession.CHILD and candidate.profession~=df.profession.BABY then
        local figure=df.historical_figure.find(candidate.hist_figure_id);local has_position=false
        if figure then for _,link in ipairs(figure.entity_links)do if link:getType()==df.histfig_entity_link_type.POSITION then has_position=true end end end
        if figure and not has_position then other=figure;break end
       end
      end
      assert(other,'spouse fixture needs an adult without positions')
      local position=add_position(other,'companion office')
      position.required_office=12345 -- A spouse title must not impose the spouse's office requirement.
      position.spouse[0]='native consort';position.spouse_female[0]='native consort';position.spouse_male[0]='native consort'
      local link=df.histfig_hf_link_spousest:new();overview_saved.spouse_link=link;link.target_hf=other.id;link.link_strength=100
      hf.histfig_links:insert(0,link)
     end
    end
   end
  end
  local target_before,target_size,target_address
  if kind=='container' then
   target_size,target_address=df.sizeof(target);target_before=df.new('uint8_t',target_size)
   dfhack.internal.memmove(target_before,target_address,target_size)
  end
  local camera_before={x=df.global.window_x,y=df.global.window_y,z=df.global.window_z}
  move(816,250);gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
  local linked=capture('farm-item-carrier-'..kind..'-view');linked.target_id=target.id
  assert(sheet.open and sheet.active_id==target.id and sheet.active_sheet==(kind=='unit' and df.view_sheet_type.UNIT or df.view_sheet_type.ITEM),'native carrier View selected wrong identity')
  if kind=='unit' then
   linked.overview_case=overview_case
   linked.room_requirements={}
   for i=0,3 do linked.room_requirements[i+1]=sheet.reqroom[i]end
   local req_file=assert(io.open(out..'/unit-room-requirements.json','w'));req_file:write(json.encode(linked.room_requirements));req_file:close()
   if overview_case=='office-requirements' then
    assert(json.encode(linked.room_requirements)==json.encode({300,600,1000,10000}),'native requirement fixture differs')
    gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
    overview_saved.assignment_indices={}
    for _,extra in ipairs(overview_saved.offices)do
     overview_saved.assignment_indices[#overview_saved.assignment_indices+1]={assignment=extra.assignment,index=extra.assignment.position_vector_idx}
     extra.assignment.position_vector_idx=-1
    end
    local protected={unit,sheet,df.global.plotinfo}
    for _,extra in ipairs(overview_saved.offices)do protected[#protected+1]=extra.assignment end
    local copies={}
    for _,object in ipairs(protected)do
     local size,address=df.sizeof(object);local bytes=df.new('uint8_t',size);dfhack.internal.memmove(bytes,address,size)
     copies[#copies+1]={size=size,address=address,bytes=bytes}
    end
    local text,status=dfhack.run_command_silent('df3d','unit-room-requirements-probe',tostring(unit.id))
    local unchanged=true
    for _,copy in ipairs(copies)do
     local after=df.new('uint8_t',copy.size);dfhack.internal.memmove(after,copy.address,copy.size)
     for i=0,copy.size-1 do if after[i]~=copy.bytes[i]then unchanged=false end end
     df.delete(after);df.delete(copy.bytes)
    end
    assert(status==0,text);assert(unchanged,'direct requirement reader changed live unit/assignment/UI bytes')
    assert(json.encode(json.decode(text))==json.encode(linked.room_requirements),'direct native requirements differ')
    linked.requirement_probe={values=json.decode(text),live_unit_assignments_ui_unchanged=true}
   end
   local p=unit.status.current_soul.personality
   if overview_case:find('^fresh%-') then
    -- Native has calculated its reference. Make the live source cold again;
    -- the viewer must compute on its own copy without changing these fields.
    gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
    p.flags.distraction_calculated=false;p.current_focus=-999;p.undistracted_focus=-999
    p.slack_end_year=0;p.slack_end_year_tick=0
   end
   local before_focus=focus_state(p)
   linked.camera_before=camera_before;linked.camera_after={x=df.global.window_x,y=df.global.window_y,z=df.global.window_z}
   assert(json.encode(linked.camera_before)==json.encode(linked.camera_after),'Unit carrier View moved native camera')
   capture('farm-item-carrier-unit-scene')
   local result=assert(io.open(out..'/carrier-scene-result.json'));linked.scene=json.decode(result:read('*a'));result:close()
   assert(linked.scene.success,'unit carrier main-scene navigation failed')
   linked.focus_before=before_focus;linked.focus_after=focus_state(p)
   assert(json.encode(before_focus)==json.encode(linked.focus_after),'viewer changed live personality focus cache/timestamps')
   if overview_case=='office-requirements' then
    linked.viewer_position_indices={}
    for _,saved in ipairs(overview_saved.assignment_indices)do linked.viewer_position_indices[#linked.viewer_position_indices+1]=saved.assignment.position_vector_idx end
   end
  end
  if kind=='container' then
   linked.description=dfhack.df2utf(sheet.raw_description)
   if cold_probe then
    assert(cold_probe.description==linked.description,'cold owned description differs from later native sheet')
    linked.cold_description_probe=cold_probe
   end
   linked.item_type=target:getType();linked.quality=target.quality;linked.maker=target.maker;linked.maker_race=target.maker_race
   linked.improvements={}
   for _,improvement in ipairs(target.improvements)do
    linked.improvements[#linked.improvements+1]={type=improvement:getType(),material_type=improvement.mat_type,material_index=improvement.mat_index,quality=improvement.quality,maker=improvement.maker}
   end
   local after=df.new('uint8_t',target_size);dfhack.internal.memmove(after,target_address,target_size)
   linked.native_item_changed_bytes={}
   for index=0,target_size-1 do
    if after[index]~=target_before[index]then linked.native_item_changed_bytes[#linked.native_item_changed_bytes+1]={offset=index,before=target_before[index],after=after[index]}end
   end
   df.delete(after);df.delete(target_before)
   local function description_probe()
    local protected={target,sheet,df.global.plotinfo}
    for _,improvement in ipairs(target.improvements)do protected[#protected+1]=improvement end
    if extra_image then
     local chunk=assert(df.art_image_chunk.find(extra_image.image.id));local art=assert(chunk.images[extra_image.image.subid].art_image)
     protected[#protected+1]=art
     if art.ref then protected[#protected+1]=art.ref end
     for _,element in ipairs(art.elements)do protected[#protected+1]=element end
     for _,property in ipairs(art.properties)do protected[#protected+1]=property end
    end
    local copies={}
    for _,object in ipairs(protected)do
     local size,address=df.sizeof(object);local bytes=df.new('uint8_t',size);dfhack.internal.memmove(bytes,address,size)
     copies[#copies+1]={size=size,address=address,bytes=bytes}
    end
    local text,status=dfhack.run_command_silent('df3d','box-description-probe',tostring(target.id))
    local unchanged=true
    for _,copy in ipairs(copies)do
     local current=df.new('uint8_t',copy.size);dfhack.internal.memmove(current,copy.address,copy.size)
     for i=0,copy.size-1 do if current[i]~=copy.bytes[i]then unchanged=false end end
     df.delete(current);df.delete(copy.bytes)
    end
    assert(status==0,text);assert(unchanged,'box description changed item/improvement/UI bytes')
    local result=json.decode(text);assert(result.description==linked.description,'owned box description differs from native')
    result.item_improvement_ui_unchanged=true;result.native_sheet_open=sheet.open
    if cold_probe then
     assert(df.global.world.worldgen.next_art_image_chunk_id==cold_probe.after.id and df.global.world.worldgen.next_art_image_chunk_offset==cold_probe.after.offset,'repeated description allocated another art image')
     result.art_unchanged=true;result.no_additional_art=true
    end
    return result
   end
   linked.description_probes={description_probe()}
   -- Follow the actual item holder action before designing its destination.
   local holder_text,holder_status=dfhack.run_command_silent('df3d','item-inspect-probe',tostring(target.id))
   assert(holder_status==0,holder_text)
   local holder=assert(json.decode(holder_text).snapshot.holder,'installed box requires building holder')
   move(816,250);gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
   local destination=capture('farm-item-carrier-container-building');destination.target_id=holder.id;destination.target_type=holder.type
   assert(sheet.open and sheet.active_id==holder.id and sheet.active_sheet==df.view_sheet_type.BUILDING,'holder View selected wrong building')
   local installed=assert(df.building.find(holder.id))
   destination.custom_name=installed.name;destination.native_name=dfhack.df2utf(dfhack.buildings.getName(installed));destination.contents={}
   for _,held in ipairs(installed.contained_items)do
    local object=held.item
    destination.contents[#destination.contents+1]={id=object.id,type=object:getType(),subtype=object:getSubtype(),role=held.use_mode,
     material=object:getMaterial(),material_index=object:getMaterialIndex(),flags=object.flags.whole,hidden=object.flags.hidden}
   end
   destination.foreign_item=item.id
   local expected=assert(io.open(out..'/chest-contents-expected.json','w'));expected:write(json.encode(destination));expected:close()
   capture('farm-chest-contents-wire')
   local result=assert(io.open(out..'/chest-contents-result.json'));destination.contents_wire=json.decode(result:read('*a'));result:close()
   assert(destination.contents_wire.success,'chest contents wire failed')
   for index,held in ipairs(installed.contained_items)do assert(held.item.flags.hidden==destination.contents[index+1].hidden,'chest contents visibility not restored')end
   assert(not item.flags.hidden,'foreign chest edit changed seed')
   move(800,82);gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
   assert(sheet.building_entering_nickname,'chest Rename did not enter editing')
   capture('farm-item-carrier-building-rename')
   gui.simulateInput(view,'SELECT');view:render(dfhack.getTickCount())
   assert(not sheet.building_entering_nickname and installed.name==destination.custom_name,'empty rename changed chest name')
   for index,held in ipairs(installed.contained_items)do
    local first
    if held.item:getType()==df.item_type.INSTRUMENT then
     local guards={}
     for _,object in ipairs{sheet,df.global.plotinfo}do
      local size,address=df.sizeof(object);local bytes=df.new('uint8_t',size);dfhack.internal.memmove(bytes,address,size)
      guards[#guards+1]={size=size,address=address,bytes=bytes}
     end
     local text,status=dfhack.run_command_silent('df3d','item-inspect-probe',tostring(held.item.id));assert(status==0,text)
     first=json.decode(text).snapshot
     for _,guard in ipairs(guards)do
      assert(dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)==0,'first instrument inspection changed UI bytes');df.delete(guard.bytes)
     end
    end
    move(772,526+index*36);gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
    assert(sheet.open and sheet.active_sheet==df.view_sheet_type.ITEM and sheet.active_id==held.item.id,'chest contents View selected wrong item')
    local inspected=capture('farm-item-carrier-building-item-'..index)
    inspected.item_id=held.item.id;inspected.item_type=held.item:getType();inspected.description=dfhack.df2utf(sheet.raw_description)
    if first then
     assert(first.description==inspected.description,'first instrument description differs from later native screen')
     inspected.first_read=first;inspected.first_read_ui_unchanged=true
    end
    local guards={}
    for _,object in ipairs{held.item,sheet,df.global.plotinfo}do
     local size,address=df.sizeof(object);local bytes=df.new('uint8_t',size);dfhack.internal.memmove(bytes,address,size)
     guards[#guards+1]={size=size,address=address,bytes=bytes}
    end
    local text,status=dfhack.run_command_silent('df3d','item-inspect-probe',tostring(held.item.id));assert(status==0,text)
    inspected.independent=json.decode(text).snapshot
    assert(inspected.independent.description==inspected.description,'instrument semantic description differs from native')
    for _,guard in ipairs(guards)do
     assert(dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)==0,'warm instrument inspection changed item/UI bytes');df.delete(guard.bytes)
    end
    inspected.guards_unchanged=true
    if held.item:getType()==df.item_type.INSTRUMENT then
     local expected=assert(io.open(out..'/carrier-expected.json','w'));expected:write(json.encode{snapshot=inspected.independent,native_reference=inspected.name});expected:close()
     capture('farm-item-carrier-instrument-'..index..'-wire')
     local result=assert(io.open(out..'/carrier-wire-result.json'));inspected.wire=json.decode(result:read('*a'));result:close()
     assert(inspected.wire.success and held.item.flags.hidden==inspected.independent.hidden,'instrument wire failed or left hidden flag changed')
    end
    gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());select_map(installed)
    assert(sheet.open and sheet.active_sheet==df.view_sheet_type.BUILDING and sheet.active_id==installed.id)
   end
   gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
   local header_source=debug.getinfo(1,'S').source:sub(2):gsub('farm%-item%-carriers%-native.lua$','chest-header-native.lua')
   assert(loadfile(header_source))(out,view,records,installed,capture,select_map)
   if sheet.open then gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())end
   linked.description_probes[#linked.description_probes+1]=description_probe()
   local text,status=dfhack.run_command_silent('df3d','item-inspect-probe',tostring(target.id));assert(status==0,text)
   linked.independent=json.decode(text).snapshot;assert(linked.independent.description==linked.description)
   local expected=assert(io.open(out..'/carrier-expected.json','w'));expected:write(json.encode{snapshot=linked.independent});expected:close()
   capture('farm-item-carrier-box-wire')
   local result=assert(io.open(out..'/carrier-wire-result.json'));linked.wire=json.decode(result:read('*a'));result:close()
   assert(linked.wire.success and target.flags.hidden==linked.independent.hidden,'box wire verification failed or left hidden flag changed')
  end
  if sheet.open then gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())end;restore()
 end
end,debug.traceback)
if sheet.open then gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())end
restore();select_map(b)
assert(b.contained_items[0]==entry and item.flags.whole==saved.flags and #item.general_refs==#saved.refs)
for index,original in ipairs(saved.refs)do assert(item.general_refs[index-1]==original)end
assert(ok,err)
records[#records+1]={name='farm-item-carriers-restored',restored=true,item_id=item.id}
