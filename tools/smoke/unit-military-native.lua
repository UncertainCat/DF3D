-- Native Military reference; diagnostic menu access only in a protected clone.
local unit,view,capture,out=...
local gui=require('gui');local json=require('json')
local g=df.global.gps;local sheet=df.global.game.main_interface.view_sheets
local frame=df.global.world.frame_counter
local function row(y)
 local text={};for x=0,g.dimx-1 do local ch=dfhack.screen.readTile(x,y).ch;text[#text+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
 return table.concat(text)
end
local function select(name,first,last)
 for y=first,last do local x=row(y):find(name,1,true);if x then
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
  g.precise_mouse_x=(x-1)*8+4;g.precise_mouse_y=y*12+10;g.mouse_x=x-1;g.mouse_y=y
  df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
  df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
  return
 end end
 error('Missing Military tab '..name)
end
local subjects={unit};local result={pages={}}
for _,candidate in ipairs(df.global.world.units.active)do
 if candidate.military.squad_id>=0 and dfhack.units.isAlive(candidate)then subjects[#subjects+1]=candidate;break end
end
if os.getenv('DF3D_UNIT_MILITARY_MISSING')=='1'then
 local subject=assert(subjects[2]);local squad=assert(df.squad.find(subject.military.squad_id))
 local id=squad.positions[subject.military.squad_position].equipment.assigned_items[0]
 local index,held
 for i,entry in ipairs(subject.inventory)do if entry.item.id==id then index=i;held=entry;break end end
 assert(held,'Expected carried first assigned item');subject.inventory:erase(index)
 _G.df3d_military_restore=function()subject.inventory:insert(index,held);_G.df3d_military_restore=nil end
end
for _,subject in ipairs(subjects)do
 sheet.active_id=subject.id;view:render(dfhack.getTickCount());select('Military',13,16)
 for _,name in ipairs{'Squad','Uniform','Kills'}do
  select(name,17,20)
  local page={unit_id=subject.id,squad_id=subject.military.squad_id,name=name,lines={},tagged_rows={}}
  for y=17,g.dimy-1 do local text=dfhack.df2utf(row(y)):gsub('%s+$','');if text~=''then page.lines[#page.lines+1]={y=y,text=text}end end
  if name=='Kills'then for _,text in ipairs(sheet.kill_description_raw_str)do page.tagged_rows[#page.tagged_rows+1]=dfhack.df2utf(text.value)end end
  result.pages[#result.pages+1]=page;capture('unit-military-'..subject.id..'-'..name:lower())
  if name=='Uniform' and subject~=unit and os.getenv('DF3D_UNIT_MILITARY_MISSING')=='1'then
   local window={df.global.window_x,df.global.window_y,df.global.window_z}
   local squad=assert(df.squad.find(subject.military.squad_id));local id=squad.positions[subject.military.squad_position].equipment.assigned_items[0]
   local item=assert(df.item.find(id));local x,y,z=dfhack.items.getPosition(item)
   df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
   g.precise_mouse_x=868;g.precise_mouse_y=250;g.mouse_x=108;g.mouse_y=20
   local function hover_pointer()
    df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
    g.precise_mouse_x=868;g.precise_mouse_y=250;g.mouse_x=108;g.mouse_y=20
    view:render(dfhack.getTickCount())
   end
   local until_hover=dfhack.getTickCount()+650
   while dfhack.getTickCount()<until_hover do hover_pointer();require('gui.script').sleep(1,'frames')end
   hover_pointer()
   page.hover={id=df.global.game.main_interface.current_hover,lines={}}
   for line=0,17 do
    local text={};for column=g.dimx-24,g.dimx-1 do local pen=dfhack.screen.readTile(column,line);text[#text+1]=pen.ch>=32 and string.char(pen.ch%256)or' 'end
    page.hover.lines[#page.hover.lines+1]=dfhack.df2utf(table.concat(text)):gsub('%s+$','')
   end
   while #page.hover.lines>0 and page.hover.lines[#page.hover.lines]==''do table.remove(page.hover.lines)end
   hover_pointer()
   df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
   df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
   assert(not sheet.open and df.global.window_z==z,'Uniform recenter did not close sheet/focus item')
   page.recenter={item_id=id,target={x,y,z},closed=true};capture('unit-military-uniform-recenter')
   df.global.window_x=window[1];df.global.window_y=window[2];df.global.window_z=window[3]
   sheet.open=true;sheet.active_id=subject.id;view:render(dfhack.getTickCount())
  end
 end
end
sheet.active_id=unit.id;view:render(dfhack.getTickCount());select('Overview',15,16)
assert(df.global.pause_state and df.global.world.frame_counter==frame,'Military reference advanced simulation')
local file=assert(io.open(out..'/unit-military-native.json','w'));file:write(json.encode(result));file:close()
return result
