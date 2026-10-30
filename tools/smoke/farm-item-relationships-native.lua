-- Protected paused oracle: temporary stockpile extent overlap, never gameplay.
local out,view,records,b,capture,select_map=...
local gui=require('gui');local json=require('json')
local g=df.global.gps;local sheet=df.global.game.main_interface.view_sheets
local item=assert(b.contained_items[0].item)
local pile=assert(df.global.world.buildings.other.STOCKPILE[0])
assert(pile.room.extents and pile.room.width*pile.room.height>0)
local saved={bounds={},room={},extent=pile.room.extents[0],categories=pile.settings.flags.whole,
 flags=item.flags.whole,whole=item.weight.whole,fraction=item.weight.fraction}
for _,key in ipairs{'x1','x2','y1','y2','z','centerx','centery'}do saved.bounds[key]=pile[key]end
for _,key in ipairs{'x','y','width','height'}do saved.room[key]=pile.room[key]end
local function restore()
 for key,value in pairs(saved.bounds)do pile[key]=value end
 for key,value in pairs(saved.room)do pile.room[key]=value end
 pile.room.extents[0]=saved.extent;pile.settings.flags.whole=saved.categories
 item.flags.whole=saved.flags;item.weight.whole=saved.whole;item.weight.fraction=saved.fraction
end
local function move(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 gui.simulateInput(view,{});view:render(dfhack.getTickCount())
end
local ok,err=xpcall(function()
 select_map(b);move(756,526);gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 assert(sheet.open and sheet.active_sheet==df.view_sheet_type.ITEM and sheet.active_id==item.id)
 local x,y,z=dfhack.items.getPosition(item);local pos={x=x,y=y,z=z}
 pile.x1=pos.x;pile.x2=pos.x;pile.centerx=pos.x;pile.y1=pos.y;pile.y2=pos.y;pile.centery=pos.y;pile.z=pos.z
 pile.room.x=pos.x;pile.room.y=pos.y;pile.room.width=1;pile.room.height=1;pile.room.extents[0]=1
 local masks={0,3};for bit=0,16 do masks[#masks+1]=1<<bit end
 for _,mask in ipairs(masks)do
  pile.settings.flags.whole=mask;move(0,4)
  local text,code=dfhack.run_command_silent('df3d','item-inspect-probe',tostring(item.id));assert(code==0,text)
  local snapshot=json.decode(text).snapshot
  assert(snapshot.holder.id==b.id and snapshot.stockpile.id==pile.id and snapshot.stockpile_categories==mask,'independent relationships differ')
  local row=capture('farm-item-relationships-'..mask);row.snapshot=snapshot
  row.in_job=item.flags.in_job;row.in_building=item.flags.in_building
  local stockpile_row,holder_row
  for index,line in ipairs(row.lines)do
   if line:find('View stockpile',1,true)then stockpile_row=index end
   if line:find('In Farm Plot',1,true)then holder_row=index end
  end
  assert(stockpile_row and holder_row==stockpile_row+3,'native relationship rows do not stack by three cells')
 end
 move(816,298);gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 assert(sheet.active_sheet==df.view_sheet_type.BUILDING and sheet.active_id==b.id,'shifted holder View selected wrong target')
 local row=capture('farm-item-relationships-holder-view');row.holder_id=b.id
end,debug.traceback)
if sheet.open then gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())end
restore();select_map(b)
for key,value in pairs(saved.bounds)do assert(pile[key]==value)end
for key,value in pairs(saved.room)do assert(pile.room[key]==value)end
assert(pile.room.extents[0]==saved.extent and pile.settings.flags.whole==saved.categories and item.flags.whole==saved.flags)
assert(ok,err)
records[#records+1]={name='farm-item-relationships-restored',restored=true,item_id=item.id,stockpile_id=pile.id}
