-- Fixed semantic area helper, embedded in the versioned native bridge.
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
-- Native zone headers (e2/e5 captures) differ from building:getName(), which
-- returns "Activity Zone #n". Custom names always take precedence.
local zone_default_names={MeetingHall='memorial hall',Bedroom='bedroom',DiningHall='dining hall',
 Office='office',Dormitory='dormitory',Pen='pen/pasture',Pond='pit/pond',WaterSource='water source',
 FishingArea='fishing area',SandCollection='sand collection area',ClayCollection='clay collection area',
 Dump='dump',AnimalTraining='animal training area',PlantGathering='plant gathering area',
 Tomb='tomb',Barracks='barracks',ArcheryRange='archery range',Dungeon='dungeon'}
local function name(b)
 if kind(b)==1 and b.name=='' then
  local label=zone_default_names[df.civzone_type[b.type]]
  if label then return 'Unnamed '..label end
 end
 return dfhack.df2utf(B.getName(b))
end
local function unit_name(u)
 return dfhack.df2utf(dfhack.translation.translateName(U.getVisibleName(u)))
end
local function owned(b) return kind(b)==1 and owner_types[df.civzone_type[b.type]] or false end
local zone_labels={MeetingHall='Meeting Area',Bedroom='Bedroom',DiningHall='Dining Hall',
 Pen='Pen/Pasture',Pond='Pit/Pond',WaterSource='Water Source',Dungeon='Dungeon',FishingArea='Fishing',
 SandCollection='Sand',Office='Office',Dormitory='Dormitory',Barracks='Barracks',ArcheryRange='Archery Range',
 Dump='Garbage Dump',AnimalTraining='Animal Training',Tomb='Tomb',PlantGathering='Gather Fruit',ClayCollection='Clay'}
local function integer(v) return type(v)=='number' and math.type(v)=='integer' end
local function default(a,key,value) local v=a[key];if v==nil then return value end;return v end
local function validate_operation(r,a)
 local op=default(a,'operation',0)
 if not integer(op) or op<0 or op>15 then return 'Unsupported area operation' end
 local actions={[1]=9,[2]=11,[3]=11,[4]=11,[6]=9,[7]=11,[8]=11,[9]=11,[10]=9,[11]=11,[12]=11,[13]=11,[14]=14,[15]=13}
 if op~=0 and not (op==5 and (r.action==10 or r.action==11) or actions[op]==r.action) then
  return 'Area operation is not valid for this action'
 end
 local k=default(a,'kind',0)
 if not integer(k) or k<0 or k>2 or (k==2)~=(op==15) then return 'Workshop kind is only valid for workshop links' end
 local stock=op==1 or op==2 or op==3 or op==10 or op==13
 local zone=(op>=6 and op<=9) or op==11 or op==12 or op==14
 if stock and k~=0 or zone and k~=1 then return 'Area kind is not valid for this operation' end
 if op~=0 and (a.x~=nil or a.y~=nil or a.z~=nil or default(a,'width',1)~=1 or default(a,'height',1)~=1 or
  (default(a,'zone_type',-1)~=-1 and not(op==5 and r.action==10)) or default(a,'categories',0)~=0 or
  default(a,'changed_categories',0)~=0 or default(a,'barrels',-1)~=-1 or default(a,'bins',-1)~=-1 or
  default(a,'wheelbarrows',-1)~=-1 or default(a,'links_only',-1)~=-1 or default(a,'active',-1)~=-1 or
  default(a,'owner_id',-2)~=-2 or (op~=15 and (default(a,'link_id',-1)~=-1 or
  default(a,'give',true)~=true or default(a,'unlink',false)~=false))) then
  return 'Legacy area fields cannot be combined with an operation'
 end
 local foreign={
  {'expected_list_revision',0,{1,6,10,14}},{'list_key','',{1,2}},{'row_key','',{2}},{'scope',0,{2}},
  {'value',0,{2}},{'preset',0,{3}},{'name','',{4}},{'spans',false,{5}},{'paint_mode',0,{5}},
  {'paint_z',-1,{5}},{'location_id',-2,{7}},{'location_kind',0,{8}},{'profession',-1,{8}},
  {'deity_kind',-1,{8}},{'deity_id',-1,{8}},{'zone_settings',false,{9}},{'unit_id',-1,{11}},
  {'assign',-1,{11}},{'squad_id',-1,{12}},{'squad_use',-1,{12}},{'organic',-1,{13}},
  {'inorganic',-1,{13}},{'candidate_kind',0,{14}},{'sort',0,{14}},{'sort_descending',false,{14}},
  {'occupation_id',-1,{}}}
 for _,entry in ipairs(foreign) do
  local v=default(a,entry[1],entry[2]);local present=v~=entry[2]
  if entry[1]=='spans' then present=v~=false and (type(v)~='table' or next(v)~=nil)
  elseif entry[1]=='zone_settings' then
   present=false
   if v~=false then
    if type(v)~='table' then present=true else
     for _,key in ipairs{'pond_mode','facing','tomb_citizens','tomb_pets','gather_trees','gather_shrubs'} do
      local empty=(key=='pond_mode' or key=='facing') and 0 or -1
      if default(v,key,empty)~=empty then present=true end
     end
    end
   end
  end
  local allowed=false;for _,selector in ipairs(entry[3]) do if selector==op then allowed=true end end
  if present and not allowed then return 'Field '..entry[1]..' does not belong to this operation' end
 end
 for _,key in ipairs{'expected_revision','expected_list_revision'} do
  local v=default(a,key,0);if not integer(v) or v<0 then return 'invalid area revision' end
 end
 if not integer(default(a,'id',-1)) or default(a,'id',-1)<-1 then return 'invalid area identity' end
 if op~=0 and not(op==5 and r.action==10) and default(a,'id',-1)<0 then return 'area id required' end
 for _,key in ipairs{'list_key','row_key','name','query'} do
  local v=default(a,key,'');local cap=(key=='name' and 512) or (key=='query' and 128) or 64
  if type(v)~='string' or #v>cap then return key=='name' and 'area name too long' or 'area key too long' end
 end
 if op==2 then
  local scope,value=default(a,'scope',0),default(a,'value',0)
  if not integer(scope) or scope<1 or scope>4 or not integer(value) or value<1 or value>2 or
   ((default(a,'row_key','')~='')~=(scope==1)) then return 'invalid area settings edit' end
 end
 if op==3 then
  local preset=default(a,'preset',0)
  if not integer(preset) or preset<1 or preset>19 then return 'invalid area preset' end
 end
 if op==7 then
  local id=default(a,'location_id',-2)
  if not integer(id) or id< -1 or id>2147483647 then return 'invalid area location' end
 end
 if op==8 then
  local k,p,d,id=default(a,'location_kind',0),default(a,'profession',-1),default(a,'deity_kind',-1),default(a,'deity_id',-1)
  if not integer(k) or k<1 or k>5 or not integer(p) or p< -1 or p>32767 or
   not integer(d) or d< -1 or d>3 or not integer(id) or id< -1 or id>2147483647 or
   (k==4 and p<0 or k~=4 and p~=-1) or (k==2 and d<1 or k~=2 and d~=-1) or
   (k==2 and d>=2 and id<0 or not(k==2 and d>=2) and id~=-1) then return 'invalid area location creation' end
 end
 if op==14 and (not integer(a.candidate_kind) or a.candidate_kind<1 or a.candidate_kind>3 or
  not integer(default(a,'sort',0)) or default(a,'sort',0)<0 or default(a,'sort',0)>3 or
  type(default(a,'sort_descending',false))~='boolean') then return 'invalid area candidate selector' end
 if op==13 then
  local o,i=default(a,'organic',-1),default(a,'inorganic',-1)
  if not integer(o) or not integer(i) or o< -1 or o>1 or i< -1 or i>1 or o==-1 and i==-1 then return 'invalid area toggles' end
 end
 if op==12 and (not integer(default(a,'squad_id',-1)) or default(a,'squad_id',-1)<0 or
  not integer(default(a,'squad_use',-1)) or default(a,'squad_use',-1)<0 or a.squad_use>15) then return 'invalid area squad use' end
 if op==11 and (not integer(default(a,'unit_id',-1)) or default(a,'unit_id',-1)<0 or
  not integer(default(a,'assign',-1)) or default(a,'assign',-1)<0 or a.assign>1) then return 'invalid area unit assignment' end
 if r.action==13 and (not integer(default(a,'link_id',-1)) or default(a,'link_id',-1)<0 or a.link_id==a.id or
  type(default(a,'give',true))~='boolean' or type(default(a,'unlink',false))~='boolean') then return 'invalid area link' end
 if op==9 then
  local z=a.zone_settings;local present=false
  if type(z)~='table' then return 'invalid area zone settings' end
  for _,key in ipairs{'pond_mode','facing','tomb_citizens','tomb_pets','gather_trees','gather_shrubs'} do
   local empty=(key=='pond_mode' or key=='facing') and 0 or -1
   local upper=key=='pond_mode' and 2 or key=='facing' and 4 or 1
   local v=default(z,key,empty)
   if not integer(v) or v<empty or v>upper then return 'invalid area zone settings' end
   present=present or v~=empty
  end
  if not present then return 'invalid area zone settings' end
 end
 if r.action==10 and op==0 then
  for _,key in ipairs{'x','y','z'} do
   if not integer(a[key]) or a[key]<0 or a[key]>32767 then return 'invalid area rectangle' end
  end
  local w,h=default(a,'width',1),default(a,'height',1)
  if not integer(w) or not integer(h) or w<1 or h<1 or w>31 or h>31 or
   a.x+w>32768 or a.y+h>32768 then return 'invalid area rectangle' end
  for _,key in ipairs{'categories','changed_categories'} do
   local v=default(a,key,0);if not integer(v) or v<0 or v>0x1ffff then return 'invalid stockpile categories' end
  end
  for _,key in ipairs{'barrels','bins','wheelbarrows'} do
   local v=default(a,key,-1);if not integer(v) or v< -1 or v>32767 then return 'invalid area edit' end
  end
  local active,owner,links=default(a,'active',-1),default(a,'owner_id',-2),default(a,'links_only',-1)
  if not integer(active) or active< -1 or active>1 or not integer(owner) or owner< -2 or owner>2147483647 or
   not integer(links) or links< -1 or links>1 then return 'invalid area edit' end
 end
 if op==5 then
  if not integer(a.paint_mode) or a.paint_mode<1 or a.paint_mode>3 or
   r.action==10 and a.paint_mode~=1 or type(a.spans)~='table' or #a.spans==0 then return 'invalid area paint' end
  if #a.spans>32768 then return 'too many area spans' end
  local total=0
  for _,span in ipairs(a.spans) do
   if type(span)~='table' or not integer(span.x) or not integer(span.y) or not integer(span.length) or
    span.x<0 or span.y<0 or span.y>32767 or span.length<1 or span.x+span.length>32768 then return 'invalid area span' end
   total=total+span.length
  end
  if total>32768 then return 'too many painted area tiles' end
  local z=default(a,'paint_z',-1)
  if not integer(z) or z< -1 or z>32767 then return 'invalid area identity' end
  if r.action==10 and z<0 then return 'area paint z required' end
 end
end

-- Kind 7 jobs keep only scalar selectors, cursors and copied rows. Native
-- vectors/objects are reacquired inside each step and never survive a yield.
local list_epoch=nil
local area_lists={}
local list_serial=0
-- PM prompt-B amendment: with15 enabled kinds, the minimum512 remaining steps
-- give34/kind/update. This summary visits at most65976 counted entries (~1941
-- updates for one job), within2400 ticks. The current table enables8 kinds;
-- reserved slots do not consume shares. Reassess when enabling more kinds.
local candidate_max_age=2400
local function clear_lists() area_lists={} end
local function sync_epoch(epoch)
 if list_epoch~=epoch then list_epoch=epoch;clear_lists() end
end
local function active_kinds()
 local mask=0
 for _,job in pairs(area_lists) do if not job.complete and not job.error then mask=mask | (1 << (job.builder_kind or 7)) end end
 return mask
end
local function tick() return (df.global.cur_year or 0)*403200+(df.global.cur_year_tick or 0) end
local function hash_integer(hash,value)
 for shift=0,56,8 do hash=(hash ~ ((value >> shift) & 255))*0x100000001b3 end
 return hash
end
local function source(job)
 if job.locations then
  local site=dfhack.world.getCurrentSite()
  if not site or site.id~=job.site_id then job.error='Location site changed; refresh';return {} end
  return site.buildings
 end
 if job.legacy and job.kind==0 then return df.global.world.buildings.other.STOCKPILE end
 if job.candidate_kind==3 then return df.global.world.squads.all end
 return df.global.world.units.active
end
local function element(vector,index)
 return vector[type(vector)=='table' and index+1 or index]
end
-- Leaf identities use native backing indices, never captions (native lists can
-- contain repeated captions). The visible category/column-2 summary is separate.
-- Every descriptor is immutable Lua data; no raw or building reference is kept.
local setting_leaves={}
local function setting_leaf(key,field,source,selector,partition)
 setting_leaves[key]={field=field,source=source,selector=selector,partition=partition}
end
for _,cat in ipairs{'ammo','armor','finished_goods','furniture','weapons'} do
 for _,quality in ipairs{'quality_core','quality_total'} do setting_leaf(cat..'/'..quality,cat..'.'..quality,'quality') end
end
for _,cat in ipairs{'armor','cloth','finished_goods','leather'} do setting_leaf(cat..'/color',cat..'.color','color') end
for _,entry in ipairs{{'ammo/type','ammo.type','ammo'},{'armor/body','armor.body','armor'},
 {'armor/head','armor.head','helms'},{'armor/feet','armor.feet','shoes'},{'armor/hands','armor.hands','gloves'},
 {'armor/legs','armor.legs','pants'},{'armor/shield','armor.shield','shields'},
 {'weapons/weapons','weapons.weapon_type','weapons'},{'weapons/trap_components','weapons.trapcomp_type','trapcomps'}} do
 setting_leaf(entry[1],entry[2],'itemdef',entry[3])
end
for _,entry in ipairs{{'meat','Meat'},{'fish','Fish'},{'unprepared_fish','UnpreparedFish'},{'egg','Eggs'},
 {'plants','Plants'},{'drink_plant','PlantDrink'},{'drink_animal','CreatureDrink'},
 {'cheese_plant','PlantCheese'},{'cheese_animal','CreatureCheese'},{'seeds','Seed'},{'leaves','PlantGrowth'},
 {'powder_plant','PlantPowder'},{'powder_creature','CreaturePowder'},{'glob','Glob'},
 {'glob_paste','Paste'},{'glob_pressed','Pressed'},{'liquid_plant','PlantLiquid'},
 {'liquid_animal','CreatureLiquid'},{'liquid_misc','MiscLiquid'}} do
 setting_leaf('food/'..entry[1],'food.'..entry[1],'organic',entry[2])
end
for _,form in ipairs{'thread','cloth'} do
 for _,entry in ipairs{{'silk','Silk'},{'plant','PlantFiber'},{'yarn','Yarn'},{'metal','MetalThread'}} do
  local key=form..'_'..entry[1];setting_leaf('cloth/'..key,'cloth.'..key,'organic',entry[2])
 end
end
setting_leaf('leather/type','leather.mats','organic','Leather')
setting_leaf('sheet/paper','sheet.paper','organic','Paper')
setting_leaf('sheet/parchment','sheet.parchment','organic','Parchment')
setting_leaf('animals/animals','animals.enabled','creature')
setting_leaf('corpses','corpses.corpses','creature')
setting_leaf('wood','wood.mats','plant')
for _,key in ipairs{'corpses','body_parts','skulls','bones','shells','teeth','horns','hair'} do
 setting_leaf('refuse/'..key,'refuse.'..key,'creature')
end
setting_leaf('coins','coins.mats','inorganic','any')
for _,cat in ipairs{'ammo','armor','weapons','furniture','finished_goods'} do
 setting_leaf(cat..'/metal',cat..'.mats','inorganic',cat,'metal')
 if cat=='weapons' or cat=='furniture' or cat=='finished_goods' then
  setting_leaf(cat..'/stone',cat..'.mats','inorganic',cat,'stone')
 end
end
setting_leaf('finished_goods/gem','finished_goods.mats','inorganic','finished_goods','gem')
setting_leaf('bars_blocks/bars_metal','bars_blocks.bars_mats','inorganic','metal','metal')
setting_leaf('bars_blocks/blocks_stone','bars_blocks.blocks_mats','inorganic','blocks','stone')
setting_leaf('bars_blocks/blocks_metal','bars_blocks.blocks_mats','inorganic','blocks','metal')
setting_leaf('gems/rough_gem','gems.rough_mats','inorganic','rough_gem','gem')
setting_leaf('gems/cut_gem','gems.cut_mats','inorganic','cut_gem','gem')
setting_leaf('gems/cut_stone','gems.cut_mats','inorganic','cut_gem','stone')
for _,part in ipairs{'metal_ores','economic','clay','other_stone'} do
 setting_leaf('stone/'..part,'stone.mats','inorganic','stone',part)
end
setting_leaf('gems/rough_glass','gems.rough_other_mats','builtin')
setting_leaf('gems/cut_glass','gems.cut_other_mats','builtin')
setting_leaf('finished_goods/type','finished_goods.type','itemtype','finished_goods')
setting_leaf('refuse/type','refuse.type','itemtype','refuse')
setting_leaf('furniture/type','furniture.type','furniture')
local other_materials={
 ammo={'WOOD','BONE'},
 armor={'WOOD','PLANT_CLOTH','BONE','SHELL','LEATHER','SILK','GREEN_GLASS','CLEAR_GLASS','CRYSTAL_GLASS','YARN'},
 furniture={'WOOD','PLANT_CLOTH','BONE','TOOTH','HORN','PEARL','SHELL','LEATHER','SILK','AMBER','CORAL','GREEN_GLASS','CLEAR_GLASS','CRYSTAL_GLASS','YARN'},
 finished_goods={'WOOD','PLANT_CLOTH','BONE','TOOTH','HORN','PEARL','SHELL','LEATHER','SILK','AMBER','CORAL','GREEN_GLASS','CLEAR_GLASS','CRYSTAL_GLASS','YARN','WAX'},
 bars={'COAL','POTASH','ASH','PEARLASH','SOAP'},blocks={'GREEN_GLASS','CLEAR_GLASS','CRYSTAL_GLASS','WOOD'}}
other_materials.weapons=other_materials.armor
for _,cat in ipairs{'ammo','armor','furniture','finished_goods','weapons'} do
 setting_leaf(cat..'/other_materials',cat..'.other_mats','other',cat)
end
setting_leaf('bars_blocks/bars_other','bars_blocks.bars_other_mats','other','bars')
setting_leaf('bars_blocks/blocks_other','bars_blocks.blocks_other_mats','other','blocks')
local finished_item_types={CHAIN=true,FLASK=true,GOBLET=true,INSTRUMENT=true,TOY=true,ARMOR=true,SHOES=true,
 HELM=true,GLOVES=true,FIGURINE=true,AMULET=true,SCEPTER=true,CROWN=true,RING=true,EARRING=true,BRACELET=true,
 GEM=true,TOTEM=true,PANTS=true,BACKPACK=true,QUIVER=true,SPLINT=true,CRUTCH=true,TOOL=true,BOOK=true}
local refused_item_types={NONE=true,BAR=true,SMALLGEM=true,BLOCKS=true,ROUGH=true,BOULDER=true,CORPSE=true,
 CORPSEPIECE=true,ROCK=true,ORTHOPEDIC_CAST=true,BRANCH=true}
-- Native Refuse/Item types mixes item-type bits with two independent booleans.
local embedded_settings={['refuse/type']={
 {key='refuse/type/fresh_raw_hide',field='refuse.fresh_raw_hide',source='toggle',label='Fresh raw hide'},
 {key='refuse/type/rotten_raw_hide',field='refuse.rotten_raw_hide',source='toggle',label='Rotten raw hide'}}}
-- Native e5 Finished goods/Refuse rows and e20 d3_type_picker compare/type
-- pairs. Enum captions are often singular and are not the stockpile captions.
local item_type_captions={AMMO='ammunition',AMULET='amulets',ANIMALTRAP='animal traps',ANVIL='anvils',
 ARMOR='armor',ARMORSTAND='armor stands',BACKPACK='backpacks',BAG='bags',
 BALLISTAARROWHEAD='ballista arrow heads',BALLISTAPARTS='ballista parts',BARREL='barrels',
 BED='beds',BIN='bins',BOLT_THROWER_PARTS='bolt thrower parts',BOX='boxes',BRACELET='bracelets',
 BRANCH='branches',BUCKET='buckets',CABINET='cabinets',CAGE='cages',CATAPULTPARTS='catapult parts',
 BOOK='codices',CHAIN='chains',CROWN='crowns',CRUTCH='crutches',EARRING='earrings',
 FIGURINE='figurines',FLASK='flasks',SHOES='footwear',GOBLET='goblets',GLOVES='handwear',
 HELM='headwear',GEM='large gems',PANTS='legwear',INSTRUMENT='musical instruments',QUIVER='quivers',
 RING='rings',SCEPTER='scepters',SPLINT='splints',TOOL='tools',TOTEM='totems',TOY='toys',
 CHAIR='thrones',COFFIN='coffins',COIN='coins',DOOR='doors',DRINK='drinks',FLOODGATE='floodgates',
 GRATE='grates',HATCH_COVER='hatch covers',SKIN_TANNED='tanned hides',TRAPPARTS='mechanisms',
 MILLSTONE='millstones',PLANT='plants',PLANT_GROWTH='leaves and fruit',FOOD='prepared meals',QUERN='querns',
 SHIELD='shields/bucklers',SLAB='slabs',STATUE='statues',TABLE='tables',PET='small tame animals',
 TRACTION_BENCH='traction benches',TRAPCOMP='trap components',VERMIN='small live animals',
 WEAPON='weapons',WEAPONRACK='weapon racks',WINDOW='windows'}
 -- Complete native Furniture/Type captions captured on the supported DF build.
local furniture_captions={ANVIL='Anvils',ARMORSTAND='Armor stands',BAG='Bags',BALLISTAARROWHEAD='Ballista arrow heads',
 BALLISTAPARTS='Ballista parts',BARREL='Barrels',BED='Beds',BIN='Bins',BOLT_THROWER_PARTS='Bolt thrower parts',
 BOX='Boxes',BUCKET='Buckets',CABINET='Cabinets',CATAPULTPARTS='Catapult parts',COFFIN='Coffins',DOOR='Doors',FLOODGATE='Floodgates',
 GRATE='Grates',HATCH_COVER='Hatch covers',FOOD_STORAGE='Large pots/food storage',TRAPPARTS='Mechanisms',
 MILLSTONE='Millstones',MINECART='Minecarts',OTHER_LARGE_TOOLS='Other large tools',PIPE_SECTION='Pipe section',
 QUERN='Querns',SAND_BAG='Sand bags',SIEGEAMMO='Siege ammo',SLAB='Slabs',STATUE='Statues',TABLE='Tables',
 CHAIR='Thrones',TRACTION_BENCH='Traction benches',WEAPONRACK='Weapon racks',WHEELBARROW='Wheelbarrows',WINDOW='Windows'}
local function setting_source(d)
 local raws=df.global.world.raws
 if d.source=='toggle' then return nil,1
 elseif d.source=='quality' then return nil,7
 elseif d.source=='other' then return other_materials[d.selector],#other_materials[d.selector]
 elseif d.source=='inorganic' then return raws.inorganics.all,#raws.inorganics.all
 elseif d.source=='builtin' then return raws.mat_table.builtin,#raws.mat_table.builtin
 elseif d.source=='itemtype' then return nil,df.item_type._last_item+1
 elseif d.source=='furniture' then return nil,df.furniture_type._last_item+1
 elseif d.source=='color' then return raws.descriptors.colors,#raws.descriptors.colors
 elseif d.source=='itemdef' then return raws.itemdefs[d.selector],#raws.itemdefs[d.selector]
 elseif d.source=='organic' then
  local values=raws.mat_table.organic_types[df.organic_mat_category[d.selector]];return values,#values
 elseif d.source=='creature' then return raws.creatures.all,#raws.creatures.all
 elseif d.source=='plant' then return raws.plants.all,#raws.plants.all end
end
-- Verbatim native settings copy captured in the supported build (2011 audit).
local quality_captions={'Standard','Well-crafted','Finely-crafted','Superior quality','Exceptional','Masterwork','Artifact'}
local other_captions={WOOD='Wood',BONE='Bone',LEATHER='Leather',SHELL='Shell',SILK='Silk',YARN='Yarn',
 PLANT_CLOTH='Plant Cloth',CLEAR_GLASS='Clear Glass',CRYSTAL_GLASS='Crystal Glass',GREEN_GLASS='Green Glass',
 AMBER='Amber',CORAL='Coral',HORN='Horn',PEARL='Pearl',TOOTH='Tooth',WAX='Wax',
 ASH='Ash',COAL='Coal',PEARLASH='Pearlash',POTASH='Potash',SOAP='Soap'}
local function setting_caption(d,index,values)
 if d.source=='toggle' then return '' end
 if d.source=='quality' then return quality_captions[index+1] or '' end
 if d.source=='furniture' then
  local token=df.furniture_type[index];return furniture_captions[token] or token or ''
 end
 if d.source=='itemtype' then
  local key=df.item_type[index]
  if d.selector=='finished_goods' and not finished_item_types[key] or d.selector=='refuse' and refused_item_types[key] then return nil end
  return item_type_captions[key] or df.item_type.attrs[index].caption or ''
 end
 if d.source=='builtin' then
  -- Builtin slots outside glass may be null (notably INORGANIC). Filter their
  -- native indices before trying to read a material object.
  local token=df.builtin_mats[index]
  if token~='GLASS_GREEN' and token~='GLASS_CLEAR' and token~='GLASS_CRYSTAL' then return nil end
  local material=dfhack.matinfo.decode(index,-1)
  return material and material:toString() or ''
 end
 local v=element(values,index)
 if v==nil then error('Settings source changed') end
 if d.source=='other' then
  local caption=other_captions[v] or ''
  -- Furniture uses lower-case second words; other captured lists use title case.
  if d.selector=='furniture' then
   local furniture_other={PLANT_CLOTH='Plant cloth',CLEAR_GLASS='Clear glass',CRYSTAL_GLASS='Crystal glass',GREEN_GLASS='Green glass'}
   caption=furniture_other[v] or caption
  end
  return caption
 elseif d.source=='inorganic' then
  local f=v.material.flags;local part
  if d.selector=='any' then part='any'
  elseif d.selector=='stone' then
   if not (v.flags.SOIL and not v.flags.AQUIFER or f.IS_STONE and not f.NO_STONE_STOCKPILE) then return nil end
   if #v.metal_ore.mat_index>0 then part='metal_ores'
   elseif #v.economic_uses>0 then part='economic'
   elseif v.flags.SOIL then part='clay'
   else part='other_stone' end
  elseif d.selector=='rough_gem' then part=f.IS_GEM and 'gem' or nil
  elseif d.selector=='cut_gem' then part=f.IS_GEM and 'gem' or f.IS_STONE and 'stone' or nil
  elseif d.selector=='finished_goods' then part=f.IS_GEM and 'gem' or f.IS_METAL and 'metal' or f.IS_STONE and 'stone' or nil
  elseif d.selector=='ammo' or d.selector=='armor' or d.selector=='metal' then part=f.IS_METAL and 'metal' or nil
  else part=f.IS_METAL and 'metal' or f.IS_STONE and 'stone' or nil end
  if not part or d.partition and d.partition~=part then return nil end
  -- Rough-gem stockpile rows use the native plural, including irregular names.
  if (d.selector=='rough_gem' or d.selector=='cut_gem' and part=='gem') and v.material.gem_name2 and v.material.gem_name2~='' then
   local plural=v.material.gem_name2
   if plural=='STP' then plural=(v.material.gem_name1 or '')..'s' end
   return plural,part
  end
  local material=dfhack.matinfo.decode(0,index)
  return material and material:toString() or '',part
 elseif d.source=='color' then return v.name or ''
 elseif d.source=='itemdef' then
  local label=v.name_plural or v.name or ''
  if v.adjective and v.adjective~='' and label~='' then label=v.adjective..' '..label end
  return label
 elseif d.source=='creature' then
  if v.flags.GENERATED or v.creature_id=='EQUIPMENT_WAGON' then return nil end
  return v.name[1] or ''
 elseif d.source=='plant' then
  if not v.flags.TREE then return nil end
  return v.name_plural or ''
 elseif d.source=='organic' then
  local raws=df.global.world.raws;local category=df.organic_mat_category[d.selector]
  local indexes=raws.mat_table.organic_indexes[category]
  if #indexes~=#values then error('Settings source changed') end
  local mat_index=element(indexes,index)
  if d.selector=='Fish' or d.selector=='UnpreparedFish' or d.selector=='Eggs' then
   local creature=element(raws.creatures.all,v)
   local caste=creature and element(creature.caste,mat_index)
   return caste and caste.caste_name[0] or ''
  end
  local material=dfhack.matinfo.decode(v,mat_index)
  local caption=material and material:toString() or ''
  -- Captured e5 thread(silk)/paper lists include these product nouns.
  if caption~='' then
   if d.field=='cloth.thread_silk' or d.field=='cloth.thread_plant' then caption=caption..' thread'
   elseif d.field=='cloth.thread_yarn' then caption=caption..' yarn'
   elseif d.field=='cloth.thread_metal' then caption=caption..' strands'
   elseif d.field:match('^cloth%.cloth_') then caption=caption..' cloth'
   elseif d.field=='sheet.paper' or d.field=='sheet.parchment' then caption=caption..' sheet' end
  end
  return caption
 end
 return ''
end
local function setting_state(b,d,index)
 local cat,field=d.field:match('^([^%.]+)%.(.+)$');local values=b.settings[cat][field]
 if d.source=='toggle' then return values and 2 or 1 end
 local v=index<#values and element(values,index) or 0
 return (v==true or type(v)=='number' and v~=0) and 2 or 1
end
local function append_setting(job,label,index)
 if label==nil then return end -- ineligible raw; not an uncaptioned row
 label=dfhack.df2utf(label)
 if type(label)~='string' or #label>512 then job.error='Area setting label exceeds 512 bytes';return end
 if label=='' then job.omitted=job.omitted+1;return end
 local key=job.list_key..'/'..index
 if #key>64 then job.error='Area setting key exceeds 64 bytes';return end
 if job.ids[key] then job.error='Duplicate row key '..key;return end
 if #job.rows==65536 then job.error='List exceeds 65,536 entries';return end
 job.ids[key]=true
 job.rows[#job.rows+1]={key=key,index=index,label=label,kind=4,state=0,estimated=false}
end
-- Native display order is independent of the wire bit/preset order in cats.
-- These captions/order come from e5/e2. Uncaptured Food rows retain the pinned
-- serializer's names under the PM's departure16, without invented wording.
local setting_pages={['']={}}
local summary_nodes={}
local function setting_node(parent,key,label,node_kind,field)
 local n={parent=parent,key=key,label=label,kind=node_kind,field=field}
 setting_pages[parent]=setting_pages[parent] or {}
 setting_pages[parent][#setting_pages[parent]+1]=n;summary_nodes[#summary_nodes+1]=n
end
for _,entry in ipairs{{'ammo','Ammo'},{'animals','Animals'},{'armor','Armor'},{'bars_blocks','Bars/blocks'},
 {'cloth','Cloth'},{'coins','Coins'},{'finished_goods','Finished goods'},{'food','Food'},
 {'furniture','Furniture/siege ammo'},{'gems','Gems'},{'leather','Leather'},{'corpses','Corpses'},
 {'refuse','Refuse'},{'sheet','Sheet'},{'stone','Stone'},{'weapons','Weapons/trap comps'},{'wood','Wood'}} do
 setting_node('',entry[1],entry[2],1);setting_pages[entry[1]]={}
end
setting_node('','organic','Organic',3,'misc.allow_organic')
setting_node('','inorganic','Inorganic',3,'misc.allow_inorganic')
local function setting_columns(cat,entries)
 for _,entry in ipairs(entries) do
  setting_node(cat,cat..'/'..entry[1],entry[2],entry[3] and 3 or 2,entry[3] and cat..'.'..entry[1] or nil)
 end
end
setting_columns('ammo',{{'type','Type'},{'metal','Metal'},{'other_materials','Other materials'},
 {'quality_core','Core quality'},{'quality_total','Total quality'}})
setting_columns('animals',{{'empty_cages','Empty cages',true},{'empty_traps','Empty animal traps',true}})
setting_columns('armor',{{'body','Body'},{'head','Head'},{'feet','Feet'},{'hands','Hands'},{'legs','Legs'},
 {'shield','Shield'},{'metal','Metal'},{'other_materials','Other materials'},{'quality_core','Core quality'},
 {'quality_total','Total quality'},{'color','Color'},{'usable','Usable armor',true},
 {'unusable','Unusable armor',true},{'undyed','Undyed',true},{'dyed','Dyed',true}})
setting_columns('bars_blocks',{{'bars_metal','Bars: metal'},{'bars_other','Bars: other materials'},
 {'blocks_stone','Blocks: stone/clay'},{'blocks_metal','Blocks: metal'},{'blocks_other','Blocks: other materials'}})
setting_columns('cloth',{{'thread_silk','Thread (silk)'},{'thread_plant','Thread (plant)'},{'thread_yarn','Thread (yarn)'},
 {'thread_metal','Thread (metal)'},{'cloth_silk','Cloth (silk)'},{'cloth_plant','Cloth (plant)'},
 {'cloth_yarn','Cloth (yarn)'},{'cloth_metal','Cloth (metal)'},{'color','Color'},{'undyed','Undyed',true},{'dyed','Dyed',true}})
setting_columns('finished_goods',{{'type','Type'},{'stone','Stone/clay'},{'metal','Metal'},{'gem','Gem'},
 {'other_materials','Other materials'},{'quality_core','Core quality'},{'quality_total','Total quality'},
 {'color','Color'},{'undyed','Undyed',true},{'dyed','Dyed',true}})
setting_columns('food',{{'prepared_meals','Prepared meals',true},{'meat','Meat'},{'fish','Fish'},
 {'unprepared_fish','Unprepared fish'},{'egg','Egg'},{'plants','Plants'},{'drink_plant','Drink (plant)'},
 {'drink_animal','Drink (animal)'},{'cheese_plant','cheese/plant'},{'cheese_animal','Cheese (animal)'},
 {'seeds','Seeds'},{'leaves','Fruit/leaves'},{'powder_plant','Milled plant'},{'powder_creature','powder/animal'},
 {'glob','Fat'},{'glob_paste','Paste'},{'glob_pressed','Pressed material'},{'liquid_plant','Extract (plant)'},
 {'liquid_animal','Extract (animal)'},{'liquid_misc','Misc. liquid'}})
setting_columns('furniture',{{'type','Type'},{'stone','Stone/clay'},{'metal','Metal'},
 {'other_materials','Other materials'},{'quality_core','Core quality'},{'quality_total','Total quality'}})
setting_columns('gems',{{'rough_gem','Rough gem'},{'rough_glass','Rough glass'},
 {'cut_gem','Cut gem'},{'cut_glass','Cut glass'},{'cut_stone','Cut stone'}})
setting_columns('leather',{{'type','Type'},{'color','Color'},{'undyed','Undyed',true},{'dyed','Dyed',true}})
setting_columns('refuse',{{'type','Item types'},{'corpses','Corpses'},{'body_parts','Body parts'},
 {'skulls','Skulls'},{'bones','Bones'},{'shells','Shells'},{'teeth','Teeth'},{'horns','Horns/hooves'},{'hair','Hair/wool'}})
setting_columns('sheet',{{'paper','Paper'},{'parchment','Parchment'}})
setting_columns('stone',{{'metal_ores','Metal ores'},{'economic','Economic'},{'other_stone','Other stone'},{'clay','Clay'}})
setting_columns('weapons',{{'weapons','Weapons'},{'trap_components','Trap components'},{'metal','Metal'},
 {'stone','Stone'},{'other_materials','Other materials'},{'quality_core','Core quality'},
 {'quality_total','Total quality'},{'usable','Usable weapons',true},{'unusable','Unusable weapons',true}})
-- Coins/Corpses/Wood have direct leaves without an intermediate native column.
local summary_groups={}
do
 local by_field={}
 for key,d in pairs(setting_leaves) do
  local group=by_field[d.field]
  if not group then
   group={field=d.field,source=d.source,selector=d.selector,views={},cat=d.field:match('^([^%.]+)')}
   by_field[d.field]=group;summary_groups[#summary_groups+1]=group
  end
  group.views[#group.views+1]={key=key,partition=d.partition}
 end
 for _,field in ipairs{'animals.empty_cages','animals.empty_traps','armor.usable','armor.unusable',
  'armor.dyed','armor.undyed','cloth.dyed','cloth.undyed','finished_goods.dyed','finished_goods.undyed',
  'food.prepared_meals','leather.dyed','leather.undyed','misc.allow_organic','misc.allow_inorganic',
  'refuse.fresh_raw_hide','refuse.rotten_raw_hide','weapons.usable','weapons.unusable'} do
  local views={{key=field}}
  if field=='refuse.fresh_raw_hide' or field=='refuse.rotten_raw_hide' then views[#views+1]={key='refuse/type'} end
  summary_groups[#summary_groups+1]={field=field,source='toggle',cat=field:match('^([^%.]+)'),views=views}
 end
 table.sort(summary_groups,function(a,b)return a.field<b.field end)
end
-- Immutable edit templates parallel the visible hierarchy. Category actions
-- include all backing fields (including fields without a separate visible row);
-- List actions include only that page's members. Direct leaves win over empty
-- middle pages for Coins/Corpses/Wood. All scopes share one preflight/commit path.
local setting_partitions={metal=2,stone=4,gem=8,metal_ores=16,economic=32,clay=64,other_stone=128}
local edit_categories,edit_lists,edit_rows={},{},{}
local function edit_template() return {entries={},fields={},flags={}} end
local function merge_edit(target,source)
 for _,entry in ipairs(source.entries) do
  local prior=target.fields[entry.field]
  if prior then prior.selection=(prior.selection==0 or entry.selection==0) and 0 or (prior.selection | entry.selection)
  else
   local copy={field=entry.field,source=entry.source,selection=entry.selection}
   target.entries[#target.entries+1]=copy;target.fields[entry.field]=copy
  end
 end
 for key in pairs(source.flags) do target.flags[key]=true end
end
local edit_all=edit_template()
for _,cat in ipairs(cats) do edit_categories[cat]=edit_template();edit_categories[cat].flags[cat]=true end
for _,group in ipairs(summary_groups) do
 local one=edit_template();local entry={field=group.field,source=group.source,selection=0}
 one.entries[1]=entry;one.fields[entry.field]=entry
 merge_edit(edit_all,one)
 if edit_categories[group.cat] then merge_edit(edit_categories[group.cat],one) end
end
for _,cat in ipairs(cats) do edit_all.flags[cat]=true end
for key,d in pairs(setting_leaves) do
 local one=edit_template();local entry={field=d.field,source=d.source,selection=setting_partitions[d.partition] or 0}
 one.entries[1]=entry;one.fields[entry.field]=entry;edit_lists[key]=one
end
for parent,nodes in pairs(setting_pages) do
 local page=edit_template();local rows={};edit_rows[parent]=rows
 for _,node in ipairs(nodes) do
  local target
  if node.kind==1 then target=edit_categories[node.key]
  elseif node.kind==2 then target=edit_lists[node.key]
  else
   target=edit_template();local entry={field=node.field,source='toggle',selection=0}
   target.entries[1]=entry;target.fields[entry.field]=entry
  end
  if target then rows[node.key]=target;merge_edit(page,target) end
 end
 if not edit_lists[parent] then edit_lists[parent]=page end
end
local embedded_edits={}
for list,rows in pairs(embedded_settings) do
 for _,row in ipairs(rows) do
  local target=edit_template();local entry={field=row.field,source='toggle',selection=0}
  target.entries[1]=entry;target.fields[row.field]=entry;embedded_edits[row.key]=target
  merge_edit(edit_lists[list],target)
 end
end
local function order_edit_flags(target)
 if target.flag_order then return end
 target.flag_order={}
 for _,cat in ipairs(cats) do if target.flags[cat] then target.flag_order[#target.flag_order+1]=cat end end
end
order_edit_flags(edit_all)
for _,target in pairs(edit_categories) do order_edit_flags(target) end
for _,target in pairs(edit_lists) do order_edit_flags(target) end
for _,target in pairs(embedded_edits) do order_edit_flags(target) end
for _,rows in pairs(edit_rows) do for _,target in pairs(rows) do order_edit_flags(target) end end
local function settings_edit_plan(a,layout,available)
 local list=default(a,'list_key','');local row=default(a,'row_key','');local scope=a.scope
 local target,index
 if scope==4 then target=edit_all
 elseif scope==3 and edit_lists[list] then target=edit_categories[list:match('^([^/]+)')]
 elseif scope==2 then target=edit_lists[list]
 elseif embedded_settings[list] and embedded_edits[row] and row:sub(1,#list+1)==list..'/' then target=embedded_edits[row]
 elseif setting_leaves[list] then
  target=edit_lists[list];local suffix=row:sub(#list+2);index=tonumber(suffix)
  if row:sub(1,#list+1)~=list..'/' or not integer(index) or index<0 or suffix~=tostring(index) then
   return nil,'Unknown stockpile settings row',0
  end
  target={entries={target.entries[1]},flag_order={}}
 else target=edit_rows[list] and edit_rows[list][row] end
 if not target then return nil,'Unknown stockpile settings list or row',0 end
 local used=1+#target.entries
 if available<used then return nil,'Area request exceeds remaining step budget',0 end
 local plan={entries={},flags=target.flag_order,cost=#target.flag_order}
 for _,d in ipairs(target.entries) do
  local entry=type(layout.fields)=='table' and layout.fields[d.field]
  local fixed=d.source=='quality' or d.source=='toggle';local count=entry and entry.count
  if type(entry)~='table' or not integer(count) or count<0 or count>65536 or entry.fixed~=fixed or
   fixed and (count~=(d.source=='quality' and 7 or 1) or entry.stored_count~=count) then
   return nil,'Stockpile settings layout changed',used
  end
  if index and index>=count then return nil,'Unknown stockpile settings row',used end
  local members,allowed,cost
  local leaf=scope==2 and setting_leaves[list]
  local embedded
  for _,candidate in ipairs(embedded_settings[list] or {}) do
   if candidate.field==d.field then embedded=candidate;break end
  end
  if leaf and embedded then leaf=embedded end
  local query=default(a,'query',''):lower()
  if leaf and query~='' then
   local values,raw_count=setting_source(leaf)
   if raw_count~=count then return nil,'Stockpile settings layout changed',used end
   if available-used<2*count then return nil,'Area request exceeds remaining step budget',used end
   local backing={};for key,value in pairs(leaf) do backing[key]=value end;backing.partition=nil
   local selected,eligible={},{}
   for i=0,count-1 do
    local label=embedded and embedded.label or setting_caption(leaf,i,values)
    eligible[i+1]=setting_caption(backing,i,values)~=nil and '\1' or '\0'
    selected[i+1]=label and dfhack.df2utf(label):lower():find(query,1,true) and '\1' or '\0'
   end
   used=used+2*count
   members=table.concat(selected);allowed=table.concat(eligible)
   cost=fixed and 2 or 1+((count+255)//256)
  elseif fixed then
   allowed=string.rep('\1',count)
   members=index and string.rep('\0',index)..'\1'..string.rep('\0',count-index-1) or allowed
   cost=2
  else members={count=count,selection=d.selection,row=index or -1};allowed='';cost=1+2*((count+255)//256) end
  -- Native global headers: None preserves misc toggles; All skips Refuse and
  -- Corpses entirely (captures215131/220959), including their filter contents.
  local preserve=scope==4 and (a.value==1 and (d.field=='misc.allow_organic' or d.field=='misc.allow_inorganic') or
   a.value==2 and (d.field:match('^refuse%.') or d.field:match('^corpses%.')))
  if not preserve then
   plan.entries[#plan.entries+1]={field=d.field,members=members,allowed=allowed,cost=cost}
   plan.cost=plan.cost+cost
  end
 end
 return plan,nil,used
end
local function count_setting(counts,key,state)
 local entry=counts[key] or {on=0,off=0};counts[key]=entry
 if state==2 then entry.on=entry.on+1 else entry.off=entry.off+1 end
end
local function summary_state(counts,key)
 local entry=counts[key]
 if not entry or entry.on==0 then return 1 end
 return entry.off==0 and 2 or 3
end
local link_sources={'give_to_pile','take_from_pile','give_to_workshop','take_from_workshop'}
local location_kinds={INN_TAVERN=1,TEMPLE=2,LIBRARY=3,GUILDHALL=4,HOSPITAL=5}
local function location_row(v,site_id)
 local k=location_kinds[df.abstract_building_type[v:getType()]]
 if not k then return nil end
 local religion=''
 if k==2 and v.deity_data.practice_id>=0 then
  local entity
  if v.deity_type==df.religious_practice_type.WORSHIP_HFID then entity=df.historical_figure.find(v.deity_data.practice_id)
  elseif v.deity_type==df.religious_practice_type.RELIGION_ENID then entity=df.historical_entity.find(v.deity_data.practice_id) end
  if entity then religion=dfhack.df2utf(dfhack.translation.translateName(entity.name,true)) end
 end
 return {id=v.id,site_id=site_id,name=dfhack.df2utf(dfhack.translation.translateName(v.name,true)),location_kind=k,religion=religion,
  guild_profession=k==4 and v.contents.profession or -1,location_tier=k==4 and v.contents.location_tier or -1}
end
local function candidate_row(job,v)
 if job.locations then return location_row(v,job.site_id) end
 if job.legacy and job.kind==0 then return {id=v.id,name=name(v)..' #'..v.id,label=''} end
 if job.candidate_kind==3 then
  if v.entity_id~=df.global.plotinfo.group_id then return nil end
  local label=v.alias~='' and v.alias or dfhack.translation.translateName(v.name,true)
  return {id=v.id,name=dfhack.df2utf(label),profession='',sex=-1,mood=0,grazer=false,
   assigned=job.assigned[v.id]~=nil,squad_use=job.assigned[v.id] or 0}
 end
 if not U.isActive(v) or U.isDead(v) then return nil end
 if job.candidate_kind==1 then
  if not U.isCitizen(v) then return nil end
 elseif U.isCitizen(v) or not (U.isTame(v) or v.flags1.caged) then return nil end
 local label=job.candidate_kind==1 and not job.legacy and unit_name(v) or dfhack.df2utf(U.getReadableName(v))
 if job.legacy then return {id=v.id,name=label..' #'..v.id,label=''} end
 return {id=v.id,name=label,profession=dfhack.df2utf(U.getProfessionName(v)),sex=v.sex,
  mood=U.getStressCategory(v)+1,grazer=job.candidate_kind==2 and U.isGrazer(v) or false,
  assigned=job.candidate_kind==1 and v.id==job.owner_id or job.assigned[v.id]~=nil,squad_use=-1}
end
local function append_candidate(job,row)
 if not row then return end
 if #job.rows==(job.locations and 65536 or 4096) then
  job.error=job.locations and 'List exceeds 65,536 entries' or job.links and 'Link list exceeds 4,096 entries' or 'Candidate list exceeds 4,096 entries';return
 end
 if type(row.name)~='string' or #row.name>512 or type(row.profession or '')~='string' or #(row.profession or '')>512 or
  type(row.religion or '')~='string' or #(row.religion or '')>512 then
  job.error='Candidate label exceeds 512 bytes';return
 end
 local identity=job.links and table.concat({row.kind,row.direction,row.id},':') or row.id
 if job.ids[identity] then job.error=job.links and 'Duplicate link identity' or 'Duplicate candidate identity';return end
 job.ids[identity]=true;row.ordinal=#job.rows+1;job.rows[#job.rows+1]=row
end
local function row_less(job,a,b)
 local x,y
 if job.settings then
  if setting_leaves[job.list_key].source=='quality' then return a.index<b.index end
  x,y=a.label:lower(),b.label:lower()
  if x==y then x,y=a.index,b.index end
  return x<y
 elseif job.legacy then x,y=a.id,b.id
 elseif job.sort==0 then x,y=a.ordinal,b.ordinal
 elseif job.sort==1 then x,y=a.name:lower(),b.name:lower()
 elseif job.sort==2 then x,y=a.mood,b.mood
 else x,y=a.profession:lower(),b.profession:lower() end
 if x==y then x,y=a.id,b.id end
 if job.descending then return x>y end
 return x<y
end
local function start_sort(job)
 job.phase=2;job.done=0;job.width=1;job.base=1;job.left=1;job.right=2;job.dest={}
 local passes=0;local width=1;while width<#job.rows do passes=passes+1;width=width*2 end
 job.total=#job.rows*passes
end
local function start_filter(job)
 job.phase=3;job.done=0;job.total=#job.rows;job.filter_index=1;job.filtered={}
 if job.settings then
  job.hash=hash_integer(0xcbf29ce484222325,job.epoch)
  for index=1,#job.list_key do job.hash=hash_integer(job.hash,job.list_key:byte(index)) end
  job.hash=hash_integer(job.hash,job.source_total);return
 end
 job.hash=hash_integer(hash_integer(0xcbf29ce484222325,job.epoch),job.area_id)
 job.hash=hash_integer(job.hash,job.candidate_kind)
 if job.locations then job.hash=hash_integer(job.hash,job.site_id) end
end
local function step_summary(job)
 if job.phase==1 then
  local group=summary_groups[job.group_index]
  if not group then
   job.phase=2;job.done=0;job.total=#summary_nodes;job.node_index=1;return
  end
  local b=df.building.find(job.area_id)
  if not b or kind(b)~=0 then job.error='Area no longer exists';return end
  local values,count=setting_source(group)
  if count~=job.field_counts[group.field] then job.error='List changed; refresh';return end
  if job.raw_index==count then
   job.raw_index=0;job.group_index=job.group_index+1;job.done=job.done+1;return
  end
  local label,partition=setting_caption(group,job.raw_index,values)
  if label~=nil then
   local state=setting_state(b,group,job.raw_index)
   count_setting(job.categories,group.cat,state)
   for _,view in ipairs(group.views) do
    if not view.partition or view.partition==partition then count_setting(job.counts,view.key,state) end
   end
  end
  job.raw_index=job.raw_index+1;job.done=job.done+1
 elseif job.phase==2 then
  local node=summary_nodes[job.node_index]
  if not node then
   job.phase=3;job.done=0;job.total=#summary_nodes;job.node_index=1
   job.hash=hash_integer(hash_integer(hash_integer(hash_integer(0xcbf29ce484222325,job.epoch),
    job.area_id),job.area_revision),job.raw_revision);return
  end
  local state=node.kind==1 and summary_state(job.categories,node.key) or summary_state(job.counts,node.field or node.key)
  if node.kind==1 and not job.flags[node.key] or node.parent~='' and not job.flags[node.parent] then state=1 end
  job.node_states[job.node_index]=state
  local counts=job.counts[node.key]
  local empty_food=node.parent=='food' and node.kind==2 and not counts
  if not empty_food then
   if node.label=='' then job.omissions[node.parent]=(job.omissions[node.parent] or 0)+1
   else
    local identity=node.parent..':'..node.key
    if job.ids[identity] then job.error='Duplicate row key '..node.key;return end
    job.ids[identity]=true
    local row={key=node.key,index=-1,label=node.label,
     kind=node.kind,state=state,estimated=false}
    local page=job.pages[node.parent] or {};job.pages[node.parent]=page;page[#page+1]=row
   end
  end
  job.node_index=job.node_index+1;job.done=job.done+1
 else
  if job.node_index>#summary_nodes then
   job.revision=job.hash & 0x7fffffffffffffff;if job.revision==0 then job.revision=1 end
   job.complete=true;job.built_tick=tick();job.phase=0
   job.counts=nil;job.categories=nil;job.flags=nil;job.field_counts=nil;job.node_states=nil;job.ids=nil;return
  end
  job.hash=hash_integer(job.hash,job.node_states[job.node_index])
  job.node_index=job.node_index+1;job.done=job.done+1
 end
end
local function step_list(job)
 if job.summary then return step_summary(job) end
 if job.phase==1 then
  if job.settings then
   local d=setting_leaves[job.list_key];local values,count=setting_source(d)
   if count~=job.source_total then job.error='List changed; refresh';return end
   if job.index==count then
    local extras=embedded_settings[job.list_key] or {};local extra=extras[job.extra_index or 1]
    if extra then
     job.rows[#job.rows+1]={key=extra.key,index=0,label=extra.label,kind=4,descriptor=extra}
     job.extra_index=(job.extra_index or 1)+1;job.done=job.done+1;return
    end
    start_sort(job);return
   end
   append_setting(job,setting_caption(d,job.index,values),job.index)
   job.index=job.index+1;job.done=job.done+1;return
  end
  if job.links then
   local b=df.building.find(job.area_id)
   if not b or kind(b)~=0 then job.error='Area no longer exists';return end
   for group,key in ipairs(link_sources) do
    if #b.links[key]~=job.link_counts[group] then job.error='List changed; refresh';return end
   end
   if job.index==job.source_total then start_sort(job);return end
   local offset=job.index;local group=1
   while offset>=job.link_counts[group] do offset=offset-job.link_counts[group];group=group+1 end
   local target=element(b.links[link_sources[group]],offset)
   if not target or df.building.find(target.id)~=target then job.error='Area no longer exists';return end
   if group<=2 and kind(target)~=0 then job.error='Area kind changed; inspect again';return end
   append_candidate(job,{id=target.id,kind=group<=2 and 0 or 2,direction=group%2==1 and 1 or 2,name=name(target)})
   job.index=job.index+1;job.done=job.done+1;return
  end
  if job.assign_index<job.assign_total then
   local b=df.building.find(job.area_id)
   if not b or kind(b)~=1 then job.error='Area no longer exists';return end
   local values=job.candidate_kind==3 and b.squad_room_info or b.assigned_units
   if #values~=job.assign_total then job.error='List changed; refresh';return end
   local value=element(values,job.assign_index)
   if job.candidate_kind==3 then job.assigned[value.squad_id]=value.mode.whole
   else job.assigned[value]=true end
   job.assign_index=job.assign_index+1;job.done=job.done+1;return
  end
  if job.pile_id then
   local b=df.building.find(job.pile_id)
   if not b or kind(b)~=0 or b.x1~=job.pile_x or b.y1~=job.pile_y or b.x2-b.x1+1~=job.pile_w or b.y2-b.y1+1~=job.pile_h or b.z~=job.pile_z then
    job.error='List changed; refresh';return
   end
   local x,y=job.pile_x+job.cell%job.pile_w,job.pile_y+job.cell//job.pile_w
   job.cell=job.cell+1
   if occupies(b,x,y) and visible{x=x,y=y,z=b.z} then append_candidate(job,candidate_row(job,b));job.pile_id=nil
   elseif job.cell==job.pile_w*job.pile_h then job.pile_id=nil end
   return
  end
  local values=source(job)
  if #values~=job.source_total then job.error='List changed; refresh';return end
  if job.index==job.source_total then start_sort(job);return end
  local value=element(values,job.index);job.index=job.index+1;job.done=job.done+1
  if job.legacy and job.kind==0 then
   local w,h=value.x2-value.x1+1,value.y2-value.y1+1
   if w<1 or h<1 or w>256 or h>256 or w*h>32768 or (value.room.extents and
    (value.room.width<1 or value.room.height<1 or value.room.width>256 or value.room.height>256 or value.room.width*value.room.height>32768)) then
    job.error='This area exceeds the bounded extent inspector (256 per side, 32768 tiles)';return
   end
   job.pile_z=value.z;job.pile_id=value.id;job.pile_x=value.x1;job.pile_y=value.y1;job.pile_w=w;job.pile_h=h;job.cell=0
  else append_candidate(job,candidate_row(job,value)) end
 elseif job.phase==2 then
  local n=#job.rows
  if job.width>=n then start_filter(job);return end
  if job.base>n then
   job.rows=job.dest;job.dest={};job.width=job.width*2;job.base=1;job.left=1;job.right=1+job.width;return
  end
  local mid=math.min(job.base+job.width,n+1);local stop=math.min(job.base+2*job.width,n+1)
  if job.left>=mid and job.right>=stop then
   job.base=job.base+2*job.width;job.left=job.base;job.right=job.base+job.width;return
  end
  if job.left<mid and (job.right>=stop or not row_less(job,job.rows[job.right],job.rows[job.left])) then
   job.dest[#job.dest+1]=job.rows[job.left];job.left=job.left+1
  else job.dest[#job.dest+1]=job.rows[job.right];job.right=job.right+1 end
  job.done=job.done+1
 else
  if job.filter_index>#job.rows then
   job.rows=job.filtered;job.filtered=nil;job.ids=nil;job.assigned=nil;job.dest=nil
   job.revision=job.hash & 0x7fffffffffffffff;if job.revision==0 then job.revision=1 end
   job.complete=true;job.built_tick=tick();job.phase=0;return
  end
  local row=job.rows[job.filter_index];job.filter_index=job.filter_index+1;job.done=job.done+1
  local label=job.settings and row.label or row.name
  if label:lower():find(job.query,1,true) or not job.settings and tostring(row.id)==job.query then
   job.filtered[#job.filtered+1]=row
   if not job.settings then job.hash=hash_integer(job.hash,row.id) end
   if job.links then job.hash=hash_integer(hash_integer(job.hash,row.kind),row.direction) end
   if job.locations then
    job.hash=hash_integer(hash_integer(hash_integer(job.hash,row.location_kind),row.guild_profession),row.location_tier)
    for _,text in ipairs{row.name,row.religion}do
     job.hash=hash_integer(job.hash,#text)
     for i=1,#text do job.hash=hash_integer(job.hash,text:byte(i))end
    end
   end
  end
 end
end
local function advance_lists(r)
 sync_epoch(r.epoch)
 local steps=0
 local order={};for key,job in pairs(area_lists) do
  if (job.builder_kind or 7)==r.builder_kind and not job.complete and not job.error then order[#order+1]={key=key,ticket=job.ticket} end
 end
 table.sort(order,function(a,b)return a.ticket<b.ticket end)
 while steps<r.step and #order>0 do
  for _,entry in ipairs(order) do
   if steps==r.step then break end
   local job=area_lists[entry.key]
   if job and not job.complete and not job.error then
    local ok=pcall(step_list,job);steps=steps+1
    if not ok then job.error='Area list source changed; refresh' end
   end
  end
  local pending=false;for _,entry in ipairs(order) do local job=area_lists[entry.key];if job and not job.complete and not job.error then pending=true;break end end
  if not pending then break end
 end
 return {ok=true,message='',steps=steps,active_kinds=active_kinds()}
end
local function summary_page(r,a,b,area_revision,layout,available)
 local list_key=default(a,'list_key','');local cursor=default(a,'cursor',0)
 if not setting_pages[list_key] then return fail('Unknown stockpile settings list'),0 end
 if not integer(cursor) or cursor<0 or cursor>2147483647 then return fail('invalid area cursor'),0 end
 if not integer(layout.raw_revision) or layout.raw_revision<=0 or type(layout.fields)~='table' then
  return fail('Stockpile settings layout changed'),0
 end
 -- Rebuild from native state in this safe-point call. Simulation-tick TTLs do
 -- not advance while paused and cannot make external native edits coherent.
 local expected=default(a,'expected_list_revision',0);local used=0
 local counts={};local total=#summary_groups
 for _,group in ipairs(summary_groups) do
  used=used+1;local entry=layout.fields[group.field]
  if not entry or not integer(entry.count) or entry.count<0 or entry.count>65536 then return fail('Stockpile settings layout changed'),used end
  counts[group.field]=entry.count;total=total+entry.count
 end
 local flags={};for _,cat in ipairs(cats) do flags[cat]=b.settings.flags[cat] and true or false;used=used+1 end
 local job={summary=true,epoch=r.epoch,area_id=b.id,area_revision=area_revision,raw_revision=layout.raw_revision,
  field_counts=counts,flags=flags,counts={},categories={},pages={},omissions={},node_states={},ids={},
  phase=1,done=0,total=total,group_index=1,raw_index=0}
 while not job.complete and not job.error do step_summary(job);used=used+1 end
 if job.error then return fail(job.error),used end
 local out={ok=true,message=job.complete and 'Observed stockpile setting summaries' or 'Building stockpile setting summaries',
  list_key=list_key,query=default(a,'query',''),build_phase=job.phase,build_done=job.done,build_total=job.total,
  captured_tick=job.built_tick or -1,omitted=job.omissions[list_key] or 0,next_cursor=0,settings={}}
 if not job.complete then return out,used end
 if used==available then return fail('Area page exceeds remaining step budget'),used end
 used=used+1
 local rows=job.pages[list_key] or {};local receipt=hash_integer(job.revision,#rows)
 for i=1,#list_key do receipt=hash_integer(receipt,list_key:byte(i)) end
 receipt=receipt & 0x7fffffffffffffff;if receipt==0 then receipt=1 end
 if expected~=0 and expected~=receipt then return fail('List changed; refresh'),used end
 out.list_revision=receipt
 if cursor<#rows and used==available then return fail('Area page exceeds remaining step budget'),used end
 for index=cursor+1,#rows do
  if #out.settings==128 or used==available then out.next_cursor=index-1;break end
  out.settings[#out.settings+1]=rows[index];used=used+1
 end
 out.truncated=out.next_cursor~=0
 return out,used
end
local function settings_page(r,a,b,area_revision,layout,available)
 local list_key=default(a,'list_key','');local d=setting_leaves[list_key]
 if not d then return summary_page(r,a,b,area_revision,layout,available) end
 local cursor=default(a,'cursor',0)
 if not integer(cursor) or cursor<0 or cursor>2147483647 then return fail('invalid area cursor'),0 end
 local field=layout.fields and layout.fields[d.field]
 if not field or not integer(field.count) or field.count<0 then return fail('Stockpile settings layout changed'),0 end
 if field.count>65536 then return fail('List exceeds 65,536 entries'),0 end
 local query=default(a,'query',''):lower()
 local key=table.concat({1,b.id,area_revision,list_key,field.count,#query,query},':')
 local job=area_lists[key];local expected=default(a,'expected_list_revision',0)
 if not job then
  if expected~=0 then return fail('List changed; refresh'),0 end
  local count=0;local oldest_key,oldest
  for k,value in pairs(area_lists) do count=count+1;if not oldest or value.used<oldest then oldest_key=k;oldest=value.used end end
  if count==8 then area_lists[oldest_key]=nil end
  list_serial=list_serial+1
  job={settings=true,builder_kind=5,epoch=r.epoch,area_id=b.id,list_key=list_key,
   source_total=field.count,query=query,rows={},ids={},omitted=0,index=0,phase=1,done=0,total=field.count+#(embedded_settings[list_key] or {}),
   ticket=list_serial,used=list_serial}
  area_lists[key]=job
 end
 list_serial=list_serial+1;job.used=list_serial
 if job.error then area_lists[key]=nil;return fail(job.error),0 end
 local out={ok=true,message=job.complete and 'Observed stockpile setting items' or 'Building stockpile setting items',
  list_key=list_key,query=default(a,'query',''),build_phase=job.phase,build_done=job.done,build_total=job.total,
  captured_tick=job.built_tick or -1,omitted=job.omitted,next_cursor=0,settings={}}
 if not job.complete then return out,0 end
 if expected~=0 and expected~=job.revision then return fail('List changed; refresh'),0 end
 out.list_revision=job.revision
 if cursor<#job.rows and available==0 then return fail('Area page exceeds remaining step budget'),0 end
 local used=0
 for index=cursor+1,#job.rows do
  if used==128 or used==available then out.next_cursor=index-1;break end
  local cached=job.rows[index]
  out.settings[#out.settings+1]={key=cached.key,index=cached.index,label=cached.label,kind=4,
   state=setting_state(b,cached.descriptor or d,cached.index),estimated=false}
  used=used+1
 end
 out.truncated=out.next_cursor~=0
 return out,used
end
local function candidate_page(r,a,b,area_revision,available)
 local legacy=default(a,'operation',0)==0
 local links=default(a,'operation',0)==10
 local locations=default(a,'operation',0)==6
 local candidate_kind=(links or locations) and 0 or legacy and 1 or a.candidate_kind
 local site=locations and dfhack.world.getCurrentSite() or nil
 if locations and not site then return fail('Location site no longer exists'),0 end
 local query=default(a,'query',''):lower()
 local key=table.concat({locations and 6 or links and 10 or legacy and 0 or 14,a.kind,default(a,'id',-1),candidate_kind,
  default(a,'sort',0),default(a,'sort_descending',false) and 1 or 0,area_revision or 0,site and site.id or -1,#query,query},':')
 local job=area_lists[key];local expected=default(a,'expected_list_revision',0)
 -- Reopening a chooser must observe current metadata even while DF is paused.
 -- Keep the completed snapshot for continuation pages; only a new first-page
 -- interaction retires an already delivered location snapshot.
 if locations and job and job.complete and job.delivered and expected==0 and default(a,'cursor',0)==0 then area_lists[key]=nil;job=nil end
 if job and job.complete and (tick()<job.built_tick or tick()-job.built_tick>candidate_max_age) then area_lists[key]=nil;job=nil end
 if not job then
  if expected~=0 then return fail('List changed; refresh'),0 end
  local count=0;local oldest_key,oldest
  for k,value in pairs(area_lists) do count=count+1;if not oldest or value.used<oldest then oldest_key=k;oldest=value.used end end
  if count==8 then area_lists[oldest_key]=nil end
  list_serial=list_serial+1
  job={epoch=r.epoch,kind=a.kind,area_id=default(a,'id',-1),legacy=legacy,links=links,locations=locations,candidate_kind=candidate_kind,
   sort=default(a,'sort',0),descending=default(a,'sort_descending',false),query=query,rows={},ids={},assigned={},
   phase=1,done=0,index=0,assign_index=0,assign_total=0,ticket=list_serial,used=list_serial}
  if locations then
   job.site_id=site.id
  end
  if b and not links and not locations then
   job.owner_id=b.assigned_unit_id
   if candidate_kind==2 then job.assign_total=#b.assigned_units
   elseif candidate_kind==3 then job.assign_total=#b.squad_room_info end
  end
  if job.assign_total>4096 then return fail('Zone exceeds 4,096 assigned units'),0 end
  if links then
   job.link_counts={};job.source_total=0
   for group,key in ipairs(link_sources) do
    local count=#b.links[key]
    if count>1024 then return fail('Link limit reached; no endpoints changed'),0 end
    job.link_counts[group]=count;job.source_total=job.source_total+count
   end
  else job.source_total=#source(job) end
  job.total=job.source_total+job.assign_total
  area_lists[key]=job
 end
 list_serial=list_serial+1;job.used=list_serial
 if job.error then area_lists[key]=nil;return fail(job.error),0 end
 local out={ok=true,message=locations and 'Building area locations' or links and 'Building area links' or 'Building area candidates',candidate_kind=legacy and 0 or candidate_kind,
  sort=job.sort,sort_descending=job.descending,query=default(a,'query',''),captured_tick=job.built_tick or -1,
  build_phase=job.phase,build_done=job.done,build_total=job.total,next_cursor=0}
 if not job.complete then return out,0 end
 if expected~=0 and expected~=job.revision then return fail('List changed; refresh'),0 end
 out.message=locations and 'Observed area locations' or links and 'Observed area links' or 'Observed area candidates';out.list_revision=job.revision
 local rows={};local cursor=default(a,'cursor',0);local used=0
 -- New operations use an ordinal cursor so every native/name/category order
 -- paginates correctly. Legacy candidates retain their committed ID cursor.
 local first=cursor+1
 if legacy then
  local low,high=1,#job.rows+1
  while low<high do
   if used==available then return fail('Candidate page exceeds remaining step budget'),used end
   local middle=(low+high)//2;used=used+1
   if job.rows[middle].id<cursor then low=middle+1 else high=middle end
  end
  first=low
 end
 if first<=#job.rows and used==available then return fail('Area page exceeds remaining step budget'),used end
 for index=first,#job.rows do
  local row=job.rows[index]
  if not legacy or row.id>=cursor then
   if #rows==128 or used==available then out.next_cursor=legacy and row.id or index-1;break end
   rows[#rows+1]=row;used=used+1
  end
 end
 out[locations and 'locations' or links and 'links' or legacy and 'choices' or 'candidates']=rows;out.truncated=out.next_cursor~=0
 if locations then job.delivered=true end
 return out,used
end

-- Requests hold observations only for this call. No native object or callback
-- is retained in a builder/cache; mutations reserve their reply snapshot first.
local function native_operation(r)
 sync_epoch(r.epoch)
 local a=r.area or {};local op=default(a,'operation',0);local steps=0
 local synchronous=r.synchronous_read==true and r.action==9 and (op==0 or op==1) or
  r.synchronous_write==true and (r.action==11 and (op==0 or op==2 or op==3 or op==5 or op==7 or op==8 or op==9) or r.action==12 and op==0 or r.action==10 and (op==0 or op==5))
 local budget=synchronous and math.huge or default(r,'step_budget',0)
 local unknown_work=false
 local function finish(result)
  result.steps=steps;result.active_kinds=active_kinds();result.operation=integer(op) and op>=0 and op<=15 and op or 0
  if synchronous then result.work_unknown=unknown_work end
  local id=default(a,'id',-1);result.area_id=integer(id) and id>=-1 and id<=2147483647 and id or -1;return result
 end
 local function reject(message) return finish(fail(message)) end
 if not synchronous and (not integer(budget) or budget<0 or budget>1536) then return reject('Invalid area step budget') end
 if budget<10 then return reject('Area request exceeds remaining step budget') end
 steps=10
 local bad=validate_operation(r,a);if bad then return reject(bad) end
 local function invoke(fn,reserve,...)
  local available=budget-steps-reserve
  if available<0 then return nil,'Area request exceeds remaining step budget' end
  if type(fn)~='function' then return nil,'Native area helper unavailable' end
  local args=table.pack(...);args.n=args.n+1;args[args.n]=not synchronous and available or nil
  local worked,result=pcall(fn,table.unpack(args,1,args.n))
  if not worked then
   if synchronous then unknown_work=true else steps=budget end
   return nil,'Native area helper failed; inspect before retrying',true
  end
  if type(result)~='table' or not integer(result.steps) or result.steps<0 or result.steps>available or
   result.work_unknown~=nil and type(result.work_unknown)~='boolean' or result.work_unknown and not synchronous then
   if synchronous then unknown_work=true else steps=budget end
   return nil,'Native area helper returned invalid work accounting',true
  end
  unknown_work=unknown_work or result.work_unknown==true
  steps=steps+result.steps
  if not result.ok then return nil,result.message or 'Native area operation rejected' end
  return result
 end
 local function observe(b,visibility)
  return invoke(r.area_snapshot,0,b,visibility)
 end
 local location_name,religion,location_kind='','',0
 local function observe_location(b)
  if kind(b)~=1 or default(b,'location_id',-1)<0 then return true end
  -- Native location IDs are site-local. Use the zone's recorded site, not the
  -- currently open site's identically numbered location. Binary lookup retains
  -- no native references between calls and charges every comparison.
  if steps==budget then return false,'Area location exceeds remaining step budget' end
  steps=steps+1
  local site=df.world_site.find(b.site_id)
  if not site then return true end
  local values=site.buildings;local low,high=0,#values
  while low<high do
   if steps==budget then return false,'Area location exceeds remaining step budget' end
   steps=steps+1;local middle=(low+high)//2
   local value=element(values,middle)
   if not value then return false,'Location no longer exists' end
   if value.id<b.location_id then low=middle+1 else high=middle end
  end
  if low<#values then
   if steps==budget then return false,'Area location exceeds remaining step budget' end
   steps=steps+1;local value=element(values,low)
   if value and value.id==b.location_id then
    local row=location_row(value,site.id)
    if row then
     if type(row.name)~='string' or #row.name>512 or type(row.religion)~='string' or #row.religion>512 then
      return false,'Area location label exceeds 512 bytes'
     end
     location_name,religion,location_kind=row.name,row.religion,row.location_kind
    end
   end
  end
  return true
 end
 local function info(b,snapshot)
  local k=kind(b);local label=k==1 and df.civzone_type[b.type] or nil
  local out={id=b.id,kind=k,name=name(b),revision=snapshot.revision,
   x=snapshot.x,y=snapshot.y,z=snapshot.z,width=snapshot.width,height=snapshot.height,extents=snapshot.extents,
   tile_count=snapshot.tile_count,zone_type=-1,categories=0,barrels=0,bins=0,wheelbarrows=0,
   links_only=false,active=true,owner_id=-1,owner_name='',owner_allowed=owned(b),gives=snapshot.gives,takes=snapshot.takes,
   zone_label='',location_site_id=kind(b)==1 and default(b,'location_id',-1)>=0 and default(b,'site_id',-1) or -1,location_id=b.location_id or -1,location_name=location_name,religion=religion,location_kind=location_kind,
   owner_profession='',owner_sex=-1,organic=-1,inorganic=-1,assigned_count=-1}
  if k==0 then
   for i,c in ipairs(cats) do if b.settings.flags[c] then out.categories=out.categories | (1 << (i-1)) end end
   out.barrels=b.storage.max_barrels;out.bins=b.storage.max_bins;out.wheelbarrows=b.storage.max_wheelbarrows
   out.links_only=b.stockpile_flag.use_links_only
   out.organic=b.settings.misc.allow_organic and 1 or 0;out.inorganic=b.settings.misc.allow_inorganic and 1 or 0
  else
   out.zone_type=b.type;out.zone_label=zone_labels[label] or '';out.active=b.spec_sub_flag.active
   out.owner_id=b.assigned_unit_id;out.assigned_count=#(snapshot.assigned_units or {})
   local owner=df.unit.find(out.owner_id)
   if owner then
    out.owner_name=unit_name(owner)
    out.owner_profession=dfhack.df2utf(U.getProfessionName(owner))
    out.owner_sex=owner.sex
   end
   local settings={pond_mode=0,facing=0,tomb_citizens=-1,tomb_pets=-1,gather_trees=-1,gather_shrubs=-1}
   if label=='Pond' then settings.pond_mode=b.zone_settings.pond.flag.keep_filled and 2 or 1
   elseif label=='ArcheryRange' then
    local dir=b.zone_settings.archery
    if dir.dir_y==0 then settings.facing=dir.dir_x==-1 and 1 or dir.dir_x==1 and 2 or 0
    elseif dir.dir_x==0 then settings.facing=dir.dir_y==-1 and 3 or dir.dir_y==1 and 4 or 0 end
   elseif label=='Tomb' then
    settings.tomb_citizens=b.zone_settings.tomb.flags.no_citizens and 0 or 1
    settings.tomb_pets=b.zone_settings.tomb.flags.no_pets and 0 or 1
   elseif label=='PlantGathering' then
    settings.gather_trees=b.zone_settings.gather.flags.pick_trees and 1 or 0
    settings.gather_shrubs=b.zone_settings.gather.flags.pick_shrubs and 1 or 0
   end
   out.zone_settings=settings
  end
  return out
 end
 if r.action==7 and op==0 then
  local choices={}
  for i=0,df.civzone_type._last_item do
   if steps==budget then return reject('Area catalog exceeds remaining step budget') end;steps=steps+1
   local key=df.civzone_type[i];if zone_types[key] then choices[#choices+1]={id=i,name=key,label=zone_labels[key]} end
  end
  return finish{ok=true,message='Native stockpile and zone types',choices=choices}
 end
 if r.action==8 and op==0 then
  if not visible{x=a.x,y=a.y,z=a.z} then return reject('Tile is hidden or outside the map') end
  local matches={};local cursor=default(a,'cursor',0)
  local function exhausted() return reject('Too many areas at this tile for one inspection') end
  for _,target in ipairs(df.global.world.buildings.all) do
   if steps==budget then return exhausted() end;steps=steps+1
   if target.id>=cursor and kind(target)>=0 and target.z==a.z and occupies(target,a.x,a.y) then
    matches[#matches+1]=target.id
   end
  end
  -- Keep committed ascending-ID results even if the source vector changes its
  -- ordering. The comparator is counted; an exhausted sort returns no page.
  local sorted=pcall(table.sort,matches,function(left,right)
   if steps==budget then error('area inspection budget') end
   steps=steps+1;return left<right
  end)
  if not sorted then return exhausted() end
  local rows={};local cells,links=0,0;local next_cursor=0
  for _,id in ipairs(matches) do
   if #rows==64 then next_cursor=id;break end
   local target=df.building.find(id)
   if not target or kind(target)<0 then return reject('Area no longer exists') end
   local snapshot,problem=observe(target,false)
   if not snapshot then return reject(problem) end
   if cells+#snapshot.extents>32768 or links+#snapshot.gives+#snapshot.takes>8192 then next_cursor=id;break end
   if steps==budget then return exhausted() end;steps=steps+1
   local row=info(target,snapshot);row.revision=0
   rows[#rows+1]=row;cells=cells+#snapshot.extents;links=links+#snapshot.gives+#snapshot.takes
  end
  return finish{ok=true,message='Observed overlapping areas',areas=rows,next_cursor=next_cursor,truncated=next_cursor~=0}
 end
 if r.action==14 and op==0 then
  local page,used=candidate_page(r,a,nil,0,budget-steps);steps=steps+used;return finish(page)
 end
 if r.action==10 then
  local zone_type=default(a,'zone_type',-1)
  if not integer(zone_type) or zone_type< -1 or zone_type>255 then return reject('invalid area edit') end
  if a.kind==1 and not zone_types[df.civzone_type[zone_type]] then return reject('Unsupported zone type') end
  local new_owner,importer,paths
  if a.kind==0 then
   if default(a,'active',-1)~=-1 or default(a,'owner_id',-2)~=-2 then return reject('Zone-only fields on stockpile') end
   if op==0 then
    local tiles=default(a,'width',1)*default(a,'height',1)
    for _,key in ipairs{'barrels','bins','wheelbarrows'} do
     if default(a,key,-1)>(key=='wheelbarrows' and math.max(0,tiles-1) or tiles) then
      return reject('Container limits exceed usable stockpile tiles')
     end
    end
   end
   if default(a,'categories',0)~=0 then
    local loaded,plugin=pcall(require,'plugins.stockpiles')
    if not loaded or type(plugin)~='table' or type(plugin.stockpiles_import)~='function' then
     return reject('Native stockpile preset plugin unavailable')
    end
    importer=plugin.stockpiles_import;paths={}
    for i,cat in ipairs(cats) do if (a.categories & (1 << (i-1)))~=0 then
     paths[#paths+1]=dfhack.getHackPath()..'/data/stockpiles/cat_'..(cat=='sheet' and 'sheets' or cat)..'.dfstock'
    end end
   end
  else
   if default(a,'changed_categories',0)~=0 or default(a,'barrels',-1)~=-1 or default(a,'bins',-1)~=-1 or
    default(a,'wheelbarrows',-1)~=-1 or default(a,'links_only',-1)~=-1 then return reject('Stockpile-only fields on zone') end
   local owner=default(a,'owner_id',-2)
   if owner~=-2 then
    if not owner_types[df.civzone_type[zone_type]] then return reject('This zone type has no single owner') end
    new_owner=owner>=0 and df.unit.find(owner) or nil
    if owner>=0 and (not new_owner or not U.isCitizen(new_owner) or not U.isActive(new_owner) or U.isDead(new_owner)) then
     return reject('Owner must be an active living citizen of this fortress')
    end
   end
  end
  local created,problem=invoke(r.create_area,0,a)
  clear_lists()
  if not created then return reject(problem) end
  local b=df.building.find(created.building_id)
  if not b or kind(b)~=a.kind then return reject('Created area could not be observed; inspect before retrying') end
  -- The native helper has transferred ownership to DF. Initialization is one
  -- protected Lua call; a normal refusal removes only this newly created area.
  unknown_work=true
  local initializing_presets=false
  local initialized,why=pcall(function()
   if a.kind==0 then
    local barrels,bins,wheelbarrows,links=b.storage.max_barrels,b.storage.max_bins,b.storage.max_wheelbarrows,b.stockpile_flag.use_links_only
    initializing_presets=true
    for _,path in ipairs(paths or {}) do
     if importer(path,b.id,'enable','')~=true then error('Native stockpile preset failed',0) end
    end
    initializing_presets=false
    b.storage.max_barrels=default(a,'barrels',-1)>=0 and a.barrels or barrels
    b.storage.max_bins=default(a,'bins',-1)>=0 and a.bins or bins
    b.storage.max_wheelbarrows=default(a,'wheelbarrows',-1)>=0 and a.wheelbarrows or wheelbarrows
    b.stockpile_flag.use_links_only=default(a,'links_only',-1)>=0 and a.links_only==1 or default(a,'links_only',-1)<0 and links
    for i,cat in ipairs(cats) do if (default(a,'changed_categories',0) & (1 << (i-1)))~=0 then
     b.settings.flags[cat]=(default(a,'categories',0) & (1 << (i-1)))~=0
    end end
   else
    local t=df.civzone_type[b.type]
    if t=='Pen' then b.zone_settings.pen.flags.check_occupants=true
    elseif t=='Pond' then b.zone_settings.pond.flag.keep_filled=false
    elseif t=='ArcheryRange' then b.zone_settings.archery.dir_x=1;b.zone_settings.archery.dir_y=0
    elseif t=='Tomb' then b.zone_settings.tomb.flags.no_pets=true
    elseif t=='PlantGathering' then
     b.zone_settings.gather.flags.pick_trees=true;b.zone_settings.gather.flags.pick_shrubs=true;b.zone_settings.gather.flags.gather_fallen=true
    end
    b.spec_sub_flag.active=default(a,'active',-1)~=0
    if not B.setOwner(b,new_owner) then error('Native owner assignment failed',0) end
    B.notifyCivzoneModified(b)
   end
  end)
  if not initialized then
   local removed=invoke(r.remove_area,0,b)
   if removed then
    local prefix=initializing_presets and 'New pile preset failed; new area removed: ' or 'Invalid new area settings; new area removed: '
    return reject(prefix..tostring(why))
   end
   return reject('New area initialization failed; cleanup uncertain; inspect before retrying')
  end
  local after,why=observe(b,false)
  if not after then return reject(why..'; native creation may have completed; inspect before retrying') end
  return finish{ok=true,message='Native area created',areas={info(b,after)},building_id=b.id,
   hint_x=after.x,hint_y=after.y,hint_z=after.z,hint_width=after.width,hint_height=after.height}
 end
 local workshop
 if op==15 then
  workshop=df.building.find(default(a,'id',-1))
  if not workshop then return reject('Area no longer exists') end
  if not workshop:canLinkToStockpile() then return reject('This workshop cannot link to stockpiles') end
 end
 local b=df.building.find(op==15 and a.link_id or default(a,'id',-1))
 if not b or kind(b)<0 then return reject('Area no longer exists') end
 if kind(b)~=(op==15 and 0 or default(a,'kind',0)) then return reject('Area kind changed; inspect again') end
 local before,why=observe(b,true);if not before then return reject(why) end
 local reply_reserve=before.reply_steps or 154
 if not integer(reply_reserve) or reply_reserve<0 then return reject('Native area helper returned invalid reply reservation') end
 reply_reserve=math.max(154,reply_reserve)
 if not before.visible then return reject('Area is not visible') end
 local expected=default(a,'expected_revision',0)
 if expected~=0 and expected~=before.revision then return reject('Area changed; inspect again') end
 if r.action==12 then
  if expected==0 then return reject('Area revision required; inspect again') end
  -- Save reply geometry before native destruction; neither this handler nor
  -- its native helper may read the building after deconstruct returns.
  local removed,problem=invoke(r.remove_area,0,b)
  clear_lists()
  if not removed then return reject(problem) end
  return finish{ok=true,message='Native area removed',building_id=a.id,
   hint_x=before.x,hint_y=before.y,hint_z=before.z,hint_width=before.width,hint_height=before.height}
 end
 if r.action==11 and op~=7 and op~=8 or r.action==13 or r.action==9 and op==0 then
  local observed,problem=observe_location(b);if not observed then return reject(problem) end
 end
 if r.action==9 and op==0 then return finish{ok=true,message='Observed native area settings',areas={info(b,before)}} end
 if op==7 or op==8 then
  if expected==0 then return reject('Area revision required; inspect again') end
  local site=dfhack.world.getCurrentSite()
  local changed,problem
  if op==7 then changed,problem=invoke(r.set_location,0,b,site,a.location_id)
  else
   if not site then return reject('Location site no longer exists') end
   -- Pinned quickfort generate_name uses this raw table for all five kinds.
   -- Reacquire it in this call; never retain raw references across epochs.
   unknown_work=true
   local language=df.global.world.raws.language
   local names=language and language.word_table and language.word_table[0]
   local words=names and names[35] and names[35].words
   local adjectives=words and words.Adjectives;local nouns=words and words.TheX
   if not adjectives or not nouns or #adjectives==0 or #nouns==0 then return reject('Location name words unavailable') end
   local adjective=element(adjectives,math.random(0,#adjectives-1))
   local noun=element(nouns,math.random(0,#nouns-1))
   if not integer(adjective) or adjective<0 or not integer(noun) or noun<0 then return reject('Location name words unavailable') end
   changed,problem=invoke(r.create_location,0,b,site,a.location_kind,default(a,'profession',-1),
    default(a,'deity_kind',-1),default(a,'deity_id',-1),adjective,noun)
  end
  -- A native recategorization error can follow published relationships. Clear
  -- estimates on every attempted native edit, and never replay a failed call.
  clear_lists()
  if not changed then return reject(problem) end
  location_name,religion,location_kind='','',0
  local observed,why=observe_location(b)
  if not observed then return reject(why..'; native edit may have completed; inspect before retrying') end
  local after,reason=observe(b,false)
  if not after then return reject(reason..'; native edit may have completed; inspect before retrying') end
  return finish{ok=true,message=op==8 and 'Native location created' or 'Native zone location updated',areas={info(b,after)},building_id=b.id}
 end
 if op==3 then
  if expected==0 then return reject('Area revision required; inspect again') end
  local importer,path
  if a.preset~=19 then
   local loaded,plugin=pcall(require,'plugins.stockpiles')
   if not loaded or type(plugin)~='table' or type(plugin.stockpiles_import)~='function' then
    return reject('Native stockpile preset plugin unavailable')
   end
   importer=plugin.stockpiles_import
   local key=a.preset==1 and 'all' or 'cat_'..cats[a.preset-1]
   if key=='cat_sheet' then key='cat_sheets' end
   path=dfhack.getHackPath()..'/data/stockpiles/'..key..'.dfstock'
  end
  -- The transaction helper performs the raw-cap inventory itself, avoiding a
  -- duplicate108-step layout payload. Its synchronous transaction restores all
  -- settings on failure, containers and links-only on success. Opaque importer
  -- work is reported separately, never fabricated as a read-budget step count.
  local changed,problem,unknown=invoke(r.settings_preset,reply_reserve,b,a.preset,importer,path or '')
  if changed or unknown then clear_lists() end
  if not changed then return reject(problem) end
  local after,why=observe(b,false)
  if not after then return reject(why..'; native edit may have completed; inspect before retrying') end
  return finish{ok=true,message='Native stockpile preset applied',areas={info(b,after)},building_id=b.id}
 end
 if op==1 or op==2 then
  -- Count raw index spaces, not the current (possibly empty) settings vectors.
  -- The native inventory contains copied sizes only; shared display partitions
  -- contribute once per backing vector and no native reference is cached.
  local layout,problem=invoke(r.settings_layout,0,b)
  if not layout then return reject(problem) end
  if op==1 then
   local page,used=settings_page(r,a,b,before.revision,layout,budget-steps)
   steps=steps+used;return finish(page)
  end
  if op==2 then
   if expected==0 then return reject('Area revision required; inspect again') end
   local plan,problem,used=settings_edit_plan(a,layout,budget-steps)
   steps=steps+used
   if not plan then return reject(problem) end
   -- Build all selection masks and reserve every field and the reply before
   -- the first native write. Filtered masks use current raw captions, never a
   -- cached/partially paged result. Their scan work is included in used above.
   if budget-steps<plan.cost+reply_reserve then return reject('Area request exceeds remaining step budget') end
   if type(r.settings_fill)~='function' then return reject('Native area helper unavailable') end
   local remaining=plan.cost;local wrote=false
   for _,entry in ipairs(plan.entries) do
    remaining=remaining-entry.cost
    local changed,reason,unknown=invoke(r.settings_fill,reply_reserve+remaining,b,entry.field,entry.members,entry.allowed,a.value==2)
    if changed or unknown then clear_lists() end
    if not changed then
     if wrote then reason=reason..'; earlier filters changed; inspect before retrying' end
     return reject(reason)
    end
    wrote=true
   end
   if #plan.flags>0 then
    clear_lists();steps=steps+#plan.flags
    for _,cat in ipairs(plan.flags) do
     -- Native top-left None clears filters but preserves category activation.
     -- Captured independently from presets in settings-native-summary-212321.
     if a.scope~=4 or (a.value~=1 and cat~='refuse' and cat~='corpses') then b.settings.flags[cat]=a.value==2 end
    end
   end
   local after,why=observe(b,false)
   if not after then return reject(why..'; native edit may have completed; inspect before retrying') end
   return finish{ok=true,message='Native stockpile filters updated',areas={info(b,after)},building_id=b.id}
  end
 end
 if op==6 or op==10 then
  local page,used=candidate_page(r,a,b,before.revision,budget-steps);steps=steps+used;return finish(page)
 end
 if op==14 then
  local zone_type=df.civzone_type[b.type]
  if a.candidate_kind==1 and not owner_types[zone_type] or
   a.candidate_kind==2 and zone_type~='Pen' and zone_type~='Pond' or
   a.candidate_kind==3 and zone_type~='Barracks' and zone_type~='ArcheryRange' then
   return reject('This operation does not apply to this zone type')
  end
  local page,used=candidate_page(r,a,b,before.revision,budget-steps);steps=steps+used;return finish(page)
 end
 if (r.action==11 or r.action==13) and expected==0 then return reject('Area revision required; inspect again') end
 local legacy_link=op==0 and r.action==13
 local legacy_pile_update=op==0 and r.action==11 and kind(b)==0
 local legacy_zone_update=op==0 and r.action==11 and kind(b)==1
 if op~=4 and op~=5 and op~=9 and op~=11 and op~=12 and op~=13 and op~=15 and not legacy_link and not legacy_pile_update and not legacy_zone_update then return reject('Unsupported area operation') end
 if budget-steps<reply_reserve+1 then return reject('Area request exceeds remaining step budget') end
 if op==11 then
  local zone_type=df.civzone_type[b.type]
  if zone_type~='Pen' and zone_type~='Pond' then return reject('This operation does not apply to this zone type') end
  local unit=df.unit.find(a.unit_id)
  if not unit then return reject('Unit no longer exists') end
  if default(r,'area_retire_capacity',0)<1 then return reject('Area retire capacity reached; restart DF3D bridge') end
  local changed,problem,unknown=invoke(r.assign_unit,reply_reserve,b,unit,a.assign)
  if changed or unknown then clear_lists() end
  if not changed then return reject(problem) end
  local after,why=observe(b,false)
  if not after then return reject(why..'; native edit may have completed; inspect before retrying') end
  return finish{ok=true,message='Native unit assignment updated',areas={info(b,after)},building_id=b.id,retired=changed.retired}
 end
 if op==12 then
  local zone_type=df.civzone_type[b.type]
  if zone_type~='Barracks' and (zone_type~='ArcheryRange' or (a.squad_use & ~2)~=0) then
   return reject('This operation does not apply to this zone type')
  end
  local squad=df.squad.find(a.squad_id)
  if not squad or squad.entity_id~=df.global.plotinfo.group_id then return reject('Squad no longer exists') end
  if a.squad_use==0 and default(r,'area_retire_capacity',0)<2 then return reject('Area retire capacity reached; restart DF3D bridge') end
  local changed,problem,unknown=invoke(r.squad_use,reply_reserve,b,squad,a.squad_use)
  if changed or unknown then clear_lists() end
  if not changed then return reject(problem) end
  local after,why=observe(b,false)
  if not after then return reject(why..'; native edit may have completed; inspect before retrying') end
  return finish{ok=true,message='Native squad use updated',areas={info(b,after)},building_id=b.id,retired=changed.retired}
 end
 if legacy_pile_update then
  for _,key in ipairs{'categories','changed_categories'} do
   local value=default(a,key,0)
   if not integer(value) or value<0 or value>0x1ffff then return reject('invalid stockpile categories') end
  end
  for _,key in ipairs{'barrels','bins','wheelbarrows'} do
   local value=default(a,key,-1)
   if not integer(value) or value< -1 or value>32767 then return reject('invalid area edit') end
   local maximum=key=='wheelbarrows' and math.max(0,before.tile_count-1) or before.tile_count
   if value>maximum then return reject('Container limits exceed usable stockpile tiles') end
  end
  local links_only=default(a,'links_only',-1)
  if not integer(links_only) or links_only< -1 or links_only>1 then return reject('invalid area edit') end
  if default(a,'active',-1)~=-1 or default(a,'owner_id',-2)~=-2 then return reject('Zone-only fields on stockpile') end
  if budget-steps<175 then return reject('Area request exceeds remaining step budget') end
 end
 local new_owner
 if legacy_zone_update then
  if default(a,'changed_categories',0)~=0 or default(a,'barrels',-1)~=-1 or default(a,'bins',-1)~=-1 or
   default(a,'wheelbarrows',-1)~=-1 or default(a,'links_only',-1)~=-1 then return reject('Stockpile-only fields on zone') end
  local active,owner=default(a,'active',-1),default(a,'owner_id',-2)
  if not integer(active) or active< -1 or active>1 or not integer(owner) or owner< -2 then return reject('invalid area edit') end
  if owner~=-2 then
   if not owned(b) then return reject('This zone type has no single owner') end
   steps=steps+1
   new_owner=owner>=0 and df.unit.find(owner) or nil
   if owner>=0 and (not new_owner or not U.isCitizen(new_owner) or not U.isActive(new_owner) or U.isDead(new_owner)) then
    return reject('Owner must be an active living citizen of this fortress')
   end

  end
 end
 if op==9 then
  local zone_type=df.civzone_type[b.type]
  for _,entry in ipairs{{'pond_mode','Pond',0},{'facing','ArcheryRange',0},
   {'tomb_citizens','Tomb',-1},{'tomb_pets','Tomb',-1},
   {'gather_trees','PlantGathering',-1},{'gather_shrubs','PlantGathering',-1}} do
   if default(a.zone_settings,entry[1],entry[3])~=entry[3] and zone_type~=entry[2] then
    return reject('Setting '..entry[1]..' does not apply to this zone type')
   end
  end
 end
 local retired,retired_bytes
 if legacy_pile_update then
  -- The snapshot already counted the footprint. Category toggles change only
  -- flags: native material/quality/subtype filters are deliberately preserved.
  clear_lists();steps=steps+21
  for i,key in ipairs(cats) do
   if (default(a,'changed_categories',0) & (1 << (i-1)))~=0 then
    b.settings.flags[key]=(default(a,'categories',0) & (1 << (i-1)))~=0
   end
  end
  if default(a,'barrels',-1)>=0 then b.storage.max_barrels=a.barrels end
  if default(a,'bins',-1)>=0 then b.storage.max_bins=a.bins end
  if default(a,'wheelbarrows',-1)>=0 then b.storage.max_wheelbarrows=a.wheelbarrows end
  if default(a,'links_only',-1)>=0 then b.stockpile_flag.use_links_only=a.links_only==1 end
 elseif legacy_zone_update then
  clear_lists();steps=steps+1
  if default(a,'owner_id',-2)~=-2 then
   unknown_work=true
   local worked,result=pcall(B.setOwner,b,new_owner)
   if not worked then return reject('Native owner assignment failed; inspect before retrying') end
   if not result then return reject('Native owner assignment failed') end
  end
  if default(a,'active',-1)>=0 then b.spec_sub_flag.active=a.active==1 end
  unknown_work=true
  local notified=pcall(B.notifyCivzoneModified,b)
  if not notified then return reject('Native zone notification failed; inspect before retrying') end
 elseif op==15 or legacy_link then
  local first,second=workshop,b
  if legacy_link then
   first=b;second=df.building.find(a.link_id)
   if kind(first)~=0 or not second or kind(second)~=0 then return reject('Links require two different stockpiles') end
   local other,problem=observe(second,true);if not other then return reject(problem) end
   if not other.visible then return reject('Area is not visible') end
  end
  local linked,problem,unknown=invoke(r.link_areas,reply_reserve,first,second,default(a,'give',true),default(a,'unlink',false))
  if linked or unknown then clear_lists() end
  if not linked then return reject(problem) end
 elseif op==4 then
  local requested=default(a,'name','');local converted=dfhack.utf2df(requested)
  if dfhack.df2utf(converted)~=requested then return reject('Name contains characters DF cannot store') end
  if #converted>128 then return reject('Area names are limited to 128 characters') end
  clear_lists();steps=steps+1;b.name=converted
 elseif op==13 then
  clear_lists();steps=steps+1
  if default(a,'organic',-1)~=-1 then b.settings.misc.allow_organic=a.organic==1 end
  if default(a,'inorganic',-1)~=-1 then b.settings.misc.allow_inorganic=a.inorganic==1 end
 elseif op==9 then
  clear_lists();steps=steps+1
  local z=a.zone_settings;local native=b.zone_settings
  if default(z,'pond_mode',0)~=0 then native.pond.flag.keep_filled=z.pond_mode==2 end
  if default(z,'facing',0)~=0 then
   native.archery.dir_x=z.facing==1 and -1 or z.facing==2 and 1 or 0
   native.archery.dir_y=z.facing==3 and -1 or z.facing==4 and 1 or 0
  end
  if default(z,'tomb_citizens',-1)~=-1 then native.tomb.flags.no_citizens=z.tomb_citizens==0 end
  if default(z,'tomb_pets',-1)~=-1 then native.tomb.flags.no_pets=z.tomb_pets==0 end
  if default(z,'gather_trees',-1)~=-1 then native.gather.flags.pick_trees=z.gather_trees==1 end
  if default(z,'gather_shrubs',-1)~=-1 then native.gather.flags.pick_shrubs=z.gather_shrubs==1 end
  unknown_work=true
  local notified=pcall(B.notifyCivzoneModified,b)
  if not notified then return reject('Native zone notification failed; inspect before retrying') end
 elseif op==5 then
  if default(a,'paint_z',-1)~=-1 and a.paint_z~=b.z then return reject("Paint must stay on the area's z level") end
  if default(r,'area_retire_capacity',0)<1 then return reject('Area retire capacity reached; restart DF3D bridge') end
  local painted,problem,unknown=invoke(r.repaint,reply_reserve,b,a.spans,a.paint_mode)
  if painted or unknown then clear_lists() end
  if not painted then return reject(problem) end
  retired=painted.retired;retired_bytes=painted.retired_bytes
 end
 local after,problem=observe(b,false)
 if not after then return reject(problem..'; native edit may have completed; inspect before retrying') end
 return finish{ok=true,message='Native area updated',areas={info(b,after)},building_id=b.id,
  hint_x=b.x1,hint_y=b.y1,hint_z=b.z,hint_width=b.x2-b.x1+1,hint_height=b.y2-b.y1+1,
  retired=retired,retired_bytes=retired_bytes}
end
return function(r)
 -- Builder dispatch precedes area payload access. The job queue belongs to
 -- this helper generation; every yielded state contains copied values only.
 if r.step~=nil or r.builder_kind~=nil then
  if not integer(r.step) or r.step<0 or r.step>2048 or not integer(r.builder_kind) or
   r.builder_kind<5 or r.builder_kind>7 or not integer(r.epoch) then
   return {ok=false,message='Invalid area builder request',steps=0,active_kinds=0}
  end
  return advance_lists(r)
 end
 if not r.area then return fail('Area request missing') end
 if r.action>=7 and r.action<=14 then return native_operation(r) end
 return fail('Unsupported area action')
end
