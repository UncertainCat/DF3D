-- Protected oracle only: selected crime comes from the native Interrogate
-- closure, never from a runtime provider's menu state.
local out,view,settle,tab,capture=...
local gui=require('gui');local json=require('json');local base=dfhack.internal.getImageBase()
local function click(x,y)
 local g=df.global.gps;g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=y//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1;settle()
end
local samples={}
local function observe(name,label)
 local selected;local scrolling={};local case_feed
 local function walk(w)
  if(w.flag.whole&1)==0 then return end
  if w.name=='Cases' then local _,p=df.sizeof(w);local vt=df.reinterpret_cast('uint64_t',p).value;case_feed=df.reinterpret_cast('uint64_t',vt+8).value-base end
  if df.widget_scroll_rows:is_instance(w)then scrolling[#scrolling+1]={x=w.rect.x1,y=w.rect.y1,scroll=w.scroll,visible=w.num_visible}end
  local _,address=df.sizeof(w.custom_activated)
  local first=df.reinterpret_cast('uint64_t',address).value;local last=df.reinterpret_cast('uint64_t',address+8).value
  assert(last>=first and(last-first)%64==0 and last-first<65536)
  for at=first,last-1,64 do
   local context=df.reinterpret_cast('uint64_t',at+56).value
   if context~=0 then
    local vt=df.reinterpret_cast('uint64_t',context).value
    if df.reinterpret_cast('uint64_t',vt+16).value-base==0x486d70 then
     local crime=df.reinterpret_cast(df.crime,df.reinterpret_cast('uint64_t',context+24).value)
     assert(df.crime.find(crime.id)==crime);selected=crime.id
    end
   end
  end
  if df.widget_container:is_instance(w)then for i,c in ipairs(dfhack.gui.getWidgetChildren(w))do
   if not df.widget_tabs:is_instance(w)or i-1==w.cur_idx then walk(c)end
  end end
 end
 walk(df.global.game.main_interface.info.justice);assert(selected,'Selected native case absent')
 samples[#samples+1]={tab=name,label=label,crime_id=selected,scrolling=scrolling,case_feed=case_feed}
 if os.getenv('DF3D_JUSTICE_CASE_KEYS')~='1' then capture('justice-case-return-'..#samples)end
end
for _,name in ipairs{'Open cases','Cold cases'}do
 tab(name);observe(name,'initial')
 if os.getenv('DF3D_JUSTICE_CASE_KEYS')=='1' then
  for _,side in ipairs{'case','witness'}do
   local g=df.global.gps;g.precise_mouse_x=side=='case'and 100 or 700;g.precise_mouse_y=300;g.mouse_x=g.precise_mouse_x//8;g.mouse_y=25
   for _,key in ipairs{'STANDARDSCROLL_DOWN','STANDARDSCROLL_PAGEDOWN','STANDARDSCROLL_UP','STANDARDSCROLL_PAGEUP'}do
    df.global.enabler.mouse_focus=true;gui.simulateInput(view,key);settle();observe(name,side..':'..key)
   end
  end
  capture('justice-case-keys-'..name:gsub(' ','-'))
 else
  click(100,202);observe(name,'second');tab('Closed cases');tab(name);observe(name,'returned')
 end
end
local f=assert(io.open(out..'/justice-case-return.json','w'));f:write(json.encode(samples));f:close()
