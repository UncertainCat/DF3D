-- Depot preparation only. DF owns caravan negotiation and hauling execution.
-- No native item/building pointers survive an update; scans retain only value rows.
local scan
local function text(v,limit)
 local s=dfhack.df2utf(tostring(v or ''))
 if #s<=limit then return s end
 local n=limit;while n>0 and s:byte(n+1)>=128 and s:byte(n+1)<192 do n=n-1 end
 return s:sub(1,n)
end
local function ready(d)
 if d:getBuildStage()<d:getMaxBuildStage() then return false end
 for _,j in ipairs(d.jobs) do if j.job_type==df.job_type.DestroyBuilding then return false end end
 return true
end
local function revision(d)
 return (d.id+1)*16+(d.trade_flags.trader_requested and 8 or 0)+(d.trade_flags.anyone_can_trade and 4 or 0)+(ready(d) and 2 or 0)+1
end
local function depot_row(d)
 local r={id=d.id,x=d.centerx,y=d.centery,z=d.z,revision=revision(d),requested=d.trade_flags.trader_requested,
 anyone=d.trade_flags.anyone_can_trade,accessible=d.accessible,ready=ready(d),broker='',hauling=0,goods=0}
 for _,j in ipairs(d.jobs) do
  if j.job_type==df.job_type.BringItemToDepot then r.hauling=r.hauling+1 end
  if j.job_type==df.job_type.TradeAtDepot then
   local u=dfhack.job.getWorker(j)
   r.broker=u and text(dfhack.units.getReadableName(u),512) or 'Awaiting trader'
  end
 end
 for _,v in ipairs(d.contained_items) do
  if v.item and v.item.flags.in_building and v.use_mode==df.building_item_role_type.TEMP then r.goods=r.goods+1 end
 end
 return r
end
local function depots()
 local rows={}
 for _,d in ipairs(df.global.world.buildings.other.TRADE_DEPOT) do
  if #rows>=64 then break end
  rows[#rows+1]=depot_row(d)
 end
 return rows
end
local function caravans()
 local rows={}
 for i,c in ipairs(df.global.plotinfo.caravans) do
  if #rows>=64 then break end
  local e=df.historical_entity.find(c.entity)
  rows[#rows+1]={id=i,name=e and text(dfhack.translation.translateName(e.name,true),512) or ('Civilization '..c.entity),
   state=text(df.caravan_state.T_trade_state[c.trade_state] or 'Unknown',128),days_remaining=math.max(0,math.floor(c.time_remaining/120))}
 end
 return rows
end
local function eligible(item,d)
 local f=item.flags
 if f.removed or f.murder or f.garbage_collect or f.trader or f.hostile or f.forbid or f.in_inventory or f.in_building or f.construction or f.on_fire then return false end
 if not dfhack.items.canTradeWithContents(item) then return false end
 local p=xyz2pos(dfhack.items.getPosition(item))
 if not p or not dfhack.maps.isValidTilePos(p) then return false end
 local designation=dfhack.maps.getTileFlags(p)
 return designation and not designation.hidden and dfhack.maps.canWalkBetween(p,xyz2pos(d.centerx,d.centery,d.z))
end
return function(request)
 if request.action>=43 then return {ok=false,message="Native trade exchange adapter retired"} end
 local a=request.trade
 local result={ok=true,message='Trade depots',depots={},caravans={},goods={},next_cursor=0,selected_depot=a.depot_id,
 detail='Caravan offers and negotiations are not available yet.'}
 if #df.global.world.buildings.other.TRADE_DEPOT>64 or #df.global.plotinfo.caravans>64 then result.detail=result.detail..' Showing the first 64 depots/caravans.' end
 if request.action==38 then result.depots=depots();result.caravans=caravans();return result end
 local d=df.building.find(a.depot_id)
 if not d or not df.building_tradedepotst:is_instance(d) then return {ok=false,message='Trade depot no longer exists'} end
 if request.action==40 then
  if a.expected_revision~=revision(d) then return {ok=false,message='Depot settings changed; refresh before editing'} end
  if not ready(d) then return {ok=false,message='Depot is incomplete or being removed'} end
  if a.requested~=-1 then
   d.trade_flags.trader_requested=a.requested==1
   if a.requested==0 then
    -- Same cancellation used by DFHack caravan dismissal. Copy references before erasing;
    -- all references are local to this one suspended native update.
    local jobs={};for _,j in ipairs(d.jobs) do if j.job_type==df.job_type.TradeAtDepot then jobs[#jobs+1]=j end end
    for _,j in ipairs(jobs) do dfhack.job.removeJob(j) end
   end
  end
  if a.anyone~=-1 then d.trade_flags.anyone_can_trade=a.anyone==1 end
  result.message='Depot settings updated'
 elseif request.action==42 then
  local item=df.item.find(a.item_id)
  if not ready(d) or not item or not eligible(item,d) then return {ok=false,message='Depot or selected goods are no longer available for trade hauling'} end
  if not dfhack.items.markForTrade(item,d) then return {ok=false,message='DF could not create the trade hauling job'} end
  result.message='Bring-to-depot job created; dwarves will haul when the game runs'
 elseif request.action==41 then
  if not ready(d) then return {ok=false,message='Complete the depot before bringing goods'} end
  local source=df.global.world.items.other.IN_PLAY
  if not scan or scan.seq~=request.seq then scan={seq=request.seq,index=a.cursor,rows={},seen={}} end
  local stop=math.min(#source,scan.index+256)
  while scan.index<stop and #scan.rows<64 do
   local item=source[scan.index];scan.index=scan.index+1
   if item and not scan.seen[item.id] and eligible(item,d) then
    scan.seen[item.id]=true
    local description=text(dfhack.items.getDescription(item,0,true),512)
    if a.query=='' or description:lower():find(a.query:lower(),1,true) then
     scan.rows[#scan.rows+1]={id=item.id,description=description,quantity=math.max(1,item:getStackSize())}
    end
   end
  end
  if scan.index<#source and #scan.rows<64 then return {ok=true,pending=true,message='Finding available trade goods'} end
  -- Revalidate retained IDs after the bounded scan, because DF can move items meanwhile.
  for _,row in ipairs(scan.rows) do local item=df.item.find(row.id);if item and eligible(item,d) then result.goods[#result.goods+1]=row end end
  result.next_cursor=scan.index<#source and scan.index or 0
  scan=nil
  result.message='Available goods (whole items and containers)'
 end
 result.depots={depot_row(d)};result.caravans=caravans()
 return result
end
