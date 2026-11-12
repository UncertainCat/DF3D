-- Protected discovery only. Widget/callback observations are oracle evidence,
-- never runtime inputs. This lane performs no conviction or interrogation.
local out,view,records=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local g=df.global.gps;local base=dfhack.internal.getImageBase()
local function bytes(address,size)
 local chars={};for offset=0,size-1 do chars[#chars+1]=string.char(df.reinterpret_cast('uint8_t',address+offset).value)end
 return table.concat(chars)
end
local function probe(command,argument,mutation)
 local menu=df.global.game.main_interface.info.justice;local size,address=df.sizeof(menu)
 local before=bytes(address,size);local rng=bytes(base+0x234e990,0x6180);local crimes={}
 for _,crime in ipairs(df.global.world.crimes.all)do
  local n,p=df.sizeof(crime);crimes[#crimes+1]={p=p,n=n,before=bytes(p,n)}
  for _,report in ipairs(crime.witnesses)do local n,p=df.sizeof(report);crimes[#crimes+1]={p=p,n=n,before=bytes(p,n)}end
 end
 local arguments=type(argument)=='table'and argument or(argument and {tostring(argument)}or{})
 local text,rc=dfhack.run_command_silent('df3d',command or 'justice-captions-probe',table.unpack(arguments));assert(rc==0,'Justice provider failed: '..text)
 assert(bytes(address,size)==before,'Justice caption provider changed menu')
 assert(bytes(base+0x234e990,0x6180)==rng,'Justice caption provider advanced randomness')
 if not mutation then for _,crime in ipairs(crimes)do assert(bytes(crime.p,crime.n)==crime.before,'Justice provider changed crime')end end
 return json.decode(text)
end
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
-- Classify the conviction effect's final global write without executing it.
-- This is oracle-only layout evidence, never a runtime menu dependency.
do
 local menu=df.global.game.main_interface.info.justice
 local _,address=df.sizeof(menu:_field('do_init'))
 result.conviction_global={field='game.main_interface.info.justice.do_init',rva=address-base}
 assert(address-base==0x18a6ff0,'Conviction final write is not Justice do_init')
end
if os.getenv('DF3D_JUSTICE_CAPTIONS')=='1' then result.cold_captions=probe()end
if os.getenv('DF3D_JUSTICE_CASES')=='1' then result.cold_cases=probe('justice-cases-probe')end
if os.getenv('DF3D_JUSTICE_CANDIDATES')=='1' then result.cold_candidate_facts=probe('justice-candidate-facts-probe',9)end
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
 local function native_captions()
  local values={}
  local function text(widget)
   if df.widget_text:is_instance(widget)and widget.name=='Text' then values[#values+1]=dfhack.df2utf(widget.str)end
   if df.widget_container:is_instance(widget)then for _,child in ipairs(dfhack.gui.getWidgetChildren(widget))do text(child)end end
  end
  local function find(widget)
   if widget.name=='Cases' then
    -- Native1416040 counts shared row widgets at Cases+2c0/+2c8 and
    -- appends through its embedded container at+160. DFHack does
    -- not expose this concrete widget type. Oracle-only bounded traversal.
    local _,address=df.sizeof(widget)
    local first=df.reinterpret_cast('uint64_t',address+0x2c0).value;local last=df.reinterpret_cast('uint64_t',address+0x2c8).value
    assert(last>=first and (last-first)%16==0 and last-first<=16384,'Invalid native case rows')
    for at=first,last-1,16 do text(df.reinterpret_cast(df.widget,df.reinterpret_cast('uint64_t',at).value))end
   elseif df.widget_container:is_instance(widget)then
    for index,child in ipairs(dfhack.gui.getWidgetChildren(widget))do if not df.widget_tabs:is_instance(widget)or index-1==widget.cur_idx then find(child)end end
   end
  end
  find(info.justice);return values
 end
if os.getenv('DF3D_JUSTICE_CAPTIONS')=='1' then
 caption_click('Open cases')
 local target
 local function find_target(widget)
  local _,address=df.sizeof(widget.custom_activated);local first=df.reinterpret_cast('uint64_t',address).value;local last=df.reinterpret_cast('uint64_t',address+8).value
  for at=first,last-1,64 do
   local context=df.reinterpret_cast('uint64_t',at+56).value
   if context~=0 then
    local vt=df.reinterpret_cast('uint64_t',context).value
    if df.reinterpret_cast('uint64_t',vt+16).value-base==0x486d70 then target=df.reinterpret_cast(df.crime,df.reinterpret_cast('uint64_t',context+24).value)end
   end
  end
  if df.widget_container:is_instance(widget)then for index,child in ipairs(dfhack.gui.getWidgetChildren(widget))do if not df.widget_tabs:is_instance(widget)or index-1==widget.cur_idx then find_target(child)end end end
 end
 find_target(info.justice);assert(target and df.crime.find(target.id)==target,'Native selected case missing')
 local old=target.mode;local samples={}
 local ok,err=xpcall(function()
  for mode=0,18 do
   gui.simulateInput(view,'LEAVESCREEN');settle();target.mode=mode
   local supplied
   for _,row in ipairs(probe())do if row.id==target.id then supplied=row.caption;break end end
   gui.simulateInput(view,'D_JUSTICE');settle()
   local native=native_captions();local found=false
   for _,caption in ipairs(native)do if caption==supplied then found=true end end
   samples[#samples+1]={mode=mode,provider=supplied,native=native}
   write('justice-captions.json',json.encode{crime_id=target.id,cases=samples})
   assert(found and supplied~='','Justice native caption differs for mode '..mode)
  end
 end,debug.traceback)
 target.mode=old;assert(ok,err)
end
if os.getenv('DF3D_JUSTICE_CASES')=='1' then
 local source=debug.getinfo(1,'S').source:sub(2):gsub('justice%-native%.lua$','justice-cases-native.lua')
 assert(loadfile(source))(out,view,probe,settle,caption_click,native_captions)
end
if os.getenv('DF3D_JUSTICE_DETAILS')=='1' then
 local source=debug.getinfo(1,'S').source:sub(2):gsub('justice%-native%.lua$','justice-details-native.lua')
 assert(loadfile(source))(out,view,probe,settle,caption_click,capture)
end
if os.getenv('DF3D_JUSTICE_CANDIDATES')=='1' then
 local source=debug.getinfo(1,'S').source:sub(2):gsub('justice%-native%.lua$','justice-candidates-native.lua')
 assert(loadfile(source))(out,view,probe,settle,caption_click,capture,result.cold_candidate_facts)
end
if os.getenv('DF3D_JUSTICE_PRESENTATION')=='1' then
 local source=debug.getinfo(1,'S').source:sub(2):gsub('justice%-native%.lua$','justice-candidate-presentation-native.lua')
 assert(loadfile(source))(out,view,probe,settle,caption_click,capture)
end
if os.getenv('DF3D_JUSTICE_SORTS')=='1' then
 local source=debug.getinfo(1,'S').source:sub(2):gsub('justice%-native%.lua$','justice-sorts-native.lua')
 assert(loadfile(source))(out,view,probe,settle,caption_click,capture)
end
if os.getenv('DF3D_JUSTICE_CONVICTS')=='1' then
 local source=debug.getinfo(1,'S').source:sub(2):gsub('justice%-native%.lua$','justice-convicts-native.lua')
 assert(loadfile(source))(out,view,probe,settle,caption_click,capture,bytes)
end
if os.getenv('DF3D_JUSTICE_GUARD')=='1' then
 local source=debug.getinfo(1,'S').source:sub(2):gsub('justice%-native%.lua$','justice-guard-native.lua')
 assert(loadfile(source))(out,view,probe,settle,caption_click,capture)
end
if os.getenv('DF3D_JUSTICE_INTELLIGENCE_GRAPH')=='1' then
 local source=debug.getinfo(1,'S').source:sub(2):gsub('justice%-native%.lua$','justice-intelligence-graph-native.lua')
 assert(loadfile(source))(out,view,probe,settle,caption_click,capture,bytes)
end
if os.getenv('DF3D_JUSTICE_INTELLIGENCE_ACTORS')=='1' then
 local source=debug.getinfo(1,'S').source:sub(2):gsub('justice%-native%.lua$','justice-intelligence-actors-native.lua')
 assert(loadfile(source))(out,view,probe,settle,caption_click,capture,bytes)
end
if os.getenv('DF3D_JUSTICE_INTELLIGENCE')=='1' then
 local source=debug.getinfo(1,'S').source:sub(2):gsub('justice%-native%.lua$','justice-intelligence-native.lua')
 assert(loadfile(source))(out,view,probe,settle,caption_click,capture,bytes)
end
if os.getenv('DF3D_JUSTICE_SHEET_NAV')=='1' then
 local samples={}
 for _,name in ipairs{'Fortress guard','Convicts'}do
  if not df.global.game.main_interface.info.open then gui.simulateInput(view,'D_JUSTICE');settle()end
  if df.global.game.main_interface.help.open then
   g.precise_mouse_x=711;g.precise_mouse_y=430;g.mouse_x=88;g.mouse_y=35
   df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L')
   df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1;settle()
  end
  caption_click(name);settle()
  capture('justice-sheet-source-'..#samples)
  local main=df.global.game.main_interface
  local g=df.global.gps;g.precise_mouse_x=380;g.precise_mouse_y=name=='Fortress guard'and 214 or 190;g.mouse_x=47;g.mouse_y=g.precise_mouse_y//12
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
  gui.simulateInput(view,'_MOUSE_L');df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1;settle()
  assert(main.view_sheets.open,'Justice sheet did not open: '..name)
  local sample={tab=name,unit_id=main.view_sheets.active_id,info_open=main.info.open,sheet_type=main.view_sheets.active_sheet}
  sample.skill_groups={}
  sample.thoughts={}
  sample.quote=dfhack.df2utf(main.view_sheets.raw_current_thought)
  sample.thought_layout={columns=main.view_sheets.thought_box_width,quote_columns=main.view_sheets.current_thought_width,quote_lines={},paragraphs={}}
  for _,line in ipairs(main.view_sheets.current_thought.text)do sample.thought_layout.quote_lines[#sample.thought_layout.quote_lines+1]=dfhack.df2utf(line.value)end
  for _,box in ipairs(main.view_sheets.thought_box)do
   local paragraph={}
   for _,line in ipairs(box.line)do
    local _,p=df.sizeof(line);local text=bytes(p,769):match('^[^%z]*');local colors={}
    for i=0,#text-1 do colors[#colors+1]=bytes(p+769+i,1):byte()end
    paragraph[#paragraph+1]={text=dfhack.df2utf(text),colors=colors}
   end
   sample.thought_layout.paragraphs[#sample.thought_layout.paragraphs+1]=paragraph
  end
  local quote_unit=df.unit.find(sample.unit_id);local quote_n,quote_p=df.sizeof(quote_unit);local quote_before=bytes(quote_p,quote_n)
  sample.quote_fallback=probe('creature-quote-fallback-probe',sample.unit_id)
  assert(sample.quote_fallback.equal,'Copied quote inputs differ from native fallback')
  assert(bytes(quote_p,quote_n)==quote_before,'Quote oracle changed original unit')
  for _,text in ipairs(main.view_sheets.raw_thought_str)do sample.thoughts[#sample.thoughts+1]=dfhack.df2utf(text.value)end
  for group,prefix in ipairs{'labor','combat','other'}do
   local count=main.view_sheets[prefix..'_skill_num'];local ids=main.view_sheets[prefix..'_skill_ind']
   for i=0,count-1 do sample.skill_groups[tostring(ids[i])]=group-1 end
  end
  capture('justice-sheet-'..#samples)
  gui.simulateInput(view,'LEAVESCREEN');settle()
  sample.after_escape_info_open=main.info.open;sample.after_escape_sheet_open=main.view_sheets.open
  capture('justice-sheet-back-'..#samples)
  samples[#samples+1]=sample
 end
 local f=assert(io.open(out..'/justice-sheet-navigation.json','w'));f:write(require('json').encode{samples=samples});f:close()
end
if os.getenv('DF3D_JUSTICE_WIRE')=='1' and os.getenv('DF3D_JUSTICE_WIRE_INTELLIGENCE')~='1' and os.getenv('DF3D_JUSTICE_WIRE_GRAPH')~='1' and os.getenv('DF3D_JUSTICE_CONVICTS_SENTENCE')~='1' then
 local source=debug.getinfo(1,'S').source:sub(2):gsub('justice%-native%.lua$','justice-wire-native.lua')
 assert(loadfile(source))(out,probe,bytes)
end
if os.getenv('DF3D_JUSTICE_CONVICTION')=='1' then
 local source=debug.getinfo(1,'S').source:sub(2):gsub('justice%-native%.lua$','justice-conviction-native.lua')
 assert(loadfile(source))(out,view,settle,caption_click,capture)
end
gui.simulateInput(view,'LEAVESCREEN');settle();assert(not info.open,'Justice did not close')
records[#records+1]={name='justice-discovery',closed=true}
