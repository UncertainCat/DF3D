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
local restore_speaker
local restore_broker
local restore_item
local restore_sources
local source_probe=os.getenv('DF3D_DEPOT_TRADE_SOURCES')=='1'
local selection_intents={}
assert(not source_probe or os.getenv('DF3D_DEPOT_TRADE_LISTS')~='1','Source isolation must not qualify appraisal')
local added_job=false;local added={};local result={depot=b.id,trader=unit.id,synthetic_prerequisites=true,cases={}}
local function click(x,y)
 -- At this fixed1200x800 oracle viewport, an overflowing right list shifts
 -- row checkboxes left16px to make room for the native scrollbar.
 if x==932 and result.bin and trade.i_height[1]>39 then x=916 end
 gps.precise_mouse_x=x;gps.precise_mouse_y=y;gps.mouse_x=x//8;gps.mouse_y=(y-4)//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L')
 -- Diagnostic isolation only: list enumeration must not train the fixture trader.
 if source_probe and trade.open then trade.handle_appraisal=0 end
 view:render(dfhack.getTickCount())
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
 if label=='speaker' and os.getenv('DF3D_DEPOT_TRADE_ROW_VALUES')=='1' then
  row.value_rows={};row.visible_value_rows=0
  for side=0,1 do
   local output,code=dfhack.run_command_silent('df3d','trade-row-values-probe',tostring(b.id),'0',tostring(side),'0','64');assert(code==0,output)
   local facts=json.decode(output);assert(facts.available and #facts.rows==#trade.good[side],output)
   local values={};for i,value in ipairs(facts.rows)do assert(value.id==trade.good[side][i-1].id);values[value.id]=value end
   local cursor=16
   for group,kind in ipairs(trade.current_type_a_type[side])do if trade.current_type_a_on[side][group]then
    cursor=cursor+3
    if trade.current_type_a_expanded[side][group]then
     local children=false
     for i,item in ipairs(trade.good[side])do
      local flags=trade.goodflag[side][i];local visible
      if flags.contained then visible=children
      else visible=item:getType()==kind and item:getSubtype()==trade.current_type_a_subtype[side][group];children=visible and not flags.container_collapsed end
      if visible then
       if cursor>=16 and cursor+1<=54 then
        local function cell_text(text)return dfhack.df2utf(dfhack.utf2df(text):gsub('[%z\1-\31]',' ')):gsub('%s+$','')end
        local value=assert(values[item.id]);local caption='Value: '..cell_text(value.value_caption);local weight='Weight: '..cell_text(value.weight_caption)
        assert(row.lines[cursor+1]:find(caption,1,true),'Native row value differs: '..item.id..' '..caption..' line '..row.lines[cursor+1])
        assert(row.lines[cursor+2]:find(weight,1,true),'Native row weight differs: '..item.id..' '..weight..' line '..row.lines[cursor+2])
        row.visible_value_rows=row.visible_value_rows+1
       end
       cursor=cursor+3
      end
     end
    end
   end end
   row.value_rows[side+1]=facts.rows
  end
  assert(row.visible_value_rows>=8 and #added[1].goods==0)
 end
 if source_probe and trade.open and not trade.choosing_merchant then
  local function ids()local sides={{},{}};for side=0,1 do for _,item in ipairs(trade.good[side])do table.insert(sides[side+1],item.id)end end;return sides end
  local expected=ids();local before=json.encode(expected);local appraisal=trade.handle_appraisal;local lists=trade.buildlists
  local source_ids={{},{}};for side=0,1 do for i,item in ipairs(trade.good[side])do if not trade.goodflag[side][i].contained then table.insert(source_ids[side+1],item.id)end end end
  for iteration=1,2 do
   local output,code=dfhack.run_command_silent('df3d','trade-goods-source-probe',tostring(b.id),'0');assert(code==0,output)
   local facts=json.decode(output);assert(facts.available and json.encode(facts.sides)==json.encode(source_ids),'Owned goods source differs: '..output..' expected '..json.encode(source_ids))
   assert(json.encode(ids())==before and trade.handle_appraisal==appraisal and trade.buildlists==lists and #added[1].goods==0)
   row.source_provider=facts
  end
  if os.getenv('DF3D_DEPOT_TRADE_PROJECTION')=='1' then
   for iteration=1,2 do
    local output,code=dfhack.run_command_silent('df3d','trade-projection-probe',tostring(b.id),'0',trade.item_filter[0],trade.item_filter[1],#selection_intents==0 and '[]' or json.encode(selection_intents));assert(code==0,output)
    local facts=json.decode(output);assert(facts.available,output)
    for side=0,1 do
     local actual=facts.sides[side+1]
     assert(json.encode(actual.items)==json.encode(expected[side+1]) and actual.height==trade.i_height[side],'Trade row order/height differs')
     assert(#actual.groups==#trade.current_type_a_type[side])
     for i,group in ipairs(actual.groups)do
      local j=i-1
      assert(group.type==trade.current_type_a_type[side][j] and group.subtype==trade.current_type_a_subtype[side][j] and group.expanded==trade.current_type_a_expanded[side][j] and group.on==trade.current_type_a_on[side][j] and group.flags==trade.current_type_a_flag[side][j].whole,'Trade group differs')
     end
     for i,flag in ipairs(actual.flags)do assert(flag==trade.goodflag[side][i-1].whole and actual.amounts[i]==trade.good_amount[side][i-1],'Trade item flags/amount differs')end
    end
    assert(json.encode(ids())==before and trade.handle_appraisal==appraisal and trade.buildlists==lists and #added[1].goods==0)
    row.projection_provider=facts
    if os.getenv('DF3D_DEPOT_TRADE_TOTALS')=='1' and trade.havetalker==1 and trade.stillunloading==0 then
     local totals=assert(facts.value_totals);local values={}
     for value in row.lines[58]:gmatch('Value: (%-?%d+)')do values[#values+1]=tonumber(value)end
     assert(#values==2 and values[1]==totals.estimated[1] and values[2]==totals.estimated[2],'Native footer values differ: '..row.lines[58])
     local label=totals.estimated_profit<0 and 'Trader Loss: ' or 'Trader Profit: '
     assert(row.lines[59]:find(label..tostring(math.abs(totals.estimated_profit)),1,true),'Native footer profit differs: '..row.lines[59])
     assert(dfhack.screen.readTile(6,58).fg==totals.profit_color,'Native footer profit color differs')
     row.value_totals=totals
    end
    row.filters={trade.item_filter[0],trade.item_filter[1]}
    row.selection_intents=json.decode(json.encode(selection_intents))
   end
  end
 end
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
 if source_probe then
  local snapshots={};local contained=#b.contained_items;local types={};local candidates={}
  for _,item in ipairs(df.global.world.items.all)do
   if item.flags.on_ground and not item.flags.in_inventory and not item.flags.in_building and not item.flags.trader and #item.general_refs==0 then
    local kind=item:getType();types[kind]=(types[kind]or 0)+1
    if types[kind]<=2 then candidates[#candidates+1]=item end
    if #candidates>=12 then break end
   end
  end
  assert(#candidates==12,'Need twelve safe source items')
  if os.getenv('DF3D_DEPOT_TRADE_CONTAINER')=='1' then
   for _,item in ipairs(df.global.world.items.all)do
    if item:getType()==df.item_type.BIN and item.flags.on_ground and not item.flags.in_inventory and not item.flags.in_building and not item.flags.trader and not item.flags.in_job then
     local children={};local nested=false
     for _,ref in ipairs(item.general_refs)do if ref:getType()==df.general_ref_type.CONTAINS_ITEM then local child=ref:getItem();if child then children[#children+1]=child.id;if child:getType()==df.item_type.BIN then nested=true end end end end
     if #children>0 and not nested then candidates[#candidates+1]=item;result.bin={id=item.id,children=children};break end
    end
   end
   assert(result.bin,'No safe populated ground bin')
  end
  restore_sources=function()
   for i=#snapshots,1,-1 do local s=snapshots[i]
    if s.ref then assert(s.item.general_refs[#s.item.general_refs-1]==s.ref);s.item.general_refs:erase(#s.item.general_refs-1);s.ref:delete()end
    s.item.flags.in_building=false;assert(dfhack.items.moveToGround(s.item,s.pos));s.item.flags.whole=s.flags
    for _,child in ipairs(s.children or {})do child.item.pos.x=child.pos.x;child.item.pos.y=child.pos.y;child.item.pos.z=child.pos.z;child.item.flags.whole=child.flags end
   end
   assert(#b.contained_items==contained);restore_sources=nil
  end
  result.source_items={};result.appraisal_suppressed=true
  for i,item in ipairs(candidates)do
   local s={item=item,pos={x=item.pos.x,y=item.pos.y,z=item.pos.z},flags=item.flags.whole};snapshots[#snapshots+1]=s
   if result.bin and item.id==result.bin.id then s.children={};for _,id in ipairs(result.bin.children)do local child=df.item.find(id);s.children[#s.children+1]={item=child,pos={x=child.pos.x,y=child.pos.y,z=child.pos.z},flags=child.flags.whole}end end
   assert(dfhack.items.moveToBuilding(item,b,0,true))
   if i<=6 then s.ref=df.general_ref_entity_itemownerst:new();s.ref.entity_id=i==6 and -1 or added[1].entity;item.general_refs:insert('#',s.ref);item.flags.trader=true end
   if i==11 then b.contained_items[#b.contained_items-1].use_mode=2 end
   if i==12 then item.flags.in_building=false end
   result.source_items[#result.source_items+1]={id=item.id,type=item:getType(),side=i<=5 and 0 or ((i>=7 and i<=10 or i==13) and 1 or -1)}
  end
 end
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
 if os.getenv('DF3D_DEPOT_TRADE_SPEAKER')=='1' then
  local speaker;local civ=df.historical_entity.find(added[1].entity)
  for _,candidate in ipairs(df.global.world.units.active)do
   if candidate.id~=unit.id and dfhack.units.isCitizen(candidate) and candidate.race==civ.race and candidate.on_item_id==-1 then
    local hauling=false;for _,entry in ipairs(candidate.inventory)do if entry.mode==df.inv_item_role_type.Hauled then hauling=true end end
    if not hauling then speaker=candidate;break end
   end
  end
  assert(speaker,'No controlled merchant speaker candidate')
  local original_flags=speaker.flags1.whole;local original_civ=speaker.civ_id;local original_nickname=speaker.name.nickname;local inventory_count=#speaker.inventory;local extra
  restore_speaker=function()
   if extra then speaker.inventory:erase(#speaker.inventory-1);extra:delete();extra=nil end
   speaker.flags1.whole=original_flags;speaker.civ_id=original_civ;speaker.name.nickname=original_nickname
   assert(#speaker.inventory==inventory_count);restore_speaker=nil
  end
  speaker.flags1.merchant=true;speaker.flags1.inactive=false;speaker.flags1.incoming=false;speaker.civ_id=added[1].entity
  local function reopen(label,unloading)
   unit.pos.x=position.x;unit.pos.y=position.y;unit.pos.z=position.z;select_map(b);assert(main.view_sheets.active_id==b.id)
   unit.pos.x=b.centerx;unit.pos.y=b.centery;unit.pos.z=b.z;click(480,190);assert(trade.open)
   local row=record(label);assert(row.merchant_trader==speaker.id and row.havetalker==1 and row.stillunloading==unloading)
   if label=='speaker' and source_probe and os.getenv('DF3D_DEPOT_TRADE_PROJECTION')=='1' then
    for _,test in ipairs{{0,'iron'},{0,'boulders'},{0,'zznomatch'},{1,'blocks'}}do
     local side,query=test[1],test[2]
     click(side==0 and 100 or 570,166)
     for byte in query:gmatch('.')do gui.simulateInput(view,('STRING_A%03d'):format(byte:byte()))end
     view:render(dfhack.getTickCount());assert(trade.item_filter[side]~='','Trade search did not receive text')
     record('search-'..side..'-'..query)
     for i=1,#query do gui.simulateInput(view,'STRING_A000')end
     view:render(dfhack.getTickCount());assert(trade.item_filter[side]=='')
     click(side==0 and 100 or 570,166)
    end
    record('search-cleared')
    if os.getenv('DF3D_DEPOT_TRADE_TOTALS')=='1' then
     local assignments=df.global.plotinfo.main.fortress_entity.assignments_by_type[df.entity_position_responsibility.TRADE]
     assert(#assignments==0 and unit.hist_figure_id>=0)
     local skill;local created=false;local skills=unit.status.current_soul.skills
     for _,s in ipairs(skills)do if s.id==df.job_skill.APPRAISAL then skill=s;break end end
     if not skill then skill=df.unit_skill:new();skill.id=df.job_skill.APPRAISAL;require('utils').insert_sorted(skills,skill,'id');created=true end
     local rating,rusty=skill.rating,skill.rusty
     local assignment=df.entity_position_assignment:new();assignment.histfig=unit.hist_figure_id;assignments:insert('#',assignment)
     restore_broker=function()
      assignments:erase(#assignments-1);assignment:delete();skill.rating=rating;skill.rusty=rusty
      if created then for i,s in ipairs(skills)do if s==skill then skills:erase(i);break end end;skill:delete()end
      restore_broker=nil
     end
     for _,level in ipairs{0,5,15}do
      skill.rating=level;skill.rusty=0
      selection_intents={{side=0,action='mark_all'}};click(310,694);record('totals-merchant-'..level)
      selection_intents[#selection_intents+1]={side=1,action='mark_all'};click(780,694);record('totals-both-'..level)
      selection_intents[#selection_intents+1]={side=0,action='unmark_all'};click(440,694);record('totals-fortress-'..level)
      selection_intents[#selection_intents+1]={side=1,action='unmark_all'};click(900,694);record('totals-cleared-'..level)
      selection_intents={}
     end
     restore_broker();record('totals-no-broker')
    end
    if result.bin then
     local index;for i,item in ipairs(trade.good[1])do if item.id==result.bin.id then index=i;break end end
     assert(index and trade.goodflag[1][index+1].contained)
     local child=trade.good[1][index+1].id
     local actions={
      {{side=1,item=result.bin.id},932,382},
      {{side=1,item=child},932,418},
      {{side=1,action='expand_container',item=result.bin.id},570,382},
      {{side=1,action='expand_container',item=result.bin.id},570,382},
      {{side=1,item=result.bin.id},932,382},
     }
     for i,test in ipairs(actions)do selection_intents[#selection_intents+1]=test[1];click(test[2],test[3]);record('bin-action-'..i)end
     for _,flag in ipairs(trade.goodflag[1])do assert(not flag.selected)end
     assert(not trade.goodflag[1][index].container_collapsed);selection_intents={}
    end
    if os.getenv('DF3D_DEPOT_TRADE_SELECTION')=='1' then
     for i,test in ipairs{{0,0,468,238},{0,1,468,274},{0,0,468,238},{1,0,932,238},{0,1,468,274},{1,0,932,238}}do
      local side,index,x,y=table.unpack(test);local item=trade.good[side][index]
      local before=trade.goodflag[side][index].selected
      selection_intents[#selection_intents+1]={side=side,item=item.id}
      click(x,y);assert(trade.goodflag[side][index].selected~=before,'Native row selection did not toggle')
      record('selection-'..i)
     end
     for side=0,1 do for _,flag in ipairs(trade.goodflag[side])do assert(not flag.selected)end end
     selection_intents={}
     if os.getenv('DF3D_DEPOT_TRADE_GROUP_ACTIONS')=='1' then
      local group_type=trade.current_type_a_type[0][0];local group_subtype=trade.current_type_a_subtype[0][0]
      local actions={
       {{side=0,item=trade.good[0][0].id},468,238},
       {{side=0,action='group',type=group_type,subtype=group_subtype},468,202},
       {{side=0,action='group',type=group_type,subtype=group_subtype},468,202},
       {{side=0,action='expand_group',type=group_type,subtype=group_subtype},100,202},
       {{side=0,action='expand_group',type=group_type,subtype=group_subtype},100,202},
       {{side=0,action='mark_all'},310,694},
       {{side=0,action='unmark_all'},440,694},
       {{side=1,action='mark_all'},780,694},
       {{side=1,action='unmark_all'},900,694},
      }
      for i,test in ipairs(actions)do
       selection_intents[#selection_intents+1]=test[1];click(test[2],test[3]);record('group-action-'..i)
      end
      for side=0,1 do for _,flag in ipairs(trade.goodflag[side])do assert(not flag.selected)end end
      assert(trade.current_type_a_expanded[0][0]);selection_intents={}
      click(100,166);for byte in ('iron'):gmatch('.')do gui.simulateInput(view,('STRING_A%03d'):format(byte:byte()))end
      view:render(dfhack.getTickCount());assert(trade.item_filter[0]~='')
      selection_intents={{side=0,action='mark_all'}};click(310,694);record('group-action-filter-mark')
      for _,flag in ipairs(trade.goodflag[0])do assert(flag.selected,'Mark all skipped a filtered item')end
      selection_intents[#selection_intents+1]={side=0,action='unmark_all'};click(440,694);record('group-action-filter-unmark')
      -- Native button clicks release search focus; reacquire it before clearing.
      if not trade.entering_item_filter[0] then click(100,166)end
      for i=1,4 do gui.simulateInput(view,'STRING_A000')end
      view:render(dfhack.getTickCount());assert(trade.item_filter[0]=='')
      if trade.entering_item_filter[0] then click(100,166)end
      selection_intents={}
     end
    end
   end
   gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());assert(not trade.open)
  end
  result.speaker_id=speaker.id
  reopen('speaker',0)
  speaker.name.nickname='Controlled long merchant nickname for truncation'
  reopen('speaker-long-name',0)
  extra=df.unit_inventory_item:new();extra.item=df.item.find(296);extra.mode=df.inv_item_role_type.Hauled;speaker.inventory:insert('#',extra)
  reopen('speaker-unloading',1)
  restore_speaker()
 end
 if restore_sources then restore_sources()end
 caravan();unit.pos.x=position.x;unit.pos.y=position.y;unit.pos.z=position.z
 select_map(b);assert(main.view_sheets.active_id==b.id)
 unit.pos.x=b.centerx;unit.pos.y=b.centery;unit.pos.z=b.z
 click(480,190);assert(trade.open and trade.choosing_merchant)
 local multiple=record('merchants');assert(multiple.merchants==2)
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());assert(not trade.open)
end,debug.traceback)
if not ok then local file=assert(io.open(out..'/depot-trade-failure.txt','w'));file:write(tostring(err));file:close()end
if trade.open then gui.simulateInput(view,'LEAVESCREEN')end
if restore_item then restore_item()end
if restore_sources then restore_sources()end
if restore_speaker then restore_speaker()end
if restore_broker then restore_broker()end
if added_job then b.jobs:erase(#b.jobs-1)end
unit.pos.x=position.x;unit.pos.y=position.y;unit.pos.z=position.z
job.general_refs:erase(0);ref:delete();job:delete()
for i=#added,1,-1 do caravans:erase(#caravans-1);added[i]:delete()end
assert(#caravans==count and #b.jobs==0 and df.global.world.frame_counter==frame and b.trade_flags.whole==flags)
if not ok then error(err)end
result.success=true;result.restored=true
local file=assert(io.open(out..'/depot-trade-native.json','w'));file:write(json.encode(result));file:close()
return result
