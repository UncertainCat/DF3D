-- Native UI discovery only. Runtime must not consume these menu fields.
local out,view,records,select_map,capture=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local sheet=df.global.game.main_interface.view_sheets
local result={buildings={}}
local provider=os.getenv('DF3D_BUILDING_LINKS_PROVIDER')=='1'
local function probe(id)
 local text,code=dfhack.run_command_silent('df3d','building-links-probe',tostring(id))
 assert(code==0,text);return json.decode(text)
end
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
 if provider then
  row.provider=probe(id)
  assert(row.provider.building_id==id and row.provider.tabs and #row.provider.rows==#row.refs,'Provider identity/count mismatch')
  for i,link in ipairs(row.provider.rows)do local ref=row.refs[i]
   assert(link.id==ref.target_id and link.type==ref.target_type and link.item_id==ref.item_id and link.reference_type==df.general_ref_type[ref.ref_type],'Provider reference order mismatch')
   assert(link.x==ref.target_position.x and link.y==ref.target_position.y and link.z==ref.target_position.z,'Provider target position mismatch')
  end
 end
 view:render(dfhack.getTickCount());select_map(b)
 assert(sheet.active_sheet==df.view_sheet_type.BUILDING and sheet.active_id==id)
 local function sample(label)
  local cursor=df.global.cursor
  local state={label=label,open=sheet.open,show_linked=sheet.show_linked_buildings,scroll=sheet.scroll_position_linked_buildings,selected_id=sheet.active_id,cursor={x=cursor.x,y=cursor.y,z=cursor.z},window={x=df.global.window_x,y=df.global.window_y,z=df.global.window_z},lines={}}
  for y=0,g.dimy-1 do local chars={};for x=52,112 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
   local text=dfhack.df2utf(table.concat(chars)):gsub('%s+$','');if text:find('%S')then state.lines[#state.lines+1]={y=y,text=text}end
  end
  row.states[#row.states+1]=state;persist();capture('building-links-'..id..'-'..label)
  if provider then
   local observed=probe(id)
   assert(observed.revision==row.provider.revision and json.encode(observed.rows)==json.encode(row.provider.rows),'Native UI changed owned provider output')
   if label=='left-tab' then
    for i,link in ipairs(observed.rows)do
     local found=false;for _,line in ipairs(state.lines)do if line.y==46+(i-1)*3 and line.text:find(link.name,1,true)then found=true end end
     assert(found,'Provider name differs from native rendered row')
    end
   end
  end
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
if provider then
 result.unlinked=probe(65)
 assert(not result.unlinked.tabs and #result.unlinked.rows==0,'Unlinked chair acquired link tabs')
 persist()
end
if os.getenv('DF3D_BUILDING_LINKS_WIRE')=='1'then
 assert(provider,'Wire qualification requires the independent provider oracle')
 capture('workshop-wire')
 local file=assert(io.open(out..'/workshop-wire-result.json','r'));local wire=json.decode(file:read('*a'));file:close()
 assert(wire.success,'Building links wire failed');result.wire=wire;persist()
end
records[#records+1]={name='building-links-native',result=result}
