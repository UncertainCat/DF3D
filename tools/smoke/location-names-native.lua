-- Protected owned paused diagnostic only. Native name-editor scratch is not a runtime API.
local out,view,records=...
local gui=require('gui');local script=require('gui.script');local g=df.global.gps
local m=df.global.game.main_interface;local details=m.location_details;local creator=m.name_creator
local function rng_snapshot()
 -- Controlled comparison only; runtime never snapshots or restores RNG.
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
local function word_part(index)
 -- DF's1fc330 copies and indexes this vector in4-byte units. The current
 -- DFHack name_creator binding incorrectly declares vector<part_of_speech>
 -- (int16); language_word_table.parts correctly specifies int32 storage.
 local _,address=df.sizeof(creator:_field('word_index_asp'))
 local first=df.reinterpret_cast('uint64_t',address).value
 local last=df.reinterpret_cast('uint64_t',address+8).value
 assert(last-first==#creator.word_index*4,'native name word/part vector size mismatch')
 return df.reinterpret_cast('int32_t',first+index*4).value
end
local function key(value)gui.simulateInput(view,value);view:render(dfhack.getTickCount())end
local function window_input(action)
 local f=assert(io.open(out..'/owner-input-request.tmp','w'));f:write(action);f:close()
 assert(os.rename(out..'/owner-input-request.tmp',out..'/owner-input-request'))
 local limit=dfhack.getTickCount()+30000
 while true do
  local ack=io.open(out..'/owner-input-ack');if ack then ack:close();break end
  assert(dfhack.getTickCount()<limit,'native window input timeout');script.sleep(1,'frames')
 end
 assert(os.remove(out..'/owner-input-ack'));script.sleep(5,'frames')
end
local function pixel(x,y)
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=y//12;key('_MOUSE_L')
end
local function name_value(name)
 local value={first_name=name.first_name,nickname=name.nickname,language=name.language,type=name.type,has_name=name.has_name,words={},parts_of_speech={}}
 for i=0,6 do value.words[#value.words+1]=name.words[i];value.parts_of_speech[#value.parts_of_speech+1]=name.parts_of_speech[i]end
 return value
end
local function capture(label,location,keep_pointer)
 if not keep_pointer then g.mouse_x=0;g.mouse_y=0;g.precise_mouse_x=0;g.precise_mouse_y=0 end
 local pointer={g.precise_mouse_x,g.precise_mouse_y,g.mouse_x,g.mouse_y}
 local function retain_pointer()
  if keep_pointer then
   df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
   g.precise_mouse_x=pointer[1];g.precise_mouse_y=pointer[2];g.mouse_x=pointer[3];g.mouse_y=pointer[4]
   gui.simulateInput(view,{})
  end
 end
 for i=1,3 do retain_pointer();view:render(dfhack.getTickCount());script.sleep(1,'frames')end
 retain_pointer();view:render(dfhack.getTickCount())
 local row={name=label,id=location.id,kind=df.abstract_building_type[location:getType()],details_open=details.open,
  creator_open=creator.open,context=creator.context,name_type=creator.name_type,name_value=name_value(location:getName()),
  name_place=creator.cur_name_place,word_place=creator.cur_word_place,filter=creator.cull_str,
  entering_filter=creator.entering_cull_str,entering_first_name=creator.entering_first_name,
  word_count=#creator.word_index,word_index={},word_parts={},lines={},scroll_position=creator.scroll_position_word,
  pointer={g.precise_mouse_x,g.precise_mouse_y,g.mouse_x,g.mouse_y},grid={g.dimx,g.dimy},
  staff_scroll=details.scroll_position_occupation,staff_count=#details.loc_occupation+#details.loc_position}
 for i=0,#creator.word_index-1 do row.word_index[#row.word_index+1]=creator.word_index[i];row.word_parts[#row.word_parts+1]=word_part(i)end
 if #records==0 then
  row.native_fields={}
  for _,field in ipairs{'open','context','namer','name','name_type','cur_name_place','cur_word_place','word_sel','word_index','word_index_asp','cull_str'}do
   local _,address=df.sizeof(creator:_field(field));row.native_fields[field]=address-dfhack.internal.getImageBase()
  end
 end
 if creator.name then local _,a=df.sizeof(creator.name);local _,b=df.sizeof(location:getName());row.direct_name_target=a==b end
 if creator.namer then row.namer_id=creator.namer.id end
 if creator.open and (label:match('%-name%-open$') or label:match('%-selected$') or label:match('%-filter%-ale$') or label:match('%-filter%-al$') or label:match('%-matrix%-'))then
  local guards={}
  for _,object in ipairs{m,g}do
   local n,at=df.sizeof(object);local bytes=df.new('uint8_t',n);dfhack.internal.memmove(bytes,at,n)
   guards[#guards+1]={bytes=bytes,address=at,size=n}
  end
  local rng_before=rng_snapshot()
  local function read_name()
   local text,code=dfhack.run_command_silent('df3d','location-name-read',tostring(df.global.plotinfo.site_id),tostring(location.id))
   assert(code==0,text);local value=require('json').decode(text);assert(value.valid and value.revision,'name read failed');return value
  end
  local observed_name=read_name();local repeated_name=read_name()
  assert(observed_name.header_valid,'native header formatter unavailable')
  local headers={native=observed_name.native_header,english=observed_name.english_header,matched=0}
  for _,entry in ipairs{{observed_name.native_header,7},{'"'..observed_name.english_header..'"',8}}do
   local expected=dfhack.utf2df(entry[1]);local chars={}
   for x=0,g.dimx-1 do chars[#chars+1]=string.char(dfhack.screen.readTile(x,entry[2]).ch&255)end
   if #expected<=75 then
    assert(table.concat(chars):find(expected,1,true),'native header text differs from drawn row')
    headers.matched=headers.matched+1
   end
  end
  row.bridge_headers=headers
  assert(require('json').encode(observed_name.name)==require('json').encode(row.name_value),'structured name differs')
  assert(observed_name.revision==repeated_name.revision,'unchanged name revision unstable')
  assert(observed_name.namer_id==df.global.plotinfo.civ_id,'name receipt uses wrong entity')
  row.bridge_name_revision=observed_name.revision
  if label=='TEMPLE-0-name-open' then
   local name=location:getName();assert(name.words[0]==-1,'expected unused front component')
   local original=name.parts_of_speech[0];name.parts_of_speech[0]=df.part_of_speech.NounPlural
   local ok,changed=xpcall(read_name,debug.traceback)
   name.parts_of_speech[0]=original
   assert(ok,changed);assert(changed.revision~=observed_name.revision,'hidden structured change did not invalidate receipt')
   assert(read_name().revision==observed_name.revision,'restored name did not recover receipt')
   row.bridge_hidden_name_change_detected=true
  end
  assert(require('json').encode(rng_before)==require('json').encode(rng_snapshot()),'name observation consumed RNG')
  local text,code=dfhack.run_command_silent('df3d','location-name-words',tostring(creator.cur_name_place),dfhack.df2utf(creator.cull_str),tostring(location:getName().language))
  assert(code==0,text);local observed=require('json').decode(text)
  assert(observed.valid and #observed.words==#creator.word_index,'native word-selector count mismatch')
  for i,pair in ipairs(observed.words)do
   if pair[1]~=creator.word_index[i-1] or pair[2]~=word_part(i-1)then
    local f=assert(io.open(out..'/word-mismatch.json','w'))
    f:write(require('json').encode({name=label,index=i,bridge=observed.words,native_words=row.word_index,native_parts=row.word_parts}));f:close()
    error('native word-selector mismatch at '..i..': '..tostring(pair[1])..'/'..tostring(pair[2])..' versus '..tostring(creator.word_index[i-1])..'/'..tostring(word_part(i-1)))
   end
   assert(pair[3]==dfhack.df2utf(df.global.world.raws.language.words[pair[1]].forms[pair[2]]),'native English word form mismatch')
   local language=location:getName().language;local translations=df.global.world.raws.language.translations
   local translated=''
   if language>=0 and language<#translations and pair[1]<#translations[language].words then translated=translations[language].words[pair[1]].value end
   assert(pair[4]==dfhack.df2utf(translated),'native language word mismatch')
  end
  if label=='TEMPLE-0-name-open' then
   local blank_text,blank_code=dfhack.run_command_silent('df3d','location-name-words','0','','-1')
   assert(blank_code==0,blank_text);local blank=require('json').decode(blank_text)
   assert(blank.valid and #blank.words==#observed.words)
   for _,pair in ipairs(blank.words)do assert(pair[4]=='','missing language should be blank')end
   row.bridge_missing_language_blank=true
  end
  for _,guard in ipairs(guards)do
   assert(dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)==0,'word observation changed native UI/gps')
   df.delete(guard.bytes)
  end
  row.bridge_word_count=#observed.words;row.bridge_ui_unchanged=true;row.bridge_forms_verified=true;row.bridge_translations_verified=true
 end
 for y=0,g.dimy-1 do
  local chars={};for x=0,g.dimx-1 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and ch<=255 and string.char(ch) or ' 'end
  row.lines[#row.lines+1]=table.concat(chars):gsub('%s+$','')
 end
 records[#records+1]=row
 local f=assert(io.open(out..'/shot.tmp','w'));f:write(label);f:close();assert(os.rename(out..'/shot.tmp',out..'/shot'))
 local limit=dfhack.getTickCount()+30000
 while true do local ack=io.open(out..'/ack-'..label);if ack then ack:close();break end;assert(dfhack.getTickCount()<limit,'capture timeout');script.sleep(1,'frames')end
 return row
end
local invalid_edits_checked=false
local function prepare_edit(location,mode,target,displayed,word,part,query)
 local json=require('json');local name=location:getName();local original=name_value(name);local rng=rng_snapshot()
 local text,code=dfhack.run_command_silent('df3d','location-name-read',tostring(df.global.plotinfo.site_id),tostring(location.id))
 assert(code==0,text);local observed=json.decode(text);assert(observed.valid)
 local guards={}
 for _,object in ipairs{m,g}do
  local n,at=df.sizeof(object);local bytes=df.new('uint8_t',n);dfhack.internal.memmove(bytes,at,n)
  guards[#guards+1]={bytes=bytes,address=at,size=n}
 end
 local function edit(receipt)
  local output,result=dfhack.run_command_silent('df3d','location-name-edit',tostring(df.global.plotinfo.site_id),tostring(location.id),
   tostring(mode),tostring(target),tostring(displayed),tostring(word),tostring(part),receipt,dfhack.df2utf(query))
  assert(result==0,output);return json.decode(output).outcome
 end
 local invalid_cases={}
 if not invalid_edits_checked then
  local cases={
   {'negative-site',{[1]='-1'}},{'other-site',{[1]=tostring(df.global.plotinfo.site_id+1)}},
   {'negative-location',{[2]='-1'}},{'missing-location',{[2]='2147483647'}},
   {'negative-target',{[4]='-1'}},{'large-target',{[4]='7'}},
   {'negative-displayed',{[5]='-1'}},{'large-displayed',{[5]='7'}},
   {'zero-revision',{[8]='0'}},{'oversized-revision',{[8]='9223372036854775808'}},
   {'clear-with-word',{[6]='0'}},{'clear-with-part',{[7]='0'}},
   {'select-wrong-component',{[3]='1',[5]='1',[6]='0',[7]='0'}},
   {'select-missing-word',{[3]='1',[6]='2147483647',[7]='0'}},
   {'select-negative-part',{[3]='1',[6]='0',[7]='-1'}},
   {'select-large-part',{[3]='1',[6]='0',[7]='9'}},
   {'select-filtered-out',{[3]='1',[6]='0',[7]='0',[9]='ZZZZ'}},
   {'random-empty-pool',{[3]='2',[9]='ZZZZ'}},
   {'whole-with-target',{[3]='3',[5]='-1'}},
   {'whole-with-query',{[3]='3',[4]='-1',[5]='-1',[9]='x'}},
  }
  for _,case in ipairs(cases)do
   local args={tostring(df.global.plotinfo.site_id),tostring(location.id),'0','0','0','-1','-1',observed.revision,''}
   for index,value in pairs(case[2])do args[index]=value end
   local output,result=dfhack.run_command_silent('df3d','location-name-edit',table.unpack(args))
   assert(result==0 and json.decode(output).outcome==0,'invalid edit accepted: '..case[1])
   assert(json.encode(name_value(name))==json.encode(original),'invalid edit changed name: '..case[1])
   assert(json.encode(rng_snapshot())==json.encode(rng),'invalid edit consumed RNG: '..case[1])
   invalid_cases[#invalid_cases+1]=case[1]
  end
  invalid_edits_checked=true
 end
 assert(edit(observed.revision=='1' and '2' or '1')==2,'stale name edit accepted')
 assert(json.encode(name_value(name))==json.encode(original),'stale edit changed name')
 assert(json.encode(rng_snapshot())==json.encode(rng),'stale edit consumed RNG')
 assert(edit(observed.revision)==1,'valid name edit rejected')
 local expected={name=name_value(name),rng=rng_snapshot(),invalid_cases=invalid_cases}
 for _,guard in ipairs(guards)do
  assert(dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)==0,'semantic name edit changed UI/GPS')
  df.delete(guard.bytes)
 end
 -- Restore only controlled fixture name/RNG for the independent native action.
 name.first_name=original.first_name;name.nickname=original.nickname;name.language=original.language
 name.type=original.type;name.has_name=original.has_name
 for i=0,6 do name.words[i]=original.words[i+1];name.parts_of_speech[i]=original.parts_of_speech[i+1]end
 restore_rng(rng)
 return expected
end
local function check_edit(row,location,expected)
 local json=require('json')
 assert(json.encode(name_value(location:getName()))==json.encode(expected.name),'semantic/native name mutation differs')
 assert(json.encode(rng_snapshot())==json.encode(expected.rng),'semantic/native edit RNG differs')
 row.bridge_edit={name_identical=true,rng_identical=true,stale_rejected_without_effect=true,ui_unchanged=true}
 if #expected.invalid_cases>0 then row.bridge_edit.invalid_cases_rejected_without_effect=expected.invalid_cases end
end
local function simple_edit(label,location,mode,target)
 local word,part=-1,-1
 if mode==1 then word=creator.word_index[0];part=word_part(0)end
 local expected=prepare_edit(location,mode,target,creator.cur_name_place,word,part,creator.cull_str)
 if mode==0 then pixel(668,142+36*target)else pixel(756,178)end
 local row=capture(label,location);check_edit(row,location,expected)
end
local function random_component(label,location,target)
 local before=rng_snapshot()
 local guards={}
 for _,object in ipairs{m,g,location:getName()}do
  local n,at=df.sizeof(object);local bytes=df.new('uint8_t',n);dfhack.internal.memmove(bytes,at,n)
  guards[#guards+1]={bytes=bytes,address=at,size=n}
 end
 local text,code=dfhack.run_command_silent('df3d','location-name-pick',tostring(creator.cur_name_place),dfhack.df2utf(creator.cull_str))
 assert(code==0,text);local picked=require('json').decode(text)
 assert(picked.valid,'native selector rejected nonempty list')
 local after=rng_snapshot()
 for _,guard in ipairs(guards)do
  assert(dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)==0,'native pick changed UI/name')
  df.delete(guard.bytes)
 end
 restore_rng(before)
 local expected=prepare_edit(location,2,target,creator.cur_name_place,-1,-1,creator.cull_str)
 pixel(608,142+36*target)
 local native_after=rng_snapshot()
 assert(require('json').encode(after)==require('json').encode(native_after),'component Random RNG mismatch')
 assert(location:getName().words[target]==picked.word and location:getName().parts_of_speech[target]==picked.part,'component Random choice mismatch')
 local row=capture(label,location)
 check_edit(row,location,expected)
 row.bridge_random={word=picked.word,part=picked.part,target=target,displayed_component=creator.cur_name_place,
  rng_identical=true,ui_and_name_unchanged=true,cursor_before=before.cursor,cursor_after=after.cursor}
 return row
end
local function random_whole(label,location)
 local before=rng_snapshot();local guards={}
 assert(creator.namer and creator.namer.id==df.global.plotinfo.civ_id,'unexpected native naming entity')
 for _,object in ipairs{m,g,location:getName(),creator.namer,creator.namer.entity_raw}do
  local n,at=df.sizeof(object);local bytes=df.new('uint8_t',n);dfhack.internal.memmove(bytes,at,n)
  guards[#guards+1]={bytes=bytes,address=at,size=n}
 end
 local rejected=0
 for _,ids in ipairs{{-1,location.id},{df.global.plotinfo.site_id,-1},{df.global.plotinfo.site_id,2147483647},{df.global.plotinfo.site_id+1,location.id}}do
  local bad_text,bad_code=dfhack.run_command_silent('df3d','location-name-generate',tostring(ids[1]),tostring(ids[2]))
  assert(bad_code==0 and not require('json').decode(bad_text).valid,'invalid naming target accepted')
  assert(require('json').encode(before)==require('json').encode(rng_snapshot()),'invalid target consumed RNG')
  rejected=rejected+1
 end
 local text,code=dfhack.run_command_silent('df3d','location-name-generate',tostring(df.global.plotinfo.site_id),tostring(location.id))
 assert(code==0,text);local generated=require('json').decode(text)
 assert(generated.valid,'native whole-name generation rejected')
 local after=rng_snapshot()
 for _,guard in ipairs(guards)do
  assert(dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)==0,'whole-name generation changed UI/name/entity')
  df.delete(guard.bytes)
 end
 restore_rng(before)
 local expected=prepare_edit(location,3,-1,-1,-1,-1,'')
 pixel(832,82)
 local native_after=rng_snapshot()
 assert(require('json').encode(after)==require('json').encode(native_after),'whole-name RNG mismatch')
 local native=name_value(location:getName())
 native.first_name=dfhack.df2utf(native.first_name);native.nickname=dfhack.df2utf(native.nickname)
 assert(require('json').encode(generated.name)==require('json').encode(native),'whole-name value mismatch')
 local row=capture(label,location)
 check_edit(row,location,expected)
 row.bridge_generation={rng_identical=true,name_identical=true,ui_name_entity_unchanged=true,namer_id=creator.namer.id,invalid_targets_rejected_without_rng=rejected}
 return row
end
m.bottom_mode_selected=-1;key('D_CIVZONE');m.civzone.cur_bld=assert(df.building.find(23));view:render(dfhack.getTickCount())
pixel(336,190);local selector=m.location_selector;assert(selector.open,'chooser did not open')
local choices={};for _,v in ipairs(selector.valid_ab)do choices[#choices+1]=v end
assert(#choices==6,'unexpected location reference fixture')
for i,location in ipairs(choices)do
 pixel(664,238+36*(i-1));assert(details.open and details.selected_ab==location)
 local prefix=df.abstract_building_type[location:getType()]..'-'..location.id
 local before=capture(prefix..'-before',location)
 if location.id==0 then
  local contents=location:getContents();local original=contents.location_tier
  local ok,err=xpcall(function()
   for tier=0,2 do
    contents.location_tier=tier
    capture(prefix..'-recognition-tier-'..tier,location)
   end
  end,debug.traceback)
  contents.location_tier=original
  assert(ok,err)
 end
 for _,size in ipairs{'small','wide','default'}do
  window_input('name-resize-'..size)
  capture(prefix..'-details-resize-'..size,location)
  if location:getType()==df.abstract_building_type.HOSPITAL and size=='small' then
   for _,event in ipairs{'CONTEXT_SCROLL_DOWN','CONTEXT_SCROLL_UP','CONTEXT_SCROLL_PAGEDOWN','CONTEXT_SCROLL_PAGEUP'}do
    df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
    g.precise_mouse_x=712;g.precise_mouse_y=490;g.mouse_x=89;g.mouse_y=40
    key(event);capture(prefix..'-details-small-'..event,location)
   end
   details.scroll_position_occupation=0
  end
 end
 pixel(944,82)
 local opened=capture(prefix..'-name-open',location)
 assert(creator.open and creator.context==df.name_creator_context_type.LOCATION_NAME,'name creator did not open')
 assert(opened.direct_name_target,'native editor does not target this location name')
 key('_MOUSE_R')
 local closed=capture(prefix..'-name-back',location)
 assert(not creator.open and details.open,'name Back did not return to Details')
 assert(require('json').encode(before.name_value)==require('json').encode(closed.name_value),'open/Back changed name')
 key('LEAVESCREEN');assert(selector.open and not details.open)
end
assert(#records==43,'incomplete location name entry coverage')

for i,location in ipairs(choices)do
 pixel(664,238+36*(i-1));assert(details.open and details.selected_ab==location)
 pixel(944,82);assert(creator.open)
 local prefix=df.abstract_building_type[location:getType()]..'-'..location.id
 if location:getType()==df.abstract_building_type.INN_TAVERN then
  local before=name_value(location:getName());local before_rng=rng_snapshot()
  for _,size in ipairs{'small','wide','default'}do
   window_input('name-resize-'..size)
   capture(prefix..'-resize-'..size,location)
  end
  -- Controlled saved-name data on the owned paused clone; restore before edits.
  local named=location:getName();local original_first=named.first_name
  local ok,err=xpcall(function()
   for _,length in ipairs{60,100,180}do
    named.first_name=('abcdefghij'):rep(length//10)
    local row=capture(prefix..'-long-header-'..length,location)
    local text,code=dfhack.run_command_silent('df3d','location-name-read',tostring(df.global.plotinfo.site_id),tostring(location.id))
    assert(code==0,text);local value=require('json').decode(text);assert(value.valid and value.header_valid)
    row.header_strings={native=value.native_header,english=value.english_header}
   end
  end,debug.traceback)
  named.first_name=original_first
  assert(ok,err)
  assert(require('json').encode(before)==require('json').encode(name_value(named)),'long-header name restore failed')
  for _,point in ipairs{{'selected',476,142},{'component',476,178},{'random',608,142},{'clear',668,214},
    {'whole',832,82},{'done',912,82},{'filter',832,142},{'word',744,178}}do
   df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
   g.precise_mouse_x=point[2];g.precise_mouse_y=point[3];g.mouse_x=point[2]//8;g.mouse_y=point[3]//12
   capture(prefix..'-hover-'..point[1],location,true)
  end
  for _,event in ipairs{{'wheel-down','STANDARDSCROLL_DOWN'},{'wheel-up','STANDARDSCROLL_UP'},
    {'page-down','STANDARDSCROLL_PAGEDOWN'},{'page-up','STANDARDSCROLL_PAGEUP'}}do
   df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
   g.precise_mouse_x=744;g.precise_mouse_y=178;g.mouse_x=93;g.mouse_y=14
   key(event[2]);capture(prefix..'-scroll-'..event[1],location)
  end
  for _,event in ipairs{{'down','CONTEXT_SCROLL_DOWN',744,178},{'up','CONTEXT_SCROLL_UP',744,178},
    {'page-down','CONTEXT_SCROLL_PAGEDOWN',744,178},{'page-up','CONTEXT_SCROLL_PAGEUP',744,178},
    {'left','CONTEXT_SCROLL_DOWN',476,178},{'outside','CONTEXT_SCROLL_DOWN',20,20}}do
   df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
   g.precise_mouse_x=event[3];g.precise_mouse_y=event[4];g.mouse_x=event[3]//8;g.mouse_y=(event[4]-4)//12
   key(event[2]);capture(prefix..'-scroll-context-'..event[1],location)
  end
  creator.scroll_position_word=0
  pixel(952,694);capture(prefix..'-scroll-arrow-down',location)
  pixel(952,166);capture(prefix..'-scroll-arrow-up',location)
  pixel(952,500);capture(prefix..'-scroll-track-below',location)
  creator.scroll_position_word=1600;creator.scrolling_word=false
  view:render(dfhack.getTickCount());pixel(952,200);capture(prefix..'-scroll-track-above',location)
  local old_lift=df.global.enabler.mouse_lbut_lift
  for _,y in ipairs{148,172,184,400,676,700,724}do
   -- Owned diagnostic reset isolates each drag; never a runtime input.
   creator.scroll_position_word=0;creator.scrolling_word=false
   g.precise_mouse_x=952;g.precise_mouse_y=178;g.mouse_x=119;g.mouse_y=14
   df.global.enabler.mouse_lbut_lift=0
   gui.simulateInput(view,{'_MOUSE_L','_MOUSE_L_DOWN'})
   g.precise_mouse_x=952;g.precise_mouse_y=y;g.mouse_x=119;g.mouse_y=(y-4)//12
   gui.simulateInput(view,{'_MOUSE_L_DOWN'})
   capture(prefix..'-scroll-drag-'..y,location)
   df.global.enabler.mouse_lbut_lift=1;gui.simulateInput(view,{})
  end
  df.global.enabler.mouse_lbut_lift=old_lift
  assert(require('json').encode(before)==require('json').encode(name_value(location:getName())),'hover/scroll changed name')
  assert(require('json').encode(before_rng)==require('json').encode(rng_snapshot()),'hover/scroll consumed RNG')
  key('_MOUSE_R');pixel(944,82);assert(creator.open and creator.cur_word_place==0)
  for part=0,6 do
   pixel(476,142+36*part);capture(prefix..'-part-'..part..'-selected',location)
   simple_edit(prefix..'-part-'..part..'-clear',location,0,part)
   simple_edit(prefix..'-part-'..part..'-first-word',location,1,part)
   random_component(prefix..'-part-'..part..'-random',location,part)
  end
  -- Exercise the native MT refill and singleton bypass on owned paused state.
  local saved_rng=rng_snapshot();local refill=rng_snapshot();refill.cursor=0x9c0;restore_rng(refill)
  local refilled=random_component(prefix..'-random-refill',location,6)
  assert(refilled.bridge_random.cursor_before==0x9c0 and refilled.bridge_random.cursor_after==4,'RNG did not refill')
  restore_rng(saved_rng)
  local forms={}
  for j=0,#creator.word_index-1 do forms[#forms+1]=df.global.world.raws.language.words[creator.word_index[j]].forms[word_part(j)] end
  local singleton
  for _,candidate in ipairs(forms)do
   if #candidate>=4 and candidate:match('^[a-z]+$')then
    local count=0;for _,form in ipairs(forms)do if form:find(candidate,1,true)then count=count+1 end end
    if count==1 then singleton=candidate;break end
   end
  end
  assert(singleton,'no singleton native word query')
  pixel(832,142)
  for j=1,#singleton do key(('STRING_A%03d'):format(singleton:byte(j)))end
  key('SELECT');capture(prefix..'-singleton-selected',location)
  assert(#creator.word_index==1,'singleton query did not produce one choice')
  local single=random_component(prefix..'-singleton-random',location,6)
  assert(single.bridge_random.cursor_before==single.bridge_random.cursor_after,'singleton consumed RNG')
  pixel(832,142);for j=1,#singleton do key('STRING_A000')end;key('SELECT')
  pixel(832,142);capture(prefix..'-filter-focus',location)
  key('STRING_A097');key('STRING_A108');key('STRING_A101');capture(prefix..'-filter-ale',location)
  key('STRING_A000');capture(prefix..'-filter-al',location)
  key('SELECT');capture(prefix..'-filter-enter',location)
  random_component(prefix..'-filtered-other-component-random',location,0)
  for part=0,6 do pixel(476,142+36*part);capture(prefix..'-matrix-al-'..part,location)end
  pixel(832,142);key('STRING_A000');key('STRING_A000')
  for n=1,4 do key('STRING_A122')end
  for part=0,6 do pixel(476,142+36*part);capture(prefix..'-matrix-no-match-'..part,location)end
  assert(#creator.word_index==0,'empty-list reference requires zero choices')
  local empty_name=name_value(location:getName());local empty_rng=rng_snapshot()
  pixel(608,142+36*6)
  local empty=capture(prefix..'-empty-random',location)
  empty.empty_random={name_unchanged=require('json').encode(empty_name)==require('json').encode(name_value(location:getName())),
   rng_unchanged=require('json').encode(empty_rng)==require('json').encode(rng_snapshot())}
  if creator.entering_cull_str then key('SELECT')end
  pixel(832,142);assert(creator.entering_cull_str,'filter must have keyboard focus')
  for n=1,32 do key('STRING_A122')end
  local length=capture(prefix..'-filter-length',location)
  length.filter_limit={attempted_bytes=36,accepted_bytes=#creator.cull_str,accepted=creator.cull_str}
  for n=1,40 do key('STRING_A000')end
  window_input('ascii')
  local ascii=capture(prefix..'-filter-window-ascii',location)
  ascii.filter_bytes={creator.cull_str:byte(1,#creator.cull_str)}
  window_input('backspace')
  local erased=capture(prefix..'-filter-window-ascii-backspace',location)
  erased.filter_bytes={creator.cull_str:byte(1,#creator.cull_str)}
  for n=1,40 do key('STRING_A000')end
  window_input('nonascii')
  local accented=capture(prefix..'-filter-window-accent',location)
  accented.filter_bytes={creator.cull_str:byte(1,#creator.cull_str)}
  window_input('backspace')
  local backspace=capture(prefix..'-filter-window-backspace',location)
  backspace.filter_bytes={creator.cull_str:byte(1,#creator.cull_str)}
  for n=1,40 do key('STRING_A000')end
  for n=1,9 do key('STRING_A097')end
  window_input('nonascii')
  local boundary=capture(prefix..'-filter-window-boundary',location)
  boundary.filter_bytes={creator.cull_str:byte(1,#creator.cull_str)}
  for n=1,40 do key('STRING_A000')end
  window_input('name-filter-mixed')
  local mixed=capture(prefix..'-filter-window-mixed',location)
  mixed.filter_bytes={creator.cull_str:byte(1,#creator.cull_str)}
  key('LEAVESCREEN')
  local escaped=capture(prefix..'-filter-leavescreen',location)
  escaped.filter_exit={open=creator.open,entering_filter=creator.entering_cull_str,filter=creator.cull_str}
  if not creator.open then pixel(944,82)end
  pixel(832,142);for n=1,40 do key('STRING_A000')end;key('SELECT')
  key('_MOUSE_R');capture(prefix..'-edited-back',location)
  if creator.open then key('_MOUSE_R')end
  assert(not creator.open and details.open,'edited name Back did not return')
  pixel(944,82);capture(prefix..'-edited-reopen',location)
 end
 if i==1 then
  -- Owned, paused diagnostic: exercise the native utterance-name branch and
  -- restore the creature raw flag before ordinary naming/exit. Never a product input.
  local race=df.global.world.raws.creatures.all[creator.namer.race]
  local original=race.flags.HAS_ANY_UTTERANCES
  race.flags.HAS_ANY_UTTERANCES=true
  local ok,err=xpcall(function()
   local row=random_whole(prefix..'-utterance-random',location)
   assert(row.name_value.first_name~='' and row.name_value.language==-1,'utterance branch not exercised')
   row.bridge_generation.utterance_branch=true
  end,debug.traceback)
  race.flags.HAS_ANY_UTTERANCES=original
  assert(race.flags.HAS_ANY_UTTERANCES==original,'utterance flag restore failed')
  assert(ok,err)
 end
 random_whole(prefix..'-whole-random',location)
 pixel(912,82);capture(prefix..'-done',location)
 assert(not creator.open and details.open,'Done did not return to Details')
 pixel(944,82);capture(prefix..'-random-reopen',location)
 key('_MOUSE_R');assert(not creator.open and details.open)
 key('LEAVESCREEN');assert(selector.open and not details.open)
end
assert(#records==158,'incomplete name mutation/filter reference')

-- Native-only mutation oracle, after naming's RNG assertions. The lane owns
-- this paused disposable clone and exits without saving any recognition effects.
local temple=choices[1];assert(temple.id==0)
pixel(664,238);assert(details.open and details.selected_ab==temple)
local religion=assert(df.historical_entity.find(temple.deity_data.Religion))
local function recognition_state()
 local result={positions={},assignments={},next_position=religion.positions.next_position_id,
  next_assignment=religion.positions.next_assignment_id,event_count=#df.global.world.history.events,
  recognized=temple:getContents().need_more.entity_recognized}
 for _,p in ipairs(religion.positions.own)do
  result.positions[#result.positions+1]={id=p.id,code=p.code,name=dfhack.df2utf(p.name[0])}
 end
 for _,a in ipairs(religion.positions.assignments)do
  result.assignments[#result.assignments+1]={id=a.id,position_id=a.position_id,histfig=a.histfig,
   histfig2=a.histfig2,site=a.st_id,location=a.ab_id,position_vector_idx=a.position_vector_idx}
 end
 return result
end
local contents=temple:getContents();local original=contents.location_tier;contents.location_tier=2
local ok,err=xpcall(function()
 local before=capture('TEMPLE-0-recognition-before',temple);before.recognition=recognition_state()
 pixel(500,214)
 local after=capture('TEMPLE-0-recognition-after',temple);after.recognition=recognition_state()
 after.recognition.new_events={}
 for i=before.recognition.event_count,#df.global.world.history.events-1 do
  local event=df.global.world.history.events[i]
  after.recognition.new_events[#after.recognition.new_events+1]={id=event.id,type=df.history_event_type[event:getType()]}
 end
 assert(require('json').encode(before.recognition.assignments)~=require('json').encode(after.recognition.assignments),'recognition did not change assignments')
 pixel(500,214)
 local repeated=capture('TEMPLE-0-recognition-repeat',temple);repeated.recognition=recognition_state()
 for _,field in ipairs{'positions','assignments','event_count','next_position','next_assignment'}do
  assert(require('json').encode(after.recognition[field])==require('json').encode(repeated.recognition[field]),'repeat recognition changed '..field)
 end
end,debug.traceback)
contents.location_tier=original
assert(ok,err)
assert(#records==161,'incomplete recognition mutation reference')
