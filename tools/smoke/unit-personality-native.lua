-- Native Personality reference; diagnostic menu access only in a protected clone.
local unit,view,capture,out=...
local gui=require('gui');local json=require('json')
local g=df.global.gps;local sheet=df.global.game.main_interface.view_sheets
local frame=df.global.world.frame_counter
local original_window={df.global.window_x,df.global.window_y,df.global.window_z}
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
 error('Missing Personality tab '..name)
end
local subjects={unit};local result={pages={}}
for _,candidate in ipairs(df.global.world.units.active)do
 if candidate.military.squad_id>=0 and dfhack.units.isAlive(candidate)then subjects[#subjects+1]=candidate;break end
end
for _,subject in ipairs(subjects)do
 -- Reset the parent page before switching the diagnostic creature.
 select('Overview',15,16)
 sheet.active_id=subject.id;view:render(dfhack.getTickCount());select('Personality',13,16)
 for _,name in ipairs{'Traits','Values','Preferences','Needs'}do
  select(name,17,20)
  local page={unit_id=subject.id,name=name,lines={},tagged_rows={}}
  local source=sheet.personality_raw_str
  for _,text in ipairs(source)do page.tagged_rows[#page.tagged_rows+1]=dfhack.df2utf(text.value)end
  for y=19,g.dimy-1 do local text=dfhack.df2utf(row(y)):gsub('%s+$','');if text~=''then page.lines[#page.lines+1]={y=y,text=text}end end
  g.precise_mouse_x=-100;g.precise_mouse_y=-100;g.mouse_x=-1;g.mouse_y=-1
  capture('unit-personality-'..subject.id..'-'..name:lower():gsub(' ','-'))
  result.pages[#result.pages+1]=page
 end
end
sheet.active_id=unit.id;view:render(dfhack.getTickCount());select('Overview',15,16)
df.global.window_x=original_window[1];df.global.window_y=original_window[2];df.global.window_z=original_window[3]
assert(df.global.pause_state and df.global.world.frame_counter==frame,'Personality reference advanced simulation')
local file=assert(io.open(out..'/unit-personality-native.json','w'));file:write(json.encode(result));file:close()
return result
