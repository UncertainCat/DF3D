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
  assert(frame==df.global.world.frame_counter,'simulation advanced')
 end)
 local f=assert(io.open(out..'/result.tmp','w'));f:write(require('json').encode{success=ok,error=tostring(why),records=records});f:close();assert(os.rename(out..'/result.tmp',out..'/result.json'))
end)
print('STOCKPILE_PRESETS_STARTED')




