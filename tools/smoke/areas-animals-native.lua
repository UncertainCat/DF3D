-- Protected paused native oracle. Widget/callback reads are diagnostic only.
local out,view,records=...
local gui=require('gui');local script=require('gui.script');local g=df.global.gps
local main=df.global.game.main_interface;local ui=main.civzone
local image_base=dfhack.internal.getImageBase()
local dumped_portraits={}
local chosen_status_unit,chosen_status_item
-- Identify the semantic item vector read by the pinned Pond producer.
for key,values in pairs(df.global.world.items.other)do
 local _,address=df.sizeof(values)
 if address-image_base==0x23e5cc0 then
  local ids={};for _,item in ipairs(values)do ids[#ids+1]=item.id end
  records[#records+1]={name='pond-item-source',field=tostring(key),vector_rva=address-image_base,ids=ids}
 end
end

local function pixel(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//(g.screen_pixel_x//g.dimx);g.mouse_y=y//(g.screen_pixel_y//g.dimy)
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
end
local function mapclick(p)
 for y=0,g.dimy-1 do for x=0,g.dimx-1 do
  g.mouse_x=x;g.mouse_y=y;g.precise_mouse_x=x*(g.screen_pixel_x//g.dimx)+4;g.precise_mouse_y=y*(g.screen_pixel_y//g.dimy)+6
  local at=dfhack.gui.getMousePos(true)
  if at and at.x==p.x and at.y==p.y and at.z==p.z then
   local pointer={g.precise_mouse_x,g.precise_mouse_y};pixel(pointer[1],pointer[2]);return pointer
  end
 end end
 error('animal fixture tile not visible')
end
local function children(container)
 local result={}
 if not df.widget_container:is_instance(container)then return result end
 local _,address=df.sizeof(df.reinterpret_cast(df.widget_container,container).children)
 local first=df.reinterpret_cast('uint64_t',address).value
 local last=df.reinterpret_cast('uint64_t',address+8).value
 assert(last>=first and (last-first)%16==0 and last-first<=65536,'invalid child vector')
 for at=first,last-1,16 do
  local ptr=df.reinterpret_cast('uint64_t',at).value
  if ptr~=0 then result[#result+1]=df.reinterpret_cast(df.widget,ptr)end
 end
 return result
end
local function walk(container,rows,depth,active)
 assert(depth<10 and #rows<16000,'widget observation truncated')
 local row={name=container.name,type=tostring(container._type),flags=container.flag.whole,
  min_w=container.min_w,active=active and (container.flag.whole&1)~=0,x=container.rect.x1,y=container.rect.y1,x2=container.rect.x2,y2=container.rect.y2}
 if df.widget_unit_name:is_instance(container)then
  local name=df.reinterpret_cast(df.widget_unit_name,container)
  row.unit_id=name.u.id;row.one_line_only=name.one_line_only
  row.show_gender=name.show_gender;row.show_profession=name.show_profession
 end
 if df.widget_unit_portrait:is_instance(container)then row.portrait_unit_id=df.reinterpret_cast(df.widget_unit_portrait,container).u.id end
 if df.widget_item_portrait:is_instance(container)then row.portrait_item_id=df.reinterpret_cast(df.widget_item_portrait,container).i.id end
 if row.portrait_unit_id or row.portrait_item_id then
  local _,address=df.sizeof(container);row.vtable_rva=df.reinterpret_cast('uint64_t',address).value-image_base
 end
 if df.widget_item_name:is_instance(container)then row.item_id=df.reinterpret_cast(df.widget_item_name,container).it.id end
 if df.widget_text:is_instance(container)then row.text=dfhack.df2utf(df.reinterpret_cast(df.widget_text,container).str)end
 rows[#rows+1]=row
 local list=df.widget_unit_list:is_instance(container) and df.reinterpret_cast(df.widget_unit_list,container) or nil
 for _,child in ipairs(children(container))do list=walk(child,rows,depth+1,row.active) or list end
 return list
end
local function callback_at(address)
 local context=df.reinterpret_cast('uint64_t',address+56).value
 if context==0 then return {}end
 local vtable=df.reinterpret_cast('uint64_t',context).value
 return {invoke_rva=df.reinterpret_cast('uint64_t',vtable+16).value-image_base}
end
local function callbacks(value,stride)
 local _,address=df.sizeof(value)
 local first=df.reinterpret_cast('uint64_t',address).value
 local last=df.reinterpret_cast('uint64_t',address+8).value
 assert(last>=first and (last-first)%stride==0 and last-first<=65536,'invalid callback vector')
 local result={};for at=first,last-1,stride do result[#result+1]=callback_at(at)end
 return result
end
local function capture(label,keep_mouse)
 if not keep_mouse then g.mouse_x=0;g.mouse_y=0;g.precise_mouse_x=0;g.precise_mouse_y=0 end
 local mouse={g.precise_mouse_x,g.precise_mouse_y,g.mouse_x,g.mouse_y}
 for i=1,3 do
  if keep_mouse then
   df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
   g.precise_mouse_x=mouse[1];g.precise_mouse_y=mouse[2];g.mouse_x=mouse[3];g.mouse_y=mouse[4]
   gui.simulateInput(view,{})
  end
  view:render(dfhack.getTickCount());script.sleep(1,'frames')
 end
 if keep_mouse then
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
  g.precise_mouse_x=mouse[1];g.precise_mouse_y=mouse[2];g.mouse_x=mouse[3];g.mouse_y=mouse[4]
  gui.simulateInput(view,{});view:render(dfhack.getTickCount())
 end
 local rows={};local list=walk(main.unit_selector,rows,0,true)
 local record={name=label,zone=ui.cur_bld and ui.cur_bld.id or -1,widgets=rows,callbacks={},entries={},assigned={}}
 if ui.cur_bld then for _,id in ipairs(ui.cur_bld.assigned_units)do record.assigned[#record.assigned+1]=id end end
 if list then
  for _,field in ipairs{'filter_func','always_sorting_by','partitions','on_select_change','preprocess_unit_func','postprocess_unit_func','preprocess_item_func','postprocess_item_func'}do record.callbacks[field]=callbacks(list[field],64)end
  record.callbacks.sorting_by=callbacks(list.sorting_by,96)
  local _,address=df.sizeof(list.is_selected);record.callbacks.is_selected=callback_at(address)
  for _,entry in ipairs(list.entry_list)do record.entries[#record.entries+1]={kind=entry.t,id=entry.t==0 and entry.u and entry.u.id or entry.t==1 and entry.i and entry.i.id or -1}end
  record.cursor=list.cursor_idx;record.query=dfhack.df2utf(list.filter_str)
  record.query_bytes={list.filter_str:byte(1,#list.filter_str)}
  record.hover=main.current_hover;record.hover_enabled=main.hover_instructions_on
  record.hover_input={gate=df.reinterpret_cast('uint8_t',image_base+0x23905d5).value,x=g.mouse_x,y=g.mouse_y}
  record.native_mouse={df.reinterpret_cast('int32_t',image_base+0x264a5b0).value,df.reinterpret_cast('int32_t',image_base+0x264a5b4).value}
  local _,gps_address=df.sizeof(g);local _,mouse_address=df.sizeof(g:_field('mouse_x'))
  record.gps_rva=gps_address-image_base;record.mouse_x_rva=mouse_address-image_base
  local _,hover_address=df.sizeof(main:_field('current_hover'))
  record.hover_state={field_rva=hover_address-image_base,native=df.reinterpret_cast('int32_t',image_base+0x18a9398).value,
   replace_minimap=df.reinterpret_cast('uint8_t',image_base+0x18a93b8).value}
  record.render_callbacks={}
  local function render_contexts(widget)
   local _,address=df.sizeof(widget.custom_render)
   local first=df.reinterpret_cast('uint64_t',address).value;local last=df.reinterpret_cast('uint64_t',address+8).value
   for at=first,last-64,64 do
    local context=df.reinterpret_cast('uint64_t',at+56).value
    if context~=0 then
     local vt=df.reinterpret_cast('uint64_t',context).value
     local invoke=df.reinterpret_cast('uint64_t',vt+16).value-image_base
     if invoke==0xf1c80 then
      local inner=df.reinterpret_cast('uint64_t',context+0x40).value
      if inner~=0 then
       local inner_vt=df.reinterpret_cast('uint64_t',inner).value
       local inner_invoke=df.reinterpret_cast('uint64_t',inner_vt+16).value-image_base
       if inner_invoke==0x3d0260 then
        local unit=df.reinterpret_cast(df.unit,df.reinterpret_cast('uint64_t',inner+0x18).value)
        record.render_callbacks[#record.render_callbacks+1]={name=widget.name,unit=unit.id,
         rect={widget.rect.x1,widget.rect.y1,widget.rect.x2,widget.rect.y2},offset=df.reinterpret_cast('int32_t',inner+0x24).value}
       end
      end
     end
    end
   end
   for _,child in ipairs(children(widget))do render_contexts(child)end
  end
  if keep_mouse then render_contexts(main.unit_selector)end
  record.help_cells={}
  if keep_mouse then for y=0,17 do for x=g.dimx-24,g.dimx-1 do
   local tile=dfhack.screen.readTile(x,y)
   if tile.ch>=33 and tile.ch<=255 then record.help_cells[#record.help_cells+1]={x=x,y=y,ch=tile.ch,fg=tile.fg,bg=tile.bg,bold=tile.bold}end
  end end end
  local _,cache_address=df.sizeof(list.job_sort_str)
  record.job_search_cache_count=df.reinterpret_cast('uint64_t',cache_address+16).value
  assert(record.job_search_cache_count==0,'animal picker unexpectedly populated secondary job search text')
  record.displayed={}
  for _,row in ipairs(rows)do
   if row.active and (row.unit_id or row.item_id)then
    record.displayed[#record.displayed+1]={kind=row.item_id and 1 or 0,id=row.item_id or row.unit_id}
   end
  end
  if label:find('%-picker$') or label:find('%-sort%-') or label:find('%-filter%-')then
   local key,direction=label:match('%-sort%-(%a+)%-(%d+)$')
   local sort=key=='name' and 1 or key=='profession' and 3 or 2
   local descending=direction=='2' and 1 or 0
   local guards={}
   for _,value in ipairs{g,main}do
    local size,address=df.sizeof(value);local copy=df.new('uint8_t',size)
    dfhack.internal.memmove(copy,address,size);guards[#guards+1]={copy=copy,address=address,size=size}
   end
   local text,code=dfhack.run_command_silent('df3d','zone-animal-picker-read',tostring(record.zone),
    tostring(sort),tostring(descending),list.filter_str)
   assert(code==0,text);local expected=require('json').decode(text)
   assert(#expected==#record.displayed,'native animal picker count differs: '..label)
   for i,entry in ipairs(expected)do
    assert(entry.kind==record.displayed[i].kind and entry.id==record.displayed[i].id,
     'native animal picker order differs: '..label..' row '..i)
   end
   for _,guard in ipairs(guards)do
    assert(dfhack.internal.memcmp(guard.copy,guard.address,guard.size)==0,'animal ordering read changed native UI/drawing state')
    df.delete(guard.copy)
   end
   record.picker_parity={sort=sort,descending=descending,exact=true,ui_unchanged=true}
  end
  if label=='Pen-picker' or label=='Pond-picker'then
   record.portrait_anchors={}
   for _,row in ipairs(rows)do
    if row.portrait_unit_id and row.active and (row.flags&2)~=0 then
     local cells={}
     for y=row.y,math.min(row.y2,g.dimy-1)do for x=row.x,row.x2 do
      local idx=x*g.dimy+y;local cell={x=x,y=y,tile=dfhack.screen.readTile(x,y).tile}
      for _,field in ipairs{'screentexpos_anchored','screentexpos_anchored_x','screentexpos_anchored_y','screentexpos_top_anchored','screentexpos_top_anchored_x','screentexpos_top_anchored_y'}do cell[field]=g[field][idx]end
      local texture=cell.screentexpos_anchored
      if texture and texture>0 and not dumped_portraits[texture]then
       local text,code=dfhack.run_command_silent('df3d','appearance','texture',tostring(texture),out..'/animal-body-'..texture)
       assert(code==0 and text:find('DF3D_TEXTURE_DUMP_PASS',1,true),text);dumped_portraits[texture]=true
      end
      cells[#cells+1]=cell
     end end
     record.portrait_anchors[#record.portrait_anchors+1]={id=row.portrait_unit_id,rect={row.x,row.y,row.x2,row.y2},cells=cells}
    end
   end
   record.unit_display={}
   for _,row in ipairs(rows)do
    if row.unit_id and row.active and (row.flags&2)~=0 and row.y>=2 and row.y<g.dimy then
     local width=math.max(row.x2-row.x+1,row.min_w)
     assert(row.show_gender and row.show_profession and not row.one_line_only,'animal unit widget variant changed')
     local guards={}
     for _,value in ipairs{g,main}do
      local size,address=df.sizeof(value);local copy=df.new('uint8_t',size)
      dfhack.internal.memmove(copy,address,size);guards[#guards+1]={copy=copy,address=address,size=size}
     end
     local text,code=dfhack.run_command_silent('df3d','zone-animal-unit-display-read',tostring(row.unit_id),tostring(width))
     assert(code==0,text)
     local native=require('json').decode(text)
     local sample={id=row.unit_id,columns=width,owner_reader=native.text,lines={},
      show_gender=row.show_gender,show_profession=row.show_profession,one_line_only=row.one_line_only}
     for y=row.y-2,row.y do
      local bytes,colors={},{}
      for x=row.x,math.min(row.x2,g.dimx-1)do
       local tile=dfhack.screen.readTile(x,y);bytes[#bytes+1]=tile.ch;colors[#colors+1]={tile.fg,tile.bg,tile.bold}
      end
      sample.lines[#sample.lines+1]={y=y,bytes=bytes,colors=colors}
     end
     local unit=assert(df.unit.find(row.unit_id))
     sample.grazer=native.grazer;sample.name_color=native.name_color
     assert(sample.grazer==unit.enemy.caste_flags[df.caste_raw_flags.GRAZER],'animal cached grazer flag differs')
     assert(#native.warning==(sample.grazer and 24 or 0),'animal warning presence differs')
     for _,guard in ipairs(guards)do
      assert(dfhack.internal.memcmp(guard.copy,guard.address,guard.size)==0,'animal unit text/color read changed native UI/drawing state')
      df.delete(guard.copy)
     end
     -- Unit-name render 14237a0: fitting combined text sits at y-1;
     -- split text moves up one row for grazers, leaving y for the warning.
     local expected={{},{},{}}
     if #sample.owner_reader[1]<=width then expected[2]=sample.owner_reader[4]
     else
      local first=sample.grazer and 1 or 2
      expected[first]=sample.owner_reader[4];expected[first+1]=sample.owner_reader[5]
     end
     if sample.grazer then
      expected[3]={0}
      for i,byte in ipairs(native.warning)do expected[3][i+1]=byte end
     end
     local function same_color(a,b)return a[1]==b[1] and a[2]==b[2] and a[3]==(b[3]~=0)end
     for line,observed in ipairs(sample.lines)do for x,byte in ipairs(observed.bytes)do
      assert(byte==(expected[line][x] or 0),'animal unit text/layout differs: '..label..'/'..row.unit_id..'/'..line..'/'..x)
      if byte~=0 then
       local color=sample.grazer and line==3 and {2,0,1} or sample.name_color.color
       assert(same_color(observed.colors[x],color) or
        (not (sample.grazer and line==3) and sample.name_color.effect~=0 and same_color(observed.colors[x],sample.name_color.alternate)),
        'animal unit text color differs: '..label..'/'..row.unit_id..'/'..line..'/'..x)
      end
     end end
     sample.exact=true;sample.ui_unchanged=true
     record.unit_display[#record.unit_display+1]=sample
    end
   end
  end
  if label=='Pen-picker' or label=='Pond-picker' or label=='Pen-assigned-picker' or label=='Pond-assigned-picker' or label=='Pond-filled-status' or label:find('^Pen%-status%-') then
   record.status_icons={}
   record.status_globals={}
   for key,rva in pairs{pasture=0x264aff8,pit=0x264affc,pond=0x264b000,fallback=0x2687a00,chain_rope=0x2684b7c,chain_metal=0x2684b78,cage_base=0x2684bdc,cage_100=0x2684bd8,cage_200=0x2684be0,cage_occupied=0x2684be8,cage_occupied_100=0x2684be4,cage_occupied_200=0x2684bec}do
    local texpos=df.reinterpret_cast('int32_t',image_base+rva).value
    local source={texture=texpos}
    for _,page in ipairs(df.global.texture.page)do
     for index,value in ipairs(page.texpos)do
      if value==texpos then source.page=page.token;source.x=index%page.page_dim_x;source.y=index//page.page_dim_x;break end
     end
     if source.page then break end
    end
    record.status_globals[key]=source
   end
   for _,row in ipairs(rows)do
    if (row.unit_id or row.item_id) and row.active and (row.flags&2)~=0 then
     local subject=row.unit_id and df.unit.find(row.unit_id) or df.item.find(row.item_id)
     local status={id=subject.id,entity=row.unit_id and 1 or 2,rect={row.x,row.y,row.x2,row.y2},refs={},cells={}}
     if row.unit_id then status.flags1=subject.flags1.whole end
     for _,ref in ipairs(subject.general_refs)do
      local building=ref:getBuilding();local item=ref:getItem()
      local fact={kind=ref:getType(),building=building and building.id or -1,item=item and item.id or -1}
      if item then
       fact.item_type=item:getType();fact.material=item:getMaterial();fact.material_index=item:getMaterialIndex()
       local material=dfhack.matinfo.decode(item)
       if material and material.material then
        local pattern_id=material.material.state_color.Solid
        local pattern=pattern_id>=0 and df.global.world.raws.descriptors.patterns[pattern_id] or nil
        if pattern and #pattern.colors>0 then
         local color_id=pattern.colors[0]
         local color=color_id>=0 and df.global.world.raws.descriptors.colors[color_id] or nil
         if color then
          fact.solid_color={pattern=pattern_id,id=color_id,token=color.id,palette={}}
          for _,value in ipairs(color.palette.color)do fact.solid_color.palette[#fact.solid_color.palette+1]=value end
         end
        end
       end
       fact.item_refs={}
       for _,nested in ipairs(item.general_refs)do
        local unit=nested:getUnit();local inside=nested:getItem()
        fact.item_refs[#fact.item_refs+1]={kind=nested:getType(),unit=unit and unit.id or -1,item=inside and inside.id or -1}
       end
      end
      status.refs[#status.refs+1]=fact
     end
     for y=math.max(0,row.y-2),math.min(g.dimy-1,row.y2+1)do for x=row.x+23,math.min(g.dimx-1,row.x+31)do
      local idx=x*g.dimy+y
      local texpos=g.screentexpos_anchored[idx]
      if texpos>0 then
       local cell={x=x,y=y,texture=texpos,offset_x=g.screentexpos_anchored_x[idx],offset_y=g.screentexpos_anchored_y[idx]}
       status.cells[#status.cells+1]=cell
       if not dumped_portraits[texpos]then
        local text,code=dfhack.run_command_silent('df3d','appearance','texture',tostring(texpos),out..'/animal-status-'..texpos)
        assert(code==0 and text:find('DF3D_TEXTURE_DUMP_PASS',1,true),text);dumped_portraits[texpos]=true
       end
      end
     end end
     local guards={}
     for _,value in ipairs{g,main}do
      local size,address=df.sizeof(value);local copy=df.new('uint8_t',size)
      dfhack.internal.memmove(copy,address,size);guards[#guards+1]={copy=copy,address=address,size=size}
     end
     local text,code=dfhack.run_command_silent('df3d','zone-animal-status-read',tostring(record.zone),tostring(status.entity),tostring(status.id))
     assert(code==0,text);local semantic=require('json').decode(text)
     if semantic.kind==4 and df.item.find(semantic.item_id):getType()==df.item_type.CAGE then
      local result,rc=dfhack.run_command_silent('df3d','zone-animal-container-read',tostring(semantic.item_id))
      assert(rc==0,result);local container=require('json').decode(result)
      -- Diagnostic oracle only: match the rendered texture to DF's cage cache
      -- key. Product code reads semantic material/refs and never this cache.
      local vector=image_base+0x24ed158
      local first=df.reinterpret_cast('uint64_t',vector).value
      local last=df.reinterpret_cast('uint64_t',vector+8).value
      assert(last>=first and (last-first)//8<100000,'invalid cage diagnostic cache')
      local native_key
      for address=first,last-8,8 do
       local entry=df.reinterpret_cast('uint64_t',address).value
       if df.reinterpret_cast('int32_t',entry+8).value==status.cells[1].texture then
        native_key=df.reinterpret_cast('uint64_t',entry).value;break
       end
      end
      assert(native_key,'rendered cage missing from diagnostic cache')
      local key=container.color_id+1
      if container.material_family==1 then key=key|0x100 elseif container.material_family==2 then key=key|0x200 end
      if container.occupant_entity~=0 then
       key=key|(container.occupant_entity==1 and 0x800 or 0x400)|(container.occupant_id<<12)
      end
      assert(key==native_key,'owned cage facts differ from native rendered key: '..label..'/'..status.id)
      if container.color_id>=0 then assert(container.solid_color==df.global.world.raws.descriptors.colors[container.color_id].id) end
      status.container={semantic=container,native_key=native_key,exact=true}
     end
     for _,guard in ipairs(guards)do
      assert(dfhack.internal.memcmp(guard.copy,guard.address,guard.size)==0,'animal status reader changed native UI/drawing state')
      df.delete(guard.copy)
     end
     local expected=0
     if #status.cells>0 then
      local texture=status.cells[1].texture
      expected=texture==record.status_globals.pasture.texture and 1 or
       texture==record.status_globals.pit.texture and 2 or texture==record.status_globals.pond.texture and 3 or
       texture==record.status_globals.fallback.texture and 5 or 4
     end
     assert(semantic.kind==expected,'animal status differs from native rendered indicator: '..label..'/'..status.id)
     if expected==4 then
      local item_id=-1
      for _,ref in ipairs(status.refs)do if ref.kind==11 then item_id=ref.item;break end end
      local expected_relation=label:find('^Pen%-status%-current%-chain') and status.id==chosen_status_unit and 1 or
       label:find('^Pen%-status%-pending%-chain') and status.id==chosen_status_unit and 3 or
       label:find('^Pen%-status%-pending%-cage') and status.id==chosen_status_unit and 4 or 2
      if expected_relation~=2 then item_id=chosen_status_item end
      assert(semantic.containment==expected_relation and semantic.item_id==item_id and item_id>=0,'native container subject differs')
     else assert(semantic.containment==0 and semantic.item_id==-1,'non-container status retained item facts') end
     if semantic.kind==4 and df.item.find(semantic.item_id):getType()==df.item_type.CHAIN then
      local item=df.item.find(semantic.item_id);local material=assert(dfhack.matinfo.decode(item))
      local pattern=df.global.world.raws.descriptors.patterns[material.material.state_color.Solid]
      local color_id=#pattern.colors>0 and pattern.colors[0] or -1
      local rope=material.material.flags.THREAD_PLANT or material.material.flags.LEATHER or material.material.flags.SILK or material.material.flags.YARN
      local key=(rope and 1 or 2)|((color_id+1)<<2)
      local vector=image_base+0x24ed2f0;local first=df.reinterpret_cast('uint64_t',vector).value;local last=df.reinterpret_cast('uint64_t',vector+8).value
      assert(last>=first and (last-first)//8<100000,'invalid restraint diagnostic cache')
      local native_key
      for address=first,last-8,8 do
       local entry=df.reinterpret_cast('uint64_t',address).value
       if df.reinterpret_cast('int32_t',entry+4).value==status.cells[1].texture then native_key=df.reinterpret_cast('int32_t',entry).value;break end
      end
      assert(native_key==key,'restraint rendered key differs')
      local guards={}
      for _,value in ipairs{g,main}do
       local size,address=df.sizeof(value);local copy=df.new('uint8_t',size)
       dfhack.internal.memmove(copy,address,size);guards[#guards+1]={copy=copy,address=address,size=size}
      end
      local data,rc=dfhack.run_command_silent('df3d','zone-animal-restraint-read',tostring(item.id))
      assert(rc==0,data);local owned=require('json').decode(data)
      assert(owned.rope==rope and owned.color_id==color_id and owned.solid_color==df.global.world.raws.descriptors.colors[color_id].id,'owned restraint facts differ')
      for _,guard in ipairs(guards)do
       assert(dfhack.internal.memcmp(guard.copy,guard.address,guard.size)==0,'restraint reader changed native UI/drawing state');df.delete(guard.copy)
      end
      status.restraint_reader={semantic=owned,exact=true,ui_unchanged=true}
      status.restraint={item_id=item.id,material_type=item:getMaterial(),material_index=item:getMaterialIndex(),rope=rope,
       solid_color=color_id>=0 and df.global.world.raws.descriptors.colors[color_id].id or '',color_id=color_id,native_key=native_key}
     end
     status.semantic=semantic;status.ui_unchanged=true
     record.status_icons[#record.status_icons+1]=status
    end
   end
  end
  record.item_portrait_anchors={}
  for _,row in ipairs(rows)do
   if row.portrait_item_id and row.active and (row.flags&2)~=0 and label=='Pond-picker' then
    local cells={}
    for y=row.y,math.min(row.y2,g.dimy-1)do for x=row.x,row.x+4 do
     local idx=x*g.dimy+y;local cell={x=x,y=y,tile=dfhack.screen.readTile(x,y).tile}
     for _,field in ipairs{'screentexpos_anchored','screentexpos_anchored_x','screentexpos_anchored_y','screentexpos_top_anchored','screentexpos_top_anchored_x','screentexpos_top_anchored_y'}do cell[field]=g[field][idx]end
     local texture=cell.screentexpos_anchored
     if texture and texture>0 and not dumped_portraits[texture]then
      local text,code=dfhack.run_command_silent('df3d','appearance','texture',tostring(texture),out..'/animal-item-body-'..texture)
      assert(code==0 and text:find('DF3D_TEXTURE_DUMP_PASS',1,true),text);dumped_portraits[texture]=true
     end
     cells[#cells+1]=cell
    end end
    local item=df.item.find(row.portrait_item_id)
    local race,caste=item:getMaterial(),item:getMaterialIndex()
    local creature=df.global.world.raws.creatures.all[race]
    assert(creature,'missing item creature raw')
    local caste_raw=caste>=0 and creature.caste[caste] or nil
    local graphics=caste_raw and caste_raw.caste_graphics or nil
    local selected='caste'
    if not graphics or graphics.creature_small_texpos[0]==0 then graphics=creature.graphics;selected='creature' end
    assert(graphics and graphics.creature_small_texpos[0]>0,'item requires unaudited fallback artwork')
    local _,graphics_address=df.sizeof(graphics)
    local _,small_address=df.sizeof(graphics:_field('creature_small_texpos'))
    assert(small_address-graphics_address==0xffd8,'native critter graphics field drift')
    local texpos=graphics.creature_small_texpos[0]
    local art={race=race,caste=caste,creature=creature.creature_id,scope=selected,texpos=texpos}
    for _,page in ipairs(df.global.texture.page)do
     for index,value in ipairs(page.texpos)do
      if value==texpos then art.page=page.token;art.x=index%page.page_dim_x;art.y=index//page.page_dim_x;break end
     end
     if art.page then break end
    end
    assert(art.page,'critter artwork is not an original tile-page reference')
    assert(cells[1].screentexpos_anchored==texpos,'native item portrait differs from semantic critter tile')
    record.item_portrait_anchors[#record.item_portrait_anchors+1]={id=row.portrait_item_id,rect={row.x,row.y,row.x2,row.y2},vtable_rva=row.vtable_rva,item_type=tostring(item:getType()),live_animal=item:isLiveAnimal(),cells=cells,art=art}
   end
  end
  record.item_text={}
  for _,row in ipairs(rows)do
   if row.item_id and row.active and (row.flags&2)~=0 and row.y>0 and row.y<g.dimy then
    local guards={}
    for _,value in ipairs{g,main}do
     local size,address=df.sizeof(value);local copy=df.new('uint8_t',size)
     dfhack.internal.memmove(copy,address,size);guards[#guards+1]={copy=copy,address=address,size=size}
    end
    local text,code=dfhack.run_command_silent('df3d','zone-animal-item-text-read',tostring(row.item_id))
    assert(code==0,text);local bytes=require('json').decode(text)
    local color_text,color_code=dfhack.run_command_silent('df3d','zone-animal-item-color-read',tostring(row.item_id))
    assert(color_code==0,color_text);local color=require('json').decode(color_text)
    for _,guard in ipairs(guards)do
     assert(dfhack.internal.memcmp(guard.copy,guard.address,guard.size)==0,'item text reader changed native drawing/UI state')
     df.delete(guard.copy)
    end
    assert(#bytes>0 and row.x+#bytes<=g.dimx,'item text fixture must fit completely')
    for i,byte in ipairs(bytes)do
     local cell=dfhack.screen.readTile(row.x+i-1,row.y-1)
     assert(cell.ch==byte,'native item text differs: '..label..' byte '..i)
     assert(cell.fg==color[1] and cell.bg==color[2] and (cell.bold and 1 or 0)==color[3],
      'native item text color differs: '..label..' byte '..i)
    end
    record.item_text[#record.item_text+1]={id=row.item_id,bytes=bytes,color=color,
     text_origin={row.x,row.y-1},widget_rect={row.x,row.y,row.x2,row.y2},exact=true,ui_unchanged=true}
   end
  end
  if label:find('%-picker$')then
   local text,code=dfhack.run_command_silent('df3d','zone-animal-candidates-read',tostring(record.zone))
   assert(code==0,text)
   local candidates=require('json').decode(text)
   assert(#candidates==#record.entries,'animal candidate count differs: '..label)
   for i,candidate in ipairs(candidates)do
    local entry=record.entries[i]
    assert(candidate.kind==entry.kind and candidate.id==entry.id,'animal raw candidate order differs: '..label..' at '..i)
   end
   record.semantic_candidates=candidates;record.exact_candidate_parity=true
  end
 end
 records[#records+1]=record
 local f=assert(io.open(out..'/shot.tmp','w'));f:write(label);f:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local limit=dfhack.getTickCount()+30000
 while not io.open(out..'/ack-'..label,'r')do assert(dfhack.getTickCount()<limit,'capture timed out');script.sleep(1,'frames')end
 return record
end
local function reopen()
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());pixel(336,154)
end
local function animal_window_input(action)
 local f=assert(io.open(out..'/owner-input-request.tmp','w'));f:write(action);f:close()
 assert(os.rename(out..'/owner-input-request.tmp',out..'/owner-input-request'))
 local deadline=dfhack.getTickCount()+30000
 while true do
  local ack=io.open(out..'/owner-input-ack','r');if ack then ack:close();break end
  assert(dfhack.getTickCount()<deadline,'animal window input timeout');script.sleep(1,'frames')
 end
 assert(os.remove(out..'/owner-input-ack'));script.sleep(5,'frames')
end
local function animal_search_input(prefix)
 local selector=main.unit_selector
 local filter=df.reinterpret_cast(df.widget_textbox,assert(dfhack.gui.getWidget(assert(dfhack.gui.getWidget(selector,'Unit selector')),'Filter box')))
 local zone=assert(ui.cur_bld);local before={}
 for _,id in ipairs(zone.assigned_units)do before[#before+1]=id end
 local function observe(label)
  view:render(dfhack.getTickCount())
  local rows={};local list=assert(walk(selector,rows,0,true));local bytes={}
  for i=1,#filter.str do bytes[#bytes+1]=filter.str:byte(i)end
  records[#records+1]={name=prefix..'-input-'..label,active=selector.flag.VISIBILITY_ACTIVE,
   focused=df.global.gview.cur_textbox==filter,listening=df.global.enabler.listening_to_text,
   bytes=bytes,query_bytes={list.filter_str:byte(1,#list.filter_str)},cursor=list.cursor_idx,maxlen=filter.maxlen,
   rect={filter.rect.x1,filter.rect.y1,filter.rect.x2,filter.rect.y2}}
  assert(selector.flag.VISIBILITY_ACTIVE and ui.cur_bld==zone,'animal input closed picker')
  assert(filter.maxlen==33 and list.cursor_idx==0,'animal filter limit/navigation changed')
  assert((df.global.gview.cur_textbox==filter)==(label~='initial' and label~='focused-enter'),'animal filter focus changed: '..label)
  local length=({limit=33,backspace=32,clear=0,nonascii=2,['partial-utf8']=1})[label]
  if length then assert(#bytes==length,'animal filter byte count changed: '..label)end
  if label=='nonascii' or label=='partial-utf8' then assert(bytes[1]==195 and (label~='nonascii' or bytes[2]==169),'animal filter input bytes changed')end
  assert(#zone.assigned_units==#before,'animal textbox input changed assignment')
  for i,id in ipairs(before)do assert(zone.assigned_units[i-1]==id,'animal textbox changed membership')end
 end
 observe('initial')
 animal_window_input('control-f');observe('ctrl-f')
 -- Windows TranslateMessage may emit a plain f without physical Control.
 animal_window_input('clear');observe('clear')
 animal_window_input('down');observe('focused-down')
 animal_window_input('enter');observe('focused-enter')
 -- Blank panel clicks can change civzone.cur_bld while retaining the selector;
 -- that parent-selection interaction needs a separate fixture.
 pixel(500,730);pixel(464,70);observe('header-click')
 pixel(500,730)
 for i,action in ipairs{'limit','backspace','clear','nonascii','backspace'}do
  animal_window_input(action);observe(i==5 and 'partial-utf8' or action)
 end
 capture(prefix..'-input-partial-utf8')
 animal_window_input('clear');animal_window_input('enter')
 reopen()
 capture(prefix..'-input-reset-picker')
end
local function controls(prefix,searches)
 for _,header in ipairs{{'name',464},{'category',544},{'profession',608}}do
  for click=1,2 do
   pixel(header[2],70);script.sleep(3,'frames')
   local observed=capture(prefix..'-sort-'..header[1]..'-'..click)
   if prefix=='Pond-selected' then
    local first=assert(observed.displayed[1])
    assert(first.kind==1 and first.id==ui.cur_bld.assigned_items[0],'selection partition reversed with sort')
   end
  end
 end
 pixel(464,70);script.sleep(3,'frames');capture(prefix..'-return-sort-name-2')
 for i,query in ipairs(searches==false and {} or {'yak','GRAZER','tame','lovebird','5969','stray','female'})do
  reopen();pixel(500,730)
  for byte in query:gmatch('.')do
   df.global.enabler.last_text_input[0]=byte:byte();df.global.enabler.last_text_input[1]=0
   gui.simulateInput(view,string.format('STRING_A%03d',byte:byte()))
   view:render(dfhack.getTickCount());script.sleep(2,'frames')
  end
  local observed=capture(prefix..'-filter-'..i)
  assert(observed.query==query:lower(),'native filter input was not delivered')
  if query=='GRAZER' or query=='5969' or query=='female' then
   assert(#observed.displayed==0,'native search matched absent description text')
  elseif query=='lovebird' then
   assert(#observed.displayed==3,'native item description search missed a PET/VERMIN fixture')
   for _,entry in ipairs(observed.displayed)do assert(entry.kind==1,'native item search returned a unit')end
  end
 end
 reopen()
end
local function status_hover(label,id,expected)
 local rows={};walk(main.unit_selector,rows,0,true)
 local target
 for _,row in ipairs(rows)do if row.unit_id==id then target=row;break end end
 assert(target,'missing status hover subject')
 local px,py=(target.x+25)*8+4,(target.y-2)*12+8
 local deadline=dfhack.getTickCount()+900
 repeat
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
  g.precise_mouse_x=px;g.precise_mouse_y=py;g.mouse_x=px//8;g.mouse_y=(py-4)//12
  gui.simulateInput(view,{});view:render(dfhack.getTickCount());script.sleep(1,'frames')
 until dfhack.getTickCount()>=deadline
 g.precise_mouse_x=px;g.precise_mouse_y=py;g.mouse_x=px//8;g.mouse_y=(py-4)//12
 local record=capture(label,true)
 record.expected_hover=expected;record.hover_match=record.hover==expected and record.hover_enabled
 -- 3d0260 passes row y as r8 and indicator x as r9 to 3acdc0,
 -- whose hit test compares those arguments against mouse x/y respectively.
 local swapped_x,swapped_y=target.y-2,target.x+25
 local swapped_deadline=dfhack.getTickCount()+900
 repeat
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
  g.mouse_x=swapped_x;g.mouse_y=swapped_y;g.precise_mouse_x=swapped_x*8+4;g.precise_mouse_y=swapped_y*12+8
  gui.simulateInput(view,{});view:render(dfhack.getTickCount());script.sleep(1,'frames')
 until dfhack.getTickCount()>=swapped_deadline
 g.mouse_x=swapped_x;g.mouse_y=swapped_y;g.precise_mouse_x=swapped_x*8+4;g.precise_mouse_y=swapped_y*12+8
 local transposed=capture(label..'-transposed',true)
 transposed.expected_hover=expected;transposed.hover_match=transposed.hover==expected and transposed.hover_enabled
 assert(transposed.hover_match,'native transposed containment hover did not activate')
 -- Retain both the visible icon's failed activation and the transposed help.
 for _,sample in ipairs{record,transposed}do
  sample.help_text={}
  for y=0,17 do
   local chars={};for x=1,24 do chars[x]=' 'end
   for _,cell in ipairs(sample.help_cells)do if cell.y==y then chars[cell.x-(g.dimx-24)+1]=string.char(cell.ch)end end
   sample.help_text[#sample.help_text+1]=dfhack.df2utf(table.concat(chars))
  end
 end
end
local function navigation(prefix,opened)
 assert(opened.cursor==0,'animal picker did not initially select first row')
 local last=#opened.displayed-1
 for _,probe in ipairs{{'down','STANDARDSCROLL_DOWN',math.min(1,last)},
  {'up','STANDARDSCROLL_UP',0},{'pagedown','STANDARDSCROLL_PAGEDOWN',math.min(16,last)},
  {'pageup','STANDARDSCROLL_PAGEUP',0}}do
  gui.simulateInput(view,probe[2]);view:render(dfhack.getTickCount())
  local observed=capture(prefix..'-navigation-'..probe[1])
  assert(observed.cursor==probe[3],'animal navigation differs: '..probe[1]..'/'..observed.cursor)
 end
 for _,probe in ipairs{{'row-third',500,172},{'portrait-third',394,172},{'checkbox-third',672,172},{'header',464,70}}do
  local until_tick=dfhack.getTickCount()+900
  repeat
   df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
   g.precise_mouse_x=probe[2];g.precise_mouse_y=probe[3];g.mouse_x=probe[2]//8;g.mouse_y=(probe[3]-4)//12
   gui.simulateInput(view,{});view:render(dfhack.getTickCount());script.sleep(1,'frames')
  until dfhack.getTickCount()>=until_tick
  local observed=capture(prefix..'-hover-'..probe[1],true)
  assert(observed.cursor==0,'animal hover changed keyboard selection: '..probe[1])
 end
 capture(prefix..'-navigation-restored')
 if prefix=='Pen' then
  local target=opened.displayed[1];assert(target.kind==0,'Pen keyboard fixture requires unit')
  local zone=ui.cur_bld;assert(#zone.assigned_units==0,'Pen keyboard fixture must start unassigned')
  gui.simulateInput(view,'SELECT');view:render(dfhack.getTickCount())
  local assigned=capture(prefix..'-keyboard-assigned')
  assert(#zone.assigned_units==1 and zone.assigned_units[0]==target.id,'SELECT did not assign focused animal')
  gui.simulateInput(view,'SELECT');view:render(dfhack.getTickCount())
  local cleared=capture(prefix..'-keyboard-cleared')
  assert(#zone.assigned_units==0,'SELECT did not clear focused animal')
  assert(assigned.cursor==0 and cleared.cursor==0,'SELECT moved first-row cursor')
 end
end
-- Diagnostic-only native color writes are compared with the owned reader,
-- then drawing state and raw facts are restored before the visible oracle.
do
 local item=assert(df.global.world.items.other.ANY_CRITTER[0])
 local race,caste_id=item.race,item.caste
 local creature=assert(df.global.world.raws.creatures.all[race])
 local caste=assert(creature.caste[caste_id])
 local creature_color={creature.color[0],creature.color[1],creature.color[2]}
 local caste_color={caste.caste_color[0],caste.caste_color[1],caste.caste_color[2]}
 local had_color=caste.flags.HAS_COLOR
 local size,address=df.sizeof(g);local saved=df.new('uint8_t',size)
 dfhack.internal.memmove(saved,address,size)
 local function check(name)
  local before=df.new('uint8_t',size);dfhack.internal.memmove(before,address,size)
  local text,code=dfhack.run_command_silent('df3d','zone-animal-item-color-read',tostring(item.id))
  assert(code==0,text);local actual=require('json').decode(text)
  assert(dfhack.internal.memcmp(before,address,size)==0,'item color reader changed drawing state')
  df.delete(before)
  item:setDisplayColor(0)
  local expected={g.screenf,g.screenb,g.screenbright and 1 or 0}
  for i=1,3 do assert(actual[i]==expected[i],'native item color branch differs: '..name)end
  records[#records+1]={name='item-color-'..name,item=item.id,color=actual,exact=true,gps_unchanged=true}
 end
 check('baseline')
 caste.flags.HAS_COLOR=false
 creature.color[0]=2;creature.color[1]=0;creature.color[2]=1;check('creature')
 caste.flags.HAS_COLOR=true
 caste.caste_color[0]=6;caste.caste_color[1]=3;caste.caste_color[2]=0;check('caste-background')
 caste.caste_color[0]=3;check('equal-colors-force-bold')
 item.caste=-1;check('missing-caste')
 item.race=-1;check('missing-race')
 item.race=race;item.caste=caste_id;caste.flags.HAS_COLOR=had_color
 for i=0,2 do creature.color[i]=creature_color[i+1];caste.caste_color[i]=caste_color[i+1]end
 dfhack.internal.memmove(address,saved,size);df.delete(saved)
end
-- Paused disposable-clone fixture: a second critter with the same description
-- exercises equal text keys and native item Category address ordering.
do
 local original=assert(df.global.world.items.other.ANY_CRITTER[0])
 local pet=df.item_petst:is_instance(original)
 assert(pet or df.item_verminst:is_instance(original),'duplicate text fixture requires a critter item')
 local extra=pet and df.item_petst:new() or df.item_verminst:new()
 extra.id=df.global.item_next_id;df.global.item_next_id=extra.id+1
 extra.race=original.race;extra.caste=original.caste
 extra.flags.whole=original.flags.whole;extra.flags2.whole=original.flags2.whole
 extra.pos:assign(original.pos)
 df.global.world.items.all:insert('#',extra)
 df.global.world.items.other.ANY_CRITTER:insert('#',extra)
 if pet then df.global.world.items.other.PET:insert('#',extra)
 else df.global.world.items.other.VERMIN:insert('#',extra)end
 records[#records+1]={name='equal-name-item-fixture',original=original.id,extra=extra.id,item_type=tostring(original:getType())}
end
-- A live VERMIN instance exercises its actual virtual dispatch separately from PET.
-- Retain it until this owned unsaved session exits, as native widgets keep pointers.
local vermin_fixture
do
 local original=assert(df.global.world.items.other.ANY_CRITTER[0])
 local extra=df.item_verminst:new()
 extra.id=df.global.item_next_id;df.global.item_next_id=extra.id+1
 extra.race=original.race;extra.caste=original.caste
 extra.flags.whole=original.flags.whole;extra.flags2.whole=original.flags2.whole
 extra.pos:assign(original.pos)
 df.global.world.items.all:insert('#',extra)
 df.global.world.items.other.ANY_CRITTER:insert('#',extra)
 df.global.world.items.other.VERMIN:insert('#',extra)
 assert(extra:isLiveAnimal(),'VERMIN fixture is not a live animal')
 vermin_fixture=extra
 records[#records+1]={name='live-vermin-fixture',id=extra.id,source=original.id,
  item_type=tostring(extra:getType()),race=extra.race,caste=extra.caste,live_animal=true}
end
local base=assert(df.global.world.buildings.other.ANY_ZONE[0])
local p={x=base.centerx,y=base.centery,z=base.z}
main.bottom_mode_selected=-1;gui.simulateInput(view,'D_CIVZONE')
dfhack.gui.revealInDwarfmodeMap(p,true);view:render(dfhack.getTickCount())
capture('animal-zone-chooser')
local function contains(values,id)
 for _,value in ipairs(values)do if value==id then return true end end
 return false
end
local function effects(label,kind,id)
 local object=assert(kind==0 and df.unit.find(id) or df.item.find(id))
 local result={name=label,kind=kind,id=id,zones={},cages={},chains={},refs={}}
 for _,zone in ipairs(df.global.world.buildings.other.ANY_ZONE)do
  if contains(kind==0 and zone.assigned_units or zone.assigned_items,id)then result.zones[#result.zones+1]=zone.id end
 end
 for _,cage in ipairs(df.global.world.buildings.other.CAGE)do
  if contains(kind==0 and cage.assigned_units or cage.assigned_items,id)then result.cages[#result.cages+1]=cage.id end
 end
 for _,ref in ipairs(object.general_refs)do
  local row={kind=df.general_ref_type[ref:getType()]}
  if df.general_ref_building:is_instance(ref)then row.building_id=df.reinterpret_cast(df.general_ref_building,ref).building_id end
  result.refs[#result.refs+1]=row
 end
 if kind==0 then
  for _,chain in ipairs(df.global.world.buildings.other.CHAIN)do
   if chain.assigned==object or chain.chained==object then
    local jobs={};for _,job in ipairs(chain.jobs)do jobs[#jobs+1]={id=job.id,type=df.job_type[job.job_type]}end
    result.chains[#result.chains+1]={id=chain.id,assigned=chain.assigned and chain.assigned.id or -1,
     chained=chain.chained and chain.chained.id or -1,jobs=jobs}
   end
  end
  result.flags1=object.flags1.whole;result.flags2=object.flags2.whole
  result.job=object.job.current_job and object.job.current_job.id or -1
 end
 records[#records+1]=result
 return result
end
local function click_entry(record,kind,id)
 for _,row in ipairs(record.widgets)do
  if row.active and (kind==0 and row.unit_id==id or kind==1 and row.item_id==id)then
   assert((row.flags&2)~=0,'target row is clipped')
   pixel(672,(row.y-1)*12+6);return
  end
 end
 error('native animal row missing: '..kind..'/'..id)
end
local function find_job(id)
 for _,value in require('utils').listpairs(df.global.world.jobs.list)do if value.id==id then return value end end
end
local chosen_unit,chosen_item,pen_zone,pond_zone
local resize_marker=io.open(out..'/picker-resize','r')
local resize_only=resize_marker~=nil
if resize_marker then
 resize_marker:close()
 -- Owned unsaved diagnostic: enough eligible items to expose the full page.
 local original=assert(df.global.world.items.other.ANY_CRITTER[0])
 local pet=df.item_petst:is_instance(original)
 assert(pet or df.item_verminst:is_instance(original))
 for index=1,32 do
  local extra=pet and df.item_petst:new() or df.item_verminst:new()
  extra.id=df.global.item_next_id;df.global.item_next_id=extra.id+1
  extra.race=original.race;extra.caste=original.caste
  extra.flags.whole=original.flags.whole;extra.flags2.whole=original.flags2.whole
  extra.pos:assign(original.pos)
  df.global.world.items.all:insert('#',extra)
  df.global.world.items.other.ANY_CRITTER:insert('#',extra)
  df.global.world.items.other[pet and 'PET' or 'VERMIN']:insert('#',extra)
 end
end
for _,probe in ipairs(resize_only and {{'Pond',60,438}} or {{'Pen',60,402},{'Pond',60,438},{'Pond-transfer',60,438}})do
 local kind=probe[1]=='Pen' and 'Pen' or 'Pond'
 pixel(probe[2],probe[3]);mapclick(p);mapclick(p)
 assert(ui.cur_bld and ui.cur_bld.type==df.civzone_type[kind],'native animal zone creation failed: '..tostring(ui.cur_bld and df.civzone_type[ui.cur_bld.type]))
 local zone=ui.cur_bld
 pixel(304,114);capture(probe[1]..'-zone')
 pixel(336,154);local opened=capture(probe[1]..'-picker')
 if resize_only then
  local function find_scroll(widget)
   if df.widget_scroll_rows:is_instance(widget)then return df.reinterpret_cast(df.widget_scroll_rows,widget)end
   for _,child in ipairs(children(widget))do local found=find_scroll(child);if found then return found end end
  end
  for _,size in ipairs{'small','wide','default'}do
   animal_window_input('name-resize-'..size)
   view:render(dfhack.getTickCount());script.sleep(2,'frames')
   local rows={};local list=assert(walk(main.unit_selector,rows,0,true));local scroll=assert(find_scroll(list))
   local filter=df.reinterpret_cast(df.widget_textbox,assert(dfhack.gui.getWidget(assert(dfhack.gui.getWidget(main.unit_selector,'Unit selector')),'Filter box')))
   records[#records+1]={name='animal-resize',size=size,dimx=g.dimx,dimy=g.dimy,
    pixel_width=g.screen_pixel_x,pixel_height=g.screen_pixel_y,rows=rows,
    num_visible=scroll.num_visible,scroll=scroll.scroll,cursor=list.cursor_idx,
    scroll_rect={scroll.rect.x1,scroll.rect.y1,scroll.rect.x2,scroll.rect.y2},
    filter_rect={filter.rect.x1,filter.rect.y1,filter.rect.x2,filter.rect.y2}}
   capture('animal-resize-'..size)
   assert(#zone.assigned_units==0,'resize changed animal assignments')
  end
  return
 end
 if probe[1]=='Pen' or probe[1]=='Pond' then navigation(probe[1],opened) end
 if probe[1]=='Pen' or probe[1]=='Pond' then animal_search_input(probe[1]) end
 if probe[1]=='Pond' then
  local previous=zone.zone_settings.pond.flag.keep_filled
  zone.zone_settings.pond.flag.keep_filled=true
  local filled=capture('Pond-filled-status')
  for _,status in ipairs(filled.status_icons)do
   for _,ref in ipairs(status.refs)do
    if status.entity==1 and ref.kind==31 and ref.building>=0 then
     assert(#status.cells>0 and status.cells[1].texture==filled.status_globals.pond.texture,'filled Pond status differs')
    end
   end
  end
  zone.zone_settings.pond.flag.keep_filled=previous
  controls('Pond');opened=capture('Pond-controls-reset-picker')
 end
 if kind=='Pen' then
  pen_zone=zone.id
  for _,entry in ipairs(opened.entries)do if entry.kind==0 and df.unit.find(entry.id).flags1.caged then chosen_unit=entry.id;break end end
  assert(chosen_unit,'caged native animal required')
  -- Controlled semantic fixture: native assignment must remove cage membership
  -- and pending chain work, but retain actual containment/chained state.
  local animal=assert(df.unit.find(chosen_unit))
  local cage=assert(df.global.world.buildings.other.CAGE[0])
  assert(not contains(cage.assigned_units,animal.id),'fixture animal already assigned to cage')
  cage.assigned_units:insert('#',animal.id)
  local chain=df.building_chainst:new()
  chain.id=df.global.building_next_id;df.global.building_next_id=chain.id+1
  chain.centerx=p.x;chain.centery=p.y;chain.z=p.z
  chain.x1=p.x;chain.x2=p.x;chain.y1=p.y;chain.y2=p.y
  chain.assigned=animal;chain.chained=animal
  df.global.world.buildings.all:insert('#',chain)
  df.global.world.buildings.other.CHAIN:insert('#',chain)
  local function job(kind)
   local value=df.job:new();value.job_type=kind;value.posting_index=-1
   local ref=df.general_ref_building_holderst:new();ref.building_id=chain.id
   value.general_refs:insert('#',ref)
   assert(dfhack.job.linkIntoWorld(value,true));chain.jobs:insert('#',value)
   return value.id
  end
  local cancelled=job(df.job_type.ChainAnimal)
  local retained=job(df.job_type.UnchainAnimal)
  local worker
  for _,unit in ipairs(df.global.world.units.active)do
   if dfhack.units.isCitizen(unit) and not unit.job.current_job then worker=unit;break end
  end
  assert(worker,'chain fixture needs an idle citizen')
  local held_item
  for _,item in ipairs(df.global.world.items.all)do
   if not item.flags.in_job and #item.specific_refs==0 then held_item=item;break end
  end
  assert(held_item,'chain fixture needs an unreserved item')
  assert(dfhack.job.addWorker(assert(find_job(cancelled)),worker))
  assert(dfhack.job.attachJobItem(find_job(cancelled),held_item,df.job_role_type.Hauled,-1,-1))
  assert(worker.job.current_job.id==cancelled and held_item.flags.in_job and #held_item.specific_refs==1)
  records[#records+1]={name='chain-worker-item-before',job=cancelled,worker=worker.id,
   item=held_item.id,current_job=worker.job.current_job.id,in_job=held_item.flags.in_job,item_refs=#held_item.specific_refs}
  records[#records+1]={name='controlled-chain-fixture',chain=chain.id,cage=cage.id,
   unit=animal.id,cancelled_job=cancelled,retained_job=retained}
  -- Exercise every containment fallback against the actual native renderer.
  -- All changes are paused, temporary fixture state in this never-saved session.
  chosen_status_unit=animal.id
  local contained
  for _,ref in ipairs(animal.general_refs)do if ref:getType()==df.general_ref_type.CONTAINED_IN_ITEM then contained=ref;break end end
  assert(contained and contained:getItem(),'status fixture needs current cage')
  local original_item_id=contained.item_id
  local original_flags=animal.flags1.whole
  local container=contained:getItem()
  local original_type,original_index=container.mat_type,container.mat_index
  local wood
  for _,item in ipairs(df.global.world.items.all)do
   if item:getMaterial()>=419 and item:getMaterial()<=618 then wood=item;break end
  end
  assert(wood,'cage variant fixture needs a real wood material')
  container.mat_type=wood:getMaterial();container.mat_index=wood:getMaterialIndex()
  capture('Pen-status-wood-cage')
  container.mat_type=3;container.mat_index=-1
  capture('Pen-status-glass-cage')
  container.mat_type=original_type;container.mat_index=original_index
  animal.flags1.inactive=true
  capture('Pen-status-inactive-cage')
  animal.flags1.whole=original_flags
  -- Diagnostic-only occupant ordering: retain original references and restore
  -- them before assignment. These fixture mutations never become product inputs.
  do
   local original_refs={}
   for _,ref in ipairs(container.general_refs)do original_refs[#original_refs+1]=ref end
   local critter=assert(df.global.world.items.other.ANY_CRITTER[0])
   assert(critter:isLiveAnimal(),'container ordering needs a live critter')
   local unit_ref=df.general_ref_contains_unitst:new();unit_ref.unit_id=animal.id
   local stale_unit=df.general_ref_contains_unitst:new();stale_unit.unit_id=-1
   local item_ref=df.general_ref_contains_itemst:new();item_ref.item_id=critter.id
   local inert_ref=df.general_ref_contains_itemst:new();inert_ref.item_id=container.id
   local stale_item=df.general_ref_contains_itemst:new();stale_item.item_id=-1
   local vermin_ref=df.general_ref_contains_itemst:new();vermin_ref.item_id=vermin_fixture.id
   local function replace(refs)
    for index=#container.general_refs-1,0,-1 do container.general_refs:erase(index)end
    for _,ref in ipairs(refs)do container.general_refs:insert('#',ref)end
   end
   for _,probe in ipairs{
    {'empty',{},0,-1},
    {'stale-unit-before-item',{stale_unit,item_ref},0,-1},
    {'stale-item-before-unit',{stale_item,unit_ref},1,animal.id},
    {'inert-item-before-critter',{inert_ref,item_ref},2,critter.id},
    {'unit-before-critter',{unit_ref,item_ref},1,animal.id},
    {'critter-before-unit',{item_ref,unit_ref},2,critter.id},
    {'vermin-before-unit',{vermin_ref,unit_ref},2,vermin_fixture.id},
    {'inactive-unit-before-critter',{unit_ref,item_ref},0,-1,true},
   }do
    replace(probe[2]);animal.flags1.inactive=probe[5] or false
    local observed=capture('Pen-status-contents-'..probe[1])
    local found
    for _,status in ipairs(observed.status_icons)do
     if status.id==animal.id and status.entity==1 then found=status.container;break end
    end
    assert(found and found.exact,'missing native cage content evidence: '..probe[1])
    assert(found.semantic.occupant_entity==probe[3] and found.semantic.occupant_id==probe[4],
     'unexpected native cage occupant: '..probe[1])
   end
   animal.flags1.whole=original_flags;replace(original_refs)
   for _,ref in ipairs{unit_ref,stale_unit,item_ref,inert_ref,stale_item,vermin_ref}do ref:delete()end
  end
  status_hover('Pen-status-current-cage-hover',animal.id,0x170)
  local chain_item=df.buildingitemst:new();chain_item.item=contained:getItem();chain.contained_items:insert('#',chain_item)
  local chain_ref=df.general_ref_building_chainst:new();chain_ref.building_id=chain.id
  animal.general_refs:insert('#',chain_ref);animal.flags1.chained=true
  chosen_status_item=original_item_id
  capture('Pen-status-current-chain')
  status_hover('Pen-status-current-chain-hover',animal.id,0x16f)
  local made={}
  local restraint_materials={{'metal','INORGANIC:COPPER'},{'rope','PLANT:GRASS_TAIL_PIG:THREAD'}}
  for _,flag in ipairs{'LEATHER','SILK','YARN'}do
   local token
   for _,raw in ipairs(df.global.world.raws.creatures.all)do
    for _,material in ipairs(raw.material)do
     if material.flags[flag] then token='CREATURE:'..raw.creature_id..':'..material.id;break end
    end
    if token then break end
   end
   assert(token,'restraint fixture needs '..flag..' material')
   restraint_materials[#restraint_materials+1]={flag:lower(),token}
  end
  for _,entry in ipairs(restraint_materials)do
   local material=assert(dfhack.matinfo.find(entry[2]),'restraint fixture material missing')
   local items=dfhack.items.createItem(animal,df.item_type.CHAIN,-1,material.type,material.index)
   assert(#items==1,'restraint fixture creation failed')
   local item=items[1];made[#made+1]=item
   chain_item.item=item;chosen_status_item=item.id
   capture('Pen-status-current-chain-'..entry[1])
  end
  chain_item.item=container;chosen_status_item=original_item_id
  for _,item in ipairs(made)do assert(dfhack.items.remove(item),'restraint fixture cleanup failed')end
  animal.flags1.whole=original_flags
  animal.general_refs:erase(#animal.general_refs-1);chain_ref:delete()
  contained.item_id=-1
  capture('Pen-status-pending-chain')
  status_hover('Pen-status-pending-chain-hover',animal.id,0x171)
  chain.assigned=nil
  assert(#cage.contained_items>0 and cage.contained_items[0].item,'status fixture needs installed cage item')
  chosen_status_item=cage.contained_items[0].item.id
  capture('Pen-status-pending-cage')
  status_hover('Pen-status-pending-cage-hover',animal.id,0x172)
  cage.assigned_units:erase(#cage.assigned_units-1)
  capture('Pen-status-missing-container')
  chain.assigned=animal
  animal.flags1.caged=false;animal.flags1.chained=false
  capture('Pen-status-uncontained-pending')
  animal.flags1.whole=original_flags;contained.item_id=original_item_id
  cage.assigned_units:insert('#',animal.id)
  chain.contained_items:erase(#chain.contained_items-1);chain_item:delete()
  chosen_status_unit=nil;chosen_status_item=nil
  effects('unit-before-pen',0,chosen_unit)
  click_entry(opened,0,chosen_unit);capture('Pen-assigned')
  gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());pixel(336,154)
  local assigned_picker=capture('Pen-assigned-picker')
  assert(assigned_picker.semantic_candidates[1].assigned and assigned_picker.entries[1].id==chosen_unit,
   'native Pen did not retain assigned unit first')
  local after=effects('unit-after-pen',0,chosen_unit)
  assert(#after.zones==1 and after.zones[1]==pen_zone,'native pen assignment did not select sole zone')
  assert(not contains(cage.assigned_units,animal.id),'native assignment retained cage membership')
  assert(not chain.assigned and chain.chained==animal,'native chain assignment cleanup changed wrong pointer')
  assert(not find_job(cancelled),'native assignment retained ChainAnimal job')
  assert(not worker.job.current_job,'native cancellation retained worker job')
  assert(not held_item.flags.in_job and #held_item.specific_refs==0,'native cancellation retained item reservation')
  records[#records+1]={name='chain-worker-item-after',job=cancelled,worker=worker.id,
   item=held_item.id,current_job=-1,in_job=held_item.flags.in_job,item_refs=#held_item.specific_refs}
  assert(find_job(retained) and #chain.jobs==1 and chain.jobs[0].id==retained,'native assignment removed unrelated chain work')
  records[#records+1]={name='controlled-chain-result',assigned=-1,chained=animal.id,
   cancelled_job_absent=true,retained_job=retained,cage_assignment_absent=true}
  -- Prove semantic holder detachment avoids the UI-dependent cancellation
  -- branch. This diagnostic changes real job relationships, never UI scratch.
  local independent=job(df.job_type.ChainAnimal)
  local pending=assert(find_job(independent))
  local cursor=df.reinterpret_cast('int32_t',image_base+0x2131b60)
  local before_cursor=cursor.value
  local refs_removed=0
  for index=#pending.general_refs-1,0,-1 do
   local ref=pending.general_refs[index]
   if ref:getType()==df.general_ref_type.BUILDING_HOLDER then
    local holder=ref:getBuilding()
    if holder then
     for at=#holder.jobs-1,0,-1 do if holder.jobs[at]==pending then holder.jobs:erase(at)end end
    end
    pending.general_refs:erase(index);ref:delete();refs_removed=refs_removed+1
   end
  end
  assert(refs_removed==1 and #chain.jobs==1,'semantic job detach failed')
  df.global.world.jobs:cancel_job(pending)
  assert(not find_job(independent),'native independent cancellation retained job')
  assert(cursor.value==before_cursor,'independent cancellation changed native job cursor')
  assert(#chain.jobs==1 and chain.jobs[0].id==retained and chain.chained==animal,
   'independent cancellation changed unrelated chain state')
  records[#records+1]={name='independent-chain-cancel',cancelled_job=independent,
   holder_refs_removed=refs_removed,job_absent=true,cursor_unchanged=true,retained_job=retained}

 elseif probe[1]=='Pond' then
  pond_zone=zone.id
  click_entry(opened,0,chosen_unit);capture('Pond-unit-assigned')
  local after=effects('unit-after-pond-transfer',0,chosen_unit)
  assert(#after.zones==1 and after.zones[1]==pond_zone,'native unit transfer did not clear prior zone')
  click_entry(opened,0,chosen_unit);capture('Pond-unit-cleared')
  assert(#effects('unit-after-clear',0,chosen_unit).zones==0,'native unit clear retained assignment')
  for _,entry in ipairs(opened.entries)do if entry.kind==1 then chosen_item=entry.id;break end end
  assert(chosen_item,'native vermin item required')
  effects('item-before-pond',1,chosen_item)
  click_entry(opened,1,chosen_item);capture('Pond-item-assigned')
  gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());pixel(336,154)
  local assigned_picker=capture('Pond-assigned-picker')
  assert(assigned_picker.semantic_candidates[1].assigned and assigned_picker.entries[1].kind==1 and
   assigned_picker.entries[1].id==chosen_item,'native Pond did not retain assigned item first')
  controls('Pond-selected',false)
  local after_item=effects('item-after-pond',1,chosen_item)
  assert(#after_item.zones==1 and after_item.zones[1]==pond_zone,'native item assignment did not select sole zone')
 else
  click_entry(opened,1,chosen_item);capture('Pond-item-transferred')
  local after=effects('item-after-transfer',1,chosen_item)
  assert(#after.zones==1 and after.zones[1]==zone.id,'native item transfer did not clear prior zone')
  click_entry(opened,1,chosen_item);capture('Pond-item-cleared')
  assert(#effects('item-after-clear',1,chosen_item).zones==0,'native item clear retained assignment')
 end
 gui.simulateInput(view,'_MOUSE_R');view:render(dfhack.getTickCount())
end

-- Diagnostic-only: distinguish parent selection from the open picker's target.
-- Restore the parent pointer between independent probes; no runtime code reads it.
do
 local zone=assert(ui.cur_bld)
 local camera={df.global.window_x,df.global.window_y,df.global.window_z}
 dfhack.gui.revealInDwarfmodeMap({x=zone.centerx-8,y=zone.centery,z=zone.z},true)
 view:render(dfhack.getTickCount())
 local same={x=zone.centerx,y=zone.centery,z=zone.z}
 local pointer=mapclick(same)
 assert(pointer[1]>760 and pointer[1]<1180 and pointer[2]>220 and pointer[2]<760,'same-zone probe behind native UI')
 assert(ui.cur_bld==zone,'same-zone baseline chose another zone')
 pixel(336,154)
 local before=capture('animal-same-zone-before')
 local target=assert(before.displayed[1]);assert(target.kind==0,'same-zone needs unit first')
 pixel(500,730);mapclick(same)
 local after=capture('animal-same-zone-after')
 local observed={name='animal-same-zone-input',zone=zone.id,parent_zone=ui.cur_bld and ui.cur_bld.id or -1,
  active=main.unit_selector.flag.VISIBILITY_ACTIVE,focused=df.global.gview.cur_textbox~=nil,pointer=pointer,target=target.id}
 records[#records+1]=observed
 gui.simulateInput(view,'SELECT');view:render(dfhack.getTickCount())
 observed.assigned_after_enter=contains(zone.assigned_units,target.id)
 gui.simulateInput(view,'SELECT');view:render(dfhack.getTickCount())
 observed.assigned_after_second_enter=contains(zone.assigned_units,target.id)
 assert(not observed.assigned_after_second_enter,'same-zone probe retained assignment')
 if main.unit_selector.flag.VISIBILITY_ACTIVE then gui.simulateInput(view,'_MOUSE_R')end
 df.global.window_x=camera[1];df.global.window_y=camera[2];df.global.window_z=camera[3]
 ui.cur_bld=zone;main.bottom_mode_selected=3;view:render(dfhack.getTickCount())
 for _,probe in ipairs{{'blank-center',500,700},{'blank-right',740,700},{'outside-map',800,700},
  {'outside-upper',800,250},{'outside-center',1000,400},{'outside-lower',1100,700}}do
  ui.cur_bld=zone;main.bottom_mode_selected=3;view:render(dfhack.getTickCount())
  pixel(336,154)
  local before=capture('Pond-'..probe[1]..'-before')
  local target=assert(before.displayed[1]);assert(target.kind==0,'blank probe needs first unit')
  pixel(500,730)
  pixel(probe[2],probe[3])
  local rows={};local list=assert(walk(main.unit_selector,rows,0,true))
  local function observe(label)
   local assigned={}
   for _,b in ipairs(df.global.world.buildings.other.ANY_ZONE)do
    if contains(b.assigned_units,target.id)then assigned[#assigned+1]=b.id end
   end
   records[#records+1]={name='animal-blank-input',probe=probe[1],stage=label,
    pointer={probe[2],probe[3]},picker_zone=zone.id,parent_zone=ui.cur_bld and ui.cur_bld.id or -1,
    parent_type=ui.cur_bld and tostring(ui.cur_bld.type) or '',
    active=main.unit_selector.flag.VISIBILITY_ACTIVE,focused=df.global.gview.cur_textbox~=nil,
    mode=main.bottom_mode_selected,cursor=list.cursor_idx,target=target.id,assigned_zones=assigned}
  end
  observe('clicked');capture('Pond-'..probe[1]..'-after-click')
  gui.simulateInput(view,'SELECT');view:render(dfhack.getTickCount());observe('selected')
  gui.simulateInput(view,'SELECT');view:render(dfhack.getTickCount());observe('cleared')
  assert(not contains(zone.assigned_units,target.id),'blank probe left assignment')
  if main.unit_selector.flag.VISIBILITY_ACTIVE then gui.simulateInput(view,'_MOUSE_R');view:render(dfhack.getTickCount())end
 end
 ui.cur_bld=zone;main.bottom_mode_selected=3;view:render(dfhack.getTickCount())
end

-- Long-list scrolling is observed separately so earlier assignment fixtures keep
-- their original membership. All temporary items live only in this unsaved clone.
do
 local original=assert(df.global.world.items.other.ANY_CRITTER[0])
 local pet=df.item_petst:is_instance(original)
 assert(pet or df.item_verminst:is_instance(original))
  for index=1,32 do
  local extra=pet and df.item_petst:new() or df.item_verminst:new()
  extra.id=df.global.item_next_id;df.global.item_next_id=extra.id+1
  extra.race=original.race;extra.caste=original.caste
  extra.flags.whole=original.flags.whole;extra.flags2.whole=original.flags2.whole
  extra.pos:assign(original.pos)
  df.global.world.items.all:insert('#',extra)
  df.global.world.items.other.ANY_CRITTER:insert('#',extra)
  df.global.world.items.other[pet and 'PET' or 'VERMIN']:insert('#',extra)
 end
 pixel(336,154)
 local opened=capture('Pond-long-picker')
 assert(#opened.displayed>32,'long animal fixture did not populate')
 local list=assert(walk(main.unit_selector,{},0,true))
 local function find_scroll(widget)
  if df.widget_scroll_rows:is_instance(widget)then return df.reinterpret_cast(df.widget_scroll_rows,widget)end
  for _,child in ipairs(children(widget))do local found=find_scroll(child);if found then return found end end
 end
 local scroll=assert(find_scroll(list))
 local function point(x,y)
  g.mouse_x=x;g.mouse_y=y
  g.precise_mouse_x=x*(g.screen_pixel_x//g.dimx)+4;g.precise_mouse_y=y*(g.screen_pixel_y//g.dimy)+6
  df.global.enabler.tracking_on=1
 end
 local function observe(label)
  view:render(dfhack.getTickCount());script.sleep(1,'frames')
  local rows={};walk(list,rows,0,true)
  local visible={}
  for _,row in ipairs(rows)do
   if row.active and (row.unit_id or row.item_id) and (row.flags&2)~=0 then
    visible[#visible+1]={id=row.unit_id or row.item_id,kind=row.item_id and 1 or 0,y=row.y,y2=row.y2}
   end
  end
  local bar={}
  for _,field in ipairs{'sel','sel_min','sel_max','page_size','print_sy','print_ey','scroller_sy','scroller_ey'}do bar[field]=scroll.scrollbar[field]end
  local cells={}
  for y=scroll.rect.y1,scroll.rect.y2 do for x=scroll.rect.x2+1,scroll.rect.x2+2 do
   cells[#cells+1]={x=x,y=y,tile=dfhack.screen.readTile(x,y).tile}
  end end
  records[#records+1]={name='animal-scroll',label=label,count=#opened.displayed,
   scroll=scroll.scroll,num_visible=scroll.num_visible,cursor=list.cursor_idx,bar=bar,
   visible=visible,cells=cells,rect={scroll.rect.x1,scroll.rect.y1,scroll.rect.x2,scroll.rect.y2}}
 end
 local function input(label,key,x,y)
  point(x or scroll.rect.x1+5,y or scroll.rect.y1+5)
  gui.simulateInput(view,key);observe(label)
 end
 observe('initial')
 input('context-down','CONTEXT_SCROLL_DOWN')
 input('context-up','CONTEXT_SCROLL_UP')
 input('context-page-down','CONTEXT_SCROLL_PAGEDOWN')
 input('context-page-up','CONTEXT_SCROLL_PAGEUP')
 input('outside-context-down','CONTEXT_SCROLL_DOWN',0,0)
 input('arrow-down','_MOUSE_L',scroll.rect.x2+2,scroll.rect.y2)
 input('arrow-up','_MOUSE_L',scroll.rect.x2+2,scroll.rect.y1)
 input('track-down','_MOUSE_L',scroll.rect.x2+2,scroll.rect.y2-3)
 input('track-up','_MOUSE_L',scroll.rect.x2+2,scroll.rect.y1+1)
 for i=1,5 do input('page-down-'..i,'STANDARDSCROLL_PAGEDOWN')end
 input('tail-down','STANDARDSCROLL_DOWN')
 capture('Pond-long-tail')
 input('tail-page-up','STANDARDSCROLL_PAGEUP')
 for i=1,5 do gui.simulateInput(view,'STANDARDSCROLL_PAGEUP');view:render(dfhack.getTickCount())end
 observe('restored-top')
 assert(list.cursor_idx==0 and scroll.scroll==0,'animal scroll did not restore top')
 local old_lift=df.global.enabler.mouse_lbut_lift
 for _,destination in ipairs{7,8,9,20,40,54,55,56,57}do
  scroll.scroll=0;scroll.scrolling=false;list.cursor_idx=0
  point(scroll.rect.x1+5,20);view:render(dfhack.getTickCount());script.sleep(2,'frames')
  point(scroll.rect.x2+2,10);df.global.enabler.mouse_lbut_lift=0
  gui.simulateInput(view,{'_MOUSE_L','_MOUSE_L_DOWN'})
  point(scroll.rect.x2+2,destination);gui.simulateInput(view,{'_MOUSE_L_DOWN'})
  observe('drag-'..destination)
  df.global.enabler.mouse_lbut_lift=1;gui.simulateInput(view,{})
 end
 df.global.enabler.mouse_lbut_lift=old_lift
 scroll.scroll=0;scroll.scrolling=false;list.cursor_idx=0
 point(scroll.rect.x1+5,20);view:render(dfhack.getTickCount());script.sleep(2,'frames')
 observe('restored-after-drag')
 gui.simulateInput(view,'_MOUSE_R');view:render(dfhack.getTickCount())
 -- Keep diagnostic items allocated until the owned session exits without saving.
 -- Closed native widgets may still retain pointers to their prior entries.
end

-- Real window closing keys are observed after the assignment fixtures finish.
pixel(336,154)
local function closing(label)
 records[#records+1]={name='animal-closing-'..label,active=main.unit_selector.flag.VISIBILITY_ACTIVE,
  selected_id=ui.cur_bld and ui.cur_bld.id or -1,focused=df.global.gview.cur_textbox~=nil,
  bottom_mode=main.bottom_mode_selected}
end
pixel(500,730);closing('focused')
animal_window_input('right-click');closing('right-click')
animal_window_input('right-click');closing('second-right-click')
if main.bottom_mode_selected==3 then pixel(336,154)end
pixel(500,730);closing('before-escape')
animal_window_input('escape');closing('escape')
capture('animal-after-real-escape')
