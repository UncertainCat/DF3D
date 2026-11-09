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
if os.getenv('DF3D_STONE_USE_DISPLAY')=='1' then
 assert(cold,'Stone use display comparison requires provider')
 local page
 for _,candidate in ipairs(df.global.texture.page)do if candidate.token=='INTERFACE_BITS_LABOR' then page=candidate;break end end
 assert(page,'Native Stone use artwork page missing')
 result.display={}
 local cursor=1
 for category=0,1 do
  click(category==0 and 14 or 30,12)
  for position,index in ipairs(panel.stone_mg_index[category])do
   -- Diagnostic-only positioning of the native list, never runtime input.
   local first=math.min(position,math.max(0,#panel.stone_mg_index[category]-15))
   panel.scroll_position[category]=first
   view:render(dfhack.getTickCount())
   local tile=dfhack.screen.readTile(34,16+(position-first)*3).tile
   local safe=tile==page.texpos[8]
   assert(safe or tile==page.texpos[3*page.page_dim_x+8],'Unexpected native magma indicator')
   local row=cold[cursor]
   assert(row.index==index and row.magma_safe==safe,'Owned magma safety differs at index '..index..' position '..position..' actual-scroll '..panel.scroll_position[category]..' provider '..tostring(row.magma_safe)..' native '..tostring(safe))
   assert(row.material_token=='INORGANIC:'..df.global.world.raws.inorganics.all[index].id,'Stone use material identity differs')
   result.display[#result.display+1]={index=index,magma_safe=safe,material_token=row.material_token}
   cursor=cursor+1
  end
  panel.scroll_position[category]=0
 end
 click(14,12)
end
if os.getenv('DF3D_STONE_USE_EDITS')=='1' then
 local function snapshot()
  local flags={};for _,value in ipairs(df.global.plotinfo.economic_stone)do flags[#flags+1]=value end;return flags
 end
 local original=snapshot();result.edits={before=original,steps={}}
 for category=0,1 do
  click(category==0 and 14 or 30,12)
  assert(panel.current_category==category,'Stone use category failed')
  shot('stone-use-category-'..category)
  local index=panel.stone_mg_index[category][0]
  for attempt=1,2 do
   click(115,17)
   local flags=snapshot()
   assert(flags[index+1]==(attempt==1 and 1-original[index+1] or original[index+1]),'Native Stone use toggle failed')
   for i,value in ipairs(flags)do if i~=index+1 then assert(value==original[i],'Stone use changed unrelated restriction')end end
   result.edits.steps[#result.edits.steps+1]={category=category,index=index,restricted=flags[index+1]}
  end
 end
 if os.getenv('DF3D_STONE_USE_RESIZED_EDIT')=='1' then
  -- Native target at position35 is the first displayed row after the verified
  -- Other stone38 ->1600x900 resize. Compare its ordinary native toggle effect.
  panel.scroll_position[1]=35;view:render(dfhack.getTickCount())
  local index=panel.stone_mg_index[1][35]
  for attempt=1,2 do
   click(115,17);local flags=snapshot()
   for i,value in ipairs(flags)do assert(value==(i==index+1 and (attempt==1 and 1-original[i] or original[i]) or original[i]),'Resized Stone use target effect mismatch')end
   result.edits.steps[#result.edits.steps+1]={category=1,index=index,restricted=flags[index+1],resized=true}
  end
  panel.scroll_position[1]=0
 end
 assert(json.encode(snapshot())==json.encode(original),'Stone use restoration failed')
 if os.getenv('DF3D_STONE_USE_APPLY')=='1' then
  result.edits.owned={}
  for _,step in ipairs(result.edits.steps)do
   local before=snapshot()
   local text,code=dfhack.run_command_silent('df3d','stone-use-edit-probe',tostring(step.category),tostring(step.index),tostring(before[step.index+1]))
   assert(code==0,'Stone use adapter failed');local reply=json.decode(text)
   assert(reply.outcome==1 and reply.write_started,'Stone use adapter did not apply')
   local after=snapshot()
   for i,value in ipairs(after)do assert(value==(i==step.index+1 and step.restricted or before[i]),'Stone use adapter effect mismatch')end
   text,code=dfhack.run_command_silent('df3d','stone-use-edit-probe',tostring(step.category),tostring(step.index),tostring(before[step.index+1]))
   assert(code==0,'Stone use stale probe failed');local stale=json.decode(text)
   assert(stale.outcome==2 and not stale.write_started and json.encode(snapshot())==json.encode(after),'Stone use stale receipt changed state')
   result.edits.owned[#result.edits.owned+1]={category=step.category,index=step.index,restricted=after[step.index+1],stale_rejected=true}
  end
  assert(json.encode(snapshot())==json.encode(original),'Stone use adapter restoration failed')
 end
 click(14,12)
end
if os.getenv('DF3D_STONE_USE_INPUT')=='1' then
 result.input={scroll={},hover={}}
 local function observe(label)
  result.input.scroll[#result.input.scroll+1]={label=label,category=panel.current_category,first={panel.scroll_position[0],panel.scroll_position[1]}}
 end
 for _,point in ipairs({{'row',200,214},{'outside',1000,400},{'bar',952,300}})do
  g.precise_mouse_x=point[2];g.precise_mouse_y=point[3];g.mouse_x=point[2]//8;g.mouse_y=(point[3]-4)//12
  for _,key in ipairs({'STANDARDSCROLL_DOWN','STANDARDSCROLL_UP','STANDARDSCROLL_PAGEDOWN','STANDARDSCROLL_PAGEUP','CONTEXT_SCROLL_DOWN','CONTEXT_SCROLL_UP'})do
   gui.simulateInput(view,key)
   for _=1,3 do script.sleep(1,'frames');view:render(dfhack.getTickCount())end
   observe(point[1]..'-'..key)
  end
 end
 click(118,60);observe('arrow-down')
 click(118,16);observe('arrow-up')
 click(118,50);observe('page-down')
 click(30,12);observe('other-category')
 click(118,60);observe('other-arrow-down')
 click(14,12);observe('economic-retained')
 -- Return to the first page for isolated hover observations.
 panel.scroll_position[0]=0;panel.scroll_position[1]=0
 local main=df.global.game.main_interface
 for _,target in ipairs({{'stone',64,214},{'name',160,214},{'magma',288,214},{'uses',400,358},{'permission',920,214},{'category',112,148},{'bar',952,300}})do
  local deadline=dfhack.getTickCount()+850
  repeat
   df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
   g.precise_mouse_x=target[2];g.precise_mouse_y=target[3];g.mouse_x=target[2]//8;g.mouse_y=(target[3]-4)//12
   gui.simulateInput(view,{});view:render(dfhack.getTickCount());script.sleep(1,'frames')
  until dfhack.getTickCount()>=deadline
  result.input.hover[#result.input.hover+1]={target=target[1],instruction=main.current_hover,displayed=main.last_displayed_hover_inst}
  if main.last_displayed_hover_inst~=-1 then shot('stone-use-hover-'..target[1])end
 end
end
if os.getenv('DF3D_STONE_USE_NAV')=='1' then
 result.navigation={}
 local function observe(label)
  result.navigation[#result.navigation+1]={label=label,columns=g.dimx,rows=g.dimy,category=panel.current_category,first={panel.scroll_position[0],panel.scroll_position[1]}}
 end
 local function request(action)
  local f=assert(io.open(out..'/owner-input-request.tmp','w'));f:write(action);f:close();assert(os.rename(out..'/owner-input-request.tmp',out..'/owner-input-request'))
  local deadline=dfhack.getTickCount()+5000
  while true do local ack=io.open(out..'/owner-input-ack');if ack then ack:close();break end;assert(dfhack.getTickCount()<deadline,'Stone use native input timeout');script.sleep(1,'frames')end
  assert(os.remove(out..'/owner-input-ack'));for _=1,5 do script.sleep(1,'frames');view:render(dfhack.getTickCount())end
 end
 for _,point in ipairs({{'row',200,250},{'outside',1100,750},{'bar',944,250}})do
  for _,step in ipairs({{'down',-120,false},{'up',120,false},{'shift-down',-120,true},{'shift-up',120,true}})do
   local f=assert(io.open(out..'/kitchen-wheel.json','w'));f:write(json.encode({x=point[2],y=point[3],delta=step[2],shift=step[3]}));f:close()
   request('kitchen-wheel');observe(point[1]..'-'..step[1])
  end
 end
 local function pointer(y)
  g.precise_mouse_x=944;g.precise_mouse_y=y;g.mouse_x=118;g.mouse_y=(y-4)//12
 end
 for _,y in ipairs({196,232,340,460,660,736})do
  panel.scroll_position[0]=0;view:render(dfhack.getTickCount())
  pointer(220);df.global.enabler.mouse_lbut_lift=0
  gui.simulateInput(view,{'_MOUSE_L','_MOUSE_L_DOWN'})
  pointer(y);gui.simulateInput(view,{'_MOUSE_L_DOWN'})
  df.global.enabler.mouse_lbut_lift=1;gui.simulateInput(view,{})
  for _=1,3 do script.sleep(1,'frames');view:render(dfhack.getTickCount())end
  observe('drag-'..y)
 end
 panel.scroll_position[0]=0;panel.scroll_position[1]=0
 if os.getenv('DF3D_STONE_USE_PAGES')=='1' then
  for category=0,1 do
   click(category==0 and 14 or 30,12)
   for _,first in ipairs(category==0 and {0,15} or {0,15,30,38})do
    -- Diagnostic positioning; captured rows still use native rendering.
    panel.scroll_position[category]=first;view:render(dfhack.getTickCount())
    observe('page-'..category..'-'..first);shot('stone-use-page-'..category..'-'..first)
   end
  end
 end
 for _,size in ipairs({'minimum','small','wide','default'})do
  request('name-resize-'..size);observe(size);shot('stone-use-layout-'..size)
 end
end
local f=assert(io.open(out..'/stone-use-native.json','w'));f:write(json.encode(result));f:close()
if os.getenv('DF3D_STONE_USE_WIRE')=='1' then
 assert(result.edits and cold,'Stone use wire needs native edit/provider evidence')
 local checked=0;local expected={}
 for i,value in ipairs(result.edits.before)do expected[i]=value end
 shot('stone-use-wire',function()
  local f=io.open(out..'/stone-use-wire-step');if not f then return end
  local index=tonumber(f:read('*a'));f:close()
  if index and index>checked then
   assert(index==checked+1 and index<=#result.edits.steps,'Unexpected Stone use wire step')
   local step=result.edits.steps[index];expected[step.index+1]=step.restricted
   for i,value in ipairs(df.global.plotinfo.economic_stone)do assert(value==expected[i+1],'Stone use wire changed unexpected restriction')end
   checked=index;local ack=assert(io.open(out..'/stone-use-wire-ack','w'));ack:write(tostring(index));ack:close()
  end
 end)
 assert(checked==#result.edits.steps,'Incomplete Stone use wire effects')
end
shot('stone-use-root')
click(30,10)
return result
