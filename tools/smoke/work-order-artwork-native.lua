-- Native oracle only, run by the protected owned unsaved lane.
local out,view,records=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local g=df.global.gps;local m=df.global.game.main_interface
-- This oracle runs only in the owned unsaved session; limit render load.
df.global.enabler.gfps=30
df.global.enabler.fps_per_gfps=df.global.enabler.fps/df.global.enabler.gfps
local function key(k)gui.simulateInput(view,k);view:render(dfhack.getTickCount())end
local function mouse(x,y)
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=math.floor(x/8);g.mouse_y=math.floor(y/12)
 df.global.enabler.mouse_lbut_lift=0;key('_MOUSE_L')
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
end
local function values(vector)local result={};for _,v in ipairs(vector)do result[#result+1]=v end;return result end
local function lines()
 local result={}
 for y=0,g.dimy-1 do
  local row={};for x=0,g.dimx-1 do local ch=dfhack.screen.readTile(x,y).ch;row[#row+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
  result[#result+1]={y=y,text=dfhack.df2utf(table.concat(row)):gsub('%s+$','')}
 end
 return result
end
local observations={}
local function click_label(label,x_override)
 for _,row in ipairs(lines())do local x=row.text:find(label,1,true);if x then mouse(x_override or ((x-1)*8+4),row.y*12+6);return true end end
 return false
end
local function back()
 df.global.enabler.mouse_rbut_lift=0;key('_MOUSE_R')
 df.global.enabler.mouse_rbut=0;df.global.enabler.mouse_rbut_down=0;df.global.enabler.mouse_rbut_lift=1
end
local function shot(name)
 for _=1,3 do script.sleep(1,'frames')end
 if name:find('%-hover$')then df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;g.precise_mouse_x=200;g.precise_mouse_y=190;g.mouse_x=25;g.mouse_y=15 end
 view:render(dfhack.getTickCount())
 local preview={};for _,line in ipairs(m.image_creator.selected_box.text)do preview[#preview+1]=dfhack.df2utf(line.value)end
 observations[#observations+1]={name=name,dimensions={g.dimx,g.dimy},lines=lines(),page=m.image_creator.current_option,open=m.image_creator.open,hovered=m.image_creator.last_selected_index,columns=m.image_creator.last_selected_box_width,preview=preview}
 local f=assert(io.open(out..'/work-order-artwork-reference.json','w'));f:write(json.encode(observations));f:close()
 f=assert(io.open(out..'/shot.tmp','w'));f:write(name);f:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local deadline=dfhack.getTickCount()+(name:find('%-wire$') and 65000 or 30000)
 while true do local ack=io.open(out..'/ack-'..name);if ack then ack:close();break end;assert(dfhack.getTickCount()<deadline,'artwork capture timeout');script.sleep(1,'frames')end
end
key('D_ORDERS');assert(m.info.open)
assert(click_label('Encrust',584),'Fixture needs visible Encrust order')
local details=m.job_details;assert(details.open and details.wq)
local order=details.wq;local before={spec=order.specdata.hist_figure_id,typ=order.art_spec.type,id=order.art_spec.id,subid=order.art_spec.subid}
if os.getenv('DF3D_WORK_ORDER_HOVER')=='1' then
 key('LEAVESCREEN');assert(not details.open)
 local hover={}
 local function probe(name,x,y,expected)
  local function move()
   df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
   g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=math.floor(x/8);g.mouse_y=math.floor((y-4)/12)
   gui.simulateInput(view,{});view:render(dfhack.getTickCount())
  end
  local deadline=dfhack.getTickCount()+650
  repeat move();script.sleep(1,'frames')until dfhack.getTickCount()>=deadline
  move();assert(m.current_hover==expected and m.last_displayed_hover_inst==expected,'Unexpected work order hover: '..name..' '..tostring(m.current_hover))
  local text={}
  for y=0,17 do
   local chars={};for x=g.dimx-24,g.dimx-1 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<127 and string.char(ch)or' 'end
   text[#text+1]=table.concat(chars):gsub('%s+$','')
  end
  while #text>0 and text[#text]==''do table.remove(text)end
  hover[#hover+1]={name=name,instruction=expected,point={x,y},lines=text}
  local f=assert(io.open(out..'/work-order-hover-reference.json','w'));f:write(json.encode(hover));f:close()
 end
 for _,p in ipairs{{'active',64,430,212},{'amount',392,430,219},{'priority',488,430,220},{'conditions',552,430,221},{'details',584,430,222},{'remove',888,430,223},{'shop_limit',784,430,216}}do probe(table.unpack(p))end
 mouse(552,430);assert(m.info.work_orders.conditions.open)
 for _,p in ipairs{{'frequency',880,142,224},{'add_item',912,142,225},{'add_order',944,142,226},{'condition_amount',640,178,227},{'comparison',736,178,228},{'item_type',768,178,229},{'material',800,178,230},{'traits',832,178,231},{'remove_condition',896,178,233}}do probe(table.unpack(p))end
 local f=assert(io.open(out..'/work-order-hover-reference.json','w'));f:write(json.encode(hover));f:close()
 shot('work-order-hover-list')
 records[#records+1]={name='work-order-hover',controls=#hover}
 return
end
if os.getenv('DF3D_WORK_ORDER_NAVIGATION')=='1' then
 local quantity,remaining,limit,frequency=order.amount_total,order.amount_left,order.max_workshops,order.frequency
 local f=assert(io.open(out..'/work-order-navigation-expected.json','w'));f:write(json.encode({id=order.id}));f:close()
 shot('work-order-navigation-wire')
 f=assert(io.open(out..'/work-order-navigation-wire-result.json'));local result=json.decode(f:read('*a'));f:close();assert(result.success,'Work orders navigation failed')
 assert(order.amount_total==quantity and order.amount_left==remaining and order.max_workshops==limit and order.frequency==frequency,'Navigation changed order quantities/frequency')
 assert(order.specdata.hist_figure_id==before.spec and order.art_spec.type==before.typ and order.art_spec.id==before.id and order.art_spec.subid==before.subid,'Navigation changed order details')
 records[#records+1]={name='work-order-navigation',order_unchanged=true}
 return
end
if os.getenv('DF3D_WORK_ORDER_LAYOUT')=='1' then
 local original_limit=order.max_workshops
 for _,size in ipairs({'wide','default','minimum'})do
  if size=='minimum' then
   key('LEAVESCREEN');assert(click_label('Encrust',552));assert(m.info.work_orders.conditions.open)
  end
  local f=assert(io.open(out..'/owner-input-request.tmp','w'));f:write('name-resize-'..size);f:close()
  assert(os.rename(out..'/owner-input-request.tmp',out..'/owner-input-request'))
  local limit=dfhack.getTickCount()+30000
  while true do local ack=io.open(out..'/owner-input-ack');if ack then ack:close();break end
   assert(dfhack.getTickCount()<limit,'Work order resize timeout');script.sleep(1,'frames')end
  assert(os.remove(out..'/owner-input-ack'));script.sleep(3,'frames');view:render(dfhack.getTickCount())
  if size=='minimum' then
   shot('work-order-conditions-'..size);key('LEAVESCREEN');shot('work-order-list-'..size)
  else
   shot('work-order-details-'..size)
   key('LEAVESCREEN');assert(not details.open)
   shot('work-order-list-'..size)
   local controls=math.floor((12+g.dimx-38)/3)
   assert(click_label('Encrust',(controls+26)*8+16));assert(m.info.work_orders.conditions.open)
   shot('work-order-conditions-'..size)
   key('LEAVESCREEN')
  end
  if size~='minimum' then
   local details_x=(math.floor((12+g.dimx-38)/3)+30)*8+16
   assert(click_label('Encrust',details_x));assert(details.open)
  end
 end
 assert(order.specdata.hist_figure_id==before.spec and order.art_spec.type==before.typ and order.art_spec.id==before.id and order.art_spec.subid==before.subid,'Layout capture changed order')
 assert(order.max_workshops==original_limit,'Layout capture changed workshop limit')
 records[#records+1]={name='work-order-layout',screens=#observations,order_unchanged=true}
 return
end
local option;for i,kind in ipairs(details.option)do if kind==3 then option=i;break end end
assert(option);mouse(200,106+option*36);assert(details.current_option==3)
mouse(200,142);local art=m.image_creator;assert(art.open)
before={spec=order.specdata.hist_figure_id,typ=order.art_spec.type,id=order.art_spec.id,subid=order.art_spec.subid}
if os.getenv('DF3D_WORK_ORDER_ARTWORK_ARTIST')=='1' then
 -- Start with a real selected image so all three cleared fields are observable.
 assert(click_label('Existing image'));assert(art.current_option==5 and #art.art_image>0)
 mouse(200,190);assert(not art.open and order.art_spec.type==3)
 local function effect()return {type=order.art_spec.type,id=order.art_spec.id,subid=order.art_spec.subid,specdata=order.specdata.hist_figure_id,amount=order.amount_total,remaining=order.amount_left,frequency=order.frequency}end
 local original=effect();local inputs={}
 for _,item in ipairs(order.items.elements)do local copy=df.job_item:new();copy:assign(item);inputs[#inputs+1]=copy end
 assert(click_label('Encrust',584));mouse(200,106+option*36);mouse(200,142);assert(art.open)
 shot('work-order-artwork-artist-before')
 assert(click_label('Allow artist to choose'));assert(not art.open and not details.open)
 local expected=effect();assert(expected.type==-1 and expected.id==-1 and expected.subid==-1)
 shot('work-order-artwork-artist-after')
 order.art_spec.type=original.type;order.art_spec.id=original.id;order.art_spec.subid=original.subid
 assert(#order.items.elements==#inputs)
 for i,item in ipairs(order.items.elements)do item:assign(inputs[i+1]);inputs[i+1]:delete()end
 local f=assert(io.open(out..'/work-order-artwork-expected.json','w'));f:write(json.encode({id=order.id,option=option,artist=true,before=original,effect=expected}));f:close()
 if os.getenv('DF3D_WORK_ORDER_ARTWORK_WIRE')=='1' then
  shot('work-order-artwork-wire')
  f=assert(io.open(out..'/work-order-artwork-wire-result.json'));local result=json.decode(f:read('*a'));f:close();assert(result.success,'Artist choice viewer failed')
  local actual=effect();for field,value in pairs(expected)do assert(actual[field]==value,'Artist choice effect differs: '..field)end
 end
 records[#records+1]={name='work-order-artwork-artist',effects_match=true}
 return
end
if os.getenv('DF3D_WORK_ORDER_ARTWORK_RESIZE')=='1' then
 for _,size in ipairs({'small','wide','default'})do
  local f=assert(io.open(out..'/owner-input-request.tmp','w'));f:write('name-resize-'..size);f:close()
  assert(os.rename(out..'/owner-input-request.tmp',out..'/owner-input-request'))
  local limit=dfhack.getTickCount()+30000
  while true do local ack=io.open(out..'/owner-input-ack');if ack then ack:close();break end
   assert(dfhack.getTickCount()<limit,'artwork resize timeout');script.sleep(1,'frames')end
  assert(os.remove(out..'/owner-input-ack'));script.sleep(3,'frames');view:render(dfhack.getTickCount())
  shot('work-order-artwork-'..size..'-root')
  assert(click_label('Related to site'));assert(art.current_option==2)
  shot('work-order-artwork-'..size..'-hover')
  back();assert(art.current_option==-1)
 end
 assert(order.specdata.hist_figure_id==before.spec and order.art_spec.type==before.typ and order.art_spec.id==before.id and order.art_spec.subid==before.subid,'Resize changed order')
 records[#records+1]={name='work-order-artwork-resize',screens=#observations,order_unchanged=true}
 return
end
if os.getenv('DF3D_WORK_ORDER_ARTWORK_SUBJECT_HOVER')=='1' then
 for page,label in ipairs({'Related to historical figure','Related to site','Related to civilization or other group'})do
  assert(click_label(label));assert(art.current_option==page)
  shot('work-order-artwork-subject-'..page..'-before')
  g.precise_mouse_x=200;g.precise_mouse_y=190;g.mouse_x=25;g.mouse_y=15;view:render(dfhack.getTickCount())
  shot('work-order-artwork-subject-'..page..'-hover')
  back();assert(art.current_option==-1)
 end
 if os.getenv('DF3D_WORK_ORDER_ARTWORK_WIRE')=='1' then
  local subjects={};for _,row in ipairs(observations)do if row.name:find('%-hover$')then subjects[#subjects+1]={page=row.page,preview=row.preview}end end
  local f=assert(io.open(out..'/work-order-artwork-expected.json','w'));f:write(json.encode({id=order.id,option=option,subjects=subjects}));f:close()
  shot('work-order-artwork-wire')
  f=assert(io.open(out..'/work-order-artwork-wire-result.json'));local result=json.decode(f:read('*a'));f:close();assert(result.success,'Subject hover viewer failed')
  assert(order.specdata.hist_figure_id==before.spec and order.art_spec.type==before.typ and order.art_spec.id==before.id and order.art_spec.subid==before.subid,'Hover changed order')
 end
 records[#records+1]={name='work-order-artwork-subject-hover',screens=#observations}
 return
end
assert(click_label('Specify a new image'));assert(art.current_option==6)
assert(click_label('Creature'));assert(art.current_option==7)
mouse(300,190);assert(art.current_option==6 and #art.new_image.elements==1)
back();shot('work-order-artwork-discard')
assert(click_label('Keep working'),'Keep working absent');assert(art.open and #art.new_image.elements==1)
shot('work-order-artwork-kept')
back();key('LEAVESCREEN');shot('work-order-artwork-discard-escape')
assert(click_label('Keep working'),'Escape changed confirmation')
back();back();shot('work-order-artwork-discard-right')
-- Record whether a second right click cancels confirmation or leaves it visible.
local pending=false;for _,row in ipairs(lines())do if row.text:find('Keep working',1,true)then pending=true end end
if not pending then back()end
assert(click_label('Leave editor and discard data'),'Discard control absent')
shot('work-order-artwork-discarded')
assert(order.specdata.hist_figure_id==before.spec and order.art_spec.type==before.typ and order.art_spec.id==before.id and order.art_spec.subid==before.subid,'Discard changed order')
if os.getenv('DF3D_WORK_ORDER_ARTWORK_WIRE')=='1' then
 local f=assert(io.open(out..'/work-order-artwork-expected.json','w'));f:write(json.encode({id=order.id,option=option}));f:close()
 -- The launcher uses the same owned process lifetime and a bounded30 FPS client.
 f=assert(io.open(out..'/shot.tmp','w'));f:write('work-order-artwork-wire');f:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local deadline=dfhack.getTickCount()+65000
 while true do local ack=io.open(out..'/ack-work-order-artwork-wire');if ack then ack:close();break end;assert(dfhack.getTickCount()<deadline,'artwork viewer timeout');script.sleep(1,'frames')end
 assert(order.specdata.hist_figure_id==before.spec and order.art_spec.type==before.typ and order.art_spec.id==before.id and order.art_spec.subid==before.subid,'Viewer discard changed order')
 f=assert(io.open(out..'/work-order-artwork-wire-result.json'));local result=json.decode(f:read('*a'));f:close();assert(result.success,'Artwork viewer failed')
end
records[#records+1]={name='work-order-artwork-discard',screens=#observations,second_right_keeps_confirmation=pending,order_unchanged=true}
