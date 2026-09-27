-- Fixed work-order domain. DF alone authorizes orders and schedules their jobs.
-- HANDOFF to 01-U:
-- Item-condition panels must echo item_subtype, mat_type and mat_index on edits;
-- omitted subtype/material fields reset to -1. Traits are replaced when supplied.
-- A successful move reply no longer echoes the order; refresh the list/inspection.
-- Stated departures: native DF has no manager-order cap. DF3D refuses all
-- requests above 4,096 orders (including delete), and creation at capacity.
-- Delete refuses above 4,096 total dependencies before mutation. These bounded
-- work limits are unlikely in practice; native DF does not impose them.
local ORDER_CAP=4096
local DELETE_DEPENDENCY_CAP=4096
-- Atomic work outside the shared step budget is bounded by ORDER_CAP: index
-- rebuild/receipt cleanup and move list hashing. Delete checks at most ORDER_CAP
-- vector lengths, then sweeps at most DELETE_DEPENDENCY_CAP dependencies twice.
local U,J,B=dfhack.units,dfhack.job,dfhack.buildings
local receipts={};local receipt_counter=0
local request_jobs
local request_order_indices
local list_scan
local estimate_queue,estimates={},{}
local builds,build_queue={},{}
local builder_serial=0
local function ticket()builder_serial=builder_serial+1;return builder_serial end
local function free_filter(e)
 if e.filter then e.filter:delete();e.filter=nil end
end
local function invalidate_estimates()
 for _,e in ipairs(estimate_queue)do free_filter(e)end
 estimate_queue={};estimates={}
end
-- Request scans yield at each read/hash operation; the driver charges these
-- against the same update allowance as background builders.
local request_scanning=false
local function request_step()if request_scanning then coroutine.yield()end end
local function sort_ids(rows)
 local width,n=1,#rows
 while width<n do
  local dest={}
  for base=1,n,width*2 do
   local i,j=base,base+width;local left,right=math.min(base+width,n+1),math.min(base+width*2,n+1)
   while i<left or j<right do
    if i<left and (j>=right or rows[i]<=rows[j])then dest[#dest+1]=rows[i];i=i+1
    else dest[#dest+1]=rows[j];j=j+1 end
    request_step()
   end
  end
  rows=dest;width=width*2
 end
 return rows
end
local function hash_values(values)
 local h=0xcbf29ce484222325
 for _,value in ipairs(values)do
  request_step()
  for shift=0,56,8 do h=(h ~ ((value >> shift) & 255))*0x100000001b3 end
 end
 h=h & 0x7fffffffffffffff;return h==0 and 1 or h
end
local function list_revision()
 local values={#df.global.world.manager_orders.all}
 for _,o in ipairs(df.global.world.manager_orders.all)do values[#values+1]=o.id;request_step()end
 return hash_values(values)
end
local function traits(c)
 local out={}
 for word=1,5 do
  local flags=word<=3 and c['flags'..word].whole or c['flags'..word]
  flags=math.tointeger(flags)
  for bit=0,31 do if (flags & (1 << bit))~=0 then out[#out+1]='f'..word..':'..bit end end
 end
 for _,v in ipairs{{'rc:',c.reaction_class},{'rp:',c.has_material_reaction_product}}do
  if v[2]~='' then out[#out+1]=v[1]..v[2] end
 end
 for _,v in ipairs{{'ore:',c.metal_ore},{'tool:',c.has_tool_use},{'dye:',c.dye_color}}do
  if v[2]>=0 then out[#out+1]=v[1]..v[2] end
 end
 return out
end
local function parse_traits(keys)
 local out={flags1=0,flags2=0,flags3=0,flags4=0,flags5=0,reaction_class='',has_material_reaction_product='',metal_ore=-1,has_tool_use=-1,dye_color=-1}
 if #keys>256 then return nil end
 for _,key in ipairs(keys)do
  if type(key)~='string' or #key>64 then return nil end
  local word,bit=key:match('^f([1-5]):(%d+)$')
  if word then
   bit=tonumber(bit);if bit>31 then return nil end
   local field='flags'..word;out[field]=out[field] | (1 << bit)
  else
   local prefix,value=key:match('^(%a+):(.+)$')
   local field=({rc='reaction_class',rp='has_material_reaction_product',ore='metal_ore',tool='has_tool_use',dye='dye_color'})[prefix]
   if not field then return nil end
   if prefix=='rc' or prefix=='rp' then out[field]=value
   else
    if not value:match('^%d+$')then return nil end
    value=tonumber(value)
    if prefix=='ore' then
     if not df.global.world.raws.inorganics or not df.global.world.raws.inorganics.all[value]then return nil end
    elseif prefix=='tool' then
     if not df.tool_uses or not df.tool_uses[value]then return nil end
    elseif not df.global.world.raws.descriptors or not df.global.world.raws.descriptors.colors[value]then return nil end
    out[field]=value
   end
  end
 end
 return out
end
local function apply_traits(c,values)
 for field,value in pairs(values)do
  local word=tonumber(field:match('^flags(%d)$'))
  if word and word<=3 then c[field].whole=value else c[field]=value end
 end
end
local detail_families={CustomReaction=1,SmeltOre=1,MeltMetalObject=1,TanAHide=1,
 ConstructBag=2,ConstructDoor=2,ConstructTable=2,ConstructBed=2,
 ProcessPlants=3,MillPlants=3,MakeArmor=4,MakeHelm=4,MakeGloves=4,MakeShoes=4,MakePants=4,
 EncrustWithGems=5,EncrustWithGlass=5,EncrustWithStones=5}
local function detail_kind(o)
 local name=df.job_type[o.job_type]
 -- The generated enum is bidirectional; test doubles may expose only its named values.
 if not name then for key,value in pairs(df.job_type)do if value==o.job_type then name=key;break end end end
 local kind=detail_families[name] or 0
 if kind==4 and (o.material_category.cloth or o.material_category.silk or o.material_category.yarn)then return 6 end
 return kind
end
local function absolute_tick()return (df.global.cur_year or 0)*403200+(df.global.cur_year_tick or 0)end
local function estimate_key(id,index)return id..':'..index end
local function queue_estimate(o,index,rev)
 local key=estimate_key(o.id,index);local old=estimates[key];local tick=absolute_tick()
 if old and old.revision==rev and tick>=old.tick and tick-old.tick<=1200 then return old end
 if old then old.cancelled=true;free_filter(old)end
 if #estimate_queue>=64 then local dropped=table.remove(estimate_queue,1);estimates[dropped.key]=nil;dropped.cancelled=true;free_filter(dropped)end
 local entry={ticket=ticket(),key=key,id=o.id,index=index,revision=rev,tick=tick,cursor=0,count=0,done=false}
 estimates[key]=entry;estimate_queue[#estimate_queue+1]=entry;return entry
end
local function fail(message)return {ok=false,message=message}end
local function utf(s)return dfhack.df2utf(s or '')end
local function all()return df.global.world.manager_orders.all end
local function find(id)
 if not request_order_indices then
  request_order_indices={};for i,o in ipairs(all())do request_order_indices[o.id]=i;request_step() end
  for cached in pairs(receipts)do if request_order_indices[cached]==nil then receipts[cached]=nil end end
 end
 local index=request_order_indices[id]
 return index~=nil and index<#all() and all()[index].id==id and all()[index] or nil
end
local function visible(b)
 local d=dfhack.maps.getTileFlags{x=b.centerx,y=b.centery,z=b.z};return d and not d.hidden
end
local function family(b)
 if df.building_workshopst:is_instance(b)then
  if b.type==df.workshop_type.Custom then return 'custom:'..b.custom_type end
  if b.type==df.workshop_type.MagmaForge then return 'MetalsmithsForge'end
  return df.workshop_type[b.type]
 end
 if df.building_furnacest:is_instance(b)then
  local name=df.furnace_type[b.type];return ({MagmaSmelter='Smelter',MagmaGlassFurnace='GlassFurnace',MagmaKiln='Kiln'})[name] or name
 end
end
-- Group identity is simulation data; magma variants share their ordinary workshop.
local group_defs={
 {'Ashery',"Ashery"},{'Bowyers',"Bowyer's Workshop"},{'Butchers',"Butcher's Shop"},
 {'Carpenters',"Carpenter's Workshop"},{'Clothiers',"Clothier's Shop"},{'Craftsdwarfs',"Craftsdwarf's Workshop"},
 {'Dyers',"Dyer's Shop"},{'Farmers',"Farmer's Workshop"},{'Fishery',"Fishery"},
 {'GlassFurnace','Glass Furnace',true},{'Jewelers',"Jeweler's Workshop"},{'Kiln','Kiln',true},
 {'Kitchen','Kitchen'},{'Leatherworks','Leather Works'},{'Loom','Loom'},
 {'Mechanics',"Mechanic's Workshop"},{'MetalsmithsForge',"Metalsmith's Forge"},
 {'Millstone','Millstone'},{'Quern','Quern'},{'Siege','Siege Workshop'},
 {'Smelter','Smelter',true},{'Still','Still'},{'Masons',"Stoneworker's Workshop"},
 {'Tanners',"Tanner's Shop"},{'Kennels',"Vermin Catcher's Shop"},{'WoodFurnace','Wood Furnace',true}}
local categories={plant=1,wood=2,cloth=4,silk=8,leather=16,bone=32,shell=64,wood2=128,
 soap=256,tooth=512,horn=1024,pearl=2048,yarn=4096,strand=8192}
local task_equipment={
  {'MakeWeapon','WEAPON','weapon','weapons'},{'MakeArmor','ARMOR','armor','armor'},
  {'MakeHelm','HELM','helm','helms'},{'MakeGloves','GLOVES','gloves','gloves'},
  {'MakeShoes','SHOES','shoes','shoes'},{'MakePants','PANTS','pants','pants'},
  {'MakeShield','SHIELD','shield','shields'},{'MakeAmmo','AMMO','ammo','ammo'},
  {'MakeTrapComponent','TRAPCOMP','trapcomp','trapcomps'},
  {'AssembleSiegeAmmo','SIEGEAMMO','siegeammo','siege_ammo'},
  {'MakeTool','TOOL','tool','tools'}}
local function task_fields(o,row)
 o:assign{job_type=row.job_type,item_type=row.item_type,item_subtype=row.item_subtype,
  mat_type=row.mat_type,mat_index=row.mat_index,reaction_name=row.reaction}
 o.material_category.whole=row.material_category;o.specflag.encrust_flags.whole=row.encrust_flags
end
-- Length-prefixed, reversible epoch-local identities. Base 36 keeps native
-- reaction codes within the wire key budget; -1 is the empty identity.
-- The complete ungrouped key is capped at 64 bytes, including decimal length
-- prefixes and numeric fields. Reaction codes therefore have a tuple-dependent
-- bound below the separate 64-byte reaction field cap (vanilla maximum: 28).
-- Precisely: code bytes + decimal digits(code bytes) + 1 must fit the bytes
-- remaining after the other seven length-prefixed fields.
local function key_number(n)
 if n==-1 then return ''end
 local digits='0123456789abcdefghijklmnopqrstuvwxyz';local out=''
 repeat local digit=n%36;out=digits:sub(digit+1,digit+1)..out;n=n//36 until n==0
 return out
end
local function task_key(row,ungrouped)
 local parts={}
 local group=key_number(row.group_type)..'/'..key_number(row.group_subtype)..'/'..key_number(row.group_custom)
 if ungrouped then group=''end
 local material=key_number(row.mat_type)..'/'..key_number(row.mat_index)
 for _,s in ipairs{group,key_number(row.job_type),row.reaction,key_number(row.item_type),
  key_number(row.item_subtype),material,key_number(row.material_category),key_number(row.encrust_flags)}do
  parts[#parts+1]=#s..':'..s
 end
 return table.concat(parts)
end
local function catalog()
 local job=builds[27]
 if job and job.error then return nil,job.error end
 if not job or job.phase~=0 then return nil,'Task catalog is building; refresh' end
 return job.rows
end
-- Each attempted material/itemdef combination yields, even if rejected. No UI templates.
local function generate_tasks(job,add,step)
 local raws=df.global.world.raws
 local entity=df.historical_entity.find(df.global.plotinfo.civ_id)
 local er=entity and entity.entity_raw
 local groups,by_family={},{}
 job.groups={{type=-1,subtype=-1,custom=-1,name='All tasks',count=0}}
 local function group(type_,sub,custom,name,family)
  if type_==nil or sub==nil then return end
  local g={type=type_,subtype=sub,custom=custom,name=utf(name),count=0,family=family}
  if #g.name>128 then error('list row exceeds string cap',0)end
  if #groups>=127 then error('list exceeds cap',0)end
  groups[#groups+1]=g;by_family[family]=g
 end
 for _,d in ipairs(group_defs)do
  group(d[3] and df.building_type.Furnace or df.building_type.Workshop,
   (d[3] and df.furnace_type or df.workshop_type)[d[1]],-1,d[2],d[1]);step()
 end
 local permitted={}
 if er then for _,id in ipairs(er.workshops.permitted_building_id or {})do permitted[id]=true;job.done=math.min(job.total,job.done+1);step()end end
 for _,d in ipairs(raws.buildings and raws.buildings.all or {})do
  if permitted[d.id] then group(d.building_type,d.building_subtype,d.id,d.name,'custom:'..d.id)end;job.done=math.min(job.total,job.done+1);step()
 end
 -- This is at most 127 group rows; keep native alphabetical group order.
 for i=2,#groups do
  local row=groups[i];local j=i-1
  while j>=1 and groups[j].name>row.name do groups[j+1]=groups[j];j=j-1;step()end
  groups[j+1]=row;step()
 end
 for _,g in ipairs(groups)do job.groups[#job.groups+1]=g end
 local seen={};job.by_key={};job.by_identity=seen
 local function emit(family,jt,sub,mt,mi,cat,flags,reaction,fallback)
  local g=type(family)=='table' and family or by_family[family]
  if type(jt)=='string' then jt=df.job_type[jt]end
  if g and jt then
   local row={group_type=g.type,group_subtype=g.subtype,group_custom=g.custom,family=g.family,
    job_type=jt,reaction=reaction or '',item_type=-1,item_subtype=sub or -1,
    mat_type=mt or -1,mat_index=mi or -1,material_category=cat or 0,encrust_flags=flags or 0}
   local identity=task_key(row,true)
   local previous=seen[identity]
   if previous then
    if previous.families[g.family]then error('Duplicate task key',0)end
    -- One native task can be offered by multiple workshops (e.g. milling).
    previous.families[g.family]=true;g.count=g.count+1;step();return
   end
   row.key=identity;row.families={[g.family]=true}
   seen[identity]=row
   -- Use DFHack's native semantic name formatter, not workshop captions.
   local o=df.manager_order:new();task_fields(o,row)
   local ok,name=pcall(J.getManagerOrderName,o);o:delete()
   if not ok then error(name,0)end
   row.name=utf(name or fallback or '')
   if #row.reaction>64 then error('list row exceeds string cap',0)end
   add(row);job.by_key[row.key]=row;g.count=g.count+1
   job.groups[1].count=job.groups[1].count+1
  end
  step()
 end
 local function many(family,names,mt,mi,cat)
  for name in names:gmatch('%S+')do emit(family,name,nil,mt,mi,cat)end
 end
 -- Generic furniture families use job enums; raw materials determine metal variants.
 local furniture='ConstructArmorStand ConstructBlocks ConstructThrone ConstructCoffin ConstructDoor ConstructFloodgate ConstructHatchCover ConstructGrate ConstructCabinet ConstructChest ConstructStatue ConstructTable ConstructWeaponRack'
 local wooden='MakeBarrel MakeBucket MakeAnimalTrap MakeCage ConstructBin ConstructSplint ConstructCrutch MakePipeSection'
 local crafts='MakeCrafts MakeAmulet MakeBracelet MakeEarring'
 local hardcrafts='MakeFigurine MakeCrown MakeRing MakeScepter MakeGem MakeGoblet MakeToy'
 many('Carpenters',furniture:gsub('ConstructStatue','')..' '..wooden..' ConstructBed',nil,nil,categories.wood)
 many('Masons',furniture..' ConstructSlab ConstructQuern ConstructMillstone',0)
 many('Craftsdwarfs',crafts..' '..hardcrafts,0)
 many('Craftsdwarfs',crafts..' '..hardcrafts,nil,nil,categories.wood)
 for _,cat in ipairs{'cloth','silk','leather','bone','shell','tooth','horn','pearl','yarn'}do
  many('Craftsdwarfs',crafts,nil,nil,categories[cat])
 end
 for _,cat in ipairs{'bone','shell','tooth','horn','pearl'}do
  -- DFHack plugins/lua/stockflow.lua:275-276,763-766 marks shell/pearl
  -- short and excludes scepters; this is a category list, not a raw token.
  many('Craftsdwarfs','MakeFigurine MakeCrown MakeRing MakeGem',nil,nil,categories[cat])
  if cat~='shell' and cat~='pearl' then emit('Craftsdwarfs','MakeScepter',nil,nil,nil,categories[cat])end
 end
 for _,cat in ipairs{'bone','shell','tooth','horn','pearl'}do emit('Craftsdwarfs','DecorateWith',nil,nil,nil,categories[cat])end
 many('Craftsdwarfs','MakeTotem')
 many('Mechanics','ConstructMechanisms',0)
 many('Mechanics','ConstructTractionBench')
 -- stockflow.lua:772-773 supplies wood for catapult/ballista parts. Bolt
 -- thrower wood is an extrapolation; "Make ballista parts" is inferred
 -- pending live measurement of the semantic formatter.
 many('Siege','ConstructBallistaParts ConstructCatapultParts ConstructBoltThrowerParts',nil,nil,categories.wood)
 -- reaction_other.txt:320,391 BUILDING:FARMER adds bag/sheet reactions.
 many('Farmers','ProcessPlants ProcessPlantsVial ProcessPlantsBarrel MilkCreature MakeCheese ShearCreature SpinThread')
 -- plant_standard.txt:362 EXTRACT_STILL_VIAL routes extraction to Still;
 -- reaction_other.txt:267,284,301 BUILDING:STILL adds BREW x2 and MAKE_MEAD;
 -- df.building.xml WORKSHOP_STILL has workshop=Still.
 many('Still','ExtractFromPlants')
 many('Fishery','PrepareRawFish ExtractFromRawFish CatchLiveFish')
 many('Butchers','ButcherAnimal ExtractFromLandAnimal')
 many('Kennels','CatchLiveLandAnimal')
 many('Dyers','DyeThread DyeCloth DyeLeather MixDye')
 many('Ashery','MakeLye MakePotashFromAsh MakePotashFromLye')
 -- reaction_other.txt:86-87,402-403 gives QUERN/MILLSTONE to the two
 -- milling reactions. MillPlants is filed under Millstone only; Quern has
 -- those reactions only (native counts 3/2). Workshop attributes are in
 -- df.building.xml WORKSHOP_MILLSTONE / WORKSHOP_QUERN.
 many('Millstone','MillPlants')
 many('WoodFurnace','MakeCharcoal MakeAsh')
 many('Smelter','MeltMetalObject');many('Kiln','CollectClay')
 many('GlassFurnace','CollectSand')
 many('Jewelers','CutGems CutGlass PolishStones')
 for _,jt in ipairs{'EncrustWithGems','EncrustWithGlass','EncrustWithStones'}do
  for _,flag in ipairs{4,64,1024}do emit('Jewelers',jt,nil,nil,nil,nil,flag)end
 end
 for ingredients=2,4 do emit('Kitchen','PrepareMeal',nil,ingredients)end
 many('Loom','CollectWebs')
 for _,cat in ipairs{'cloth','silk','yarn'}do
  emit('Loom','WeaveCloth',nil,nil,nil,categories[cat])
  many('Clothiers','ConstructBag SewImage MakeChain',nil,nil,categories[cat])
 end
 many('Leatherworks','ConstructBag SewImage MakeFlask MakeBackpack MakeQuiver',nil,nil,categories.leather)
 for _,mat in ipairs{'GLASS_GREEN','GLASS_CLEAR','GLASS_CRYSTAL'}do
  local mt=df.builtin_mats and df.builtin_mats[mat]
  if mt then many('GlassFurnace',furniture..' MakeGoblet MakeToy MakeCage MakePipeSection MakeFlask MakeWindow MakeRawGlass',mt)end
 end
 local equipment=task_equipment
 -- Keep civ weapon and digger permissions distinct, even when both name a subtype.
 local weapon_permissions,digger_permissions={},{}
 local resources=entity and entity.resources
 for _,entry in ipairs{{weapon_permissions,'weapon'},{digger_permissions,'digger'}}do
  local ids=(resources and resources[entry[2]..'_type']) or (er and er.equipment and er.equipment[entry[2]..'_id']) or {}
  for _,sub in ipairs(ids)do entry[1][sub]=true;step()end
 end
 local function definitions(e,visit)
  local t=df.item_type[e[2]]
  if not t or not dfhack.items then return end
  local resources=entity and entity.resources
  local allowed=(resources and resources[e[3]..'_type']) or (er and er.equipment and er.equipment[e[3]..'_id'])
  if allowed then
   local used={}
   for _,sub in ipairs(allowed)do used[sub]=true;visit(sub,dfhack.items.getSubtypeDef(t,sub))end
   if e[3]=='weapon' then
    for _,source in ipairs{resources and resources.digger_type or (er and er.equipment.digger_id) or {},resources and resources.training_weapon_type or {}}do
     for _,sub in ipairs(source)do
      if not used[sub]then used[sub]=true;visit(sub,dfhack.items.getSubtypeDef(t,sub))else step()end
     end
    end
   end
  else
   for sub=0,dfhack.items.getSubtypeCount(t)-1 do visit(sub,dfhack.items.getSubtypeDef(t,sub))end
  end
 end
 local armor={armor=true,helm=true,gloves=true,shoes=true,pants=true}
 local function clothing(def,flag)return def.props.flags[flag]end
 for _,e in ipairs(equipment)do definitions(e,function(sub,def)
  if def then
   if armor[e[3]] then
    if clothing(def,'SOFT')then for _,cat in ipairs{'cloth','silk','yarn'}do emit('Clothiers',e[1],sub,nil,nil,categories[cat])end end
    if clothing(def,'LEATHER')then emit('Leatherworks',e[1],sub,nil,nil,categories.leather)end
    if clothing(def,'BARRED')then emit('Craftsdwarfs',e[1],sub,nil,nil,categories.bone)end
    if clothing(def,'SCALED')then emit('Craftsdwarfs',e[1],sub,nil,nil,categories.shell)end
   elseif e[3]=='weapon' then
    if def.flags.CAN_STONE then emit('Craftsdwarfs',e[1],sub,0)end
    if def.flags.TRAINING then emit('Carpenters',e[1],sub,nil,nil,categories.wood)
    elseif def.skill_ranged>=0 then
     emit('Bowyers',e[1],sub,nil,nil,categories.wood);emit('Bowyers',e[1],sub,nil,nil,categories.bone)
    end
   elseif e[3]=='shield' or e[3]=='siegeammo' then
    emit(e[3]=='siegeammo' and 'Siege' or 'Carpenters',e[1],sub,nil,nil,categories.wood)
    if e[3]=='shield' then emit('Leatherworks',e[1],sub,nil,nil,categories.leather)end
   elseif e[3]=='trapcomp' then
    if def.flags.WOOD then emit('Carpenters',e[1],sub,nil,nil,categories.wood)end
    if def.flags.METAL then for _,mat in ipairs{'GLASS_GREEN','GLASS_CLEAR','GLASS_CRYSTAL'}do
     local mt=df.builtin_mats and df.builtin_mats[mat];if mt then emit('GlassFurnace',e[1],sub,mt)end
    end end
   elseif e[3]=='ammo' then
    emit('Craftsdwarfs',e[1],sub,nil,nil,categories.wood);emit('Craftsdwarfs',e[1],sub,nil,nil,categories.bone)
   elseif e[3]=='tool' and not def.flags.NO_DEFAULT_JOB then
    if def.flags.WOOD_MAT or def.flags.HARD_MAT then emit((def.flags.FURNITURE or def.flags.WOOD_MAT) and 'Carpenters' or 'Craftsdwarfs',e[1],sub,nil,nil,categories.wood)end
    if def.flags.STONE_MAT or def.flags.HARD_MAT then emit(def.flags.FURNITURE and 'Masons' or 'Craftsdwarfs',e[1],sub,0)end
    if def.flags.GLASS_MAT or def.flags.HARD_MAT then
     for _,mat in ipairs{'GLASS_GREEN','GLASS_CLEAR','GLASS_CRYSTAL'}do local mt=df.builtin_mats and df.builtin_mats[mat];if mt then emit('GlassFurnace',e[1],sub,mt)end end
    end
   end
  end
  job.done=math.min(job.total,job.done+1);step()
 end)end
 for mi,raw in ipairs(raws.inorganics and raws.inorganics.all or {})do
  local flags=raw.material.flags
  if #raw.metal_ore.mat_index>0 then emit('Smelter','SmeltOre',nil,0,mi)end
  if #raw.thread_metal.mat_index>0 then emit('Craftsdwarfs','ExtractMetalStrands',nil,0,mi)end
  if flags.IS_METAL then
   -- IS_METAL alone allows studding, not the hard-goods families.
   emit('MetalsmithsForge','StudWith',nil,0,mi)
   if flags.ITEMS_HARD then
    many('MetalsmithsForge',furniture..' '..wooden..' '..crafts..' '..hardcrafts..' MakeChain MakeFlask MintCoins',0,mi)
    emit('Mechanics','ConstructMechanisms',nil,0,mi)
   end
   if flags.ITEMS_ANVIL then emit('MetalsmithsForge','ForgeAnvil',nil,0,mi)end
   if flags.ITEMS_WEAPON then emit('MetalsmithsForge','MakeBallistaArrowHead',nil,0,mi)end
   for _,e in ipairs(equipment)do definitions(e,function(sub,def)
    local accept=false
    if def then
     if armor[e[3]] then
      accept=(clothing(def,'METAL') and flags.ITEMS_ARMOR) or (clothing(def,'SOFT') and flags.ITEMS_SOFT)
     elseif e[3]=='weapon' then
      accept=not def.flags.TRAINING and ((weapon_permissions[sub] and ((def.skill_ranged>=0 and flags.ITEMS_WEAPON_RANGED)or (def.skill_ranged<0 and flags.ITEMS_WEAPON)))or (digger_permissions[sub] and flags.ITEMS_DIGGER))
     elseif e[3]=='ammo' then accept=flags.ITEMS_AMMO
     elseif e[3]=='shield' then accept=flags.ITEMS_ARMOR
     elseif e[3]=='trapcomp' then accept=def.flags.METAL and flags.ITEMS_WEAPON
     elseif e[3]=='siegeammo' then accept=flags.ITEMS_WEAPON
     elseif e[3]=='tool' then accept=not def.flags.NO_DEFAULT_JOB and ((def.flags.HARD_MAT and flags.ITEMS_HARD) or (def.flags.METAL_MAT and flags.ITEMS_METAL) or (def.flags.METAL_WEAPON_MAT and flags.ITEMS_WEAPON))end
    end
    if accept then emit(e[3]=='siegeammo' and 'Siege' or 'MetalsmithsForge',e[1],sub,0,mi)else step()end
   end)end
   if flags.ITEMS_SOFT then
    many('MetalsmithsForge','MakeBackpack MakeQuiver',0,mi)
    many('Siege','ConstructBallistaParts ConstructCatapultParts ConstructBoltThrowerParts',0,mi)
   end
  end
  job.done=math.min(job.total,job.done+1);step()
 end
 local allowed={}
 if er then for _,id in ipairs(er.workshops.permitted_reaction_id)do allowed[id]=true;job.done=math.min(job.total,job.done+1);step()end end
 for index,r in ipairs(raws.reactions.reactions)do
  if allowed[index] or (entity and r.source_enid==entity.id)then
   for i,t in ipairs(r.building.type)do
    for _,g in ipairs(groups)do
     if g.type==t and g.subtype==r.building.subtype[i] and g.custom==r.building.custom[i]then
      emit(g,'CustomReaction',nil,nil,nil,nil,nil,r.code,r.name)
     end
     step()
    end
   end
  end
  job.done=math.min(job.total,job.done+1);step()
 end
end
local function recipe_for(o)
 local job=builds[27]
 if not job or job.phase~=0 or job.error then return nil end
 return job.by_identity[task_key({group_type=-1,group_subtype=-1,group_custom=-1,
  job_type=o.job_type,reaction=o.reaction_name or '',item_type=o.item_type,item_subtype=o.item_subtype,
  mat_type=o.mat_type,mat_index=o.mat_index,material_category=o.material_category.whole,
  encrust_flags=o.specflag.encrust_flags.whole},true)]
end
local function jobs(o)
 if not request_jobs then
  request_jobs={};local link=df.global.world.jobs.list.next
  while link do local j=link.item;if j and j.order_id>=0 then
   request_jobs[j.order_id]=request_jobs[j.order_id] or {};local ids=request_jobs[j.order_id];ids[#ids+1]=j.id
  end;link=link.next end
  for _,ids in pairs(request_jobs)do table.sort(ids)end
 end
 return request_jobs[o.id] or {}
end
-- Collision-free content receipt within an epoch. Retain strings and IDs only.
local function revision(o)
 local parts={}
 local function add(v)local s=tostring(v);parts[#parts+1]=#s..':'..s end
 for _,key in ipairs{'id','job_type','item_type','item_subtype','reaction_name','mat_type','mat_index','amount_left','amount_total','frequency','finished_year','finished_year_tick','workshop_id','max_workshops'}do add(o[key])end
 add(o.status.whole);add(o.material_category.whole);add(o.specflag.whole);add(o.specdata.hist_figure_id)
 for _,key in ipairs{'type','id','subid'}do add(o.art_spec[key])end
 add(#o.item_conditions)
 for _,c in ipairs(o.item_conditions)do
  for _,key in ipairs{'compare_type','compare_val','item_type','item_subtype','mat_type','mat_index','flags4','flags5','reaction_class','has_material_reaction_product','metal_ore','min_dimension','reaction_id','has_tool_use','dye_color'}do add(c[key])end
  add(c.flags1.whole);add(c.flags2.whole);add(c.flags3.whole)
  add(#c.contains);for _,v in ipairs(c.contains)do add(v)end
 end
 add(#o.order_conditions)
 for _,c in ipairs(o.order_conditions)do add(c.order_id);add(c.condition);add(c.flags.whole)end
 add(o.items~=nil)
 if o.items then
  add(#o.items.elements)
  for _,f in ipairs(o.items.elements)do
   for _,key in ipairs{'item_type','item_subtype','mat_type','mat_index','quantity','vector_id','flags4','flags5','metal_ore','reaction_class','has_material_reaction_product','min_dimension','reagent_index','reaction_id','has_tool_use','dye_color','job_details_mat_type','job_details_mat_index'}do add(f[key])end
   add(f.flags1.whole);add(f.flags2.whole);add(f.flags3.whole);add(f.job_details_flags.whole);add(f.job_details_item_flags2.whole)
   add(#f.contains);for _,v in ipairs(f.contains)do add(v)end
  end
 end
 local text=table.concat(parts);local old=receipts[o.id]
 if old and old.content==text then return old.revision end
 receipt_counter=receipt_counter+1;receipts[o.id]={content=text,revision=receipt_counter};return receipt_counter
end
local function inspect(o)
 if #o.item_conditions+#o.order_conditions>64 then return nil,'Order exceeds 64-condition inspector'end
 if o.items and #o.items.elements>64 then return nil,'Order exceeds 64-input inspector'end
 local generated=jobs(o);if #generated>1024 then return nil,'Order exceeds 1024-job inspector'end
 local conditions={};local trait_total=0
 local rev=revision(o)
 for i,c in ipairs(o.item_conditions)do
  local condition_traits=traits(c)
  if #condition_traits>256 then return nil,'Condition exceeds trait cap'end
  trait_total=trait_total+#condition_traits
  if trait_total>2048 then return nil,'Order exceeds trait page cap'end
  for _,key in ipairs(condition_traits)do if #key>64 then return nil,'Condition trait exceeds string cap'end end
  local editable=c.compare_type>=0 and c.compare_type<=5
  conditions[#conditions+1]={kind=0,index=i,description=(df.item_type[c.item_type] or 'Any item')..' '..(df.logic_condition_type[c.compare_type] or '?')..' '..c.compare_val..(editable and '' or ' (custom filters preserved; read only)'),
   editable=editable,compare=c.compare_type,threshold=c.compare_val,item_type=c.item_type,target_order=-1,dependency=-1,
   item_subtype=c.item_subtype,mat_type=c.mat_type,mat_index=c.mat_index,traits=condition_traits,estimated=true,satisfaction=1,estimate_count=-1}
  local row=conditions[#conditions];local estimate=queue_estimate(o,i,rev)
  if estimate.done then
   row.satisfaction=2;row.estimate_count=estimate.count;row.satisfied=estimate.satisfied
   row.description=row.description..'; DF3D estimate: '..estimate.count..' matching (rule '..(estimate.satisfied and 'met' or 'not met')..')'
  end
 end
 for i,c in ipairs(o.order_conditions)do
  conditions[#conditions+1]={kind=1,index=i,description='Order #'..c.order_id..' '..(df.workquota_order_condition_type[c.condition] or '?')..'; '..(c.flags.satisfied and 'Satisfied for next check' or 'Not satisfied for next check'),
   editable=c.condition>=0 and c.condition<=1,compare=-1,threshold=-1,item_type=-1,target_order=c.order_id,dependency=c.condition,satisfied=c.flags.satisfied,satisfaction=2,estimated=false}
 end
 -- Catalogs and orders are separate replies. With 256-byte descriptions, the
 -- 16/128/2048/2048/128 aggregate order caps stay below the 512 KiB channel.
 for _,c in ipairs(conditions)do if #c.description>256 then return nil,'Condition description exceeds string cap'end end
 local order_name=utf(J.getManagerOrderName(o))
 if #order_name>512 then return nil,'Order name exceeds string cap'end
 local editable=#generated==0 and (o.amount_total==0 or o.amount_total==o.amount_left)
 local reason=#generated>0 and 'Finish outstanding jobs before editing' or (editable and 'Your manager approves new or changed orders' or 'This batch has started; settings are read only to preserve completed work')
 local kind=detail_kind(o);local inputs={}
 if o.items then for i,f in ipairs(o.items.elements)do
  inputs[#inputs+1]={index=i,description='',mat_type=f.job_details_mat_type,mat_index=f.job_details_mat_index,
   editable=editable and (kind==2 or kind==3 or kind==5 or kind==6)}
 end end
 local position=request_order_indices and request_order_indices[o.id]
 if position==nil then for i,v in ipairs(all())do if v.id==o.id then position=i;break end end end
 return {id=o.id,revision=rev,position=position,detail_kind=kind,inputs=inputs,
  size_raw=o.specdata.hist_figure_id,encrust_flags=o.specflag.encrust_flags and o.specflag.encrust_flags.whole or 0,
  mat_type=o.mat_type,mat_index=o.mat_index,material_category=o.material_category.whole,name=order_name,total=o.amount_total,remaining=o.amount_left,
  frequency=o.frequency,validated=o.status.validated,active=o.status.active,finished_year=o.finished_year,finished_tick=o.finished_year_tick,
  workshop_id=o.workshop_id,max_workshops=o.max_workshops,generated_jobs=generated,conditions=conditions,editable=editable,reason=reason}
end
local function managers()
 local out={}
 local offices_by_unit={}
 for _,b in ipairs(df.global.world.buildings.other.ACTIVITY_ZONE)do if b.type==df.civzone_type.Office and b.assigned_unit_id>=0 then
  local ids=offices_by_unit[b.assigned_unit_id] or {};ids[#ids+1]=b.id;offices_by_unit[b.assigned_unit_id]=ids
 end end
 for _,u in ipairs(df.global.world.units.active)do if U.isCitizen(u) and U.isActive(u) and not U.isDead(u)then
  for _,n in ipairs(U.getNoblePositions(u) or {})do
   if n.entity.id==df.global.plotinfo.group_id and n.position.responsibilities[df.entity_position_responsibility.MANAGE_PRODUCTION]then
    local offices=offices_by_unit[u.id] or {}
    if #offices>64 or #out>=32 then return nil,'Manager role inspector exceeds bounds'end
    out[#out+1]={unit_id=u.id,name=utf(U.getReadableName(u)),position=utf(n.position.name[0]),offices=offices,job=u.job.current_job and utf(J.getName(u.job.current_job)) or 'No current job'}
    break
   end
  end
 end end
 return out
end
local function reply(o,message)
 local v,err=inspect(o);if not v then return fail(err)end
 return {ok=true,message=message or 'Observed native work order',orders={v},active=#build_queue>0 or #estimate_queue>0}
end
local function workshop_valid(id,r)
 if id==-1 then return true end
 local b=df.building.find(id)
 return b and visible(b) and b:getBuildStage()==b:getMaxBuildStage() and r and r.families[family(b)]
end
local function cycles(from,to)
 local seen={};local stack={to};local count=0
 while #stack>0 do
  local id=table.remove(stack);if id==from then return true end
  if not seen[id]then
   seen[id]=true;count=count+1;if count>4096 then return true end
   local o=find(id);if o then for _,c in ipairs(o.order_conditions)do stack[#stack+1]=c.order_id end end
  end
 end
 return false
end
-- List jobs yield at each source read, emitted row, merge move and filter test.
-- Cached rows contain only scalar values, never DF objects.
local function source_vectors(kind)
 local raws=df.global.world.raws
 if kind==5 then return {raws.inorganics and raws.inorganics.all or {}}end
 return {raws.inorganics and raws.inorganics.all or {},raws.plants and raws.plants.all or {},
  raws.creatures and raws.creatures.all or {}}
end
local function list_total(kind)
 if kind==27 then
  local raws=df.global.world.raws
  local n=#(raws.inorganics and raws.inorganics.all or {})+#raws.reactions.reactions+#(raws.buildings and raws.buildings.all or {})
  for _,e in ipairs(task_equipment)do
   local t=df.item_type[e[2]];if t and dfhack.items then n=n+dfhack.items.getSubtypeCount(t)end
  end
  local entity=df.historical_entity.find(df.global.plotinfo.civ_id)
  if entity then local w=entity.entity_raw.workshops;n=n+#(w.permitted_building_id or {})+#w.permitted_reaction_id end
  return n
 end
 if kind==3 then return df.item_type._last_item+2 end
 local n=0;for _,v in ipairs(source_vectors(kind))do n=n+#v end
 local table_=df.global.world.raws.mat_table
 return n+(kind~=5 and table_ and #table_.builtin or 0)
end
-- DF 53.16 condition adjectives (native e_logs_trait_master evidence).
-- Re-capture this table from native on every DF version update.
-- These are selectable predicates, not every job flag or raw reaction tag.
local condition_adjectives={
 {'f1:28','Ammo items'},
 {'rp:BAG_ITEM','Bag-processable items'},
 {'f2:28','Blunt items'},
 {'f2:17','Bone items'},
 {'tool:21','Bookcase items'},
 {'f2:6','Building material items'},
 {'f1:1','Butcherable items'},
 {'rc:CALCIUM_CARBONATE','Calcite/limestone/chalk/marble items'},
 {'rp:FIRED_MAT','Clay items'},
 {'f1:6','Collected items'},
 {'f1:13','Cookable items'},
 {'f2:9','Deep material items'},
 {'tool:22','Display object items'},
 {'tool:24','Divination items'},
 {'f2:0','Dye items'},
 {'f2:1','Dyeable items'},
 {'f2:2','Dyed items'},
 {'f3:12','Edged items'},
 {'f1:10','Empty items'},
 {'f1:15','Extract-bearing fish items'},
 {'f1:14','Extract-bearing plant items'},
 {'f1:16','Extract-bearing small creature items'},
 {'rc:FAT','Fat items'},
 {'rp:SOAP_MAT','Fatty items'},
 {'rp:DRINK_MAT','Fermentable items'},
 {'f1:27','Finished good items'},
 {'f2:7','Fire-safe items'},
 {'rc:FLUX','Flux items'},
 {'tool:19','Folded sheet protector items'},
 {'tool:11','Food storage items'},
 {'f3:7','Food storage items'},
 {'f1:29','Furniture items'},
 {'tool:25','Games of chance items'},
 {'f1:24','Glass items'},
 {'f2:4','Glass-making items'},
 {'rc:CAN_GLAZE','Glazable items'},
 {'rp:GLAZE_MAT','Glaze items'},
 {'rc:GYPSUM','Gypsum items'},
 {'f2:30','Hair/wool items'},
 {'f3:6','Hard items'},
 {'tool:16','Heavy object hauler items'},
 {'tool:12','Hive items'},
 {'rp:HONEYCOMB_PRESS_MAT','Honey-bearing items'},
 {'f2:20','Horn items'},
 {'f1:0','Improvable items'},
 {'f2:26','Ivory/tooth items'},
 {'f2:16','Leather items'},
 {'tool:10','Liquid container items'},
 {'tool:0','Liquid cooking items'},
 {'tool:1','Liquid scoop items'},
 {'f1:31','Lye-bearing items'},
 {'f2:27','Lye/milk-free items'},
 {'f2:8','Magma-safe items'},
 {'tool:9','Meal container items'},
 {'tool:5','Meat boning items'},
 {'tool:4','Meat carving items'},
 {'tool:7','Meat cleaving items'},
 {'tool:6','Meat slicing items'},
 {'tool:8','Meat-carving holder items'},
 {'f2:10','Melt-designated items'},
 {'f3:8','Metal items'},
 {'f1:25','Milk items'},
 {'f1:26','Milkable items'},
 {'f1:2','Millable items'},
 {'f1:8','Murdered items'},
 {'f1:22','Nearby items'},
 {'tool:13','Nest box items'},
 {'f3:2','Non-absorbent items'},
 {'f2:11','Non-economic items'},
 {'f3:3','Non-pressed items'},
 {'tool:23','Offering placement items'},
 {'rp:PRESS_LIQUID_MAT','Oil-bearing items'},
 {'rc:PAPER_PLANT','Paper-making items'},
 {'rc:PAPER_SLURRY','Paper-slurry items'},
 {'rp:PRESS_PAPER_MAT','Paper-slurryable items'},
 {'rp:PARCHMENT_MAT','Parchment-producing items'},
 {'f2:21','Pearl items'},
 {'f2:14','Plant items'},
 {'f2:22','Plaster-containing items'},
 {'f1:3','Possibly buriable items'},
 {'tool:3','Powder grinding items'},
 {'tool:2','Powder grinding receptacle items'},
 {'f1:19','Processable (to barrel) items'},
 {'f1:17','Processable (to vial) items'},
 {'f1:11','Processable items'},
 {'rp:RENDER_MAT','Renderable items'},
 {'f3:9','Sand items'},
 {'f1:23','Sand-bearing items'},
 {'f2:5','Screw items'},
 {'f2:3','Sewn-imageless items'},
 {'f1:7','Sharpenable items'},
 {'tool:18','Sheet roller items'},
 {'f2:18','Shell items'},
 {'f2:15','Silk items'},
 {'tool:14','Small object container items'},
 {'f2:24','Soap items'},
 {'f1:20','Solid items'},
 {'tool:17','Stand-and-work items'},
 {'rc:TALLOW','Tallow items'},
 {'f1:21','Tameable small creature items'},
 {'rp:TAN_MAT','Tannable items'},
 {'f2:19','Totemable items'},
 {'tool:15','Track cart items'},
 {'f1:5','Undisturbed items'},
 {'f2:29','Unengraved items'},
 {'f3:0','Unimproved items'},
 {'f1:4','Unrotten items'},
 {'rc:WAX','Wax items'},
 {'tool:20','Writing container items'},
 {'f3:11','Written-on items'},
 {'f2:31','Yarn items'},
}
local function build_list(kind,epoch)
 local job={ticket=ticket(),builder_kind=kind==27 and 1 or 0,kind=kind,phase=1,done=0,total=list_total(kind),rows={},seen={},epoch=epoch}
 local cap=kind==27 and 8192 or (kind==4 and 65536 or 1024)
 local function step()coroutine.yield()end
 local function add(row)
  if #job.rows>=cap then error('list exceeds cap',0)end
  if #(row.name or '')>128 or #(row.key or '')>64 then error('list row exceeds string cap',0)end
  job.rows[#job.rows+1]=row
 end
 local function trait(key,name)
  if not job.seen[key]then job.seen[key]=true;add{key=key,name=name or ''}end
 end
 local function material(mt,mi,mat)
  if kind==4 then
   local info=dfhack.matinfo.decode(mt,mi)
   if info then add{mat_type=mt,mat_index=mi,name=utf(info:toString())}end
   step()
  end
 end
 job.thread=coroutine.create(function()
  if kind==27 then generate_tasks(job,add,step)
  elseif kind==3 then
   add{item_type=-1,item_subtype=-1,name='NONE'};job.done=math.min(job.total,job.done+1);step()
   for t=0,df.item_type._last_item do
    add{item_type=t,item_subtype=-1,name=df.item_type[t] or ''};job.done=math.min(job.total,job.done+1);step()
    -- FOOD subtypes are prepared-meal levels, absent from the native Type picker.
    for sub=0,(t==df.item_type.FOOD and 0 or dfhack.items.getSubtypeCount(t))-1 do
     local def=dfhack.items.getSubtypeDef(t,sub)
     add{item_type=t,item_subtype=sub,name=utf(def and def.name or '')};step()
    end
   end
  else
   if kind==4 then add{mat_type=-1,mat_index=-1,name='None'};step()
   else
    for _,row in ipairs(condition_adjectives)do trait(row[1],row[2]);step()end
    for id,color in ipairs(df.global.world.raws.descriptors.colors)do
     trait('dye:'..id,'Color '..utf(color.name or '')..' items');step()
    end
   end
   -- Native Mat includes AMBER..SALT; generic/filth/placeholder builtins are absent.
   local table_=df.global.world.raws.mat_table
   if kind==4 and table_ then for mt,mat in ipairs(table_.builtin)do
    if mat and df.builtin_mats and mt>=df.builtin_mats.AMBER and mt<=df.builtin_mats.SALT then material(mt,-1,mat)end;job.done=math.min(job.total,job.done+1);step()
   end end
   for family,source in ipairs(source_vectors(kind))do
    for index,raw in ipairs(source)do
     if family==1 then
      material(0,index,raw.material)
      if kind==5 then
       for _,target in ipairs(raw.metal_ore.mat_index)do
        local info=dfhack.matinfo.decode(0,target)
        local name=info and utf(info:toString()) or ''
        trait('ore:'..target,name:gsub('^%l',string.upper)..'-bearing items');step()
       end
      end
     else
      for mi,mat in ipairs(raw.material)do material((family==2 and 419 or 19)+mi,index,mat)end
     end
     job.done=math.min(job.total,job.done+1);step()
    end
   end
  end
  if kind==4 or kind==5 or kind==27 then
   job.phase=2;job.done=0
   local rows=job.rows;local width=1;local n=#rows
   local passes=0;local w=1;while w<n do passes=passes+1;w=w*2 end
   job.total=n*passes
   local function less(a,b)
    if kind==27 or kind==5 then return a.name==b.name and a.key<b.key or a.name<b.name end
    if a.mat_type==-1 or b.mat_type==-1 then return a.mat_type==-1 and b.mat_type~=-1 end
    if a.name~=b.name then return a.name<b.name end
    if a.mat_type~=b.mat_type then return a.mat_type<b.mat_type end
    return a.mat_index<b.mat_index
   end
   while width<n do
    local dest={}
    for base=1,n,width*2 do
     local i,j=base,base+width;local left=math.min(base+width,n+1);local right=math.min(base+2*width,n+1)
     while i<left or j<right do
      if i<left and (j>=right or not less(rows[j],rows[i]))then dest[#dest+1]=rows[i];i=i+1
      else dest[#dest+1]=rows[j];j=j+1 end
      job.done=math.min(job.total,job.done+1);step()
     end
    end
    rows=dest;width=width*2
   end
   job.rows=rows
  end
  job.phase=0;job.done=job.total
  job.revision=hash_values{epoch,kind,#job.rows}
 end)
 builds[kind]=job;build_queue[#build_queue+1]=job;return job
end
local function list_reply(r,a)
 local kind=r.action==27 and 27 or a.candidate_kind;local job=builds[kind] or build_list(kind,r.epoch or 0)
 if job.error then return fail(job.error)end
 local function progress(j)return {ok=true,message='Building work-order candidates',active=true,
  build_phase=j.phase,build_done=j.done,build_total=j.total}end
 if job.phase~=0 then return progress(job)end
 if (a.expected_list_revision or 0)~=0 and a.expected_list_revision~=job.revision then return fail('List changed; refresh')end
 local query=a.query:lower()
 local gt,gs,gc=a.group_type or -1,a.group_subtype or -1,a.group_custom or -1
 local filter_key=query..':'..gt..':'..gs..':'..gc
 local selected_family
 if kind==27 then for _,g in ipairs(job.groups)do
  if g.type==gt and g.subtype==gs and g.custom==gc then selected_family=g.family;break end
 end end
 if not job.filter or job.filter.key~=filter_key then
  if job.filter then job.filter.cancelled=true end
  local f={ticket=ticket(),builder_kind=job.builder_kind,key=filter_key,query=query,phase=3,done=0,total=#job.rows,rows={}}
  f.thread=coroutine.create(function()
   for _,row in ipairs(job.rows)do
    if (kind~=27 or (gt==-1 and gs==-1 and gc==-1) or (selected_family and row.families[selected_family])) and row.name:lower():find(query,1,true)then f.rows[#f.rows+1]=row end
    f.done=f.done+1;coroutine.yield()
   end
   f.phase=0
  end)
  job.filter=f;build_queue[#build_queue+1]=f
 end
 local f=job.filter
 if f.error then return fail(f.error)end
 if f.phase~=0 then return progress(f)end
 local rows={};local finish=math.min(#f.rows,a.cursor+128)
 for i=a.cursor+1,finish do rows[#rows+1]=f.rows[i]end
 local out={ok=true,message='Observed work-order candidates',total=#f.rows,list_revision=job.revision,
  next_cursor=finish<#f.rows and finish or 0,active=#build_queue>0 or #estimate_queue>0}
 out[({[3]='types',[4]='materials',[5]='traits',[27]='tasks'})[kind]]=rows
 if kind==27 then
  out.groups=job.groups;local ms,err=managers();if not ms then return fail(err)end;out.managers=ms
 end
 return out
end
local function active_kinds()
 local mask=0
 for _,job in ipairs(build_queue)do if not job.cancelled then mask=mask | (1 << job.builder_kind)end end
 for _,e in ipairs(estimate_queue)do if not e.cancelled then mask=mask | 4;break end end
 return mask
end
local function step_builder(budget,kind)
 local steps=0;local checked={}
 local function estimate_step(e)
  local o=find(e.id)
  if not e.started then e.started=true;e.tick=absolute_tick()end
  if e.cancelled or not o or absolute_tick()<e.tick or absolute_tick()-e.tick>1200 then return false end
  if not checked[e]then
   checked[e]=true
   if revision(o)~=e.revision then return false end
  end
  if e.index<0 or e.index>=#o.item_conditions then return false end
  local c=o.item_conditions[e.index]
  local other=df.global.world.items.other
  local item_list=c.item_type>=0 and df.items_other_id[df.item_type[c.item_type]] or nil
  local items=other[item_list or df.items_other_id.IN_PLAY]
  if e.cursor>=#items then
   local n,v=e.count,c.compare_val
   e.satisfied=({n>=v,n<=v,n>v,n<v,n==v,n~=v})[c.compare_type+1] or false
   e.done=true;return false
  end
  if not e.filter then
   e.filter=df.job_item:new()
   e.filter:assign{item_type=c.item_type,item_subtype=c.item_subtype,mat_type=c.mat_type,mat_index=c.mat_index,
    flags1=c.flags1,flags2=c.flags2,flags3=c.flags3,flags4=c.flags4,flags5=c.flags5,
    reaction_class=c.reaction_class,has_material_reaction_product=c.has_material_reaction_product,
    metal_ore=c.metal_ore,min_dimension=c.min_dimension,reaction_id=c.reaction_id,contains=c.contains,
    has_tool_use=c.has_tool_use,dye_color=c.dye_color,quantity=1}
  end
  local item=items[e.cursor];e.cursor=e.cursor+1;steps=steps+1
  if item and not(item.flags.removed or item.flags.garbage_collect or item.flags.forbid or item.flags.dump or item.flags.in_job or item.flags.owned)then
   if J.isSuitableItem(e.filter,item:getType(),item:getSubtype()) and
      J.isSuitableMaterial(e.filter,item:getMaterial(),item:getMaterialIndex(),item:getType())then
    e.count=e.count+item:getStackSize()
   end
  end
  return true
 end
 while steps<budget do
  local index
  for i,job in ipairs(build_queue)do
   if kind==nil or job.builder_kind==kind then index=i;break end
  end
  if index then
   local job=build_queue[index]
   if job.cancelled then table.remove(build_queue,index)
   else
    local ok,err=coroutine.resume(job.thread)
    if coroutine.status(job.thread)~='dead' then steps=steps+1 end
    if not ok then job.error=tostring(err);table.remove(build_queue,index)
    elseif coroutine.status(job.thread)=='dead' then table.remove(build_queue,index)end
   end
  elseif (kind==nil or kind==2)and #estimate_queue>0 then
   local e=estimate_queue[1]
   local ok,keep=pcall(estimate_step,e)
   if not ok or not keep then
    free_filter(e)
    if not e.done and estimates[e.key]==e then estimates[e.key]=nil end
    table.remove(estimate_queue,1)
   end
  else break end
 end
 return {ok=true,message='Work-order builder advanced',steps=steps}
end
local function handle(r)
 if r.cancel_builders then
  invalidate_estimates();build_queue={};builds={};return {ok=true,message='Work-order builders cancelled'}
 end
 if r.step then
  local saved_jobs,saved_indices=request_jobs,request_order_indices
  request_jobs=nil;request_order_indices=nil
  local result=step_builder(math.min(2048,math.max(0,r.step)),r.builder_kind)
  request_jobs,request_order_indices=saved_jobs,saved_indices
  return result
 end
 request_jobs=nil
 request_order_indices=nil
 local a=r.work_order;if not a then return fail('Work order request missing')end
 if r.action==26 and a.candidate_kind>=3 then return list_reply(r,a)end
 if r.action==27 then return list_reply(r,a)end
 if r.action==20 or r.action==26 then
  local current=list_revision()
  if r.action==20 and (a.expected_list_revision or 0)~=0 and a.expected_list_revision~=current then return fail('List changed; refresh')end
  if not list_scan or list_scan.seq~=r.seq then
   local ids={}
   if r.action==20 then for i,o in ipairs(all())do if i>=a.cursor then ids[#ids+1]=o.id end;request_step()end
   elseif a.candidate_kind==0 then for _,o in ipairs(all())do if o.id>=a.cursor then ids[#ids+1]=o.id end;request_step()end
   elseif a.candidate_kind==1 then for _,b in ipairs(df.global.world.buildings.all)do if b.id>=a.cursor and family(b)then ids[#ids+1]=b.id end;request_step()end
   else for i=math.max(0,a.cursor),df.item_type._last_item do request_step();ids[#ids+1]=i end end
   if r.action~=20 then ids=sort_ids(ids)end
   list_scan={seq=r.seq,ids=ids,index=1,matches={},revision=current}
   if r.action==26 then
    local eligible={r.epoch or 0,a.candidate_kind}
    if a.candidate_kind==2 then eligible[#eligible+1]=df.item_type._last_item+1
    elseif a.candidate_kind==0 then for _,o in ipairs(all())do eligible[#eligible+1]=o.id;request_step()end
    else for _,b in ipairs(df.global.world.buildings.all)do if family(b) and visible(b) and b:getBuildStage()==b:getMaxBuildStage()then eligible[#eligible+1]=b.id end;request_step()end end
    list_scan.revision=hash_values(eligible)
   end
  end
  local scan=list_scan
  if (a.expected_list_revision or 0)~=0 and a.expected_list_revision~=scan.revision then list_scan=nil;return fail('List changed; refresh')end
  if r.action==20 and scan.revision~=current then list_scan=nil;return fail('List changed; refresh')end
  local limit=r.action==20 and 16 or 128
  local finish=math.min(#scan.ids,scan.index+511)
  for index=scan.index,finish do
   request_step()
   local id=scan.ids[index];local name
   if r.action==20 or a.candidate_kind==0 then local o=find(id);if o then name=utf(J.getManagerOrderName(o))end
   elseif a.candidate_kind==1 then local b=df.building.find(id);if b and visible(b) and b:getBuildStage()==b:getMaxBuildStage()then name=utf(B.getName(b))end
   else name=df.item_type[id]end
   scan.index=index+1
   if name and (name:lower():find(a.query:lower(),1,true) or tostring(id)==a.query)then
    scan.matches[#scan.matches+1]={id=id,name=name..' #'..id}
    if #scan.matches>limit then break end
   end
  end
  if scan.index<=#scan.ids and #scan.matches<=limit then return {ok=true,pending=true,message='Searching native identities'}end
  local rows,choices={},{};local cursor=0;local condition_count,job_count,trait_count,input_count=0,0,0,0
  for _,v in ipairs(scan.matches)do
   if r.action==20 then
    local native=find(v.id);local o,err;if native then o,err=inspect(native)end
    if err then list_scan=nil;return fail(err)end
    if o then
     local nt=0;for _,c in ipairs(o.conditions)do nt=nt+#(c.traits or {})end
     if nt>2048 then list_scan=nil;return fail('Order exceeds trait page cap')end
     if #rows==limit or condition_count+#o.conditions>128 or job_count+#o.generated_jobs>2048 or trait_count+nt>2048 or input_count+#o.inputs>128 then cursor=o.position;break end
     trait_count=trait_count+nt;input_count=input_count+#o.inputs
     rows[#rows+1]=o;condition_count=condition_count+#o.conditions;job_count=job_count+#o.generated_jobs
    end
   else
    if #choices==limit then cursor=v.id;break end
    choices[#choices+1]=v
   end
  end
  list_scan=nil
  return {ok=true,message='Observed work-order identities',orders=rows,choices=choices,next_cursor=cursor,total=r.action==20 and #all() or #scan.ids,list_revision=scan.revision,active=#build_queue>0 or #estimate_queue>0}
 end
 if r.action==22 and #all()>=ORDER_CAP then return fail('Work order count exceeds 4096-order cap')end
 if r.action==22 then
  local rs,err=catalog();if not rs then return fail(err)end
  local recipe=builds[27].by_key[a.recipe]
  if not recipe then return fail('Recipe changed or is unavailable')end
  if not workshop_valid(a.workshop_id==-2 and -1 or a.workshop_id,recipe)then return fail('Selected workshop cannot service this recipe')end
  local o=df.manager_order:new()
  task_fields(o,recipe)
  o:assign{frequency=a.frequency<0 and df.workquota_frequency_type.OneTime or a.frequency,
   amount_left=a.remaining<0 and 10 or a.remaining,amount_total=a.remaining<0 and 10 or a.remaining,workshop_id=a.workshop_id==-2 and -1 or a.workshop_id,
   max_workshops=a.max_workshops<0 and 0 or a.max_workshops}
  o.status.validated=false;o.status.active=false
  o.id=df.global.world.manager_orders.manager_order_next_id
  df.global.world.manager_orders.manager_order_next_id=o.id+1
  all():insert('#',o);request_order_indices=nil;invalidate_estimates()
  return reply(o,'Queued unvalidated work order; DF owns authorization')
 end
 local o=find(a.id);if not o then return fail('Work order no longer exists')end
 if r.action==21 then return reply(o)end
 local observed,err
 if r.action==24 or (r.action==23 and (a.move or 0)~=0)then
  observed={revision=revision(o),position=request_order_indices[o.id]}
 else observed,err=inspect(o)end
 if not observed then return fail(err)end
 if a.expected_revision~=observed.revision then return fail('Work order changed; inspect again before editing')end
 if r.action==24 then
  local dependencies=0
  for _,other in ipairs(all())do
   dependencies=dependencies+#other.order_conditions
   if dependencies>DELETE_DEPENDENCY_CAP then return fail('Delete exceeds 4096-dependency sweep cap')end
  end
  local count=1
  for _,other in ipairs(all())do for _,c in ipairs(other.order_conditions)do if c.order_id==o.id then count=count+1 end end end
  if count>(r.retire_capacity or 0)then return fail('Deleted-order capacity reached; restart DF')end
  local retired={}
  for _,other in ipairs(all())do
   for i=#other.order_conditions-1,0,-1 do local c=other.order_conditions[i]
    if c.order_id==o.id then retired[#retired+1]=c;other.order_conditions:erase(i)end
   end
  end
  retired[#retired+1]=o;all():erase(observed.position);receipts[o.id]=nil;request_order_indices=nil;invalidate_estimates()
  return {ok=true,message='Work order deleted; generated jobs retained',retired=retired}
 end
 if r.action==23 and (a.move or 0)~=0 then
  if a.move~=-1 and a.move~=1 then return fail('Invalid work-order move')end
  if (a.expected_list_revision or 0)==0 or a.expected_list_revision~=list_revision()then return fail('List changed; refresh')end
  if a.remaining~=-1 or a.frequency~=-1 or a.workshop_id~=-2 or a.max_workshops~=-1 or (a.input_index or -1)~=-1 or (a.traits and #a.traits>0) or (a.mat_type or -1)~=-1 or (a.mat_index or -1)~=-1 or (a.encrust_flags or -1)~=-1 then return fail('Move must be an exclusive update')end
  local pos=observed.position;local target=pos+a.move
  if target<0 or target>=#all()then return fail('Neighbor changed; inspect again')end
  local neighbor=all()[target]
  if not neighbor or neighbor.id~=a.expected_neighbor then return fail('Neighbor changed; inspect again')end
  all():erase(pos);all():insert(pos+a.move,o);request_order_indices=nil;invalidate_estimates()
  return {ok=true,message='Work order moved'}
 end
 if (r.action==23 or r.action==25) and not observed.editable then return fail(observed.reason)end
 if r.action==23 and (a.input_index or -1)>=0 then
  if a.remaining~=-1 or a.frequency~=-1 or a.workshop_id~=-2 or a.max_workshops~=-1 or (a.traits and #a.traits>0) then return fail('Details must be an exclusive update')end
  local f=o.items and a.input_index<#o.items.elements and o.items.elements[a.input_index]
  local kind=detail_kind(o)
  if not f or not(kind==2 or kind==3 or kind==5 or kind==6)then return fail('Order has no editable material input')end
  if (a.encrust_flags or -1)>=0 and (kind~=5 or (a.encrust_flags & ~1092)~=0)then return fail('Invalid gem decoration flags')end
  if ((a.mat_type or -1)>=0 or (a.mat_index or -1)>=0) and not dfhack.matinfo.decode(a.mat_type,a.mat_index or -1)then return fail('Unknown native material')end
  if (a.mat_type or -1)>=0 or (a.mat_index or -1)>=0 then
   f.job_details_mat_type=a.mat_type or -1;f.job_details_mat_index=a.mat_index or -1
   f.job_details_flags.have_set_job_details=true
  end
  if (a.encrust_flags or -1)>=0 then o.specflag.encrust_flags.whole=a.encrust_flags end
 elseif r.action==23 then
  if a.remaining<0 and a.frequency<0 and a.workshop_id==-2 and a.max_workshops<0 then return reply(o,'No work-order fields changed')end
  local total=o.amount_total
  if a.remaining>=0 then
   if #observed.generated_jobs>0 then return fail('Finish generated jobs before changing remaining work')end
   if (a.remaining==0 or o.amount_total==0) and o.amount_total~=o.amount_left then return fail('Cannot change finite/indefinite mode after work completed')end
   total=a.remaining==0 and 0 or o.amount_total-o.amount_left+a.remaining
   if total>32767 then return fail('Total quantity would overflow native int16')end
  end
  if a.workshop_id>=0 then local rs,why=catalog();if not rs then return fail(why)end;if not workshop_valid(a.workshop_id,recipe_for(o))then return fail('Workshop restriction unsupported for this order')end end
  if a.remaining>=0 then o.amount_total=total;o.amount_left=a.remaining end
  if a.frequency>=0 then o.frequency=a.frequency end
  if a.workshop_id~=-2 then o.workshop_id=a.workshop_id end
  if a.max_workshops>=0 then o.max_workshops=a.max_workshops end
 elseif r.action==25 then
  local conditions=a.condition_kind==0 and o.item_conditions or o.order_conditions
  local existing=a.condition_index>=0 and a.condition_index<#conditions and conditions[a.condition_index] or nil
  if a.condition_index>=0 and not existing then return fail('Condition identity changed')end
  if a.remove_condition then
   if not existing then return fail('Condition identity changed')end
   if (r.retire_capacity or 0)<1 then return fail('Deleted-order capacity reached; restart DF')end
   conditions:erase(a.condition_index);invalidate_estimates();o.status.validated=false;o.status.active=false
   local result=reply(o,'Condition removed; awaiting native reevaluation');result.retired={existing};return result
  end
  if existing and a.condition_kind==1 and (existing.condition<0 or existing.condition>1)then return fail('Unsupported custom condition is read only')end
  do
   if not existing and #o.item_conditions+#o.order_conditions>=64 then return fail('Condition limit reached')end
   if a.condition_kind==0 then
    if a.item_type < -1 or a.item_type>df.item_type._last_item then return fail('Unknown native item type')end
    if (a.item_subtype or -1)>=0 and (a.item_type<0 or a.item_subtype>=dfhack.items.getSubtypeCount(a.item_type))then return fail('Unknown native item subtype')end
    local values=a.traits~=nil and parse_traits(a.traits) or nil
    if a.traits~=nil and not values then return fail('Unknown condition trait')end
    if ((a.mat_type or -1)>=0 or (a.mat_index or -1)>=0) and (not existing or existing.mat_type~=(a.mat_type or -1) or existing.mat_index~=(a.mat_index or -1)) and not dfhack.matinfo.decode(a.mat_type,a.mat_index or -1)then return fail('Unknown native material')end
    local c=existing or df.manager_order_condition_item:new()
    if not existing then
     c:assign{item_subtype=-1,mat_type=-1,mat_index=-1,metal_ore=-1,min_dimension=-1,reaction_id=-1,has_tool_use=-1,dye_color=-1}
    end
    c.item_type=a.item_type;c.compare_type=a.compare;c.compare_val=a.threshold
    -- 01-U: item-condition edits must echo subtype/material; omitted values reset to -1.
    c.item_subtype=a.item_subtype or -1;c.mat_type=a.mat_type or -1;c.mat_index=a.mat_index or -1
    if values then apply_traits(c,values)end
    if not existing then
     if #conditions==0 and o.frequency==df.workquota_frequency_type.OneTime then o.frequency=df.workquota_frequency_type.Daily end
     conditions:insert('#',c)
    end
   else
    if not find(a.target_order) or cycles(o.id,a.target_order)then return fail('Dependency target missing or would form a cycle')end
    for i,c in ipairs(conditions)do if i~=a.condition_index and c.order_id==a.target_order then return fail('Duplicate order dependency')end end
    local c=existing or df.manager_order_condition_order:new();c.order_id=a.target_order;c.condition=a.dependency;c.flags.satisfied=false
    if not existing then conditions:insert('#',c)end
   end
  end
 else return fail('Unsupported work-order action')end
 -- Preserve outstanding jobs/counters/filters; only DF may reauthorize edited intent.
 o.status.validated=false;o.status.active=false;invalidate_estimates()
 return reply(o,'Order changed; awaiting native reevaluation and authorization')
end

local inline_request
return function(r)
 local result
 -- Check every continuation too: native orders can grow between request slices.
 if not r.cancel_builders and #all()>ORDER_CAP then
  inline_request=nil
  invalidate_estimates();build_queue={};builds={}
  result=fail('Work order count exceeds 4096-order cap')
 elseif not r.step and not r.cancel_builders and (r.action==20 or (r.action==26 and r.work_order and r.work_order.candidate_kind<3))then
  if not inline_request or inline_request.seq~=r.seq then
   inline_request={seq=r.seq,thread=coroutine.create(function()return handle(r)end)}
  end
  local used=0;local budget=math.min(2048,r.step_budget or 2048)
  request_scanning=true
  while used<budget do
   local ok,value=coroutine.resume(inline_request.thread)
   if not ok then result=fail(tostring(value));inline_request=nil;break end
   if coroutine.status(inline_request.thread)=='dead' then result=value;inline_request=nil;break end
   used=used+1
  end
  request_scanning=false
  result=result or {ok=true,pending=true,message='Searching native identities'}
  result.steps=used
 else
  if r.cancel_builders then inline_request=nil end
  result=handle(r)
 end
 result.active_kinds=active_kinds()
 result.active=result.active_kinds~=0
 return result
end
