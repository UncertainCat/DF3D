-- Actual native picker input on the protected paused clone; never save.
local out,view,records=...
local gui=require('gui');local script=require('gui.script');local g=df.global.gps
local ui=df.global.game.main_interface.civzone
local last_search_input=""
local dumped_portraits={}
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
local function find_widget(container,kind,depth)
 assert(depth<8,'native widget tree too deep')
 if kind:is_instance(container)then return df.reinterpret_cast(kind,container)end
 if not df.widget_container:is_instance(container)then return end
 container=df.reinterpret_cast(df.widget_container,container)
 local _,address=df.sizeof(container.children)
 local begin=df.reinterpret_cast('uint64_t',address).value
 local finish=df.reinterpret_cast('uint64_t',address+8).value
 assert(finish>=begin and (finish-begin)%16==0 and finish-begin<=65536,'invalid native child vector')
 for at=begin,finish-1,16 do
  local ptr=df.reinterpret_cast('uint64_t',at).value
  if ptr~=0 then
   local found=find_widget(df.reinterpret_cast(df.widget,ptr),kind,depth+1)
   if found then return found end
  end
 end
end
local function unit_list(container,depth)return find_widget(container,df.widget_unit_list,depth)end
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
  records[#records+1]={name=name..'-row-cursor',cursor=list.cursor_idx,mouse_x=g.mouse_x,mouse_y=g.mouse_y}
  if name=='tomb-picker' or name:find('%-portrait$') then
   local cells={}
   for y=7,12 do for x=47,51 do
    local idx=x*g.dimy+y;local cell={x=x,y=y,tile=dfhack.screen.readTile(x,y).tile}
    for _,field in ipairs{'screentexpos_anchored','screentexpos_anchored_x','screentexpos_anchored_y','screentexpos_top_anchored','screentexpos_top_anchored_x','screentexpos_top_anchored_y'}do cell[field]=g[field][idx]end
    local texture=cell.screentexpos_anchored
    if texture and texture>0 and not dumped_portraits[texture] then
     local text,code=dfhack.run_command_silent('df3d','appearance','texture',tostring(texture),out..'/owner-body-'..texture)
     assert(code==0 and text:find('DF3D_TEXTURE_DUMP_PASS',1,true),text)
     dumped_portraits[texture]=true
    end
    cells[#cells+1]=cell
   end end
   records[#records+1]={name=name..'-portrait-anchors',cells=cells}
  end
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
     local source_text,source_code=dfhack.run_command_silent('df3d','zone-owner-color-sources-read',tostring(row.unit_id));assert(source_code==0,source_text)
     local sources=require('json').decode(source_text)
     local effective_profession=sources.identity_profession>=0 and sources.identity_profession or unit.profession
     local color_text,color_code=dfhack.run_command_silent('df3d','zone-owner-profession-color-read',tostring(row.unit_id),tostring(effective_profession));assert(color_code==0,color_text)
     sources.profession_color=require('json').decode(color_text)
     local name_text,name_code=dfhack.run_command_silent('df3d','zone-owner-name-color-read',tostring(row.unit_id));assert(name_code==0,name_text)
     sources.name_color=require('json').decode(name_text)
     local function same_color(a,b)return a[1]==b[1] and a[2]==b[2] and a[3]==(b[3]~=0)end
     for line=2,3 do for x,ch in ipairs(lines[line].bytes)do if ch~=0 then
      assert(same_color(lines[line].colors[x],sources.name_color.color) or
       (sources.name_color.effect~=0 and same_color(lines[line].colors[x],sources.name_color.alternate)),
       'native name color differs: '..name..'/'..row.unit_id..'/'..line..'/'..x)
     end end end
     local hf=df.historical_figure.find(unit.hist_figure_id)
     local function strength(links,kind)
      if links then for _,link in ipairs(links)do if link:getType()==kind then return link.link_strength end end end
      return 0
     end
     assert(sources.slave_strength==strength(hf and hf.entity_links,df.histfig_entity_link_type.SLAVE),'native slave strength differs')
     assert(sources.prisoner_strength==strength(hf and hf.entity_links,df.histfig_entity_link_type.PRISONER),'native prisoner strength differs')
     assert(sources.imprisoner_strength==strength(hf and hf.histfig_links,df.histfig_hf_link_type.IMPRISONER),'native imprisoner strength differs')
     local deity_hf=df.historical_figure.find(sources.deity_histfig_id)
     assert(sources.deity==(deity_hf~=nil and deity_hf.flags.deity),'native deity source differs')
     if sources.identity_id>=0 then
      local identity=assert(df.identity.find(sources.identity_id),'native identity missing')
      assert(identity.profession==sources.identity_profession and identity.impersonated_hf==sources.identity_impersonated_histfig,'identity facts differ')
     end
     if sources.position_id>=0 then
      local entity=assert(df.historical_entity.find(sources.entity_id),'native position entity missing')
      local position,assignment
      for _,value in ipairs(entity.positions.own)do if value.id==sources.position_id then position=value end end
      for _,value in ipairs(entity.positions.assignments)do if value.id==sources.assignment_id then assignment=value end end
      assert(position and assignment and assignment.position_id==position.id,'native position source differs')
      for i=0,2 do assert(position.color[i]==sources.position_color[i+1],'native position color differs')end
     end
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
       dfhack_profession_color=dfhack.units.getProfessionColor(unit),native_sources=sources}}
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
  if ui.cur_bld.assigned_unit_id==-1 then
   local fresh_text,fresh_code=dfhack.run_command_silent('df3d','zone-new-owner-candidates-read',tostring(ui.cur_bld.type))
   assert(fresh_code==0,fresh_text)
   assert(fresh_text==text,'new-zone semantic context differs from unassigned native zone')
   records[#records+1]={name=name..'-new-owner-context',zone_type=ui.cur_bld.type,exact=true,count=#require('json').decode(fresh_text)}
  end
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
-- Native list navigation uses STANDARDSCROLL, not map CURSOR bindings.
for _,probe in ipairs{{'down','STANDARDSCROLL_DOWN',1},{'up','STANDARDSCROLL_UP',0},{'pagedown','STANDARDSCROLL_PAGEDOWN',16},{'pageup','STANDARDSCROLL_PAGEUP',0}}do
 gui.simulateInput(view,probe[2]);capture('tomb-picker-row-'..probe[1])
 local list=assert(unit_list(df.global.game.main_interface.unit_selector,0))
 records[#records+1]={name='owner-navigation-'..probe[1],cursor=list.cursor_idx,expected=probe[3]}
 assert(list.cursor_idx==probe[3],'native owner navigation changed: '..probe[1])
end
-- Oracle-only row scroll state: no product reads native widgets.
do
 local root=df.global.game.main_interface.unit_selector
 local list=assert(unit_list(root,0))
 local scroll=assert(find_widget(list,df.widget_scroll_rows,0))
 local function point(x,y)
  g.mouse_x=x;g.mouse_y=y;g.precise_mouse_x=x*(g.screen_pixel_x//g.dimx)+4;g.precise_mouse_y=y*(g.screen_pixel_y//g.dimy)+6
  df.global.enabler.tracking_on=1
 end
 local function observe(label)
  view:render(dfhack.getTickCount());script.sleep(1,'frames')
  local rows={};widget_rows(list,rows,0)
  local visible={};local count=0
  for _,row in ipairs(rows)do if row.unit_id and row.visible then
   count=count+1
   if (row.flags&2)~=0 then visible[#visible+1]={id=row.unit_id,y=row.y,y2=row.y2}end
  end end
  local bar={};for _,field in ipairs{'sel','sel_min','sel_max','page_size','print_sy','print_ey','scroller_sy','scroller_ey'}do bar[field]=scroll.scrollbar[field]end
  local cells={}
  for y=7,56 do for x=117,118 do cells[#cells+1]={x=x,y=y,tile=dfhack.screen.readTile(x,y).tile}end end
  records[#records+1]={name='owner-scroll',label=label,cells=cells,scroll=scroll.scroll,num_visible=scroll.num_visible,
   cursor=list.cursor_idx,bar=bar,count=count,visible=visible,rect={scroll.rect.x1,scroll.rect.y1,scroll.rect.x2,scroll.rect.y2}}
 end
 local function input(label,key,x,y)
  point(x or 60,y or 20);gui.simulateInput(view,key);observe(label)
 end
 observe('initial')
 input('context-down','CONTEXT_SCROLL_DOWN')
 input('context-up','CONTEXT_SCROLL_UP')
 input('context-page-down','CONTEXT_SCROLL_PAGEDOWN')
 input('context-page-up','CONTEXT_SCROLL_PAGEUP')
 input('outside-context-down','CONTEXT_SCROLL_DOWN',0,0)
 input('arrow-down','_MOUSE_L',118,56)
 input('arrow-up','_MOUSE_L',118,7)
 input('track-down','_MOUSE_L',118,40)
 input('track-up','_MOUSE_L',118,8)
 for i=1,20 do input('page-down-'..i,'STANDARDSCROLL_PAGEDOWN')end
 input('tail-down','STANDARDSCROLL_DOWN')
 capture('tomb-picker-scroll-tail')
 input('tail-page-up','STANDARDSCROLL_PAGEUP')
 for i=1,20 do gui.simulateInput(view,'STANDARDSCROLL_PAGEUP');view:render(dfhack.getTickCount())end
 observe('restored-top')
 local old_lift=df.global.enabler.mouse_lbut_lift
 for _,destination in ipairs{7,8,9,20,40,54,55,56,57}do
  -- Isolate each drag's starting state; this diagnostic widget write never
  -- participates in runtime behavior or establishes keyboard reset semantics.
  scroll.scroll=0;scroll.scrolling=false;list.cursor_idx=0
  point(60,20);view:render(dfhack.getTickCount());script.sleep(2,'frames')
  point(118,10);df.global.enabler.mouse_lbut_lift=0
  gui.simulateInput(view,{'_MOUSE_L','_MOUSE_L_DOWN'})
  point(118,destination);gui.simulateInput(view,{'_MOUSE_L_DOWN'})
  observe('drag-'..destination)
  df.global.enabler.mouse_lbut_lift=1;gui.simulateInput(view,{})
 end
 df.global.enabler.mouse_lbut_lift=old_lift
 scroll.scroll=0;scroll.scrolling=false;list.cursor_idx=0
 point(60,20);view:render(dfhack.getTickCount());script.sleep(2,'frames')
 observe('restored-after-drag')
 assert(list.cursor_idx==0 and scroll.scroll==0,'owner scroll probe did not restore top')
end
-- Observe the owner textbox itself, not a different selector's input policy.
local selector=df.global.game.main_interface.unit_selector
local filter=assert(dfhack.gui.getWidget(assert(dfhack.gui.getWidget(selector,'Unit selector')),'Filter box'))
filter=df.reinterpret_cast(df.widget_textbox,filter)
local function input_state(label)
 view:render(dfhack.getTickCount())
 local list=assert(unit_list(selector,0));local bytes={}
 for i=1,#filter.str do bytes[#bytes+1]=filter.str:byte(i)end
 records[#records+1]={name='owner-input-'..label,active=selector.flag.VISIBILITY_ACTIVE,
  focused=df.global.gview.cur_textbox==filter,listening=df.global.enabler.listening_to_text,
  bytes=bytes,query_display=dfhack.df2utf(list.filter_str),cursor=list.cursor_idx,maxlen=filter.maxlen,owner=zone.assigned_unit_id}
 assert(selector.flag.VISIBILITY_ACTIVE and zone.assigned_unit_id==-1,'textbox input changed assignment or closed picker')
 assert(filter.maxlen==33 and list.cursor_idx==0,'textbox input changed limit or cursor')
 local lengths={limit=33,backspace=32,clear=0,nonascii=2,['partial-utf8']=1}
 if lengths[label]then assert(#bytes==lengths[label],'textbox byte count changed: '..label)end
 if label=='nonascii' or label=='partial-utf8' then
  assert(bytes[1]==195 and (label~='nonascii' or bytes[2]==169),'textbox UTF-8 bytes changed')
 end
 local focused=label~='initial' and label~='focused-enter' and label~='blank-click'
 assert((df.global.gview.cur_textbox==filter)==focused,'textbox focus changed: '..label)
end
local function window_input(label,action,observe)
 local f=assert(io.open(out..'/owner-input-request.tmp','w'));f:write(action);f:close()
 assert(os.rename(out..'/owner-input-request.tmp',out..'/owner-input-request'))
 local limit=dfhack.getTickCount()+30000
 while true do
  local ack=io.open(out..'/owner-input-ack','r');if ack then ack:close();break end
  assert(dfhack.getTickCount()<limit,'window input timeout');script.sleep(1,'frames')
 end
 assert(os.remove(out..'/owner-input-ack'));script.sleep(5,'frames');if observe~=false then input_state(label)end
end
local resize_marker=io.open(out..'/picker-resize','r')
if resize_marker then
 resize_marker:close()
 for _,size in ipairs{'small','wide','default'}do
  window_input('resize','name-resize-'..size,false)
  view:render(dfhack.getTickCount());script.sleep(2,'frames')
  local list=assert(unit_list(selector,0));local scroll=assert(find_widget(list,df.widget_scroll_rows,0))
  local rows={};widget_rows(selector,rows,0)
  records[#records+1]={name='owner-resize',size=size,dimx=g.dimx,dimy=g.dimy,
   pixel_width=g.screen_pixel_x,pixel_height=g.screen_pixel_y,rows=rows,
   num_visible=scroll.num_visible,scroll=scroll.scroll,cursor=list.cursor_idx,
   scroll_rect={scroll.rect.x1,scroll.rect.y1,scroll.rect.x2,scroll.rect.y2},
   filter_rect={filter.rect.x1,filter.rect.y1,filter.rect.x2,filter.rect.y2}}
  capture('owner-resize-'..size)
  assert(zone.assigned_unit_id==-1,'resize changed owner')
 end
 return
end
-- Hidden-desktop SDL polls reset GPS mouse coordinates. Retain pointer/focus
-- during the native input/render loop. Recenter supplies a positive control.
-- Sample rendered glyphs immediately; asynchronous screenshots lose this pointer.
local previous_tracking=df.global.enabler.tracking_on
local previous_focus=df.global.enabler.mouse_focus
local function help_cells()
 local cells={}
 for y=0,17 do for x=g.dimx-24,g.dimx-1 do
  local pen=dfhack.screen.readTile(x,y)
  if pen.ch>=33 and pen.ch<=255 then cells[#cells+1]={x=x,y=y,ch=pen.ch,fg=pen.fg,bg=pen.bg,bold=pen.bold}end
 end end
 return cells
end
for _,probe in ipairs{{'recenter',796,106},{'filter',500,730},{'filter-icon',688,730},{'row-third',500,172},{'portrait-third',394,172},{'header-name',464,70},{'blank',800,700}}do
 local started=dfhack.getTickCount();local first_tooltip_ms
 local function move()
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
  g.precise_mouse_x=probe[2];g.precise_mouse_y=probe[3];g.mouse_x=probe[2]//8;g.mouse_y=(probe[3]-4)//12
  gui.simulateInput(view,{});filter:logic()
  if filter.displaying_tooltip and not first_tooltip_ms then first_tooltip_ms=dfhack.getTickCount()-started end
 end
 local deadline=dfhack.getTickCount()+900
 repeat move();view:render(dfhack.getTickCount());script.sleep(1,'frames') until dfhack.getTickCount()>=deadline
 move();view:render(dfhack.getTickCount())
 local list=assert(unit_list(selector,0));local main=df.global.game.main_interface
 local text={}
 for y=0,g.dimy-1 do
  local line='';for x=0,g.dimx-1 do local t=dfhack.screen.readTile(x,y).ch;line=line..string.char(t>=32 and t<=255 and t or 32)end
  text[#text+1]=dfhack.df2utf(line)
 end
 local frame_cells={}
 if probe[1]=='recenter' then
  for y=0,17 do for x=g.dimx-25,g.dimx-1 do frame_cells[#frame_cells+1]={x=x,y=y,tile=dfhack.screen.readTile(x,y).tile}end end
 end
 records[#records+1]={name='owner-hover-'..probe[1],cursor=list.cursor_idx,mouse={g.precise_mouse_x,g.precise_mouse_y},hover=main.current_hover,enabled=main.hover_instructions_on,text=text,cells=help_cells(),frame_cells=frame_cells,filter_tooltip=filter.displaying_tooltip,first_tooltip_ms=first_tooltip_ms}
 assert(list.cursor_idx==0,'native hover changed owner selection: '..probe[1])
 if probe[1]=='recenter' then
  assert(main.hover_instructions_on and main.current_hover==234,'native recenter hover positive control failed')
  assert(text[1]:find('Leave this menu and',1,true) and text[5]:find('Hotkey: Ctrl+c',1,true),'native recenter help changed')
 end
end
df.global.enabler.tracking_on=previous_tracking;df.global.enabler.mouse_focus=previous_focus
gui.simulateInput(view,'STANDARDSCROLL_PAGEUP');view:render(dfhack.getTickCount())
-- Controlled native picker setup, then actual click/key activation. Restore the
-- selected zone and map only between probes; no recenter output is synthesized.
for _,method in ipairs{'click','control-c','focused-control-c'}do
 local rows={};widget_rows(assert(unit_list(selector,0)),rows,0)
 local target;for _,row in ipairs(rows)do if row.unit_id and row.visible then target=df.unit.find(row.unit_id);break end end
 assert(target,'no recenter candidate')
 local before={df.global.window_x,df.global.window_y,df.global.window_z}
 if method=='focused-control-c' then window_input('focus-recenter','control-f',false);window_input('clear-recenter','clear',false)end
 if method=='click' then pixel(796,106)else window_input('recenter','control-c',false)end
 script.sleep(3,'frames');view:render(dfhack.getTickCount())
 records[#records+1]={name='owner-recenter-'..method,unit_id=target.id,position={target.pos.x,target.pos.y,target.pos.z},
  before=before,after={df.global.window_x,df.global.window_y,df.global.window_z},selector_active=selector.flag.VISIBILITY_ACTIVE,
  bottom_mode=df.global.game.main_interface.bottom_mode_selected,owner=zone.assigned_unit_id,focused=df.global.gview.cur_textbox~=nil,query=dfhack.df2utf(assert(unit_list(selector,0)).filter_str)}
 assert(zone.assigned_unit_id==-1,'recenter assigned owner')
 if method=='focused-control-c' then
  assert(selector.flag.VISIBILITY_ACTIVE and df.global.game.main_interface.bottom_mode_selected==3 and df.global.gview.cur_textbox~=nil,'focused recenter escaped textbox')
  assert(df.global.window_x==before[1] and df.global.window_y==before[2] and df.global.window_z==before[3],'focused recenter moved map')
 else
  assert(not selector.flag.VISIBILITY_ACTIVE and df.global.game.main_interface.bottom_mode_selected==-1,'recenter did not leave Zones')
  assert(df.global.window_z==target.pos.z,'recenter elevation differs')
 end
 capture('owner-recenter-'..method)
 selector.flag.VISIBILITY_ACTIVE=false;df.global.game.main_interface.bottom_mode_selected=3;ui.cur_bld=zone
 dfhack.gui.revealInDwarfmodeMap(p,true);view:render(dfhack.getTickCount());pixel(336,154)
end
-- Read the same open widget after a controlled semantic name change.
local name_rows={};widget_rows(assert(unit_list(selector,0)),name_rows,0)
local named;for _,row in ipairs(name_rows)do if row.unit_id and row.visible then named=assert(df.unit.find(row.unit_id));break end end
assert(named,'no open-row name fixture')
local old_name=named.name.first_name
local function name_text()
 view:render(dfhack.getTickCount())
 local lines={}
 for y=6,14 do
  local line='';for x=52,96 do local ch=dfhack.screen.readTile(x,y).ch;line=line..string.char(ch>=32 and ch<=255 and ch or 32)end
  lines[#lines+1]=dfhack.df2utf(line)
 end
 return lines
end
local before_name=name_text()
named.name.first_name='OwnerRefreshProbe'
local rename_ok,rename_error=pcall(function()
 script.sleep(3,'frames')
 local after_name=name_text()
 records[#records+1]={name='owner-open-name-refresh',id=named.id,before=before_name,after=after_name,selector_active=selector.flag.VISIBILITY_ACTIVE,cursor=assert(unit_list(selector,0)).cursor_idx}
 assert(table.concat(after_name,' '):find('OwnerRefreshProbe',1,true),'open owner row retained stale name')
 assert(selector.flag.VISIBILITY_ACTIVE and assert(unit_list(selector,0)).cursor_idx==0,'open name refresh changed navigation')
 capture('owner-open-name-refresh')
end)
named.name.first_name=old_name;assert(rename_ok,rename_error)
local function visible_owner_ids()
 view:render(dfhack.getTickCount())
 local widgets={};widget_rows(assert(unit_list(selector,0)),widgets,0)
 local ids={};for _,row in ipairs(widgets)do if row.unit_id and row.visible then ids[#ids+1]=row.unit_id end end
 return ids
end
local function reopen_owner()
 selector.flag.VISIBILITY_ACTIVE=false;df.global.game.main_interface.bottom_mode_selected=3;ui.cur_bld=zone
 view:render(dfhack.getTickCount());pixel(336,154)
end
pixel(464,70);script.sleep(3,'frames')
local sorted_before=visible_owner_ids();local sorted_unit=assert(df.unit.find(sorted_before[7]))
local sorted_name=sorted_unit.name.first_name
sorted_unit.name.first_name='zzzzOwnerRefreshOrder'
local order_ok,order_error=pcall(function()
 script.sleep(3,'frames')
 local retained=visible_owner_ids()
 capture('owner-open-name-order')
 reopen_owner();pixel(464,70);script.sleep(3,'frames')
 records[#records+1]={name='owner-open-name-order',id=sorted_unit.id,before=sorted_before,after=retained,reopened=visible_owner_ids()}
 capture('owner-reopened-name-order')
end)
sorted_unit.name.first_name=sorted_name;assert(order_ok,order_error)
named.name.first_name='OwnerRefreshFilter'
local filter_ok,filter_error=pcall(function()
 reopen_owner();search('OwnerRefreshFilter');script.sleep(3,'frames')
 local before=visible_owner_ids()
 named.name.first_name='OwnerRefreshChanged'
 script.sleep(3,'frames')
 records[#records+1]={name='owner-open-filter-membership',id=named.id,before=before,after=visible_owner_ids(),text=name_text(),query=assert(unit_list(selector,0)).filter_str}
 capture('owner-open-filter-membership')
end)
named.name.first_name=old_name;assert(filter_ok,filter_error)
reopen_owner()
filter=df.reinterpret_cast(df.widget_textbox,assert(dfhack.gui.getWidget(assert(dfhack.gui.getWidget(selector,'Unit selector')),'Filter box')))
input_state('initial')
window_input('ctrl-f','control-f')
-- PostMessage modifier state is tracked by SDL, but Windows TranslateMessage
-- can still emit a plain f because no physical Control key is held. Clear the
-- diagnostic text before continuing; only focus is asserted for this probe.
window_input('clear','clear')
local function focus_help(label)
 local deadline=dfhack.getTickCount()+900
 repeat
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
  g.precise_mouse_x=800;g.precise_mouse_y=700;g.mouse_x=100;g.mouse_y=58
  gui.simulateInput(view,{});filter:logic();view:render(dfhack.getTickCount());script.sleep(1,'frames')
 until dfhack.getTickCount()>=deadline
 view:render(dfhack.getTickCount())
 local main=df.global.game.main_interface
 records[#records+1]={name='owner-help-'..label,focused=df.global.gview.cur_textbox==filter,
  hover=main.current_hover,enabled=main.hover_instructions_on,cells=help_cells(),
  filter_rect={filter.rect.x1,filter.rect.y1,filter.rect.x2,filter.rect.y2}}
 capture('owner-help-'..label)
 df.global.enabler.tracking_on=previous_tracking;df.global.enabler.mouse_focus=previous_focus
end
focus_help('focused-blank-pointer')
window_input('focused-enter','enter')
focus_help('unfocused-blank-pointer')
pixel(500,730);script.sleep(3,'frames');input_state('focus')
window_input('focused-down','down')
window_input('focused-enter','enter')
pixel(500,730);pixel(800,700);input_state('blank-click')
pixel(500,730);pixel(464,70);input_state('header-click')
assert(zone.assigned_unit_id==-1,'textbox navigation unexpectedly assigned owner')
pixel(500,730);script.sleep(3,'frames')
window_input('limit','limit')
window_input('backspace','backspace')
window_input('clear','clear')
window_input('nonascii','nonascii');capture('owner-input-nonascii')
window_input('partial-utf8','backspace');capture('owner-input-partial-utf8')
gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());pixel(336,154)
-- Isolate retained candidates without changing eligibility or appearance.
local inactive=assert(df.unit.find(996),'inactive owner fixture missing')
assert(inactive.flags1.inactive,'inactive fixture unexpectedly active')
local eligible_text,eligible_code=dfhack.run_command_silent('df3d','zone-owner-candidates-read',tostring(zone.id))
assert(eligible_code==0,eligible_text)
local deceased={}
for _,id in ipairs(require('json').decode(eligible_text))do
 local unit=assert(df.unit.find(id))
 if dfhack.units.isDead(unit)then deceased[#deceased+1]=id end
end
records[#records+1]={name='portrait-deceased-candidates',ids=deceased}
local probes={{name='inactive',unit=inactive}}
if #deceased>0 then probes[#probes+1]={name='deceased',unit=assert(df.unit.find(deceased[1]))}end
for _,probe in ipairs(probes)do
 local unit=probe.unit;local old_first=unit.name.first_name
 local ok,err=pcall(function()
  unit.name.first_name='OwnerPortraitProbe'
  gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());pixel(336,154)
  search('OwnerPortraitProbe');capture('tomb-picker-display-'..probe.name..'-portrait')
  records[#records+1]={name=probe.name..'-portrait-unit',id=unit.id,dead=dfhack.units.isDead(unit),killed=unit.flags2.killed,ghost=unit.flags3.ghostly,inactive=unit.flags1.inactive,pos={unit.pos.x,unit.pos.y,unit.pos.z},sheet_icon=unit.sheet_icon_texpos,portrait=unit.portrait_texpos}
 end)
 unit.name.first_name=old_first
 assert(ok,err)
end
gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());pixel(336,154)
last_search_input=''
snapshot('before-assignment')
window_input('unfocused-enter','enter',false)
records[#records+1]={name='owner-unfocused-enter',owner=zone.assigned_unit_id,active=selector.flag.VISIBILITY_ACTIVE,bottom_mode=df.global.game.main_interface.bottom_mode_selected}
assert(not selector.flag.VISIBILITY_ACTIVE,'Enter did not close owner picker')
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
  local function color_case(name,fg,bg,bright,effect,source)
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
     if fg then assert(color[1]==fg and color[2]==bg and color[3]==bright,'native color precedence differs: '..name)end
     observed=true
    end
   end
   assert(observed,'color fixture has no glyphs')
   if effect then assert(sample.color_facts.native_sources.name_color.effect==effect,'native effect differs: '..name)end
   if source then assert(sample.color_facts.native_sources.name_color.source==source,'native color source differs: '..name)end
   if sample.color_facts.native_sources.name_color.source==0 and sample.color_facts.native_sources.name_color.effect==0 then
    local ordinary=sample.color_facts.native_sources.ordinary_color
    assert(ordinary[1]==fg and ordinary[2]==bg and (ordinary[3]~=0)==bright,'owned ordinary color differs: '..name)
   end
   if name:find('^profession%-') or name:find('^raw%-') or name=='identity-before-noble' then
    local base=sample.color_facts.native_sources.profession_color
    assert(base[1]==fg and base[2]==bg and (base[3]~=0)==bright,'owned base color differs: '..name)
   end
  end
  -- Oracle-only standalone native name widget for states excluded by the
  -- owner eligibility predicate. Never use this as evidence of picker admission.
  local function standalone_color_case(name,fg,bg,bright,effect,source)
   view:render(dfhack.getTickCount())
   local widget=df.widget_unit_name:new()
   widget.u=first_unit;widget.show_gender=true;widget.show_profession=true;widget.one_line_only=false
   widget.flag.whole=7;widget.rect.x1=52;widget.rect.x2=96;widget.rect.y1=20;widget.rect.y2=21
   local ok,why=pcall(function()
    for y=19,20 do for x=52,96 do dfhack.screen.paintTile({ch=0,fg=0,bg=0},x,y)end end
    local observed={}
    local seen={};local began=dfhack.getTickCount()
    repeat
     widget:render(dfhack.getTickCount())
     for y=19,20 do for x=52,96 do
      local tile=dfhack.screen.readTile(x,y)
      if tile.ch~=0 then
       local key=tile.fg..'/'..tile.bg..'/'..tostring(tile.bold)
       if not seen[key]then seen[key]=true;observed[#observed+1]={tile.fg,tile.bg,tile.bold}end
      end
     end end
     if effect~=1 and effect~=2 or #observed>=2 then break end
     script.sleep(1,'frames')
    until dfhack.getTickCount()-began>=2500
    assert(#observed>0,'standalone native name has no glyphs: '..name)
    if effect==1 or effect==2 then assert(#observed==2,'native flash did not show both phases: '..name)end
    local size,address=df.sizeof(df.global.gps);local saved=df.new('uint8_t',size);dfhack.internal.memmove(saved,address,size)
    local text,code=dfhack.run_command_silent('df3d','zone-owner-name-color-read',tostring(owner))
    local unchanged=dfhack.internal.memcmp(saved,address,size)==0;df.delete(saved);assert(unchanged,'color reader changed gps')
    assert(code==0,text);local color=require('json').decode(text)
    assert(color.effect==effect and color.source==source,'standalone native color effect/source differs: '..name)
    local function matches(a,b)return a[1]==b[1] and a[2]==b[2] and a[3]==(b[3]~=0)end
    for _,actual in ipairs(observed)do
     assert(matches(actual,color.color) or (color.effect~=0 and matches(actual,color.alternate)),'standalone native color differs: '..name)
     if fg then assert(actual[1]==fg and actual[2]==bg and actual[3]==bright,'standalone fixed color differs: '..name)end
    end
    records[#records+1]={name='standalone-name-color-'..name,unit_id=owner,color=color,observed=observed,unchanged_gps=true}
   end)
   widget:delete();assert(ok,why)
  end
  first_unit.uwss_display_tile=88;first_unit.uwss_display_color_f=1
  first_unit.uwss_display_color_b=2;first_unit.uwss_display_color_br=1
  color_case('override',1,2,true)
  first_unit.flags3.ghostly=true
  color_case('override-before-ghost',1,2,true)
  first_unit.uwss_display_tile=0
  color_case('ghost',7,0,true)
  first_unit.flags3.ghostly=false
  local saved_skills={}
  for _,skill in ipairs(first_unit.status.current_soul.skills)do
   saved_skills[#saved_skills+1]={skill=skill,rating=skill.rating}
  end
  local hf=assert(df.historical_figure.find(first_unit.hist_figure_id))
  local info=assert(hf.info);local old_reputation=info.reputation
  local reputation=old_reputation or df.reputation_profilest:new()
  local old_identity=reputation.cur_identity
  local identity,inserted
  local identity_ok,identity_error=pcall(function()
   for _,saved in ipairs(saved_skills)do if saved.skill.rating>=15 then saved.skill.rating=14 end end
   info.reputation=reputation
   local all=df.global.world.identities.all
   identity=df.identity:new();identity.id=#all>0 and all[#all-1].id+1 or 0
   identity.name:assign(first_unit.name);identity.race=first_unit.race;identity.caste=first_unit.caste
   identity.type=df.identity_type.FalseIdentity;identity.profession=df.profession.MINER
   identity.histfig_id=first_unit.hist_figure_id;identity.impersonated_hf=-1
   all:insert('#',identity);inserted=true;reputation.cur_identity=identity.id
   color_case('identity-before-noble',7,0,false)
   -- Exercise each immutable profession dispatch destination, including raw
   -- STANDARD fallback and the highest supported profession index.
   for _,profession in ipairs{0,1,5,10,16,22,25,37,41,61,66,76,85,86,87,102,134}do
    identity.profession=profession
    local text,code=dfhack.run_command_silent('df3d','zone-owner-profession-color-read',tostring(owner),tostring(profession));assert(code==0,text)
    local color=require('json').decode(text)
    color_case('profession-'..profession,color[1],color[2],color[3]~=0)
   end
   local creature=df.global.world.raws.creatures.all[first_unit.race]
   local caste=creature.caste[first_unit.caste]
   local saved_raw={creature.color[0],creature.color[1],creature.color[2],
    caste.caste_color[0],caste.caste_color[1],caste.caste_color[2],caste.flags.HAS_COLOR,caste.flags.NO_UNIT_TYPE_COLOR}
   local raw_ok,raw_error=pcall(function()
    identity.profession=0;caste.flags.NO_UNIT_TYPE_COLOR=true;caste.flags.HAS_COLOR=false
    creature.color[0]=4;creature.color[1]=2;creature.color[2]=0
    color_case('raw-creature',4,2,false)
    caste.flags.HAS_COLOR=true;caste.caste_color[0]=1;caste.caste_color[1]=3;caste.caste_color[2]=0
    color_case('raw-caste',1,3,false)
    caste.caste_color[0]=3
    color_case('raw-contrast',3,3,true)
   end)
   for i=0,2 do creature.color[i]=saved_raw[i+1];caste.caste_color[i]=saved_raw[i+4]end
   caste.flags.HAS_COLOR=saved_raw[7];caste.flags.NO_UNIT_TYPE_COLOR=saved_raw[8]
   assert(raw_ok,raw_error)
   -- Native relationship readers preserve first-match strength, including zero.
   -- Own only appended test links and restore flags/identity even on failure.
   local saved_deity=hf.flags.deity
   local owned_links={}
   local relation_ok,relation_error=pcall(function()
    reputation.cur_identity=-1;identity.profession=-1;hf.flags.deity=false
    color_case('noble',5,0,true)
    local function append_link(vector,kind,strength)
     local link=kind:new();link.link_strength=strength
     vector:insert('#',link);owned_links[#owned_links+1]={vector=vector,link=link}
     return link
    end
    local slave=append_link(hf.entity_links,df.histfig_entity_link_slavest,0)
    local slave_later=append_link(hf.entity_links,df.histfig_entity_link_slavest,50)
    color_case('slave-first-zero',5,0,true)
    slave.link_strength=-1;color_case('slave-negative',5,0,true)
    slave.link_strength=50;color_case('slave',7,0,false)
    reputation.cur_identity=identity.id;identity.profession=1
    color_case('identity-before-slave',6,0,true)
    reputation.cur_identity=-1;slave.link_strength=0;slave_later.link_strength=0
    local prisoner=append_link(hf.entity_links,df.histfig_entity_link_prisonerst,50)
    color_case('prisoner',7,0,false)
    prisoner.link_strength=0
    local imprisoner=append_link(hf.histfig_links,df.histfig_hf_link_imprisonerst,50)
    color_case('imprisoner',7,0,false)
    hf.flags.deity=true;color_case('deity-after-imprisoner',6,0,true)
    reputation.cur_identity=identity.id;identity.profession=0;identity.impersonated_hf=-1
    color_case('identity-hides-original-deity',7,0,false)
    identity.impersonated_hf=hf.id;color_case('identity-impersonates-deity',6,0,true)
   end)
   for i=#owned_links,1,-1 do
    local owned=owned_links[i];assert(owned.vector[#owned.vector-1]==owned.link,'relationship fixture ownership changed')
    owned.vector:erase(#owned.vector-1);owned.link:delete()
   end
   hf.flags.deity=saved_deity
   assert(relation_ok,relation_error)
   reputation.cur_identity=-1
   local block=assert(dfhack.maps.getTileBlock(first_unit.pos))
   local above=assert(dfhack.maps.getTileBlock(first_unit.pos.x,first_unit.pos.y,first_unit.pos.z+1))
   local x,y=first_unit.pos.x%16,first_unit.pos.y%16
   local water,water_above=block.designation[x][y],above.designation[x][y]
   local saved_special={water.whole,water_above.whole,first_unit.flags1.whole,first_unit.flags2.whole,
    caste.flags.AQUATIC_UNDERSWIM,caste.flags.HAS_BLOOD,first_unit.enemy.undead,
    caste.misc.remains_color[0],caste.misc.remains_color[1],caste.misc.remains_color[2]}
   local part=assert(first_unit.body.components.body_part_status[0]);local saved_part=part.whole
   local undead=df.unit_active_animationst:new();undead.root_body_part_id=1
   local special_ok,special_error=pcall(function()
    first_unit.enemy.undead=nil;first_unit.flags1.inactive=false;first_unit.flags1.projectile=false;first_unit.flags1.caged=false
    water.flow_size=7;water.liquid_type=false;water_above.flow_size=0;water_above.liquid_type=false
    caste.flags.AQUATIC_UNDERSWIM=false;first_unit.flags2.swimming=false
    color_case('water-submerged',1,1,true,0,4)
    first_unit.flags2.swimming=true;color_case('water-surface-swimmer',5,0,true,0,0)
    water_above.flow_size=1;color_case('water-swimmer-covered',1,1,true,0,4)
    water_above.flow_size=0;caste.flags.AQUATIC_UNDERSWIM=true;color_case('water-aquatic',1,1,true,0,4)
    first_unit.flags1.caged=true;color_case('water-caged-excluded',5,0,true,0,0)
    first_unit.flags1.caged=false;water.liquid_type=true;color_case('water-magma-excluded',5,0,true,0,0)
    water.flow_size=0;water.liquid_type=false
    first_unit.enemy.undead=undead;caste.flags.HAS_BLOOD=false
    caste.misc.remains_color[0]=2;caste.misc.remains_color[1]=3;caste.misc.remains_color[2]=0
    standalone_color_case('undead-remains',2,3,false,0,3)
    caste.misc.remains_color[0]=3;standalone_color_case('undead-remains-contrast',3,3,true,0,3)
    caste.flags.HAS_BLOOD=true;standalone_color_case('undead-blood',nil,nil,nil,0,3)
    first_unit.enemy.undead=nil
    part.missing=false;part.on_fire=true;color_case('fire-body',nil,nil,nil,3,5)
    part.missing=true;color_case('fire-missing-part',5,0,true,0,0)
    local item=assert(first_unit.inventory[0]).item;local old_item_fire=item.flags.on_fire
    local item_ok,item_error=pcall(function()item.flags.on_fire=true;color_case('fire-inventory',nil,nil,nil,3,5)end)
    item.flags.on_fire=old_item_fire;assert(item_ok,item_error)
    part.whole=saved_part
    local skill=assert(first_unit.status.current_soul.skills[0]);local saved_rating=skill.rating
    skill.rating=15
    local legendary_ok,legendary_error=pcall(function()
     color_case('legendary',nil,nil,nil,1,0)
     standalone_color_case('legendary-phases',nil,nil,nil,1,0)
     local raw_saved={caste.caste_color[0],caste.caste_color[1],caste.caste_color[2],caste.flags.HAS_COLOR,caste.flags.NO_UNIT_TYPE_COLOR}
     local contrast_ok,contrast_error=pcall(function()
      reputation.cur_identity=identity.id;identity.profession=0;identity.impersonated_hf=-1
      caste.flags.HAS_COLOR=true;caste.flags.NO_UNIT_TYPE_COLOR=true
      caste.caste_color[0]=3;caste.caste_color[1]=3;caste.caste_color[2]=1
      standalone_color_case('legendary-contrast-phases',nil,nil,nil,1,0)
     end)
     for i=0,2 do caste.caste_color[i]=raw_saved[i+1]end
     caste.flags.HAS_COLOR=raw_saved[4];caste.flags.NO_UNIT_TYPE_COLOR=raw_saved[5];reputation.cur_identity=-1
     assert(contrast_ok,contrast_error)
    end)
    skill.rating=saved_rating;assert(legendary_ok,legendary_error)
    local nemesis=assert(dfhack.units.getNemesis(first_unit));local old_flashes=nemesis.flags.FLASHES
    local flash_ok,flash_error=pcall(function()
     first_unit.flags1.merchant=true;first_unit.flags1.important_historical_figure=true;nemesis.flags.FLASHES=true
     standalone_color_case('nemesis-flashes',nil,nil,nil,2,0)
     first_unit.flags1.important_historical_figure=false;standalone_color_case('nemesis-unimportant',5,0,true,0,0)
     first_unit.flags1.important_historical_figure=true
     reputation.cur_identity=identity.id;identity.profession=1;identity.impersonated_hf=-1
     standalone_color_case('identity-before-nemesis',6,0,true,0,0)
    end)
    nemesis.flags.FLASHES=old_flashes;assert(flash_ok,flash_error)
   end)
   first_unit.enemy.undead=saved_special[7];undead:delete();part.whole=saved_part
   water.whole=saved_special[1];water_above.whole=saved_special[2]
   first_unit.flags1.whole=saved_special[3];first_unit.flags2.whole=saved_special[4]
   caste.flags.AQUATIC_UNDERSWIM=saved_special[5];caste.flags.HAS_BLOOD=saved_special[6]
   for i=0,2 do caste.misc.remains_color[i]=saved_special[i+8]end
   assert(special_ok,special_error)
  end)
  reputation.cur_identity=old_identity
  if inserted then
   local all=df.global.world.identities.all
   assert(all[#all-1]==identity,'identity fixture ownership changed');all:erase(#all-1)
  end
  if identity then identity:delete()end
  info.reputation=old_reputation
  if not old_reputation then reputation:delete()end
  for _,saved in ipairs(saved_skills)do saved.skill.rating=saved.rating end
  assert(identity_ok,identity_error)
 end)
 first_unit.uwss_display_tile=old_color[1];first_unit.uwss_display_color_f=old_color[2]
 first_unit.uwss_display_color_b=old_color[3];first_unit.uwss_display_color_br=old_color[4]
 first_unit.flags3.ghostly=old_color[5]
 assert(color_ok,color_error)
end)
first_unit.relationship_ids.Spouse=old_first;spouse.relationship_ids.Spouse=old_spouse
df.global.plotinfo.economy_active=old_economy
assert(ok,why)

-- Observe real Escape after all effect/color fixtures have restored their inputs.
local function closing_state(label)
 records[#records+1]={name=label,selector_active=selector.flag.VISIBILITY_ACTIVE,
  selected_id=ui.cur_bld and ui.cur_bld.id or -1,focused=df.global.gview.cur_textbox~=nil,
  bottom_mode=df.global.game.main_interface.bottom_mode_selected}
end
closing_state('owner-before-right-click')
window_input('right-click','right-click',false)
closing_state('owner-after-right-click');capture('owner-after-right-click')
window_input('right-click-again','right-click',false)
closing_state('owner-after-second-right-click');capture('owner-after-second-right-click')
if df.global.game.main_interface.bottom_mode_selected==3 then pixel(336,154)end
closing_state('owner-before-real-escape')
window_input('escape','escape',false)
closing_state('owner-after-real-escape')
capture('owner-after-real-escape')
