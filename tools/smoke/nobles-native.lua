-- Protected native discovery only. Menu storage is never a runtime input.
local out,view,records=...
local gui=require('gui');local script=require('gui.script');local json=require('json');local g=df.global.gps
local function write(name,value)local f=assert(io.open(out..'/'..name,'w'));f:write(value);f:close()end
local function settle()for _=1,3 do script.sleep(1,'frames')end;view:render(dfhack.getTickCount())end
local function lines()
 local result={}
 for y=0,g.dimy-1 do
  local chars={};for x=0,g.dimx-1 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
  result[#result+1]={y=y,text=dfhack.df2utf(table.concat(chars)):gsub('%s+$','')}
 end
 return result
end
local function capture(name)
 write('shot.tmp',name);assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local deadline=dfhack.getTickCount()+10000
 while true do local ack=io.open(out..'/ack-'..name);if ack then ack:close();break end;assert(dfhack.getTickCount()<deadline,'Nobles capture timeout');script.sleep(1,'frames')end
end
local function bytes(address,size)
 local chars={};for offset=0,size-1 do chars[#chars+1]=string.char(df.reinterpret_cast('uint8_t',address+offset).value)end
 return table.concat(chars)
end
local function cache_snapshot()
 local result={}
 for _,unit in ipairs(df.global.world.units.active)do
  result[#result+1]={unit.id,unit.enemy.histfig_vector_idx}
  local hf=df.historical_figure.find(unit.hist_figure_id)
  if hf then for _,link in ipairs(hf.entity_links)do
   if link:getType()==df.histfig_entity_link_type.POSITION then
    local assignment=-1;local entity=df.historical_entity.find(link.entity_id)
    if entity then for _,entry in ipairs(entity.positions.assignments)do if entry.id==link.assignment_id then assignment=entry.position_vector_idx;break end end end
    result[#result+1]={hf.id,link.entity_id,link.entity_vector_idx,link.assignment_id,link.assignment_vector_idx,assignment}
   end
  end end
 end
 return json.encode(result)
end
local function probe(command)
 local menu=df.global.game.main_interface.info.administrators
 local size,address=df.sizeof(menu);local before=bytes(address,size)
 local base=dfhack.internal.getImageBase();local rng={}
 for _,range in ipairs{{0x234e990,0x6180},{0x2131b30,40},{0x2159084,2},{0x18adf98,8}}do rng[#rng+1]={range[1],range[2],bytes(base+range[1],range[2])}end
 local caches=cache_snapshot()
 local output,rc=dfhack.run_command_silent('df3d',table.unpack(command or {'nobles-overview-probe'}))
 assert(rc==0,'Owned Nobles overview failed: '..output)
 assert(bytes(address,size)==before,'Owned Nobles overview changed native menu')
 for _,r in ipairs(rng)do assert(bytes(base+r[1],r[2])==r[3],'Owned Nobles overview advanced randomness')end
 assert(caches==cache_snapshot(),'Owned Nobles read changed lookup caches')
 return json.decode(output)
end
local cold=probe()
local cold_candidates={}
for _,row in ipairs(cold)do if row.position_name=='manager' or row.position_name=='messenger' then
 cold_candidates[row.position_name]=probe({'nobles-candidates-probe',tostring(row.entity_id),tostring(row.position_id),tostring(row.assignment_id)})
end end
gui.simulateInput(view,'D_NOBLES');settle()
local info=df.global.game.main_interface.info
assert(info.open and info.current_mode==df.info_interface_mode_type.ADMINISTRATORS,'Nobles shortcut failed')
local menu=info.administrators
local rows={}
for _,row in ipairs(menu.noblelist)do
 rows[#rows+1]={unit_id=row.un and row.un.id or -1,nemesis_id=row.nem and row.nem.id or -1,entity_id=row.enid,position_id=row.ep and row.ep.id or -1,assignment_id=row.epp and row.epp.id or -1,value=row.value,position_name=row.ep and dfhack.df2utf(row.ep.name[0])or''}
end
-- Observe the actual plus-button input for every captured row. Cancel each
-- picker without selecting an appointment; no eligibility formula in the oracle.
for index,row in ipairs(rows)do
 local x,y=232,178+(index-1)*36
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=y//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1;settle()
 row.can_appoint=menu.choosing_candidate
 if menu.choosing_candidate then
  assert(menu.candidate_noblelist_ind==index-1,'Appointment button selected wrong row')
  gui.simulateInput(view,'LEAVESCREEN');settle();assert(not menu.choosing_candidate,'Appointment Cancel failed')
 end
 assert(info.open and info.current_mode==df.info_interface_mode_type.ADMINISTRATORS,'Appointment button left overview')
end
local warm=probe()
write('nobles-caption-observed.json',json.encode({cold=cold,warm=warm,lines=lines()}))
local room_reference={}
local function native_icon(rva,x,y)
 local base=dfhack.internal.getImageBase()
 for dx=0,3 do for dy=0,2 do
  local tile=df.reinterpret_cast('int32_t',base+rva+(dx*3+dy)*4).value
  local offset=(x+dx)*g.dimy+y+dy
  assert(tile>0 and (g.screentexpos_lower[offset]==tile or g.screentexpos_top_lower[offset]==tile),'Nobles status artwork differs at '..(x+dx)..','..(y+dy)..' expected '..tile..' actual '..g.screentexpos_lower[offset]..' top '..g.screentexpos_top_lower[offset])
 end end
end
local room_matrices={0x264fe68,0x264fda8,0x264ff28,0x264ffe8}
for index,owned in ipairs(warm)do
 local native=menu.noblelist[index-1]
 assert(owned.has_room_assessment==(native.un~=nil),'Nobles assessment presence differs')
 if native.un then
  local requirements={0,0,0,0};local furniture={0,0,0,0}
  local room_fields={'required_office','required_bedroom','required_dining','required_tomb'}
  local furniture_fields={'required_boxes','required_cabinets','required_racks','required_stands'}
  -- Independent semantic cross-check against the actual native builder arrays.
  for i,assignment in ipairs(menu.spec_prof)do if assignment and menu.spec_hfid[i]==native.un.hist_figure_id then
   local entity=df.historical_entity.find(menu.spec_enid[i])
   if entity then for _,position in ipairs(entity.positions.own)do if position.id==assignment.position_id then
    for k,field in ipairs(room_fields)do requirements[k]=math.max(requirements[k],position[field])end
    if entity.id==df.global.plotinfo.group_id or entity.id==df.global.plotinfo.civ_id then
     for k,field in ipairs(furniture_fields)do furniture[k]=math.max(furniture[k],position[field])end
    end
   end end end
  end end
  assert(json.encode(requirements)==json.encode(owned.required_rooms),'Native room requirements differ')
  assert(json.encode(furniture)==json.encode(owned.required_furniture),'Native furniture requirements differ')
  local actual={native.upplist.boxcount,native.upplist.cabcount,native.upplist.rackcount,native.upplist.standcount}
  assert(json.encode(actual)==json.encode(owned.actual_furniture),'Native furnishing counts differ')
  local states={};local furniture_state=0
  for k=1,4 do
   local required,value=owned.required_rooms[k],owned.actual_rooms[k]
   local state=required<=0 and 0 or value>=required and 3 or value<=0 and 1 or 2
   states[k]=state;native_icon(room_matrices[k]+state*0x30,72+(k-1)*4,13+(index-1)*3)
   if actual[k]<furniture[k] then furniture_state=math.max(furniture_state,actual[k]<=0 and 2 or 1)end
  end
  native_icon(0x26502b8+(furniture_state==2 and 1 or furniture_state==1 and 2 or 0)*0x30,88,13+(index-1)*3)
  native_icon(0x26500d8+(owned.demand_status+1)*0x30,94,13+(index-1)*3)
  native_icon(0x26501c8+(owned.mandate_status+1)*0x30,98,13+(index-1)*3)
  room_reference[#room_reference+1]={unit_id=owned.unit_id,demand_status=owned.demand_status,mandate_status=owned.mandate_status,room_states=states,furniture_state=furniture_state,required_rooms=requirements,actual_rooms=owned.actual_rooms,required_furniture=furniture,actual_furniture=actual}
 end
 for _,field in ipairs{'demand_status','mandate_status','has_room_assessment','required_rooms','actual_rooms','required_furniture','actual_furniture'}do rows[index][field]=owned[field]end
end
local caption_reference={}
local function cells(x,y,count)
 local chars={};for i=0,count-1 do local ch=dfhack.screen.readTile(x+i,y).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
 return table.concat(chars):gsub('%s+$','')
end
for index,row in ipairs(rows)do
 local owned=warm[index];local y=14+(index-1)*3
 local title=cells(6,y,22);local squad=cells(6,y+1,20);local holder=cells(39,y,26)
 assert(title==dfhack.utf2df(owned.title),'Office title differs: '..index..' ['..title..'] vs ['..dfhack.utf2df(owned.title)..']')
 assert(squad==dfhack.utf2df(owned.squad_caption),'Squad caption differs: '..index)
 local full=dfhack.utf2df(owned.holder_caption)
 if holder:sub(-3)=='...' then
  assert(full:sub(1,#holder-3)==holder:sub(1,-4) and #full>#holder,'Clipped holder caption differs: '..index)
 else assert(full==holder,'Holder caption differs: '..index)end
 caption_reference[#caption_reference+1]={title=dfhack.df2utf(title),squad=dfhack.df2utf(squad),holder_visible=dfhack.df2utf(holder),holder_full=owned.holder_caption}
 row.title=owned.title;row.squad_caption=owned.squad_caption;row.holder_caption=owned.holder_caption
end
assert(json.encode(cold)==json.encode(rows) and json.encode(warm)==json.encode(rows),'Owned Nobles overview differs from native order/identities')
local result={room_reference=room_reference,caption_reference=caption_reference,owned={cold=cold,warm=warm,menu_preserved=true,rng_preserved=true},dimensions={g.dimx,g.dimy},rows=rows,lines=lines(),scroll=menu.scroll_position_noblelist,choosing_candidate=menu.choosing_candidate,assigning_symbol=menu.assigning_symbol}
write('nobles-native.json',json.encode(result));capture('nobles-overview')
-- Native hover discovery: sample actual input/rendering, never use these menu
-- fields as runtime sources. Preserve whole text cells because Nobles also draws
-- holder-specific help in place of its introduction rather than only the global help.
local function hover_sample(kind,x,y)
 local deadline=dfhack.getTickCount()+650
 repeat
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
  g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
  df.global.game.main_interface.current_hover=0
  gui.simulateInput(view,{});view:render(dfhack.getTickCount());script.sleep(1,'frames')
 until dfhack.getTickCount()>=deadline
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 gui.simulateInput(view,{});view:render(dfhack.getTickCount())
 return {kind=kind,x=x,y=y,instruction=df.global.game.main_interface.current_hover,lines=lines()}
end
if os.getenv('DF3D_NOBLES_HOVER')=='1' then
 result.hover={}
 for _,target in ipairs{{'appointment',232,250},{'portrait',272,178},{'title',96,178},{'symbol',544,178},{'office',592,178},{'bedroom',624,178},{'dining',656,178},{'tomb',688,178},{'furniture',720,178},{'demands',768,178},{'mandates',800,178},{'footer-clear',900,700}}do
  result.hover[#result.hover+1]=hover_sample(table.unpack(target))
 end
 result.owned_help=probe({'nobles-help-probe'})
 result.room_help_reference={}
 for index,row in ipairs(result.owned_help)do if row.unit_id>=0 then
  local sample=hover_sample('rooms-'..index,592,178+(index-1)*36)
  for kind,room in ipairs(row.help.rooms)do
   local x=6+54*((kind-1)//2);local y=10+(kind-1)%2
   assert(cells(x,y,#dfhack.utf2df(room.actual))==dfhack.utf2df(room.actual),'Native room hover caption differs')
   if room.required~=''then assert(cells(x+27,y,#dfhack.utf2df(room.required))==dfhack.utf2df(room.required),'Native required room hover differs')end
   local tile=dfhack.screen.readTile(x,y);local color=tile.fg+((tile.bold and tile.bold~=0) and 8 or 0)
   assert(color==room.color,'Native room hover color differs: '..color..' vs '..room.color)
  end
  result.room_help_reference[#result.room_help_reference+1]={unit_id=row.unit_id,rooms=row.help.rooms,native_text_colors_match=true}
 end end
 result.furniture_help_reference={};result.mandate_help_reference={}
 for index,row in ipairs(result.owned_help)do if row.unit_id>=0 then
  hover_sample('furniture-'..index,720,178+(index-1)*36)
  for kind,part in ipairs(row.help.furniture)do if part.actual~=''then
   local x=6+54*((kind-1)//2);local y=10+(kind-1)%2
   assert(cells(x,y,#dfhack.utf2df(part.actual))==dfhack.utf2df(part.actual),'Native furniture caption differs')
   if part.required~=''then assert(cells(x+27,y,#dfhack.utf2df(part.required))==dfhack.utf2df(part.required),'Native furniture requirement differs')end
   local tile=dfhack.screen.readTile(x,y);local color=tile.fg+((tile.bold and tile.bold~=0) and 8 or 0)
   assert(color==part.color,'Native furniture hover color differs')
  end end
  result.furniture_help_reference[#result.furniture_help_reference+1]={unit_id=row.unit_id,parts=row.help.furniture,native_text_colors_match=true}
  hover_sample('mandates-'..index,800,178+(index-1)*36)
  for offset,item in ipairs(row.help.mandates)do
   local x=6+30*((offset-1)//3);local y=10+(offset-1)%3
   assert(cells(x,y,#dfhack.utf2df(item.text))==dfhack.utf2df(item.text),'Native mandate caption differs: '..item.text)
   local tile=dfhack.screen.readTile(x,y);local color=tile.fg+((tile.bold and tile.bold~=0) and 8 or 0)
   assert(color==item.color,'Native mandate hover color differs')
  end
  result.mandate_help_reference[#result.mandate_help_reference+1]={unit_id=row.unit_id,items=row.help.mandates,native_text_colors_match=true}
 end end
 result.hover[#result.hover+1]=hover_sample('manager-description',544,394)
 result.hover[#result.hover+1]=hover_sample('bookkeeper-symbol',544,502)
 result.hover[#result.hover+1]=hover_sample('rooms-final',592,178)
 write('nobles-native.json',json.encode(result))
 capture('nobles-hover-rooms')
end
-- Controlled semantic cases in the paused unsaved clone. Native renders the
-- changed demand; the owned provider must agree with every indicator tile.
local demand_target=menu.noblelist[1].un
assert(demand_target and #demand_target.status.demands==0,'Demand fixture needs the mayor without existing demands')
local demand=df.unit_demand:new();demand.overtype=df.demand_type.ROOM_ITEM;demand.place=df.demand_room.Office
 demand.item_subtype=-1;demand.mat_type=-1;demand.mat_index=-1;demand.timeout_limit=10000
 demand_target.status.demands:insert('#',demand)
result.demand_cases={}
for _,case in ipairs{{-1,0,0},{df.item_type.DRINK,0,1},{df.item_type.DRINK,2500,2},{df.item_type.DRINK,5000,3}}do
 demand.item_type=case[1];demand.timeout_counter=case[2];settle()
 local owned=probe();assert(owned[2].demand_status==case[3],'Controlled demand status differs')
 native_icon(0x26500d8+(owned[2].demand_status+1)*0x30,94,16)
 result.demand_cases[#result.demand_cases+1]={item_type=case[1],elapsed=case[2],status=owned[2].demand_status,native_icon_match=true}
 if os.getenv('DF3D_NOBLES_HOVER')=='1' then
  local help=probe({'nobles-help-probe'})[2].help.demands[1]
  hover_sample('controlled-demand',768,214)
  assert(cells(6,10,#dfhack.utf2df(help.text))==dfhack.utf2df(help.text),'Native demand caption differs: '..help.text)
  local tile=dfhack.screen.readTile(6,10);local color=tile.fg+((tile.bold and tile.bold~=0) and 8 or 0)
  assert(color==help.color,'Native demand hover color differs')
  result.demand_cases[#result.demand_cases].help=help
  result.demand_cases[#result.demand_cases].native_help_match=true
 end
end
demand_target.status.demands:erase(#demand_target.status.demands-1);demand:delete();settle()
write('nobles-native.json',json.encode(result))
local _,menu_address=df.sizeof(menu);result.menu_rva=menu_address-dfhack.internal.getImageBase()
result.field_rvas={}
for _,field in ipairs{'noblelist','candidate','choosing_candidate','candidate_noblelist_ind'}do
 local _,address=df.sizeof(menu:_field(field));result.field_rvas[field]=address-dfhack.internal.getImageBase()
end
result.pickers={}
for _,target in ipairs{{'manager',232,394},{'messenger',232,646}}do
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=target[2];g.precise_mouse_y=target[3];g.mouse_x=target[2]//8;g.mouse_y=target[3]//12
 df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L')
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1;settle()
 assert(menu.choosing_candidate,'Appointment picker did not open')
 local selected=rows[menu.candidate_noblelist_ind+1];assert(selected.position_name==target[1],'Wrong appointment target')
 local candidates={};for _,row in ipairs(menu.candidate)do candidates[#candidates+1]={unit_id=row.un and row.un.id or -1,value=row.value}end
 local owned=probe({'nobles-candidates-probe',tostring(selected.entity_id),tostring(selected.position_id),tostring(selected.assignment_id)})
 assert(json.encode(owned)==json.encode(candidates) and json.encode(cold_candidates[target[1]])==json.encode(candidates),'Owned candidate ordering/value differs')
 result.pickers[#result.pickers+1]={position=target[1],selected=selected,candidates=candidates,lines=lines(),owned_cold_warm_equal=true,menu_rng_caches_preserved=true}
 local text=probe({'nobles-candidate-text-probe',tostring(selected.entity_id),tostring(selected.position_id),tostring(selected.assignment_id)})
 local observed={}
 for index=1,math.min(#text,17)do
  local row=text[index];assert(row.unit_id==candidates[index].unit_id and row.value==candidates[index].value)
  local y=11+(index-1)*3;local caption=cells(13,y,42);local full=dfhack.utf2df(row.caption)
  if caption:sub(-3)=='...' then
   assert(full:sub(1,#caption-3)==caption:sub(1,-4) and #full>#caption,'Candidate clipped name differs')
  else assert(caption==full,'Candidate name differs: '..caption..' vs '..full)end
  local skill=cells(57,y,20)
  if row.unit_id>=0 then
   local expected=#row.skills>0 and dfhack.utf2df(row.skills[1].caption) or row.no_skills
   assert(skill==expected,'Candidate first skill differs: '..skill..' vs '..expected)
  end
  observed[#observed+1]={unit_id=row.unit_id,caption=dfhack.df2utf(caption),first_skill=dfhack.df2utf(skill)}
 end
 result.pickers[#result.pickers].text_reference={rows=text,visible=observed,menu_rng_caches_preserved=true}
 write('nobles-native.json',json.encode(result));capture('nobles-candidates-'..target[1])
 gui.simulateInput(view,'LEAVESCREEN');settle();assert(info.open and not menu.choosing_candidate,'Picker Cancel did not return to overview')
end

if os.getenv('DF3D_NOBLES_SYMBOLS')=='1' then
 local index,office
 for i,row in ipairs(menu.noblelist)do if row.ep.name[0]=='manager' then index=i;office=rows[i+1];break end end
 assert(index and office and office.assignment_id>=0,'Missing Manager symbol office')
 local symbol_command={'nobles-symbols-probe',tostring(office.entity_id),tostring(office.position_id),tostring(office.assignment_id)}
 local function staged(revision,...)
  return probe({'nobles-symbol-stage-probe',tostring(office.entity_id),tostring(office.position_id),tostring(office.assignment_id),tostring(revision),...})
 end
 local cold_symbols=probe(symbol_command)
 local function compare_symbols(owned)
  assert(#owned==#menu.cand_symbol,'Owned symbol candidate count differs')
  local function compare_office(actual,ind)
   if ind==-1 then assert(actual==nil,'Unexpected symbol office');return end
   local row=menu.noblelist[ind]
   assert(actual and actual.entity_id==row.enid and actual.position_id==row.ep.id and
    actual.assignment_id==(row.epp and row.epp.id or -1) and actual.draft_slot==0,'Symbol office identity differs')
  end
  for i,item in ipairs(menu.cand_symbol)do
   local row=owned[i+1];assert(row.item_id==item.id and row.value==menu.cand_symbol_value[i],'Symbol order/value differs at '..i)
   compare_office(row.current_office,menu.cand_symbol_is_symbol_of_ind[i])
   compare_office(row.selected_office,menu.cand_symbol_new_ind[i])
  end
 end
 local x,y=544,178+index*36
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=y//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1;settle()
 assert(menu.assigning_symbol and menu.symbol_noblelist_ind==index,'Wrong native symbol picker')
 compare_symbols(cold_symbols);compare_symbols(probe(symbol_command))
 assert(staged(1).stale,'Stale symbol revision was accepted')
 assert(staged(0,'-1','1').rejected,'Missing symbol item was accepted')
 assert(staged(0,tostring(menu.cand_symbol[0].id),'1',tostring(menu.cand_symbol[0].id),'0').rejected,'Duplicate symbol edit was accepted')
 local symbols={}
 for i,item in ipairs(menu.cand_symbol)do
  symbols[#symbols+1]={item_id=item.id,new_index=menu.cand_symbol_new_ind[i],current_index=menu.cand_symbol_is_symbol_of_ind[i],value=menu.cand_symbol_value[i]}
 end
 result.symbol_reference={office=office,rows=symbols,lines=lines(),columns=g.dimx,height=g.dimy,owned_candidates_match=true}
 if os.getenv('DF3D_NOBLES_SYMBOL_TEXT')=='1' then
  local function text_rows()
   local actual=probe({'nobles-symbol-text-probe',tostring(office.entity_id),tostring(office.position_id),tostring(office.assignment_id),'0','15'})
   assert(#actual==15)
   for i,row in ipairs(actual)do
    local chars={};for column=0,g.dimx-1 do chars[#chars+1]=string.char(dfhack.screen.readTile(column,15+(i-1)*3).ch)end
    local line=table.concat(chars);local caption=dfhack.utf2df(row.caption);local value=dfhack.utf2df(row.value)
    if #caption<23 then assert(line:find(caption,1,true),'Native symbol caption differs at '..i)end
    if #value>0 then assert(line:find(value,1,true),'Native symbol value differs at '..i..': '..row.value)
    else assert(not line:find('Value: ',1,true),'Owned symbol value missing')end
   end
   return actual
  end
  result.symbol_reference.text={initial=text_rows()}
  local assignment
  for _,row in ipairs(menu.noblelist)do if row.ep.responsibilities.TRADE and row.epp then assignment=row.epp;break end end
  assert(assignment,'Missing broker assignment')
  local holder
  for _,unit in ipairs(df.global.world.units.active)do if unit.hist_figure_id>=0 and unit.status.current_soul then holder=unit;break end end
  assert(holder)
  local previous=assignment.histfig
  local trade=df.global.plotinfo.main.fortress_entity.assignments_by_type.TRADE
  local inserted=true;for _,entry in ipairs(trade)do if entry==assignment then inserted=false end end
  local insertion_index=#trade
  local ok,err=xpcall(function()
   assignment.histfig=holder.hist_figure_id;if inserted then trade:insert('#',assignment)end;settle()
   result.symbol_reference.text.with_broker=text_rows()
   assert(#result.symbol_reference.text.with_broker[1].value>0,'Broker value remained hidden')
  end,debug.traceback)
  assignment.histfig=previous;if inserted then trade:erase(insertion_index)end;settle();assert(ok,err)
  result.symbol_reference.text.broker_restored=true
 end
 write('nobles-native.json',json.encode(result));capture('nobles-symbols-manager')
 if os.getenv('DF3D_NOBLES_SYMBOL_RESIZE')=='1' then
  result.symbol_reference.resize={}
  for _,size in ipairs({'minimum','wide','default'})do
   write('owner-input-request.tmp','name-resize-'..size);assert(os.rename(out..'/owner-input-request.tmp',out..'/owner-input-request'))
   local deadline=dfhack.getTickCount()+10000
   while true do local ack=io.open(out..'/owner-input-ack');if ack then ack:close();break end;assert(dfhack.getTickCount()<deadline,'Symbol resize timed out');script.sleep(1,'frames')end
   assert(os.remove(out..'/owner-input-ack'));script.sleep(5,'frames');settle()
   result.symbol_reference.resize[#result.symbol_reference.resize+1]={size=size,columns=g.dimx,height=g.dimy,first=menu.scroll_position_symbol,count=#menu.cand_symbol,lines=lines()}
   capture('nobles-symbols-'..size)
  end
 end
 gui.simulateInput(view,'LEAVESCREEN');settle()
 assert(info.open and not menu.assigning_symbol and menu.handling_symbol_closure_ind==-1,'Symbol Back did not return to overview')
 result.symbol_reference.back_returns_overview=true
 result.symbol_reference.effects={}
 local function click_symbol(px,py)
  g.precise_mouse_x=px;g.precise_mouse_y=py;g.mouse_x=px//8;g.mouse_y=py//12
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
  gui.simulateInput(view,'_MOUSE_L');df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1;settle()
 end
 local artifact
 for _,ref in ipairs(df.item.find(symbols[1].item_id).general_refs)do
  if ref:getType()==df.general_ref_type.IS_ARTIFACT then artifact=ref:getArtifact();break end
 end
 assert(artifact,'Symbol fixture first item is not an artifact')
 local function claims()
  local entries={}
  for _,entity in ipairs(df.global.world.entities.all)do for _,claim in ipairs(entity.artifact_claims)do
   if claim.artifact_id==artifact.id then entries[#entries+1]={entity=entity.id,type=claim.claim_type,assignment=claim.symbol_claim_id,year=claim.claim_year,tick=claim.claim_year_tick,renounced=claim.renounce_event}end
  end end
  return entries
 end
 for _,operation in ipairs{'back','done'}do
  click_symbol(x,y);assert(menu.assigning_symbol and menu.cand_symbol[0].id==symbols[1].item_id)
  compare_symbols(probe(symbol_command))
  local before=claims();local previous=menu.cand_symbol_new_ind[0]
  click_symbol(912,190);assert(menu.cand_symbol_new_ind[0]~=previous,'Symbol checkbox did not toggle')
  assert(json.encode(claims())==json.encode(before),'Symbol toggle applied before dismissal')
  local staged=menu.cand_symbol_new_ind[0]
  compare_symbols(probe({'nobles-symbol-stage-probe',tostring(office.entity_id),tostring(office.position_id),tostring(office.assignment_id),'0',tostring(symbols[1].item_id),staged==index and '1' or '0'}))
  capture('nobles-symbols-selected-'..operation)
  if operation=='back' then gui.simulateInput(view,'LEAVESCREEN');settle()else click_symbol(928,142)end
  assert(info.open and not menu.assigning_symbol and menu.handling_symbol_closure_ind==-1,'Symbol dismissal did not finish')
  result.symbol_reference.effects[#result.symbol_reference.effects+1]={operation=operation,item_id=symbols[1].item_id,artifact_id=artifact.id,before=before,after=claims(),previous_index=previous,staged_index=staged,toggle_is_local=true}
 end
 if os.getenv('DF3D_NOBLES_SYMBOL_NAVIGATION')=='1' then
  click_symbol(x,y);assert(menu.assigning_symbol,'Navigation fixture did not open symbols')
  click_symbol(912,190)
  assert(menu.cand_symbol_new_ind[0]==index,'Navigation fixture did not select the artifact')
  local before=claims()
  click_symbol(170,75)
  result.symbol_reference.header_navigation={mode=info.current_mode,open=info.open,
   assigning_symbol=menu.assigning_symbol,pending=menu.handling_symbol_closure_ind,before=before,after=claims(),selected_before=true,lines=lines()}
  assert(info.current_mode==df.info_interface_mode_type.JOBS and not menu.assigning_symbol and menu.handling_symbol_closure_ind==-1 and json.encode(claims())==json.encode(before),'Native header did not discard symbols and open Tasks')
  write('nobles-native.json',json.encode(result));capture('nobles-symbol-header-navigation')
  gui.simulateInput(view,'D_NOBLES');settle()
  result.symbol_reference.header_navigation.reopened={mode=info.current_mode,assigning_symbol=menu.assigning_symbol,pending=menu.handling_symbol_closure_ind}
  if menu.assigning_symbol then gui.simulateInput(view,'LEAVESCREEN');settle()end
 end
 if os.getenv('DF3D_NOBLES_SYMBOL_APPLY')=='1' then
  local function symbol_call(name,expected,...)
   local size,address=df.sizeof(menu);local before=bytes(address,size)
   local creator=df.global.game.main_interface.name_creator
   local cs,ca=df.sizeof(creator);local creator_before=bytes(ca,cs)
   local command={name,tostring(office.entity_id),tostring(office.position_id),tostring(office.assignment_id),...}
   local text,rc=dfhack.run_command_silent('df3d',table.unpack(command));assert(rc==0,text)
   local value=json.decode(text);assert(value.outcome==expected,'Owned symbol outcome differs: '..text)
   assert(bytes(address,size)==before and bytes(ca,cs)==creator_before,'Owned apply changed native UI')
   return value
  end
  local function apply(...)return symbol_call('nobles-symbol-apply-probe',2,...)end
  local function continue_step(previous,expected)
   local args={previous.continuation_revision}
   for _,row in ipairs(previous.remaining)do args[#args+1]=tostring(row.item_id);args[#args+1]=row.selected and '1' or '0' end
   return symbol_call('nobles-symbol-continue-probe',expected,table.unpack(args))
  end
  local selected=apply(tostring(symbols[1].item_id),'1')
  assert(selected.naming_artifact_id==-1 and #selected.remaining==0)
  assert(json.encode(claims())==json.encode(result.symbol_reference.effects[1].after),'Owned artifact claim differs from native')
  apply(tostring(symbols[1].item_id),'0')
  assert(json.encode(claims())==json.encode(result.symbol_reference.effects[2].after),'Owned artifact removal differs from native')
  local ordinary={}
  for _,row in ipairs(symbols)do if not df.item.find(row.item_id).flags.artifact then ordinary[#ordinary+1]=row.item_id;if #ordinary==3 then break end end end
  assert(#ordinary==3)
  local artifacts_before=#df.global.world.artifacts.all;local events_before=#df.global.world.history.events
  local first=apply(tostring(ordinary[3]),'1',tostring(ordinary[2]),'1',tostring(ordinary[1]),'1')
  assert(first.naming_artifact_id>=0 and #first.remaining==2 and first.remaining[1].item_id==ordinary[2] and first.remaining[2].item_id==ordinary[3])
  assert(not df.item.find(ordinary[2]).flags.artifact,'Second ordinary item was elevated early')
  local second=continue_step(first,2)
  assert(second.naming_artifact_id>=0 and #second.remaining==1 and second.remaining[1].item_id==ordinary[3])
  local artifact_count=#df.global.world.artifacts.all;local event_count=#df.global.world.history.events
  continue_step(first,4)
  assert(#df.global.world.artifacts.all==artifact_count and #df.global.world.history.events==event_count,'Replayed continuation changed records')
  assert(not df.item.find(ordinary[3]).flags.artifact,'Replay elevated the next item')
  local third=continue_step(second,2)
  assert(third.naming_artifact_id>=0 and #third.remaining==0 and third.continuation_revision=='0')
  local entity=df.historical_entity.find(office.entity_id)
  for i,id in ipairs{first.naming_artifact_id,second.naming_artifact_id,third.naming_artifact_id}do
   local artifact=df.artifact_record.find(id);assert(artifact and artifact.item.id==ordinary[i] and artifact.item.flags.artifact and artifact.name.has_name)
   local found=false;for _,claim in ipairs(entity.artifact_claims)do
    if claim.artifact_id==id and claim.symbol_claim_id==office.assignment_id and claim.renounce_event==-1 then found=true end
   end;assert(found,'Elevated symbol lacks office claim')
   found=false;for _,candidate in ipairs(df.global.world.items.other.ANY_ARTIFACT)do if candidate.id==ordinary[i] then found=true end end
   assert(found,'Elevated item missing artifact category')
  end
  assert(#df.global.world.artifacts.all==artifacts_before+3 and #df.global.world.history.events==events_before+6,'Owned elevation event/record count differs')
  result.symbol_reference.owned_apply={existing_claim_matches=true,existing_removal_matches=true,first=first,second=second,third=third,artifacts_added=3,events_added=6,replay_rejected=true,native_ui_unchanged=true}
 end
 if os.getenv('DF3D_NOBLES_SYMBOL_NAME')=='1' then
  click_symbol(x,y);assert(menu.assigning_symbol)
  local ordinary_index,item,second_index,second_item
  for i,candidate in ipairs(menu.cand_symbol)do
   if not candidate.flags.artifact then
    if not item then ordinary_index=i;item=candidate else second_index=i;second_item=candidate;break end
   end
  end
  assert(second_index and second_index<15,'No two visible ordinary symbol items')
  local artifacts_before=#df.global.world.artifacts.all
  click_symbol(912,190+ordinary_index*36)
  click_symbol(912,190+second_index*36)
  assert(not item.flags.artifact,'Ordinary symbol toggle applied early')
  click_symbol(928,142)
  local creator=df.global.game.main_interface.name_creator
  assert(creator.open and item.flags.artifact,'Ordinary symbol did not enter artifact naming')
  result.symbol_reference.naming={item_id=item.id,index=ordinary_index,second_item_id=second_item.id,second_index=second_index,context=creator.context,
   pending_index=menu.handling_symbol_closure_ind,artifacts_added=#df.global.world.artifacts.all-artifacts_before,lines=lines()}
  assert(not second_item.flags.artifact and menu.handling_symbol_closure_ind==second_index,'Second symbol did not wait for naming')
  capture('nobles-symbol-name-open')
  if os.getenv('DF3D_NOBLES_SYMBOL_NAME_RESIZE')=='1' then
   result.symbol_reference.naming.resize={}
   for _,size in ipairs({'minimum','wide','default'})do
    write('owner-input-request.tmp','name-resize-'..size);assert(os.rename(out..'/owner-input-request.tmp',out..'/owner-input-request'))
    local deadline=dfhack.getTickCount()+10000
    while true do local ack=io.open(out..'/owner-input-ack');if ack then ack:close();break end;assert(dfhack.getTickCount()<deadline,'Symbol name resize timed out');script.sleep(1,'frames')end
    assert(os.remove(out..'/owner-input-ack'));script.sleep(5,'frames');settle()
    result.symbol_reference.naming.resize[#result.symbol_reference.naming.resize+1]={size=size,columns=g.dimx,height=g.dimy,lines=lines()}
    capture('nobles-symbol-name-'..size)
   end
  end
  if os.getenv('DF3D_NOBLES_SYMBOL_NAME_EDIT')=='1' then
   local artifact
   for _,ref in ipairs(item.general_refs)do if ref:getType()==df.general_ref_type.IS_ARTIFACT then artifact=ref:getArtifact();break end end
   assert(artifact)
   local function name_value()
    local n=artifact.name;local v={first=n.first_name,nickname=n.nickname,language=n.language,type=n.type,has_name=n.has_name,words={},parts={}}
    for i=0,6 do v.words[#v.words+1]=n.words[i];v.parts[#v.parts+1]=n.parts_of_speech[i] end;return v
   end
   local base=dfhack.internal.getImageBase()
   local function rng()
    local context=df.reinterpret_cast('int16_t',base+0x2159084).value;assert(context>=0 and context<16)
    local r={context=context,cursor=df.reinterpret_cast('uint32_t',base+0x2131b30+context*4).value,words={}}
    for i=0,623 do r.words[i+1]=df.reinterpret_cast('uint32_t',base+0x234e990+context*0x9c0+i*4).value end;return r
   end
   local function restore_rng(r)
    assert(df.reinterpret_cast('int16_t',base+0x2159084).value==r.context)
    df.reinterpret_cast('uint32_t',base+0x2131b30+r.context*4).value=r.cursor
    for i,v in ipairs(r.words)do df.reinterpret_cast('uint32_t',base+0x234e990+r.context*0x9c0+(i-1)*4).value=v end
   end
   local function command(edit,...)
    local args={edit and 'nobles-symbol-name-edit-probe' or 'nobles-symbol-name-probe',tostring(office.entity_id),tostring(office.position_id),tostring(office.assignment_id),tostring(artifact.id),...}
    local text,rc=dfhack.run_command_silent('df3d',table.unpack(args));assert(rc==0,text);return json.decode(text)
   end
   result.symbol_reference.naming.edits={}
   for _,test in ipairs{{0,316,130},{1,500,166},{2,256,130},{3,848,70}}do
    local before=df.language_name:new();before:assign(artifact.name)
    local revision=command(false).revision;local random_before=rng()
    click_symbol(test[2],test[3]);local expected=name_value();local random_after=rng()
    artifact.name:assign(before);before:delete();restore_rng(random_before)
    local mode=test[1];local target=mode==3 and -1 or 0
    local word=mode==1 and expected.words[1] or -1;local part=mode==1 and expected.parts[1] or -1
    local size,address=df.sizeof(creator);local menu_before=bytes(address,size)
    assert(command(true,revision,tostring(mode),tostring(target),tostring(target),tostring(word),tostring(part),'')==2,'Owned name edit failed')
    assert(json.encode(name_value())==json.encode(expected),'Owned/native symbol name differs')
    assert(json.encode(rng())==json.encode(random_after),'Owned/native symbol name RNG differs')
    assert(bytes(address,size)==menu_before,'Owned name edit changed native editor')
    assert(command(true,'1','0','0','0','-1','-1','')==4,'Stale symbol name edit was accepted')
    assert(json.encode(name_value())==json.encode(expected) and json.encode(rng())==json.encode(random_after),'Stale symbol name changed state')
    result.symbol_reference.naming.edits[#result.symbol_reference.naming.edits+1]={mode=mode,name_matches=true,rng_matches=true,stale_rejected=true,native_ui_unchanged=true}
   end
  end
  gui.simulateInput(view,'LEAVESCREEN');settle()
  assert(creator.open and second_item.flags.artifact,'Closing first name did not open second')
  result.symbol_reference.naming.second_context=creator.context
  result.symbol_reference.naming.second_pending_index=menu.handling_symbol_closure_ind
  capture('nobles-symbol-name-second')
  gui.simulateInput(view,'LEAVESCREEN');settle()
  assert(not creator.open and menu.handling_symbol_closure_ind==-1,'Symbol naming Back did not finish assignment')
  result.symbol_reference.naming.back_finishes=true
  local created
  for _,ref in ipairs(item.general_refs)do if ref:getType()==df.general_ref_type.IS_ARTIFACT then created=ref:getArtifact();break end end
  assert(created,'Ordinary item lacks artifact record')
  result.symbol_reference.naming.artifact_id=created.id
  local entity=assert(df.historical_entity.find(office.entity_id));local assigned=false
  for _,claim in ipairs(entity.artifact_claims)do
   if claim.artifact_id==created.id and claim.symbol_claim_id==office.assignment_id and claim.renounce_event==-1 then assigned=true end
  end
  assert(assigned,'Naming Back lost the symbol claim');result.symbol_reference.naming.assigned=true
  result.symbol_reference.naming.total_artifacts_added=#df.global.world.artifacts.all-artifacts_before
  capture('nobles-symbol-name-back')
 end
end

if os.getenv('DF3D_NOBLES_ACCOUNTING')=='1' then
 local function resize(size)
  write('owner-input-request.tmp','name-resize-'..size);assert(os.rename(out..'/owner-input-request.tmp',out..'/owner-input-request'))
  local deadline=dfhack.getTickCount()+10000
  while true do local ack=io.open(out..'/owner-input-ack');if ack then ack:close();break end;assert(dfhack.getTickCount()<deadline,'Nobles resize timed out');script.sleep(1,'frames')end
  assert(os.remove(out..'/owner-input-ack'));script.sleep(5,'frames');settle()
 end
 resize('wide');assert(g.dimx>=200,'Accounting requires wide native layout')
 local base=dfhack.internal.getImageBase()
 local inactive=df.reinterpret_cast('int32_t',base+0x2650378).value
 local active=df.reinterpret_cast('int32_t',base+0x2650468).value
 local sx,sy
 for x=0,g.dimx-1 do for y=0,g.dimy-1 do
  local at=x*g.dimy+y;local tile=g.screentexpos_lower[at];local top=g.screentexpos_top_lower[at]
  if tile==inactive or tile==active or top==inactive or top==active then assert(not sx,'Ambiguous accounting first icon');sx=x;sy=y end
 end end
 assert(sx,'Native accounting icons unavailable')
 local facts=df.global.plotinfo.nobles;local original_setting=facts.bookkeeper_settings;local original_precision=facts.bookkeeper_precision
 result.accounting_reference={columns=g.dimx,rows=g.dimy,first_icon={x=sx,y=sy},original_setting=original_setting,original_precision=original_precision,cases={}}
 for level,precision in ipairs{0,150,1500,15000,100000}do
  facts.bookkeeper_precision=precision
  local x=(sx+(level-1)*4)*8+16;local y=sy*12+18
  g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=y//12
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
  gui.simulateInput(view,'_MOUSE_L');df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1;settle()
  assert(facts.bookkeeper_settings==level-1,'Native accounting button selected wrong precision')
  local current=probe({'nobles-help-probe'});local help
  for _,row in ipairs(current)do if row.help.accounting then help=row.help.accounting;break end end
  assert(help and help.setting==level-1,'Owned accounting settings differ')
  local accounting_row
  for _,row in ipairs(current)do if row.help.accounting then accounting_row=row;break end end
  local function set_owned(expected,value,target)
   target=target or accounting_row
   return probe({'nobles-accounting-probe',tostring(target.entity_id),tostring(target.position_id),tostring(target.assignment_id),tostring(expected),tostring(value)})
  end
  local desired=level-1;local different=(desired+1)%5
  assert(set_owned(desired,different)==2 and facts.bookkeeper_settings==different,'Owned accounting setting did not apply')
  assert(facts.bookkeeper_precision==precision,'Accounting setting changed attained precision')
  assert(set_owned(desired,desired)==4 and facts.bookkeeper_settings==different,'Stale accounting setting accepted')
  assert(set_owned(different,desired)==2 and facts.bookkeeper_settings==desired,'Owned setting differs from native click')
  assert(set_owned(desired,5)==1 and facts.bookkeeper_settings==desired,'Invalid accounting setting accepted')
  local invalid
  for _,row in ipairs(current)do if not row.help.accounting then invalid=row;break end end
  assert(invalid and set_owned(desired,different,invalid)==1 and facts.bookkeeper_settings==desired,'Non-accounting office accepted setting')
  local sample=hover_sample('accounting-'..level,x,y)
  for _,key in ipairs{'title','examples','attained','progress'}do
   local found=help[key]==''
   for _,line in ipairs(sample.lines)do if line.text:find(help[key],1,true)then found=true end end
   assert(found,'Native accounting caption differs: '..key..' '..help[key])
  end
  result.accounting_reference.cases[#result.accounting_reference.cases+1]={precision=precision,help=help,lines=sample.lines,native_text_match=true,native_click_effect=true,owned_setting_effect=true,stale_rejected=true,invalid_rejected=true,precision_unchanged=true}
 end
 facts.bookkeeper_settings=original_setting;facts.bookkeeper_precision=original_precision
 result.accounting_reference.restored=true;write('nobles-native.json',json.encode(result))
 capture('nobles-accounting-wide');resize('default')
end

local wire_commit=os.getenv('DF3D_NOBLES_COMMIT_WIRE')=='1'
local wire_symbols=os.getenv('DF3D_NOBLES_SYMBOL_WIRE')=='1'
local symbol_wire
local wire_events,wire_precision,wire_setting
if os.getenv('DF3D_NOBLES_WIRE')=='1' then
 if wire_commit or wire_symbols then
  gui.simulateInput(view,'LEAVESCREEN');settle();assert(not info.open)
  wire_events=#df.global.world.history.events
  wire_precision=df.global.plotinfo.nobles.bookkeeper_precision;wire_setting=df.global.plotinfo.nobles.bookkeeper_settings
 end
 if wire_symbols then
  assert(not wire_commit,'Symbol and appointment effects use separate oracle counts')
  local target=result.pickers[1].selected
  local candidates=probe({'nobles-symbols-probe',tostring(target.entity_id),tostring(target.position_id),tostring(target.assignment_id)})
  local items={}
  for _,row in ipairs(candidates)do local item=df.item.find(row.item_id);if item and not item.flags.artifact and #items<3 then items[#items+1]=item.id end end
  assert(#items==3,'Missing ordinary symbols')
  symbol_wire={target={entity_id=target.entity_id,position_id=target.position_id,assignment_id=target.assignment_id,draft_slot=0},rows=candidates,items=items}
  local clothing={}
  for i=1,math.min(15,#candidates)do
   local item=df.item.find(candidates[i].item_id)
   if item:getType()==df.item_type.PANTS then
    local raw=df.itemdef_pantsst.find(item:getSubtype())
    local art={item_id=item.id,raw_id=raw.id,procedural=raw.procedural_item_graphics,original_tile=raw.texpos_item,source_hfid=raw.source_hfid}
    art.selected_tile=probe({'item-legwear-probe',tostring(item.id)}).tile
    for _,page in ipairs(df.global.texture.page)do for index,tile in ipairs(page.texpos)do
     if tile==raw.texpos_item then art.page=page.token;art.x=index%page.page_dim_x;art.y=index//page.page_dim_x end
     if tile==art.selected_tile then art.selected_page=page.token;art.selected_x=index%page.page_dim_x;art.selected_y=index//page.page_dim_x end
    end end
    assert(art.selected_page,'Legwear selector did not return original installed artwork')
    if raw.procedural_item_graphics==11 then
     assert(art.selected_page=='ITEM_EQUIPMENT' and art.selected_x==0 and art.selected_y==12,'Generated skirt artwork differs')
    elseif raw.procedural_item_graphics==-1 then assert(art.selected_tile==raw.texpos_item,'Raw legwear artwork differs')end
    clothing[#clothing+1]=art
   end
  end
  write('nobles-symbol-clothing-native.json',json.encode(clothing))
  write('nobles-symbol-wire-reference.json',json.encode(symbol_wire))
  symbol_wire.artifacts_before=#df.global.world.artifacts.all
 end
 write('nobles-wire-reference.json',json.encode(probe({'nobles-help-probe'})))
 write('shot.tmp','nobles-wire');assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local deadline=dfhack.getTickCount()+(os.getenv('DF3D_NOBLES_SYMBOL_NAME_RESIZE')=='1' and 120000 or 30000)
 while true do local ack=io.open(out..'/ack-nobles-wire');if ack then ack:close();break end
  assert(dfhack.getTickCount()<deadline,'Nobles wire timeout');script.sleep(1,'frames')
 end
end
if wire_symbols then
 local f=assert(io.open(out..'/nobles-symbol-wire.json'));local receipt=json.decode(f:read('*a'));f:close()
 assert(receipt.success and #receipt.artifacts==3,'Typed symbol client failed')
 assert(#df.global.world.artifacts.all==symbol_wire.artifacts_before+3 and #df.global.world.history.events==wire_events+6,'Typed symbol effect count differs')
 local entity=assert(df.historical_entity.find(symbol_wire.target.entity_id))
 for i,id in ipairs(receipt.artifacts)do
  local artifact=assert(df.artifact_record.find(id));assert(artifact.item.id==symbol_wire.items[i] and artifact.item.flags.artifact,'Typed symbol item/order differs')
  local claim=false;for _,c in ipairs(entity.artifact_claims)do if c.artifact_id==id and c.symbol_claim_id==symbol_wire.target.assignment_id and c.claim_type==0 and c.renounce_event==-1 then claim=true end end
  assert(claim,'Typed symbol claim missing');if i==1 then assert(artifact.name.words[0]==-1,'Typed name clear missing')end
  if i==1 and receipt.first_name then
   for slot=0,6 do assert(artifact.name.words[slot]==receipt.first_name.words[slot+1],'Rendered name differs from native final name')end
  end
 end
 result.typed_symbols={items=receipt.items,artifacts=receipt.artifacts,artifacts_added=3,events_added=6,name_clear=true,order_matches=true}
end
if wire_commit then
 local f=assert(io.open(out..'/nobles-commit-wire.json'));local receipt=json.decode(f:read('*a'));f:close()
 local entity=assert(df.historical_entity.find(receipt.entity_id));local assignment
 for _,row in ipairs(entity.positions.assignments)do if row.id==receipt.assignment_id then assignment=row;break end end
 local unit=assert(df.unit.find(receipt.unit_id));assert(assignment and assignment.histfig==unit.hist_figure_id and assignment.histfig2==unit.hist_figure_id,'Typed commit holder differs')
 assert(#df.global.world.history.events==wire_events+1,'Typed appointment history count differs')
 local figure=assert(df.historical_figure.find(unit.hist_figure_id));local linked=false
 for _,link in ipairs(figure.entity_links)do
  if link:getType()==df.histfig_entity_link_type.POSITION and link.entity_id==entity.id and link:getPosition()==assignment.id then linked=true end
 end
 assert(linked,'Typed appointment lacks position link')
 assert(receipt.accounting_restored==wire_setting and df.global.plotinfo.nobles.bookkeeper_settings==wire_setting,'Typed accounting was not restored')
 assert(df.global.plotinfo.nobles.bookkeeper_precision==wire_precision,'Typed accounting changed achieved precision')
 result.typed_accounting={values=receipt.accounting_values,restored=true,precision_unchanged=true}
 result.typed_commit={unit_id=unit.id,histfig=unit.hist_figure_id,assignment_id=assignment.id,events_added=#df.global.world.history.events-wire_events,position_link=true}
end
if info.open then gui.simulateInput(view,'LEAVESCREEN');settle()end
assert(not info.open,'Nobles did not close')
if os.getenv('DF3D_NOBLES_APPOINTMENT')=='1' then
 local source=debug.getinfo(1,'S').source:sub(2):gsub('nobles%-native%.lua$','nobles-appointment-native.lua')
 assert(loadfile(source))(out,view,probe)
end
result.closed=true;write('nobles-native.json',json.encode(result));records[#records+1]={name='nobles-discovery',rows=#rows,closed=true}
