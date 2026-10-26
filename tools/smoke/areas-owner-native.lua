-- Actual native picker input on the protected paused clone; never save.
local out,view,records=...
local gui=require('gui');local script=require('gui.script');local g=df.global.gps
local ui=df.global.game.main_interface.civzone
local last_search_input=""
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
  x=container.rect.x1,y=container.rect.y1,x2=container.rect.x2,y2=container.rect.y2,type=tostring(container._type),visible=parent_visible~=false and (container.flag.whole&1)==1}
 local base=dfhack.internal.getImageBase()
 local _,object_address=df.sizeof(container)
 local vtable=df.reinterpret_cast('uint64_t',object_address).value
 row.render_rva=df.reinterpret_cast('uint64_t',vtable+24).value-base
 if df.widget_unit_name:is_instance(container)then
  local value=df.reinterpret_cast(df.widget_unit_name,container)
  row.unit_id=value.u.id;row.show_gender=value.show_gender;row.show_profession=value.show_profession;row.one_line_only=value.one_line_only
 end
 if df.widget_text:is_instance(container)then
  local value=df.reinterpret_cast(df.widget_text,container)
  row.text=dfhack.df2utf(value.str);row.fg=value.fg;row.bg=value.bg;row.bright=value.bright
 end
 local _,callbacks_address=df.sizeof(container.custom_render)
 local first=df.reinterpret_cast('uint64_t',callbacks_address).value
 local last=df.reinterpret_cast('uint64_t',callbacks_address+8).value
 assert(last>=first and (last-first)%64==0 and last-first<=65536,'invalid render callback vector')
 row.custom_render={}
 for at=first,last-1,64 do
  local context=df.reinterpret_cast('uint64_t',at+56).value
  if context~=0 then
   local table_address=df.reinterpret_cast('uint64_t',context).value
   local invoke=df.reinterpret_cast('uint64_t',table_address+16).value-base
   local callback={invoke=invoke}
   if invoke==0xf1c80 then
    local inner=df.reinterpret_cast('uint64_t',context+0x40).value
    if inner~=0 then
     local inner_table=df.reinterpret_cast('uint64_t',inner).value
     callback.inner_invoke=df.reinterpret_cast('uint64_t',inner_table+16).value-base
    end
   end
   row.custom_render[#row.custom_render+1]=callback
  end
 end
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
  if name=='tomb-picker' or name=='bedroom-picker' or name=='tomb-transfer-candidate' or name=='bedroom-candidate' or name:find('%-display%-') then records[#records+1]={name=name..'-row-widgets',rows=rows} end
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
  if name=='tomb-picker' or name=='bedroom-picker' or name=='tomb-transfer-candidate' or name=='bedroom-candidate' or name:find('%-display%-') then
   guard(df.global.gps)
   local samples={}
   for _,row in ipairs(rows)do
    if row.unit_id and row.visible and (row.flags&2)~=0 and row.y>=2 and row.y<g.dimy-5 then
     local text,code=dfhack.run_command_silent('df3d','zone-owner-text-read',tostring(row.unit_id),tostring(row.x2-row.x+1));assert(code==0,text)
     local status_text,status_code=dfhack.run_command_silent('df3d','zone-owner-status-read',tostring(ui.cur_bld.id),tostring(row.unit_id));assert(status_code==0,status_text)
     local status=require('json').decode(status_text)
     local lines={}
     for y=row.y-2,row.y do
      local bytes,colors={},{}
      for x=row.x,math.min(row.x2,g.dimx-1)do
       local tile=dfhack.screen.readTile(x,y);bytes[#bytes+1]=tile.ch;colors[#colors+1]={tile.fg,tile.bg,tile.bold}
      end
      lines[#lines+1]={bytes=bytes,colors=colors}
     end
     local native_text=require('json').decode(text)
     local width=row.x2-row.x+1
     local expected={native_text[4],native_text[5]}
     for x=1,width do assert(lines[1].bytes[x]==(status[2][x] or 0),'native room status mismatch: '..name..'/'..row.unit_id..'/'..x)end
     for line=1,2 do
      for x=1,width do assert(lines[line+1].bytes[x]==(expected[line][x] or 0),'native display reader mismatch: '..name..'/'..row.unit_id..'/'..line..'/'..x)end
     end
     local unit=assert(df.unit.find(row.unit_id))
     local skills={}
     if unit.status.current_soul then
      for _,skill in ipairs(unit.status.current_soul.skills)do
       if skill.rating>=15 then skills[#skills+1]={id=skill.id,rating=skill.rating}end
      end
     end
     samples[#samples+1]={unit_id=row.unit_id,x=row.x,y=row.y,x2=row.x2,text=native_text,status=status,lines=lines,exact=true,
      color_facts={race=unit.race,caste=unit.caste,profession=unit.profession,hist_figure_id=unit.hist_figure_id,
       flags1=unit.flags1.whole,flags2=unit.flags2.whole,flags3=unit.flags3.whole,
       override_tile=unit.uwss_display_tile,override_fg=unit.uwss_display_color_f,override_bg=unit.uwss_display_color_b,
       override_bright=unit.uwss_display_color_br,legendary_skills=skills,
       dfhack_profession_color=dfhack.units.getProfessionColor(unit)}}
    end
   end
   records[#records+1]={name=name..'-display-text',samples=samples}
  end
  local text,code=dfhack.run_command_silent('df3d','zone-owner-candidates-read',tostring(assert(ui.cur_bld).id));assert(code==0,text)
  local order_text,order_code=dfhack.run_command_silent('df3d','zone-owner-order-read',tostring(ui.cur_bld.id));assert(order_code==0,order_text)
  local order_facts=require('json').decode(order_text)
  records[#records+1]={name=name..'-order-facts',facts=order_facts}
  if name:find('%-filter%-') then
   local query_text,query_code=dfhack.run_command_silent('df3d','zone-owner-query-read',last_search_input);assert(query_code==0,query_text)
   local query_bytes=require('json').decode(query_text);local query=string.char(table.unpack(query_bytes))
   local expected={}
   for ordinal,facts in ipairs(order_facts)do
    local key=string.char(table.unpack(facts[7]))
    if key:find(query,1,true)then expected[#expected+1]={facts=facts,ordinal=ordinal}end
   end
   table.sort(expected,function(a,b)
    local x,y=a.facts,b.facts
    if x[2]~=y[2]then return x[2]>y[2]end
    if x[3]~=y[3]then return x[3]>y[3]end
    if x[4]~=y[4]then return x[4]<y[4]end
    if x[5]~=y[5]then return x[5]<y[5]end
    return a.ordinal<b.ordinal
   end)
   assert(#expected==#displayed,'native filtered count differs: '..name)
   for i,row in ipairs(expected)do assert(row.facts[1]==displayed[i],'native filtered order differs: '..name)end
   records[#records+1]={name=name..'-filter-parity',input=last_search_input,query=list.filter_str,key=query_bytes,ids=displayed,exact=true}
  end
  for _,v in ipairs(guards)do assert(dfhack.internal.memcmp(v.copy,v.address,v.size)==0,'candidate query changed native UI/search scratch');df.delete(v.copy)end
  local eligible=require('json').decode(text)
  records[#records+1]={name=name..'-candidates',source_ids=ids,displayed_ids=displayed,eligible_ids=eligible,query=list.filter_str,unchanged_guards=#guards}
  if name:find('%-sort%-') then
   assert(#sorting==1,'expected one active native header')
   local header=sorting[1]
   local function compare_bytes(a,b)
    for i=1,math.min(#a,#b)do if a[i]~=b[i]then return a[i]<b[i] and -1 or 1 end end
    return #a==#b and 0 or #a<#b and -1 or 1
   end
   local function matches(descending)
    local sorted={};for i,row in ipairs(order_facts)do sorted[#sorted+1]={row=row,ordinal=i}end
    table.sort(sorted,function(a,b)
     local x,y=a.row,b.row
     if x[2]~=y[2]then return x[2]>y[2]end
     if x[3]~=y[3]then return x[3]>y[3]end
     local cmp=0
     if header=='Name' then cmp=compare_bytes(x[7],y[7])
     elseif header=='Prof' then cmp=compare_bytes(x[8],y[8])
     elseif header=='Stress' then cmp=x[6]-y[6]
     elseif header=='Cat' then cmp=x[4]-y[4];if cmp==0 then cmp=x[5]-y[5]end
     else error('unexpected native sort header')end
     if cmp==0 then return a.ordinal<b.ordinal end
     return descending and cmp>0 or not descending and cmp<0
    end)
    if #sorted~=#displayed then return false end
    for i,row in ipairs(sorted)do if row.row[1]~=displayed[i]then return false end end
    return true
   end
   local ascending,descending=matches(false),matches(true)
   assert(ascending~=descending,'native header order differs or direction is ambiguous: '..name)
   records[#records+1]={name=name..'-header-order-parity',header=header,descending=descending,count=#displayed,exact=true}
  end
  if list.filter_str=='' and not name:find('%-sort%-') then
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
 last_search_input=text
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
 pixel(336,154)
 local before_clear=df.global.game.main_interface.unit_selector.flag.whole
 pixel(520,106)
 records[#records+1]={name='bedroom-clear-empty',before_flags=before_clear,after_flags=df.global.game.main_interface.unit_selector.flag.whole,owner=bedroom.assigned_unit_id}
 assert(bedroom.assigned_unit_id==-1,'empty clear assigned an owner')
 capture('bedroom-clear-empty')
 df.global.plotinfo.economy_active=true
 pixel(336,154);capture('bedroom-economy-picker')
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
 df.global.plotinfo.economy_active=old_economy
 pixel(336,154)
 for _,header in ipairs{{'cat-first',540},{'cat-second',540},{'name-first',472},{'name-second',472},
   {'prof-first',620},{'prof-second',620},{'stress-first',832},{'stress-second',832},
   {'name-return',472},{'cat-return',540}}do
  pixel(header[2],70);capture('bedroom-picker-sort-'..header[1])
 end
 for i,query in ipairs{'miner','MINER','mi','king','mayor',',',' ','5981','notfound','er','kubuk','unib','bedroom'}do
  gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());pixel(336,154)
  search(query);capture('bedroom-picker-filter-'..i)
 end
 local previous_nickname=first_unit.name.nickname
 local display_ok,display_error=pcall(function()
  first_unit.name.nickname=string.rep('OwnerDisplayName',4)
  gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());pixel(336,154)
  search('OwnerDisplayName');capture('bedroom-picker-display-long')
 end)
 first_unit.name.nickname=previous_nickname
 assert(display_ok,display_error)
 for _,sample in ipairs{{'office',208,285,df.civzone_type.Office},{'dining',55,356,df.civzone_type.DiningHall}}do
  gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
  pixel(sample[2],sample[3]);mapclick(p);mapclick(p)
  assert(ui.cur_bld.type==sample[4],'wrong owner room fixture')
  pixel(304,114);pixel(336,154);capture(sample[1]..'-picker-display-default')
  search('king');capture(sample[1]..'-picker-display-king')
  if sample[1]=='dining' then
   local owned_dining=ui.cur_bld
   pixel(520,142);assert(owned_dining.assigned_unit_id==owner,'native dining assignment failed')
   pixel(55,356);mapclick(p);mapclick(p)
   assert(ui.cur_bld~=owned_dining and ui.cur_bld.type==df.civzone_type.DiningHall)
   pixel(304,114);pixel(336,154);search('king');capture('dining-picker-display-owned')
  end
 end
 -- Controlled native color precedence. These semantic fixture fields are
 -- restored even if capture fails; no native drawing function is called here.
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
 pixel(208,502);mapclick(p);mapclick(p)
 assert(ui.cur_bld.type==df.civzone_type.Tomb)
 pixel(304,114);pixel(336,154)
 local old_color={first_unit.uwss_display_tile,first_unit.uwss_display_color_f,
  first_unit.uwss_display_color_b,first_unit.uwss_display_color_br,first_unit.flags3.ghostly}
 local color_ok,color_error=pcall(function()
  local function color_case(name,fg,bg,bright)
   gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());pixel(336,154)
   search(first_unit.name.first_name);capture('tomb-picker-display-color-'..name)
   local sample
   for _,record in ipairs(records)do
    if record.name=='tomb-picker-display-color-'..name..'-display-text' then
     for _,candidate in ipairs(record.samples)do if candidate.unit_id==owner then sample=candidate end end
    end
   end
   assert(sample and sample.unit_id==owner,'color fixture candidate missing')
   local observed=false
   for i,ch in ipairs(sample.lines[2].bytes)do
    if ch~=0 then
     local color=sample.lines[2].colors[i]
     assert(color[1]==fg and color[2]==bg and color[3]==bright,'native color precedence differs: '..name)
     observed=true
    end
   end
   assert(observed,'color fixture has no glyphs')
  end
  first_unit.uwss_display_tile=88;first_unit.uwss_display_color_f=1
  first_unit.uwss_display_color_b=2;first_unit.uwss_display_color_br=1
  color_case('override',1,2,true)
  first_unit.flags3.ghostly=true
  color_case('override-before-ghost',1,2,true)
  first_unit.uwss_display_tile=0
  color_case('ghost',7,0,true)
 end)
 first_unit.uwss_display_tile=old_color[1];first_unit.uwss_display_color_f=old_color[2]
 first_unit.uwss_display_color_b=old_color[3];first_unit.uwss_display_color_br=old_color[4]
 first_unit.flags3.ghostly=old_color[5]
 assert(color_ok,color_error)
end)
first_unit.relationship_ids.Spouse=old_first;spouse.relationship_ids.Spouse=old_spouse
df.global.plotinfo.economy_active=old_economy
assert(ok,why)
