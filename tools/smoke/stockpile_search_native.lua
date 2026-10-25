-- Protected owned lane only: pause, disable autosave, preserve save manifests,
-- and close without saving. Mutates the first pile through native clicks.
-- Run with an output directory; result.json is published atomically.
local out,width_probe,historical,text_chunks=...
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
  if text_chunks then
   for _,prefix in ipairs{'',string.rep('a',75),string.rep('a',76)}do
    for _,chunk in ipairs{'abc XYZ','aéα中b','ab\r\ncd\tef','ab\ncd','ab\tcd',string.rep('b',31)}do
     input(prefix);c.entering_spec_filter=true
     assert(#chunk<32)
     for j=0,31 do df.global.enabler.last_text_input[j]=j<#chunk and chunk:byte(j+1) or 0 end
     -- A STRING_A key overwrites the supplied buffer inside DFHack.
     gui.simulateInput(view,{});view:render(dfhack.getTickCount())
     records[#records+1]={probe='committed_text_chunk',prefix_length=#prefix,chunk=chunk,stored=dfhack.df2utf(c.spec_filter),stored_length=#c.spec_filter}
    end
   end
   input('');return
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
   local figure
   for i=#df.global.world.history.figures-1,0,-1 do
    local f=df.global.world.history.figures[i]
    if f.race>=0 and f.race<#df.global.world.raws.creatures.all then figure=f;break end
   end
   assert(figure,'no historical material fixture figure')
   for _,entry in ipairs({{'Food','food','meat',2,'Meat',0},
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
   {'Sheet','sheet','parchment',108,'Parchment',38}})do
    if entry[4]~=3 and entry[4]~=4 and entry[4]~=5 then
   local types,indexes=table.organic_types[entry[6]],table.organic_indexes[entry[6]]
   local type_count,index_count=#types,#indexes
   local old_type,old_index=type_count>0 and types[0],index_count>0 and indexes[0]
   local values=b.settings[entry[2]][entry[3]];local saved={}
   for i,v in ipairs(values)do saved[i]=v end
   local success,problem=pcall(function()
    types:resize(math.max(1,type_count));indexes:resize(math.max(1,index_count))
    types[0]=222;indexes[0]=figure.id
    c.scroll_position_main=0;view:render(dfhack.getTickCount());label_click('Ammo')
    values:resize(1);values[0]=1;label_click(entry[1])
    local alternate=entry[2]=='food' and 'Fish' or entry[2]=='sheet' and (entry[4]==107 and 'Parchment' or 'Paper') or 'Color'
    c.scroll_position_sub=0;view:render(dfhack.getTickCount());label_click(alternate,0,2)
    values:resize(1);values[0]=1
    local sub_index
    for i,mode in ipairs(c.sub_mode)do if mode==entry[4]then sub_index=i;break end end
    assert(sub_index,'historical sublist absent '..entry[4])
    c.scroll_position_sub=math.max(0,sub_index-5);view:render(dfhack.getTickCount());label_click(entry[5],0,2)
    assert(c.cur_sub_mode==entry[4],'wrong historical mode')
    -- Native has now populated any cache entry. The provider must preserve
    -- the exact existing map object and native UI for every query.
    local cache=df.global.world.raws.creatures:_field('hist_fig_to_creature_map')
    local cache_size,cache_address=df.sizeof(cache)
    local guard=df.new('uint8_t',cache_size);dfhack.internal.memmove(guard,cache_address,cache_size)
    for _,query in ipairs{'','a','zzzznomatch'}do
     input(query)
     local size,address=df.sizeof(df.global.game.main_interface)
     local ui=df.new('uint8_t',size);dfhack.internal.memmove(ui,address,size)
     local text,code=dfhack.run_command_silent('df3d','stockpile-rows-read',tostring(b.id),tostring(entry[4]),c.spec_filter)
     assert(code==0,text)
     assert(dfhack.internal.memcmp(ui,address,size)==0,'historical provider changed UI')
     assert(dfhack.internal.memcmp(guard,cache_address,cache_size)==0,'historical provider changed cache header')
     local cold_text,cold_code=dfhack.run_command_silent('df3d','stockpile-rows-cold-read',tostring(b.id),tostring(entry[4]),c.spec_filter)
     assert(cold_code==0,cold_text);local cold=json.decode(cold_text)
     assert(cold.cache_insertions<=1,'unexpected cold historical cache entries')
     assert(dfhack.internal.memcmp(guard,cache_address,cache_size)==0,'cold provider changed original cache header')
     assert(dfhack.internal.memcmp(ui,address,size)==0,'cold historical provider changed UI');df.delete(ui)
     local actual=json.decode(text);assert(#actual==c.cur_spec_item_sz and #actual==#cold.rows,'historical row count mismatch')
     for i,row in ipairs(actual)do
      local native=c.spec_item[i-1]
      assert(cold.rows[i].name==row.name and cold.rows[i].visible==row.visible,'cold/warm historical names differ')
      assert(row.name==dfhack.df2utf(native.name) and row.visible==native.on and row.enabled==(values[row.index]~=0),'historical native/provider mismatch')
     end
     records[#records+1]={probe='historical_material',mode=entry[4],field=entry[2]..'.'..entry[3],material_type=222,figure=figure.id,race=figure.race,query=query,rows=actual,cache_header_unchanged=true,cold_cache_insertions=cold.cache_insertions}
    end
    df.delete(guard)
   end)
   -- Retire native row pointers before restoring a potentially reallocated vector.
   local closed,close_error=pcall(function()input('');c.scroll_position_main=0;view:render(dfhack.getTickCount());label_click('Ammo')end)
   if success and closed then
    -- Corrupt only the paused oracle inputs; restore before assertions or render.
    local guarded,guard_error=pcall(function()
     local function refused(kind,change,restore)
      local value=values[0]
      change()
      local called,text,code=pcall(dfhack.run_command_silent,'df3d','stockpile-rows-read',tostring(b.id),tostring(entry[4]),'')
      restore()
      assert(called and code~=0,'malformed organic input was not refused: '..kind)
      assert(values[0]==value,'refused organic read changed settings')
      records[#records+1]={probe='organic_guard',mode=entry[4],kind=kind,refused=true}
     end
     local saved_indexes={};for _,value in ipairs(indexes)do saved_indexes[#saved_indexes+1]=value end
     refused('missing_paired_index',function()indexes:resize(0)end,function()indexes:resize(#saved_indexes);for i,v in ipairs(saved_indexes)do indexes[i-1]=v end end)
     local creatures=df.global.world.raws.creatures.all;local creature=assert(creatures[0])
     types[0]=19;indexes[0]=0
     refused('null_creature_raw',function()creatures[0]=nil end,function()creatures[0]=creature end)
     local plants=df.global.world.raws.plants.all;local plant=assert(plants[0])
     types[0]=419
     refused('null_plant_raw',function()plants[0]=nil end,function()plants[0]=plant end)
    end)
    if not guarded then success=false;problem=guard_error end
   end
   types:resize(type_count);indexes:resize(index_count);if type_count>0 then types[0]=old_type end;if index_count>0 then indexes[0]=old_index end;values:resize(#saved);for i,v in ipairs(saved)do values[i-1]=v end
   assert(closed,close_error)
   assert(success,problem)
    end
   end
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
