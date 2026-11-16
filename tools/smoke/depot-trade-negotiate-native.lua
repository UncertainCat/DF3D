-- Disposable paused differential oracle; runtime never snapshots or rewinds RNG.
local view,trade,click,capture=...
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
local ok,err=xpcall(function()
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
 set_rng(controlled);click(508,730)
 assert(trade.counter_offer and #trade.counter_offer_item>0,'Controlled offer did not produce a native counteroffer: '..trade.talkline..'/'..tostring(trade.counter_offer)..'/'..#trade.counter_offer_item)
 result.native={dialogue=trade.talkline,items={},people=people(),caravan=caravan_state()}
 for _,item in ipairs(trade.counter_offer_item)do result.native.items[#result.native.items+1]=item.id end
 local native_rng=rng();capture('depot-trade-counteroffer')
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
restore_people(original_people);restore_caravan(original_caravan);set_rng(original_rng)
caravan.total_capacity.whole=mass.whole;caravan.total_capacity.fraction=mass.fraction
trade.counter_offer=false;trade.counter_offer_item:resize(0);trade.talkline=line
click(440,694);click(900,694)
assert(ok,err);return result

