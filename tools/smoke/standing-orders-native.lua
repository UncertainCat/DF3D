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
-- Discovery-only reads: symbols.xml standingorder aliases, confirmed by input RIP targets.
local aliases={standing_orders_ignore_damp_stone=0x18d6f67,standing_orders_ignore_warm_stone=0x18d6f0f,standing_orders_petition_citizenship=0x189c29d,standing_orders_petition_resident_performer=0x189c295,standing_orders_petition_resident_monster_hunter=0x189c29c,standing_orders_petition_resident_mercenary=0x189c29e,standing_orders_petition_resident_scholar=0x189c297,standing_orders_petition_resident_sanctuary=0x189c296,standing_orders_forbid_floor_and_wall_cleaning=0x189c1ed,standing_orders_forbid_trap_cleaning=0x189c1eb,standing_orders_forbid_rearming_traps=0x189c1f7,standing_orders_forbid_cages_from_sprung_traps=0x189c1f2,standing_orders_forbid_toppled_building_items=0x189c1ea}
local function values()
 local state={}
 for _,name in ipairs(globals)do
  local ok,value=pcall(function()return df.global[name]end)
  if ok then state[name]=value else
   result.unavailable_globals[name]=tostring(value)
   if os.getenv('DF3D_STANDING_ORDERS_EXTENDED')=='1' and aliases[name] then
    state[name]=df.reinterpret_cast('uint8_t',base+aliases[name]).value
    result.alias_addresses=result.alias_addresses or {};result.alias_addresses[name]=aliases[name]
   end
  end
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
 local checked=0
 while true do
  if name=='standing-orders-wire' then
   local step_file=io.open(out..'/standing-wire-step')
   if step_file then
    local step=tonumber(step_file:read('*a'));step_file:close()
    if step and step>checked then
     assert(step==checked+1 and step<=#result.wire_steps,'Unexpected wire step')
     assert(json.encode(values())==json.encode(result.wire_steps[step].values),'Standing orders wire effects differ at step '..step)
     checked=step
     local ack=assert(io.open(out..'/standing-wire-ack','w'));ack:write(tostring(step));ack:close()
    end
   end
  end
  local ack=io.open(out..'/ack-'..name);if ack then ack:close();break end
  assert(dfhack.getTickCount()<deadline,'Standing orders capture timeout');script.sleep(1,'frames')
 end
 if name=='standing-orders-wire' then assert(checked==#result.wire_steps,'Wire steps incomplete');result.wire_checked=checked end
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
if os.getenv('DF3D_STANDING_ORDERS_EXTENDED')=='1' then
 result.extended_cycles={}
 for _,category in ipairs{{id=3,x=46,count=10},{id=4,x=60,count=6},{id=6,x=80,count=7}}do
  click(category.x,12);assert(panel.current_category==category.id,'Extended category click failed')
  for index=0,category.count-1 do
   local before=values();local cycle={category=category.id,index=index,before=before,states={}}
   for attempt=1,5 do
    click(12,15+3*index);cycle.states[#cycle.states+1]={values=values(),rows=rows()}
    if json.encode(values())==json.encode(before)then break end
   end
   assert(#cycle.states>1,'Extended control did not change '..category.id..':'..index)
   assert(json.encode(values())==json.encode(before),'Extended control did not restore')
   result.extended_cycles[#result.extended_cycles+1]=cycle
  end
 end
 assert(json.encode(values())==json.encode(original),'Extended settings did not restore')
 result.extended_restored=true
 click(10,12)
end
if os.getenv('DF3D_STANDING_ORDERS_CATEGORIES')=='1' then
 result.category_cycles={};result.refuse_gates={}
 local function cycle(category,index)
  local before=values();local entry={category=category,index=index,before=before,states={}}
  for attempt=1,4 do
   click(12,15+3*index);entry.states[#entry.states+1]={values=values(),rows=rows()}
   if json.encode(values())==json.encode(before)then break end
  end
  assert(#entry.states>1,'Category setting did not change '..category..':'..index)
  assert(json.encode(values())==json.encode(before),'Category setting did not restore')
  result.category_cycles[#result.category_cycles+1]=entry
 end
 click(23,12)
 for index=0,5 do cycle(1,index)end
 click(34,12)
 -- Native Refuse gates later controls on gather_refuse and vermin on outdoor.
 local gather=df.global.standing_orders_gather_refuse
 local outdoor=df.global.standing_orders_gather_refuse_outside
 if gather~=0 then click(12,15)end
 local before=values()
 for index=1,9 do click(12,15+3*index);assert(json.encode(values())==json.encode(before),'Disabled refuse control changed state')end
 result.refuse_gates.gather_off={values=values(),rows=rows()};shot('standing-orders-refuse-disabled')
 click(12,15)
 if df.global.standing_orders_gather_refuse_outside~=0 then click(12,18)end
 before=values();click(12,21)
 assert(json.encode(values())==json.encode(before),'Disabled vermin control changed state')
 result.refuse_gates.outdoor_off={values=values(),rows=rows()}
 click(12,18)
 for index=0,9 do cycle(2,index)end
 if df.global.standing_orders_gather_refuse_outside~=outdoor then click(12,18)end
 if df.global.standing_orders_gather_refuse~=gather then click(12,15)end
 assert(json.encode(values())==json.encode(original),'Category discovery did not restore settings')
 if os.getenv('DF3D_STANDING_ORDERS_CATEGORY_PROVIDER')=='1' then
  local function provider(category,...)
   local text,code=dfhack.run_command_silent('df3d','standing-category-probe',tostring(category),...)
   assert(code==0,'Category provider failed: '..text);return json.decode(text)
  end
  result.category_provider={cycles={}}
  for _,cycle in ipairs(result.category_cycles)do
   if cycle.category==2 then
    provider(2,'0',tostring(df.global.standing_orders_gather_refuse),'1')
    provider(2,'1',tostring(df.global.standing_orders_gather_refuse_outside),'1')
   end
   local key
   for _,state in ipairs(cycle.states)do for name,value in pairs(state.values)do if value~=cycle.before[name]then assert(not key or key==name);key=name end end end
   assert(json.encode(values())==json.encode(cycle.before),'Provider cycle precondition differs')
   local stale=provider(cycle.category,tostring(cycle.index),tostring(1-df.global[key]),tostring(df.global[key]))
   assert(stale.outcome==1 and json.encode(values())==json.encode(cycle.before),'Stale category edit changed state')
   local steps={}
   for _,expected in ipairs(cycle.states)do
    local reply=provider(cycle.category,tostring(cycle.index),tostring(df.global[key]),tostring(expected.values[key]))
    assert(reply.outcome==2 and json.encode(values())==json.encode(expected.values),'Category provider differs from native')
    steps[#steps+1]=reply
   end
   result.category_provider.cycles[#result.category_provider.cycles+1]={category=cycle.category,id=cycle.index,steps=steps}
  end
  provider(2,'1',tostring(df.global.standing_orders_gather_refuse_outside),'0')
  local before=values();local reply=provider(2,'2',tostring(df.global.standing_orders_gather_vermin_remains),tostring(1-df.global.standing_orders_gather_vermin_remains))
  assert(reply.outcome==0 and reply.settings[3].visible and not reply.settings[3].editable and json.encode(values())==json.encode(before),'Visible disabled vermin gate differs')
  provider(2,'0',tostring(df.global.standing_orders_gather_refuse),'0');before=values()
  for id=1,9 do
   reply=provider(2,tostring(id),'0','1')
   assert(reply.outcome==0 and not reply.settings[id+1].visible and not reply.settings[id+1].editable and json.encode(values())==json.encode(before),'Hidden refuse gate differs')
  end
  provider(2,'0','0','1');provider(2,'1','0',tostring(outdoor));provider(2,'0','1',tostring(gather))
  assert(json.encode(values())==json.encode(original),'Category provider did not restore settings')
  result.category_provider.restored=true
 end
 if os.getenv('DF3D_STANDING_ORDERS_CATEGORY_WIRE')=='1' then
  result.wire_steps={}
  local current=json.decode(json.encode(original))
  local function step(category,id,key,desired,outcome,expected)
   expected=expected or current[key];outcome=outcome or 1
   if outcome==1 then current[key]=desired end
   result.wire_steps[#result.wire_steps+1]={category=category,id=id,expected=expected,value=desired,outcome=outcome,values=json.decode(json.encode(current))}
  end
  for _,cycle in ipairs(result.category_cycles)do
   if cycle.category==2 then
    if current.standing_orders_gather_refuse~=1 then step(2,0,'standing_orders_gather_refuse',1)end
    if current.standing_orders_gather_refuse_outside~=1 then step(2,1,'standing_orders_gather_refuse_outside',1)end
   end
   assert(json.encode(current)==json.encode(cycle.before),'Wire cycle setup differs')
   local key
   for _,state in ipairs(cycle.states)do for name,value in pairs(state.values)do if value~=cycle.before[name]then key=name end end end
   step(cycle.category,cycle.index,key,current[key],3,1-current[key])
   for _,state in ipairs(cycle.states)do step(cycle.category,cycle.index,key,state.values[key])end
  end
  step(2,1,'standing_orders_gather_refuse_outside',0)
  step(2,2,'standing_orders_gather_vermin_remains',1-current.standing_orders_gather_vermin_remains,2)
  step(2,0,'standing_orders_gather_refuse',0)
  for _,cycle in ipairs(result.category_cycles)do if cycle.category==2 and cycle.index>0 then
   local key
   for _,state in ipairs(cycle.states)do for name,value in pairs(state.values)do if value~=cycle.before[name]then key=name end end end
   step(2,cycle.index,key,1-current[key],2)
  end end
  step(2,0,'standing_orders_gather_refuse',1)
  step(2,1,'standing_orders_gather_refuse_outside',outdoor)
  step(2,0,'standing_orders_gather_refuse',gather)
  assert(json.encode(current)==json.encode(original),'Wire plan did not restore')
  if os.getenv('DF3D_STANDING_ORDERS_RENDER')=='1' then
   local applied={};for _,entry in ipairs(result.wire_steps)do if entry.outcome==1 and entry.expected~=entry.value then applied[#applied+1]=entry end end
   result.wire_steps=applied
  end
  shot('standing-orders-wire')
  assert(json.encode(values())==json.encode(original),'Category wire edits did not restore settings')
 end
 result.categories_restored=true
 click(10,12)
end
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
if os.getenv('DF3D_STANDING_ORDERS_WIRE')=='1' then
 result.wire_steps={}
 for _,cycle in ipairs(result.workshop_cycles)do
  local key
  for _,state in ipairs(cycle.states)do for name,value in pairs(state.values)do if value~=cycle.before[name] then key=name end end end
  local current=original[key]
  result.wire_steps[#result.wire_steps+1]={id=cycle.index,expected=(current+1)%(cycle.index==0 and 3 or 2),value=current,outcome=3,values=original}
  for _,state in ipairs(cycle.states)do
   result.wire_steps[#result.wire_steps+1]={id=cycle.index,expected=current,value=state.values[key],outcome=1,values=state.values}
   current=state.values[key]
  end
 end
 for id=8,10 do result.wire_steps[#result.wire_steps+1]={id=id,expected=0,value=1,outcome=2,values=original}end
 if os.getenv('DF3D_STANDING_ORDERS_RENDER')=='1' then
  local applied={};for _,step in ipairs(result.wire_steps)do if step.outcome==1 then applied[#applied+1]=step end end
  result.wire_steps=applied
 end
 shot('standing-orders-wire')
 assert(json.encode(values())==json.encode(original),'Wire settings were not restored')
end
shot('standing-orders-restored');records[#records+1]={name='standing-orders',categories=#result.pages,cycles=#result.workshop_cycles}
