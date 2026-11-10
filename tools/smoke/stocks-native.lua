-- Protected discovery only. Native UI storage is evidence, never runtime input.
local out,view,records=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local function scratch()
 local values={}
 for _,item in ipairs(df.global.world.items.other.IN_PLAY)do values[#values+1]={item.id,item.base_uniform_score}end
 return json.encode(values)
end
local function probe(command,...)
 local before=scratch();local menu=df.global.game.main_interface.stocks
 local open=menu.open;local selected=menu.current_type;local query=menu.item_filter
 local text,code=dfhack.run_command_silent('df3d',command,...)
 assert(code==0,'Stocks inventory failed: '..text)
 assert(before==scratch(),'Inventory probe changed item temporary_32')
 assert(open==menu.open and selected==menu.current_type and query==menu.item_filter,'Inventory probe changed menu state')
 return json.decode(text)
end
local function run()
if os.getenv('DF3D_STOCKS_WIRE')=='1' then
 local source=debug.getinfo(1,'S').source:sub(2):gsub('stocks%-native.lua$','stocks-wire-native.lua')
 assert(loadfile(source))(out,probe)
end
local cold,cold_groups,cold_totals,cold_display,cold_ordered
local selection_cases={{39,''},{39,'iron'},{39,'silver'},{0,''},{4,''},{24,''},{54,''},{60,''},{91,''}}
local cold_selections
if os.getenv('DF3D_STOCKS_SELECTION')=='1' then
 cold_selections={}
 for _,case in ipairs(selection_cases)do cold_selections[#cold_selections+1]=probe('stocks-selection-probe',tostring(case[1]),case[2])end
end
if os.getenv('DF3D_STOCKS_ORDERED')=='1' then cold_ordered=probe('stocks-ordered-inventory-probe').ids end
local category_queries={'','iron','WOOD','bar','prepared','zzzznotstock',' ','silk'};local cold_categories
if os.getenv('DF3D_STOCKS_CATEGORIES')=='1' then
 cold_categories={}
 for _,query in ipairs(category_queries)do cold_categories[#cold_categories+1]=probe('stocks-categories-probe',query).types end
end
if os.getenv('DF3D_STOCKS_DISPLAY')=='1' then cold_display=probe('stocks-display-probe').rows end
if os.getenv('DF3D_STOCKS_PROVIDER')=='1' then cold=probe('stocks-inventory-probe').ids end
if os.getenv('DF3D_STOCKS_GROUPS')=='1' then cold_groups=probe('stocks-groups-probe').groups end
if os.getenv('DF3D_STOCKS_TOTALS')=='1' then cold_totals=probe('stocks-totals-probe')end
gui.simulateInput(view,'D_STOCKS')
for _=1,3 do script.sleep(1,'frames')end
view:render(dfhack.getTickCount())
local stocks=df.global.game.main_interface.stocks;assert(stocks.open,'Stocks did not open')
local function values(vector)
 local result={};for _,value in ipairs(vector)do result[#result+1]=value end;return result
end
local _,address=df.sizeof(stocks)
local result={stocks_rva=address-dfhack.internal.getImageBase(),current_type=stocks.current_type,
 types=values(stocks.type_list),filtered_types=values(stocks.filtered_type_list),
 stored=values(stocks.storeamount),unavailable=values(stocks.badamount),
 scroll_type=stocks.scroll_position_type,scroll_item=stocks.scroll_position_item,
 item_filter=stocks.item_filter,individual_ids={},groups={},screen_rows={}}
if cold_totals then
 local warm=probe('stocks-totals-probe')
 for _,field in ipairs{'stored','unavailable'}do
  assert(json.encode(cold_totals[field])==json.encode(result[field]),'Cold '..field..' totals differ')
  assert(json.encode(warm[field])==json.encode(result[field]),'Warm '..field..' totals differ')
 end
 result.totals_provider={cold=cold_totals,warm=warm,scratch_preserved=true}
end
for _,item in ipairs(stocks.current_type_i_list)do result.individual_ids[#result.individual_ids+1]=item.id end
if cold then
 local warm=probe('stocks-inventory-probe').ids;local native={}
 for _,item in ipairs(stocks.master_i_list.l_item)do native[#native+1]=item.id end
 table.sort(cold);table.sort(warm);table.sort(native)
 assert(json.encode(cold)==json.encode(native),'Cold inventory membership differs from native')
 assert(json.encode(warm)==json.encode(native),'Warm inventory membership differs from native')
 local _,address=df.sizeof(df.global.world.items.other.IN_PLAY)
 result.inventory={cold=cold,warm=warm,native=native,scratch_preserved=true,in_play_rva=address-dfhack.internal.getImageBase()}
end
if cold_ordered then
 local warm=probe('stocks-ordered-inventory-probe').ids;local native={}
 for _,item in ipairs(stocks.master_i_list.l_item)do native[#native+1]=item.id end
 assert(json.encode(cold_ordered)==json.encode(native),'Cold ordered inventory differs')
 assert(json.encode(warm)==json.encode(native),'Warm ordered inventory differs')
 result.ordered_inventory={cold=cold_ordered,warm=warm,native=native,scratch_preserved=true}
end
if cold_groups then
 local warm=probe('stocks-groups-probe').groups;local native={};local master=stocks.master_a_list
 for index,kind in ipairs(master.type)do
  native[#native+1]={type=kind,subtype=master.subtype[index],subcat1=master.subcat1[index],subcat2=master.subcat2[index],amount=master.amount[index],expanded=master.expanded[index]}
 end
 local function equal(actual,label)
  assert(#actual==#native,label..' group count differs')
  for i,row in ipairs(native)do for key,value in pairs(row)do assert(actual[i][key]==value,label..' group differs at '..i..'/'..key)end end
 end
 equal(cold_groups,'Cold');equal(warm,'Warm')
 result.group_provider={cold=cold_groups,warm=warm,native=native,scratch_preserved=true}
end
for index,subtype in ipairs(stocks.current_type_a_subtype)do
 result.groups[#result.groups+1]={subtype=subtype,subcat1=stocks.current_type_a_subcat1[index],
  subcat2=stocks.current_type_a_subcat2[index],amount=stocks.current_type_a_amount[index],
  expanded=stocks.current_type_a_expanded[index],on=stocks.current_type_a_on[index],flags=stocks.current_type_a_flag[index].whole}
end
if cold_display then
 local warm=probe('stocks-display-probe').rows
 assert(json.encode(cold_display)==json.encode(warm),'Cold/warm category display differs')
 local original=stocks.scroll_position_type;local captured={}
 local function text_at(x,y,length)
  local text=''
  for column=x,x+length-1 do
   local ch=dfhack.screen.readTile(column,y).ch
   text=text..(ch>=32 and ch<127 and string.char(ch) or ' ')
  end
  return text:gsub('%s+$','')
 end
 for index,kind in ipairs(stocks.filtered_type_list)do
  stocks.scroll_position_type=index
  view:render(dfhack.getTickCount())
  local row=cold_display[kind+1];assert(row.type==kind)
  local native={type=kind,caption=text_at(8,7,24),stored=text_at(32,7,8),unavailable=text_at(32,8,8)}
  for _,field in ipairs{'caption','stored','unavailable'}do
   assert(native[field]==row[field],('Display differs for %d/%s: [%s] vs [%s]'):format(kind,field,native[field],row[field]))
  end
  captured[#captured+1]=native
 end
 stocks.scroll_position_type=original;view:render(dfhack.getTickCount())
 result.display_provider={cold=cold_display,warm=warm,native=captured,scratch_preserved=true}
end
if cold_categories then
 result.category_provider={cases={},scratch_preserved=true}
 local entering=stocks.entering_item_filter
 local gps=df.global.gps
 gps.precise_mouse_x=500;gps.precise_mouse_y=94;gps.mouse_x=62;gps.mouse_y=7
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 local function key(value)gui.simulateInput(view,value);view:render(dfhack.getTickCount())end
 for index,query in ipairs(category_queries)do
  while #stocks.item_filter>0 do key('STRING_A000')end
  for byte=1,#query do key(('STRING_A%03d'):format(query:byte(byte)))end
  assert(stocks.item_filter==query:upper(),'Native search input mismatch: '..query..' vs '..stocks.item_filter)
  local native=values(stocks.filtered_type_list)
  local warm=probe('stocks-categories-probe',query).types
  assert(json.encode(cold_categories[index])==json.encode(native),'Cold categories differ for '..query)
  assert(json.encode(warm)==json.encode(native),'Warm categories differ for '..query)
  result.category_provider.cases[#result.category_provider.cases+1]={query=query,types=native}
 end
 while #stocks.item_filter>0 do gui.simulateInput(view,'STRING_A000')end
 stocks.entering_item_filter=entering;view:render(dfhack.getTickCount())
end
if cold_selections then
 local gps=df.global.gps;local original_type=stocks.current_type
 local function key(value)gui.simulateInput(view,value);view:render(dfhack.getTickCount())end
 local function click(x,y)gps.precise_mouse_x=x;gps.precise_mouse_y=y;gps.mouse_x=x//8;gps.mouse_y=(y-4)//12;key('_MOUSE_L')end
 local function focus()if not stocks.entering_item_filter then click(500,94)end;assert(stocks.entering_item_filter,'Filter did not focus')end
 local function clear()focus();for _=1,#stocks.item_filter do key('STRING_A000')end;assert(stocks.item_filter=='')end
 local function select_type(kind)
  clear();local found=false
  for index,value in ipairs(stocks.filtered_type_list)do if value==kind then stocks.scroll_position_type=index;found=true;break end end
  assert(found,'Missing selection category');view:render(dfhack.getTickCount());click(100,94)
  assert(stocks.current_type==kind,'Category click failed')
 end
 result.selection_provider={cases={},scratch_preserved=true}
 for index,case in ipairs(selection_cases)do
  select_type(case[1]);focus()
  for byte=1,#case[2]do key(('STRING_A%03d'):format(case[2]:byte(byte)))end
  assert(stocks.current_type==case[1] and stocks.item_filter==case[2]:upper(),('Selection search changed target: case %d expected %d/%s actual %d/%s'):format(index,case[1],case[2],stocks.current_type,stocks.item_filter))
  local native={ids={},groups={}}
  for _,item in ipairs(stocks.current_type_i_list)do native.ids[#native.ids+1]=item.id end
  for i,subtype in ipairs(stocks.current_type_a_subtype)do
   native.groups[#native.groups+1]={subtype=subtype,subcat1=stocks.current_type_a_subcat1[i],subcat2=stocks.current_type_a_subcat2[i],amount=stocks.current_type_a_amount[i],expanded=stocks.current_type_a_expanded[i],on=stocks.current_type_a_on[i],flags=stocks.current_type_a_flag[i].whole}
  end
  local warm=probe('stocks-selection-probe',tostring(case[1]),case[2])
  for _,actual in ipairs{cold_selections[index],warm}do
   assert(json.encode(actual.ids)==json.encode(native.ids),'Selection IDs differ')
   assert(#actual.groups==#native.groups,'Selection group count differs')
   for i,row in ipairs(native.groups)do for field,value in pairs(row)do assert(actual.groups[i][field]==value,('Selection %d group %d/%s differs'):format(case[1],i,field))end end
  end
  local observed={type=case[1],query=case[2],native=native}
  if os.getenv('DF3D_STOCKS_GROUP_CAPTIONS')=='1' then
   observed.group_captions={};local expanded={};local original_scroll=stocks.scroll_position_item
   for i,value in ipairs(stocks.current_type_a_expanded)do expanded[i]=value;stocks.current_type_a_expanded[i]=false end
   local visible=0
   for i,row in ipairs(warm.groups)do if row.on then
    stocks.scroll_position_item=visible*3;view:render(dfhack.getTickCount())
    local length=math.min(#row.caption,57);local text=''
    for x=47,47+length-1 do local ch=dfhack.screen.readTile(x,10).ch;text=text..string.char(ch%256)end
    assert(text==row.caption:sub(1,length),('Group caption %d/%d differs: [%s] vs [%s]'):format(case[1],i,text,row.caption))
    observed.group_captions[#observed.group_captions+1]={index=i-1,caption=row.caption,verified_characters=length}
    visible=visible+1
   end end
   for i,value in pairs(expanded)do stocks.current_type_a_expanded[i]=value end
   stocks.scroll_position_item=original_scroll;view:render(dfhack.getTickCount())
  end
  if os.getenv('DF3D_STOCKS_MEMBERS')=='1' and case[2]=='' and #native.groups>0 then
   local members=warm.groups[1].ids;local member_set={};for _,id in ipairs(members)do member_set[id]=true end
   local height=stocks.i_height;local expanded=stocks.current_type_a_expanded[0]
   assert(expanded,'Expected default expanded group')
   click(500,130);assert(not stocks.current_type_a_expanded[0],'Group did not collapse')
   assert(height-stocks.i_height==#members*3,'Collapsed height differs from membership')
   click(500,130);assert(stocks.current_type_a_expanded[0] and stocks.i_height==height,'Group expansion did not restore')
   local before={};for _,id in ipairs(native.ids)do before[id]=df.item.find(id).flags.whole end
   local want=(native.groups[1].flags&8)==0
   click(916,130)
   local changed={}
   for _,id in ipairs(native.ids)do
    local item=df.item.find(id);local expected=before[id]
    if member_set[id]then if want then expected=expected|0x1000000 else expected=expected&(~0x1000000)end end
    assert(item.flags.whole==expected,'Native group visibility affected wrong member '..id)
    if item.flags.whole~=before[id]then changed[#changed+1]=id end
   end
   for id,flags in pairs(before)do df.item.find(id).flags.whole=flags end
   observed.membership={ids=members,native_visibility_changed=changed,height_delta=#members*3,restored=true}
  end
  result.selection_provider.cases[#result.selection_provider.cases+1]=observed
 end
 select_type(original_type);stocks.scroll_position_type=0;view:render(dfhack.getTickCount())
end
if os.getenv('DF3D_STOCKS_ACTIONS')=='1' or os.getenv('DF3D_STOCKS_ITEM_ACTIONS')=='1' then
 local source=debug.getinfo(1,'S').source:sub(2):gsub('stocks%-native.lua$','stocks-actions-native.lua')
 assert(loadfile(source))(view,result,probe)
end
if os.getenv('DF3D_STOCKS_HOVER')=='1' then
 local source=debug.getinfo(1,'S').source:sub(2):gsub('stocks%-native.lua$','stocks-hover-native.lua')
 assert(loadfile(source))(out,view,result)
end
if os.getenv('DF3D_STOCKS_NAVIGATION')=='1' then
 local source=debug.getinfo(1,'S').source:sub(2):gsub('stocks%-native.lua$','stocks-navigation-native.lua')
 assert(loadfile(source))(out,view,result)
end
if os.getenv('DF3D_STOCKS_DESTINATIONS')=='1' then
 local sheet=df.global.game.main_interface.view_sheets
 local id=probe('stocks-selection-probe','39','').groups[1].ids[1]
 local item=df.item.find(id);local x,y,z=dfhack.items.getPosition(item)
 local function observed()
  return {stocks=stocks.open,sheet=sheet.open,sheet_type=sheet.active_sheet,sheet_id=sheet.active_id,
   window={df.global.window_x,df.global.window_y,df.global.window_z},
   follow_item=df.global.plotinfo.follow_item,follow_unit=df.global.plotinfo.follow_unit}
 end
 local function click(px)
  local gps=df.global.gps;gps.precise_mouse_x=px;gps.precise_mouse_y=166;gps.mouse_x=px//8;gps.mouse_y=13
  gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 end
 result.destinations={item_id=id,position={x,y,z},before=observed()}
 click(796);result.destinations.recenter=observed()
 assert(not stocks.open and not sheet.open,'Recenter did not leave Stocks')
 gui.simulateInput(view,'D_STOCKS');view:render(dfhack.getTickCount())
 df.global.window_x=result.destinations.before.window[1];df.global.window_y=result.destinations.before.window[2];df.global.window_z=result.destinations.before.window[3]
 view:render(dfhack.getTickCount());result.destinations.before_view=observed()
 click(820);result.destinations.view=observed()
 assert(not stocks.open and sheet.open and sheet.active_sheet==df.view_sheet_type.ITEM and sheet.active_id==id,'View did not open expected item sheet')
 if os.getenv('DF3D_STOCKS_AMMO_SHEET')=='1' then
  local text,code=dfhack.run_command_silent('df3d','item-inspect-probe',tostring(id));assert(code==0,text)
  local observed=json.decode(text).snapshot
  assert(observed.description==dfhack.df2utf(sheet.raw_description),'Ammunition native description differs')
  result.destinations.item_snapshot=observed
  result.destinations.native_description=dfhack.df2utf(sheet.raw_description)
  if os.getenv('DF3D_STOCKS_BIN_CONTENTS')=='1' then
   local carrier=assert(observed.carrier,'Expected ammunition carrier')
   local bin=assert(df.item.find(carrier.id));assert(bin:getType()==df.item_type.BIN)
   local contents=probe('item-container-contents-probe',tostring(bin.id))
   assert(contents.container==bin.flags.container,'Container flag differs')
   local expected=0
   if bin.flags.container then for _,ref in ipairs(bin.general_refs)do
    local kind=ref:getType()
    if kind==df.general_ref_type.CONTAINS_ITEM or kind==df.general_ref_type.CONTAINS_UNIT then
     local child=kind==df.general_ref_type.CONTAINS_ITEM and ref:getItem() or nil
     expected=expected+1
     local row=assert(contents.entries[expected],'Missing direct contents entry')
     assert(row.item_type==(child and child:getType() or -1),'Contents order/type differs')
     if child then
      local material=dfhack.matinfo.decode(child)
      assert(row.material_token==(material and material:getToken() or ''),'Contents material differs')
      local color=child:getColorWhetherDyedOrNot()
      assert(row.color_token==((color>=0 and color<255)and df.descriptor_color.find(color).id or ''),'Contents color differs')
      assert(row.metal==(material and material.material.flags.IS_METAL or false),'Contents metal differs')
     end
    end
   end end
   assert(expected==#contents.entries and expected>0,'Contents count differs')
   result.destinations.bin_contents=contents
  end
  if os.getenv('DF3D_STOCKS_AMMO_ASSIGNMENT')=='1' then
   local function read_assignment()
    local text,code=dfhack.run_command_silent('df3d','item-ammunition-assignment-probe',tostring(id));assert(code==0,text)
    local value=json.decode(text);view:render(dfhack.getTickCount())
    local lines={};for y=0,df.global.gps.dimy-1 do local chars={}
     for x=0,df.global.gps.dimx-1 do chars[#chars+1]=string.char(dfhack.screen.readTile(x,y).ch%256)end
     lines[#lines+1]=table.concat(chars)
    end
    local screen=table.concat(lines,'\n')
    if value.kind==0 then assert(not screen:find('Assigned to',1,true),'Native assignment unexpectedly present')
    else assert(screen:find(value.caption,1,true),'Native assignment caption differs')end
    return value
   end
   local cases={};local equipment=df.global.plotinfo.equipment;local assigned=equipment.items_assigned[df.item_type.AMMO]
   local function copy(vec)local values={};for _,v in ipairs(vec)do values[#values+1]=v end;return values end
   local function restore(vec,values)vec:resize(0);for _,v in ipairs(values)do vec:insert('#',v)end end
   local original=copy(assigned);local hunters={};for _,spec in ipairs(equipment.hunter_ammunition)do hunters[#hunters+1]={spec=spec,ids=copy(spec.assigned)}end
   local squad=df.squad.find(df.global.plotinfo.main.fortress_entity.squads[0] or -1)
   local added,alias
   local ok,err=xpcall(function()
    cases.hunters=read_assignment();assert(cases.hunters.kind==1,'Expected hunter fixture')
    assigned:resize(0);cases.unassigned=read_assignment();assert(cases.unassigned.kind==0,'Assigned-list gate ignored');restore(assigned,original)
    for _,row in ipairs(hunters)do local kept={};for _,value in ipairs(row.ids)do if value~=id then kept[#kept+1]=value end end;restore(row.spec.assigned,kept)end
    cases.no_hunters=read_assignment()
    if squad then
     alias=squad.alias;squad.alias='Assignment probe';added=df.squad_ammo_spec:new();added.assigned:insert('#',id);squad.ammo.ammunition:insert('#',added)
     cases.squad=read_assignment();assert(cases.squad.kind==2 and cases.squad.squad_id==squad.id,'Squad assignment differs')
     for _,row in ipairs(hunters)do restore(row.spec.assigned,row.ids)end
     cases.precedence=read_assignment();assert(cases.precedence.kind==1,'Hunter precedence differs')
    end
   end,debug.traceback)
   restore(assigned,original);for _,row in ipairs(hunters)do restore(row.spec.assigned,row.ids)end
   if added then squad.ammo.ammunition:erase(#squad.ammo.ammunition-1);added:delete();squad.alias=alias end
   view:render(dfhack.getTickCount());assert(ok,err);result.destinations.assignment_cases=cases
  end
  local f=assert(io.open(out..'/shot.tmp','w'));f:write('stocks-ammo-sheet');f:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
  local deadline=dfhack.getTickCount()+10000
  while true do local ack=io.open(out..'/ack-stocks-ammo-sheet');if ack then ack:close();break end
   assert(dfhack.getTickCount()<deadline,'Ammunition sheet capture timeout');script.sleep(1,'frames')end
 end
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
 result.destinations.back=observed()
 gui.simulateInput(view,'D_STOCKS');view:render(dfhack.getTickCount())
end
if os.getenv('DF3D_STOCKS_INPUT')=='1' then
 local source=debug.getinfo(1,'S').source:sub(2):gsub('stocks%-native.lua$','stocks-input-native.lua')
 result.input=assert(loadfile(source))(view,stocks,out)
end
if os.getenv('DF3D_STOCKS_FURNITURE_SHEETS')=='1' then
 local source=debug.getinfo(1,'S').source:sub(2):gsub('stocks%-native.lua$','stocks-furniture-sheets-native.lua')
 result.furniture=assert(loadfile(source))(out,view,stocks,probe)
end
if os.getenv('DF3D_STOCKS_ART_RENDER')=='1' then
 local source=debug.getinfo(1,'S').source:sub(2):gsub('stocks%-native.lua$','stocks-art-native.lua')
 result.art=assert(loadfile(source))(out,view,stocks)
end
if os.getenv('DF3D_STOCKS_RESIZE')=='1' then
 local source=debug.getinfo(1,'S').source:sub(2):gsub('stocks%-native.lua$','stocks-resize-native.lua')
 result.resize=assert(loadfile(source))(out,view,stocks)
end
if os.getenv('DF3D_STOCKS_FILTER_RENDER')=='1' then
 local g=df.global.gps;df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=500;g.precise_mouse_y=94;g.mouse_x=62;g.mouse_y=7
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 for _,byte in ipairs{105,114,111,110}do gui.simulateInput(view,('STRING_A%03d'):format(byte));view:render(dfhack.getTickCount())end
 gui.simulateInput(view,'SELECT');view:render(dfhack.getTickCount())
 result.filter_render={query=stocks.item_filter,focused=stocks.entering_item_filter,category=stocks.current_type}
 assert(stocks.item_filter=='IRON' and not stocks.entering_item_filter,'Native filled filter differs')
end
if os.getenv('DF3D_STOCKS_SCROLL_RENDER')=='1' then
 stocks.scroll_position_type=0;stocks.scroll_position_item=0
 local g=df.global.gps
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=100;g.precise_mouse_y=130;g.mouse_x=12;g.mouse_y=10
 gui.simulateInput(view,'CONTEXT_SCROLL_DOWN');view:render(dfhack.getTickCount())
 g.precise_mouse_x=500;g.precise_mouse_y=94;g.mouse_x=62;g.mouse_y=7
 gui.simulateInput(view,'CONTEXT_SCROLL_PAGEDOWN');view:render(dfhack.getTickCount())
 result.scrolled={category=stocks.scroll_position_type,item=stocks.scroll_position_item}
 assert(result.scrolled.category==1 and result.scrolled.item==51,'Native scroll reference differs: '..json.encode(result.scrolled))
end
for y=0,df.global.gps.dimy-1 do
 local row={};for x=0,df.global.gps.dimx-1 do row[#row+1]=dfhack.screen.readTile(x,y).ch end
 result.screen_rows[#result.screen_rows+1]=row
end
local f=assert(io.open(out..'/stocks-native.json','w'));f:write(json.encode(result));f:close()
f=assert(io.open(out..'/shot.tmp','w'));f:write('stocks-root');f:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
local deadline=dfhack.getTickCount()+10000
while true do local ack=io.open(out..'/ack-stocks-root');if ack then ack:close();break end
 assert(dfhack.getTickCount()<deadline,'Stocks capture timeout');script.sleep(1,'frames')end
records[#records+1]={name='stocks-root',types=#result.types,groups=#result.groups}
gui.simulateInput(view,'LEAVESCREEN');assert(not stocks.open,'Stocks did not close')

end
-- A coinless save must not turn the coin-family lane into a vacuous pass.
-- Only this disposable, paused native fixture creates items; product reads do not.
if os.getenv('DF3D_STOCKS_WRITTEN_FIXTURE')=='1' then
 local worker,pages
 for _,unit in ipairs(df.global.world.units.active)do if dfhack.units.isCitizen(unit)then worker=unit;break end end
 for _,book in ipairs(df.global.world.items.other.BOOK)do
  for _,improvement in ipairs(book.improvements)do
   if df.itemimprovement_pagesst:is_instance(improvement) and #improvement.contents==1 then pages=improvement;break end
  end
  if pages then break end
 end
 assert(worker and pages,'Written sheet fixture needs a citizen and a book with content')
 local created={}
 return dfhack.with_finalize(function()
  for _,item in ipairs(created)do dfhack.items.remove(item)end
 end,function()
  created=dfhack.items.createItem(worker,df.item_type.SHEET,-1,pages.mat_type,pages.mat_index)
  assert(#created>0,'Native sheet creation failed')
  for _,item in ipairs(created)do
   local writing=df.itemimprovement_writingst:new()
   writing.mat_type=pages.mat_type;writing.mat_index=pages.mat_index
   writing.maker=pages.maker;writing.quality=pages.quality
   writing.contents:insert('#',pages.contents[0]);item.improvements:insert('#',writing)
  end
  local f=assert(io.open(out..'/stocks-written-fixture.json','w'))
  f:write(json.encode({item_id=created[1].id,content_id=pages.contents[0],mat_type=pages.mat_type,mat_index=pages.mat_index}));f:close()
  run()
 end)
end
if os.getenv('DF3D_STOCKS_COIN_FIXTURE')=='1' then
 local worker
 for _,unit in ipairs(df.global.world.units.active)do
  if dfhack.units.isCitizen(unit)then worker=unit;break end
 end
 assert(worker,'Coin fixture needs a citizen')
 local material=assert(dfhack.matinfo.find('INORGANIC:COPPER'))
 local batches=df.global.world.coin_batches.all
 local batch=df.coin_batch:new();local index=#batches;local created={};local inserted=false
 batch.year=df.global.cur_year;batch.mat_type=material.type;batch.mat_index=material.index
 batch.entity=df.global.plotinfo.civ_id;batch.ruler=-1
 batch.image_front.id=-1;batch.image_front.subid=-1
 batch.image_back.id=-1;batch.image_back.subid=-1
 return dfhack.with_finalize(function()
  for _,item in ipairs(created)do dfhack.items.remove(item)end
  -- Generated art retains the batch index; keep its record until unsaved exit.
  if not inserted then df.delete(batch)end
 end,function()
  assert(index<32768,'Coin batch index exceeds item storage')
  batches:insert('#',batch);inserted=true
  created=dfhack.items.createItem(worker,df.item_type.COIN,-1,material.type,material.index)
  assert(#created>0,'Native coin creation failed')
  for _,item in ipairs(created)do item.coin_batch=index end
  if os.getenv('DF3D_STOCKS_ART_RENDER')=='1' then
   for _,item in ipairs(created)do probe('item-inspect-probe',tostring(item.id))end
  end
  run()
  assert(batch.image_front.id>=0 and batch.image_back.id>=0,'Coin descriptions did not initialize both images')
  local f=assert(io.open(out..'/stocks-coin-fixture.json','w'))
  f:write(json.encode({item_id=created[1].id,batch_index=index,entity=batch.entity,
   front={id=batch.image_front.id,subid=batch.image_front.subid},
   back={id=batch.image_back.id,subid=batch.image_back.subid},cold_images_initialized=true}));f:close()
 end)
end
if os.getenv('DF3D_STOCKS_DOOR_STATES')=='1' then
 local source=debug.getinfo(1,'S').source:sub(2):gsub('stocks%-native.lua$','stocks-door-states-native.lua')
 return assert(loadfile(source))(out,probe,run)
end
if os.getenv('DF3D_STOCKS_SKIN_SHEETS')=='1' then
 -- This paused clone has no naturally occurring TAN_MAT pieces. Keep the
 -- real body's identity/anatomy and temporarily supply native skin material
 -- plus an existing two-color pattern to exercise the composition branch.
 local selection=probe('stocks-selection-probe','46','')
 local item=assert(df.item.find(selection.groups[1].ids[1]))
 local skin=assert(dfhack.matinfo.find('CREATURE:DWARF:SKIN'))
 local pattern_index,pattern
 for index,value in ipairs(df.global.world.raws.descriptors.patterns)do
  if value.pattern==df.pattern_type.STRIPES and #value.colors>=2 then pattern_index=index;pattern=value;break end
 end
 assert(pattern,'Missing native striped pattern fixture')
 local old_type,old_index=item.largest_tissue.mat_type,item.largest_tissue.mat_index
 local old_flags=item.corpse_flags.whole
 local old_pattern=skin.material.state_color[df.matter_state.Solid]
 local facts={controlled_material_fixture=true,item_id=item.id,material=skin:getToken(),pattern=pattern.id,
  original_material_type=old_type,original_material_index=old_index,original_flags=old_flags,original_pattern=old_pattern}
 local function record()local f=assert(io.open(out..'/stocks-skin-fixture.json','w'));f:write(json.encode(facts));f:close()end
 return dfhack.with_finalize(function()
  item.largest_tissue.mat_type=old_type;item.largest_tissue.mat_index=old_index;item.corpse_flags.whole=old_flags
  skin.material.state_color[df.matter_state.Solid]=old_pattern
  facts.restored=item.largest_tissue.mat_type==old_type and item.largest_tissue.mat_index==old_index and item.corpse_flags.whole==old_flags and skin.material.state_color[df.matter_state.Solid]==old_pattern
  record();assert(facts.restored,'Skin fixture did not restore')
 end,function()
  item.largest_tissue.mat_type=skin.type;item.largest_tissue.mat_index=skin.index;item.corpse_flags.unbutchered=false
  skin.material.state_color[df.matter_state.Solid]=pattern_index;record()
  return run()
 end)
end
return run()
