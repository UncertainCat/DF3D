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
local warm=probe();assert(json.encode(cold)==json.encode(rows) and json.encode(warm)==json.encode(rows),'Owned Nobles overview differs from native order/identities')
local result={owned={cold=cold,warm=warm,menu_preserved=true,rng_preserved=true},dimensions={g.dimx,g.dimy},rows=rows,lines=lines(),scroll=menu.scroll_position_noblelist,choosing_candidate=menu.choosing_candidate,assigning_symbol=menu.assigning_symbol}
write('nobles-native.json',json.encode(result));capture('nobles-overview')
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
