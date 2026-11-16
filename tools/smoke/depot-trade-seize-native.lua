-- Disposable paused foreign-caravan Seize comparison; never save this session.
local view,trade,click,capture,out=...
local json=require('json')
local mode=os.getenv('DF3D_DEPOT_TRADE_SEIZE');assert(mode=='native' or mode=='owned')
local tracked={}
for side=0,1 do for _,item in ipairs(trade.good[side])do tracked[item.id]=item end end
local function snapshot()
 local rows={}
 for id,item in pairs(tracked)do
  local refs={}
  for _,ref in ipairs(item.general_refs)do
   local kind=ref:getType()
   if kind==df.general_ref_type.ENTITY_ITEMOWNER or kind==df.general_ref_type.ENTITY_OFFERED or kind==df.general_ref_type.ENTITY_STOLEN then
    refs[#refs+1]={kind=kind,id=ref.entity_id}
   elseif kind==df.general_ref_type.CONTAINED_IN_ITEM then refs[#refs+1]={kind=kind,id=ref:getItem().id}
   elseif kind==df.general_ref_type.BUILDING_HOLDER then refs[#refs+1]={kind=kind,id=ref:getBuilding().id}end
  end
  table.sort(refs,function(a,b)return a.kind<b.kind or a.kind==b.kind and a.id<b.id end)
  rows[#rows+1]={id=id,refs=refs,flags=item.flags.whole,stack=item:getStackSize(),position={item.pos.x,item.pos.y,item.pos.z}}
 end
 table.sort(rows,function(a,b)return a.id<b.id end)
 local contained={};for _,row in ipairs(trade.bld.contained_items)do contained[#contained+1]={id=row.item.id,use_mode=row.use_mode}end
 table.sort(contained,function(a,b)return a.id<b.id end)
 local c=trade.mer
 return {items=rows,contained=contained,times_used=trade.bld.times_used,history_suppression=df.global.world.artifact_history_suppression_count,
  caravan={flags=c.flags.whole,mood=c.mood,haggle=c.haggle_fail_count,time=c.time_remaining,import_value=c.import_value,export_value_total=c.export_value_total,export_value_personal=c.export_value_personal,offer_value=c.offer_value}}
end

local civ=trade.civ;local entity=trade.mer.entity
local foreign
for _,candidate in ipairs(df.global.world.entities.all)do
 if candidate.type==df.historical_entity_type.Civilization and candidate.id~=df.global.plotinfo.civ_id then foreign=candidate;break end
end
assert(foreign,'No foreign civilization for Seize fixture')
local flags,mood,time=trade.mer.flags.whole,trade.mer.mood,trade.mer.time_remaining
local line=trade.talkline
trade.civ=foreign;trade.mer.entity=foreign.id
-- Align the synthetic merchant goods' ownership with the chosen caravan.
local owners={}
for _,item in ipairs(trade.good[0])do for _,ref in ipairs(item.general_refs)do
 if ref:getType()==df.general_ref_type.ENTITY_ITEMOWNER then owners[#owners+1]={ref=ref,id=ref.entity_id,item=item};ref.entity_id=foreign.id end
end end
click(440,694);click(900,694);click(468,238)
local selected
for i,item in ipairs(trade.good[0])do if trade.goodflag[0][i].selected then assert(not selected);selected=item end end
assert(selected,'Seize fixture requires exactly one selected merchant item')
view:render(dfhack.getTickCount());capture('depot-trade-seize-before')
local result={mode=mode,foreign=foreign.id,item=selected.id,before=snapshot()}
for _,row in ipairs(result.before.items)do for _,ref in ipairs(row.refs)do assert(ref.kind~=df.general_ref_type.ENTITY_STOLEN,'Seize cleanup requires no old stolen refs')end end
local ok,err=xpcall(function()
 if mode=='native' then
  local found
  for y=0,df.global.gps.dimy-1 do
   local text={};for x=0,df.global.gps.dimx-1 do local c=dfhack.screen.readTile(x,y).ch;text[#text+1]=c>=32 and c<=126 and string.char(c)or' 'end
   local at=table.concat(text):find('Seize',1,true)
   if at then assert(not found);found={x=(at+1)*8,y=4+y*12+6}end
  end
  assert(found,'Native Seize button not visible');result.button=found;click(found.x,found.y)
  result.dialogue=trade.talkline;result.counter_offer=trade.counter_offer;result.announcement={}
  for _,text in ipairs(trade.big_announce.text)do result.announcement[#result.announcement+1]=dfhack.df2utf(text.value)end
  capture('depot-trade-seize-after')
 else
  local output,code=dfhack.run_command_silent('df3d','trade-seize-probe',tostring(trade.bld.id),'0','','',json.encode{{side=0,item=selected.id}})
  assert(code==0,output);local response=json.decode(output)
  assert(response.available and response.executed and response.effects_started and response.rebuild and not response.unknown,output)
  result.dialogue=response.dialogue;result.counter_offer=response.counter_offer;result.announcement=response.announcement
  assert(trade.talkline==line,'Owned Seize changed native conversation')
 end
 result.before_row_refresh=snapshot()
 for side=0,1 do
  local output,code=dfhack.run_command_silent('df3d','trade-row-values-probe',tostring(trade.bld.id),'0',tostring(side),'0','64')
  assert(code==0 and json.decode(output).available,output)
 end
 result.after=snapshot()
 assert(result.dialogue==9 and not result.counter_offer and not selected.flags.trader,'Seize did not complete')
 assert(trade.mer.flags.whole&0x30==0x30 and trade.mer.mood==0 and trade.mer.time_remaining<=501)
 result.success=true
end,debug.traceback)
for _,item in pairs(tracked)do for i=#item.general_refs-1,0,-1 do local ref=item.general_refs[i]
 if ref:getType()==df.general_ref_type.ENTITY_STOLEN then item.general_refs:erase(i);ref:delete()end
end end
-- References of selected goods may have been deleted; locate survivors by item.
for _,saved in ipairs(owners)do for _,ref in ipairs(saved.item.general_refs)do if ref:getType()==df.general_ref_type.ENTITY_ITEMOWNER then ref.entity_id=saved.id end end end
trade.civ=civ;trade.mer.entity=entity;trade.mer.flags.whole=flags;trade.mer.mood=mood;trade.mer.time_remaining=time;trade.talkline=line
click(440,694);click(900,694)
assert(ok,err)
local file=assert(io.open(out..'/trade-seize-result.json','w'));file:write(json.encode(result));file:close()
return result
