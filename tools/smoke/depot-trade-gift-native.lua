-- Disposable paused Gift oracle. Native and owned effects run in separate
-- protected sessions; neither session is saved.
local view,trade,click,capture,out=...
local json=require('json')
local mode=os.getenv('DF3D_DEPOT_TRADE_GIFT');assert(mode=='native' or mode=='owned')
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
click(440,694);click(900,694)
local bar
for _,item in ipairs(trade.good[1])do if item:getType()==df.item_type.BAR then bar=item;break end end
assert(bar,'Gift fixture needs the opened bin and a steel bar')
click(932,418)
for side=0,1 do for i,item in ipairs(trade.good[side])do assert(trade.goodflag[side][i].selected==(side==1 and item.id==bar.id),'Gift fixture selected the wrong item')end end
local whole,fraction=trade.mer.total_capacity.whole,trade.mer.total_capacity.fraction
trade.mer.total_capacity.whole=100000;trade.mer.total_capacity.fraction=0
view:render(dfhack.getTickCount())
local line=trade.talkline
local result={mode=mode,item=bar.id,before=snapshot()}
for _,row in ipairs(result.before.items)do for _,ref in ipairs(row.refs)do assert(ref.kind~=df.general_ref_type.ENTITY_OFFERED,'Gift cleanup needs an unoffered fixture')end end
local ok,err=xpcall(function()
 if mode=='native' then
  click(735,730)
  result.dialogue=trade.talkline;result.counter_offer=trade.counter_offer;result.announcement={}
  for _,text in ipairs(trade.big_announce.text)do result.announcement[#result.announcement+1]=dfhack.df2utf(text.value)end
  capture('depot-trade-gift')
 else
  local output,code=dfhack.run_command_silent('df3d','trade-gift-probe',tostring(trade.bld.id),'0','','',json.encode{{side=1,item=bar.id}})
  assert(code==0,output);local response=json.decode(output)
  assert(response.available and response.executed and response.effects_started and response.rebuild and not response.unknown,output)
  result.dialogue=response.dialogue;result.counter_offer=response.counter_offer;result.announcement=response.announcement
  assert(trade.talkline==line and not trade.counter_offer,'Owned Gift changed the native conversation')
 end
 result.before_row_refresh=snapshot()
 -- Native pointer dispatch redraws immediately, whereas the owned executor
 -- leaves row reads to its caller. Compare after the same semantic reads.
 for side=0,1 do
  local output,code=dfhack.run_command_silent('df3d','trade-row-values-probe',tostring(trade.bld.id),'0',tostring(side),'0','64')
  assert(code==0 and json.decode(output).available,output)
 end
 result.after=snapshot()
 assert(result.dialogue==8 and not result.counter_offer,'Gift did not complete')
 local changes=0
 for i,row in ipairs(result.after.items)do if json.encode(row)~=json.encode(result.before.items[i])then changes=changes+1 end end
 assert(changes>0 and bar.flags.trader,'Gift changed no ownership')
 result.changed_items=changes;result.success=true
end,debug.traceback)
-- Existing source cleanup restores ownership, positions and bin containment.
-- Remove only Gift references added to this unoffered disposable fixture.
for _,item in pairs(tracked)do for i=#item.general_refs-1,0,-1 do local ref=item.general_refs[i]
 if ref:getType()==df.general_ref_type.ENTITY_OFFERED then item.general_refs:erase(i);ref:delete()end
end end
trade.mer.total_capacity.whole=whole;trade.mer.total_capacity.fraction=fraction;trade.talkline=line
click(440,694);click(900,694)
assert(ok,err)
local file=assert(io.open(out..'/trade-gift-result.json','w'));file:write(json.encode(result));file:close()
return result
