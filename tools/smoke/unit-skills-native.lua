-- Read native Skills presentation in the owned paused unsaved diagnostic.
local unit,view,capture,out=...
local gui=require('gui');local json=require('json')
local g=df.global.gps;local sheet=df.global.game.main_interface.view_sheets
local frame=df.global.world.frame_counter
local function row(y)
 local text={};for x=0,g.dimx-1 do local p=dfhack.screen.readTile(x,y);text[#text+1]=p.ch>=32 and string.char(p.ch%256)or' 'end
 return table.concat(text)
end
-- Preserve the actual native character cells, including color and placement.
-- Text alone cannot distinguish profession colors or rust suffix styling.
local function cells(y)
 local result={}
 for x=0,g.dimx-1 do
  local p=dfhack.screen.readTile(x,y)
  if p.ch>=33 then result[#result+1]={x=x,ch=p.ch,fg=p.fg,bg=p.bg,bold=p.bold}end
 end
 return result
end
local function click(x,y)
 df.global.enabler.mouse_focus=true;df.global.enabler.tracking_on=1
 g.precise_mouse_x=x;g.precise_mouse_y=y;g.mouse_x=x//8;g.mouse_y=(y-4)//12
 df.global.enabler.mouse_lbut_lift=0;gui.simulateInput(view,'_MOUSE_L');view:render(dfhack.getTickCount())
 df.global.enabler.mouse_lbut=0;df.global.enabler.mouse_lbut_down=0;df.global.enabler.mouse_lbut_lift=1
end
local function select(name,first,last)
 for y=first,last do local x=row(y):find(name,1,true);if x then click((x-1)*8+4,y*12+10);return end end
 error('Missing native Skills tab '..name)
end
local function observe(name)
  select(name=='Labor'and'Combat'or'Labor',17,20);select(name,17,20)
  local page={name=name,tab=sheet.unit_skill_active_tab,first=sheet.scroll_position_unit_skill,skills={},values={},rust_values={},lines={}}
  for _,v in ipairs(sheet.unit_skill)do page.skills[#page.skills+1]=v end
  for _,v in ipairs(sheet.unit_skill_val)do page.values[#page.values+1]=v end
  for _,v in ipairs(sheet.unit_skill_val_w_rust)do page.rust_values[#page.rust_values+1]=v end
  page.knowledge_types={};page.knowledge_ids={};page.knowledge_bits={}
  for _,v in ipairs(sheet.unit_knowledge_type)do page.knowledge_types[#page.knowledge_types+1]=v end
  for _,v in ipairs(sheet.unit_knowledge_id)do page.knowledge_ids[#page.knowledge_ids+1]=v end
  for _,v in ipairs(sheet.unit_knowledge_bits)do page.knowledge_bits[#page.knowledge_bits+1]=v end
  if os.getenv('DF3D_UNIT_SKILLS_PROBE')=='1'then
   local guards={}
   local function guard(address,size)
    if size==0 then return end;assert(size>0 and size<1048576)
    local bytes=df.new('uint8_t',size);dfhack.internal.memmove(bytes,address,size)
    guards[#guards+1]={bytes=bytes,address=address,size=size}
   end
   local function object(value)if value then local size,address=df.sizeof(value);guard(address,size)end end
   local function vector(value)
    local _,address=df.sizeof(value);local first=df.reinterpret_cast('uint64_t',address).value
    guard(first,df.reinterpret_cast('uint64_t',address+8).value-first)
   end
   local original_cache=unit.enemy.histfig_vector_idx;unit.enemy.histfig_vector_idx=-1
   object(unit);object(sheet);object(df.global.plotinfo)
   local soul=unit.status.current_soul;object(soul)
   if soul then vector(soul.skills);for _,skill in ipairs(soul.skills)do object(skill)end end
   local hf=df.historical_figure.find(unit.hist_figure_id);object(hf)
   if hf then object(hf.info);if hf.info then
    local known=hf.info.known_info;object(known)
    if known then object(known.knowledge);for _,field in ipairs{'known_poetic_forms','known_musical_forms','known_dance_forms','known_written_contents'}do vector(known[field])end end
   end end
   for _,field in ipairs{'unit_skill','unit_skill_val','unit_skill_val_w_rust','unit_knowledge_type','unit_knowledge_id','unit_knowledge_bits'}do vector(sheet[field])end
   local base=dfhack.internal.getImageBase()
   for _,range in ipairs{{0x234e990,0x6180},{0x2131b30,40},{0x2159084,2},{0x18adf98,8}}do guard(base+range[1],range[2])end
   local text,status=dfhack.run_command_silent('df3d','unit-skills-page-probe',tostring(unit.id),tostring(page.tab))
   local unchanged=true
   for _,g in ipairs(guards)do if dfhack.internal.memcmp(g.bytes,g.address,g.size)~=0 then unchanged=false end;df.delete(g.bytes)end
   unit.enemy.histfig_vector_idx=original_cache
   assert(status==0,text);assert(unchanged,'Skills probe changed source/UI/random state')
   page.probe=json.decode(text);page.probe_guards_unchanged=true;page.cold_source_cache_preserved=true
   for _,field in ipairs{'skills','values','rust_values','knowledge_types','knowledge_ids','knowledge_bits'}do assert(json.encode(page[field])==json.encode(page.probe[field]),'Skills probe differs: '..name..' '..field)end
  end
  if page.probe and os.getenv('DF3D_UNIT_SKILLS_CAPTIONS')=='1'then
   local captions=page.probe.captions;local count=#captions;page.caption_rows={};page.subtitle_rows={};page.caption_cells={};page.subtitle_cells={}
   for start=0,count-1,14 do
    local first=math.max(0,math.min(start,count-14));sheet.scroll_position_unit_skill=first;view:render(dfhack.getTickCount())
    for index=first,math.min(first+13,count-1)do
     local text=dfhack.df2utf(row(20+3*(index-first))):gsub('^%s+',''):gsub('%s+$','')
     local caption=captions[index+1]
     assert(caption~='' and text:find(caption,1,true),'Native Skills caption differs: '..name..' row '..index..' expected '..caption..' visible '..text)
     page.caption_rows[index+1]=text
     page.caption_cells[index+1]=cells(20+3*(index-first))
     if name~='Knowledge'then
      local expected=assert(page.probe.colors[index+1],'Missing native Skills color')
      local observed=dfhack.screen.readTile(54,20+3*(index-first))
      assert(observed.fg==expected[1] and observed.bg==expected[2] and (observed.bold and 1 or 0)==expected[3],
       'Native Skills color differs: '..name..' row '..index)
     end
     if name=='Knowledge'then
      local subtitle=dfhack.df2utf(row(21+3*(index-first))):gsub('^%s+',''):gsub('%s+$','')
      assert(subtitle==page.probe.subtitles[index+1],'Native Knowledge subtitle differs: '..index..' expected '..page.probe.subtitles[index+1]..' visible '..subtitle)
      page.subtitle_rows[index+1]=subtitle
      page.subtitle_cells[index+1]=cells(21+3*(index-first))
     end
    end
   end
   sheet.scroll_position_unit_skill=page.first;view:render(dfhack.getTickCount())
  end
  for y=17,g.dimy-1 do local text=dfhack.df2utf(row(y)):gsub('%s+$','');if text~=''then page.lines[#page.lines+1]={y=y,text=text}end end
 return page
end
local pages={};local cases={};local details={};local detail_page
local ok,err=xpcall(function()
 assert(sheet.open and sheet.active_id==unit.id,'Expected creature sheet')
 select('Skills',15,16)
 for _,name in ipairs{'Labor','Combat','Social','Other skills','Knowledge'}do
  pages[#pages+1]=observe(name);capture('unit-skills-'..name:lower():gsub(' ','-'))
 end
 if os.getenv('DF3D_UNIT_SKILLS_DETAILS')=='1'then
  local added={};local written_samples={}
  if os.getenv('DF3D_UNIT_SKILLS_ALL_FORMS')=='1'then
   local known=assert(df.historical_figure.find(unit.hist_figure_id).info.known_info)
   for _,entry in ipairs{{known.known_musical_forms,df.global.world.musical_forms.all},{known.known_dance_forms,df.global.world.dance_forms.all}}do
    assert(#entry[2]>0,'Missing world art forms')
    local id=entry[2][0].id;local exists=false
    for _,value in ipairs(entry[1])do if value==id then exists=true end end
    if not exists then entry[1]:insert('#',id);added[#added+1]={vector=entry[1],id=id}end
   end
  end
  local details_ok,details_error=xpcall(function()
  if os.getenv('DF3D_UNIT_POETIC_FORMS')=='1'then
   local known=assert(df.historical_figure.find(unit.hist_figure_id).info.known_info).known_poetic_forms
   for index,form in ipairs(df.global.world.poetic_forms.all)do
    if index>=12 then break end
    local exists=false;for _,id in ipairs(known)do if id==form.id then exists=true end end
    if not exists then known:insert('#',form.id);added[#added+1]={vector=known,id=form.id}end
   end
  end
  if os.getenv('DF3D_UNIT_MUSICAL_FORMS')=='1'then
   local known=assert(df.historical_figure.find(unit.hist_figure_id).info.known_info).known_musical_forms
   for index,form in ipairs(df.global.world.musical_forms.all)do
    if index>=12 then break end
    local exists=false;for _,id in ipairs(known)do if id==form.id then exists=true end end
    if not exists then known:insert('#',form.id);added[#added+1]={vector=known,id=form.id}end
   end
  end
  if os.getenv('DF3D_UNIT_DANCE_FORMS')=='1'then
   local known=assert(df.historical_figure.find(unit.hist_figure_id).info.known_info).known_dance_forms
   for index,form in ipairs(df.global.world.dance_forms.all)do
    if index>=12 then break end
    local exists=false;for _,id in ipairs(known)do if id==form.id then exists=true end end
    if not exists then known:insert('#',form.id);added[#added+1]={vector=known,id=form.id}end
   end
  end
  if os.getenv('DF3D_UNIT_WRITTEN_CONTENTS')=='1'then
   local known=assert(df.historical_figure.find(unit.hist_figure_id).info.known_info).known_written_contents
   local types={};local count=0
   for _,content in ipairs(df.global.world.written_contents.all)do
    if not types[content.type]then
     types[content.type]=true;written_samples[content.id]=true;count=count+1
     local exists=false;for _,id in ipairs(known)do if id==content.id then exists=true end end
     if not exists then known:insert('#',content.id);added[#added+1]={vector=known,id=content.id}end
     if count==12 then break end
    end
   end
  end
  local reference=observe('Knowledge');detail_page=reference;local seen={}
  local function capture_detail(index,kind,variant)
    local captured_page=observe('Knowledge')
    sheet.scroll_position_unit_skill=index-1;view:render(dfhack.getTickCount())
    local first=sheet.scroll_position_unit_skill
    local count=#sheet.unit_knowledge_type;first=math.max(0,math.min(first,count-14))
    click(852,250+36*(index-1-first))
    assert(#sheet.skill_description_raw_str>0,'Knowledge detail did not open')
    local detail={kind=kind,id=reference.knowledge_ids[index],case=variant,tagged_rows={},lines={}}
    if captured_page.caption_rows then
     detail.native_caption=captured_page.caption_rows[index]
     detail.native_subtitle=captured_page.subtitle_rows[index]
    end
    if kind==16 then
     local form=assert(df.dance_form.find(detail.id))
     detail.form={sections=#form.sections,moves=#form.moves,event=form.event,hfid=form.hfid,race=form.race,section_events={}}
     for _,section in ipairs(form.sections)do detail.form.section_events[#detail.form.section_events+1]=section.acts_out_event end
     if form.event>=0 then
      local event=assert(df.history_event.find(form.event));detail.form.event_type=event:getType()
      detail.form.event_type_name=df.history_event_type[detail.form.event_type]
      local _,address=df.sizeof(event);local vtable=df.reinterpret_cast('uint64_t',address).value
      detail.form.event_phrase_rva=df.reinterpret_cast('uint64_t',vtable+0xd8).value-dfhack.internal.getImageBase()
     end
    end
    if kind==17 then
     local content=assert(df.written_content.find(detail.id))
     detail.content={type=content.type,type_name=df.written_content_type[content.type],title=dfhack.df2utf(content.title),author=content.author,author_roll=content.author_roll,poetic_form=content.poetic_form,refs={},styles={}}
     assert(#content.refs==#content.ref_aux and #content.styles==#content.style_strength,'Written content paired vectors differ')
     for i,ref in ipairs(content.refs)do
      local _,address=df.sizeof(ref);local vtable=df.reinterpret_cast('uint64_t',address).value
      local record={type=ref:getType(),type_name=df.general_ref_type[ref:getType()],id=ref:getID(),role=content.ref_aux[i],description_rva=df.reinterpret_cast('uint64_t',vtable+0x90).value-dfhack.internal.getImageBase()}
      if record.type_name=='HISTORICAL_EVENT'then
       record.event_id=ref.event_id
       local event=df.history_event.find(ref.event_id)
       if event then
        record.event_type=event:getType();record.event_type_name=df.history_event_type[record.event_type]
        local _,event_address=df.sizeof(event);local event_vtable=df.reinterpret_cast('uint64_t',event_address).value
        record.event_phrase_rva=df.reinterpret_cast('uint64_t',event_vtable+0xd8).value-dfhack.internal.getImageBase()
       end
      elseif record.type_name=='SITE'then record.site_id=ref.site_id
      elseif record.type_name=='KNOWLEDGE_SCHOLAR_FLAG'then
       record.knowledge_category=ref.knowledge.flag_type;record.knowledge_bits=ref.knowledge.flag_data.whole
      end
      detail.content.refs[#detail.content.refs+1]=record
     end
     for i,style in ipairs(content.styles)do detail.content.styles[#detail.content.styles+1]={style=style,strength=content.style_strength[i]}end
    end
    for _,value in ipairs(sheet.skill_description_raw_str)do
     if type(value)=='string'then detail.tagged_rows[#detail.tagged_rows+1]=dfhack.df2utf(value)
     else
      local _,address=df.sizeof(value);local size=df.reinterpret_cast('uint64_t',address+16).value
      local capacity=df.reinterpret_cast('uint64_t',address+24).value
      assert(size>=0 and size<=65536 and capacity>=size)
      local data=capacity<16 and address or df.reinterpret_cast('uint64_t',address).value
      local chars={};for i=0,size-1 do chars[#chars+1]=string.char(df.reinterpret_cast('uint8_t',data+i).value)end
      detail.tagged_rows[#detail.tagged_rows+1]=dfhack.df2utf(table.concat(chars))
     end
    end
    for y=17,g.dimy-1 do local text=dfhack.df2utf(row(y)):gsub('%s+$','');if text~=''then detail.lines[#detail.lines+1]={y=y,text=text}end end
    if kind==14 and os.getenv('DF3D_UNIT_POETIC_PROBE')=='1'then
     local source=debug.getinfo(1,'S').source:sub(2):gsub('unit%-skills%-native.lua$','poetic-detail-native.lua')
     detail.probe=assert(loadfile(source))(unit,detail)
    end
    if kind==15 and os.getenv('DF3D_UNIT_MUSICAL_PROBE')=='1'then
     local source=debug.getinfo(1,'S').source:sub(2):gsub('unit%-skills%-native.lua$','musical-detail-native.lua')
     detail.probe=assert(loadfile(source))(unit,detail)
    end
    if kind==16 and os.getenv('DF3D_UNIT_DANCE_PROBE')=='1'then
     local source=debug.getinfo(1,'S').source:sub(2):gsub('unit%-skills%-native.lua$','dance-detail-native.lua')
     detail.probe=assert(loadfile(source))(unit,detail)
    end
    if kind==17 and os.getenv('DF3D_UNIT_WRITTEN_PROBE')=='1'then
     local source=debug.getinfo(1,'S').source:sub(2):gsub('unit%-skills%-native.lua$','written-detail-native.lua')
     detail.probe=assert(loadfile(source))(unit,detail)
    end
    if os.getenv('DF3D_UNIT_KNOWLEDGE_SELECTION')=='1'then
     local source=debug.getinfo(1,'S').source:sub(2):gsub('unit%-skills%-native.lua$','knowledge-selection-native.lua')
     detail.selection_probe=assert(loadfile(source))(unit,detail)
    end
    details[#details+1]=detail;capture('unit-skills-detail-'..kind..'-'..detail.id..(variant and('-'..variant)or''))
    if kind==15 and os.getenv('DF3D_UNIT_KNOWLEDGE_INPUT')=='1'then
     local source=debug.getinfo(1,'S').source:sub(2):gsub('unit%-skills%-native.lua$','knowledge-input-native.lua')
     assert(loadfile(source))(unit,view,capture,out,function()
      select('Skills',15,16);observe('Knowledge')
      sheet.scroll_position_unit_skill=index-1;view:render(dfhack.getTickCount())
      local first=math.max(0,math.min(sheet.scroll_position_unit_skill,#sheet.unit_knowledge_type-14))
      click(852,250+36*(index-1-first));assert(#sheet.skill_description_raw_str>0)
     end)
    end
    return detail.tagged_rows[1]
  end
  local written_event_checked=false
  for index,kind in ipairs(reference.knowledge_types)do
   if kind>=14 and (not seen[kind]or(kind==14 and os.getenv('DF3D_UNIT_POETIC_FORMS')=='1')or(kind==15 and os.getenv('DF3D_UNIT_MUSICAL_FORMS')=='1')or(kind==16 and os.getenv('DF3D_UNIT_DANCE_FORMS')=='1')or(kind==17 and written_samples[reference.knowledge_ids[index]]))then
    seen[kind]=true;local baseline=capture_detail(index,kind)
    if kind==17 and not written_event_checked and os.getenv('DF3D_UNIT_WRITTEN_EVENTS')=='1'then
     written_event_checked=true
     local source=debug.getinfo(1,'S').source:sub(2):gsub('unit%-skills%-native.lua$','written-event-validation-native.lua')
     assert(loadfile(source))(unit,reference.knowledge_ids[index],function(variant)return capture_detail(index,kind,variant)end,out)
    end
    if kind==17 and os.getenv('DF3D_UNIT_WRITTEN_CASES')=='1'then
     local source=debug.getinfo(1,'S').source:sub(2):gsub('unit%-skills%-native.lua$','written-cases-native.lua')
     assert(loadfile(source))(unit,reference.knowledge_ids[index],function(variant)return capture_detail(index,kind,variant)end,baseline)
    end
    if kind==14 and os.getenv('DF3D_UNIT_POETIC_CASES')=='1'then
     local source=debug.getinfo(1,'S').source:sub(2):gsub('unit%-skills%-native.lua$','poetic-cases-native.lua')
     assert(loadfile(source))(unit,reference.knowledge_ids[index],function(variant)return capture_detail(index,kind,variant)end,baseline)
    end
    if kind==16 and os.getenv('DF3D_UNIT_DANCE_AGREEMENT_IDENTITY')=='1'then
     local source=debug.getinfo(1,'S').source:sub(2):gsub('unit%-skills%-native.lua$','dance-agreement-identity-native.lua')
     assert(loadfile(source))(unit,reference.knowledge_ids[index],function(variant)return capture_detail(index,kind,variant)end,out)
    end
    if kind==16 and os.getenv('DF3D_UNIT_DANCE_IDENTITY')=='1'then
     local source=debug.getinfo(1,'S').source:sub(2):gsub('unit%-skills%-native.lua$','dance-identity-native.lua')
     assert(loadfile(source))(unit,reference.knowledge_ids[index],function(variant)return capture_detail(index,kind,variant)end,out)
    end
    if kind==16 and os.getenv('DF3D_UNIT_DANCE_CAGE')=='1'then
     local source=debug.getinfo(1,'S').source:sub(2):gsub('unit%-skills%-native.lua$','dance-cage-native.lua')
     assert(loadfile(source))(unit,reference.knowledge_ids[index],function(variant)return capture_detail(index,kind,variant)end,out)
    end
    if kind==16 and os.getenv('DF3D_UNIT_DANCE_COIN')=='1'then
     local source=debug.getinfo(1,'S').source:sub(2):gsub('unit%-skills%-native.lua$','dance-coin-native.lua')
     assert(loadfile(source))(unit,reference.knowledge_ids[index],function(variant)return capture_detail(index,kind,variant)end,out)
    end
    if kind==16 and os.getenv('DF3D_UNIT_DANCE_ARTIFACT')=='1'then
     local source=debug.getinfo(1,'S').source:sub(2):gsub('unit%-skills%-native.lua$','dance-artifact-native.lua')
     assert(loadfile(source))(unit,reference.knowledge_ids[index],function(variant)return capture_detail(index,kind,variant)end,out)
    end
    if kind==16 and os.getenv('DF3D_UNIT_DANCE_RECURSION')=='1'then
     local source=debug.getinfo(1,'S').source:sub(2):gsub('unit%-skills%-native.lua$','dance-recursion-native.lua')
     assert(loadfile(source))(reference.knowledge_ids[index],function(variant)return capture_detail(index,kind,variant)end,out)
    end
    if kind==16 and os.getenv('DF3D_UNIT_DANCE_EVENTS')=='1'then
     local form=assert(df.dance_form.find(reference.knowledge_ids[index]));local original=form.event
     local events_ok,events_error=xpcall(function()
      local seen_types={};local count=0
      for _,event in ipairs(df.global.world.history.events)do
       local kind=event:getType()
       if not seen_types[kind]then
        seen_types[kind]=true;form.event=event.id
        assert(capture_detail(index,16,'event-'..kind)~=baseline,'Dance event did not change native text')
        count=count+1;if count==4 then break end
       end
      end
      assert(count==4,'Need four existing historical event types')
     end,debug.traceback)
     form.event=original;assert(events_ok,events_error)
    end
   end
  end
  end,debug.traceback)
  for i=#added,1,-1 do local entry=added[i];assert(entry.vector[#entry.vector-1]==entry.id);entry.vector:erase(#entry.vector-1)end
  observe('Labor');assert(details_ok,details_error)
 end
 if os.getenv('DF3D_UNIT_SKILLS_CASES')=='1'then
  local soul=assert(unit.status.current_soul);local original={}
  local hf_id,cache=unit.hist_figure_id,unit.enemy.histfig_vector_idx
  for _,skill in ipairs(soul.skills)do original[#original+1]={skill=skill,rating=skill.rating,rusty=skill.rusty}end
  local function restore()
   unit.status.current_soul=soul;unit.hist_figure_id=hf_id;unit.enemy.histfig_vector_idx=cache
   soul.skills:resize(0)
   for _,record in ipairs(original)do record.skill.rating=record.rating;record.skill.rusty=record.rusty;soul.skills:insert('#',record.skill)end
  end
  local cases_ok,cases_error=xpcall(function()
   for _,variant in ipairs{'empty-skills','reversed-ties','negative-ratings','excess-rust','no-soul'}do
    restore()
    if variant=='empty-skills'then soul.skills:resize(0)
    elseif variant=='no-soul'then unit.status.current_soul=nil
    else
     for _,record in ipairs(original)do
      record.skill.rating=variant=='negative-ratings'and-2 or 5
      record.skill.rusty=variant=='excess-rust'and 9 or 0
     end
     if variant=='reversed-ties'then soul.skills:resize(0);for i=#original,1,-1 do soul.skills:insert('#',original[i].skill)end end
    end
    for _,name in ipairs{'Labor','Combat','Social','Other skills','Knowledge'}do
     local sample=observe(name);sample.case=variant;sample.lines=nil;cases[#cases+1]=sample
    end
   end
   restore();unit.hist_figure_id=-1;unit.enemy.histfig_vector_idx=-1
   local sample=observe('Knowledge');sample.case='no-historical-figure';sample.lines=nil;cases[#cases+1]=sample
  end,debug.traceback)
  restore();observe('Labor');assert(cases_ok,cases_error)
 end
 if os.getenv('DF3D_UNIT_SKILLS_INPUT')=='1'then
  local source=debug.getinfo(1,'S').source:sub(2):gsub('unit%-skills%-native.lua$','unit-skills-input-native.lua')
  assert(loadfile(source))(unit,view,capture,out)
 end
end,debug.traceback)
select('Overview',15,16)
assert(df.global.pause_state and df.global.world.frame_counter==frame,'Skills reference advanced simulation')
local result={success=ok,unit_id=unit.id,pages=pages,cases=cases,details=details,detail_page=detail_page,error=not ok and err or nil}
local f=assert(io.open(out..'/unit-skills-native.json','w'));f:write(json.encode(result));f:close()
assert(ok,err);return result
