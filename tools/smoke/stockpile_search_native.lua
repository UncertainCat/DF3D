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
  local originals={} 
  local function restore()
   for _,row in ipairs(originals)do row.raw.name=row.name;row.raw.name_plural=row.plural;row.raw.adjective=row.adjective end
  end
  local success,problem=pcall(function()
   for i,name in ipairs{'épreuve','äther','straße','ñame','Ωmega'}do
    local raw=assert(df.global.world.raws.itemdefs.ammo[i-1])
    originals[#originals+1]={raw=raw,name=raw.name,plural=raw.name_plural,adjective=raw.adjective}
    raw.name=dfhack.utf2df(name);raw.name_plural=raw.name;raw.adjective=''
   end
   c.spec_filter='';label_click('Ammo')
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
   end
  end)
  restore();assert(success,problem)
  c.spec_filter='';label_click('Ammo')
  assert(frame==df.global.world.frame_counter,'simulation advanced')
 end)
 local f=assert(io.open(out..'/result.tmp','w'));f:write(require('json').encode{success=ok,error=tostring(why),records=records});f:close();assert(os.rename(out..'/result.tmp',out..'/result.json'))
end)
print('STOCKPILE_SEARCH_STARTED')
