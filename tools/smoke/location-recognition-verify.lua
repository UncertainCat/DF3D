-- Owned paused clone diagnostics. Native fields, not transport replies, prove effects.
local out,index=...
local json=require('json')
local f=assert(io.open(out..'/request-'..index..'.json'));local request=json.decode(f:read('*a'));f:close()
assert(df.global.pause_state and df.global.world.frame_counter==0,'paused clone required')
local site=assert(dfhack.world.getCurrentSite());local temple
for _,v in ipairs(site.buildings)do
 if v.id==0 and df.abstract_building_templest:is_instance(v)then temple=v;break end
end
assert(temple and temple.deity_type==df.religious_practice_type.RELIGION_ENID)
local religion=assert(df.historical_entity.find(temple.deity_data.Religion))
local result={status='passed',site_id=site.id,location_id=temple.id}
local function capture()
 local v={positions={},assignments={},next_position=religion.positions.next_position_id,next_assignment=religion.positions.next_assignment_id,
  events=#df.global.world.history.events,emotions=0,rng={}}
 for _,p in ipairs(religion.positions.own)do v.positions[#v.positions+1]={id=p.id,code=p.code}end
 for _,a in ipairs(religion.positions.assignments)do v.assignments[#v.assignments+1]={id=a.id,position=a.position_id,histfig=a.histfig,site=a.st_id}end
 for _,u in ipairs(df.global.world.units.active)do
  local soul=u.status.current_soul
  if soul then for _,e in ipairs(soul.personality.emotions)do if e.thought==df.unit_thought_type.EstablishedTemple and e.subthought==religion.id then v.emotions=v.emotions+1 end end end
 end
 local base=dfhack.internal.getImageBase();local context=df.reinterpret_cast('int16_t',base+0x2159084).value
 assert(context>=0 and context<16);v.rng.context=context;v.rng.cursor=df.reinterpret_cast('uint32_t',base+0x2131b30+context*4).value
 for i=0,623 do v.rng[i+1]=df.reinterpret_cast('uint32_t',base+0x234e990+context*0x9c0+i*4).value end
 return v
end
local function command(name)
 local text,code=dfhack.run_command_silent('df3d',name,tostring(site.id),tostring(temple.id));assert(code==0,text);return json.decode(text)
end
if request.op=='recognition_setup' then
 local variant=request.variant or 'promote'
 assert(variant=='reusehigh' or variant=='promote' or variant=='first' or variant=='empty' or variant=='new')
 if not _G.df3d_recognition_variant then
  _G.df3d_recognition_variant=variant
  if variant=='reusehigh' then
   local priest
   for _,p in ipairs(religion.positions.own)do
    assert(p.code~='HIGH_PRIEST','high priest fixture already present')
    if p.code=='PRIEST' then priest=p end
   end
   assert(priest,'priest template absent')
   local high=df.entity_position:new();high:assign(priest)
   high.id=religion.positions.next_position_id;religion.positions.next_position_id=high.id+1
   high.code='HIGH_PRIEST';religion.positions.own:insert('#',high)
  end
  if variant~='promote' and variant~='reusehigh' then
   local changed=0
   for _,a in ipairs(religion.positions.assignments)do
    if a.st_id==site.id then
     if variant=='first' or variant=='new' then a.st_id=-1 else a.histfig=-1 end
     changed=changed+1
    end
   end
   assert(changed==1,'unexpected recognition fixture assignments')
   if variant=='new' then
    local templates=0
    for _,p in ipairs(religion.positions.own)do
     if p.code=='PRIEST' then p.code='DF3D_FIXTURE_OLD_PRIEST';templates=templates+1 end
    end
    assert(templates==1,'unexpected priest template fixture count')
   end
  end
 end
 assert(_G.df3d_recognition_variant==variant)
 temple:getContents().location_tier=(variant=='first' or variant=='new') and 1 or 2
 result.before=capture()
 assert(#result.before.assignments>0,'priest fixture missing')
 _G.df3d_recognition_transport_before=result.before
elseif request.op=='recognition_guard' then
 local guards={}
 local m=df.global.game.main_interface
 for _,object in ipairs{m,df.global.gps,m.location_details,m.location_selector,m.name_creator}do
  local size,address=df.sizeof(object);local bytes=df.new('uint8_t',size);dfhack.internal.memmove(bytes,address,size)
  guards[#guards+1]={bytes=bytes,address=address,size=size}
 end
 _G.df3d_recognition_transport_guard={state=capture(),ui=guards,bottom_mode=m.bottom_mode_selected}
elseif request.op=='recognition_unchanged' or request.op=='recognition_applied' then
 local guard=assert(_G.df3d_recognition_transport_guard)
 result.ui_changed={}
 for i,v in ipairs(guard.ui)do
  local changed=dfhack.internal.memcmp(v.bytes,v.address,v.size)~=0
  result.ui_changed[i]=changed
  if i~=2 then assert(not changed,'recognition changed native UI '..i)end
  df.delete(v.bytes)
 end
 assert(guard.bottom_mode==df.global.game.main_interface.bottom_mode_selected,'recognition changed bottom mode')
 if request.op=='recognition_unchanged' then assert(json.encode(guard.state)==json.encode(capture()),'read/refusal changed native effects or RNG')
 else
  local before=assert(_G.df3d_recognition_transport_before);local after=capture()
  local variant=_G.df3d_recognition_variant or 'promote'
  assert(after.next_position==before.next_position+((variant=='first' or variant=='reusehigh') and 0 or 1) and after.next_assignment==before.next_assignment+1,'recognition allocation mismatch')
  assert(after.events==before.events+((variant=='promote' or variant=='reusehigh') and 1 or 0),'recognition event mismatch')
  assert(after.emotions==before.emotions+54,'native thought recipients differ')
  -- Native first024521 reuses PRIEST without RNG; empty024612/promote020539
  -- allocate a named HIGH_PRIEST template and advance it.
  assert((json.encode(after.rng)==json.encode(before.rng))==(variant=='first' or variant=='reusehigh'),'recognition RNG behavior differs from native branch')
  local old=before.assignments[#before.assignments];local added=after.assignments[#after.assignments]
  assert(added.site==site.id,'assignment site mismatch')
  if variant=='reusehigh' then
   assert(json.encode(before.positions)==json.encode(after.positions),'existing position definitions changed')
   assert(added.position==before.positions[#before.positions].id and before.positions[#before.positions].code=='HIGH_PRIEST','existing high priest definition was not reused')
  end
  if variant=='promote' or variant=='reusehigh' then assert(old.histfig>=0 and added.histfig==old.histfig,'holder promotion mismatch')
  else assert(added.histfig==-1,'expected vacant assignment')end
  result.after=after
 end
 _G.df3d_recognition_transport_guard=nil
elseif request.op=='recognition_threshold' then
 local difficulty=df.global.plotinfo.main.custom_difficulty
 if request.restore then difficulty.high_priesthood_unit_count=assert(_G.df3d_recognition_threshold)
 else _G.df3d_recognition_threshold=difficulty.high_priesthood_unit_count;difficulty.high_priesthood_unit_count=difficulty.high_priesthood_unit_count+1 end
elseif request.op=='recognition_tier' then temple:getContents().location_tier=request.value
elseif request.op=='recognition_readback' then
 local observed=command('location-recognition-read');local receipt=command('location-recognition-receipt')
 assert(receipt.valid and tostring(request.revision)==receipt.revision,'revision transport mismatch')
 for _,key in ipairs{'site_id','location_id','religion_id','tier','rank','worshippers','priest_threshold','high_priest_threshold','state','continuing_agreements'}do
  assert(json.encode(request.snapshot[key])==json.encode(observed[key]),'recognition transport mismatch '..key)
 end
else error('unexpected recognition operation')end
f=assert(io.open(out..'/response-'..index..'.json','w'));f:write(json.encode(result));f:close()
print('SEMANTIC_PASS '..index..' '..request.op)
