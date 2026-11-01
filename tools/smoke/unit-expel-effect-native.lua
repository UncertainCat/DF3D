-- Final native effect on an owned unsaved clone. Effects are discarded on exit,
-- not rolled back by copying stale unit structures over native allocations.
local unit,view,pointer,capture,out,mode=...
local gui=require('gui')
local json=require('json')
local world=df.global.world
local sheet=df.global.game.main_interface.view_sheets
local frame=world.frame_counter
local fixture
local family
local legacy_saved
local function click(x,y)
 pointer(x,y);df.global.enabler.mouse_lbut_lift=0
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
end
local function snapshot(target)
 local unit=target or unit
 local r={flags1=unit.flags1.whole,flags2=unit.flags2.whole,civ_id=unit.civ_id,
  army_id=unit.enemy.army_controller_id,job_id=unit.job.current_job and unit.job.current_job.id or -1,
  controllers=#world.army_controllers.all,history_count=#world.history.events,offices={},emotions={}}
 for _,office in ipairs(dfhack.units.getNoblePositions(unit) or {})do
  r.offices[#r.offices+1]={entity=office.entity.id,assignment=office.assignment.id,histfig=office.assignment.histfig}
 end
 if unit.status.current_soul then
  for _,emotion in ipairs(unit.status.current_soul.personality.emotions)do
   r.emotions[#r.emotions+1]={type=emotion.type,thought=emotion.thought,subthought=emotion.subthought}
  end
 end
 local controller=unit.enemy.army_controller
 if controller then
  r.controller={id=controller.id,entity_id=controller.entity_id,site_id=controller.site_id,
   goal=controller.goal,year=controller.year,year_tick=controller.year_tick,master_id=controller.master_id}
 end
 local travel=unit.enemy.travel_log
 if travel then r.travel={flags=travel.flags.whole,year=travel.year,year_tick=travel.year_tick,rumour_type=travel.rumour_type,rumour_location_id=travel.rumour_location_id}end
 return r
end
local result={mode=mode,unit_id=unit.id,histfig_id=unit.hist_figure_id}
local ok,err=xpcall(function()
 assert(mode=='expel' or mode=='send','Unknown effect mode')
 assert(sheet.open and sheet.active_id==unit.id and not sheet.unit_overview_expelling)
 if os.getenv('DF3D_UNIT_EXPEL_EFFECT_FAMILY')=='1' then
  local relative
  for _,candidate in ipairs(world.units.active)do
   if candidate.id~=unit.id and dfhack.units.isCitizen(candidate) and dfhack.units.getAge(candidate)>18 and not candidate.flags1.inactive and #(dfhack.units.getNoblePositions(candidate) or {})==0 then relative=candidate;break end
  end
  assert(relative,'Expected adult citizen relative')
  family={entries={},relative=relative}
  for _,pair in ipairs{{unit,relative},{relative,unit}}do
   local hf=assert(df.historical_figure.find(pair[1].hist_figure_id))
   local entry={hf=hf,links={},created=df.histfig_hf_link_spousest:new()}
   family.entries[#family.entries+1]=entry
   for _,link in ipairs(hf.histfig_links)do entry.links[#entry.links+1]=link end
   entry.created.target_hf=pair[2].hist_figure_id;entry.created.link_strength=100
   hf.histfig_links:resize(0);hf.histfig_links:insert('#',entry.created)
  end
 end
 local destination=-1
 if mode=='send' then
  for _,site in ipairs(world.world_data.sites)do
   if site.id~=df.global.plotinfo.site_id then
    for _,link in ipairs(site.entity_links)do
     if link.flags.residence and link.type==df.entity_site_link_type.All and link.start_hr==-1 then
      local owner=df.historical_entity.find(link.entity_id)
      if owner and owner.id~=df.global.plotinfo.group_id then
       local created=df.entity_site_link:new();created.target=df.global.plotinfo.site_id;created.entity_id=owner.id;created.flags.local_market=true
       fixture={owner=owner,created=created,links={}}
       for _,old in ipairs(owner.site_links)do fixture.links[#fixture.links+1]=old end
       owner.site_links:insert(0,created);destination=site.id
      end
      break
     end
    end
   end
   if fixture then break end
  end
  assert(fixture,'No governed destination')
 end
 result.destination=destination;result.before=snapshot()
 if family then result.relative_id=family.relative.id;result.relative_before=snapshot(family.relative)end
 local legacy=df.global.game.main_interface.view.expel_total_list
 local _,legacy_address=df.sizeof(legacy);local _,game_address=df.sizeof(df.global.game)
 result.legacy_list_offset=legacy_address-game_address;result.legacy_list_count=#legacy
 click(856,100)
 assert(sheet.unit_overview_expelling and sheet.unit_overview_expel_cannot_expel_reason==-1)
 if #sheet.unit_overview_expel_dest_stid>0 then
  local index
  for i,id in ipairs(sheet.unit_overview_expel_dest_stid)do if id==destination then index=i end end
  assert(index,'Destination absent');click(600,178+index*36)
 end
 assert(#sheet.unit_overview_expel_dest_stid==0 and sheet.unit_overview_expel_selected_dest_stid==destination)
 result.affected={};for _,id in ipairs(sheet.unit_overview_expel_total_unid)do result.affected[#result.affected+1]=id end
 assert(#result.affected==(family and 2 or 1) and result.affected[1]==unit.id,'Unexpected affected group')
 if os.getenv('DF3D_UNIT_EXPEL_EFFECT_LEGACY_GROUP')=='1' then
  legacy_saved={};for _,old in ipairs(legacy)do legacy_saved[#legacy_saved+1]=old end
  legacy:resize(0)
  for _,id in ipairs(result.affected)do legacy:insert('#',assert(df.unit.find(id)))end
  result.legacy_diagnostic_group=true
 end
 capture('unit-expel-effect-'..mode..'-before')
 if os.getenv('DF3D_UNIT_EXPEL_EFFECT_WIRE')=='1' then
  gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
  assert(not sheet.unit_overview_expelling)
  -- Async wire waits permit native redraws. Retire the native sheet so its
  -- own render/cache updates cannot be confused with bridge scratch writes.
  gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
  assert(not sheet.open,'Native unit sheet must be closed during wire acceptance')
  local output,status=dfhack.run_command_silent('df3d','unit-expel-preview-probe',tostring(unit.id))
  assert(status==0,output);local expected=json.decode(output);expected.destination=destination
  local file=assert(io.open(out..'/unit-expel-wire-expected.json','w'));file:write(json.encode(expected));file:close()
  local size,address=df.sizeof(sheet);local bytes=df.new('uint8_t',size)
  dfhack.internal.memmove(bytes,address,size)
  capture('unit-expel-wire-preview')
  file=assert(io.open(out..'/unit-expel-wire-preview.json'));result.wire_preview=json.decode(file:read('*a'));file:close()
  assert(result.wire_preview.success,'Expel wire preview/rejections failed')
  assert(json.encode(snapshot())==json.encode(result.before),'Wire preview/rejections changed creature')
  capture('unit-expel-wire-apply')
  file=assert(io.open(out..'/unit-expel-wire-apply.json'));result.wire_apply=json.decode(file:read('*a'));file:close()
  result.sheet_unchanged=dfhack.internal.memcmp(bytes,address,size)==0
  local observed=df.new('uint8_t',size);dfhack.internal.memmove(observed,address,size)
  result.sheet_changes={}
  for i=0,size-1 do if bytes[i]~=observed[i] then result.sheet_changes[#result.sheet_changes+1]={offset=i,before=bytes[i],after=observed[i]}end end
  df.delete(observed);df.delete(bytes)
  assert(result.wire_apply.success and result.sheet_unchanged,'Expel wire apply/sheet guard failed')
 elseif os.getenv('DF3D_UNIT_EXPEL_EFFECT_SEMANTIC')=='1' then
  gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
  assert(not sheet.unit_overview_expelling)
  local size,address=df.sizeof(sheet);local bytes=df.new('uint8_t',size)
  dfhack.internal.memmove(bytes,address,size)
  local function apply(id,dest,ids)
   local args={'df3d','unit-expel-apply-probe',tostring(id),tostring(dest)}
   for _,value in ipairs(ids)do args[#args+1]=tostring(value)end
   local output,status=dfhack.run_command_silent(table.unpack(args));assert(status==0,output)
   return json.decode(output).outcome
  end
  result.rejections={apply(unit.id,destination,{2147483000}),apply(unit.id,2147483000,result.affected),apply(2147483000,destination,result.affected)}
  for _,outcome in ipairs(result.rejections)do assert(outcome==1,'Expected stale intent rejection')end
  assert(json.encode(snapshot())==json.encode(result.before),'Rejected action changed selected creature')
  result.semantic_outcome=apply(unit.id,destination,result.affected)
  result.sheet_unchanged=dfhack.internal.memcmp(bytes,address,size)==0;df.delete(bytes)
  assert(result.semantic_outcome==2,'Semantic Expel did not apply')
  assert(result.sheet_unchanged,'Semantic Expel changed native sheet scratch')
  result.repeat_outcome=apply(unit.id,destination,result.affected)
  assert(result.repeat_outcome==1,'Already departing creature was accepted again')
 else click(476,730)end
 result.after=snapshot();result.expelling=sheet.unit_overview_expelling
 if family then result.relative_after=snapshot(family.relative)end
 result.events={}
 for i=result.before.history_count,#world.history.events-1 do
  local event=world.history.events[i]
  local row={id=event.id,type=event:getType()}
  if df.history_event_entity_expels_hfst:is_instance(event)then row.expelled=true end
  result.events[#result.events+1]=row
 end
 capture('unit-expel-effect-'..mode..'-after')
 assert(not sheet.unit_overview_expelling,'Native confirmation remained open')
 assert(result.after.controller and result.after.controller.goal==df.army_controller_goal_type.MOVE_TO_SITE and result.after.controller.site_id==destination,'Native departure controller differs')
 assert(result.after.army_id~=result.before.army_id and result.after.controllers==result.before.controllers+1,'Expected one new departure controller')
 assert(unit.flags2.visitor,'Native departure visitor flag absent')
 local expelled=false;for _,event in ipairs(result.events)do if event.expelled then expelled=true end end
 assert(expelled==(mode=='expel'),'Native expulsion history differs')
 assert(df.global.pause_state and world.frame_counter==frame,'Effect capture advanced simulation')
end,debug.traceback)
if fixture then
 fixture.owner.site_links:resize(0);for _,old in ipairs(fixture.links)do fixture.owner.site_links:insert('#',old)end
 fixture.created:delete()
end
if legacy_saved then
 local legacy=df.global.game.main_interface.view.expel_total_list
 legacy:resize(0);for _,old in ipairs(legacy_saved)do legacy:insert('#',old)end
end
if family then
 for _,entry in ipairs(family.entries)do
  entry.hf.histfig_links:resize(0);for _,old in ipairs(entry.links)do entry.hf.histfig_links:insert('#',old)end
  entry.created:delete()
 end
end
result.success=ok;result.error=not ok and err or nil
local file=assert(io.open(out..'/unit-expel-effect.json','w'));file:write(json.encode(result));file:close()
assert(ok,err)
return result
