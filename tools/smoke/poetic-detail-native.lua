-- Compare the owned formatter with an already-open native Knowledge detail.
local unit,detail=...
local json=require('json')
local form=assert(df.poetic_form.find(detail.id))
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
local function subject(kind,id)if kind==df.poetic_form_subject.Histfig then figure(id)end end
local ok,result=xpcall(function()
 object(form);name(form.name)
 for _,field in ipairs{'parts','perspectives','common_features'}do vector(form[field])end
 figure(form.original_author);figure(form.subject_hf)
 subject(form.subject,form.subject_target.Histfig.subject_histfig)
 local entity=df.historical_entity.find(form.originating_entity)
 if entity then object(entity);name(entity.name)end
 for _,part in ipairs(form.parts)do
  object(part)
  for _,field in ipairs{'line_endings','line_feet','line_patterns','line_caesura_positions','line_features',
   'additional_features','additional_targets','additional_lines','line_mood','line_subject','line_subject_target',
   'line_action','line_persona_ind','certain_lines_additional_features'}do vector(part[field])end
  subject(part.subject,part.subject_id)
  for index,kind in ipairs(part.line_subject)do subject(kind,part.line_subject_target[index].Histfig.subject_histfig)end
 end
 for _,perspective in ipairs(form.perspectives)do
  object(perspective)
  if perspective.type==df.poetic_form_persona_type.Histfig then figure(perspective.subtype)end
  if perspective.type==df.poetic_form_persona_type.Animal and perspective.subtype>=0 then
   local raw=assert(df.global.world.raws.creatures.all[perspective.subtype]);object(raw)
   local _,address=df.sizeof(raw:_field('name'));for i=0,2 do string_backing(address+i*32)end
   if perspective.subtype2>=0 then
    local caste=assert(raw.caste[perspective.subtype2]);object(caste)
    local _,address=df.sizeof(caste:_field('caste_name'));for i=0,2 do string_backing(address+i*32)end
   end
  end
 end
 object(unit);object(df.global.game.main_interface.view_sheets);object(df.global.plotinfo)
 local base=dfhack.internal.getImageBase()
 for _,range in ipairs{{0x234e990,0x6180},{0x2131b30,40},{0x2159084,2},{0x18adf98,8}}do guard(base+range[1],range[2])end
 local text,status=dfhack.run_command_silent('df3d','poetic-detail-probe',tostring(form.id))
 assert(status==0,text)
 local probe=json.decode(text)
 assert(#detail.tagged_rows==1 and probe.text==detail.tagged_rows[1],'Poetic description differs from native')
 return probe
end,debug.traceback)
local unchanged=true
for _,entry in ipairs(guards)do
 if dfhack.internal.memcmp(entry.bytes,entry.address,entry.size)~=0 then unchanged=false end
 df.delete(entry.bytes)
end
assert(ok,result);assert(unchanged,'Poetic probe changed guarded source/UI/random state')
result.guards_unchanged=true
result.form={parts=#form.parts,perspectives=#form.perspectives,subject=form.subject,
 mood=form.mood,action=form.action,original_author=form.original_author,subject_hf=form.subject_hf}
return result
