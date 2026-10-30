-- Paused disposable diagnostic. Reciprocal temporary relationships are restored.
local out,view,records,b,capture,select_map=...
local gui=require('gui');local json=require('json')
local g=df.global.gps;local sheet=df.global.game.main_interface.view_sheets
local entry=assert(b.contained_items[0]);local item=entry.item
local saved={flags=item.flags.whole,x=item.pos.x,y=item.pos.y,z=item.pos.z,refs={}}
for _,ref in ipairs(item.general_refs)do saved.refs[#saved.refs+1]=ref end
local container,unit
for _,candidate in ipairs(df.global.world.items.other.BOX)do
 local x,y,z=dfhack.items.getPosition(candidate)
 if not candidate.flags.removed and x and x>=0 and z==b.z then container=candidate;break end
end
for _,candidate in ipairs(df.global.world.units.active)do
 if dfhack.units.isCitizen(candidate) and candidate.pos.z==b.z then unit=candidate;break end
end
assert(container and unit,'carrier fixture requires a box and citizen on the farm level')
local ref,reciprocal,inventory,detached
local function restore()
 if not detached then return end
 if reciprocal then assert(container.general_refs[#container.general_refs-1]==reciprocal);container.general_refs:erase(#container.general_refs-1);df.delete(reciprocal);reciprocal=nil end
 if inventory then assert(unit.inventory[#unit.inventory-1]==inventory);unit.inventory:erase(#unit.inventory-1);df.delete(inventory);inventory=nil end
 while #item.general_refs>0 do item.general_refs:erase(#item.general_refs-1)end
 if ref then df.delete(ref);ref=nil end
 for _,original in ipairs(saved.refs)do item.general_refs:insert('#',original)end
 b.contained_items:insert(0,entry)
 item.flags.whole=saved.flags;item.pos.x=saved.x;item.pos.y=saved.y;item.pos.z=saved.z
 detached=false
end
local function move(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 gui.simulateInput(view,{});view:render(dfhack.getTickCount())
end
local ok,err=xpcall(function()
 for _,kind in ipairs{'container','unit'}do
  select_map(b);move(756,526);gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
  assert(sheet.open and sheet.active_sheet==df.view_sheet_type.ITEM and sheet.active_id==item.id)
  b.contained_items:erase(0);detached=true
  for index=#item.general_refs-1,0,-1 do if item.general_refs[index]:getType()==df.general_ref_type.BUILDING_HOLDER then item.general_refs:erase(index)end end
  item.flags.in_building=false;item.flags.in_inventory=true;item.flags.on_ground=false
  local target
  if kind=='container' then
   target=container;ref=df.general_ref_contained_in_itemst:new();ref.item_id=target.id
   reciprocal=df.general_ref_contains_itemst:new();reciprocal.item_id=item.id;container.general_refs:insert('#',reciprocal)
  else
   target=unit;ref=df.general_ref_unit_holderst:new();ref.unit_id=target.id
   inventory=df.unit_inventory_item:new();inventory.item=item;inventory.mode=df.inv_item_role_type.Hauled;inventory.body_part_id=-1;unit.inventory:insert('#',inventory)
  end
  item.general_refs:insert('#',ref);item.pos:assign(target.pos);move(0,4)
  local row=capture('farm-item-carrier-'..kind);row.item_id=item.id;row.target_id=target.id;row.description=dfhack.df2utf(sheet.raw_description)
  local text,code=dfhack.run_command_silent('df3d','item-inspect-probe',tostring(item.id));assert(code==0,text);row.independent=json.decode(text).snapshot
  local guards={}
  for _,object in ipairs{sheet,df.global.plotinfo}do
   local size,address=df.sizeof(object);local bytes=df.new('uint8_t',size)
   dfhack.internal.memmove(bytes,address,size);guards[#guards+1]={bytes=bytes,address=address,size=size}
  end
  local semantic,status=dfhack.run_command_silent('df3d','item-carrier-probe',tostring(item.id));assert(status==0,semantic)
  row.carrier=json.decode(semantic)
  assert(row.carrier.kind==(kind=='container' and 1 or 2) and row.carrier.id==target.id,'semantic carrier differs from native navigation')
  local native_name=dfhack.utf2df(row.carrier.name):gsub('[^ -~]',' '):sub(1,18)
  local matched=false;for _,line in ipairs(row.lines)do if line:find(native_name,1,true)then matched=true end end
  assert(matched,'semantic carrier name differs from native row')
  for _,guard in ipairs(guards)do
   local bytes=df.new('uint8_t',guard.size);dfhack.internal.memmove(bytes,guard.address,guard.size)
   for index=0,guard.size-1 do assert(bytes[index]==guard.bytes[index],'carrier reader changed native UI state')end
   df.delete(bytes);df.delete(guard.bytes)
  end
  row.native_ui_unchanged=true
  move(816,250);gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
  local linked=capture('farm-item-carrier-'..kind..'-view');linked.target_id=target.id
  assert(sheet.open and sheet.active_id==target.id and sheet.active_sheet==(kind=='unit' and df.view_sheet_type.UNIT or df.view_sheet_type.ITEM),'native carrier View selected wrong identity')
  gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());restore()
 end
end,debug.traceback)
if sheet.open then gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())end
restore();select_map(b)
assert(b.contained_items[0]==entry and item.flags.whole==saved.flags and #item.general_refs==#saved.refs)
for index,original in ipairs(saved.refs)do assert(item.general_refs[index-1]==original)end
assert(ok,err)
records[#records+1]={name='farm-item-carriers-restored',restored=true,item_id=item.id}
