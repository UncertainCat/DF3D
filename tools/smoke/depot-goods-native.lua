-- Diagnostic-only native menu oracle in a paused disposable save.
local out,view,b,capture=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local caravans=df.global.plotinfo.caravans
local frame=df.global.world.frame_counter
local caravan=df.caravan_state:new()
caravan.entity=df.global.plotinfo.main.fortress_entity.id
caravan.trade_state=df.caravan_state.T_trade_state.Approaching
caravan.time_remaining=1200
local index=#caravans;caravans:insert('#',caravan)
local menu=df.global.game.main_interface.assign_trade
assert(not menu.open and #b.jobs==0)
local result={id=b.id,synthetic_caravan=true,frame=frame}
local ok,err=xpcall(function()
 view:render(dfhack.getTickCount());capture('depot-goods-available')
 g.precise_mouse_x=520;g.precise_mouse_y=166;g.mouse_x=65;g.mouse_y=13
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
 assert(menu.open and menu.trade_depot_bld.id==b.id,'Goods click did not open native picker')
 capture('depot-goods-initial')
 result.types={};for _,v in ipairs(menu.type_list)do result.types[#result.types+1]=v end
 result.current_type=menu.current_type
 result.sort_by_distance=menu.sort_by_distance;result.pending_on_top=menu.pending_on_top;result.exclude_prohib=menu.exclude_prohib
 result.items={}
 for _,row in ipairs(menu.master_i_list.tgi)do result.items[#result.items+1]={id=row.it.id,distance=row.dist,tag=row.tag,prohibited=row.prohibited,value=row.value,sort_value=row.sort_value}end
 if os.getenv('DF3D_DEPOT_DISTANCE_NATIVE')=='1' then
  local output,code=dfhack.run_command_silent('df3d','depot-distance-probe',tostring(b.id));assert(code==0,output)
  local facts=json.decode(output);assert(facts.restored)
  local by_id={};for _,row in ipairs(facts.rows)do by_id[row.id]=row.distance end
  for _,row in ipairs(result.items)do assert(by_id[row.id]==row.distance,'Native distance differs for item '..row.id..': '..tostring(by_id[row.id])..' vs '..row.distance)end
  assert(#facts.available==#result.items,'Native unassigned count differs')
  for i,row in ipairs(result.items)do assert(row.tag==0 and facts.available[i]==row.id,'Native unassigned order differs at '..i)end
  assert(menu.open and menu.trade_depot_bld.id==b.id and #menu.master_i_list.tgi==#result.items and menu.current_type==result.current_type)
  result.distance_provider={matched=#result.items,observed=#facts.rows,unassigned_matched=#facts.available,search_storage_restored=facts.restored}
 end
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
 assert(not menu.open,'Goods Escape failed')
end,debug.traceback)
if menu.open then gui.simulateInput(view,'LEAVESCREEN')end
caravans:erase(index);caravan:delete()
assert(df.global.world.frame_counter==frame and #b.jobs==0)
if not ok then error(err)end
result.success=true
local f=assert(io.open(out..'/depot-goods-native.json','w'));f:write(json.encode(result));f:close()
return result
