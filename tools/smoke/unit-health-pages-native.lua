-- Native Health page oracle in the owned unsaved clone.
local unit,view,capture,out=...
local gui=require('gui');local json=require('json')
local g=df.global.gps;local sheet=df.global.game.main_interface.view_sheets
local frame=df.global.world.frame_counter;local original=sheet.active_sub_tab
local function row(y)
 local text={};for x=0,g.dimx-1 do local p=dfhack.screen.readTile(x,y);text[#text+1]=p.ch>=32 and string.char(p.ch%256) or ' ' end
 return table.concat(text)
end
local function click(x,y)
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
end
local pages={}
local ok,err=xpcall(function()
 assert(sheet.open and sheet.active_id==unit.id,'Expected creature sheet')
 click(616,196)
 for _,name in ipairs{'Status','Wounds','Treatment','History','Description'}do
  local found=false
  for y=17,20 do
   local first,last=row(y):find(name,1,true)
   if first then click((first-1)*8+4,y*12+10);found=true;break end
  end
  assert(found,'Missing Health tab '..name)
  local sample={name=name,lines={}}
  for y=18,g.dimy-1 do local text=dfhack.df2utf(row(y)):gsub('%s+$','');if text~=''then sample.lines[#sample.lines+1]={y=y,text=text}end end
  pages[#pages+1]=sample
  capture('unit-health-page-'..name:lower())
 end
end,debug.traceback)
click(464,196)
assert(sheet.active_sub_tab==original,'Health reference did not return to Overview')
assert(df.global.pause_state and df.global.world.frame_counter==frame,'Health reference advanced simulation')
local result={success=ok,unit_id=unit.id,pages=pages,error=not ok and err or nil}
local file=assert(io.open(out..'/unit-health-pages-native.json','w'));file:write(json.encode(result));file:close()
assert(ok,err);return result
