-- Native UI discovery only. Runtime must not consume these menu fields.
local out,view,records,select_map,capture=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local sheet=df.global.game.main_interface.view_sheets
local result={buildings={}}
local function click(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
end
local function persist()
 local f=assert(io.open(out..'/building-links-native.json','w'));f:write(json.encode(result));f:close()
end
for _,id in ipairs{39,55}do
 local b=assert(df.building.find(id));local row={id=id,type=b:getType(),refs={},states={}}
 for _,held in ipairs(b.contained_items)do for _,ref in ipairs(held.item.general_refs)do
  local kind=ref:getType()
  if kind==df.general_ref_type.BUILDING_TRIGGER or kind==df.general_ref_type.BUILDING_TRIGGERTARGET then
   local target=ref:getBuilding()
   row.refs[#row.refs+1]={item_id=held.item.id,ref_type=df.general_ref_type[kind],target_id=target and target.id or -1,target_type=target and target:getType() or -1,target_position=target and {x=target.centerx,y=target.centery,z=target.z} or nil}
  end
 end end
 result.buildings[#result.buildings+1]=row
 if sheet.open then gui.simulateInput(view,'LEAVESCREEN')end
 view:render(dfhack.getTickCount());select_map(b)
 assert(sheet.active_sheet==df.view_sheet_type.BUILDING and sheet.active_id==id)
 local function sample(label)
  local cursor=df.global.cursor
  local state={label=label,open=sheet.open,show_linked=sheet.show_linked_buildings,scroll=sheet.scroll_position_linked_buildings,selected_id=sheet.active_id,cursor={x=cursor.x,y=cursor.y,z=cursor.z},window={x=df.global.window_x,y=df.global.window_y,z=df.global.window_z},lines={}}
  for y=0,g.dimy-1 do local chars={};for x=52,112 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
   local text=dfhack.df2utf(table.concat(chars)):gsub('%s+$','');if text:find('%S')then state.lines[#state.lines+1]={y=y,text=text}end
  end
  row.states[#row.states+1]=state;persist();capture('building-links-'..id..'-'..label)
 end
 sample('initial');click(540,520);sample('left-tab')
 click(540,562);sample('row-body')
 assert(sheet.active_id==id,'Linked row body unexpectedly changed selection')
 click(868,562);sample('navigate-first')
 local target=assert(df.building.find(row.refs[1].target_id))
 assert(not sheet.open,'Linked row recenter did not close panel')
 assert(df.global.window_z==target.z,'Linked row recenter missed target level')
 view:render(dfhack.getTickCount());select_map(b)
 sample('reopened');click(720,520);sample('right-tab')
end
records[#records+1]={name='building-links-native',result=result}
