-- Protected discovery only. Widget/callback observations are oracle evidence,
-- never runtime inputs. This lane performs no conviction or interrogation.
local out,view,records=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local g=df.global.gps;local base=dfhack.internal.getImageBase()
local function write(name,value)local f=assert(io.open(out..'/'..name,'w'));f:write(value);f:close()end
local function settle()for _=1,3 do script.sleep(1,'frames')end;view:render(dfhack.getTickCount())end
local function lines()
 local result={}
 for y=0,g.dimy-1 do
  local chars={};for x=0,g.dimx-1 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
  result[#result+1]={y=y,text=dfhack.df2utf(table.concat(chars)):gsub('%s+$','')}
 end
 return result
end
local function caption_click(caption)
 local target
 local function find(widget)
  if df.widget_tabs:is_instance(widget)then
   local x=widget.rect.x1
   for _,label in ipairs(widget.tab_labels)do
    if label==caption then target={widget=widget,x=x+math.floor((#label+4)/2),y=widget.rect.y1+1};return end
    x=x+#label+4
   end
  end
  if df.widget_container:is_instance(widget)then for _,child in ipairs(dfhack.gui.getWidgetChildren(widget))do if not target then find(child)end end end
 end
 find(df.global.game.main_interface.info.justice)
 assert(target,'Justice caption missing: '..caption)
 g.mouse_x=target.x;g.mouse_y=target.y;g.precise_mouse_x=target.x*8+4;g.precise_mouse_y=target.y*12+6
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
 settle();return target.widget.cur_idx
end
local function capture(name)
 write('shot.tmp',name);assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local deadline=dfhack.getTickCount()+10000
 while true do local f=io.open(out..'/ack-'..name);if f then f:close();return end
  assert(dfhack.getTickCount()<deadline,'Justice capture timeout');script.sleep(1,'frames')
 end
end
local function callbacks(vector)
 local _,address=df.sizeof(vector);local first=df.reinterpret_cast('uint64_t',address).value;local last=df.reinterpret_cast('uint64_t',address+8).value
 assert(last>=first and (last-first)%64==0 and last-first<=65536)
 local result={}
 for at=first,last-1,64 do
  local context=df.reinterpret_cast('uint64_t',at+56).value
  if context~=0 then local vt=df.reinterpret_cast('uint64_t',context).value;result[#result+1]=df.reinterpret_cast('uint64_t',vt+16).value-base end
 end
 return result
end
local result={tabs={},crimes={}}
for _,crime in ipairs(df.global.world.crimes.all)do
 result.crimes[#result.crimes+1]={id=crime.id,mode=crime.mode,site=crime.site,entity=crime.entity,criminal=crime.criminal,accused=crime.accused,victim=crime.victim,flags=crime.flags.whole,event_year=crime.event_year,event_time=crime.event_time,discovered_year=crime.discovered_year,discovered_time=crime.discovered_time}
end
gui.simulateInput(view,'D_JUSTICE');settle()
if df.global.game.main_interface.help.open then
 -- Protected173318 locates the first-use Justice help's Okay button here.
 g.mouse_x=88;g.mouse_y=35;g.precise_mouse_x=711;g.precise_mouse_y=430
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
 settle();assert(not df.global.game.main_interface.help.open,'Justice first-use help did not close')
end
local info=df.global.game.main_interface.info
assert(info.open and info.current_mode==df.info_interface_mode_type.JUSTICE,'Justice did not open')
local source=debug.getinfo(1,'S').source:sub(2):gsub('smoke/justice%-native%.lua$','ui_bake/capture_widgets.lua')
for index,caption in ipairs{'Open cases','Closed cases','Cold cases','Fortress guard','Convicts','Intelligence'}do
 local selected=caption_click(caption)
 local observed={caption=caption,selected=selected,mode=info.justice.current_mode,lines=lines(),callbacks={}}
 assert(selected==index-1,'Justice selected wrong category')
 local function walk(widget,depth)
  assert(depth<32,'Justice widget depth exceeded')
  if (widget.flag.whole&1)==0 then return end
  if #widget.custom_feed+#widget.custom_logic+#widget.custom_render+#widget.custom_activated>0 then
   observed.callbacks[#observed.callbacks+1]={name=widget.name,rect={widget.rect.x1,widget.rect.y1,widget.rect.x2,widget.rect.y2},feed=callbacks(widget.custom_feed),logic=callbacks(widget.custom_logic),render=callbacks(widget.custom_render),activated=callbacks(widget.custom_activated)}
  end
  if df.widget_container:is_instance(widget)then for child_index,child in ipairs(dfhack.gui.getWidgetChildren(widget))do if not df.widget_tabs:is_instance(widget)or child_index-1==widget.cur_idx then walk(child,depth+1)end end end
 end
 walk(info.justice,0)
 result.tabs[#result.tabs+1]=observed
 assert(loadfile(source))(out..'/justice-widgets-'..(index-1)..'.json','templates')
 write('justice-native.json',json.encode(result));capture('justice-tab-'..(index-1))
end
gui.simulateInput(view,'LEAVESCREEN');settle();assert(not info.open,'Justice did not close')
records[#records+1]={name='justice-discovery',closed=true}
