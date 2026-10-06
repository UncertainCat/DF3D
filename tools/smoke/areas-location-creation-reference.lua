-- Capture-only native selector effects on the protected paused clone.
-- No runtime reader may use these UI fields.
local out,state=...
assert(state and df.global.pause_state and df.global.world.frame_counter==0)
local json=require('json')
local site=assert(dfhack.world.getCurrentSite())
local baseline={};for _,v in ipairs(site.buildings)do baseline[v.id]=true end
local results={}
local function save()
 local f=assert(io.open(out..'/native-location-creation.json','w'))
 f:write(json.encode(results));f:close()
end
local function key(k)require('gui').simulateInput(dfhack.gui.getDFViewscreen(true),k)end
local function pixel(x,y)
 local g=df.global.gps;g.precise_mouse_x=x;g.precise_mouse_y=y
 g.mouse_x=x//(g.screen_pixel_x//g.dimx);g.mouse_y=y//(g.screen_pixel_y//g.dimy);key('_MOUSE_L')
end
local function mapclick(x,y,z)
 local g=df.global.gps
 for ty=0,g.dimy-1 do for tx=0,g.dimx-1 do
  g.mouse_x=tx;g.mouse_y=ty;g.precise_mouse_x=tx*(g.screen_pixel_x//g.dimx)+4;g.precise_mouse_y=ty*(g.screen_pixel_y//g.dimy)+6
  local p=dfhack.gui.getMousePos(true)
  if p and p.x==x and p.y==y and p.z==(z or 164) then key('_MOUSE_L');return end
 end end
 error('creation reference tile unavailable')
end
for _,scenario in ipairs({'temple-back','guild-back','none','deity','religion','guild','tavern','library','hospital'})do
 df.global.game.main_interface.bottom_mode_selected=-1;key('D_CIVZONE')
 dfhack.gui.revealInDwarfmodeMap({x=171,y=58,z=164},true)
 pixel(55,320);pixel(310,202);mapclick(170,57);mapclick(172,59)
 local zone=assert(df.global.game.main_interface.civzone.cur_bld)
 assert(not state.baseline_ids[zone.id]);state.created_ids[zone.id]=true
 pixel(310,118);pixel(336,190)
 local guild=scenario=='guild' or scenario=='guild-back'
 local direct=({tavern=1,library=3,hospital=5})[scenario]
 local before_count,before_next=#site.buildings,site.next_building_id
 if direct then pixel(440,118+36*((direct-1)//2))else pixel(610,guild and 154 or 118)end
 local selector=df.global.game.main_interface.location_selector
 if not direct then assert(selector.open and (guild and selector.choosing_craft_guild or not guild and selector.choosing_temple_religious_practice),'subselector did not open')end
 local row={scenario=scenario,zone_id=zone.id,kind=direct or (guild and 4 or 2)}
 if scenario:find('back',1,true)then
  key('LEAVESCREEN')
  assert(selector.open and not selector.choosing_craft_guild and not selector.choosing_temple_religious_practice,'Back did not return to locations')
  assert(zone.location_id==-1 and #site.buildings==before_count and site.next_building_id==before_next,'Back created a location')
  row.no_mutation=true;key('LEAVESCREEN')
 else
  if not direct then
  local index
  if guild then index=0;row.profession=selector.valid_craft_guild_type[index]
  else
   local wanted=scenario=='none' and -1 or scenario=='deity' and 0 or 1
   for i,kind in ipairs(selector.valid_religious_practice)do if kind==wanted then index=i;row.practice_kind=kind;row.practice_id=selector.valid_religious_practice_id[i];break end end
  end
  assert(index,'native choice unavailable')
  local first=math.max(0,index-9)
  if guild then selector.scroll_position_guild=first else selector.scroll_position_deity=first end
  dfhack.gui.getDFViewscreen(true):render(dfhack.getTickCount())
  pixel(450,108+36*(index-first))
  end
  assert(zone.location_id>=0 and #site.buildings==before_count+1,'choice did not create one location')
  local location
  for _,v in ipairs(site.buildings)do if v.id==zone.location_id then location=v;break end end
  assert(location and not baseline[location.id],'creation reused existing location')
  local c=assert(location:getContents());local n=assert(location:getName())
  row.location={kind=location:getType(),flags={},owner=location.site_owner_id,site=location.site_id,
   need_more=c.need_more.whole,profession=c.profession,name_type=n.type,name=dfhack.df2utf(dfhack.translation.translateName(n,true)),buildings={}}
  for _,flag in ipairs({'VISITORS_ALLOWED','NON_CITIZENS_ALLOWED','MEMBERS_ONLY','DOES_NOT_EXIST','WG_RUINED','PWG_RUINED'})do row.location.flags[flag]=location.flags[flag]end
  for _,id in ipairs(c.building_ids)do row.location.buildings[#row.location.buildings+1]=id end
  for _,field in ipairs({'desired_goblets','desired_instruments','desired_paper','desired_splints','desired_thread','desired_cloth','desired_crutches','desired_powder','desired_buckets','desired_soap','desired_copies','location_tier','location_value'})do row.location[field]=c[field]end
  if row.kind==2 then row.location.practice_kind=location.deity_type;row.location.practice_id=location.deity_data.practice_id end
  row.focus=dfhack.gui.getCurFocus(true)
  row.selector_open=selector.open
  row.personal_value=zone:getPersonalValue(nil)
  row.arch_value=zone:getArchValue()
  -- Diagnostic only: distinguish a cached value from render-time computation.
  -- Restore the exact native value before any further input or cleanup.
  local original_value=c.location_value
  c.location_value=-123
  dfhack.gui.getDFViewscreen(true):render(dfhack.getTickCount())
  row.value_after_render=c.location_value
  c.location_value=original_value
  pixel(304,190);pixel(450,118)
  row.removal_probe={location_id=zone.location_id,members=#c.building_ids,selector_open=selector.open,focus=dfhack.gui.getCurFocus(true)}
  if zone.location_id~=-1 or #c.building_ids~=0 then results[#results+1]=row;save()end
  assert(zone.location_id==-1,'native location removal did not clear identity')
  assert(#c.building_ids==0,'native location removal retained membership')
  row.removal={value=c.location_value,site=zone.site_id,selector_open=selector.open}
  pixel(336,190)
  local target_index
  for i,v in ipairs(selector.valid_ab)do if v.id==location.id then target_index=i;break end end
  assert(target_index,'native existing location absent')
  local first=math.max(0,target_index-5)
  selector.scroll_position_location=first
  dfhack.gui.getDFViewscreen(true):render(dfhack.getTickCount())
  pixel(450,234+36*(target_index-first))
  assert(zone.location_id==location.id and #c.building_ids==1 and c.building_ids[0]==zone.id,'native reassignment failed')
  row.reassignment={value=c.location_value,site=zone.site_id,selector_open=selector.open}
  pixel(304,190);pixel(440,154) -- Assigned chooser: New inn/tavern below Remove.
  local replacement
  for _,v in ipairs(site.buildings)do if v.id==zone.location_id then replacement=v;break end end
  assert(replacement and replacement.id~=location.id and not baseline[replacement.id],'native replacement did not create a new location')
  local rc=assert(replacement:getContents())
  assert(#c.building_ids==0 and #rc.building_ids==1 and rc.building_ids[0]==zone.id,'native replacement memberships differ')
  row.replacement={previous_value=c.location_value,new_value=rc.location_value,kind=replacement:getType()}
  pixel(304,190)
  target_index=nil
  for i,v in ipairs(selector.valid_ab)do if v.id==location.id then target_index=i;break end end
  assert(target_index,'native transfer destination absent')
  first=math.max(0,target_index-4);selector.scroll_position_location=first
  dfhack.gui.getDFViewscreen(true):render(dfhack.getTickCount())
  pixel(450,270+36*(target_index-first))
  assert(zone.location_id==location.id and #rc.building_ids==0 and #c.building_ids==1 and c.building_ids[0]==zone.id,'native transfer memberships differ')
  row.transfer={previous_value=rc.location_value,new_value=c.location_value,kind=location:getType()}
  key('LEAVESCREEN')
  row.multi_zone={}
  for _,second_z in ipairs({165,164})do
  df.global.game.main_interface.bottom_mode_selected=-1;key('D_CIVZONE')
  dfhack.gui.revealInDwarfmodeMap({x=170,y=57,z=second_z},true)
  pixel(55,320);pixel(310,202);mapclick(170,57,second_z);mapclick(170,57,second_z)
  local second=assert(df.global.game.main_interface.civzone.cur_bld)
  assert(second.id~=zone.id and not state.baseline_ids[second.id]);state.created_ids[second.id]=true
  pixel(310,118);pixel(336,190)
  target_index=nil
  for i,v in ipairs(selector.valid_ab)do if v.id==location.id then target_index=i;break end end
  assert(target_index,'multi-zone destination absent')
  first=math.max(0,target_index-5);selector.scroll_position_location=first
  dfhack.gui.getDFViewscreen(true):render(dfhack.getTickCount())
  pixel(450,234+36*(target_index-first))
  assert(second.location_id==location.id and #c.building_ids==2,'second native zone not assigned')
  row.multi_zone[tostring(second_z)]={both=c.location_value}
  pixel(304,190);pixel(450,118)
  assert(second.location_id==-1 and #c.building_ids==1 and c.building_ids[0]==zone.id,'native removal lost remaining zone')
  row.multi_zone[tostring(second_z)].remaining=c.location_value
  key('LEAVESCREEN');assert(dfhack.buildings.deconstruct(second),'second native zone cleanup failed')
  end
 end
 results[#results+1]=row;save()
 key('LEAVESCREEN')
 local removed_zone_id=zone.id
 assert(dfhack.buildings.deconstruct(zone),'probe zone cleanup failed')
 -- Simulation never ran. Remove only this probe's unreferenced location object;
 -- monotonically allocated IDs remain consumed, like other native references.
 for i=#site.buildings-1,0,-1 do
  local v=site.buildings[i]
  if not baseline[v.id]then
   local c=assert(v:getContents())
   for j=#c.building_ids-1,0,-1 do
    assert(c.building_ids[j]==removed_zone_id and not df.building.find(removed_zone_id),'probe location has a foreign or live zone reference')
    c.building_ids:erase(j)
   end
   site.buildings:erase(i);v:delete()
  end
 end
 assert(#site.buildings==before_count,'probe location cleanup changed baseline registry')
end
