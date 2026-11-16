-- Paused renderer facts only; restore every controlled native input.
local view,trade,click,capture,out=...
local json=require('json')
local civ,entity,flags,king=trade.civ,trade.mer.entity,trade.mer.flags.whole,df.global.plotinfo.king_arrived
local foreign;for _,candidate in ipairs(df.global.world.entities.all)do if candidate.type==df.historical_entity_type.Civilization and candidate.id~=df.global.plotinfo.civ_id then foreign=candidate;break end end
local local_entity=df.historical_entity.find(df.global.plotinfo.civ_id);assert(foreign and local_entity)
local item=trade.good[1][0];local imported=item.flags.foreign
local result={cases={}}
local ok,err=xpcall(function()
 for _,case in ipairs{{'local',false,false,false,false},{'foreign',true,false,false,false},{'stopped',true,true,false,false},{'king',false,false,true,false},{'imported',false,false,false,true}}do
  click(440,694);click(900,694)
  trade.civ=case[2] and foreign or local_entity;trade.mer.entity=trade.civ.id;trade.mer.flags.whole=case[3] and 0x20 or 0;df.global.plotinfo.king_arrived=case[4];item.flags.foreign=case[5]
  local intents={};if case[5]then click(932,238);intents={{side=1,item=item.id}}end
  view:render(dfhack.getTickCount())
  local output,code=dfhack.run_command_silent('df3d','trade-negotiation-seed-probe',tostring(trade.bld.id),'0','','',json.encode(intents))
  assert(code==0,output);local facts=json.decode(output);assert(facts.available and #facts.actions==3,output)
  assert(facts.actions[1].enabled==case[2] and facts.actions[2].enabled==not case[3] and facts.actions[3].enabled==not(case[3] or case[4] or case[5]),output)
  local row={label=case[1],actions=facts.actions};result.cases[#result.cases+1]=row;capture('trade-buttons-'..case[1])
 end
end,debug.traceback)
trade.civ=civ;trade.mer.entity=entity;trade.mer.flags.whole=flags;df.global.plotinfo.king_arrived=king;item.flags.foreign=imported
click(440,694);click(900,694)
assert(ok,err)
local file=assert(io.open(out..'/trade-buttons-result.json','w'));file:write(json.encode(result));file:close();return result
