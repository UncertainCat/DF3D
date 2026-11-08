-- Protected discovery only. Widgets/camera are not runtime semantic inputs.
local out,view,records=...
local gui=require('gui');local script=require('gui.script');local json=require('json')
local g=df.global.gps
local function settle()
 for _=1,3 do script.sleep(1,'frames')end
 view:render(dfhack.getTickCount())
end
local function click(x,y)
 g.precise_mouse_x=x*8+4;g.precise_mouse_y=y*12+6;g.mouse_x=x;g.mouse_y=y
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L')
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
 settle()
end
gui.simulateInput(view,'D_LABOR');settle()
-- Default1200x800 Labor tab geometry, independently captured with Work Details.
click(30,10)
local info=df.global.game.main_interface.info
local panel
local function find(widget)
 if df.labor_standing_orders_interfacest:is_instance(widget) then panel=widget;return end
 if df.widget_container:is_instance(widget) then for _,child in ipairs(dfhack.gui.getWidgetChildren(widget))do find(child)end end
end
find(info.labor)
assert(info.open and panel and (panel.flag.whole&3)==3,'Standing orders tab did not open')
local result={pages={},workshop_cycles={},vtable={},unavailable_globals={}}
local _,address=df.sizeof(panel);local vt=df.reinterpret_cast('uint64_t',address).value
local base=dfhack.internal.getImageBase()
for slot=0,7 do result.vtable[#result.vtable+1]=df.reinterpret_cast('uint64_t',vt+slot*8).value-base end
local globals={'standing_orders_gather_minerals','standing_orders_gather_wood','standing_orders_gather_food','standing_orders_gather_bodies','standing_orders_gather_refuse','standing_orders_gather_animals','standing_orders_gather_furniture','standing_orders_farmer_harvest','standing_orders_ignore_damp_stone','standing_orders_ignore_warm_stone','standing_orders_auto_loom','standing_orders_auto_collect_webs','standing_orders_zoneonly_drink','standing_orders_zoneonly_fish','standing_orders_auto_slaughter','standing_orders_auto_butcher','standing_orders_auto_tan','standing_orders_auto_fishery','standing_orders_auto_kitchen','standing_orders_auto_kiln','standing_orders_auto_smelter','standing_orders_auto_other','standing_orders_use_dyed_cloth','standing_orders_gather_refuse_outside','standing_orders_gather_vermin_remains','standing_orders_dump_corpses','standing_orders_dump_skulls','standing_orders_dump_skins','standing_orders_dump_bones','standing_orders_dump_hair','standing_orders_dump_shells','standing_orders_dump_other','standing_orders_forbid_used_ammo','standing_orders_forbid_own_dead','standing_orders_forbid_other_nohunt','standing_orders_forbid_own_dead_items','standing_orders_forbid_other_dead_items','standing_orders_forbid_floor_and_wall_cleaning','standing_orders_forbid_trap_cleaning','standing_orders_forbid_rearming_traps','standing_orders_forbid_cages_from_sprung_traps','standing_orders_forbid_toppled_building_items','standing_orders_petition_resident_monster_hunter','standing_orders_petition_resident_performer','standing_orders_petition_resident_mercenary','standing_orders_petition_resident_scholar','standing_orders_petition_resident_sanctuary','standing_orders_petition_citizenship','standing_orders_job_cancel_announce','standing_orders_mix_food'}
local function values()
 local state={}
 for _,name in ipairs(globals)do
  local ok,value=pcall(function()return df.global[name]end)
  if ok then state[name]=value else result.unavailable_globals[name]=tostring(value)end
 end
 return state
end
local function rows()
 local result={}
 for y=14,g.dimy-4 do
  local chars={};for x=6,117 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
  local text=dfhack.df2utf(table.concat(chars)):gsub('%s+$','')
  if text:find('%S')then result[#result+1]={y=y,text=text}end
 end
 return result
end
local function shot(name)
 local file=assert(io.open(out..'/standing-orders-native.json','w'));file:write(json.encode(result));file:close()
 file=assert(io.open(out..'/shot.tmp','w'));file:write(name);file:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local deadline=dfhack.getTickCount()+10000
 while true do local ack=io.open(out..'/ack-'..name);if ack then ack:close();break end;assert(dfhack.getTickCount()<deadline,'Standing orders capture timeout');script.sleep(1,'frames')end
end
local original=values()
for category,x in ipairs{10,23,34,46,60,71,80}do
 click(x,12);assert(panel.current_category==category-1,'Standing orders category click failed')
 result.pages[#result.pages+1]={category=panel.current_category,rows=rows(),values=values()}
 shot('standing-orders-category-'..(category-1))
end
click(10,12)
for index=0,7 do
 local before=values();local cycle={index=index,before=before,states={}}
 for attempt=1,5 do
  click(12,15+3*index)
  local after=values();cycle.states[#cycle.states+1]={values=after,rows=rows()}
  if json.encode(after)==json.encode(before)then break end
 end
 assert(json.encode(values())==json.encode(before),'Workshop control did not return to original value')
 assert(#cycle.states>1,'Workshop click did not change a standing order')
 result.workshop_cycles[#result.workshop_cycles+1]=cycle
end
assert(json.encode(values())==json.encode(original),'Standing orders were not restored')
if os.getenv('DF3D_STANDING_ORDERS_PROVIDER')=='1' then
 local function provider(...)
  local text,code=dfhack.run_command_silent('df3d','standing-workshops-probe',...)
  assert(code==0,'Standing workshop provider failed: '..text);return json.decode(text)
 end
 result.provider={initial=provider(),cycles={}}
 for _,row in ipairs(result.provider.initial.settings)do
  assert(row.available==(row.id<8),'Workshop availability differs from captured native controls')
 end
 local invalid=provider('11','0','1');assert(invalid.outcome==0,'Invalid control was accepted')
 assert(json.encode(values())==json.encode(original),'Invalid request changed state')
 for _,cycle in ipairs(result.workshop_cycles)do
  local key
  for _,state in ipairs(cycle.states)do
   for name,value in pairs(state.values)do if value~=cycle.before[name] then assert(not key or key==name);key=name end end
  end
  assert(key,'Native cycle has no changed setting')
  local stale=provider(tostring(cycle.index),tostring(original[key]+1),tostring(original[key]))
  assert(stale.outcome==1,'Stale request was not refused')
  assert(json.encode(values())==json.encode(original),'Stale request changed state')
  local steps={}
  for _,expected in ipairs(cycle.states)do
   local reply=provider(tostring(cycle.index),tostring(df.global[key]),tostring(expected.values[key]))
   assert(reply.outcome==2,'Semantic workshop edit failed')
   assert(json.encode(values())==json.encode(expected.values),'Semantic workshop effects differ from native')
   steps[#steps+1]=reply
  end
  result.provider.cycles[#result.provider.cycles+1]={id=cycle.index,steps=steps}
 end
 assert(json.encode(values())==json.encode(original),'Semantic workshop edits did not restore state')
 result.provider.restored=true
end
shot('standing-orders-restored');records[#records+1]={name='standing-orders',categories=#result.pages,cycles=#result.workshop_cycles}
