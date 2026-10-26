-- Protected native diagnostic only. Selector state is never a product input.
local out,view,records=...
local gui=require('gui');local script=require('gui.script');local g=df.global.gps
local main=df.global.game.main_interface
local base_zone
local function rng_snapshot()
 -- Diagnostic observation of DF's active RNG stream; never a product input.
 local base=dfhack.internal.getImageBase()
 local context=df.reinterpret_cast('int16_t',base+0x2159084).value
 assert(context>=0 and context<16,'unexpected RNG context')
 local state={context=context,cursor=df.reinterpret_cast('uint32_t',base+0x2131b30+context*4).value,words={}}
 for i=0,623 do state.words[#state.words+1]=df.reinterpret_cast('uint32_t',base+0x234e990+context*0x9c0+i*4).value end
 return state
end
local function restore_rng(state)
 local base=dfhack.internal.getImageBase()
 assert(df.reinterpret_cast('int16_t',base+0x2159084).value==state.context,'RNG context changed')
 df.reinterpret_cast('uint32_t',base+0x2131b30+state.context*4).value=state.cursor
 for i,value in ipairs(state.words)do df.reinterpret_cast('uint32_t',base+0x234e990+state.context*0x9c0+(i-1)*4).value=value end
end
local rack_fixture=assert(loadfile((debug.getinfo(1,'S').source:sub(2):gsub('areas%-squads%-native.lua$','areas-squad-fixture.lua'))))()
local function pixel(x,y)
 g.precise_mouse_x=x;g.precise_mouse_y=y
 g.mouse_x=x//(g.screen_pixel_x//g.dimx);g.mouse_y=y//(g.screen_pixel_y//g.dimy)
 gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
end
local function mapclick(p)
 for y=0,g.dimy-1 do for x=0,g.dimx-1 do
  g.mouse_x=x;g.mouse_y=y;g.precise_mouse_x=x*(g.screen_pixel_x//g.dimx)+4;g.precise_mouse_y=y*(g.screen_pixel_y//g.dimy)+6
  local at=dfhack.gui.getMousePos(true)
  if at and at.x==p.x and at.y==p.y and at.z==p.z then pixel(g.precise_mouse_x,g.precise_mouse_y);return end
 end end
 error('squad fixture tile not visible')
end
local function capture(name,b)
 g.mouse_x=0;g.mouse_y=0;g.precise_mouse_x=0;g.precise_mouse_y=0
 for i=1,3 do view:render(dfhack.getTickCount());script.sleep(1,'frames')end
 local ui=main.squad_selector
 local row={name=name,zone=b.id,zone_type=tostring(b.type),open=ui.open,context=ui.context,
  target=ui.bld_id,scroll=ui.scroll_position,ids={},zone_assignments={},squads={},lines={}}
 for _,id in ipairs(ui.squad_id)do row.ids[#row.ids+1]=id end
 if ui.open then
  local guards={}
  for _,value in ipairs{main,g}do
   local size,address=df.sizeof(value);local bytes=df.new('uint8_t',size)
   dfhack.internal.memmove(bytes,address,size);guards[#guards+1]={bytes=bytes,address=address,size=size}
  end
  local text,code=dfhack.run_command_silent('df3d','zone-squad-candidates-read');assert(code==0,text)
  row.semantic_ids=require('json').decode(text)
  assert(#row.semantic_ids==#row.ids,'native squad count differs')
  for i,id in ipairs(row.ids)do assert(row.semantic_ids[i]==id,'native squad order differs')end
  row.names={}
  for i=1,math.min(4,#row.ids)do
   local squad=assert(df.squad.find(row.ids[i]))
   local size,address=df.sizeof(squad);local before=df.new('uint8_t',size)
   dfhack.internal.memmove(before,address,size)
   local text,code=dfhack.run_command_silent('df3d','zone-squad-name-read',tostring(squad.id));assert(code==0,text)
   local bytes=require('json').decode(text)
   local symbol_text,symbol_code=dfhack.run_command_silent('df3d','zone-squad-symbol-read',tostring(squad.id));assert(symbol_code==0,symbol_text)
   local symbol=require('json').decode(symbol_text)
   local expected={squad.symbol,squad.foreground_r,squad.foreground_g,squad.foreground_b,squad.background_r,squad.background_g,squad.background_b}
   assert(#symbol==7,'invalid semantic symbol size')
   for n,value in ipairs(expected)do assert(symbol[n]==value,'semantic squad symbol differs')end
   assert(dfhack.internal.memcmp(before,address,size)==0,'name reader changed squad')
   df.delete(before)
   local rendered={}
   for x=54,113 do rendered[#rendered+1]=dfhack.screen.readTile(x,9+(i-1)*3).ch end
   -- Short captions compare in full; long captions retain the native clipped
   -- glyph row for the independent presentation audit.
   for n=1,math.min(#bytes,40)do assert(bytes[n]==rendered[n],'native squad name glyph differs: '..name)end
   row.names[#row.names+1]={id=squad.id,bytes=bytes,rendered=rendered,symbol=symbol,source_unchanged=true}
  end
  for _,guard in ipairs(guards)do
   assert(dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)==0,'squad reader changed UI/gps')
   df.delete(guard.bytes)
  end
  row.ui_gps_unchanged=true
 end
 for _,r in ipairs(b.squad_room_info)do row.zone_assignments[#row.zone_assignments+1]={id=r.squad_id,mode=r.mode.whole}end
 for _,s in ipairs(df.global.world.squads.all)do if s.entity_id==df.global.plotinfo.group_id then
  local squad={id=s.id,entity=s.entity_id,alias=dfhack.df2utf(s.alias),rooms={},rack_combat={},rack_training={},
   symbol=s.symbol,foreground={s.foreground_r,s.foreground_g,s.foreground_b},background={s.background_r,s.background_g,s.background_b}}
  for _,r in ipairs(s.rooms)do squad.rooms[#squad.rooms+1]={id=r.building_id,mode=r.mode.whole}end
  for _,id in ipairs(s.rack_combat)do squad.rack_combat[#squad.rack_combat+1]=id end
  for _,id in ipairs(s.rack_training)do squad.rack_training[#squad.rack_training+1]=id end
  row.squads[#row.squads+1]=squad
 end end
 local _,address=df.sizeof(ui);row.selector_rva=address-dfhack.internal.getImageBase()
 row.equipment_update_flags=df.reinterpret_cast('uint32_t',dfhack.internal.getImageBase()+0x2399858).value
 if ui.open and (name:match('%-picker$') or name:find('%-symbol%-'))then
  row.symbols={}
  local count=name:match('%-picker$') and math.min(4,#row.ids) or 1
  for i=1,count do
   local s=assert(df.squad.find(row.ids[i]))
   local symbol={id=s.id,index=s.symbol,foreground={s.foreground_r,s.foreground_g,s.foreground_b},
    background={s.background_r,s.background_g,s.background_b},solid=s.solid_texpos,blended=s.blended_texpos}
   local source=g.texpos_custom_symbol[s.symbol]
   for _,page in ipairs(df.global.texture.page)do
    for index,value in ipairs(page.texpos)do if value==source then
     symbol.page=page.token;symbol.x=index%page.page_dim_x;symbol.y=index//page.page_dim_x;break
    end end
    if symbol.page then break end
   end
   assert(symbol.page=='CUSTOM_SYMBOLS','unexpected squad symbol source')
   for _,variant in ipairs{'solid','blended'}do
    local prefix=name..'-'..i..'-'..variant
    local text,code=dfhack.run_command_silent('df3d','appearance','texture',tostring(symbol[variant]),out..'/'..prefix)
    assert(code==0 and text:find('DF3D_TEXTURE_DUMP_PASS',1,true),text)
    symbol[variant..'_file']=prefix..'.rgba'
   end
   row.symbols[#row.symbols+1]=symbol
  end
 end
 for y=0,g.dimy-1 do
  local bytes={};for x=0,g.dimx-1 do bytes[#bytes+1]=dfhack.screen.readTile(x,y).ch end
  row.lines[#row.lines+1]=bytes
 end
 records[#records+1]=row
 local f=assert(io.open(out..'/shot.tmp','w'));f:write(name);f:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local limit=dfhack.getTickCount()+30000
 while true do local ack=io.open(out..'/ack-'..name,'r');if ack then ack:close();break end
  assert(dfhack.getTickCount()<limit,'capture timed out');script.sleep(1,'frames')end
 return row
end
local function mode(b,id)
 for _,r in ipairs(b.squad_room_info)do if r.squad_id==id then return r.mode.whole end end
 return 0
end
local function toggle(name,b,id,x,y,bit)
 local expected=mode(b,id)~bit
 rack_fixture.prepare()
 pixel(x,y)
 local row=capture(name,b)
 row.rack_effects=rack_fixture.verify(id,expected)
 assert(mode(b,id)==expected,'native zone toggle differs: '..name)
 local squad=assert(df.squad.find(id));local found=false
 for _,r in ipairs(squad.rooms)do if r.building_id==b.id then
  assert(expected~=0 and r.mode.whole==expected,'native reciprocal mode differs: '..name);found=true
 end end
 assert(found==(expected~=0),'native reciprocal presence differs: '..name)
 if expected==0 then
  local retained=false
  for _,r in ipairs(b.squad_room_info)do if r.squad_id==id then retained=true end end
  assert(retained,'native zero zone record missing: '..name)
 end
 row.expected_mode=expected
end
for _,kind in ipairs{'Barracks','ArcheryRange'}do
 local b
 for _,v in ipairs(df.global.world.buildings.other.ANY_ZONE)do if v.type==df.civzone_type[kind]then b=v;break end end
 if not b and kind=='ArcheryRange' then
  assert(base_zone)
  main.bottom_mode_selected=-1;gui.simulateInput(view,'D_CIVZONE')
  local p={x=base_zone.centerx,y=base_zone.centery,z=base_zone.z}
  dfhack.gui.revealInDwarfmodeMap(p,true);view:render(dfhack.getTickCount())
  pixel(208,394);mapclick(p);mapclick(p)
  b=assert(main.civzone.cur_bld);assert(b.type==df.civzone_type.ArcheryRange,'wrong native range fixture')
  pixel(304,114)
 end
 assert(b,'missing native '..kind..' fixture');base_zone=b
 main.bottom_mode_selected=-1;gui.simulateInput(view,'D_CIVZONE')
 dfhack.gui.revealInDwarfmodeMap({x=b.centerx,y=b.centery,z=b.z},true)
 -- Diagnostic selection avoids ambiguous overlapping zones; opening uses native input.
 main.civzone.cur_bld=b;view:render(dfhack.getTickCount())
 capture(kind..'-zone',b)
 pixel(336,154)
 local opened=capture(kind..'-picker',b)
 assert(opened.open and opened.target==b.id,'native squad picker did not open')
 assert(#opened.ids>=2,'squad fixture needs two squads')
 rack_fixture.start(b,{opened.ids[1],opened.ids[2]})
 local columns=kind=='Barracks' and {{'sleep',816,1},{'train',848,2},{'equipment',880,4},{'individual',912,8}} or {{'train',912,2}}
 for _,column in ipairs(columns)do
  for n=1,2 do toggle(kind..'-first-'..column[1]..'-'..n,b,opened.ids[1],column[2],118,column[3])end
 end
 for _,column in ipairs(columns)do
  toggle(kind..'-second-'..column[1]..'-on',b,opened.ids[2],column[2],154,column[3])
 end
 for _,column in ipairs(columns)do
  toggle(kind..'-second-'..column[1]..'-off',b,opened.ids[2],column[2],154,column[3])
 end
 local entity=assert(df.global.plotinfo.main.fortress_entity)
 local original={};for _,id in ipairs(entity.squads)do original[#original+1]=id end
 local reordered={};for i=#original,1,-1 do reordered[#reordered+1]=original[i]end
 local subset={original[#original],-1,2147483647}
 local foreign
 for _,s in ipairs(df.global.world.squads.all)do if s.entity_id~=entity.id then foreign=s.id;break end end
 assert(foreign,'missing foreign squad membership probe')
 for _,case in ipairs{{'reversed',reordered},{'subset-stale',subset},{'foreign-listed',{foreign}},{'empty',{}},{'restored',original}}do
  gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
  entity.squads:resize(0);for _,id in ipairs(case[2])do entity.squads:insert('#',id)end
  pixel(336,154)
  local observed=capture(kind..'-membership-'..case[1],b)
  local expected={};for _,id in ipairs(case[2])do if df.squad.find(id)then expected[#expected+1]=id end end
  assert(#observed.ids==#expected,'native entity squad membership differs')
  for i,id in ipairs(expected)do assert(observed.ids[i]==id,'native entity squad ordering differs')end
 end
 local named=assert(df.squad.find(original[1]))
 local alias,first,nick=named.alias,named.name.first_name,named.name.nickname
 for _,case in ipairs{{'alias','Squad Alias'},{'lowercase','lowercase guard'},
  {'cp437','G'..string.char(129)..'ard '..string.char(130,132,148)},
  {'long',string.rep('1234567890',6)}}do
  named.alias=case[2]
  capture(kind..'-name-'..case[1],b)
 end
 named.alias='';named.name.first_name='first';named.name.nickname='nickname'
 capture(kind..'-name-first-nickname',b)
 named.alias=alias;named.name.first_name=first;named.name.nickname=nick
 capture(kind..'-name-restored',b)
 if kind=='Barracks' then
  local saved={}
  for _,field in ipairs{'symbol','solid_texpos','blended_texpos','foreground_r','foreground_g','foreground_b','background_r','background_g','background_b'}do saved[field]=named[field]end
  assert(#g.texpos_custom_symbol==23,'native symbol count changed')
  local main_size,main_address=df.sizeof(main);local guard=df.new('uint8_t',main_size)
  dfhack.internal.memmove(guard,main_address,main_size)
  local text,code=dfhack.run_command_silent('df3d','zone-squad-swatches-read');assert(code==0,text)
  local swatches=require('json').decode(text);assert(#swatches==1080,'owned swatch count differs')
  assert(dfhack.internal.memcmp(guard,main_address,main_size)==0,'swatch generator changed native UI');df.delete(guard)
  local n=1
  for _,field in ipairs{'swatch_r','swatch_g','swatch_b'}do for _,row in ipairs(main.custom_symbol[field])do
   for _,value in ipairs(row)do assert(swatches[n]==value,'owned native swatch differs');n=n+1 end
  end end
  assert(n==1081,'native swatch shape differs')
  for index=0,#g.texpos_custom_symbol-1 do
   named.symbol=index;named.solid_texpos=0;named.blended_texpos=0
   named.foreground_r=13;named.foreground_g=127;named.foreground_b=241
   named.background_r=233;named.background_g=61;named.background_b=7
   capture(kind..'-symbol-'..index,b)
  end
  for index,invalid in ipairs{-1,23,2147483647,-1,-1,-1,-1,-1,-1}do
   named.symbol=invalid;named.solid_texpos=0;named.blended_texpos=0
   local saved_rng
   if index>=8 then
    -- Controlled native contrast rejection: identical black first pair, then
    -- white background. Restore the owned session's original RNG afterward.
    saved_rng=rng_snapshot();local controlled=rng_snapshot();controlled.cursor=0
    if index==8 then
     for i,value in ipairs{0,0,9*214748365,0,9*214748365,35*59652324,9*214748365}do controlled.words[i]=value end
    else controlled.cursor=2496 end
    restore_rng(controlled)
   end
   local before=rng_snapshot()
   local guards={}
   for _,value in ipairs{main,g,named}do
    local size,address=df.sizeof(value);local bytes=df.new('uint8_t',size)
    dfhack.internal.memmove(bytes,address,size);guards[#guards+1]={bytes=bytes,address=address,size=size}
   end
   local text,code=dfhack.run_command_silent('df3d','zone-squad-symbol-read',tostring(named.id));assert(code==0,text)
   local product=require('json').decode(text);local product_rng=rng_snapshot()
   for i,guard in ipairs(guards)do
    if i==3 then
     -- Only the saved symbol and six color bytes may change, never cache IDs.
     for offset=0,guard.size-1 do if offset<0x1dc or offset>=0x1e6 then
      assert(guard.bytes[offset]==df.reinterpret_cast('uint8_t',guard.address+offset).value,'initializer changed unrelated squad field')
     end end
    else assert(dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)==0,'initializer changed native UI/gps')end
    df.delete(guard.bytes)
   end
   local text,code=dfhack.run_command_silent('df3d','zone-squad-symbol-read',tostring(named.id));assert(code==0,text)
   local repeated=require('json').decode(text);local repeated_rng=rng_snapshot()
   for i=1,7 do assert(product[i]==repeated[i],'valid symbol rerolled')end
   assert(product_rng.cursor==repeated_rng.cursor,'valid symbol consumed RNG')
   for i=1,624 do assert(product_rng.words[i]==repeated_rng.words[i],'valid symbol changed RNG')end
   restore_rng(before);named.symbol=invalid
   view:render(dfhack.getTickCount())
   local after=rng_snapshot()
   local initialized=capture(kind..'-initialize-'..index,b)
   initialized.initialization={invalid=invalid,before=before,after=after,swatches=swatches,controlled=index==8,refill=index==9,
    product=product,product_rng=product_rng,
    symbol={named.symbol,named.foreground_r,named.foreground_g,named.foreground_b,named.background_r,named.background_g,named.background_b}}
   for i,value in ipairs(initialized.initialization.symbol)do assert(value==product[i],'product initialization differs from native')end
   assert(after.context==product_rng.context and after.cursor==product_rng.cursor,'product RNG cursor differs from native')
   for i=1,624 do assert(after.words[i]==product_rng.words[i],'product RNG stream differs from native')end
   assert(named.symbol>=0 and named.symbol<23,'native failed to initialize symbol')
   if saved_rng then restore_rng(saved_rng)end
  end
  for field,value in pairs(saved)do named[field]=value end
 end
 gui.simulateInput(view,'LEAVESCREEN');view:render(dfhack.getTickCount())
 capture(kind..'-closed',b)
 rack_fixture.finish()
end
