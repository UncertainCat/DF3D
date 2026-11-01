-- Compare the owned formatter with an already-open native Knowledge detail.
local unit,detail=...
local json=require('json')
local content=assert(df.written_content.find(detail.id))
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
local function string_field(value,field)
 local _,address=df.sizeof(value:_field(field));string_backing(address)
end
local function entity(id)
 local value=df.historical_entity.find(id);if not value then return end
 object(value);name(value.name);vector(value.positions.own)
 for _,position in ipairs(value.positions.own)do object(position)end
end
local function site(id)
 local value=df.world_site.find(id);if not value then return end
 object(value);name(value.name);vector(value.buildings)
 for _,building in ipairs(value.buildings)do object(building)end
end
local function event(id)
 if id<0 then return end
 local value=assert(df.history_event.find(id));object(value)
 local _,address=df.sizeof(value:_field('flags'))
 guard(df.reinterpret_cast('uint64_t',address).value,df.reinterpret_cast('int32_t',address+8).value)
 local kind=value:getType()
 if kind==df.history_event_type.CHANGE_HF_STATE then
  figure(value.hfid);site(value.site)
 elseif kind==df.history_event_type.ADD_HF_ENTITY_LINK then
  figure(value.histfig);figure(value.appointer_hfid);figure(value.promise_to_hfid);entity(value.civ)
 elseif kind==df.history_event_type.CREATED_SITE or kind==df.history_event_type.CREATED_BUILDING then
  figure(value.builder_hf);entity(value.civ);entity(value.site_civ);site(value.site)
 elseif kind==df.history_event_type.WAR_PLUNDERED_SITE then
  entity(value.attacker_civ);entity(value.defender_civ);entity(value.site_civ);site(value.site)
 elseif kind==df.history_event_type.CEREMONY then
  entity(value.entity);site(value.site)
  assert(value.region<0 and value.layer<0,'Add region/layer guards for this ceremony')
  local owner=df.historical_entity.find(value.entity)
  if owner and owner.occasion_info then
   object(owner.occasion_info);vector(owner.occasion_info.occasions)
   for _,occasion in ipairs(owner.occasion_info.occasions)do
    object(occasion);name(occasion.name);vector(occasion.schedule)
    for _,schedule in ipairs(occasion.schedule)do object(schedule)end
   end
  end
 else error('Add source guards before probing this event type')end
end
local ok,result=xpcall(function()
 object(content);string_field(content,'title');figure(content.author)
 for _,field in ipairs{'refs','ref_aux','styles','style_strength'}do vector(content[field])end
 for _,ref in ipairs(content.refs)do
  object(ref);local kind=ref:getType()
  if kind==df.general_ref_type.HISTORICAL_EVENT then event(ref.event_id)
  elseif kind==df.general_ref_type.SITE then site(ref.site_id)
  elseif kind==df.general_ref_type.ENTITY then entity(ref:getID())
  elseif kind~=df.general_ref_type.KNOWLEDGE_SCHOLAR_FLAG then error('Add source guards before probing this written reference type')end
 end
 -- Art-form source roots are guarded here; their deep graphs have separate
 -- owned-adapter comparisons. This does not claim all transitive backing coverage.
 local form=content.type==df.written_content_type.Poem and df.poetic_form.find(content.poetic_form)
  or content.type==df.written_content_type.MusicalComposition and df.musical_form.find(content.poetic_form)
  or content.type==df.written_content_type.Choreography and df.dance_form.find(content.poetic_form)
 if form then object(form);name(form.name)end
 object(unit);object(df.global.game.main_interface.view_sheets);object(df.global.plotinfo)
 local base=dfhack.internal.getImageBase()
 for _,range in ipairs{{0x234e990,0x6180},{0x2131b30,40},{0x2159084,2},{0x18adf98,8}}do guard(base+range[1],range[2])end
 local text,status=dfhack.run_command_silent('df3d','written-detail-probe',tostring(content.id))
 assert(status==0,text);local probe=json.decode(text)
 assert(#detail.tagged_rows==1 and probe.text==detail.tagged_rows[1],'Written description differs from native: '..content.id..'\n'..probe.text..'\nNATIVE: '..table.concat(detail.tagged_rows))
 return probe
end,debug.traceback)
local unchanged=true
for _,entry in ipairs(guards)do
 if dfhack.internal.memcmp(entry.bytes,entry.address,entry.size)~=0 then unchanged=false end
 df.delete(entry.bytes)
end
assert(ok,result);assert(unchanged,'Written probe changed guarded source/UI/random state')
result.guards_unchanged=true
return result
