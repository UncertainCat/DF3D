-- Protected owned paused diagnostic only. Native name-editor scratch is not a runtime API.
local out,view,records=...
local marker=io.open(out..'/recognition-only');local recognition_only=marker~=nil;if marker then marker:close()end
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
  staff_scroll=details.scroll_position_occupation,staff_count=#details.loc_occupation+#details.loc_position,
  hover=m.current_hover,displayed_hover=m.last_displayed_hover_inst}
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
if not recognition_only then
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
end

-- Native-only mutation oracle, after naming's RNG assertions. The lane owns
-- this paused disposable clone and exits without saving any recognition effects.
local temple=choices[1];assert(temple.id==0)
local religion=assert(df.historical_entity.find(temple.deity_data.Religion))
local mode_file=io.open(out..'/recognition-case');local recognition_case='promote'
if mode_file then recognition_case=mode_file:read('*a'):match('%a+');mode_file:close()end
local semantic_recognition=recognition_case:sub(1,6)=='action'
if semantic_recognition then recognition_case=recognition_case:sub(7)end
assert(recognition_case=='promote' or recognition_case=='empty' or recognition_case=='first' or recognition_case=='new' or recognition_case=='eligibility' or recognition_case=='thoughts' or recognition_case=='petitions' or recognition_case=='agreements' or recognition_case=='positionhigh' or recognition_case=='positionnew' or recognition_case=='waiver' or recognition_case=='firstguidance' or recognition_case=='specialization' or recognition_case=='specializationhover' or recognition_case=='staffindicators' or recognition_case=='assignpriest' or recognition_case=='assignspypriest' or (recognition_case=='assignmilitarypriest' or recognition_case=='assigncommandpriest') or recognition_case=='assignhighpriest' or recognition_case:sub(1,7)=='replace' or recognition_case=='removepriest' or recognition_case=='removeabsentpriest' or recognition_case=='removesquadpriest' or recognition_case=='removemanagerpriest' or recognition_case=='removeaccountantpriest')
local fixture_agreements={}
if recognition_case=='petitions' or recognition_case=='agreements' or recognition_case=='waiver' then
 -- World-owned fixtures on the disposable clone, discarded by unsaved exit.
 -- Each list starts with a nonmatching applicant, then two matching entries.
 for list_index,list in ipairs{df.global.plotinfo.petitions,df.global.plotinfo.continuing_agreement_id}do
  if recognition_case~='waiver' or list_index==2 then
  for entry=1,(recognition_case=='waiver' and 1 or 3)do
   local agreement=df.agreement:new();local party=df.agreement_party:new()
   local subject=df.agreement_details:new();local location=df.agreement_details_data_location:new()
   agreement.id=2147483600+#fixture_agreements
   local all=df.global.world.agreements.all
   assert(#all==0 or all[#all-1].id<agreement.id,'agreement fixture ID occupied')
   party.id=0;party.entity_ids:insert('#',recognition_case~='waiver' and entry==1 and df.global.plotinfo.group_id or religion.id)
   assert(entry~=1 or df.global.plotinfo.group_id~=religion.id,'nonmatching applicant fixture invalid')
   location.applicant=0;location.government=1;location.site=df.global.plotinfo.site_id
   location.type=df.abstract_building_type.TEMPLE;location.deity_type=df.religious_practice_type.RELIGION_ENID
   location.deity_data.Religion=religion.id;location.tier=2
   subject.id=0;subject.type=df.agreement_details_type.Location;subject.data.Location=location
   agreement.parties:insert('#',party);agreement.details:insert('#',subject)
   agreement.flags.whole=list_index==1 and 1 or 0
   all:insert('#',agreement);list:insert('#',agreement.id)
   fixture_agreements[#fixture_agreements+1]=agreement.id
  end
  end
 end
end
local first_recognition=recognition_case=='firstguidance' or recognition_case=='first' or recognition_case=='new' or recognition_case=='positionnew'
if recognition_case=='empty' or first_recognition then
 -- Controlled world fixture on the owned unsaved clone; never a runtime path.
 local changed=0
 for _,assignment in ipairs(religion.positions.assignments)do
  if assignment.st_id==df.global.plotinfo.site_id then
   if first_recognition then assignment.st_id=-1 else assignment.histfig=-1 end
   changed=changed+1
  end
 end
 assert(changed==1,'unexpected recognition fixture assignment count')
end
if recognition_case=='new' or recognition_case=='positionnew' then
 -- Keep old allocations/links owned by the world, but force native template
 -- creation instead of reuse. This diagnostic state is discarded unsaved.
 local changed=0
 for _,position in ipairs(religion.positions.own)do
  if position.code=='PRIEST' then position.code='DF3D_FIXTURE_OLD_PRIEST';changed=changed+1 end
 end
 assert(changed==1,'unexpected priest template fixture count')
end
pixel(664,238);assert(details.open and details.selected_ab==temple)
if recognition_case=='staffindicators' then
 local function facts()
  local result={}
  for _,id in ipairs{5813,6536}do
   local u=assert(df.unit.find(id));local r={unit_id=id,occupations={},workshops={},furnaces={},work_details={}}
   for _,o in ipairs(u.occupations)do r.occupations[#r.occupations+1]={id=o.id,type=o.type,unit_id=o.unit_id,histfig_id=o.histfig_id}end
   for _,entry in ipairs{{'WORKSHOP_ANY','workshops'},{'FURNACE_ANY','furnaces'}}do
    for _,b in ipairs(df.global.world.buildings.other[entry[1]])do
     local profile=b:getWorkshopProfile()
     if profile then for _,worker in ipairs(profile.permitted_workers)do
      if worker==id then r[entry[2]][#r[entry[2]]+1]={id=b.id,type=b:getType(),subtype=b:getSubtype(),custom=b:getCustomType()}end
     end end
    end
   end
   for i,detail in ipairs(df.global.plotinfo.labor_info.work_details)do
    for _,worker in ipairs(detail.assigned_units)do
     if worker==id then r.work_details[#r.work_details+1]={index=i,icon=detail.icon,name=dfhack.df2utf(detail.name),mode=detail.flags.mode}end
    end
   end
   result[#result+1]=r
  end
  return result
 end
 local original=facts()
 local baseline=capture('TEMPLE-staff-indicators-before',temple);baseline.units=original
 for _,target in ipairs{{'performer-icon',816,394},{'performer-portrait',592,394},{'priest-icon',816,358},{'priest-portrait',592,358}}do
  local function move()
   df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
   g.precise_mouse_x=target[2];g.precise_mouse_y=target[3];g.mouse_x=target[2]//8;g.mouse_y=(target[3]-4)//12
   gui.simulateInput(view,{});view:render(dfhack.getTickCount())
  end
  local until_tick=dfhack.getTickCount()+900
  repeat move();script.sleep(1,'frames')until dfhack.getTickCount()>=until_tick
  move()
  local cells={}
  for y=28,33 do for x=96,119 do
   local pen=dfhack.screen.readTile(x,y)
   cells[#cells+1]={x=x,y=y,ch=pen.ch,tile=pen.tile,fg=pen.fg,bg=pen.bg,bold=pen.bold}
  end end
  local row=capture('TEMPLE-staff-indicators-'..target[1],temple,true);row.cells=cells
  assert(require('json').encode(facts())==require('json').encode(original),'hover changed assignment facts')
 end
 -- Diagnostic-only world fixture: make every assignment source visible on one
 -- row, without using any native panel or borrowing its list state at runtime.
 local restores={}
 local function add_worker(vector)
  local before={};for _,id in ipairs(vector)do before[#before+1]=id;assert(id~=6536,'fixture worker already assigned')end
  restores[#restores+1]={vector=vector,before=before}
  vector:insert('#',6536)
  local sorted={};for _,id in ipairs(vector)do sorted[#sorted+1]=id end;table.sort(sorted)
  for i,id in ipairs(sorted)do vector[i-1]=id end
 end
 for _,kind in ipairs{'WORKSHOP_ANY','FURNACE_ANY'}do
  local found=false
  for _,b in ipairs(df.global.world.buildings.other[kind])do
   local profile=b:getWorkshopProfile()
   if profile then add_worker(profile.permitted_workers);found=true;break end
  end
  assert(found,'assignment fixture missing '..kind)
 end
 add_worker(assert(df.global.plotinfo.labor_info.work_details[0]).assigned_units)
 local row=capture('TEMPLE-staff-indicators-all-sources',temple);row.units=facts();row.cells={}
 for y=31,33 do for x=100,115 do
  local pen=dfhack.screen.readTile(x,y)
  row.cells[#row.cells+1]={x=x,y=y,ch=pen.ch,tile=pen.tile,fg=pen.fg,bg=pen.bg,bold=pen.bold}
 end end
 for _,restore in ipairs(restores)do
  restore.vector:resize(0);for _,id in ipairs(restore.before)do restore.vector:insert('#',id)end
 end
 assert(require('json').encode(facts())==require('json').encode(original),'assignment fixture restoration failed')
 return
end
if recognition_case=='specializationhover' then
 for index,target in ipairs{{'specialized',358,df.main_hover_instruction.INFO_UNIT_IS_SPECIALIZED},{'available',394,df.main_hover_instruction.INFO_UNIT_IS_NOT_SPECIALIZED}}do
  local until_tick=dfhack.getTickCount()+1800
  repeat
   df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
   g.precise_mouse_x=784;g.precise_mouse_y=target[2];g.mouse_x=98;g.mouse_y=(target[2]-4)//12
   gui.simulateInput(view,{});view:render(dfhack.getTickCount());script.sleep(1,'frames')
  until dfhack.getTickCount()>=until_tick
  g.precise_mouse_x=784;g.precise_mouse_y=target[2];g.mouse_x=98;g.mouse_y=(target[2]-4)//12
  local row=capture('TEMPLE-specialization-hover-'..target[1],temple,true)
  assert(row.displayed_hover==target[3],'specialization help did not appear: current='..tostring(row.hover)..' displayed='..tostring(row.displayed_hover)..' expected='..tostring(target[3]))
 end
 return
end
if recognition_case=='specialization' then
 local function state()
  local result={}
  for _,unit in ipairs(df.global.world.units.active)do
   local labors={};for i=0,df.unit_labor._last_item do labors[#labors+1]=unit.status.labors[i]end
   result[tostring(unit.id)]={flags4=unit.flags4.whole,specialized=unit.flags4.only_do_assigned_jobs,labors=labors}
  end
  return result
 end
 local before=state()
 local reference
 local function command(name,args)
  local text,code=dfhack.run_command_silent('df3d',name,table.unpack(args))
  assert(code==0,text);return require('json').decode(text)
 end
 if semantic_recognition then
  local marker=assert(io.open(out..'/recognition-reference'));local path=marker:read('*a'):match('^%s*(.-)%s*$');marker:close()
  local file=assert(io.open(path));reference=require('json').decode(file:read('*a'));file:close()
  assert(reference.success and #reference.records==5)
  assert(require('json').encode(before)==require('json').encode(reference.records[1].units),'initial specialization state differs')
 end
 capture('TEMPLE-specialization-before',temple).units=before
 for index,target in ipairs{{'priest',358},{'performer',394}}do
  local original=state()
  local args,receipt,change
  local function read()return command('location-specialization-read',args)end
  local function apply(revision,value)
   local values={table.unpack(args)};values[#values+1]=revision;values[#values+1]=value and '1' or '0'
   return command('location-specialization-set',values).outcome
  end
  if semantic_recognition then
   change=reference.records[index*2].changed[1]
   local staff=command('location-staff-read',{tostring(df.global.plotinfo.site_id),tostring(temple.id)})
   for _,row in ipairs(staff.rows)do
    if row.names.holder_kind==1 and row.names.holder_id==change.unit_id then
     assert(not args,'ambiguous specialization row')
     args={tostring(df.global.plotinfo.site_id),tostring(temple.id),row.occupation and '0' or '1',
      tostring(row.entity),tostring(row.occupation and row.occupation.id or row.assignment),tostring(change.unit_id)}
    end
   end
   assert(args);receipt=read();assert(receipt.valid and receipt.eligible and receipt.specialized==change.before.specialized)
   for i=1,6 do
    if i~=3 and not(i==4 and args[i]=='-1')then
     local old=args[i];args[i]='-1';assert(not read().valid);assert(apply(receipt.revision,change.after.specialized)==1);args[i]=old
    end
   end
   assert(apply('0',change.after.specialized)==1)
   assert(apply(receipt.revision,receipt.specialized)==1)
   local unit=assert(df.unit.find(change.unit_id));local old=unit.profession
   unit.profession=df.profession.BABY
   local stale=read();assert(stale.valid and not stale.eligible and stale.revision~=receipt.revision)
   assert(apply(receipt.revision,change.after.specialized)==4)
   assert(apply(stale.revision,change.after.specialized)==1)
   unit.profession=old;assert(read().revision==receipt.revision)
   assert(require('json').encode(state())==require('json').encode(original),'refusal changed specialization/labors')
   local guards={}
   for _,object in ipairs{m,g}do local n,at=df.sizeof(object);local bytes=df.new('uint8_t',n);dfhack.internal.memmove(bytes,at,n);guards[#guards+1]={bytes=bytes,address=at,size=n}end
   assert(apply(receipt.revision,change.after.specialized)==2)
   for _,guard in ipairs(guards)do assert(dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)==0,'specialization changed UI/gps');df.delete(guard.bytes)end
  else pixel(784,target[2])end
  local row=capture('TEMPLE-specialization-'..target[1]..'-toggle',temple)
  row.changed={};local after=state()
  for id,value in pairs(after)do
   if value.specialized~=original[id].specialized then
    row.changed[#row.changed+1]={unit_id=tonumber(id),before=original[id],after=value}
   end
  end
  assert(#row.changed==1,'native specialization must toggle one unit')
  if semantic_recognition then
   assert(require('json').encode(row.changed)==require('json').encode(reference.records[index*2].changed),'specialization effects differ from native')
   assert(apply(receipt.revision,change.after.specialized)==4,'specialization replay accepted')
   assert(require('json').encode(state())==require('json').encode(after),'replay changed state')
   row.semantic_matches_native=true;row.stale_and_ineligible_refused=true
   assert(apply(read().revision,change.before.specialized)==2)
  else pixel(784,target[2])end
  local restored=state()
  assert(require('json').encode(restored)==require('json').encode(original),'native specialization did not restore')
  capture('TEMPLE-specialization-'..target[1]..'-restored',temple)
 end
 assert(#records==5);return
end
local function recognition_state()
 local function values(vector)
  local result={};for _,value in ipairs(vector)do result[#result+1]=value end;return result
 end
 local function flags(array,enum)
  local result={};for i=0,enum._last_item do if array[i] then result[#result+1]=enum[i] end end;return result
 end
 local result={case=recognition_case,positions={},assignments={},site_links={},holder_links={},next_position=religion.positions.next_position_id,
  next_assignment=religion.positions.next_assignment_id,event_count=#df.global.world.history.events,
  recognized=temple:getContents().need_more.entity_recognized,temple_emotions={},rng=rng_snapshot(),
  petitions=values(df.global.plotinfo.petitions),continuing=values(df.global.plotinfo.continuing_agreement_id),agreements={}}
 for _,id in ipairs(fixture_agreements)do
  local agreement=assert(df.agreement.find(id));result.agreements[#result.agreements+1]={id=id,flags=agreement.flags.whole}
 end
 for _,p in ipairs(religion.positions.own)do
  local item={id=p.id,code=p.code,name=dfhack.df2utf(p.name[0]),flags=flags(p.flags,df.entity_position_flags)}
  for _,field in ipairs{'squad_size','land_holder','requires_population','execution_skill','precedence','replaced_by','number','required_boxes','required_cabinets','required_racks','required_stands','required_office','required_bedroom','required_dining','required_tomb','mandate_max','demand_max','best_appointment_precedence'}do item[field]=p[field]end
  for _,field in ipairs{'allowed_creature','rejected_creature','commander_id','commander_civ','commander_types','appointed_by','appointed_by_civ','succession_by_position','responsibilities','color'}do item[field]=values(p[field])end
  for _,field in ipairs{'name','name_female','name_male','spouse','spouse_female','spouse_male','squad'}do
   item[field..'_forms']={dfhack.df2utf(p[field][0]),dfhack.df2utf(p[field][1])}
  end
  item.land_name=dfhack.df2utf(p.land_name);item.description=dfhack.df2utf(p.description)
  for _,field in ipairs{'allowed_class','rejected_class'}do
   item[field]={};for _,value in ipairs(p[field])do item[field][#item[field]+1]=dfhack.df2utf(value.value)end
  end
  result.positions[#result.positions+1]=item
 end
 for _,a in ipairs(religion.positions.assignments)do
  result.assignments[#result.assignments+1]={id=a.id,position_id=a.position_id,histfig=a.histfig,
   histfig2=a.histfig2,site=a.st_id,location=a.ab_id,position_vector_idx=a.position_vector_idx,
   flags=flags(a.flags,df.entity_position_profile_flags),squad_id=a.squad_id,
   vassal_of_entity_id=a.vassal_of_entity_id,vassal_of_position_profile_id=a.vassal_of_position_profile_id,
   claim_count=#a.claim}
  if a.histfig>=0 and not result.holder_links[tostring(a.histfig)] then
   local holder=assert(df.historical_figure.find(a.histfig));local links={}
   for _,link in ipairs(holder.entity_links)do
    if link.entity_id==religion.id then
     local item={type=df.histfig_entity_link_type[link:getType()],entity_id=link.entity_id,
      entity_vector_idx=link.entity_vector_idx,strength=link.link_strength}
     if df.histfig_entity_link_positionst:is_instance(link) then
      item.assignment_id=link.assignment_id;item.assignment_vector_idx=link.assignment_vector_idx;item.start_year=link.start_year
     elseif df.histfig_entity_link_former_positionst:is_instance(link) then
      item.assignment_id=link.assignment_id;item.start_year=link.start_year;item.end_year=link.end_year
     end
     links[#links+1]=item
    end
   end
   result.holder_links[tostring(a.histfig)]=links
  end
 end
 for _,unit in ipairs(df.global.world.units.active)do
  local soul=unit.status.current_soul
  if soul then
   for _,emotion in ipairs(soul.personality.emotions)do
    if emotion.thought==df.unit_thought_type.EstablishedTemple then
     local item={unit_id=unit.id,unit_flags1=unit.flags1.whole,flags=emotion.flags.whole}
     for _,field in ipairs{'type','strength','relative_strength','thought','subthought','severity','next_overcome_timer','year','year_tick'}do item[field]=emotion[field]end
     result.temple_emotions[#result.temple_emotions+1]=item
    end
   end
  end
 end
 for _,link in ipairs(religion.site_links)do
  local item={}
  for _,field in ipairs{'target','entity_id','entity_cache_index','position_profile_id','type','start_hr','end_hr','link_strength','initial_controlling_population','last_check_controlling_population','target_site_x','target_site_y','last_checked_army_year','last_checked_army_year_tick'}do item[field]=link[field] end
  item.flags=link.flags.whole;item.former_flags=link.former_flag.whole;item.ab_profile={}
  for _,profile in ipairs(link.ab_profile)do item.ab_profile[#item.ab_profile+1]={id=profile.id,purpose_flags=profile.purpose_flag.whole}end
  result.site_links[#result.site_links+1]=item
 end
 local guards={};local rng_before=rng_snapshot()
 for _,object in ipairs{m,g}do
  local n,at=df.sizeof(object);local bytes=df.new('uint8_t',n);dfhack.internal.memmove(bytes,at,n)
  guards[#guards+1]={bytes=bytes,address=at,size=n}
 end
 local function read()
  local text,code=dfhack.run_command_silent('df3d','location-recognition-read',tostring(df.global.plotinfo.site_id),tostring(temple.id))
  assert(code==0,text);return require('json').decode(text)
 end
 result.bridge=read();assert(result.bridge.valid,'recognition facts unavailable')
 assert(require('json').encode(result.bridge)==require('json').encode(read()),'recognition read unstable')
 assert(result.bridge.religion_id==religion.id and result.bridge.tier==temple:getContents().location_tier)
 assert(result.bridge.worshippers==53,'native worshipper counter mismatch')
 assert(result.bridge.priest_threshold==df.global.plotinfo.main.custom_difficulty.priesthood_unit_count)
 assert(result.bridge.high_priest_threshold==df.global.plotinfo.main.custom_difficulty.high_priesthood_unit_count)
 for _,target in ipairs{{-1,temple.id},{df.global.plotinfo.site_id+1,temple.id},{df.global.plotinfo.site_id,-1},{df.global.plotinfo.site_id,2147483647},{df.global.plotinfo.site_id,1}}do
  local text,code=dfhack.run_command_silent('df3d','location-recognition-read',tostring(target[1]),tostring(target[2]))
  assert(code==0 and not require('json').decode(text).valid,'invalid recognition target accepted')
 end
 for _,guard in ipairs(guards)do
  assert(dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)==0,'recognition observation changed native UI/gps')
  df.delete(guard.bytes)
 end
 assert(require('json').encode(rng_before)==require('json').encode(rng_snapshot()),'recognition observation consumed RNG')
 result.bridge_ui_rng_unchanged=true
 return result
end
local contents=temple:getContents();local original=contents.location_tier;contents.location_tier=first_recognition and 1 or 2
local difficulty=df.global.plotinfo.main.custom_difficulty;local original_threshold=difficulty.high_priesthood_unit_count
local original_priest_threshold=difficulty.priesthood_unit_count
if recognition_case=='assignpriest' or recognition_case=='assignspypriest' or (recognition_case=='assignmilitarypriest' or recognition_case=='assigncommandpriest') or recognition_case=='assignhighpriest' or recognition_case:sub(1,7)=='replace' then
 local assignment_row_y=recognition_case=='assignhighpriest' and 394 or 358
 local promotion_rng
 local assignment
 for _,a in ipairs(religion.positions.assignments)do if a.st_id==df.global.plotinfo.site_id then assert(not assignment);assignment=a end end
 assert(assignment and assignment.histfig>=0)
 if recognition_case=='assignhighpriest' then
  if semantic_recognition then
   local marker=assert(io.open(out..'/recognition-reference'));local path=marker:read('*a'):match('^%s*(.-)%s*$');marker:close()
   local file=assert(io.open(path));local reference=require('json').decode(file:read('*a'));file:close()
   restore_rng(assert(reference.records[1].promotion_rng))
  end
  promotion_rng=rng_snapshot()
  view:render(dfhack.getTickCount())
  pixel(500,214)
  assert(recognition_state().bridge.rank==2,'native high-priest recognition failed')
  local position
  for _,p in ipairs(religion.positions.own)do if p.code=='HIGH_PRIEST' then assert(not position);position=p end end
  assert(position,'native promotion did not create high-priest position')
  assignment=nil
  for _,a in ipairs(religion.positions.assignments)do
   if a.st_id==df.global.plotinfo.site_id and a.position_id==position.id then assert(not assignment);assignment=a end
  end
  assert(assignment and assignment.histfig>=0,'native promotion did not transfer holder')
  capture('TEMPLE-high-priest-promoted',temple);table.remove(records)
 end
 if recognition_case=='assignpriest' or recognition_case=='assignspypriest' or (recognition_case=='assignmilitarypriest' or recognition_case=='assigncommandpriest') or recognition_case=='assignhighpriest' then pixel(944,assignment_row_y);assert(assignment.histfig==-1,'native removal did not vacate religious assignment')end
 local expected_holder=assignment.histfig
 local previous_holder=expected_holder>=0 and assert(df.historical_figure.find(expected_holder)) or nil
 local previous_holder_unit=previous_holder and previous_holder.unit_id
 if recognition_case=='replaceabsentpriest' then
  -- Missing association only; retain the original unit for effect comparisons.
  assert(previous_holder);previous_holder.unit_id=-1
  assert(not df.unit.find(previous_holder.unit_id))
 end
 local linked_squad,seeded_assignment_job
 if recognition_case=='assignspypriest' then
  -- Native follow-up c2fde0 reads responsibilities+25 (ESPIONAGE) at0x341.
  -- Exercise that semantic branch only in this unsaved diagnostic fixture.
  local position
  for _,p in ipairs(religion.positions.own)do if p.id==assignment.position_id then position=p end end
  assert(position);position.responsibilities[df.entity_position_responsibility.ESPIONAGE]=true
  local _,base=df.sizeof(position);local _,at=df.sizeof(position:_field('responsibilities'))
  assert(at-base+df.entity_position_responsibility.ESPIONAGE==0x341)
 end
 if recognition_case=='assigncommandpriest' then
  -- Controlled semantic branch fixture, not a new player-facing position type.
  local position
  for _,p in ipairs(religion.positions.own)do if p.id==assignment.position_id then position=p end end
  assert(position and position.squad_size==0);position.squad_size=10
 end
 if recognition_case=='replacesquadpriest' then
  local unit=assert(df.unit.find(previous_holder.unit_id));linked_squad=assert(df.squad.find(unit.military.squad_id))
  assert(unit.military.squad_position==0 and linked_squad.positions[0].occupant==previous_holder.id)
  assignment.squad_id=linked_squad.id
 elseif recognition_case=='replacemanagerpriest' or recognition_case=='replaceaccountantpriest' then
  local unit=assert(df.unit.find(previous_holder.unit_id));assert(not unit.job.current_job)
  local position
  for _,p in ipairs(religion.positions.own)do if p.id==assignment.position_id then position=p end end
  assert(position);local manager=recognition_case=='replacemanagerpriest'
  position.responsibilities[manager and df.entity_position_responsibility.MANAGE_PRODUCTION or df.entity_position_responsibility.ACCOUNTING]=true
  seeded_assignment_job=df.job:new();seeded_assignment_job.job_type=manager and df.job_type.ManageWorkOrders or df.job_type.UpdateStockpileRecords
  seeded_assignment_job.pos:assign(unit.pos);seeded_assignment_job.posting_index=-1
  assert(dfhack.job.linkIntoWorld(seeded_assignment_job,true));assert(dfhack.job.addWorker(seeded_assignment_job,unit))
 end
 local vacant=capture(expected_holder>=0 and 'TEMPLE-priest-occupied' or 'TEMPLE-priest-vacant',temple);vacant.recognition=recognition_state()
 vacant.promotion_rng=promotion_rng
 if recognition_case=='assigncommandpriest' then vacant.seeded_squad_size=10 end
 local function candidates(ids,rows)
  local guards={}
  for _,object in ipairs{m,g}do
   local n,at=df.sizeof(object);local bytes=df.new('uint8_t',n);dfhack.internal.memmove(bytes,at,n)
   guards[#guards+1]={bytes=bytes,address=at,size=n}
  end
  local args=ids or {df.global.plotinfo.site_id,temple.id,religion.id,assignment.id}
  local text,code=dfhack.run_command_silent('df3d',rows and 'location-religious-candidate-rows' or 'location-religious-candidates',tostring(args[1]),tostring(args[2]),tostring(args[3]),tostring(args[4]))
  for _,guard in ipairs(guards)do
   assert(dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)==0,'religious candidates changed native UI/gps');df.delete(guard.bytes)
  end
  assert(code==0,text);return require('json').decode(text)
 end
 vacant.semantic_candidates=candidates();assert(vacant.semantic_candidates.valid,'religious candidates unavailable')
 vacant.before_candidate_observation=vacant.recognition;vacant.recognition=recognition_state()
 local function without_lookup_indexes(value)
  if type(value)~='table' then return value end
  local result={};for k,v in pairs(value)do
   if k~='entity_vector_idx' and k~='assignment_vector_idx' and k~='position_vector_idx' then result[k]=without_lookup_indexes(v)end
  end;return result
 end
 assert(require('json').encode(without_lookup_indexes(vacant.before_candidate_observation))==require('json').encode(without_lookup_indexes(vacant.recognition)),'candidate observation changed captured simulation beyond lookup caches')
 vacant.invalid_candidates={}
 for i=1,4 do
  local ids={df.global.plotinfo.site_id,temple.id,religion.id,assignment.id};ids[i]=-1
  local rejected=candidates(ids);assert(not rejected.valid and #rejected.unit_ids==0)
  vacant.invalid_candidates[#vacant.invalid_candidates+1]=i
 end
 local function open_picker()
  -- Occupied native rows do not offer assignment directly. For the replacement
  -- callback oracle, open a vacant picker then restore its old holder before
  -- selection, modelling a target that became occupied while the picker was open.
  local first,second=assignment.histfig,assignment.histfig2
  if expected_holder>=0 then assignment.histfig=-1;assignment.histfig2=-1;view:render(dfhack.getTickCount())end
  pixel(592,assignment_row_y)
  assignment.histfig=first;assignment.histfig2=second
 end
 open_picker()
 local selector=m.unit_selector
 assert(selector.flag.VISIBILITY_ACTIVE,'religious assignment selector did not open')
 local function find_list(widget,depth)
  assert(depth<10)
  if df.widget_unit_list:is_instance(widget)then return df.reinterpret_cast(df.widget_unit_list,widget)end
  if not df.widget_container:is_instance(widget)then return end
  local _,address=df.sizeof(df.reinterpret_cast(df.widget_container,widget).children)
  local first=df.reinterpret_cast('uint64_t',address).value;local last=df.reinterpret_cast('uint64_t',address+8).value
  assert(last>=first and (last-first)%16==0 and last-first<=65536)
  for at=first,last-1,16 do
   local child=df.reinterpret_cast('uint64_t',at).value
   if child~=0 then local found=find_list(df.reinterpret_cast(df.widget,child),depth+1);if found then return found end end
  end
 end
 local list=assert(find_list(selector,0),'religious unit list missing')
 local opened=capture('TEMPLE-priest-selector',temple)
 opened.scrollbar_tiles={}
 for y=7,56 do for x=117,118 do
  local cell={x=x,y=y}
  for _,field in ipairs{'screentexpos','screentexpos_lower','screentexpos_top','screentexpos_top_lower'}do
   cell[field]=g[field][x*g.dimy+y]
  end
  opened.scrollbar_tiles[#opened.scrollbar_tiles+1]=cell
 end end
 opened.scrollbar_base=g.graphical_interface.texpos_scrollbar[0][0]
 opened.selector={context=selector.context,entity_id=selector.loc_ent and selector.loc_ent.id or -1,
  position_id=selector.loc_position and selector.loc_position.id or -1,assignment_id=selector.loc_epp and selector.loc_epp.id or -1,
  filter=list.filter_str,skill_type=list.skill_type,flags=list.flags.whole,sort_flags=list.sort_flags.whole,candidates={}}
 for _,entry in ipairs(list.entry_list)do
  assert(entry.t==0 and entry.u,'nonunit religious candidate')
  opened.selector.candidates[#opened.selector.candidates+1]={id=entry.u.id,histfig_id=entry.u.hist_figure_id,name=dfhack.df2utf(dfhack.units.getReadableName(entry.u)),profession=entry.u.profession}
 end
 assert(opened.selector.entity_id==religion.id and opened.selector.assignment_id==assignment.id)
 local native_ids={};for _,row in ipairs(opened.selector.candidates)do native_ids[#native_ids+1]=row.id end
 assert(require('json').encode(native_ids)==require('json').encode(vacant.semantic_candidates.unit_ids),'religious candidate membership/source order differs from native')
 opened.semantic_candidates=candidates();assert(require('json').encode(native_ids)==require('json').encode(opened.semantic_candidates.unit_ids),'open-picker candidate observation changed result')
 opened.selector.displayed={};opened.selector.skills={};opened.selector.sorting={}
 for _,sort in ipairs(list.sorting_by)do opened.selector.sorting[#opened.selector.sorting+1]=sort.ident end
 for i=0,df.job_skill._last_item do if list.skills[i]~=0 then opened.selector.skills[#opened.selector.skills+1]={skill=i,weight=list.skills[i]}end end
 local function names(widget,depth,visible)
  assert(depth<10);visible=visible and (widget.flag.whole&1)==1
  if df.widget_unit_name:is_instance(widget) and visible then
   local name=df.reinterpret_cast(df.widget_unit_name,widget)
   opened.selector.displayed[#opened.selector.displayed+1]={id=name.u.id,histfig_id=name.u.hist_figure_id,x=widget.rect.x1,y=widget.rect.y1,x2=widget.rect.x2,y2=widget.rect.y2,flags=widget.flag.whole,tree_index=#opened.selector.displayed}
  end
  if not df.widget_container:is_instance(widget)then return end
  local _,address=df.sizeof(df.reinterpret_cast(df.widget_container,widget).children)
  local first=df.reinterpret_cast('uint64_t',address).value;local last=df.reinterpret_cast('uint64_t',address+8).value
  assert(last>=first and (last-first)%16==0 and last-first<=65536)
  for at=first,last-1,16 do local child=df.reinterpret_cast('uint64_t',at).value;if child~=0 then names(df.reinterpret_cast(df.widget,child),depth+1,visible)end end
 end
 names(list,0,true)
 assert(#opened.selector.displayed>0,'religious displayed candidates missing')
 table.sort(opened.selector.displayed,function(a,b)return a.y==b.y and a.tree_index<b.tree_index or a.y<b.y end)
 opened.semantic_rows=candidates(nil,true);assert(opened.semantic_rows.valid)
 assert(#opened.semantic_rows.rows==#opened.selector.displayed)
 for i,row in ipairs(opened.semantic_rows.rows)do
  assert(row.unit_id==opened.selector.displayed[i].id,'religious displayed order differs at '..i)
  assert(row.unit_id==native_ids[row.source_index+1],'religious source index differs')
  local unit=assert(df.unit.find(row.unit_id));assert(row.histfig_id==unit.hist_figure_id)
  local skills={};local score=0
  if unit.status.current_soul then for _,skill in ipairs(unit.status.current_soul.skills)do
   if list.skills[skill.id]~=0 then
    skills[#skills+1]={id=skill.id,rating=skill.rating,experience=skill.experience,weight=list.skills[skill.id]}
    score=score+skill.rating*list.skills[skill.id]
   end
  end end
  assert(score==row.score and require('json').encode(skills)==require('json').encode(row.skills),'religious skill facts differ')
 end
 local initial_displayed=opened.selector.displayed
 opened.interactions={}
 local function interaction(label)
  view:render(dfhack.getTickCount())
  opened.selector.displayed={};names(list,0,true)
  table.sort(opened.selector.displayed,function(a,b)return a.y==b.y and a.tree_index<b.tree_index or a.y<b.y end)
  local ids={};for _,row in ipairs(opened.selector.displayed)do ids[#ids+1]=row.id end
  local sorting={};for _,sort in ipairs(list.sorting_by)do sorting[#sorting+1]=sort.ident end
  opened.interactions[#opened.interactions+1]={name=label,ids=ids,sorting=sorting,
   sort_flags=list.sort_flags.whole,filter_bytes={list.filter_str:byte(1,#list.filter_str)}}
 end
 for header,x in ipairs{432,512,584,680}do
  for click=1,2 do pixel(x,70);interaction('sort-'..header..'-'..click)end
 end
 -- Fresh native open restores the default sort without mutating widget scratch.
 key('_MOUSE_R');open_picker();list=assert(find_list(selector,0))
 for _,query in ipairs{'a','AMOS','zzzzzz','glass'}do
  key('_MOUSE_R');open_picker();list=assert(find_list(selector,0))
  pixel(500,730);script.sleep(2,'frames')
  for i=1,#query do
   df.global.enabler.last_text_input[0]=query:byte(i);df.global.enabler.last_text_input[1]=0
   key(('STRING_A%03d'):format(query:byte(i)))
   script.sleep(2,'frames')
  end
  assert(list.filter_str==query:lower(),'religious filter input was not delivered: '..query..' => '..list.filter_str)
  interaction('filter-'..query)
 end
 key('_MOUSE_R');open_picker();list=assert(find_list(selector,0))
 opened.selector.displayed=initial_displayed
 g.mouse_x=60;g.mouse_y=20;g.precise_mouse_x=480;g.precise_mouse_y=240
 for i=1,8 do key('STANDARDSCROLL_PAGEDOWN')end
 opened.tail=capture('TEMPLE-priest-selector-tail',temple);table.remove(records)
 opened.selector.displayed={};names(list,0,true)
 opened.tail.displayed=opened.selector.displayed;opened.selector.displayed=initial_displayed
 local row_index={};for i,row in ipairs(opened.semantic_rows.rows)do row_index[row.unit_id]=i end
 local previous=0;local seen=0
 for _,row in ipairs(opened.tail.displayed)do if (row.flags&2)~=0 then
  local index=assert(row_index[row.id]);assert(index>previous,'scrolled native rows out of order');previous=index;seen=seen+1
 end end
 assert(seen>0 and previous==#opened.semantic_rows.rows,'native scroll did not expose final candidate')
 opened.recognition=recognition_state();assert(require('json').encode(opened.recognition)==require('json').encode(vacant.recognition),'opening selector changed simulation')
 key('_MOUSE_R');assert(not selector.flag.VISIBILITY_ACTIVE,'religious selector cancel failed')
 local cancelled=capture('TEMPLE-priest-selector-cancelled',temple);cancelled.recognition=recognition_state()
 assert(require('json').encode(cancelled.recognition)==require('json').encode(vacant.recognition),'cancelling selector changed simulation')
 cancelled.candidate_boundaries={}
 local probe_unit=assert(df.unit.find(opened.selector.displayed[1].id))
 local function probe(object,field,value,label)
  local old=object[field];object[field]=value
  local semantic=candidates();assert(semantic.valid)
  open_picker();assert(selector.flag.VISIBILITY_ACTIVE)
  local native={};for _,entry in ipairs(assert(find_list(selector,0)).entry_list)do native[#native+1]=entry.u.id end
  assert(require('json').encode(native)==require('json').encode(semantic.unit_ids),'religious eligibility mismatch: '..label)
  local included=false;for _,id in ipairs(native)do if id==probe_unit.id then included=true end end
  cancelled.candidate_boundaries[#cancelled.candidate_boundaries+1]={case=label,included=included,count=#native}
  key('_MOUSE_R');assert(not selector.flag.VISIBILITY_ACTIVE);object[field]=old
 end
 for profession=0,134 do probe(probe_unit,'profession',profession,'profession-'..profession)end
 for _,flag in ipairs{'inactive','marauder','merchant','diplomat','active_invader','invader_origin','forest'}do
  probe(probe_unit.flags1,flag,true,'unit-'..flag)
 end
 probe(probe_unit.flags3,'ghostly',true,'unit-ghostly')
 local probe_figure=assert(df.historical_figure.find(probe_unit.hist_figure_id))
 for _,link in ipairs(probe_figure.entity_links)do
  if link:getType()==df.histfig_entity_link_type.MEMBER and (link.entity_id==religion.id or link.entity_id==df.global.plotinfo.group_id)then
   probe(link,'link_strength',0,'membership-'..link.entity_id)
  end
 end
 open_picker();assert(selector.flag.VISIBILITY_ACTIVE)
 list=assert(find_list(selector,0))
 local chosen=opened.selector.displayed[1]
 local chosen_index=1
 if (recognition_case=='assignmilitarypriest' or recognition_case=='assigncommandpriest') then
  chosen=nil
  for i,row in ipairs(opened.selector.displayed)do
   local unit=assert(df.unit.find(row.id))
   if unit.military.squad_id>=0 then
    chosen=row;chosen_index=i;linked_squad=assert(df.squad.find(unit.military.squad_id));break
   end
  end
  assert(chosen,'no eligible military candidate')
 else assert(chosen.y<15,'unexpected first row geometry')end
 local function selected_state(unit_id,figure_id)
  local unit=assert(df.unit.find(unit_id or chosen.id));local figure=assert(df.historical_figure.find(figure_id or chosen.histfig_id))
  local function values(vector)local out={};for _,v in ipairs(vector)do out[#out+1]=v end;return out end
  local function scalar_fields(object)
   local out={};for k,v in pairs(object)do if type(v)=='number' or type(v)=='boolean' then out[k]=v end end;return out
  end
  local state={unit={id=unit.id,profession=unit.profession,profession2=unit.profession2,
   flags1=unit.flags1.whole,flags2=unit.flags2.whole,flags3=unit.flags3.whole,
   squad_id=unit.military.squad_id,squad_position=unit.military.squad_position,
   current_job=unit.job.current_job and scalar_fields(unit.job.current_job) or false,occupations={}},
   figure=scalar_fields(figure),entity_links={},site_links={},histfig_links={},nemesis=false,actors={}}
  for _,o in ipairs(unit.occupations)do state.unit.occupations[#state.unit.occupations+1]=scalar_fields(o)end
  for _,field in ipairs{'entity_links','site_links','histfig_links'}do
   for _,link in ipairs(figure[field])do local row=scalar_fields(link);row.type=link:getType();state[field][#state[field]+1]=row end
  end
  if figure.info and figure.info.skills then
   local skills=figure.info.skills;state.skills=scalar_fields(skills)
   for _,field in ipairs{'skills','points','professions_held','profession_years'}do state.skills[field]=values(skills[field])end
  end
  state.profiles={}
  for _,field in ipairs{'personality','reputation','relationships'}do
   local profile=figure.info and figure.info[field]
   state.profiles[field]=profile and scalar_fields(profile) or false
  end
  local function personality_state(p)
   if not p then return false end
   local result=scalar_fields(p);result.flags=p.flags.whole;result.traits=values(p.traits);result.habit=values(p.habit)
   for _,field in ipairs{'values','ethics','emotions','dreams','preferences','mannerism','needs'}do
    result[field]={};for _,entry in ipairs(p[field])do result[field][#result[field]+1]=scalar_fields(entry)end
   end
   return result
  end
  state.figure_personality=personality_state(figure.info and figure.info.personality and figure.info.personality.personality)
  state.unit_personality=personality_state(unit.status.current_soul and unit.status.current_soul.personality)
  local relationships=figure.info and figure.info.relationships
  local intrigues=relationships and relationships.intrigues
  state.intrigues=intrigues and scalar_fields(intrigues) or false
  if intrigues then
   for _,field in ipairs{'intrigue','plots','task','message'}do
    state.intrigues[field]={};for _,entry in ipairs(intrigues[field])do state.intrigues[field][#state.intrigues[field]+1]=scalar_fields(entry)end
   end
  end
  local nemesis
  for _,n in ipairs(df.global.world.nemesis.all)do if n.figure==figure then assert(not nemesis);nemesis=n end end
  assert(nemesis,'selected candidate has no nemesis')
  state.nemesis=scalar_fields(nemesis);state.nemesis.flags={};state.nemesis.companions=values(nemesis.companions)
  for i=0,df.nemesis_flags._last_item do if nemesis.flags[i]then state.nemesis.flags[#state.nemesis.flags+1]=df.nemesis_flags[i]end end
  for _,field in ipairs{'independent_actor','civilized_actor','plotter_actor','new_plotter_actor','religious_actor'}do
   state.actors[field]={};for _,n in ipairs(df.global.world.nemesis[field])do state.actors[field][#state.actors[field]+1]=n.id end
  end
  if linked_squad then
   state.squad={id=linked_squad.id,positions={},equipment_update=df.global.plotinfo.equipment.update.whole}
   for _,position in ipairs(linked_squad.positions)do
    local row=scalar_fields(position);row.activities=values(position.activities);row.events=values(position.events)
    row.equipment=scalar_fields(position.equipment);row.equipment.flags=position.equipment.flags.whole
    row.equipment.assigned_items=values(position.equipment.assigned_items)
    state.squad.positions[#state.squad.positions+1]=row
   end
   state.unit.uniform=scalar_fields(unit.uniform);state.unit.uniform.pickup_flags=unit.uniform.pickup_flags.whole
   state.unit.uniform.uniforms={}
   for i=0,df.unit_uniform_mode_type._last_item do state.unit.uniform.uniforms[#state.unit.uniform.uniforms+1]=values(unit.uniform.uniforms[i])end
   for _,field in ipairs{'clothing_item_id','uniform_pickup','uniform_drop'}do state.unit.uniform[field]=values(unit.uniform[field])end
  end
  if seeded_assignment_job then
   state.seeded_job={exists=false}
   for _,job in require('utils').listpairs(df.global.world.jobs.list)do if job.id==seeded_assignment_job.id then
    state.seeded_job=scalar_fields(job);state.seeded_job.exists=true;state.seeded_job.flags=job.flags.whole;state.seeded_job.refs={}
    for _,ref in ipairs(job.general_refs)do
     local row=scalar_fields(ref);row.type=ref:getType();state.seeded_job.refs[#state.seeded_job.refs+1]=row
    end
   end end
  end
  if not unit_id and previous_holder then state.previous_holder=selected_state(previous_holder_unit,previous_holder.id)end
  return state
 end
 cancelled.selected=selected_state()
 local assignment_expected,assign_semantic,assign_revision,assign_observe
 if semantic_recognition then
  local marker=assert(io.open(out..'/recognition-reference'));local path=marker:read('*a'):match('^%s*(.-)%s*$');marker:close()
  local file=assert(io.open(path));local reference=require('json').decode(file:read('*a'));file:close()
  assert(reference.success and #reference.records==4);assignment_expected=reference.records[4]
  assert(require('json').encode(cancelled.selected)==require('json').encode(reference.records[3].selected),'assignment initial selected state differs')
  restore_rng(reference.records[3].recognition.rng)
  local function assignment_receipt()
   local text,code=dfhack.run_command_silent('df3d','location-religious-assignment-receipt',tostring(df.global.plotinfo.site_id),tostring(temple.id),tostring(religion.id),tostring(assignment.id),tostring(chosen.id))
   assert(code==0,text);local receipt=require('json').decode(text);assert(receipt.valid);return receipt
  end
  local receipt=assignment_receipt();assert(receipt.eligible and receipt.holder_id==expected_holder and receipt.histfig_id==chosen.histfig_id)
  assign_observe=assignment_receipt
  assign_revision=receipt.revision
  assign_semantic=function(ids,revision)
   local args=ids or {df.global.plotinfo.site_id,temple.id,religion.id,assignment.id,chosen.id,expected_holder}
   local strings={};for _,value in ipairs(args)do strings[#strings+1]=tostring(value)end
   strings[#strings+1]=revision or assign_revision
   local result,status=dfhack.run_command_silent('df3d','location-religious-assign',table.unpack(strings))
   assert(status==0,result);return require('json').decode(result).outcome
  end
  local guards={}
  for _,object in ipairs{m,g}do
   local n,at=df.sizeof(object);local bytes=df.new('uint8_t',n);dfhack.internal.memmove(bytes,at,n)
   guards[#guards+1]={bytes=bytes,address=at,size=n}
  end
  local before=require('json').encode(selected_state());local simulation=require('json').encode(recognition_state())
  for i=1,5 do
   local ids={df.global.plotinfo.site_id,temple.id,religion.id,assignment.id,chosen.id,expected_holder};ids[i]=-1
   assert(assign_semantic(ids)==1,'invalid assignment accepted')
  end
  assert(assign_semantic(nil,'0')==1,'zero assignment revision accepted')
  assert(assign_semantic(nil,tostring(tonumber(assign_revision)+1))==4,'stale assignment accepted')
  assert(before==require('json').encode(selected_state()) and simulation==require('json').encode(recognition_state()),'rejected assignment changed simulation')
  cancelled.assignment_receipt_probes={}
  local function stale_probe(name,object,field,value)
   local original=object[field];object[field]=value
   local changed=assignment_receipt();assert(changed.revision~=assign_revision,'receipt missed '..name)
   local function simulation_snapshot()
    local text,code=dfhack.run_command_silent('df3d','location-recognition-read',tostring(df.global.plotinfo.site_id),tostring(temple.id))
    assert(code==0,text);return text
   end
   local seeded=require('json').encode(selected_state());local seeded_sim=simulation_snapshot()
   assert(assign_semantic()==4,'stale candidate accepted: '..name)
   assert(seeded==require('json').encode(selected_state()) and seeded_sim==simulation_snapshot(),'stale candidate changed simulation: '..name)
   object[field]=original
   assert(assignment_receipt().revision==assign_revision,'receipt not restored: '..name)
   cancelled.assignment_receipt_probes[#cancelled.assignment_receipt_probes+1]={dependency=name,eligible=changed.eligible,outcome=4}
  end
  local selected_unit=assert(df.unit.find(chosen.id))
  local selected_figure=assert(df.historical_figure.find(chosen.histfig_id))
  local member
  for _,link in ipairs(selected_figure.entity_links)do
   if link.entity_id==religion.id and link:getType()==df.histfig_entity_link_type.MEMBER then member=link;break end
  end
  assert(member and member.link_strength==100)
  stale_probe('membership strength',member,'link_strength',99)
  stale_probe('membership eligibility',member,'link_strength',0)
  stale_probe('custom profession',selected_unit,'custom_profession','receipt probe')
  stale_probe('unit inactive',selected_unit.flags1,'inactive',true)
  local nemesis=assert(df.nemesis_record.find(receipt.nemesis_id))
  stale_probe('nemesis group leader',nemesis,'group_leader_id',nemesis.group_leader_id+1)
  stale_probe('uniform pickup',selected_unit.uniform.pickup_flags,'whole',selected_unit.uniform.pickup_flags.whole~1)
  assert(assign_semantic()==2,'semantic religious assignment failed')
  for _,guard in ipairs(guards)do
   assert(dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)==0,'religious assignment changed UI/gps');df.delete(guard.bytes)
  end
 elseif (recognition_case=='assignmilitarypriest' or recognition_case=='assigncommandpriest') then
  cancelled.selection_input={initial_cursor=list.cursor_idx,chosen_index=chosen_index,unit_id=chosen.id}
  for i=2,chosen_index do key('STANDARDSCROLL_DOWN')end
  cancelled.selection_input.final_cursor=list.cursor_idx
  assert(list.cursor_idx==chosen_index-1,'native selected military cursor differs: '..list.cursor_idx..' expected '..(chosen_index-1))
  key('SELECT')
 else pixel(450,106) end
 assert(assignment.histfig==chosen.histfig_id,'native assignment did not choose first displayed candidate')
 local assigned=capture('TEMPLE-priest-assigned',temple);assigned.recognition=recognition_state();assigned.chosen=chosen
 assigned.selector_active=selector.flag.VISIBILITY_ACTIVE;assigned.new_events={}
 assigned.selected=selected_state()
 for i=cancelled.recognition.event_count,#df.global.world.history.events-1 do
  local event=df.global.world.history.events[i];local value={id=event.id,type=df.history_event_type[event:getType()],year=event.year,seconds=event.seconds}
  if df.history_event_add_hf_entity_linkst:is_instance(event) or df.history_event_remove_hf_entity_linkst:is_instance(event)then for _,field in ipairs{'civ','histfig','link_type','position_id'}do value[field]=event[field]end end
  assigned.new_events[#assigned.new_events+1]=value
 end
 if assignment_expected then
  -- Native5c02a0 initializes through0x183, then starts the debug block at0x18c.
  -- Newly allocated historical profiles leave these two counters indeterminate.
  -- Retain their raw observations; compare them only for pre-existing profiles.
  assigned.comparison_excluded_fields={}
  local function comparable_selected(value,before,path)
   local copy=require('json').decode(require('json').encode(value))
   if before.figure_personality==false and copy.figure_personality then
    copy.figure_personality.current_focus=nil;copy.figure_personality.undistracted_focus=nil
    assigned.comparison_excluded_fields[path..'.figure_personality']='newly allocated current_focus/undistracted_focus'
   end
   if copy.previous_holder then copy.previous_holder=comparable_selected(copy.previous_holder,before.previous_holder,path..'.previous_holder')end
   return copy
  end
  if cancelled.selected.figure_personality==false then
   local personality=assert(df.historical_figure.find(chosen.histfig_id).info.personality).personality
   local _,base=df.sizeof(personality);assigned.personality_focus_offsets={}
   for _,field in ipairs{'current_focus','undistracted_focus'}do
    local _,address=df.sizeof(personality:_field(field));assigned.personality_focus_offsets[field]=address-base
   end
   assert(assigned.personality_focus_offsets.current_focus==0x184 and assigned.personality_focus_offsets.undistracted_focus==0x188)
  end
  for _,field in ipairs{'recognition','selected','new_events'}do
   local actual,expected=assigned[field],assignment_expected[field]
   if field=='selected' then
    actual=comparable_selected(actual,cancelled.selected,'selected');expected=comparable_selected(expected,cancelled.selected,'selected')
   end
   assert(require('json').encode(actual)==require('json').encode(expected),'semantic assignment differs from native: '..field)
  end
  assert(assign_semantic()==4,'completed assignment replay accepted')
  assigned.selected_after_stale_replay=selected_state()
  assert(require('json').encode(without_lookup_indexes(assigned.selected))==require('json').encode(without_lookup_indexes(assigned.selected_after_stale_replay)),'stale replay changed selected unit')
  assigned.semantic_matches_native=true
  if recognition_case=='assignspypriest' then
   local plots=assert(df.historical_figure.find(chosen.histfig_id).info.relationships.intrigues)
   assert(#plots.plots==1 and plots.plots[0].plot_type==12 and plots.plots[0].parameter==religion.id)
   assigned.plot_receipt_probes={}
   for _,probe in ipairs{{plots,'next_plot_id'},{plots.plots[0],'id'},{plots.plots[0],'plot_type'},{plots.plots[0],'parameter'}}do
    local before=assign_observe().revision;local object,field=probe[1],probe[2];local original=object[field]
    object[field]=original+1;assert(assign_observe().revision~=before,'receipt missed plot '..field)
    local seeded=require('json').encode(selected_state())
    local args={df.global.plotinfo.site_id,temple.id,religion.id,assignment.id,chosen.id,assignment.histfig}
    assert(assign_semantic(args,before)==4,'changed plot receipt was accepted '..field)
    assert(require('json').encode(selected_state())==seeded,'stale plot request changed selected records '..field)
    object[field]=original;assert(assign_observe().revision==before,'plot receipt did not restore '..field)
    assigned.plot_receipt_probes[#assigned.plot_receipt_probes+1]=field
   end
  end
 end
 contents.location_tier=original;assert(#records==4);return
end
if recognition_case:sub(1,6)=='remove' then
 local assignment
 for _,a in ipairs(religion.positions.assignments)do if a.st_id==df.global.plotinfo.site_id then assert(not assignment);assignment=a end end
 assert(assignment and assignment.histfig>=0)
 local holder=assert(df.historical_figure.find(assignment.histfig))
 local original_holder_unit=holder.unit_id
 if recognition_case=='removeabsentpriest' then
  -- Exercise absent historical-figure unit association in the unsaved clone.
  -- Keep unrelated live unit records intact; native lookup must resolve nil.
  holder.unit_id=-1;assert(not df.unit.find(holder.unit_id))
 end
 local squad
 if recognition_case=='removesquadpriest' then
  local unit=assert(df.unit.find(holder.unit_id));squad=assert(df.squad.find(unit.military.squad_id))
  assert(unit.military.squad_position==0 and squad.positions[0].occupant==holder.id)
  assignment.squad_id=squad.id
 end
 local seeded_job_id
 if recognition_case=='removemanagerpriest' or recognition_case=='removeaccountantpriest' then
  local unit=assert(df.unit.find(holder.unit_id));assert(not unit.job.current_job)
  local position
  for _,p in ipairs(religion.positions.own)do if p.id==assignment.position_id then position=p end end
  assert(position)
  local manager=recognition_case=='removemanagerpriest'
  position.responsibilities[manager and df.entity_position_responsibility.MANAGE_PRODUCTION or df.entity_position_responsibility.ACCOUNTING]=true
  local job=df.job:new();job.job_type=manager and df.job_type.ManageWorkOrders or df.job_type.UpdateStockpileRecords
  job.pos:assign(unit.pos);job.posting_index=-1
  assert(dfhack.job.linkIntoWorld(job,true));assert(dfhack.job.addWorker(job,unit));seeded_job_id=job.id
 end
 local function holder_state()
  local result={id=holder.id,links={}}
  if seeded_job_id then result.seeded_job_exists=false;for _,job in require('utils').listpairs(df.global.world.jobs.list)do if job.id==seeded_job_id then result.seeded_job_exists=true end end end
  local unit=df.unit.find(holder.unit_id)
  if unit then
   result.unit={id=unit.id,profession=unit.profession,profession2=unit.profession2,
    squad_id=unit.military.squad_id,squad_position=unit.military.squad_position,
    current_job=unit.job.current_job and {id=unit.job.current_job.id,type=df.job_type[unit.job.current_job.job_type]} or false}
  end
  local function offset(object,field)
   local _,base=df.sizeof(object);local _,address=df.sizeof(object:_field(field));return address-base
  end
  local position
  for _,p in ipairs(religion.positions.own)do if p.id==assignment.position_id then position=p end end
  assert(position)
  result.native_offsets={assignment_squad=offset(assignment,'squad_id'),position_responsibilities=offset(position,'responsibilities')}
  if unit then result.native_offsets.unit_military=offset(unit,'military') end
  if squad then
   local leader=squad.positions[0];local equipment=leader.equipment
   result.squad={id=squad.id,occupant=leader.occupant,quiver=equipment.quiver,backpack=equipment.backpack,flask=equipment.flask}
   result.native_offsets.squad_positions=offset(squad,'positions')
   result.native_offsets.squad_quiver=offset(leader,'equipment')+offset(equipment,'quiver')
   result.native_offsets.squad_backpack=offset(leader,'equipment')+offset(equipment,'backpack')
   local _,address=df.sizeof(df.global.plotinfo.equipment:_field('update'))
   result.native_offsets.equipment_update=address-dfhack.internal.getImageBase()
  end
  result.position_responsibilities={}
  for i=0,df.entity_position_responsibility._last_item do
   if position.responsibilities[i]then result.position_responsibilities[#result.position_responsibilities+1]=df.entity_position_responsibility[i]end
  end

  for _,link in ipairs(holder.entity_links)do
   local row={type=df.histfig_entity_link_type[link:getType()],entity_id=link.entity_id,strength=link.link_strength}
   if df.histfig_entity_link_positionst:is_instance(link) then row.assignment_id=link.assignment_id;row.start_year=link.start_year
   elseif df.histfig_entity_link_former_positionst:is_instance(link) then row.assignment_id=link.assignment_id;row.start_year=link.start_year;row.end_year=link.end_year end
   result.links[#result.links+1]=row
  end
  return result
 end
 local expected,removal_revision
 local function removal_receipt()
  local text,code=dfhack.run_command_silent('df3d','location-religious-receipt',tostring(df.global.plotinfo.site_id),tostring(temple.id),tostring(religion.id),tostring(assignment.id))
  assert(code==0,text);local receipt=require('json').decode(text);assert(receipt.valid,'religious receipt unavailable');return receipt
 end
 local function remove_semantic(ids,revision)
  local args=ids or {tostring(df.global.plotinfo.site_id),tostring(temple.id),tostring(religion.id),tostring(assignment.id),tostring(holder.id)}
  args[6]=revision or removal_revision
  local text,code=dfhack.run_command_silent('df3d','location-religious-remove',table.unpack(args))
  assert(code==0,text);return require('json').decode(text).outcome
 end
 if semantic_recognition then
  local marker=assert(io.open(out..'/recognition-reference'));local path=marker:read('*a'):match('^%s*(.-)%s*$');marker:close()
  local file=assert(io.open(path));local reference=require('json').decode(file:read('*a'));file:close()
  assert(reference.success and #reference.records==3);expected=reference.records[2]
  restore_rng(reference.records[1].recognition.rng)
 end
 local ok,err=xpcall(function()
  local before=capture('TEMPLE-0-priest-remove-before',temple);before.recognition=recognition_state();before.holder=holder_state()
  local guards={}
  if semantic_recognition then
   for _,object in ipairs{m,g}do
    local n,at=df.sizeof(object);local bytes=df.new('uint8_t',n);dfhack.internal.memmove(bytes,at,n);guards[#guards+1]={bytes=bytes,address=at,size=n}
   end
   local receipt=removal_receipt();assert(receipt.removable and receipt.holder_id==holder.id)
   removal_revision=receipt.revision
   assert(require('json').encode(receipt)==require('json').encode(removal_receipt()),'religious receipt unstable')
   assert(remove_semantic(nil,'0')==1 and remove_semantic(nil,'9223372036854775808')==1,'invalid revision accepted')
   before.removal_receipt=receipt;before.stale_dependencies={}
   local function stale(object,key,value,label)
    local original=object[key];object[key]=value
    local changed=removal_receipt();assert(changed.revision~=removal_revision,'dependency not bound: '..label)
    local records=require('json').encode(recognition_state());local held=require('json').encode(holder_state())
    assert(remove_semantic()==4,'stale removal not refused: '..label)
    assert(records==require('json').encode(recognition_state()) and held==require('json').encode(holder_state()),'stale removal changed state: '..label)
    assert(changed.revision==removal_receipt().revision,'stale removal changed receipt: '..label)
    object[key]=original;assert(removal_receipt().revision==removal_revision,'restored dependency changed revision: '..label)
    before.stale_dependencies[#before.stale_dependencies+1]=label
   end
   stale(assignment,'histfig',-1,'assignment holder')
   stale(assignment,'squad_id',assignment.squad_id==-1 and 125 or -1,'assignment squad')
   local position
   for _,p in ipairs(religion.positions.own)do if p.id==assignment.position_id then position=p end end
   assert(position)
   stale(position.responsibilities,df.entity_position_responsibility.MANAGE_PRODUCTION,not position.responsibilities.MANAGE_PRODUCTION,'position responsibility')
   stale(holder,'unit_id',holder.unit_id==-1 and original_holder_unit or -1,'holder unit')
   for _,link in ipairs(holder.entity_links)do
    if df.histfig_entity_link_positionst:is_instance(link) and link.entity_id==religion.id and link.assignment_id==assignment.id then stale(link,'link_strength',link.link_strength+1,'position link')end
   end
   local unit=df.unit.find(holder.unit_id)
   if unit then
    stale(unit.military,'squad_position',unit.military.squad_position+1,'unit military position')
    stale(unit.uniform.pickup_flags,'whole',unit.uniform.pickup_flags.whole==0 and 1 or 0,'uniform pickup flags')
    local current_squad=df.squad.find(unit.military.squad_id)
    if current_squad and #current_squad.positions>0 then stale(current_squad.positions[0],'occupant',-1,'squad occupant')end
    if unit.job.current_job then stale(unit.job.current_job,'order_id',unit.job.current_job.order_id+1,'current job order')end
   end
   for field=1,5 do
    local ids={tostring(df.global.plotinfo.site_id),tostring(temple.id),tostring(religion.id),tostring(assignment.id),tostring(holder.id)}
    ids[field]='2147483647';assert(remove_semantic(ids)==1,'invalid removal identity accepted')
   end
   assert(require('json').encode(recognition_state())==require('json').encode(before.recognition),'rejected removal changed records')
   assert(require('json').encode(holder_state())==require('json').encode(before.holder),'rejected removal changed holder')
   assert(remove_semantic()==2,'semantic religious removal failed')
   for _,guard in ipairs(guards)do assert(dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)==0,'semantic removal changed native UI/gps');df.delete(guard.bytes)end
  else pixel(944,358)end
  local after=capture('TEMPLE-0-priest-remove-after',temple);after.recognition=recognition_state();after.holder=holder_state()
  assert(assignment.histfig==-1,'native religious removal did not vacate assignment')
  if squad then assert(after.holder.squad.occupant==-1 and after.holder.unit.squad_id==-1 and after.holder.unit.squad_position==-1,'native squad cleanup missing')end
  if seeded_job_id then assert(not after.holder.unit.current_job,'native matching job not cancelled')end
  assert(after.recognition.bridge.rank==before.recognition.bridge.rank,'removal changed recognition rank')
  for _,field in ipairs{'positions','next_position','next_assignment','temple_emotions','rng'}do
   assert(require('json').encode(before.recognition[field])==require('json').encode(after.recognition[field]),'removal unexpectedly changed '..field)
  end
  after.new_events={}
  for i=before.recognition.event_count,#df.global.world.history.events-1 do
   local event=df.global.world.history.events[i]
   local item={id=event.id,type=df.history_event_type[event:getType()],year=event.year,seconds=event.seconds}
   if df.history_event_remove_hf_entity_linkst:is_instance(event)then
    for _,field in ipairs{'civ','histfig','link_type','position_id'}do item[field]=event[field]end
   end
   after.new_events[#after.new_events+1]=item
  end
  if expected then
   for _,field in ipairs{'recognition','holder','new_events'}do
    assert(require('json').encode(after[field])==require('json').encode(expected[field]),'semantic removal differs from native '..field)
   end
   assert(remove_semantic()==4,'completed removal old receipt not stale')
   local fresh=removal_receipt();assert(not fresh.removable,'vacated assignment still removable')
   assert(remove_semantic(nil,fresh.revision)==1,'completed removal not rejected')
  else pixel(944,358)end
  local repeated=capture('TEMPLE-0-priest-remove-repeat',temple);repeated.recognition=recognition_state();repeated.holder=holder_state()
  assert(require('json').encode(after.recognition)==require('json').encode(repeated.recognition),'empty remove changed recognition records')
  assert(require('json').encode(after.holder)==require('json').encode(repeated.holder),'empty remove changed holder links')
 end,debug.traceback)
 contents.location_tier=original
 assert(ok,err);assert(#records==3,'incomplete priest removal reference');return
end
local ok,err=xpcall(function()
 if recognition_case=='firstguidance' then
  difficulty.priesthood_unit_count=54
  local row=capture('TEMPLE-0-recognition-first-population',temple);row.recognition=recognition_state()
  assert(row.recognition.bridge.state==3,'first population state mismatch')
  difficulty.priesthood_unit_count=original_priest_threshold
 end
 if recognition_case=='eligibility' then
  for tier=0,1 do
   contents.location_tier=tier
   local row=capture('TEMPLE-0-recognition-guidance-'..tier,temple);row.recognition=recognition_state()
   assert(row.recognition.bridge.state==tier+1,'native tier guidance mismatch')
   assert(row.lines[18]:find(tier==0 and 'You can recognize a priesthood once this is a temple.' or 'You can recognize a high priest when this is a temple complex.',1,true),'native tier hint absent')
  end
  contents.location_tier=2;difficulty.high_priesthood_unit_count=54
  local denied=capture('TEMPLE-0-recognition-population-denied',temple);denied.recognition=recognition_state()
  assert(denied.recognition.bridge.state==3 and denied.lines[18]:find('High priest: 54 worshippers',1,true),'native population guidance mismatch')
  pixel(500,214)
  local refused=capture('TEMPLE-0-recognition-population-refused',temple);refused.recognition=recognition_state()
  for _,field in ipairs{'positions','assignments','event_count','next_position','next_assignment','site_links','holder_links'}do
   assert(require('json').encode(denied.recognition[field])==require('json').encode(refused.recognition[field]),'ineligible native click changed '..field)
  end
  difficulty.high_priesthood_unit_count=53
  local boundary=capture('TEMPLE-0-recognition-population-exact',temple);boundary.recognition=recognition_state()
  assert(boundary.recognition.bridge.state==5 and boundary.lines[18]:find('Recognize high priest',1,true),'native inclusive threshold mismatch')
  -- A continuing agreement waives the population gate. Own every fixture
  -- object and remove it before any native recognition action is submitted.
  difficulty.high_priesthood_unit_count=54
  local agreement=df.agreement:new();local party=df.agreement_party:new()
  local subject=df.agreement_details:new();local location=df.agreement_details_data_location:new()
  local all=df.global.world.agreements.all;local continuing=df.global.plotinfo.continuing_agreement_id
  agreement.id=2147483646;assert(#all==0 or all[#all-1].id<agreement.id,'recognition fixture ID occupied')
  party.id=0;party.entity_ids:insert('#',religion.id)
  location.applicant=0;location.government=1;location.site=df.global.plotinfo.site_id
  location.type=df.abstract_building_type.TEMPLE;location.deity_type=df.religious_practice_type.RELIGION_ENID
  location.deity_data.Religion=religion.id;location.tier=2
  subject.id=0;subject.type=df.agreement_details_type.Location;subject.data.Location=location
  agreement.parties:insert('#',party);agreement.details:insert('#',subject)
  all:insert('#',agreement);continuing:insert('#',agreement.id)
  local agreement_ok,agreement_error=xpcall(function()
   local row=capture('TEMPLE-0-recognition-agreement-waiver',temple);row.recognition=recognition_state()
   assert(row.recognition.bridge.state==5 and row.lines[18]:find('Recognize high priest',1,true),'native continuing-agreement waiver mismatch')
   assert(#row.recognition.bridge.continuing_agreements==1 and row.recognition.bridge.continuing_agreements[1]==agreement.id)
  end,debug.traceback)
  assert(continuing[#continuing-1]==agreement.id and all[#all-1]==agreement,'recognition fixture ownership changed')
  continuing:erase(#continuing-1);all:erase(#all-1)
  agreement.parties:resize(0);agreement.details:resize(0);subject.data.Location=nil
  df.delete(location);df.delete(subject);df.delete(party);df.delete(agreement)
  assert(agreement_ok,agreement_error)
  difficulty.high_priesthood_unit_count=original_threshold
 end
 if recognition_case=='waiver' then difficulty.high_priesthood_unit_count=54 end
 local before=capture('TEMPLE-0-recognition-before',temple);before.recognition=recognition_state()
 if recognition_case=='positionhigh' or recognition_case=='positionnew' then
  local marker=assert(io.open(out..'/recognition-reference'));local path=marker:read('*a'):match('^%s*(.-)%s*$');marker:close()
  local file=assert(io.open(path,'rb'));local reference=require('json').decode(file:read('*a'));file:close()
  assert(reference.success and #reference.records==3,'invalid native position reference')
  local expected_before=reference.records[1].recognition;local expected_after=reference.records[2].recognition
  assert(expected_before.case==(first_recognition and 'new' or 'promote'),'wrong position reference branch')
  local function invoke(command,site,id)
   local text,code=dfhack.run_command_silent('df3d',command,tostring(site),tostring(id))
   assert(code==0,text);return require('json').decode(text)
  end
  local guards={}
  for _,object in ipairs{m,g}do
   local n,at=df.sizeof(object);local bytes=df.new('uint8_t',n);dfhack.internal.memmove(bytes,at,n)
   guards[#guards+1]={bytes=bytes,address=at,size=n}
  end
  for _,target in ipairs{{-1,temple.id},{df.global.plotinfo.site_id,2147483647},{df.global.plotinfo.site_id+1,temple.id},{df.global.plotinfo.site_id,1}}do
   assert(not invoke('location-recognition-position',target[1],target[2]).prepared,'invalid position target accepted')
  end
  local rejected=recognition_state()
  assert(require('json').encode(before.recognition.rng)==require('json').encode(rejected.rng),'rejected position preparation consumed RNG')
  restore_rng(expected_before.rng)
  assert(invoke('location-recognition-thoughts',df.global.plotinfo.site_id,temple.id).applied,'native preceding thought step unavailable')
  local prepared=invoke('location-recognition-position',df.global.plotinfo.site_id,temple.id)
  assert(prepared.prepared,'native position preparation unavailable')
  for _,guard in ipairs(guards)do
   assert(dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)==0,'position preparation changed native UI/gps')
   df.delete(guard.bytes)
  end
  local after=capture('TEMPLE-0-recognition-position-after',temple);after.recognition=recognition_state();after.recognition.prepared=prepared.position
  local expected=expected_after.positions[#expected_after.positions]
  for field,value in pairs(expected)do
   assert(require('json').encode(prepared.position[field])==require('json').encode(value),'prepared position differs from native field '..field)
  end
  assert(require('json').encode(after.recognition.rng)==require('json').encode(expected_after.rng),'position preparation RNG differs from native')
  for _,field in ipairs{'positions','assignments','event_count','next_position','next_assignment','site_links','holder_links','petitions','continuing','agreements'}do
   assert(require('json').encode(before.recognition[field])==require('json').encode(after.recognition[field]),'unpublished position changed '..field)
  end
  return
 end
 if recognition_case=='agreements' then
  local marker=assert(io.open(out..'/recognition-reference'));local path=marker:read('*a'):match('^%s*(.-)%s*$');marker:close()
  local file=assert(io.open(path,'rb'));local reference=require('json').decode(file:read('*a'));file:close()
  assert(reference.success and #reference.records==3,'invalid native agreement reference')
  local expected_before=reference.records[1].recognition;local expected_after=reference.records[2].recognition
  assert(expected_before.case=='petitions','expected native petition case')
  for _,field in ipairs{'petitions','continuing','agreements'}do
   assert(require('json').encode(before.recognition[field])==require('json').encode(expected_before[field]),'agreement fixture mismatch')
  end
  local function apply(site,id)
   local text,code=dfhack.run_command_silent('df3d','location-recognition-agreements',tostring(site),tostring(id))
   assert(code==0,text);return require('json').decode(text)
  end
  local guards={}
  for _,object in ipairs{m,g}do
   local n,at=df.sizeof(object);local bytes=df.new('uint8_t',n);dfhack.internal.memmove(bytes,at,n)
   guards[#guards+1]={bytes=bytes,address=at,size=n}
  end
  for _,target in ipairs{{-1,temple.id},{df.global.plotinfo.site_id,2147483647},{df.global.plotinfo.site_id+1,temple.id},{df.global.plotinfo.site_id,1}}do
   assert(not apply(target[1],target[2]).applied,'invalid agreement target accepted')
  end
  contents.location_tier=1
  assert(not apply(df.global.plotinfo.site_id,temple.id).applied,'ineligible agreement action accepted')
  contents.location_tier=2
  local rejected=recognition_state()
  for _,field in ipairs{'petitions','continuing','agreements','rng'}do
   assert(require('json').encode(before.recognition[field])==require('json').encode(rejected[field]),'rejected agreement action changed '..field)
  end
  local applied=apply(df.global.plotinfo.site_id,temple.id)
  assert(applied.applied and #applied.agreement_ids==2 and applied.agreement_ids[1]==fixture_agreements[2] and applied.agreement_ids[2]==fixture_agreements[5],'wrong agreements concluded')
  for _,guard in ipairs(guards)do
   assert(dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)==0,'agreement primitive changed native UI/gps')
   df.delete(guard.bytes)
  end
  local after=capture('TEMPLE-0-recognition-agreements-after',temple);after.recognition=recognition_state();after.recognition.applied=applied
  for _,field in ipairs{'petitions','continuing','agreements'}do
   assert(require('json').encode(after.recognition[field])==require('json').encode(expected_after[field]),'bridge agreement effect differs from native '..field)
  end
  for _,field in ipairs{'positions','assignments','event_count','next_position','next_assignment','site_links','holder_links','temple_emotions','rng'}do
   assert(require('json').encode(before.recognition[field])==require('json').encode(after.recognition[field]),'agreement primitive changed '..field)
  end
  return
 end
 if recognition_case=='thoughts' then
  local marker=assert(io.open(out..'/recognition-reference'));local path=marker:read('*a'):match('^%s*(.-)%s*$');marker:close()
  local file=assert(io.open(path,'rb'));local reference=require('json').decode(file:read('*a'));file:close()
  assert(reference.success and #reference.records==3,'invalid native effect reference')
  local expected_before=reference.records[1].recognition;local expected_after=reference.records[2].recognition
  assert(expected_before.case=='promote' and expected_before.rng,'native promotion reference lacks RNG')
  assert(require('json').encode(before.recognition.temple_emotions)==require('json').encode(expected_before.temple_emotions),'thought fixture baseline mismatch')
  local function apply(site,id)
   local text,code=dfhack.run_command_silent('df3d','location-recognition-thoughts',tostring(site),tostring(id))
   assert(code==0,text);return require('json').decode(text)
  end
  local guards={}
  for _,object in ipairs{m,g}do
   local n,at=df.sizeof(object);local bytes=df.new('uint8_t',n);dfhack.internal.memmove(bytes,at,n)
   guards[#guards+1]={bytes=bytes,address=at,size=n}
  end
  for _,target in ipairs{{-1,temple.id},{df.global.plotinfo.site_id,-1},{df.global.plotinfo.site_id+1,temple.id},{df.global.plotinfo.site_id,1}}do
   assert(not apply(target[1],target[2]).applied,'invalid thought target accepted')
  end
  difficulty.high_priesthood_unit_count=54
  assert(not apply(df.global.plotinfo.site_id,temple.id).applied,'ineligible thought action accepted')
  difficulty.high_priesthood_unit_count=original_threshold
  local rejected=recognition_state()
  assert(require('json').encode(rejected.temple_emotions)==require('json').encode(before.recognition.temple_emotions),'rejected thought action changed emotions')
  assert(require('json').encode(rejected.rng)==require('json').encode(before.recognition.rng),'rejected thought action consumed RNG')
  -- Controlled paired-effect comparison only. Runtime does not restore RNG.
  restore_rng(expected_before.rng)
  local applied=apply(df.global.plotinfo.site_id,temple.id)
  assert(applied.applied and #applied.unit_ids==54,'native thought application unavailable')
  for _,guard in ipairs(guards)do
   assert(dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)==0,'thought primitive changed native UI/gps')
   df.delete(guard.bytes)
  end
  local after=capture('TEMPLE-0-recognition-thoughts-after',temple);after.recognition=recognition_state();after.recognition.applied=applied
  assert(require('json').encode(after.recognition.temple_emotions)==require('json').encode(expected_after.temple_emotions),'bridge thoughts differ from native recognition')
  for _,field in ipairs{'positions','assignments','event_count','next_position','next_assignment','site_links','holder_links'}do
   assert(require('json').encode(before.recognition[field])==require('json').encode(after.recognition[field]),'thought primitive changed '..field)
  end
  return
 end
 local expected_action=nil
 local function recognition_receipt(site,id)
  local text,code=dfhack.run_command_silent('df3d','location-recognition-receipt',tostring(site or df.global.plotinfo.site_id),tostring(id or temple.id))
  assert(code==0,text);return require('json').decode(text)
 end
 local function recognize(site,id,revision)
  if revision==nil then revision=recognition_receipt(site,id).revision or '1' end
  local text,code=dfhack.run_command_silent('df3d','location-recognize',tostring(site or df.global.plotinfo.site_id),tostring(id or temple.id),revision)
  assert(code==0,text);return require('json').decode(text).outcome
 end
 if semantic_recognition then
  local marker=assert(io.open(out..'/recognition-reference'));local path=marker:read('*a'):match('^%s*(.-)%s*$');marker:close()
  local file=assert(io.open(path,'rb'));local reference=require('json').decode(file:read('*a'));file:close()
  assert(reference.success and #reference.records==3 and reference.records[1].recognition.case==recognition_case,'invalid complete recognition reference')
  expected_action=reference.records[2].recognition
  restore_rng(reference.records[1].recognition.rng)
  local guards={}
  for _,object in ipairs{m,g}do
   local n,at=df.sizeof(object);local bytes=df.new('uint8_t',n);dfhack.internal.memmove(bytes,at,n)
   guards[#guards+1]={bytes=bytes,address=at,size=n}
  end
  local rejection_baseline=recognition_state()
  for _,target in ipairs{{-1,temple.id},{df.global.plotinfo.site_id,-1},{df.global.plotinfo.site_id+1,temple.id},{df.global.plotinfo.site_id,2147483647},{df.global.plotinfo.site_id,1}}do
   assert(recognize(target[1],target[2])==0,'invalid full recognition target accepted')
  end
  local eligible_tier=contents.location_tier;contents.location_tier=0
  assert(recognize()==0,'ineligible full recognition accepted');contents.location_tier=eligible_tier
  local receipt=recognition_receipt();assert(receipt.valid and receipt.revision==recognition_receipt().revision,'unstable recognition receipt')
  assert(recognize(nil,nil,'0')==0 and recognize(nil,nil,'9223372036854775808')==0,'invalid revision accepted')
  local stale_checks=0
  local function stale_scalar(object,field,value)
   local saved=object[field];object[field]=value
   if field=='incoming' then assert(recognition_state().bridge.worshippers==before.recognition.bridge.worshippers,'recipient probe changed displayed count')end
   assert(recognize(nil,nil,receipt.revision)==3,'changed '..field..' did not stale recognition')
   object[field]=saved;stale_checks=stale_checks+1
   assert(recognition_receipt().revision==receipt.revision,'restored '..field..' changed receipt')
  end
  local incoming=assert(df.unit.find(7351));assert(incoming.flags1.inactive and incoming.flags1.incoming,'incoming recipient fixture missing')
  stale_scalar(incoming.flags1,'incoming',false)
  stale_scalar(contents,'location_tier',0)
  stale_scalar(difficulty,'priesthood_unit_count',difficulty.priesthood_unit_count+1)
  stale_scalar(difficulty,'high_priesthood_unit_count',difficulty.high_priesthood_unit_count+1)
  stale_scalar(religion.positions,'next_position_id',religion.positions.next_position_id+1)
  stale_scalar(religion.positions,'next_assignment_id',religion.positions.next_assignment_id+1)
  stale_scalar(religion.positions.own[0],'code','DF3D_STALE_TEMPLATE')
  stale_scalar(religion.positions.own[0],'precedence',religion.positions.own[0].precedence+1)
  stale_scalar(religion.positions.own[0].color,0,(religion.positions.own[0].color[0]+1)%16)
  stale_scalar(religion.positions.assignments[0],'histfig',-987654)
  if #religion.relations.deities>0 then stale_scalar(religion.relations.deities,0,-987654)end
  if #religion.site_links>0 then
   local flags=religion.site_links[0].flags;stale_scalar(flags,'whole',flags.whole+4)
  end
  for _,id in ipairs(fixture_agreements)do
   local agreement=assert(df.agreement.find(id));stale_scalar(agreement.flags,'whole',agreement.flags.whole+4)
  end
  before.recognition.receipt_revision=receipt.revision
  before.recognition.stale_checks=stale_checks
  local rejected=recognition_state()
  for _,field in ipairs{'positions','assignments','event_count','next_position','next_assignment','site_links','holder_links','temple_emotions','rng','recognized','bridge','petitions','continuing','agreements'}do
   assert(require('json').encode(rejected[field])==require('json').encode(rejection_baseline[field]),'rejected recognition changed '..field)
  end
  local outcome=recognize();assert(outcome==1,'semantic recognition did not complete: '..outcome)
  for _,guard in ipairs(guards)do
   assert(dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)==0,'recognition changed native UI/gps')
   df.delete(guard.bytes)
  end
 else pixel(500,214)end
 local after=capture('TEMPLE-0-recognition-after',temple);after.recognition=recognition_state()
 assert(before.recognition.bridge.rank==(first_recognition and 0 or 1),'initial semantic priesthood rank mismatch')
 assert(after.recognition.bridge.rank==(first_recognition and 1 or 2),'recognized semantic priesthood rank mismatch')
 assert(before.recognition.bridge.state==(first_recognition and 4 or 5),'native recognition action state mismatch')
 assert(after.recognition.bridge.state==(first_recognition and 2 or 0),'native post-recognition state mismatch')
 local prior_emotions={}
 for _,emotion in ipairs(before.recognition.temple_emotions)do prior_emotions[require('json').encode(emotion)]=true end
 after.recognition.new_temple_emotions={}
 for _,emotion in ipairs(after.recognition.temple_emotions)do
  if not prior_emotions[require('json').encode(emotion)]then
   assert(emotion.subthought==religion.id,'recognition thought targets another religion')
   after.recognition.new_temple_emotions[#after.recognition.new_temple_emotions+1]=emotion
  end
 end
 assert(#after.recognition.new_temple_emotions==54,'unexpected native recognition thought recipients')
 local creates_position=recognition_case~='first' and recognition_case~='firstguidance'
 assert(after.recognition.next_position-before.recognition.next_position==(creates_position and 1 or 0),'unexpected native position allocation')
 assert(after.recognition.next_assignment-before.recognition.next_assignment==1,'unexpected native assignment allocation')
 if recognition_case=='petitions' then
  for index,item in ipairs(after.recognition.agreements)do
   local expected=index<=3 and 1 or 0
   if index==2 or index==5 then expected=expected+2 end
   assert(item.flags==expected,'native concluded unexpected agreement')
  end
  assert(#before.recognition.petitions-#after.recognition.petitions==1,'native petition removal count mismatch')
  assert(#before.recognition.continuing-#after.recognition.continuing==1,'native continuing removal count mismatch')
 end
 after.recognition.new_events={}
 for i=before.recognition.event_count,#df.global.world.history.events-1 do
  local event=df.global.world.history.events[i]
  local item={id=event.id,type=df.history_event_type[event:getType()],year=event.year,seconds=event.seconds}
  if df.history_event_add_hf_entity_linkst:is_instance(event) then
   for _,field in ipairs{'civ','histfig','link_type','position_id','appointer_hfid','promise_to_hfid'}do item[field]=event[field]end
  end
  after.recognition.new_events[#after.recognition.new_events+1]=item
 end
 assert(require('json').encode(before.recognition.assignments)~=require('json').encode(after.recognition.assignments),'recognition did not change assignments')
 if expected_action then
  for _,field in ipairs{'positions','assignments','event_count','next_position','next_assignment','site_links','holder_links','temple_emotions','rng','new_events','recognized','bridge','petitions','continuing','agreements'}do
   if expected_action[field]~=nil then
    assert(require('json').encode(after.recognition[field])==require('json').encode(expected_action[field]),'complete recognition differs from native '..field)
   end
  end
 end
 if semantic_recognition then assert(recognize()==0,'completed recognition replay was not rejected')else pixel(500,214)end
 local repeated=capture('TEMPLE-0-recognition-repeat',temple);repeated.recognition=recognition_state()
 for _,field in ipairs{'positions','assignments','event_count','next_position','next_assignment','site_links','holder_links','temple_emotions','petitions','continuing','agreements','rng'}do
  assert(require('json').encode(after.recognition[field])==require('json').encode(repeated.recognition[field]),'repeat recognition changed '..field)
 end
end,debug.traceback)
contents.location_tier=original;difficulty.high_priesthood_unit_count=original_threshold;difficulty.priesthood_unit_count=original_priest_threshold
assert(ok,err)
assert(#records==((recognition_case=='thoughts' or recognition_case=='agreements' or recognition_case=='positionhigh' or recognition_case=='positionnew') and 2 or recognition_case=='eligibility' and 9 or recognition_case=='firstguidance' and 4 or recognition_only and 3 or 161),'incomplete recognition mutation reference')
