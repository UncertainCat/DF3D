-- Protected oracle only: synthetic reports live in the paused disposable clone.
-- These labels test copying/wrapping and are never product UI copy.
local out,view,probe,settle,tab,capture,bytes=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local reports=df.global.world.status.interrogation_reports;local original=#reports
local added={};local samples={}
local function write()local f=assert(io.open(out..'/justice-intelligence.json','w'));f:write(json.encode(samples));f:close()end
local function click(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=y//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1;settle()
end
local ok,err=xpcall(function()
 assert(original==0,'Intelligence oracle requires empty baseline')
 assert(#probe('justice-intelligence-reports-probe',80)==0)
 local long=os.getenv('DF3D_JUSTICE_REPORT_SCROLL')=='1'
 for i=1,2 do
  local r=df.interrogation_report:new();r.title='Synthetic interrogation report '..i..': a deliberately long title for native wrapping verification.'
  r.officer_name='Synthetic officer '..i;r.officer_hf=-1;r.subject_hf=-1;r.subject_identity_id=-1;r.flags.whole=0
  reports:insert('#',r);added[#added+1]=r
  for _,text in ipairs{'Synthetic detail paragraph: '..string.rep('native wrapping words ',12),'Second synthetic detail paragraph.'}do
   local line=df.new('string');line.value=text;r.details:insert('#',line)
  end
  if long then
   for n=1,80 do local line=df.new('string');line.value='Synthetic report paragraph '..n..': native scrolling reference.';r.details:insert('#',line)end
  end
 end
 gui.simulateInput(view,'LEAVESCREEN');settle();gui.simulateInput(view,'D_JUSTICE');settle();if df.global.game.main_interface.help.open then click(711,430)end;tab('Intelligence')
 local menu=df.global.game.main_interface.info.justice
 assert(#menu.interrogation_report==2,'Native report roster differs')
 local reference=probe('justice-intelligence-reports-probe',80)
 for i,r in ipairs(added)do assert(reference[i].title==r.title and menu.interrogation_report[i-1]==r,'Native report order differs')end
 samples[#samples+1]={name='roster',provider=reference};write();capture('justice-intelligence-roster')
 -- Native report rows begin below the four Intelligence sub-tabs.
 click(120,190)
 assert(menu.viewing_interrogation_report==added[1],'Report row did not open')
 local native={};for _,line in ipairs(menu.interrogation_report_box.text)do native[#native+1]=dfhack.df2utf(line.value)end
 local columns=menu.interrogation_report_box_width;local supplied=probe('justice-intelligence-reports-probe',columns)
 samples[#samples+1]={name='detail',columns=columns,native=native,provider=supplied[1],viewed=added[1].flags.viewed};write()
 assert(json.encode(native)==json.encode(supplied[1].lines),'Native report wrapping differs')
 capture('justice-intelligence-detail')
 if long then
  local function record_scroll(name)
   samples[#samples+1]={name=name,first=menu.scroll_position_interrogation_report};write();capture('justice-intelligence-'..name)
  end
  for _,step in ipairs{{'CONTEXT_SCROLL_DOWN','report-wheel'},{'CONTEXT_SCROLL_PAGEDOWN','report-page'}}do
   g.precise_mouse_x=200;g.precise_mouse_y=250;g.mouse_x=25;g.mouse_y=20;df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
   gui.simulateInput(view,step[1]);settle();record_scroll(step[2])
  end
  click(952,730);record_scroll('report-arrow')
 end
 if os.getenv('DF3D_JUSTICE_WIRE_INTELLIGENCE')=='1' then
  local source=debug.getinfo(1,'S').source:sub(2):gsub('justice%-intelligence%-native%.lua$','justice-wire-native.lua')
  assert(loadfile(source))(out,probe,bytes)
 end
end,debug.traceback)
gui.simulateInput(view,'LEAVESCREEN');settle()
while #reports>original do reports:erase(#reports-1)end
for _,r in ipairs(added)do
 while #r.details>0 do local line=r.details[#r.details-1];r.details:erase(#r.details-1);line:delete()end
 r:delete()
end
-- Reopen the native menu to retire pointers to removed synthetic records.
gui.simulateInput(view,'D_JUSTICE');settle();if df.global.game.main_interface.help.open then click(711,430)end;tab('Intelligence')
assert(#probe('justice-intelligence-reports-probe',80)==original,'Reports not restored')
assert(ok,err)
