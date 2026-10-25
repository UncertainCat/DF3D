-- Protected owned lane only: pause, disable autosave, preserve save manifests,
-- and close without saving. Mutates the first pile through native clicks.
-- Run with an output directory; result.json is published atomically.
local out,width_probe,historical=...
require('gui.script').start(function()
 local records={}
 local ok,why=pcall(function()
  local json=require('json');local gui=require('gui');local g=df.global.gps
  local view=dfhack.gui.getDFViewscreen(true)
  assert(df.global.pause_state);local frame=df.global.world.frame_counter
  assert(dfhack.run_command('disable','overlay')==0)
  for i=1,4 do gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())end
  local b=assert(df.global.world.buildings.other.STOCKPILE[0])
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

  label_click('Custom',-2)
  local c=df.global.game.main_interface.custom_stockpile
  local _,filter_address=df.sizeof(c:_field('spec_filter'))
  local _,editing_address=df.sizeof(c:_field('entering_spec_filter'))
  records[#records+1]={probe='input_context',grid={g.dimx,g.dimy},filter_rva=filter_address-dfhack.internal.getImageBase(),editing_rva=editing_address-dfhack.internal.getImageBase()}
  local function input(text)
   c.entering_spec_filter=true
   for i=1,#c.spec_filter do gui.simulateInput(view,'STRING_A000')end
   assert(c.spec_filter=='','native backspace did not clear filter')
   for i=1,#text do
    local utf=dfhack.df2utf(text:sub(i,i))
    for j=0,31 do df.global.enabler.last_text_input[j]=j<#utf and utf:byte(j+1) or 0 end
    gui.simulateInput(view,string.format('STRING_A%03d',text:byte(i)))
   end
   view:render(dfhack.getTickCount());c.entering_spec_filter=false
  end
  for byte=32,255 do
   local key=string.format('STRING_A%03d',byte)
   if df.interface_key[key] then
    input(string.char(byte))
    local stored={};for i=1,#c.spec_filter do stored[#stored+1]=c.spec_filter:byte(i)end
    records[#records+1]={probe='input_byte',byte=byte,input=dfhack.df2utf(string.char(byte)),stored=dfhack.df2utf(c.spec_filter),stored_bytes=stored}
   end
  end
  for _,length in ipairs{31,127,128,129,256}do
   input(string.rep('a',length));records[#records+1]={probe='input_limit',typed_length=length,stored_length=#c.spec_filter}
  end
  input('')
  if historical then
   local table=df.global.world.raws.mat_table
   local types,indexes=table.organic_types[17],table.organic_indexes[17]
   assert(#types>0 and #indexes>0)
   local figure
   for i=#df.global.world.history.figures-1,0,-1 do
    local f=df.global.world.history.figures[i]
    if f.race>=0 and f.race<#df.global.world.raws.creatures.all then figure=f;break end
   end
   assert(figure,'no historical material fixture figure')
   local old_type,old_index=types[0],indexes[0]
   local values=b.settings.leather.mats;local saved={}
   for i,v in ipairs(values)do saved[i]=v end
   local success,problem=pcall(function()
    types[0]=222;indexes[0]=figure.id
    label_click('Leather');values:resize(1);values[0]=1
    -- Rebuild explicitly after resizing; category entry may have initialized it.
    label_click('Color',0,2);label_click('Type',0,2)
    -- Native has now populated any cache entry. The provider must preserve
    -- the exact existing map object and native UI for every query.
    local cache=df.global.world.raws.creatures:_field('hist_fig_to_creature_map')
    local cache_size,cache_address=df.sizeof(cache)
    local guard=df.new('uint8_t',cache_size);dfhack.internal.memmove(guard,cache_address,cache_size)
    for _,query in ipairs{'','a','zzzznomatch'}do
     input(query)
     local size,address=df.sizeof(df.global.game.main_interface)
     local ui=df.new('uint8_t',size);dfhack.internal.memmove(ui,address,size)
     local text,code=dfhack.run_command_silent('df3d','stockpile-rows-read',tostring(b.id),'73',c.spec_filter)
     assert(code==0,text)
     assert(dfhack.internal.memcmp(ui,address,size)==0,'historical provider changed UI');df.delete(ui)
     assert(dfhack.internal.memcmp(guard,cache_address,cache_size)==0,'historical provider changed cache header')
     local cold_text,cold_code=dfhack.run_command_silent('df3d','stockpile-rows-cold-read',tostring(b.id),'73',c.spec_filter)
     assert(cold_code==0,cold_text);local cold=json.decode(cold_text)
     assert(cold.cache_insertions==1,'cold historical cache path was not exercised')
     assert(dfhack.internal.memcmp(guard,cache_address,cache_size)==0,'cold provider changed original cache header')
     assert(cold.rows[1].name==json.decode(text)[1].name,'cold/warm historical names differ')
     local actual=json.decode(text);assert(#actual==c.cur_spec_item_sz and #actual==1)
     local native=c.spec_item[0]
     assert(actual[1].name==dfhack.df2utf(native.name) and actual[1].visible==native.on and actual[1].enabled==(values[0]~=0),'historical native/provider mismatch')
     records[#records+1]={probe='historical_material',mode=73,material_type=222,figure=figure.id,race=figure.race,query=query,rows=actual,cache_header_unchanged=true,cold_cache_insertions=cold.cache_insertions}
    end
    df.delete(guard)
   end)
   -- Retire native row pointers before restoring a potentially reallocated vector.
   local closed,close_error=pcall(function()gui.simulateInput(view,'LEAVESCREEN')end)
   types[0]=old_type;indexes[0]=old_index;values:resize(#saved);for i,v in ipairs(saved)do values[i-1]=v end
   assert(closed,close_error)
   assert(success,problem)
   return
  end
  local originals={} 
  local function restore()
   for _,row in ipairs(originals)do row.raw.name=row.name;row.raw.name_plural=row.plural;row.raw.adjective=row.adjective end
  end
  local success,problem=pcall(function()
   local names={'épreuve','äther','straße','ñame','Ωmega'}
   -- CP437 characters whose Unicode uppercase differs from DF's byte rules.
   for _,byte in ipairs{160,133,224,225,230}do names[#names+1]=dfhack.df2utf(string.char(byte))..'caption' end
   for i,name in ipairs(names)do
    local raw=assert(df.global.world.raws.itemdefs.ammo[i-1])
    originals[#originals+1]={raw=raw,name=raw.name,plural=raw.name_plural,adjective=raw.adjective}
    raw.name=dfhack.utf2df(name);raw.name_plural=raw.name;raw.adjective=''
   end
   c.spec_filter='';label_click('Ammo')
   -- Category entry sorts its initial leaf twice. Compare mode45 against an
   -- explicit Type selection, not parent mode44, including equal sort keys.
   label_click('Metal',0,2);label_click('Type',0,2)
   for _,query in ipairs{'é','É','ä','Ä','ß','SS','ñ','Ñ','Ω','a','A',''}do
    input(dfhack.utf2df(query))
    local before_size,before_address=df.sizeof(df.global.game.main_interface)
    local guard=df.new('uint8_t',before_size);dfhack.internal.memmove(guard,before_address,before_size)
    local text,code=dfhack.run_command_silent('df3d','stockpile-rows-read',tostring(b.id),'45',c.spec_filter)
    assert(dfhack.internal.memcmp(guard,before_address,before_size)==0,'provider changed native UI');df.delete(guard)
    assert(code==0,text);local rows=json.decode(text)
    assert(#rows==c.cur_spec_item_sz,'native/provider item count')
    local visible={}
    for i,row in ipairs(rows)do
     local native=c.spec_item[i-1]
     assert(row.name==dfhack.df2utf(native.name) and row.visible==native.on,'native/provider non-ASCII row mismatch '..json.encode{query=query,index=i,provider=row,native={name=dfhack.df2utf(native.name),visible=native.on}})
     if row.visible then visible[#visible+1]=row.name end
    end
    records[#records+1]={probe='filtered_names',typed=query,stored=dfhack.df2utf(c.spec_filter),visible=visible}
    if query=='' then
     c.scroll_position_spec=0;view:render(dfhack.getTickCount())
     local rendered={}
     for i=1,math.min(#visible,(g.dimy-16)//3)do
      local bytes={}
      for x=79,math.min(g.dimx-26,100)do bytes[#bytes+1]=dfhack.screen.readTile(x,10+3*(i-1)).ch end
      rendered[#rendered+1]={name=visible[i],x=79,y=10+3*(i-1),bytes=bytes}
     end
     records[#records+1]={probe='rendered_captions',rows=rendered}
    end
   end
   local function record_truncation(kind)
    c.scroll_position_spec=0;view:render(dfhack.getTickCount())
    local shown={};local page=(g.dimy-16)//3
    for i=0,math.min(c.cur_spec_item_sz,page)-1 do
     local row=c.spec_item[i];assert(row.on,'truncation probe expects unfiltered rows')
     local chars={}
     for x=80,g.dimx-1 do
      local ch=dfhack.screen.readTile(x,10+3*i).ch
      if ch==0 then break end
      chars[#chars+1]=string.char(ch)
     end
     shown[#shown+1]={label=dfhack.df2utf(row.name),display=dfhack.df2utf(table.concat(chars))}
    end
    records[#records+1]={probe='caption_truncation',kind=kind,grid={g.dimx,g.dimy},
     page=page,count=c.cur_spec_item_sz,rows=shown}
   end
   for i,length in ipairs{1,2,3,4,5,6,7,8,35,36,80}do
    local raw=assert(df.global.world.raws.itemdefs.ammo[i-1])
    if i>#originals then originals[#originals+1]={raw=raw,name=raw.name,plural=raw.name_plural,adjective=raw.adjective}end
    raw.name=string.rep('x',length);raw.name_plural=raw.name;raw.adjective=''
   end
   label_click('Metal',0,2);label_click('Type',0,2)
   record_truncation('ammo_boundaries')
   label_click('Food');record_truncation('food_with_scrollbar')
  end)
  restore();assert(success,problem)
  c.spec_filter='';label_click(width_probe and 'Food' or 'Ammo')
  assert(frame==df.global.world.frame_counter,'simulation advanced')
 end)
 local f=assert(io.open(out..'/result.tmp','w'));f:write(require('json').encode{success=ok,error=tostring(why),records=records});f:close();assert(os.rename(out..'/result.tmp',out..'/result.json'))
end)
print('STOCKPILE_SEARCH_STARTED')
