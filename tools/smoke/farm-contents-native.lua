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
   flags=item.flags.whole,countdown=item.stockpile_countdown,delay=item.stockpile_delay,
   name=dfhack.df2utf(dfhack.items.getDescription(item,0)),type=df.item_type[item:getType()],
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
 local native_states={}
 for toggle=1,2 do
  move(probe[2],526);gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
  local row=capture('farm-contents-'..probe[1]..'-'..toggle)
  row.contents=items();row.building_flags=b.flags.whole
  native_states[toggle]={contents=row.contents,building_flags=row.building_flags}
  assert(row.active_sheet=='BUILDING' and row.active_id==b.id,'contents action lost farm target')
  if toggle==1 then assert(require('json').encode(row.contents)~=original or b.flags.whole~=flags,'contents control had no effect')end
 end
 assert(require('json').encode(items())==original and b.flags.whole==flags,'contents toggle did not restore original facts')
 local action=probe[1]=='visibility' and 'hidden' or probe[1]
 local item=assert(b.contained_items[0].item)
 local function command(want,expected,outcome)
  local guards={}
  for _,object in ipairs{main.view_sheets,df.global.plotinfo}do
   local size,address=df.sizeof(object);local bytes=df.new('uint8_t',size)
   dfhack.internal.memmove(bytes,address,size);guards[#guards+1]={size=size,address=address,bytes=bytes}
  end
  local text,code=dfhack.run_command_silent('df3d','farm-item-set',tostring(b.id),tostring(item.id),action,tostring(want),tostring(expected))
  assert(code==0,text);local result=require('json').decode(text)
  assert(result.outcome==outcome,'native adapter outcome differs: '..text)
  for _,guard in ipairs(guards)do
   assert(dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)==0,'native item action changed UI scratch')
   df.delete(guard.bytes)
  end
  return result
 end
 local stale=command(1,item.flags.whole+1,'stale')
 assert(require('json').encode(items())==original,'stale adapter changed item facts')
 for toggle=1,2 do
  local result=command(toggle==1 and 1 or 0,item.flags.whole,'completed')
  local actual={contents=items(),building_flags=b.flags.whole}
  assert(require('json').encode(actual)==require('json').encode(native_states[toggle]),'adapter differs from native item click')
  local identical=command(toggle==1 and 1 or 0,item.flags.whole,'completed')
  assert(require('json').encode(actual)==require('json').encode({contents=items(),building_flags=b.flags.whole}),'identical intent changed item facts')
  records[#records+1]={name='farm-contents-adapter-'..action..'-'..toggle,result=result,identical=identical,stale=stale,native_equal=true,ui_scratch_unchanged=true}
 end
end
local item=b.contained_items[0].item
local text,code=dfhack.run_command_silent('df3d','farm-item-set',tostring(b.id),tostring(item.id),'melt','1',tostring(item.flags.whole))
assert(code==0 and require('json').decode(text).outcome=='rejected','ineligible seed melting accepted')
for _,args in ipairs{{'-1',tostring(item.id)},{tostring(b.id),'2147483647'}}do
 local _,bad=dfhack.run_command_silent('df3d','farm-item-set',args[1],args[2],'dump','1',tostring(item.flags.whole))
 assert(bad~=0,'invalid contained-item target accepted')
end
