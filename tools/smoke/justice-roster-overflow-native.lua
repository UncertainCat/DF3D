-- Protected oracle: temporary semantic crimes in the owned, paused clone.
-- Never copy crime vectors or retain fixture pointers after closing Justice.
local out,view,probe,settle,tab,capture,bytes=...
local gui=require('gui');local json=require('json')
local crimes=df.global.world.crimes.all
local original_count=#crimes;local added={};local samples={};local provider_ids={}
local template=assert(df.crime.find(9),'Overflow fixture requires crime9')
local used={};local next_id=0
for _,crime in ipairs(crimes)do used[crime.accused]=true;next_id=math.max(next_id,crime.id+1)end
local function observe(label)
 local list;local scrolling={};local names={}
 local function walk(w)
  if(w.flag.whole&1)==0 then return end
  if df.widget_unit_list:is_instance(w)then list=w end
  if df.widget_unit_name:is_instance(w)and w.u then names[#names+1]={id=w.u.id,y=w.rect.y1}end
  if df.widget_scroll_rows:is_instance(w)then scrolling[#scrolling+1]={x=w.rect.x1,y=w.rect.y1,scroll=w.scroll,visible=w.num_visible}end
  if df.widget_container:is_instance(w)then for i,c in ipairs(dfhack.gui.getWidgetChildren(w))do
   if (not df.widget_tabs:is_instance(w)or i-1==w.cur_idx)and(not df.widget_scroll_rows:is_instance(w)or(i>w.scroll and i<=w.scroll+w.num_visible))then walk(c)end
  end end
 end
 walk(df.global.game.main_interface.info.justice);assert(list,'Convicts list absent')
 table.sort(names,function(a,b)return a.y<b.y end)
 local ids={};for _,name in ipairs(names)do ids[#ids+1]=name.id end
 samples[#samples+1]={label=label,cursor=list.cursor_idx,scrolling=scrolling,visible_ids=ids}
end
local ok,err=xpcall(function()
 gui.simulateInput(view,'LEAVESCREEN');settle()
 for _,unit in ipairs(df.global.world.units.active)do
  if not used[unit.id]and unit.civ_id==df.global.plotinfo.civ_id and unit.hist_figure_id>=0 then
   local crime=df.crime:new();added[#added+1]=crime
   for _,field in ipairs{'mode','victim','incident_id','event_year','event_time','discovered_year','discovered_time','site','entity','item_id','agreement_id'}do crime[field]=template[field]end
   crime.id=next_id;next_id=next_id+1;crime.criminal=unit.id;crime.accused=unit.id
   crime.flags.whole=template.flags.whole;crime.flags.discovered=true
   crimes:insert('#',crime);used[unit.id]=true
   if #added==24 then break end
  end
 end
 assert(#added==24,'Insufficient fixture units')
 local rows=probe('justice-convicts-probe');assert(#rows>=24,'Owned roster did not include fixture crimes')
 gui.simulateInput(view,'D_JUSTICE');settle()
 if df.global.game.main_interface.help.open then
  local g=df.global.gps;g.precise_mouse_x=711;g.precise_mouse_y=430;g.mouse_x=88;g.mouse_y=35
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
  gui.simulateInput(view,'_MOUSE_L');df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1;settle()
  assert(not df.global.game.main_interface.help.open,'Help intercepted overflow fixture')
 end
 tab('Convicts');observe('initial')
 for _=1,22 do df.global.enabler.mouse_focus=true;gui.simulateInput(view,'STANDARDSCROLL_DOWN');settle()end
 observe('down22');capture('justice-roster-overflow-down')
 tab('Fortress guard');tab('Convicts');observe('returned');capture('justice-roster-overflow-return')
 assert(samples[2].cursor==22 and samples[3].cursor==22,'Native did not retain overflow cursor')
 local scrolled=false
 for _,scroll in ipairs(samples[2].scrolling)do if scroll.scroll>0 then scrolled=true end end
 assert(scrolled,'Fixture failed to overflow')
 for _,row in ipairs(rows)do provider_ids[#provider_ids+1]=row.unit_id end
 local f=assert(io.open(out..'/justice-roster-overflow.json','w'));f:write(json.encode{samples=samples,provider_ids=provider_ids});f:close()
 if os.getenv('DF3D_JUSTICE_WIRE')=='1' then
  local source=debug.getinfo(1,'S').source:sub(2):gsub('justice%-roster%-overflow%-native%.lua$','justice-wire-native.lua')
  assert(loadfile(source))(out,probe,bytes)
 end
end,debug.traceback)
if df.global.game.main_interface.info.open then gui.simulateInput(view,'LEAVESCREEN');settle()end
for index=#added,1,-1 do
 local crime=added[index]
 if #crimes>original_count and crimes[#crimes-1]==crime then crimes:erase(#crimes-1)end
 crime:delete()
end
assert(#crimes==original_count,'Fixture crime count not restored')
local f=assert(io.open(out..'/justice-roster-overflow.json','w'));f:write(json.encode{samples=samples,provider_ids=provider_ids,restored=true,error=not ok and err or nil});f:close()
assert(ok,err)
gui.simulateInput(view,'D_JUSTICE');settle()
