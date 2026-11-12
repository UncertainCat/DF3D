-- Protected native oracle. Temporary punishment records exist only in the owned
-- paused clone and are removed before exit; no runtime widget access is used.
local out,view,probe,settle,tab,capture,bytes=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local punishments=df.global.plotinfo.punishments
local supplied=probe('justice-convicts-probe');assert(#supplied>0,'Fixture requires convicts')
local id=supplied[1].unit_id;local original_count=#punishments
local added=df.punishment:new();added.criminal=id;added.officer=-1;added.beating=0;added.hammer_strikes=0;added.prison_counter=0
local function click(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=y//12
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1;settle()
end
local samples={}
local function observe(name)
 gui.simulateInput(view,'LEAVESCREEN');settle();gui.simulateInput(view,'D_JUSTICE');settle()
 if df.global.game.main_interface.help.open then click(711,430)end
 tab('Convicts')
 local ids,texts,positions={},{},{}
 local function walk(w)
  if(w.flag.whole&1)==0 then return end
  if df.widget_unit_name:is_instance(w)and w.u then positions[w.u.id]=w.rect.y1-2 end
  if df.widget_unit_list:is_instance(w)then for _,entry in ipairs(w.deferred_units_builds)do
   if entry.anon_2.t==0 and entry.anon_2.u then
    local _,address=df.sizeof(entry.anon_1)
    local ptr=df.reinterpret_cast('uint64_t',address).value
    assert(ptr~=0);local row=df.reinterpret_cast(df.widget_container,ptr)
    positions[entry.anon_2.u.id]=row.rect.y1
   end
  end end
  if df.widget_text:is_instance(w)and w.rect.x1>=65 then texts[#texts+1]={text=dfhack.df2utf(w.str),color=w.fg+(w.bright and 8 or 0)}end
  if df.widget_container:is_instance(w)then for i,c in ipairs(dfhack.gui.getWidgetChildren(w))do
   if not df.widget_tabs:is_instance(w)or i-1==w.cur_idx then walk(c)end
  end end
 end
 walk(df.global.game.main_interface.info.justice)
 for unit_id,y in pairs(positions)do ids[#ids+1]={id=unit_id,y=y}end
 table.sort(ids,function(a,b)return a.y<b.y end)
 for i,row in ipairs(ids)do ids[i]=row.id end
 local result=probe('justice-convicts-probe');local expected_ids={};for _,row in ipairs(result)do expected_ids[#expected_ids+1]=row.unit_id end
 assert(json.encode(ids)==json.encode(expected_ids),'Convict roster/order mismatch: '..json.encode{native=ids,provider=expected_ids,positions=positions})
 local row=result[1];local expected={}
 for _,s in ipairs(row.sentence)do expected[#expected+1]={text=s,color=15}end
 if row.officer then expected[#expected+1]={text=row.officer,color=9}end
 for _,c in ipairs(row.crimes)do
  if #c.caption>0 then expected[#expected+1]={text=c.caption,color=15}end
  if c.injured_party then expected[#expected+1]={text=c.injured_party,color=7}end
 end
 assert(json.encode(texts)==json.encode(expected),'Convict text mismatch '..name..': '..json.encode{native=texts,provider=expected})
 samples[#samples+1]={name=name,provider=result,native_rows=ids,native_text=texts}
end
local ok,err=xpcall(function()
 observe('baseline');capture('justice-convicts-baseline')
 punishments:insert('#',added)
 observe('zero-sentence')
 added.beating=1;added.hammer_strikes=1;added.prison_counter=119
 observe('combined-singular')
 added.hammer_strikes=2;added.prison_counter=120;added.officer=id
 observe('combined-plural-officer');capture('justice-convicts-sentence')
 if os.getenv('DF3D_JUSTICE_CONVICTS_SENTENCE')=='1' then
  assert(os.getenv('DF3D_JUSTICE_WIRE_CONVICTS')=='1','Sentence viewer requires Convicts wire mode')
  local source=debug.getinfo(1,'S').source:sub(2):gsub('justice%-convicts%-native%.lua$','justice-wire-native.lua')
  assert(loadfile(source))(out,probe,bytes)
 end
end,debug.traceback)
if #punishments>original_count then assert(punishments[#punishments-1]==added);punishments:erase(#punishments-1)end
added:delete();assert(#punishments==original_count)
local f=assert(io.open(out..'/justice-convicts.json','w'));f:write(json.encode{samples=samples,restored=true});f:close()
assert(ok,err)
