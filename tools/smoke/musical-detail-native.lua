-- Compare the owned formatter with an already-open native musical Knowledge detail.
local unit,detail=...
local json=require('json')
local form=assert(df.musical_form.find(detail.id))
local guards={}
local function guard(address,size)
 if size==0 then return end
 assert(size>0 and size<1048576)
 local bytes=df.new('uint8_t',size);dfhack.internal.memmove(bytes,address,size)
 guards[#guards+1]={bytes=bytes,address=address,size=size}
end
local function object(value)if value then local size,address=df.sizeof(value);guard(address,size)end end
local function vector(value)
 local _,address=df.sizeof(value);local first=df.reinterpret_cast('uint64_t',address).value
 guard(first,df.reinterpret_cast('uint64_t',address+8).value-first)
end
local function string_backing(address)
  local size=df.reinterpret_cast('uint64_t',address+16).value
  local capacity=df.reinterpret_cast('uint64_t',address+24).value
  if capacity>=16 then guard(df.reinterpret_cast('uint64_t',address).value,size+1)end
end
local function name(value)
 object(value)
 for _,field in ipairs{'first_name','nickname'}do
  local _,address=df.sizeof(value:_field(field));string_backing(address)
 end
end
local figures={}
local function figure(id)
 if id<0 or figures[id]then return end;figures[id]=true
 local value=df.historical_figure.find(id)
 if value then object(value);name(value.name);object(value.info)end
end
local function strings(value,field,count)
 local _,address=df.sizeof(value:_field(field));for i=0,(count or 1)-1 do string_backing(address+i*32)end
end
local function melody(value)
 object(value);vector(value.intervals);for _,interval in ipairs(value.intervals)do object(interval)end
end
local scales,rhythms={},{}
local function references(value)
 if value.poetic_form_id>=0 then local poem=df.poetic_form.find(value.poetic_form_id);object(poem);if poem then name(poem.name)end end
 if value.written_content_id>=0 then local content=df.written_content.find(value.written_content_id);object(content);if content then strings(content,'title')end end
 if value.scale_id>=0 then scales[value.scale_id]=true end
 if value.rhythm_id>=0 then rhythms[value.rhythm_id]=true end
end
local ok,result=xpcall(function()
 object(form);name(form.name);figure(form.original_author);figure(form.devotion_target)
 local entity=df.historical_entity.find(form.originating_entity);if entity then object(entity);name(entity.name)end
 for _,field in ipairs{'passages','instruments','melodies','play_order'}do vector(form[field])end
 references(form)
 for _,value in ipairs(form.passages)do
  object(value);references(value)
  for _,field in ipairs{'instruments','components','passage_lengths','lowest_register_range','highest_register_range','melodies'}do vector(value[field])end
  for _,item in ipairs(value.melodies)do melody(item)end
 end
 for _,value in ipairs(form.melodies)do melody(value)end
 for _,value in ipairs(form.play_order)do object(value)end
 for _,value in ipairs(form.instruments)do
  object(value)
  if value.instrument_subtype>=0 then
   local raw=assert(df.global.world.raws.itemdefs.instruments[value.instrument_subtype]);object(raw)
   strings(raw,'name');strings(raw,'name_plural')
   vector(raw.timbre.registers);vector(raw.timbre.timbre)
   for _,register in ipairs(raw.timbre.registers)do object(register);vector(register.timbres)end
  end
 end
 for id in pairs(scales)do
  local value=assert(df.scale.find(id));object(value);vector(value.chords);vector(value.scales)
  for _,chord in ipairs(value.chords)do object(chord);strings(chord,'name')end
  for _,scale in ipairs(value.scales)do object(scale);strings(scale,'name')end
  strings(value.notes,'name',25);strings(value.notes,'abreviation',25)
 end
 for id in pairs(rhythms)do
  local value=assert(df.rhythm.find(id));object(value);vector(value.patterns);vector(value.sub_rhythms)
  for _,pattern in ipairs(value.patterns)do
   object(pattern);strings(pattern,'name');vector(pattern.bars)
   for _,bar in ipairs(pattern.bars)do object(bar);if bar.length>0 then local _,address=df.sizeof(bar.beat);guard(address,bar.length*4)end end
   if pattern.length>0 then
    for _,field in ipairs{'beat_name','beat_abbreviation'}do
     local _,address=df.sizeof(pattern[field]);guard(address,pattern.length*32)
     for i=0,pattern.length-1 do string_backing(address+i*32)end
    end
   end
  end
  for _,sub in ipairs(value.sub_rhythms)do object(sub);strings(sub,'name');vector(sub.patterns);vector(sub.pattern_flags)end
 end
 object(unit);object(df.global.game.main_interface.view_sheets);object(df.global.plotinfo)
 local base=dfhack.internal.getImageBase()
 for _,range in ipairs{{0x234e990,0x6180},{0x2131b30,40},{0x2159084,2},{0x18adf98,8}}do guard(base+range[1],range[2])end
 local text,status=dfhack.run_command_silent('df3d','musical-detail-probe',tostring(form.id))
 assert(status==0,text);local probe=json.decode(text)
 assert(#detail.tagged_rows==1 and probe.text==detail.tagged_rows[1],'Musical description differs from native')
 return probe
end,debug.traceback)
local unchanged=true
for _,entry in ipairs(guards)do
 if dfhack.internal.memcmp(entry.bytes,entry.address,entry.size)~=0 then unchanged=false end
 df.delete(entry.bytes)
end
assert(ok,result);assert(unchanged,'Music probe changed guarded source/UI/random state')
result.guards_unchanged=true
result.form={passages=#form.passages,instruments=#form.instruments,melodies=#form.melodies,play_order=#form.play_order}
return result
