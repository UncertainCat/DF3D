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
  if at and at.x==p.x and at.y==p.y and at.z==p.z then pixel(g.precise_mouse_x,g.precise_mouse_y);return end
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
 for i=1,3 do view:render(dfhack.getTickCount());script.sleep(1,'frames')end
 local rows={};local list=walk(main.unit_selector,rows,0,true)
 local record={name=label,zone=ui.cur_bld and ui.cur_bld.id or -1,widgets=rows,callbacks={},entries={},assigned={}}
 if ui.cur_bld then for _,id in ipairs(ui.cur_bld.assigned_units)do record.assigned[#record.assigned+1]=id end end
 if list then
  for _,field in ipairs{'filter_func','always_sorting_by','partitions','on_select_change','preprocess_unit_func','postprocess_unit_func','preprocess_item_func','postprocess_item_func'}do record.callbacks[field]=callbacks(list[field],64)end
  record.callbacks.sorting_by=callbacks(list.sorting_by,96)
  local _,address=df.sizeof(list.is_selected);record.callbacks.is_selected=callback_at(address)
  for _,entry in ipairs(list.entry_list)do record.entries[#record.entries+1]={kind=entry.t,id=entry.t==0 and entry.u and entry.u.id or entry.t==1 and entry.i and entry.i.id or -1}end
  record.cursor=list.cursor_idx;record.query=list.filter_str
  record.hover=main.current_hover;record.hover_enabled=main.hover_instructions_on
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
    tostring(sort),tostring(descending),record.query)
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
   for key,rva in pairs{pasture=0x264aff8,pit=0x264affc,pond=0x264b000,fallback=0x2687a00,cage_base=0x2684bdc,cage_100=0x2684bd8,cage_200=0x2684be0,cage_occupied=0x2684be8,cage_occupied_100=0x2684be4,cage_occupied_200=0x2684bec}do
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
      local expected_relation=label=='Pen-status-current-chain' and status.id==chosen_status_unit and 1 or
       label=='Pen-status-pending-chain' and status.id==chosen_status_unit and 3 or
       label=='Pen-status-pending-cage' and status.id==chosen_status_unit and 4 or 2
      if expected_relation~=2 then item_id=chosen_status_item end
      assert(semantic.containment==expected_relation and semantic.item_id==item_id and item_id>=0,'native container subject differs')
     else assert(semantic.containment==0 and semantic.item_id==-1,'non-container status retained item facts') end
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
    record.item_portrait_anchors[#record.item_portrait_anchors+1]={id=row.portrait_item_id,rect={row.x,row.y,row.x2,row.y2},vtable_rva=row.vtable_rva,cells=cells,art=art}
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
    for _,guard in ipairs(guards)do
     assert(dfhack.internal.memcmp(guard.copy,guard.address,guard.size)==0,'item text reader changed native drawing/UI state')
     df.delete(guard.copy)
    end
    assert(#bytes>0 and row.x+#bytes<=g.dimx,'item text fixture must fit completely')
    for i,byte in ipairs(bytes)do
     assert(dfhack.screen.readTile(row.x+i-1,row.y-1).ch==byte,'native item text differs: '..label..' byte '..i)
    end
    record.item_text[#record.item_text+1]={id=row.item_id,bytes=bytes,exact=true,ui_unchanged=true}
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
   assert(#observed.displayed==2 and observed.displayed[1].kind==1 and observed.displayed[2].kind==1,'native item description search failed')
  end
 end
 reopen()
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
for _,probe in ipairs{{'Pen',60,402},{'Pond',60,438},{'Pond-transfer',60,438}}do
 local kind=probe[1]=='Pen' and 'Pen' or 'Pond'
 pixel(probe[2],probe[3]);mapclick(p);mapclick(p)
 assert(ui.cur_bld and ui.cur_bld.type==df.civzone_type[kind],'native animal zone creation failed: '..tostring(ui.cur_bld and df.civzone_type[ui.cur_bld.type]))
 local zone=ui.cur_bld
 pixel(304,114);capture(probe[1]..'-zone')
 pixel(336,154);local opened=capture(probe[1]..'-picker')
 if probe[1]=='Pen' or probe[1]=='Pond' then navigation(probe[1],opened) end
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
  local chain_item=df.buildingitemst:new();chain_item.item=contained:getItem();chain.contained_items:insert('#',chain_item)
  local chain_ref=df.general_ref_building_chainst:new();chain_ref.building_id=chain.id
  animal.general_refs:insert('#',chain_ref);animal.flags1.chained=true
  chosen_status_item=original_item_id
  capture('Pen-status-current-chain')
  animal.flags1.whole=original_flags
  animal.general_refs:erase(#animal.general_refs-1);chain_ref:delete()
  contained.item_id=-1
  capture('Pen-status-pending-chain')
  chain.assigned=nil
  assert(#cage.contained_items>0 and cage.contained_items[0].item,'status fixture needs installed cage item')
  chosen_status_item=cage.contained_items[0].item.id
  capture('Pen-status-pending-cage')
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
