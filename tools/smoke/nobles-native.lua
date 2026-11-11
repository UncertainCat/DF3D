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
 write('nobles-native.json',json.encode(result));capture('nobles-candidates-'..target[1])
 gui.simulateInput(view,'LEAVESCREEN');settle();assert(info.open and not menu.choosing_candidate,'Picker Cancel did not return to overview')
end

gui.simulateInput(view,'LEAVESCREEN');settle();assert(not info.open,'Nobles did not close')
result.closed=true;write('nobles-native.json',json.encode(result));records[#records+1]={name='nobles-discovery',rows=#rows,closed=true}
