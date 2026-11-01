-- Diagnostic role inputs in an owned paused clone; no equip/drop command.
local unit,view,pointer,read=...
local entry=assert(unit.inventory[0]);local weapon=assert(df.global.world.items.other.WEAPON[0])
local saved={item=entry.item,mode=entry.mode,part=entry.body_part_id,seed=entry.pet_seed,
 size=unit.body.size_info.size_cur,flags2=unit.flags2.whole,flags3=unit.flags3.whole,
 glow=unit.cache.cached_glowtile_type}
local copies={}
local function save(address,size)
 if size==0 then return end
 local bytes=df.new('uint8_t',size);dfhack.internal.memmove(bytes,address,size)
 copies[#copies+1]={address=address,size=size,bytes=bytes}
end
for _,vector in ipairs{unit.body.components.body_part_status,unit.enemy.motor_nervenet,
 unit.enemy.sensory_nervenet,unit.enemy.body_part_useable}do
 local _,address=df.sizeof(vector)
 local first=df.reinterpret_cast('uint64_t',address).value
 local last=df.reinterpret_cast('uint64_t',address+8).value
 save(first,last-first)
end
local base=dfhack.internal.getImageBase()
for _,range in ipairs{{0x234e990,0x6180},{0x2131b30,40},{0x2159084,2},{0x18adf98,8}}do save(base+range[1],range[2])end
local function restore()
 entry.item=saved.item;entry.mode=saved.mode;entry.body_part_id=saved.part;entry.pet_seed=saved.seed
 unit.body.size_info.size_cur=saved.size;unit.flags2.whole=saved.flags2;unit.flags3.whole=saved.flags3
 unit.cache.cached_glowtile_type=saved.glow
 for _,v in ipairs(copies)do dfhack.internal.memmove(v.address,v.bytes,v.size)end
end
local function line(y)
 local text={}
 for x=61,101 do local p=dfhack.screen.readTile(x,y);text[#text+1]=p.ch>=32 and string.char(p.ch%256) or ' 'end
 return dfhack.df2utf(table.concat(text)):match('^%s*(.-)%s*$')
end
local cases={}
local ok,err=xpcall(function()
 local function observe(name)
  -- Read BEFORE native rendering can warm the source's caches or alter RNG.
  local result=read();local reader=result.rows[1].role
  pointer(400,400)
  local native=line(19)
  cases[#cases+1]={name=name,reader=reader,native=native,guards_unchanged=result.guards_unchanged}
  assert(reader==native,'Role differs: '..name..' ['..reader..'] ['..native..']')
 end
 for _,seed in ipairs{0,1,2,12345}do
  restore();entry.mode=df.inv_item_role_type.Pet;entry.pet_seed=seed
  observe('pet-'..seed)
 end
 restore();entry.item=weapon;entry.mode=df.inv_item_role_type.Weapon
 unit.body.size_info.size_cur=1
 assert(weapon:needTwoHandedWield(1),'Expected two-handed weapon fixture')
 unit.flags2.calculated_nerves=false;unit.flags2.calculated_bodyparts=false
 observe('weapon-cold-body-caches')
end,debug.traceback)
restore()
for _,v in ipairs(copies)do df.delete(v.bytes)end
pointer(400,400)
assert(ok,err)
return cases
