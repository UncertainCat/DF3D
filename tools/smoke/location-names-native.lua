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
local function pixel(x,y)
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=y//12;key('_MOUSE_L')
end
local function name_value(name)
 local value={first_name=name.first_name,nickname=name.nickname,language=name.language,type=name.type,has_name=name.has_name,words={},parts_of_speech={}}
 for i=0,6 do value.words[#value.words+1]=name.words[i];value.parts_of_speech[#value.parts_of_speech+1]=name.parts_of_speech[i]end
 return value
end
local function capture(label,location)
 g.mouse_x=0;g.mouse_y=0;g.precise_mouse_x=0;g.precise_mouse_y=0
 view:render(dfhack.getTickCount());script.sleep(3,'frames')
 local row={name=label,id=location.id,kind=df.abstract_building_type[location:getType()],details_open=details.open,
  creator_open=creator.open,context=creator.context,name_type=creator.name_type,name_value=name_value(location:getName()),
  name_place=creator.cur_name_place,word_place=creator.cur_word_place,filter=creator.cull_str,
  entering_filter=creator.entering_cull_str,entering_first_name=creator.entering_first_name,
  word_count=#creator.word_index,word_index={},word_parts={},lines={}}
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
  local text,code=dfhack.run_command_silent('df3d','location-name-words',tostring(creator.cur_name_place),dfhack.df2utf(creator.cull_str))
  assert(code==0,text);local observed=require('json').decode(text)
  assert(observed.valid and #observed.words==#creator.word_index,'native word-selector count mismatch')
  for i,pair in ipairs(observed.words)do
   if pair[1]~=creator.word_index[i-1] or pair[2]~=word_part(i-1)then
    local f=assert(io.open(out..'/word-mismatch.json','w'))
    f:write(require('json').encode({name=label,index=i,bridge=observed.words,native_words=row.word_index,native_parts=row.word_parts}));f:close()
    error('native word-selector mismatch at '..i..': '..tostring(pair[1])..'/'..tostring(pair[2])..' versus '..tostring(creator.word_index[i-1])..'/'..tostring(word_part(i-1)))
   end
   assert(pair[3]==dfhack.df2utf(df.global.world.raws.language.words[pair[1]].forms[pair[2]]),'native English word form mismatch')
  end
  for _,guard in ipairs(guards)do
   assert(dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)==0,'word observation changed native UI/gps')
   df.delete(guard.bytes)
  end
  row.bridge_word_count=#observed.words;row.bridge_ui_unchanged=true;row.bridge_forms_verified=true
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
 pixel(608,142+36*target)
 local native_after=rng_snapshot()
 assert(require('json').encode(after)==require('json').encode(native_after),'component Random RNG mismatch')
 assert(location:getName().words[target]==picked.word and location:getName().parts_of_speech[target]==picked.part,'component Random choice mismatch')
 local row=capture(label,location)
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
 local text,code=dfhack.run_command_silent('df3d','location-name-generate',tostring(df.global.plotinfo.site_id),tostring(location.id))
 assert(code==0,text);local generated=require('json').decode(text)
 assert(generated.valid,'native whole-name generation rejected')
 local after=rng_snapshot()
 for _,guard in ipairs(guards)do
  assert(dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)==0,'whole-name generation changed UI/name/entity')
  df.delete(guard.bytes)
 end
 restore_rng(before);pixel(832,82)
 local native_after=rng_snapshot()
 assert(require('json').encode(after)==require('json').encode(native_after),'whole-name RNG mismatch')
 local native=name_value(location:getName())
 native.first_name=dfhack.df2utf(native.first_name);native.nickname=dfhack.df2utf(native.nickname)
 assert(require('json').encode(generated.name)==require('json').encode(native),'whole-name value mismatch')
 local row=capture(label,location)
 row.bridge_generation={rng_identical=true,name_identical=true,ui_name_entity_unchanged=true,namer_id=creator.namer.id}
end
m.bottom_mode_selected=-1;key('D_CIVZONE');m.civzone.cur_bld=assert(df.building.find(23));view:render(dfhack.getTickCount())
pixel(336,190);local selector=m.location_selector;assert(selector.open,'chooser did not open')
local choices={};for _,v in ipairs(selector.valid_ab)do choices[#choices+1]=v end
assert(#choices==6,'unexpected location reference fixture')
for i,location in ipairs(choices)do
 pixel(664,238+36*(i-1));assert(details.open and details.selected_ab==location)
 local prefix=df.abstract_building_type[location:getType()]..'-'..location.id
 local before=capture(prefix..'-before',location)
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
assert(#records==18,'incomplete location name entry coverage')

for i,location in ipairs(choices)do
 pixel(664,238+36*(i-1));assert(details.open and details.selected_ab==location)
 pixel(944,82);assert(creator.open)
 local prefix=df.abstract_building_type[location:getType()]..'-'..location.id
 if location:getType()==df.abstract_building_type.INN_TAVERN then
  for part=0,6 do
   pixel(476,142+36*part);capture(prefix..'-part-'..part..'-selected',location)
   pixel(668,142+36*part);capture(prefix..'-part-'..part..'-clear',location)
   pixel(756,178);capture(prefix..'-part-'..part..'-first-word',location)
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
  pixel(832,142);for n=1,4 do key('STRING_A000')end;key('SELECT')
  key('_MOUSE_R');capture(prefix..'-edited-back',location)
  if creator.open then key('_MOUSE_R')end
  assert(not creator.open and details.open,'edited name Back did not return')
  pixel(944,82);capture(prefix..'-edited-reopen',location)
 end
 random_whole(prefix..'-whole-random',location)
 pixel(912,82);capture(prefix..'-done',location)
 assert(not creator.open and details.open,'Done did not return to Details')
 pixel(944,82);capture(prefix..'-random-reopen',location)
 key('_MOUSE_R');assert(not creator.open and details.open)
 key('LEAVESCREEN');assert(selector.open and not details.open)
end
assert(#records==88,'incomplete name mutation/filter reference')
