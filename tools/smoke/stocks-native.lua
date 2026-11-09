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
