-- Protected discovery only; native widgets are not runtime semantic inputs.
local out,view,shot=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local g=df.global.gps;local base=dfhack.internal.getImageBase()
local function click(x,y)
 g.precise_mouse_x=x*8+4;g.precise_mouse_y=y*12+6;g.mouse_x=x;g.mouse_y=y
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L')
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
 for _=1,3 do script.sleep(1,'frames')end;view:render(dfhack.getTickCount())
end
local cold
if os.getenv('DF3D_STONE_USE_PROVIDER')=='1' then
 local text,code=dfhack.run_command_silent('df3d','stone-use-probe')
 assert(code==0,'Cold owned Stone use provider failed');cold=json.decode(text)
end
click(57,10)
local panel
local function find(widget)
 if df.labor_stone_use_interfacest:is_instance(widget)then panel=widget;return end
 if df.widget_container:is_instance(widget)then for _,child in ipairs(dfhack.gui.getWidgetChildren(widget))do find(child)end end
end
find(df.global.game.main_interface.info.labor)
assert(panel and (panel.flag.whole&3)==3,'Stone use did not open')
local result={category=panel.current_category,vtable={},categories={},rows={}}
result.provider=cold
local _,address=df.sizeof(panel);local vt=df.reinterpret_cast('uint64_t',address).value
for slot=0,7 do result.vtable[#result.vtable+1]=df.reinterpret_cast('uint64_t',vt+slot*8).value-base end
for category=0,1 do
 local entries={}
 for position,index in ipairs(panel.stone_mg_index[category])do
  local raw=df.global.world.raws.inorganics.all[index]
  local entry={index=index,id=raw.id,name=dfhack.df2utf(raw.material.state_name.Solid),restricted=df.global.plotinfo.economic_stone[index]}
  if category==0 then entry.uses=dfhack.df2utf(panel.stone_item_use_str[position].value)end
  entries[#entries+1]=entry
 end
 result.categories[#result.categories+1]={category=category,entries=entries}
end
if cold then
 local cursor=1
 for _,category in ipairs(result.categories)do for _,entry in ipairs(category.entries)do
  local row=cold[cursor];assert(row and row.category==category.category and row.index==entry.index and row.restricted==(entry.restricted~=0),'Stone use owned order/restriction mismatch at '..cursor)
  assert(row.uses==(entry.uses or ''),'Stone use economic description mismatch')
  cursor=cursor+1
 end end
 assert(cursor==#cold+1,'Stone use owned row count mismatch')
end
for y=11,g.dimy-4 do
 local chars={}
 for x=5,math.min(117,g.dimx-1)do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
 local text=dfhack.df2utf(table.concat(chars)):gsub('%s+$','')
 if text:find('%S')then result.rows[#result.rows+1]={y=y,text=text}end
end
local f=assert(io.open(out..'/stone-use-native.json','w'));f:write(json.encode(result));f:close()
shot('stone-use-root')
click(30,10)
return result
