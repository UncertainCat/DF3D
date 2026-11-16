-- Disposable paused Gift oracle. Native and owned effects run in separate
-- protected sessions; neither session is saved.
local view,trade,click,capture,out=...
local json=require('json')
local artifact_case=os.getenv('DF3D_DEPOT_TRADE_ARTIFACT')=='1' or os.getenv('DF3D_DEPOT_TRADE_ARTIFACT')=='long'
local mode=os.getenv('DF3D_DEPOT_TRADE_GIFT');assert(mode=='native' or mode=='owned' or mode=='session' or mode=='wire')
local history={};for _,id in ipairs(trade.mer.goods)do history[#history+1]=id end
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
local imported=bar.flags.foreign;bar.flags.foreign=true
view:render(dfhack.getTickCount())
local imported_before=snapshot()
if mode=='native' then
 click(735,730)
else
 local output,code=dfhack.run_command_silent('df3d','trade-gift-probe',tostring(trade.bld.id),'0','','',json.encode{{side=1,item=bar.id}})
 assert(code==0,output);local refusal=json.decode(output)
 assert(not refusal.executed and not refusal.effects_started and not refusal.unknown,output)
end
assert(trade.talkline==line and json.encode(snapshot())==json.encode(imported_before),'Imported Gift changed state')
bar.flags.foreign=imported;view:render(dfhack.getTickCount())
local artifact,artifact_ref,artifact_flag
if artifact_case then
 assert(mode=='native' or mode=='wire','Artifact oracle qualifies native and wire modes')
 local artifacts=df.global.world.artifacts.all
 assert(#artifacts>0 and not bar.flags.artifact)
 artifact=df.artifact_record:new();artifact.id=artifacts[#artifacts-1].id+1;artifact.item=bar
 artifact.name:assign(artifacts[0].name)
 if os.getenv('DF3D_DEPOT_TRADE_ARTIFACT')=='long' then artifact.name.first_name=string.rep('Controlled artifact name for wrapping and scrolling ',14) end
 artifact.entity_claims:insert('#',trade.civ.id)
 artifacts:insert('#',artifact)
 artifact_ref=df.general_ref_is_artifactst:new();artifact_ref.artifact_id=artifact.id
 bar.general_refs:insert('#',artifact_ref);artifact_flag=bar.flags.artifact;bar.flags.artifact=true
end
local result={mode=mode,item=bar.id,before=snapshot(),artifact_case=artifact_case}
result.imported_gift_rejected=true
for _,row in ipairs(result.before.items)do for _,ref in ipairs(row.refs)do assert(ref.kind~=df.general_ref_type.ENTITY_OFFERED,'Gift cleanup needs an unoffered fixture')end end
local ok,err=xpcall(function()
 if mode=='native' then
  click(735,730)
  result.dialogue=trade.talkline;result.counter_offer=trade.counter_offer;result.announcement={}
  for _,text in ipairs(trade.big_announce.text)do result.announcement[#result.announcement+1]=dfhack.df2utf(text.value)end
  capture('depot-trade-gift')
  if os.getenv('DF3D_DEPOT_TRADE_ARTIFACT')=='long' then
   assert(#result.announcement>8,'Long artifact name did not overflow the announcement viewport')
   result.scroll={initial=trade.scroll_position_big_announce}
   click(700,178);result.scroll.below_thumb=trade.scroll_position_big_announce;capture('depot-trade-announcement-down')
   click(700,94);result.scroll.above_thumb=trade.scroll_position_big_announce;capture('depot-trade-announcement-up')
   click(700,190);result.scroll.arrow_down=trade.scroll_position_big_announce;capture('depot-trade-announcement-arrow')
   click(700,82);result.scroll.arrow_up=trade.scroll_position_big_announce

  end
 elseif mode=='wire' then
  local file=assert(io.open(out..'/trade-transfer-wire-expected.json','w'));file:write(json.encode({depot=trade.bld.id,side=1,intents={{side=1,item=bar.id}},dialogue=artifact_case and -1 or 8}));file:close()
  capture('trade-transfer-wire')
  file=assert(io.open(out..'/trade-transfer-wire-result.json'));local wire=json.decode(file:read('*a'));file:close();assert(wire.success,json.encode(wire))
  result.dialogue=wire.conversation.dialogue;result.counter_offer=wire.conversation.counter_offer;result.announcement=wire.conversation.announcement;result.wire=wire
  assert(trade.talkline==line,'Wire transfer changed native conversation')
 elseif mode=='session' then
  local function probe(action,...)
   local args={...};for i,value in ipairs(args)do args[i]=tostring(value)end
   local output,code=dfhack.run_command_silent('df3d','trade-session-probe',action,table.unpack(args));assert(code==0,output);return json.decode(output)
  end
  local state=probe('open',trade.bld.id,0);assert(state.status==0)
  local id=state.session
  state=probe('item',id,state.revision,1,bar.id);assert(state.status==0)
  local selected_revision=state.revision
  state=probe('gift',id,selected_revision);assert(state.status==0 and state.exchange_status==0,json.encode(state))
  assert(state.revision==selected_revision+1)
  local refreshed=probe('read',id,state.revision)
  assert(refreshed.status==0 and refreshed.dialogue==8 and not refreshed.counter_offer and json.encode(refreshed.sides)==json.encode(state.sides),'Gift session did not survive refresh')
  local found=false
  for _,item in ipairs(refreshed.sides[1].items)do if item==bar.id then found=true end end
  assert(found,'Gift did not rebuild merchant goods')
  for _,item in ipairs(refreshed.sides[2].items)do assert(item~=bar.id,'Gift remained in fortress goods')end
  local after=snapshot()
  assert(probe('gift',id,selected_revision).exchange_status==1,'Stale Gift replayed')
  assert(json.encode(snapshot())==json.encode(after),'Stale Gift changed simulation')
  assert(probe('close',id).status==3)
  assert(probe('gift',id,state.revision).exchange_status==1,'Closed Gift replayed')
  assert(json.encode(snapshot())==json.encode(after),'Closed Gift changed simulation')
  result.dialogue=state.dialogue;result.counter_offer=state.counter_offer;result.announcement=state.announcement
  result.session={revision=state.revision,refreshed=true,stale_rejected=true,closed_rejected=true,sides=refreshed.sides}
  assert(trade.talkline==line and not trade.counter_offer,'Session Gift changed the native conversation')
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
 assert(result.dialogue==(artifact_case and -1 or 8) and not result.counter_offer,'Gift did not complete')
 if artifact_case then assert(#result.announcement>0,'Artifact transfer produced no announcement');result.artifact_id=artifact.id end
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
if artifact then
 for i=#bar.general_refs-1,0,-1 do if bar.general_refs[i]==artifact_ref then bar.general_refs:erase(i);break end end
 artifact_ref:delete();bar.flags.artifact=artifact_flag
 local artifacts=df.global.world.artifacts.all;assert(artifacts[#artifacts-1]==artifact);artifacts:erase(#artifacts-1);artifact:delete()
end
trade.mer.total_capacity.whole=whole;trade.mer.total_capacity.fraction=fraction;trade.talkline=line
click(440,694);click(900,694)
trade.mer.goods:resize(0);for _,id in ipairs(history)do trade.mer.goods:insert("#",id)end
assert(ok,err)
local file=assert(io.open(out..'/trade-gift-result.json','w'));file:write(json.encode(result));file:close()
return result
