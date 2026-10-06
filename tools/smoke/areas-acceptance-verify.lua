-- Native observations/assertions. All area commands are sent by the Godot driver.
local out,index=...
local json=require('json')
local B=dfhack.buildings
local function read(path) local f=io.open(path,'r');if not f then return nil end;local s=f:read('*a');f:close();return s end
local function write(path,value) local f=assert(io.open(path,'w'));f:write(json.encode(value));f:close() end
if index=='pause' then df.global.pause_state=true;print('SEMANTIC_PASS paused');return end
if index=='final' then
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
local function fingerprint(without_flags_id)
 local all={areas={},workshops={},cages={},units={},squads={},locations={},next_building=df.global.building_next_id}
 for _,b in ipairs(df.global.world.buildings.all) do
  if df.building_stockpilest:is_instance(b) or df.building_civzonest:is_instance(b) then
   local observed=area(b)
   if b.id==without_flags_id then
    observed.settings.flags=nil
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
if request.op=='guard_before' then
 assert(df.global.pause_state,'refusal guard requires paused fortress')
 _G.df3d_areas_guard=fingerprint()
elseif request.op=='guard_after' then
 assert(df.global.pause_state,'refusal guard requires paused fortress')
 assert(_G.df3d_areas_guard==fingerprint(),'refusal changed native area state')
elseif request.op=='category_before' then
 assert(df.global.pause_state,'category guard requires paused fortress')
 local b=building()
 _G.df3d_category_guard={id=b.id,flags=native_value(b.settings.flags,0),other=fingerprint(b.id)}
elseif request.op=='category_after' then
 local b=building();local before=assert(_G.df3d_category_guard)
 assert(df.global.pause_state and before.id==b.id,'category guard identity changed')
 assert(b.settings.flags[request.category],'selected native category was not enabled')
 local after_flags=native_value(b.settings.flags,0)
 for key,value in pairs(before.flags) do
  if key~='whole' and key~=request.category then
   assert(after_flags[key]==value,'category selection changed another flag: '..key)
  end
 end
 assert(before.other==fingerprint(b.id),'category selection changed filters or unrelated native state')
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
 for i,raw in ipairs(df.global.world.raws.plants.all) do
  if raw.flags.TREE and raw.name_plural~='' then
   local on=i<#b.settings.wood.mats and b.settings.wood.mats[i]~=0
   rows[#rows+1]={key='wood/'..i,index=i,label=dfhack.df2utf(raw.name_plural),state=on and 2 or 1,kind=4,estimated=false}
  end
 end
 table.sort(rows,function(a,b) if a.label:lower()==b.label:lower() then return a.index<b.index end;return a.label:lower()<b.label:lower() end)
 if request.rows then assert(canonical(rows)==canonical(request.rows),'wood page differs from native raw/settings dump') end
 if request.value then for _,row in ipairs(rows) do
  if not request.row_key or request.row_key==row.key then assert(row.state==request.value,'wood filter did not change') end
 end end
 result.rows=rows
elseif request.op=='preset' then
 local b=building();local cats={'animals','food','furniture','corpses','refuse','stone','ammo','coins','bars_blocks','gems','finished_goods','leather','cloth','wood','weapons','armor','sheet'}
 for _,key in ipairs(cats) do
  -- The pinned All preset excludes Corpses and Refuse (E9 finding1 and
  -- native import receipt131047); SettingsSet/All is a different operation.
  local enabled=request.preset==1 and key~='corpses' and key~='refuse' or request.category==key
  assert(b.settings.flags[key]==enabled,'preset category '..key)
 end
 local retained=request.retained or {barrels=2,bins=1,wheelbarrows=1,links_only=true}
 assert(b.storage.max_barrels==retained.barrels and b.storage.max_bins==retained.bins and
  b.storage.max_wheelbarrows==retained.wheelbarrows and b.stockpile_flag.use_links_only==retained.links_only,
  'preset changed containers/links-only')
 result.area=area(b)
elseif request.op=='zone_settings' then
 local b=building();local v=b.zone_settings;local actual={}
 local typ=df.civzone_type[b.type]
 if typ=='Pond' then actual.pond_mode=v.pond.flag.keep_filled and 2 or 1
 elseif typ=='ArcheryRange' then
  local x,y=v.archery.dir_x,v.archery.dir_y
  actual.facing=x==-1 and y==0 and 1 or x==1 and y==0 and 2 or x==0 and y==-1 and 3 or x==0 and y==1 and 4 or 0
 elseif typ=='Tomb' then actual.tomb_citizens=v.tomb.flags.no_citizens and 0 or 1;actual.tomb_pets=v.tomb.flags.no_pets and 0 or 1
 elseif typ=='PlantGathering' then actual.gather_trees=v.gather.flags.pick_trees and 1 or 0;actual.gather_shrubs=v.gather.flags.pick_shrubs and 1 or 0 end
 check_properties(actual,request.expected,'zone_settings')
elseif request.op=='candidates' then
 local b=building();local rows={};local U=dfhack.units
 if request.kind==3 then
  for _,s in ipairs(df.global.world.squads.all) do if s.entity_id==df.global.plotinfo.group_id then
   local use=0;for _,v in ipairs(b.squad_room_info) do if v.squad_id==s.id then use=v.mode.whole end end
   rows[#rows+1]={id=s.id,name=dfhack.df2utf(s.alias~='' and s.alias or dfhack.translation.translateName(s.name,true)),
    profession='',sex=-1,mood=0,grazer=false,assigned=contains(b.squad_room_info,s.id,'squad_id'),squad_use=use}
  end end
 else
  for _,u in ipairs(df.global.world.units.active) do
   if U.isActive(u) and not U.isDead(u) and (request.kind==1 and U.isCitizen(u) or
      request.kind==2 and not U.isCitizen(u) and (U.isTame(u) or u.flags1.caged)) then
    rows[#rows+1]={id=u.id,name=dfhack.df2utf(request.kind==1 and dfhack.translation.translateName(U.getVisibleName(u)) or U.getReadableName(u)),profession=dfhack.df2utf(U.getProfessionName(u)),
     sex=u.sex,mood=U.getStressCategory(u)+1,grazer=request.kind==2 and U.isGrazer(u) or false,
     assigned=request.kind==1 and b.assigned_unit_id==u.id or request.kind==2 and contains(b.assigned_units,u.id),squad_use=-1}
   end
  end
 end
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
elseif request.op=='assignment_before' then
 local u=assert(df.unit.find(request.unit_id));local refs={}
 for _,r in ipairs(u.general_refs) do if df.general_ref_contained_in_itemst:is_instance(r) then refs[#refs+1]=r.item_id end end
 _G.df3d_areas_containment={id=u.id,refs=canonical(refs)}
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
