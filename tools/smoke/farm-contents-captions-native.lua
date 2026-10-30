-- Owned paused diagnostic only. Restore raw names and membership before exit.
local out,view,records,b,capture,select_map=...
local json=require('json');local script=require('gui.script')
local g=df.global.gps;local sheet=df.global.game.main_interface.view_sheets
local saved={};local flags={}
for _,entry in ipairs(b.contained_items)do saved[#saved+1]=entry;flags[entry.item.id]=entry.item.flags.whole end
assert(#saved>=7,'caption fixture requires a scrolling list')
local item=saved[1].item;assert(item:getType()==df.item_type.SEEDS)
local plant=assert(dfhack.matinfo.decode(item).plant,'seed plant missing')
local singular,plural=plant.seed_singular,plant.seed_plural
local frame=df.global.world.frame_counter
local function restore()
 plant.seed_singular=singular;plant.seed_plural=plural
 while #b.contained_items>0 do b.contained_items:erase(#b.contained_items-1)end
 for _,entry in ipairs(saved)do b.contained_items:insert('#',entry)end
end
local ok,err=xpcall(function()
 for _,count in ipairs{#saved,6}do
  for _,length in ipairs{28,29,30,31,32,33,34,35,36,64}do
   restore()
   while #b.contained_items>count do b.contained_items:erase(#b.contained_items-1)end
   local name=('ABCDEFGHIJKLMNOPQRSTUVWXYZ'):rep(3):sub(1,length)
   plant.seed_singular=name;plant.seed_plural=name
   select_map(b);sheet.scroll_position_item=0
   g.precise_mouse_x=0;g.precise_mouse_y=4;g.mouse_x=0;g.mouse_y=0
   for i=1,5 do view:render(dfhack.getTickCount());script.sleep(1,'frames')end
   assert(sheet.open and sheet.active_id==b.id and df.global.pause_state and df.global.world.frame_counter==frame)
   local text,code=dfhack.run_command_silent('df3d','farm-contents-read',tostring(b.id));assert(code==0,text)
   local native=json.decode(text);assert(#native.rows==count and native.rows[1].name==name,'native caption source differs')
   local row=capture('farm-contents-caption-'..count..'-'..length)
   row.caption_length=length;row.total=count;row.rows=native.rows;row.native_caption=name
   row.rendered_caption=nil
   for _,line in ipairs(row.lines)do
    local first=line:find('ABCDEFGHIJKLMNOPQRSTUVWXYZ',1,true)
    if first then row.rendered_caption=line:sub(first,first+35):gsub('%s+$','');break end
   end
   assert(row.rendered_caption,'native caption not found in screen cells')
  end
 end
end,debug.traceback)
restore();select_map(b)
assert(plant.seed_singular==singular and plant.seed_plural==plural and #b.contained_items==#saved)
for index,entry in ipairs(saved)do assert(b.contained_items[index-1]==entry and entry.item.flags.whole==flags[entry.item.id],'caption fixture changed item/order')end
assert(ok,err)
records[#records+1]={name='farm-contents-caption-restored',restored=true,frame=frame,building_id=b.id}
