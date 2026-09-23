-- Fixed semantic area helper, embedded in the native bridge (Management v2).
local B,U=dfhack.buildings,dfhack.units
local utils=require('utils')
local cats={'animals','food','furniture','corpses','refuse','stone','ammo','coins',
 'bars_blocks','gems','finished_goods','leather','cloth','wood','weapons','armor','sheet'}
local zone_types={MeetingHall=true,Bedroom=true,DiningHall=true,Office=true,Dormitory=true,
 Pen=true,Pond=true,WaterSource=true,FishingArea=true,SandCollection=true,ClayCollection=true,
 Dump=true,AnimalTraining=true,PlantGathering=true,Tomb=true,Barracks=true,ArcheryRange=true,Dungeon=true}
local owner_types={Bedroom=true,Office=true,DiningHall=true,Tomb=true}
local function fail(message) return {ok=false,message=message} end
local function kind(b)
 if df.building_stockpilest:is_instance(b) then return 0 end
 if df.building_civzonest:is_instance(b) then return 1 end
 return -1
end
local function visible(p)
 if not dfhack.maps.isValidTilePos(p) then return false end
 local d=dfhack.maps.getTileFlags(p);return d and not d.hidden
end
local function occupies(b,x,y)
 if x<b.x1 or x>b.x2 or y<b.y1 or y>b.y2 then return false end
 if not b.room.extents then return true end
 local rx,ry=x-b.room.x,y-b.room.y
 if rx<0 or ry<0 or rx>=b.room.width or ry>=b.room.height then return false end
 return b.room.extents[ry*b.room.width+rx]~=0
end
local function name(b)
 if b.name and #b.name>0 then return dfhack.df2utf(b.name) end
 return (kind(b)==0 and 'Stockpile' or (df.civzone_type[b.type] or 'Zone'))..' #'..b.id
end
local function unit_name(u)
 return dfhack.df2utf(U.getReadableName(u))
end
local function owned(b) return kind(b)==1 and owner_types[df.civzone_type[b.type]] or false end
local function inspect(b)
 local w,h=b.x2-b.x1+1,b.y2-b.y1+1
 if w>256 or h>256 or w*h>32768 then return nil,'This area exceeds the bounded extent inspector (256 per side, 32768 tiles)' end
 if kind(b)==0 and (#b.links.give_to_pile>1024 or #b.links.take_from_pile>1024) then return nil,'This pile exceeds the bounded link inspector (1024 per direction)' end
 local r={id=b.id,kind=kind(b),name=name(b),x=b.x1,y=b.y1,z=b.z,width=w,height=h,extents={},
 zone_type=-1,categories=0,barrels=0,bins=0,wheelbarrows=0,active=true,owner_id=-1,
 owner_name='',owner_allowed=owned(b),gives={},takes={}}
 for y=b.y1,b.y2 do for x=b.x1,b.x2 do r.extents[#r.extents+1]=occupies(b,x,y) and 1 or 0 end end
 if r.kind==0 then
  for i,c in ipairs(cats) do if b.settings.flags[c] then r.categories=r.categories+2^(i-1) end end
  r.barrels=b.storage.max_barrels;r.bins=b.storage.max_bins;r.wheelbarrows=b.storage.max_wheelbarrows
  r.links_only=b.stockpile_flag.use_links_only
  for _,p in ipairs(b.links.give_to_pile) do r.gives[#r.gives+1]=p.id end
  for _,p in ipairs(b.links.take_from_pile) do r.takes[#r.takes+1]=p.id end
 else
  r.zone_type=b.type;r.active=b.spec_sub_flag.active;r.owner_id=b.assigned_unit_id
  local u=df.unit.find(r.owner_id);if u then r.owner_name=unit_name(u) end
 end
 return r
end
local function find(id)
 local b=df.building.find(id)
 if not b or kind(b)<0 then return nil,'Area no longer exists' end
 -- A visible occupied tile is required; no hidden-area inspection by ID.
 for y=b.y1,b.y2 do for x=b.x1,b.x2 do
  if occupies(b,x,y) and visible{x=x,y=y,z=b.z} then return b end
 end end
 return nil,'Area is not visible'
end
local function reply(b,message)
 local info,err=inspect(b);if not info then return fail(err) end
 return {ok=true,message=message or 'Observed native area settings',areas={info},building_id=b.id,
 hint_x=b.x1,hint_y=b.y1,hint_z=b.z,hint_width=b.x2-b.x1+1,hint_height=b.y2-b.y1+1}
end
local function site(a)
 if a.width<1 or a.height<1 or a.width>31 or a.height>31 then return false,'Area must be 1..31 tiles on each side' end
 for y=a.y,a.y+a.height-1 do for x=a.x,a.x+a.width-1 do
  local p={x=x,y=y,z=a.z}
  if not visible(p) then return false,'Every selected tile must be visible and loaded' end
  local tt=dfhack.maps.getTileType(p);local shape=df.tiletype.attrs[tt].shape
  local d,o=dfhack.maps.getTileFlags(p)
  if a.kind==0 then
   if shape~=df.tiletype_shape.FLOOR and shape~=df.tiletype_shape.BOULDER and shape~=df.tiletype_shape.PEBBLES and
      shape~=df.tiletype_shape.STAIR_UP and shape~=df.tiletype_shape.STAIR_DOWN and shape~=df.tiletype_shape.STAIR_UPDOWN and
      shape~=df.tiletype_shape.RAMP and shape~=df.tiletype_shape.TWIG and shape~=df.tiletype_shape.SAPLING and shape~=df.tiletype_shape.SHRUB then
    return false,'Stockpiles require supported floor on every tile'
   end
   if d.flow_size>0 or o.building~=0 then return false,'Stockpile site contains liquid or a building' end
   for _,b in ipairs(df.global.world.buildings.other.STOCKPILE) do
    if b.z==a.z and occupies(b,x,y) then return false,'Stockpiles cannot overlap another stockpile' end
   end
  elseif shape==df.tiletype_shape.WALL or shape==df.tiletype_shape.FORTIFICATION then
   return false,'Zone rectangle includes an impassable wall'
  end
 end end
 return true
end
local function edit_valid(a,b)
 local n=0;for y=b.y1,b.y2 do for x=b.x1,b.x2 do if occupies(b,x,y) then n=n+1 end end end
 if kind(b)==0 then
  if a.active~=-1 or a.owner_id~=-2 then return false,'Zone-only fields on stockpile' end
  if a.barrels>n or a.bins>n or a.wheelbarrows>math.max(0,n-1) then return false,'Container limits exceed usable stockpile tiles' end
 else
  if a.changed_categories~=0 or a.barrels~=-1 or a.bins~=-1 or a.wheelbarrows~=-1 or a.links_only~=-1 then return false,'Stockpile-only fields on zone' end
  if a.owner_id~=-2 then
   if not owned(b) then return false,'This zone type has no single owner' end
   local u=a.owner_id>=0 and df.unit.find(a.owner_id) or nil
   if a.owner_id>=0 and (not u or not U.isCitizen(u) or not U.isActive(u) or U.isDead(u)) then return false,'Owner must be an active living citizen of this fortress' end
  end
 end
 return true
end
local function update(a,b)
 local ok,err=edit_valid(a,b);if not ok then return fail(err) end
 if kind(b)==0 then
  -- Critically: never call preset import here. Category flag toggles preserve
  -- every material/quality/subtype filter and unrelated category flag.
  for i,c in ipairs(cats) do
   if math.floor(a.changed_categories/2^(i-1))%2==1 then b.settings.flags[c]=math.floor(a.categories/2^(i-1))%2==1 end
  end
  if a.barrels>=0 then b.storage.max_barrels=a.barrels end
  if a.bins>=0 then b.storage.max_bins=a.bins end
  if a.wheelbarrows>=0 then b.storage.max_wheelbarrows=a.wheelbarrows end
  if a.links_only>=0 then b.stockpile_flag.use_links_only=a.links_only==1 end
 else
  if a.owner_id~=-2 and not B.setOwner(b,a.owner_id>=0 and df.unit.find(a.owner_id) or nil) then return fail('Native owner assignment failed') end
  if a.active>=0 then b.spec_sub_flag.active=a.active==1 end
  B.notifyCivzoneModified(b)
 end
 return reply(b,'Native area settings updated; other filters preserved')
end
local function candidates(a)
 local choices={};local native=a.kind==0 and df.global.world.buildings.other.STOCKPILE or df.global.world.units.active
 local source={};for _,v in ipairs(native) do source[#source+1]=v end
 table.sort(source,function(x,y)return x.id<y.id end)
 local next_cursor=0;local q=(a.query or ''):lower()
 for _,v in ipairs(source) do
  if v.id>=a.cursor and ((a.kind==0 and find(v.id)) or (a.kind==1 and U.isCitizen(v) and U.isActive(v) and not U.isDead(v))) then
   local label=a.kind==0 and name(v) or unit_name(v)
   if label:lower():find(q,1,true) or tostring(v.id)==q then
    if #choices==128 then next_cursor=v.id;break end
    choices[#choices+1]={id=v.id,name=label..' #'..v.id}
   end
  end
 end
 table.sort(choices,function(x,y)return x.id<y.id end)
 return {ok=true,message='Choose an observed identity; search or More for later IDs',choices=choices,next_cursor=next_cursor}
end
return function(r)
 local a=r.area
 if not a then return fail('Area request missing') end
 if r.action==7 then
  local choices={}
  for i=0,df.civzone_type._last_item do
   local n=df.civzone_type[i];if zone_types[n] then choices[#choices+1]={id=i,name=n} end
  end
  return {ok=true,message='Rectangular stockpiles and zones; custom subfilters are preserved, not edited here',choices=choices}
 end
 if r.action==14 then return candidates(a) end
 if r.action==8 then
  if not visible{x=a.x,y=a.y,z=a.z} then return fail('Tile is hidden or outside the map') end
  local out={};local cells=0;local next_cursor=0
  local source={};for _,b in ipairs(df.global.world.buildings.all) do if kind(b)>=0 then source[#source+1]=b end end
  table.sort(source,function(x,y)return x.id<y.id end)
  for _,b in ipairs(source) do
   if b.id>=a.cursor and kind(b)>=0 and b.z==a.z and occupies(b,a.x,a.y) then
    local info,err=inspect(b);if not info then return fail(err) end
    if #out==64 or cells+#info.extents>32768 then next_cursor=b.id;break end
    out[#out+1]=info;cells=cells+#info.extents
   end
  end
  table.sort(out,function(x,y)return x.id<y.id end)
  return {ok=true,message='Observed overlapping areas',areas=out,next_cursor=next_cursor,truncated=next_cursor~=0}
 end
 if r.action==10 then
  local ok,err=site(a);if not ok then return fail(err) end
  if a.kind==1 and not zone_types[df.civzone_type[a.zone_type]] then return fail('Unsupported zone type') end
  if a.kind==0 and a.categories==0 then return fail('Choose at least one stockpile category') end
  local presets
  if a.kind==0 then
   local loaded,value=pcall(require,'plugins.stockpiles')
   if not loaded or type(value.stockpiles_import)~='function' then return fail('Native stockpile preset plugin unavailable') end
   presets=value
  end
  local extents=df.reinterpret_cast(df.building_extents_type,df.new('uint8_t',a.width*a.height))
  for i=0,a.width*a.height-1 do extents[i]=1 end
  local b,why=B.constructBuilding{type=a.kind==0 and df.building_type.Stockpile or df.building_type.Civzone,
   subtype=a.kind==0 and -1 or a.zone_type,abstract=true,pos={x=a.x,y=a.y,z=a.z},width=a.width,height=a.height,
   fields={room={x=a.x,y=a.y,width=a.width,height=a.height,extents=extents}}}
  if not b then return fail('Native area construction rejected: '..tostring(why)) end
  if a.kind==0 then
   local worked,problem=pcall(function()
    for i,c in ipairs(cats) do if math.floor(a.categories/2^(i-1))%2==1 then
     -- Public Lua wrapper drops the native bool result. Call the pinned
     -- exported native function directly so missing/corrupt presets fail.
     local path=dfhack.getHackPath()..'/data/stockpiles/cat_'..(c=='sheet' and 'sheets' or c)..'.dfstock'
     if not presets.stockpiles_import(path,b.id,'enable','') then error('Preset failed: '..c) end
    end end
   end)
   if not worked then B.deconstruct(b);return fail('New pile preset failed; new area removed: '..tostring(problem)) end
  else
   local t=df.civzone_type[b.type]
   if t=='Pen' then b.zone_settings.pen.flags.check_occupants=true
   elseif t=='Pond' then b.zone_settings.pond.flag.keep_filled=true
   elseif t=='ArcheryRange' then b.zone_settings.archery.dir_x=1;b.zone_settings.archery.dir_y=0
   elseif t=='Tomb' then b.zone_settings.tomb.flags.no_pets=true
   elseif t=='PlantGathering' then
    b.zone_settings.gather.flags.pick_trees=true;b.zone_settings.gather.flags.pick_shrubs=true;b.zone_settings.gather.flags.gather_fallen=true
   end
   b.spec_sub_flag.active=true;B.setOwner(b,nil);B.notifyCivzoneModified(b)
  end
  local edited=update(a,b)
  if not edited.ok then B.deconstruct(b);return fail('Invalid new area settings; new area removed: '..edited.message) end
  edited.message='Native area created';return edited
 end
 local b,err=find(a.id);if not b then return fail(err) end
 if kind(b)~=a.kind then return fail('Area kind changed; inspect again') end
 local checked,why=inspect(b);if not checked then return fail(why) end
 if r.action==9 then return reply(b) end
 if r.action==11 then return update(a,b) end
 if r.action==12 then
  if not B.deconstruct(b) then return fail('Native area removal rejected') end
  return {ok=true,message='Native area removed',building_id=a.id,
   hint_x=checked.x,hint_y=checked.y,hint_z=checked.z,hint_width=checked.width,hint_height=checked.height}
 end
 if r.action==13 then
  local other,why=find(a.link_id)
  if kind(b)~=0 or not other or kind(other)~=0 or b.id==other.id then return fail(why or 'Links require two different stockpiles') end
  local other_info,other_error=inspect(other);if not other_info then return fail(other_error) end
  local from,to=b,other;if not a.give then from,to=to,from end
  if a.unlink then
   utils.erase_sorted(from.links.give_to_pile,to,'id');utils.erase_sorted(to.links.take_from_pile,from,'id')
  else
   local present=false;for _,p in ipairs(from.links.give_to_pile) do if p.id==to.id then present=true end end
   local reverse=false;for _,p in ipairs(to.links.take_from_pile) do if p.id==from.id then reverse=true end end
   if (not present and #from.links.give_to_pile>=1024) or (not reverse and #to.links.take_from_pile>=1024) then return fail('Link limit reached; no endpoints changed') end
   utils.insert_sorted(from.links.give_to_pile,to,'id');utils.insert_sorted(to.links.take_from_pile,from,'id')
  end
  return reply(b,a.unlink and 'Both stockpile link endpoints removed' or 'Both stockpile link endpoints updated')
 end
 return fail('Unsupported area action')
end
