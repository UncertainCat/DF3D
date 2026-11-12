-- Protected oracle only: observe native widget focus and sorting, never runtime input.
local out,view,settle,tab,capture=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local function click(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=y//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1;settle()
end
local samples={}
local navigation=os.getenv('DF3D_JUSTICE_PICKER_NAV')=='1'
local list_navigation=os.getenv('DF3D_JUSTICE_LIST_NAV')=='1'
for attempt,name in ipairs((list_navigation or navigation)and {'Interrogate','Convict','Interrogate','Convict'}or{'Fortress guard','Convicts','Interrogate','Convict'})do
 if name=='Interrogate'or name=='Convict'then
  tab('Open cases');click(100,202);click(100,166);click(name=='Interrogate'and 560 or 652,190)
 else tab(name)end
 local function observe(label)
  local filter,list;local ids={};local scrolling={}
  local function walk(w)
   if (w.flag.whole&1)==0 then return end
   if w.name=='Filter box'then filter=w end
   if df.widget_unit_list:is_instance(w)then list=w end
   if df.widget_scroll_rows:is_instance(w)then scrolling[#scrolling+1]={x=w.rect.x1,y=w.rect.y1,scroll=w.scroll,visible=w.num_visible}end
   if df.widget_unit_name:is_instance(w)and w.u then ids[#ids+1]=w.u.id end
   if df.widget_container:is_instance(w)then for i,c in ipairs(dfhack.gui.getWidgetChildren(w))do
    if not df.widget_tabs:is_instance(w)or i-1==w.cur_idx then walk(c)end
   end end
  end
  walk(df.global.game.main_interface.info.justice)
  if not filter then
   samples[#samples+1]={tab=name,label=label,filter_absent=true,info_open=df.global.game.main_interface.info.open,sheet_open=df.global.game.main_interface.view_sheets.open}
   local file=assert(io.open(out..'/justice-keyboard.json','w'));file:write(json.encode(samples));file:close()
   return
  end
  local sorts={};if list then for _,entry in ipairs(list.sorting_by)do sorts[#sorts+1]=entry.ident end end
  local _,address=df.sizeof(filter);local focused=false
  if df.global.gview.cur_textbox then local _,p=df.sizeof(df.global.gview.cur_textbox);focused=p==address end
  local vt=df.reinterpret_cast('uint64_t',address).value
  samples[#samples+1]={tab=name,label=label,flags=filter.flag.whole,focused=focused,sorts=sorts,ids=ids,scrolling=scrolling,cursor=list and list.cursor_idx or -1,filter_feed=df.reinterpret_cast('uint64_t',vt+8).value-dfhack.internal.getImageBase()}
  local file=assert(io.open(out..'/justice-keyboard.json','w'));file:write(json.encode(samples));file:close()
 end
 local function key(label,event)
  df.global.enabler.mouse_focus=true;gui.simulateInput(view,event);settle();observe(label)
 end
 if list_navigation then
  if attempt>2 then key('filter','FILTER')end
  observe('initial')
  for _,event in ipairs{'STANDARDSCROLL_DOWN','STANDARDSCROLL_DOWN','STANDARDSCROLL_PAGEDOWN','STANDARDSCROLL_UP','STANDARDSCROLL_PAGEUP','CONTEXT_SCROLL_DOWN','CONTEXT_SCROLL_PAGEDOWN'}do
   g.precise_mouse_x=700;g.precise_mouse_y=400;g.mouse_x=87;g.mouse_y=33
   key(event,event);capture('justice-list-nav-'..#samples)
  end
 elseif navigation then
  observe('initial')
  if #samples>6 then key('filter','FILTER')end
  key('left','STANDARDSCROLL_LEFT');capture('justice-nav-left-'..#samples)
  key('right','STANDARDSCROLL_RIGHT');capture('justice-nav-right-'..#samples)
 else
 observe('initial');key('name-sort','UNITLIST_SORT_NAME');key('filter','FILTER')
 -- Text entry is SDL text input, not these interface-key events. Do not send
 -- SELECT as a textbox Enter: it can activate the selected conviction row.
 click(900,680);observe('finish');capture('justice-keyboard-'..#samples)
 end
end
local file=assert(io.open(out..'/justice-keyboard.json','w'));file:write(json.encode(samples));file:close()
