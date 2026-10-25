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
local link_keys={'give_to_pile','take_from_pile','give_to_workshop','take_from_workshop'}
local function copy_links(b)
 local out={};local links=b:getStockpileLinks()
 for _,key in ipairs(link_keys)do
  local rows={};for i=0,#links[key]-1 do rows[i+1]=links[key][i] or false end
  out[key]=rows
 end
 return out
end
local function set_rows(vector,rows)
 vector:resize(0)
 for _,value in ipairs(rows)do vector:insert('#',value or nil)end
end
local function restore_link_fixture(s)
 for i,b in ipairs(s.endpoints)do for _,key in ipairs(link_keys)do set_rows(b:getStockpileLinks()[key],s.original[i][key])end end
 for _,b in ipairs(s.owned)do b:delete()end
 _G.df3d_link_boundary=nil
end
local function same_links(b,expected)
 local actual=copy_links(b)
 for _,key in ipairs(link_keys)do
  if #actual[key]~=#expected[key]then return false end
  for i,value in ipairs(expected[key])do if actual[key][i]~=value then return false end end
 end
 return true
end
if request.op=='resize_link_setup' then
 assert(not _G.df3d_link_boundary)
 local endpoints={}
 local function shown(b)
  for y=b.y1,b.y2 do for x=b.x1,b.x2 do
   local block=dfhack.maps.getTileBlock(x,y,b.z)
   if block and not block.designation[x%16][y%16].hidden then return true end
  end end
  return false
 end
 for _,b in ipairs(df.global.world.buildings.other.STOCKPILE)do
  if shown(b)then endpoints[#endpoints+1]=b;if #endpoints==2 then break end end
 end
 assert(#endpoints==2,'two revealed stockpiles required')
 local workshop
 for _,b in ipairs(df.global.world.buildings.other.IN_PLAY)do
  if b:canLinkToStockpile() and not df.building_stockpilest:is_instance(b) and shown(b)then workshop=b;break end
 end
 assert(workshop,'revealed linkable workshop required')
 endpoints[3]=workshop
 local s={endpoints=endpoints,original={},owned={}}
 _G.df3d_link_boundary=s
 for i,b in ipairs(endpoints)do s.original[i]=copy_links(b)end
 for _,b in ipairs(endpoints)do for _,key in ipairs(link_keys)do b:getStockpileLinks()[key]:resize(0)end end
 result.source=endpoints[1].id;result.target=endpoints[2].id;result.workshop=workshop.id
elseif request.op=='resize_link_inject' then
 local s=assert(_G.df3d_link_boundary)
 local ok,why=pcall(function()
  local vector=s.endpoints[request.endpoint]:getStockpileLinks()[request.key]
  if request.case=='null' then vector:resize(1)
  else
   local n=request.count or 2
   for i=1,n do
    local b=request.key:find('workshop') and df.building_workshopst:new() or df.building_stockpilest:new()
    b.id=1000000000+i;s.owned[#s.owned+1]=b;vector:insert('#',b)
   end
   if request.case=='duplicate' then vector[1]=vector[0]
   elseif request.case=='unsorted' then local b=vector[0];vector[0]=vector[1];vector[1]=b end
  end
  s.before={};for i,b in ipairs(s.endpoints)do s.before[i]=copy_links(b)end
 end)
 if not ok then restore_link_fixture(s);error(why)end
elseif request.op=='resize_link_check_restore' then
 local s=assert(_G.df3d_link_boundary)
 local ok,why=pcall(function()
  local expected=s.before
  if request.success then
   local source=s.endpoints[request.workshop and 3 or 1];local target=s.endpoints[2]
   local a=request.give and 'give_to_pile' or 'take_from_pile'
   local b=request.workshop and (request.give and 'take_from_workshop' or 'give_to_workshop') or
    (request.give and 'take_from_pile' or 'give_to_pile')
   table.insert(expected[request.workshop and 3 or 1][a],1,target)
   table.insert(expected[2][b],1,source)
  end
  for i,b in ipairs(s.endpoints)do assert(same_links(b,expected[i]),'endpoint '..i..' changed unexpectedly')end
 end)
 restore_link_fixture(s)
 assert(ok,why)
 result.restored=true
elseif request.op=='resize_setup' then
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
elseif request.op=='resize_transfer_prepare' then
 local recipient=assert(df.building.find(request.id));local donor
 for _,candidate in ipairs(df.global.world.buildings.other.STOCKPILE)do
  if candidate.id~=recipient.id and candidate.z==recipient.z and #candidate.storage.container_item_id>0 then
   local usable=true
   if request.case:find('create',1,true)then
    local first_y,last_y=candidate.y1,candidate.y2;local x=candidate.x1-1
    if request.case:find('partial',1,true)then x=candidate.storage.container_x[0]-1;first_y=candidate.storage.container_y[0];last_y=first_y end
    for y=first_y,last_y do
     local block=dfhack.maps.getTileBlock(x,y,candidate.z)
     if not block or block.designation[x%16][y%16].pile or block.occupancy[x%16][y%16].building~=0 then usable=false;break end
    end
   end
   if usable then donor=candidate;break end
  end
 end
 assert(donor,'missing stocked donor')
 local spans={}
 if request.case:find('partial',1,true) then spans={{x=donor.storage.container_x[0],y=donor.storage.container_y[0],length=1}}
 else for y=donor.y1,donor.y2 do spans[#spans+1]={x=donor.x1,y=y,length=donor.x2-donor.x1+1}end end
 if request.case:find('create',1,true) then
  for _,span in ipairs(spans)do
   span.x=span.x-1;span.length=span.length+1
   local block=assert(dfhack.maps.getTileBlock(span.x,span.y,donor.z))
   assert(not block.designation[span.x%16][span.y%16].pile and block.occupancy[span.x%16][span.y%16].building==0,'creation anchor occupied')
  end
 end
 local cells={}
 for y=donor.y1,donor.y2 do for x=donor.x1,donor.x2 do
  if dfhack.buildings.containsTile(donor,x,y)then
   local transferred=false;for _,span in ipairs(spans)do if span.y==y and x>=span.x and x<span.x+span.length then transferred=true end end
   cells[#cells+1]={x=x,y=y,transferred=transferred}
  end
 end end
 _G.df3d_transfer_check={recipient=recipient.id,donor=donor.id,before=snapshot(donor),recipient_before=snapshot(recipient),cells=cells}
 result.spans=spans;result.donor=donor.id
elseif request.op=='resize_transfer_unchanged' then
 local s=assert(_G.df3d_transfer_check)
 assert(json.encode(snapshot(assert(df.building.find(s.donor))))==json.encode(s.before),'erase changed other pile')
 assert(json.encode(snapshot(assert(df.building.find(s.recipient))))==json.encode(s.recipient_before),'outside erase changed selected pile')
elseif request.op=='resize_transfer_malformed' then
 local s=assert(_G.df3d_transfer_check);local b=assert(df.building.find(s.donor))
 s.recipient_before=snapshot(assert(df.building.find(s.recipient)))
 s.last_y=b.storage.container_y[#b.storage.container_y-1];b.storage.container_y:erase(#b.storage.container_y-1)
elseif request.op=='resize_transfer_restore' then
 local s=assert(_G.df3d_transfer_check);local b=assert(df.building.find(s.donor))
 b.storage.container_y:insert('#',s.last_y)
 assert(json.encode(snapshot(b))==json.encode(s.before),'refusal changed donor')
 assert(json.encode(snapshot(assert(df.building.find(s.recipient))))==json.encode(s.recipient_before),'refusal changed recipient')
elseif request.op=='resize_transfer_check' then
 local s=assert(_G.df3d_transfer_check);local recipient=assert(df.building.find(request.id or s.recipient));local donor=df.building.find(s.donor)
 local retained,transferred=0,0
 for _,cell in ipairs(s.cells)do
  assert(dfhack.buildings.containsTile(recipient,cell.x,cell.y)==cell.transferred,'wrong recipient ownership')
  if cell.transferred then transferred=transferred+1 else retained=retained+1 end
  assert((donor and dfhack.buildings.containsTile(donor,cell.x,cell.y) or false)==not cell.transferred,'wrong donor ownership')
 end
 assert((donor~=nil)==(retained>0),'empty donor was not deleted')
 for _,item in ipairs(s.before.containers)do
  local ref=assert(df.item.find(item.id)):getStockpile2();local moved=false
  for _,cell in ipairs(s.cells)do if cell.x==item.x and cell.y==item.y then moved=cell.transferred;break end end
  assert(ref and ref.id==(moved and -1 or s.donor) and ref.x==(moved and -30000 or item.x) and ref.y==(moved and -30000 or item.y),'wrong donor item assignment')
 end
 if donor then
  local current=snapshot(donor)
  for i,v in ipairs(current.limits)do assert(v==math.min(s.before.limits[i],retained),'donor limit not clamped')end
  result.donor=current
 end
 result.transferred=transferred;result.retained=retained;result.recipient=snapshot(recipient)
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
 assert(b.centerx==(b.x1+b.x2)//2 and b.centery==(b.y1+b.y2)//2,'growth center differs from native midpoint')
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
  assert(b.centerx==(b.x1+b.x2)//2 and b.centery==(b.y1+b.y2)//2,'creation center differs from native midpoint')
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
