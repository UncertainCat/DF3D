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
gui.simulateInput(view,'D_NOBLES');settle()
local info=df.global.game.main_interface.info
assert(info.open and info.current_mode==df.info_interface_mode_type.ADMINISTRATORS,'Nobles shortcut failed')
local menu=info.administrators
local rows={}
for _,row in ipairs(menu.noblelist)do
 rows[#rows+1]={unit_id=row.un and row.un.id or -1,nemesis_id=row.nem and row.nem.id or -1,entity_id=row.enid,position_id=row.ep and row.ep.id or -1,assignment_id=row.epp and row.epp.id or -1,value=row.value,position_name=row.ep and dfhack.df2utf(row.ep.name[0])or''}
end
local result={dimensions={g.dimx,g.dimy},rows=rows,lines=lines(),scroll=menu.scroll_position_noblelist,choosing_candidate=menu.choosing_candidate,assigning_symbol=menu.assigning_symbol}
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
 result.pickers[#result.pickers+1]={position=target[1],selected=selected,candidates=candidates,lines=lines()}
 write('nobles-native.json',json.encode(result));capture('nobles-candidates-'..target[1])
 gui.simulateInput(view,'LEAVESCREEN');settle();assert(info.open and not menu.choosing_candidate,'Picker Cancel did not return to overview')
end

gui.simulateInput(view,'LEAVESCREEN');settle();assert(not info.open,'Nobles did not close')
result.closed=true;write('nobles-native.json',json.encode(result));records[#records+1]={name='nobles-discovery',rows=#rows,closed=true}
