-- Fixed semantic area helper, embedded in the versioned native bridge.
local B,U=dfhack.buildings,dfhack.units
local native_parent_modes={['food/meat']=1,['furniture/type']=21,['refuse/type']=29,['stone/metal_ores']=39,['ammo/type']=44,['bars_blocks/bars_metal']=51,['gems/rough_gem']=57,['finished_goods/type']=63,['leather/type']=72,['cloth/thread_silk']=75,['weapons/weapons']=86,['armor/body']=94,['sheet/paper']=106}
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
 if not integer(op) or op<0 or (op>15 and op~=26) then return 'Unsupported area operation' end
 local actions={[1]=9,[2]=11,[3]=11,[4]=11,[6]=9,[7]=11,[8]=11,[9]=11,[10]=9,[11]=11,[12]=11,[13]=11,[14]=14,[15]=13,[26]=9}
 if op~=0 and not (op==5 and (r.action==10 or r.action==11) or actions[op]==r.action) then
  return 'Area operation is not valid for this action'
 end
 local k=default(a,'kind',0)
 if not integer(k) or k<0 or k>2 or (k==2)~=(op==15) then return 'Workshop kind is only valid for workshop links' end
 local stock=op==1 or op==2 or op==3 or op==10 or op==13 or op==26
 local zone=(op>=6 and op<=9) or op==11 or op==12 or op==14
 if stock and k~=0 or zone and k~=1 then return 'Area kind is not valid for this operation' end
 if op~=0 and (op~=26 and (a.x~=nil or a.y~=nil or a.z~=nil) or default(a,'width',1)~=1 or default(a,'height',1)~=1 or
  (default(a,'zone_type',-1)~=-1 and not(op==5 and r.action==10)) or default(a,'categories',0)~=0 or
  default(a,'changed_categories',0)~=0 or default(a,'barrels',-1)~=-1 or default(a,'bins',-1)~=-1 or
  default(a,'wheelbarrows',-1)~=-1 or default(a,'links_only',-1)~=-1 or default(a,'active',-1)~=-1 or
  default(a,'owner_id',-2)~=-2 or (op~=15 and (default(a,'link_id',-1)~=-1 or
  (op~=26 and default(a,'give',true)~=true) or default(a,'unlink',false)~=false))) then
  return 'Legacy area fields cannot be combined with an operation'
 end
 local foreign={
  {'expected_list_revision',0,{1,6,10,14}},{'list_key','',{1,2}},{'row_key','',{2}},{'scope',0,{2}},
  {'value',0,{2}},{'preset',0,{3}},{'name','',{4}},{'spans',false,{5}},{'paint_mode',0,{5}},
  {'paint_z',-1,{5}},{'location_id',-2,{7}},{'location_kind',0,{8}},{'profession',-1,{8}},
  {'deity_kind',-1,{8}},{'deity_id',-1,{8}},{'zone_settings',false,{9}},{'unit_id',-1,{11}},{'item_id',-1,{11}},
  {'assign',-1,{11}},{'squad_id',-1,{12}},{'squad_use',-1,{12}},{'organic',-1,{13}},
  {'inorganic',-1,{13}},{'candidate_kind',0,{14}},{'sort',0,{14}},{'sort_descending',false,{14}},
  {'occupation_id',-1,{}},{'category_opening',false,{1}}}
 for _,entry in ipairs(foreign) do
  local v=default(a,entry[1],entry[2]);local present=v~=entry[2]
  if entry[1]=='spans' then present=v~=false and (type(v)~='table' or next(v)~=nil)
  elseif entry[1]=='zone_settings' then
   present=false
   if v~=false then
    if type(v)~='table' then present=true else
     for _,key in ipairs{'pond_mode','facing','tomb_citizens','tomb_pets','gather_trees','gather_shrubs','gather_fallen'} do
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
 if op==26 then
  for _,key in ipairs{'x','y','z'} do
   if not integer(a[key]) or a[key]<0 or a[key]>32767 then return 'invalid stockpile link target request' end
  end
  if default(a,'expected_revision',0)==0 or default(a,'cursor',0)~=0 or default(a,'query','')~='' or
   type(default(a,'give',true))~='boolean' then return 'invalid stockpile link target request' end
 end
 if a.query_bytes~=nil and (type(a.query_bytes)~='string' or #a.query_bytes>33 or r.action~=14 or op~=14 or a.kind~=1 or a.candidate_kind~=1 or default(a,'query','')~='') then return 'invalid owner query bytes' end
 local limit=default(a,'candidate_limit',0)
 if not integer(limit) or limit<0 or limit>128 or (limit~=0 and (r.action~=14 or op~=14 or a.kind~=1 or a.candidate_kind~=1)) then return 'invalid owner candidate limit' end
 for _,key in ipairs{'list_key','row_key','name','query'} do
  local v=default(a,key,'');local cap=(key=='name' and 512) or (key=='query' and 128) or 64
  if type(v)~='string' or #v>cap then return key=='name' and 'area name too long' or 'area key too long' end
 end
 if type(default(a,'category_opening',false))~='boolean' or
  default(a,'category_opening',false) and not native_parent_modes[default(a,'list_key','')] then return 'invalid settings opening context' end
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
  not integer(default(a,'sort',0)) or default(a,'sort',0)<0 or default(a,'sort',0)>(a.candidate_kind==1 and 4 or 3) or
  type(default(a,'sort_descending',false))~='boolean') then return 'invalid area candidate selector' end
 if op==13 then
  local o,i=default(a,'organic',-1),default(a,'inorganic',-1)
  if not integer(o) or not integer(i) or o< -1 or o>1 or i< -1 or i>1 or o==-1 and i==-1 then return 'invalid area toggles' end
 end
 if op==12 and (not integer(default(a,'squad_id',-1)) or default(a,'squad_id',-1)<0 or
  not integer(default(a,'squad_use',-1)) or default(a,'squad_use',-1)<0 or a.squad_use>15) then return 'invalid area squad use' end
 if op==11 and (not integer(default(a,'unit_id',-1)) or default(a,'unit_id',-1)<-1 or
  not integer(default(a,'item_id',-1)) or default(a,'item_id',-1)<-1 or
  ((default(a,'unit_id',-1)>=0)==(default(a,'item_id',-1)>=0)) or
  not integer(default(a,'assign',-1)) or default(a,'assign',-1)<0 or a.assign>1) then return 'invalid area unit assignment' end
 if r.action==13 and (not integer(default(a,'link_id',-1)) or default(a,'link_id',-1)<0 or a.link_id==a.id or
  type(default(a,'give',true))~='boolean' or type(default(a,'unlink',false))~='boolean') then return 'invalid area link' end
 if op==9 then
  local z=a.zone_settings;local present=false
  if type(z)~='table' then return 'invalid area zone settings' end
  for _,key in ipairs{'pond_mode','facing','tomb_citizens','tomb_pets','gather_trees','gather_shrubs','gather_fallen'} do
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
  if not integer(a.paint_mode) or a.paint_mode<1 or a.paint_mode>2 or
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
 if job.native_animals then return job.animal_candidates end
 if job.locations then
  local site=dfhack.world.getCurrentSite()
  if not site or site.id~=job.site_id then job.error='Location site changed; refresh';return {} end
  return site.buildings
 end
 if job.legacy and job.kind==0 then return df.global.world.buildings.other.STOCKPILE end
 if job.candidate_kind==3 then return df.global.world.squads.all end
 if job.native_owner then return df.global.world.units.all end
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
local native_setting_modes={
 ['food/meat']=2,
 ['food/fish']=3,
 ['food/unprepared_fish']=4,
 ['food/egg']=5,
 ['food/plants']=6,
 ['food/drink_plant']=7,
 ['food/drink_animal']=8,
 ['food/cheese_plant']=9,
 ['food/cheese_animal']=10,
 ['food/seeds']=11,
 ['food/leaves']=12,
 ['food/powder_plant']=13,
 ['food/powder_creature']=14,
 ['food/glob']=15,
 ['food/glob_paste']=16,
 ['food/glob_pressed']=17,
 ['food/liquid_plant']=18,
 ['food/liquid_animal']=19,
 ['food/liquid_misc']=20,
 ['leather/type']=73,
 ['cloth/thread_silk']=76,
 ['cloth/thread_plant']=77,
 ['cloth/thread_yarn']=78,
 ['cloth/thread_metal']=79,
 ['cloth/cloth_silk']=80,
 ['cloth/cloth_plant']=81,
 ['cloth/cloth_yarn']=82,
 ['cloth/cloth_metal']=83,
 ['sheet/paper']=107,
 ['sheet/parchment']=108,
 ['stone/metal_ores']=40,['stone/economic']=41,['stone/other_stone']=42,['stone/clay']=43,
 ['gems/rough_glass']=58,['gems/cut_glass']=59,
 ['gems/rough_gem']=60,['gems/cut_gem']=61,['gems/cut_stone']=62,
 ['furniture/stone']=23,['furniture/metal']=24,['ammo/metal']=47,['coins']=50,
 ['bars_blocks/bars_metal']=52,['bars_blocks/blocks_stone']=54,['bars_blocks/blocks_metal']=55,
 ['finished_goods/stone']=65,['finished_goods/metal']=66,['finished_goods/gem']=67,
 ['weapons/metal']=89,['weapons/stone']=90,['armor/metal']=101,
 ['furniture/type']=22,['refuse/type']=30,['finished_goods/type']=64,
 ['wood']=85,
 ['animals/animals']=0,['corpses']=28,
 ['refuse/corpses']=31,['refuse/body_parts']=32,['refuse/skulls']=33,['refuse/bones']=34,
 ['refuse/shells']=35,['refuse/teeth']=36,['refuse/horns']=37,['refuse/hair']=38,
 ['furniture/quality_core']=26,['furniture/quality_total']=27,
 ['ammo/quality_core']=48,['ammo/quality_total']=49,
 ['finished_goods/quality_core']=69,['finished_goods/quality_total']=70,
 ['weapons/quality_core']=92,['weapons/quality_total']=93,
 ['armor/quality_core']=103,['armor/quality_total']=104,
 ['furniture/other_materials']=25,['ammo/other_materials']=46,
 ['bars_blocks/bars_other']=53,['bars_blocks/blocks_other']=56,
 ['finished_goods/other_materials']=68,['weapons/other_materials']=91,
 ['armor/other_materials']=102,
 ['ammo/type']=45,['weapons/weapons']=87,['weapons/trap_components']=88,
 ['armor/body']=95,['armor/head']=96,['armor/feet']=97,['armor/hands']=98,['armor/legs']=99,['armor/shield']=100,
 ['finished_goods/color']=71,['leather/color']=74,['cloth/color']=84,['armor/color']=105,
}
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
for _,cat in ipairs{'ammo','armor','furniture','finished_goods','weapons'} do
 setting_leaf(cat..'/other_materials',cat..'.other_mats','other',cat)
end
setting_leaf('bars_blocks/bars_other','bars_blocks.bars_other_mats','other','bars')
setting_leaf('bars_blocks/blocks_other','bars_blocks.blocks_other_mats','other','blocks')
-- Native Refuse/Item types mixes item-type bits with two independent booleans.
local embedded_settings={['refuse/type']={
 {key='refuse/type/fresh_raw_hide',field='refuse.fresh_raw_hide',source='toggle',label='Fresh raw hide'},
 {key='refuse/type/rotten_raw_hide',field='refuse.rotten_raw_hide',source='toggle',label='Rotten raw hide'}}}
local function setting_state(b,d,index)
 local cat,field=d.field:match('^([^%.]+)%.(.+)$');local values=b.settings[cat][field]
 if d.source=='toggle' then return values and 2 or 1 end
 local v=index<#values and element(values,index) or 0
 return (v==true or type(v)=='number' and v~=0) and 2 or 1
end
-- Native display order is independent of the wire bit/preset order in cats.
-- Captured native columns supply these captions/order; optional Food labels
-- also appear in native renderer3805c4 (Cheese) and380600 (Bone meal).
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
 {'drink_animal','Drink (animal)'},{'cheese_plant','Cheese (plant)'},{'cheese_animal','Cheese (animal)'},
 {'seeds','Seeds'},{'leaves','Fruit/leaves'},{'powder_plant','Milled plant'},{'powder_creature','Bone meal'},
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
-- Leaf masks come exclusively from owned native rows. Header actions use
-- settings_header; only scalar rows have local fixed-storage edit templates.
local edit_lists,edit_rows,embedded_edits={},{},{}
for key,d in pairs(setting_leaves) do
 assert(native_setting_modes[key], 'stockpile leaf has no native row provider: '..key)
 edit_lists[key]={entries={{field=d.field,source=d.source}}}
end
for parent,nodes in pairs(setting_pages) do
 local rows={};edit_rows[parent]=rows
 for _,node in ipairs(nodes) do
  if node.kind==3 then rows[node.key]={entries={{field=node.field,source='toggle'}}} end
 end
end
for list,rows in pairs(embedded_settings) do
 for _,row in ipairs(rows) do
  local entry={field=row.field,source='toggle'}
  embedded_edits[row.key]={entries={entry}}
  edit_lists[list].entries[#edit_lists[list].entries+1]=entry
 end
end
local function native_setting_identity(list,row)
 local d=setting_leaves[list]
 if not d or not integer(row.index) or row.index<0 then return nil end
 if row.field==d.field then return list..'/'..row.index end
 for _,extra in ipairs(embedded_settings[list] or {}) do
  if row.field==extra.field and row.index==0 then return extra.key end
 end
end
local function settings_edit_plan(a,layout,available,native_rows)
 local list=default(a,'list_key','');local row=default(a,'row_key','');local scope=a.scope
 local target,index
 if scope==2 then target=edit_lists[list]
 elseif embedded_settings[list] and embedded_edits[row] and row:sub(1,#list+1)==list..'/' then target=embedded_edits[row]
 elseif setting_leaves[list] then
  target=edit_lists[list];local suffix=row:sub(#list+2);index=tonumber(suffix)
  if row:sub(1,#list+1)~=list..'/' or not integer(index) or index<0 or suffix~=tostring(index) then
   return nil,'Unknown stockpile settings row',0
  end
  target={entries={target.entries[1]}}
 else target=edit_rows[list] and edit_rows[list][row] end
 if not target then return nil,'Unknown stockpile settings list or row',0 end
 if native_rows then
  local seen={};local selected=scope==2
  for _,item in ipairs(native_rows) do
   local identity=native_setting_identity(list,item)
   local field=layout.fields and layout.fields[item.field]
   if not identity or seen[identity] or not field or not integer(field.stored_count) or
    item.index>=field.stored_count then return nil,'',0 end
   seen[identity]=true
   if identity==row and item.visible then selected=true end
  end
  if not selected then return nil,'Unknown stockpile settings row',0 end
 end
 local used=1+#target.entries
 if available<used then return nil,'Area request exceeds remaining step budget',0 end
 local plan={entries={},cost=0}
 for _,d in ipairs(target.entries) do
  local entry=type(layout.fields)=='table' and layout.fields[d.field]
  local fixed=d.source=='quality' or d.source=='toggle';local count=entry and entry.count
  if type(entry)~='table' or not integer(count) or count<0 or count>65536 or entry.fixed~=fixed or
   fixed and (count~=(d.source=='quality' and 7 or 1) or entry.stored_count~=count) then
   return nil,'Stockpile settings layout changed',used
  end
  -- Native leaf actions only touch existing native rows. In particular, All
  -- and None at327fca..3281c9 never resize a short/empty backing vector.
  if native_rows and not fixed then
   count=entry.stored_count
   if not integer(count) or count<0 or count>65536 then return nil,'',used end
  end
  if index and index>=count then return nil,'Unknown stockpile settings row',used end
  local members,allowed,cost
  if native_rows then
   local selected,eligible={},{}
   for i=1,count do selected[i]='\0';eligible[i]='\0' end
   for _,row in ipairs(native_rows) do
    if row.field==d.field then
     eligible[row.index+1]='\1';selected[row.index+1]=row.visible and (not index or index==row.index) and '\1' or '\0'
    end
   end
   if index and selected[index+1]~='\1' then return nil,'Unknown stockpile settings row',used end
   members=table.concat(selected);allowed=table.concat(eligible);cost=fixed and 2 or 1+((count+255)//256)
  elseif fixed then
   allowed=string.rep('\1',count)
   members=index and string.rep('\0',index)..'\1'..string.rep('\0',count-index-1) or allowed
   cost=2
  else return nil,'Unknown stockpile settings list or row',used end
  plan.entries[#plan.entries+1]={field=d.field,members=members,allowed=allowed,cost=cost}
  plan.cost=plan.cost+cost
 end
 return plan,nil,used
end
-- Native33616d..33633b indexes these vectors in this order, preserving each
-- vector's native ID order. Neither click order nor translated names sorts it.
local link_sources={{key='take_from_workshop',kind=2,direction=2},
 {key='give_to_workshop',kind=2,direction=1},
 {key='take_from_pile',kind=0,direction=2},{key='give_to_pile',kind=0,direction=1}}
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
local function candidate_row(job,v,r,refresh_display)
 local order_facts,display,animal_assigned
 if job.native_animals then
  local entry=v
  animal_assigned=entry.assigned
  if entry.entity==2 then
   local item=df.item.find(entry.id)
   if not item then job.error='List changed; refresh';return nil end
   local text=type(r.animal_item_text)=='function' and r.animal_item_text(item) or nil
   if type(text)~='string' then job.error='Native area helper unavailable';return nil end
   return {id=entry.id,entity=2,name=text,profession='',sex=-1,mood=0,grazer=false,
    assigned=animal_assigned,squad_use=-1}
  end
  v=df.unit.find(entry.id)
  if not v then job.error='List changed; refresh';return nil end
 end
 if job.locations then return location_row(v,job.site_id) end
 if job.legacy and job.kind==0 then return {id=v.id,name=name(v)..' #'..v.id,label=''} end
 if job.candidate_kind==3 then
  if v.entity_id~=df.global.plotinfo.group_id then return nil end
  local label=v.alias~='' and v.alias or dfhack.translation.translateName(v.name,true)
  return {id=v.id,entity=3,name=dfhack.df2utf(label),profession='',sex=-1,mood=0,grazer=false,
   assigned=job.assigned[v.id]~=nil,squad_use=job.assigned[v.id] or 0}
 end
 if job.native_owner then
  local b=df.building.find(job.area_id)
  if not b or kind(b)~=1 or b.type~=job.zone_type or b.assigned_unit_id~=job.owner_id then
   job.error='List changed; refresh';return nil
  end
  local eligible
  if type(r.owner_eligible)=='function' then eligible=r.owner_eligible(b,v) end
  if eligible==nil then job.error='Native area helper unavailable';return nil end
  if not eligible then return nil end
  if type(r.owner_order_facts)=='function' then order_facts=r.owner_order_facts(b,v) end
  if not order_facts then job.error='Native area helper unavailable';return nil end
  if refresh_display then
   if type(r.owner_display)=='function' then display=r.owner_display(b,v) end
   if type(display)~='table' or display.columns~=45 or type(display.room_value)~='number' or
    display.room_value<0 or display.room_value%1~=0 or display.room_value>2147483647 or
    type(display.first_line)~='string' or #display.first_line>384 or
    type(display.second_line)~='string' or #display.second_line>384 or
    type(display.status)~='string' or #display.status>256 or
    ((display.room_value==0)~=(display.status=='')) or
    type(display.name)~='string' or type(display.profession)~='string' then
    job.error='Native area helper unavailable';return nil
   end
   if display.sheet_icon~=nil and (type(display.sheet_icon)~='string' or #display.sheet_icon>200*1024)then job.error='Native area helper unavailable';return nil end
   local color=display.name_color
   if type(color)~='table' then job.error='Native area helper unavailable';return nil end
   for key,limit in pairs{foreground=7,background=7,bright=1,alternate_foreground=7,alternate_background=7,alternate_bright=1,effect=3}do
    local value=color[key]
    if type(value)~='number' or value%1~=0 or value<0 or value>limit then job.error='Native area helper unavailable';return nil end
   end
   if color.effect==0 and (color.foreground~=color.alternate_foreground or color.background~=color.alternate_background or color.bright~=color.alternate_bright)then
    job.error='Native area helper unavailable';return nil
   end
  end
  if type(order_facts.name_key)~='string' or #order_facts.name_key>2048 or
   type(order_facts.profession_key)~='string' or #order_facts.profession_key>2048 then
   job.error='Native area helper unavailable';return nil
  end
 elseif not job.native_animals then
  return nil
 end
 local label=display and display.name or job.candidate_kind==1 and not job.legacy and unit_name(v) or dfhack.df2utf(U.getReadableName(v))
 if job.legacy then return {id=v.id,name=label..' #'..v.id,label=''} end
 return {id=v.id,entity=1,name=label,profession=display and display.profession or dfhack.df2utf(U.getProfessionName(v)),sex=v.sex,owner_display=display,sheet_icon=display and display.sheet_icon or nil,
  mood=U.getStressCategory(v)+1,grazer=job.candidate_kind==2 and U.isGrazer(v) or false,
  assigned=job.native_animals and animal_assigned or job.candidate_kind==1 and v.id==job.owner_id or (job.assigned~=nil and job.assigned[v.id]~=nil),squad_use=-1,owner_order=order_facts}
end
local function candidate_text_valid(row)
 return type(row.name)=='string' and #row.name<=512 and type(row.profession or '')=='string' and #(row.profession or '')<=512 and
  type(row.religion or '')=='string' and #(row.religion or '')<=512
end
local function append_candidate(job,row)
 if not row then return end
 if #job.rows==(job.locations and 65536 or 4096) then
  job.error=job.locations and 'List exceeds 65,536 entries' or job.links and 'Link list exceeds 4,096 entries' or 'Candidate list exceeds 4,096 entries';return
 end
 if not candidate_text_valid(row) then
  job.error='Candidate label exceeds 512 bytes';return
 end
 local identity=job.links and table.concat({row.kind,row.direction,row.id},':') or job.native_animals and table.concat({row.entity,row.id},':') or row.id
 if job.ids[identity] then job.error=job.links and 'Duplicate link identity' or 'Duplicate candidate identity';return end
 job.ids[identity]=true;row.ordinal=#job.rows+1;job.rows[#job.rows+1]=row
end
local function compare_native_bytes(a,b)
 for i=1,math.min(#a,#b)do
  local x,y=a:byte(i),b:byte(i);if x~=y then return x<y and -1 or 1 end
 end
 return #a==#b and 0 or #a<#b and -1 or 1
end
local function row_less(job,a,b)
 if job.native_owner then
  local x,y=a.owner_order,b.owner_order
  if x.without_room~=y.without_room then return x.without_room end
  if x.priority~=y.priority then return x.priority>y.priority end
  local cmp
  if job.sort==1 then cmp=compare_native_bytes(x.name_key,y.name_key)
  elseif job.sort==3 then cmp=compare_native_bytes(x.profession_key,y.profession_key)
  elseif job.sort==4 then cmp=x.stress-y.stress
  else
   cmp=x.category-y.category
   if cmp==0 then cmp=x.category_status-y.category_status end
  end
  if cmp==0 then return a.ordinal<b.ordinal end
  return job.descending and cmp>0 or not job.descending and cmp<0
 end
 local x,y
 if job.legacy then x,y=a.id,b.id
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
 job.hash=hash_integer(hash_integer(0xcbf29ce484222325,job.epoch),job.area_id)
 job.hash=hash_integer(job.hash,job.candidate_kind)
 if job.locations then job.hash=hash_integer(job.hash,job.site_id) end
end
local function step_list(job,r)
 if job.phase==1 then
  if job.links then
   local b=df.building.find(job.area_id)
   if not b or kind(b)~=0 then job.error='Area no longer exists';return end
   for group,source in ipairs(link_sources) do
    if #b.links[source.key]~=job.link_counts[group] then job.error='List changed; refresh';return end
   end
   if job.index==job.source_total then start_sort(job);return end
   local offset=job.index;local group=1
   while offset>=job.link_counts[group] do offset=offset-job.link_counts[group];group=group+1 end
   local source=link_sources[group]
   local target=element(b.links[source.key],offset)
   if not target or df.building.find(target.id)~=target then job.error='Area no longer exists';return end
   if source.kind==0 and kind(target)~=0 then job.error='Area kind changed; inspect again';return end
   append_candidate(job,{id=target.id,kind=source.kind,direction=source.direction,name=name(target)})
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
   if occupies(b,x,y) and visible{x=x,y=y,z=b.z} then append_candidate(job,candidate_row(job,b,r));job.pile_id=nil
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
  else append_candidate(job,candidate_row(job,value,r)) end
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
  local label=job.native_owner and row.owner_order.name_key or row.name:lower()
  if label:find(job.query,1,true) or not job.native_owner and tostring(row.id)==job.query then
   job.filtered[#job.filtered+1]=row
   job.hash=hash_integer(job.hash,row.id)
   if job.native_animals then job.hash=hash_integer(hash_integer(job.hash,row.entity),row.assigned and 1 or 0) end
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
    local ok=pcall(step_list,job,r);steps=steps+1
    if not ok then job.error='Area list source changed; refresh' end
   end
  end
  local pending=false;for _,entry in ipairs(order) do local job=area_lists[entry.key];if job and not job.complete and not job.error then pending=true;break end end
  if not pending then break end
 end
 return {ok=true,message='',steps=steps,active_kinds=active_kinds()}
end
local function summary_page(r,a,b,area_revision,layout,available,summary)
 local list_key=default(a,'list_key','');local cursor=default(a,'cursor',0)
 if not setting_pages[list_key] then return fail('Unknown stockpile settings list'),0 end
 if not integer(cursor) or cursor<0 or cursor>2147483647 then return fail('invalid area cursor'),0 end
 if not integer(layout.raw_revision) or layout.raw_revision<=0 then return fail('Stockpile settings layout changed'),0 end
 if type(summary.states)~='table' or #summary.states~=109 or type(summary.categories)~='table' or #summary.categories~=17 or
    type(summary.plant_cheese)~='boolean' or type(summary.animal_powder)~='boolean' then return fail(''),0 end
 for _,values in ipairs{summary.states,summary.categories}do
  for _,value in ipairs(values)do if not integer(value) or value<0 or value>2 then return fail(''),0 end end
 end
 local category_index={};for i,key in ipairs(cats)do category_index[key]=i end
 local native_state={[0]=1,[1]=3,[2]=2};local pages={}
 local hash=hash_integer(hash_integer(hash_integer(hash_integer(0xcbf29ce484222325,r.epoch),b.id),area_revision),layout.raw_revision)
 local used=0
 for _,node in ipairs(summary_nodes)do
  used=used+1
  local visible=not(node.key=='food/cheese_plant' and not summary.plant_cheese or node.key=='food/powder_creature' and not summary.animal_powder)
  if visible then
   local state
   if node.kind==1 then state=native_state[summary.categories[category_index[node.key]]]
   elseif node.kind==2 then
    local mode=native_setting_modes[node.key];if not mode then return fail(''),used end
    state=native_state[summary.states[mode+1]]
   else state=setting_state(b,{field=node.field,source='toggle'},0) end
   local page=pages[node.parent] or {};pages[node.parent]=page
   page[#page+1]={key=node.key,index=-1,label=node.label,kind=node.kind,state=state,estimated=false}
   hash=hash_integer(hash,state)
   for i=1,#node.key do hash=hash_integer(hash,node.key:byte(i))end
   for i=1,#node.label do hash=hash_integer(hash,node.label:byte(i))end
  end
  hash=hash_integer(hash,visible and 1 or 0)
 end
 for i=1,#list_key do hash=hash_integer(hash,list_key:byte(i))end
 local revision=hash & 0x7fffffffffffffff;if revision==0 then revision=1 end
 if default(a,'expected_list_revision',0)~=0 and a.expected_list_revision~=revision then return fail('List changed; refresh'),used end
 local rows=pages[list_key] or {}
 local out={ok=true,message='',list_key=list_key,query=default(a,'query',''),list_revision=revision,
  build_phase=0,build_done=#summary_nodes,build_total=#summary_nodes,captured_tick=tick(),omitted=0,next_cursor=0,settings={}}
 for index=cursor+1,#rows do
  if #out.settings==128 or used>=available then out.next_cursor=index-1;break end
  out.settings[#out.settings+1]=rows[index];used=used+1
 end
 out.truncated=out.next_cursor~=0;return out,used
end
local function native_settings_page(r,a,b,area_revision,layout,rows)
 local key=a.list_key;local d=setting_leaves[key];local cursor=default(a,'cursor',0)
 if not integer(cursor) or cursor<0 or cursor>2147483647 then return fail('invalid area cursor') end
 local hash=hash_integer(hash_integer(hash_integer(0xcbf29ce484222325,r.epoch),b.id),area_revision)
 hash=hash_integer(hash,layout.raw_revision or 0)
 for _,text in ipairs{key,default(a,'query','')} do
  hash=hash_integer(hash,#text);for i=1,#text do hash=hash_integer(hash,text:byte(i)) end
 end
 hash=hash_integer(hash,default(a,'category_opening',false) and 1 or 0)
 local visible={};local identities={}
 for _,row in ipairs(rows) do
  local identity=native_setting_identity(key,row)
  local field=layout.fields and layout.fields[row.field]
  if not identity or identities[identity] or not field or not integer(field.stored_count) or
   row.index>=field.stored_count then return fail('') end
  identities[identity]=true
  hash=hash_integer(hash,#identity)
  for i=1,#identity do hash=hash_integer(hash,identity:byte(i)) end
  hash=hash_integer(hash,row.index);hash=hash_integer(hash,row.enabled and 1 or 0)
  hash=hash_integer(hash,row.visible and 1 or 0);hash=hash_integer(hash,#row.label)
  for i=1,#row.label do hash=hash_integer(hash,row.label:byte(i)) end
  if row.visible then visible[#visible+1]=row end
 end
 local revision=hash & 0x7fffffffffffffff;if revision==0 then revision=1 end
 local expected=default(a,'expected_list_revision',0)
 if expected~=0 and expected~=revision then return fail('List changed; refresh') end
 local out={ok=true,message='',list_key=key,query=default(a,'query',''),list_revision=revision,
  build_phase=0,build_done=#rows,build_total=#rows,settings_count=#visible,captured_tick=tick(),omitted=0,next_cursor=0,settings={}}
 for i=cursor+1,math.min(cursor+128,#visible) do
  local row=visible[i]
  out.settings[#out.settings+1]={key=native_setting_identity(key,row),index=row.index,label=row.label,
   kind=4,state=row.enabled and 2 or 1,estimated=false}
 end
 if cursor+128<#visible then out.next_cursor=cursor+128 end
 out.truncated=out.next_cursor~=0;return out
end
local function candidate_page(r,a,b,area_revision,available)
 local legacy=default(a,'operation',0)==0
 local links=default(a,'operation',0)==10
 local locations=default(a,'operation',0)==6
 local candidate_kind=(links or locations) and 0 or legacy and 1 or a.candidate_kind
 local site=locations and dfhack.world.getCurrentSite() or nil
 if locations and not site then return fail('Location site no longer exists'),0 end
 local query=default(a,'query',''):lower()
 if not legacy and not links and not locations and candidate_kind==1 then
  if type(r.owner_query)~='function' then return fail('Native area helper unavailable'),0 end
  local worked,value=pcall(r.owner_query,a.query_bytes~=nil and a.query_bytes or default(a,'query',''))
  if not worked or type(value)~='string' then return fail('Native area helper unavailable'),0 end
  query=value
 end
 local key=table.concat({locations and 6 or links and 10 or legacy and 0 or 14,a.kind,default(a,'id',-1),candidate_kind,
  default(a,'sort',0),default(a,'sort_descending',false) and 1 or 0,area_revision or 0,site and site.id or -1,#query,query},':')
 local job=area_lists[key];local expected=default(a,'expected_list_revision',0)
 -- Reopening a chooser must observe current metadata even while DF is paused.
 -- Keep the completed snapshot for continuation pages; only a new first-page
 -- interaction retires an already delivered owner/location snapshot.
 if (locations or (not legacy and (candidate_kind==1 or candidate_kind==2))) and job and job.complete and job.delivered and expected==0 and default(a,'cursor',0)==0 then area_lists[key]=nil;job=nil end
 if job and job.complete then
  -- An open owner picker keeps its frozen membership/order while reading fresh
  -- facts. Successful reads renew that lease; abandoned lists still expire.
  local observed=job.native_owner and job.read_tick or job.built_tick
  observed=observed or job.built_tick
  if tick()<observed or tick()-observed>candidate_max_age then area_lists[key]=nil;job=nil end
 end
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
   job.native_owner=not legacy and candidate_kind==1
   job.zone_type=b.type
   if candidate_kind==2 then
    local entries=type(r.animal_candidates)=='function' and r.animal_candidates(b) or nil
    if type(entries)~='table' or #entries>4096 then return fail('Native area helper unavailable'),0 end
    for _,entry in ipairs(entries)do
     if type(entry)~='table' or not integer(entry.id) or entry.id<0 or entry.id>2147483647 or
      (entry.entity~=1 and entry.entity~=2) or type(entry.assigned)~='boolean' then
      return fail('Native area helper unavailable'),0
     end
    end
    job.native_animals=true;job.animal_candidates=entries
   elseif candidate_kind==3 then job.assign_total=#b.squad_room_info end
  end
  if job.assign_total>4096 then return fail('Zone exceeds 4,096 assigned units'),0 end
  if links then
   job.link_counts={};job.source_total=0
   for group,source in ipairs(link_sources) do
    local count=#b.links[source.key]
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
  sort=job.sort,sort_descending=job.descending,query=default(a,'query',''),query_bytes=a.query_bytes,captured_tick=job.built_tick or -1,
  build_phase=job.phase,build_done=job.done,build_total=job.total,next_cursor=0}
 if not job.complete then return out,0 end
 if expected~=0 and expected~=job.revision then return fail('List changed; refresh'),0 end
 out.message=locations and 'Observed area locations' or links and 'Observed area links' or 'Observed area candidates';out.list_revision=job.revision
 local rows={};local cursor=default(a,'cursor',0);local used=0;local page_bytes=1024
 local limit=default(a,'candidate_limit',0);if limit==0 then limit=128 end
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
  if not legacy and (#rows==limit or used==available) then out.next_cursor=index-1;break end
  if job.native_owner then
   -- The open native picker retains ordering/filter membership but renders live
   -- unit facts. Cache IDs/order keys, not per-unit portrait recipe snapshots.
   local unit=df.unit.find(row.id)
   if not unit then return fail('List changed; refresh'),used end
   row=candidate_row(job,unit,r,true)
   if not row then return fail(job.error or 'List changed; refresh'),used end
   if not candidate_text_valid(row) then return fail('Candidate label exceeds 512 bytes'),used end
  end
  if not legacy or row.id>=cursor then
   local row_bytes=9+#row.name+#(row.profession or '')
   if row.owner_display then local d=row.owner_display;row_bytes=row_bytes+13+#d.first_line+#d.second_line+#d.status end
   -- Encoded recipes include their alignment/table overhead and exceed the
   -- semantic payload charge. Keep room for the surrounding response too.
   row_bytes=row_bytes+#(row.sheet_icon or '')+64
   if #rows==128 or used==available or (#rows>0 and page_bytes+row_bytes>220*1024)then out.next_cursor=legacy and row.id or index-1;break end
   if page_bytes+row_bytes>220*1024 then return fail('Candidate page exceeds bounded payload'),used end
   page_bytes=page_bytes+row_bytes
   rows[#rows+1]=row;used=used+1
  end
 end
 out[locations and 'locations' or links and 'links' or legacy and 'choices' or 'candidates']=rows;out.truncated=out.next_cursor~=0
 if locations or job.native_owner or job.native_animals then job.delivered=true end
 if job.native_owner then job.read_tick=tick() end
 return out,used
end

-- Requests hold observations only for this call. No native object or callback
-- is retained in a builder/cache; mutations reserve their reply snapshot first.
local function native_operation(r)
 sync_epoch(r.epoch)
 local a=r.area or {};local op=default(a,'operation',0);local steps=0
 local synchronous=r.synchronous_read==true and r.action==9 and (op==0 or op==1 or op==26) or
  r.synchronous_write==true and (r.action==13 and (op==0 or op==15) or r.action==11 and (op==0 or op==2 or op==3 or op==5 or op==7 or op==8 or op==9 or op==11) or r.action==12 and op==0 or r.action==10 and (op==0 or op==5))
 local budget=synchronous and math.huge or default(r,'step_budget',0)
 local unknown_work=false
 local function finish(result)
  result.steps=steps;result.active_kinds=active_kinds();result.operation=integer(op) and op>=0 and (op<=15 or op==26) and op or 0
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
  if not result.ok then return nil,result.message or 'Native area operation rejected',result.work_unknown==true end
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
  local out={id=b.id,kind=k,name=k==1 and snapshot.zone_name or name(b),custom_name=dfhack.df2utf(b.name),revision=snapshot.revision,
   x=snapshot.x,y=snapshot.y,z=snapshot.z,width=snapshot.width,height=snapshot.height,extents=snapshot.extents,
   tile_count=snapshot.tile_count,overlapping=snapshot.overlapping or -1,storage_limit=snapshot.storage_limit or -1,zone_type=-1,categories=0,barrels=0,bins=0,wheelbarrows=0,
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
   out.owner_id=b.assigned_unit_id;out.assigned_count=#(snapshot.assigned_units or {})+#(snapshot.assigned_items or {})
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
    settings.gather_fallen=b.zone_settings.gather.flags.gather_fallen and 1 or 0
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
  if a.kind~=0 then return reject('Unsupported area operation') end
  local page,used=candidate_page(r,a,nil,0,budget-steps);steps=steps+used;return finish(page)
 end
 if r.action==10 then
  local zone_type=default(a,'zone_type',-1)
  if not integer(zone_type) or zone_type< -1 or zone_type>255 then return reject('invalid area edit') end
  if a.kind==1 and not zone_types[df.civzone_type[zone_type]] then return reject('Unsupported zone type') end
  local new_owner
  if a.kind==0 then
   if default(a,'active',-1)~=-1 or default(a,'owner_id',-2)~=-2 then return reject('Zone-only fields on stockpile') end
   if op==0 then
    local tiles=default(a,'width',1)*default(a,'height',1)
    for _,key in ipairs{'barrels','bins','wheelbarrows'} do
     if default(a,key,-1)>tiles then
      return reject('Container limits exceed usable stockpile tiles')
     end
    end
   end
  else
   if default(a,'changed_categories',0)~=0 or default(a,'barrels',-1)~=-1 or default(a,'bins',-1)~=-1 or
    default(a,'wheelbarrows',-1)~=-1 or default(a,'links_only',-1)~=-1 then return reject('Stockpile-only fields on zone') end
   local owner=default(a,'owner_id',-2)
   if owner~=-2 then
    if not owner_types[df.civzone_type[zone_type]] then return reject('This zone type has no single owner') end
    new_owner=owner>=0 and df.unit.find(owner) or nil
    if owner>=0 then
     if not new_owner then return reject('Native owner assignment failed') end
     if type(r.new_owner_eligible)~='function' then return reject('Native area helper unavailable') end
     local worked,eligible=pcall(r.new_owner_eligible,zone_type,new_owner)
     if not worked or eligible==nil then return reject('Native area helper unavailable') end
     if not eligible then return reject('Native owner assignment failed') end
    end
   end
  end
  local created,problem=invoke(r.create_area,0,a)
  clear_lists()
  if not created then return reject(problem) end
  if a.kind==0 and created.paint_noop==true and created.building_id==-1 then
   return finish{ok=true,message='',areas={},building_id=-1}
  end
  local b=df.building.find(created.building_id)
  if not b or kind(b)~=a.kind then return reject('Created area could not be observed; inspect before retrying') end
  -- The native helper has transferred ownership to DF. Initialization is one
  -- protected Lua call; a normal refusal removes only this newly created area.
  unknown_work=true
  local initialized,why=pcall(function()
   if a.kind==0 then
    local barrels,bins,wheelbarrows,links=b.storage.max_barrels,b.storage.max_bins,b.storage.max_wheelbarrows,b.stockpile_flag.use_links_only
    b.storage.max_barrels=default(a,'barrels',-1)>=0 and a.barrels or barrels
    b.storage.max_bins=default(a,'bins',-1)>=0 and a.bins or bins
    b.storage.max_wheelbarrows=default(a,'wheelbarrows',-1)>=0 and a.wheelbarrows or wheelbarrows
    b.stockpile_flag.use_links_only=default(a,'links_only',-1)>=0 and a.links_only==1 or default(a,'links_only',-1)<0 and links
    for i,cat in ipairs(cats) do if (default(a,'changed_categories',0) & (1 << (i-1)))~=0 then
     b.settings.flags[cat]=(default(a,'categories',0) & (1 << (i-1)))~=0
    end end
   else
    -- Creation obtains settings from DF's initializer before publication.
    -- Preserve them here; only apply explicit request fields.
    b.spec_sub_flag.active=default(a,'active',-1)~=0
    -- Native creation already established room membership.
   end
  end)
  if not initialized then
   local removed=invoke(r.remove_area,0,b)
   if removed then
    local prefix='Invalid new area settings; new area removed: '
    return reject(prefix..tostring(why))
   end
   return reject('New area initialization failed; cleanup uncertain; inspect before retrying')
  end
  if new_owner then
   -- Native assignment can transfer another tomb. Never remove this zone as
   -- rollback after entering that routine; retain the unknown outcome.
   local assigned,problem=invoke(r.set_owner,0,b,new_owner)
   if not assigned then return reject(problem) end
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
 if op==26 then
  local found,problem=invoke(r.link_target,0,b)
  if not found then return reject(problem) end
  local rows={}
  if found.building_id>=0 then
   local target=df.building.find(found.building_id)
   if not target then return reject('Area no longer exists') end
   rows[1]={id=target.id,kind=kind(target)==0 and 0 or 2,direction=default(a,'give',true) and 1 or 2,name=name(target)}
  end
  return finish{ok=true,message='',links=rows}
 end
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
  -- Native routines prepare owned settings before atomically publishing them.
  -- Their synchronous work is separate from the paginated read budget.
  local changed,problem,unknown=invoke(r.settings_preset,reply_reserve,b,a.preset)
  if changed or unknown then clear_lists() end
  if not changed then return reject(problem) end
  local after,why=observe(b,false)
  if not after then return reject(why..'; native edit may have completed; inspect before retrying') end
  return finish{ok=true,message='Native stockpile preset applied',areas={info(b,after)},building_id=b.id}
 end
 if op==2 and (a.scope==3 or a.scope==4) then
  if expected==0 then return reject('Area revision required; inspect again') end
  local category=0
  if a.scope==3 then
   local key=default(a,'list_key','')
   if not edit_lists[key] and not setting_pages[key] then return reject('Unknown stockpile settings list or row') end
   local name=key:match('^([^/]+)')
   for bit,cat in ipairs(cats)do if cat==name then category=1 << (bit-1);break end end
   if category==0 then return reject('Unknown stockpile settings list or row') end
  end
  local changed,problem,unknown=invoke(r.settings_header,reply_reserve,b,category,a.value==2)
  if changed or unknown then clear_lists() end
  if not changed then return reject(problem) end
  local after,why=observe(b,false)
  if not after then return reject(why..'; native edit may have completed; inspect before retrying') end
  return finish{ok=true,message='',areas={info(b,after)},building_id=b.id}
 end
 if op==1 or op==2 then
  -- Count raw index spaces, not the current (possibly empty) settings vectors.
  -- The native inventory contains copied sizes only; shared display partitions
  -- contribute once per backing vector and no native reference is cached.
  local layout,problem=invoke(r.settings_layout,0,b)
  if not layout then return reject(problem) end
  local mode=native_setting_modes[default(a,'list_key','')]
  if default(a,'category_opening',false) then mode=native_parent_modes[a.list_key] end
  local native_rows
  local native_leaf_edit=mode and setting_leaves[a.list_key].source~='quality' and (a.scope==1 or a.scope==2)
  if mode and (op==1 or native_leaf_edit or a.scope==2 and default(a,'query','')~='') then
   local result,why=invoke(r.settings_rows,0,b,mode,default(a,'query',''))
   if not result then return reject(why) end
   if type(result.rows)~='table' then return reject('') end
   native_rows=result.rows
  end
  if op==1 then
   if native_rows then return finish(native_settings_page(r,a,b,before.revision,layout,native_rows)) end
   local selected=0;local key=default(a,'list_key','')
   if not setting_pages[key] then return reject('Unknown stockpile settings list') end
   for i,cat in ipairs(cats)do if key==cat then selected=1 << (i-1);break end end
   local summary,why=invoke(r.settings_summary,0,b,selected)
   if not summary then return reject(why) end
   local page,used=summary_page(r,a,b,before.revision,layout,budget-steps,summary)
   steps=steps+used;return finish(page)
  end
  if op==2 then
   if expected==0 then return reject('Area revision required; inspect again') end
   local plan,problem,used=settings_edit_plan(a,layout,budget-steps,native_rows)
   steps=steps+used
   if not plan then return reject(problem) end
   -- Build all selection masks and reserve every field and the reply before
   -- the first native write. Vector masks use fresh native row membership,
   -- never a partially paged result or locally reconstructed raw rules.
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
  local is_item=default(a,'item_id',-1)>=0
  local target,callback
  if is_item then target=df.item.find(a.item_id);callback=r.assign_item
  else target=df.unit.find(a.unit_id);callback=r.assign_unit end
  if not target then return reject(is_item and 'Item no longer exists' or 'Unit no longer exists') end
  local changed,problem,unknown=invoke(callback,reply_reserve,b,target,a.assign)
  if changed or unknown then clear_lists() end
  if not changed then return reject(problem) end
  local after,why=observe(b,false)
  if not after then return reject(why..'; native edit may have completed; inspect before retrying') end
  return finish{ok=true,message='',areas={info(b,after)},building_id=b.id,retired=changed.retired}
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
   local maximum=before.storage_limit or -1
   if value>maximum then return reject('Container limits exceed usable stockpile tiles') end
  end
  local links_only=default(a,'links_only',-1)
  if not integer(links_only) or links_only< -1 or links_only>1 then return reject('invalid area edit') end
  if default(a,'active',-1)~=-1 or default(a,'owner_id',-2)~=-2 then return reject('Zone-only fields on stockpile') end
  if budget-steps<(default(a,'changed_categories',0)~=0 and 200 or 175) then return reject('Area request exceeds remaining step budget') end
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
   if owner>=0 then
    if not new_owner then return reject('Native owner assignment failed') end
    if type(r.owner_eligible)~='function' then return reject('Native area helper unavailable') end
    local worked,eligible=pcall(r.owner_eligible,b,new_owner)
    if not worked or eligible==nil then return reject('Native area helper unavailable') end
    if not eligible then return reject('Native owner assignment failed') end
   end

  end
 end
 if op==9 then
  local zone_type=df.civzone_type[b.type]
  for _,entry in ipairs{{'pond_mode','Pond',0},{'facing','ArcheryRange',0},
   {'tomb_citizens','Tomb',-1},{'tomb_pets','Tomb',-1},
   {'gather_trees','PlantGathering',-1},{'gather_shrubs','PlantGathering',-1},{'gather_fallen','PlantGathering',-1}} do
   if default(a.zone_settings,entry[1],entry[3])~=entry[3] and zone_type~=entry[2] then
    return reject('Setting '..entry[1]..' does not apply to this zone type')
   end
  end
 end
 local retired,retired_bytes
 if legacy_pile_update then
  -- Selecting a disabled category initializes and clears its native filters.
  -- Prepare all category changes before publishing settings or container edits.
  if default(a,'changed_categories',0)~=0 then
   local changed,problem,unknown=invoke(r.settings_categories,reply_reserve+4,b,a.changed_categories,default(a,'categories',0))
   if changed or unknown then clear_lists() end
   if not changed then return reject(problem) end
  end
  clear_lists();steps=steps+4
  if default(a,'barrels',-1)>=0 then b.storage.max_barrels=a.barrels end
  if default(a,'bins',-1)>=0 then b.storage.max_bins=a.bins end
  if default(a,'wheelbarrows',-1)>=0 then b.storage.max_wheelbarrows=a.wheelbarrows end
  if default(a,'links_only',-1)>=0 then b.stockpile_flag.use_links_only=a.links_only==1 end
 elseif legacy_zone_update then
  clear_lists();steps=steps+1
  if default(a,'owner_id',-2)~=-2 then
   local assigned,problem=invoke(r.set_owner,reply_reserve,b,new_owner)
   if not assigned then return reject(problem) end
  end
  if default(a,'active',-1)>=0 then
   b.spec_sub_flag.active=a.active==1
   unknown_work=true
   local notified=pcall(B.notifyCivzoneModified,b)
   if not notified then return reject('Native zone notification failed; inspect before retrying') end
  end
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
  if default(z,'gather_fallen',-1)~=-1 then native.gather.flags.gather_fallen=z.gather_fallen==1 end
  -- Native gathering handlers only change these bits (34b81e..34b926);
  -- rebuilding room membership is unrelated to a gathering toggle.
  if df.civzone_type[b.type]~='PlantGathering' then
   unknown_work=true
   local notified=pcall(B.notifyCivzoneModified,b)
   if not notified then return reject('Native zone notification failed; inspect before retrying') end
  end
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
