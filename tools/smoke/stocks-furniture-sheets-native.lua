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
 -- Allow the native renderer to finish drawing the new sheet before capture.
 script.sleep(3,'frames');view:render(dfhack.getTickCount())
 local name='stocks-furniture-native-'..family.kind
 local f=assert(io.open(out..'/shot.tmp','w'));f:write(name);f:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local deadline=dfhack.getTickCount()+10000
 while true do local ack=io.open(out..'/ack-'..name);if ack then ack:close();break end
  assert(dfhack.getTickCount()<deadline,'Furniture capture timeout');script.sleep(1,'frames')end
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
 assert(not sheet.open and not stocks.open,'Native furniture close differs')
 gui.simulateInput(view,'D_STOCKS');view:render(dfhack.getTickCount())
end
return results
