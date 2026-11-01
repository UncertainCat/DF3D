-- Native observation only. Diagnostic restoration below is not a product Back
-- implementation and is reported separately from native navigation outcomes.
local unit,view,pointer,click,capture=...
local gui=require('gui');local script=require('gui.script')
local main=df.global.game.main_interface;local sheet=main.view_sheets;local g=df.global.gps
local saved={};local vectors={}
for _,key in ipairs{'open','context','active_sheet','active_id','active_sub_tab','scroll_position_inventory',
 'scroll_position','viewing_bldid','viewing_x','viewing_y','viewing_z'}do saved[key]=sheet[key]end
for _,key in ipairs{'viewing_unid','viewing_itid','viewing_vermin_combined_id'}do
 vectors[key]={};for _,id in ipairs(sheet[key])do vectors[key][#vectors[key]+1]=id end
end
local function restore()
 for key,value in pairs(saved)do sheet[key]=value end
 for key,values in pairs(vectors)do sheet[key]:resize(0);for _,id in ipairs(values)do sheet[key]:insert('#',id)end end
 pointer(400,400)
end
local function state()
 local inventory={}
 for _,entry in ipairs(unit.inventory)do inventory[#inventory+1]={id=entry.item.id,flags=entry.item.flags.whole,
  mode=entry.mode,body_part_id=entry.body_part_id,weight_computed=entry.item.flags.weight_computed}end
 return {open=sheet.open,kind=sheet.active_sheet,id=sheet.active_id,tab=sheet.active_sub_tab,
  scroll=sheet.scroll_position_inventory,context=sheet.context,inventory=inventory}
end
local result={initial=state(),help={}}
local ok,err=xpcall(function()
 for _,case in ipairs{{'clothing',836,226,df.main_hover_instruction.INVENTORY_IS_CLOTHING},
   {'inspect',868,226,df.main_hover_instruction.INVENTORY_VIEW_ITEM}}do
  local until_hover=dfhack.getTickCount()+650
  while dfhack.getTickCount()<until_hover do pointer(case[2],case[3]);script.sleep(1,'frames')end
  pointer(case[2],case[3]);assert(main.current_hover==case[4] and main.hover_instructions_on,'Items help did not activate')
  local row={name=case[1],hover=main.current_hover,lines={}}
  for y=0,17 do
   local text={}
   for x=g.dimx-24,g.dimx-1 do local pen=dfhack.screen.readTile(x,y);text[#text+1]=pen.ch>=32 and string.char(pen.ch%256) or ' 'end
   row.lines[#row.lines+1]=dfhack.df2utf(table.concat(text)):gsub('%s+$','')
  end
  while #row.lines>0 and row.lines[#row.lines]==''do table.remove(row.lines)end
  result.help[#result.help+1]=row;capture('unit-items-help-'..case[1],function()pointer(case[2],case[3])end)
 end
 click(836,226);result.clothing_click=state()
 assert(sheet.open and sheet.active_sheet==df.view_sheet_type.UNIT and sheet.active_id==unit.id and sheet.active_sub_tab==saved.active_sub_tab,'Clothing indicator navigated')
 click(868,226);pointer(400,400);result.inspect=state();capture('unit-items-inspected')
 assert(sheet.open and sheet.active_sheet==df.view_sheet_type.ITEM and sheet.active_id==unit.inventory[0].item.id,'Inspect selected wrong item')
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
 result.escape_from_item=state();capture('unit-items-inspected-escape')
 restore();click(868,226);pointer(400,400)
 click(816,250);pointer(400,400);result.carrier_return=state();capture('unit-items-carrier-return')
 assert(sheet.open and sheet.active_sheet==df.view_sheet_type.UNIT and sheet.active_id==unit.id,'Carrier View selected wrong creature')
end,debug.traceback)
restore();result.diagnostic_restored=state()
assert(ok,err)
return result
