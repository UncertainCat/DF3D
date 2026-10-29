-- Protected paused-clone oracle. UI scratch is diagnostic evidence only.
local out,view,records,b,capture,select_map=...
local gui=require('gui');local script=require('gui.script');local g=df.global.gps
local main=df.global.game.main_interface
local function move(x,y)
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 gui.simulateInput(view,{});view:render(dfhack.getTickCount())
end
local function items()
 local rows={}
 for _,held in ipairs(b.contained_items)do
  local item=assert(held.item)
  rows[#rows+1]={id=item.id,role=df.building_item_role_type[held.use_mode],role_value=held.use_mode,
   flags=item.flags.whole,name=dfhack.df2utf(dfhack.items.getDescription(item,0)),type=df.item_type[item:getType()],
   position={x=item.pos.x,y=item.pos.y,z=item.pos.z}}
 end
 return rows
end
local baseline=capture('farm-contents-baseline');baseline.contents=items()
local _,address=df.sizeof(b);local _,field=df.sizeof(b:_field('contained_items'))
baseline.contained_items_offset=field-address
assert(#baseline.contents>0,'farm contents fixture empty')
for _,probe in ipairs{{'role',732,526},{'view',756,526},{'forbid',780,526},{'dump',804,526},{'melt',828,526},{'visibility',852,526}}do
 local deadline=dfhack.getTickCount()+900
 repeat move(probe[2],probe[3]);script.sleep(1,'frames')until dfhack.getTickCount()>=deadline
 move(probe[2],probe[3])
 local lines={};for y=0,17 do local text={};for x=g.dimx-24,g.dimx-1 do
  local ch=dfhack.screen.readTile(x,y).ch;text[#text+1]=ch>=32 and ch<127 and string.char(ch)or' '
 end;lines[#lines+1]=table.concat(text):gsub('%s+$','')end
 records[#records+1]={name='farm-contents-hover-'..probe[1],hover=main.current_hover,
  enabled=main.hover_instructions_on,lines=lines,mouse={probe[2],probe[3]},contents=items()}
end
-- Eye controls expose the actual row identity without guessing name order.
for index=0,5 do
 move(756,526+index*36);gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 local row=capture('farm-contents-view-'..index)
 assert(row.active_sheet=='ITEM' and row.active_id==baseline.contents[index+1].id,'contents eye row identity/order differs')
 row.contents=items()
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
 select_map(b)
 assert(main.view_sheets.active_sheet==df.view_sheet_type.BUILDING and main.view_sheets.active_id==b.id,'contents fixture did not return to farm')
end
for _,probe in ipairs{{'forbid',780},{'dump',804},{'visibility',852}}do
 local original=require('json').encode(items());local flags=b.flags.whole
 for toggle=1,2 do
  move(probe[2],526);gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
  local row=capture('farm-contents-'..probe[1]..'-'..toggle)
  row.contents=items();row.building_flags=b.flags.whole
  assert(row.active_sheet=='BUILDING' and row.active_id==b.id,'contents action lost farm target')
  if toggle==1 then assert(require('json').encode(row.contents)~=original or b.flags.whole~=flags,'contents control had no effect')end
 end
 assert(require('json').encode(items())==original and b.flags.whole==flags,'contents toggle did not restore original facts')
end
