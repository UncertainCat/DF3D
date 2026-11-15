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
 result.cases[#result.cases+1]=row
 assert(df.global.world.frame_counter==frame and unit.flags1.whole==unit_flags and unit.job.current_job==old_job and b.trade_flags.whole==flags)
 return row
end
local ok,err=xpcall(function()
 caravan();select_map(b);click(480,190)
 assert(not trade.open,'Trade opened without a trader');record('no-trader')
 b.jobs:insert('#',job);added_job=true;unit.pos.x=b.centerx;unit.pos.y=b.centery;unit.pos.z=b.z
 local output,code=dfhack.run_command_silent('df3d','depot-settings-probe',tostring(b.id));assert(code==0,output)
 local facts=json.decode(output);assert(facts.worker==unit.id,'Native trader lookup: '..output)
 assert(main.view_sheets.active_id==b.id,'Depot selection lost before Trade');click(480,190);assert(trade.open and not trade.choosing_merchant,'Trade did not open: '..output)
 local single=record('single');assert(single.fortress_trader==unit.id and single.merchants==1)
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());assert(not trade.open)
 caravan();unit.pos.x=position.x;unit.pos.y=position.y;unit.pos.z=position.z
 select_map(b);assert(main.view_sheets.active_id==b.id)
 unit.pos.x=b.centerx;unit.pos.y=b.centery;unit.pos.z=b.z
 click(480,190);assert(trade.open and trade.choosing_merchant)
 local multiple=record('merchants');assert(multiple.merchants==2)
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());assert(not trade.open)
end,debug.traceback)
if trade.open then gui.simulateInput(view,'LEAVESCREEN')end
if added_job then b.jobs:erase(#b.jobs-1)end
unit.pos.x=position.x;unit.pos.y=position.y;unit.pos.z=position.z
job.general_refs:erase(0);ref:delete();job:delete()
for i=#added,1,-1 do caravans:erase(#caravans-1);added[i]:delete()end
assert(#caravans==count and #b.jobs==0 and df.global.world.frame_counter==frame and b.trade_flags.whole==flags)
if not ok then error(err)end
result.success=true;result.restored=true
local file=assert(io.open(out..'/depot-trade-native.json','w'));file:write(json.encode(result));file:close()
return result
