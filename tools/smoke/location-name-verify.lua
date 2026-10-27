-- Protected paused clone diagnostics; never a runtime UI input.
local out,index=...
local json=require('json')
local f=assert(io.open(out..'/request-'..index..'.json'));local request=json.decode(f:read('*a'));f:close()
assert(df.global.pause_state and df.global.world.frame_counter==0,'paused clone required')
local site=assert(dfhack.world.getCurrentSite());local result={status='passed'}
local function bytes(text)local v={};for i=1,#text do v[i]=text:byte(i)end;return v end
local function value(name)
 local v={first_name_bytes=bytes(name.first_name),nickname_bytes=bytes(name.nickname),words={},parts={},language=name.language,type=name.type,has_name=name.has_name}
 for i=0,6 do v.words[i+1]=name.words[i];v.parts[i+1]=name.parts_of_speech[i]end
 return v
end
local function same(a,b)
 if type(a)~=type(b)then return false end
 if type(a)~='table'then return a==b end
 for k,v in pairs(a)do if not same(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end
 return true
end
local function rng()
 local base=dfhack.internal.getImageBase();local context=df.reinterpret_cast('int16_t',base+0x2159084).value
 assert(context>=0 and context<16);local r={context=context,cursor=df.reinterpret_cast('uint32_t',base+0x2131b30+context*4).value,words={}}
 for i=0,623 do r.words[i+1]=df.reinterpret_cast('uint32_t',base+0x234e990+context*0x9c0+i*4).value end
 return r
end
if request.op=='name_locations' then
 result.locations={};for _,v in ipairs(site.buildings)do result.locations[#result.locations+1]={site_id=site.id,id=v.id}end
else
 local location;for _,v in ipairs(site.buildings)do if v.id==request.location_id then location=v;break end end
 local name=assert(location):getName()
 if request.op=='name_details' then
  assert(request.name==dfhack.df2utf(dfhack.translation.translateName(name,true)),'Details name did not refresh after naming')
 elseif request.op=='name_headers' then
  local text,code=dfhack.run_command_silent('df3d','location-name-read',tostring(site.id),tostring(location.id))
  assert(code==0,text);local observed=json.decode(text);assert(observed.valid and observed.header_valid)
  assert(request.native_header==observed.native_header and request.english_header==observed.english_header,'header transport differs')
 elseif request.op=='name_read' then
  assert(same(request.value,value(name)),'structured name readback differs')
 elseif request.op=='name_guard' then
  _G.df3d_name_transport_guard={name=value(name),rng=rng()}
 elseif request.op=='name_rng_unchanged' then
  assert(same(assert(_G.df3d_name_transport_guard).rng,rng()),'discarded dependent naming action consumed RNG')
 elseif request.op=='name_unchanged' then
  local guard=assert(_G.df3d_name_transport_guard)
  assert(same(guard.name,value(name)),'rejected/read request changed name')
  assert(same(guard.rng,rng()),'rejected/read request consumed RNG')
 elseif request.op=='name_random_check' then
  local guard=assert(_G.df3d_name_transport_guard);local actual=value(name)
  assert(same(request.value,actual),'random edit reply differs from native fields')
  assert(not same(guard.rng,rng()),'random edit did not advance RNG')
  if request.mode==2 then
   local expected=guard.name;expected.words[request.target+1]=actual.words[request.target+1];expected.parts[request.target+1]=actual.parts[request.target+1]
   assert(same(expected,actual),'random component changed unrelated fields')
   local text,code=dfhack.run_command_silent('df3d','location-name-words',tostring(request.displayed),'',tostring(name.language))
   assert(code==0,text);local choices=json.decode(text);assert(choices.valid and #choices.words>1)
   local found=false;for _,v in ipairs(choices.words)do if v[1]==actual.words[request.target+1] and v[2]==actual.parts[request.target+1]then found=true end end
   assert(found,'random component outside native displayed pool')
  else assert(request.mode==3 and actual.has_name,'whole random name missing')end
 elseif request.op=='name_edit_check' then
  local guard=assert(_G.df3d_name_transport_guard);local expected=guard.name
  assert(request.mode==0 or request.mode==1)
  expected.words[request.target+1]=request.mode==0 and -1 or request.word
  expected.parts[request.target+1]=request.mode==0 and 0 or request.part
  assert(same(expected,value(name)),'native component write differs')
  assert(same(guard.rng,rng()),'nonrandom edit consumed RNG')
  assert(same(request.value,value(name)),'edit reply differs from native name')
 elseif request.op=='name_choices' then
  -- The diagnostic provider's full ordering was independently compared with
  -- the native picker. Here verify transport paging plus raw display columns.
  local text,code=dfhack.run_command_silent('df3d','location-name-words',tostring(request.component),request.query,tostring(name.language))
  assert(code==0,text);local native=json.decode(text);assert(native.valid)
  assert(#request.choices==#native.words,'choice total mismatch')
  for i,row in ipairs(request.choices)do
   local ref=native.words[i];assert(row.word==ref[1] and row.part==ref[2],'native choice order differs')
   assert(row.english==dfhack.df2utf(df.global.world.raws.language.words[row.word].forms[row.part]),'English form differs')
   assert(row.translated==ref[4],'translation differs')
  end
  result.total=#native.words
 else error('unexpected naming operation')end
end
f=assert(io.open(out..'/response-'..index..'.json','w'));f:write(json.encode(result));f:close()
print('SEMANTIC_PASS '..index..' '..request.op)
