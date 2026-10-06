-- Protected fixture helper only: independent native facts for transport checks.
local out,phase=...
local json=require('json')
assert(df.global.pause_state and df.global.world.frame_counter==0,'paused clone required')
local site=assert(dfhack.world.getCurrentSite())
local keys={'goblets','instruments','paper','splints','thread','cloth','crutches','powder','buckets','soap'}
local function appraisal()
 local entity=df.global.plotinfo.main.fortress_entity
 if entity then
  local assignments=entity.assignments_by_type[df.entity_position_responsibility.TRADE]
  for i=#assignments-1,0,-1 do
   local hf=df.historical_figure.find(assignments[i].histfig)
   local unit=hf and df.unit.find(hf.unit_id)
   if unit then return math.max(0,dfhack.units.getEffectiveSkill(unit,df.job_skill.APPRAISAL))end
  end
 end
 return -1
end
local function facilities(location)
 local counts={chests=0,beds=0,tables=0,traction_benches=0,bookcases=0,chairs=0,rooms=0,rented_rooms=0}
 local kinds={Box='chests',Bed='beds',Table='tables',TractionBench='traction_benches',Bookcase='bookcases',Chair='chairs'}
 for _,id in ipairs(location.contents.building_ids)do
  local zone=df.building.find(id)
  if zone and df.building_civzonest:is_instance(zone)then
   if zone.type==df.civzone_type.Bedroom then
    counts.rooms=counts.rooms+1;if zone.assigned_unit_id~=-1 then counts.rented_rooms=counts.rented_rooms+1 end
   else
    for _,building in ipairs(zone.contained_buildings)do
     local key=kinds[df.building_type[building:getType()]]
     if key then counts[key]=counts[key]+1 end
    end
   end
  end
 end
 return counts
end
local function count_written(v)
 local count=0
 for _,name in ipairs{'BOOK','TOOL'}do
  for _,item in ipairs(df.global.world.items.other[name])do
   if name=='BOOK' or item:hasWriting()then
    local x,y,z=dfhack.items.getPosition(item)
    for _,id in ipairs(v.contents.building_ids)do
     local zone=df.building.find(id)
     if zone and df.building_civzonest:is_instance(zone)and zone.type~=df.civzone_type.Bedroom and
        z==zone.z and zone.room.extents then
      local rx,ry=x-zone.room.x,y-zone.room.y
      if rx>=0 and ry>=0 and rx<zone.room.width and ry<zone.room.height and zone.room.extents[ry*zone.room.width+rx]~=0 then
       count=count+1;break
      end
     end
    end
   end
  end
 end
 return count
end
-- Expected dimensions come from native captures, validated against this clone's
-- complete room footprint and terrain. This oracle is fixture-only, never runtime.
local reference_file=assert(io.open(out..'/../../fixtures/areas/native_location_dance.json','r'))
local dance_reference=json.decode(reference_file:read('*a'));reference_file:close()
local function dance_dimensions(location)
 local probe=_G.df3d_location_details_probe
 local changed=probe and probe.dance_cells and location.id==1
 local label=changed and 'all_building_occupancy' or 'baseline'
 local reference
 for _,row in ipairs(dance_reference.cases)do if row.id==location.id and row.case==label then reference=row;break end end
 assert(reference,'native dance fixture missing')
 assert(#location.contents.building_ids==#reference.zones,'native dance membership changed')
 for i,saved in ipairs(reference.zones)do
  assert(location.contents.building_ids[i-1]==saved.id,'native dance zone identity changed')
  local zone=assert(df.building.find(saved.id));local room=zone.room
  assert(zone.z==saved.bounds.z and df.civzone_type[zone.type]==saved.type,'native dance zone changed')
  assert(room.x==saved.room.x and room.y==saved.room.y and room.width==saved.room.width and room.height==saved.room.height,'native dance bounds changed')
  for y=0,room.height-1 do for x=0,room.width-1 do
   local index=y*room.width+x+1;assert(room.extents[index-1]==saved.extents[index],'native dance mask changed')
   local px,py=room.x+x,room.y+y;local block=assert(dfhack.maps.getTileBlock(px,py,zone.z));local tx,ty=px%16,py%16
   local tile=saved.tiles[index]
   assert(block.tiletype[tx][ty]==tile.tile and block.designation[tx][ty].whole==tile.designation and block.occupancy[tx][ty].building==tile.occupancy%8,'native dance terrain changed')
  end end
 end
 return reference.capture_only.dx,reference.capture_only.dy
end
-- The pinned helper has two non-native fallback captions. Use independently
-- captured native evidence for affected baseline holders, not the bridge output.
local name_file=assert(io.open(out..'/../../fixtures/areas/native_location_staff_candidate_names.json','r'))
local name_evidence=json.decode(name_file:read('*a'));name_file:close()
local corrected_names={}
for _,row in ipairs(name_evidence.rows)do
 if row.case=='default' and row.profession_name~=row.native_profession then
  corrected_names[row.unit_id]={observed=row.readable_name,native=row.base_name..', '..row.native_profession}
 end
end
local function observed_staff_name(unit)
 local value=dfhack.df2utf(dfhack.units.getReadableName(unit,true))
 local correction=corrected_names[unit.id]
 if correction then
  assert(value==correction.observed,'captured holder-name source changed; refresh native evidence')
  return correction.native
 end
 return value
end
local function staff_names(unit_id,histfig_id,position_name)
 local unit=df.unit.find(unit_id);local hf=df.historical_figure.find(histfig_id)
 return {position_name=position_name or '',holder_kind=unit and 1 or hf and 2 or 0,
  holder_id=unit and unit.id or hf and hf.id or -1,
  holder_name=unit and observed_staff_name(unit)or hf and dfhack.df2utf(dfhack.translation.translateName(hf.name))or ''}
end
local function staff_snapshot(location,kind)
 local result={rows={},missing_roles={}}
 if kind==2 and location.deity_type==df.religious_practice_type.RELIGION_ENID then
  local entity=df.historical_entity.find(location.deity_data.Religion)
  if entity then for _,assignment in ipairs(entity.positions.assignments)do
   local position=require('utils').binsearch(entity.positions.own,assignment.position_id,'id')
   if assignment.st_id==site.id and position then
    local holder=df.historical_figure.find(assignment.histfig)
    result.rows[#result.rows+1]={names=staff_names(holder and holder.unit_id or -1,assignment.histfig,dfhack.df2utf(dfhack.capitalizeStringWords(position.name[0]))),source=1,occupation_id=-1,role=-1,histfig_id=assignment.histfig,unit_id=-1,
     location_id=location.id,site_id=site.id,group_id=-1,entity_id=entity.id,position_id=position.id,assignment_id=assignment.id}
   end
  end end
 end
 local function occupation_row(occupation)
  return {names=staff_names(occupation.unit_id,occupation.histfig_id),source=0,occupation_id=occupation.id,role=occupation.type,histfig_id=occupation.histfig_id,unit_id=occupation.unit_id,
   location_id=occupation.location_id,site_id=occupation.site_id,group_id=occupation.group_id,entity_id=-1,position_id=-1,assignment_id=-1}
 end
 for _,role in ipairs(({[1]={0,1},[2]={1},[3]={2,5},[4]={},[5]={7,8,9,10}})[kind])do
  local empty
  for _,occupation in ipairs(location.occupations)do
   if occupation.type==role and occupation.site_id==site.id and occupation.location_id==location.id then
    if occupation.histfig_id==-1 and occupation.unit_id==-1 then empty=empty or occupation
    else result.rows[#result.rows+1]=occupation_row(occupation)end
   end
  end
  if empty then result.rows[#result.rows+1]=occupation_row(empty)else result.missing_roles[#result.missing_roles+1]=role end
 end
 return result
end
local function affiliation(v,kind)
 if kind~=2 and kind~=4 then return nil end
 local r={kind=1,id=-1,name='',count=0,workers=-1}
 if kind==2 then
  if v.deity_type==df.religious_practice_type.NONE then return r end
  r.kind=v.deity_type+2;r.id=v.deity_data.practice_id
  local owner=r.kind==2 and df.historical_figure.find(r.id)or df.historical_entity.find(r.id)
  r.name=dfhack.df2utf(dfhack.translation.translateName(assert(owner).name,true))
 else
  r.kind=4;r.workers=0
  for _,link in ipairs(site.entity_links)do
   local guild=df.historical_entity.find(link.entity_id)
   if link.flags.capital and guild and guild.type==df.historical_entity_type.Guild then
    for _,focus in ipairs(guild.guild_professions)do
     if focus.type==df.entity_focus_type.PROMOTE_PROFESSION_UNIT and focus.profession==v.contents.profession then
      r.id=guild.id;r.name=dfhack.df2utf(dfhack.translation.translateName(guild.name,true));break
     end
    end
    if r.id>=0 then break end
   end
  end
 end
 local endpoints={WOODWORKER='WOODCUTTER',STONEWORKER='MASON',RANGER='ANIMAL_DISSECTOR',METALSMITH='METALCRAFTER',JEWELER='GEM_SETTER',CRAFTSMAN='STRAND_EXTRACTOR',FISHERY_WORKER='FISH_CLEANER',FARMER='BEEKEEPER',ENGINEER='PUMP_OPERATOR',DOCTOR='SURGEON'}
 local profession=v.contents.profession;local last=df.profession[endpoints[df.profession[profession]]or'']or profession
 for _,unit in ipairs(df.global.world.units.active)do
  if dfhack.units.isActive(unit)and dfhack.units.isFortControlled(unit)then
   if kind==4 and unit.profession>=profession and unit.profession<=last then r.workers=r.workers+1 end
   local hf=df.historical_figure.find(unit.hist_figure_id)
   if hf and r.id>=0 then
    local member=false
    if r.kind==2 then
     for _,link in ipairs(hf.histfig_links)do if link:getType()==df.histfig_hf_link_type.DEITY and link.target_hf==r.id then member=true end end
    else
     for _,link in ipairs(hf.entity_links)do if link:getType()==df.histfig_entity_link_type.MEMBER and link.entity_id==r.id then member=true end end
    end
    if member then r.count=r.count+1 end
   end
  end
 end
 return r
end
local function snapshot()
 local rows={}
 for _,v in ipairs(site.buildings)do
  local kind=({INN_TAVERN=1,TEMPLE=2,LIBRARY=3,GUILDHALL=4,HOSPITAL=5})[df.abstract_building_type[v:getType()]]
  if kind and not v.flags.DOES_NOT_EXIST and not v.flags.WG_RUINED and not v.flags.PWG_RUINED then
   local c=assert(v:getContents())
   local row={site_id=site.id,id=v.id,kind=kind,name=dfhack.df2utf(dfhack.translation.translateName(v.name,true)),
    visitors=v.flags.VISITORS_ALLOWED,residents=v.flags.NON_CITIZENS_ALLOWED,members=v.flags.MEMBERS_ONLY,
    profession=c.profession,tier=c.location_tier,value=c.location_value,desired_copies=c.desired_copies,
    recognized=c.need_more.entity_recognized,appraisal=appraisal(),facilities=facilities(v),written_objects=count_written(v),supplies={},zone_ids={}}
   row.affiliation=affiliation(v,kind)
   row.staff=staff_snapshot(v,kind)
   row.dance_floor_x,row.dance_floor_y=dance_dimensions(v)
   row.access=row.members and 3 or row.visitors and 0 or row.residents and 1 or 2
   for i,key in ipairs(keys)do row.supplies[#row.supplies+1]={kind=i-1,stored=c['count_'..key],desired=c['desired_'..key]}end
   for _,id in ipairs(c.building_ids)do row.zone_ids[#row.zone_ids+1]=id end
   rows[#rows+1]=row
  end
 end
 return {site_id=site.id,rows=rows}
end
local function equal(a,b)
 assert(type(a)==type(b),'access fact type differs')
 if type(a)~='table'then assert(a==b,'access changed unrelated fact');return end
 for k,v in pairs(a)do equal(v,b[k])end
 for k in pairs(b)do assert(a[k]~=nil,'missing access fact')end
end
if phase=='access_begin' then
 assert(not _G.df3d_location_access_probe,'access probe already active')
 local p={before=snapshot(),timers={},counter=df.global.occupation_next_id}
 for _,v in ipairs(site.buildings)do local c=v:getContents();if c then p.timers[v.id]={c.update_timer,c.update_count}end end
 local f=assert(io.open(out..'/../../fixtures/areas/native_location_access.json'));p.reference=json.decode(f:read('*a'));f:close()
 _G.df3d_location_access_probe=p
elseif phase:match('^access_check_') then
 local p=assert(_G.df3d_location_access_probe)
 local id,mode=phase:match('^access_check_(%d+)_(%d+)$');id=assert(tonumber(id));mode=assert(tonumber(mode))
 local action=({'LOCATION_DETAILS_VISITORS_ALLOWED','LOCATION_DETAILS_RESIDENTS_ALLOWED','LOCATION_DETAILS_CITIZENS_ONLY','LOCATION_DETAILS_MEMBERS_ONLY'})[mode+1]
 local expected
 for _,case in ipairs(p.reference.cases)do if case.id==id and case.action==action then expected=case.after.flags;break end end
 assert(expected,'missing independent native reference')
 local now=snapshot()
 for _,row in ipairs(now.rows)do
  if row.id==id then
   assert(row.visitors==expected.VISITORS_ALLOWED and row.residents==expected.NON_CITIZENS_ALLOWED and row.members==expected.MEMBERS_ONLY,'native access flags differ')
  end
  for _,original in ipairs(p.before.rows)do if original.id==row.id then
   row.visitors=original.visitors;row.residents=original.residents;row.members=original.members;row.access=original.access
  end end
 end
 equal(now,p.before)
 for _,v in ipairs(site.buildings)do if p.timers[v.id]then equal({v:getContents().update_timer,v:getContents().update_count},p.timers[v.id])end end
 assert(df.global.occupation_next_id==p.counter,'access allocated staff')
elseif phase=='access_restore' then
 local p=assert(_G.df3d_location_access_probe)
 for _,row in ipairs(p.before.rows)do for _,v in ipairs(site.buildings)do if v.id==row.id then
  v.flags.VISITORS_ALLOWED=row.visitors;v.flags.NON_CITIZENS_ALLOWED=row.residents;v.flags.MEMBERS_ONLY=row.members
 end end end
 equal(snapshot(),p.before);_G.df3d_location_access_probe=nil
elseif phase=='entry_begin' then
 assert(not _G.df3d_location_entry_probe,'entry probe already active')
 local hospital;for _,v in ipairs(site.buildings)do if v:getType()==df.abstract_building_type.HOSPITAL then hospital=v;break end end
 assert(hospital,'hospital missing')
 local p={location=hospital,fields={},local_occupations={},all={},next_id=df.global.occupation_next_id}
 for _,key in ipairs(keys)do p.fields['count_'..key]=hospital.contents['count_'..key]end
 for _,key in ipairs{'location_value','update_timer','update_count'}do p.fields[key]=hospital.contents[key]end
 p.need_more=hospital.contents.need_more.whole
 for _,v in ipairs(hospital.occupations)do p.local_occupations[#p.local_occupations+1]=v end
 for _,v in ipairs(df.global.world.occupations.all)do p.all[#p.all+1]=v end
 _G.df3d_location_entry_probe=p
 hospital.occupations:resize(0)
 hospital.contents.count_cloth=-123456;hospital.contents.update_timer=17;hospital.contents.update_count=31
elseif phase=='entry_fail' then
 assert(_G.df3d_location_entry_probe);df.global.occupation_next_id=2147483647
elseif phase=='entry_recover' then
 local p=assert(_G.df3d_location_entry_probe)
 assert(#p.location.occupations==0 and p.location.contents.count_cloth~=-123456,'partial entry classification differs')
 assert(df.global.occupation_next_id==2147483647,'refused allocation changed counter')
 df.global.occupation_next_id=p.next_id
elseif phase=='entry_after' then
 local p=assert(_G.df3d_location_entry_probe);local v=p.location
 assert(v.contents.count_cloth~=-123456 and v.contents.update_timer==100 and v.contents.update_count==0,'entry cache effects absent')
 assert(#v.occupations==4 and df.global.occupation_next_id==p.next_id+4,'entry slot allocation differs')
 for i,occupation in ipairs(v.occupations)do
  assert(occupation.id==p.next_id+i and occupation.type==7+i,'entry slot identity/order differs')
  assert(occupation.histfig_id==-1 and occupation.unit_id==-1 and occupation.group_id==-1 and occupation.site_id==site.id and occupation.location_id==v.id,'entry defaults differ')
 end
elseif phase=='entry_poll' then
 local p=assert(_G.df3d_location_entry_probe)
 p.location.contents.count_cloth=-123456;p.location.contents.update_timer=17;p.location.contents.update_count=31
elseif phase=='entry_restore' then
 local p=assert(_G.df3d_location_entry_probe);local created={}
 local original={};for _,v in ipairs(p.all)do original[v.id]=true end
 for _,v in ipairs(df.global.world.occupations.all)do if not original[v.id]then created[#created+1]=v end end
 p.location.occupations:resize(0);for _,v in ipairs(p.local_occupations)do p.location.occupations:insert('#',v)end
 df.global.world.occupations.all:resize(0);for _,v in ipairs(p.all)do df.global.world.occupations.all:insert('#',v)end
 for _,v in ipairs(created)do v:delete()end
 df.global.occupation_next_id=p.next_id
 for key,value in pairs(p.fields)do p.location.contents[key]=value end
 p.location.contents.need_more.whole=p.need_more
 _G.df3d_location_entry_probe=nil
elseif phase=='baseline' then
 assert(not _G.df3d_location_details_probe,'details probe already active')
 local hospital
 for _,v in ipairs(site.buildings)do if v:getType()==df.abstract_building_type.HOSPITAL then hospital=v;break end end
 assert(hospital,'hospital fixture absent')
 _G.df3d_location_details_probe={location=hospital,stored=hospital.contents.count_cloth,
  desired=hospital.contents.desired_cloth,visitors=hospital.flags.VISITORS_ALLOWED,before=snapshot()}
elseif phase=='change' then
 local p=assert(_G.df3d_location_details_probe)
 p.affiliation_units={}
 for _,unit in ipairs(df.global.world.units.active)do p.affiliation_units[#p.affiliation_units+1]={ref=unit,value=unit.flags1.inactive} end
 local dance_zone=assert(df.building.find(408));p.dance_cells={}
 for y=0,dance_zone.room.height-1 do for x=0,dance_zone.room.width-1 do
  local px,py=dance_zone.room.x+x,dance_zone.room.y+y;local block=assert(dfhack.maps.getTileBlock(px,py,dance_zone.z));local occ=block.occupancy[px%16][py%16]
  p.dance_cells[#p.dance_cells+1]={ref=occ,value=occ.building};occ.building=1
 end end
 p.written_item=assert(df.item.find(110));p.written_x=p.written_item.pos.x;p.written_item.pos.x=200
 p.staff_occupation=assert(p.location.occupations[0],'staff fixture missing')
 p.staff_histfig=p.staff_occupation.histfig_id;p.staff_group=p.staff_occupation.group_id
 p.staff_occupation.histfig_id=2147483647;p.staff_occupation.group_id=2147483647
 p.location.contents.count_cloth=p.stored+1;p.location.contents.desired_cloth=p.desired+10000
 p.location.flags.VISITORS_ALLOWED=not p.visitors
 p.facility_zone=assert(df.building.find(p.location.contents.building_ids[0]))
 p.original_furniture={};for _,entry in ipairs(p.facility_zone.contained_buildings)do p.original_furniture[#p.original_furniture+1]=entry end
 p.facility_zone.contained_buildings:resize(0)

 local entity=assert(df.global.plotinfo.main.fortress_entity)
 p.assignments=entity.assignments_by_type[df.entity_position_responsibility.TRADE]
 p.original_assignments={};for _,entry in ipairs(p.assignments)do p.original_assignments[#p.original_assignments+1]=entry end
 local unit
 for _,candidate in ipairs(df.global.world.units.active)do
  if dfhack.units.isCitizen(candidate) and candidate.status.current_soul and candidate.hist_figure_id>=0 then unit=candidate;break end
 end
 assert(unit,'appraisal fixture citizen missing')
 p.skills=unit.status.current_soul.skills
 for _,entry in ipairs(p.skills)do if entry.id==df.job_skill.APPRAISAL then p.skill=entry;break end end
 if not p.skill then
  p.skill=df.unit_skill:new();p.skill.id=df.job_skill.APPRAISAL;p.created_skill=true
  require('utils').insert_sorted(p.skills,p.skill,'id')
 end
 p.rating=p.skill.rating;p.rusty=p.skill.rusty;p.skill.rating=15;p.skill.rusty=0
 p.assignment=df.entity_position_assignment:new();p.assignment.histfig=unit.hist_figure_id
 p.assignments:resize(0);p.assignments:insert('#',p.assignment)

 for _,row in ipairs(p.affiliation_units)do row.ref.flags1.inactive=true end
elseif phase=='restore' then
 local p=_G.df3d_location_details_probe
 if p then
  if p.affiliation_units then for _,row in ipairs(p.affiliation_units)do row.ref.flags1.inactive=row.value end end
  if p.staff_occupation then p.staff_occupation.histfig_id=p.staff_histfig;p.staff_occupation.group_id=p.staff_group end
  if p.dance_cells then for _,cell in ipairs(p.dance_cells)do cell.ref.building=cell.value end;p.dance_cells=nil end
  if p.written_item then p.written_item.pos.x=p.written_x end
  if p.facility_zone then
   p.facility_zone.contained_buildings:resize(0)
   for _,entry in ipairs(p.original_furniture)do p.facility_zone.contained_buildings:insert('#',entry)end
  end
  if p.assignments then
   p.assignments:resize(0)
   for _,entry in ipairs(p.original_assignments)do p.assignments:insert('#',entry)end
  end
  if p.assignment then p.assignment:delete();p.assignment=nil end
  if p.skill then
   p.skill.rating=p.rating;p.skill.rusty=p.rusty
   if p.created_skill then
    for i,entry in ipairs(p.skills)do if entry==p.skill then p.skills:erase(i);break end end
    p.skill:delete()
   end
   p.skill=nil
  end
  p.location.contents.count_cloth=p.stored;p.location.contents.desired_cloth=p.desired;p.location.flags.VISITORS_ALLOWED=p.visitors
  local now=snapshot()
  -- Compare concrete fields; JSON object ordering is not an equality contract.
  assert(#now.rows==#p.before.rows,'location population changed')
  local function equal(actual,expected)
   assert(type(actual)==type(expected),'details field type changed')
   if type(actual)~='table' then assert(actual==expected,'details scalar changed');return end
   for key,value in pairs(actual)do equal(value,expected[key])end
   for key in pairs(expected)do assert(actual[key]~=nil,'details field missing')end
  end
  equal(now,p.before)
  _G.df3d_location_details_probe=nil
 end
else error('unknown details phase')end
local f=assert(io.open(out..'/location-details-'..phase..'.json','w'));f:write(json.encode(snapshot()));f:close()
print('LOCATION_DETAILS_REFERENCE_PASS '..phase)
