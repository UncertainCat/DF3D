-- Actual native picker input on the protected paused clone; never save.
local out,view,records=...
local gui=require('gui');local script=require('gui.script');local g=df.global.gps
local ui=df.global.game.main_interface.civzone
local function pixel(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//(g.screen_pixel_x//g.dimx);g.mouse_y=y//(g.screen_pixel_y//g.dimy)
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
end
local function mapclick(p)
 for y=0,g.dimy-1 do for x=0,g.dimx-1 do
  g.mouse_x=x;g.mouse_y=y;g.precise_mouse_x=x*(g.screen_pixel_x//g.dimx)+4;g.precise_mouse_y=y*(g.screen_pixel_y//g.dimy)+6
  local at=dfhack.gui.getMousePos(true)
  if at and at.x==p.x and at.y==p.y and at.z==p.z then pixel(g.precise_mouse_x,g.precise_mouse_y);return end
 end end
 error('owner fixture tile not visible')
end
-- Oracle-only widget observation. Runtime candidate filtering receives owned
-- semantic context and never traverses these native presentation objects.
local function unit_list(container,depth)
 assert(depth<8,'native widget tree too deep')
 if df.widget_unit_list:is_instance(container)then return df.reinterpret_cast(df.widget_unit_list,container)end
 if not df.widget_container:is_instance(container)then return end
 container=df.reinterpret_cast(df.widget_container,container)
 local _,address=df.sizeof(container.children)
 local begin=df.reinterpret_cast('uint64_t',address).value
 local finish=df.reinterpret_cast('uint64_t',address+8).value
 assert(finish>=begin and (finish-begin)%16==0 and finish-begin<=65536,'invalid native child vector')
 for at=begin,finish-1,16 do
  local ptr=df.reinterpret_cast('uint64_t',at).value
  if ptr~=0 then
   local found=unit_list(df.reinterpret_cast(df.widget,ptr),depth+1)
   if found then return found end
  end
 end
end
-- Include active rows outside the scroll viewport; visibility bit2 is clipping.
local function widget_rows(container,rows,depth,parent_visible)
 if depth>5 or #rows>=2000 then return end
 local row={depth=depth,name=container.name,search=container.search_string,flags=container.flag.whole,
  x=container.rect.x1,y=container.rect.y1,type=tostring(container._type),visible=parent_visible~=false and (container.flag.whole&1)==1}
 if df.widget_unit_name:is_instance(container)then row.unit_id=df.reinterpret_cast(df.widget_unit_name,container).u.id end
 if df.widget_text:is_instance(container)then row.text=dfhack.df2utf(df.reinterpret_cast(df.widget_text,container).str)end
 rows[#rows+1]=row
 if not df.widget_container:is_instance(container)then return end
 local _,address=df.sizeof(df.reinterpret_cast(df.widget_container,container).children)
 local begin=df.reinterpret_cast('uint64_t',address).value
 local finish=df.reinterpret_cast('uint64_t',address+8).value
 assert(finish>=begin and (finish-begin)%16==0 and finish-begin<=65536)
 for at=begin,finish-1,16 do
  local ptr=df.reinterpret_cast('uint64_t',at).value
  if ptr~=0 then widget_rows(df.reinterpret_cast(df.widget,ptr),rows,depth+1,row.visible)end
 end
end
local function capture(name)
 g.mouse_x=0;g.mouse_y=0
 for i=1,3 do view:render(dfhack.getTickCount());script.sleep(1,'frames')end
 if name:find('picker') or name:find('candidate') then
  local list=assert(unit_list(df.global.game.main_interface.unit_selector,0),'native unit list missing')
  local ids={}
  for _,entry in ipairs(list.entry_list)do if entry.t==0 and entry.u then ids[#ids+1]=entry.u.id end end
  local rows={};widget_rows(list,rows,0);assert(#rows<2000,'widget observation truncated')
  local displayed={};for _,row in ipairs(rows)do if row.unit_id and row.visible then displayed[#displayed+1]=row.unit_id end end
  local _,list_address=df.sizeof(list)
  local sorting={}
  for _,entry in ipairs(list.sorting_by)do sorting[#sorting+1]=entry.ident end
  local callbacks={}
  for _,field in ipairs{'sorting_by','always_sorting_by','partitions'}do
   local _,address=df.sizeof(list[field])
   local begin=df.reinterpret_cast('uint64_t',address).value
   local finish=df.reinterpret_cast('uint64_t',address+8).value
   local stride=field=='sorting_by' and 96 or 64
   assert(finish>=begin and (finish-begin)%stride==0 and finish-begin<=65536)
   local entries={}
   for at=begin,finish-1,stride do
    local context=df.reinterpret_cast('uint64_t',at+56).value
    if context~=0 then
     local vtable=df.reinterpret_cast('uint64_t',context).value
     entries[#entries+1]={invoke=df.reinterpret_cast('uint64_t',vtable+16).value,zone_type=field=='partitions' and df.reinterpret_cast('int32_t',context+8).value or nil}
    end
   end
   callbacks[field]={offset=address-list_address,entries=entries}
  end
  records[#records+1]={name=name..'-sort-metadata',sorting=sorting,callbacks=callbacks}
  local guards={}
  local function guard(value)
   local size,address=df.sizeof(value);local copy=df.new('uint8_t',size)
   dfhack.internal.memmove(copy,address,size);guards[#guards+1]={copy=copy,address=address,size=size}
  end
  guard(df.global.game.main_interface)
  if name=='tomb-picker' then
   for _,block in ipairs(df.global.world.map.map_blocks)do guard(block.path_cost);guard(block.path_tag)end
  end
  local text,code=dfhack.run_command_silent('df3d','zone-owner-candidates-read',tostring(assert(ui.cur_bld).id));assert(code==0,text)
  local order_text,order_code=dfhack.run_command_silent('df3d','zone-owner-order-read',tostring(ui.cur_bld.id));assert(order_code==0,order_text)
  local order_facts=require('json').decode(order_text)
  records[#records+1]={name=name..'-order-facts',facts=order_facts}
  for _,v in ipairs(guards)do assert(dfhack.internal.memcmp(v.copy,v.address,v.size)==0,'candidate query changed native UI/search scratch');df.delete(v.copy)end
  local eligible=require('json').decode(text)
  records[#records+1]={name=name..'-candidates',source_ids=ids,displayed_ids=displayed,eligible_ids=eligible,query=list.filter_str,unchanged_guards=#guards}
  if list.filter_str=='' then
   local sorted={};for i,facts in ipairs(order_facts)do sorted[#sorted+1]={id=facts[1],room=facts[2],priority=facts[3],category=facts[4],status=facts[5],ordinal=i}end
   table.sort(sorted,function(a,b)
    if a.room~=b.room then return a.room>b.room end
    if a.priority~=b.priority then return a.priority>b.priority end
    if a.category~=b.category then return a.category<b.category end
    if a.status~=b.status then return a.status<b.status end
    return a.ordinal<b.ordinal
   end)
   assert(#sorted==#displayed,'native default order count differs')
   for i,row in ipairs(sorted)do assert(row.id==displayed[i],'native default order differs at '..i)end
   records[#records+1]={name=name..'-default-order-parity',count=#sorted,exact=true}
   local expected={};for _,id in ipairs(eligible)do expected[id]=true end
   assert(#displayed==#eligible,'native displayed candidate count differs: '..#displayed..' / '..#eligible)
   for _,id in ipairs(displayed)do assert(expected[id],'native displayed candidate missing');expected[id]=nil end
  end
 end
 local f=assert(io.open(out..'/shot.tmp','w'));f:write(name);f:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local limit=dfhack.getTickCount()+30000
 while not io.open(out..'/ack-'..name,'r')do assert(dfhack.getTickCount()<limit,'capture timed out');script.sleep(1,'frames')end
end
local function search(text)
 pixel(500,730)
 for byte in text:gmatch('.')do
  df.global.enabler.last_text_input[0]=byte:byte();df.global.enabler.last_text_input[1]=0
  gui.simulateInput(view,string.format('STRING_A%03d',byte:byte()))
  view:render(dfhack.getTickCount());script.sleep(2,'frames')
 end
end
local function count_owned(unit,id)
 local n=0;for _,b in ipairs(unit.owned_buildings)do if b.id==id then n=n+1 end end;return n
end
local base=assert(df.global.world.buildings.other.ANY_ZONE[0])
local function snapshot(name)
 local row={name=name,zones={},units={}}
 for _,z in ipairs(df.global.world.buildings.other.ANY_ZONE)do
  row.zones[#row.zones+1]={id=z.id,type=df.civzone_type[z.type],owner=z.assigned_unit_id,settings=z.zone_settings.whole.i1}
 end
 for _,u in ipairs(df.global.world.units.all)do
  if #u.owned_buildings>0 then
   local owned={};for _,b in ipairs(u.owned_buildings)do owned[#owned+1]=b.id end
   row.units[#row.units+1]={id=u.id,spouse=u.relationship_ids.Spouse,owned=owned}
  end
 end
 records[#records+1]=row
end
local p={x=base.centerx,y=base.centery,z=base.z}
df.global.game.main_interface.bottom_mode_selected=-1;gui.simulateInput(view,'D_CIVZONE')
dfhack.gui.revealInDwarfmodeMap(p,true);view:render(dfhack.getTickCount())
pixel(208,502);mapclick(p);mapclick(p)
local zone=assert(ui.cur_bld);assert(zone.type==df.civzone_type.Tomb)
pixel(304,114)
records[#records+1]={name='new-tomb',id=zone.id,owner=zone.assigned_unit_id,settings=zone.zone_settings.whole.i1}
pixel(336,154);capture('tomb-picker')
snapshot('before-assignment')
pixel(520,106)
assert(zone.assigned_unit_id>=0 and zone.zone_settings.whole.i1==3,'native tomb assignment failed')
local owner=zone.assigned_unit_id
snapshot('assigned');capture('tomb-assigned')
pixel(336,154);capture('tomb-picker-assigned');pixel(520,106)
assert(zone.assigned_unit_id>=0 and zone.assigned_unit_id~=owner,'current owner was not excluded')
snapshot('replacement-owner')
-- Tomb context skips the native Remove assignment entry; record its tail.
pixel(336,154)
for i=1,250 do pixel(944,678)end
capture('tomb-picker-bottom')

gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
pixel(208,502);mapclick(p);mapclick(p)
local second=assert(ui.cur_bld);assert(second~=zone and second.type==df.civzone_type.Tomb)
pixel(304,114);pixel(336,154);pixel(520,106)
assert(second.assigned_unit_id==owner,'native second tomb assignment failed')
-- The first tomb currently belongs to the mayor. Select her on the second
-- tomb to exercise removal of her existing tomb, regardless of other rooms.
pixel(336,154);search('mayor')
view:render(dfhack.getTickCount());capture('tomb-transfer-candidate');pixel(520,106)
snapshot('transfer-result')
assert(second.assigned_unit_id>=0 and zone.assigned_unit_id==-1,'native tomb transfer failed')
snapshot('transferred');capture('tomb-transferred')
local first_unit=assert(df.unit.find(owner));local spouse=assert(df.unit.find(second.assigned_unit_id))
local old_first,old_spouse=first_unit.relationship_ids.Spouse,spouse.relationship_ids.Spouse
local old_economy=df.global.plotinfo.economy_active
first_unit.relationship_ids.Spouse=spouse.id;spouse.relationship_ids.Spouse=first_unit.id
local ok,why=pcall(function()
 pixel(55,320);mapclick(p);mapclick(p)
 local bedroom=assert(ui.cur_bld);assert(bedroom.type==df.civzone_type.Bedroom)
 pixel(304,114);pixel(336,154);capture('bedroom-picker')
 records[#records+1]={name='bedroom-created',id=bedroom.id,fixture_owner=owner,fixture_spouse=spouse.id}
 search('king');capture('bedroom-candidate');pixel(520,142)
 assert(bedroom.assigned_unit_id==owner,'native bedroom assignment failed')
 assert(count_owned(first_unit,bedroom.id)==1 and count_owned(spouse,bedroom.id)==1,'native spouse membership failed')
 snapshot('bedroom-assigned');capture('bedroom-assigned')
 pixel(336,154);capture('bedroom-picker-assigned');pixel(520,106)
 assert(bedroom.assigned_unit_id==-1,'native bedroom clear failed')
 assert(count_owned(first_unit,bedroom.id)==0 and count_owned(spouse,bedroom.id)==0,'native spouse clear failed')
 snapshot('bedroom-cleared');capture('bedroom-cleared')
 df.global.plotinfo.economy_active=true
 pixel(336,154);capture('bedroom-economy-picker')
end)
first_unit.relationship_ids.Spouse=old_first;spouse.relationship_ids.Spouse=old_spouse
df.global.plotinfo.economy_active=old_economy
assert(ok,why)
