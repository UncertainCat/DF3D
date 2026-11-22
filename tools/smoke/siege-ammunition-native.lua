-- Native rendering is used only as a disposable observation oracle.
local engine,probe,view,lines,capture,worker,material=...
local json=require('json');local created={};local result={}
local function compare(label)
 view:render(dfhack.getTickCount())
 local counts={}
 for _,row in ipairs(lines())do
  local value=row.text:match('^Bolts .-: (%d+)$')
  if value then counts[#counts+1]=tonumber(value)end
 end
 assert(#counts==4,'Missing native ammunition captions')
 local owned=probe(engine)
 assert(json.encode(counts)==json.encode(owned.ammunition),'Owned ammunition counts differ: '..json.encode(owned))
 result[#result+1]={label=label,native=counts,owned=owned.ammunition}
 return counts
end
local ok,err=xpcall(function()
 local baseline=compare('natural')
 local subtype
 for i,raw in ipairs(df.global.world.raws.itemdefs.ammo)do if raw.ammo_class=='BOLT' then subtype=i;break end end
 assert(subtype,'No bolt subtype')
 local function make(amount)
  local values=dfhack.items.createItem(worker,df.item_type.AMMO,subtype,material.type,material.index)
  assert(#values==1);local item=values[1];created[#created+1]=item;item:setStackSize(amount)
  assert(dfhack.items.moveToGround(item,{x=engine.centerx+1,y=engine.centery+1,z=engine.z}))
  return item
 end
 local available=make(7);local loaded=make(11);local forbidden=make(13);forbidden.flags.forbid=true
 assert(dfhack.items.moveToBuilding(loaded,engine,0,true))
 local values=compare('loaded-available-forbidden')
 assert(values[1]==baseline[1]+11 and values[2]==baseline[2]+7 and values[3]==baseline[3] and values[4]==baseline[4])
 capture('siege-ammunition-mixed')
 forbidden.flags.forbid=false
 values=compare('unforbidden')
 assert(values[2]==baseline[2]+20)
 for _,item in ipairs(created)do item.flags.in_building=false;assert(dfhack.items.remove(item))end
 created={}
 assert(json.encode(compare('restored'))==json.encode(baseline))
end,debug.traceback)
for _,item in ipairs(created)do item.flags.in_building=false;assert(dfhack.items.remove(item))end
assert(ok,err);return result
