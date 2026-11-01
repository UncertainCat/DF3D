-- Membership validation for a selected Knowledge detail, in the owned clone.
local unit,detail=...
local json=require('json');local results={}
local function probe(label,unit_id,kind,id,available)
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
 object(unit);object(unit.status.current_soul);object(df.global.game.main_interface.view_sheets);object(df.global.plotinfo)
 local hf=df.historical_figure.find(unit.hist_figure_id);object(hf)
 if hf then object(hf.info);if hf.info then
  local known=hf.info.known_info;object(known)
  if known then object(known.knowledge);for _,field in ipairs{'known_poetic_forms','known_musical_forms','known_dance_forms','known_written_contents'}do vector(known[field])end end
 end end
 local base=dfhack.internal.getImageBase()
 for _,range in ipairs{{0x234e990,0x6180},{0x2131b30,40},{0x2159084,2},{0x18adf98,8}}do guard(base+range[1],range[2])end
 local text,status=dfhack.run_command_silent('df3d','unit-knowledge-detail-probe',tostring(unit_id),tostring(kind),tostring(id))
 local unchanged=true;for _,g in ipairs(guards)do if dfhack.internal.memcmp(g.bytes,g.address,g.size)~=0 then unchanged=false end;df.delete(g.bytes)end
 assert(status==0,text);assert(unchanged,'Selected Knowledge probe changed membership/source/UI/random state')
 local value=json.decode(text);assert(value.available==available,'Wrong Knowledge availability: '..label)
 if available then assert(value.text==detail.tagged_rows[1],'Selected Knowledge detail differs from native')
 else assert(value.text==nil,'Rejected Knowledge detail leaked text')end
 results[#results+1]={case=label,available=available,guards_unchanged=unchanged,length=available and #value.text or 0}
end
probe('known-entry',unit.id,detail.kind,detail.id,true)
probe('missing-creature',2147483647,detail.kind,detail.id,false)
probe('missing-entry',unit.id,detail.kind,2147483647,false)
probe('scholarly-kind',unit.id,13,detail.id,false)
probe('invalid-kind',unit.id,18,detail.id,false)
probe('negative-entry',unit.id,detail.kind,-1,false)
local soul=unit.status.current_soul;unit.status.current_soul=nil
local ok,err=xpcall(function()probe('no-soul',unit.id,detail.kind,detail.id,false)end,debug.traceback)
unit.status.current_soul=soul;assert(ok,err)
local fields={[14]='known_poetic_forms',[15]='known_musical_forms',[16]='known_dance_forms',[17]='known_written_contents'}
local vector=assert(df.historical_figure.find(unit.hist_figure_id).info.known_info)[fields[detail.kind]]
local original={};for _,id in ipairs(vector)do original[#original+1]=id end
for i=#vector-1,0,-1 do if vector[i]==detail.id then vector:erase(i)end end
ok,err=xpcall(function()probe('removed-membership',unit.id,detail.kind,detail.id,false)end,debug.traceback)
vector:resize(0);for _,id in ipairs(original)do vector:insert('#',id)end
assert(ok,err);probe('restored-membership',unit.id,detail.kind,detail.id,true)
if os.getenv('DF3D_UNIT_KNOWLEDGE_CACHE')=='1'then
 local text,status=dfhack.run_command_silent('df3d','unit-knowledge-cache-probe',tostring(unit.id),tostring(detail.kind),tostring(detail.id))
 assert(status==0,text);local value=json.decode(text)
 assert(value.available and value.text==detail.tagged_rows[1],'Cold-cache Knowledge text differs from native')
 assert(value.cold_insertions>0,'Historical-material probe did not force a cache miss')
 assert(value.nested_restored and value.exception_restored and value.original_restored,'Knowledge material cache was not restored')
 results[#results+1]={case='cold-material-cache',cold_insertions=value.cold_insertions,nested_restored=value.nested_restored,exception_restored=value.exception_restored,original_restored=value.original_restored,length=#value.text}
end
return results
