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
local hunter_snapshot
local function shot(name)
 local file=assert(io.open(out..'/standing-orders-native.json','w'));file:write(json.encode(result));file:close()
 file=assert(io.open(out..'/shot.tmp','w'));file:write(name);file:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local deadline=dfhack.getTickCount()+((os.getenv('DF3D_STANDING_ORDERS_RENDER')=='1' or os.getenv('DF3D_HUNTER_AMMUNITION_RENDER')=='1') and 20000 or 10000)
 local checked=0
 while true do
  if name=='hunter-ammunition-wire' then
   local step_file=io.open(out..'/hunter-wire-step')
   if step_file then
    local step=tonumber(step_file:read('*a'));step_file:close()
    if step and step>checked then
     assert(step==checked+1 and step<=#result.hunter_ammunition.wire_steps,'Unexpected ammunition wire step')
     assert(json.encode(hunter_snapshot())==json.encode(result.hunter_ammunition.wire_steps[step].values),'Ammunition wire effects differ at step '..step)
     checked=step;local ack=assert(io.open(out..'/hunter-wire-ack','w'));ack:write(tostring(step));ack:close()
    end
   end
  end
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
 if name=='hunter-ammunition-wire' then assert(checked==#result.hunter_ammunition.wire_steps,'Ammunition wire steps incomplete');result.hunter_ammunition.wire_checked=checked end
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
 if os.getenv('DF3D_STANDING_ORDERS_EXTENDED_PROVIDER')=='1' then
  result.extended_provider={cycles={}}
  local function provider(category,...)
   local text,code=dfhack.run_command_silent('df3d','standing-category-probe',tostring(category),...)
   assert(code==0,'Extended provider failed: '..text);return json.decode(text)
  end
  for _,cycle in ipairs(result.extended_cycles)do
   local key
   for _,state in ipairs(cycle.states)do for name,value in pairs(state.values)do if value~=cycle.before[name]then assert(not key or key==name);key=name end end end
   local initial=provider(cycle.category)
   assert(#initial.settings==(cycle.category==3 and 10 or cycle.category==4 and 6 or 7),'Extended setting count differs')
   for _,row in ipairs(initial.settings)do assert(row.visible and row.editable,'Extended setting unavailable')end
   local stale=provider(cycle.category,tostring(cycle.index),tostring(cycle.before[key]+10),'0')
   assert(stale.outcome==1 and json.encode(values())==json.encode(cycle.before),'Extended stale write changed settings')
   local invalid=provider(cycle.category,tostring(cycle.index),tostring(cycle.before[key]),'4')
   assert(invalid.outcome==0 and json.encode(values())==json.encode(cycle.before),'Extended invalid value changed settings')
   local steps={}
   for _,expected in ipairs(cycle.states)do
    local reply=provider(cycle.category,tostring(cycle.index),tostring(values()[key]),tostring(expected.values[key]))
    assert(reply.outcome==2 and json.encode(values())==json.encode(expected.values),'Extended provider effects differ')
    steps[#steps+1]=reply
   end
   result.extended_provider.cycles[#result.extended_provider.cycles+1]={category=cycle.category,id=cycle.index,steps=steps}
  end
  assert(json.encode(values())==json.encode(original),'Extended provider did not restore settings')
  result.extended_provider.restored=true
 end
 if os.getenv('DF3D_STANDING_ORDERS_EXTENDED_WIRE')=='1' then
  result.wire_steps={}
  for _,cycle in ipairs(result.extended_cycles)do
   local key
   for _,state in ipairs(cycle.states)do for name,value in pairs(state.values)do if value~=cycle.before[name]then key=name end end end
   local current=cycle.before[key];local maximum=cycle.category==6 and (cycle.index==0 and 3 or 1)or 2
   result.wire_steps[#result.wire_steps+1]={category=cycle.category,id=cycle.index,expected=(current+1)%(maximum+1),value=current,outcome=3,values=original}
   for _,state in ipairs(cycle.states)do
    result.wire_steps[#result.wire_steps+1]={category=cycle.category,id=cycle.index,expected=current,value=state.values[key],outcome=1,values=state.values}
    current=state.values[key]
   end
  end
  if os.getenv('DF3D_STANDING_ORDERS_RENDER')=='1' then
   local applied={};for _,entry in ipairs(result.wire_steps)do if entry.outcome==1 then applied[#applied+1]=entry end end
   result.wire_steps=applied
  end
  shot('standing-orders-wire')
  assert(json.encode(values())==json.encode(original),'Extended wire did not restore settings')
 end
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
if os.getenv('DF3D_HUNTER_AMMUNITION_NATIVE')=='1' then
 local equipment=df.global.plotinfo.equipment
 local function vector(source)local result={};for _,value in ipairs(source)do result[#result+1]=value end;return result end
 local function snapshot()
  local result={update=equipment.update.whole,ammo_items=vector(equipment.ammo_items),ammo_units=vector(equipment.ammo_units),specs={}}
  result.assigned_ammo=vector(equipment.items_assigned[df.item_type.AMMO])
  result.unassigned_ammo=vector(equipment.items_unassigned[df.item_type.AMMO])
  for _,spec in ipairs(equipment.hunter_ammunition)do
   result.specs[#result.specs+1]={item_type=spec.item_type,item_subtype=spec.item_subtype,material_class=spec.material_class,mattype=spec.mattype,matindex=spec.matindex,amount=spec.amount,flags=spec.flags.whole,assigned=vector(spec.assigned)}
  end
  return result
 end
 hunter_snapshot=snapshot
 local owned_candidates
 if os.getenv('DF3D_HUNTER_AMMUNITION_PROVIDER')=='1' then
  local ui=df.global.game.main_interface.squad_equipment
  local function menu_snapshot()
   return {open=ui.open,setting=ui.setting_ammo,target=ui.setting_ammo_squad_id,amount=ui.setting_ammo_amount_str,
    material_class=vector(ui.am_cand_civ_mat),mattype=vector(ui.am_cand_spec_mat),matindex=vector(ui.am_cand_spec_matg),
    item_type=vector(ui.am_cand_type),item_subtype=vector(ui.am_cand_subtype),foreign=vector(ui.am_cand_foreign)}
  end
  local menu_before=json.encode(menu_snapshot());local simulation_before=json.encode(snapshot())
  local text,code=dfhack.run_command_silent('df3d','hunter-ammunition-candidates-probe')
  assert(code==0,'Owned ammunition candidates failed');owned_candidates=json.decode(text)
  assert(menu_before==json.encode(menu_snapshot()),'Owned candidates changed native menu state')
  assert(simulation_before==json.encode(snapshot()),'Owned candidates changed simulation settings')
 end
 local before=snapshot();click(80,12);click(12,37)
 local ui=df.global.game.main_interface.squad_equipment
 assert(ui.open and ui.setting_ammo and ui.setting_ammo_squad_id==-1,'Hunter ammunition did not open')
 result.hunter_ammunition={before=before,opened=snapshot(),rows=rows(),candidates={material_class=vector(ui.am_cand_civ_mat),mattype=vector(ui.am_cand_spec_mat),matindex=vector(ui.am_cand_spec_matg),item_type=vector(ui.am_cand_type),item_subtype=vector(ui.am_cand_subtype),foreign=vector(ui.am_cand_foreign)}}
 if owned_candidates then
  assert(json.encode(owned_candidates)==json.encode(result.hunter_ammunition.candidates),'Owned candidate values/order differ from native')
  result.hunter_ammunition.provider={all_candidates_match=true,menu_unchanged=true,simulation_unchanged=true}
 end
 assert(json.encode(before)==json.encode(snapshot()),'Opening hunter ammunition changed simulation settings')
 shot('hunter-ammunition-root')
 if os.getenv('DF3D_HUNTER_AMMUNITION_HOVER')=='1' then
  local probes={};local main=df.global.game.main_interface
  for _,target in ipairs({{'add',512,250},{'confirm',924,250},{'material',524,298},{'amount',572,298},{'delete',920,298},{'remove',920,334},{'picture',202,334},{'caption',320,334}})do
   local function move()
    df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
    g.precise_mouse_x=target[2];g.precise_mouse_y=target[3];g.mouse_x=target[2]//8;g.mouse_y=(target[3]-4)//12
    gui.simulateInput(view,{});view:render(dfhack.getTickCount())
   end
   local deadline=dfhack.getTickCount()+850
   repeat move();script.sleep(1,'frames')until dfhack.getTickCount()>=deadline
   move();script.sleep(2,'frames')
   local lines={}
   for y=0,19 do
    local chars={};for x=g.dimx-24,g.dimx-1 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<127 and string.char(ch)or' 'end
    lines[#lines+1]=table.concat(chars):gsub('%s+$','')
   end
   probes[#probes+1]={name=target[1],point={target[2],target[3]},instruction=main.current_hover,displayed=main.last_displayed_hover_inst,lines=lines}
   shot('hunter-hover-'..target[1])
  end
  result.hunter_ammunition.hover_reference=probes
  assert(json.encode(before)==json.encode(snapshot()),'Hover changed ammunition settings')
 end
 local function layout_probe(kind)
  if os.getenv('DF3D_HUNTER_AMMUNITION_LAYOUT')~='1' then return end
  result.hunter_ammunition.layout=result.hunter_ammunition.layout or {}
  for _,size in ipairs({'minimum','small','wide','default'})do
   local file=assert(io.open(out..'/owner-input-request.tmp','w'));file:write('name-resize-'..size);file:close();assert(os.rename(out..'/owner-input-request.tmp',out..'/owner-input-request'))
   local deadline=dfhack.getTickCount()+5000
   while true do local ack=io.open(out..'/owner-input-ack');if ack then ack:close();break end;assert(dfhack.getTickCount()<deadline,'Ammunition resize timed out');script.sleep(1,'frames')end
   assert(os.remove(out..'/owner-input-ack'));script.sleep(5,'frames');settle()
   local text={}
   for y=0,g.dimy-1 do
    local chars={};for x=0,g.dimx-1 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
    local line=dfhack.df2utf(table.concat(chars)):gsub('%s+$','');if line:find('%S')then text[#text+1]={y=y,text=line}end
   end
   result.hunter_ammunition.layout[#result.hunter_ammunition.layout+1]={kind=kind,size=size,columns=g.dimx,rows=g.dimy,text=text,first=ui.setting_ammo_scroll_position,choice_first=ui.setting_ammo_scroll_position_am}
   assert(json.encode(before)==json.encode(snapshot()),'Resizing ammunition changed equipment')
   shot('hunter-layout-'..kind..'-'..size)
   if size=='minimum' then
    local scroll={}
    for _,probe in ipairs({{'down',34},{'up',23}})do
     click(102,probe[2]);scroll[#scroll+1]={action=probe[1],first=ui.setting_ammo_scroll_position,choice_first=ui.setting_ammo_scroll_position_am}
     shot('hunter-layout-'..kind..'-minimum-'..probe[1])
    end
    result.hunter_ammunition[kind..'_arrows']=scroll
    local contextual={}
    for _,key in ipairs({'CONTEXT_SCROLL_DOWN','CONTEXT_SCROLL_UP'})do
     g.precise_mouse_x=320;g.precise_mouse_y=334;g.mouse_x=40;g.mouse_y=27
     gui.simulateInput(view,key);settle()
     contextual[#contextual+1]={key=key,first=ui.setting_ammo_scroll_position,choice_first=ui.setting_ammo_scroll_position_am}
     shot('hunter-layout-'..kind..'-'..key)
    end
    result.hunter_ammunition[kind..'_context_scroll']=contextual
   end
  end
 end
 local function picker_hover(kind)
  if os.getenv('DF3D_HUNTER_AMMUNITION_PICKER_HOVER')~='1' then return end
  result.hunter_ammunition.picker_hover=result.hunter_ammunition.picker_hover or {}
  for _,target in ipairs({{'row',320,298},{'second',320,334},{'cancel',924,250}})do
   local deadline=dfhack.getTickCount()+850
   repeat
    df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
    g.precise_mouse_x=target[2];g.precise_mouse_y=target[3];g.mouse_x=target[2]//8;g.mouse_y=(target[3]-4)//12
    gui.simulateInput(view,{});view:render(dfhack.getTickCount());script.sleep(1,'frames')
   until dfhack.getTickCount()>=deadline
   local main=df.global.game.main_interface
   result.hunter_ammunition.picker_hover[#result.hunter_ammunition.picker_hover+1]={kind=kind,target=target[1],instruction=main.current_hover,displayed=main.last_displayed_hover_inst}
   shot('hunter-hover-'..kind..'-'..target[1])
  end
  assert(json.encode(before)==json.encode(snapshot()),'Picker hover changed equipment')
 end
 layout_probe('main')
 click(64,20)
 assert(ui.setting_ammo_new_type,'Add ammunition did not open type choices')
 result.hunter_ammunition.add_picker={rows=rows(),values=snapshot()}
 assert(json.encode(before)==json.encode(snapshot()),'Opening ammunition choices changed simulation settings')
 shot('hunter-ammunition-add-picker')
 picker_hover('types')
 layout_probe('types')
 if os.getenv('DF3D_HUNTER_AMMUNITION_LAYOUT')=='1' then
  local scroll={}
  for _,key in ipairs({'STANDARDSCROLL_DOWN','STANDARDSCROLL_UP','STANDARDSCROLL_PAGEDOWN','STANDARDSCROLL_PAGEUP'})do
   gui.simulateInput(view,key);settle();scroll[#scroll+1]={key=key,first=ui.setting_ammo_scroll_position_am}
  end
  result.hunter_ammunition.layout_scroll=scroll
  shot('hunter-layout-types-scroll')
 end
 gui.simulateInput(view,'LEAVESCREEN');settle()
 result.hunter_ammunition.cancelled_picker={open=ui.open,setting_ammo=ui.setting_ammo,values=snapshot()}
 assert(json.encode(before)==json.encode(snapshot()),'Cancelling ammunition choices changed simulation settings')
 shot('hunter-ammunition-cancelled-picker')
 click(65,24)
 assert(ui.setting_ammo_mat,'Material button did not open choices')
 result.hunter_ammunition.material_picker={rows=rows(),values=snapshot(),selected=ui.setting_ammo_mat_sea_index}
 shot('hunter-ammunition-material-picker')
 picker_hover('materials')
 click(35,30)
 result.hunter_ammunition.material_selected={rows=rows(),values=snapshot(),selecting=ui.setting_ammo_mat}
 shot('hunter-ammunition-material-selected')
 local spec=equipment.hunter_ammunition[0]
 spec.material_class=before.specs[1].material_class;spec.mattype=before.specs[1].mattype;spec.matindex=before.specs[1].matindex
 equipment.update.whole=before.update
 assert(json.encode(before)==json.encode(snapshot()),'Material edit affected fields beyond material/update')
 click(71,24)
 assert(ui.setting_ammo_entering_amount,'Amount button did not open entry')
 result.hunter_ammunition.amount_entry={rows=rows(),text=ui.setting_ammo_amount_str,values=snapshot()}
 shot('hunter-ammunition-amount-entry')
 for _,byte in ipairs({49,50,53})do gui.simulateInput(view,('STRING_A%03d'):format(byte))end
 settle()
 result.hunter_ammunition.amount_draft={text=ui.setting_ammo_amount_str,values=snapshot()}
 gui.simulateInput(view,'SELECT');settle()
 result.hunter_ammunition.amount_confirmed={text=ui.setting_ammo_amount_str,entering=ui.setting_ammo_entering_amount,values=snapshot(),rows=rows()}
 shot('hunter-ammunition-amount-confirmed')
 equipment.hunter_ammunition[0].amount=before.specs[1].amount
 equipment.update.whole=before.update
 assert(json.encode(before)==json.encode(snapshot()),'Amount edit affected fields beyond amount/update')
 if os.getenv('DF3D_HUNTER_AMMUNITION_INPUT')=='1' then
  local probes={}
  local function observe()
   return {open=ui.open,entering=ui.setting_ammo_entering_amount,types=ui.setting_ammo_new_type,materials=ui.setting_ammo_mat,text=ui.setting_ammo_amount_str,values=snapshot()}
  end
  local function reopen()
   while ui.open do gui.simulateInput(view,'LEAVESCREEN');settle()end
   gui.simulateInput(view,'D_LABOR');settle();click(30,10);click(80,12);click(12,37)
   assert(ui.open and ui.setting_ammo,'Ammunition reentry failed')
  end
  for _,case in ipairs({{name='mixed',text='a-12.3x',enter=true},{name='long',text='12345678901234567890',enter=true},{name='blank',text='',enter=true},{name='upper',text='5001',enter=true},{name='same-amount',text='125',x=71,y=24},{name='material',text='125',x=65,y=24},{name='add',text='125',x=64,y=20},{name='blank-click',text='125',x=40,y=55},{name='confirm',text='125',x=115,y=20}})do
   click(71,24)
   for i=1,#case.text do gui.simulateInput(view,('STRING_A%03d'):format(case.text:byte(i)))end
   settle();local draft=observe()
   if case.enter then gui.simulateInput(view,'SELECT');settle()else click(case.x,case.y)end
   probes[#probes+1]={name=case.name,draft=draft,after=observe()}
   shot('hunter-input-'..case.name)
   if case.name=='add' or case.name=='material' then
    gui.simulateInput(view,'LEAVESCREEN');settle();probes[#probes].cancelled=observe()
    shot('hunter-input-'..case.name..'-cancelled')
   end
   equipment.hunter_ammunition[0].amount=before.specs[1].amount;equipment.update.whole=before.update
   assert(json.encode(before)==json.encode(snapshot()),'Quantity probe changed unrelated equipment')
   reopen()
  end
  result.hunter_ammunition.input_reference=probes
 end
 click(64,20);click(35,24)
 result.hunter_ammunition.added={rows=rows(),values=snapshot()}
 assert(#equipment.hunter_ammunition==#before.specs+1,'Adding ammunition did not append a spec')
 shot('hunter-ammunition-added')
 click(114,42)
 result.hunter_ammunition.deleted_empty={rows=rows(),values=snapshot()}
 equipment.update.whole=before.update
 assert(json.encode(before)==json.encode(snapshot()),'Deleting added ammunition did not restore specs')
 shot('hunter-ammunition-deleted-empty')
 click(114,27)
 result.hunter_ammunition.removed_stack={rows=rows(),values=snapshot()}
 shot('hunter-ammunition-removed-stack')
 local function restore_vector(target,source)
  target:resize(0);for _,value in ipairs(source)do target:insert('#',value)end
 end
 restore_vector(equipment.hunter_ammunition[0].assigned,before.specs[1].assigned)
 restore_vector(equipment.items_assigned[df.item_type.AMMO],before.assigned_ammo)
 restore_vector(equipment.items_unassigned[df.item_type.AMMO],before.unassigned_ammo)
 equipment.update.whole=before.update
 assert(json.encode(before)==json.encode(snapshot()),'Stack removal changed unexpected ammunition fields')
 click(114,24)
 result.hunter_ammunition.deleted_populated={rows=rows(),values=snapshot()}
 assert(#equipment.hunter_ammunition==0,'Populated ammunition spec was not deleted')
 shot('hunter-ammunition-deleted-populated')
 local restored=df.squad_ammo_spec:new()
 for _,key in ipairs({'item_type','item_subtype','material_class','mattype','matindex','amount'})do restored[key]=before.specs[1][key]end
 restored.flags.whole=before.specs[1].flags
 restore_vector(restored.assigned,before.specs[1].assigned)
 equipment.hunter_ammunition:insert('#',restored)
 restore_vector(equipment.items_assigned[df.item_type.AMMO],before.assigned_ammo)
 restore_vector(equipment.items_unassigned[df.item_type.AMMO],before.unassigned_ammo)
 equipment.update.whole=before.update
 assert(json.encode(before)==json.encode(snapshot()),'Populated deletion changed unexpected ammunition fields')
 if os.getenv('DF3D_HUNTER_AMMUNITION_EDITS')=='1' then
  local function edit(kind,value,expected,index)
   local text,code=dfhack.run_command_silent('df3d','hunter-ammunition-edit-probe',kind,tostring(index or 0),tostring(value),json.encode(expected or before.specs))
   assert(code==0,'Semantic ammunition edit diagnostic failed');return json.decode(text)
  end
  local checks={}
  checks.noop=edit('amount',before.specs[1].amount)
  assert(checks.noop.outcome==2 and json.encode(before)==json.encode(snapshot()),'No-op amount changed equipment')
  checks.invalid=edit('amount',5001)
  assert(checks.invalid.outcome==0 and json.encode(before)==json.encode(snapshot()),'Invalid amount changed equipment')
  local stale=json.decode(json.encode(before.specs));table.remove(stale[1].assigned,1)
  checks.assignment_stale=edit('amount',125,stale)
  assert(checks.assignment_stale.outcome==1 and json.encode(before)==json.encode(snapshot()),'Stale assignment receipt was accepted')
  checks.amount=edit('amount',125)
  assert(checks.amount.outcome==2 and json.encode(snapshot())==json.encode(result.hunter_ammunition.amount_confirmed.values),'Semantic quantity differs from native')
  checks.stale=edit('amount',100)
  assert(checks.stale.outcome==1 and json.encode(snapshot())==json.encode(result.hunter_ammunition.amount_confirmed.values),'Stale amount receipt changed state')
  equipment.hunter_ammunition[0].amount=before.specs[1].amount;equipment.update.whole=before.update
  checks.material=edit('material',2)
  assert(checks.material.outcome==2 and json.encode(snapshot())==json.encode(result.hunter_ammunition.material_selected.values),'Semantic material differs from native')
  local spec=equipment.hunter_ammunition[0]
  spec.material_class=before.specs[1].material_class;spec.mattype=before.specs[1].mattype;spec.matindex=before.specs[1].matindex
  equipment.update.whole=before.update
  assert(json.encode(before)==json.encode(snapshot()),'Semantic ammunition checks did not restore state')
  checks.add=edit('add',0)
  assert(checks.add.outcome==2 and json.encode(snapshot())==json.encode(result.hunter_ammunition.added.values),'Semantic Add differs from native')
  checks.structural_stale=edit('delete',0)
  assert(checks.structural_stale.outcome==1 and json.encode(snapshot())==json.encode(result.hunter_ammunition.added.values),'Stale structural receipt changed state')
  checks.delete_empty=edit('delete',0,snapshot().specs,1)
  assert(checks.delete_empty.outcome==2 and json.encode(snapshot())==json.encode(result.hunter_ammunition.deleted_empty.values),'Semantic empty Delete differs from native')
  equipment.update.whole=before.update
  checks.remove=edit('remove',before.specs[1].assigned[1])
  assert(checks.remove.outcome==2 and json.encode(snapshot())==json.encode(result.hunter_ammunition.removed_stack.values),'Semantic Remove differs from native')
  restore_vector(equipment.hunter_ammunition[0].assigned,before.specs[1].assigned)
  restore_vector(equipment.items_assigned[df.item_type.AMMO],before.assigned_ammo)
  restore_vector(equipment.items_unassigned[df.item_type.AMMO],before.unassigned_ammo)
  equipment.update.whole=before.update
  checks.delete_populated=edit('delete',0)
  assert(checks.delete_populated.outcome==2 and json.encode(snapshot())==json.encode(result.hunter_ammunition.deleted_populated.values),'Semantic populated Delete differs from native')
  local restored=df.squad_ammo_spec:new()
  for _,key in ipairs({'item_type','item_subtype','material_class','mattype','matindex','amount'})do restored[key]=before.specs[1][key]end
  restored.flags.whole=before.specs[1].flags;restore_vector(restored.assigned,before.specs[1].assigned)
  equipment.hunter_ammunition:insert('#',restored)
  restore_vector(equipment.items_assigned[df.item_type.AMMO],before.assigned_ammo)
  restore_vector(equipment.items_unassigned[df.item_type.AMMO],before.unassigned_ammo)
  equipment.update.whole=before.update
  assert(json.encode(before)==json.encode(snapshot()),'Semantic structural checks did not restore state')
  result.hunter_ammunition.edit_provider=checks
 end
 if os.getenv('DF3D_HUNTER_AMMUNITION_CAPTIONS')=='1' then
  local text,code=dfhack.run_command_silent('df3d','hunter-ammunition-captions-probe')
  assert(code==0,'Ammunition captions provider failed');local captions=json.decode(text)
  for i=1,10 do
   assert(result.hunter_ammunition.add_picker.rows[i+1].text:match('^%s*(.-)%s*$')==captions.types[i],'Type caption differs from native')
   assert(result.hunter_ammunition.material_picker.rows[i+1].text:match('^%s*(.-)%s*$')==captions.materials[i],'Material caption differs from native')
  end
  assert(captions.specs[1].assigned_quantity==119,'Assigned quantity differs from native')
  assert(result.hunter_ammunition.rows[2].text:find(captions.specs[1].caption,1,true),'Rule caption differs from native')
  for i,item in ipairs(captions.specs[1].items)do
   assert(result.hunter_ammunition.rows[i+2].text:find(item.caption,1,true),'Assigned stack caption differs from native')
  end
  assert(json.encode(before)==json.encode(snapshot()),'Caption formatting changed equipment')
  result.hunter_ammunition.caption_provider=captions
 end
 if os.getenv('DF3D_HUNTER_AMMUNITION_WIRE')=='1' then
  local h=result.hunter_ammunition;local function clone(v)return json.decode(json.encode(v))end
  local reset=clone(before);reset.update=before.update|64
  h.wire_steps={
   {operation=1,index=0,amount=125,expected=before.specs,values=h.amount_confirmed.values,outcome=1},
   {operation=1,index=0,amount=100,expected=before.specs,values=h.amount_confirmed.values,outcome=3},
   {operation=1,index=0,amount=100,expected=h.amount_confirmed.values.specs,values=reset,outcome=1},
   {operation=2,index=0,material_class=3,expected=before.specs,values=h.material_selected.values,outcome=1},
   {operation=2,index=0,expected=h.material_selected.values.specs,values=reset,outcome=1},
   {operation=3,item_type=39,item_subtype=0,expected=before.specs,values=h.added.values,outcome=1},
   {operation=4,index=1,expected=h.added.values.specs,values=h.deleted_empty.values,outcome=1},
   {operation=5,index=0,item_id=before.specs[1].assigned[1],expected=before.specs,values=h.removed_stack.values,outcome=1},
   {operation=4,index=0,expected=h.removed_stack.values.specs,values=h.deleted_populated.values,outcome=1}}
  shot('hunter-ammunition-wire')
  assert(#equipment.hunter_ammunition==0,'Wire deletion did not finish')
  local restored=df.squad_ammo_spec:new()
  for _,key in ipairs({'item_type','item_subtype','material_class','mattype','matindex','amount'})do restored[key]=before.specs[1][key]end
  restored.flags.whole=before.specs[1].flags;restore_vector(restored.assigned,before.specs[1].assigned)
  equipment.hunter_ammunition:insert('#',restored)
  restore_vector(equipment.items_assigned[df.item_type.AMMO],before.assigned_ammo)
  restore_vector(equipment.items_unassigned[df.item_type.AMMO],before.unassigned_ammo)
  equipment.update.whole=before.update
  assert(json.encode(before)==json.encode(snapshot()),'Ammunition wire state did not restore')
 end
 gui.simulateInput(view,'LEAVESCREEN');settle()
 result.hunter_ammunition.cancelled_amount={open=ui.open,setting_ammo=ui.setting_ammo,entering=ui.setting_ammo_entering_amount,values=snapshot()}
 assert(json.encode(before)==json.encode(snapshot()),'Cancelling amount changed ammunition')
 shot('hunter-ammunition-amount-cancelled')
end
shot('standing-orders-restored');records[#records+1]={name='standing-orders',categories=#result.pages,cycles=#result.workshop_cycles}
