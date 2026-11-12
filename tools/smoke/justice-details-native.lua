-- Read-only providers; temporary date changes are confined to the paused clone.
local out,view,probe,settle,tab,capture=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local info=df.global.game.main_interface.info;local crime=df.crime.find(9)
local function click(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=y//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1;settle()
end
local function dates()
 local result={};local pending
 local function walk(w)
  if df.widget_text:is_instance(w)then
   local s=dfhack.df2utf(w.str)
   if s:sub(1,6)=='Date: 'then pending=s
   elseif s:sub(1,10)=='Reported: 'then assert(pending,'Native Reported without Date');result[#result+1]={date=pending,reported=s};pending=nil end
  end
  if df.widget_container:is_instance(w)then for index,child in ipairs(dfhack.gui.getWidgetChildren(w))do if not df.widget_tabs:is_instance(w)or index-1==w.cur_idx then walk(child)end end end
 end
 walk(info.justice);return result
end
tab('Open cases');click(100,202);click(100,166)
local reference={crime_id=9,cases={}}
if os.getenv('DF3D_JUSTICE_WITNESSES')=='1' then
 local source=debug.getinfo(1,'S').source:sub(2):gsub('justice%-details%-native%.lua$','justice-witnesses-native.lua')
 assert(loadfile(source))(out,probe,click,crime,info)
 return
end
local function summary()
 local result={}
 local function walk(w)
  if df.widget_text:is_instance(w)then
   local s=dfhack.df2utf(w.str)
   if s:sub(1,15)=='Injured party: 'then result.injured_party=s
   elseif s:sub(1,11)=='Convicted: 'or s=='Unknown convict.'or s=='Unsolved.'then
    result.status=s;result.resolution=s=='Unsolved.'and 1 or(s=='Unknown convict.'and 3 or 2)
    assert(w.fg==(result.resolution==1 and 3 or 5) and w.bright,'Unexpected native status color')
   end
  end
  if df.widget_container:is_instance(w)then for index,child in ipairs(dfhack.gui.getWidgetChildren(w))do if not df.widget_tabs:is_instance(w)or index-1==w.cur_idx then walk(child)end end end
 end
 walk(info.justice);return result
end
if os.getenv('DF3D_JUSTICE_SUMMARY')=='1' then
 local original={victim=crime.victim,accused=crime.accused,flags=crime.flags.whole}
 local samples={}
 local ok,err=xpcall(function()
  for _,case in ipairs{
   {name='baseline',victim=original.victim,accused=original.accused},
   {name='no-victim',victim=-1,accused=-1},
   {name='missing-victim',victim=2147483647,accused=-1},
   {name='convicted',victim=original.victim,accused=crime.criminal},
   {name='unknown-convict',victim=original.victim,accused=2147483647},
   {name='no-trial-unsolved',victim=original.victim,accused=-1,no_trial=true},
  }do
   crime.victim=case.victim;crime.accused=case.accused;crime.flags.whole=original.flags
   if case.no_trial then crime.flags.needs_trial=false end
   click(100,202);click(100,166)
   local native=summary();local owned=probe('justice-summary-probe',9)
   samples[#samples+1]={case=case,native=native,owned=owned}
   local f=assert(io.open(out..'/justice-summary.json','w'));f:write(json.encode(samples));f:close()
   assert(native.status and json.encode(native)==json.encode(owned),'Justice summary differs: '..case.name)
  end
 end,debug.traceback)
 crime.victim=original.victim;crime.accused=original.accused;crime.flags.whole=original.flags
 click(100,202);click(100,166)
 assert(ok,err)
 return
end
local report=crime.witnesses[0];assert(report,'Fixture requires witness')
local original=report.reported_year
local ok,err=xpcall(function()
 for _,crossyear in ipairs{false,true}do
  report.reported_year=crossyear and report.year+1 or original
  click(100,202);click(100,166)
  local native=dates();local owned=probe('justice-witness-dates-probe',9)
  reference.cases[#reference.cases+1]={crossyear=crossyear,year=report.year,reported_year=report.reported_year,native=native,owned=owned}
  local f=assert(io.open(out..'/justice-details.json','w'));f:write(json.encode(reference));f:close()
  assert(#native==#crime.witnesses and #native>0,'Native witness date rows missing')
  assert(json.encode(native)==json.encode(owned),'Owned witness dates differ from native')
 end
 capture('justice-witness-dates')
end,debug.traceback)
report.reported_year=original
click(100,202);click(100,166)
assert(ok,err)
