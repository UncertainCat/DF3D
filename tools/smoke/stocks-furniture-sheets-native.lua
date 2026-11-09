-- Protected native reference only; no product code consumes UI storage.
local out,view,stocks,probe=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local function read(name)local f=assert(io.open(out..'/'..name));local data=json.decode(f:read('*a'));f:close();return data end
local results={};local g=df.global.gps;local sheet=df.global.game.main_interface.view_sheets
local function click(x,y)
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=y//12
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
end
for _,family in ipairs(read('stocks-wire-reference.json').furniture)do
 local found=false
 for index,value in ipairs(stocks.filtered_type_list)do if value==family.kind then stocks.scroll_position_type=index;found=true;break end end
 assert(found,'Missing native furniture category');view:render(dfhack.getTickCount());click(100,94)
 assert(stocks.current_type==family.kind,'Native category click failed')
 stocks.scroll_position_type=0;stocks.scroll_position_item=0;view:render(dfhack.getTickCount())
 if not stocks.current_type_a_expanded[0] then click(500,130) end
 local selection=probe('stocks-selection-probe',tostring(family.kind),'')
 local rows=0
 for index,group in ipairs(selection.groups)do rows=rows+1+(stocks.current_type_a_expanded[index-1] and #group.ids or 0)end
 local capacity=math.floor((g.dimy-10)/3)*3-3
 click(rows*3>capacity and 820 or 836,166)
 assert(not stocks.open and sheet.open and sheet.active_sheet==df.view_sheet_type.ITEM and sheet.active_id==family.id,'Native furniture View differs')
 local wire=read('stocks-furniture-wire-'..family.kind..'.json')
 local description=dfhack.df2utf(sheet.raw_description)
 assert(wire.description==description,'Furniture description mismatch '..family.kind)
 local observed=probe('item-inspect-probe',tostring(family.id)).snapshot
 assert(observed.description==description,'Native provider description mismatch '..family.kind)
 results[#results+1]={kind=family.kind,id=family.id,description=description,snapshot=observed}
 if os.getenv('DF3D_STOCKS_ITEM_USES')=='1' then
  local uses=probe('item-uses-probe',tostring(family.id))
  assert(uses.description==description,'Owned Uses builder description differs')
  assert(#uses.uses==#sheet.item_use and #uses.uses==#sheet.item_use_reaction_index,'Owned Uses row count differs')
  for index,row in ipairs(uses.uses)do
   assert(row.caption==dfhack.df2utf(sheet.item_use[index-1].value),'Owned Uses caption differs')
   assert(row.reaction==sheet.item_use_reaction_index[index-1],'Owned Uses reaction differs')
  end
  results[#results].uses=uses.uses
  local f=assert(io.open(out..'/stocks-item-uses-'..family.kind..'.json','w'));f:write(json.encode(uses));f:close()
 end
 -- Allow the native renderer to finish drawing the new sheet before capture.
 script.sleep(3,'frames');view:render(dfhack.getTickCount())
 local name='stocks-furniture-native-'..family.kind
 local f=assert(io.open(out..'/shot.tmp','w'));f:write(name);f:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local deadline=dfhack.getTickCount()+10000
 while true do local ack=io.open(out..'/ack-'..name);if ack then ack:close();break end
  assert(dfhack.getTickCount()<deadline,'Furniture capture timeout');script.sleep(1,'frames')end
 if os.getenv('DF3D_STOCKS_CONTENTS_SCROLL')=='1' then
  local source=debug.getinfo(1,'S').source:sub(2):gsub('stocks%-furniture%-sheets%-native.lua$','item-contents-scroll-native.lua')
  results[#results].contents_scroll=assert(loadfile(source))(out,view)
 end
 if os.getenv('DF3D_STOCKS_CHILD_HOVER')=='1' then
  local main=df.global.game.main_interface;local observations={}
  for _,target in ipairs{{'header-forbid',804,76},{'header-dump',828,76},{'task-absent',748,406},{'view',772,406},{'forbid',796,406},{'dump',820,406},{'melt',844,406},{'visibility',868,406},{'melt-absent',844,298}}do
   local deadline=dfhack.getTickCount()+700
   repeat
    df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
    g.precise_mouse_x=target[2];g.precise_mouse_y=target[3];g.mouse_x=target[2]//8;g.mouse_y=(target[3]-4)//12
    gui.simulateInput(view,{});view:render(dfhack.getTickCount());script.sleep(1,'frames')
   until dfhack.getTickCount()>=deadline
   local row={kind=target[1],x=target[2],y=target[3],instruction=main.current_hover,active=main.hover_instructions_on,lines={}}
   if row.active then
    for y=0,17 do local line={}
     for x=g.dimx-24,g.dimx-1 do local ch=dfhack.screen.readTile(x,y).ch;line[#line+1]=ch>=32 and string.char(ch%256)or' 'end
     row.lines[#row.lines+1]=dfhack.df2utf(table.concat(line)):gsub('%s+$','')
    end
    while #row.lines>0 and row.lines[#row.lines]==''do table.remove(row.lines)end
   end
   if row.kind=='header-dump' then assert(row.active and row.instruction==208,'Header tooltip control failed')end
   if row.kind=='view' or row.kind=='forbid' or row.kind=='dump' or row.kind=='melt' or row.kind=='visibility' or row.kind=='melt-absent' then assert(not row.active and row.instruction==-1,'Unexpected native child tooltip')end
   observations[#observations+1]=row
  end
  results[#results].child_hover=observations
  local f=assert(io.open(out..'/stocks-child-hover-native.json','w'));f:write(json.encode(observations));f:close()
 end
 if os.getenv('DF3D_STOCKS_CHILD_VIEW')=='1' then
  local child=read('stocks-child-wire.json');click(772,298)
  assert(sheet.open and sheet.active_sheet==df.view_sheet_type.ITEM and sheet.active_id==child.id,'Native child View target differs')
  assert(child.description==dfhack.df2utf(sheet.raw_description),'Native child description differs')
  results[#results].child={id=child.id,description=dfhack.df2utf(sheet.raw_description)}
  script.sleep(8,'frames');view:render(dfhack.getTickCount())
  local f=assert(io.open(out..'/shot.tmp','w'));f:write('stocks-child-native');f:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
  local deadline=dfhack.getTickCount()+10000
  while true do local ack=io.open(out..'/ack-stocks-child-native');if ack then ack:close();break end
   assert(dfhack.getTickCount()<deadline,'Child capture timeout');script.sleep(1,'frames')end
  click(816,286)
  assert(sheet.open and sheet.active_id==family.id,'Native container View return differs')
  results[#results].child.returned_to_container=true
 end
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
 assert(not sheet.open and not stocks.open,'Native furniture close differs')
 gui.simulateInput(view,'D_STOCKS');view:render(dfhack.getTickCount())
end
return results
