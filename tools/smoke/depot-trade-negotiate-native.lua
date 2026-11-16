-- Disposable paused differential oracle; runtime never snapshots or rewinds RNG.
local view,trade,click,capture,out=...
local json=require('json');local utils=require('utils')
local base=dfhack.internal.getImageBase()
local function rng()
 local context=df.reinterpret_cast('int16_t',base+0x2159084).value;assert(context>=0 and context<16)
 local r={context=context,cursor=df.reinterpret_cast('uint32_t',base+0x2131b30+context*4).value,words={}}
 for i=0,623 do r.words[i+1]=df.reinterpret_cast('uint32_t',base+0x234e990+context*0x9c0+i*4).value end
 return r
end
local function set_rng(r)
 assert(df.reinterpret_cast('int16_t',base+0x2159084).value==r.context)
 df.reinterpret_cast('uint32_t',base+0x2131b30+r.context*4).value=r.cursor
 for i,v in ipairs(r.words)do df.reinterpret_cast('uint32_t',base+0x234e990+r.context*0x9c0+(i-1)*4).value=v end
end
local sf={'rating','experience','unused_counter','rusty','rust_counter','demotion_counter','natural_skill_lvl'}
local af={'value','max_value','improve_counter','unused_counter','soft_demotion','rust_counter','demotion_counter'}
local function fields(o,names)local r={};for _,n in ipairs(names)do r[n]=o[n]end;return r end
local function write(o,r)for k,v in pairs(r)do o[k]=v end end
local units={trade.merchant_trader,trade.fortress_trader}
local function people()
 local result={}
 for _,unit in ipairs(units)do local soul=assert(unit.status.current_soul);local r={skills={},mental={},physical={}}
  for _,s in ipairs(soul.skills)do local v=fields(s,sf);v.id=s.id;r.skills[#r.skills+1]=v end
  for i=0,12 do r.mental[i+1]=fields(soul.mental_attrs[i],af)end
  for i=0,5 do r.physical[i+1]=fields(unit.body.physical_attrs[i],af)end
  result[#result+1]=r
 end
 return result
end
local function restore_people(rows)
 for i,unit in ipairs(units)do local soul=unit.status.current_soul;local r=rows[i];local kept={}
  for _,v in ipairs(r.skills)do kept[v.id]=true;local s
   for _,candidate in ipairs(soul.skills)do if candidate.id==v.id then s=candidate;break end end
   if not s then s=df.unit_skill:new();s.id=v.id;utils.insert_sorted(soul.skills,s,'id')end;write(s,v)
  end
  for j=#soul.skills-1,0,-1 do local s=soul.skills[j];if not kept[s.id]then soul.skills:erase(j);s:delete()end end
  for j=0,12 do write(soul.mental_attrs[j],r.mental[j+1])end
  for j=0,5 do write(unit.body.physical_attrs[j],r.physical[j+1])end
 end
end
local caravan=trade.mer
local function caravan_state()return {mood=caravan.mood,haggle_fail_count=caravan.haggle_fail_count,time_remaining=caravan.time_remaining,flags=caravan.flags.whole}end
local function restore_caravan(r)caravan.mood=r.mood;caravan.haggle_fail_count=r.haggle_fail_count;caravan.time_remaining=r.time_remaining;caravan.flags.whole=r.flags end
local original_rng=rng();local original_people=people();local original_caravan=caravan_state()
local mass={whole=caravan.total_capacity.whole,fraction=caravan.total_capacity.fraction};local line=trade.talkline
local result={}
local accept_mode=os.getenv('DF3D_DEPOT_TRADE_ACCEPT')
local ethics_mode=os.getenv('DF3D_DEPOT_TRADE_ETHICS')
local original_ethics={animal=trade.civ.resources.ethic.KILL_ANIMAL,plant=trade.civ.resources.ethic.KILL_PLANT}
assert(not ethics_mode or ethics_mode=='native' or ethics_mode=='session')
local active_okay=os.getenv('DF3D_DEPOT_TRADE_ACTIVE_OKAY')=='1'
assert(not accept_mode or accept_mode=='native' or accept_mode=='owned' or accept_mode=='session' or accept_mode=='wire')
local history={};for _,id in ipairs(caravan.goods)do history[#history+1]=id end
if accept_mode=='wire' or ethics_mode then
 -- Isolate negotiation from entry appraisal, which has separate live coverage.
 -- Record all current goods before the controlled native reference as well.
 local seen={};for _,id in ipairs(history)do seen[id]=true end
 for side=0,1 do for _,item in ipairs(trade.good[side])do if not seen[item.id]then caravan.goods:insert('#',item.id);seen[item.id]=true end end end
end
local tracked={};for side=0,1 do for _,item in ipairs(trade.good[side])do tracked[item.id]=item end end
local function goods()
 local sides={}
 for side=0,1 do local r={items={},flags={},amounts={},groups={},height=trade.i_height[side]}
  for i,item in ipairs(trade.good[side])do r.items[#r.items+1]=item.id;r.flags[#r.flags+1]=trade.goodflag[side][i].whole;r.amounts[#r.amounts+1]=trade.good_amount[side][i]end
  for i,kind in ipairs(trade.current_type_a_type[side])do r.groups[#r.groups+1]={type=kind,subtype=trade.current_type_a_subtype[side][i],expanded=trade.current_type_a_expanded[side][i],on=trade.current_type_a_on[side][i],flags=trade.current_type_a_flag[side][i].whole}end
  sides[#sides+1]=r
 end
 return sides
end
local function session_probe(action,...)
 local args={...};for i,v in ipairs(args)do args[i]=tostring(v)end
 local text,code=dfhack.run_command_silent('df3d','trade-session-probe',action,table.unpack(args));assert(code==0,text);return json.decode(text)
end
local function transfers()
 local rows={};for id,item in pairs(tracked)do
  local owners={};for _,ref in ipairs(item.general_refs)do if ref:getType()==df.general_ref_type.ENTITY_ITEMOWNER then owners[#owners+1]=ref.entity_id end end
  table.sort(owners);rows[#rows+1]={id=id,owners=owners,trader=item.flags.trader,owned=item.flags.owned,forbid=item.flags.forbid,stack=item:getStackSize()}
 end
 table.sort(rows,function(a,b)return a.id<b.id end)
 return {items=rows,times_used=trade.bld.times_used,import_value=caravan.import_value,export_value_total=caravan.export_value_total,export_value_personal=caravan.export_value_personal,offer_value=caravan.offer_value}
end
local ok,err=xpcall(function()
 if ethics_mode then
  result.ethics={mode=ethics_mode,cases={}}
  trade.civ.resources.ethic.KILL_ANIMAL=df.ethic_response.UNTHINKABLE
  trade.civ.resources.ethic.KILL_PLANT=df.ethic_response.UNTHINKABLE
  local bone,bin
  for _,item in ipairs(trade.good[1])do
   if item:getType()==df.item_type.CORPSEPIECE then bone=item end
   if item:getType()==df.item_type.BIN then bin=item end
  end
  assert(bone and bin,'Ethics fixture requires bone remains and a wooden bin')
  for _,test in ipairs{{'animal',true,false,19},{'plant',false,true,20},{'both',true,true,18}}do
   restore_people(original_people);restore_caravan(original_caravan)
   click(440,694);click(900,694);trade.talkline=line;trade.counter_offer=false;trade.counter_offer_item:resize(0)
   caravan.mood=100;caravan.haggle_fail_count=0;caravan.time_remaining=1200
   caravan.total_capacity.whole=100000;caravan.total_capacity.fraction=0
   for _,unit in ipairs(units)do for _,skill in ipairs(unit.status.current_soul.skills)do for _,field in ipairs(sf)do skill[field]=0 end end end
   local intents={{side=0,item=trade.good[0][0].id}};click(468,238)
   if test[2]then intents[#intents+1]={side=1,item=bone.id};click(932,310)end
   if test[3]then intents[#intents+1]={side=1,item=bin.id};click(932,382)end
   local output,code=dfhack.run_command_silent('df3d','trade-refusal-probe',tostring(trade.bld.id),'0','','',json.encode(intents))
   assert(code==0,output);local check=json.decode(output);assert(check.ethical and check.reply_base==test[4],output)
   local controlled=rng();controlled.cursor=0;for i=1,624 do controlled.words[i]=(i*104729)%2147483647 end;set_rng(controlled)
   local sample={label=test[1],before={people=people(),caravan=caravan_state(),rng=rng(),transfers=transfers()}}
   if ethics_mode=='native' then
    click(508,730);sample.dialogue=trade.talkline;capture('depot-trade-ethics-'..test[1])
   else
    local state=session_probe('open',trade.bld.id,0);assert(state.status==0,json.encode(state));local id=state.session
    for _,intent in ipairs(intents)do state=session_probe('item',id,state.revision,intent.side,intent.item);assert(state.status==0,json.encode(state))end
    local revision=state.revision;state=session_probe('exchange',id,revision)
    assert(state.status==0 and state.exchange_status==0,json.encode(state));sample.dialogue=state.dialogue
    local after_rng=rng();local after_people=people();local after_caravan=caravan_state()
    local refreshed=session_probe('read',id,state.revision);assert(refreshed.status==0 and refreshed.dialogue==state.dialogue,json.encode(refreshed))
    assert(session_probe('exchange',id,revision).exchange_status==1,'Stale ethical offer replayed')
    assert(json.encode(rng())==json.encode(after_rng) and json.encode(people())==json.encode(after_people) and json.encode(caravan_state())==json.encode(after_caravan),'Refusal refresh/rejection changed simulation')
    assert(session_probe('close',id).status==3);assert(trade.talkline==line,'Owned ethical refusal changed native menu')
   end
   sample.after={people=people(),caravan=caravan_state(),rng=rng(),transfers=transfers()}
   assert(sample.dialogue==test[4] and caravan.time_remaining<=501,'Ethical offer did not apply native refusal')
   assert(json.encode(sample.before.transfers)==json.encode(sample.after.transfers),'Ethical refusal transferred goods')
   result.ethics.cases[#result.ethics.cases+1]=sample
  end
  result.success=true;return
 end
 click(440,694);click(900,694)
 local anvil,bar
 for _,item in ipairs(trade.good[0])do if item:getType()==df.item_type.ANVIL then anvil=item;break end end
 for _,item in ipairs(trade.good[1])do if item:getType()==df.item_type.BAR then bar=item;break end end
 assert(anvil and bar,'Counteroffer fixture needs an anvil and populated bar bin')
 click(468,238);click(468,346);click(932,418)
 local intents={{side=0,item=trade.good[0][0].id},{side=0,item=anvil.id},{side=1,item=bar.id}}
 local facts,code=dfhack.run_command_silent('df3d','trade-projection-probe',tostring(trade.bld.id),'0','','',json.encode(intents))
 assert(code==0,facts);local values=json.decode(facts).value_totals.actual
 assert(values[1]>0 and values[2]>=values[1] and (values[2]-values[1])*100/values[1]<50,'Counteroffer fixture must offer under50% profit')
 for side=0,1 do
  local wanted={};for _,intent in ipairs(intents)do if intent.side==side then wanted[intent.item]=true end end
  for i,item in ipairs(trade.good[side])do assert(trade.goodflag[side][i].selected==not not wanted[item.id],'Unexpected selected fixture item');wanted[item.id]=nil end
  assert(next(wanted)==nil,'Fixture item absent')
 end
 result.values=values
 caravan.total_capacity.whole=100000;caravan.total_capacity.fraction=0;caravan.mood=100;caravan.haggle_fail_count=0
 for _,unit in ipairs(units)do for _,s in ipairs(unit.status.current_soul.skills)do for _,f in ipairs(sf)do s[f]=0 end end end
 view:render(dfhack.getTickCount())
 local initial_people=people();local initial_caravan=caravan_state();local controlled=rng();controlled.cursor=0;controlled.words[1]=2147483646;controlled.words[2]=0
 if accept_mode then for i=3,624 do controlled.words[i]=(i*104729)%2147483647 end end
 set_rng(controlled);click(508,730)
 assert(trade.counter_offer and #trade.counter_offer_item>0,'Controlled offer did not produce a native counteroffer: '..trade.talkline..'/'..tostring(trade.counter_offer)..'/'..#trade.counter_offer_item)
 result.native={dialogue=trade.talkline,items={},people=people(),caravan=caravan_state()}
 for _,item in ipairs(trade.counter_offer_item)do result.native.items[#result.native.items+1]=item.id end
 local native_rng=rng();capture('depot-trade-counteroffer')
 if os.getenv('DF3D_DEPOT_TRADE_LONG_COUNTER')=='1' then
  local saved={};for _,item in ipairs(trade.counter_offer_item)do saved[#saved+1]=item end
  local offset=trade.scroll_position_counter_offer
  trade.counter_offer_item:resize(0)
  for _,item in ipairs(trade.good[1])do trade.counter_offer_item:insert('#',item)end
  trade.scroll_position_counter_offer=0
  result.long_counter={count=#trade.counter_offer_item,goods_height=trade.i_height[1],steps={}}
  local function record_long(label)
   local g=df.global.gps;g.precise_mouse_x=0;g.precise_mouse_y=0;g.mouse_x=0;g.mouse_y=0
   view:render(dfhack.getTickCount());capture('depot-trade-long-counter-'..label)
   result.long_counter.steps[#result.long_counter.steps+1]={label=label,offset=trade.scroll_position_counter_offer}
  end
  record_long('initial');click(952,646);record_long('down');click(952,190);record_long('up')
  click(952,610);record_long('track')
  assert(result.long_counter.count==15 and result.long_counter.steps[2].offset==1 and result.long_counter.steps[3].offset==0 and result.long_counter.steps[4].offset==6,'Native counteroffer scroll behavior changed')
  local function point(x,y)
   local g=df.global.gps;g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
  end
  result.long_counter.inputs={}
  for _,probe in ipairs{{'body-wheel','CONTEXT_SCROLL_DOWN',600,300},{'bar-wheel','CONTEXT_SCROLL_DOWN',952,300},{'heading-wheel','CONTEXT_SCROLL_DOWN',600,160},{'outside-wheel','CONTEXT_SCROLL_DOWN',0,0},{'body-page','CONTEXT_SCROLL_PAGEDOWN',600,300},{'standard','STANDARDSCROLL_DOWN',600,300}}do
   trade.scroll_position_counter_offer=0;trade.scrolling_counter_offer=false;point(probe[3],probe[4]);view:render(dfhack.getTickCount())
   require('gui').simulateInput(view,probe[2]);view:render(dfhack.getTickCount())
   result.long_counter.inputs[#result.long_counter.inputs+1]={label=probe[1],offset=trade.scroll_position_counter_offer}
  end
  for _,y in ipairs{190,202,214,300,490,622,646}do
   trade.scroll_position_counter_offer=0;trade.scrolling_counter_offer=false;point(0,0);view:render(dfhack.getTickCount())
   point(952,220);df.global.enabler.mouse_lbut_lift=0;require('gui').simulateInput(view,{'_MOUSE_L','_MOUSE_L_DOWN'})
   point(952,y);require('gui').simulateInput(view,{'_MOUSE_L_DOWN'})
   result.long_counter.inputs[#result.long_counter.inputs+1]={label='drag-'..y,offset=trade.scroll_position_counter_offer,held=trade.scrolling_counter_offer}
   df.global.enabler.mouse_lbut_lift=1;require('gui').simulateInput(view,{})
   result.long_counter.inputs[#result.long_counter.inputs].released=not trade.scrolling_counter_offer
  end
  trade.counter_offer_item:resize(0);for _,item in ipairs(saved)do trade.counter_offer_item:insert('#',item)end
  trade.scroll_position_counter_offer=offset;trade.scrolling_counter_offer=false
  view:render(dfhack.getTickCount())
 end
 if os.getenv('DF3D_DEPOT_TRADE_RESIZE')=='1' then
  result.resize={};local script=require('gui.script');local g=df.global.gps
  for _,size in ipairs{'minimum','small','wide','default'}do
   local request=assert(io.open(out..'/owner-input-request.tmp','w'));request:write('name-resize-'..size);request:close();assert(os.rename(out..'/owner-input-request.tmp',out..'/owner-input-request'))
   local limit=dfhack.getTickCount()+30000
   while true do local ack=io.open(out..'/owner-input-ack');if ack then ack:close();break end
    assert(dfhack.getTickCount()<limit,'Trade resize timeout');script.sleep(1,'frames')end
   assert(os.remove(out..'/owner-input-ack'))
   g.precise_mouse_x=0;g.precise_mouse_y=0;g.mouse_x=0;g.mouse_y=0;view:render(dfhack.getTickCount())
   capture('depot-trade-resize-'..size)
   local columns=g.dimx-48
   local output,code=dfhack.run_command_silent('df3d','trade-header-probe',tostring(trade.bld.id),'0',tostring(trade.talkline),tostring(columns));assert(code==0,output)
   local header=json.decode(output);assert(header.available)
   for i,text in ipairs(header.lines)do
    local chars={};for x=17,17+columns-1 do local tile=dfhack.screen.readTile(x,6+i);chars[#chars+1]=tile.ch>=32 and tile.ch<=255 and string.char(tile.ch)or' 'end
    local bytes=dfhack.utf2df(text);assert(bytes..string.rep(' ',columns-#bytes)==table.concat(chars),'Native resize wrapping differs: '..size)
   end
   result.resize[#result.resize+1]={size=size,columns=columns,lines=header.lines}
  end
 end
 if accept_mode then
  result.accept_before=transfers();result.counter_goods=goods()
  if accept_mode=='native' then
   if active_okay then
    local before_rng=rng();local before_people=people();local before_transfers=transfers();local before_goods=goods()
    click(920,166)
    assert(trade.counter_offer and #trade.counter_offer_item==0 and trade.talkline==24)
    assert(json.encode(rng())==json.encode(before_rng) and json.encode(people())==json.encode(before_people) and json.encode(transfers())==json.encode(before_transfers) and json.encode(goods())==json.encode(before_goods),'Active Okay changed simulation or draft')
    result.active_okay={counter_offer=trade.counter_offer,dialogue=trade.talkline,requested_items=0,effects_unchanged=true}
    capture('depot-trade-active-okay')
   end
   click(508,730)
   result.accept_conversation={dialogue=trade.talkline,counter_offer=trade.counter_offer,announcement={}}
   for _,text in ipairs(trade.big_announce.text)do result.accept_conversation.announcement[#result.accept_conversation.announcement+1]=dfhack.df2utf(text.value)end
   result.accept_goods=goods()
   capture('depot-trade-accepted')
  else
   restore_people(initial_people);restore_caravan(initial_caravan);trade.counter_offer=false;trade.counter_offer_item:resize(0);trade.talkline=line
   set_rng(controlled)
   if accept_mode=='wire' then
    local file=assert(io.open(out..'/trade-exchange-wire-expected.json','w'));file:write(json.encode({depot=trade.bld.id,intents=intents,counter_items=result.native.items,active_okay=active_okay}));file:close()
    capture('trade-exchange-wire')
    file=assert(io.open(out..'/trade-exchange-wire-result.json'));local wire=json.decode(file:read('*a'));file:close();assert(wire.success,json.encode(wire))
    result.accept_conversation={dialogue=wire.final.dialogue,counter_offer=wire.final.counter_offer,announcement=wire.final.announcement};result.wire=wire
   elseif accept_mode=='session' then
    local state=session_probe('open',trade.bld.id,0);assert(state.status==0)
    local id=state.session
    for _,intent in ipairs(intents)do state=session_probe('item',id,state.revision,intent.side,intent.item);assert(state.status==0)end
    local previous=state.revision
    state=session_probe('exchange',id,previous);assert(state.status==0 and state.exchange_status==0 and state.counter_offer,json.encode(state))
    assert(json.encode(state.sides)==json.encode(result.counter_goods),'Persistent counteroffer goods differ')
    local first=state
    state=session_probe('read',id,first.revision);assert(state.status==0 and state.counter_offer and state.dialogue==24 and json.encode(state.requested_items)==json.encode(first.requested_items))
    local before_rng=rng();local before_people=people()
    assert(session_probe('exchange',id,previous).exchange_status==1,'Stale negotiation replayed')
    assert(json.encode(rng())==json.encode(before_rng) and json.encode(people())==json.encode(before_people),'Rejected replay changed simulation')
    state=session_probe('exchange',id,first.revision);assert(state.status==0 and state.exchange_status==0 and not state.counter_offer,json.encode(state))
    result.accept_conversation={dialogue=state.dialogue,counter_offer=state.counter_offer,announcement=state.announcement};result.accept_goods=state.sides
    local final=session_probe('read',id,state.revision);assert(final.status==0 and json.encode(final.sides)==json.encode(state.sides) and final.dialogue==state.dialogue and json.encode(final.requested_items)==json.encode(state.requested_items),'Accepted session did not survive refresh')
    result.counter_page=final.counter_page
    assert(final.counter_page.total==#final.requested_items)
    for i,row in ipairs(final.counter_page.rows)do assert(row.id==final.requested_items[i])end
    local before_transfers=transfers();before_rng=rng()
    assert(session_probe('exchange',id,first.revision).exchange_status==1,'Accepted exchange replayed')
    assert(json.encode(transfers())==json.encode(before_transfers) and json.encode(rng())==json.encode(before_rng))
    local dismissed=session_probe('okay',id,final.revision)
    assert(dismissed.status==0 and dismissed.revision==final.revision+1 and #dismissed.requested_items==0 and dismissed.counter_offer==final.counter_offer and dismissed.dialogue==final.dialogue)
    assert(json.encode(dismissed.sides)==json.encode(final.sides),'Okay changed the goods draft')
    assert(session_probe('okay',id,final.revision).status==1,'Stale Okay accepted')
    assert(session_probe('okay',id,dismissed.revision).status==1,'Empty Okay accepted')
    local cleared=session_probe('read',id,dismissed.revision);assert(cleared.status==0 and cleared.counter_page.total==0)
    assert(json.encode(transfers())==json.encode(before_transfers) and json.encode(rng())==json.encode(before_rng),'Okay changed simulation')
    result.counter_dismiss_verified=true
    assert(session_probe('close',id).status==3);assert(session_probe('exchange',id,state.revision).exchange_status==1)
    result.session_verified=true
   else
   local output,code=dfhack.run_command_silent('df3d','trade-accept-probe',tostring(trade.bld.id),'0','','',json.encode(intents))
   assert(code==0,output);local accepted=json.decode(output)
   assert(accepted.accepted_executed and accepted.accept_effects_started and not accepted.unknown,output)
   result.accept_conversation={dialogue=accepted.dialogue,counter_offer=accepted.counter_offer,announcement=accepted.announcement}
   end
   assert(not trade.counter_offer and trade.talkline==line,'Owned acceptance changed native menu')
  end
  result.accept_after=transfers();result.accept_people=people();result.accept_caravan=caravan_state();result.accept_rng=rng();result.accept_mode=accept_mode
  assert(not result.accept_conversation.counter_offer and result.accept_after.times_used==result.accept_before.times_used+1,'Counteroffer was not accepted')
  local changed=0;for i,item in ipairs(result.accept_after.items)do if json.encode(item)~=json.encode(result.accept_before.items[i])then changed=changed+1 end end
  assert(changed>0,'Acceptance transferred no goods');result.changed_items=changed;result.success=true;return
 end
 restore_people(initial_people);restore_caravan(initial_caravan);trade.counter_offer=false;trade.counter_offer_item:resize(0);trade.talkline=line
 set_rng(controlled)
 local output,code=dfhack.run_command_silent('df3d','trade-negotiate-probe',tostring(trade.bld.id),'0','','',json.encode(intents))
 assert(code==0,output);local owned=json.decode(output);assert(owned.available and owned.executed and owned.effects_started and owned.counter_offer,output)
 assert(owned.conversation_restored and owned.missing_counter_item_rejected and owned.owned_text_roundtrip,'Negotiation checkpoint restoration failed')
 result.conversation_restored=true;result.missing_counter_item_rejected=true;result.owned_text_roundtrip=true
 result.owned={dialogue=owned.dialogue,items=owned.requested_items,people=people(),caravan=caravan_state()}
 assert(json.encode(result.owned)==json.encode(result.native),'Owned negotiation effects differ from native')
 local after=rng();assert(after.context==native_rng.context and after.cursor==native_rng.cursor,'Negotiation RNG cursor differs')
 for i,v in ipairs(after.words)do assert(v==native_rng.words[i],'Negotiation RNG state differs')end
 assert(not trade.counter_offer and trade.talkline==line,'Owned negotiation changed native menu')
 result.rng_equal=true;result.rng_cursor=after.cursor;result.success=true
end,debug.traceback)
trade.civ.resources.ethic.KILL_ANIMAL=original_ethics.animal;trade.civ.resources.ethic.KILL_PLANT=original_ethics.plant
restore_people(original_people);restore_caravan(original_caravan);set_rng(original_rng)
caravan.goods:resize(0);for _,id in ipairs(history)do caravan.goods:insert("#",id)end
caravan.total_capacity.whole=mass.whole;caravan.total_capacity.fraction=mass.fraction
trade.counter_offer=false;trade.counter_offer_item:resize(0);trade.talkline=line
click(440,694);click(900,694)
assert(ok,err);return result

