-- Native observations/assertions. All area commands are sent by the Godot driver.
local out,index=...
local json=require('json')
local B=dfhack.buildings
local function read(path) local f=io.open(path,'r');if not f then return nil end;local s=f:read('*a');f:close();return s end
local function write(path,value) local f=assert(io.open(path,'w'));f:write(json.encode(value));f:close() end
local function restore_link_block()
 local saved=_G.df3d_link_unloaded
 if not saved then return end
 saved.column[saved.z]=saved.block
 assert(dfhack.maps.getTileBlock(saved.x,saved.y,saved.z)==saved.block,'unloaded fixture block restoration')
 _G.df3d_link_unloaded=nil
end
if index=='pause' then df.global.pause_state=true;print('SEMANTIC_PASS paused');return end
local function restore_owner_fact_name()
 local saved=_G.df3d_owner_fact_name
 if saved then saved.unit.name.first_name=saved.name;_G.df3d_owner_fact_name=nil end
end
local function restore_animal_query_name()
 local saved=_G.df3d_animal_query_name
 if saved then
  saved.unit.name.first_name=saved.first_name;saved.unit.name.nickname=saved.nickname;saved.unit.name.has_name=saved.has_name
  _G.df3d_animal_query_name=nil
 end
end
if index=='final' then
 restore_animal_query_name()
 restore_owner_fact_name()
 restore_link_block()
 assert(df.global.pause_state,'DF must be paused before teardown')
 assert(df.global.d_init.feature.autosave==df.d_init_autosave.NONE,'autosave must remain disabled')
 print('SEMANTIC_PASS final paused');return
end
if index=='restore_prefs' then
 assert(df.global.pause_state,'must pause before restoring fixture preferences')
 local saved=_G.df3d_areas_acceptance_prefs
 if saved then
  df.global.d_init.feature.autosave=saved.autosave
  for id,whole in pairs(saved.announcements) do df.global.d_init.announcements.flags[id].whole=whole end
  _G.df3d_areas_acceptance_prefs=nil
 end
 print('SEMANTIC_PASS restored fixture preferences');return
end
local fixture=assert(_G.df3d_areas_acceptance,'fixture missing')
local request=json.decode(assert(read(out..'/request-'..index..'.json')))
local result={status='passed'}
local function array(v,mapper)
 local r={};for _,x in ipairs(v) do r[#r+1]=mapper and mapper(x) or x end;return r
end
local function id(v) return v.id end
local function contains(v,value,field)
 for _,x in ipairs(v) do if (field and x[field] or x)==value then return true end end
 return false
end
local function canonical(v)
 if type(v)~='table' then local s=tostring(v);return type(v)..#s..':'..s end
 local keys={};for k in pairs(v) do keys[#keys+1]=k end
 table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
 local parts={'{'};for _,k in ipairs(keys) do parts[#parts+1]=canonical(k);parts[#parts+1]=canonical(v[k]) end
 parts[#parts+1]='}';return table.concat(parts)
end
-- Pinned native stockpile structs contain scalars, bitfields, fixed arrays and
-- vectors only. Traverse their declared fields, never a viewscreen or adapter.
local function native_value(v,depth)
 if type(v)~='userdata' then return v end
 assert(depth<6,'unexpected native settings nesting')
 local r={}
 for k,x in pairs(v) do
  if type(x)~='function' and tostring(k):sub(1,1)~='_' then r[tostring(k)]=native_value(x,depth+1) end
 end
 return r
end
local function links(b)
 local v=df.building_stockpilest:is_instance(b) and b.links or b:canLinkToStockpile() and b:getStockpileLinks()
 local r={}
 if v then for _,key in ipairs{'give_to_pile','take_from_pile','give_to_workshop','take_from_workshop'} do
  r[key]=array(v[key],id)
 end end
 return r
end
local function area(b)
 local stock=df.building_stockpilest:is_instance(b)
 local r={id=b.id,kind=stock and 0 or 1,name=dfhack.df2utf(B.getName(b)),custom_name=dfhack.df2utf(b.name),
  x=b.x1,y=b.y1,z=b.z,width=b.x2-b.x1+1,height=b.y2-b.y1+1,extents={},tile_count=0,links=links(b)}
 for y=b.y1,b.y2 do for x=b.x1,b.x2 do
  local dx,dy=x-b.room.x,y-b.room.y
  local on=not b.room.extents or dx>=0 and dy>=0 and dx<b.room.width and dy<b.room.height and b.room.extents[dy*b.room.width+dx]~=0
  r.extents[#r.extents+1]=on and 1 or 0;if on then r.tile_count=r.tile_count+1 end
 end end
 if stock then
  r.settings=native_value(b.settings,0);r.barrels=b.storage.max_barrels;r.bins=b.storage.max_bins
  r.wheelbarrows=b.storage.max_wheelbarrows;r.links_only=b.stockpile_flag.use_links_only
  r.organic=b.settings.misc.allow_organic and 1 or 0;r.inorganic=b.settings.misc.allow_inorganic and 1 or 0
 else
  r.overlapping=b.flags.room_collision and 1 or 0
  r.zone_type=b.type;r.active=b.spec_sub_flag.active;r.owner_id=b.assigned_unit_id
  local owner=df.unit.find(b.assigned_unit_id)
  r.owner_name=owner and dfhack.df2utf(dfhack.translation.translateName(dfhack.units.getVisibleName(owner))) or ''
  r.owner_profession=owner and dfhack.df2utf(dfhack.units.getProfessionName(owner)) or ''
  r.owner_sex=owner and owner.sex or -1
  r.site_id=b.site_id;r.location_id=b.location_id;r.assigned_units=array(b.assigned_units)
  r.zone_settings=native_value(b.zone_settings,0)
  r.squads=array(b.squad_room_info,function(s) return {id=s.squad_id,use=s.mode.whole} end)
 end
 return r
end
local function fingerprint(without_settings_id,without_misc)
 local all={areas={},workshops={},cages={},units={},squads={},locations={},next_building=df.global.building_next_id}
 for _,b in ipairs(df.global.world.buildings.all) do
  if df.building_stockpilest:is_instance(b) or df.building_civzonest:is_instance(b) then
   local observed=area(b)
   if b.id==without_settings_id then
    observed.settings=nil
    if without_misc then observed.organic=nil;observed.inorganic=nil end
    -- DF derives an unnamed stockpile's display name from its category flags.
    -- Its stored custom_name remains in the guard.
    if observed.custom_name=='' then observed.name=nil end
   end
   all.areas[#all.areas+1]=observed
  elseif b:canLinkToStockpile() then all.workshops[#all.workshops+1]={id=b.id,links=links(b)} end
  if df.building_cagest:is_instance(b) then all.cages[#all.cages+1]={id=b.id,units=array(b.assigned_units)} end
 end
 for _,u in ipairs(df.global.world.units.active) do
  local refs={}
  for _,ref in ipairs(u.general_refs) do
   if df.general_ref_building_civzone_assignedst:is_instance(ref) then refs[#refs+1]={zone=ref.building_id}
   elseif df.general_ref_contained_in_itemst:is_instance(ref) then refs[#refs+1]={container=ref.item_id} end
  end
  all.units[#all.units+1]={id=u.id,refs=refs}
 end
 for _,s in ipairs(df.global.world.squads.all) do
  all.squads[#all.squads+1]={id=s.id,rooms=array(s.rooms,function(r) return {id=r.building_id,use=r.mode.whole} end)}
 end
 local site=dfhack.world.getCurrentSite()
 if site then
  all.next_location=site.next_building_id
  for _,v in ipairs(site.buildings) do
   local contents=v:getContents()
   local name=v:getName()
   all.locations[#all.locations+1]={id=v.id,kind=v:getType(),name=name and dfhack.translation.translateName(name,true) or '',
    buildings=contents and array(contents.building_ids) or {},value=contents and contents.location_value or -1}
  end
 end
 return canonical(all)
end
local function building() return assert(df.building.find(assert(request.id)),'native building missing') end
local function check_properties(actual,expected,path)
 for key,value in pairs(expected) do
  if type(value)=='table' then check_properties(assert(actual[key],path..'.'..key),value,path..'.'..key)
  else assert(actual[key]==value,path..'.'..key..' mismatch: '..tostring(actual[key])..' / '..tostring(value)) end
 end
end
if request.op=='zone_name_contents' then
 local b=building();assert(df.building_civzonest:is_instance(b) and b.type==df.civzone_type.MeetingHall)
 local saved=_G.df3d_name_fixture
 if not saved then
  saved={id=b.id,members=array(b.contained_buildings),samples={coffin=df.building_coffinst:new(),slab=df.building_slabst:new(),
   statue=df.building_statuest:new(),cage=df.building_cagest:new(),chain=df.building_chainst:new(),display=df.building_display_furniturest:new()}}
  _G.df3d_name_fixture=saved
 end
 assert(saved.id==b.id);b.contained_buildings:resize(0)
 for _,key in ipairs(request.members)do b.contained_buildings:insert('#',assert(saved.samples[key]))end
 result.members=request.members
elseif request.op=='zone_name_restore' then
 local saved=assert(_G.df3d_name_fixture);local b=assert(df.building.find(saved.id));b.contained_buildings:resize(0)
 for _,member in ipairs(saved.members)do b.contained_buildings:insert('#',member)end
 for _,sample in pairs(saved.samples)do sample:delete()end
 _G.df3d_name_fixture=nil
elseif request.op=='overlap_prepare' then
 assert(not _G.df3d_overlap_fixture)
 local p=request.site;local block=assert(dfhack.maps.getTileBlock(p.x,p.y,p.z))
 local saved={block=block,x=p.x%16,y=p.y%16,tile=block.tiletype[p.x%16][p.y%16],guards={}}
 if request.scenario=='wall' then block.tiletype[saved.x][saved.y]=df.tiletype.StoneWall end
 if request.scenario=='door' then
  saved.door=df.building_doorst:new();saved.door.centerx=p.x;saved.door.centery=p.y;saved.door.z=p.z
  df.global.world.buildings.other.DOOR:insert('#',saved.door)
 end
 for _,b in ipairs(df.global.world.map.map_blocks)do
  for _,field in ipairs{'path_cost','path_tag'}do
   local size,address=df.sizeof(b[field]);local copy=df.new('uint8_t',size)
   dfhack.internal.memmove(copy,address,size);saved.guards[#saved.guards+1]={copy=copy,address=address,size=size}
  end
 end
 _G.df3d_overlap_fixture=saved
elseif request.op=='overlap_result' then
 for _,id in ipairs(request.ids)do assert(df.building.find(id).flags.room_collision==request.expected,'overlap differs from native reference')end
 local saved=assert(_G.df3d_overlap_fixture)
 for _,guard in ipairs(saved.guards)do assert(dfhack.internal.memcmp(guard.copy,guard.address,guard.size)==0,'zone creation changed map search scratch')end
 result.scratch_guards=#saved.guards
elseif request.op=='overlap_measure' then
 local saved=assert(_G.df3d_overlap_fixture);local changed=0
 for _,guard in ipairs(saved.guards)do if dfhack.internal.memcmp(guard.copy,guard.address,guard.size)~=0 then changed=changed+1 end end
 result.scratch_guards=#saved.guards;result.changed_guards=changed
 if request.require_unchanged then assert(changed==0,"zone removal changed map search scratch")end
 -- Read-only identity evidence for the removal audit; these addresses never
 -- cross the gameplay protocol and are not runtime command inputs.
 local base=dfhack.internal.getImageBase();result.vectors={}
 for key,value in pairs{units_all=df.global.world.units.all,units_active=df.global.world.units.active,
  items_all=df.global.world.items.all,tax_rooms=df.global.plotinfo.tax_collection.rooms,
  punishments=df.global.plotinfo.punishments,historical_figures=df.global.world.history.figures}do
  local _,address=df.sizeof(value);result.vectors[key]=address-base
 end
elseif request.op=='overlap_clear' then
 local saved=assert(_G.df3d_overlap_fixture)
 for _,guard in ipairs(saved.guards)do df.delete(guard.copy)end
 if saved.door then local doors=df.global.world.buildings.other.DOOR;assert(doors[#doors-1]==saved.door);doors:erase(#doors-1);saved.door:delete()end
 saved.block.tiletype[saved.x][saved.y]=saved.tile;_G.df3d_overlap_fixture=nil
elseif request.op=='zone_owner_prepare' then
 assert(not _G.df3d_zone_owner_fixture)
 local units={}
 for _,u in ipairs(df.global.world.units.active)do
  if dfhack.units.isCitizen(u) and dfhack.units.isActive(u) and not dfhack.units.isDead(u) then
   local tomb=false
   for _,b in ipairs(u.owned_buildings)do
    if df.building_civzonest:is_instance(b) and b.type==df.civzone_type.Tomb then tomb=true end
   end
   if not tomb then units[#units+1]=u end
   if #units==2 then break end
  end
 end
 assert(#units==2,'owner fixture requires two citizens without tombs')
 _G.df3d_zone_owner_fixture={a=units[1],b=units[2],spouse_a=units[1].relationship_ids.Spouse,spouse_b=units[2].relationship_ids.Spouse}
 units[1].relationship_ids.Spouse=units[2].id;units[2].relationship_ids.Spouse=units[1].id
 result.owner_a=units[1].id;result.owner_b=units[2].id
elseif request.op=='owner_fact_name' then
 local unit=assert(df.unit.find(request.unit_id),'missing fact probe unit')
 if not _G.df3d_owner_fact_name then _G.df3d_owner_fact_name={unit=unit,name=unit.name.first_name}end
 assert(_G.df3d_owner_fact_name.unit.id==unit.id,'fact probe unit changed')
 unit.name.first_name=assert(request.name)
 result.unit_id=unit.id
elseif request.op=='owner_fact_restore' then
 restore_owner_fact_name()
elseif request.op=='zone_owner_candidates' then
 local text,code=dfhack.run_command_silent('df3d','zone-owner-candidates-read',tostring(request.id));assert(code==0,text)
 local expected=json.decode(text);local actual={}
 for _,id in ipairs(request.ids)do assert(not actual[id],'duplicate owner candidate');actual[id]=true end
 local order_text,order_code=dfhack.run_command_silent('df3d','zone-owner-order-read',tostring(request.id));assert(order_code==0,order_text)
 local facts=json.decode(order_text)
 local query=request.query_bytes and string.char(table.unpack(request.query_bytes)) or request.query or ''
 if query~='' then
  local normalized,normalized_code=dfhack.run_command_silent('df3d','zone-owner-query-read',query);assert(normalized_code==0,normalized)
  local key=string.char(table.unpack(json.decode(normalized)));local selected={};expected={}
  for _,row in ipairs(facts)do
   if string.char(table.unpack(row[7])):find(key,1,true)then selected[#selected+1]=row;expected[#expected+1]=row[1]end
  end
  facts=selected
 end
 assert(#expected==#request.ids,'owner candidate count differs')
 for _,id in ipairs(expected)do assert(actual[id],'native owner candidate missing')end
 result.query=request.query or ''
 for i,row in ipairs(facts)do row[9]=i end
 table.sort(facts,function(a,b)
  if a[2]~=b[2]then return a[2]>b[2]end
  if a[3]~=b[3]then return a[3]>b[3]end
  local sort=request.sort or 0;local cmp=0
  if sort==1 or sort==3 then
   local x,y=a[sort==1 and 7 or 8],b[sort==1 and 7 or 8]
   for i=1,math.min(#x,#y)do if x[i]~=y[i]then cmp=x[i]-y[i];break end end
   if cmp==0 then cmp=#x-#y end
  elseif sort==4 then cmp=a[6]-b[6]
  else cmp=a[4]-b[4];if cmp==0 then cmp=a[5]-b[5]end end
  if cmp==0 then return a[9]<b[9]end
  return request.descending and cmp>0 or not request.descending and cmp<0
 end)
 for i,row in ipairs(facts)do assert(request.ids[i]==row[1],'native owner order differs at '..i)end
 result.order_exact=true;result.sort=request.sort or 0;result.descending=request.descending or false
 result.count=#expected
   if request.display_rows then
    assert(#request.display_rows==#request.ids,'owner display count differs')
    local function utf(bytes)return dfhack.df2utf(string.char(table.unpack(bytes)))end
    for i,row in ipairs(request.display_rows)do
     assert(row.id==request.ids[i],'owner display identity differs')
     local display=assert(row.owner_display,'native owner display absent')
     assert(display.columns==45,'owner display columns differ')
     local lines,lines_code=dfhack.run_command_silent('df3d','zone-owner-text-read',tostring(row.id),'45');assert(lines_code==0,lines)
     local text=json.decode(lines)
     local status,status_code=dfhack.run_command_silent('df3d','zone-owner-status-read',tostring(request.id),tostring(row.id));assert(status_code==0,status)
     local value=json.decode(status)
     assert(display.first_line==utf(text[4]) and display.second_line==utf(text[5]),'owner display lines differ')
     assert(display.room_value==value[1] and display.status==utf(value[2]),'owner room status differs')
     assert(row.name==utf(text[2]) and row.profession==utf(text[3]),'owner native name/profession differs')
     local color_text,color_code=dfhack.run_command_silent('df3d','zone-owner-name-color-read',tostring(row.id));assert(color_code==0,color_text)
     local expected_color=json.decode(color_text);local color=assert(display.name_color,'owner name color absent')
     assert(color.effect==expected_color.effect,'owner color effect differs')
     for component=1,3 do assert(color.color[component]==expected_color.color[component] and color.alternate[component]==expected_color.alternate[component],'owner color components differ')end
    end
    result.display_rows_exact=#request.display_rows
   end
 result.nonliving_or_noncitizen=-1
 for _,id in ipairs(expected)do
  local u=assert(df.unit.find(id))
  if not dfhack.units.isCitizen(u) or not dfhack.units.isActive(u) or dfhack.units.isDead(u) then result.nonliving_or_noncitizen=id;break end
 end
elseif request.op=='zone_owner_result' then
 local saved=assert(_G.df3d_zone_owner_fixture)
 local b=building();assert(b.assigned_unit_id==request.owner,'native owner differs')
 if request.settings then assert(b.zone_settings.whole.i1==request.settings,'native owner settings differ')end
 for _,entry in ipairs{{saved.a,request.count_a},{saved.b,request.count_b}}do
  local count=0;for _,room in ipairs(entry[1].owned_buildings)do if room.id==b.id then count=count+1 end end
  assert(count==entry[2],'native owner membership differs')
 end
 result.owner=b.assigned_unit_id;result.settings=b.zone_settings.whole.i1
elseif request.op=='zone_owner_clear' then
 local saved=assert(_G.df3d_zone_owner_fixture)
 saved.a.relationship_ids.Spouse=saved.spouse_a;saved.b.relationship_ids.Spouse=saved.spouse_b
 _G.df3d_zone_owner_fixture=nil
elseif request.op=='zone_removal_prepare' then
 local b=building()
 assert(not _G.df3d_zone_removal_fixture,'removal fixture already active')
 local unit=assert(df.global.world.units.active[0],'removal fixture needs a unit')
 local item=assert(df.global.world.items.all[0],'removal fixture needs an item')
 local squad=assert(df.global.world.squads.all[0],'removal fixture needs a squad')
 local hf=assert(df.historical_figure.find(unit.hist_figure_id),'removal fixture needs a historical figure')
 local saved={zone=b,id=b.id,unit=unit,item=item,squad=squad,hf=hf,
  unit_refs=#unit.general_refs,item_refs=#item.general_refs,owners=#unit.owned_buildings,
  squad_rooms=#squad.rooms,hf_links=#hf.site_links,tax_rooms=#df.global.plotinfo.tax_collection.rooms,
  destroy_target=unit.job.destroy_target}
 _G.df3d_zone_removal_fixture=saved
 local function ref(kind,target)
  local r=kind:new();r.building_id=b.id;target:insert('#',r)
 end
 ref(df.general_ref_building_civzone_assignedst,unit.general_refs);b.assigned_units:insert('#',unit.id)
 ref(df.general_ref_building_civzone_assignedst,item.general_refs);b.assigned_items:insert('#',item.id)
 unit.owned_buildings:insert('#',b);unit.owned_buildings:insert('#',b)
 unit.job.destroy_target=b
 local info=df.building_squad_infost:new();info.squad_id=squad.id;b.squad_room_info:insert('#',info)
 for i=1,2 do local room=df.squad_barracks_infost:new();room.building_id=b.id;squad.rooms:insert('#',room)end
 local link=df.histfig_site_link_home_site_saved_civzonest:new();link.site=b.site_id;link.sub_id=b.id
 hf.site_links:insert('#',link);b.home_general_hf:insert('#',hf.id)
 for i=1,2 do df.global.plotinfo.tax_collection.rooms:insert('#',b.id)end
 local punishment=df.punishment:new();punishment.chain=b.id;df.global.plotinfo.punishments:insert('#',punishment);saved.punishment=punishment
 local owned=df.job:new();owned.job_type=df.job_type.ConstructBuilding;owned.posting_index=-1
 ref(df.general_ref_building_holderst,owned.general_refs);assert(dfhack.job.linkIntoWorld(owned,true));b.jobs:insert('#',owned);saved.owned_job=owned.id
 local external=df.job:new();external.job_type=df.job_type.ConstructBuilding;external.posting_index=-1;external.flags.dessource=true
 ref(df.general_ref_building_holderst,external.general_refs);assert(dfhack.job.linkIntoWorld(external,true));saved.external_job=external.id
 result.unit=unit.id;result.item=item.id;result.squad=squad.id;result.historical_figure=hf.id
 result.owned_job=owned.id;result.external_job=external.id
elseif request.op=='zone_removal_result' then
 local saved=assert(_G.df3d_zone_removal_fixture)
 assert(not df.building.find(saved.id),'removed zone remains in all buildings')
 for _,v in pairs(df.global.world.buildings.other)do
  for _,b in ipairs(v)do assert(b.id~=saved.id,'removed zone remains in a typed building list')end
 end
 assert(#saved.unit.general_refs==saved.unit_refs,'assigned unit reference remains')
 assert(#saved.item.general_refs==saved.item_refs,'assigned item reference remains')
 assert(#saved.unit.owned_buildings==saved.owners,'duplicate ownership pointers remain')
 assert(saved.unit.job.destroy_target==nil,'destroy target remains')
 assert(#saved.squad.rooms==saved.squad_rooms,'reciprocal squad rooms remain')
 assert(#saved.hf.site_links==saved.hf_links,'historical-figure site link remains')
 assert(#df.global.plotinfo.tax_collection.rooms==saved.tax_rooms,'tax-room entries remain')
 assert(saved.punishment.chain==-1,'punishment chain remains')
 local function find_job(id)
  local link=df.global.world.jobs.list.next
  while link do if link.item and link.item.id==id then return link.item end;link=link.next end
 end
 assert(not find_job(saved.owned_job),'owned job not retired')
 local external=assert(find_job(saved.external_job),'independent job incorrectly retired')
 assert(#external.general_refs==0,'independent job holder reference remains')
 saved.unit.job.destroy_target=saved.destroy_target
 assert(dfhack.job.removeJob(external),'fixture independent-job cleanup failed')
 local punishments=df.global.plotinfo.punishments
 assert(punishments[#punishments-1]==saved.punishment);punishments:erase(#punishments-1);saved.punishment:delete()
 result.effects={'typed registration','assigned unit','assigned item','duplicate ownership','destroy target',
  'duplicate squad rooms','historical-figure link','duplicate tax rooms','punishment chain','owned job','independent job reference'}
 _G.df3d_zone_removal_fixture=nil
elseif request.op=='zone_location_prepare' then
 local b=building();local site=assert(dfhack.world.getCurrentSite())
 assert(not _G.df3d_zone_location_fixture)
 local location=df.abstract_building_inn_tavernst:new()
 location.id=(#site.buildings>0 and site.buildings[#site.buildings-1].id or -1)+1
 location.site_id=site.id;site.buildings:insert('#',location)
 _G.df3d_zone_location_fixture={zone=b,site=site,location=location,old_site=b.site_id,old_location=b.location_id}
 b.site_id=site.id;b.location_id=location.id;location.contents.building_ids:insert('#',b.id)
 location.contents.location_value=654321;location.contents.count_goblets=123
 location.contents.update_timer=13;location.contents.update_count=19
elseif request.op=='zone_location_result' then
 local saved=assert(_G.df3d_zone_location_fixture);local c=saved.location.contents
 result.value=c.location_value;result.goblets=c.count_goblets
 result.update_timer=c.update_timer;result.update_count=c.update_count
 -- Native212941: the empty/floor-only location remains zero-valued; each
 -- actual erase/regrow replaces poisoned caches and resets the scheduler.
 assert(c.location_value==0 and c.count_goblets==0 and c.update_timer==100 and c.update_count==0,'location repaint effects differ from native')
 c.location_value=654321;c.count_goblets=123;c.update_timer=13;c.update_count=19
elseif request.op=='zone_location_clear' then
 local saved=assert(_G.df3d_zone_location_fixture)
 saved.zone.site_id=saved.old_site;saved.zone.location_id=saved.old_location
 local values=saved.site.buildings;assert(values[#values-1]==saved.location)
 values:erase(#values-1);saved.location:delete();_G.df3d_zone_location_fixture=nil
elseif request.op=='zone_membership_site' then
 for _,candidate in ipairs(df.global.world.buildings.other.IN_PLAY)do
  if candidate:canMakeRoom() then
   local flags=dfhack.maps.getTileFlags(candidate.x1,candidate.y1,candidate.z)
   if flags and not flags.hidden then
    result.x=candidate.x1;result.y=candidate.y1;result.z=candidate.z;result.member_id=candidate.id;break
   end
  end
 end
 assert(result.member_id,'no visible room-defining building')
elseif request.op=='zone_publication' then
 local b=building()
 local function occurrences(values,want)
  local n=0;for _,v in ipairs(values)do if v==want then n=n+1 end end;return n
 end
 for _,values in ipairs{df.global.world.buildings.all,df.global.world.buildings.other.IN_PLAY,df.global.world.buildings.other.ANY_ZONE}do
  assert(occurrences(values,b)==1,'zone registration missing or duplicated')
 end
 assert(b.flags.exists and b.spec_sub_flag.active and b.race==df.global.plotinfo.race_id)
 assert(b.zone_num>0 and b.id<df.global.building_next_id)
 assert(b.centerx==(b.x1+b.x2)//2 and b.centery==(b.y1+b.y2)//2,'zone center differs')
 local expected=0
 for _,candidate in ipairs(df.global.world.buildings.other.IN_PLAY)do
  local included=candidate~=b and candidate:canMakeRoom() and candidate.z==b.z and B.containsTile(b,candidate.x1,candidate.y1)
  assert(occurrences(b.contained_buildings,candidate)==(included and 1 or 0),'zone membership differs')
  assert(occurrences(candidate.relations,b)==(included and 1 or 0),'reciprocal room membership differs')
  if included then expected=expected+1 end
 end
 assert(#b.contained_buildings==expected,'unexpected zone member')
 if request.member_id then assert(occurrences(b.contained_buildings,df.building.find(request.member_id))==1,'required room member absent') end
 result.members=expected;result.id=b.id;result.zone_num=b.zone_num
elseif request.op=='archery_prepare' then
 assert(not _G.df3d_archery_target,'previous target fixture still active')
 local p=request.target
 local target=df.building_archerytargetst:new()
 target.x1=p.x;target.x2=p.x;target.centerx=p.x
 target.y1=p.y;target.y2=p.y;target.centery=p.y;target.z=p.z
 local targets=df.global.world.buildings.other.ARCHERY_TARGET
 targets:insert('#',target)
 _G.df3d_archery_target={target=target,index=#targets-1,x=p.x,y=p.y,z=p.z}
elseif request.op=='archery_clear' then
 local saved=assert(_G.df3d_archery_target)
 local targets=df.global.world.buildings.other.ARCHERY_TARGET
 assert(targets[saved.index]==saved.target and #targets==saved.index+1,'target list changed')
 assert(saved.target.centerx==saved.x and saved.target.centery==saved.y and saved.target.z==saved.z,'creation changed target')
 targets:erase(saved.index);saved.target:delete();_G.df3d_archery_target=nil
elseif request.op=='pile_designations' then
 local b=building()
 for y=0,b.room.height-1 do for x=0,b.room.width-1 do
  if b.room.extents[y*b.room.width+x]~=0 then
   local tx,ty=b.room.x+x,b.room.y+y
   local block=assert(dfhack.maps.getTileBlock(tx,ty,b.z))
   assert(block.designation[tx%16][ty%16].pile,'created stockpile missing pile designation')
  end
 end end
elseif request.op=='link_rows' then
 local b=building();local expected={}
 -- Order verified by native renderer and four-group pointer oracle.
 for _,group in ipairs{{'take_from_workshop',2,2},{'give_to_workshop',2,1},{'take_from_pile',0,2},{'give_to_pile',0,1}} do
  for _,target in ipairs(b.links[group[1]])do
   expected[#expected+1]={id=target.id,kind=group[2],direction=group[3],name=dfhack.df2utf(B.getName(target))}
  end
 end
 assert(#expected==#request.rows,'link row count')
 for index,row in ipairs(expected)do check_properties(request.rows[index],row,'link row '..index)end
elseif request.op=='link_overlap_prepare' then
 assert(df.global.pause_state and not _G.df3d_link_overlap)
 local saved={}
 for _,target in ipairs(request.targets) do
  local b=assert(df.building.find(target));assert(df.building_stockpilest:is_instance(b))
  assert(b.room.width==1 and b.room.height==1 and b.room.extents[0]==1)
  saved[#saved+1]={id=target,x1=b.x1,x2=b.x2,y1=b.y1,y2=b.y2,z=b.z,
   centerx=b.centerx,centery=b.centery,rx=b.room.x,ry=b.room.y}
  b.x1=request.x;b.x2=request.x;b.y1=request.y;b.y2=request.y;b.z=request.z
  b.centerx=request.x;b.centery=request.y;b.room.x=request.x;b.room.y=request.y
 end
 _G.df3d_link_overlap=saved
elseif request.op=='link_overlap_restore' then
 assert(df.global.pause_state)
 for _,s in ipairs(assert(_G.df3d_link_overlap)) do
  local b=assert(df.building.find(s.id))
  b.x1=s.x1;b.x2=s.x2;b.y1=s.y1;b.y2=s.y2;b.z=s.z
  b.centerx=s.centerx;b.centery=s.centery;b.room.x=s.rx;b.room.y=s.ry
 end
 _G.df3d_link_overlap=nil
elseif request.op=='link_unloaded_prepare' then
 assert(df.global.pause_state and not _G.df3d_link_unloaded)
 local block=assert(dfhack.maps.getTileBlock(request.x,request.y,request.z))
 local source=building()
 assert(dfhack.maps.getTileBlock(source.centerx,source.centery,source.z)~=block,'source must stay loaded')
 local column=df.global.world.map.block_index[request.x//16][request.y//16]
 assert(column[request.z]==block,'block lookup identity')
 -- Keep the block owned by map_blocks; only its lookup slot is absent. Never
 -- free it, change its contents, or save this paused fixture.
 _G.df3d_link_unloaded={column=column,block=block,x=request.x,y=request.y,z=request.z}
 column[request.z]=nil
 assert(not dfhack.maps.getTileBlock(request.x,request.y,request.z),'block remained available')
elseif request.op=='link_unloaded_restore' then
 assert(_G.df3d_link_unloaded,'missing unloaded fixture')
 restore_link_block()
elseif request.op=='link_hidden_prepare' then
 assert(df.global.pause_state and not _G.df3d_link_hidden)
 local block=assert(dfhack.maps.getTileBlock(request.x,request.y,request.z))
 local x,y=request.x%16,request.y%16
 _G.df3d_link_hidden={block=block,x=x,y=y,whole=block.designation[x][y].whole}
 block.designation[x][y].hidden=true
elseif request.op=='link_hidden_restore' then
 local s=assert(_G.df3d_link_hidden)
 s.block.designation[s.x][s.y].whole=s.whole;_G.df3d_link_hidden=nil
elseif request.op=='transfer_links' then
 assert(not df.building.find(request.deleted),'empty donor still exists')
 for _,survivor in ipairs(request.survivors)do
  local observed=links(assert(df.building.find(survivor)))
  for _,rows in pairs(observed)do for _,target in ipairs(rows)do assert(target~=request.deleted,'deleted donor remains linked')end end
 end
elseif request.op=='creation_noop_prepare' then
 assert(df.global.pause_state)
 local block=assert(dfhack.maps.getTileBlock(request.x,request.y,request.z))
 local x,y=request.x%16,request.y%16
 assert(not block.designation[x][y].pile and block.occupancy[x][y].building==0)
 _G.df3d_creation_noop={block=block,x=x,y=y,occupancy=block.occupancy[x][y].whole,
  next_id=df.global.building_next_id,count=#df.global.world.buildings.all}
 block.occupancy[x][y].building=1
elseif request.op=='creation_noop_restore' then
 local s=assert(_G.df3d_creation_noop)
 assert(df.global.building_next_id==s.next_id and #df.global.world.buildings.all==s.count,'all-clipped gesture allocated a building')
 s.block.occupancy[s.x][s.y].whole=s.occupancy
 _G.df3d_creation_noop=nil
elseif request.op=='guard_before' then
 assert(df.global.pause_state,'refusal guard requires paused fortress')
 _G.df3d_areas_guard=fingerprint()
elseif request.op=='guard_after' then
 assert(df.global.pause_state,'refusal guard requires paused fortress')
 assert(_G.df3d_areas_guard==fingerprint(),'refusal changed native area state')
elseif request.op=='header_setup' then
 local b=building();assert(df.global.pause_state)
 if request.category=='' then
  b.settings.misc.allow_organic=false;b.settings.misc.allow_inorganic=true
  b.settings.refuse.type:resize(2);b.settings.corpses.corpses:resize(2)
  for i=0,1 do b.settings.refuse.type[i]=1-i;b.settings.corpses.corpses[i]=i end
  b.settings.flags.refuse=request.enabled;b.settings.flags.corpses=request.enabled
 else
  local text,code=dfhack.run_command_silent('df3d','stockpile-header-read',tostring(b.id),'0','1')
  assert(code==0,text)
  for field in pairs(json.decode(text).vectors)do
   local cat,key=field:match('^([^%.]+)%.(.+)$')
   if cat==request.category then local values=b.settings[cat][key];values:resize(math.min(1,#values))end
  end
  b.settings.flags[request.category]=false
 end
elseif request.op=='category_before' or request.op=='header_before' then
 assert(df.global.pause_state,'category guard requires paused fortress')
 local b=building()
 local categories={'animals','food','furniture','corpses','refuse','stone','ammo','coins',
  'bars_blocks','gems','finished_goods','leather','cloth','wood','weapons','armor','sheet'}
 local header=request.op=='header_before'
 local bit=header and request.category=='' and 0 or nil
 for i,key in ipairs(categories)do if key==request.category then bit=1 << (i-1)end end
 assert(bit,'category guard requires explicit category')
 local text,code
 if header then text,code=dfhack.run_command_silent('df3d','stockpile-header-read',tostring(b.id),tostring(bit),tostring(request.value))
 else text,code=dfhack.run_command_silent('df3d','stockpile-category-read',tostring(b.id),tostring(bit))end
 assert(code==0,text)
 _G.df3d_category_guard={id=b.id,category=request.category,header=header,expected=json.decode(text),other=fingerprint(b.id,header)}
elseif request.op=='category_after' or request.op=='header_after' then
 local b=building();local before=assert(_G.df3d_category_guard)
 assert(df.global.pause_state and before.id==b.id and before.category==request.category,'category guard identity changed')
 assert(b.settings.flags.whole==before.expected.flags,'category flags differ from native selection')
 for kind,fields in pairs{vectors=before.expected.vectors,fixed=before.expected.fixed}do
  for key,values in pairs(fields)do
   local cat,name=key:match('^([^%.]+)%.(.+)$');local actual=b.settings[cat][name]
   if kind=='vectors'then assert(#actual==#values,'category vector length '..key)end
   if kind=='fixed' and #values==1 then assert(actual==values[1],'category fixed '..key)
   else for i,value in ipairs(values)do assert(actual[i-1]==value,'category value '..key..' '..i)end end
  end
 end
 assert(before.other==fingerprint(b.id,before.header),'category selection changed unrelated native state')
elseif request.op=='snapshot' then
 result.area=area(building());if request.expected then check_properties(result.area,request.expected,'area') end
elseif request.op=='global_all_prepare' then
 assert(df.global.pause_state,'global All fixture requires paused fortress')
 local b=building();local enabled=request.enabled==true
 b.settings.flags.refuse=enabled;b.settings.flags.corpses=enabled;b.settings.flags.ammo=false
 b.settings.refuse.type[0]=1;b.settings.refuse.type[1]=0
 b.settings.corpses.corpses[0]=1;b.settings.corpses.corpses[1]=0
 b.settings.refuse.fresh_raw_hide=true;b.settings.refuse.rotten_raw_hide=false
 b.settings.misc.allow_organic=false;b.settings.misc.allow_inorganic=false
 b.settings.ammo.quality_core[0]=false
 _G.df3d_global_all_excluded={enabled=enabled,refuse=canonical(native_value(b.settings.refuse,0)),corpses=canonical(native_value(b.settings.corpses,0))}
elseif request.op=='global_all_verify' then
 local b=building();local before=assert(_G.df3d_global_all_excluded)
 assert(b.settings.flags.refuse==before.enabled and b.settings.flags.corpses==before.enabled,'global All changed excluded category flags')
 assert(before.refuse==canonical(native_value(b.settings.refuse,0)) and before.corpses==canonical(native_value(b.settings.corpses,0)),'global All changed excluded filters')
 for _,cat in ipairs{'animals','food','furniture','stone','ammo','coins','bars_blocks','gems','finished_goods','leather','cloth','wood','weapons','armor','sheet'} do
  assert(b.settings.flags[cat],'global All omitted category '..cat)
 end
 for i=0,6 do assert(b.settings.ammo.quality_core[i],'global All omitted quality grade') end
 assert(b.settings.misc.allow_organic and b.settings.misc.allow_inorganic,'global All omitted misc toggles')
elseif request.op=='global_none_prepare' then
 assert(df.global.pause_state,'global None fixture requires paused fortress')
 local b=building()
 b.settings.flags.ammo=true;b.settings.flags.armor=true;b.settings.flags.food=false
 b.settings.misc.allow_organic=request.organic==true;b.settings.misc.allow_inorganic=request.organic~=true
 _G.df3d_global_none_misc={b.settings.misc.allow_organic,b.settings.misc.allow_inorganic}
 b.settings.ammo.quality_core[0]=true;b.settings.refuse.fresh_raw_hide=true
 _G.df3d_global_none_flags=canonical(native_value(b.settings.flags,0))
 result.area=area(b)
elseif request.op=='global_none_verify' then
 local b=building()
 assert(_G.df3d_global_none_flags==canonical(native_value(b.settings.flags,0)),'global None changed category flags')
 assert(b.settings.misc.allow_organic==_G.df3d_global_none_misc[1] and b.settings.misc.allow_inorganic==_G.df3d_global_none_misc[2],'global None changed misc header toggles')
 for i=0,6 do assert(not b.settings.ammo.quality_core[i],'global None left a quality grade on') end
 assert(not b.settings.refuse.fresh_raw_hide and not b.settings.refuse.rotten_raw_hide,'global None left hide filters on')
 result.area=area(b)
elseif request.op=='external_parchment_change' then
 assert(df.global.pause_state,'external settings acceptance requires paused fortress')
 local b=building();local count=#df.global.world.raws.mat_table.organic_types[df.organic_mat_category.Parchment]
 assert(type(request.raw_index)=='number' and request.raw_index>=0 and request.raw_index<count,'invalid parchment fixture index')
 if #b.settings.sheet.parchment<count then b.settings.sheet.parchment:resize(count) end
 b.settings.sheet.parchment[request.raw_index]=1
 result.area=area(b)
elseif request.op=='external_material_change' then
 assert(df.global.pause_state,'external settings acceptance requires paused fortress')
 local b=building();assert(#b.settings.ammo.other_mats==2,'expected initialized material vector')
 b.settings.ammo.other_mats[0]=0;b.settings.ammo.other_mats[1]=1
 result.area=area(b)
elseif request.op=='external_hide_change' then
 assert(df.global.pause_state,'external settings acceptance requires paused fortress')
 local b=building();assert(df.building_stockpilest:is_instance(b),'expected owned fixture stockpile')
 b.settings.refuse.fresh_raw_hide=request.fresh~=false
 b.settings.refuse.rotten_raw_hide=request.fresh==false
 result.area=area(b)
elseif request.op=='wood' then
 local b=building();local rows={}
 -- Use DF's owned Wood row producer: native skips absent vector entries and
 -- owns captions/order. Raw enumeration fabricates rows for empty settings.
 local text,code=dfhack.run_command_silent('df3d','stockpile-wood-read',tostring(b.id))
 assert(code==0,text)
 for _,row in ipairs(json.decode(text))do
  if row.visible then rows[#rows+1]={key='wood/'..row.index,index=row.index,label=row.name,
   state=row.enabled and 2 or 1,kind=4,estimated=false}end
 end
 if request.rows then assert(canonical(rows)==canonical(request.rows),'wood page differs from native row producer') end
 if request.value then for _,row in ipairs(rows) do
  if not request.row_key or request.row_key==row.key then assert(row.state==request.value,'wood filter did not change') end
 end end
 result.rows=rows
elseif request.op=='preset' then
 local b=building();local cats={'animals','food','furniture','corpses','refuse','stone','ammo','coins','bars_blocks','gems','finished_goods','leather','cloth','wood','weapons','armor','sheet'}
 for _,key in ipairs(cats) do
  -- The pinned All preset excludes Corpses and Refuse (E9 finding1 and
  -- native pointer receipt131047); SettingsSet/All is a different operation.
  local enabled=request.preset==1 and key~='corpses' and key~='refuse' or request.category==key
  assert(b.settings.flags[key]==enabled,'preset category '..key)
 end
 local retained=request.retained or {barrels=2,bins=1,wheelbarrows=1,links_only=true}
 local tiles=0
 for y=b.y1,b.y2 do for x=b.x1,b.x2 do if dfhack.buildings.containsTile(b,x,y) then tiles=tiles+1 end end end
 local barrels,bins,wheelbarrows=0,0,0
 if request.preset==1 then barrels=tiles//2;bins=(tiles+1)//2;wheelbarrows=1
 elseif request.preset==3 then barrels=tiles
 elseif request.preset==7 then wheelbarrows=1
 elseif (request.preset>=8 and request.preset<=14) or (request.preset>=16 and request.preset<=18)then bins=tiles end
 assert(b.storage.max_barrels==barrels and b.storage.max_bins==bins and
  b.storage.max_wheelbarrows==wheelbarrows and b.stockpile_flag.use_links_only==retained.links_only,
  'preset native container defaults/links-only differ')
 result.area=area(b)
elseif request.op=='zone_settings' then
 local b=building();local v=b.zone_settings;local actual={}
 local typ=df.civzone_type[b.type]
 if typ=='Pen' then actual.check_occupants=v.pen.flags.check_occupants
 elseif typ=='Pond' then actual.pond_mode=v.pond.flag.keep_filled and 2 or 1;actual.check_occupants=v.pond.flag.check_occupants
 elseif typ=='ArcheryRange' then
  local x,y=v.archery.dir_x,v.archery.dir_y
  actual.facing=x==-1 and y==0 and 1 or x==1 and y==0 and 2 or x==0 and y==-1 and 3 or x==0 and y==1 and 4 or 0
 elseif typ=='Tomb' then actual.tomb_citizens=v.tomb.flags.no_citizens and 0 or 1;actual.tomb_pets=v.tomb.flags.no_pets and 0 or 1
 elseif typ=='PlantGathering' then actual.gather_trees=v.gather.flags.pick_trees and 1 or 0;actual.gather_shrubs=v.gather.flags.pick_shrubs and 1 or 0;actual.gather_fallen=v.gather.flags.gather_fallen and 1 or 0 end
 check_properties(actual,request.expected,'zone_settings')
elseif request.op=='animal_restraint_begin' then
 assert(not _G.df3d_restraint_fixture,'restraint fixture already active')
 local u=assert(df.unit.find(request.unit_id));local m=assert(dfhack.matinfo.find('INORGANIC:COPPER'))
 local items=dfhack.items.createItem(u,df.item_type.CHAIN,-1,m.type,m.index);assert(#items==1)
 local chain=df.building_chainst:new();chain.id=df.global.building_next_id;df.global.building_next_id=chain.id+1
 chain.centerx=u.pos.x;chain.centery=u.pos.y;chain.z=u.pos.z;chain.x1=u.pos.x;chain.x2=u.pos.x;chain.y1=u.pos.y;chain.y2=u.pos.y
 local contained=df.buildingitemst:new();contained.item=items[1];chain.contained_items:insert('#',contained)
 df.global.world.buildings.all:insert('#',chain);df.global.world.buildings.other.CHAIN:insert('#',chain)
 local ref=df.general_ref_building_chainst:new();ref.building_id=chain.id
 _G.df3d_restraint_fixture={unit=u,flags=u.flags1.whole,ref=ref,chain=chain,item=items[1],contained=contained}
 u.general_refs:insert('#',ref);u.flags1.chained=true
 result.unit=u.id;result.item=items[1].id
elseif request.op=='animal_restraint_material' then
 local saved=assert(_G.df3d_restraint_fixture);local token=({'INORGANIC:COPPER','PLANT:GRASS_TAIL_PIG:THREAD'})[request.variant+1]
 if not token then
  local flag=assert(({[2]='LEATHER',[3]='SILK',[4]='YARN'})[request.variant])
  for _,raw in ipairs(df.global.world.raws.creatures.all)do
   for _,mat in ipairs(raw.material)do if mat.flags[flag]then token='CREATURE:'..raw.creature_id..':'..mat.id;break end end
   if token then break end
  end
 end
 local material=assert(dfhack.matinfo.find(assert(token)));saved.item.mat_type=material.type;saved.item.mat_index=material.index
 result.item=saved.item.id;result.token=token
elseif request.op=='animal_restraint_end' then
 local saved=assert(_G.df3d_restraint_fixture)
 for i=#saved.unit.general_refs-1,0,-1 do if saved.unit.general_refs[i]==saved.ref then saved.unit.general_refs:erase(i);break end end
 saved.ref:delete();saved.unit.flags1.whole=saved.flags
 for _,values in ipairs{df.global.world.buildings.all,df.global.world.buildings.other.CHAIN}do
  for i=#values-1,0,-1 do if values[i]==saved.chain then values:erase(i);break end end
 end
 saved.chain.contained_items:erase(0);saved.contained:delete();saved.chain:delete();assert(dfhack.items.remove(saved.item))
 _G.df3d_restraint_fixture=nil;result.restored=true
elseif request.op=='animal_vermin_fixture' then
 assert(df.global.pause_state,'VERMIN fixture requires paused disposable session')
 local original=assert(df.item.find(request.item_id))
 local extra=df.item_verminst:new()
 extra.id=df.global.item_next_id;df.global.item_next_id=extra.id+1
 extra.race=original.race;extra.caste=original.caste
 extra.flags.whole=original.flags.whole;extra.flags2.whole=original.flags2.whole
 extra.pos:assign(original.pos)
 df.global.world.items.all:insert('#',extra)
 df.global.world.items.other.ANY_CRITTER:insert('#',extra)
 df.global.world.items.other.VERMIN:insert('#',extra)
 local cage=assert(df.global.world.buildings.other.CAGE[0])
 local ref=df.general_ref_building_cagedst:new();ref.building_id=cage.id
 extra.general_refs:insert('#',ref);cage.assigned_items:insert('#',extra.id)
 assert(extra:isLiveAnimal(),'VERMIN fixture must be alive')
 -- Retain allocation until unsaved exit; picker membership can retain its pointer.
 result.item_id=extra.id;result.cage_id=cage.id;result.item_type='VERMIN'
elseif request.op=='animal_long_list' then
 assert(df.global.pause_state,'long animal fixture requires paused disposable session')
 local original=assert(df.item.find(request.item_id))
 local pet=df.item_petst:is_instance(original)
 assert(pet or df.item_verminst:is_instance(original),'long animal fixture requires critter item')
 local ids={}
 for index=1,64 do
  local extra=pet and df.item_petst:new() or df.item_verminst:new()
  extra.id=df.global.item_next_id;df.global.item_next_id=extra.id+1
  extra.race=original.race;extra.caste=original.caste
  extra.flags.whole=original.flags.whole;extra.flags2.whole=original.flags2.whole
  extra.pos:assign(original.pos)
  df.global.world.items.all:insert('#',extra)
  df.global.world.items.other.ANY_CRITTER:insert('#',extra)
  df.global.world.items.other[pet and 'PET' or 'VERMIN']:insert('#',extra)
  ids[#ids+1]=extra.id
 end
 -- Keep allocations valid for retained native widget entries until unsaved exit.
 result.ids=ids
elseif request.op=='animal_query_name' then
 local unit=assert(df.unit.find(request.unit_id));assert(not _G.df3d_animal_query_name)
 _G.df3d_animal_query_name={unit=unit,first_name=unit.name.first_name,nickname=unit.name.nickname,has_name=unit.name.has_name}
 unit.name.first_name=string.char(195,169)..'ByteProbe';unit.name.nickname='';unit.name.has_name=true;result.unit_id=unit.id
elseif request.op=='animal_query_restore' then
 restore_animal_query_name();result.restored=true
elseif request.op=='animal_candidates' then
 local b=building()
 local query=request.query_bytes and string.char(table.unpack(request.query_bytes)) or dfhack.utf2df(request.query or '')
 local text,code=dfhack.run_command_silent('df3d','zone-animal-picker-read',tostring(b.id),tostring(request.sort or 0),request.descending and '1' or '0',query)
 assert(code==0,text)
 local expected=require('json').decode(text)
 if request.limit then
  local selected={}
  for index=request.first+1,math.min(#expected,request.first+request.limit)do selected[#selected+1]=expected[index]end
  expected=selected
 end
 assert(#expected==#request.rows,'native animal candidate count differs')
 for i,entry in ipairs(expected)do
  local row=request.rows[i]
  assert(row.id==entry.id and row.entity==entry.kind+1 and row.assigned==entry.assigned,
   'native animal candidate identity/order/assignment differs')
  local status_text,status_code=dfhack.run_command_silent('df3d','zone-animal-status-read',tostring(b.id),tostring(row.entity),tostring(row.id))
  assert(status_code==0,status_text)
  local native_status=require('json').decode(status_text)
  assert(row.animal_status and row.animal_status.kind==native_status.kind and row.animal_status.containment==native_status.containment and row.animal_status.item_id==native_status.item_id,'native animal status transport differs')
  if native_status.kind==4 and df.item.find(native_status.item_id):getType()==df.item_type.CAGE then
   local data,rc=dfhack.run_command_silent('df3d','zone-animal-container-read',tostring(native_status.item_id))
   assert(rc==0,data);local expected_container=require('json').decode(data);local actual=row.animal_container
   assert(actual,'cage facts absent from Godot row')
   for _,key in ipairs{'material_family','solid_color','occupant_entity','occupant_id'}do
    assert(actual[key]==expected_container[key],'cage fact changed in transport: '..key)
   end
   if actual.occupant_entity~=0 then assert(actual.occupant and #actual.occupant.layers>0,'owned cage occupant recipe absent') end
  else assert(not row.animal_container,'non-cage received cage facts') end
  if native_status.kind==4 and df.item.find(native_status.item_id):getType()==df.item_type.CHAIN then
   local data,rc=dfhack.run_command_silent('df3d','zone-animal-restraint-read',tostring(native_status.item_id));assert(rc==0,data)
   local facts=require('json').decode(data)
   assert(row.animal_restraint and row.animal_restraint.rope==facts.rope and row.animal_restraint.solid_color==facts.solid_color,'native restraint transport differs')
  else assert(not row.animal_restraint,'non-restraint received restraint facts')end
  if entry.kind==1 then
   local value,status=dfhack.run_command_silent('df3d','zone-animal-item-text-read',tostring(entry.id))
   assert(status==0,value)
   local bytes=require('json').decode(value)
   assert(row.name==dfhack.df2utf(string.char(table.unpack(bytes))),'native animal item text differs')
   assert(not row.animal_display,'item received unit display')
   local color_text,color_status=dfhack.run_command_silent('df3d','zone-animal-item-color-read',tostring(entry.id))
   assert(color_status==0,color_text);local color=require('json').decode(color_text)
   assert(row.animal_item_color and row.animal_item_color.foreground==color[1] and
    row.animal_item_color.background==color[2] and row.animal_item_color.bright==color[3],'native item color transport differs')
   assert(row.sheet_icon and #row.sheet_icon.layers==1,'animal item selector recipe absent')
   local item=assert(df.item.find(entry.id))
   local creature=assert(df.global.world.raws.creatures.all[item:getMaterial()])
   local caste=item:getMaterialIndex()>=0 and creature.caste[item:getMaterialIndex()] or nil
   local graphics=caste and caste.caste_graphics or nil
   if not graphics or graphics.creature_small_texpos[0]==0 then graphics=creature.graphics end
   local tile=assert(graphics).creature_small_texpos[0];assert(tile>0,'fixture needs original critter art')
   local matched=false
   for _,page in ipairs(df.global.texture.page)do
    for index,value in ipairs(page.texpos)do if value==tile then
     local layer=row.sheet_icon.layers[1]
     assert(row.sheet_icon.tile_pages[layer[1]+1]==page.token and
      layer[2]==index%page.page_dim_x and layer[3]==index//page.page_dim_x,
      'native critter tile differs from transported recipe')
     matched=true;break
    end end
    if matched then break end
   end
   assert(matched,'native critter tile page absent')

  else
   local value,status=dfhack.run_command_silent('df3d','zone-animal-unit-display-read',tostring(entry.id),'27')
   assert(status==0,value);local native=require('json').decode(value)
   local function utf(bytes)return dfhack.df2utf(string.char(table.unpack(bytes)))end
   assert(row.sheet_icon and #row.sheet_icon.layers>0,'animal unit selector recipe absent')
   local d=assert(row.animal_display,'animal display absent')
   assert(d.columns==27 and d.first_line==utf(native.text[4]) and d.second_line==utf(native.text[5]),'animal native lines differ')
   assert(d.combined_fits==(#native.text[1]<=27) and d.warning==utf(native.warning) and row.grazer==native.grazer,'animal layout facts differ')
   assert(row.name==utf(native.text[1]) and row.profession==utf(native.text[3]),'animal native name/profession differ')
   assert(d.name_color.effect==native.name_color.effect,'animal color effect differs')
   for component=1,3 do
    assert(d.name_color.color[component]==native.name_color.color[component] and
     d.name_color.alternate[component]==native.name_color.alternate[component],'animal color differs')
   end
  end
 end
 result.count=#expected;result.exact=true
elseif request.op=='candidates' then
 assert(request.kind==3,'owner/animal candidates require their native-backed verifier')
 local b=building();local rows={}
 for _,s in ipairs(df.global.world.squads.all) do if s.entity_id==df.global.plotinfo.group_id then
  local use=0;for _,v in ipairs(b.squad_room_info) do if v.squad_id==s.id then use=v.mode.whole end end
  rows[#rows+1]={id=s.id,entity=3,name=dfhack.df2utf(s.alias~='' and s.alias or dfhack.translation.translateName(s.name,true)),
   profession='',sex=-1,mood=0,grazer=false,assigned=contains(b.squad_room_info,s.id,'squad_id'),squad_use=use}
 end end
 if request.sort~=0 then table.sort(rows,function(a,b)
  local x,y
  if request.sort==1 then x,y=a.name:lower(),b.name:lower()
  elseif request.sort==2 then x,y=a.mood,b.mood else x,y=a.profession:lower(),b.profession:lower() end
  if x==y then x,y=a.id,b.id end
  if request.descending then return x>y end;return x<y
 end)
 elseif request.descending then local reverse={};for i=#rows,1,-1 do reverse[#reverse+1]=rows[i] end;rows=reverse end
 if request.query and request.query~='' then
  local query=request.query:lower();local filtered={}
  for _,row in ipairs(rows) do
   if row.name:lower():find(query,1,true) or tostring(row.id)==query then filtered[#filtered+1]=row end
  end
  rows=filtered
 end
 assert(canonical(rows)==canonical(request.rows),'candidate values/order differ from native dump')
elseif request.op=='remove_target' then
 assert(dfhack.buildings.deconstruct(building()),'fixture target removal failed')
 assert(not df.building.find(request.id),'fixture target still registered')
elseif request.op=='removed' then assert(not df.building.find(request.id),'deleted area still registered')
elseif request.op=='status' then
 result=json.decode(assert(read(out..'/status-'..index..'.json')));result.status='passed'
elseif request.op=='stale_edit' then
 local b=building();b.name=b.name..' stale fixture edit';print('FIXTURE_WRITE out-of-band name '..b.id)
elseif request.op=='item_assignment_before' then
 local item=assert(df.item.find(request.item_id));local refs={}
 for _,ref in ipairs(item.general_refs)do
  if df.general_ref_contained_in_itemst:is_instance(ref)then refs[#refs+1]=ref.item_id end
 end
 local cages=0
 for _,cage in ipairs(df.global.world.buildings.other.CAGE)do
  if contains(cage.assigned_items,item.id)then cages=cages+1 end
 end
 assert(cages>0,'item fixture needs a cage assignment')
 _G.df3d_item_containment={id=item.id,refs=canonical(refs)}
 result.item=item.id;result.cage_assignments=cages
elseif request.op=='item_assignment' then
 local b,item=building(),assert(df.item.find(request.item_id));local refs={};local found=0
 for _,ref in ipairs(item.general_refs)do
  if df.general_ref_contained_in_itemst:is_instance(ref)then refs[#refs+1]=ref.item_id end
  if df.general_ref_building_civzone_assignedst:is_instance(ref)then
   found=found+1;assert(request.assign and ref.building_id==b.id,'wrong item zone reference')
  end
  assert(not df.general_ref_building_cagedst:is_instance(ref),'item cage assignment reference remains')
 end
 assert(found==(request.assign and 1 or 0),'item zone reference count differs')
 assert(contains(b.assigned_items,item.id)==request.assign,'item membership differs')
 for _,zone in ipairs(df.global.world.buildings.other.ANY_ZONE)do
  if zone.id~=b.id then assert(not contains(zone.assigned_items,item.id),'prior zone retains item')end
 end
 for _,cage in ipairs(df.global.world.buildings.other.CAGE)do assert(not contains(cage.assigned_items,item.id),'cage retains item')end
 local before=assert(_G.df3d_item_containment)
 assert(before.id==item.id and before.refs==canonical(refs),'physical item containment changed')
 result.item=item.id;result.assigned=request.assign;result.assigned_count=#b.assigned_units+#b.assigned_items
elseif request.op=='assignment_before' then
 local u=assert(df.unit.find(request.unit_id));local refs={}
 for _,r in ipairs(u.general_refs) do if df.general_ref_contained_in_itemst:is_instance(r) then refs[#refs+1]=r.item_id end end
 _G.df3d_areas_containment={id=u.id,refs=canonical(refs)}
 local chain=df.building_chainst:new();chain.id=df.global.building_next_id
 df.global.building_next_id=chain.id+1
 chain.centerx=u.pos.x;chain.centery=u.pos.y;chain.z=u.pos.z
 chain.x1=u.pos.x;chain.x2=u.pos.x;chain.y1=u.pos.y;chain.y2=u.pos.y
 chain.assigned=u;chain.chained=u
 df.global.world.buildings.all:insert('#',chain);df.global.world.buildings.other.CHAIN:insert('#',chain)
 local function add_job(kind)
  local job=df.job:new();job.job_type=kind;job.posting_index=-1
  local ref=df.general_ref_building_holderst:new();ref.building_id=chain.id
  job.general_refs:insert('#',ref);assert(dfhack.job.linkIntoWorld(job,true))
  chain.jobs:insert('#',job);return job.id,job
 end
 local pending,pending_job=add_job(df.job_type.ChainAnimal)
 local retained=add_job(df.job_type.UnchainAnimal)
 local worker
 for _,unit in ipairs(df.global.world.units.active)do
  if dfhack.units.isCitizen(unit) and not unit.job.current_job then worker=unit;break end
 end
 assert(worker,'chain fixture needs idle citizen')
 local held_item
 for _,item in ipairs(df.global.world.items.all)do
  if not item.flags.in_job and #item.specific_refs==0 then held_item=item;break end
 end
 assert(held_item,'chain fixture needs unreserved item')
 assert(dfhack.job.addWorker(pending_job,worker))
 assert(dfhack.job.attachJobItem(pending_job,held_item,df.job_role_type.Hauled,-1,-1))
 assert(worker.job.current_job==pending_job and held_item.flags.in_job and #held_item.specific_refs==1)
 _G.df3d_areas_chain={chain=chain,pending=pending,retained=retained,worker=worker,item=held_item,
  cursor=df.reinterpret_cast('int32_t',dfhack.internal.getImageBase()+0x2131b60).value}
 result.chain=chain.id;result.pending_job=pending;result.retained_job=retained;result.worker=worker.id;result.item=held_item.id

elseif request.op=='assignment' then
 local b,u=building(),assert(df.unit.find(request.unit_id));local found=0;local contained={}
 for _,r in ipairs(u.general_refs) do
  if df.general_ref_building_civzone_assignedst:is_instance(r) then found=found+1;assert(request.assign and r.building_id==b.id,'wrong native zone reference')
  elseif df.general_ref_contained_in_itemst:is_instance(r) then contained[#contained+1]=r.item_id end
 end
 assert(found==(request.assign and 1 or 0),'native unit zone reference count')
 assert(contains(b.assigned_units,u.id)==request.assign,'zone membership mismatch')
 for _,z in ipairs(df.global.world.buildings.other.ACTIVITY_ZONE) do
  if z.id~=b.id then assert(not contains(z.assigned_units,u.id),'old zone retained unit') end
 end
 for _,c in ipairs(df.global.world.buildings.other.CAGE) do assert(not contains(c.assigned_units,u.id),'cage retained assignment') end
 local before=assert(_G.df3d_areas_containment)
 assert(before.id==u.id and before.refs==canonical(contained),'physical containment references changed')
 local saved=assert(_G.df3d_areas_chain);local chain=saved.chain
 assert(not chain.assigned and chain.chained==u,'chain assignment/physical state differs from native')
 assert(#chain.jobs==1 and chain.jobs[0].id==saved.retained,'chain job cleanup differs from native')
 for _,job in require('utils').listpairs(df.global.world.jobs.list)do
  assert(job.id~=saved.pending,'cancelled chain job remains in world')
 end
 assert(df.reinterpret_cast('int32_t',dfhack.internal.getImageBase()+0x2131b60).value==saved.cursor,'native job cursor changed')
 assert(not saved.worker.job.current_job,'chain cancellation retained worker job')
 assert(not saved.item.flags.in_job and #saved.item.specific_refs==0,'chain cancellation retained item reservation')
 result.worker=saved.worker.id;result.worker_job=-1;result.item=saved.item.id
 result.item_in_job=false;result.item_refs=0
 result.chain=chain.id;result.pending_job_absent=true;result.retained_job=saved.retained;result.cursor_unchanged=true

elseif request.op=='squad' then
 local b,s=building(),assert(df.squad.find(request.squad_id));local n,m=0,0
 for _,r in ipairs(b.squad_room_info) do if r.squad_id==s.id then n=n+1;assert(r.mode.whole==request.use,'zone squad use') end end
 for _,r in ipairs(s.rooms) do if r.building_id==b.id then m=m+1;assert(r.mode.whole==request.use,'squad room use') end end
 local count=request.use==0 and 0 or 1;assert(n==count and m==count,'squad reciprocal membership')
elseif request.op=='pile_link' then
 local source,target=building(),assert(df.building.find(request.target_id))
 assert(df.building_stockpilest:is_instance(source) and df.building_stockpilest:is_instance(target),'expected two stockpiles')
 local a=source.links[request.give and 'give_to_pile' or 'take_from_pile']
 local b=target.links[request.give and 'take_from_pile' or 'give_to_pile']
 assert(contains(a,target.id,'id')==request.linked and contains(b,source.id,'id')==request.linked,'stockpile endpoints disagree')
elseif request.op=='link' then
 local workshop=building();local pile=assert(df.building.find(request.pile_id))
 local a=workshop:getStockpileLinks()[request.give and 'give_to_pile' or 'take_from_pile']
 local b=pile.links[request.give and 'take_from_workshop' or 'give_to_workshop']
 assert(contains(a,pile.id,'id')==request.linked and contains(b,workshop.id,'id')==request.linked,'link endpoints disagree')
elseif request.op=='location' then
 local b=building();local site=assert(dfhack.world.getCurrentSite())
 assert(b.location_id==request.location_id,'zone location mismatch')
 local observed_kind=0
 for _,v in ipairs(site.buildings) do
  if v.id==b.location_id then observed_kind=({INN_TAVERN=1,TEMPLE=2,LIBRARY=3,GUILDHALL=4,HOSPITAL=5})[df.abstract_building_type[v:getType()]] or 0 end
  local contents=v:getContents()
  if contents then assert(contains(contents.building_ids,b.id)==(v.id==request.location_id),'location membership mismatch') end
 end
 if request.location_id>=0 then assert(b.site_id==site.id,'zone site mismatch') end
 if request.location_kind~=nil then assert(request.location_kind==observed_kind,'observed location type mismatch') end
elseif request.op=='departures' then
 local text=read(out..'/../evidence/native/e9/findings.md') or '';local rows={}
 for n=1,23 do
  local found
  for line in text:gmatch('[^\r\n]+') do
   if line:lower():match('departure%s+'..n..'%f[%D]') then found=line;break end
  end
  rows[tostring(n)]=found or 'incomplete: evidence missing'
 end
 result.departures=rows;write(out..'/departures.json',rows)
elseif request.op=='wait_start' then
 _G.df3d_areas_wait={tick=df.global.cur_year*403200+df.global.cur_year_tick,wall=dfhack.getTickCount()}
elseif request.op=='wait_poll' then
 local start=assert(_G.df3d_areas_wait);result.ticks=df.global.cur_year*403200+df.global.cur_year_tick-start.tick
 result.waiting=result.ticks<120
 if result.waiting and dfhack.getTickCount()-start.wall>=60000 then
  result.waiting=false;result.status='incomplete';result.reason='120 simulation ticks not reached within 60 seconds'
 end
elseif request.op=='final' then assert(df.global.pause_state,'final fortress not paused')
else error('unknown native verification '..tostring(request.op)) end
write(out..'/response-'..index..'.json',result)
print((result.status=='incomplete' and 'SEMANTIC_INCOMPLETE ' or 'SEMANTIC_PASS ')..index..' '..request.op)
