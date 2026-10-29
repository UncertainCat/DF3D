-- Protected paused-clone oracle. UI scratch is diagnostic evidence only.
local out,view,records,b,capture,select_map=...
local gui=require('gui');local script=require('gui.script');local g=df.global.gps
local main=df.global.game.main_interface
local function move(x,y)
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 gui.simulateInput(view,{});view:render(dfhack.getTickCount())
end
local function help(label)
 local row={name='farm-contents-help-'..label,hover=main.current_hover,enabled=main.hover_instructions_on,lines={},text_cells={},frame_cells={}}
 for y=0,17 do
  local line={}
  for x=g.dimx-25,g.dimx-1 do
   local pen=dfhack.screen.readTile(x,y)
   row.frame_cells[#row.frame_cells+1]={x=x,y=y,tile=pen.tile}
   if pen.ch>=33 and pen.ch<=255 then row.text_cells[#row.text_cells+1]={x=x,y=y,ch=pen.ch,fg=pen.fg,bg=pen.bg,bold=pen.bold}end
   if x>g.dimx-25 then line[#line+1]=(pen.ch>=32 and string.char(pen.ch%256) or ' ')end
  end
  row.lines[#row.lines+1]=dfhack.df2utf(table.concat(line)):gsub('%s+$','')
 end
 while #row.lines>0 and row.lines[#row.lines]==''do table.remove(row.lines)end
 records[#records+1]=row;return row
end
local function items()
 local rows={}
 for _,held in ipairs(b.contained_items)do
  local item=assert(held.item)
  rows[#rows+1]={id=item.id,role=df.building_item_role_type[held.use_mode],role_value=held.use_mode,
   flags=item.flags.whole,countdown=item.stockpile_countdown,delay=item.stockpile_delay,
   name=dfhack.df2utf(dfhack.items.getDescription(item,0)),type=df.item_type[item:getType()],
   position={x=item.pos.x,y=item.pos.y,z=item.pos.z}}
 end
 return rows
end
local baseline=capture('farm-contents-baseline');baseline.contents=items()
-- Diagnostic graphics provenance, never a runtime cache source. Native
-- c8745b..c87484 selects seed art via plant raw+0x208, without material tint.
local seed_art={name='farm-contents-seed-art',items={},cells={}}
local wanted={}
for index=0,math.min(5,#b.contained_items-1)do
 local item=b.contained_items[index].item
 assert(item:getType()==df.item_type.SEEDS,'seed artwork fixture changed')
 local material=assert(dfhack.matinfo.decode(item:getMaterial(),item:getMaterialIndex()))
 local plant=assert(material.plant)
 local _,address=df.sizeof(plant)
 local texture=df.reinterpret_cast('int32_t',address+0x208).value
 assert(texture>0,'native seed texture missing')
 wanted[texture]={texture=texture}
 seed_art.items[#seed_art.items+1]={id=item.id,raw_id=plant.id,material_token=material:getToken(),texture=texture}
end
for _,page in ipairs(df.global.texture.page)do
 for index,texture in ipairs(page.texpos)do
  if wanted[texture]then wanted[texture]={texture=texture,page=page.token,x=index%page.page_dim_x,y=index//page.page_dim_x}end
 end
end
for y=42,59 do for x=53,58 do
 local index=x*g.dimy+y;local texture=g.screentexpos_anchored[index]
 if texture>0 then seed_art.cells[#seed_art.cells+1]={x=x,y=y,texture=texture,offset_x=g.screentexpos_anchored_x[index],offset_y=g.screentexpos_anchored_y[index]}end
end end
for _,item in ipairs(seed_art.items)do
 item.source=wanted[item.texture];assert(item.source.page,'seed sprite is not an installed page')
 local found=false;for _,cell in ipairs(seed_art.cells)do if cell.texture==item.texture then found=true;break end end
 assert(found,'seed raw texture absent from rendered contents')
end
records[#records+1]=seed_art
local function read_contents(label)
 local before=require('json').encode(items());local guards={}
 for _,object in ipairs{main.view_sheets,df.global.plotinfo}do
  local size,address=df.sizeof(object);local bytes=df.new('uint8_t',size)
  dfhack.internal.memmove(bytes,address,size);guards[#guards+1]={size=size,address=address,bytes=bytes}
 end
 local text,code=dfhack.run_command_silent('df3d','farm-contents-read',tostring(b.id))
 assert(code==0,text);local result=require('json').decode(text)
 assert(result.building_id==b.id and #result.rows==#b.contained_items,'contents reader identity/count')
 for index,row in ipairs(result.rows)do
  local held=b.contained_items[index-1]
  assert(row.id==held.item.id and row.role_value==held.use_mode and row.flags==held.item.flags.whole,'contents reader order/facts')
  assert(row.can_dump==true and row.can_melt==false,'seed eligibility differs')
 end
 local lines={}
 for y=0,g.dimy-1 do
  local chars={};for x=0,g.dimx-1 do chars[#chars+1]=string.char(dfhack.screen.readTile(x,y).ch%256)end
  lines[#lines+1]=dfhack.df2utf(table.concat(chars))
 end
 for index=1,6 do
  local found=false;for _,line in ipairs(lines)do if line:find(result.rows[index].name,1,true)then found=true;break end end
  assert(found,'native rendered caption differs: '..result.rows[index].name)
 end
 for _,guard in ipairs(guards)do
  assert(dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)==0,'contents reader changed UI scratch');df.delete(guard.bytes)
 end
 assert(require('json').encode(items())==before,'contents reader changed item facts')
 records[#records+1]={name='farm-contents-reader-'..label,result=result,visible_names_equal=true,ui_scratch_unchanged=true}
end
read_contents('baseline')
local _,address=df.sizeof(b);local _,field=df.sizeof(b:_field('contained_items'))
baseline.contained_items_offset=field-address
assert(#baseline.contents>0,'farm contents fixture empty')
for _,probe in ipairs{{'role',732,526},{'view',756,526},{'forbid',780,526},{'dump',804,526},{'melt',828,526},{'visibility',852,526}}do
 local deadline=dfhack.getTickCount()+900
 repeat move(probe[2],probe[3]);script.sleep(1,'frames')until dfhack.getTickCount()>=deadline
 move(probe[2],probe[3])
 if main.hover_instructions_on then help(probe[1])end
 local lines={};for y=0,17 do local text={};for x=g.dimx-24,g.dimx-1 do
  local ch=dfhack.screen.readTile(x,y).ch;text[#text+1]=ch>=32 and ch<127 and string.char(ch)or' '
 end;lines[#lines+1]=table.concat(text):gsub('%s+$','')end
 records[#records+1]={name='farm-contents-hover-'..probe[1],hover=main.current_hover,
  enabled=main.hover_instructions_on,lines=lines,mouse={probe[2],probe[3]},contents=items()}
end
-- Eye controls expose the actual row identity without guessing name order.
for index=0,5 do
 move(756,526+index*36);gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 local row=capture('farm-contents-view-'..index)
 assert(row.active_sheet=='ITEM' and row.active_id==baseline.contents[index+1].id,'contents eye row identity/order differs')
 row.contents=items()
 local item=assert(df.item.find(row.active_id));local guards={}
 for _,object in ipairs{main.view_sheets,df.global.plotinfo,item}do
  local size,address=df.sizeof(object);local bytes=df.new('uint8_t',size)
  dfhack.internal.memmove(bytes,address,size);guards[#guards+1]={size=size,address=address,bytes=bytes}
 end
 local weight_line
 for y,line in ipairs(row.lines)do
  local start=line:find('Weight: ',1,true)
  if start then
   local chars={};for x=start+7,g.dimx-1 do local ch=dfhack.screen.readTile(x,y-1).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch)or' 'end
   weight_line=dfhack.df2utf(table.concat(chars):gsub('%s+$',''));break
  end
 end
 assert(weight_line,'native item weight text missing')
 local original_flags=item.flags.whole;local original_whole=item.weight.whole;local original_fraction=item.weight.fraction
 local header_ok,header_error=xpcall(function()
  for _,cold in ipairs{false,true}do
   if cold then item.flags.weight_computed=false;item.weight.whole=0;item.weight.fraction=0 end
   local text,code=dfhack.run_command_silent('df3d','farm-item-header-read',tostring(b.id),tostring(item.id));assert(code==0,text)
   local header=require('json').decode(text);assert(header.item_id==item.id and header.weight==weight_line,'semantic item weight differs from native')
   local title_found=false;for _,line in ipairs(row.lines)do if line:find(header.caption,1,true)then title_found=true end end
   assert(title_found,'semantic item title differs from native')
   for _,guard in ipairs(guards)do assert(dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)==0,'item header changed UI or differed from native weight state')end
   records[#records+1]={name='farm-item-header-reader',item_id=item.id,cold=cold,header=header,native_equal=true,ui_unchanged=true,weight_whole=item.weight.whole,weight_fraction=item.weight.fraction}
  end
 end,debug.traceback)
 item.flags.whole=original_flags;item.weight.whole=original_whole;item.weight.fraction=original_fraction
 for _,guard in ipairs(guards)do df.delete(guard.bytes)end
 assert(header_ok,header_error)
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
 select_map(b)
 assert(main.view_sheets.active_sheet==df.view_sheet_type.BUILDING and main.view_sheets.active_id==b.id,'contents fixture did not return to farm')
end
for _,probe in ipairs{{'forbid',780},{'dump',804},{'visibility',852}}do
 local original=require('json').encode(items());local flags=b.flags.whole
 local native_states={}
 for toggle=1,2 do
  move(probe[2],526);gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
  local row=capture('farm-contents-'..probe[1]..'-'..toggle)
  row.contents=items();row.building_flags=b.flags.whole
  read_contents(probe[1]..'-'..toggle)
  native_states[toggle]={contents=row.contents,building_flags=row.building_flags}
  assert(row.active_sheet=='BUILDING' and row.active_id==b.id,'contents action lost farm target')
  if toggle==1 then assert(require('json').encode(row.contents)~=original or b.flags.whole~=flags,'contents control had no effect')end
 end
 assert(require('json').encode(items())==original and b.flags.whole==flags,'contents toggle did not restore original facts')
 local action=probe[1]=='visibility' and 'hidden' or probe[1]
 local item=assert(b.contained_items[0].item)
 local function revision()
  local text,code=dfhack.run_command_silent('df3d','farm-contents-read',tostring(b.id));assert(code==0,text)
  local value=require('json').decode(text).revision;assert(type(value)=='string');return value
 end
 local function command(want,expected,outcome)
  local guards={}
  for _,object in ipairs{main.view_sheets,df.global.plotinfo}do
   local size,address=df.sizeof(object);local bytes=df.new('uint8_t',size)
   dfhack.internal.memmove(bytes,address,size);guards[#guards+1]={size=size,address=address,bytes=bytes}
  end
  local text,code=dfhack.run_command_silent('df3d','farm-item-edit',tostring(b.id),tostring(item.id),action,tostring(want),tostring(expected))
  assert(code==0,text);local result=require('json').decode(text)
  assert(result.outcome==outcome,'native adapter outcome differs: '..text)
  for _,guard in ipairs(guards)do
   assert(dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)==0,'native item action changed UI scratch')
   df.delete(guard.bytes)
  end
  return result
 end
 local stale=command(1,'1','stale')
 assert(require('json').encode(items())==original,'stale adapter changed item facts')
 for toggle=1,2 do
  local result=command(toggle==1 and 1 or 0,revision(),'completed')
  local actual={contents=items(),building_flags=b.flags.whole}
  assert(require('json').encode(actual)==require('json').encode(native_states[toggle]),'adapter differs from native item click')
  local identical=command(toggle==1 and 1 or 0,revision(),'completed')
  assert(result.mutated and not identical.mutated,'desired-value transaction entry count differs')
  assert(require('json').encode(actual)==require('json').encode({contents=items(),building_flags=b.flags.whole}),'identical intent changed item facts')
  records[#records+1]={name='farm-contents-adapter-'..action..'-'..toggle,result=result,identical=identical,stale=stale,native_equal=true,ui_scratch_unchanged=true}
 end
end
local item=b.contained_items[0].item
local read,readcode=dfhack.run_command_silent('df3d','farm-contents-read',tostring(b.id));assert(readcode==0,read)
local expected=require('json').decode(read).revision
local text,code=dfhack.run_command_silent('df3d','farm-item-edit',tostring(b.id),tostring(item.id),'melt','1',expected)
assert(code==0 and require('json').decode(text).outcome=='rejected','ineligible seed melting accepted')
for _,args in ipairs{{'-1',tostring(item.id)},{tostring(b.id),'2147483647'}}do
 local badtext,bad=dfhack.run_command_silent('df3d','farm-item-edit',args[1],args[2],'dump','1',expected)
 assert(bad~=0 or require('json').decode(badtext).outcome=='rejected','invalid contained-item target accepted')
end
-- A different row changes the contents revision even while the target's flags
-- stay identical. Preserve/restore the fixture via explicit native intents.
local second=b.contained_items[1].item
local original_hidden=second.flags.hidden and 1 or 0
local original=require('json').encode(items())
local function edit(id,want,revision,outcome)
 local text,code=dfhack.run_command_silent('df3d','farm-item-edit',tostring(b.id),tostring(id),'hidden',tostring(want),revision)
 assert(code==0,text);local result=require('json').decode(text);assert(result.outcome==outcome,text);return result
end
local changed=edit(second.id,1-original_hidden,expected,'completed')
local changed_state=require('json').encode(items())
local stale=edit(item.id,1,expected,'stale')
assert(require('json').encode(items())==changed_state,'stale cross-row revision mutated contents')
edit(second.id,original_hidden,changed.revision,'completed')
assert(require('json').encode(items())==original,'cross-row fixture not restored')
records[#records+1]={name='farm-contents-cross-row-stale',result=stale,target_flags_unchanged=true,restored=true}
-- Role names are not a rendering contract: in particular TEMP_PRINTHIDDEN
-- must be observed in this sheet before the viewer filters any contents rows.
-- Change only the held-item role in this paused diagnostic clone; retain the
-- real item and its membership/flags, and restore even if an assertion fails.
local held=b.contained_items[0]
local original_role=held.use_mode
local role_baseline=require('json').encode(items())
local ok,err=xpcall(function()
 for _,role in ipairs{0,1,2}do
  held.use_mode=role
  move(732,526)
  local deadline=dfhack.getTickCount()+900
  repeat move(732,526);script.sleep(1,'frames')until dfhack.getTickCount()>=deadline
  move(732,526)
  help('role-'..role)
  local hover=main.current_hover
  local enabled=main.hover_instructions_on
  local row=capture('farm-contents-role-'..role)
  row.role_value=role;row.role_name=df.building_item_role_type[role]
  row.role_hover=hover;row.role_help_enabled=enabled;row.contents=items()
  read_contents('role-'..role)
  move(756,526);gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
  assert(main.view_sheets.active_sheet==df.view_sheet_type.ITEM and main.view_sheets.active_id==held.item.id,'role changes first visible item identity')
  row.view_item_id=main.view_sheets.active_id
  gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());select_map(b)
 end
end,debug.traceback)
held.use_mode=original_role
assert(require('json').encode(items())==role_baseline,'role oracle did not restore item facts')
assert(ok,err)
records[#records+1]={name='farm-contents-roles-restored',restored=true}

-- Read-only rendering fixtures for task and melt instructions. No action is
-- clicked and simulation remains paused. These do not prove active job cleanup.
local seed=held.item
local seed_flags=seed.flags.whole
local probe_ok,probe_err=xpcall(function()
 seed.flags.in_job=true
 local deadline=dfhack.getTickCount()+900
 repeat move(732,526);script.sleep(1,'frames')until dfhack.getTickCount()>=deadline
 move(732,526);local task=help('task');assert(task.hover==286 and task.enabled,'task instruction missing')
 seed.flags.whole=seed_flags
 local metal
 for _,candidate in ipairs(df.global.world.items.other.WEAPON)do
  held.item=candidate
  local text,code=dfhack.run_command_silent('df3d','farm-contents-read',tostring(b.id))
  if code==0 and require('json').decode(text).rows[1].can_melt then metal=candidate;break end
 end
 assert(metal,'no native melt-eligible weapon fixture')
 local flags=metal.flags.whole
 deadline=dfhack.getTickCount()+900
 repeat move(828,526);script.sleep(1,'frames')until dfhack.getTickCount()>=deadline
 move(828,526);local melt=help('melt');melt.item_id=metal.id
 assert(melt.hover==327 and melt.enabled,'melt instruction missing')
 assert(metal.flags.whole==flags,'hover changed weapon flags')
end,debug.traceback)
held.item=seed;seed.flags.whole=seed_flags
assert(require('json').encode(items())==role_baseline,'tooltip fixture not restored')
assert(probe_ok,probe_err)
records[#records+1]={name='farm-contents-help-restored',restored=true}

-- Resize oracle reads native presentation state only in this protected lane.
local sheet=main.view_sheets
local resize_frame=df.global.world.frame_counter
local function resize_shot(label,expected_items)
 move(0,4)
 for i=1,5 do view:render(dfhack.getTickCount());script.sleep(1,'frames')end
 assert(df.global.pause_state and df.global.world.frame_counter==resize_frame,'contents resize advanced simulation')
 assert(sheet.open and sheet.active_id==b.id,'contents resize lost target')
 assert(require('json').encode(items())==(expected_items or role_baseline),'contents resize changed item facts')
 local row={name='farm-contents-resize-'..label,grid={g.dimx,g.dimy},pixels={g.screen_pixel_x,g.screen_pixel_y},lines={},positions={},item_ids={}}
 for _,held_item in ipairs(b.contained_items)do row.item_ids[#row.item_ids+1]=held_item.item.id end
 for key,value in pairs(sheet)do if type(key)=='string' and key:find('scroll_position',1,true)then row.positions[key]=value end end
 for y=0,g.dimy-1 do
  local line={};for x=0,g.dimx-1 do local ch=dfhack.screen.readTile(x,y).ch;line[#line+1]=ch>=32 and ch<127 and string.char(ch)or' 'end
  row.lines[#row.lines+1]=table.concat(line)
 end
 records[#records+1]=row
 local f=assert(io.open(out..'/shot','w'));f:write(row.name);f:close()
 local limit=dfhack.getTickCount()+30000
 while true do local ack=io.open(out..'/ack-'..row.name);if ack then ack:close();break end
  assert(dfhack.getTickCount()<limit,'contents resize capture timeout');script.sleep(1,'frames')end
end
local function resize_window(size)
 local f=assert(io.open(out..'/owner-input-request.tmp','w'));f:write('name-resize-'..size);f:close()
 assert(os.rename(out..'/owner-input-request.tmp',out..'/owner-input-request'))
 local limit=dfhack.getTickCount()+30000
 while true do local ack=io.open(out..'/owner-input-ack');if ack then ack:close();break end
  assert(dfhack.getTickCount()<limit,'contents window resize timeout');script.sleep(1,'frames')end
 assert(os.remove(out..'/owner-input-ack'))
end
for _,size in ipairs{'small','wide','default'}do resize_window(size);resize_shot(size)end

-- Native input probes, including the final page. No simulation writes.
for _,probe in ipairs{{'wheel','CONTEXT_SCROLL_DOWN',650,526},{'bar-wheel','CONTEXT_SCROLL_DOWN',880,550},{'arrow-down','_MOUSE_L',880,718},{'arrow-up','_MOUSE_L',880,514}}do
 move(probe[3],probe[4]);gui.simulateInput(view,probe[2]);resize_shot(probe[1])
end
for i=1,45 do move(880,718);gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())end
resize_shot('tail')
-- Owned diagnostic vector surgery: retain every buildingitemst allocation,
-- temporarily shorten membership while paused, then restore original order.
local saved={};for _,entry in ipairs(b.contained_items)do saved[#saved+1]=entry end
local function restore_membership()
 while #b.contained_items>0 do b.contained_items:erase(#b.contained_items-1)end
 for _,entry in ipairs(saved)do b.contained_items:insert('#',entry)end
end
local short_ok,short_error=xpcall(function()
 for _,count in ipairs{7,6,1,0}do
  restore_membership()
  while #b.contained_items>count do b.contained_items:erase(#b.contained_items-1)end
  select_map(b)
  resize_shot('short-'..count,require('json').encode(items()))
 end
end,debug.traceback)
restore_membership();select_map(b)
assert(require('json').encode(items())==role_baseline,'short-list membership not restored')
assert(short_ok,short_error)
records[#records+1]={name='farm-contents-short-restored',restored=true}

-- Saturate the scrollbar and verify actual item identity with native View.
for i=1,150 do move(880,718);gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())end
resize_shot('endpoint')
local endpoint=sheet.scroll_position_item
move(756,706);gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
assert(sheet.active_sheet==df.view_sheet_type.ITEM and sheet.active_id==saved[#saved].item.id,'endpoint last row identity differs')
records[#records+1]={name='farm-contents-endpoint-identity',cell=endpoint,last_item_id=sheet.active_id}
gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount());select_map(b)
records[#records+1]={name='farm-contents-endpoint-view-facts',before=require('json').decode(role_baseline),after=items()}
role_baseline=require('json').encode(items())
sheet.scroll_position_item=endpoint
for _,size in ipairs{'wide','small','default'}do resize_window(size);resize_shot('scrolled-'..size)end
-- Diagnostic-only state reset isolates native input mapping at each position.
local old_lift=df.global.enabler.mouse_lbut_lift
local drag_ok,drag_error=xpcall(function()
 for _,y in ipairs{500,520,550,600,700,740}do
  sheet.scroll_position_item=0;sheet.scrolling_item=false;view:render(dfhack.getTickCount())
  move(880,538);df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,{'_MOUSE_L','_MOUSE_L_DOWN'})
  g.precise_mouse_x=880;g.precise_mouse_y=y;g.mouse_x=110;g.mouse_y=(y-4)//12
  gui.simulateInput(view,{'_MOUSE_L_DOWN'})
  df.global.enabler.mouse_lbut_lift=1;gui.simulateInput(view,{})
  resize_shot('drag-'..y)
 end
end,debug.traceback)
df.global.enabler.mouse_lbut_lift=old_lift
assert(drag_ok,drag_error)
for _,probe in ipairs{{'page-key','CONTEXT_SCROLL_PAGEDOWN',650,526},{'bar-page-key','CONTEXT_SCROLL_PAGEDOWN',880,550},{'track','_MOUSE_L',880,650}}do
 sheet.scroll_position_item=0;sheet.scrolling_item=false;view:render(dfhack.getTickCount())
 move(probe[3],probe[4]);gui.simulateInput(view,probe[2]);resize_shot(probe[1])
end
