-- Native Stocks shared item-selector reference; discovery only.
local out,view,stocks=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local rows={};local g=df.global.gps
-- Pair captured artwork with independently readable simulation facts. Keep
-- this diagnostic bounded; the ids vector still records the complete list.
local function appearance_facts(item)
 local row={id=item.id,quality=item:getQuality(),wear=item:getWear(),flags=item.flags.whole,
  material=item:getMaterial(),material_index=item:getMaterialIndex(),contents={}}
 for _,ref in ipairs(item.general_refs)do
  local kind=ref:getType()
  if kind==df.general_ref_type.BUILDING_HOLDER then
   local building=ref:getBuilding()
   if building then
    row.building={id=building.id,type=building:getType()}
    if df.building_floodgatest:is_instance(building)then row.building.gate_flags=building.gate_flags.whole end
    if df.building_doorst:is_instance(building)then row.building.door_flags=building.door_flags.whole;row.building.close_timer=building.close_timer end
   end
  elseif kind==df.general_ref_type.CONTAINS_ITEM then
   local child=ref:getItem()
   if child then row.contents[#row.contents+1]={id=child.id,type=child:getType(),material=child:getMaterial(),material_index=child:getMaterialIndex()}end
  end
 end
 return row
end
local kinds=os.getenv('DF3D_STOCKS_EQUIPMENT_ART')=='1' and {24,25,26,27,28,29,60} or {0,2,4,5,30,32}
if os.getenv('DF3D_STOCKS_HOUSEHOLD_ART')=='1' then kinds={6,7,10,11,12,18,22,45}end
if os.getenv('DF3D_STOCKS_EXTENDED_ART')=='1' then kinds={23,46,55,69,70,72,74,87}end
if os.getenv('DF3D_STOCKS_DOOR_STATES')=='1' then kinds={6}end
local function capture(name)
 local f=assert(io.open(out..'/shot.tmp','w'));f:write(name);f:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local deadline=dfhack.getTickCount()+10000
 while true do local ack=io.open(out..'/ack-'..name);if ack then ack:close();break end;assert(dfhack.getTickCount()<deadline,'Stocks art capture timeout');script.sleep(1,'frames')end
end
for _,kind in ipairs(kinds)do
 local found=false
 for index,value in ipairs(stocks.filtered_type_list)do if value==kind then stocks.scroll_position_type=index;found=true;break end end
 assert(found,'Missing Stocks art category '..kind);view:render(dfhack.getTickCount())
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=100;g.precise_mouse_y=94;g.mouse_x=12;g.mouse_y=7
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 assert(stocks.current_type==kind,'Stocks art category click failed')
 stocks.scroll_position_type=0;stocks.scroll_position_item=0
 if os.getenv('DF3D_STOCKS_EXTENDED_ART')=='1' and #stocks.current_type_a_expanded>0 and not stocks.current_type_a_expanded[0] then
  view:render(dfhack.getTickCount());g.precise_mouse_x=500;g.precise_mouse_y=130;g.mouse_x=62;g.mouse_y=10
  gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 end
 g.precise_mouse_x=0;g.precise_mouse_y=0;g.mouse_x=0;g.mouse_y=0
 gui.simulateInput(view,{});view:render(dfhack.getTickCount())
 local ids,facts={},{};for _,item in ipairs(stocks.current_type_i_list)do
  ids[#ids+1]=item.id
  if #facts<128 then facts[#facts+1]=appearance_facts(item)end
 end
 rows[#rows+1]={category=kind,ids=ids,appearance_facts=facts}
 capture('stocks-art-'..kind)
 if os.getenv('DF3D_STOCKS_DOOR_STATES')=='1' then
  local f=assert(io.open(out..'/stocks-door-states.json'));local reference=json.decode(f:read('*a'));f:close()
  for _,case in ipairs(reference.cases)do
   stocks.scroll_position_item=case.row_index*3;view:render(dfhack.getTickCount())
   capture('stocks-door-state-'..case.id)
  end
  stocks.scroll_position_item=0
 end
end
return rows
