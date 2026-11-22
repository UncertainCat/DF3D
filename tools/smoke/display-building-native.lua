-- Protected native UI observation only. Runtime must use owned semantic inputs.
local out,view,building,capture,select_map=...
if os.getenv('DF3D_DISPLAY_REASSIGN')=='1' then
 local source=debug.getinfo(1,'S').source:sub(2):gsub('display%-building%-native.lua$','display-reassignment-native.lua')
 return assert(loadfile(source))(out,view,building,capture,select_map)
end
local gui=require('gui');local json=require('json');local g=df.global.gps
local main=df.global.game.main_interface;local picker=main.assign_display_item
local multi=os.getenv('DF3D_DISPLAY_MULTI')=='1'
assert(not multi or os.getenv('DF3D_DISPLAY_ASSIGNMENT')~='1','Multi public fixture does not use the single-item provider comparison')
local function values(v)local result={};for _,value in ipairs(v)do result[#result+1]=value end;return result end
local function click(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
end
local function probe(command,...)
 local args={'df3d',command or 'display-inventory-probe',tostring(building.id)}
 for _,value in ipairs{...}do args[#args+1]=tostring(value)end
 return dfhack.with_suspend(function()
  local guards={}
  for _,storage in ipairs{g,main}do
   local size,address=df.sizeof(storage);local copy=df.new('uint8_t',size)
   dfhack.internal.memmove(copy,address,size);guards[#guards+1]={size=size,address=address,copy=copy}
  end
  local text,code=dfhack.run_command_silent(table.unpack(args))
  local unchanged=true
  for _,guard in ipairs(guards)do
   unchanged=unchanged and dfhack.internal.memcmp(guard.copy,guard.address,guard.size)==0;df.delete(guard.copy)
  end
  assert(code==0,text);assert(unchanged,'Display inventory changed native UI storage')
  return json.decode(text)
 end)
end
local cold_ids
if os.getenv('DF3D_DISPLAY_PROVIDER')=='1' then cold_ids=probe()end
local before={displayed=values(building.displayed_items),jobs=#building.jobs}
g.precise_mouse_x=520;g.precise_mouse_y=406;g.mouse_x=65;g.mouse_y=33
df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
assert(picker.open and picker.display_bld==building,'Display assignment did not open')
capture('display-assignment-open');view:render(dfhack.getTickCount());capture('display-assignment-settled')
local result={id=building.id,before=before,types=values(picker.type_list),filtered_types=values(picker.filtered_type_list),
 current_type=picker.current_type,storeamount=values(picker.storeamount),badamount=values(picker.badamount),
 draft=values(picker.new_display_itid),master_ids={},current_ids={},height=picker.i_height,lines={}}
local context_size,context_address=df.sizeof(picker)
result.context_size=context_size;result.context_rva=context_address-dfhack.internal.getImageBase()
local function checkpoint()
 local file=assert(io.open(out..'/display-building-native.json','w'));file:write(json.encode(result));file:close()
end
local function compare_picker(label)
 if os.getenv('DF3D_DISPLAY_PICKER')~='1' then return end
 local owned=probe('display-picker-probe',picker.current_type,dfhack.df2utf(picker.item_filter))
 local native={height=picker.i_height,categories=values(picker.filtered_type_list),stored=values(picker.storeamount),unavailable=values(picker.badamount),items={},groups={}}
 for _,item in ipairs(picker.current_type_i_list)do native.items[#native.items+1]=item.id end
 for i,subtype in ipairs(picker.current_type_a_subtype)do
  native.groups[#native.groups+1]={subtype=subtype,subcat1=picker.current_type_a_subcat1[i],subcat2=picker.current_type_a_subcat2[i],amount=picker.current_type_a_amount[i],expanded=picker.current_type_a_expanded[i],matches=picker.current_type_a_on[i]}
 end
 result.picker_comparisons=result.picker_comparisons or {};result.picker_comparisons[#result.picker_comparisons+1]={label=label,native=native,owned=owned};checkpoint()
 for _,key in ipairs{'height','categories','stored','unavailable','items'}do assert(json.encode(native[key])==json.encode(owned[key]),'Display picker '..label..' '..key..' differs')end
 assert(#native.groups==#owned.groups,'Display group count differs')
 for i,group in ipairs(native.groups)do for key,value in pairs(group)do assert(value==owned.groups[i][key],'Display group '..label..' '..i..' '..key..' differs')end end
 return owned
end
for _,item in ipairs(picker.master_i_list.l_item)do result.master_ids[#result.master_ids+1]=item.id end
for _,item in ipairs(picker.current_type_i_list)do result.current_ids[#result.current_ids+1]=item.id end
compare_picker('initial')
if os.getenv('DF3D_DISPLAY_PROVIDER')=='1' then
 local before_scratch={};for _,item in ipairs(df.global.world.items.other.IN_PLAY)do before_scratch[#before_scratch+1]=item.base_uniform_score end
 result.owned_ids=probe()
 result.cold_ids=cold_ids
 assert(json.encode(cold_ids)==json.encode(result.owned_ids),'Display cold/open inventory differs')
 assert(json.encode(result.master_ids)==json.encode(result.owned_ids),'Owned display inventory/order differs')
 local after_scratch={};for _,item in ipairs(df.global.world.items.other.IN_PLAY)do after_scratch[#after_scratch+1]=item.base_uniform_score end
 assert(json.encode(before_scratch)==json.encode(after_scratch),'Owned display inventory changed item scratch')
end
for y=4,58 do local chars={}
 for x=0,112 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
 local text=dfhack.df2utf(table.concat(chars)):gsub('%s+$','');if text:find('%S')then result.lines[#result.lines+1]={y=y,text=text}end
end
if os.getenv('DF3D_DISPLAY_SELECT')=='1' then
 click(160,130);assert(picker.current_type==df.item_type.AMULET)
 capture('display-amulets')
 compare_picker('amulets')
 if os.getenv('DF3D_DISPLAY_INPUT')=='1' then
  local expanded=picker.current_type_a_expanded[0];local height=picker.i_height
  click(500,130)
  local collapsed=picker.current_type_a_expanded[0];local collapsed_height=picker.i_height
  click(500,130)
  assert(picker.current_type_a_expanded[0]==expanded and picker.i_height==height,'Display group restoration differs')
  local draft_before=values(picker.new_display_itid)
  click(500,166)
  local draft_after=values(picker.new_display_itid)
  result.input={expanded=expanded,after_group=collapsed,height=height,collapsed_height=collapsed_height,name_click_unchanged=json.encode(draft_before)==json.encode(draft_after)}
  checkpoint()
  assert(collapsed==expanded and collapsed_height==height and result.input.name_click_unchanged,'Display group/name click unexpectedly edits')
  if not result.input.name_click_unchanged then click(500,166) end
  assert(json.encode(draft_before)==json.encode(values(picker.new_display_itid)),'Display name click restoration differs')
 end

 if os.getenv('DF3D_DISPLAY_PICKER')=='1' then
  click(500,94)
  for ch in ('steel'):gmatch('.')do gui.simulateInput(view,string.format('STRING_A%03d',ch:byte()))end
  view:render(dfhack.getTickCount());capture('display-search-steel');compare_picker('steel')
  for _=1,5 do gui.simulateInput(view,'STRING_A000')end
  view:render(dfhack.getTickCount());assert(picker.item_filter=='');compare_picker('cleared')
  click(160,130);assert(picker.current_type==df.item_type.AMULET)
 end
 local candidate=assert(picker.current_type_i_list[0]);local candidate_id=candidate.id
 local function snapshot()
  local jobs={};for _,job in ipairs(building.jobs)do jobs[#jobs+1]={id=job.id,type=df.job_type[job.job_type]}end
  local refs={};for _,ref in ipairs(candidate.general_refs)do refs[#refs+1]={type=df.general_ref_type[ref:getType()],building=ref:getBuilding() and ref:getBuilding().id or -1}end
  return {displayed=values(building.displayed_items),draft=values(picker.new_display_itid),jobs=jobs,item_flags=tostring(candidate.flags.whole),item_flags2=tostring(candidate.flags2.whole),item_refs=refs}
 end
 result.selection={id=candidate_id,ids={candidate_id},before=snapshot()}
 click(916,166)
 if multi then
  local second=assert(picker.current_type_i_list[1]);result.selection.ids[#result.selection.ids+1]=second.id
  click(916,202);assert(#picker.new_display_itid==2,'Native multi-checkbox draft differs')
 end
 result.selection.selected=snapshot();capture('display-selected-draft')
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
 assert(not picker.open);result.selection.closed=snapshot();checkpoint()
 -- Escape closes the assignment screen and its parent sheet. Re-select the
 -- building through the ordinary map route before observing/removing the item.
 select_map(building);view:render(dfhack.getTickCount());capture('display-selected-parent')
 if os.getenv('DF3D_DISPLAY_PICKER')=='1' then
  local owned=probe('display-picker-probe',df.item_type.AMULET,'')
  assert(#owned.body==#result.selection.ids,'Display assigned body count differs')
  for i,row in ipairs(owned.body)do
   assert(row.id==building.displayed_items[i-1] and row.resolved and not row.on_display and row.status=='Assigned' and row.color==15,'Display assigned body differs')
  end
  result.assigned_body=owned.body;checkpoint()
 end
 for _=1,#result.selection.ids do
  assert(#building.displayed_items>#before.displayed,'Display removal lost additional selection')
  click(880,142)
 end
 result.selection.removed=snapshot();checkpoint();capture('display-removed-parent')
 assert(#building.displayed_items==#before.displayed,'Display parent removal missed')
 if os.getenv('DF3D_DISPLAY_ASSIGNMENT')=='1' then
  local authority=probe('display-assignment-probe')
  local command='display-assignment-probe';local draft_revision=authority.revision
  if os.getenv('DF3D_DISPLAY_READ')=='1' then
   command='display-draft-probe'
   local first=probe('display-read-probe',-2,'')
   local page=probe('display-read-probe',df.item_type.AMULET,'',candidate_id)
   local repeated=probe('display-read-probe',df.item_type.AMULET,'',candidate_id)
   assert(first.category==df.item_type.AMMO and first.inventory_revision==page.inventory_revision,'Display initial category/source differs')
   assert(page.revision==authority.revision and page.inventory_revision==repeated.inventory_revision,'Drawing display item changed authority')
   assert(#page.items==1 and page.items[1].id==candidate_id and page.items[1].appearance,'Display visible-page item missing')
   local flags=candidate.flags.whole;candidate.flags.forbid=true
   local changed=probe(command,page.inventory_revision,1,candidate_id)
   candidate.flags.whole=flags
   assert(changed.outcome==2 and not changed.effects_started,'Changed display inventory accepted')
   result.read_provider={initial=first,page=page,repeated=repeated,changed=changed}
   draft_revision=page.inventory_revision
  end
  local invalid=probe(command,draft_revision,1,candidate_id,candidate_id)
  assert(invalid.outcome==0 and not invalid.effects_started,'Duplicate display draft accepted')
  local assigned=probe(command,draft_revision,1,candidate_id)
  assert(assigned.outcome==1 and assigned.effects_started,'Owned display assignment failed')
  result.selection.owned_assigned=snapshot()
  assert(json.encode(result.selection.owned_assigned)==json.encode(result.selection.closed),'Owned display assignment effects differ')
  local stale=probe(command,authority.revision,0,candidate_id)
  assert(stale.outcome==2 and not stale.effects_started,'Stale display removal accepted')
  local removed=probe(command,assigned.revision,0,candidate_id)
  assert(removed.outcome==1 and removed.effects_started,'Owned display removal failed')
  result.selection.owned_removed=snapshot()
  assert(json.encode(result.selection.owned_removed)==json.encode(result.selection.removed),'Owned display removal effects differ')
  result.assignment_provider={assigned=assigned,removed=removed,stale=stale,duplicate=invalid}
  checkpoint()
 end
 click(520,406);assert(picker.open)
end
gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
assert(not picker.open,'Display assignment did not close');capture('display-assignment-closed')
result.after={displayed=values(building.displayed_items),jobs=#building.jobs}
assert(json.encode(before)==json.encode(result.after),'Display open/close changed assignment')
if os.getenv('DF3D_DISPLAY_SCENE')=='1' then
 select_map(building);view:render(dfhack.getTickCount());capture('display-scene-initial')
 local original=building.name;assert(#building.jobs==0)
 click(800,82);gui.simulateInput(view,'STRING_A120');gui.simulateInput(view,'SELECT');assert(building.name==original..'x');capture('display-scene-renamed')
 click(800,82);gui.simulateInput(view,'STRING_A000');gui.simulateInput(view,'SELECT');assert(building.name==original);capture('display-scene-restored')
 click(832,82);assert(#building.jobs==1 and building.jobs[0].job_type==df.job_type.DestroyBuilding);capture('display-scene-removing')
 click(520,202);assert(#building.jobs==0);capture('display-scene-cancelled')
end
if os.getenv('DF3D_DISPLAY_WIRE')=='1' then
 local expected={tile={building.centerx,building.centery,building.z},custom_name=dfhack.df2utf(building.name),id=building.id,item_id=result.selection.id,item_ids=result.selection.ids,assigned_ids=result.selection.closed.displayed,picker=result.picker_comparisons[2].owned}
 local large=os.getenv('DF3D_DISPLAY_LARGE_REPLY')=='1'
 local saved=values(building.displayed_items)
 if large then
  expected.large_ids={}
  for _,candidate in ipairs(df.global.world.items.all)do
   expected.large_ids[#expected.large_ids+1]=candidate.id
   if #expected.large_ids>=20000 then break end
  end
  assert(#expected.large_ids>=12000,'Large Display oracle requires enough existing items')
  building.displayed_items:resize(0)
  for _,id in ipairs(expected.large_ids)do building.displayed_items:insert('#',id)end
 end
 local f=assert(io.open(out..'/display-wire-expected.json','w'));f:write(json.encode(expected));f:close()
 local ok,err=pcall(capture,'display-wire')
 if large then building.displayed_items:resize(0);for _,id in ipairs(saved)do building.displayed_items:insert('#',id)end end
 assert(ok,err)
 f=assert(io.open(out..'/display-wire-result.json'));result.wire=json.decode(f:read('*a'));f:close()
 assert(result.wire.success and #building.displayed_items==#before.displayed and #building.jobs==before.jobs,'Display wire failed to restore')
end
result.success=true
local file=assert(io.open(out..'/display-building-native.json','w'));file:write(json.encode(result));file:close()
return result
