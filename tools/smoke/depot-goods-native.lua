-- Diagnostic-only native menu oracle in a paused disposable save.
local out,view,b,capture,select_map=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local caravans=df.global.plotinfo.caravans
local frame=df.global.world.frame_counter
local caravan=df.caravan_state:new()
caravan.entity=df.global.plotinfo.main.fortress_entity.id
caravan.trade_state=df.caravan_state.T_trade_state.Approaching
caravan.time_remaining=1200
local index=#caravans;caravans:insert('#',caravan)
local menu=df.global.game.main_interface.assign_trade
assert(not menu.open and #b.jobs==0)
local result={id=b.id,synthetic_caravan=true,frame=frame}
local restore_delivered
local prohibition,prohibition_index
local function compare_selection(label,projection,draft,sort_draft)
 if os.getenv('DF3D_DEPOT_SELECTION_PROVIDER')~='1' then return end
 local facts=projection
 if not facts then
  local output,code=dfhack.run_command_silent('df3d','depot-selection-probe',tostring(b.id),tostring(menu.current_type),menu.sort_by_distance and '1' or '0',menu.pending_on_top and '1' or '0',menu.exclude_prohib and '1' or '0',menu.item_filter)
  assert(code==0,output);facts=json.decode(output)
 end
 assert(#facts.categories==#menu.filtered_type_list,'Category count differs: '..label)
 for i,kind in ipairs(menu.filtered_type_list)do assert(facts.categories[i+1]==kind,'Category order differs: '..label..' '..i)end
 local function text_at(x,y,n)
  local chars={};for col=x,x+n-1 do local ch=dfhack.screen.readTile(col,y).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
  return dfhack.df2utf(table.concat(chars))
 end
 local visible=0
 for i=menu.scroll_position_type+1,#facts.category_captions do
  local y=7+3*(i-menu.scroll_position_type-1);if y>=g.dimy-5 then break end
  local caption=facts.category_captions[i]
  assert(text_at(8,y,#dfhack.utf2df(caption))==caption,'Category caption differs: '..label..' '..caption)
  visible=visible+1
 end
 local screen={};for y=10,g.dimy-5 do screen[#screen+1]=text_at(47,y,65)end
 local text=table.concat(screen,'\n');local first_group
 for _,group in ipairs(facts.groups)do if group.matches then first_group=group.caption;break end end
 assert((#facts.ids>0 and first_group and text:find(first_group,1,true)) or (#facts.ids==0 and menu.i_height==0),'First displayed group caption differs: '..label..' '..tostring(first_group))
 local item_match=false
 for _,caption in ipairs(facts.item_captions)do if text:find(caption,1,true)then item_match=true;break end end
 assert(item_match or #facts.ids==0,'No displayed item caption matches: '..label)
 assert(#facts.ids==#menu.current_type_tgi and #facts.groups==#menu.current_type_a_subtype,'Selection size differs: '..label)
 assert(facts.row_cells==menu.i_height,'Native row height differs: '..label)
 for i,row in ipairs(menu.current_type_tgi)do assert(facts.ids[i+1]==row.it.id,'Selection order differs: '..label..' '..i)end
 for i,subtype in ipairs(menu.current_type_a_subtype)do local row=facts.groups[i+1]
  assert(row.subtype==subtype and row.subcat1==menu.current_type_a_subcat1[i] and row.subcat2==menu.current_type_a_subcat2[i] and row.amount==menu.current_type_a_amount[i] and row.expanded==menu.current_type_a_expanded[i] and row.matches==menu.current_type_a_on[i] and row.flags==menu.current_type_a_flag[i].whole,'Selected group differs: '..label..' '..i)
  local ids={}
  for _,entry in ipairs(menu.current_type_tgi)do local item=entry.it
   if item:getSubtype()==subtype and item:getMaterial()==menu.current_type_a_subcat1[i] and item:getMaterialIndex()==menu.current_type_a_subcat2[i]then ids[#ids+1]=item.id end
  end
  assert(#ids==#row.ids,'Group membership size differs: '..label)
  for j,id in ipairs(ids)do assert(row.ids[j]==id,'Group member order differs: '..label)end
 end
 local projected_cells=0
 if #facts.ids>0 then for _,group in ipairs(facts.groups)do if group.matches then projected_cells=projected_cells+3+(group.expanded and #group.ids*3 or 0)end end end
 assert(projected_cells==menu.i_height,'Group projection differs from native height: '..label)
 if os.getenv('DF3D_DEPOT_GOODS_WIRE')=='1' then
  local expected={label=label,request={depot_id=b.id,category=menu.current_type,query=menu.item_filter,sort_by_distance=menu.sort_by_distance,pending_on_top=menu.pending_on_top,exclude_prohibited=menu.exclude_prohib,item_ids={}},categories={},groups={},items={}}
  if draft then
   local function choices(text)local rows={};for id,wanted in text:gmatch('(%d+):([01])')do rows[#rows+1]={id=tonumber(id),desired=wanted=='1'}end;return rows end
   expected.request.expected_revision=facts.revision -- decimal string preserves all64 bits through JSON
   expected.request.draft=choices(draft);expected.request.sort_draft=choices(sort_draft)
  end
  for i,kind in ipairs(facts.categories)do expected.categories[#expected.categories+1]={type=kind,caption=facts.category_captions[i]}end
  for _,group in ipairs(facts.groups)do local row={};for k,v in pairs(group)do row[k=='ids' and 'item_ids' or k]=v end;expected.groups[#expected.groups+1]=row end
  for i,entry in ipairs(menu.current_type_tgi)do if i>=64 then break end
   expected.request.item_ids[#expected.request.item_ids+1]=entry.it.id
   expected.items[#expected.items+1]={id=entry.it.id,caption=facts.item_captions[i+1],distance=entry.dist,value=entry.value,tag=entry.tag,prohibited=entry.prohibited}
  end
  local file=assert(io.open(out..'/depot-goods-wire-expected.json','w'));file:write(json.encode(expected));file:close()
  local before_flags={};for _,entry in ipairs(menu.master_i_list.tgi)do before_flags[entry.it.id]=entry.it.flags.whole end
  capture('depot-goods-wire-'..label)
  local cache_changes={}
  for _,entry in ipairs(menu.master_i_list.tgi)do
   local before=before_flags[entry.it.id];local after=entry.it.flags.whole
   if before~=after then
    assert((before ~ after)==0x20000000 and entry.it.flags.weight_computed,'Inspection changed a non-cache item flag')
    cache_changes[#cache_changes+1]={id=entry.it.id,before=before,after=after}
   end
  end
  file=assert(io.open(out..'/depot-goods-wire-'..label..'-result.json'));local wire=json.decode(file:read('*a'));file:close();assert(wire.success and wire.label==label,'Goods wire failed: '..label)
  assert(menu.open and menu.trade_depot_bld.id==b.id and df.global.world.frame_counter==frame,'Goods read changed native picker/frame')
  wire.weight_cache_changes=cache_changes
  result.wire=result.wire or {};result.wire[#result.wire+1]=wire
 end
 result.selections=result.selections or {};result.selections[#result.selections+1]={label=label,type=menu.current_type,query=menu.item_filter,categories=facts.categories,category_captions=facts.category_captions,visible_category_captions=visible,item_captions=facts.item_captions,screen_text=text,ids=facts.ids,groups=facts.groups,row_cells=facts.row_cells,success=true}
end
local function compare_goods(label)
 if os.getenv('DF3D_DEPOT_GOODS_PROVIDER')~='1' then return end
 local output,code=dfhack.run_command_silent('df3d','depot-goods-probe',tostring(b.id));assert(code==0,output)
 local facts=json.decode(output);assert(#facts.rows==#menu.master_i_list.tgi,'Master count differs: '..label)
 for i,row in ipairs(menu.master_i_list.tgi)do
  local actual=facts.rows[i+1]
  assert(actual.id==row.it.id and actual.distance==row.dist and actual.tag==row.tag and actual.value==row.value and actual.prohibited==row.prohibited,'Master row differs: '..label..' '..i)
 end
 local groups=menu.master_a_list;assert(#facts.groups==#groups.type,'Group count differs')
 for i,kind in ipairs(groups.type)do
  local actual=facts.groups[i+1]
  assert(actual.type==kind and actual.subtype==groups.subtype[i] and actual.subcat1==groups.subcat1[i] and actual.subcat2==groups.subcat2[i] and actual.amount==groups.amount[i] and actual.expanded==groups.expanded[i],'Group differs: '..label..' '..i)
 end
 result.goods_provider=result.goods_provider or {}
 result.goods_provider[#result.goods_provider+1]={label=label,rows=#facts.rows,groups=#facts.groups,success=true}
end
local function click(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
end
local function job_facts()
 local jobs={}
 for _,j in ipairs(b.jobs)do
  local row={id=j.id,type=j.job_type,flags=j.flags.whole,pos={j.pos.x,j.pos.y,j.pos.z},items={},refs={}}
  for _,it in ipairs(j.items)do row.items[#row.items+1]={id=it.item.id,role=it.role}end
  for _,ref in ipairs(j.general_refs)do row.refs[#row.refs+1]={type=ref:getType(),building=ref:getBuilding() and ref:getBuilding().id or -1}end
  jobs[#jobs+1]=row
 end
 return jobs
end
local function draft_text()
 local changes={}
 for _,row in ipairs(menu.master_i_list.tgi)do
  if row.tag==1 or row.tag==-1 or row.tag==-2 then changes[#changes+1]=tostring(row.it.id)..':'..(row.tag>0 and '1' or '0')end
 end
 table.sort(changes);return #changes==0 and '-' or table.concat(changes,',')
end
local function compare_draft(label,sort_draft)
 if os.getenv('DF3D_DEPOT_DRAFT_NATIVE')~='1' then return end
 local before=json.encode(job_facts());local intent=draft_text()
 local output,code=dfhack.run_command_silent('df3d','depot-selection-probe',tostring(b.id),tostring(menu.current_type),menu.sort_by_distance and '1' or '0',menu.pending_on_top and '1' or '0',menu.exclude_prohib and '1' or '0',menu.item_filter,intent,sort_draft or '-')
 assert(code==0,output);local facts=json.decode(output)
 assert(facts.stale_rejected and #facts.ids==#menu.current_type_tgi,'Draft size/source guard differs: '..label)
 for i,row in ipairs(menu.current_type_tgi)do assert(facts.ids[i+1]==row.it.id and facts.tags[i+1]==row.tag,'Draft order/tag differs: '..label..' '..i)end
 assert(#facts.groups==#menu.current_type_a_flag,'Draft group count differs: '..label)
 for i,flag in ipairs(menu.current_type_a_flag)do
  local group=facts.groups[i+1]
  assert(group.flags==flag.whole and group.matches==menu.current_type_a_on[i],'Native draft aggregation differs: '..label..' '..i)
 end
 assert(menu.open and df.global.world.frame_counter==frame and json.encode(job_facts())==before,'Draft provider changed simulation/jobs')
 result.draft_provider=result.draft_provider or {}
 result.draft_provider[#result.draft_provider+1]={label=label,draft=intent,sort_draft=sort_draft or '-',ids=facts.ids,tags=facts.tags,groups=facts.groups,revision=facts.revision,stale_rejected=facts.stale_rejected}
 if os.getenv('DF3D_DEPOT_DRAFT_WIRE')=='1' then compare_selection('draft-'..label,facts,intent,sort_draft or '-')end
end
local ok,err=xpcall(function()
 view:render(dfhack.getTickCount());capture('depot-goods-available')
 g.precise_mouse_x=520;g.precise_mouse_y=166;g.mouse_x=65;g.mouse_y=13
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
 assert(menu.open and menu.trade_depot_bld.id==b.id,'Goods click did not open native picker')
 capture('depot-goods-initial')
 result.types={};for _,v in ipairs(menu.type_list)do result.types[#result.types+1]=v end
 result.current_type=menu.current_type
 result.sort_by_distance=menu.sort_by_distance;result.pending_on_top=menu.pending_on_top;result.exclude_prohib=menu.exclude_prohib
 result.items={}
 for _,row in ipairs(menu.master_i_list.tgi)do result.items[#result.items+1]={id=row.it.id,distance=row.dist,tag=row.tag,prohibited=row.prohibited,value=row.value,sort_value=row.sort_value}end
 compare_goods('unassigned')
 compare_selection('anvils')
 if os.getenv('DF3D_DEPOT_SELECTION_PROVIDER')=='1' then
  click(150,130);compare_selection('bags');capture('depot-selection-bags')
  click(150,202);compare_selection('bars');capture('depot-selection-bars')
  -- The Bars scrollbar narrows the header by two character cells.
  click(768,94)
  for byte in ('iron'):gmatch('.')do gui.simulateInput(view,('STRING_A%03d'):format(byte:byte()))end
  view:render(dfhack.getTickCount());capture('depot-selection-iron')
  assert(menu.item_filter=='IRON','Search typing failed: '..menu.item_filter..' focus='..tostring(menu.entering_item_filter))
  compare_selection('iron')
  for i=1,4 do gui.simulateInput(view,'STRING_A000')end
  view:render(dfhack.getTickCount());assert(menu.item_filter=='')
  click(150,94);compare_selection('restored-anvils')
 end
 if os.getenv('DF3D_DEPOT_DISTANCE_NATIVE')=='1' then
  local output,code=dfhack.run_command_silent('df3d','depot-distance-probe',tostring(b.id));assert(code==0,output)
  local facts=json.decode(output);assert(facts.restored)
  local by_id={};for _,row in ipairs(facts.rows)do by_id[row.id]=row.distance end
  for _,row in ipairs(result.items)do assert(by_id[row.id]==row.distance,'Native distance differs for item '..row.id..': '..tostring(by_id[row.id])..' vs '..row.distance)end
  assert(#facts.available==#result.items,'Native unassigned count differs')
  for i,row in ipairs(result.items)do assert(row.tag==0 and facts.available[i]==row.id,'Native unassigned order differs at '..i)end
  assert(menu.open and menu.trade_depot_bld.id==b.id and #menu.master_i_list.tgi==#result.items and menu.current_type==result.current_type)
  result.distance_provider={matched=#result.items,observed=#facts.rows,unassigned_matched=#facts.available,search_storage_restored=facts.restored}
 end
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
 assert(not menu.open,'Goods Escape failed')
 if os.getenv('DF3D_DEPOT_HAUL_NATIVE')=='1' then
  select_map(b);click(520,166);assert(menu.open and menu.current_type==df.item_type.ANVIL,'Reopen initial goods failed')
  if os.getenv('DF3D_DEPOT_EXPANSION_NATIVE')=='1' then
   local samples={}
   local function sample(label)
    assert(menu.open and menu.current_type==df.item_type.ANVIL and #b.jobs==0 and df.global.world.frame_counter==frame)
    local row={label=label,height=menu.i_height,scroll=menu.scroll_position_item,query=menu.item_filter,expanded={},ids={},tags={},master_expanded={}}
    for _,v in ipairs(menu.current_type_a_expanded)do row.expanded[#row.expanded+1]=v end
    for _,v in ipairs(menu.current_type_tgi)do row.ids[#row.ids+1]=v.it.id;row.tags[#row.tags+1]=v.tag end
    for i,v in ipairs(menu.master_a_list.type)do if v==df.item_type.ANVIL then row.master_expanded[#row.master_expanded+1]=menu.master_a_list.expanded[i]end end
    samples[#samples+1]=row;capture('depot-expansion-'..label)
   end
   sample('initial');click(500,130);sample('collapsed')
   assert(not menu.current_type_a_expanded[0] and menu.i_height==3,'Group label did not collapse')
   click(500,94);for byte in ('iron'):gmatch('.')do gui.simulateInput(view,('STRING_A%03d'):format(byte:byte()))end
   view:render(dfhack.getTickCount());sample('searched')
   for i=1,4 do gui.simulateInput(view,'STRING_A000')end
   view:render(dfhack.getTickCount());sample('cleared-search')
   click(150,130);click(150,94);sample('returned-category')
   if not menu.current_type_a_expanded[0] then click(500,130)end
   sample('restored');assert(menu.current_type_a_expanded[0] and menu.i_height==9)
   result.group_expansion=samples
  end
  if os.getenv('DF3D_DEPOT_DRAFT_NATIVE')=='1' then
   local rows=menu.current_type_tgi;assert(#rows==2 and #b.jobs==0)
   local ids={rows[0].it.id,rows[1].it.id};local samples={}
   local function draft(label,a,c,flag)
    assert(menu.open and df.global.world.frame_counter==frame and #b.jobs==0,'Draft changed simulation/jobs')
    assert(#menu.current_type_tgi==2 and menu.current_type_tgi[0].it.id==ids[1] and menu.current_type_tgi[1].it.id==ids[2],'Draft reordered items')
    assert(menu.current_type_tgi[0].tag==a and menu.current_type_tgi[1].tag==c,'Unexpected native draft tags: '..label)
    assert(menu.current_type_a_flag[0].whole==flag,'Unexpected native aggregate: '..label)
    local outside=0
    for _,row in ipairs(menu.master_i_list.tgi)do if row.it.id~=ids[1] and row.it.id~=ids[2] and row.tag~=0 then outside=outside+1 end end
    assert(outside==0,'Draft changed another category')
    samples[#samples+1]={label=label,ids=ids,tags={a,c},group_flags=flag,other_category_changes=outside,jobs=#b.jobs}
    compare_draft(label)
   end
   draft('initial',0,0,2)
   click(932,166);draft('individual-on',1,0,2)
   click(932,130);draft('mixed-group-on',1,1,1)
   click(932,130);draft('group-off',0,0,2)
   click(928,94);draft('select-all-on',1,1,1)
   click(928,94);draft('select-all-off',0,0,2)
   click(932,166);click(932,166);draft('individual-roundtrip',0,0,2)
   result.draft_selection=samples
   click(932,202);compare_draft('second-item-on')
   local basis=draft_text()
   click(150,130);assert(menu.current_type==df.item_type.BAG);compare_draft('bags-retain-anvil',basis)
   click(150,94);assert(menu.current_type==df.item_type.ANVIL);compare_draft('anvils-resort-draft',basis)
   assert(menu.current_type_tgi[0].it.id==ids[2] and menu.current_type_tgi[0].tag==1,'Category navigation did not sort selected second anvil first')
   click(500,94)
   for byte in ('iron'):gmatch('.')do gui.simulateInput(view,('STRING_A%03d'):format(byte:byte()))end
   view:render(dfhack.getTickCount());assert(menu.item_filter=='IRON');compare_draft('search-retains-draft-order',basis)
   for i=1,4 do gui.simulateInput(view,'STRING_A000')end
   view:render(dfhack.getTickCount());assert(menu.item_filter=='');compare_draft('clear-search-retains-draft-order',basis)
   click(932,166);compare_draft('uncheck-retains-navigation-order',basis)
   click(150,130);click(150,94);compare_draft('navigation-restores-order')
   assert(menu.current_type_tgi[0].it.id==ids[1] and menu.current_type_tgi[1].it.id==ids[2] and draft_text()=='-')
   for _,invalid in ipairs{tostring(ids[1])..':1,'..tostring(ids[1])..':0','2147483647:1'}do
    local _,code=dfhack.run_command_silent('df3d','depot-selection-probe',tostring(b.id),'45','1','1','0','',invalid,'-')
    assert(code~=0,'Invalid draft accepted')
   end
  end
  if os.getenv('DF3D_DEPOT_BATCH_NATIVE')=='1' then
   local ids={menu.current_type_tgi[0].it.id,menu.current_type_tgi[1].it.id}
   local flags={df.item.find(ids[1]).flags.whole,df.item.find(ids[2]).flags.whole}
   click(932,130);assert(#b.jobs==0)
   gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
   local native=job_facts();assert(#native==2,'Native group close did not create both hauls')
   select_map(b);click(520,166);click(932,130)
   gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());assert(#b.jobs==0)
   local selected=df.global.game.main_interface.view_sheets.active_id
   local function apply(wanted,fault)
    local output,code=dfhack.run_command_silent('df3d','depot-haul-batch-probe',tostring(b.id),tostring(wanted),tostring(fault),tostring(ids[1]),tostring(ids[2]))
    assert(code==0,output);local reply=json.decode(output)
    assert(not menu.open and df.global.world.frame_counter==frame and df.global.game.main_interface.view_sheets.active_id==selected)
    return reply.outcome
   end
   for fault=1,3 do
    assert(apply(1,fault)==0,'Invalid batch was not rejected')
    assert(#b.jobs==0 and df.item.find(ids[1]).flags.whole==flags[1] and df.item.find(ids[2]).flags.whole==flags[2],'Rejected batch partially applied')
   end
   assert(apply(1,0)==1);local created=job_facts();assert(#created==2)
   local expected=json.decode(json.encode(native));local actual=json.decode(json.encode(created))
   for i=1,2 do expected[i].id=0;actual[i].id=0 end
   assert(json.encode(expected)==json.encode(actual),'Batch jobs differ from native group commit')
   assert(apply(1,0)==1 and json.encode(job_facts())==json.encode(created),'Duplicate batch changed jobs')
   assert(apply(0,1)==0 and json.encode(job_facts())==json.encode(created),'Invalid cancellation partially applied')
   assert(apply(0,0)==1 and #b.jobs==0 and apply(0,0)==1)
   assert(df.item.find(ids[1]).flags.whole==flags[1] and df.item.find(ids[2]).flags.whole==flags[2])
   result.batch_hauling={ids=ids,native=native,provider=created,rejected_before_mutation=3,stale_cancel_preserved=true,duplicate_preserved=true,cancel_restored=true}
   if os.getenv('DF3D_DEPOT_COMMIT_NATIVE')=='1' then
    local function revision()
     local output,code=dfhack.run_command_silent('df3d','depot-commit-probe',tostring(b.id));assert(code==0,output)
     local value=json.decode(output).revision;assert(type(value)=='string' and value~='0');return value
    end
    local function commit(token,wanted,first,second)
     local output,code=dfhack.run_command_silent('df3d','depot-commit-probe',tostring(b.id),token,tostring(wanted),tostring(first or ids[1]),tostring(second or ids[2]))
     assert(code==0,output)
     assert(not menu.open and df.global.world.frame_counter==frame and df.global.game.main_interface.view_sheets.active_id==selected)
     return json.decode(output)
    end
    local initial=revision()
    local stale=commit('1',1);assert(stale.stale and stale.outcome==0 and stale.revision==initial and #b.jobs==0)
    for _,last in ipairs{ids[1],2147483647}do local bad=commit(initial,1,ids[1],last);assert(not bad.stale and bad.outcome==0 and #b.jobs==0)end
    local applied=commit(initial,1);assert(applied.outcome==1 and not applied.stale and applied.revision==initial and #b.jobs==2)
    local jobs=json.encode(job_facts());local repeat_reply=commit(initial,1)
    assert(repeat_reply.stale and repeat_reply.outcome==0 and json.encode(job_facts())==jobs,'Stale source replay changed jobs')
    local pending=revision();assert(pending~=initial and pending==repeat_reply.revision)
    local cancelled=commit(pending,0);assert(cancelled.outcome==1 and not cancelled.stale and #b.jobs==0)
    local late=commit(pending,0);assert(late.stale and late.outcome==0 and #b.jobs==0)
    assert(df.item.find(ids[1]).flags.whole==flags[1] and df.item.find(ids[2]).flags.whole==flags[2])
    result.revision_commit={initial=initial,pending=pending,applied=applied,cancelled=cancelled,stale_replay=repeat_reply,stale_cancel=late,foreign_rejected=true,duplicate_rejected=true}
   end
   select_map(b);click(520,166);assert(menu.open and menu.current_type==df.item_type.ANVIL)
  end
  result.hauling={}
  click(932,166);capture('depot-goods-selected')
  result.hauling.selected=job_facts()
  gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
  result.hauling.closed=job_facts();capture('depot-goods-hauling')
  select_map(b);click(520,166);assert(menu.open,'Reopen pending goods failed')
  result.hauling.pending={}
  for _,row in ipairs(menu.current_type_tgi)do result.hauling.pending[#result.hauling.pending+1]={id=row.it.id,tag=row.tag,distance=row.dist}end
  capture('depot-goods-pending')
  compare_goods('pending')
  compare_selection('pending')
  click(932,166);result.hauling.deselected=job_facts();compare_draft('pending-cancel-draft')
  gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
  result.hauling.cancelled=job_facts();assert(#b.jobs==0,'Native deselection did not cancel haul')
  if os.getenv('DF3D_DEPOT_HAUL_PROVIDER')=='1' then
   assert(#result.hauling.selected==0 and #result.hauling.closed==1)
   local native=result.hauling.closed[1];local item=df.item.find(native.items[1].id);assert(item)
   local flags=item.flags.whole;local sheet=df.global.game.main_interface.view_sheets;local selected=sheet.active_id
   local function apply(wanted)
    local output,code=dfhack.run_command_silent('df3d','depot-haul-probe',tostring(b.id),tostring(item.id),tostring(wanted))
    assert(code==0,output);local reply=json.decode(output);assert(reply.outcome==1,output)
    assert(not menu.open and sheet.active_id==selected and df.global.world.frame_counter==frame)
    return job_facts()
   end
   result.hauling.provider=apply(1);assert(#result.hauling.provider==1)
   local created=result.hauling.provider[1];local registered=false
   for _,job in require('utils').listpairs(df.global.world.jobs.list)do if job.id==created.id then registered=true end end
   assert(registered and created.id~=native.id)
   local expected=json.decode(json.encode(native));local actual=json.decode(json.encode(created));expected.id=0;actual.id=0
   assert(json.encode(expected)==json.encode(actual),'Provider hauling effects differ')
   local duplicate=apply(1);assert(#duplicate==1 and duplicate[1].id==created.id,'Duplicate added hauling job')
   assert(#apply(0)==0 and #apply(0)==0 and item.flags.whole==flags,'Provider cancellation failed to restore item')
   result.hauling.provider_success=true
  end
  if os.getenv('DF3D_DEPOT_GOODS_PROVIDER')=='1' then
   local item=df.item.find(result.hauling.closed[1].items[1].id)
   assert(item and item.flags.on_ground and not item.flags.in_inventory)
   local pos={x=item.pos.x,y=item.pos.y,z=item.pos.z};local flags=item.flags.whole;local count=#b.contained_items
   restore_delivered=function()
    -- DFHack detach rejects even TEMP items while in_building is set.
    -- This flag adjustment belongs only to disposable fixture restoration.
    local marked=item.flags.in_building;item.flags.in_building=false
    local moved=dfhack.items.moveToGround(item,pos)
    if not moved then item.flags.in_building=marked end
    assert(moved,'Could not restore delivered fixture');item.flags.whole=flags
    assert(#b.contained_items==count);restore_delivered=nil
   end
   assert(dfhack.items.moveToBuilding(item,b,0,true))
   select_map(b);click(520,166);assert(menu.open)
   capture('depot-goods-delivered');compare_goods('delivered')
   compare_selection('delivered')
   local delivered_flags=item.flags.whole
   click(932,166);assert(item.flags.whole==delivered_flags,'Delivered release applied before close');compare_draft('delivered-release-draft')
   gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
   local released_flags=item.flags.whole;assert(not item.flags.in_building and #b.jobs==0)
   item.flags.whole=delivered_flags -- restore only the controlled fixture flag
   for _,wanted in ipairs{1,0,0}do
    local output,code=dfhack.run_command_silent('df3d','depot-haul-probe',tostring(b.id),tostring(item.id),tostring(wanted))
    assert(code==0,output);assert(json.decode(output).outcome==1,output)
    assert(item.flags.whole==(wanted==1 and delivered_flags or released_flags) and #b.jobs==0,'Delivered provider differs')
   end
   result.delivered_release={id=item.id,before=delivered_flags,after=released_flags,provider_success=true}
   restore_delivered()
  end
 end
 if os.getenv('DF3D_DEPOT_GOODS_WIRE')=='1' then
  assert(not menu.open and #b.jobs==0)
  prohibition=df.mandate:new();prohibition.mode=0;prohibition.item_type=45;prohibition.item_subtype=-1;prohibition.mat_type=-1;prohibition.mat_index=-1;prohibition.timeout_limit=1200
  prohibition_index=#df.global.world.mandates.all;df.global.world.mandates.all:insert('#',prohibition)
  select_map(b);click(520,166);assert(menu.open and menu.current_type==45)
  local count=0;for _,entry in ipairs(menu.current_type_tgi)do assert(entry.prohibited);count=count+1 end;assert(count==2)
  capture('depot-goods-prohibited');compare_selection('prohibited')
  click(824,94);assert(menu.exclude_prohib,'Exclude prohibited toggle missed')
  assert(menu.current_type==45 and #menu.current_type_tgi==0 and #menu.current_type_a_subtype==1,'Expected retained empty anvil group')
  capture('depot-goods-excluded');compare_selection('excluded')
  gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
 end
end,debug.traceback)
if menu.open then gui.simulateInput(view,'LEAVESCREEN')end
if prohibition then assert(df.global.world.mandates.all[prohibition_index]==prohibition);df.global.world.mandates.all:erase(prohibition_index);prohibition:delete()end
if restore_delivered then restore_delivered()end
if not ok then local jobs={};for _,j in ipairs(b.jobs)do jobs[#jobs+1]=j end;for _,j in ipairs(jobs)do dfhack.job.removeJob(j)end end
caravans:erase(index);caravan:delete()
assert(df.global.world.frame_counter==frame and #b.jobs==0)
if not ok then error(err)end
result.success=true
local f=assert(io.open(out..'/depot-goods-native.json','w'));f:write(json.encode(result));f:close()
return result
