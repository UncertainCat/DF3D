-- Protected owned lane only. Setup establishes limits on an existing stocked
-- pile; all geometry changes are sent through the ordinary DF3D command path.
local out,index=...
local json=require('json')
local f=assert(io.open(out..'/request-'..index..'.json'));local request=json.decode(f:read('*a'));f:close()
local result={status='passed'}
assert(df.global.pause_state)
local function snapshot(b)
 local r={bounds={b.x1,b.y1,b.x2,b.y2},extents={},containers={},limits={b.storage.max_barrels,b.storage.max_bins,b.storage.max_wheelbarrows}}
 for y=b.y1,b.y2 do for x=b.x1,b.x2 do r.extents[#r.extents+1]=dfhack.buildings.containsTile(b,x,y) end end
 for i,id in ipairs(b.storage.container_item_id)do r.containers[#r.containers+1]={id=id,type=b.storage.container_type[i],x=b.storage.container_x[i],y=b.storage.container_y[i]}end
 return r
end
if request.op=='resize_setup' then
 local b
 for _,candidate in ipairs(df.global.world.buildings.other.STOCKPILE)do
  if #candidate.storage.container_item_id>1 and dfhack.buildings.countExtentTiles(candidate,-1)>2 then b=candidate;break end
 end
 assert(b,'no stocked pile available')
 local keep={x=b.storage.container_x[0],y=b.storage.container_y[0]}
 assert(dfhack.buildings.containsTile(b,keep.x,keep.y))
 local erase={};local grow
 for y=b.y1,b.y2 do for x=b.x1,b.x2 do
  if dfhack.buildings.containsTile(b,x,y) and (x~=keep.x or y~=keep.y)then
   erase[#erase+1]={x=x,y=y,length=1};grow=grow or {x=x,y=y,length=1}
  end
 end end
 local count=dfhack.buildings.countExtentTiles(b,-1)
 b.storage.max_barrels=count;b.storage.max_bins=count;b.storage.max_wheelbarrows=count
 _G.df3d_resize_check={id=b.id,keep=keep,before=snapshot(b)}
 result.id=b.id;result.erase=erase;result.grow={grow};result.keep={{x=keep.x,y=keep.y,length=1}};result.before=_G.df3d_resize_check.before
elseif request.op=='resize_malformed' then
 local s=assert(_G.df3d_resize_check);local b=assert(df.building.find(s.id))
 s.last_y=b.storage.container_y[#b.storage.container_y-1];b.storage.container_y:erase(#b.storage.container_y-1)
elseif request.op=='resize_restore' then
 local s=assert(_G.df3d_resize_check);local b=assert(df.building.find(s.id))
 assert(#b.storage.container_y+1==#s.before.containers,'malformed vector changed')
 b.storage.container_y:insert('#',s.last_y)
 assert(json.encode(snapshot(b))==json.encode(s.before),'refusal changed pile state')
elseif request.op=='resize_check' then
 local s=assert(_G.df3d_resize_check);local b=assert(df.building.find(s.id));local actual=snapshot(b)
 assert(dfhack.buildings.countExtentTiles(b,-1)==request.tiles,'wrong occupied count')
 for i,v in ipairs(s.before.bounds)do assert(actual.bounds[i]==v,'erase changed bounds')end
 for _,v in ipairs(actual.limits)do assert(v==1,'limit failed to clamp or regrowth reset it')end
 local expected={};local released=0
 for _,row in ipairs(s.before.containers)do
  local item=assert(df.item.find(row.id));local ref=assert(item:getStockpile2())
  if row.x==s.keep.x and row.y==s.keep.y then
   expected[#expected+1]=row;assert(ref.id==b.id and ref.x==row.x and ref.y==row.y,'retained assignment changed')
  else
   released=released+1;assert(ref.id==-1 and ref.x==-30000 and ref.y==-30000,'native item assignment was not released')
  end
 end
 assert(#actual.containers==#expected,'wrong container vector length')
 for i,row in ipairs(expected)do for key,value in pairs(row)do assert(actual.containers[i][key]==value,'parallel vectors differ')end end
 result.area=actual;result.released=released;result.retained=#expected
elseif request.op=='resize_deleted' then
 local s=assert(_G.df3d_resize_check)
 assert(not df.building.find(s.id),'empty stockpile still exists after deletion')
 for _,row in ipairs(s.before.containers)do
  local item=assert(df.item.find(row.id));local ref=assert(item:getStockpile2())
  assert(ref.id==-1 and ref.x==-30000 and ref.y==-30000,'deletion retained item assignment')
 end
 result.deleted=s.id;result.released=#s.before.containers
else error('unknown resize verification '..tostring(request.op))end
f=assert(io.open(out..'/response-'..index..'.json','w'));f:write(json.encode(result));f:close()
print('SEMANTIC_PASS '..index..' '..request.op)
