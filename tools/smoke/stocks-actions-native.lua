-- Owned, paused clone only. Compare native group clicks with semantic intents.
local view,result,probe=...
local gui=require('gui');local json=require('json');local stocks=df.global.game.main_interface.stocks
assert(stocks.current_type==39 and stocks.item_filter=='')
local individual=os.getenv('DF3D_STOCKS_ITEM_ACTIONS')=='1'
local initial=probe('stocks-selection-probe','39','');local group=initial.groups[1]
assert(group.flags==240,'Action fixture requires an unmarked eligible first group')
local function click(x)
 local gps=df.global.gps;gps.precise_mouse_x=x;gps.precise_mouse_y=individual and 166 or 130;gps.mouse_x=x//8;gps.mouse_y=gps.precise_mouse_y//12
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
end
local function snapshot()
 local state={items={},melt={}}
 for _,item in ipairs(df.global.world.items.other.IN_PLAY)do local id=item.id
  state.items[#state.items+1]={id=id,flags=item.flags.whole,countdown=item.stockpile_countdown,delay=item.stockpile_delay}
 end
 for _,item in ipairs(df.global.world.items.other.ANY_MELT_DESIGNATED)do state.melt[#state.melt+1]=item.id end
 return state
end
local function restore(state)
 assert(json.encode(snapshot().melt)==json.encode(state.melt),'Melt registration did not restore')
 for _,row in ipairs(state.items)do local item=df.item.find(row.id)
  item.flags.whole=row.flags;item.stockpile_countdown=row.countdown;item.stockpile_delay=row.delay
 end
end
local function edit(action,want,revision,subtype,target)
 local text,code=dfhack.run_command_silent('df3d',individual and 'stocks-item-edit-probe' or 'stocks-group-edit-probe','39',tostring(subtype or group.subtype),tostring(group.subcat1),tostring(group.subcat2),action,want and '1' or '0',revision,'owned-test',table.unpack(individual and {tostring(target or group.ids[1])} or {}))
 assert(code==0,text);return json.decode(text)
end
local original=snapshot();local observations={}
if individual then result.item_actions=observations else result.group_actions=observations end
for _,action in ipairs{{'forbid',844},{'dump',868},{'melt',892},{'hidden',916}}do
 local name,x=table.unpack(action);local before=snapshot()
 click(x);local native_on=snapshot();click(x);local native_off=snapshot()
 assert(json.encode(native_on)~=json.encode(before),'Native action did nothing: '..name)
 restore(before)
 local fresh=probe('stocks-selection-probe','39','').groups[1]
 local stale=edit(name,true,'1');assert(stale.outcome==2 and stale.changed==0,'Stale action accepted')
 local missing=edit(name,true,fresh.revision,32767);assert(missing.outcome==2 and missing.changed==0,'Missing group accepted')
 if individual then
  local foreign=edit(name,true,fresh.revision,nil,initial.groups[2].ids[1]);assert(foreign.outcome==2 and foreign.changed==0,'Foreign item accepted')
 end
 assert(json.encode(snapshot())==json.encode(before),'Rejected action mutated items')
 local enabled=edit(name,true,fresh.revision);assert(enabled.outcome==1 and enabled.receipt,'Group action failed')
 assert(json.encode(snapshot())==json.encode(native_on),'Native enabled effects differ: '..name)
 local repeated=edit(name,true,fresh.revision);assert(repeated.outcome==2 and repeated.changed==0,'Old action revision replayed')
 assert(json.encode(snapshot())==json.encode(native_on),'Stale replay changed items')
 fresh=probe('stocks-selection-probe','39','').groups[1]
 local disabled=edit(name,false,fresh.revision);assert(disabled.outcome==1 and disabled.receipt,'Group clear failed')
 assert(json.encode(snapshot())==json.encode(native_off),'Native disabled effects differ: '..name)
 restore(before)
 observations[#observations+1]={action=name,native_on=native_on,native_off=native_off,enabled=enabled,disabled=disabled,stale_rejected=true,missing_rejected=true,replay_rejected=true}
end
restore(original);assert(json.encode(snapshot())==json.encode(original),'Original action state not restored')
