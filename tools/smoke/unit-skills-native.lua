-- Read native Skills presentation in the owned paused unsaved diagnostic.
local unit,view,capture,out=...
local gui=require('gui');local json=require('json')
local g=df.global.gps;local sheet=df.global.game.main_interface.view_sheets
local frame=df.global.world.frame_counter
local function row(y)
 local text={};for x=0,g.dimx-1 do local p=dfhack.screen.readTile(x,y);text[#text+1]=p.ch>=32 and string.char(p.ch%256)or' 'end
 return table.concat(text)
end
local function click(x,y)
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
end
local function select(name,first,last)
 for y=first,last do local x=row(y):find(name,1,true);if x then click((x-1)*8+4,y*12+10);return end end
 error('Missing native Skills tab '..name)
end
local pages={}
local ok,err=xpcall(function()
 assert(sheet.open and sheet.active_id==unit.id,'Expected creature sheet')
 select('Skills',15,16)
 for _,name in ipairs{'Labor','Combat','Social','Other skills','Knowledge'}do
  select(name,17,20)
  local page={name=name,tab=sheet.unit_skill_active_tab,first=sheet.scroll_position_unit_skill,skills={},values={},rust_values={},lines={}}
  for _,v in ipairs(sheet.unit_skill)do page.skills[#page.skills+1]=v end
  for _,v in ipairs(sheet.unit_skill_val)do page.values[#page.values+1]=v end
  for _,v in ipairs(sheet.unit_skill_val_w_rust)do page.rust_values[#page.rust_values+1]=v end
  for y=17,g.dimy-1 do local text=dfhack.df2utf(row(y)):gsub('%s+$','');if text~=''then page.lines[#page.lines+1]={y=y,text=text}end end
  pages[#pages+1]=page;capture('unit-skills-'..name:lower():gsub(' ','-'))
 end
end,debug.traceback)
select('Overview',15,16)
assert(df.global.pause_state and df.global.world.frame_counter==frame,'Skills reference advanced simulation')
local result={success=ok,unit_id=unit.id,pages=pages,error=not ok and err or nil}
local f=assert(io.open(out..'/unit-skills-native.json','w'));f:write(json.encode(result));f:close()
assert(ok,err);return result
