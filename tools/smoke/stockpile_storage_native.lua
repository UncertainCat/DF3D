-- Protected owned lane only: pause, disable autosave, preserve save manifests,
-- and close without saving. Mutates the first pile through native clicks.
-- Run with an output directory; result.json is published atomically.
local out,repaint,gestures,eligibility_case,test_predicates=...
require('gui.script').start(function()
 local records={}
 local ok,why=pcall(function()
  local json=require('json');local gui=require('gui');local g=df.global.gps
  local view=dfhack.gui.getDFViewscreen(true)
  assert(df.global.pause_state);local frame=df.global.world.frame_counter
  assert(dfhack.run_command('disable','overlay')==0)
  local b=assert(df.global.world.buildings.other.STOCKPILE[0])
  local pile_id=b.id
  if test_predicates then
   local guards={}
   local function guard(address,size)
    local copy=df.new('uint8_t',size);dfhack.internal.memmove(copy,address,size)
    guards[#guards+1]={copy=copy,address=address,size=size}
   end
   local base=dfhack.internal.getImageBase()
   for _,range in ipairs{{0x234e990,0x6180},{0x2131b30,40},{0x2159084,2},{0x18adf98,8}}do guard(base+range[1],range[2])end
   local size,address=df.sizeof(df.global.game.main_interface);guard(address,size)
   size,address=df.sizeof(b);guard(address,size)
   local allowed={}
   for first=0,65535,1024 do
    local text,code=dfhack.run_command_silent('df3d','stockpile-tile-types-read',tostring(first),'1024');assert(code==0,text)
    local result=json.decode(text);assert(result.first==first and #result.allowed==1024)
    for index,value in ipairs(result.allowed)do assert(type(value)=='boolean');if value then allowed[#allowed+1]=first+index-1 end end
   end
   for _,args in ipairs{{'-1','1'},{'65536','1'},{'0','0'},{'0','1025'},{'65535','2'}}do
    local _,code=dfhack.run_command_silent('df3d','stockpile-tile-types-read',args[1],args[2]);assert(code~=0,'invalid range accepted')
   end
   for _,g in ipairs(guards)do assert(dfhack.internal.memcmp(g.copy,g.address,g.size)==0,'predicate changed RNG/UI/source');df.delete(g.copy)end
   records[#records+1]={name='native-tile-predicates',tested=65536,allowed=allowed,guards_unchanged=true}
  end
  local point={x=b.centerx,y=b.centery,z=b.z}
  gui.simulateInput(view,'D_STOCKPILES');df.global.game.main_interface.bottom_mode_selected=-1
  dfhack.gui.revealInDwarfmodeMap(point,true);view:render(dfhack.getTickCount())
  local function click(x,y)
   g.mouse_x=x;g.mouse_y=y;g.precise_mouse_x=x*(g.screen_pixel_x//g.dimx)+4;g.precise_mouse_y=y*(g.screen_pixel_y//g.dimy)+6
   gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
  end
  local found=false
  for y=0,g.dimy-1 do for x=0,g.dimx-1 do
   g.mouse_x=x;g.mouse_y=y;g.precise_mouse_x=x*(g.screen_pixel_x//g.dimx)+4;g.precise_mouse_y=y*(g.screen_pixel_y//g.dimy)+6
   local p=dfhack.gui.getMousePos(true)
   if p and p.x==point.x and p.y==point.y and p.z==point.z then click(x,y);found=true;break end
  end if found then break end end
  assert(found,'no pile pointer');require('gui.script').sleep(2,'frames');view:render(dfhack.getTickCount())
  local function capture(name)
   g.mouse_x=0;g.mouse_y=0;view:render(dfhack.getTickCount());require('gui.script').sleep(3,'frames')
   local lines={};for y=0,g.dimy-1 do local line={};for x=0,g.dimx-1 do local t=dfhack.screen.readTile(x,y);line[#line+1]=(t.ch>=32 and t.ch<127)and string.char(t.ch)or' ' end;lines[#lines+1]=table.concat(line)end
   local f=assert(io.open(out..'/'..name..'.txt','w'));f:write(table.concat(lines,'\n'));f:close()
   local alive=df.building.find(pile_id)
   records[#records+1]=alive and {name=name,barrels=alive.storage.max_barrels,bins=alive.storage.max_bins,wheelbarrows=alive.storage.max_wheelbarrows} or {name=name,removed=true}
   f=assert(io.open(out..'/shot.tmp','w'));f:write(name);f:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
   local limit=dfhack.getTickCount()+30000
   while not io.open(out..'/ack-'..name,'r')do assert(dfhack.getTickCount()<limit,'capture timeout');require('gui.script').sleep(1,'frames')end
  end
  capture('pile')
  if repaint then
   click(38,9) -- Native pile repaint icon at304,118 in pile.png.
   local paint=df.global.game.main_interface.stockpile
   assert(paint.repainting,'repaint did not open')
   capture('repaint')
   local cells={}
   for y=b.y1,b.y2 do for x=b.x1,b.x2 do
    if not b.room.extents or b.room.extents[(y-b.room.y)*b.room.width+x-b.room.x]~=0 then cells[#cells+1]={x=x,y=y,z=b.z}end
   end end
   assert(#cells==dfhack.buildings.countExtentTiles(b,-1) and #cells>3)
   local assigned_ids={}
   for _,id in ipairs(b.storage.container_item_id)do assigned_ids[#assigned_ids+1]=id end
   local function assignments(name)
    local rows,items={},{}
    local alive=df.building.find(pile_id)
    if alive then
     for i,id in ipairs(alive.storage.container_item_id)do
      rows[#rows+1]={id=id,type=alive.storage.container_type[i],x=alive.storage.container_x[i],y=alive.storage.container_y[i]}
     end
    end
    for _,id in ipairs(assigned_ids)do
     local item=df.item.find(id);local ref=item and item:getStockpile2()
     items[#items+1]={id=id,exists=item~=nil,assignment=ref and {id=ref.id,x=ref.x,y=ref.y} or false}
    end
    records[#records+1]={name=name,containers=rows,items=items}
   end
   local function mapclick(p,phase)
    dfhack.gui.revealInDwarfmodeMap(p,true);view:render(dfhack.getTickCount())
    for y=0,g.dimy-1 do for x=0,g.dimx-1 do
     g.mouse_x=x;g.mouse_y=y;g.precise_mouse_x=x*(g.screen_pixel_x//g.dimx)+4;g.precise_mouse_y=y*(g.screen_pixel_y//g.dimy)+6
     local hit=dfhack.gui.getMousePos(true)
     if hit and hit.x==p.x and hit.y==p.y and hit.z==p.z then
      if phase then
       local e=df.global.enabler;local lift=e.mouse_lbut_lift
       e.mouse_lbut_lift=phase=='release' and 1 or 0
       local ok,why=pcall(function()
        gui.simulateInput(view,phase=='press' and {'_MOUSE_L','_MOUSE_L_DOWN'} or phase=='hold' and {'_MOUSE_L_DOWN'} or {})
        view:render(dfhack.getTickCount())
       end)
       e.mouse_lbut_lift=lift;assert(ok,why)
      else click(x,y)end
      return
     end
    end end
    error('repaint tile is not visible')
   end
   local function record(name)
    b=assert(df.building.find(pile_id),'pile unexpectedly removed before '..name)
    records[#records+1]={name=name,tiles=dfhack.buildings.countExtentTiles(b,-1),barrels=b.storage.max_barrels,bins=b.storage.max_bins,wheelbarrows=b.storage.max_wheelbarrows,
     bounds={b.x1,b.y1,b.x2,b.y2},repainting=paint.repainting,erasing=paint.erasing,
     current=paint.cur_bld and paint.cur_bld.id or -1,bottom_mode=df.global.game.main_interface.bottom_mode_selected,
     corner={df.global.selection_rect.start_x,df.global.selection_rect.start_y,df.global.selection_rect.start_z}}
   end
   if gestures=='transfer-partial' or gestures=='transfer-full' or gestures=='transfer-create-partial' or gestures=='transfer-create-full' or gestures=='transfer-erase-partial' or gestures=='transfer-erase-full' then
    local creating=gestures:find('create',1,true)~=nil
    local donor
    for _,candidate in ipairs(df.global.world.buildings.other.STOCKPILE)do
     if candidate.id~=b.id and candidate.z==b.z and #candidate.storage.container_item_id>0 and
      math.max(candidate.x2,b.x2)-math.min(candidate.x1,b.x1)<128 and math.max(candidate.y2,b.y2)-math.min(candidate.y1,b.y1)<128 then donor=candidate;break end
    end
    assert(donor,'no nearby stocked donor')
    local donor_id=donor.id;local donor_cells,items={},{}
    for y=donor.y1,donor.y2 do for x=donor.x1,donor.x2 do
     if dfhack.buildings.containsTile(donor,x,y)then donor_cells[#donor_cells+1]={x=x,y=y,z=donor.z}end
    end end
    for _,id in ipairs(donor.storage.container_item_id)do items[#items+1]=id end
    local first,last
    if gestures:find('partial',1,true) then
     first={x=donor.storage.container_x[0],y=donor.storage.container_y[0],z=donor.z};last=first
    else first={x=donor.x1,y=donor.y1,z=donor.z};last={x=donor.x2,y=donor.y2,z=donor.z}end
    local function donor_record(name)
     local current=df.building.find(donor_id);local assignments={}
     for _,id in ipairs(items)do
      local item=assert(df.item.find(id));local ref=item:getStockpile2()
      assignments[#assignments+1]={id=id,assignment=ref and {id=ref.id,x=ref.x,y=ref.y} or false}
     end
     local transferred,retained=0,0
     for _,p in ipairs(donor_cells)do
      if dfhack.buildings.containsTile(b,p.x,p.y)then transferred=transferred+1 end
      if current and dfhack.buildings.containsTile(current,p.x,p.y)then retained=retained+1 end
     end
     records[#records+1]={name=name,donor_id=donor_id,donor_exists=current~=nil,first=first,last=last,
      donor_tiles=current and dfhack.buildings.countExtentTiles(current,-1) or 0,transferred=transferred,retained=retained,
      donor_containers=current and #current.storage.container_item_id or 0,items=assignments,
      donor_limits=current and {current.storage.max_barrels,current.storage.max_bins,current.storage.max_wheelbarrows} or false}
    end
    if creating then
     first={x=donor.x1-1,y=donor.y1,z=donor.z}
     local block=assert(dfhack.maps.getTileBlock(first));assert(not block.designation[first.x%16][first.y%16].pile and block.occupancy[first.x%16][first.y%16].building==0,'creation anchor occupied')
    end
    donor_record('donor-before');record('recipient-before')
    local next_id=df.global.building_next_id
    if creating then gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());gui.simulateInput(view,'D_STOCKPILES');view:render(dfhack.getTickCount())end
    if gestures:find('erase',1,true)then click(84,61);assert(paint.erasing)end
    mapclick(first);mapclick(last)
    if creating then b=assert(df.building.find(next_id),'transfer creation failed')end
    donor_record('donor-after')
    if creating then records[#records+1]={name='created-recipient',id=b.id,tiles=dfhack.buildings.countExtentTiles(b,-1),bounds={b.x1,b.y1,b.x2,b.y2}} else record('recipient-after')end
    capture(gestures)
    assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
    return
   end
   if gestures=='eligibility-grow' then
    assert(eligibility_case=='floor' or eligibility_case=='wall-left' or eligibility_case=='wall-right' or eligibility_case=='all-wall')
    local first,last
    for ty=b.y1,b.y2 do
     local free=true
     for tx=b.x2+1,b.x2+3 do
      local block=dfhack.maps.getTileBlock(tx,ty,b.z)
      if not block or block.designation[tx%16][ty%16].pile or block.occupancy[tx%16][ty%16].building~=0 then free=false;break end
     end
     if free then first={x=b.x2+1,y=ty,z=b.z};last={x=b.x2+3,y=ty,z=b.z};break end
    end
    assert(first,'no free growth span along right edge')
    local saved={}
    for tx=first.x,last.x do
     local block=assert(dfhack.maps.getTileBlock(tx,first.y,first.z));local x,y=tx%16,first.y%16
     assert(not block.designation[x][y].pile and block.occupancy[x][y].building==0,'growth fixture overlaps existing building')
     saved[#saved+1]={block=block,x=x,y=y,tile=block.tiletype[x][y],designation=block.designation[x][y].whole}
     block.tiletype[x][y]=(eligibility_case=='all-wall' or eligibility_case=='wall-left' and tx==first.x or eligibility_case=='wall-right' and tx==last.x) and df.tiletype.StoneWall or df.tiletype.StoneFloor1
     block.designation[x][y].hidden=false;block.designation[x][y].flow_size=0
    end
    record('before-grow')
    mapclick(first);mapclick(last)
    record('after-grow')
    local mask={};for tx=first.x,last.x do mask[#mask+1]=dfhack.buildings.containsTile(b,tx,first.y)end
    records[#records+1]={name='grow-cells',case=eligibility_case,first=first,last=last,mask=mask}
    capture('eligibility-grow-'..eligibility_case)
    for _,s in ipairs(saved)do
     s.block.tiletype[s.x][s.y]=s.tile
     local pile=s.block.designation[s.x][s.y].pile
     s.block.designation[s.x][s.y].whole=s.designation;s.block.designation[s.x][s.y].pile=pile
    end
    assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
    return
   end
   if gestures=='eligibility' or gestures=='eligibility-create' or gestures=='eligibility-erase' then
    local first,last
    for _,p in ipairs(cells)do
     if dfhack.buildings.containsTile(b,p.x+1,p.y) and dfhack.buildings.containsTile(b,p.x+2,p.y)then
      first=p;last={x=p.x+2,y=p.y,z=p.z};break
     end
    end
    assert(first,'no three-cell eligibility span')
    local middle={x=first.x+1,y=first.y,z=first.z}
    if eligibility_case=='wall-left' then middle=first elseif eligibility_case=='wall-right' then middle=last end
    local block=assert(dfhack.maps.getTileBlock(middle));local x,y=middle.x%16,middle.y%16
    local tile=block.tiletype[x][y];local designation=block.designation[x][y].whole;local occupancy=block.occupancy[x][y].whole
    local function restore()
     block.tiletype[x][y]=tile;block.designation[x][y].whole=designation;block.occupancy[x][y].whole=occupancy
    end
    local cases={{name='floor'},{name='wall',tile='StoneWall'},{name='water1',depth=1},{name='water2',depth=2},
     {name='water7',depth=7},{name='magma1',depth=1,magma=true},{name='building1',building=1},{name='building2',building=2},
     {name='hidden',hidden=true},{name='ramp',tile='StoneRamp'},{name='open',tile='OpenSpace'},{name='all-wall',tile='StoneWall',all_wall=true}}
    if eligibility_case=='wall-left' or eligibility_case=='wall-right' then cases={{name=eligibility_case,tile='StoneWall'}}end
    if eligibility_case and eligibility_case~='all' then
     local filtered={};for _,case in ipairs(cases)do if case.name==eligibility_case then filtered[1]=case end end
     assert(#filtered==1,'unknown eligibility case');cases=filtered
    end
    for _,case in ipairs(cases)do
     restore()
     if paint.erasing then click(84,61)end
     mapclick(first);mapclick(last)
     if gestures~='eligibility-erase' then
      click(84,61);assert(paint.erasing and paint.doing_rectangle)
      mapclick(first);mapclick(last)
      assert(not dfhack.buildings.containsTile(b,first.x,first.y) and not dfhack.buildings.containsTile(b,last.x,last.y),'erase setup failed')
     end
     block.tiletype[x][y]=assert(df.tiletype[case.tile or 'StoneFloor1'])
     block.designation[x][y].hidden=case.hidden or false
     block.designation[x][y].flow_size=case.depth or 0;block.designation[x][y].liquid_type=case.magma or false
     block.occupancy[x][y].building=case.building or 0
     if case.all_wall then
      for _,p in ipairs{first,last}do local cell=assert(dfhack.maps.getTileBlock(p));cell.tiletype[p.x%16][p.y%16]=df.tiletype.StoneWall end
     end
     if test_predicates then
      local text,code=dfhack.run_command_silent('df3d','stockpile-tile-types-read',tostring(block.tiletype[x][y]),'1');assert(code==0,text)
      case.native_tile_eligible=json.decode(text).allowed[1]
     end
     local created
     if gestures=='eligibility-create' then
      gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
      gui.simulateInput(view,'D_STOCKPILES');view:render(dfhack.getTickCount())
      local next_id=df.global.building_next_id
      mapclick(first);mapclick(last)
      for _,candidate in ipairs(df.global.world.buildings.other.STOCKPILE)do if candidate.id>=next_id then assert(not created,'multiple piles created');created=candidate end end
      if case.all_wall then
       assert(not created,'all-wall rectangle unexpectedly created a pile')
       records[#records+1]={name=case.name,setup=case,created=false,first=first,middle=middle,last=last,bottom_mode=df.global.game.main_interface.bottom_mode_selected}
       capture('eligibility-created-none')
       assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
       return
      end
      assert(created,'native created no pile for mixed rectangle')
     else
      click(84,61);assert(paint.erasing==(gestures=='eligibility-erase'))
      mapclick(first);mapclick(last)
     end
     local observed=created or b
     records[#records+1]={name=case.name,first=first,middle=middle,last=last,setup=case,
      tiletype=df.tiletype[block.tiletype[x][y]],designation=block.designation[x][y].whole,occupancy=block.occupancy[x][y].whole,
      start_present=dfhack.buildings.containsTile(observed,first.x,first.y),middle_present=dfhack.buildings.containsTile(observed,middle.x,middle.y),
      end_present=dfhack.buildings.containsTile(observed,last.x,last.y),tiles=dfhack.buildings.countExtentTiles(observed,-1),
      id=observed.id,bounds={observed.x1,observed.y1,observed.x2,observed.y2}}
     if test_predicates then
      local expected=case.native_tile_eligible and not case.hidden and (not case.building or case.building==0)
      assert(dfhack.buildings.containsTile(observed,middle.x,middle.y)==expected,'native UI disagrees with owned scalar predicate and occupancy/visibility')
     end
     if created then
      capture('eligibility-created-'..case.name)
      assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
      return
     end
    end
    restore();capture('eligibility-completed')
    assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
    return
   end
   if gestures=='brush' then
    click(81,61);click(84,61);assert(paint.erasing and not paint.doing_rectangle)
    local first,last
    for _,p in ipairs(cells)do
     if dfhack.buildings.containsTile(b,p.x+1,p.y) and dfhack.buildings.containsTile(b,p.x+2,p.y)then
      first=p;last={x=p.x+2,y=p.y,z=p.z};break
     end
    end
    assert(first,'no three-cell brush span')
    record('brush-before');mapclick(first,'press');record('brush-press')
    mapclick(last,'hold');record('brush-held-jump');mapclick(last,'release');record('brush-release')
    records[#records+1]={name='brush-cells',first=first,last=last,
     start_present=dfhack.buildings.containsTile(b,first.x,first.y),
     middle_present=dfhack.buildings.containsTile(b,first.x+1,first.y),
     end_present=dfhack.buildings.containsTile(b,last.x,last.y)}
    capture('brush-completed')
    assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
    return
   end
   if gestures then
    click(84,61);assert(paint.erasing and paint.doing_rectangle)
    record('gesture-before')
    mapclick(cells[#cells]);record('first-corner')
    mapclick(cells[#cells]);record('completed-erase')
    capture('gesture-committed')
    if gestures:find('partial',1,true)then
     mapclick(cells[#cells-1]);record('partial-before-exit')
    end
    local key=gestures:find('right',1,true)and '_MOUSE_R' or 'LEAVESCREEN'
    gui.simulateInput(view,key);view:render(dfhack.getTickCount());record(gestures)
    capture(gestures)
    assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
    return
   end
   for _,key in ipairs{'barrels','bins','wheelbarrows'}do b.storage['max_'..key]=#cells end
   record('before-shrink')
   assignments('assignments-before')
   click(84,61) -- Eraser at678,742 in protected repaint.png (1200x800).
   assert(paint.erasing and paint.doing_rectangle,'rectangle erase did not activate')
   for index=#cells,2,-1 do
    mapclick(cells[index]);mapclick(cells[index])
    assert(dfhack.buildings.countExtentTiles(b,-1)==index-1,'erase did not remove exactly one tile')
    record('erase-'..index)
    if index==#cells or index==2 then assignments('assignments-after-erase-'..index)end
   end
   capture('one-tile')
   click(84,61);assert(not paint.erasing,'erase did not toggle off')
   mapclick(cells[2]);mapclick(cells[2]);record('regrow-two')
   capture('regrown')
   b.storage.max_barrels=0;b.storage.max_bins=2;b.storage.max_wheelbarrows=0
   record('mixed-limits-two')
   click(84,61);assert(paint.erasing)
   mapclick(cells[2]);mapclick(cells[2]);record('mixed-limits-one')
   mapclick(cells[1]);mapclick(cells[1]);record('erased-all')
   capture('empty')
   assignments('assignments-empty')
   click(84,61);assert(not paint.erasing)
   mapclick(cells[1]);mapclick(cells[1]);record('regrow-empty')
   click(84,61);assert(paint.erasing)
   mapclick(cells[1]);mapclick(cells[1]);record('empty-before-accept')
   click(38,6) -- Accept at310,82, observed in repaint.png.
   records[#records+1]={name='accept-empty',exists=df.building.find(pile_id)~=nil,repainting=paint.repainting,current=paint.cur_bld and paint.cur_bld.id or -1}
   capture('accepted-empty')
   gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
   records[#records+1]={name='escape-empty',exists=df.building.find(pile_id)~=nil,repainting=paint.repainting,current=paint.cur_bld and paint.cur_bld.id or -1}
   capture('escaped-empty')
   assignments('assignments-after-exit')
   assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
   return
  end
  click(42,15) -- Storage/tool barrel icon observed in protected pile.png
  capture('storage')
  local ui=df.global.game.main_interface.stockpile_tools
  local tiles=dfhack.buildings.countExtentTiles(b,-1)
  local function observe(name,key,before)
   records[#records+1]={name=name,key=key,before=before,after=b.storage['max_'..key],tiles=tiles,open=ui.open,entering=ui['entering_'..key],text=ui.number_str}
  end
  for index,key in ipairs{'barrels','bins','wheelbarrows'}do
   local y=10+(index-1)*3
   local cap=tiles-(key=='wheelbarrows' and 1 or 0)
   for _,value in ipairs{0,cap-1,cap,cap+1,32767}do
    b.storage['max_'..key]=value;view:render(dfhack.getTickCount());click(80,y);observe('plus',key,value)
    b.storage['max_'..key]=value;view:render(dfhack.getTickCount());click(84,y);observe('minus',key,value)
   end
   for _,text in ipairs{'1',tostring(cap),tostring(cap+1),'99999','-1','abc',''}do
    b.storage['max_'..key]=7;view:render(dfhack.getTickCount());click(76,y)
    assert(ui['entering_'..key],'number field did not focus')
    observe('entry-open',key,7)
    for i=1,#text do df.global.enabler.last_text_input[0]=text:byte(i);df.global.enabler.last_text_input[1]=0;gui.simulateInput(view,string.format('STRING_A%03d',text:byte(i)))end
    observe('entry-typed-'..text,key,7)
    gui.simulateInput(view,'SELECT');view:render(dfhack.getTickCount());observe('entry-submit-'..text,key,7)
    if ui['entering_'..key] then gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())end
   end
   b.storage['max_'..key]=7;view:render(dfhack.getTickCount());click(76,y)
   for _,byte in ipairs{49,50}do df.global.enabler.last_text_input[0]=byte;df.global.enabler.last_text_input[1]=0;gui.simulateInput(view,string.format('STRING_A%03d',byte))end
   observe('before-escape',key,7);gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());observe('after-escape',key,7)
   if not ui.open then click(42,15)end
   click(76,y)
   for _,byte in ipairs{49,50}do df.global.enabler.last_text_input[0]=byte;df.global.enabler.last_text_input[1]=0;gui.simulateInput(view,string.format('STRING_A%03d',byte))end
   gui.simulateInput(view,'STRING_A000');observe('backspace-one',key,7)
   gui.simulateInput(view,'STRING_A000');observe('backspace-empty',key,7)
   gui.simulateInput(view,'SELECT')
  end
  capture('storage-after-input')
  assert(df.global.pause_state and df.global.world.frame_counter==frame,'simulation advanced')
 end)
 local f=assert(io.open(out..'/result.json.tmp','w'));f:write(require('json').encode{success=ok,error=ok and '' or tostring(why),records=records});f:close();assert(os.rename(out..'/result.json.tmp',out..'/result.json'))
end)
print('STOCKPILE_STORAGE_STARTED')
