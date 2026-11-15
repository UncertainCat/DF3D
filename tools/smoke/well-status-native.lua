-- Controlled paused well refusal states, restoring the existing bucket and well.
local out,view,b,capture=...
local json=require('json')
local bucket_entry,bucket_index
for index,held in ipairs(b.contained_items)do if held.item:getType()==df.item_type.BUCKET then bucket_entry=held;bucket_index=index;break end end
assert(bucket_entry,'Well lacks baseline bucket')
local bucket=bucket_entry.item;local original_z=b.bucket_z;local detached=false;local water
local result={building_id=b.id,cases={}}
local function shot(label,status,text)
 view:render(dfhack.getTickCount());capture('well-status-'..label)
 local output,code=dfhack.run_command_silent('df3d','well-status-probe',tostring(b.id));assert(code==0,output)
 local value=json.decode(output);assert(value.status==status,label..': '..output)
 local g=df.global.gps;local found=false
 for y=4,g.dimy-1 do
  local chars={};for x=52,112 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
  if table.concat(chars):find(text,1,true)then found=true end
 end
 assert(found,'Native message missing: '..text)
 result.cases[#result.cases+1]={label=label,status=status,text=text}
end
local ok,err=xpcall(function()
 shot('operational',-1,'The well is operational.')
 b.contained_items:erase(bucket_index);detached=true
 shot('no-bucket',84,'There is no bucket.')
 b.contained_items:insert(bucket_index,bucket_entry);detached=false
 b.bucket_z=0;shot('dry',86,'The well is dry.');b.bucket_z=original_z
 local worker
 for _,u in ipairs(df.global.world.units.active)do if dfhack.units.isCitizen(u)then worker=u;break end end
 local mat=assert(dfhack.matinfo.find('WATER'))
 local items=dfhack.items.createItem(assert(worker),df.item_type.LIQUID_MISC,-1,mat.type,mat.index)
 assert(#items==1);water=items[1]
 -- Diagnostic fill uses native per-stack volume; dimension is separate.
 local capacity=dfhack.items.getCapacity(bucket);local unit_volume=water:getVolume()
 assert(unit_volume>0 and capacity%unit_volume==0,'Unexpected water volume '..unit_volume)
 water.stack_size=capacity//unit_volume
 assert(water:getVolume()==capacity,'Stack volume '..water:getVolume())
 assert(dfhack.items.moveToContainer(water,bucket))
 result.water_stack=water.stack_size;result.bucket_capacity=capacity;result.water_volume=water:getVolume()
 shot('full',85,'The bucket is full.')
end,debug.traceback)
if water then assert(dfhack.items.remove(water))end
if detached then b.contained_items:insert(bucket_index,bucket_entry)end
b.bucket_z=original_z
assert(ok,err);shot('restored',-1,'The well is operational.');result.restored=true
return result

