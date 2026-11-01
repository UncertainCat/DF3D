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
local base=dfhack.internal.getImageBase()
local entity=assert(df.global.plotinfo.main.fortress_entity)
local _,entity_address=df.sizeof(entity)
assert(df.reinterpret_cast('uint64_t',base+0x239a1e8).value==entity_address,'Health fortress entity global differs')
local function native_string(value)
 if type(value)=='string'then return dfhack.df2utf(value)end
 local _,address=df.sizeof(value)
 local size=df.reinterpret_cast('uint64_t',address+16).value
 local capacity=df.reinterpret_cast('uint64_t',address+24).value
 assert(size>=0 and size<=65536 and capacity>=size,'Invalid native Health string')
 local data=capacity<16 and address or df.reinterpret_cast('uint64_t',address).value
 local bytes=df.new('uint8_t',math.max(1,size));dfhack.internal.memmove(bytes,data,size)
 local text={};for i=0,size-1 do text[#text+1]=string.char(bytes[i])end;df.delete(bytes)
 return dfhack.df2utf(table.concat(text))
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
  local sample={name=name,lines={},tagged_rows={}}
  for _,text in ipairs(sheet.unit_health_raw_str)do sample.tagged_rows[#sample.tagged_rows+1]=native_string(text)end
  sample.color_box_count=#sheet.unit_health_box
  for y=18,g.dimy-1 do local text=dfhack.df2utf(row(y)):gsub('%s+$','');if text~=''then sample.lines[#sample.lines+1]={y=y,text=text}end end
  pages[#pages+1]=sample
  capture('unit-health-page-'..name:lower())
 end
end,debug.traceback)
click(464,196)
assert(sheet.active_sub_tab==original,'Health reference did not return to Overview')
assert(df.global.pause_state and df.global.world.frame_counter==frame,'Health reference advanced simulation')
local result={success=ok,unit_id=unit.id,fortress_entity_global_verified=true,pages=pages,error=not ok and err or nil}
local file=assert(io.open(out..'/unit-health-pages-native.json','w'));file:write(json.encode(result));file:close()
assert(ok,err);return result
