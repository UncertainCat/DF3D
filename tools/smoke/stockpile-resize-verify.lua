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
 _G.df3d_resize_check={id=b.id,z=b.z,keep=keep,before=snapshot(b)}
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
elseif request.op=='resize_erase_prepare' then
 local b=assert(df.building.find(request.id));local x,y=b.x1+1,b.y1
 local block=assert(dfhack.maps.getTileBlock(x,y,b.z));local bx,by=x%16,y%16
 block.tiletype[bx][by]=request.case=='wall' and df.tiletype.StoneWall or request.case=='open' and df.tiletype.OpenSpace or df.tiletype.StoneFloor1
 block.designation[bx][by].hidden=request.case=='hidden'
 block.designation[bx][by].flow_size=request.case=='water7' and 7 or request.case=='magma1' and 1 or 0
 block.designation[bx][by].liquid_type=request.case=='magma1'
 block.occupancy[bx][by].building=request.case=='building' and 2 or 0
 _G.df3d_erase_check={id=b.id,before=snapshot(b)}
elseif request.op=='resize_erase_check' then
 local s=assert(_G.df3d_erase_check);local b=assert(df.building.find(s.id))
 assert(dfhack.buildings.countExtentTiles(b,-1)==0,'invalid cell was not erased')
 local after=snapshot(b)
 for i,v in ipairs(s.before.bounds)do assert(after.bounds[i]==v,'erase changed allocation bounds')end
 for y=b.y1,b.y2 do for x=b.x1,b.x2 do
  local block=assert(dfhack.maps.getTileBlock(x,y,b.z))
  assert(not block.designation[x%16][y%16].pile and block.occupancy[x%16][y%16].building==0,'erase retained occupancy')
 end end
 result.area=after
elseif request.op=='resize_grow_prepare' then
 local b=assert(df.building.find(request.id));local x,y,z=b.x2+1,b.y1,b.z
 local mask={1,1,1}
 if request.case=='wall-left' then mask[1]=0 elseif request.case=='wall-right' then mask[3]=0
 elseif request.case=='all-wall' then mask={0,0,0}end
 for i=1,3 do
  local block=assert(dfhack.maps.getTileBlock(x+i-1,y,z));local bx,by=(x+i-1)%16,y%16
  assert(not block.designation[bx][by].pile and block.occupancy[bx][by].building==0,'growth fixture overlaps building')
  block.tiletype[bx][by]=mask[i]==0 and df.tiletype.StoneWall or df.tiletype.StoneFloor1
  block.designation[bx][by].hidden=false;block.designation[bx][by].flow_size=0
 end
 _G.df3d_grow_check={id=b.id,x=x,y=y,mask=mask,before=snapshot(b)}
 result.origin={x=x,y=y,z=z}
elseif request.op=='resize_grow_check' then
 local s=assert(_G.df3d_grow_check);local b=assert(df.building.find(s.id));local right=s.before.bounds[3];local count=3
 for i,v in ipairs(s.mask)do
  assert(dfhack.buildings.containsTile(b,s.x+i-1,s.y)==(v==1),'wrong growth cell')
  if v==1 then right=s.x+i-1;count=count+1 end
 end
 assert(b.x1==s.before.bounds[1] and b.x2==right and b.y1==s.before.bounds[2] and b.y2==s.before.bounds[4],'growth bounds include rejected edge')
 assert(dfhack.buildings.countExtentTiles(b,-1)==count,'growth changed retained cells')
 result.area=snapshot(b)
elseif request.op=='resize_create_prepare' then
 local s=assert(_G.df3d_resize_check);local x,y,z=s.before.bounds[1],s.before.bounds[2],s.z
 local mask={1,1,1}
 if request.case=='wall' or request.case=='hidden' or request.case=='building' then mask[2]=0
 elseif request.case=='wall-left' then mask[1]=0 elseif request.case=='wall-right' then mask[3]=0
 elseif request.case=='all-wall' then mask={0,0,0}end
 for i=1,3 do
  local block=assert(dfhack.maps.getTileBlock(x+i-1,y,z));local bx,by=(x+i-1)%16,y%16
  block.tiletype[bx][by]=mask[i]==0 and request.case:find('wall',1,true) and df.tiletype.StoneWall or df.tiletype.StoneFloor1
  block.designation[bx][by].hidden=request.case=='hidden' and i==2
  block.designation[bx][by].pile=false
  block.designation[bx][by].flow_size=(request.case=='water7' and 7 or request.case=='magma1' and 1 or 0)
  block.designation[bx][by].liquid_type=request.case=='magma1'
  block.occupancy[bx][by].building=request.case=='building' and i==2 and 1 or 0
 end
 _G.df3d_create_check={x=x,y=y,z=z,mask=mask,next_id=df.global.building_next_id,count=#df.global.world.buildings.all}
 result.origin={x=x,y=y,z=z};result.mask=mask
elseif request.op=='resize_create_check' then
 local s=assert(_G.df3d_create_check)
 if request.id==-1 then
  assert(df.global.building_next_id==s.next_id and #df.global.world.buildings.all==s.count,'no-op creation allocated a building')
  result.noop=true
 else
  local b=assert(df.building.find(request.id));assert(b.x1==s.x and b.x2==s.x+2 and b.y1==s.y and b.y2==s.y and b.z==s.z,'clipped creation changed requested bounds')
  local count=0
  for i,value in ipairs(s.mask)do assert(dfhack.buildings.containsTile(b,s.x+i-1,s.y)==(value==1),'wrong clipped cell');count=count+value end
  assert(dfhack.buildings.countExtentTiles(b,-1)==count,'wrong clipped creation count')
  result.area=snapshot(b);result.id=b.id
 end
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
