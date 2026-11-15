-- Diagnostic native workshop reference in the protected owned paused clone.
local out,view,records,original,capture,select_map=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local sheet=df.global.game.main_interface.view_sheets
local frame=df.global.world.frame_counter
local building
for _,b in ipairs(df.global.world.buildings.other.WORKSHOP_ANY)do
 if df.building_workshopst:is_instance(b) and b.type==df.workshop_type.Carpenters and b:getBuildStage()==b:getMaxBuildStage()then building=b;break end
end
assert(building,'Native workshop reference needs a completed carpenter workshop')
if os.getenv('DF3D_WORKSHOP_SELECTOR_LAYOUT')=='1'then
 for _,candidate in ipairs(df.global.world.buildings.other.WORKSHOP_ANY)do
  if df.building_workshopst:is_instance(candidate) and candidate.type==df.workshop_type.Still then building=candidate;break end
 end
end
if os.getenv('DF3D_FURNACE_HEADER')=='1'then
 building=nil
 for _,candidate in ipairs(df.global.world.buildings.other.FURNACE_ANY)do
  if df.building_furnacest:is_instance(candidate) and candidate.type==df.furnace_type.Smelter and candidate:getBuildStage()==candidate:getMaxBuildStage() and #candidate.jobs==0 then building=candidate;break end
 end
 assert(building,'Furnace header reference needs an idle completed smelter')
end
local jobs={};for _,job in ipairs(building.jobs)do jobs[#jobs+1]=job.id end
local result={building_id=building.id,building_type=building:getType(),type=(df.building_furnacest:is_instance(building) and df.furnace_type or df.workshop_type)[building.type],position={building.centerx,building.centery,building.z},jobs=jobs,pages={}}
-- Diagnostic oracle only; runtime worker reads never traverse widgets.
local function worker_list(container,depth)
 assert(depth<8,'Native worker widget tree too deep')
 if df.widget_unit_list:is_instance(container)then return df.reinterpret_cast(df.widget_unit_list,container)end
 if not df.widget_container:is_instance(container)then return end
 container=df.reinterpret_cast(df.widget_container,container)
 local _,address=df.sizeof(container.children)
 local first=df.reinterpret_cast('uint64_t',address).value
 local finish=df.reinterpret_cast('uint64_t',address+8).value
 assert(finish>=first and (finish-first)%16==0 and finish-first<=65536,'Invalid native worker widget children')
 for at=first,finish-1,16 do
  local ptr=df.reinterpret_cast('uint64_t',at).value
  if ptr~=0 then local found=worker_list(df.reinterpret_cast(df.widget,ptr),depth+1);if found then return found end end
 end
end
local function worker_names(widget,ids,depth,visible)
 assert(depth<10);visible=visible and (widget.flag.whole&1)==1
 if df.widget_unit_name:is_instance(widget) and visible then
  ids[#ids+1]=df.reinterpret_cast(df.widget_unit_name,widget).u.id
 end
 if not df.widget_container:is_instance(widget)then return end
 local _,address=df.sizeof(df.reinterpret_cast(df.widget_container,widget).children)
 local first=df.reinterpret_cast('uint64_t',address).value;local finish=df.reinterpret_cast('uint64_t',address+8).value
 assert(finish>=first and (finish-first)%16==0 and finish-first<=65536,'Invalid native worker row children')
 for at=first,finish-1,16 do local ptr=df.reinterpret_cast('uint64_t',at).value;if ptr~=0 then worker_names(df.reinterpret_cast(df.widget,ptr),ids,depth+1,visible)end end
end
local function worker_geometry(widget,rows,depth)
 assert(depth<12)
 if (widget.flag.whole&1)==0 then return end
 local r=widget.rect
 if r.y1>=0 and r.y1<64 and r.y2>=r.y1 then
  rows[#rows+1]={name=widget.name,type=tostring(widget._type),rect={r.x1,r.y1,r.x2,r.y2},depth=depth,
   min_w=widget.min_w,min_h=widget.min_h,anchors={widget.anchor_left,widget.anchor_top,widget.anchor_right,widget.anchor_bottom},
   offsets={widget.offset_left,widget.offset_top,widget.offset_right,widget.offset_bottom}}
  if df.widget_columns_container:is_instance(widget)then rows[#rows].padding=df.reinterpret_cast(df.widget_columns_container,widget).padding end
 end
 if not df.widget_container:is_instance(widget)then return end
 local _,address=df.sizeof(df.reinterpret_cast(df.widget_container,widget).children)
 local first=df.reinterpret_cast('uint64_t',address).value;local finish=df.reinterpret_cast('uint64_t',address+8).value
 assert(finish>=first and (finish-first)%16==0 and finish-first<=65536)
 for at=first,finish-1,16 do local ptr=df.reinterpret_cast('uint64_t',at).value;if ptr~=0 then worker_geometry(df.reinterpret_cast(df.widget,ptr),rows,depth+1)end end
end
local function lines()
 local rows={};for y=0,g.dimy-1 do
  local text={};for x=0,g.dimx-1 do local ch=dfhack.screen.readTile(x,y).ch;text[#text+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
  rows[#rows+1]={y=y,text=dfhack.df2utf(table.concat(text)):gsub('%s+$','')}
 end;return rows
end
local function shot(name)
 local rows=lines();result.pages[#result.pages+1]={name=name,lines=rows,active_id=sheet.active_id,active_sub_tab=sheet.active_sub_tab}
 capture('workshop-'..name)
 local file=assert(io.open(out..'/workshop-native.json','w'));file:write(json.encode(result));file:close()
end
local function click_label(label)
 if os.getenv('DF3D_WORKSHOP_DYER_PAGES')=='1' and #label>40 then label=label:sub(1,40)end
 for _,row in ipairs(lines())do local x=row.text:lower():find(label:lower(),1,true);if x then
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
  g.precise_mouse_x=(x-1)*8+4;g.precise_mouse_y=row.y*12+10;g.mouse_x=x-1;g.mouse_y=row.y
  df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
  df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
  return true
 end end;return false
end
local function resize_worker(size)
 local script=require('gui.script')
 local f=assert(io.open(out..'/owner-input-request.tmp','w'));f:write('name-resize-'..size);f:close()
 assert(os.rename(out..'/owner-input-request.tmp',out..'/owner-input-request'))
 local limit=dfhack.getTickCount()+30000
 while true do local ack=io.open(out..'/owner-input-ack');if ack then ack:close();break end
  assert(dfhack.getTickCount()<limit,'worker resize timeout');script.sleep(1,'frames')end
 assert(os.remove(out..'/owner-input-ack'));script.sleep(2,'frames');view:render(dfhack.getTickCount())
end
local function read_worker_reference(target)
 local native_ids={};local nonunit={}
 local list=assert(worker_list(df.global.game.main_interface.unit_selector,0))
 for _,entry in ipairs(list.entry_list)do
  if entry.t==0 and entry.u then -- Raw source list also contains filtered-out units.
  else nonunit[#nonunit+1]={kind=entry.t,null=not entry.u}end
 end
 worker_names(list,native_ids,0,true)
 local geometry={};worker_geometry(list,geometry,0)
 local worker_text,worker_code=dfhack.run_command_silent('df3d','workshop-workers-probe',tostring(target.id))
 assert(worker_code==0,worker_text)
 local semantic=json.decode(worker_text);local actual_ids=semantic.ids;local sorted_ids={table.unpack(native_ids)}
 local native_skills={}
 for skill=0,df.job_skill._last_item do if list.skills[skill]~=0 then native_skills[#native_skills+1]={skill=skill,weight=list.skills[skill]}end end
 assert(json.encode(native_skills)==json.encode(semantic.skills),'Workshop native skill weights differ')
 table.sort(sorted_ids);table.sort(actual_ids)
 local comparison=assert(io.open(out..'/workshop-workers-comparison-'..target.id..'.json','w'))
 comparison:write(json.encode({native_ids=native_ids,actual_ids=actual_ids,nonunit=nonunit}));comparison:close()
 assert(#sorted_ids==#actual_ids,'Workshop native worker membership count differs: '..#sorted_ids..' native / '..#actual_ids..' semantic')
 for i,id in ipairs(sorted_ids)do assert(actual_ids[i]==id,'Workshop native worker membership differs')end
 return {building_id=target.id,native_order=native_ids,member_ids=actual_ids,skills=native_skills,rows=semantic.rows,geometry=geometry,all_equal=true}
end
local fuel_flags={}
local furnace_fixtures={}
local dye_names={}
local workshop_fixtures={}
local workshop_fixture_ids={}
local craft_tool_fixture
local custom_supplies={}
local magma_tiles={}
local selection_moves={}
local selection_units={}
local selection_designations={}
local selection_engravings={}
local ok,err=xpcall(function()
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());select_map(building)
 assert(sheet.open and sheet.active_sheet==df.view_sheet_type.BUILDING and sheet.active_id==building.id,'Native workshop selection missed')
 shot('jobs')
 if os.getenv('DF3D_TILE_SELECTION')=='1'then
  local function ids(vector)local values={};for _,id in ipairs(vector)do values[#values+1]=id end;return values end
  local function observe()
   local tabs={};for i,kind in ipairs(sheet.tab)do tabs[#tabs+1]={kind=kind,id=sheet.tab_id[i]}end
   return {valid=true,units=ids(sheet.viewing_unid),items=ids(sheet.viewing_itid),vermin=ids(sheet.viewing_vermin_combined_id),
    building=sheet.viewing_bldid,tabs=tabs,active_kind=sheet.active_sheet,active_id=sheet.active_id}
  end
  result.tile_selection_reference={cases={}}
  if os.getenv('DF3D_TILE_SELECTION_ENGRAVING')=='1' then
   local target
   for _,engraving in ipairs(df.global.world.event.engravings)do
    local p=engraving.pos;local d=dfhack.maps.getTileFlags(p)
    if d and not d.hidden then target=engraving;break end
   end
   assert(target,'Engraving reference needs a revealed engraving')
   if os.getenv('DF3D_TILE_SELECTION_ENGRAVING_INIT')=='1' then
    local unresolved=0;local revealed
    for _,e in ipairs(df.global.world.event.engravings)do if e.art_id==-1 then
     unresolved=unresolved+1;local d=dfhack.maps.getTileFlags(e.pos);if d and not d.hidden and not revealed then revealed=e end
    end end
    local controlled=not revealed;target=revealed or target
    selection_engravings[#selection_engravings+1]={target=target,art_id=target.art_id,art_subid=target.art_subid,tile=target.tile,flags=target.flags.whole}
    if controlled then target.art_id=-1;target.art_subid=-1 end
    local p=target.pos;local before={art_id=target.art_id,art_subid=target.art_subid,tile=target.tile,flags=target.flags.whole,chunks=#df.global.world.art_image_chunks.all}
    local owned,owned_effect
    if os.getenv('DF3D_TILE_SELECTION_ENGRAVING_INIT_RUNTIME')=='1' then
     local menu=json.encode(observe());local title,description=sheet.engraving_title,sheet.raw_description
     local output,code=dfhack.run_command_silent('df3d','engraving-description-probe',tostring(p.x),tostring(p.y),tostring(p.z))
     assert(code==0,output);owned=json.decode(output);assert(owned.valid,'Owned initializer failed: '..output)
     assert(menu==json.encode(observe()) and title==sheet.engraving_title and description==sheet.raw_description,'Owned initializer changed native sheet')
     owned_effect={art_id=target.art_id,art_subid=target.art_subid,tile=target.tile,flags=target.flags.whole,chunks=#df.global.world.art_image_chunks.all}
    end
    select_map{centerx=p.x,centery=p.y,z=p.z}
    if sheet.active_sheet~=df.view_sheet_type.ENGRAVING then
     local index;for i,kind in ipairs(sheet.tab)do if kind==df.view_sheet_type.ENGRAVING then index=i;break end end
     assert(index,'Initialization reference has no engraving tab')
     g.precise_mouse_x=(g.dimx-35)*8;g.precise_mouse_y=52+index*36+16
     g.mouse_x=g.precise_mouse_x//8;g.mouse_y=(g.precise_mouse_y-4)//12
     df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
     gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount());df.global.enabler.mouse_lbut_lift=1
    end
    assert(sheet.active_sheet==df.view_sheet_type.ENGRAVING and target.art_id>=0,'Native sheet did not initialize missing artwork')
    result.tile_selection_reference.engraving_initialization={tile={p.x,p.y,p.z},unresolved_count=unresolved,
     controlled_missing_ids=controlled,before=before,
     after={art_id=target.art_id,art_subid=target.art_subid,tile=target.tile,flags=target.flags.whole,chunks=#df.global.world.art_image_chunks.all},
     title=dfhack.df2utf(sheet.engraving_title),description=dfhack.df2utf(sheet.raw_description),lines=lines()}
    if owned then
     local reference=result.tile_selection_reference.engraving_initialization
     assert(owned.title==reference.title and owned.description==reference.description,'Initialized artwork text differs from native sheet')
     assert(json.encode(owned_effect)==json.encode(reference.after),'Native sheet repeated initialization after owned read')
     local output,code=dfhack.run_command_silent('df3d','engraving-description-probe',tostring(p.x),tostring(p.y),tostring(p.z))
     assert(code==0,output);local repeated=json.decode(output)
     assert(repeated.valid and repeated.title==owned.title and repeated.description==owned.description,'Repeated initialized read changed text')
     assert(target.art_id==owned_effect.art_id and target.art_subid==owned_effect.art_subid and target.tile==owned_effect.tile and #df.global.world.art_image_chunks.all==owned_effect.chunks,'Repeated read changed initialized artwork')
     reference.owned={text=owned,effect=owned_effect,repeated=repeated,sheet_unchanged=true}
    end
    shot('selection-engraving-initialization')
    return
   end
   local p=target.pos
   local prior={art_id=target.art_id,art_subid=target.art_subid,flags=target.flags.whole}
   local function artwork_state()
    local chunk=df.art_image_chunk.find(target.art_id)
    if not chunk then return 'unloaded' end
    local image=chunk.images[target.art_subid].art_image
    if not image then return 'missing-image' end
    local values={target.art_id,target.art_subid,target.flags.whole,image.event,image.artist,image.site,
     image.mat_type,image.mat_index,image.quality,image.year,image.season_tick,image.id,image.subid,
     image.name.first_name,image.name.nickname,image.name.language,image.name.has_name}
    for _,word in ipairs(image.name.words)do values[#values+1]=word end
    for _,part in ipairs(image.name.parts_of_speech)do values[#values+1]=part end
    for _,element in ipairs(image.elements)do
     local row={tostring(element),element.count}
     for _,key in ipairs{'race','caste','histfig','item_type','item_subtype','mat_type','mat_index','item_id','plant_id','shape_id','shape_adj'}do
      local ok,value=pcall(function()return element[key]end);if ok then row[#row+1]={key,value}end
     end
     values[#values+1]=row
    end
    for _,property in ipairs(image.properties)do
     local row={tostring(property)}
     for _,key in ipairs{'subject','object','verb'}do
      local ok,value=pcall(function()return property[key]end);if ok then row[#row+1]={key,value}end
     end
     values[#values+1]=row
    end
    return json.encode(values)
   end
   local function probe()
    local before=artwork_state();local menu=json.encode(observe())
    local chunks={};for _,chunk in ipairs(df.global.world.art_image_chunks.all)do chunks[#chunks+1]={id=chunk.id,pointer=tostring(chunk)}end
    local title,description=sheet.engraving_title,sheet.raw_description
    local output,code=dfhack.run_command_silent('df3d','engraving-description-probe',tostring(p.x),tostring(p.y),tostring(p.z))
    assert(code==0,output);local value=json.decode(output)
    if before=='unloaded' then
     assert(value.valid and artwork_state()~='unloaded','Native artwork loader did not populate the missing chunk')
     assert(#df.global.world.art_image_chunks.all==#chunks+1,'Native artwork loader added unexpected chunks')
    else
     assert(before==artwork_state(),'Owned formatter changed source artwork')
     assert(#df.global.world.art_image_chunks.all==#chunks,'Warm artwork read changed chunk count')
    end
    for i,prior_chunk in ipairs(chunks)do local chunk=df.global.world.art_image_chunks.all[i-1]
     assert(chunk.id==prior_chunk.id and tostring(chunk)==prior_chunk.pointer,'Artwork loader replaced a prior chunk')
    end
    assert(target.art_id==prior.art_id and target.art_subid==prior.art_subid and target.flags.whole==prior.flags,'Artwork loader changed engraving identity')
    assert(menu==json.encode(observe()) and title==sheet.engraving_title and description==sheet.raw_description,'Owned formatter changed native sheet')
    return value
   end
   local initially_unloaded=artwork_state()=='unloaded'
   assert(initially_unloaded,'Cold artwork reference was already loaded')
   local owned_before=probe()
   select_map{centerx=p.x,centery=p.y,z=p.z}
   if sheet.active_sheet~=df.view_sheet_type.ENGRAVING then
    local index
    for i,kind in ipairs(sheet.tab)do if kind==df.view_sheet_type.ENGRAVING then index=i;break end end
    assert(index,'Engraving side tab missing')
    g.precise_mouse_x=(g.dimx-35)*8;g.precise_mouse_y=52+index*36+16
    g.mouse_x=g.precise_mouse_x//8;g.mouse_y=(g.precise_mouse_y-4)//12
    df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
    gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount());df.global.enabler.mouse_lbut_lift=1
   end
   assert(sheet.active_sheet==df.view_sheet_type.ENGRAVING,'Engraving tab did not open')
   result.tile_selection_reference.engraving={tile={p.x,p.y,p.z},before=prior,
    after={art_id=target.art_id,art_subid=target.art_subid,flags=target.flags.whole},
    native=observe(),title=dfhack.df2utf(sheet.engraving_title),description=dfhack.df2utf(sheet.raw_description),lines=lines()}
   local owned_after=probe();local reference=result.tile_selection_reference.engraving
   assert(owned_before.valid and owned_before.title==reference.title and owned_before.description==reference.description,'Owned engraving text differs before native opening')
   assert(owned_after.title==reference.title and owned_after.description==reference.description,'Owned engraving text differs after native opening: '..json.encode(owned_after))
   reference.owned={before=owned_before,after=owned_after,source_fields_unchanged=true,sheet_unchanged=true}
   reference.owned.loaded_without_sheet=initially_unloaded
   shot('selection-engraving')
   gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
   local owned_closed=probe()
   assert(owned_closed.title==reference.title and owned_closed.description==reference.description,'Owned engraving text differs with native sheet closed')
   reference.owned.closed=owned_closed
   local planned
   for dx=1,20 do
    local q={x=p.x+dx,y=p.y,z=p.z};local d=dfhack.maps.getTileFlags(q)
    local existing=false;for _,e in ipairs(df.global.world.event.engravings)do if e.pos.x==q.x and e.pos.y==q.y and e.pos.z==q.z then existing=true;break end end
    if d and not d.hidden and not existing then planned=q;break end
   end
   assert(planned,'Planned engraving reference needs revealed neighboring tile')
   local d=dfhack.maps.getTileFlags(planned);selection_designations[#selection_designations+1]={designation=d,whole=d.whole}
   d.whole=d.whole|0x100
   select_map{centerx=planned.x,centery=planned.y,z=planned.z}
   assert(sheet.active_sheet==df.view_sheet_type.ENGRAVING_PLANNED,'Planned engraving is not default on fixture tile')
   result.tile_selection_reference.engraving.planned={tile={planned.x,planned.y,planned.z},native=observe(),lines=lines()}
   shot('selection-engraving-planned')
   g.precise_mouse_x=500;g.precise_mouse_y=118;g.mouse_x=62;g.mouse_y=9
   df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
   gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount());df.global.enabler.mouse_lbut_lift=1
   result.tile_selection_reference.engraving.planned.picker_lines=lines()
   shot('selection-engraving-image-picker')
   gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
   result.tile_selection_reference.engraving.planned.after_escape_lines=lines()
   shot('selection-engraving-image-after-escape')
   return
  end
  local targets={building,original}
  local counts={};local fullest
  for _,item in ipairs(df.global.world.items.all)do
   local p=item.pos
   if p.z==building.z and p.x>=0 and p.y>=0 and item.flags.on_ground and not item.flags.garbage_collect then
    local d=dfhack.maps.getTileFlags(p.x,p.y,p.z)
    if d and not d.hidden then
     local key=p.x..','..p.y;local row=counts[key]or{centerx=p.x,centery=p.y,z=p.z,count=0,id='items'}
     row.count=row.count+1;counts[key]=row
     if not fullest or row.count>fullest.count then fullest=row end
    end
   end
  end
  assert(fullest and fullest.count>=6,'Selection fixture needs a populated item tile');targets[#targets+1]=fullest
  for _,unit in ipairs(df.global.world.units.active)do
   local p=unit.pos;local d=dfhack.maps.getTileFlags(p.x,p.y,p.z)
   if p.z==building.z and d and not d.hidden and not unit.flags1.inactive and not unit.flags1.caged and not unit.flags1.hidden_in_ambush then
    targets[#targets+1]={centerx=p.x,centery=p.y,z=p.z,id='unit'};break
   end
  end
  for _,target in ipairs(targets)do
   select_map(target)
   local before=observe()
   local output,code=dfhack.run_command_silent('df3d','tile-selection-read',tostring(target.centerx),tostring(target.centery),tostring(target.z))
   assert(code==0,output);local actual=json.decode(output)
   result.tile_selection_reference.cases[#result.tile_selection_reference.cases+1]={tile={target.centerx,target.centery,target.z},native=before,actual=actual}
   shot('selection-'..target.id)
   assert(json.encode(observe())==json.encode(before),'Selection provider changed native sheet')
   assert(json.encode(actual)==json.encode(before),'Selection provider differs from native')
   if os.getenv('DF3D_TILE_SELECTION_LAYOUT')=='1' and target.id=='items'then
    local function click(x,y)
     df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
     g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
     df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
     df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
    end
    local function layout(name)
     local cells={}
     for y=4,math.min(g.dimy-1,35)do for x=g.dimx-98,g.dimx-30 do
      local pen=dfhack.screen.readTile(x,y)
      cells[#cells+1]={x=x,y=y,ch=pen.ch,fg=pen.fg,bg=pen.bg,bold=pen.bold,tile=pen.tile}
     end end
     result.tile_selection_reference[name]={state=observe(),cells=cells,dimensions={g.dimx,g.dimy}}
     shot('selection-'..name)
    end
    layout('tabs-building')
    click((g.dimx-35)*8,104)
    assert(sheet.active_sheet==df.view_sheet_type.ITEM_LIST,'Item group tab click missed')
    layout('item-group')
    result.tile_selection_reference.item_names={}
    for i,id in ipairs(before.items)do
     local bytes={}
     for x=g.dimx-90,g.dimx-40 do local ch=dfhack.screen.readTile(x,9+(i-1)*3).ch%256;bytes[#bytes+1]=string.char(ch==0 and 32 or ch)end
     result.tile_selection_reference.item_names[tostring(id)]=dfhack.df2utf(table.concat(bytes)):gsub('%s+$','')
    end
    click((g.dimx-75)*8,118)
    assert(sheet.active_sheet==df.view_sheet_type.ITEM and sheet.active_id==before.items[1],'Group row did not select first item')
    layout('item-member')
    gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
   end
  end
  if os.getenv('DF3D_TILE_SELECTION_SCROLL')=='1' then
   -- Controlled paused clone only: collect loose blocks into one visible tile.
   -- Restore their positions/flags below even when an assertion fails.
   local count=fullest.count
   for _,item in ipairs(df.global.world.items.all)do
    if count>=24 then break end
    local p=item.pos
    if item:getType()==df.item_type.BLOCKS and item.flags.on_ground and not item.flags.in_job and not item.flags.garbage_collect
       and not(p.x==fullest.centerx and p.y==fullest.centery and p.z==fullest.z)then
     selection_moves[#selection_moves+1]={item=item,pos={x=p.x,y=p.y,z=p.z},flags=item.flags.whole}
     assert(dfhack.items.moveToGround(item,{x=fullest.centerx,y=fullest.centery,z=fullest.z}))
     count=count+1
    end
   end
   assert(count==24,'Selection overflow fixture needs24 ground items')
   gui.simulateInput(view,'LEAVESCREEN');select_map(fullest)
   local native=observe()
   local output,code=dfhack.run_command_silent('df3d','tile-selection-read',tostring(fullest.centerx),tostring(fullest.centery),tostring(fullest.z))
   assert(code==0,output);local actual=json.decode(output)
   assert(json.encode(actual)==json.encode(native),'Overflow selection provider differs')
   result.tile_selection_reference.cases[3]={tile={fullest.centerx,fullest.centery,fullest.z},native=native,actual=actual}
   local function input(key,x,y)
    df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
    g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
    df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,key);view:render(dfhack.getTickCount())
    df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
   end
   input('_MOUSE_L',(g.dimx-35)*8,104)
   assert(sheet.active_sheet==df.view_sheet_type.ITEM_LIST)
   result.tile_selection_reference.scroll={tile={fullest.centerx,fullest.centery,fullest.z},ids=ids(sheet.viewing_itid),samples={}}
   local function sample(name)
    local row={name=name,first=sheet.scroll_position,dimx=g.dimx,dimy=g.dimy}
    result.tile_selection_reference.scroll.samples[#result.tile_selection_reference.scroll.samples+1]=row
    shot('selection-scroll-'..name)
    row.first=sheet.scroll_position
    -- Renderer159bad..159c0f clamps a local copy, retaining the stored offset.
    row.visible_first=math.max(0,math.min(row.first,#sheet.viewing_itid-(g.dimy-12)//3))
    for i=0,math.min((g.dimy-12)//3-1,#sheet.viewing_itid-1-row.visible_first)do
     local bytes={}
     for x=g.dimx-90,g.dimx-42 do local ch=dfhack.screen.readTile(x,9+i*3).ch%256;bytes[#bytes+1]=string.char(ch==0 and 32 or ch)end
     result.tile_selection_reference.item_names[tostring(sheet.viewing_itid[row.visible_first+i])]=dfhack.df2utf(table.concat(bytes)):gsub('%s+$','')
    end
   end
   sample('top')
   input('CONTEXT_SCROLL_DOWN',600,154);sample('wheel')
   input('CONTEXT_SCROLL_PAGEDOWN',600,154);sample('page')
   input('_MOUSE_L',(g.dimx-39)*8,(g.dimy-5)*12+4);sample('arrow')
   for _,size in ipairs{'small','minimum','wide','default'}do
    resize_worker(size);sample(size)
    if size=='wide'then
     input('CONTEXT_SCROLL_UP',1000,154);sample('wide-wheel')
     local retained=sheet.scroll_position
     local visible=math.max(0,math.min(retained,#sheet.viewing_itid-(g.dimy-12)//3))
     local expected=sheet.viewing_itid[visible]
     input('_MOUSE_L',1000,114)
     result.tile_selection_reference.scroll.row_after_resize={stored=retained,visible=visible,expected=expected,actual=sheet.active_id,kind=sheet.active_sheet}
     shot('selection-scroll-resized-member')
     input('_MOUSE_L',(g.dimx-35)*8,104)
     assert(sheet.active_sheet==df.view_sheet_type.ITEM_LIST,'Resized member return missed group')
     sheet.scroll_position=retained;view:render(dfhack.getTickCount())
    end
   end
   -- Isolated native scrollbar input probes; scratch reset is diagnostic only.
   sheet.scroll_position=0;sheet.scrolling=false;view:render(dfhack.getTickCount())
   input('_MOUSE_L',888,700);sample('track')
   for _,probe in ipairs{{'drag-top',100},{'drag-middle',400},{'drag-end',748}}do
    sheet.scroll_position=0;sheet.scrolling=false;view:render(dfhack.getTickCount())
    g.precise_mouse_x=888;g.precise_mouse_y=200;g.mouse_x=111;g.mouse_y=(200-4)//12
    df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,{'_MOUSE_L','_MOUSE_L_DOWN'})
    g.precise_mouse_y=probe[2];g.mouse_y=(probe[2]-4)//12
    gui.simulateInput(view,{'_MOUSE_L_DOWN'})
    df.global.enabler.mouse_lbut_lift=1;gui.simulateInput(view,{});view:render(dfhack.getTickCount())
    assert(not sheet.scrolling,'Native thumb retained drag after release')
    sample(probe[1])
   end
   gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
  end
  if os.getenv('DF3D_TILE_SELECTION_UNITS')=='1' then
   -- Paused selection-only fixture: change positions without teleport's
   -- posture, idle-area or rider mutations. No simulation frame may advance.
   for _,unit in ipairs(df.global.world.units.active)do
    if #selection_units>=6 then break end
    if dfhack.units.isCitizen(unit) and not unit.flags1.inactive and not unit.flags1.caged and not unit.flags1.hidden_in_ambush and not unit.flags1.projectile then
     selection_units[#selection_units+1]={unit=unit,pos={x=unit.pos.x,y=unit.pos.y,z=unit.pos.z}}
     unit.pos:assign{x=fullest.centerx,y=fullest.centery,z=fullest.z}
    end
   end
   assert(#selection_units==6,'Unit selection fixture needs six citizens')
   gui.simulateInput(view,'LEAVESCREEN');select_map(fullest)
   assert(sheet.active_sheet==df.view_sheet_type.UNIT_LIST,'Native six-unit grouping missing')
   local native=observe()
   local output,code=dfhack.run_command_silent('df3d','tile-selection-read',tostring(fullest.centerx),tostring(fullest.centery),tostring(fullest.z))
   assert(code==0,output);local actual=json.decode(output)
   assert(json.encode(native)==json.encode(actual),'Six-unit provider differs')
   local names={}
   for index,id in ipairs(native.units)do
    local bytes={}
    for x=g.dimx-90,g.dimx-40 do local ch=dfhack.screen.readTile(x,9+(index-1)*3).ch%256;bytes[#bytes+1]=string.char(ch==0 and 32 or ch)end
    names[tostring(id)]=dfhack.df2utf(table.concat(bytes)):gsub('%s+$','')
   end
   result.tile_selection_reference.unit_group={tile={fullest.centerx,fullest.centery,fullest.z},native=native,actual=actual,names=names,dimx=g.dimx,dimy=g.dimy}
   shot('selection-unit-group')
   g.precise_mouse_x=600;g.precise_mouse_y=118;g.mouse_x=75;g.mouse_y=9
   df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1;df.global.enabler.mouse_lbut_lift=0
   gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount());df.global.enabler.mouse_lbut_lift=1
   result.tile_selection_reference.unit_group.member={kind=sheet.active_sheet,id=sheet.active_id}
   local selected_unit=df.unit.find(sheet.active_id)
   result.tile_selection_reference.unit_group.member.report_counts={#selected_unit.reports.log[0],#selected_unit.reports.log[1],#selected_unit.reports.log[2]}
   assert(sheet.active_sheet==df.view_sheet_type.UNIT and sheet.active_id==native.units[1],'Native unit row selection differs')
   shot('selection-unit-group-member')
   gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
  end
  if os.getenv('DF3D_TILE_SELECTION_RUNTIME')=='1' or os.getenv('DF3D_TILE_SELECTION_SCENE')=='1' then
   local before=observe()
   capture('workshop-wire')
   local file=assert(io.open(out..'/workshop-wire-result.json'));local receipt=json.decode(file:read('*a'));file:close()
   assert(receipt.success,'Selection wire failed')
   assert(json.encode(observe())==json.encode(before),'Selection wire changed native sheet')
  end
  return
 end
 if os.getenv('DF3D_WORKSHOP_CONNECTIONS')=='1'then
  local function click(x,y)
   df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
   g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
   df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
   df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
  end
  result.connections_reference={can_link=building:canLinkToStockpile(),vectors={}}
  local links=building:getWorkshopProfile().links
  for _,field in ipairs{'give_to_pile','take_from_pile','give_to_workshop','take_from_workshop'}do
   local ids={};for _,target in ipairs(links[field])do ids[#ids+1]=target.id end
   result.connections_reference.vectors[field]=ids
  end
  click(768,82);shot('connections-open')
  if os.getenv('DF3D_WORKSHOP_CONNECTIONS_NAV')=='1'then
   assert(click_label('Work orders'));shot('connections-parent-orders')
   assert(sheet.active_sub_tab==0,'Connections allowed parent Work orders tab')
   assert(click_label('Tasks'));shot('connections-parent-tasks')
   local other
   for _,candidate in ipairs(df.global.world.buildings.other.WORKSHOP_ANY)do
    local d=dfhack.maps.getTileFlags(candidate.centerx,candidate.centery,candidate.z)
    if candidate.id~=building.id and candidate.z==building.z and d and not d.hidden and candidate:getBuildStage()==candidate:getMaxBuildStage()then other=candidate;break end
   end
   assert(other,'No second workshop for Connections navigation')
   result.connections_reference.navigation={other_id=other.id,other_type=other:getType()}
   -- The common map helper puts its target underneath the Connections panel.
   -- Put this diagnostic target below it and record the actual exposed-map hit.
   dfhack.gui.revealInDwarfmodeMap({x=other.centerx,y=other.centery,z=other.z},true)
   df.global.window_x=math.max(0,other.centerx-8)
   local hit
   for offset=8,40 do
    df.global.window_y=math.max(0,other.centery-offset)
    view:render(dfhack.getTickCount())
    for y=40,62 do for x=4,49 do
     g.precise_mouse_x=x*8+4;g.precise_mouse_y=y*12+10;g.mouse_x=x;g.mouse_y=y
     local pos=dfhack.gui.getMousePos(true)
     if not hit and pos and pos.x==other.centerx and pos.y==other.centery and pos.z==other.z then hit={x*8+4,y*12+10}end
    end end
    if hit then break end
   end
   assert(hit,'No exposed map hit below Connections')
   result.connections_reference.navigation.hit=hit
   click(hit[1],hit[2]);shot('connections-other-workshop')
   result.connections_reference.navigation.active_after_map=sheet.active_id
   assert(sheet.active_id==building.id,'Connections allowed map selection')
   assert(click_label('Done'));shot('connections-navigation-done')
   click(hit[1],hit[2]);shot('connections-other-after-done')
   assert(sheet.active_id==other.id,'Exposed map baseline did not select other workshop')
   select_map(building);shot('connections-return-workshop')
   return
  end
  click(80,82);shot('connections-give')
  assert(click_label('Cancel'));shot('connections-give-cancel')
  click(112,82);shot('connections-take')
  assert(click_label('Cancel'));assert(click_label('Done'));shot('connections-done')
  if os.getenv('DF3D_WORKSHOP_CONNECTIONS_EFFECTS')=='1'then
   assert(#links.give_to_pile==0 and #links.take_from_pile==0,'Link fixture needs unlinked workshop')
   local pile
   for _,candidate in ipairs(df.global.world.buildings.other.STOCKPILE)do
    local d=dfhack.maps.getTileFlags(candidate.centerx,candidate.centery,candidate.z)
    if candidate.z==building.z and d and not d.hidden then pile=candidate;break end
   end
   assert(pile,'No visible stockpile for workshop link')
   result.connections_reference.pile_id=pile.id
   result.connections_reference.pile_tile={x=pile.centerx,y=pile.centery,z=pile.z}
   local before_pile={}
   for _,field in ipairs{'take_from_workshop','give_to_workshop'}do
    before_pile[field]={};for _,target in ipairs(pile.links[field])do before_pile[field][#before_pile[field]+1]=target.id end
   end
   local function contains(rows,id)for _,row in ipairs(rows)do if row.id==id then return true end end;return false end
   click(768,82);click(80,82);select_map(pile)
   assert(#links.give_to_pile==1 and links.give_to_pile[0].id==pile.id,'Native workshop give pick failed')
   assert(contains(pile.links.take_from_workshop,building.id),'Native give missing reciprocal link')
   shot('connections-linked-give')
   if os.getenv('DF3D_WORKSHOP_CONNECTIONS_MULTI')=='1'then
    local extras={};local backups={}
    for _,candidate in ipairs(df.global.world.buildings.other.STOCKPILE)do
     local d=dfhack.maps.getTileFlags(candidate.centerx,candidate.centery,candidate.z)
     if candidate.id~=pile.id and candidate.z==building.z and d and not d.hidden and #extras<11 then
      extras[#extras+1]=candidate;backups[candidate.id]={}
      for _,field in ipairs{'take_from_workshop','give_to_workshop'}do
       local ids={};for _,entry in ipairs(candidate.links[field])do ids[#ids+1]=entry.id end;backups[candidate.id][field]=ids
      end
     end
    end
    assert(#extras==11,'Multirow Connections fixture needs twelve visible same-level stockpiles')
    for i,target in ipairs(extras)do click(i%2==0 and 80 or 112,82);select_map(target)end
    local ordered={}
    for _,source in ipairs{{'take_from_pile',2},{'give_to_pile',1}}do
     for _,target in ipairs(links[source[1]])do ordered[#ordered+1]={id=target.id,direction=source[2],name=dfhack.df2utf(dfhack.buildings.getName(target))}end
    end
    assert(#ordered==12)
    result.connections_reference.multiple={rows=ordered}
    shot('connections-multiple-top')
    g.precise_mouse_x=200;g.precise_mouse_y=200;g.mouse_x=25;g.mouse_y=16
    click(368,452);shot('connections-multiple-arrow')
    for i=1,20 do click(368,452)end
    shot('connections-multiple-bottom')
    if os.getenv('DF3D_WORKSHOP_CONNECTIONS_MULTI_SCENE')=='1'then
     capture('workshop-wire');local f=assert(io.open(out..'/workshop-wire-result.json'));local receipt=json.decode(f:read('*a'));f:close();assert(receipt.success)
     result.connections_reference.multiple.viewer=receipt
    end
    assert(click_label('Done'));click(768,82)
    for i=1,20 do click(368,140)end
    for remaining=12,2,-1 do
     assert(#links.take_from_pile+#links.give_to_pile==remaining)
     local first=#links.take_from_pile>0 and links.take_from_pile[0] or links.give_to_pile[0]
     click(remaining>9 and 336 or 360,first.id==pile.id and 190 or 154)
     assert(#links.take_from_pile+#links.give_to_pile==remaining-1,'Native multirow unlink made no progress')
    end
    assert(#links.give_to_pile==1 and links.give_to_pile[0].id==pile.id)
    for _,target in ipairs(extras)do
     for field,ids in pairs(backups[target.id])do assert(#target.links[field]==#ids);for i,id in ipairs(ids)do assert(target.links[field][i-1].id==id)end end
    end
    result.connections_reference.multiple.restored=true
    shot('connections-multiple-restored')
   end
   if os.getenv('DF3D_WORKSHOP_CONNECTIONS_RESIZE')=='1'then
    result.connections_reference.resize={}
    for _,size in ipairs{'small','wide','minimum','default'}do
     resize_worker(size)
     result.connections_reference.resize[#result.connections_reference.resize+1]={size=size,dimx=g.dimx,dimy=g.dimy}
     shot('connections-'..size..'-list')
     click(math.max(32,(g.dimx-143)*8)+24,size=='default' and 82 or 78);shot('connections-'..size..'-give')
     assert(click_label('Cancel'))
    end
   end
   if os.getenv('DF3D_WORKSHOP_CONNECTIONS_RUNTIME')=='1' or os.getenv('DF3D_WORKSHOP_CONNECTIONS_SCENE')=='1'then
    capture('workshop-wire');local f=assert(io.open(out..'/workshop-wire-result.json'));local receipt=json.decode(f:read('*a'));f:close();assert(receipt.success)
    assert(#links.give_to_pile==1 and links.give_to_pile[0].id==pile.id and #links.take_from_pile==0,'Semantic link roundtrip did not restore native give')
    result.connections_reference.viewer=receipt
   end
   if click_label('Cancel')then shot('connections-linked-give-cancel')end
   click(360,154)
   assert(#links.give_to_pile==0 and not contains(pile.links.take_from_workshop,building.id),'Native workshop unlink failed');shot('connections-unlinked')
   click(112,82);select_map(pile)
   assert(#links.take_from_pile==1 and links.take_from_pile[0].id==pile.id and contains(pile.links.give_to_workshop,building.id),'Native take missing reciprocal link')
   shot('connections-linked-take');click(360,154)
   assert(#links.take_from_pile==0 and not contains(pile.links.give_to_workshop,building.id),'Native take unlink failed')
   for field,ids in pairs(before_pile)do assert(#pile.links[field]==#ids);for i,id in ipairs(ids)do assert(pile.links[field][i-1].id==id)end end
   result.connections_reference.effects={give=true,take=true,reciprocal=true,unlink=true,original_pile_vectors_restored=true}
   assert(click_label('Done'));shot('connections-effects-restored')
  end
  for field,ids in pairs(result.connections_reference.vectors)do
   assert(#links[field]==#ids);for i,id in ipairs(ids)do assert(links[field][i-1].id==id)end
  end
  return
 end
 if os.getenv('DF3D_WORKSHOP_HEADER')=='1'then
  assert(#jobs==0,'Header reference requires empty queue')
  local name=building.name
  local function key(value)gui.simulateInput(view,value);view:render(dfhack.getTickCount())end
  local function click(x,y)
   df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
   g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
   df.global.enabler.mouse_lbut_lift=0;key('_MOUSE_L')
   df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
  end
  local function text(value)for i=1,#value do key(('STRING_A%03d'):format(value:byte(i)))end end
  result.header_reference={original_name=dfhack.df2utf(name),states={}}
  local function record(label)
   local row={name=label,custom_name=dfhack.df2utf(building.name),editing=sheet.building_entering_nickname,open=sheet.open,removing=dfhack.buildings.markedForRemoval(building),jobs={}}
   for _,j in ipairs(building.jobs)do row.jobs[#row.jobs+1]={id=j.id,type=j.job_type,flags=j.flags.whole}end
   result.header_reference.states[#result.header_reference.states+1]=row;shot('header-'..label)
  end
  local worked,problem=xpcall(function()
   click(800,82);text('lower workshop');assert(building.name==name..'lower workshop');record('draft')
   key('SELECT');assert(not sheet.building_entering_nickname and sheet.open);record('renamed')
   click(800,82);text(' appended');key('LEAVESCREEN');assert(building.name==name..'lower workshop appended' and not sheet.open);record('escape')
   select_map(building);click(800,82);for i=1,100 do key('STRING_A000')end;text(name);key('SELECT');assert(building.name==name);record('restored')
   click(832,82);assert(dfhack.buildings.markedForRemoval(building) and #building.jobs==1 and building.jobs[0].job_type==df.job_type.DestroyBuilding);record('remove')
   assert(click_label('Cancel removal'));assert(#building.jobs==0 and not dfhack.buildings.markedForRemoval(building));record('cancel')
   if os.getenv('DF3D_WORKSHOP_HEADER_QUEUED')=='1'then
    assert(df.building_workshopst:is_instance(building))
    for i=1,2 do assert(click_label('Add new task'));assert(click_label('Make bed'))end
    assert(#building.jobs==2)
    local worker
    for _,unit in ipairs(df.global.world.units.active)do
     if dfhack.units.isCitizen(unit) and not dfhack.units.isDead(unit) and not unit.job.current_job then worker=unit;break end
    end
    assert(worker and dfhack.job.addWorker(building.jobs[0],worker))
    building.jobs[0].flags.working=true
    result.header_reference.queued={worker_id=worker.id,before_ids={building.jobs[0].id,building.jobs[1].id},setup='Paused native-button fixture: two native Make bed jobs; addWorker and working=true on first job, no AI ticks.'}
    record('queued')
    click(832,82);record('queued-remove')
    assert(#building.jobs==1 and building.jobs[0].job_type==df.job_type.DestroyBuilding,'Removal retained production jobs')
    assert(not worker.job.current_job,'Removal retained production worker job')
    result.header_reference.queued.worker_released=true
    assert(click_label('Cancel removal'));record('queued-cancel')
    assert(#building.jobs==0 and not dfhack.buildings.markedForRemoval(building))
    result.header_reference.queued.cancel_empty=true
    if os.getenv('DF3D_WORKSHOP_HEADER_QUEUED_RUNTIME')=='1'then
     for i=1,2 do assert(click_label('Add new task'));assert(click_label('Make bed'))end
     assert(#building.jobs==2 and dfhack.job.addWorker(building.jobs[0],worker));building.jobs[0].flags.working=true
     result.header_reference.queued.viewer_before_ids={building.jobs[0].id,building.jobs[1].id}
     record('queued-wire')
    end
   end
   if os.getenv('DF3D_WORKSHOP_HEADER_RUNTIME')=='1'then
    capture('workshop-wire')
    local f=assert(io.open(out..'/workshop-wire-result.json'));local receipt=json.decode(f:read('*a'));f:close();assert(receipt.success)
    assert(building.name==name and #building.jobs==0 and not dfhack.buildings.markedForRemoval(building),'Viewer header did not restore name/queue')
    if result.header_reference.queued then assert(not df.unit.find(result.header_reference.queued.worker_id).job.current_job,'Viewer removal retained production worker job')end
    result.header_reference.viewer=receipt;record('viewer-complete')
   end
  end,debug.traceback)
  building.name=name
  if dfhack.buildings.markedForRemoval(building)then select_map(building);assert(click_label('Cancel removal'))end
  assert(worked,problem);return
 end
 if os.getenv('DF3D_WORKSHOP_SHEET_LAYOUT')=='1'then
  assert(#jobs==0,'Sheet layout reference needs empty queue')
  local original_limit=building:getWorkshopProfile().max_general_orders
  local assigned,specialized
  local profile=building:getWorkshopProfile()
  local function click(x,y)
   df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
   g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
   df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
   df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
  end
  local created={}
  local order_ids={}
  local function find_order(id)
   for _,o in ipairs(df.global.world.manager_orders.all)do if o.id==id then return o end end
  end
  local manager_position,manager_index,manager_prior,manager_entries
  local worked,problem=xpcall(function()
   if os.getenv('DF3D_WORKSHOP_SHEET_ORDERS')=='1'then
    local fortress=assert(df.global.plotinfo.main.fortress_entity)
    local responsibility=df.entity_position_responsibility.MANAGE_PRODUCTION
    local assignment
    for _,a in ipairs(fortress.positions.assignments)do
     if a.histfig>=0 then
      for _,u in ipairs(df.global.world.units.active)do
       if u.hist_figure_id==a.histfig then
        for _,p in ipairs(fortress.positions.own)do if p.id==a.position_id then manager_position=p;assignment=a;break end end
       end
       if manager_position then break end
      end
     end
     if manager_position then break end
    end
    assert(manager_position,'Populated orders need an occupied office')
    manager_index=fortress.assignments_by_type[responsibility];manager_entries={}
    for _,a in ipairs(manager_index)do manager_entries[#manager_entries+1]=a end
    manager_prior=manager_position.responsibilities[responsibility]
    manager_position.responsibilities[responsibility]=true;manager_index:insert('#',assignment)
    for _,o in ipairs(df.global.world.manager_orders.all)do assert(o.workshop_id~=building.id,'Expected no existing shop orders')end
    local picker=df.global.game.main_interface.create_work_order
    assert(click_label('Work orders'))
    for i=1,(os.getenv('DF3D_WORKSHOP_ORDERS_OVERFLOW')=='1' and 12 or 2)do
     click(880,154);assert(picker.open);click(600,94)
     for char in ('make bed'):gmatch('.')do gui.simulateInput(view,('STRING_A%03d'):format(char:byte()))end
     gui.simulateInput(view,'SELECT');view:render(dfhack.getTickCount())
     local id=df.global.world.manager_orders.manager_order_next_id
     click(600,130);assert(not picker.open)
     local order=assert(find_order(id));assert(order.workshop_id==building.id and order.job_type==df.job_type.ConstructBed)
     order_ids[#order_ids+1]=id
    end
    result.sheet_orders={ids=order_ids,quantity=find_order(order_ids[1]).amount_left}
    assert(click_label('Tasks'))
   end
   if os.getenv('DF3D_WORKSHOP_SHEET_ASSIGNED')=='1'then
    assert(#profile.permitted_workers==0)
    assert(click_label('Workers'));click(448,154);click(80,106)
    assert(#profile.permitted_workers==1);assigned=assert(df.unit.find(profile.permitted_workers[0]))
    specialized=assigned.flags4.only_do_assigned_jobs
    result.sheet_assigned={unit_id=assigned.id,specialized=specialized}
    assert(click_label('Tasks'))
   end
   for i=1,2 do
    assert(click_label('Add new task'));assert(click_label('Make bed'))
    created[#created+1]=assert(building.jobs[#building.jobs-1])
   end
   result.sheet_layout={}
   for _,size in ipairs{'small','wide','minimum','default'}do
    resize_worker(size)
    result.sheet_layout[#result.sheet_layout+1]={size=size,dimx=g.dimx,dimy=g.dimy}
    for _,tab in ipairs{'Tasks','Workers','Work orders'}do
     assert(click_label(tab),'Layout tab missing: '..tab)
     shot('sheet-'..size..'-'..tab:gsub(' ','-'))
     if os.getenv('DF3D_WORKSHOP_ORDERS_OVERFLOW')=='1' and size=='default' and tab=='Work orders'then
      click(880,452);shot('orders-overflow-arrow')
      for i=1,20 do click(880,452)end;shot('orders-overflow-bottom')
      for i=1,20 do click(880,178)end
     end
     if assigned and tab=='Workers'then
      click((g.dimx-98)*8+32,48+(size=='default' and 4 or 0)+198)
      assert(assigned.flags4.only_do_assigned_jobs~=specialized)
      shot('sheet-'..size..'-Workers-mode')
      click((g.dimx-98)*8+32,48+(size=='default' and 4 or 0)+198)
      assert(assigned.flags4.only_do_assigned_jobs==specialized)
     end
    end
    assert(click_label('Tasks'));assert(click_label('Add new task'))
    shot('sheet-'..size..'-picker')
    assert(click_label('Cancel'));assert(click_label('Add new task'))
    assert(click_label('Cancel'));shot('sheet-'..size..'-return')
   end
   local receipt={}
   if os.getenv('DF3D_WORKSHOP_ORDERS_OVERFLOW_NATIVE')~='1'then
    capture('workshop-wire')
    local file=assert(io.open(out..'/workshop-wire-result.json'));receipt=json.decode(file:read('*a'));file:close();assert(receipt.success)
   end
   assert(building:getWorkshopProfile().max_general_orders==original_limit,'Resized viewer changed original general-order limit')
   if os.getenv('DF3D_WORKSHOP_ORDERS_OVERFLOW')=='1'then for _,id in ipairs(order_ids)do assert(find_order(id).amount_left==result.sheet_orders.quantity,'Overflow viewer changed original quantity')end end
   if assigned then assert(#profile.permitted_workers==1 and profile.permitted_workers[0]==assigned.id and assigned.flags4.only_do_assigned_jobs==specialized,'Resized worker gestures changed initial assignment/mode')end
   result.sheet_layout_viewer=receipt.sheet_layout;shot('sheet-layout-complete')
  end,debug.traceback)
  for _,job in ipairs(created)do assert(dfhack.job.removeJob(job))end
  if assigned then assigned.flags4.only_do_assigned_jobs=specialized;profile.permitted_workers:resize(0)end
  resize_worker('default')
  if #order_ids>0 then
   select_map(building);assert(click_label('Work orders'))
   for _,id in ipairs(order_ids)do
    assert(find_order(id));local remaining=0;for _,o in ipairs(df.global.world.manager_orders.all)do if o.workshop_id==building.id then remaining=remaining+1 end end;click(remaining>8 and 856 or 872,190)
    assert(not find_order(id),'Native cleanup retained workshop order')
   end
  end
  if manager_position then
   manager_position.responsibilities[df.entity_position_responsibility.MANAGE_PRODUCTION]=manager_prior
   manager_index:resize(0);for _,a in ipairs(manager_entries)do manager_index:insert('#',a)end
  end
  assert(worked,problem);return
 end
 if os.getenv('DF3D_WORKSHOP_WORKER_HOVER')=='1'then
  local profile=building:getWorkshopProfile();assert(#profile.permitted_workers==0)
  local assigned,specialized
  local function click(x,y)
   df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
   g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
   df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
   df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
  end
  local worked,problem=xpcall(function()
   assert(click_label('Workers'));result.worker_hover={}
   local function sample(kind,x,y)
    local script=require('gui.script')
    local function move()
     g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
     df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
     gui.simulateInput(view,{});view:render(dfhack.getTickCount())
    end
    local deadline=dfhack.getTickCount()+700
    repeat move();script.sleep(1,'frames')until dfhack.getTickCount()>=deadline
    move()
    local row={kind=kind,x=x,y=y,instruction=df.global.game.main_interface.current_hover,enabled=df.global.game.main_interface.hover_instructions_on,lines={}}
    for yy=0,17 do
     local chars={};for xx=g.dimx-24,g.dimx-1 do local ch=dfhack.screen.readTile(xx,yy).ch;chars[#chars+1]=ch>=32 and string.char(ch%256)or' 'end
     row.lines[#row.lines+1]=dfhack.df2utf(table.concat(chars)):gsub('%s+$','')
    end
    while #row.lines>0 and row.lines[#row.lines]==''do table.remove(row.lines)end
    result.worker_hover[#result.worker_hover+1]=row
   end
   sample('rename-control',800,82);assert(result.worker_hover[1].instruction==301)
   sample('assign-free',448,154);sample('free-caption',600,154)
   click(448,154);click(80,106);assert(#profile.permitted_workers==1)
   assigned=assert(df.unit.find(profile.permitted_workers[0]));specialized=assigned.flags4.only_do_assigned_jobs
   sample('portrait',448,154);sample('assigned-caption',600,154);sample('remove',864,154);sample('assign',448,190)
   sample(specialized and 'specialized' or 'unspecialized',448,250)
   click(448,250);assert(assigned.flags4.only_do_assigned_jobs~=specialized)
   sample(specialized and 'unspecialized' or 'specialized',448,250)
   sample('mode-caption',600,250)
   shot('worker-hover')
  end,debug.traceback)
  if assigned then assigned.flags4.only_do_assigned_jobs=specialized end
  profile.permitted_workers:resize(0)
  assert(worked,problem);return
 end
 if os.getenv('DF3D_WORKSHOP_TASK_HOVER')=='1'then
  assert(#jobs==0,'Hover reference needs an empty workshop queue')
  assert(click_label('Add new task'));assert(click_label('Make bed'))
  local created=assert(building.jobs[0]);assert(#building.jobs==1)
  local second
  local worked,problem=xpcall(function()
   local script=require('gui.script');result.task_hover={}
   for _,target in ipairs{{'rename-control',800,82},{'repeat',748,154},{'priority',772,154},{'move-up',796,154},{'details',820,154},{'suspend',844,154},{'remove',868,154},{'add',744,190},{'repeat-on',748,154,true},{'priority-on',772,154,true},{'suspend-on',844,154,true},{'move-up-enabled',796,190,false,true},{'remove-control',832,82}}do
    if target[5] then
     assert(click_label('Add new task'));assert(click_label('Make bed'))
     second=assert(building.jobs[1]);assert(#building.jobs==2)
    end
    if target[4] then
     g.precise_mouse_x=target[2];g.precise_mouse_y=target[3];g.mouse_x=target[2]//8;g.mouse_y=(target[3]-4)//12
     df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
     df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
    end
    local deadline=dfhack.getTickCount()+700
    repeat
     g.precise_mouse_x=target[2];g.precise_mouse_y=target[3]
     g.mouse_x=target[2]//8;g.mouse_y=(target[3]-4)//12
     df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
     gui.simulateInput(view,{});view:render(dfhack.getTickCount());script.sleep(1,'frames')
    until dfhack.getTickCount()>=deadline
    g.precise_mouse_x=target[2];g.precise_mouse_y=target[3]
    g.mouse_x=target[2]//8;g.mouse_y=(target[3]-4)//12
    df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
    gui.simulateInput(view,{});view:render(dfhack.getTickCount())
    local sample={kind=target[1],x=target[2],y=target[3],instruction=df.global.game.main_interface.current_hover,enabled=df.global.game.main_interface.hover_instructions_on,lines={}}
    local expected=({['rename-control']=301,['remove-control']=302})[target[1]]
    if expected then assert(sample.instruction==expected and sample.enabled,'Workshop hover positive control differs: '..target[1])end
    for yy=0,17 do
     local chars={};for xx=g.dimx-24,g.dimx-1 do local ch=dfhack.screen.readTile(xx,yy).ch;chars[#chars+1]=ch>=32 and string.char(ch%256)or' 'end
     sample.lines[#sample.lines+1]=dfhack.df2utf(table.concat(chars)):gsub('%s+$','')
    end
    while #sample.lines>0 and sample.lines[#sample.lines]==''do table.remove(sample.lines)end
    result.task_hover[#result.task_hover+1]=sample
   end
   shot('task-hover')
  end,debug.traceback)
  if second then assert(dfhack.job.removeJob(second))end
  assert(dfhack.job.removeJob(created));assert(worked,problem)
  return
 end
 if os.getenv('DF3D_WORKSHOP_FORGE_CHOICES')=='1'then
  local utils=require('utils');local forge
  for _,b in ipairs(df.global.world.buildings.other.WORKSHOP_ANY)do
   if df.building_workshopst:is_instance(b) and b.type==df.workshop_type.MetalsmithsForge and b:getBuildStage()==b:getMaxBuildStage()then forge=b;break end
  end
  assert(forge,'Forge choice reference needs a completed forge')
  if os.getenv('DF3D_WORKSHOP_MAGMA_FORGE')=='1'then
   workshop_fixtures[#workshop_fixtures+1]={building=forge,prior_type=forge.type,prior_custom=forge.custom_type,prior_stage=forge.construction_stage}
   forge.type=df.workshop_type.MagmaForge
   local x,y,z=forge.x1,forge.y1,forge.z;local tx,ty=x%16,y%16
   assert(x~=forge.centerx or y~=forge.centery,'Magma forge requires a noncenter opening')
   local upper=assert(dfhack.maps.getTileBlock(x,y,z));local lower=assert(dfhack.maps.getTileBlock(x,y,z-1))
   magma_tiles[#magma_tiles+1]={upper=upper,lower=lower,x=tx,y=ty,tile=upper.tiletype[tx][ty],designation=lower.designation[tx][ty].whole}
   upper.tiletype[tx][ty]=df.tiletype.OpenSpace
   lower.designation[tx][ty].flow_size=7;lower.designation[tx][ty].liquid_type=df.tile_liquid.Magma
   assert(not forge:isUnpowered(),'Controlled opening did not power magma forge')
  end
  local before={};for _,job in ipairs(forge.jobs)do before[#before+1]=job.id end
  result.forge_choices={building_id=forge.id,subtype=forge:getSubtype(),unpowered=forge:isUnpowered(),pages={}}
  for category=-1,6 do
   gui.simulateInput(view,'LEAVESCREEN');select_map(forge);assert(click_label('Add new task'))
   if category>=0 then
    local button=assert(df.global.game.main_interface.building.filtered_button[category])
    assert(df.interface_button_building_category_selectorst:is_instance(button))
    assert(click_label(dfhack.df2utf(utils.call_with_string(button,'text'))))
   end
   local native={}
   for _,button in ipairs(df.global.game.main_interface.building.filtered_button)do
    if category==-1 and df.interface_button_building_category_selectorst:is_instance(button)then
     local b=df.reinterpret_cast(df.interface_button_building_category_selectorst,button)
     native[#native+1]={category=b.category,material_index=-1,caption=dfhack.df2utf(utils.call_with_string(button,'text'))}
    elseif category==6 and df.interface_button_building_new_jobst:is_instance(button)then
     local b=df.reinterpret_cast(df.interface_button_building_new_jobst,button)
     native[#native+1]={job_type=b.jobtype,item_subtype=b.subtype,mat_type=b.material,mat_index=b.matgloss,
      material_category=b.job_item_flag.whole,specflag=b.specflag.whole,specdata=b.specdata.hist_figure_id,
      art_type=b.art_specifier,art_id=b.art_specifier_id1,art_subid=b.art_specifier_id2,caption=dfhack.df2utf(utils.call_with_string(button,'text'))}
    elseif category>=0 and df.interface_button_building_material_selectorst:is_instance(button)then
     local b=df.reinterpret_cast(df.interface_button_building_material_selectorst,button)
     native[#native+1]={category=category,material_index=b.matgloss,caption=dfhack.df2utf(utils.call_with_string(button,'text'))}
    end
   end
   local encoded,status=dfhack.run_command_silent('df3d','workshop-forge-choices-probe',tostring(forge.id),tostring(category));assert(status==0,encoded)
   local owned=json.decode(encoded)
   result.forge_choices.pages[#result.forge_choices.pages+1]={category=category,native=native,owned=owned}
   shot('forge-choices-'..category)
   assert(json.encode(native)==json.encode(owned),'Forge category/material choices differ: '..category)
   if category==0 then
    local function sample(name)
     local rows={}
     for _,button in ipairs(df.global.game.main_interface.building.filtered_button)do
      rows[#rows+1]={caption=dfhack.df2utf(utils.call_with_string(button,'text')),type=tostring(button._type)}
     end
     result.forge_navigation=result.forge_navigation or {}
     result.forge_navigation[#result.forge_navigation+1]={name=name,query=sheet.building_job_filter_str,
      focused=sheet.entering_building_job_filter,open=sheet.open,rows=rows}
     shot('forge-navigation-'..name)
    end
    assert(click_label(native[1].caption));sample('tasks')
    assert(click_label('...'));assert(sheet.entering_building_job_filter)
    for char in ('bolt'):gmatch('.')do gui.simulateInput(view,('STRING_A%03d'):format(char:byte()))end
    gui.simulateInput(view,'SELECT');view:render(dfhack.getTickCount());sample('filtered-tasks')
    assert(click_label('Back'));sample('material-return')
   end
   if category>=0 then
    assert(click_label('Back'),'Forge category page has no Back control')
    local roots={}
    for _,button in ipairs(df.global.game.main_interface.building.filtered_button)do
     if df.interface_button_building_category_selectorst:is_instance(button)then roots[#roots+1]=dfhack.df2utf(utils.call_with_string(button,'text'))end
    end
    assert(#roots==7,'Back did not restore forge root categories')
    result.forge_choices.pages[#result.forge_choices.pages].back_root=roots
    shot('forge-back-'..category)
   end
  end
  if os.getenv('DF3D_WORKSHOP_FORGE_RUNTIME')=='1'then
   local function effect(job)
    local inputs={};for _,i in ipairs(job.job_items.elements)do
     inputs[#inputs+1]={item_type=i.item_type,item_subtype=i.item_subtype,mat_type=i.mat_type,mat_index=i.mat_index,quantity=i.quantity,
      flags1=i.flags1.whole,flags2=i.flags2.whole,flags3=i.flags3.whole}
    end
    return {job_type=job.job_type,item_subtype=job.item_subtype,mat_type=job.mat_type,mat_index=job.mat_index,material_category=job.material_category.whole,inputs=inputs}
   end
   gui.simulateInput(view,'LEAVESCREEN');select_map(forge);assert(click_label('Add new task'))
   assert(click_label('Weapons and ammunition'));assert(click_label('iron (opens menu)'))
   local first=assert(df.global.game.main_interface.building.filtered_button[0])
   assert(df.interface_button_building_new_jobst:is_instance(first))
   assert(click_label(dfhack.df2utf(utils.call_with_string(first,'text'))))
   local native_job=assert(forge.jobs[#forge.jobs-1]);result.forge_effect={native=effect(native_job)}
   assert(dfhack.job.removeJob(native_job));shot('forge-effect-before')
   capture('workshop-wire')
   local file=assert(io.open(out..'/workshop-wire-result.json'));local receipt=json.decode(file:read('*a'));file:close();assert(receipt.success)
   local created;for _,job in ipairs(forge.jobs)do if job.id==receipt.created_job then created=job;break end end
   assert(created,'Viewer forge job missing');result.forge_effect.viewer=effect(created);assert(dfhack.job.removeJob(created))
   shot('forge-effect-after')
   assert(json.encode(result.forge_effect.native)==json.encode(result.forge_effect.viewer),'Viewer forge job/input effects differ')
  end
  local after={};for _,job in ipairs(forge.jobs)do after[#after+1]=job.id end
  assert(json.encode(before)==json.encode(after),'Forge choice diagnostic changed queue')
  return
 end
 if os.getenv('DF3D_WORKSHOP_CATEGORY_NAV')=='1'then
  local utils=require('utils');result.category_navigation={}
  local function sample(name)
   local rows={}
   for _,button in ipairs(df.global.game.main_interface.building.filtered_button)do
    rows[#rows+1]={caption=dfhack.df2utf(utils.call_with_string(button,'text')),type=tostring(button._type),leave=button.leave_button}
   end
   result.category_navigation[#result.category_navigation+1]={name=name,category=df.global.game.main_interface.building.current_custom_category_token,
    query=sheet.building_job_filter_str,focused=sheet.entering_building_job_filter,open=sheet.open,rows=rows}
   shot('category-'..name)
  end
  assert(click_label('Add new task'));sample('root')
  assert(click_label('Make instrument piece'));sample('child')
  gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());sample('escape')
  select_map(building);assert(click_label('Add new task'));assert(click_label('Make instrument piece'));sample('child-again')
  assert(click_label('Cancel'));sample('cancel')
  select_map(building);assert(click_label('Add new task'))
  assert(click_label('...'))
  assert(sheet.entering_building_job_filter)
  for char in ('instrument'):gmatch('.')do gui.simulateInput(view,('STRING_A%03d'):format(char:byte()))end
  gui.simulateInput(view,'SELECT');view:render(dfhack.getTickCount());sample('filtered-root')
  assert(click_label('Make instrument piece'));sample('filtered-child')
  return
 end
 if os.getenv('DF3D_WORKSHOP_TASK_CATALOG')=='1'then
  local utils=require('utils')
  local function family_effect(job)
   local inputs={};for _,i in ipairs(job.job_items.elements)do
    inputs[#inputs+1]={item_type=i.item_type,item_subtype=i.item_subtype,mat_type=i.mat_type,mat_index=i.mat_index,quantity=i.quantity,
     flags1=i.flags1.whole,flags2=i.flags2.whole,flags3=i.flags3.whole}
    if os.getenv('DF3D_WORKSHOP_CUSTOM_SUPPLIES')=='1'then
     local row=inputs[#inputs]
     for _,field in ipairs({'vector_id','flags4','flags5','metal_ore','reaction_class','has_material_reaction_product','min_dimension','reagent_index','reaction_id','has_tool_use','dye_color'})do row[field]=i[field]end
     row.contains={};for _,value in ipairs(i.contains)do row.contains[#row.contains+1]=value end
    end
   end
   local effect={job_type=job.job_type,reaction_name=job.reaction_name,item_subtype=job.item_subtype,mat_type=job.mat_type,mat_index=job.mat_index,
    material_category=job.material_category.whole,specflag=job.specflag.whole,specdata=job.specdata.hist_figure_id,inputs=inputs}
   if os.getenv('DF3D_WORKSHOP_DYER_RUNTIME')=='1'then effect.art_type=job.art_spec.type;effect.art_id=job.art_spec.id;effect.art_subid=job.art_spec.subid end
   return effect
  end
  if os.getenv('DF3D_WORKSHOP_CUSTOM_SUPPLIES')=='1'then
   assert(os.getenv('DF3D_WORKSHOP_CUSTOM_DISCOVERY')=='1' and df.global.pause_state,'Custom supplies require paused owned custom lane')
   local worker
   for _,unit in ipairs(df.global.world.units.active)do if dfhack.units.isCitizen(unit) and not unit.job.current_job then worker=unit;break end end
   assert(worker,'Custom supplies need an idle citizen')
   local function tool(code)
    for index,raw in ipairs(df.global.world.raws.itemdefs.tools)do if raw.id==code then return index end end
    error('Missing fixture tool '..code)
   end
   local function supply(kind,subtype,token,container)
    local material=assert(dfhack.matinfo.find(token),'Missing fixture material '..token)
    local items=dfhack.items.createItem(worker,df.item_type[kind],subtype,material.type,material.index)
    assert(#items==1,'Custom supply creation failed')
    local item=items[1];custom_supplies[#custom_supplies+1]=item
    assert(dfhack.items.moveToGround(item,worker.pos));item.flags.forbid=false
    if kind=='GLOB' or kind=='LIQUID_MISC' then item:setDimension(150)end
    if container then assert(dfhack.items.moveToContainer(item,container))end
    return item
   end
   local pot=tool('ITEM_TOOL_LARGE_POT')
   local lye_pot=supply('TOOL',pot,'INORGANIC:GRANITE')
   supply('LIQUID_MISC',-1,'LYE',lye_pot)
   local oil_pot=supply('TOOL',pot,'INORGANIC:GRANITE')
   supply('LIQUID_MISC',-1,'PLANT_MAT:FLAX:OIL',oil_pot)
   supply('GLOB',-1,'CREATURE_MAT:COW:TALLOW')
   supply('GLOB',-1,'PLANT_MAT:FLAX:SEED')
   supply('GLOB',-1,'PLANT_MAT:FLAX:THREAD')
   supply('PLANT_GROWTH',-1,'PLANT_MAT:OLIVE:FRUIT')
   supply('TOOL',tool('ITEM_TOOL_HONEYCOMB'),'CREATURE_MAT:HONEY_BEE:WAX')
   supply('TOOL',pot,'INORGANIC:GRANITE')
   result.custom_supplies={}
   for _,item in ipairs(custom_supplies)do result.custom_supplies[#result.custom_supplies+1]={id=item.id,type=item:getType(),subtype=item:getSubtype(),mat_type=item:getMaterial(),mat_index=item:getMaterialIndex()}end
  end
  if os.getenv('DF3D_WORKSHOP_CRAFT_BONE_TOOL')=='1'then
   assert(os.getenv('DF3D_WORKSHOP_CRAFT_NAV')=='1','Bone tool probe requires Craft navigation')
   local entity=assert(df.global.plotinfo.main.fortress_entity)
   for _,id in ipairs(entity.resources.tool_type)do
    local raw=df.global.world.raws.itemdefs.tools[id]
    if raw and not raw.flags.NO_DEFAULT_JOB and not raw.flags.FURNITURE and not raw.flags.BONE_MAT then
     craft_tool_fixture={raw=raw,id=id,bone=raw.flags.BONE_MAT};raw.flags.BONE_MAT=true;break
    end
   end
   assert(craft_tool_fixture,'No suitable civilization tool for controlled bone probe')
   result.craft_bone_tool={tool_id=craft_tool_fixture.id,raw_id=craft_tool_fixture.raw.id,prior_bone=craft_tool_fixture.bone}
  end
  if os.getenv('DF3D_WORKSHOP_SMELTER_NO_FUEL')=='1'then
   assert(os.getenv('DF3D_WORKSHOP_SMELTER_RUNTIME')=='1','Fuel scenario requires Smelter lane')
   for _,item in ipairs(df.global.world.items.other.BAR)do if item:getMaterial()==7 then
    fuel_flags[#fuel_flags+1]={item=item,forbid=item.flags.forbid};item.flags.forbid=true
   end end
   result.fuel_scenario={forbidden_bars=#fuel_flags};assert(#fuel_flags>0,'Fuel scenario has no fuel bars')
  end
  if os.getenv('DF3D_WORKSHOP_FURNACE_DISCOVERY')=='1' or os.getenv('DF3D_WORKSHOP_KILN_RUNTIME')=='1' or os.getenv('DF3D_WORKSHOP_GLASS_RUNTIME')=='1'then
   local magma_type=tonumber(os.getenv('DF3D_WORKSHOP_MAGMA_TYPE')or '')
   if magma_type then assert(magma_type>=4 and magma_type<=6,'Invalid magma furnace fixture')end
   local kiln_only=os.getenv('DF3D_WORKSHOP_KILN_RUNTIME')=='1'
   local glass_only=os.getenv('DF3D_WORKSHOP_GLASS_RUNTIME')=='1'
   for _,target in ipairs(df.global.world.buildings.all)do
    if df.building_furnacest:is_instance(target) and target:getBuildStage()==target:getMaxBuildStage() and #target.jobs==0 and target.custom_type==-1 then
     local subtype=magma_type or (kiln_only and 3 or 2+#furnace_fixtures)
     furnace_fixtures[#furnace_fixtures+1]={building=target,prior_type=target.type,id=target.id,fixture_type=subtype}
     target.type=subtype
     if magma_type and os.getenv('DF3D_WORKSHOP_MAGMA_SUPPLY')=='1'then
      local x,y,z=target.x1,target.y1,target.z
      assert(x~=target.centerx or y~=target.centery,'Magma fixture needs a noncenter tile')
      local upper=assert(dfhack.maps.getTileBlock(x,y,z));local lower=assert(dfhack.maps.getTileBlock(x,y,z-1))
      local tx,ty=x%16,y%16
      magma_tiles[#magma_tiles+1]={upper=upper,lower=lower,x=tx,y=ty,tile=upper.tiletype[tx][ty],designation=lower.designation[tx][ty].whole}
      upper.tiletype[tx][ty]=df.tiletype.OpenSpace
      lower.designation[tx][ty].flow_size=7;lower.designation[tx][ty].liquid_type=df.tile_liquid.Magma
      assert(not target:isUnpowered(),'Controlled magma opening did not power furnace')
     end
     if #furnace_fixtures==((magma_type or kiln_only or glass_only) and 1 or 2) then break end
    end
   end
   assert(#furnace_fixtures==((magma_type or kiln_only or glass_only) and 1 or 2),'Furnace fixture needs idle completed furnace records')
   result.furnace_fixtures={}
   for _,entry in ipairs(furnace_fixtures)do result.furnace_fixtures[#result.furnace_fixtures+1]={id=entry.id,prior_type=entry.prior_type,fixture_type=entry.fixture_type}end
  end
  if os.getenv('DF3D_WORKSHOP_EXTRA_DISCOVERY')=='1'then
   if os.getenv('DF3D_WORKSHOP_DYER_INGREDIENT_NAV')=='1'then
    local encoded,status=dfhack.run_command_silent('df3d','workshop-dye-counts-probe')
    assert(status==0,encoded);result.dyer_ingredient_counts=json.decode(encoded)
   end
   if os.getenv('DF3D_WORKSHOP_DYER_PAGES')=='1'then
    for _,color in ipairs(df.global.world.raws.descriptors.colors)do
     dye_names[#dye_names+1]={color=color,name=color.name}
     color.name=color.name..string.rep('x',math.max(0,140-#color.name))
    end
    result.dyer_long_names=true
   end
   local types=os.getenv('DF3D_WORKSHOP_DYER_NAV')=='1' and {21} or (os.getenv('DF3D_WORKSHOP_EXTRA_RUNTIME')=='1' and {7,9,14,16,17,18,20} or {7,9,14,16,17,18,20,21})
   local custom_ids={}
   if os.getenv('DF3D_WORKSHOP_CUSTOM_DISCOVERY')=='1'then
    types={23,23,24}
    for _,code in ipairs({'SOAP_MAKER','SCREW_PRESS'})do
     local found
     for _,raw in ipairs(df.global.world.raws.buildings.all)do if raw.code==code then found=raw.id;break end end
     assert(found,'Missing installed custom workshop '..code);custom_ids[#custom_ids+1]=found
    end
   end
   for _,target in ipairs(df.global.world.buildings.all)do
    if df.building_workshopst:is_instance(target) and target:getBuildStage()==target:getMaxBuildStage() and #target.jobs==0 and target.custom_type==-1 then
     local subtype=types[#workshop_fixtures+1]
     workshop_fixtures[#workshop_fixtures+1]={building=target,prior_type=target.type,prior_custom=target.custom_type,prior_stage=target.construction_stage,id=target.id,fixture_type=subtype}
     workshop_fixture_ids[target.id]=true;target.type=subtype
     if subtype==23 then target.custom_type=custom_ids[#workshop_fixtures]end
     target.construction_stage=target:getMaxBuildStage()
     if #workshop_fixtures==#types then break end
    end
   end
   assert(#workshop_fixtures==#types,'Extra discovery has insufficient idle completed workshops')
   result.workshop_fixtures={}
   for _,entry in ipairs(workshop_fixtures)do result.workshop_fixtures[#result.workshop_fixtures+1]={id=entry.id,prior_type=entry.prior_type,prior_stage=entry.prior_stage,fixture_type=entry.fixture_type,fixture_stage=entry.building.construction_stage}end
  end
  result.task_catalogs={};local seen={}
  for _,target in ipairs(df.global.world.buildings.all)do
   local type=target:getType();local key=type..':'..target:getSubtype()..':'..target:getCustomType()
   if (os.getenv('DF3D_WORKSHOP_EXTRA_DISCOVERY')~='1' or workshop_fixture_ids[target.id]) and (type==df.building_type.Workshop or type==df.building_type.Furnace)and (os.getenv('DF3D_WORKSHOP_STONE_NAV')~='1' or key=='13:2:-1') and not seen[key]and target:getBuildStage()==target:getMaxBuildStage() and (os.getenv('DF3D_WORKSHOP_FURNACE_DISCOVERY')~='1' or (os.getenv('DF3D_WORKSHOP_MAGMA_TYPE') and key=='5:'..os.getenv('DF3D_WORKSHOP_MAGMA_TYPE')..':-1') or (not os.getenv('DF3D_WORKSHOP_MAGMA_TYPE') and (key=='5:2:-1' or key=='5:3:-1'))) and (os.getenv('DF3D_WORKSHOP_CRAFT_NAV')~='1' or key=='13:3:-1') and (os.getenv('DF3D_WORKSHOP_GLASS_RUNTIME')~='1' or key=='5:2:-1' or key=='5:5:-1') and (os.getenv('DF3D_WORKSHOP_CLOTHIER_NAV')~='1' or key=='13:13:-1') and (os.getenv('DF3D_WORKSHOP_FAMILY_RUNTIME')~='1' or os.getenv('DF3D_WORKSHOP_MAGMA_TYPE') or os.getenv('DF3D_WORKSHOP_EXTRA_RUNTIME')=='1' or os.getenv('DF3D_WORKSHOP_CUSTOM_DISCOVERY')=='1' or (os.getenv('DF3D_WORKSHOP_BUTCHER_RUNTIME')=='1' and key=='13:10:-1') or (os.getenv('DF3D_WORKSHOP_MECHANIC_RUNTIME')=='1' and key=='13:8:-1') or (os.getenv('DF3D_WORKSHOP_KILN_RUNTIME')=='1' and key=='5:3:-1') or (os.getenv('DF3D_WORKSHOP_SMELTER_RUNTIME')=='1' and key=='5:1:-1') or (os.getenv('DF3D_WORKSHOP_JEWELER_RUNTIME')=='1' and key=='13:4:-1') or (os.getenv('DF3D_WORKSHOP_LEATHER_RUNTIME')=='1' and key=='13:11:-1') or (os.getenv('DF3D_WORKSHOP_BUTCHER_RUNTIME')~='1' and os.getenv('DF3D_WORKSHOP_MECHANIC_RUNTIME')~='1' and os.getenv('DF3D_WORKSHOP_KILN_RUNTIME')~='1' and os.getenv('DF3D_WORKSHOP_LEATHER_RUNTIME')~='1' and os.getenv('DF3D_WORKSHOP_JEWELER_RUNTIME')~='1' and os.getenv('DF3D_WORKSHOP_SMELTER_RUNTIME')~='1' and (key=='13:1:-1' or key=='13:12:-1' or key=='13:22:-1')))then
    seen[key]=true;select_map(target)
    assert(click_label('Add new task'),'Native task catalog did not open: '..key)
    local function read_rows()
    local rows={}
    for _,button in ipairs(df.global.game.main_interface.building.filtered_button)do
     local row={caption=dfhack.df2utf(utils.call_with_string(button,'text')),type=tostring(button._type)}
     row.leave=button.leave_button
     if df.interface_button_building_new_jobst:is_instance(button)then
      local job=df.reinterpret_cast(df.interface_button_building_new_jobst,button)
      row.job_type=job.jobtype;row.reaction=job.mstring;row.item_type=job.itemtype;row.item_subtype=job.subtype
      row.mat_type=job.material;row.mat_index=job.matgloss;row.material_category=job.job_item_flag.whole
      row.specflag=job.specflag.whole;row.specdata=job.specdata.hist_figure_id
      row.art_type=job.art_specifier;row.art_id=job.art_specifier_id1;row.art_subid=job.art_specifier_id2
      row.available=not job.show_help_instead;row.objection=dfhack.df2utf(job.objection);row.priority=job.list_priority
      if os.getenv('DF3D_WORKSHOP_STONE_NAV')=='1' or os.getenv('DF3D_WORKSHOP_DYER_NAV')=='1'then row.info=dfhack.df2utf(job.info)end
     elseif df.interface_button_building_category_selectorst:is_instance(button)then
      local selector=df.reinterpret_cast(df.interface_button_building_category_selectorst,button)
      row.category=selector.category
     elseif df.interface_button_building_custom_category_selectorst:is_instance(button)then
      row.custom_category=df.reinterpret_cast(df.interface_button_building_custom_category_selectorst,button).custom_category_token
     elseif df.interface_button_building_material_selectorst:is_instance(button)then
      local selector=df.reinterpret_cast(df.interface_button_building_material_selectorst,button)
      row.material=selector.material;row.matgloss=selector.matgloss;row.material_category=selector.job_item_flag.whole
     elseif df.interface_button_building_color_selectorst:is_instance(button)then
      local selector=df.reinterpret_cast(df.interface_button_building_color_selectorst,button)
      row.color=selector.color_index;row.color_job=selector.job
      if os.getenv('DF3D_WORKSHOP_DYER_NAV')=='1'then row.info=dfhack.df2utf(selector.info);row.prepare_interface=selector.prepare_interface end
     end
     if os.getenv('DF3D_WORKSHOP_DYER_NAV')=='1'then
      row.alpha_order=button.alpha_order
      local color=button:get_swatch_color();row.native_swatch=color
      if color and color>=0 then local raw=df.global.world.raws.descriptors.colors[color];row.swatch={red=raw.red,green=raw.green,blue=raw.blue}end
     end
     rows[#rows+1]=row
    end
    return rows
    end
    local rows=read_rows()
    local text,code=dfhack.run_command_silent('df3d','workshop-task-templates-probe',tostring(target.id));assert(code==0,text)
    local catalog={building_id=target.id,kind=key,name=dfhack.df2utf(dfhack.buildings.getName(target)),unpowered=target:isUnpowered(),native=rows,templates=json.decode(text).rows,pages={}}
    result.task_catalogs[#result.task_catalogs+1]=catalog
    if target.id==building.id then shot('task-catalog-carpenter')end
    if os.getenv('DF3D_WORKSHOP_EXTRA_DISCOVERY')=='1'then shot('extra-root-'..target:getSubtype()..(os.getenv('DF3D_WORKSHOP_CUSTOM_DISCOVERY')=='1' and ('-'..target:getCustomType())or ''))end
    if os.getenv('DF3D_WORKSHOP_FAMILY_RUNTIME')=='1'then shot('family-'..target:getSubtype())end
    if os.getenv('DF3D_WORKSHOP_FURNACE_DISCOVERY')=='1'then shot('furnace-root-'..target:getSubtype())end
    -- Discovery only: invoke category buttons, never job/action buttons. Runtime
    -- catalogs must not read these widgets or use their mutable menu storage.
    local pending={{path={},rows=rows,reaction_parent=''}};local next_page=1
    local queue_ids={};for _,job in ipairs(target.jobs)do queue_ids[#queue_ids+1]=job.id end;catalog.queue_ids=queue_ids
    while next_page<=#pending do
     assert(#pending<=512,'Native task category discovery exceeded page bound')
     local page=pending[next_page];next_page=next_page+1
     catalog.pages[#catalog.pages+1]=page
     if os.getenv('DF3D_WORKSHOP_DYER_INGREDIENT_NAV')=='1' and #page.path==2 then
      local first=assert(page.rows[1]);local job=first.job_type
      local target_color=job==243 and first.mat_index or first.specdata
      local encoded,status=dfhack.run_command_silent('df3d','workshop-dye-targets-probe',tostring(target.id),tostring(job),tostring(target_color))
      assert(status==0,encoded);page.owned_ingredients=json.decode(encoded)
      assert(#page.owned_ingredients==#page.rows,'Dyer ingredient count differs')
      local counts=assert(result.dyer_ingredient_counts[target_color+1]);assert(counts.color==target_color)
      assert((job==243 and counts.mix or counts.tint)==#page.rows,'Dyer complete-pair count differs')
      for index,row in ipairs(page.owned_ingredients)do
       local native=page.rows[index]
       assert(row.caption==native.caption and row.info==native.info and row.alpha_order==native.alpha_order and row.color==target_color and not row.tint,'Dyer ingredient row differs at '..index)
      end
      if os.getenv('DF3D_WORKSHOP_DYER_RUNTIME')=='1'then
       gui.simulateInput(view,'LEAVESCREEN');select_map(target);assert(click_label('Add new task'))
       for _,step in ipairs(page.path)do
        local clicked=false
        for scroll=0,128 do
         if click_label(step.caption)then clicked=true;break end
         g.precise_mouse_x=600;g.precise_mouse_y=350;g.mouse_x=75;g.mouse_y=29
         gui.simulateInput(view,'CONTEXT_SCROLL_DOWN');view:render(dfhack.getTickCount())
        end
        assert(clicked,'Dyer effect category unreachable')
       end
       assert(click_label(first.caption));local created=assert(target.jobs[#target.jobs-1])
       assert(#target.jobs==#queue_ids+1,'Dyer native selection must append exactly one job')
       page.effect=family_effect(created);assert(dfhack.job.removeJob(created))
      end
     end
     if os.getenv('DF3D_WORKSHOP_DYER_NAV')=='1' and #page.path==1 then
      local jobs={191,244,190,243};local job=assert(jobs[page.path[1].index])
      local encoded,status=dfhack.run_command_silent('df3d','workshop-dye-targets-probe',tostring(target.id),tostring(job))
      assert(status==0,encoded);page.owned_dye_targets=json.decode(encoded)
      assert(#page.rows==#page.owned_dye_targets,'Dyer target count differs')
      local expected={}
      for _,row in ipairs(page.rows)do
       local tint=row.color~=nil;local color=tint and row.color or row.specdata
       local digits=(row.info or ''):match('At least ([%d,]+)')or '0'
       local count=tonumber((digits:gsub(',','')))
       assert(count~=nil,'Dyer count format needs native-number decoding')
       expected[tostring(tint)..':'..color]={count=count,alpha_order=row.alpha_order}
      end
      for index,row in ipairs(page.owned_dye_targets)do
       assert(row.caption==page.rows[index].caption and row.info==page.rows[index].info,'Dyer target text/order differs at '..index)
       local key=tostring(row.tint)..':'..row.color;local native=assert(expected[key],'Missing native Dyer target '..key)
       assert(native.count==row.available and native.alpha_order==row.alpha_order,'Dyer target availability differs: '..key)
       expected[key]=nil
      end
      assert(next(expected)==nil,'Dyer target provider omitted native choices')
     end
     if (key=='13:5:-1' or key=='13:6:-1') and #page.path==2 and page.path[1].index<=6 then
      local category=page.path[1].index-1;local parent
      for _,candidate in ipairs(catalog.pages)do
       if #candidate.path==1 and candidate.path[1].index==page.path[1].index then parent=candidate;break end
      end
      local material=assert(parent).rows[page.path[2].index].matgloss
      assert(material~=nil,'Forge task path did not select a material')
      local encoded,status=dfhack.run_command_silent('df3d','workshop-forge-choices-probe',tostring(target.id),tostring(category),tostring(material))
      assert(status==0,encoded);page.owned_forge_tasks=json.decode(encoded)
      local native={}
      for _,row in ipairs(page.rows)do if row.job_type then
       local copy={};for _,field in ipairs({'job_type','item_subtype','mat_type','mat_index','material_category','specflag','specdata','art_type','art_id','art_subid','caption'})do copy[field]=row[field]end
       native[#native+1]=copy
      end end
      local comparison=assert(io.open(out..'/workshop-forge-task-comparison.json','w'))
      comparison:write(json.encode({category=category,material=material,native=native,owned=page.owned_forge_tasks}));comparison:close()
      assert(json.encode(native)==json.encode(page.owned_forge_tasks),'Forge task descriptors differ: '..category..'/'..material)
     end
     if page.reaction_parent~=nil and not catalog.unpowered then
      local encoded,status=dfhack.run_command_silent('df3d','workshop-reaction-categories-probe',tostring(target.id),page.reaction_parent)
      assert(status==0,encoded);page.owned_categories=json.decode(encoded)
      local native_categories={};local native_count=0
      for _,row in ipairs(page.rows)do if row.custom_category then native_categories[row.custom_category]=row.caption;native_count=native_count+1 end end
      assert(#page.owned_categories==native_count,'Native reaction category count differs: '..key)
      for _,row in ipairs(page.owned_categories)do assert(native_categories[row.code]==row.caption,'Native reaction category differs: '..row.code)end
      encoded,status=dfhack.run_command_silent('df3d','workshop-reactions-probe',tostring(target.id),page.reaction_parent)
      assert(status==0,encoded);page.owned_reactions=json.decode(encoded)
      local native_reactions={};local reaction_count=0
      for _,row in ipairs(page.rows)do if row.reaction and row.reaction~=''then native_reactions[row.reaction]=row;reaction_count=reaction_count+1 end end
      assert(#page.owned_reactions==reaction_count,'Native reaction choice count differs: '..key)
      for _,row in ipairs(page.owned_reactions)do
       local native=assert(native_reactions[row.code],'Native reaction absent: '..row.code)
       assert(native.caption==row.caption and native.available==row.available and native.objection==row.objection,'Native reaction choice differs: '..row.code)
      end
     end
     if os.getenv('DF3D_WORKSHOP_REACTION_RUNTIME')=='1' and page.reaction_parent and page.reaction_parent~=''then
      local function reopen()
       gui.simulateInput(view,'LEAVESCREEN');select_map(target);assert(click_label('Add new task'))
       for _,step in ipairs(page.path)do assert(click_label(step.caption),'Reaction category unreachable')end
      end
      reopen();shot('reaction-page-'..#catalog.pages)
      assert(click_label('Cancel'),'Reaction Cancel missing')
      shot('reaction-cancel-'..#catalog.pages)
      page.cancel_returns_tasks=false
      for _,line in ipairs(lines())do if line.text:find('Add new task',1,true)then page.cancel_returns_tasks=true end end
      reopen()
      for index,row in ipairs(page.rows)do if row.available and row.reaction and row.reaction~=''then
       assert(click_label(row.caption),'Reaction task unreachable')
       local job=assert(target.jobs[#target.jobs-1]);assert(#target.jobs==#queue_ids+1)
       page.effect={index=index,caption=row.caption,native=family_effect(job)}
       assert(dfhack.job.removeJob(job));break
      end end
     end
     for index,row in ipairs(page.rows)do
      local requested_color=tonumber(os.getenv('DF3D_WORKSHOP_DYER_TARGET')or '')
      local dyer_child=os.getenv('DF3D_WORKSHOP_DYER_INGREDIENT_NAV')=='1' and #page.path==1 and page.path[1].index==tonumber(os.getenv('DF3D_WORKSHOP_DYER_ROOT')or '1') and
       (requested_color and row.color==requested_color or not requested_color and index==1)
      if (os.getenv('DF3D_WORKSHOP_EXTRA_DISCOVERY')~='1' or os.getenv('DF3D_WORKSHOP_CUSTOM_DISCOVERY')=='1' or (os.getenv('DF3D_WORKSHOP_DYER_NAV')=='1' and #page.path==0) or dyer_child) and not row.leave and (row.category~=nil or row.custom_category~=nil or row.material~=nil or row.color~=nil)then
       assert(#page.path<8,'Native task category discovery exceeded depth bound')
       gui.simulateInput(view,'LEAVESCREEN');select_map(target)
       assert(click_label('Add new task'),'Native task catalog did not reopen')
       local path={table.unpack(page.path)};path[#path+1]={index=index,caption=row.caption}
       for _,step in ipairs(path)do
        local button=assert(df.global.game.main_interface.building.filtered_button[step.index-1])
        assert(dfhack.df2utf(utils.call_with_string(button,'text'))==step.caption,'Native task category path changed')
        assert(not df.interface_button_building_new_jobst:is_instance(button),'Category path reached a job')
        local trace=assert(io.open(out..'/workshop-category-progress.json','w'))
        trace:write(json.encode({building_id=target.id,path=path,step=step}));trace:close()
        local clicked=false
        for scroll=0,128 do
         if click_label(step.caption)then clicked=true;break end
         g.precise_mouse_x=600;g.precise_mouse_y=350;g.mouse_x=75;g.mouse_y=29
         gui.simulateInput(view,'CONTEXT_SCROLL_DOWN');view:render(dfhack.getTickCount())
        end
        assert(clicked,'Native category caption not reachable: '..step.caption)
       end
       pending[#pending+1]={path=path,rows=read_rows(),reaction_parent=row.custom_category}
       if os.getenv('DF3D_WORKSHOP_DYER_NAV')=='1'then shot((dyer_child and 'dyer-ingredients-' or 'dyer-page-')..index)end
      end
     end
    end
    if os.getenv('DF3D_WORKSHOP_STONE_NAV')=='1'then
     gui.simulateInput(view,'LEAVESCREEN');select_map(target);assert(click_label('Add new task'))
     shot('stone-root')
     local category
     for _,row in ipairs(rows)do if row.category==7 then category=row;break end end
     assert(category and click_label(category.caption),'Native memorial category missing')
     local child=read_rows();shot('stone-memorials')
     assert(click_label('Cancel'),'Native memorial Cancel missing')
     shot('stone-memorial-cancelled')
     assert(click_label('Add new task'),'Native memorial Cancel did not return to Tasks')
     local returned=read_rows()
     local function semantic(values)
      local copy={};for _,entry in ipairs(values)do local row={};for field,value in pairs(entry)do if field~='item_type'then row[field]=value end end;copy[#copy+1]=row end
      return json.encode(copy)
     end
     assert(semantic(rows)==semantic(returned),'Memorial reopen did not restore root')
     catalog.memorial_navigation={rows=child,cancel_returns_tasks=true,reopen_restores_root=true}
     shot('stone-reopened-root')
     if os.getenv('DF3D_WORKSHOP_STONE_RUNTIME')=='1'then
      catalog.queue_ids=queue_ids;catalog.memorial_navigation.effects={}
      for _,pick in ipairs({1,#child})do
       gui.simulateInput(view,'LEAVESCREEN');select_map(target);assert(click_label('Add new task'))
       assert(click_label(category.caption))
       local clicked=false
       for scroll=0,128 do
        if click_label(child[pick].caption)then clicked=true;break end
        g.precise_mouse_x=600;g.precise_mouse_y=350;g.mouse_x=75;g.mouse_y=29
        gui.simulateInput(view,'CONTEXT_SCROLL_DOWN');view:render(dfhack.getTickCount())
       end
       assert(clicked,'Memorial task unreachable')
       local job=assert(target.jobs[#target.jobs-1]);assert(#target.jobs==#queue_ids+1)
       catalog.memorial_navigation.effects[#catalog.memorial_navigation.effects+1]={index=pick,native=family_effect(job)}
       assert(dfhack.job.removeJob(job));view:render(dfhack.getTickCount())
      end
     end
    end
    if os.getenv('DF3D_WORKSHOP_CLOTHIER_NAV')=='1' or os.getenv('DF3D_WORKSHOP_GLASS_RUNTIME')=='1' or os.getenv('DF3D_WORKSHOP_CRAFT_NAV')=='1'then
     local glass=os.getenv('DF3D_WORKSHOP_GLASS_RUNTIME')=='1'
     local craft=os.getenv('DF3D_WORKSHOP_CRAFT_NAV')=='1'
     local prefix=craft and 'craft' or glass and 'glass' or 'clothier'
     local function semantic_rows(values)
      local copy={};for _,entry in ipairs(values)do local row={};for field,value in pairs(entry)do if field~='item_type'then row[field]=value end end;copy[#copy+1]=row end
      return json.encode(copy)
     end
     catalog.navigation={}
     gui.simulateInput(view,'LEAVESCREEN');select_map(target);assert(click_label('Add new task'))
     shot(prefix..'-root')
     for index,root_row in ipairs(rows)do if (not glass and not craft) or root_row.material~=nil then
      assert(click_label(root_row.caption),'Clothier fabric selection failed')
      local child=read_rows();shot(prefix..'-page-'..index)
      assert(click_label('Back'),'Clothier Back missing')
      local returned=read_rows();assert(semantic_rows(returned)==semantic_rows(rows),'Clothier Back did not restore root')
      catalog.navigation[#catalog.navigation+1]={fabric=glass and root_row.material or root_row.material_category,caption=root_row.caption,rows=child,back_restored_root=true}
      if craft_tool_fixture and root_row.material_category==32 then
       local selected
       for _,row in ipairs(child)do if row.job_type==216 and row.item_subtype==craft_tool_fixture.id then selected=row;break end end
       assert(selected,'Controlled bone tool missing from native page')
       result.craft_bone_tool.row=selected
       assert(selected.material_category==2,'Native bone tool does not use the suspected wood category')
       assert(click_label(root_row.caption))
       local clicked=false
       for scroll=0,128 do
        if click_label(selected.caption)then clicked=true;break end
        g.precise_mouse_x=600;g.precise_mouse_y=350;g.mouse_x=75;g.mouse_y=29
        gui.simulateInput(view,'CONTEXT_SCROLL_DOWN');view:render(dfhack.getTickCount())
       end
       assert(clicked,'Controlled bone tool not reachable')
       local job=assert(target.jobs[#target.jobs-1]);assert(#target.jobs==#queue_ids+1)
       result.craft_bone_tool.effect=family_effect(job)
       assert(job.material_category.whole==2,'Bone tool job did not retain wood category')
       assert(dfhack.job.removeJob(job));view:render(dfhack.getTickCount());assert(click_label('Add new task'))
      end
      if os.getenv('DF3D_WORKSHOP_CLOTHIER_RUNTIME')=='1' or glass or os.getenv('DF3D_WORKSHOP_CRAFT_RUNTIME')=='1'then
       local nav=catalog.navigation[#catalog.navigation];nav.effects={}
       for _,pick in ipairs({1,#child})do
        assert(click_label(root_row.caption))
        local clicked=false
        for scroll=0,128 do
         if click_label(child[pick].caption)then clicked=true;break end
         g.precise_mouse_x=600;g.precise_mouse_y=350;g.mouse_x=75;g.mouse_y=29
         gui.simulateInput(view,'CONTEXT_SCROLL_DOWN');view:render(dfhack.getTickCount())
        end
        assert(clicked,'Clothier task unreachable')
        local job=assert(target.jobs[#target.jobs-1]);assert(#target.jobs==#queue_ids+1)
        nav.effects[#nav.effects+1]={index=pick,caption=child[pick].caption,native=family_effect(job)}
        assert(dfhack.job.removeJob(job));view:render(dfhack.getTickCount());assert(click_label('Add new task'))
        nav.reopened=read_rows();shot(prefix..'-reopened-'..index..'-'..pick)
        if semantic_rows(nav.reopened)~=semantic_rows(rows)then assert(click_label('Back'),'Reopened clothier page has no Back')end
       end
      end
     end end
     if craft and os.getenv('DF3D_WORKSHOP_CRAFT_RUNTIME')=='1'then
      for index,row in ipairs(rows)do if row.available and row.job_type and row.job_type~=209 then
       assert(click_label(row.caption));local job=assert(target.jobs[#target.jobs-1]);assert(#target.jobs==#queue_ids+1)
       catalog.root_effect={index=index,caption=row.caption,native=family_effect(job)}
       assert(dfhack.job.removeJob(job));view:render(dfhack.getTickCount());assert(click_label('Add new task'));break
      end end
     end
     shot(prefix..'-back-root')
    end
    if os.getenv('DF3D_WORKSHOP_FURNACE_DISCOVERY')=='1' and os.getenv('DF3D_WORKSHOP_GLASS_RUNTIME')~='1'then
     catalog.navigation={}
     gui.simulateInput(view,'LEAVESCREEN');select_map(target);assert(click_label('Add new task'))
     for index,row in ipairs(rows)do if row.material~=nil then
      assert(click_label(row.caption));local child=read_rows();shot('furnace-'..target:getSubtype()..'-page-'..index)
      assert(click_label('Back'),'Furnace material Back missing')
      local returned=read_rows()
      local function semantic_rows(values)
       local copy={};for _,entry in ipairs(values)do local row={};for field,value in pairs(entry)do if field~='item_type'then row[field]=value end end;copy[#copy+1]=row end
       return copy
      end
      local comparison=assert(io.open(out..'/furnace-back-comparison.json','w'));comparison:write(json.encode({before=rows,after=returned}));comparison:close()
      assert(json.encode(semantic_rows(returned))==json.encode(semantic_rows(rows)),'Furnace Back changed root')
      catalog.navigation[#catalog.navigation+1]={material=row.material,rows=child,back_restored_root=true}
     end end
    end
    assert(#target.jobs==#queue_ids,'Category discovery changed workshop queue')
    for i,id in ipairs(queue_ids)do assert(target.jobs[i-1].id==id,'Category discovery reordered workshop queue')end
    if os.getenv('DF3D_WORKSHOP_CUSTOM_SUPPLIES')=='1' and target:getSubtype()==23 then
     assert(#rows==(target.custom_type==0 and 2 or 4),'Custom stocked catalog count changed')
     for _,row in ipairs(rows)do assert(row.available,'Stocked custom reaction unavailable: '..row.caption)end
    end
    if os.getenv('DF3D_WORKSHOP_FAMILY_RUNTIME')=='1'then
     catalog.effects={};catalog.queue_ids=queue_ids;local effect_types={};local available_index=0
     for index,row in ipairs(rows)do
      if row.available then available_index=available_index+1 end
      local magma_batch=tonumber(os.getenv('DF3D_WORKSHOP_MAGMA_BATCH')or '0')
      local magma_in_batch=not os.getenv('DF3D_WORKSHOP_MAGMA_TYPE') or math.floor((available_index-1)/10)==magma_batch
      local jeweler_batch=tonumber(os.getenv('DF3D_WORKSHOP_JEWELER_BATCH')or '0')
      local in_batch=os.getenv('DF3D_WORKSHOP_JEWELER_RUNTIME')~='1' or (jeweler_batch==0 and index<=10) or (jeweler_batch==1 and index>10)
      if row.available and in_batch and magma_in_batch and (os.getenv('DF3D_WORKSHOP_EXTRA_RUNTIME')~='1' or not effect_types[tostring(row.job_type)..':'..tostring(row.material_category)]) and (os.getenv('DF3D_WORKSHOP_SMELTER_RUNTIME')~='1' or row.job_type~=209 or not effect_types[209]) and (os.getenv('DF3D_WORKSHOP_LEATHER_RUNTIME')~='1' or (#catalog.effects<8 and not effect_types[row.job_type])) then
      effect_types[row.job_type]=true;effect_types[tostring(row.job_type)..':'..tostring(row.material_category)]=true
      gui.simulateInput(view,'LEAVESCREEN');select_map(target);assert(click_label('Add new task'))
      local clicked=false
      for scroll=0,128 do
       if click_label(row.caption)then clicked=true;break end
       g.precise_mouse_x=600;g.precise_mouse_y=350;g.mouse_x=75;g.mouse_y=29
       gui.simulateInput(view,'CONTEXT_SCROLL_DOWN');view:render(dfhack.getTickCount())
      end
      assert(clicked,'Family native task unavailable')
      local job=assert(target.jobs[#target.jobs-1]);assert(#target.jobs==#queue_ids+1,'Native task did not append a job')
      catalog.effects[#catalog.effects+1]={index=index,caption=row.caption,native=family_effect(job)}
      assert(dfhack.job.removeJob(job))
     end end
    end
    local saved=assert(io.open(out..'/workshop-native.json','w'));saved:write(json.encode(result));saved:close()
    gui.simulateInput(view,'LEAVESCREEN')
   end
  end
  if os.getenv('DF3D_WORKSHOP_EXTRA_DISCOVERY')=='1'then assert(#result.task_catalogs==(os.getenv('DF3D_WORKSHOP_CUSTOM_DISCOVERY')=='1' and 3 or os.getenv('DF3D_WORKSHOP_DYER_NAV')=='1' and 1 or (os.getenv('DF3D_WORKSHOP_EXTRA_RUNTIME')=='1' and 7 or 8)),'Missing extra-family root catalog')end
  shot('task-catalog-return')
  if os.getenv('DF3D_WORKSHOP_DYER_RUNTIME')=='1'then
   capture('workshop-wire')
   local file=assert(io.open(out..'/workshop-wire-result.json'));local receipt=json.decode(file:read('*a'));file:close();assert(receipt.success)
   for _,catalog in ipairs(result.task_catalogs)do
    local target=assert(df.building.find(catalog.building_id))
    for index,page in ipairs(catalog.pages)do if page.effect then
     local id=assert(receipt.created[tostring(index)]);local job
     for _,candidate in ipairs(target.jobs)do if candidate.id==id then job=candidate;break end end
     assert(job and #target.jobs==#catalog.queue_ids+1,'Dyer viewer must append exactly one job')
     page.viewer_effect=family_effect(job);assert(json.encode(page.effect)==json.encode(page.viewer_effect),'Dyer job effect differs')
     assert(dfhack.job.removeJob(job))
    end end
    assert(#target.jobs==#catalog.queue_ids)
    for i,id in ipairs(catalog.queue_ids)do assert(target.jobs[i-1].id==id)end
   end
  end
  if os.getenv('DF3D_WORKSHOP_STONE_RUNTIME')=='1'then
   capture('workshop-wire')
   local file=assert(io.open(out..'/workshop-wire-result.json'));local receipt=json.decode(file:read('*a'));file:close();assert(receipt.success)
   for _,catalog in ipairs(result.task_catalogs)do
    local target=assert(df.building.find(catalog.building_id))
    for _,entry in ipairs(catalog.memorial_navigation.effects)do
     local id=assert(receipt.created[tostring(entry.index)]);local job
     for _,candidate in ipairs(target.jobs)do if candidate.id==id then job=candidate;break end end
     assert(job and json.encode(entry.native)==json.encode(family_effect(job)),'Memorial job effect differs')
     assert(dfhack.job.removeJob(job))
    end
    assert(#target.jobs==#catalog.queue_ids)
    for i,id in ipairs(catalog.queue_ids)do assert(target.jobs[i-1].id==id)end
   end
  end
  if os.getenv('DF3D_WORKSHOP_REACTION_RUNTIME')=='1'then
   capture('workshop-wire')
   local file=assert(io.open(out..'/workshop-wire-result.json'));local receipt=json.decode(file:read('*a'));file:close();assert(receipt.success)
   for _,catalog in ipairs(result.task_catalogs)do
    local target=assert(df.building.find(catalog.building_id))
    for index,page in ipairs(catalog.pages)do if page.effect then
     local id=assert(receipt.created[tostring(catalog.building_id)..':'..index]);local job
     for _,candidate in ipairs(target.jobs)do if candidate.id==id then job=candidate;break end end
     assert(job);page.effect.viewer=family_effect(job)
     assert(json.encode(page.effect.native)==json.encode(page.effect.viewer),'Reaction category job effects differ')
     assert(dfhack.job.removeJob(job))
    end end
    assert(#target.jobs==#catalog.queue_ids)
    for index,id in ipairs(catalog.queue_ids)do assert(target.jobs[index-1].id==id)end
   end
   shot('reaction-effects-return')
  end
  if os.getenv('DF3D_WORKSHOP_CLOTHIER_RUNTIME')=='1' or os.getenv('DF3D_WORKSHOP_GLASS_RUNTIME')=='1' or os.getenv('DF3D_WORKSHOP_CRAFT_RUNTIME')=='1'then
   capture('workshop-wire')
   local file=assert(io.open(out..'/workshop-wire-result.json'));local receipt=json.decode(file:read('*a'));file:close();assert(receipt.success)
   for _,catalog in ipairs(result.task_catalogs)do
    local target=assert(df.building.find(catalog.building_id))
    for _,nav in ipairs(catalog.navigation)do for _,entry in ipairs(nav.effects)do
     local id=assert(receipt.created[tostring(nav.fabric)..':'..entry.index]);local job
     for _,candidate in ipairs(target.jobs)do if candidate.id==id then job=candidate;break end end
     assert(job);entry.viewer=family_effect(job);assert(json.encode(entry.native)==json.encode(entry.viewer),'Clothier task effect differs')
     assert(dfhack.job.removeJob(job))
    end end
    if catalog.root_effect then
     local id=assert(receipt.created['root:'..catalog.root_effect.index]);local job
     for _,candidate in ipairs(target.jobs)do if candidate.id==id then job=candidate;break end end
     assert(job and json.encode(catalog.root_effect.native)==json.encode(family_effect(job)),'Craft root task effect differs')
     assert(dfhack.job.removeJob(job))
    end
    assert(#target.jobs==#catalog.queue_ids)
    for i,id in ipairs(catalog.queue_ids)do assert(target.jobs[i-1].id==id)end
   end
  end
  if os.getenv('DF3D_WORKSHOP_FAMILY_RUNTIME')=='1'then
   capture('workshop-wire')
   local file=assert(io.open(out..'/workshop-wire-result.json'));local receipt=json.decode(file:read('*a'));file:close();assert(receipt.success)
   for _,catalog in ipairs(result.task_catalogs)do
    local target=assert(df.building.find(catalog.building_id))
    for _,entry in ipairs(catalog.effects)do
     local id=assert(receipt.created[tostring(catalog.building_id)..':'..entry.index]);local job
     for _,candidate in ipairs(target.jobs)do if candidate.id==id then job=candidate;break end end
     assert(job,'Family job missing from target workshop')
     entry.viewer=family_effect(job)
     if json.encode(entry.native)~=json.encode(entry.viewer)then
      local difference=assert(io.open(out..'/family-effect-mismatch.json','w'));difference:write(json.encode(entry));difference:close()
     end
     assert(json.encode(entry.native)==json.encode(entry.viewer),'Family job effects differ: '..entry.caption)
     assert(dfhack.job.removeJob(job))
    end
    assert(#target.jobs==#catalog.queue_ids,'Family checks changed original queue')
    for i,id in ipairs(catalog.queue_ids)do assert(target.jobs[i-1].id==id,'Family checks reordered original queue')end
   end
   shot('family-effects-return')
  end
  return
 end
 if os.getenv('DF3D_WORKSHOP_JOB_CONTROLS')=='1'then
  assert(click_label('Add new task'))
  local task_choices={};local utils=require('utils')
  for _,button in ipairs(df.global.game.main_interface.building.filtered_button)do
   if df.interface_button_building_new_jobst:is_instance(button)then
    local job=df.reinterpret_cast(df.interface_button_building_new_jobst,button)
    task_choices[#task_choices+1]={name=dfhack.df2utf(utils.call_with_string(button,'text')),available=not job.show_help_instead,objection=dfhack.df2utf(job.objection)}
   end
  end
  local function variant_effect(job)
   local inputs={}
   for _,item in ipairs(job.job_items.elements)do
    inputs[#inputs+1]={item_type=item.item_type,item_subtype=item.item_subtype,mat_type=item.mat_type,mat_index=item.mat_index,
     quantity=item.quantity,flags1=item.flags1.whole,flags2=item.flags2.whole,flags3=item.flags3.whole}
   end
   return {job_type=job.job_type,reaction_name=job.reaction_name,item_subtype=job.item_subtype,mat_type=job.mat_type,mat_index=job.mat_index,material_category=job.material_category.whole,inputs=inputs}
  end
  assert(click_label('Make instrument piece'))
  local category_reference={key='reaction:'..df.global.game.main_interface.building.current_custom_category_token,rows={}}
  for _,button in ipairs(df.global.game.main_interface.building.filtered_button)do
   local job=df.reinterpret_cast(df.interface_button_building_new_jobst,button)
   category_reference.rows[#category_reference.rows+1]={name=dfhack.df2utf(utils.call_with_string(button,'text')),available=not job.show_help_instead,objection=dfhack.df2utf(job.objection)}
  end
  shot('task-category-child');assert(click_label('Cancel'));assert(click_label('Add new task'));shot('task-category-root')
  assert(click_label('Make instrument piece'));assert(category_reference.rows[1].available,'Category fixture needs available logs')
  assert(click_label(category_reference.rows[1].name))
  local category_job=assert(building.jobs[#building.jobs-1]);category_reference.effect=variant_effect(category_job)
  assert(dfhack.job.removeJob(category_job));select_map(building);assert(click_label('Add new task'))
  assert(click_label('Make menacing wooden spike'))
  local variant=assert(building.jobs[#building.jobs-1]);local variant_reference=variant_effect(variant)
  assert(dfhack.job.removeJob(variant));select_map(building)
  assert(click_label('Add new task'));assert(click_label('Make bed'))
  local created=assert(building.jobs[#building.jobs-1]);assert(#building.jobs==#jobs+1)
  local function click(x,y)
   df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
   g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=math.floor(x/8);g.mouse_y=math.floor(y/12)
   df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
   df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
  end
  local function snapshot()
   local queue={};for _,job in ipairs(building.jobs)do queue[#queue+1]=job.id end
   return {id=created.id,flags=created.flags.whole,do_now=created.flags.do_now,suspended=created.flags.suspend,repeat_job=created.flags['repeat'],queue=queue}
  end
  local worked,problem=xpcall(function()
   local priority_worker
   result.job_controls={building_id=building.id,job_id=created.id,before=snapshot(),task_choices=task_choices,variant_reference=variant_reference,category_reference=category_reference}
   shot('job-controls-before')
   click(772,154);result.job_controls.priority_on=snapshot();shot('job-priority-on')
   assert(created.flags.do_now,'Native Priority did not set do_now')
   click(772,154);result.job_controls.priority_off=snapshot();shot('job-priority-off')
   assert(not created.flags.do_now,'Native Priority did not clear do_now')
   -- Exercise queue interactions before selecting Details on the original job.
   local extra={}
   local queue_ok,queue_problem=xpcall(function()
    for _,unit in ipairs(df.global.world.units.active)do
     if not unit.flags1.inactive and not unit.job.current_job and dfhack.units.isCitizen(unit)then priority_worker=unit;break end
    end
    assert(priority_worker,'Priority reference needs an idle citizen')
    assert(dfhack.job.addWorker(created,priority_worker))
    result.job_controls.priority_worker_id=priority_worker.id
    for i=1,2 do
     assert(click_label('Add new task'));assert(click_label('Make bed'))
     extra[#extra+1]=assert(building.jobs[#building.jobs-1])
    end
    local function queue_snapshot()
     local rows={}
     for _,job in ipairs(building.jobs)do local worker=dfhack.job.getWorker(job);rows[#rows+1]={id=job.id,flags=job.flags.whole,do_now=job.flags.do_now,worker_id=worker and worker.id or -1}end
     return rows
    end
    local moves={{name='before',rows=queue_snapshot()}}
    for _,step in ipairs{{'middle-up',extra[1].id},{'first-no-op',extra[1].id},{'last-up',extra[2].id},{'original-up',created.id},{'original-first',created.id}}do
     local index
     for i,job in ipairs(building.jobs)do if job.id==step[2]then index=i;break end end
     assert(index,'Move-up target left queue')
     click(796,154+index*36);moves[#moves+1]={name=step[1],target=step[2],rows=queue_snapshot()}
     if step[1]=='middle-up'then shot('job-move-up-middle')end
    end
    assert(json.encode(moves[1].rows)==json.encode(moves[#moves].rows),'Move-up did not restore queue, flags and workers')
    assert(json.encode(moves[2].rows)==json.encode(moves[3].rows),'Move-up changed the first row')
    assert(moves[2].rows[1].id==extra[1].id and moves[2].rows[2].id==created.id,'Move-up did not swap adjacent jobs')
    assert(priority_worker.job.current_job==created and dfhack.job.getWorker(created)==priority_worker,'Move-up released the displaced worker')
    result.job_controls.move_up=moves
    shot('job-move-up-restored')
    local samples={{name='before',rows=queue_snapshot()}}
    for _,step in ipairs{{'middle-on',extra[1].id},{'original-on',created.id},{'last-on',extra[2].id},{'middle-off',extra[1].id},{'original-off',created.id},{'last-off',extra[2].id}}do
     local index
     for i,job in ipairs(building.jobs)do if job.id==step[2]then index=i;break end end
     assert(index,'Priority target left queue')
     click(772,154+index*36);samples[#samples+1]={name=step[1],target=step[2],rows=queue_snapshot()}
     if step[1]=='middle-on'then shot('job-priority-middle-on')end
    end
    result.job_controls.priority_queue=samples
    assert(not priority_worker.job.current_job and not dfhack.job.getWorker(created),'Native Priority did not release displaced worker')
    local _,job_address=df.sizeof(created);local _,flags_address=df.sizeof(created.flags)
    result.job_controls.flags_offset=flags_address-job_address
    shot('job-priority-queue-restored')
   end,debug.traceback)
   for _,job in ipairs(extra)do assert(dfhack.job.removeJob(job),'Priority queue cleanup failed')end
   assert(queue_ok,queue_problem)
   select_map(building)
   click(820,154)
   local details=df.global.game.main_interface.job_details
   assert(details.open and details.jb==created,'Native workshop Details did not target created task')
   local options={};for i,kind in ipairs(details.option)do options[#options+1]={kind=kind,index=details.option_index[i]}end
   local materials={};for i,kind in ipairs(details.material)do materials[#materials+1]={type=kind,index=details.matgloss[i],count=details.material_count[i]}end
   result.job_controls.details={context=details.context,current_option=details.current_option,current_index=details.current_option_index,options=options,materials=materials}
   shot('job-details')
   local function material_effect()
    local item=assert(created.job_items.elements[0])
    return {mat_type=created.mat_type,mat_index=created.mat_index,flags=created.flags.whole,
     item_type=item.mat_type,item_index=item.mat_index,item_flags1=item.flags1.whole,item_flags2=item.flags2.whole,item_flags3=item.flags3.whole,
     details_flags=item.job_details_flags.whole,details_type=item.job_details_mat_type,details_index=item.job_details_mat_index,details_item_flags2=item.job_details_item_flags2.whole}
   end
   click(100,190);assert(not details.open,'Native material selection did not return to workshop')
   result.job_controls.material_effect=material_effect();shot('job-details-return')
   assert(dfhack.job.removeJob(created));created=nil
   select_map(building);assert(click_label('Add new task'));assert(click_label('Make bed'))
   created=assert(building.jobs[#building.jobs-1]);result.job_controls.viewer_job_id=created.id
   assert(dfhack.job.addWorker(created,priority_worker))
   shot('job-viewer-before');capture('workshop-wire')
   assert(not priority_worker.job.current_job and not dfhack.job.getWorker(created),'Viewer Priority did not release displaced worker')
   assert(json.encode(material_effect())==json.encode(result.job_controls.material_effect),'Viewer material edit differs from native job/input effect')
   local wire_file=assert(io.open(out..'/workshop-wire-result.json'));local wire=json.decode(wire_file:read('*a'));wire_file:close()
   local viewer_variant
   for _,job in ipairs(building.jobs)do if job.id==wire.variant_id then viewer_variant=job;break end end
   assert(viewer_variant,'Viewer variant job missing')
   assert(dfhack.job.getHolder(viewer_variant)==building,'Viewer variant holder differs')
   local actual_variant=variant_effect(viewer_variant)
   local comparison=assert(io.open(out..'/workshop-variant-comparison.json','w'));comparison:write(json.encode({native=variant_reference,viewer=actual_variant}));comparison:close()
   assert(dfhack.job.removeJob(viewer_variant))
   assert(json.encode(actual_variant)==json.encode(variant_reference),'Viewer task variant/input effects differ')
   result.job_controls.viewer_variant_effect=actual_variant
   local viewer_category
   for _,job in ipairs(building.jobs)do if job.id==wire.category_job_id then viewer_category=job;break end end
   assert(viewer_category,'Viewer category job missing')
   local category_effect=variant_effect(viewer_category);assert(dfhack.job.removeJob(viewer_category))
   local category_comparison=assert(io.open(out..'/workshop-category-comparison.json','w'));category_comparison:write(json.encode({native=category_reference.effect,viewer=category_effect}));category_comparison:close()
   assert(json.encode(category_effect)==json.encode(category_reference.effect),'Viewer category job/input effects differ')
   result.job_controls.viewer_category_effect=category_effect
   result.job_controls.viewer_material_effect=material_effect();shot('job-viewer-after')
  end,debug.traceback)
  if df.global.game.main_interface.job_details.open then gui.simulateInput(view,'LEAVESCREEN')end
  assert(dfhack.job.removeJob(created),'Diagnostic job cleanup failed')
  assert(worked,problem)
  return
 end
 assert(click_label('Workers'),'Native Workers tab not found')
 shot('workers')
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=448;g.precise_mouse_y=154;g.mouse_x=56;g.mouse_y=12
 df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
 shot('worker-selector')
 result.worker_candidates_reference=read_worker_reference(building)
 if os.getenv('DF3D_WORKSHOP_SELECTOR_LAYOUT')=='1'then
  result.selector_layout={}
  for _,size in ipairs{'small','wide','default'}do
   resize_worker(size)
   local geometry={};worker_geometry(df.global.game.main_interface.unit_selector,geometry,0)
   result.selector_layout[#result.selector_layout+1]={size=size,dimx=g.dimx,dimy=g.dimy,geometry=geometry}
   shot('selector-layout-'..size)
  end
  gui.simulateInput(view,'LEAVESCREEN');capture('workshop-wire');return
 end
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());select_map(building)
 assert(click_label('Work orders'),'Native Work orders tab not found')
 shot('work-orders')
 local limit_before=building:getWorkshopProfile().max_general_orders
 local function order_click(x)
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
  g.precise_mouse_x=x;g.precise_mouse_y=478;g.mouse_x=math.floor(x/8);g.mouse_y=39
  df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
  df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
 end
 assert(limit_before>=0 and limit_before<99,'Reference needs a reversible general-order increment')
 order_click(840);assert(building:getWorkshopProfile().max_general_orders==limit_before+1,'Native general-order increase failed')
 order_click(872);assert(building:getWorkshopProfile().max_general_orders==limit_before,'Native general-order decrease failed')
 result.general_order_steps={before=limit_before,increased=limit_before+1,restored=limit_before}
 -- Numeric entry applies each changed draft; SELECT only ends editing.
 order_click(808)
 local numeric={}
 local function number_key(key)
  gui.simulateInput(view,key);view:render(dfhack.getTickCount())
  numeric[#numeric+1]={key=key,draft=sheet.gen_work_order_num_str,editing=sheet.entering_gen_work_order_num,value=building:getWorkshopProfile().max_general_orders}
 end
 assert(sheet.entering_gen_work_order_num and sheet.gen_work_order_num_str=='','Native number editor did not start empty')
 number_key('STRING_A049');assert(building:getWorkshopProfile().max_general_orders==1,'Native first digit did not apply')
 number_key('STRING_A050');assert(building:getWorkshopProfile().max_general_orders==12,'Native second digit did not apply')
 number_key('SELECT');assert(not sheet.entering_gen_work_order_num,'Native number Enter did not release editing')
 order_click(808)
 for digit in tostring(limit_before):gmatch('.')do number_key(('STRING_A%03d'):format(digit:byte()))end
 number_key('SELECT');assert(building:getWorkshopProfile().max_general_orders==limit_before,'Native number editor failed to restore limit')
 result.general_order_numeric=numeric
 assert(click_label('Tasks'),'Native Tasks tab not found')
 assert(click_label('Add new task'),'Native Add new task control not found')
 shot('add-task')
 assert(click_label('Make bed'),'Native Make bed choice not found')
 assert(#building.jobs==#jobs+1,'Native Make bed did not create a task')
 local created=building.jobs[#building.jobs-1]
 shot('queued')
 local text,code=dfhack.run_command_silent('df3d','workshop-requirements-probe',tostring(building.id),tostring(created.id))
 local removed=dfhack.job.removeJob(created)
 assert(removed,'Native reference task cleanup failed')
 assert(code==0,text)
 result.requirements_reference=json.decode(text)
 assert(result.requirements_reference.caption=='Make bed','Native task caption differs from visible picker')
 shot('restored')
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
 local still
 for _,candidate in ipairs(df.global.world.buildings.other.WORKSHOP_ANY)do
  if df.building_workshopst:is_instance(candidate) and candidate.type==df.workshop_type.Still and candidate:getBuildStage()==candidate:getMaxBuildStage()then still=candidate;break end
 end
 assert(still,'Workshop reference needs a completed Still')
 select_map(still)
 assert(sheet.active_id==still.id,'Native Still selection missed')
 local order_text,order_code=dfhack.run_command_silent('df3d','workshop-orders-probe',tostring(still.id))
 assert(order_code==0,order_text);result.still_orders_reference=json.decode(order_text)
 assert(result.still_orders_reference.general_order_limit==still:getWorkshopProfile().max_general_orders,'Order limit reader differs')
 assert(result.still_orders_reference.manager_available==(#df.global.plotinfo.main.fortress_entity.assignments_by_type[df.entity_position_responsibility.MANAGE_PRODUCTION]>0),'Manager prerequisite reader differs')
 local expected_orders={};for _,order in ipairs(df.global.world.manager_orders.all)do if order.workshop_id==still.id then expected_orders[#expected_orders+1]=order.id end end
 assert(json.encode(result.still_orders_reference.order_ids)==json.encode(expected_orders),'Workshop order membership differs')
 assert(click_label('Workers'),'Native Still Workers tab not found')
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=448;g.precise_mouse_y=154;g.mouse_x=56;g.mouse_y=12
 df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
 shot('still-worker-selector')
 result.still_worker_reference=read_worker_reference(still)
 resize_worker('small')
 result.small_worker_reference=read_worker_reference(still)
 shot('still-worker-selector-small')
 resize_worker('default')
 -- Observe the assigned row through native input, then restore the restriction.
 local function worker_click(x,y)
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
  g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=math.floor(x/8);g.mouse_y=math.floor(y/12)
  df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
  df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
 end
 local profile=still:getWorkshopProfile()
 assert(#profile.permitted_workers==0,'Native worker reference must start unrestricted')
 worker_click(80,106)
 assert(#profile.permitted_workers==1,'Native worker click did not assign')
 result.assigned_worker_reference={building_id=still.id,unit_id=profile.permitted_workers[0]}
 shot('still-worker-assigned')
 local assigned=df.unit.find(profile.permitted_workers[0]);local specialized=assigned.flags4.only_do_assigned_jobs
 local text,code=dfhack.run_command_silent('df3d','workshop-workers-probe',tostring(still.id))
 assert(code==0,text);result.assigned_worker_reference.semantic=json.decode(text).assigned
 worker_click(448,250)
 assert(assigned.flags4.only_do_assigned_jobs~=specialized,'Native workshop specialization did not toggle')
 shot('still-worker-specialized')
 worker_click(448,250)
 assert(assigned.flags4.only_do_assigned_jobs==specialized,'Native workshop specialization did not restore')
 worker_click(448,190)
 result.assigned_worker_selector=read_worker_reference(still)
 shot('still-worker-selector-assigned')
 worker_click(80,106)
 assert(#profile.permitted_workers==0,'Native worker reselect did not restore unrestricted profile')
 shot('still-workers-restored')
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());select_map(still)
 assert(click_label('Tasks'),'Native Still Tasks tab not found')
 shot('still-jobs')
 assert(click_label('Add new task'),'Native Still picker did not open')
 local rows={};local utils=require('utils')
 for _,button in ipairs(df.global.game.main_interface.building.button)do
  if df.interface_button_building_new_jobst:is_instance(button) and button.jobtype==df.job_type.CustomReaction then
   local raw_index=-1;for index,reaction in ipairs(df.global.world.raws.reactions.reactions)do if reaction.code==button.mstring then raw_index=index;break end end
   rows[#rows+1]={raw_index=raw_index,code=dfhack.df2utf(button.mstring),caption=dfhack.df2utf(utils.call_with_string(button,'text')),
    objection=dfhack.df2utf(button.objection),available=not button.show_help_instead}
  end
 end
 local tasks={}
 for _,button in ipairs(df.global.game.main_interface.building.filtered_button)do
  assert(df.interface_button_building_new_jobst:is_instance(button),'Unexpected Still task category')
  local key=button.jobtype==df.job_type.CustomReaction and 'reaction:'..dfhack.df2utf(button.mstring) or 'builtin:'..button.jobtype..':'..button.material
  tasks[#tasks+1]={key=key,name=dfhack.df2utf(utils.call_with_string(button,'text')),availability={available=not button.show_help_instead,objection=dfhack.df2utf(button.objection)}}
  assert(button.list_priority==1000 and button.alpha_order==0,'Still ordering metadata changed')
 end
 result.task_reference={building_id=still.id,rows=tasks}
 local order=function(a,b)return a.code<b.code end;table.sort(rows,order)
 local permission_text,permission_code=dfhack.run_command_silent('df3d','workshop-reactions-probe',tostring(still.id))
 assert(permission_code==0,permission_text)
 local actual=json.decode(permission_text);table.sort(actual,order)
 assert(#rows>0 and #rows==#actual,'Native Still reaction membership differs')
 for i,row in ipairs(rows)do for key,value in pairs(row)do assert(actual[i][key]==value,'Native Still '..row.code..' '..key..' differs: '..tostring(actual[i][key])..' ~= '..tostring(value))end end
 local codes={};for _,row in ipairs(rows)do codes[#codes+1]=row.code end
 result.reaction_reference={building_id=still.id,codes=codes,rows=rows,all_equal=true}
 local contents={};for _,held in ipairs(still.contained_items)do contents[#contents+1]={id=held.item.id,role=held.use_mode}end
 result.sheet_reference={id=still.id,type=still:getType(),stage=still:getBuildStage(),max_stage=still:getMaxBuildStage(),custom_name=dfhack.df2utf(still.name),native_name=dfhack.df2utf(utils.call_with_string(still,'getName')),contents=contents}
 shot('still-add-task')
 local function search_text(value)
  if not sheet.entering_building_job_filter then
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
  g.precise_mouse_x=600;g.precise_mouse_y=154;g.mouse_x=75;g.mouse_y=12
  df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L')
  df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
  end
  assert(sheet.entering_building_job_filter,'Native workshop search did not focus')
  for i=1,#sheet.building_job_filter_str do gui.simulateInput(view,'STRING_A000')end
  for i=1,#value do gui.simulateInput(view,('STRING_A%03d'):format(value:byte(i)))end
  view:render(dfhack.getTickCount())
 end
 result.search_reference={cases={}}
 for _,query in ipairs{'BREW','fruit','Requires','zzzzz'}do
  search_text(query)
  local names={};for _,button in ipairs(df.global.game.main_interface.building.filtered_button)do names[#names+1]=dfhack.df2utf(utils.call_with_string(button,'text'))end
  result.search_reference.cases[#result.search_reference.cases+1]={query=query,names=names}
 end
 search_text(string.rep('x',100));result.search_reference.max_bytes=#sheet.building_job_filter_str
 search_text('BREW');gui.simulateInput(view,'SELECT');view:render(dfhack.getTickCount())
 result.search_reference.enter_releases_focus=not sheet.entering_building_job_filter
 shot('still-search')
 search_text('');gui.simulateInput(view,'SELECT');view:render(dfhack.getTickCount())
 local file=assert(io.open(out..'/workshop-native.json','w'));file:write(json.encode(result));file:close()
 local before_jobs={};for _,job in ipairs(still.jobs)do before_jobs[#before_jobs+1]=job.id end
 local original_workers={};for _,id in ipairs(still:getWorkshopProfile().permitted_workers)do original_workers[#original_workers+1]=id end
 capture('workshop-wire')
 local restored=still:getWorkshopProfile().permitted_workers
 assert(#restored==#original_workers,'Worker workflow did not restore native restriction')
 for i,id in ipairs(original_workers)do assert(restored[i-1]==id,'Worker workflow changed native restriction')end
 assert(#still.jobs==#before_jobs,'Rejected workshop task changed native queue size')
 for i,id in ipairs(before_jobs)do assert(still.jobs[i-1].id==id,'Rejected workshop task changed native queue order')end
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
 -- Controlled clone fixture: grant an occupied fortress office the manager
 -- responsibility, as in the existing petition panel oracle. Restore it after
 -- opening/cancelling the real native picker; no orders are created here.
 local fortress=assert(df.global.plotinfo.main.fortress_entity)
 local responsibility=df.entity_position_responsibility.MANAGE_PRODUCTION
 local position,assignment
 for _,a in ipairs(fortress.positions.assignments)do
  if a.histfig>=0 then
   local present=false;for _,u in ipairs(df.global.world.units.active)do if u.hist_figure_id==a.histfig then present=true;break end end
   if present then for _,p in ipairs(fortress.positions.own)do if p.id==a.position_id then position=p;assignment=a;break end end end
  end
  if position then break end
 end
 assert(position,'Order picker reference needs an occupied fortress office')
 local indexed=fortress.assignments_by_type[responsibility];local prior_index={}
 for _,a in ipairs(indexed)do prior_index[#prior_index+1]=a end
 local prior_responsibility=position.responsibilities[responsibility]
 position.responsibilities[responsibility]=true;indexed:insert('#',assignment)
 local orders_before=#df.global.world.manager_orders.all
 local prior_order_ids={};for _,o in ipairs(df.global.world.manager_orders.all)do prior_order_ids[#prior_order_ids+1]=o.id end
 local picker=df.global.game.main_interface.create_work_order
 local function read_rows(rows)
  local values={}
  for _,r in ipairs(rows)do values[#values+1]={job_type=r.job_type,reaction=r.reaction_name,item_type=r.item_type,item_subtype=r.item_subtype,mat_type=r.mat_type,mat_index=r.mat_index,caption=dfhack.df2utf(r.name),compare=dfhack.df2utf(r.compare_str)}end
  return values
 end
 local function catalog(target)
  select_map(target);assert(click_label('Work orders'));shot('order-picker-entry-'..target.id)
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
  g.precise_mouse_x=880;g.precise_mouse_y=154;g.mouse_x=110;g.mouse_y=12
  df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
  df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
  assert(picker.open and picker.forced_bld_id==target.id,'Native forced workshop picker did not open')
  local text,code=dfhack.run_command_silent('df3d','work-orders-catalog-probe');assert(code==0,text)
  local global=json.decode(text).rows;local native_global=read_rows(picker.jminfo_master)
  assert(json.encode(global)==json.encode(native_global),'Owned global order catalog differs from native picker')
  assert(#picker.building==1,'Forced workshop picker should have one group')
  text,code=dfhack.run_command_silent('df3d','work-orders-catalog-probe',tostring(target.id));assert(code==0,text)
  local filtered=json.decode(text).rows;local native_filtered=read_rows(picker.building[0].jminfo)
  local comparison=assert(io.open(out..'/work-order-catalog-'..target.id..'.json','w'))
  comparison:write(json.encode({native=native_filtered,owned=filtered}));comparison:close()
  assert(json.encode(filtered)==json.encode(native_filtered),'Owned workshop order catalog differs from native picker')
  result.order_catalogs=result.order_catalogs or {};result.order_catalogs[#result.order_catalogs+1]={building_id=target.id,global_count=#global,filtered_count=#filtered,rows=filtered}
  shot('order-picker-'..target.id)
  gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());assert(not picker.open)
  gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
 end
 local function order_values(order)
  return {job_type=order.job_type,reaction=order.reaction_name,item_type=order.item_type,item_subtype=order.item_subtype,
   mat_type=order.mat_type,mat_index=order.mat_index,specflag=order.specflag.whole,specdata=order.specdata.hist_figure_id,
   material_category=order.material_category.whole,art_type=order.art_spec.type,art_id=order.art_spec.id,art_subid=order.art_spec.subid,
   amount_left=order.amount_left,amount_total=order.amount_total,status=order.status.whole,frequency=order.frequency,
   finished_year=order.finished_year,finished_tick=order.finished_year_tick,workshop_id=order.workshop_id,max_workshops=order.max_workshops,
   item_conditions=#order.item_conditions,order_conditions=#order.order_conditions,items=order.items~=nil}
 end
 local catalog_ok,catalog_err=xpcall(function()
  catalog(building);catalog(still)
  assert(#df.global.world.manager_orders.all==orders_before,'Opening/cancelling picker created an order')
  select_map(still);assert(click_label('Work orders'))
  local function mouse(x,y)
   df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
   g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=math.floor(x/8);g.mouse_y=math.floor(y/12)
   df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
   df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
  end
  mouse(880,154);assert(picker.open)
  local chosen=picker.building[0].jminfo[2];assert(chosen.name=='Extract from plants')
  mouse(600,94)
  for char in ('extract'):gmatch('.')do gui.simulateInput(view,('STRING_A%03d'):format(char:byte()))end
  view:render(dfhack.getTickCount())
  local matches={};for _,row in ipairs(picker.building[0].jminfo)do if row.on then matches[#matches+1]=dfhack.df2utf(row.name)end end
  assert(#matches==1 and matches[1]=='Extract from plants','Native order search changed')
  shot('order-search-native')
  gui.simulateInput(view,'SELECT');view:render(dfhack.getTickCount());assert(picker.open,'Search Enter unexpectedly closed picker')
  local next_id=df.global.world.manager_orders.manager_order_next_id
  mouse(600,130);assert(not picker.open,'Native recipe click did not close picker')
  assert(#df.global.world.manager_orders.all==orders_before+1)
  local native=df.global.world.manager_orders.all[orders_before];assert(native.id==next_id)
  local expected={building_id=still.id,choice=0,query='extract',search_names=matches,caption='Extract from plants',native=order_values(native),native_id=native.id}
  shot('orders-created-native')
  mouse(775,190)
  gui.simulateInput(view,'STRING_A049');view:render(dfhack.getTickCount())
  assert(native.amount_left==1 and native.amount_total==1,'Native order quantity first digit differs')
  gui.simulateInput(view,'STRING_A050');view:render(dfhack.getTickCount())
  assert(native.amount_left==12 and native.amount_total==12,'Native order quantity second digit differs')
  shot('order-quantity-native')
  gui.simulateInput(view,'SELECT');view:render(dfhack.getTickCount())
  expected.quantity_native=order_values(native)
  mouse(808,190)
  local conditions=df.global.game.main_interface.info.work_orders.conditions
  assert(conditions.open and conditions.wq.id==next_id,'Native work-order conditions did not open')
  result.order_conditions={order_id=next_id,frequency=native.frequency,suggested_count=#conditions.suggested_item_condition}
  shot('order-conditions-native')
  -- The supported XML declares value elements here, but native stores pointers.
  -- This raw diagnostic observation never supplies runtime UI state.
  local _,condition_address=df.sizeof(conditions)
  local first=df.reinterpret_cast('uint64_t',condition_address+0x58).value
  local finish=df.reinterpret_cast('uint64_t',condition_address+0x60).value
  assert(finish>=first and (finish-first)%8==0 and finish-first<=1024)
  local native_suggestions={}
  for at=first,finish-1,8 do
   local pointer=df.reinterpret_cast('uint64_t',at).value
   local c=df.reinterpret_cast(df.manager_order_condition_item,pointer)
   local contained={};for _,value in ipairs(c.contains)do contained[#contained+1]=value end
   native_suggestions[#native_suggestions+1]={compare=c.compare_type,threshold=c.compare_val,item_type=c.item_type,item_subtype=c.item_subtype,
    mat_type=c.mat_type,mat_index=c.mat_index,flags1=c.flags1.whole,flags2=c.flags2.whole,flags3=c.flags3.whole,flags4=c.flags4,flags5=c.flags5,
    reaction_class=c.reaction_class,material_product=c.has_material_reaction_product,metal_ore=c.metal_ore,min_dimension=c.min_dimension,
    reaction_id=c.reaction_id,tool_use=c.has_tool_use,dye_color=c.dye_color,contains=contained}
  end
  local function context_bytes()
   local values={};for i=0,0x6f do values[#values+1]=df.reinterpret_cast('uint8_t',condition_address+i).value end;return table.concat(values,',')
  end
  local before_context=context_bytes();local before_order=json.encode(order_values(native))
  local text,code=dfhack.run_command_silent('df3d','work-order-suggestions-probe',tostring(next_id));assert(code==0,text)
  local owned=json.decode(text).rows
  assert(#owned==#native_suggestions,'Owned native suggestion count differs')
  local rendered={};for _,line in ipairs(lines())do rendered[#rendered+1]=line.text end
  local rendered_text=table.concat(rendered,'\n')
  for _,row in ipairs(owned)do assert(row.item_caption and rendered_text:find(row.item_caption,1,true),'Condition caption differs from native screen')end
  expected.suggestions=owned
  for i,c in ipairs(native_suggestions)do for key,value in pairs(c)do
   if key=='contains' then assert(json.encode(value)==json.encode(owned[i][key]),'Suggestion contained identities differ')
   else assert(value==owned[i][key],'Suggestion '..i..' '..key..' differs')end
  end end
  assert(before_context==context_bytes() and before_order==json.encode(order_values(native)),'Owned suggestions changed source order or native context')
  result.order_conditions.suggested_count=#native_suggestions
  result.order_conditions.suggestions=native_suggestions
  result.order_conditions.owned_suggestions=owned
  result.order_conditions.source_unchanged=true

  result.order_conditions.frequency_steps={}
  for i=1,5 do
   mouse(880,142)
   result.order_conditions.frequency_steps[#result.order_conditions.frequency_steps+1]={frequency=native.frequency,status=native.status.whole,finished_year=native.finished_year,finished_tick=native.finished_year_tick,lines=lines()}
  end
  shot('order-conditions-frequency-native')
  assert(native.frequency==expected.native.frequency,'Frequency cycle did not return to original value')
  assert(#native.item_conditions==0)
  mouse(768,586)
  assert(#native.item_conditions==1 and native.frequency==1,'Native suggestion did not append and enable daily frequency')
  local added=native.item_conditions[0]
  local wanted=native_suggestions[1]
  assert(added.compare_type==wanted.compare and added.compare_val==wanted.threshold)
  for _,key in ipairs{'item_type','item_subtype','mat_type','mat_index','flags4','flags5','reaction_class','metal_ore','min_dimension','reaction_id','dye_color'}do assert(added[key]==wanted[key],'Native suggested add differs: '..key)end
  assert(added.flags1.whole==wanted.flags1 and added.flags2.whole==wanted.flags2 and added.flags3.whole==wanted.flags3)
  assert(added.has_material_reaction_product==wanted.material_product and added.has_tool_use==wanted.tool_use)
  local added_contains={};for _,value in ipairs(added.contains)do added_contains[#added_contains+1]=value end
  assert(json.encode(added_contains)==json.encode(wanted.contains))
  expected.added_condition=owned[1]
  expected.added_condition.satisfied=conditions.item_condition_satisfied[0]
  result.order_conditions.added={frequency=native.frequency,condition=owned[1],lines=lines()}
  shot('order-condition-added-native')
  expected.condition_steps={}
  for _,x in ipairs{672,704,736,736,736,736,736,736}do
   mouse(x,178)
   expected.condition_steps[#expected.condition_steps+1]={x=x,compare=added.compare_type,threshold=added.compare_val,satisfied=conditions.item_condition_satisfied[0]}
  end
  assert(added.compare_type==wanted.compare and added.compare_val==wanted.threshold,'Native amount/comparison cycle did not restore original values')
  result.order_conditions.edit_steps=expected.condition_steps
  mouse(640,178)
  assert(conditions.entering_logic_number and conditions.logic_number_str=='','Condition number entry did not start empty')
  shot('order-condition-number-empty-native')
  gui.simulateInput(view,'STRING_A049');view:render(dfhack.getTickCount())
  assert(added.compare_val==1)
  gui.simulateInput(view,'STRING_A050');view:render(dfhack.getTickCount())
  assert(added.compare_val==12)
  shot('order-condition-number-native')
  gui.simulateInput(view,'SELECT');view:render(dfhack.getTickCount())
  assert(not conditions.entering_logic_number and conditions.open)
  expected.condition_number=12
  result.order_conditions.filter_catalogs={}
  expected.filter_steps={}
  for kind=0,2 do
   mouse(768+kind*32,178)
   assert(conditions.change_type==kind,'Native condition selector did not open')
   shot('order-condition-filter-'..kind..'-native')
   local catalog_text,catalog_code=dfhack.run_command_silent('df3d','work-order-filter-choices-probe',tostring(kind),tostring(next_id))
   assert(catalog_code==0,catalog_text)
   local choices=json.decode(catalog_text).rows
   assert(#choices==#conditions.compare_master,'Owned filter catalog size differs')
   for i,row in ipairs(choices)do
    local at=i-1
    if kind==0 then
     assert(row.item_type==conditions.item_type_master[at] and row.item_subtype==conditions.item_subtype_master[at],'Owned item type order differs')
    elseif kind==1 then
     assert(row.mat_type==conditions.item_material_master[at] and row.mat_index==conditions.item_matgloss_master[at] and row.mat_state==conditions.item_matstate_master[at],'Owned material order differs')
    else
     local t=conditions.item_trait_master[at]
     assert(row.caption==dfhack.df2utf(t.display_string) and row.flag==t.flg and row.flag_word==t.flgn and row.reaction_class==t.reaction_class and row.reaction_product==t.reaction_product_class and row.metal_ore==t.metal_ore and row.reaction_index==t.contains_reaction_index and row.reagent_index==t.contains_reagent_index and row.tool_use==t.tool_use and row.dye_color==t.dye_color,'Owned trait differs')
    end
   end
   result.order_conditions.filter_catalogs[#result.order_conditions.filter_catalogs+1]={kind=kind,rows=choices,lines=lines()}
   local query=({'BARS','GRANITE','FIRE'})[kind+1]
   for char in query:gmatch('.')do gui.simulateInput(view,('STRING_A%03d'):format(char:byte()))end
   view:render(dfhack.getTickCount())
   assert(conditions.filter==query,'Native selector query differs')
   local matched={}
   for at=0,#conditions.compare_master-1 do
    local on=kind==0 and conditions.item_type_on[at] or kind==1 and conditions.item_material_on[at] or kind==2 and conditions.item_trait_master[at].on
    if on then matched[#matched+1]=at end
   end
   assert(#matched>0,'Native selector query found no rows')
   local text_lines={};for _,line in ipairs(lines())do text_lines[#text_lines+1]=line.text end
   shot('order-condition-filter-search-'..kind..'-native')
   mouse(400,214)
   assert(conditions.open and conditions.change_type==(kind==2 and 2 or -1),'Native selection close behavior differs')
   expected.filter_steps[#expected.filter_steps+1]={kind=kind,query=query,ids=matched,text=table.concat(text_lines,'\n'),item_type=added.item_type,item_subtype=added.item_subtype,mat_type=added.mat_type,mat_index=added.mat_index}
   shot('order-condition-filter-applied-'..kind..'-native')
   df.global.enabler.mouse_rbut_lift=0;gui.simulateInput(view,'_MOUSE_R');view:render(dfhack.getTickCount())
   df.global.enabler.mouse_rbut=0;df.global.enabler.mouse_rbut_down=0;df.global.enabler.mouse_rbut_lift=1
   assert(not conditions.open,'Native selector Back did not close Conditions')
   if df.global.game.main_interface.info.open then gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())end
   select_map(still);assert(click_label('Work orders'));mouse(808,190)
   assert(conditions.open and conditions.wq.id==next_id and conditions.change_type==-1,'Conditions did not reopen after selector Back')
  end
  mouse(896,178)
  assert(#native.item_conditions==0 and native.frequency==1,'Native condition removal changed frequency or retained the row')
  result.order_conditions.removed={frequency=native.frequency,status=native.status.whole,finished_year=native.finished_year,finished_tick=native.finished_year_tick}
  shot('order-condition-removed-native')
  mouse(912,142)
  assert(#native.item_conditions==1,'Native manual condition was not created')
  local manual=native.item_conditions[0]
  assert(manual.compare_type==0 and manual.compare_val==0 and manual.min_dimension==-1)
  expected.manual_condition={compare=manual.compare_type,threshold=manual.compare_val,item_type=manual.item_type,item_subtype=manual.item_subtype,mat_type=manual.mat_type,mat_index=manual.mat_index}
  expected.manual_satisfied=conditions.item_condition_satisfied[0]
  shot('order-condition-manual-native')
  mouse(896,178)
  assert(#native.item_conditions==0)
  for i=1,14 do mouse(912,142)end
  assert(#native.item_conditions==14)
  shot('order-conditions-overflow-native')
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
  g.precise_mouse_x=400;g.precise_mouse_y=240;g.mouse_x=50;g.mouse_y=20
  gui.simulateInput(view,'CONTEXT_SCROLL_DOWN');view:render(dfhack.getTickCount())
  expected.condition_scroll={wheel=conditions.scroll_position_conditions}
  mouse(912,550)
  expected.condition_scroll.first=conditions.scroll_position_conditions
  shot('order-conditions-scrolled-native')
  -- Retire diagnostic blank rows before the independent dependency reference.
  while #native.item_conditions>0 do local c=native.item_conditions[0];native.item_conditions:erase(0);c:delete()end
  conditions.scroll_position_conditions=0
  view:render(dfhack.getTickCount())
  mouse(944,142)
  assert(conditions.selecting_order_condition and #conditions.condition_wq>0)
  expected.dependency_candidates={}
  for _,candidate in ipairs(conditions.condition_wq)do expected.dependency_candidates[#expected.dependency_candidates+1]=candidate.id end
  shot('order-dependency-picker-native')
  mouse(400,202)
  assert(#native.order_conditions==1 and not conditions.selecting_order_condition,'Native dependency selection failed')
  local linked=native.order_conditions[0]
  expected.dependency={target=linked.order_id,condition=linked.condition,frequency=native.frequency}
  shot('order-dependency-added-native')
  mouse(640,178)
  expected.dependency.toggled=linked.condition
  shot('order-dependency-toggled-native')
  mouse(896,178)
  assert(#native.order_conditions==0,'Native dependency removal failed')
  gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());assert(not conditions.open)
  assert(df.global.game.main_interface.info.open,'Conditions Back did not open global work orders')
  expected.global_order_ids={}
  for _,order in ipairs(df.global.world.manager_orders.all)do expected.global_order_ids[#expected.global_order_ids+1]=order.id end
  shot('global-work-orders-native')
  -- Native clothing-size reference on an existing order in the unsaved clone.
  local size_order,size_position
  for i,order in ipairs(df.global.world.manager_orders.all)do
   if order.job_type==100 or order.job_type==101 or order.job_type==102 or order.job_type==116 or order.job_type==117 then size_order=order;size_position=i;break end
  end
  assert(size_order,'Fixture needs an existing clothing order')
  local work_orders=df.global.game.main_interface.info.work_orders
  local prior_scroll=work_orders.scroll_position_work_orders
  work_orders.scroll_position_work_orders=math.min(size_position,math.max(0,#df.global.world.manager_orders.all-15));view:render(dfhack.getTickCount())
  mouse(584,142+(size_position-work_orders.scroll_position_work_orders)*36)
  local sizing=df.global.game.main_interface.job_details
  assert(sizing.open and sizing.wq==size_order,'Clothing Details did not open')
  local size_slot
  for i,kind in ipairs(sizing.option)do if kind==2 then size_slot=i;break end end
  assert(size_slot,'Clothing size option missing');mouse(200,106+size_slot*36)
  assert(sizing.current_option==2,'Clothing size chooser did not open')
  local size_rows={};for _,race in ipairs(sizing.clothing_size_race_index)do size_rows[#size_rows+1]=race end
  local size_text,size_code=dfhack.run_command_silent('df3d','work-order-details-probe',tostring(size_order.id),tostring(size_slot))
  assert(size_code==0,size_text);local size_owned=json.decode(size_text)
  assert(#size_owned.materials==#size_rows,'Owned clothing size count differs')
  for i,row in ipairs(size_owned.materials)do assert(row.index==size_rows[i],'Owned clothing size order differs')end
  expected.clothing_size={id=size_order.id,option=size_slot,rows=size_owned.materials,original=size_order.specdata.hist_figure_id}
  shot('order-clothing-size-native')
  mouse(200,154);for byte in ('human'):gmatch('.')do gui.simulateInput(view,('STRING_A%03d'):format(byte:byte()))end
  view:render(dfhack.getTickCount());assert(#sizing.clothing_size_race_index>0,'Native clothing size search found no humans')
  expected.clothing_size.race=sizing.clothing_size_race_index[0]
  local saved_size_inputs={};for _,item in ipairs(size_order.items.elements)do local saved=df.job_item:new();saved:assign(item);saved_size_inputs[#saved_size_inputs+1]=saved end
  shot('order-clothing-size-search-native');mouse(200,190)
  assert(size_order.specdata.hist_figure_id==expected.clothing_size.race,'Native clothing size selection failed')
  size_order.specdata.hist_figure_id=expected.clothing_size.original
  assert(#saved_size_inputs==#size_order.items.elements)
  for i,saved in ipairs(saved_size_inputs)do size_order.items.elements[i-1]:assign(saved);saved:delete()end
  if sizing.open then gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())end
  work_orders.scroll_position_work_orders=prior_scroll;view:render(dfhack.getTickCount())
  -- Reuse an existing visible Encrust order for the native type chooser.
  local improvement_y
  for _,line in ipairs(lines())do if line.text:find('Encrust',1,true)then improvement_y=line.y*12+6;break end end
  assert(improvement_y,'Fixture needs a visible Encrust order')
  mouse(584,improvement_y)
  local improvement=df.global.game.main_interface.job_details
  assert(improvement.open and improvement.wq,'Encrust Details did not open')
  local improved=improvement.wq
  local improvement_slot
  for i,kind in ipairs(improvement.option)do if kind==3 then improvement_slot=i;break end end
  assert(improvement_slot,'Encrust type option missing')
  mouse(200,106+improvement_slot*36)
  assert(improvement.current_option==3,'Improvement type chooser did not open')
  local probe_text,probe_code=dfhack.run_command_silent('df3d','work-order-details-probe',tostring(improved.id),tostring(improvement_slot))
  assert(probe_code==0,probe_text)
  local observed=json.decode(probe_text)
  assert(#observed.materials==#improvement.improvement_type,'Improvement choice count differs')
  local pick
  for i,row in ipairs(observed.materials)do
   assert(row.index==improvement.improvement_type[i-1],'Improvement order differs')
   if not pick and row.index>0 then pick=i-1 end
  end
  assert(pick,'No direct improvement choice available')
  expected.improvement={id=improved.id,option=improvement_slot,choice=pick,rows=observed.materials}
  for i,order in ipairs(df.global.world.manager_orders.all)do if order.id==improved.id then expected.improvement.position=i;break end end
  shot('order-details-improvement-native')
  local prior_improvement=improved.specdata.hist_figure_id
  mouse(200,142)
  local artwork=df.global.game.main_interface.image_creator
  local function art_back()
   df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
   df.global.enabler.mouse_rbut_lift=0;gui.simulateInput(view,'_MOUSE_R');view:render(dfhack.getTickCount())
   df.global.enabler.mouse_rbut=0;df.global.enabler.mouse_rbut_down=0;df.global.enabler.mouse_rbut_lift=1
  end
  assert(artwork.open,'Image improvement did not open artwork picker')
  shot('order-artwork-native')
  expected.artwork_subjects={}
  for kind,label in ipairs({'Related to historical figure','Related to site','Related to civilization or other group'})do
   assert(click_label(label),'Artwork subject control missing: '..label)
   assert(artwork.current_option==kind,'Artwork subject page differs')
   local subjects=kind==1 and artwork.hf or kind==2 and artwork.st or artwork.ent
   local ids={};for _,subject in ipairs(subjects)do ids[#ids+1]=subject.id end
   local text,code=dfhack.run_command_silent('df3d','work-order-art-subjects-probe',tostring(improved.id),tostring(kind))
   assert(code==0,text)
   local owned=json.decode(text)
   assert(json.encode(ids)==json.encode(owned.ids),'Owned artwork subject order differs')
   local screen_text={};for _,line in ipairs(lines())do screen_text[#screen_text+1]=line.text end
   screen_text=table.concat(screen_text,'\n')
   for _,caption in ipairs(owned.captions)do assert(screen_text:find(caption:sub(1,70),1,true),'Native artwork subject caption differs')end
   assert(artwork.open and artwork.current_option==kind and #subjects==#ids,'Owned artwork reader changed native menu')
   expected.artwork_subjects[#expected.artwork_subjects+1]={kind=kind,count=#ids,list_revision=owned.list_revision,first=ids[1],later=ids[129],captions=owned.captions}
   if kind==2 then
    local filtered_text,filtered_code=dfhack.run_command_silent('df3d','work-order-art-subjects-probe',tostring(improved.id),'2','a')
    assert(filtered_code==0,filtered_text)
    local filtered=json.decode(filtered_text);assert(#filtered.ids>0,'Site search fixture is empty')
    expected.artwork_search={query='a',first=filtered.ids[1],count=#filtered.ids}
   end
   shot('order-artwork-subject-'..tostring(kind)..'-native')
   art_back()
   assert(artwork.open and artwork.current_option==-1,'Artwork subject Back did not return to root')
   assert(click_label(label));assert(#ids>0,'Artwork fixture needs a subject')
   local prior_art={type=improved.art_spec.type,id=improved.art_spec.id,subid=improved.art_spec.subid}
   local prior_inputs={};for _,item in ipairs(improved.items.elements)do local copy=df.job_item:new();copy:assign(item);prior_inputs[#prior_inputs+1]=copy end
   local function restore_art()
    improved.art_spec.type=prior_art.type;improved.art_spec.id=prior_art.id;improved.art_spec.subid=prior_art.subid
    assert(#improved.items.elements==#prior_inputs,'Artwork changed requirement count')
    for i,item in ipairs(improved.items.elements)do item:assign(prior_inputs[i+1])end
   end
   local function art_effect()return {type=improved.art_spec.type,id=improved.art_spec.id,subid=improved.art_spec.subid,specdata=improved.specdata.hist_figure_id,amount=improved.amount_total,remaining=improved.amount_left,frequency=improved.frequency}end
   mouse(200,190);assert(not artwork.open,'Native subject selection did not close artwork')
   local native_effect=art_effect();restore_art()
   local edit_text,edit_code=dfhack.run_command_silent('df3d','work-order-art-select-probe',tostring(improved.id),tostring(improvement_slot),tostring(kind),tostring(ids[1]))
   assert(edit_code==0,edit_text)
   assert(json.encode(art_effect())==json.encode(native_effect),'Semantic artwork subject effect differs')
   restore_art();for _,item in ipairs(prior_inputs)do item:delete()end
   mouse(584,improvement_y);assert(improvement.open)
   mouse(200,106+improvement_slot*36);mouse(200,142);assert(artwork.open and artwork.current_option==-1)
  end
  assert(click_label('Existing image'));assert(artwork.current_option==5)
  expected.artwork_images={}
  for _,image in ipairs(artwork.art_image)do expected.artwork_images[#expected.artwork_images+1]={id=image.id,subid=image.subid}end
  assert(#expected.artwork_images>0,'Fixture needs an existing image')
  shot('order-artwork-existing-native')
  df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
  g.precise_mouse_x=200;g.precise_mouse_y=190;g.mouse_x=25;g.mouse_y=15;view:render(dfhack.getTickCount())
  expected.artwork_preview={};for _,line in ipairs(artwork.selected_box.text)do expected.artwork_preview[#expected.artwork_preview+1]=dfhack.df2utf(line.value)end
  assert(#expected.artwork_preview>0,'Existing image hover description missing')
  shot('order-artwork-existing-preview-native')
  art_back();assert(artwork.open and artwork.current_option==-1)
  assert(click_label('Specify a new image'));assert(artwork.current_option==6)
  shot('order-artwork-new-native')
  expected.artwork_draft={}
  mouse(56,418)
  local name_creator=df.global.game.main_interface.name_creator
  assert(name_creator.open and name_creator.context==2,'Artwork Name did not open')
  shot('order-artwork-name-native')
  mouse(400,166)
  expected.artwork_draft.name_word=artwork.new_image.name.words[0]
  expected.artwork_draft.name_part=artwork.new_image.name.parts_of_speech[0]
  assert(expected.artwork_draft.name_word>=0,'Artwork name word was not selected')
  mouse(912,82)
  assert(not name_creator.open and artwork.open and artwork.current_option==6,'Name Done did not return to artwork')
  local function draft_text()local lines={};for _,line in ipairs(artwork.art_box.text)do lines[#lines+1]=dfhack.df2utf(line.value)end;return lines end
  -- Observe one complete draft-editing path before implementing the owned editor.
  assert(click_label('Creature'));assert(artwork.current_option==7)
  shot('order-artwork-new-creature-native')
  mouse(300,190);assert(artwork.current_option==6 and #artwork.new_image.elements==1,'Creature did not enter draft')
  expected.artwork_draft.one=draft_text()
  shot('order-artwork-new-one-element-native')
  assert(click_label('Plant'));assert(artwork.current_option==9)
  shot('order-artwork-new-plant-native')
  mouse(300,190);assert(artwork.current_option==6 and #artwork.new_image.elements==2,'Plant did not enter draft')
  expected.artwork_draft.two=draft_text()
  shot('order-artwork-new-two-elements-native')
  assert(click_label('Action or relationship'));assert(artwork.current_option==14)
  shot('order-artwork-new-relationship-native')
  mouse(300,190);assert(artwork.current_option==15,'Relationship did not request actor')
  shot('order-artwork-new-actor-native')
  mouse(300,190)
  if artwork.current_option==16 then
   shot('order-artwork-new-target-native');mouse(300,190)
  end
  assert(artwork.current_option==6 and #artwork.new_image.properties==1,'Relationship did not enter draft')
  expected.artwork_draft.related=draft_text()
  shot('order-artwork-new-related-native')
  assert(click_label('Delete element'));assert(artwork.current_option==17)
  shot('order-artwork-new-delete-native')
  mouse(960,154);assert(#artwork.new_image.elements==1,'Element was not deleted')
  expected.artwork_draft.deleted=draft_text()
  shot('order-artwork-new-deleted-native')
  if artwork.current_option==17 then art_back()end
  art_back()
  if artwork.open and artwork.current_option==-1 then art_back()end
  if artwork.open then assert(click_label('Leave editor and discard data'),'Artwork exit confirmation missing')end
  if artwork.open and artwork.current_option==-1 then art_back()end
  assert(not artwork.open,'Artwork picker did not close')
  improved.specdata.hist_figure_id=prior_improvement
  if not improvement.open then
   mouse(584,improvement_y);assert(improvement.open,'Details did not reopen after artwork exit')
   mouse(200,106+improvement_slot*36);assert(improvement.current_option==3)
  end
  gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
  assert(improvement.open and improvement.current_option==-1,'Improvement Back did not return to options')
  gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
  assert(not improvement.open,'Improvement Back did not close Details')
  mouse(944,142);assert(picker.open and picker.forced_bld_id==-1,'Native global picker did not open')
  local groups={}
  for _,group in ipairs(picker.building)do
   groups[#groups+1]={type=group.type,subtype=group.subtype,custom=group.custom_id,name=dfhack.df2utf(group.name),rows=read_rows(group.jminfo)}
  end
  local global_file=assert(io.open(out..'/global-work-order-picker.json','w'))
  global_file:write(json.encode({selected=picker.selected_building_index,groups=groups}));global_file:close()
  local grouped_text,grouped_code=dfhack.run_command_silent('df3d','work-orders-catalog-probe');assert(grouped_code==0,grouped_text)
  assert(json.encode(groups)==json.encode(json.decode(grouped_text).groups),'Owned global categories differ from native picker')
  shot('global-order-picker-native')
  gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());assert(not picker.open)
  if df.global.game.main_interface.info.open then gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())end
  select_map(still);assert(click_label('Work orders'))
  mouse(840,190)
  assert(df.global.game.main_interface.job_details.open,'Native order Details did not open')
  shot('order-details-native')
  local details=df.global.game.main_interface.job_details
  local detail_options={}
  for i,kind in ipairs(details.option)do detail_options[#detail_options+1]={kind=kind,index=details.option_index[i]}end
  local function detail_probe(selected,choice)
   local args={'df3d','work-order-details-probe',tostring(native.id)}
   if selected then args[#args+1]=tostring(selected)end
   if choice then args[#args+1]=tostring(choice)end
   local text,code=dfhack.run_command_silent(table.unpack(args));assert(code==0,text)
   return json.decode(text)
  end
  local root_details=detail_probe()
  local root_text={};for _,line in ipairs(lines())do root_text[#root_text+1]=line.text end
  root_text=table.concat(root_text,'\n')
  assert(root_text:find(root_details.caption,1,true),'Details heading differs')
  for i,row in ipairs(root_details.options)do
   assert(row.kind==detail_options[i].kind and row.index==detail_options[i].index,'Native Details options differ')
   assert(root_text:find(row.caption,1,true),'Native Details option caption differs')
  end
  local function detail_effect()
   local inputs={}
   for _,item in ipairs(native.items.elements)do
    local row={}
    for _,key in ipairs{'item_type','item_subtype','mat_type','mat_index','quantity','vector_id','flags4','flags5','metal_ore','reaction_class','has_material_reaction_product','min_dimension','reagent_index','reaction_id','has_tool_use','dye_color','job_details_mat_type','job_details_mat_index'}do row[key]=item[key]end
    row.flags1=item.flags1.whole;row.flags2=item.flags2.whole;row.flags3=item.flags3.whole
    row.saved=item.job_details_flags.whole;row.saved_flags2=item.job_details_item_flags2.whole
    row.contains={};for _,id in ipairs(item.contains)do row.contains[#row.contains+1]=id end
    inputs[#inputs+1]=row
   end
   return {mat_type=native.mat_type,mat_index=native.mat_index,inputs=inputs,status=native.status.whole,frequency=native.frequency,amount_left=native.amount_left,amount_total=native.amount_total}
  end
  expected.details={options=detail_options,choices={}}
  for slot,option in ipairs(detail_options)do
   if option.kind==0 or option.kind==6 then
    mouse(200,118+(slot-1)*36)
    assert(details.current_option==option.kind and details.current_option_index==option.index)
    local types=option.kind==0 and details.material or details.plant_mat
    local indices=option.kind==0 and details.matgloss or details.plant_matgloss
    local counts=option.kind==0 and details.material_count or details.plant_count
    local rows={}
    for i,kind in ipairs(types)do rows[#rows+1]={type=kind,index=indices[i],count=counts[i]}end
    local before=json.encode({options=detail_options,rows=rows,current=details.current_option,index=details.current_option_index})
    local owned=detail_probe(slot-1)
    local choice_text={};for _,line in ipairs(lines())do choice_text[#choice_text+1]=line.text end
    choice_text=table.concat(choice_text,'\n')
    assert(#owned.materials==#rows,'Details choice count differs')
    for i,row in ipairs(owned.materials)do
     assert(row.type==rows[i].type and row.index==rows[i].index and row.count==rows[i].count,'Owned Details material/plant choices differ')
     assert(choice_text:find(row.caption,1,true),'Details material/plant caption differs')
    end
    local after_rows={}
    for i,kind in ipairs(types)do after_rows[#after_rows+1]={type=kind,index=indices[i],count=counts[i]}end
    assert(before==json.encode({options=detail_options,rows=after_rows,current=details.current_option,index=details.current_option_index}),'Details reader changed native picker')
    expected.details.choices[#expected.details.choices+1]={option=slot-1,kind=option.kind,rows=rows}
    shot('order-details-choice-'..tostring(option.kind)..'-native')
    local search=option.kind==0 and 'crystal' or 'kobold'
    mouse(200,154)
    for i=1,#search do gui.simulateInput(view,('STRING_A%03d'):format(search:byte(i)))end
    view:render(dfhack.getTickCount())
    local filtered={};for i,kind in ipairs(types)do filtered[#filtered+1]={type=kind,index=indices[i]}end
    expected.details.choices[#expected.details.choices].search=search
    expected.details.choices[#expected.details.choices].filtered=filtered
    shot('order-details-search-'..tostring(option.kind)..'-native')
    for i=1,#search do gui.simulateInput(view,'STRING_A000')end
    gui.simulateInput(view,'SELECT');view:render(dfhack.getTickCount())
    assert(#types==#rows,'Native Details search did not clear')
    local prior_type,prior_index=native.mat_type,native.mat_index
    local prior_inputs={};for _,item in ipairs(native.items.elements)do local copy=df.job_item:new();copy:assign(item);prior_inputs[#prior_inputs+1]=copy end
    local function restore_inputs()
     assert(#prior_inputs==#native.items.elements,'Details changed input count; cannot restore this reference')
     native.mat_type=prior_type;native.mat_index=prior_index
     for i,item in ipairs(native.items.elements)do item:assign(prior_inputs[i+1])end
    end
    mouse(200,190);assert(not details.open,'Native Details choice did not close')
    local native_effect=detail_effect()
    restore_inputs()
    detail_probe(slot-1,0)
    assert(json.encode(detail_effect())==json.encode(native_effect),'Details selection effects differ')
    expected.details.choices[#expected.details.choices].effect=native_effect
    restore_inputs();for _,item in ipairs(prior_inputs)do item:delete()end
    select_map(still);assert(click_label('Work orders'));mouse(840,190)
    assert(details.open and details.current_option==-1,'Details reopen did not return to options')
   end
  end
  gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
  select_map(still);assert(click_label('Work orders'))
  local dependent=assert(df.global.world.manager_orders.all[0]);assert(dependent.id~=next_id)
  local prior_dependencies=#dependent.order_conditions
  local function dependency(target)
   local c=df.manager_order_condition_order:new();c.order_id=target;c.condition=0;c.flags.whole=0
   dependent.order_conditions:insert('#',c)
  end
  dependency(next_id)
  mouse(872,190)
  assert(#df.global.world.manager_orders.all==orders_before,'Native remove retained order')
  assert(#dependent.order_conditions==prior_dependencies,'Native remove retained incoming dependency')
  shot('order-removed-native')
  -- The new viewer order will receive the next identity. Keep this paused
  -- diagnostic dependency so removal is checked against an independent record.
  dependency(next_id+1)

  local file=assert(io.open(out..'/workshop-order-expected.json','w'));file:write(json.encode(expected));file:close()
  gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
  capture('workshop-order-wire')
  assert(size_order.specdata.hist_figure_id==expected.clothing_size.race,'Viewer clothing size selection differs from native')
  assert(improved.specdata.improvement==0,'Viewer Image entry effect missing')
  assert(improved.art_spec.type==3,'Viewer Done did not select a specific image')
  local chunk=assert(df.art_image_chunk.find(improved.art_spec.id),'Viewer image chunk missing')
  local installed=assert(chunk.images[improved.art_spec.subid].art_image,'Viewer image missing')
  assert(#installed.elements==1 and df.art_image_element_plantst:is_instance(installed.elements[0]),'Viewer image lost its plant')
  assert(#installed.properties==0 and installed.name.has_name,'Viewer image name or relationship state differs')
  assert(installed.name.words[0]==expected.artwork_draft.name_word and installed.name.parts_of_speech[0]==expected.artwork_draft.name_part,'Viewer artwork name edit was not installed')
  local resources=df.global.plotinfo.main.fortress_entity.resources
  local ref=installed.ref
  assert(ref and df.general_ref_entity_art_image:is_instance(ref) and ref.entity_id==df.global.plotinfo.main.fortress_entity.id,'Viewer commissioned image reference missing')
  assert(resources.art_image_types[ref.index]==1 and resources.art_image_ids[ref.index]==installed.id and resources.art_image_subids[ref.index]==installed.subid,'Viewer commissioned image registration missing')
  assert(#df.global.world.manager_orders.all==orders_before,'Viewer removal did not restore order count')
  for i,id in ipairs(prior_order_ids)do assert(df.global.world.manager_orders.all[i-1].id==id,'Viewer removal changed unrelated order sequence')end
  assert(#dependent.order_conditions==prior_dependencies,'Viewer removal retained incoming dependency')
  local comparison=assert(io.open(out..'/workshop-order-removal-comparison.json','w'))
  comparison:write(json.encode({native_removed=next_id,viewer_removed=next_id+1,remaining_ids=prior_order_ids,dependencies_restored=true}));comparison:close()
  assert(df.global.plotinfo.nobles.manager_cooldown==0,'Viewer creation did not reset manager cooldown')
  result.order_removal={native_id=next_id,viewer_id=next_id+1,unrelated_ids_unchanged=true,dependencies_restored=true}

 end,debug.traceback)
 position.responsibilities[responsibility]=prior_responsibility;indexed:resize(0)
 for _,a in ipairs(prior_index)do indexed:insert('#',a)end
 assert(catalog_ok,catalog_err)
end,debug.traceback)
for _,prior in ipairs(selection_moves)do assert(dfhack.items.moveToGround(prior.item,prior.pos),'Selection fixture restoration failed');prior.item.flags.whole=prior.flags end
for _,prior in ipairs(selection_units)do prior.unit.pos:assign(prior.pos)end
for _,prior in ipairs(selection_designations)do prior.designation.whole=prior.whole end
for _,prior in ipairs(selection_engravings)do
 prior.target.art_id=prior.art_id;prior.target.art_subid=prior.art_subid;prior.target.tile=prior.tile;prior.target.flags.whole=prior.flags
end
for _,tile in ipairs(magma_tiles)do tile.upper.tiletype[tile.x][tile.y]=tile.tile;tile.lower.designation[tile.x][tile.y].whole=tile.designation end
for index=#custom_supplies,1,-1 do assert(dfhack.items.remove(custom_supplies[index]),'Custom supply cleanup failed')end
for _,prior in ipairs(fuel_flags)do prior.item.flags.forbid=prior.forbid end
for _,prior in ipairs(dye_names)do prior.color.name=prior.name;assert(prior.color.name==prior.name)end
for _,entry in ipairs(furnace_fixtures)do entry.building.type=entry.prior_type end
for _,entry in ipairs(workshop_fixtures)do entry.building.type=entry.prior_type;entry.building.custom_type=entry.prior_custom;entry.building.construction_stage=entry.prior_stage end
if craft_tool_fixture then craft_tool_fixture.raw.flags.BONE_MAT=craft_tool_fixture.bone end
assert(#building.jobs==#jobs,'Workshop capture changed job count'..(ok and '' or '\n'..tostring(err)))
for i,id in ipairs(jobs)do assert(building.jobs[i-1].id==id,'Workshop capture changed job order')end
select_map(original)
assert(df.global.pause_state and df.global.world.frame_counter==frame,'Workshop capture advanced simulation')
assert(ok,err)
records[#records+1]={name='workshop-native-reference',building_id=building.id,jobs_unchanged=true}
return result
