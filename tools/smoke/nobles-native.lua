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
  local sample=hover_sample('accounting-'..level,x,y)
  for _,key in ipairs{'title','examples','attained','progress'}do
   local found=help[key]==''
   for _,line in ipairs(sample.lines)do if line.text:find(help[key],1,true)then found=true end end
   assert(found,'Native accounting caption differs: '..key..' '..help[key])
  end
  result.accounting_reference.cases[#result.accounting_reference.cases+1]={precision=precision,help=help,lines=sample.lines,native_text_match=true,native_click_effect=true}
 end
 facts.bookkeeper_settings=original_setting;facts.bookkeeper_precision=original_precision
 result.accounting_reference.restored=true;write('nobles-native.json',json.encode(result))
 capture('nobles-accounting-wide');resize('default')
end

if os.getenv('DF3D_NOBLES_WIRE')=='1' then
 write('nobles-wire-reference.json',json.encode(probe({'nobles-help-probe'})))
 write('shot.tmp','nobles-wire');assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local deadline=dfhack.getTickCount()+30000
 while true do local ack=io.open(out..'/ack-nobles-wire');if ack then ack:close();break end
  assert(dfhack.getTickCount()<deadline,'Nobles wire timeout');script.sleep(1,'frames')
 end
end
gui.simulateInput(view,'LEAVESCREEN');settle();assert(not info.open,'Nobles did not close')
if os.getenv('DF3D_NOBLES_APPOINTMENT')=='1' then
 local source=debug.getinfo(1,'S').source:sub(2):gsub('nobles%-native%.lua$','nobles-appointment-native.lua')
 assert(loadfile(source))(out,view,probe)
end
result.closed=true;write('nobles-native.json',json.encode(result));records[#records+1]={name='nobles-discovery',rows=#rows,closed=true}
