-- Minimal paused terrain fixture for the native062137 count references.
-- This is acceptance-only setup, never runtime inference from native UI.
local out,index=...
local json=require('json')
local function read(path)local f=assert(io.open(path));local s=f:read('*a');f:close();return json.decode(s)end
local function write(path,v)local f=assert(io.open(path,'w'));f:write(json.encode(v));f:close()end
local function zones()
 local rows={}
 for _,b in ipairs(df.global.world.buildings.other.ANY_ZONE)do
  local extents={};for y=b.y1,b.y2 do for x=b.x1,b.x2 do extents[#extents+1]=b.room.extents[(y-b.room.y)*b.room.width+x-b.room.x]end end
  rows[#rows+1]={b.id,b.type,b.x1,b.y1,b.x2,b.y2,b.z,b.flags.whole,b.name,extents}
 end
 return json.encode(rows)
end
local function restore_collision_flags(state)
 -- The controlled overlap/add case touches the adjacent native bedroom's
 -- collision bit. Reject any other baseline flag change before restoration.
 for _,row in ipairs(json.decode(state.zones))do
  local b=assert(df.building.find(row[1]))
  if b.flags.whole~=row[8] then assert((b.flags.whole ~ row[8])==4,'unexpected baseline flag change');b.flags.whole=row[8]end
 end
end
local function baseline_unchanged(state)
 local rows={}
 local expected={};for _,row in ipairs(json.decode(state.zones))do expected[row[1]]=row end
 for _,row in ipairs(json.decode(zones()))do
  if not (state.bridge_ids and state.bridge_ids[row[1]])then
   local original=expected[row[1]]
   if state.bridge_ids and original and (row[8] ~ original[8])==4 then row[8]=original[8]end
   rows[#rows+1]=row
  end
 end
 return json.encode(rows)==state.zones
end
local request=index=='cleanup' and {op='paint_counts_cleanup'} or read(out..'/request-'..index..'.json')
local ok,err=pcall(function()
 assert(df.global.pause_state and df.global.world.frame_counter==0,'fixture must remain paused at frame0')
 if request.op=='paint_counts_location_details' then
  local source=debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])')
  assert(loadfile(source..'location-details-reference.lua'))(out,request.phase)
 elseif request.op=='paint_counts_location_list' then
  local source=debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])')
  assert(loadfile(source..'location-list-reference.lua'))(out)
 elseif request.op=='paint_counts_begin' then
  assert(not _G.df3d_paint_counts_fixture,'fixture already exists')
  local state={tiles={},zones=zones(),baseline_ids={},created_ids={}};_G.df3d_paint_counts_fixture=state
  for _,b in ipairs(df.global.world.buildings.other.ANY_ZONE)do state.baseline_ids[b.id]=true end
  for z=164,165 do for y=57,59 do for x=170,173 do
   local b=assert(dfhack.maps.getTileBlock(x,y,z));local bx,by=x%16,y%16
   state.tiles[#state.tiles+1]={b=b,x=bx,y=by,t=b.tiletype[bx][by],d=b.designation[bx][by].whole,o=b.occupancy[bx][by].whole}
   b.tiletype[bx][by]=df.tiletype.StoneFloor1
   b.designation[bx][by].hidden=false;b.designation[bx][by].flow_size=0
   b.occupancy[bx][by].building=0
   assert(b.tiletype[bx][by]==df.tiletype.StoneFloor1 and not b.designation[bx][by].hidden and b.designation[bx][by].flow_size==0 and b.occupancy[bx][by].building==0)
  end end end
 elseif request.op=='paint_counts_controls' or request.op=='paint_counts_switches' or request.op=='paint_counts_brush' or request.op=='paint_counts_elevation' or request.op=='paint_counts_repaint_elevation' or request.op=='paint_counts_location_choices' or request.op=='paint_counts_location_eligibility' or request.op=='paint_counts_guild_workers' then
  local state=assert(_G.df3d_paint_counts_fixture)
  local capture_path=out..(request.op=='paint_counts_switches' and '/native-paint-switches.json' or '/native-paint-controls.json')
  if request.op=='paint_counts_brush' then capture_path=out..'/native-paint-brush.json'end
  if request.op=='paint_counts_elevation' then capture_path=out..'/native-paint-elevation.json'end
  if request.op=='paint_counts_repaint_elevation' then capture_path=out..'/native-paint-repaint-elevation.json'end
  if request.op=='paint_counts_location_choices' then capture_path=out..'/native-location-choices.json'end
  if request.op=='paint_counts_location_eligibility' then capture_path=out..'/native-location-eligibility-zones.json'end
  if request.op=='paint_counts_guild_workers' then capture_path=out..'/native-guild-worker-zones.json'end
  local function restore_zones()
   for id in pairs(state.created_ids)do
    local b=df.building.find(id)
    if b then assert(not state.baseline_ids[id]);assert(dfhack.buildings.deconstruct(b),'native capture cleanup failed')end
   end
   if zones()~=state.zones then write(out..'/native-restore-mismatch.json',{expected=json.decode(state.zones),actual=json.decode(zones())})end
   assert(zones()==state.zones,'native capture left a draft')
  end
  local function key(k)require('gui').simulateInput(dfhack.gui.getDFViewscreen(true),k)end
  local function pixel(x,y)
   local g=df.global.gps;g.precise_mouse_x=x;g.precise_mouse_y=y
   g.mouse_x=x//(g.screen_pixel_x//g.dimx);g.mouse_y=y//(g.screen_pixel_y//g.dimy)
   key('_MOUSE_L')
  end
  local function mappoint(x,y,z)
   local g=df.global.gps
   for ty=0,g.dimy-1 do for tx=0,g.dimx-1 do
    g.mouse_x=tx;g.mouse_y=ty;g.precise_mouse_x=tx*(g.screen_pixel_x//g.dimx)+4;g.precise_mouse_y=ty*(g.screen_pixel_y//g.dimy)+6
    local p=dfhack.gui.getMousePos(true)
    if p and p.x==x and p.y==y and p.z==z then return end
   end end
   error('capture tile outside viewport')
  end
  local function mapclick(x,y,z)mappoint(x,y,z);key('_MOUSE_L')end
  local function feed(x,y,phase,z)
   mappoint(x,y,z or 164)
   local e=df.global.enabler;local lift=e.mouse_lbut_lift
   e.mouse_lbut_lift=phase=='release' and 1 or 0
   local ok,why=pcall(function()
    key(phase=='press' and {'_MOUSE_L','_MOUSE_L_DOWN'} or phase=='hold' and {'_MOUSE_L_DOWN'} or {})
   end)
   e.mouse_lbut_lift=lift;assert(ok,why)
  end
  local rows={}
  local function record(label)
   local ui=df.global.game.main_interface.civzone
   local count=0;local b=ui.cur_bld
   if b and b.room.extents then for y=b.y1,b.y2 do for x=b.x1,b.x2 do if b.room.extents[(y-b.room.y)*b.room.width+x-b.room.x]~=0 then count=count+1 end end end end
   if b and b.id>=0 and not state.baseline_ids[b.id] then state.created_ids[b.id]=true end
   dfhack.gui.getDFViewscreen(true):render(dfhack.getTickCount())
   local lines={}
   local full=request.op=='paint_counts_location_choices'
   for y=0,(full and df.global.gps.dimy-1 or 22) do local s=''for x=0,(full and df.global.gps.dimx-1 or 45) do local c=dfhack.screen.readTile(x,y);local ch=c and c.ch or 32;s=s..(ch>=32 and ch<127 and string.char(ch)or' ')end;lines[#lines+1]=s end
   rows[#rows+1]={label=label,rectangle=ui.doing_rectangle,erasing=ui.erasing,multi=ui.doing_multizone,tiles=count,
    current=b and b.id or -1,zone_z=b and b.z or -1,focus=dfhack.gui.getCurFocus(true),screen=table.concat(lines,'\n'),world_zones=json.decode(zones())}
   if full then
    local location=df.global.game.main_interface.location_selector
    local choices={religions={},guilds={},temple_open=location.choosing_temple_religious_practice,guild_open=location.choosing_craft_guild,
     temple_scroll=location.scroll_position_deity,guild_scroll=location.scroll_position_guild}
    for i,kind in ipairs(location.valid_religious_practice)do choices.religions[#choices.religions+1]={kind=kind,id=location.valid_religious_practice_id[i]}end
    for _,kind in ipairs(location.valid_craft_guild_type)do choices.guilds[#choices.guilds+1]={profession=kind,enum=df.profession[kind]}end
    rows[#rows].choices=choices
    local text,glyphs={},{}
    for y=0,df.global.gps.dimy-1 do
     local line,raw='',{}
     for x=0,df.global.gps.dimx-1 do
      local tile=dfhack.screen.readTile(x,y);local ch=tile and tile.ch or 32
      raw[#raw+1]=ch;line=line..(ch>=32 and ch<=255 and string.char(ch)or' ')
     end
     text[#text+1]=dfhack.df2utf(line);glyphs[#glyphs+1]=raw
    end
    rows[#rows].screen_utf8=table.concat(text,'\n');rows[#rows].glyphs=glyphs
   end
   write(capture_path,rows)
  end
  if request.op=='paint_counts_controls' then
  -- Button locations were inspected in native224155 regular_multiz_draft.png.
  df.global.game.main_interface.bottom_mode_selected=-1;key('D_CIVZONE')
  dfhack.gui.revealInDwarfmodeMap({x=171,y=58,z=164},true)
  pixel(55,320);pixel(310,202)
  record('initial');mapclick(170,57,164);record('first-corner')
  mapclick(172,59,164);record('second-corner')
  pixel(120,154);record('erase-on')
  pixel(88,154);record('brush-while-erasing')
  pixel(56,154);record('rectangle-while-erasing')
  pixel(120,154);record('erase-off')
  pixel(88,154);record('brush')
  pixel(120,154);record('brush-erase-on')
  pixel(120,154);record('brush-erase-off')
  pixel(56,154);record('rectangle')
  mapclick(170,57,164);pixel(120,154);record('partial-toggle-erase')
  mapclick(171,58,164);record('partial-toggle-erase-completed')
  pixel(310,82)
  assert(zones()==state.zones,'toggle capture left a draft')
  df.global.game.main_interface.bottom_mode_selected=-1;key('D_CIVZONE')
  dfhack.gui.revealInDwarfmodeMap({x=171,y=58,z=164},true)
  pixel(55,320);pixel(310,202)
  mapclick(170,57,164);mapclick(172,59,164);record('escape-baseline')
  mapclick(170,57,164);record('escape-pending')
  key('LEAVESCREEN');record('escape-partial')
  restore_zones()
  -- Distinguish native exit keys from the on-screen rollback control. Capture
  -- committed world extents as well as focus: cur_bld/tool flags survive exit.
  -- _MOUSE_R is a gui.simulateInput synthetic mouse key, not interface_key.
  for _,action in ipairs({'escape','right-click','cancel'})do
   for _,stage in ipairs({'empty-partial','painted','painted-partial'})do
    df.global.game.main_interface.bottom_mode_selected=-1;key('D_CIVZONE')
    dfhack.gui.revealInDwarfmodeMap({x=171,y=58,z=164},true)
    pixel(55,320);pixel(310,202)
    if stage~='empty-partial' then mapclick(170,57,164);mapclick(172,59,164)end
    if stage~='painted' then mapclick(170,57,164)end
    local label=action..'-'..stage
    record(label..'-before')
    if action=='escape' then key('LEAVESCREEN')
    elseif action=='right-click' then key('_MOUSE_R')
    else pixel(310,82)end
    record(label..'-after')
    key('LEAVESCREEN')
    restore_zones()
   end
  end
  local function begin_zone()
   df.global.game.main_interface.bottom_mode_selected=-1;key('D_CIVZONE')
   dfhack.gui.revealInDwarfmodeMap({x=171,y=58,z=164},true)
   pixel(55,320);pixel(310,202)
   mapclick(170,57,164);mapclick(172,59,164)
  end
  for _,action in ipairs({'escape','right-click','accept'})do
   begin_zone();record('repaint-'..action..'-created')
   local created_id=assert(df.global.game.main_interface.civzone.cur_bld).id
   assert(state.created_ids[created_id],'repaint must own its target')
   pixel(310,118);record('repaint-'..action..'-accepted')
   mapclick(171,58,164);pixel(272,118);record('repaint-'..action..'-start')
   assert(df.global.game.main_interface.civzone.cur_bld and df.global.game.main_interface.civzone.cur_bld.id==created_id,'repaint selected a different zone')
   -- Stay inside the probe-owned footprint. Column173 overlaps an existing
   -- native bedroom and repaint legitimately changes its room_collision flag.
   pixel(120,154);mapclick(170,57,164);mapclick(171,57,164);record('repaint-'..action..'-edited')
   mapclick(170,57,164);record('repaint-'..action..'-pending')
   if action=='escape' then key('LEAVESCREEN')
   elseif action=='right-click' then key('_MOUSE_R')
   else pixel(310,118)end
   record('repaint-'..action..'-after')
   key('LEAVESCREEN');restore_zones()
  end
  begin_zone();record('new-erase-all-before')
  pixel(120,154);mapclick(170,57,164);mapclick(172,59,164)
  record('new-erase-all-after')
  pixel(120,154);mapclick(170,57,164);mapclick(170,57,164)
  record('new-erase-all-readd')
  pixel(310,82);record('new-erase-all-cancel')
  key('LEAVESCREEN');restore_zones()
  for _,existing in ipairs({false,true})do
   for _,action in ipairs({'escape','accept'})do
    begin_zone()
    record('empty-exit-created')
    local created_id=df.global.game.main_interface.civzone.cur_bld.id
    if existing then
     pixel(310,118);mapclick(171,58,164);pixel(272,118)
     assert(df.global.game.main_interface.civzone.cur_bld and df.global.game.main_interface.civzone.cur_bld.id==created_id,'empty repaint selected a different zone')
    end
    local label=(existing and 'existing' or 'new')..'-empty-'..action
    pixel(120,154);mapclick(170,57,164);mapclick(172,59,164)
    record(label..'-before')
    if action=='escape' then key('LEAVESCREEN')else pixel(310,118)end
    record(label..'-after')
    key('LEAVESCREEN');restore_zones()
   end
  end
  elseif request.op=='paint_counts_switches' then
  for _,stage in ipairs({'empty-partial','painted','painted-partial','erased-empty'})do
   df.global.game.main_interface.bottom_mode_selected=-1;key('D_CIVZONE')
   dfhack.gui.revealInDwarfmodeMap({x=171,y=58,z=164},true)
   pixel(55,320);pixel(310,202)
   if stage~='empty-partial' then mapclick(170,57,164);mapclick(172,59,164);record('switch-'..stage..'-created')end
   if stage=='erased-empty' then pixel(120,154);mapclick(170,57,164);mapclick(172,59,164)end
   if stage=='empty-partial' or stage=='painted-partial' then mapclick(170,57,164)end
   record('switch-'..stage..'-before')
   pixel(310,166);record('switch-'..stage..'-multi')
   mapclick(170,57,164);record('switch-'..stage..'-multi-partial')
   pixel(310,202);record('switch-'..stage..'-paint')
   mapclick(170,57,164);record('switch-'..stage..'-paint-first')
   mapclick(172,59,164);record('switch-'..stage..'-paint-second')
   key('LEAVESCREEN');record('switch-'..stage..'-exit')
   restore_zones()
  end
  elseif request.op=='paint_counts_guild_workers' then
   df.global.game.main_interface.bottom_mode_selected=-1;key('D_CIVZONE')
   dfhack.gui.revealInDwarfmodeMap({x=171,y=58,z=164},true)
   pixel(55,320);pixel(310,202);mapclick(170,57,164);mapclick(172,59,164)
   record('created');pixel(310,118)
   local unit
   for _,u in ipairs(df.global.world.units.active)do
    if dfhack.units.isActive(u) and dfhack.units.isAlive(u) and dfhack.units.isCitizen(u)then unit=u;break end
   end
   assert(unit,'no guild worker probe unit')
   local original,secondary=unit.profession,unit.profession2
   local selector=df.global.game.main_interface.location_selector
   local guild_comparisons={}
   local function observe()
    pixel(336,190);pixel(610,154);assert(selector.choosing_craft_guild,'guild selector did not open')
    local text,status=dfhack.run_command_silent('df3d','location-guilds-read')
    assert(status==0,'bridge guild read failed');local bridge=json.decode(text);assert(bridge.valid,'bridge guild reader unavailable')
    assert(#bridge.choices==#selector.valid_craft_guild_type,'bridge guild choice count differs')
    for i,profession in ipairs(selector.valid_craft_guild_type)do assert(bridge.choices[i+1].profession==profession,'bridge guild order differs')end
    guild_comparisons[#guild_comparisons+1]=bridge.choices
    local result={}
    for _,name in ipairs({'WOODWORKER','STONEWORKER','CRAFTSMAN','FARMER','DOCTOR'})do
     local index
     for i,profession in ipairs(selector.valid_craft_guild_type)do if profession==df.profession[name]then index=i;break end end
     assert(index,'native guild choice absent')
     local first=math.min(index,math.max(0,#selector.valid_craft_guild_type-10));selector.scroll_position_guild=first
     local g=df.global.gps;local tx,ty=56,9+3*(index-first)
     g.mouse_x=tx;g.mouse_y=ty;g.precise_mouse_x=tx*(g.screen_pixel_x//g.dimx)+4;g.precise_mouse_y=ty*(g.screen_pixel_y//g.dimy)+6
     key({});dfhack.gui.getDFViewscreen(true):render(dfhack.getTickCount());assert(selector.current_hover_index==index,'worker hover differs')
     local lines={}
     for y=5,40 do local line=''for x=46,120 do local tile=dfhack.screen.readTile(x,y);local ch=tile and tile.ch or 32;line=line..(ch>=32 and ch<=255 and string.char(ch)or' ')end;lines[#lines+1]=dfhack.df2utf(line)end
     local screen=table.concat(lines,'\n');local count=screen:match('(%d+) worker')
     if screen:find('No workers',1,true)then count='0'end
     assert(count,'native worker count missing');assert(bridge.choices[index+1].workers==tonumber(count),'bridge worker count differs: '..name)
     result[name]={workers=tonumber(count),screen=screen}
    end
    key('LEAVESCREEN');key('LEAVESCREEN');return result
   end
   local result={unit=unit.id,original=original,secondary=secondary,baseline=observe(),cases={}}
   local success,why=pcall(function()
    for _,name in ipairs({'MINER','WOODWORKER','CARPENTER','STONEWORKER','STONECUTTER','STONE_CARVER','ENGRAVER','CRAFTSMAN','WOODCRAFTER','PAPERMAKER','BOOKBINDER','FARMER','CHEESE_MAKER','DOCTOR','DIAGNOSER'})do
     unit.profession=df.profession[name];unit.profession2=secondary
     result.cases[#result.cases+1]={label=name,profession=unit.profession,profession2=unit.profession2,observed=observe()}
     unit.profession=original;unit.profession2=secondary;write(out..'/native-guild-workers.json',result)
    end
    unit.profession2=df.profession.CRAFTSMAN
    result.cases[#result.cases+1]={label='secondary-only',profession=unit.profession,profession2=unit.profession2,observed=observe()}
   end)
   unit.profession=original;unit.profession2=secondary
   assert(unit.profession==original and unit.profession2==secondary,'profession restoration failed');assert(success,why)
   result.restored=observe()
   for name,row in pairs(result.baseline)do assert(result.restored[name].workers==row.workers,'restored worker count differs')end
   result.restoration_verified=true;result.bridge_comparisons=guild_comparisons;write(out..'/native-guild-workers.json',result)
   key('LEAVESCREEN');restore_zones()
  elseif request.op=='paint_counts_location_eligibility' then
   df.global.game.main_interface.bottom_mode_selected=-1;key('D_CIVZONE')
   dfhack.gui.revealInDwarfmodeMap({x=171,y=58,z=164},true)
   pixel(55,320);pixel(310,202);mapclick(170,57,164);mapclick(172,59,164)
   record('created');pixel(310,118)
   local selector=df.global.game.main_interface.location_selector
   local bridge_comparisons={}
   local function choices()
    pixel(336,190);pixel(610,118)
    assert(selector.open and selector.choosing_temple_religious_practice,'temple control failed')
    local result={}
    for i,kind in ipairs(selector.valid_religious_practice)do result[#result+1]={kind=kind,id=selector.valid_religious_practice_id[i]}end
    local text,status=dfhack.run_command_silent('df3d','location-religions-read')
    assert(status==0,'bridge location read failed: '..tostring(text))
    local observed=json.decode(text);assert(observed.valid,'bridge location read unavailable')
    assert(#observed.choices==#result,'bridge location choice count differs')
    for i,row in ipairs(result)do
     local kind=row.kind==-1 and 1 or row.kind==0 and 2 or row.kind==1 and 3 or -1
     assert(observed.choices[i].kind==kind and observed.choices[i].id==row.id,'bridge ordered location identity differs at '..i)
    end
    bridge_comparisons[#bridge_comparisons+1]=observed.choices
    key('LEAVESCREEN');key('LEAVESCREEN');return result
   end
   local baseline=choices();local present={}
   for _,row in ipairs(baseline)do if row.kind==0 then present[row.id]=true end end
   local unit,link,group,probe
   for _,candidate in ipairs(df.global.world.units.active)do
    local hf=df.historical_figure.find(candidate.hist_figure_id)
    if hf then
     for _,item in ipairs(hf.histfig_links)do
      if item:getType()==df.histfig_hf_link_type.DEITY then
       if not present[item.target_hf] and df.historical_figure.find(item.target_hf)then probe=probe or item.target_hf end
       if not unit and dfhack.units.isActive(candidate) and dfhack.units.isAlive(candidate) and dfhack.units.isCitizen(candidate)then
        for _,member in ipairs(hf.entity_links)do
         if member:getType()==df.histfig_entity_link_type.MEMBER and member.entity_id==df.global.plotinfo.group_id then unit,link,group=candidate,item,member;break end
        end
       end
      end
     end
    end
   end
   assert(unit and link and group and probe,'missing controlled membership probe')
   local original={flags1=unit.flags1.whole,flags2=unit.flags2.whole,flags3=unit.flags3.whole,civ=unit.civ_id,mood=unit.mood,target=link.target_hf,strength=link.link_strength,group=group.entity_id}
   local function restore()
    unit.flags1.whole=original.flags1;unit.flags2.whole=original.flags2;unit.flags3.whole=original.flags3
    unit.civ_id=original.civ;unit.mood=original.mood;link.target_hf=original.target;link.link_strength=original.strength;group.entity_id=original.group
    assert(unit.flags1.whole==original.flags1 and unit.flags2.whole==original.flags2 and unit.flags3.whole==original.flags3 and unit.civ_id==original.civ and unit.mood==original.mood and link.target_hf==original.target and link.link_strength==original.strength and group.entity_id==original.group,'probe restoration failed')
   end
   local result={unit=unit.id,probe_deity=probe,baseline=baseline,cases={}}
   local ok_case,why=pcall(function()
    local cases={
     {'linked',function()end},
     {'foreign-civ-citizen',function()unit.civ_id=-1 end},
     {'own-civ-resident',function()group.entity_id=-1 end},
     {'foreign-nonmember',function()unit.civ_id=-1;group.entity_id=-1 end},
     {'citizen-visitor',function()unit.flags2.visitor=true end},
     {'resident-visitor',function()group.entity_id=-1;unit.flags2.visitor=true end},
     {'inactive',function()unit.flags1.inactive=true end},
     {'killed',function()unit.flags2.killed=true end},
     {'ghostly',function()unit.flags3.ghostly=true end},
     {'berserk',function()unit.mood=df.mood_type.Berserk end},
     {'melancholy',function()unit.mood=df.mood_type.Melancholy end},
     {'raving',function()unit.mood=df.mood_type.Raving end},
     {'merchant',function()unit.flags1.merchant=true end},
     {'diplomat',function()unit.flags1.diplomat=true end},
     {'forest',function()unit.flags1.forest=true end},
     {'active-invader',function()unit.flags1.active_invader=true end},
     {'invader-origin',function()unit.flags1.invader_origin=true end},
     {'marauder',function()unit.flags1.marauder=true end},
     {'resident-flag',function()unit.flags2.resident=true end},
     {'uninvited-visitor',function()unit.flags2.visitor_uninvited=true end},
     {'underworld',function()unit.flags2.underworld=true end},
     {'foreign-tame',function()unit.civ_id=-1;unit.flags1.tame=true end},
     {'tame-visitor',function()unit.flags1.tame=true;unit.flags2.visitor=true end},
     {'tame-invader',function()unit.flags1.tame=true;unit.flags1.active_invader=true end},
     {'zero-strength',function()link.link_strength=0 end}}
    for _,case in ipairs(cases)do
     restore();link.target_hf=probe;case[2]()
     local observed=choices();local included=false
     for _,row in ipairs(observed)do if row.kind==0 and row.id==probe then included=true end end
     result.cases[#result.cases+1]={label=case[1],included=included,choices=observed,civ=unit.civ_id,citizen=dfhack.units.isCitizen(unit),resident=dfhack.units.isResident(unit),active=dfhack.units.isActive(unit),alive=dfhack.units.isAlive(unit),fort_controlled=dfhack.units.isFortControlled(unit)}
     restore();write(out..'/native-location-eligibility.json',result)
    end
   end)
   restore();assert(ok_case,why)
   result.restored=choices();assert(json.encode(result.restored)==json.encode(baseline),'restored native choices differ')
   result.restoration_verified=true;result.bridge_comparisons=bridge_comparisons;write(out..'/native-location-eligibility.json',result)
   key('LEAVESCREEN');restore_zones()
  elseif request.op=='paint_counts_location_choices' then
   -- Independent world facts for catalog derivation, never native UI input.
   local facts={units={},entities={},cultures={},site_practices={},figures={},locations={},civ_id=df.global.plotinfo.civ_id,group_id=df.global.plotinfo.group_id,site_id=df.global.plotinfo.site_id}
   local site=assert(df.world_site.find(df.global.plotinfo.site_id))
   local figures={}
   local function record_figure(id)
    if figures[id]then return end
    figures[id]=true
    local figure=df.historical_figure.find(id);if not figure then return end
    local spheres={}
    if figure.info and figure.info.metaphysical then
     for _,sphere in ipairs(figure.info.metaphysical.spheres)do spheres[#spheres+1]={id=sphere,key=df.sphere_type[sphere]}end
    end
    facts.figures[#facts.figures+1]={id=id,name=dfhack.df2utf(dfhack.translation.translateName(figure.name,true)),native_name=dfhack.df2utf(dfhack.translation.translateName(figure.name,false)),spheres=spheres}
   end
   for _,location in ipairs(site.buildings)do
    local contents=location:getContents()
    if contents then
     local zones={};for _,id in ipairs(contents.building_ids)do zones[#zones+1]=id end
     local row={id=location.id,kind=df.abstract_building_type[location:getType()],owner=location.site_owner_id,profession=contents.profession,recognized=contents.need_more.entity_recognized,zones=zones,name=dfhack.df2utf(dfhack.translation.translateName(location:getName(),true))}
     if df.abstract_building_templest:is_instance(location)then row.practice_kind=location.deity_type;row.practice_id=location.deity_data.practice_id end
     facts.locations[#facts.locations+1]=row
    end
   end
   for _,batch in ipairs(site.culture_infrastructure.religious_structure_batch)do
    for i=0,batch.rstructnum-1 do local row=batch.rstruct[i];facts.site_practices[#facts.site_practices+1]={kind=row.type,id=row.data.practice_id,points=row.points}end
   end
   local cultures={}
   for _,entity in ipairs(df.global.world.entities.all)do
    if entity.type==df.historical_entity_type.Religion or entity.type==df.historical_entity_type.Guild or entity.id==facts.civ_id or entity.id==facts.group_id then
     local deities={};for _,id in ipairs(entity.relations.deities)do deities[#deities+1]=id;record_figure(id)end
     local professions={};for _,focus in ipairs(entity.guild_professions)do professions[#professions+1]={kind=focus.type,profession=focus.profession}end
     local sites={};for _,link in ipairs(entity.site_links)do sites[#sites+1]={id=link.target,kind=link.type,flags=link.flags.whole,former_flags=link.former_flag.whole}end
     facts.entities[#facts.entities+1]={id=entity.id,type=entity.type,type_name=df.historical_entity_type[entity.type],name=dfhack.df2utf(dfhack.translation.translateName(entity.name,true)),deities=deities,professions=professions,sites=sites}
    end
   end
   for _,unit in ipairs(df.global.world.units.active)do
    local hf=df.historical_figure.find(unit.hist_figure_id)
    if hf then
     local figure_links,entity_links={},{}
     for _,link in ipairs(hf.histfig_links)do figure_links[#figure_links+1]={kind=df.histfig_hf_link_type[link:getType()],id=link.target_hf,strength=link.link_strength};if link:getType()==df.histfig_hf_link_type.DEITY then record_figure(link.target_hf)end end
     for _,link in ipairs(hf.entity_links)do entity_links[#entity_links+1]={kind=df.histfig_entity_link_type[link:getType()],id=link.entity_id}end
     local skills={}
     if unit.status.current_soul then for _,skill in ipairs(unit.status.current_soul.skills)do skills[#skills+1]={id=skill.id,rating=skill.rating}end end
     facts.units[#facts.units+1]={id=unit.id,hfid=hf.id,civ_id=unit.civ_id,citizen=dfhack.units.isCitizen(unit),resident=dfhack.units.isResident(unit),
      active=dfhack.units.isActive(unit),alive=dfhack.units.isAlive(unit),fort_controlled=dfhack.units.isFortControlled(unit),visiting=dfhack.units.isVisiting(unit),culture=hf.cultural_identity,
      profession=unit.profession,profession2=unit.profession2,skills=skills,figure_links=figure_links,entity_links=entity_links}
     if hf.cultural_identity>=0 and not cultures[hf.cultural_identity]then
      cultures[hf.cultural_identity]=true
      local culture=df.cultural_identity.find(hf.cultural_identity);local practices={}
      if culture then for _,row in ipairs(culture.religious_practice)do practices[#practices+1]={kind=row.type,id=row.data.practice_id,points=row.points}end end
      facts.cultures[#facts.cultures+1]={id=hf.cultural_identity,practices=practices}
     end
    end
   end
   write(out..'/location-world-facts.json',facts)
   df.global.game.main_interface.bottom_mode_selected=-1;key('D_CIVZONE')
   dfhack.gui.revealInDwarfmodeMap({x=171,y=58,z=164},true)
   pixel(55,320);pixel(310,202);mapclick(170,57,164);mapclick(172,59,164)
   record('created');pixel(310,118);pixel(336,190);record('location-selector')
   pixel(610,118)
   local selector=df.global.game.main_interface.location_selector
   assert(selector.open and selector.choosing_temple_religious_practice,'native Temple selector did not open')
   local metadata={}
   local function hover_rows(kind,count)
    for index=0,count-1 do
     local first=math.min(index,math.max(0,count-10))
     if kind=='temple' then selector.scroll_position_deity=first else selector.scroll_position_guild=first end
     local g=df.global.gps;local tx,ty=56,9+3*(index-first)
     g.mouse_x=tx;g.mouse_y=ty;g.precise_mouse_x=tx*(g.screen_pixel_x//g.dimx)+4;g.precise_mouse_y=ty*(g.screen_pixel_y//g.dimy)+6
     key({});dfhack.gui.getDFViewscreen(true):render(dfhack.getTickCount())
     local lines={}
     for y=5,40 do
      local line=''
      for x=46,120 do local tile=dfhack.screen.readTile(x,y);local ch=tile and tile.ch or 32;line=line..(ch>=32 and ch<=255 and string.char(ch)or' ')end
      lines[#lines+1]=dfhack.df2utf(line)
     end
     metadata[#metadata+1]={kind=kind,index=index,hover=selector.current_hover_index,scroll=first,screen=table.concat(lines,'\n')}
    end
    write(out..'/native-location-metadata.json',metadata)
   end
   local scroll_observations={}
   local scroll_art={}
   local scroll_states={}
   local function capture_scroll(kind,count)
    local field=kind=='temple' and 'scroll_position_deity' or 'scroll_position_guild'
    local original=selector[field]
    local gps=df.global.gps
    local cell_w,cell_h=gps.screen_pixel_x//gps.dimx,gps.screen_pixel_y//gps.dimy
    local inset_x,inset_y=(gps.screen_pixel_x-cell_w*gps.dimx)//2,(gps.screen_pixel_y-cell_h*gps.dimy)//2
    write(out..'/native-location-scroll-geometry.json',{width=gps.screen_pixel_x,height=gps.screen_pixel_y,
     columns=gps.dimx,rows=gps.dimy,cell_width=cell_w,cell_height=cell_h,inset_x=inset_x,inset_y=inset_y})
    local function point(y)
     local g=df.global.gps;g.precise_mouse_x=680;g.precise_mouse_y=y
     g.mouse_x=(680-inset_x)//cell_w;g.mouse_y=(y-inset_y)//cell_h
    end
    local function observe(label,start,y,input)
     selector[field]=start;point(y);key({});dfhack.gui.getDFViewscreen(true):render(dfhack.getTickCount())
     key(input)
     scroll_observations[#scroll_observations+1]={kind=kind,count=count,label=label,start=start,y=y,after=selector[field]}
    end
    -- Inputs stay on the scrollbar, never over an actionable location row.
    for y=100,111 do observe('up-arrow',20,y,'_MOUSE_L')end
    for y=448,459 do observe('down-arrow',20,y,'_MOUSE_L')end
    for y=112,447,12 do observe('track-from-top',0,y,'_MOUSE_L')end
    for _,input in ipairs({'STANDARDSCROLL_UP','STANDARDSCROLL_DOWN','STANDARDSCROLL_PAGEUP','STANDARDSCROLL_PAGEDOWN',
                          'CONTEXT_SCROLL_UP','CONTEXT_SCROLL_DOWN','CONTEXT_SCROLL_PAGEUP','CONTEXT_SCROLL_PAGEDOWN'})do
     observe(input,20,280,input)
    end
    observe('up-at-start',0,106,'_MOUSE_L')
    observe('down-at-end',count-10,454,'_MOUSE_L')
    for destination=90,470 do
     selector[field]=0;point(kind=='temple' and 142 or 136)
     local after_press
     local e=df.global.enabler;local lift=e.mouse_lbut_lift
     local ok,why=pcall(function()
      e.mouse_lbut_lift=0;key({'_MOUSE_L','_MOUSE_L_DOWN'})
      after_press=selector[field]
      point(destination);key({'_MOUSE_L_DOWN'})
      e.mouse_lbut_lift=1;key({})
     end)
     e.mouse_lbut_lift=lift;assert(ok,why)
     scroll_observations[#scroll_observations+1]={kind=kind,count=count,label='drag-from-top',start=0,y=destination,after_press=after_press,after=selector[field]}
    end
    for first=0,count-10 do
     selector[field]=first;gps.mouse_x=56;gps.mouse_y=9
     gps.precise_mouse_x=452;gps.precise_mouse_y=118
     key({});dfhack.gui.getDFViewscreen(true):render(dfhack.getTickCount())
     local tiles={}
     for y=8,37 do
      local left,right=dfhack.screen.readTile(84,y),dfhack.screen.readTile(85,y)
      tiles[#tiles+1]={left=left.tile,right=right.tile}
     end
     scroll_art[#scroll_art+1]={kind=kind,count=count,first=first,base=df.global.init.scrollbar_texpos[0],tiles=tiles}
    end
    local function state_art(label,total,y,pressed)
     local tiles={}
     dfhack.gui.getDFViewscreen(true):render(dfhack.getTickCount())
     for ty=8,37 do
      local left,right=dfhack.screen.readTile(84,ty),dfhack.screen.readTile(85,ty)
      tiles[#tiles+1]={left=left.tile,right=right.tile}
     end
     scroll_states[#scroll_states+1]={kind=kind,count=total,label=label,first=selector[field],hover_y=y,
      pressed=pressed,anchor=scroll_art[1].tiles[1].left,tiles=tiles}
    end
    local e=df.global.enabler
    local saved_mouse={button=e.mouse_lbut,down=e.mouse_lbut_down,lift=e.mouse_lbut_lift}
    local hover_ok,hover_error=pcall(function()
     for _,pressed in ipairs({false,true})do
      for _,y in ipairs({90,100,106,111,112,130,142,160,200,448,454,459,470})do
       if not pressed or (y>=100 and y<460)then
       selector[field]=20;point(y)
       e.mouse_lbut=pressed and 1 or 0;e.mouse_lbut_down=pressed and 1 or 0;e.mouse_lbut_lift=pressed and 0 or 1
       key(pressed and {'_MOUSE_L','_MOUSE_L_DOWN'} or {})
       state_art('hover',count,y,pressed)
       e.mouse_lbut=0;e.mouse_lbut_down=0;e.mouse_lbut_lift=1;key({})
       end
      end
     end
    end)
    e.mouse_lbut=saved_mouse.button;e.mouse_lbut_down=saved_mouse.down;e.mouse_lbut_lift=saved_mouse.lift
    assert(hover_ok,hover_error)
    -- Restrict/extend only the ephemeral native selector vectors, never world data.
    -- Repeated existing identities are test setup for native layout, not product choices.
    local vectors=kind=='temple' and {selector.valid_religious_practice,selector.valid_religious_practice_id} or {selector.valid_craft_guild_type}
    local backups={}
    for i,vector in ipairs(vectors)do backups[i]={};for _,value in ipairs(vector)do backups[i][#backups[i]+1]=value end end
    local sizes_ok,sizes_error=pcall(function()
     for _,total in ipairs({0,1,9,10,11,12,14,20,40,100,140,280})do
      for i,vector in ipairs(vectors)do vector:resize(total);for index=0,total-1 do vector[index]=backups[i][index%#backups[i]+1]end end
      for _,first in ipairs({0,math.max(0,(total-10)//2),math.max(0,total-10)})do
       selector[field]=first;gps.mouse_x=140;gps.mouse_y=50;gps.precise_mouse_x=1124;gps.precise_mouse_y=610
       key({});state_art('size',total,-1,false)
      end
     end
    end)
    for i,vector in ipairs(vectors)do vector:resize(#backups[i]);for index,value in ipairs(backups[i])do vector[index-1]=value end end
    assert(sizes_ok,sizes_error)
    selector[field]=original
    write(out..'/native-location-scroll.json',scroll_observations)
    write(out..'/native-location-scroll-art.json',scroll_art)
    write(out..'/native-location-scroll-states.json',scroll_states)
   end
   record('new-temple')
   for first=8,#selector.valid_religious_practice-1,8 do selector.scroll_position_deity=first;record('temple-page-'..first)end
   hover_rows('temple',#selector.valid_religious_practice)
   capture_scroll('temple',#selector.valid_religious_practice)
   local sphere_figure,sphere_index
   for i,kind in ipairs(selector.valid_religious_practice)do
    if kind==df.religious_practice_type.WORSHIP_HFID then
     local figure=df.historical_figure.find(selector.valid_religious_practice_id[i])
     if figure and figure.info and figure.info.metaphysical and #figure.info.metaphysical.spheres==1 then sphere_figure=figure;sphere_index=i;break end
    end
   end
   assert(sphere_figure,'no single-sphere deity for caption controls')
   local sphere_original=sphere_figure.info.metaphysical.spheres[0]
   local sphere_result={deity=sphere_figure.id,original=sphere_original,choices={}}
   local sphere_ok,sphere_error=pcall(function()
    for sphere=0,df.sphere_type._last_item do
     sphere_figure.info.metaphysical.spheres[0]=sphere
     key('LEAVESCREEN');pixel(610,118)
     assert(selector.choosing_temple_religious_practice and selector.valid_religious_practice_id[sphere_index]==sphere_figure.id,'sphere selector identity changed')
     local first=math.min(sphere_index,math.max(0,#selector.valid_religious_practice-10));selector.scroll_position_deity=first
     local g=df.global.gps;local tx,ty=56,9+3*(sphere_index-first)
     g.mouse_x=tx;g.mouse_y=ty;g.precise_mouse_x=tx*(g.screen_pixel_x//g.dimx)+4;g.precise_mouse_y=ty*(g.screen_pixel_y//g.dimy)+6
     key({});dfhack.gui.getDFViewscreen(true):render(dfhack.getTickCount());assert(selector.current_hover_index==sphere_index,'sphere hover changed')
     local lines={}
     for y=5,40 do
      local text='';for x=89,120 do local tile=dfhack.screen.readTile(x,y);local ch=tile and tile.ch or 32;text=text..(ch>=32 and ch<=255 and string.char(ch)or' ')end
      text=dfhack.df2utf(text):match('^%s*(.-)%s*$');if text~=''then lines[#lines+1]=text end
     end
     assert(#lines==2 and lines[1]:find('worshipper',1,true) and not lines[2]:find('...',1,true),'sphere caption missing or truncated')
     local text,status=dfhack.run_command_silent('df3d','location-religions-read');assert(status==0,'sphere reader failed')
     local bridge=json.decode(text);assert(bridge.valid,'sphere reader unavailable')
     local choice=bridge.choices[sphere_index+1]
     assert(choice.id==sphere_figure.id and #choice.deities==1 and #choice.deities[1].spheres==1 and choice.deities[1].spheres[1]==sphere,'compiled sphere identity differs')
     sphere_result.choices[#sphere_result.choices+1]={id=sphere,key=df.sphere_type[sphere],label=lines[2],screen=lines}
    end
   end)
   sphere_figure.info.metaphysical.spheres[0]=sphere_original
   assert(sphere_figure.info.metaphysical.spheres[0]==sphere_original,'sphere fixture not restored');assert(sphere_ok,sphere_error)
   sphere_result.restoration_verified=true;write(out..'/native-sphere-captions.json',sphere_result)
   key('LEAVESCREEN');record('temple-back')
   pixel(610,154)
   assert(selector.open and selector.choosing_craft_guild,'native Guildhall selector did not open')
   record('new-guildhall')
   for first=8,#selector.valid_craft_guild_type-1,8 do selector.scroll_position_guild=first;record('guild-page-'..first)end
   hover_rows('guild',#selector.valid_craft_guild_type)
   capture_scroll('guild',#selector.valid_craft_guild_type)
   local bridge_text,bridge_status=dfhack.run_command_silent('df3d','location-religions-read')
   assert(bridge_status==0,'location metadata bridge read failed')
   local bridge=json.decode(bridge_text);assert(bridge.valid,'location metadata bridge unavailable')
   local guild_text,guild_status=dfhack.run_command_silent('df3d','location-guilds-read')
   assert(guild_status==0,'guild metadata read failed');local guild_bridge=json.decode(guild_text);assert(guild_bridge.valid,'guild metadata unavailable')
   local compared,guild_compared=0,0
   for _,row in ipairs(metadata)do
    assert(row.hover==row.index,'hover metadata index mismatch')
    if row.kind=='temple' then
     local count=row.screen:match('(%d+) worshipper')
     if row.screen:find('No worshippers',1,true)then count='0'end
     assert(count,'native worshipper count absent')
     assert(bridge.choices[row.index+1].worshippers==tonumber(count),'bridge worshipper count differs')
     compared=compared+1
    else
     local count=row.screen:match('(%d+) worker')
     if row.screen:find('No workers',1,true)then count='0'end
     assert(count,'native worker count absent')
     assert(guild_bridge.choices[row.index+1].profession==selector.valid_craft_guild_type[row.index] and guild_bridge.choices[row.index+1].workers==tonumber(count),'bridge guild metadata differs')
     guild_compared=guild_compared+1
    end
   end
   write(out..'/location-metadata-comparison.json',{worshipper_counts=compared,worker_counts=guild_compared,bridge=bridge,guild_bridge=guild_bridge})
   key('LEAVESCREEN');key('LEAVESCREEN')
   -- Reopen the native selector for each independent world-state control.
   -- Never infer indicator semantics from the similarly named recognition flag.
   local indicator_results={cases={}}
   for _,kind in ipairs({'temple','guild'})do
    local location
    for _,candidate in ipairs(site.buildings)do
     if (kind=='temple' and df.abstract_building_templest:is_instance(candidate))or
        (kind=='guild' and df.abstract_building_guildhallst:is_instance(candidate))then location=candidate;break end
    end
    assert(location,'no existing '..kind..' for indicator controls')
    local contents=location:getContents()
    local practice_kind=kind=='temple' and location.deity_type or -1
    local identity=kind=='temple' and location.deity_data.practice_id or contents.profession
    local function observe_indicator()
     pixel(336,190);pixel(610,kind=='temple' and 118 or 154)
     assert(selector.open and (kind=='temple' and selector.choosing_temple_religious_practice or kind=='guild' and selector.choosing_craft_guild),'indicator selector failed')
     local index,count
     if kind=='temple' then
      count=#selector.valid_religious_practice
      for i,value in ipairs(selector.valid_religious_practice_id)do if value==identity and selector.valid_religious_practice[i]==practice_kind then index=i;break end end
     else
      count=#selector.valid_craft_guild_type
      for i,value in ipairs(selector.valid_craft_guild_type)do if value==identity then index=i;break end end
     end
     assert(index,'indicator choice absent')
     local first=math.min(index,math.max(0,count-10))
     if kind=='temple' then selector.scroll_position_deity=first else selector.scroll_position_guild=first end
     dfhack.gui.getDFViewscreen(true):render(dfhack.getTickCount())
     local text=''
     for x=46,88 do local tile=dfhack.screen.readTile(x,10+3*(index-first));local ch=tile and tile.ch or 32;text=text..(ch>=32 and ch<=255 and string.char(ch)or' ')end
     text=dfhack.df2utf(text):match('^%s*(.-)%s*$')
     assert(text=='' or text==(kind=='temple' and 'Have temple' or 'Have meeting place'),'unexpected native indicator: '..text)
     local bridge_text,status=dfhack.run_command_silent('df3d',kind=='temple' and 'location-religions-read' or 'location-guilds-read')
     assert(status==0,'indicator bridge read failed');local observed=json.decode(bridge_text);assert(observed.valid,'indicator bridge unavailable')
     local match
     for _,row in ipairs(observed.choices)do
      if (kind=='temple' and row.kind==practice_kind+2 and row.id==identity)or(kind=='guild' and row.profession==identity)then match=row;break end
     end
     assert(match,'indicator bridge choice missing')
     local indicator=kind=='temple' and match.has_temple or kind=='guild' and match.has_meeting_place
     assert(indicator==(text~=''),'bridge indicator differs from native')
     indicator_results.bridge_comparisons=(indicator_results.bridge_comparisons or 0)+1
     key('LEAVESCREEN');key('LEAVESCREEN');return text
    end
    local baseline=observe_indicator();assert(baseline~='','baseline indicator missing')
    local function control(label,object,field,value)
     local original=object[field]
     local ok,result=pcall(function()object[field]=value;return observe_indicator()end)
     object[field]=original;assert(object[field]==original,'indicator field not restored')
     assert(ok,result)
     assert(observe_indicator()==baseline,'restored indicator differs')
     indicator_results.cases[#indicator_results.cases+1]={kind=kind,location=location.id,label=label,indicator=result,restored=baseline}
     write(out..'/native-location-indicator-controls.json',indicator_results)
    end
    for _,flag in ipairs({'DOES_NOT_EXIST','WG_RUINED','PWG_RUINED','VISITORS_ALLOWED','NON_CITIZENS_ALLOWED','MEMBERS_ONLY'})do control(flag,location.flags,flag,not location.flags[flag])end
    control('foreign-owner',location,'site_owner_id',-1)
    control('recognized',contents.need_more,'entity_recognized',not contents.need_more.entity_recognized)
    assert(#contents.building_ids>0,'no location zone link')
    control('missing-zone-id',contents.building_ids,0,-1)
    if kind=='temple' then control('different-practice',location.deity_data,'practice_id',-1)
    else control('different-profession',contents,'profession',df.profession.MINER)end
   end
   indicator_results.restoration_verified=true;write(out..'/native-location-indicator-controls.json',indicator_results)
   local guild,guild_site,member,membership
   for _,entity in ipairs(df.global.world.entities.all)do
    if entity.type==df.historical_entity_type.Guild and #entity.guild_professions>0 then
     for _,link in ipairs(entity.site_links)do if link.target==site.id then guild=entity;guild_site=link;break end end
    end
    if guild then break end
   end
   assert(guild,'no local guild for controls')
   for _,unit in ipairs(df.global.world.units.active)do
    if dfhack.units.isActive(unit) and dfhack.units.isFortControlled(unit)then
     local figure=df.historical_figure.find(unit.hist_figure_id)
     if figure then for _,link in ipairs(figure.entity_links)do
      if link:getType()==df.histfig_entity_link_type.MEMBER and link.entity_id==guild.id then member=unit;membership=link;break end
     end end
    end
    if member then break end
   end
   assert(member,'no local guild member for controls')
   local profession=guild.guild_professions[0].profession
   local guild_metadata_comparisons=0
   local function observe_guild(capture_only)
    pixel(336,190);pixel(610,154);assert(selector.choosing_craft_guild,'guild metadata selector failed')
    local index
    for i,value in ipairs(selector.valid_craft_guild_type)do if value==profession then index=i;break end end
    assert(index,'guild metadata choice absent')
    local first=math.min(index,math.max(0,#selector.valid_craft_guild_type-10));selector.scroll_position_guild=first
    local g=df.global.gps;local tx,ty=56,9+3*(index-first)
    g.mouse_x=tx;g.mouse_y=ty;g.precise_mouse_x=tx*(g.screen_pixel_x//g.dimx)+4;g.precise_mouse_y=ty*(g.screen_pixel_y//g.dimy)+6
    key({});dfhack.gui.getDFViewscreen(true):render(dfhack.getTickCount());assert(selector.current_hover_index==index,'guild metadata hover differs')
    local lines={}
    for y=5,40 do
     local text='';for x=89,120 do local tile=dfhack.screen.readTile(x,y);local ch=tile and tile.ch or 32;text=text..(ch>=32 and ch<=255 and string.char(ch)or' ')end
     text=dfhack.df2utf(text):match('^%s*(.-)%s*$');if text~=''then lines[#lines+1]=text end
    end
    if not capture_only then
    local text,status=dfhack.run_command_silent('df3d','location-guilds-read')
    assert(status==0,'guild metadata bridge read failed');local observed=json.decode(text);assert(observed.valid,'guild metadata bridge unavailable')
    local choice
    for _,row in ipairs(observed.choices)do if row.profession==profession then choice=row;break end end
    assert(choice,'guild metadata bridge choice missing')
    if lines[2]=='No established guild'then assert(choice.guild_id==-1 and choice.members==0,'unexpected established guild')
    else
     assert(lines[2]=='Guild:' and choice.guild_id==guild.id,'guild identity differs')
     local count=tonumber(lines[4]:match('^(%d+) member'));assert(count and choice.members==count,'guild member count differs')
    end
    guild_metadata_comparisons=guild_metadata_comparisons+1
    end
    key('LEAVESCREEN');key('LEAVESCREEN');return lines
   end
   local guild_results={guild=guild.id,member=member.id,profession=profession,baseline=observe_guild(),cases={}}
   local function guild_control(label,object,field,value)
    local original=object[field]
    local ok,result=pcall(function()object[field]=value;return observe_guild()end)
    object[field]=original;assert(object[field]==original,'guild control not restored');assert(ok,result)
    assert(json.encode(observe_guild())==json.encode(guild_results.baseline),'guild metadata restoration differs')
    guild_results.cases[#guild_results.cases+1]={label=label,observed=result}
    write(out..'/native-guild-metadata-controls.json',guild_results)
   end
   guild_control('different-site',guild_site,'target',-1)
   guild_control('no-site-flags',guild_site.flags,'whole',0)
   guild_control('residence-only',guild_site.flags,'whole',1)
   guild_control('fortress-only',guild_site.flags,'whole',4)
   guild_control('base-only',guild_site.flags,'whole',32768)
   guild_control('former-site-flags',guild_site.former_flag,'whole',2)
   guild_control('site-type-none',guild_site,'type',df.entity_site_link_type.None)
   guild_control('different-profession',guild.guild_professions[0],'profession',df.profession.MINER)
   guild_control('focus-type-none',guild.guild_professions[0],'type',df.entity_focus_type.NONE)
   guild_control('non-guild-entity',guild,'type',df.historical_entity_type.Religion)
   local site_guild_link
   for _,link in ipairs(site.entity_links)do if link.entity_id==guild.id then site_guild_link=link;break end end
   assert(site_guild_link,'site has no reciprocal guild link')
   guild_results.reciprocal_link_shared=site_guild_link==guild_site
   guild_control('site-guild-id-removed',site_guild_link,'entity_id',-1)
   guild_control('member-link-removed',membership,'entity_id',-1)
   guild_control('member-inactive',member.flags1,'inactive',true)
   guild_control('member-killed',member.flags2,'killed',true)
   guild_control('member-visitor',member.flags2,'visitor',true)
   guild_control('member-foreign-civ',member,'civ_id',-1)
   guild_control('member-other-profession',member,'profession',df.profession.MINER)
   guild_results.restoration_verified=true;guild_results.bridge_comparisons=guild_metadata_comparisons;write(out..'/native-guild-metadata-controls.json',guild_results)
   local second_guild,second_link,first_index,second_index
   for _,entity in ipairs(df.global.world.entities.all)do
    if entity.type==df.historical_entity_type.Guild and entity.id~=guild.id and #entity.guild_professions==1 then second_guild=entity;break end
   end
   for i,link in ipairs(site.entity_links)do
    if link==site_guild_link then first_index=i
    elseif not second_link then second_link=link;second_index=i end
   end
   assert(second_guild and second_link and first_index,'multiple guild fixture unavailable')
   local old_id,old_flags=second_link.entity_id,second_link.flags.whole
   local old_prof,old_focus=second_guild.guild_professions[0].profession,second_guild.guild_professions[0].type
   local first_flags=site_guild_link.flags.whole
   local multiple={first_index=first_index,second_index=second_index,first_id=guild.id,second_id=second_guild.id,
    first_name=dfhack.df2utf(dfhack.translation.translateName(guild.name,true)),second_name=dfhack.df2utf(dfhack.translation.translateName(second_guild.name,true)),cases={}}
   local function restore_multiple()
    site_guild_link.entity_id=guild.id;site_guild_link.flags.whole=first_flags
    second_link.entity_id=old_id;second_link.flags.whole=old_flags
    second_guild.guild_professions[0].profession=old_prof;second_guild.guild_professions[0].type=old_focus
   end
   local function multi_case(label)
    local observed=observe_guild(true)
    local expected=site_guild_link.flags.capital and site_guild_link.entity_id or second_link.entity_id
    if second_link.flags.capital and (not site_guild_link.flags.capital or second_index<first_index)then expected=second_link.entity_id end
    local expected_name=expected==guild.id and multiple.first_name or multiple.second_name
    local visible=observed[3];assert(visible,'multiple guild name absent')
    if visible:sub(-3)=='...'then assert(expected_name:sub(1,#visible-3)==visible:sub(1,-4),'native guild order differs')else assert(visible==expected_name,'native guild identity differs')end
    local text,status=dfhack.run_command_silent('df3d','location-guilds-read');assert(status==0,'multiple guild reader failed')
    local bridge=json.decode(text);assert(bridge.valid,'multiple guild reader unavailable')
    local choice;for _,row in ipairs(bridge.choices)do if row.profession==profession then choice=row;break end end
    local count=observed[4]=='No members' and 0 or tonumber(observed[4]:match('^(%d+) member'))
    assert(choice and choice.guild_id==expected and choice.guild_name==expected_name and count and choice.members==count,'compiled multiple guild metadata differs')
    multiple.cases[#multiple.cases+1]={label=label,observed=observed,first_id=site_guild_link.entity_id,second_id=second_link.entity_id,
     first_flags=site_guild_link.flags.whole,second_flags=second_link.flags.whole,bridge=choice}
    write(out..'/native-multiple-guilds.json',multiple)
   end
   local success,why=pcall(function()
    second_guild.guild_professions[0].profession=profession;second_guild.guild_professions[0].type=df.entity_focus_type.PROMOTE_PROFESSION_UNIT
    second_link.entity_id=second_guild.id;second_link.flags.whole=2
    multi_case('two-guilds')
    site_guild_link.entity_id=second_guild.id;second_link.entity_id=guild.id;multi_case('swapped-identities')
    site_guild_link.entity_id=guild.id;second_link.entity_id=second_guild.id
    site_guild_link.flags.whole=0;multi_case('only-second');site_guild_link.flags.whole=first_flags
    second_link.flags.whole=0;multi_case('only-first')
   end)
   restore_multiple();assert(success,why)
   assert(site_guild_link.entity_id==guild.id and site_guild_link.flags.whole==first_flags and second_link.entity_id==old_id and second_link.flags.whole==old_flags and second_guild.guild_professions[0].profession==old_prof and second_guild.guild_professions[0].type==old_focus,'multiple guild fixture not restored')
   assert(json.encode(observe_guild())==json.encode(guild_results.baseline),'multiple guild baseline not restored')
   multiple.restoration_verified=true;write(out..'/native-multiple-guilds.json',multiple)
   key('LEAVESCREEN');restore_zones()
  elseif request.op=='paint_counts_repaint_elevation' then
   for _,existing in ipairs({false,true})do for _,tool in ipairs({'rectangle','brush'})do
    local label=(existing and 'existing-' or 'new-')..tool
    df.global.game.main_interface.bottom_mode_selected=-1;key('D_CIVZONE')
    dfhack.gui.revealInDwarfmodeMap({x=171,y=58,z=164},true)
    pixel(55,320);pixel(310,202);mapclick(170,57,164);mapclick(172,59,164)
    record(label..'-created')
    if existing then pixel(310,118);pixel(272,118)end
    pixel(120,154)
    if tool=='brush' then pixel(88,154)else mapclick(170,57,164)end
    record(label..'-before-elevation')
    key('CURSOR_UP_Z');record(label..'-away')
    if tool=='brush' then feed(171,58,'press',165);feed(171,58,'release',165)else mapclick(171,58,165)end
    record(label..'-away-click')
    key('CURSOR_DOWN_Z');record(label..'-return')
    if tool=='brush' then feed(171,58,'press');feed(171,58,'release')else mapclick(171,58,164)end
    record(label..'-return-click')
    key('LEAVESCREEN');restore_zones()
   end end
  elseif request.op=='paint_counts_elevation' then
   for _,tool in ipairs({'rectangle','brush','brush-multi'})do
    df.global.game.main_interface.bottom_mode_selected=-1;key('D_CIVZONE')
    dfhack.gui.revealInDwarfmodeMap({x=171,y=58,z=164},true)
    pixel(55,320);pixel(310,202);mapclick(170,57,164)
    if tool~='rectangle' then pixel(88,154)end
    if tool=='brush-multi' then pixel(310,166)end
    record(tool..'-before-elevation')
    key('CURSOR_UP_Z');record(tool..'-after-elevation')
    if tool=='brush-multi' then pixel(310,202)end
    if tool~='rectangle' then pixel(56,154)end
    mapclick(172,59,165);record(tool..'-completed')
    pixel(310,82);key('LEAVESCREEN');restore_zones()
   end
  else
   local function open_paint()
    df.global.game.main_interface.bottom_mode_selected=-1;key('D_CIVZONE')
    dfhack.gui.revealInDwarfmodeMap({x=171,y=58,z=164},true)
    pixel(55,320);pixel(310,202)
   end
   open_paint();pixel(88,154);record('brush-initial')
   feed(170,57,'press');record('brush-press')
   feed(172,59,'hold');record('brush-diagonal-hold')
   feed(171,58,'release');record('brush-release')
   feed(171,58,'move');record('brush-unheld-move')
   feed(172,57,'press');record('brush-second-press')
   feed(170,59,'hold');record('brush-cross-hold')
   feed(170,59,'release');record('brush-cross-release')
   pixel(120,154)
   feed(170,57,'press');record('brush-erase-press')
   feed(172,59,'hold');record('brush-erase-hold')
   feed(172,59,'release');record('brush-erase-release')
   pixel(310,82);key('LEAVESCREEN');restore_zones()
   open_paint();record('drag-initial')
   feed(170,57,'press');record('rectangle-drag-press')
   feed(172,59,'hold');record('rectangle-drag-hold')
   feed(172,59,'release');record('rectangle-drag-release')
   mapclick(172,59,164);record('rectangle-drag-second-click')
   pixel(310,82);key('LEAVESCREEN');restore_zones()
   open_paint();mapclick(170,57,164);record('tool-switch-pending')
   pixel(88,154);record('tool-switch-brush')
   pixel(56,154);record('tool-switch-rectangle')
   mapclick(172,59,164);record('tool-switch-next-click')
   pixel(310,82);key('LEAVESCREEN');restore_zones()
   open_paint();mapclick(170,57,164);pixel(88,154)
   feed(172,57,'press');feed(172,57,'release');record('tool-switch-brush-painted')
   pixel(56,154);mapclick(172,59,164);record('tool-switch-after-brush-paint')
   pixel(310,82);key('LEAVESCREEN');restore_zones()
   open_paint();mapclick(170,57,164);pixel(88,154);record('brush-multi-anchor-before')
   pixel(310,166);record('brush-multi-anchor-multi')
   pixel(310,202);record('brush-multi-anchor-return')
   pixel(56,154);mapclick(172,59,164);record('brush-multi-anchor-completed')
   pixel(310,82);key('LEAVESCREEN');restore_zones()
  end
  write(capture_path,rows)
 elseif request.op=='paint_counts_location_creation' then
  assert(loadfile(out..'/../../tools/smoke/areas-location-creation-reference.lua'))(out,_G.df3d_paint_counts_fixture)
 elseif request.op=='paint_counts_location_compare' then
  local state=assert(_G.df3d_paint_counts_fixture)
  assert(state.bridge_ids and state.bridge_ids[request.id],'location comparison requires tracked probe zone')
  local zone=assert(df.building.find(request.id));local site=assert(dfhack.world.getCurrentSite())
  local location
  for _,v in ipairs(site.buildings)do if v.id==zone.location_id then location=v;break end end
  assert(location and zone.site_id==site.id,'created location assignment missing')
  state.location_ids=state.location_ids or {};state.location_ids[location.id]=zone.id
  local reference
  for _,row in ipairs(read(out..'/native-location-creation.json'))do if row.scenario==request.scenario then reference=row.location;break end end
  assert(reference,'native creation reference missing')
  local c=assert(location:getContents());local n=assert(location:getName())
  local actual={kind=location:getType(),flags={},owner=location.site_owner_id,site=location.site_id,
   need_more=c.need_more.whole,profession=c.profession,name_type=n.type}
  for flag in pairs(reference.flags)do actual.flags[flag]=location.flags[flag]end
  for field in pairs(reference)do
   if field:find('desired_',1,true)==1 or field=='location_tier' or field=='location_value' then actual[field]=c[field]end
  end
  if reference.practice_kind~=nil then actual.practice_kind=location.deity_type;actual.practice_id=location.deity_data.practice_id end
  local differences={}
  for field,value in pairs(reference)do
   if field~='name' and field~='buildings' then
    if type(value)=='table' then
     for k,v in pairs(value)do if actual[field][k]~=v then differences[#differences+1]={field=field..'.'..k,expected=v,actual=actual[field][k]}end end
    elseif actual[field]~=value then differences[#differences+1]={field=field,expected=value,actual=actual[field]}end
   end
  end
  assert(n.has_name and #c.building_ids==1 and c.building_ids[0]==zone.id,'native name or membership missing')
  state.location_comparisons=state.location_comparisons or {}
  local refresh_probe={initial=c.location_value,personal_value=zone:getPersonalValue(nil),arch_value=zone:getArchValue()}
  zone:uncategorize();zone:categorize(true)
  refresh_probe.recategorized=c.location_value
  dfhack.buildings.notifyCivzoneModified(zone)
  refresh_probe.associations_updated=c.location_value
  dfhack.gui.getDFViewscreen(true):render(dfhack.getTickCount())
  refresh_probe.rendered=c.location_value
  table.insert(state.location_comparisons,{scenario=request.scenario,actual=actual,differences=differences,refresh_probe=refresh_probe})
  write(out..'/location-creation-comparison.json',state.location_comparisons)
  for _,difference in ipairs(differences)do error('native creation default differs: '..difference.field)end
 elseif request.op=='paint_counts_location_removed' or request.op=='paint_counts_location_reassigned' then
  local assigning=request.op=='paint_counts_location_reassigned'
  local state=assert(_G.df3d_paint_counts_fixture);local site=assert(dfhack.world.getCurrentSite())
  local zone=assert(df.building.find(request.id))
  assert(assigning or zone.location_id==-1,'probe still assigned')
  local location
  for _,v in ipairs(site.buildings)do if state.location_ids[v.id]==zone.id then location=v;break end end
  assert(location,'tracked location missing');local c=assert(location:getContents())
  assert(#c.building_ids==(assigning and 1 or 0),'location membership count differs')
  if assigning then assert(zone.location_id==location.id and c.building_ids[0]==zone.id,'reassigned membership differs')end
  local expected
  for _,r in ipairs(read(out..'/native-location-creation.json'))do if r.scenario==request.scenario then expected=assigning and r.reassignment or r.removal;break end end
  assert(expected and zone.site_id==expected.site,'removed site identity differs')
  state.removal_comparisons=state.removal_comparisons or {}
  table.insert(state.removal_comparisons,{scenario=request.scenario,phase=assigning and 'reassignment' or 'removal',expected=expected.value,actual=c.location_value})
  write(out..'/location-removal-comparison.json',state.removal_comparisons)
  assert(c.location_value==expected.value,'removed location value differs')
 elseif request.op=='paint_counts_location_replaced' or request.op=='paint_counts_location_transferred' then
  local transfer=request.op=='paint_counts_location_transferred'
  local state=assert(_G.df3d_paint_counts_fixture);local site=assert(dfhack.world.getCurrentSite())
  local zone=assert(df.building.find(request.id));local previous,replacement
  assert(state.location_ids[request.previous]==zone.id,'untracked former location')
  for _,v in ipairs(site.buildings)do
   if v.id==request.previous then previous=v end
   if v.id==zone.location_id then replacement=v end
  end
  assert(previous and replacement and previous~=replacement,'replacement identity missing')
  state.location_ids[replacement.id]=zone.id
  local pc,rc=previous:getContents(),replacement:getContents()
  assert(#pc.building_ids==0 and #rc.building_ids==1 and rc.building_ids[0]==zone.id,'replacement memberships differ')
  local expected
  for _,r in ipairs(read(out..'/native-location-creation.json'))do if r.scenario==request.scenario then expected=transfer and r.transfer or r.replacement;break end end
  assert(expected and replacement:getType()==expected.kind,'replacement type differs')
  state.replacement_comparisons=state.replacement_comparisons or {}
  table.insert(state.replacement_comparisons,{scenario=request.scenario,phase=transfer and 'transfer' or 'replacement',expected=expected,previous_value=pc.location_value,new_value=rc.location_value})
  write(out..'/location-replacement-comparison.json',state.replacement_comparisons)
  assert(pc.location_value==expected.previous_value and rc.location_value==expected.new_value,'replacement location values differ')
 elseif request.op=='paint_counts_location_multi' then
  local state=assert(_G.df3d_paint_counts_fixture);local site=assert(dfhack.world.getCurrentSite())
  assert(state.location_ids[request.location]==request.first and state.bridge_ids[request.second],'untracked multi-zone probe')
  local location
  for _,v in ipairs(site.buildings)do if v.id==request.location then location=v;break end end
  local c=assert(location and location:getContents());local second=assert(df.building.find(request.second))
  local ids={};for _,id in ipairs(c.building_ids)do ids[#ids+1]=id end
  table.sort(ids)
  assert(ids[1]==request.first and #ids==(request.remaining and 1 or 2),'remaining membership differs')
  if request.remaining then assert(second.location_id==-1,'second zone remains assigned')
  else assert(ids[2]==request.second and second.location_id==location.id,'second membership differs')end
  local expected
  for _,r in ipairs(read(out..'/native-location-creation.json'))do if r.scenario==request.scenario then expected=r.multi_zone[tostring(request.z)][request.remaining and 'remaining' or 'both'];break end end
  state.multi_location_comparisons=state.multi_location_comparisons or {}
  table.insert(state.multi_location_comparisons,{scenario=request.scenario,z=request.z,remaining=request.remaining or false,actual=c.location_value,expected=expected})
  write(out..'/location-multi-zone-comparison.json',state.multi_location_comparisons)
  assert(c.location_value==expected,'multi-zone location value differs')
 elseif request.op=='paint_counts_absent' then
  local state=assert(_G.df3d_paint_counts_fixture)
  local known=state.created_ids[request.id] or (request.created_reply and request.id>=0 and not state.baseline_ids[request.id])
  assert(known and not df.building.find(request.id),'probe zone was not deleted')
 elseif request.op=='paint_counts_track' then
  local state=assert(_G.df3d_paint_counts_fixture)
  local b=assert(df.building.find(request.id),'bridge-created zone missing')
  assert(df.building_civzonest:is_instance(b) and not state.baseline_ids[b.id],'must track only probe-created zone')
  state.created_ids[b.id]=true
  state.bridge_ids=state.bridge_ids or {};state.bridge_ids[b.id]=true
  if request.hidden~=nil then
   local block=assert(dfhack.maps.getTileBlock(170,57,164));block.designation[170%16][57%16].hidden=request.hidden
  end
  local extents={};local count=0
  for y=b.y1,b.y2 do for x=b.x1,b.x2 do local v=b.room.extents[(y-b.room.y)*b.room.width+x-b.room.x];extents[#extents+1]=v;if v~=0 then count=count+1 end end end
  assert(count==request.tiles,'native bridge footprint count differs')
  assert(b.x1==170 and b.y1==57 and b.x2==169+(request.width or 3) and b.y2==56+(request.height or 3) and b.z==(request.z or 164),'native bridge footprint bounds differ')
  if request.extents then assert(json.encode(extents)==json.encode(request.extents),'native bridge mask differs')end
  write(out..'/paint-zone-'..index..'.json',{id=b.id,tiles=count,extents=extents})
 elseif request.op=='paint_counts_wall' or request.op=='paint_counts_floor' then
  assert(_G.df3d_paint_counts_fixture,'fixture absent')
  local b=assert(dfhack.maps.getTileBlock(170,57,164))
  b.tiletype[170%16][57%16]=request.op=='paint_counts_wall' and df.tiletype.StoneWall or df.tiletype.StoneFloor1
 elseif request.op=='paint_counts_cleanup' then
  if _G.df3d_location_details_probe then
   local source=debug.getinfo(1,'S').source:sub(2):match('^(.*[/\\])')
   assert(loadfile(source..'location-details-reference.lua'))(out,'restore')
  end
  local state=_G.df3d_paint_counts_fixture
  if state then
   for id in pairs(state.created_ids)do
    local b=df.building.find(id)
    if b then assert(not state.baseline_ids[id]);assert(dfhack.buildings.deconstruct(b),'capture zone restoration failed')end
   end
   if state.bridge_ids then restore_collision_flags(state)end
   if state.location_ids then
    local site=assert(dfhack.world.getCurrentSite())
    for i=#site.buildings-1,0,-1 do
     local v=site.buildings[i];local id=state.location_ids[v.id]
     if id then
      assert(not df.building.find(id),'location cleanup requires deleted probe zone')
      local c=assert(v:getContents())
      for j=#c.building_ids-1,0,-1 do assert(c.building_ids[j]==id,'foreign zone in probe location');c.building_ids:erase(j)end
      site.buildings:erase(i);v:delete()
     end
    end
   end
   for _,s in ipairs(state.tiles)do s.b.tiletype[s.x][s.y]=s.t;s.b.designation[s.x][s.y].whole=s.d;s.b.occupancy[s.x][s.y].whole=s.o end
   for _,s in ipairs(state.tiles)do assert(s.b.tiletype[s.x][s.y]==s.t and s.b.designation[s.x][s.y].whole==s.d and s.b.occupancy[s.x][s.y].whole==s.o,'terrain restoration mismatch')end
   assert(zones()==state.zones,'count reads changed native zones')
   _G.df3d_paint_counts_fixture=nil
  end
 else error('unknown paint count fixture operation')end
 if _G.df3d_paint_counts_fixture and request.op~='paint_counts_track' then assert(baseline_unchanged(_G.df3d_paint_counts_fixture),'count reads changed native zones')end
end)
if index=='cleanup' then assert(ok,err);print('SEMANTIC_PASS paint counts restored')
else write(out..'/response-'..index..'.json',{status=ok and 'passed' or 'failed',reason=ok and request.op or tostring(err)});print('SEMANTIC_PASS '..request.op..' '..tostring(ok));assert(ok,err)end
