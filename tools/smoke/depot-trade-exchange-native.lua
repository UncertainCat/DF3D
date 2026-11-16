-- Paused native reference. Empty selections cannot transfer fixture items.
local view,trade,click,capture,out=...
local gps=df.global.gps
local result={cases={},globals={}}
for _,entry in ipairs{{'display',gps,'force_full_display_count'}, {'history_suppression',df.global.world,'artifact_history_suppression_count'}, {'fortress_entity',df.global.plotinfo.main,'fortress_entity'}}do
 local _,address=df.sizeof(entry[2]:_field(entry[3]));result.globals[entry[1]]=address-dfhack.internal.getImageBase()
end
local mass=trade.mer.total_capacity;local whole,fraction=mass.whole,mass.fraction
local talkline=trade.talkline
local function snapshot(label)
 local row={label=label,talkline=trade.talkline,counter_offer=trade.counter_offer,lines={}}
 for side=0,1 do for _,flag in ipairs(trade.goodflag[side])do assert(not flag.selected,'Empty exchange selected an item')end end
 for y=5,11 do local text={};for x=5,120 do local ch=dfhack.screen.readTile(x,y).ch;text[#text+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end;row.lines[#row.lines+1]=dfhack.df2utf(table.concat(text)):gsub('%s+$','')end
 result.cases[#result.cases+1]=row;capture('depot-trade-empty-'..label)
end
local ok,err=xpcall(function()
 if os.getenv('DF3D_DEPOT_TRADE_NEGOTIATE')=='1' then
  local source=debug.getinfo(1,'S').source:sub(2):gsub('depot%-trade%-exchange%-native.lua$','depot-trade-negotiate-native.lua')
  result.negotiation=assert(loadfile(source))(view,trade,click,capture,out)
 end
 if os.getenv('DF3D_DEPOT_TRADE_NEGOTIATION_SEED')=='1' then
  local json=require('json');result.seeds={}
  for iteration=1,2 do
   local intents=iteration==1 and {} or {{side=0,item=trade.good[0][0].id}}
   if iteration==2 then click(468,238)end
   local before={talkline=trade.talkline,buildlists=trade.buildlists,appraisal=trade.handle_appraisal,title=trade.title}
   local output,code=dfhack.run_command_silent('df3d','trade-negotiation-seed-probe',tostring(trade.bld.id),'0','','',json.encode(intents))
   assert(code==0,output);local seed=json.decode(output);assert(seed.available and seed.dialogue==trade.talkline and seed.counter_offer==trade.counter_offer and #seed.requested_items==0 and #seed.announcement==0)
   for side=0,1 do local rows=seed.sides[side+1];assert(#rows.items==#trade.good[side] and rows.height==trade.i_height[side])
    for i,item in ipairs(trade.good[side])do assert(rows.items[i+1]==item.id and rows.flags[i+1]==trade.goodflag[side][i].whole and rows.amounts[i+1]==trade.good_amount[side][i])end
   end
   assert(trade.talkline==before.talkline and trade.buildlists==before.buildlists and trade.handle_appraisal==before.appraisal and trade.title==before.title)
   result.seeds[#result.seeds+1]=seed
   if iteration==2 then click(468,238)end
  end
 end
 if os.getenv('DF3D_DEPOT_TRADE_REFUSAL')=='1' then
  local json=require('json');result.refusals={}
  for _,test in ipairs{{'empty',false,false,100000},{'merchant-only',true,false,100000},{'fortress-only',false,true,100000},{'both',true,true,100000},{'both-overweight',true,true,0}}do
   click(440,694);click(900,694)
   local intents={}
   if test[2]then intents[#intents+1]={side=0,item=trade.good[0][0].id};click(468,238)end
   if test[3]then intents[#intents+1]={side=1,item=trade.good[1][0].id};click(932,238)end
   mass.whole=test[4];mass.fraction=0;view:render(dfhack.getTickCount())
   local native_line=trade.talkline
   local output,code=dfhack.run_command_silent('df3d','trade-refusal-probe',tostring(trade.bld.id),'0','','',json.encode(intents))
   assert(code==0,output);local facts=json.decode(output);assert(facts.available and not facts.ethical and trade.talkline==native_line)
   if facts.disposition==1 then
    assert(#facts.replies==2 and facts.replies[1]~=facts.replies[2] and math.min(facts.replies[1],facts.replies[2])==facts.reply_base)
    -- Set the same prior conversation so native's alternating branch is exact;
    -- do not rewind or substitute the simulation RNG consumed by the owned call.
    trade.talkline=facts.replies[1];click(508,730)
    assert(trade.talkline==facts.replies[2] and not trade.counter_offer,'Owned refusal differs from native Trade')
    facts.native_dialogue=trade.talkline
   else assert(facts.disposition==2,'Offer unexpectedly unavailable')end
   facts.label=test[1];result.refusals[#result.refusals+1]=facts
  end
  click(440,694);click(900,694);trade.talkline=talkline
 end
 mass.whole=100000;mass.fraction=0;view:render(dfhack.getTickCount());snapshot('before')
 click(508,730);snapshot('trade')
 click(735,730);snapshot('gift')
end,debug.traceback)
mass.whole=whole;mass.fraction=fraction;trade.talkline=talkline
assert(ok,err);return result
