-- Native trade entry oracle only; synthetic paused prerequisites, never runtime inputs.
local out,view,b,capture,select_map=...
local gui=require('gui');local json=require('json');local gps=df.global.gps
local main=df.global.game.main_interface;local trade=main.trade
local caravans=df.global.plotinfo.caravans;local count=#caravans
local frame=df.global.world.frame_counter;local flags=b.trade_flags.whole
assert(#b.jobs==0 and not trade.open and count==0)
local unit
for _,candidate in ipairs(df.global.world.units.active)do if dfhack.units.isCitizen(candidate) and candidate.status.current_soul and not candidate.flags1.caged and not candidate.flags1.rider then unit=candidate;break end end
assert(unit)
local position={x=unit.pos.x,y=unit.pos.y,z=unit.pos.z};local unit_flags=unit.flags1.whole;local old_job=unit.job.current_job
local job=df.job:new();job.job_type=df.job_type.TradeAtDepot
local ref=df.general_ref_unit_workerst:new();ref.unit_id=unit.id;job.general_refs:insert('#',ref)
local restore_item
local added_job=false;local added={};local result={depot=b.id,trader=unit.id,synthetic_prerequisites=true,cases={}}
local function click(x,y)
 gps.precise_mouse_x=x;gps.precise_mouse_y=y;gps.mouse_x=x//8;gps.mouse_y=(y-4)//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
end
local function caravan()
 local c=df.caravan_state:new();c.entity=df.global.plotinfo.main.fortress_entity.id;c.trade_state=df.caravan_state.T_trade_state.AtDepot;c.time_remaining=1200
 caravans:insert('#',c);added[#added+1]=c
end
local function record(label)
 view:render(dfhack.getTickCount());capture('depot-trade-'..label)
 local row={label=label,open=trade.open,choosing=trade.choosing_merchant,merchants=#trade.merlist,title=dfhack.df2utf(trade.title),talker=dfhack.df2utf(trade.talker),fortname=dfhack.df2utf(trade.fortname),place=dfhack.df2utf(trade.place),stillunloading=trade.stillunloading,havetalker=trade.havetalker,fortress_trader=trade.fortress_trader and trade.fortress_trader.id or -1,merchant_trader=trade.merchant_trader and trade.merchant_trader.id or -1,talkline=trade.talkline,goods={#trade.good[0],#trade.good[1]},lines={}}
 for y=0,gps.dimy-1 do local line={};for x=0,gps.dimx-1 do local c=dfhack.screen.readTile(x,y).ch;line[#line+1]=c>=32 and c<=255 and string.char(c)or' 'end;row.lines[#row.lines+1]=dfhack.df2utf(table.concat(line)):gsub('%s+$','')end
 if os.getenv('DF3D_DEPOT_TRADE_PROVIDER')=='1' and trade.open and not trade.choosing_merchant then
  local goods={};for _,id in ipairs(added[1].goods)do goods[#goods+1]=id end
  local active=main.view_sheets.active_id;local lists=trade.buildlists;local appraisal=trade.handle_appraisal
  for iteration=1,2 do
   local output,code=dfhack.run_command_silent('df3d','trade-entry-probe',tostring(b.id),'0');assert(code==0,output)
   local facts=json.decode(output);assert(facts.available,output)
   for _,key in ipairs{'title','talker','fortname','place','stillunloading','havetalker','fortress_trader','merchant_trader','talkline'}do assert(facts[key]==row[key],'Owned trade initializer differs: '..key)end
   assert(facts.entity==added[1].entity)
   local after={};for _,id in ipairs(added[1].goods)do after[#after+1]=id end
   assert(json.encode(after)==json.encode(goods) and main.view_sheets.active_id==active and trade.buildlists==lists and trade.handle_appraisal==appraisal and trade.title==dfhack.utf2df(row.title) and #trade.good[0]==row.goods[1] and #trade.good[1]==row.goods[2])
   row.provider=facts
  end
 end
 result.cases[#result.cases+1]=row
 assert(df.global.world.frame_counter==frame and unit.flags1.whole==unit_flags and unit.job.current_job==old_job and b.trade_flags.whole==flags)
 return row
end

local function gate_scene(label,worker)
 if os.getenv('DF3D_DEPOT_TRADE_SCENE')~='1' then return end
 view:render(dfhack.getTickCount());capture('depot-trade-gate-'..label)
 local selected=main.view_sheets.active_id;local jobs=#b.jobs
 local file=assert(io.open(out..'/depot-wire-expected.json','w'));file:write(json.encode{id=b.id,trade_worker=worker,reference='depot-trade-gate-'..label});file:close()
 capture('depot-scene-gate-'..label)
 file=assert(io.open(out..'/depot-scene-gate-'..label..'-result.json'));local observed=json.decode(file:read('*a'));file:close()
 assert(observed.success and main.view_sheets.active_id==selected and not trade.open and #b.jobs==jobs and df.global.world.frame_counter==frame)
 result.gate_scene=result.gate_scene or {};result.gate_scene[#result.gate_scene+1]={label=label,worker=worker,success=true}
end
local ok,err=xpcall(function()
 caravan();select_map(b);click(480,190)
 assert(not trade.open,'Trade opened without a trader');record('no-trader');gate_scene('absent',-1)
 if os.getenv('DF3D_DEPOT_TRADE_PROVIDER')=='1' then
  local output,code=dfhack.run_command_silent('df3d','trade-entry-probe',tostring(b.id),'0');assert(code==0 and not json.decode(output).available,'Missing trader must reject')
 end
 b.jobs:insert('#',job);added_job=true;unit.pos.x=b.centerx;unit.pos.y=b.centery;unit.pos.z=b.z
 local output,code=dfhack.run_command_silent('df3d','depot-settings-probe',tostring(b.id));assert(code==0,output)
 local facts=json.decode(output);assert(facts.worker==unit.id,'Native trader lookup: '..output)
 if os.getenv('DF3D_DEPOT_TRADE_PROVIDER')=='1' then
  local invalid,code=dfhack.run_command_silent('df3d','trade-entry-probe',tostring(b.id),'100');assert(code==0 and not json.decode(invalid).available,'Foreign caravan must reject')
 end
 gate_scene('present',unit.id)
 if os.getenv('DF3D_DEPOT_TRADE_LISTS')=='1' then
  local item=df.item.find(296);assert(item and item.flags.on_ground and not item.flags.in_inventory and not item.flags.trader)
  local pos={x=item.pos.x,y=item.pos.y,z=item.pos.z};local flags=item.flags.whole;local contained=#b.contained_items
  restore_item=function()
   item.flags.in_building=false;assert(dfhack.items.moveToGround(item,pos));item.flags.whole=flags
   assert(#b.contained_items==contained);restore_item=nil
  end
  assert(dfhack.items.moveToBuilding(item,b,0,true));assert(#added[1].goods==0)
  result.list_item=item.id
 end
 assert(main.view_sheets.active_id==b.id,'Depot selection lost before Trade');click(480,190);assert(trade.open and not trade.choosing_merchant,'Trade did not open: '..output)
 local single=record('single');assert(single.fortress_trader==unit.id and single.merchants==1)
 if restore_item then
  assert(#trade.good[0]==0 and #trade.good[1]==1 and trade.good[1][0].id==result.list_item,'Native own-goods membership differs')
  assert(#added[1].goods==1 and added[1].goods[0]==result.list_item,'Native rendering did not record inspected own item')
  result.list_initial={own_id=trade.good[1][0].id,appraised_id=added[1].goods[0],buildlists=trade.buildlists,handle_appraisal=trade.handle_appraisal}
  view:render(dfhack.getTickCount());view:render(dfhack.getTickCount());assert(#added[1].goods==1)
 end
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());assert(not trade.open)
 if restore_item then
  unit.pos.x=position.x;unit.pos.y=position.y;unit.pos.z=position.z;select_map(b)
  unit.pos.x=b.centerx;unit.pos.y=b.centery;unit.pos.z=b.z;click(480,190)
  assert(trade.open and #trade.good[1]==1 and trade.good[1][0].id==result.list_item and #added[1].goods==1)
  record('reopened');result.list_initial.reopen_deduplicated=true
  gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());assert(not trade.open)
  restore_item()
 end
 caravan();unit.pos.x=position.x;unit.pos.y=position.y;unit.pos.z=position.z
 select_map(b);assert(main.view_sheets.active_id==b.id)
 unit.pos.x=b.centerx;unit.pos.y=b.centery;unit.pos.z=b.z
 click(480,190);assert(trade.open and trade.choosing_merchant)
 local multiple=record('merchants');assert(multiple.merchants==2)
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());assert(not trade.open)
end,debug.traceback)
if trade.open then gui.simulateInput(view,'LEAVESCREEN')end
if restore_item then restore_item()end
if added_job then b.jobs:erase(#b.jobs-1)end
unit.pos.x=position.x;unit.pos.y=position.y;unit.pos.z=position.z
job.general_refs:erase(0);ref:delete();job:delete()
for i=#added,1,-1 do caravans:erase(#caravans-1);added[i]:delete()end
assert(#caravans==count and #b.jobs==0 and df.global.world.frame_counter==frame and b.trade_flags.whole==flags)
if not ok then error(err)end
result.success=true;result.restored=true
local file=assert(io.open(out..'/depot-trade-native.json','w'));file:write(json.encode(result));file:close()
return result
