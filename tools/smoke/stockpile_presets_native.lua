-- Protected owned lane only: pause, disable autosave, preserve save manifests,
-- and close without saving. Mutates the first pile through native clicks.
-- Run with an output directory; result.json is published atomically.
local out=...
require('gui.script').start(function()
 local records={}
 local ok,why=pcall(function()
  local json=require('json');local gui=require('gui');local g=df.global.gps
  local view=dfhack.gui.getDFViewscreen(true)
  assert(df.global.pause_state);local frame=df.global.world.frame_counter
  assert(dfhack.run_command('disable','overlay')==0)
  local b=assert(df.global.world.buildings.other.STOCKPILE[0])
  -- A loaded pile can retain oversized old filters after its raws change.
  -- Reject before copying any of those vectors; restore this unsaved setup.
  local wood={};for i,v in ipairs(b.settings.wood.mats)do wood[#wood+1]=v end
  b.settings.wood.mats:resize(65537)
  local _,oversized_code=dfhack.run_command_silent('df3d','stockpile-preset-read',tostring(b.id),'1')
  assert(oversized_code~=0,'oversized stored filter was accepted')
  assert(#b.settings.wood.mats==65537,'rejection changed stored filter')
  b.settings.wood.mats:resize(#wood);for i,v in ipairs(wood)do b.settings.wood.mats[i-1]=v end
  local point={x=b.centerx,y=b.centery,z=b.z}
  gui.simulateInput(view,'D_STOCKPILES');df.global.game.main_interface.bottom_mode_selected=-1
  dfhack.gui.revealInDwarfmodeMap(point,true);view:render(dfhack.getTickCount())
  local function click(x,y)
   g.mouse_x=x;g.mouse_y=y;g.precise_mouse_x=x*(g.screen_pixel_x//g.dimx)+4;g.precise_mouse_y=y*(g.screen_pixel_y//g.dimy)+6
   gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
  end
  local found=false
  for y=0,g.dimy-1 do for x=0,g.dimx-1 do
   g.mouse_x=x;g.mouse_y=y;g.precise_mouse_x=x*(g.screen_pixel_x//g.dimx)+4;g.precise_mouse_y=y*(g.screen_pixel_y//g.dimy)+6
   local p=dfhack.gui.getMousePos(true)
   if p and p.x==point.x and p.y==point.y and p.z==point.z then click(x,y);found=true;break end
  end if found then break end end
  assert(found,'no pile pointer');require('gui.script').sleep(2,'frames');view:render(dfhack.getTickCount())
  local lines={}
  for y=0,g.dimy-1 do local chars={};for x=0,g.dimx-1 do local t=dfhack.screen.readTile(x,y);chars[#chars+1]=(t.ch>=32 and t.ch<127)and string.char(t.ch)or' ' end;lines[#lines+1]=table.concat(chars)end
  local f=assert(io.open(out..'/screen.txt','w'));f:write(table.concat(lines,'\n'));f:close()
  local labels={'All','Animals','Food','Furniture','Corpses','Refuse','Stone','Ammo','Coins','Bars and','Gem','Finished','Leather','Cloth','Wood','Weapons','Armor','Sheets','None'}
  for preset,label in ipairs(labels)do
   local guards={}
   local function guard(address,size)
    local copy=df.new('uint8_t',size);dfhack.internal.memmove(copy,address,size)
    guards[#guards+1]={copy=copy,address=address,size=size}
   end
   local base=dfhack.internal.getImageBase()
   for _,range in ipairs{{0x234e990,0x6180},{0x2131b30,40},{0x2159084,2},{0x18adf98,8}}do guard(base+range[1],range[2])end
   local size,address=df.sizeof(df.global.game.main_interface);guard(address,size)
   size,address=df.sizeof(b);guard(address,size)
   local text,code=dfhack.run_command_silent('df3d','stockpile-preset-read',tostring(b.id),tostring(preset));assert(code==0,text)
   for _,g in ipairs(guards)do assert(dfhack.internal.memcmp(g.copy,g.address,g.size)==0,'RNG/UI/source guard changed');df.delete(g.copy)end
   local predicted=json.decode(text);local px,py
   for y,line in ipairs(lines)do local x=line:find(label,1,true);if x and x>=6 and x<=40 and y>=7 then px=x-1;py=y-1;break end end
   assert(px,'No label '..label)
   click(px-2,py)
   local errors={}
   for key,value in pairs(predicted.storage)do
    if b.storage['max_'..key]~=value then errors[#errors+1]='storage '..key end
   end
   if b.settings.flags.whole~=predicted.flags then errors[#errors+1]='flags '..b.settings.flags.whole..' vs '..predicted.flags end
   for kind,fields in pairs{vectors=predicted.vectors,fixed=predicted.fixed}do for key,values in pairs(fields)do
    local category,name=key:match('^([^%.]+)%.(.+)$');local actual=b.settings[category][name]
    if kind=='vectors' then
     if #actual~=#values then errors[#errors+1]=key..' length '..#actual..' vs '..#values else for i,v in ipairs(values)do if actual[i-1]~=v then errors[#errors+1]=key..' value '..i;break end end end
    elseif #values==1 then if actual~=values[1]then errors[#errors+1]=key end
    else for i,v in ipairs(values)do if actual[i-1]~=v then errors[#errors+1]=key..' value '..i;break end end end
   end end
   records[#records+1]={preset=preset,label=label,pointer={x=px-2,y=py},errors=errors,predicted=predicted,storage={barrels=b.storage.max_barrels,bins=b.storage.max_bins,wheelbarrows=b.storage.max_wheelbarrows}}
   assert(#errors==0,label..': '..table.concat(errors,', '))
  end
  -- Native list oracle: select the Wood preset, open Custom, select Wood.
  -- Runtime probe uses only its own settings/list storage; native UI is test-only.
  local function label_click(label,offset,column)
   local screen={};local px,py
   for y=0,g.dimy-1 do
    local chars={};for x=0,g.dimx-1 do local t=dfhack.screen.readTile(x,y);chars[#chars+1]=(t.ch>=32 and t.ch<127)and string.char(t.ch)or' ' end
    local line=table.concat(chars);screen[#screen+1]=line
    local x=line:find(label,column==3 and 75 or column==2 and 40 or 1,true)
    local in_column=x and (column==3 and x>=75 or column==2 and x>=40 and x<75 or not column and x<40)
    if in_column and not px then px=x-1+(offset or 0);py=y end
   end
   if px then
    if column==3 then
     local f=assert(io.open(out..'/bulk-screen.txt','w'));f:write(table.concat(screen,'\n'));f:close()
    end
    click(px,py);return {x=px,y=py}
   end
   local custom=df.global.game.main_interface.custom_stockpile
   if not column and custom.open and custom.scroll_position_main==0 then
    -- Oracle-only viewport setup; selection itself still uses the native click.
    custom.scroll_position_main=4;view:render(dfhack.getTickCount())
    return label_click(label,offset,column)
   end
   local f=assert(io.open(out..'/missing-'..label..'.txt','w'));f:write(table.concat(screen,'\n'));f:close()
   error('Native label absent: '..label)
  end
  label_click('Wood',-2)
  -- Keep populated/selected Wood filters but disable its category. Native
  -- selection must initialize and clear it, rather than merely setting the bit.
  b.settings.flags.wood=false
  label_click('Custom',-2)
  local category_text,category_code=dfhack.run_command_silent('df3d','stockpile-category-read',tostring(b.id),'8192')
  assert(category_code==0,category_text)
  assert(not b.settings.flags.wood,'category probe published its prediction')
  local category_prediction=json.decode(category_text)
  label_click('Wood')
  local c=df.global.game.main_interface.custom_stockpile
  assert(c.open and c.cur_main_mode==df.stockpile_list.Wood,'native Wood selection failed')
  assert(b.settings.flags.whole==category_prediction.flags,'category activation flags')
  for kind,fields in pairs{vectors=category_prediction.vectors,fixed=category_prediction.fixed}do
   for key,values in pairs(fields)do
    local cat,name=key:match('^([^%.]+)%.(.+)$');local actual=b.settings[cat][name]
    if kind=='vectors'then assert(#actual==#values,'category length '..key)end
    if kind=='fixed' and #values==1 then assert(actual==values[1],'category '..key)
    else for i,value in ipairs(values)do assert(actual[i-1]==value,'category value '..key..' '..i)end end
   end
  end
  records[#records+1]={probe='wood_category_activation',predicted=category_prediction}
  local function native_rows()
   local result={}
   for i=0,c.cur_spec_item_sz-1 do
    local row=c.spec_item[i]
    result[#result+1]={name=dfhack.df2utf(row.name),visible=row.on}
   end
   return json.encode(result)
  end
  local native_before=native_rows()
  local wood_before={};for _,v in ipairs(b.settings.wood.mats)do wood_before[#wood_before+1]=v end
  local size,address=df.sizeof(df.global.game.main_interface)
  local saved=df.new('uint8_t',size);dfhack.internal.memmove(saved,address,size)
  local rng={};local base=dfhack.internal.getImageBase()
  for _,range in ipairs{{0x234e990,0x6180},{0x2131b30,40},{0x2159084,2},{0x18adf98,8}}do
   local copy=df.new('uint8_t',range[2]);dfhack.internal.memmove(copy,base+range[1],range[2])
   rng[#rng+1]={copy=copy,address=base+range[1],size=range[2]}
  end
  local text,code=dfhack.run_command_silent('df3d','stockpile-wood-read',tostring(b.id))
  assert(code==0,text)
  assert(dfhack.internal.memcmp(saved,address,size)==0,'Wood probe changed native UI');df.delete(saved)
  for _,guard in ipairs(rng)do assert(dfhack.internal.memcmp(guard.copy,guard.address,guard.size)==0,'Wood probe changed RNG');df.delete(guard.copy)end
  assert(native_rows()==native_before,'Wood probe changed native rows')
  assert(#b.settings.wood.mats==#wood_before,'Wood probe changed source length')
  for i,v in ipairs(wood_before)do assert(b.settings.wood.mats[i-1]==v,'Wood probe changed source value')end
  local predicted=json.decode(text);assert(#predicted==c.cur_spec_item_sz,'Wood row count')
  for i,row in ipairs(predicted)do
   local actual=c.spec_item[i-1]
   assert(row.name==dfhack.df2utf(actual.name),'Wood row name/order '..i)
   assert(row.visible==actual.on,'Wood row visibility '..i)
   assert(row.enabled==(b.settings.wood.mats[row.index]~=0),'Wood row selection '..i)
  end
  records[#records+1]={probe='wood_rows',rows=predicted}
  local categories={'animals','food','furniture','corpses','refuse','stone','ammo','coins',
   'bars_blocks','gems','finished_goods','leather','cloth','wood','weapons','armor','sheet'}
  local category_labels={'Animals','Food','Furniture/siege ammo','Corpses','Refuse','Stone','Ammo','Coins',
   'Bars/blocks','Gems','Finished goods','Leather','Cloth','Wood','Weapons/trap comps','Armor','Sheet'}
  local modes={0,1,21,28,29,39,44,50,51,57,63,72,75,85,86,94,106}
  local function compare_settings(expected)
   assert(b.settings.flags.whole==expected.flags,'activation flags')
   for kind,fields in pairs{vectors=expected.vectors,fixed=expected.fixed}do
    for key,values in pairs(fields)do
     local cat,name=key:match('^([^%.]+)%.(.+)$');local actual=b.settings[cat][name]
     if kind=='vectors'then assert(#actual==#values,'activation length '..key)end
     if kind=='fixed' and #values==1 then assert(actual==values[1],'activation '..key)
     else for i,value in ipairs(values)do assert(actual[i-1]==value,'activation '..key..' '..i)end end
    end
   end
  end
  for bit,key in ipairs(categories)do
   for _,enabled in ipairs{false,true}do
    b.settings.flags[key]=enabled
    c.scroll_position_main=0;view:render(dfhack.getTickCount())
    local size,address=df.sizeof(df.global.game.main_interface)
    local guard=df.new('uint8_t',size);dfhack.internal.memmove(guard,address,size)
    local text,code=dfhack.run_command_silent('df3d','stockpile-category-read',tostring(b.id),tostring(1 << (bit-1)))
    assert(code==0,text)
    assert(dfhack.internal.memcmp(guard,address,size)==0,'activation probe changed native interface');df.delete(guard)
    assert(b.settings.flags[key]==enabled,'activation probe published flag')
    local expected=json.decode(text)
    label_click(category_labels[bit])
    assert(c.cur_main_mode==modes[bit],'wrong category selected: '..key)
    compare_settings(expected)
    records[#records+1]={probe='category_activation',category=key,was_enabled=enabled,predicted=expected}
   end
  end
  c.scroll_position_main=0;view:render(dfhack.getTickCount());label_click('Wood')
  for _,query in ipairs{'maple','TREE','zzzznomatch'}do
   -- Oracle-only focus setup; DF's actual text-input handler performs filtering.
   c.spec_filter='';c.entering_spec_filter=true
   for i=1,#query do
    df.global.enabler.last_text_input[0]=query:byte(i);df.global.enabler.last_text_input[1]=0
    gui.simulateInput(view,string.format('STRING_A%03d',query:byte(i)))
   end
   view:render(dfhack.getTickCount())
   assert(c.spec_filter:lower()==query:lower(),'native search input differs: '..tostring(c.spec_filter)..' / '..query)
   local size,address=df.sizeof(df.global.game.main_interface)
   local guard=df.new('uint8_t',size);dfhack.internal.memmove(guard,address,size)
   local text,code=dfhack.run_command_silent('df3d','stockpile-wood-read',tostring(b.id),query)
   assert(code==0,text)
   assert(dfhack.internal.memcmp(guard,address,size)==0,'search probe changed native UI');df.delete(guard)
   local rows=json.decode(text);assert(#rows==c.cur_spec_item_sz,'filtered row count')
   for i,row in ipairs(rows)do
    local actual=c.spec_item[i-1]
    assert(row.name==dfhack.df2utf(actual.name) and row.visible==actual.on,'native search row differs '..i)
   end
   records[#records+1]={probe='wood_search',query=query,native_query=c.spec_filter,rows=rows}
  end
  c.entering_spec_filter=false;c.spec_filter=''
  for _,category in ipairs{{'Furniture/siege ammo','furniture',26,27},{'Ammo','ammo',48,49},
   {'Finished goods','finished_goods',69,70},{'Weapons/trap comps','weapons',92,93},{'Armor','armor',103,104}}do
   c.scroll_position_main=0;view:render(dfhack.getTickCount());label_click(category[1])
   for quality=1,2 do
    local field=quality==1 and 'quality_core' or 'quality_total'
    local values=b.settings[category[2]][field]
    for i=0,#values-1 do values[i]=(i%2)==quality-1 end
    label_click(quality==1 and 'Core quality' or 'Total quality',0,2)
    assert(c.cur_sub_mode==category[quality+2],'native quality selection differs')
    local size,address=df.sizeof(df.global.game.main_interface)
    local guard=df.new('uint8_t',size);dfhack.internal.memmove(guard,address,size)
    local text,code=dfhack.run_command_silent('df3d','stockpile-rows-read',tostring(b.id),tostring(category[quality+2]))
    assert(code==0,text)
    assert(dfhack.internal.memcmp(guard,address,size)==0,'quality probe changed native UI');df.delete(guard)
    local rows=json.decode(text);assert(#rows==c.cur_spec_item_sz,'quality row count')
    for i,row in ipairs(rows)do
     local actual=c.spec_item[i-1]
     assert(row.name==dfhack.df2utf(actual.name) and row.visible==actual.on,'quality name/order '..i)
     assert(row.field==category[2]..'.'..field and row.index==i-1,'quality setting identity')
     assert(row.enabled==values[row.index],'quality setting value')
    end
    records[#records+1]={probe='quality_rows',mode=category[quality+2],rows=rows}
   end
  end
  for _,entry in ipairs{
   {'Furniture/siege ammo','Other materials','furniture.other_mats',25},
   {'Ammo','Other materials','ammo.other_mats',46},
   {'Bars/blocks','Bars: other materials','bars_blocks.bars_other_mats',53},
   {'Bars/blocks','Blocks: other materials','bars_blocks.blocks_other_mats',56},
   {'Finished goods','Other materials','finished_goods.other_mats',68},
   {'Weapons/trap comps','Other materials','weapons.other_mats',91},
   {'Armor','Other materials','armor.other_mats',102}}do
   c.entering_spec_filter=false;c.spec_filter='';c.scroll_position_main=0
   view:render(dfhack.getTickCount());label_click(entry[1])
   local category,field=entry[3]:match('^([^%.]+)%.(.+)$')
   local values=b.settings[category][field]
   for i=0,#values-1 do values[i]=i%2 end
   label_click(entry[2],0,2)
   assert(c.cur_sub_mode==entry[4],'native Other-material selection differs')
   for _,query in ipairs{'','a','zzzznomatch'}do
    c.spec_filter='';c.entering_spec_filter=true
    for i=1,#query do
     df.global.enabler.last_text_input[0]=query:byte(i);df.global.enabler.last_text_input[1]=0
     gui.simulateInput(view,string.format('STRING_A%03d',query:byte(i)))
    end
    view:render(dfhack.getTickCount());assert(c.spec_filter:lower()==query,'native filter differs')
    local size,address=df.sizeof(df.global.game.main_interface)
    local guard=df.new('uint8_t',size);dfhack.internal.memmove(guard,address,size)
    local text,code=dfhack.run_command_silent('df3d','stockpile-rows-read',tostring(b.id),tostring(entry[4]),query)
    assert(code==0,text)
    assert(dfhack.internal.memcmp(guard,address,size)==0,'Other-material probe changed native UI');df.delete(guard)
    local rows=json.decode(text);assert(#rows==c.cur_spec_item_sz,'Other-material row count')
    for i,row in ipairs(rows)do
     local actual=c.spec_item[i-1]
     assert(row.name==dfhack.df2utf(actual.name) and row.visible==actual.on,'Other-material name/order/filter '..i)
     assert(row.field==entry[3] and row.index>=0 and row.index<#values,'Other-material setting identity')
     local _,expected_pointer=df.sizeof(values:_field(row.index))
     local _,actual_pointer=df.sizeof(actual.set_pointer)
     assert(actual_pointer==expected_pointer,'Other-material setting pointer')
     assert(row.enabled==(values[row.index]~=0),'Other-material setting value')
    end
    records[#records+1]={probe='other_material_rows',mode=entry[4],query=query,rows=rows}
    -- Leave oracle typing focus before testing actual button effects.
    c.entering_spec_filter=false
    for _,action in ipairs{{'All',1},{'None',0}}do
     local expected={};for i,v in ipairs(values)do expected[i]=v end
     for _,row in ipairs(rows)do if row.visible then expected[row.index]=action[2]end end
     local pointer=label_click(action[1],0,3)
     local differences={}
     for i,v in ipairs(values)do if v~=expected[i] then differences[#differences+1]={index=i,actual=v,expected=expected[i]}end end
     records[#records+1]={probe='other_material_action',mode=entry[4],query=query,action=action[1],pointer=pointer,differences=differences}
     assert(#differences==0,'native filtered action changed unexpected row '..json.encode(differences))
    end
   end
   local original={};for _,v in ipairs(values)do original[#original+1]=v end
   values:resize(0);c.spec_filter='';c.entering_spec_filter=false
   -- A repeated click on the already selected submode keeps native's cached
   -- rows. Leave and re-enter after this test-only external vector change.
   local alternate=(entry[4]==53 or entry[4]==56) and 'Bars: metal' or entry[4]==91 and 'Weapons' or entry[4]==102 and 'Body' or 'Type'
   label_click(alternate,0,2)
   label_click(entry[2],0,2);assert(c.cur_spec_item_sz==0,'native empty vector has rows')
   label_click('All',0,3);assert(#values==0,'native All resized empty vector')
   label_click('None',0,3);assert(#values==0,'native None resized empty vector')
   records[#records+1]={probe='other_material_empty',mode=entry[4],stored_count=#values}
   values:resize(#original);for i,v in ipairs(original)do values[i-1]=v end
  end
  local function settings_snapshot(v)
   if type(v)~='userdata' then return tostring(v)end
   local parts={}
   for key,value in pairs(v)do
    if type(value)~='function' and tostring(key):sub(1,1)~='_' then parts[#parts+1]=tostring(key)..'='..settings_snapshot(value)end
   end
   table.sort(parts);return '{'..table.concat(parts,';')..'}'
  end
  for _,entry in ipairs{{'Finished goods','finished_goods',71,'Type'},
   {'Leather','leather',74,'Type'},{'Cloth','cloth',84,'Thread (silk)'},{'Armor','armor',105,'Body'},
   {'Ammo','ammo',45,'Metal','type','ammo','Type'},
   {'Weapons/trap comps','weapons',87,'Metal','weapon_type','weapons','Weapons'},
   {'Weapons/trap comps','weapons',88,'Metal','trapcomp_type','trapcomps','Trap components'},
   {'Armor','armor',95,'Metal','body','armor','Body'},
   {'Armor','armor',96,'Metal','head','helms','Head'},
   {'Armor','armor',97,'Metal','feet','shoes','Feet'},
   {'Armor','armor',98,'Metal','hands','gloves','Hands'},
   {'Armor','armor',99,'Metal','legs','pants','Legs'},
   {'Armor','armor',100,'Metal','shield','shields','Shield'}}do
   c.entering_spec_filter=false;c.spec_filter='';c.scroll_position_main=0
   view:render(dfhack.getTickCount());label_click(entry[1])
   local field=entry[5] or 'color';local probe=entry[5] and 'itemdef' or 'color'
   local values=b.settings[entry[2]][field];local original={}
   for _,v in ipairs(values)do original[#original+1]=v end
   local raw_count=entry[6] and #df.global.world.raws.itemdefs[entry[6]] or #df.global.world.raws.descriptors.colors
   -- Do not select the native list with this deliberately stale length. Only the
   -- owned service may be asked: it must reject before the unchecked getter.
   values:resize(raw_count+1)
   local before=settings_snapshot(b.settings)
   local _,code=dfhack.run_command_silent('df3d','stockpile-rows-read',tostring(b.id),tostring(entry[3]))
   assert(code~=0 and settings_snapshot(b.settings)==before,'stale typed vector was accepted or changed')
   records[#records+1]={probe=probe..'_bounds',mode=entry[3],stored_count=#values,raw_count=raw_count,rejected=true}
   for _,count in ipairs{raw_count,1,0}do
    c.spec_filter='';c.entering_spec_filter=false
    values:resize(count);for i=0,count-1 do values[i]=i%2 end
    -- Rebuild after oracle-only settings changes; a repeated sublist click
    -- intentionally keeps native's existing rows.
    label_click(entry[4],0,2);label_click(entry[7] or 'Color',0,2)
    assert(c.cur_sub_mode==entry[3],'wrong Typed list mode')
    for _,query in ipairs{'',entry[5] and 'a' or 'blue','zzzznomatch'}do
     c.spec_filter='';c.entering_spec_filter=true
     for i=1,#query do
      df.global.enabler.last_text_input[0]=query:byte(i);df.global.enabler.last_text_input[1]=0
      gui.simulateInput(view,string.format('STRING_A%03d',query:byte(i)))
     end
     c.entering_spec_filter=false;view:render(dfhack.getTickCount())
     local before=settings_snapshot(b.settings)
     local size,address=df.sizeof(df.global.game.main_interface)
     local guard=df.new('uint8_t',size);dfhack.internal.memmove(guard,address,size)
     local text,code=dfhack.run_command_silent('df3d','stockpile-rows-read',tostring(b.id),tostring(entry[3]),query)
     assert(code==0,text)
     assert(dfhack.internal.memcmp(guard,address,size)==0,'Typed list probe changed UI');df.delete(guard)
     assert(settings_snapshot(b.settings)==before,'Typed list probe changed settings')
     local rows=json.decode(text);assert(#rows==c.cur_spec_item_sz,'Typed list row count')
     for i,row in ipairs(rows)do
      local native=c.spec_item[i-1]
      local _,expected_pointer=df.sizeof(values:_field(row.index));local _,actual_pointer=df.sizeof(native.set_pointer)
      assert(row.field==entry[2]..'.'..field and expected_pointer==actual_pointer,'Typed list identity')
      assert(row.name==dfhack.df2utf(native.name) and row.visible==native.on,'Typed list labels/order/search')
      assert(row.enabled==(values[row.index]~=0),'Typed list selection')
     end
     for _,action in ipairs{{'All',1},{'None',0}}do
      local expected={};for i,v in ipairs(values)do expected[i]=v end
      for _,row in ipairs(rows)do if row.visible then expected[row.index]=action[2]end end
      label_click(action[1],0,3);assert(#values==count,'Typed list bulk action resized vector')
      for i,v in ipairs(values)do assert(v==expected[i],'Typed list bulk action changed hidden row')end
     end
     records[#records+1]={probe=probe..'_rows',mode=entry[3],stored_count=count,query=query,rows=rows,bulk_actions=2}
    end
   end
   values:resize(#original);for i,v in ipairs(original)do values[i-1]=v end
  end
  -- Organic native UI references and independently owned provider comparisons.
  for _,entry in ipairs{{'Food','food','meat',2,'Meat',0},
   {'Food','food','fish',3,'Fish',1},
   {'Food','food','unprepared_fish',4,'Unprepared fish',2},
   {'Food','food','egg',5,'Egg',3},
   {'Food','food','plants',6,'Plants',4},
   {'Food','food','drink_plant',7,'Drink (plant)',5},
   {'Food','food','drink_animal',8,'Drink (animal)',6},
   {'Food','food','cheese_plant',9,'Cheese (plant)',7},
   {'Food','food','cheese_animal',10,'Cheese (animal)',8},
   {'Food','food','seeds',11,'Seeds',9},
   {'Food','food','leaves',12,'Fruit/leaves',10},
   {'Food','food','powder_plant',13,'Milled plant',11},
   {'Food','food','powder_creature',14,'Bone meal',12},
   {'Food','food','glob',15,'Fat',13},
   {'Food','food','glob_paste',16,'Paste',33},
   {'Food','food','glob_pressed',17,'Pressed material',34},
   {'Food','food','liquid_plant',18,'Extract (plant)',14},
   {'Food','food','liquid_animal',19,'Extract (animal)',15},
   {'Food','food','liquid_misc',20,'Misc. liquid',16},
   {'Leather','leather','mats',73,'Type',17},
   {'Cloth','cloth','thread_silk',76,'Thread (silk)',18},
   {'Cloth','cloth','thread_plant',77,'Thread (plant)',19},
   {'Cloth','cloth','thread_yarn',78,'Thread (yarn)',35},
   {'Cloth','cloth','thread_metal',79,'Thread (metal)',36},
   {'Cloth','cloth','cloth_silk',80,'Cloth (silk)',18},
   {'Cloth','cloth','cloth_plant',81,'Cloth (plant)',19},
   {'Cloth','cloth','cloth_yarn',82,'Cloth (yarn)',35},
   {'Cloth','cloth','cloth_metal',83,'Cloth (metal)',36},
   {'Sheet','sheet','paper',107,'Paper',37},
   {'Sheet','sheet','parchment',108,'Parchment',38}}do
   c.entering_spec_filter=false;c.spec_filter='';c.scroll_position_main=0;c.scroll_position_sub=0
   view:render(dfhack.getTickCount());label_click(entry[1])
   local values=b.settings[entry[2]][entry[3]];local original={}
   for _,v in ipairs(values)do original[#original+1]=v end
   local types=df.global.world.raws.mat_table.organic_types[entry[6]]
   local indexes=df.global.world.raws.mat_table.organic_indexes[entry[6]]
   assert(#types==#indexes,'organic paired arrays differ')
   local pairs={};for i,t in ipairs(types)do pairs[#pairs+1]={type=t,index=indexes[i]}end
   -- Reserve before rebuilding UI pointers; short probes never render the UI.
   values:resize(math.max(#original,#types+1));values:resize(#original)
   for i,v in ipairs(original)do values[i-1]=v end
   c.scroll_position_main=0;view:render(dfhack.getTickCount());label_click('Ammo');label_click(entry[1])
   local function compare_provider(rows,query,count)
    local saved={};for _,v in ipairs(values)do saved[#saved+1]=v end
    values:resize(count);for i=0,count-1 do values[i]=i<#saved and saved[i+1] or 9 end
    local before=settings_snapshot(b.settings)
    local size,address=df.sizeof(df.global.game.main_interface)
    local guard=df.new('uint8_t',size);dfhack.internal.memmove(guard,address,size)
    local text,code=dfhack.run_command_silent('df3d','stockpile-rows-read',tostring(b.id),tostring(entry[4]),query)
    assert(code==0,text)
    assert(dfhack.internal.memcmp(guard,address,size)==0,'organic provider changed UI');df.delete(guard)
    assert(settings_snapshot(b.settings)==before,'organic provider changed settings')
    local actual=json.decode(text);local expected={}
    for _,row in ipairs(rows)do if row.index<count then expected[#expected+1]=row end end
    assert(#actual==#expected,'organic provider row count '..entry[4])
    for i,row in ipairs(actual)do
     local e=expected[i]
     if not(row.field==e.field and row.index==e.index and row.name==e.name and row.visible==e.visible)then
      local f=assert(io.open(out..'/organic-mismatch.json','w'));f:write(json.encode{mode=entry[4],query=query,count=count,ordinal=i,actual=row,expected=e,actual_rows=actual,expected_rows=expected});f:close()
      error('organic row mismatch '..entry[4])
     end
     assert(row.enabled==(values[row.index]~=0),'organic selection mismatch')
    end
    records[#records+1]={probe='organic_provider',mode=entry[4],stored_count=count,query=query,rows=actual}
    values:resize(#saved);for i,v in ipairs(saved)do values[i-1]=v end
   end

   if #values==0 then
    compare_provider({},'',0);compare_provider({},'',#types+1)
    records[#records+1]={probe='organic_reference_empty',mode=entry[4],field=entry[2]..'.'..entry[3],stored_count=0,materials=pairs}
   else
    -- A parent category also sorts after its default leaf returns. Switch
    -- away first so this oracle compares one explicit native leaf rebuild.
    if c.cur_sub_mode==entry[4]then
     c.scroll_position_sub=0;view:render(dfhack.getTickCount())
     label_click(entry[2]=='food' and 'Fish' or entry[2]=='sheet' and 'Parchment' or 'Color',0,2)
    end
    local sub_index
    for i,mode in ipairs(c.sub_mode)do if mode==entry[4]then sub_index=i;break end end
    assert(sub_index,'organic sublist absent')
    c.scroll_position_sub=math.max(0,sub_index-5);view:render(dfhack.getTickCount());label_click(entry[5],0,2)
    assert(c.cur_sub_mode==entry[4],'wrong organic mode')
    local pointers={};for i=0,#values-1 do local _,address=df.sizeof(values:_field(i));pointers[address]=i end
    for _,query in ipairs{'','a','zzzznomatch'}do
     c.spec_filter='';c.entering_spec_filter=true
     for i=1,#query do
      df.global.enabler.last_text_input[0]=query:byte(i);df.global.enabler.last_text_input[1]=0
      gui.simulateInput(view,string.format('STRING_A%03d',query:byte(i)))
     end
     c.entering_spec_filter=false;view:render(dfhack.getTickCount())
     local rows={}
     for i=0,c.cur_spec_item_sz-1 do
      local native=c.spec_item[i];local _,address=df.sizeof(native.set_pointer)
      local index=assert(pointers[address],'organic row outside stored settings')
      rows[#rows+1]={field=entry[2]..'.'..entry[3],index=index,name=dfhack.df2utf(native.name),visible=native.on,enabled=values[index]~=0}
     end
     for _,count in ipairs{#original,1,0,#types+1}do compare_provider(rows,query,count)end
     for _,action in ipairs{{'All',1},{'None',0}}do
      local expected={};for i,v in ipairs(values)do expected[i]=v end
      for _,row in ipairs(rows)do if row.visible then expected[row.index]=action[2]end end
      label_click(action[1],0,3);assert(#values==#original,'organic action resized vector')
      for i,v in ipairs(values)do assert(v==expected[i],'organic action changed excluded row')end
     end
     records[#records+1]={probe='organic_reference',mode=entry[4],stored_count=#values,query=query,rows=rows,materials=pairs,bulk_actions=2}
    end
   end
   for i,v in ipairs(original)do values[i-1]=v end
  end
  for _,entry in ipairs{{'Stone','stone','mats',40,'Metal ores','stone','Economic'},
   {'Stone','stone','mats',41,'Economic','stone','Metal ores'},
   {'Stone','stone','mats',42,'Other stone','stone','Metal ores'},
   {'Stone','stone','mats',43,'Clay','stone','Metal ores'},
   {'Gems','gems','rough_mats',60,'Rough gem','gem','Cut gem'},
   {'Gems','gems','cut_mats',61,'Cut gem','gem','Rough gem'},
   {'Gems','gems','cut_mats',62,'Cut stone','gem','Rough gem'},
   {'Furniture','furniture','mats',23,'Stone/clay','inorganic','Type'},
   {'Furniture','furniture','mats',24,'Metal','inorganic','Type'},
   {'Ammo','ammo','mats',47,'Metal','inorganic','Type'},
   {'Coins','coins','mats',50,nil,'inorganic'},
   {'Bars/blocks','bars_blocks','bars_mats',52,'Bars: metal','inorganic','Bars: other materials'},
   {'Bars/blocks','bars_blocks','blocks_mats',54,'Blocks: stone/clay','inorganic','Bars: other materials'},
   {'Bars/blocks','bars_blocks','blocks_mats',55,'Blocks: metal','inorganic','Bars: other materials'},
   {'Finished goods','finished_goods','mats',65,'Stone/clay','inorganic','Type'},
   {'Finished goods','finished_goods','mats',66,'Metal','inorganic','Type'},
   {'Finished goods','finished_goods','mats',67,'Gem','inorganic','Type'},
   {'Weapons/trap comps','weapons','mats',89,'Metal','inorganic','Weapons'},
   {'Weapons/trap comps','weapons','mats',90,'Stone','inorganic','Weapons'},
   {'Armor','armor','mats',101,'Metal','inorganic','Body'},
   {'Wood','wood','mats',85},{'Animals','animals','enabled',0},{'Corpses','corpses','corpses',28},
   {'Refuse','refuse','corpses',31,'Corpses'},{'Refuse','refuse','body_parts',32,'Body parts'},
   {'Refuse','refuse','skulls',33,'Skulls'},{'Refuse','refuse','bones',34,'Bones'},
   {'Refuse','refuse','shells',35,'Shells'},{'Refuse','refuse','teeth',36,'Teeth'},
   {'Refuse','refuse','horns',37,'Horns/hooves'},{'Refuse','refuse','hair',38,'Hair/wool'}}do
   c.entering_spec_filter=false;c.spec_filter='';c.scroll_position_main=0
   view:render(dfhack.getTickCount());label_click(entry[1])
   local values=b.settings[entry[2]][entry[3]];local original={}
   for _,v in ipairs(values)do original[#original+1]=v end
   local wood=entry[4]==85;local inorganic=entry[6]=='inorganic';local gem=entry[6]=='gem';local stone=entry[6]=='stone'
   local raw_count=(inorganic or gem or stone) and #df.global.world.raws.inorganics.all or wood and #df.global.world.raws.plants.all or #df.global.world.raws.creatures.all
   for _,count in ipairs{raw_count,1,0,raw_count+1}do
    c.spec_filter='';c.entering_spec_filter=false
    values:resize(count);for i=0,count-1 do values[i]=i%2 end
    if entry[5] then label_click(entry[7] or 'Item types',0,2);label_click(entry[5],0,2)
    else
     c.scroll_position_main=0;view:render(dfhack.getTickCount());label_click('Ammo');label_click(entry[1])
    end
    assert((entry[5] and c.cur_sub_mode or c.cur_main_mode)==entry[4],'wrong creature mode')
    for _,query in ipairs{'',stone and 'ite' or gem and 'quartz' or inorganic and 'iron' or wood and 'maple' or 'aard','zzzznomatch'}do
     c.spec_filter='';c.entering_spec_filter=true
     for i=1,#query do
      df.global.enabler.last_text_input[0]=query:byte(i);df.global.enabler.last_text_input[1]=0
      gui.simulateInput(view,string.format('STRING_A%03d',query:byte(i)))
     end
     c.entering_spec_filter=false;view:render(dfhack.getTickCount())
     local before=settings_snapshot(b.settings)
     local size,address=df.sizeof(df.global.game.main_interface)
     local guard=df.new('uint8_t',size);dfhack.internal.memmove(guard,address,size)
     local text,code=dfhack.run_command_silent('df3d','stockpile-rows-read',tostring(b.id),tostring(entry[4]),query)
     assert(code==0,text)
     assert(dfhack.internal.memcmp(guard,address,size)==0,'creature probe changed UI');df.delete(guard)
     assert(settings_snapshot(b.settings)==before,'creature probe changed settings')
     local rows=json.decode(text);assert(#rows==c.cur_spec_item_sz,'creature row count')
     for i,row in ipairs(rows)do
      local native=c.spec_item[i-1]
      local _,expected_pointer=df.sizeof(values:_field(row.index));local _,actual_pointer=df.sizeof(native.set_pointer)
      assert(row.field==entry[2]..'.'..entry[3] and expected_pointer==actual_pointer,'creature identity')
      assert(row.name==dfhack.df2utf(native.name) and row.visible==native.on,'creature labels/order/search')
      assert(row.enabled==(values[row.index]~=0),'creature selection')
     end
     for _,action in ipairs{{'All',1},{'None',0}}do
      local expected={};for i,v in ipairs(values)do expected[i]=v end
      for _,row in ipairs(rows)do if row.visible then expected[row.index]=action[2]end end
      label_click(action[1],0,3);assert(#values==count,'creature action resized vector')
      for i,v in ipairs(values)do assert(v==expected[i],'creature action changed excluded row')end
     end
     records[#records+1]={probe=stone and 'stone_rows' or gem and 'gem_rows' or inorganic and 'inorganic_rows' or wood and 'wood_leaf_rows' or 'creature_rows',mode=entry[4],stored_count=count,raw_count=raw_count,query=query,rows=rows,bulk_actions=2}
    end
   end
   values:resize(#original);for i,v in ipairs(original)do values[i-1]=v end
  end
  -- Fixed-index branches need full native UI backing. Provider-only probes
  -- exercise short vectors; Refuse also embeds two scalar settings.
  for _,entry in ipairs{{'Gems','gems',58,659,'Rough glass','rough_other_mats'},
   {'Gems','gems',59,659,'Cut glass','cut_other_mats'},{'Furniture','furniture',22,35,'Type'},
   {'Finished goods','finished_goods',64,93,'Type'},{'Refuse','refuse',30,93,'Item types'}}do
   c.entering_spec_filter=false;c.spec_filter='';c.scroll_position_main=0
   view:render(dfhack.getTickCount());label_click('Ammo')
   local leaf=entry[6] or 'type';local values=b.settings[entry[2]][leaf];local original={}
   for _,v in ipairs(values)do original[#original+1]=v end
   local fresh,rotten=b.settings.refuse.fresh_raw_hide,b.settings.refuse.rotten_raw_hide
   values:resize(entry[4]+1);values:resize(entry[4]);for i=0,#values-1 do values[i]=i%2 end
   label_click(entry[1])
   label_click(entry[5],0,2)
   assert(c.cur_sub_mode==entry[3],'wrong item-type mode')
   local pointers={}
   for i=0,#values-1 do
    local _,address=df.sizeof(values:_field(i));pointers[address]={field=entry[2]..'.'..leaf,index=i}
   end
   if entry[3]==30 then
    for _,field in ipairs{'fresh_raw_hide','rotten_raw_hide'}do
     local _,address=df.sizeof(b.settings.refuse:_field(field));pointers[address]={field='refuse.'..field,index=0}
    end
   end
   for _,query in ipairs{'','a','zzzznomatch'}do
    c.spec_filter='';c.entering_spec_filter=true
    for i=1,#query do
     df.global.enabler.last_text_input[0]=query:byte(i);df.global.enabler.last_text_input[1]=0
     gui.simulateInput(view,string.format('STRING_A%03d',query:byte(i)))
    end
    c.entering_spec_filter=false;view:render(dfhack.getTickCount())
    local rows={}
    for i=0,c.cur_spec_item_sz-1 do
     local native=c.spec_item[i];local _,address=df.sizeof(native.set_pointer)
     local identity=assert(pointers[address],'unknown item-type pointer')
     rows[#rows+1]={field=identity.field,index=identity.index,name=dfhack.df2utf(native.name),visible=native.on}
    end
    for _,action in ipairs{{'All',1},{'None',0}}do
     local expected={};for i,v in ipairs(values)do expected[i]=v end
     local ef,er=b.settings.refuse.fresh_raw_hide,b.settings.refuse.rotten_raw_hide
     for _,row in ipairs(rows)do if row.visible then
      if row.field==entry[2]..'.'..leaf then expected[row.index]=action[2]
      elseif row.field=='refuse.fresh_raw_hide' then ef=action[2]==1
      elseif row.field=='refuse.rotten_raw_hide' then er=action[2]==1 end
     end end
     label_click(action[1],0,3)
     assert(#values==entry[4],'item-type action resized vector')
     for i,v in ipairs(values)do assert(v==expected[i],'item-type action changed excluded row')end
     assert(b.settings.refuse.fresh_raw_hide==ef and b.settings.refuse.rotten_raw_hide==er,'item-type scalar effect')
    end
    -- Only the owned provider sees short vectors: the native UI builder uses
    -- unchecked fixed indices and must retain full backing storage.
    local saved={};for _,v in ipairs(values)do saved[#saved+1]=v end
    for _,count in ipairs(entry[6] and {entry[4],4,1,0,entry[4]+1} or {entry[4],1,0,entry[4]+1})do
     values:resize(count)
     for j=0,count-1 do values[j]=j<#saved and saved[j+1] or 9 end
     local before=settings_snapshot(b.settings)
     local size,address=df.sizeof(df.global.game.main_interface)
     local guard=df.new('uint8_t',size);dfhack.internal.memmove(guard,address,size)
     local text,code=dfhack.run_command_silent('df3d','stockpile-rows-read',tostring(b.id),tostring(entry[3]),query)
     assert(code==0,text)
     assert(dfhack.internal.memcmp(guard,address,size)==0,'item-type provider changed UI');df.delete(guard)
     assert(settings_snapshot(b.settings)==before,'item-type provider changed settings')
     local actual=json.decode(text);local expected={}
     for _,row in ipairs(rows)do if row.field~=entry[2]..'.'..leaf or row.index<count then expected[#expected+1]=row end end
     assert(#actual==#expected,'item-type provider row count')
     for j,row in ipairs(actual)do
      local e=expected[j]
      assert(row.field==e.field and row.index==e.index and row.name==e.name and row.visible==e.visible,'item-type provider row identity/order/search')
      local category,field=row.field:match('^([^%.]+)%.(.+)$')
      local v=b.settings[category][field];local enabled=type(v)=='boolean' and v or type(v)~='boolean' and v[row.index]~=0
      assert(row.enabled==enabled,'item-type provider state')
     end
     records[#records+1]={probe=entry[6] and 'glass_provider' or 'itemtype_provider',mode=entry[3],stored_count=count,query=query,rows=actual}
    end
    values:resize(#saved);for j,v in ipairs(saved)do values[j-1]=v end
    records[#records+1]={probe=entry[6] and 'glass_reference' or 'itemtype_reference',mode=entry[3],stored_count=#values,query=query,rows=rows,bulk_actions=2}
   end
   values:resize(#original);for i,v in ipairs(original)do values[i-1]=v end
   b.settings.refuse.fresh_raw_hide=fresh;b.settings.refuse.rotten_raw_hide=rotten
  end
  local function header_action(category,action,column,variant)
   local before=settings_snapshot(b.settings)
   local size,address=df.sizeof(df.global.game.main_interface)
   local guard=df.new('uint8_t',size);dfhack.internal.memmove(guard,address,size)
   local text,code=dfhack.run_command_silent('df3d','stockpile-header-read',tostring(b.id),tostring(category),tostring(action))
   assert(code==0,text)
   assert(dfhack.internal.memcmp(guard,address,size)==0,'header probe changed native UI');df.delete(guard)
   assert(settings_snapshot(b.settings)==before,'header probe changed source settings')
   local expected=json.decode(text)
   label_click(action==2 and 'All' or 'None',0,column)
   compare_settings(expected)
   records[#records+1]={probe='header_action',category=category,action=action,variant=variant,predicted=expected}
  end
  c.entering_spec_filter=false;c.spec_filter=''
  for bit,key in ipairs(categories)do
   -- These three direct leaves have no native middle-column header buttons.
   if key~='wood' and key~='coins' and key~='corpses' then
    c.scroll_position_main=0;view:render(dfhack.getTickCount());label_click(category_labels[bit])
    for _,variant in ipairs{'existing','short'}do
     if variant=='short' then
      for field in pairs(category_prediction.vectors)do
       local cat,name=field:match('^([^%.]+)%.(.+)$')
       if cat==key then local value=b.settings[cat][name];value:resize(math.min(1,#value))end
      end
     end
     for _,action in ipairs{2,1}do header_action(1 << (bit-1),action,2,variant)end
    end
   end
  end
  for _,action in ipairs{2,1,2,1}do
   b.settings.misc.allow_organic=false;b.settings.misc.allow_inorganic=true
   header_action(0,action,nil,'mixed allowances')
  end
  -- Status artwork occupies the right edge of the first two columns. Native
  -- clicks there must be compared with selection, not inferred from the icon.
  c.entering_spec_filter=false;c.spec_filter=''
  for bit,key in ipairs(categories)do
   for _,enabled in ipairs{false,true}do
    b.settings.flags[key]=enabled
    c.scroll_position_main=0;view:render(dfhack.getTickCount())
    local text,code=dfhack.run_command_silent('df3d','stockpile-category-read',tostring(b.id),tostring(1 << (bit-1)))
    assert(code==0,text);local expected=json.decode(text)
    local pointer=label_click(category_labels[bit],23)
    assert(c.cur_main_mode==modes[bit],'status icon failed to select category '..key)
    compare_settings(expected)
    local before=settings_snapshot(b.settings)
    label_click(category_labels[bit],23)
    assert(settings_snapshot(b.settings)==before,'repeated category icon changed settings '..key)
    records[#records+1]={probe='category_status_click',category=key,was_enabled=enabled,pointer=pointer,repeated_unchanged=true}
   end
  end
  for _,entry in ipairs{
   {'Furniture/siege ammo','furniture',26,27,25}, {'Ammo','ammo',48,49,46},
   {'Finished goods','finished_goods',69,70,68}, {'Weapons/trap comps','weapons',92,93,91},
   {'Armor','armor',103,104,102}}do
   c.scroll_position_main=0;view:render(dfhack.getTickCount());label_click(entry[1])
   for _,field in ipairs{'quality_core','quality_total','other_mats'}do
    local values=b.settings[entry[2]][field]
    for i=0,#values-1 do values[i]=field=='other_mats' and i%2 or (i%2==0)end
   end
   for i,label in ipairs{'Core quality','Total quality','Other materials'}do
    local before=settings_snapshot(b.settings)
    local pointer=label_click(label,28,2)
    assert(c.cur_sub_mode==entry[i+2],'status icon failed to select sublist '..label)
    assert(settings_snapshot(b.settings)==before,'sublist icon changed settings '..label)
    label_click(label,28,2)
    assert(settings_snapshot(b.settings)==before,'repeated sublist icon changed settings '..label)
    records[#records+1]={probe='sublist_status_click',category=entry[2],label=label,mode=entry[i+2],pointer=pointer,repeated_unchanged=true}
   end
  end
  -- Compare owned summary states with the actual native 4x3 status artwork.
  -- Template addresses are renderer inputs observed at380958/61/6a; they are
  -- oracle-only and never runtime inputs to the provider.
  local summary_labels={[2]='Meat',[3]='Fish',[4]='Unprepared fish',[5]='Egg',[6]='Plants',[7]='Drink (plant)',[8]='Drink (animal)',[9]='Cheese (plant)',[10]='Cheese (animal)',[11]='Seeds',[12]='Fruit/leaves',[13]='Milled plant',[14]='Bone meal',[15]='Fat',[16]='Paste',[17]='Pressed material',[18]='Extract (plant)',[19]='Extract (animal)',[20]='Misc. liquid',[22]='Type',[23]='Stone/clay',[24]='Metal',[25]='Other materials',[26]='Core quality',[27]='Total quality',[30]='Item types',[31]='Corpses',[32]='Body parts',[33]='Skulls',[34]='Bones',[35]='Shells',[36]='Teeth',[37]='Horns/hooves',[38]='Hair/wool',[40]='Metal ores',[41]='Economic',[42]='Other stone',[43]='Clay',[45]='Type',[46]='Other materials',[47]='Metal',[48]='Core quality',[49]='Total quality',[52]='Bars: metal',[53]='Bars: other materials',[54]='Blocks: stone/clay',[55]='Blocks: metal',[56]='Blocks: other materials',[58]='Rough glass',[59]='Cut glass',[60]='Rough gem',[61]='Cut gem',[62]='Cut stone',[64]='Type',[65]='Stone/clay',[66]='Metal',[67]='Gem',[68]='Other materials',[69]='Core quality',[70]='Total quality',[71]='Color',[73]='Type',[74]='Color',[76]='Thread (silk)',[77]='Thread (plant)',[78]='Thread (yarn)',[79]='Thread (metal)',[80]='Cloth (silk)',[81]='Cloth (plant)',[82]='Cloth (yarn)',[83]='Cloth (metal)',[84]='Color',[87]='Weapons',[88]='Trap components',[89]='Metal',[90]='Stone',[91]='Other materials',[92]='Core quality',[93]='Total quality',[95]='Body',[96]='Head',[97]='Feet',[98]='Hands',[99]='Legs',[100]='Shield',[101]='Metal',[102]='Other materials',[103]='Core quality',[104]='Total quality',[105]='Color',[107]='Paper',[108]='Parchment'}
  local templates={}
  for state,rva in pairs{[0]=0x2651128,[1]=0x26510f8,[2]=0x26510c8}do
   templates[state]={};for i=0,11 do
    templates[state][i+1]=df.reinterpret_cast('int32_t',dfhack.internal.getImageBase()+rva+i*4).value
   end
  end
  local function screen_state(y,start_x,end_x)
   local matches={}
   for state,tiles in pairs(templates)do
    for x=start_x or 40,end_x or 74 do
     local found=true
     for dx=0,3 do for dy=0,2 do
      local index=(x+dx)*g.dimy+y+dy;local expected=tiles[dx*3+dy+1]
      if g.screentexpos[index]~=expected and g.screentexpos_lower[index]~=expected and
         g.screentexpos_top[index]~=expected and g.screentexpos_top_lower[index]~=expected then found=false end
     end end
     if found then matches[#matches+1]={state=state,x=x}end
    end
   end
   assert(#matches==1,'native summary artwork missing/ambiguous at '..y..': '..json.encode(matches))
   return matches[1].state
  end
  -- Earlier short-vector probes deliberately leave some categories short.
  -- Reinitialize each through native category activation before asking DF's
  -- renderer (which has unchecked fixed glass slots) for summary artwork.
  for bit,key in ipairs(categories)do
   b.settings.flags[key]=false;c.scroll_position_main=0;c.spec_filter='';c.entering_spec_filter=false
   view:render(dfhack.getTickCount());label_click(category_labels[bit])
  end
  for _,entry in ipairs{{'gems','rough_other_mats'},{'gems','cut_other_mats'},{'refuse','type'},{'finished_goods','type'}}do
   local category,field=entry[1],entry[2]
   local values=b.settings[category][field];local saved={};for _,v in ipairs(values)do saved[#saved+1]=v end
   values:resize(0)
   local before=settings_snapshot(b.settings)
   local _,code=dfhack.run_command_silent('df3d','stockpile-summary-read',tostring(b.id))
   assert(code~=0 and settings_snapshot(b.settings)==before,'short fixed-index summary not rejected unchanged')
   for _,mask in ipairs{0,8192}do
    local selected,selected_code=dfhack.run_command_silent('df3d','stockpile-summary-read',tostring(b.id),tostring(mask))
    assert(selected_code==0 and settings_snapshot(b.settings)==before,'unrequested short vector blocked selective summary')
    local result=json.decode(selected)
    for mode,state in ipairs(result.states)do if mask==0 or mode~=86 then assert(state==0,'unrequested native mode was evaluated')end end
    records[#records+1]={probe='summary_selective',field=category..'.'..field,stored_count=0,mask=mask}
   end
   values:resize(#saved);for i,v in ipairs(saved)do values[i-1]=v end
   records[#records+1]={probe='summary_rejection',field=category..'.'..field,stored_count=0}
  end
  for bit,key in ipairs(categories)do
   b.settings.flags[key]=false
   c.scroll_position_main=0;c.spec_filter='';c.entering_spec_filter=false
   view:render(dfhack.getTickCount());label_click(category_labels[bit])
   local function fill(value)
    for field,values in pairs(b.settings[key])do
     if tostring(field):sub(1,1)~='_' and type(values)~='function'then
      if type(values)=='boolean'then b.settings[key][field]=value~=0
      elseif type(values)=='userdata'then
       for i=0,#values-1 do
        if type(values[i])=='boolean'then values[i]=value==2 and i%2==0 or value==1
        else values[i]=value==2 and i%2 or value end
       end
      end
     end
    end
   end
   for _,variant in ipairs{0,1,2,3,4}do
    fill(variant==3 and 1 or variant==4 and 0 or variant)
    if variant>=3 then
     for field,value in pairs(b.settings[key])do
      if type(value)=='boolean'then b.settings[key][field]=variant==4 end
     end
    end
    local before=settings_snapshot(b.settings)
    local size,address=df.sizeof(df.global.game.main_interface)
    local guard=df.new('uint8_t',size);dfhack.internal.memmove(guard,address,size)
    local text,code=dfhack.run_command_silent('df3d','stockpile-summary-read',tostring(b.id))
    assert(code==0,'summary service refused '..key..': '..text)
    assert(dfhack.internal.memcmp(guard,address,size)==0,'summary probe changed UI');df.delete(guard)
    assert(settings_snapshot(b.settings)==before,'summary probe changed settings')
    local summary=json.decode(text);local states=summary.states;assert(#states==109 and #summary.categories==17,'summary mode count')
    view:render(dfhack.getTickCount())
    local root_y
    for row=9,g.dimy-1 do
     local chars={};for x=0,39 do local t=dfhack.screen.readTile(x,row);chars[#chars+1]=(t.ch>=32 and t.ch<127)and string.char(t.ch)or' 'end
     if table.concat(chars):find(category_labels[bit],1,true)then root_y=row-1;break end
    end
    assert(root_y,'root summary label absent '..key)
    local root_state=screen_state(root_y,0,35)
    assert(root_state==summary.categories[bit],'root aggregation differs '..key..' variant '..variant)
    if key=='corpses' or key=='coins' or key=='wood'then
     assert(root_state==states[modes[bit]+1],'direct root summary differs '..key)
    end
    local compared={}
    for i,mode in ipairs(c.sub_mode)do
     if c.sub_mode_ptr_type[i]==-1 then
      c.scroll_position_sub=math.max(0,i-5);view:render(dfhack.getTickCount())
      local label=assert(summary_labels[mode],'missing summary label '..mode);local y
      for row=9,g.dimy-1 do
       local chars={};for x=40,70 do local t=dfhack.screen.readTile(x,row);chars[#chars+1]=(t.ch>=32 and t.ch<127)and string.char(t.ch)or' 'end
       if table.concat(chars):find(label,1,true)then y=row-1;break end
      end
      assert(y,'summary label absent '..label)
      local actual=screen_state(y)
      assert(actual==states[mode+1],'native summary state differs mode '..mode)
      compared[#compared+1]={mode=mode,state=actual}
     end
    end
    records[#records+1]={probe='summary_render',category=key,variant=variant,root_state=root_state,states=states,compared=compared}
   end
  end
  -- These optional native columns are normally absent on this save. Give
  -- their stored vectors one entry, then rebuild through native selection;
  -- no raw/material table or product caption is supplied to the native UI.
  b.settings.food.cheese_plant:resize(1);b.settings.food.cheese_plant[0]=1
  b.settings.food.powder_creature:resize(1);b.settings.food.powder_creature[0]=1
  c.scroll_position_main=0;view:render(dfhack.getTickCount());label_click('Food')
  for _,entry in ipairs{{9,'Cheese (plant)'},{14,'Bone meal'}}do
   local ordinal
   for i,mode in ipairs(c.sub_mode)do if mode==entry[1]then ordinal=i end end
   assert(ordinal,'optional native Food column missing')
   c.scroll_position_sub=math.max(0,ordinal-5);view:render(dfhack.getTickCount())
   local pointer=label_click(entry[2],0,2)
   assert(c.cur_sub_mode==entry[1],'optional native Food label selected wrong mode')
   records[#records+1]={probe='optional_food_caption',mode=entry[1],label=entry[2],stored_count=1,pointer=pointer}
  end
  assert(frame==df.global.world.frame_counter,'simulation advanced')
 end)
 local f=assert(io.open(out..'/result.tmp','w'));f:write(require('json').encode{success=ok,error=tostring(why),records=records});f:close();assert(os.rename(out..'/result.tmp',out..'/result.json'))
end)
print('STOCKPILE_PRESETS_STARTED')




