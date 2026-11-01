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
for _,subject in ipairs(subjects)do
 sheet.active_id=subject.id;view:render(dfhack.getTickCount());select('Military',13,16)
 for _,name in ipairs{'Squad','Uniform','Kills'}do
  select(name,17,20)
  local page={unit_id=subject.id,squad_id=subject.military.squad_id,name=name,lines={},tagged_rows={}}
  for y=17,g.dimy-1 do local text=dfhack.df2utf(row(y)):gsub('%s+$','');if text~=''then page.lines[#page.lines+1]={y=y,text=text}end end
  if name=='Kills'then for _,text in ipairs(sheet.kill_description_raw_str)do page.tagged_rows[#page.tagged_rows+1]=dfhack.df2utf(text.value)end end
  result.pages[#result.pages+1]=page;capture('unit-military-'..subject.id..'-'..name:lower())
 end
end
sheet.active_id=unit.id;view:render(dfhack.getTickCount());select('Overview',15,16)
assert(df.global.pause_state and df.global.world.frame_counter==frame,'Military reference advanced simulation')
local file=assert(io.open(out..'/unit-military-native.json','w'));file:write(json.encode(result));file:close()
return result
