-- Native oracle only, run by the protected owned unsaved lane.
local out,view,records=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local g=df.global.gps;local m=df.global.game.main_interface
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
local function shot(name,order)
 view:render(dfhack.getTickCount())
 local d=m.job_details
 local row={name=name,lines=lines(),order={id=order.id,job_type=order.job_type,specdata=order.specdata.hist_figure_id,art_type=order.art_spec.type,art_id=order.art_spec.id,art_subid=order.art_spec.subid},kind=d.current_option,
  dye_target=values(d.dye_object_target_color),dye_available=values(d.dye_object_target_color_available),dye_tint=values(d.dye_object_target_color_is_tint),tint=d.dye_object_tint_color,
  dye_reagent1=values(d.dye_object_tint_reagent_color1),dye_reagent2=values(d.dye_object_tint_reagent_color2),dye_reagent_available=values(d.dye_object_tint_reagent_available),
  mix_target=values(d.mix_dye_target_color),mix_available=values(d.mix_dye_target_color_available),mix_selected=d.mix_dye_chosen_target_color,
  mix_reagent1=values(d.mix_dye_reagent_color1),mix_reagent2=values(d.mix_dye_reagent_color2),mix_reagent_available=values(d.mix_dye_reagent_available)}
 observations[#observations+1]=row
 if os.getenv('DF3D_WORK_ORDER_DYE_COMPARE')=='1' then
  local target=row.kind==4 and row.tint or row.mix_selected
  local text,code=dfhack.run_command_silent('df3d','work-order-dye-probe',tostring(order.id),tostring(target))
  assert(code==0,'Owned dye provider failed: '..text)
  local owned=json.decode(text);row.owned=owned
  local first=row.kind==4 and row.dye_reagent1 or row.mix_reagent1
  local second=row.kind==4 and row.dye_reagent2 or row.mix_reagent2
  local colors=row.kind==4 and row.dye_target or row.mix_target
  local available=target>=0 and(row.kind==4 and row.dye_reagent_available or row.mix_reagent_available)or(row.kind==4 and row.dye_available or row.mix_available)
  assert(#owned.rows==#available,'Owned dye choice count differs')
  for i,value in ipairs(owned.rows)do
   assert(value.available==available[i],'Owned dye availability differs at '..i)
   if target>=0 then assert(value.first==first[i] and value.second==second[i],'Owned dye ingredient order differs at '..i)
   else assert(value.color==colors[i] and value.tint==(row.kind==5 or row.dye_tint[i]),'Owned dye target order differs at '..i)end
  end
 end
 local f=assert(io.open(out..'/work-order-dye-reference.json','w'));f:write(json.encode(observations));f:close()
 f=assert(io.open(out..'/shot.tmp','w'));f:write(name);f:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local deadline=dfhack.getTickCount()+30000
 while true do local ack=io.open(out..'/ack-'..name);if ack then ack:close();break end;assert(dfhack.getTickCount()<deadline,'dye capture timeout');script.sleep(1,'frames')end
end
-- Diagnostic manager eligibility, restored before leaving the unsaved clone.
local fortress=assert(df.global.plotinfo.main.fortress_entity)
local responsibility=df.entity_position_responsibility.MANAGE_PRODUCTION
local position,assignment
for _,a in ipairs(fortress.positions.assignments)do
 if a.histfig>=0 then
  local present=false;for _,u in ipairs(df.global.world.units.active)do if u.hist_figure_id==a.histfig then present=true;break end end
  if present then for _,p in ipairs(fortress.positions.own)do if p.id==a.position_id then position=p;assignment=a;break end end end
 end
 if position then break end
end
assert(position,'Dye reference requires occupied fortress office')
local prior=position.responsibilities[responsibility];local indexed=fortress.assignments_by_type[responsibility];local old=values(indexed)
position.responsibilities[responsibility]=true;indexed:insert('#',assignment)
local ok,err=xpcall(function()
 key('D_ORDERS');assert(m.info.open)
 for _,spec in ipairs{{query='dye cloth',job=191,kind=4},{query='mix dye',job=243,kind=5}}do
  mouse(944,142);assert(m.create_work_order.open,'Global order picker did not open')
  mouse(600,94)
  for char in spec.query:gmatch('.')do key(('STRING_A%03d'):format(char:byte()))end
  key('SELECT');local before=#df.global.world.manager_orders.all
  mouse(600,130);assert(not m.create_work_order.open,'Dye recipe did not close picker')
  assert(#df.global.world.manager_orders.all==before+1,'Dye order was not created')
  local order=df.global.world.manager_orders.all[before];assert(order.job_type==spec.job,'Wrong dye recipe')
  local w=m.info.work_orders;w.scroll_position_work_orders=math.max(0,before-14);view:render(dfhack.getTickCount())
  mouse(584,142+(before-w.scroll_position_work_orders)*36)
  local d=m.job_details;assert(d.open and d.wq==order,'Dye Details did not open')
  local slot;for i,kind in ipairs(d.option)do if kind==spec.kind then slot=i;break end end
  assert(slot,'Dye Details option missing');mouse(200,106+slot*36)
  assert(d.current_option==spec.kind,'Dye color chooser did not open')
  shot('work-order-dye-'..spec.kind..'-targets',order)
  -- Select the first tint/mix target from its visible native row. Diagnostic
  -- scrolling exposes the row; the actual click drives native navigation.
  local at=0
  if spec.kind==4 then
   at=nil;for i,tint in ipairs(d.dye_object_target_color_is_tint)do if tint then at=i;break end end
  end
  local targets=spec.kind==4 and d.dye_object_target_color or d.mix_dye_target_color
  if at and #targets>at then
   local target=targets[at];local caption=df.global.world.raws.descriptors.colors[target].name
   if spec.kind==4 then d.scroll_position_dye_object=at else d.scroll_position_mix_dye=at end
   view:render(dfhack.getTickCount())
   local clicked=false
   for _,line in ipairs(lines())do if line.y>=12 and line.text:find(caption,1,true)then mouse(200,line.y*12+6);clicked=true;break end end
   assert(clicked,'Dye target caption not visible')
   assert((spec.kind==4 and d.dye_object_tint_color==target)or(spec.kind==5 and d.mix_dye_chosen_target_color==target),'Dye reagent stage did not open')
   shot('work-order-dye-'..spec.kind..'-reagents',order)
  end
  while d.open do key('LEAVESCREEN')end
 end
end,debug.traceback)
position.responsibilities[responsibility]=prior;indexed:resize(0);for _,a in ipairs(old)do indexed:insert('#',a)end
assert(ok,err)
records[#records+1]={name='work-order-dye-reference',screens=#observations}
