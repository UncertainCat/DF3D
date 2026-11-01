-- Exercise the non-impersonation identity formatter through native agreements.
local unit,form_id,capture,out=...
local json=require('json');local form=assert(df.dance_form.find(form_id))
local world=df.global.world;local events=world.history.events;local identities=world.identities.all;local agreements=world.agreements.all
local original=form.event;local counts={#events,#identities,#agreements};local results={}
for _,variant in ipairs{'named','unnamed','profession','unnamed-profession','entity','reason-two','missing-identity'}do
 local identity=df.identity:new();local event=df.history_event_agreement_formedst:new()
 local lost=df.history_event_masterpiece_lostst:new()
 local agreement=df.agreement:new();local detail=df.agreement_details:new();local data=df.agreement_details_data_join_party:new()
 local member=df.agreement_party:new();local party=df.agreement_party:new()
 local ok,err=xpcall(function()
  identity.id=#identities>0 and identities[#identities-1].id+1 or 0
  identity.name:assign(unit.name);identity.race=unit.race;identity.caste=unit.caste
  assert(identity.race>=0 and identity.race<32767)
  identity.impersonated_hf=-1;identity.histfig_id=-1;identity.type=df.identity_type.FalseIdentity
  identity.profession=-1;identity.entity_id=-1
  if variant=='unnamed'or variant=='unnamed-profession'then identity.name.has_name=false end
  if variant=='profession'or variant=='unnamed-profession'then identity.profession=df.profession.MINER end
  if variant=='entity'then identity.entity_id=unit.civ_id end
  identities:insert('#',identity)
  member.id=0;member.histfig_ids:insert('#',unit.hist_figure_id)
  party.id=1;party.entity_ids:insert('#',unit.civ_id)
  agreement.id=#agreements>0 and agreements[#agreements-1].id+1 or 0
  agreement.parties:insert('#',member);agreement.parties:insert('#',party)
  detail.id=0;detail.type=df.agreement_details_type.JoinParty;detail.data.JoinParty=data
  data.reason=variant=='reason-two'and 2 or 24;data.member=0;data.party=1
  data.site=-1;data.entity=variant=='missing-identity'and identity.id+1 or identity.id;data.figure=-1
  agreement.details:insert('#',detail);agreements:insert('#',agreement)
  event.id=events[#events-1].id+1;event.year=df.global.cur_year;event.seconds=df.global.cur_year_tick
  event.agreement_id=agreement.id;events:insert('#',event);form.event=event.id
  lost.id=event.id+1;lost.year=event.year;lost.seconds=event.seconds;lost.creation_event=event.id;lost.histfig=-1;lost.site=-1;lost.method=0
  events:insert('#',lost)
  local text=capture('agreement-identity-'..variant);local repeated=capture('agreement-identity-'..variant..'-warm')
  assert(text==repeated,'Repeated agreement identity description differs')
  local nested_text
  if variant=='profession'then
   form.event=lost.id;nested_text=capture('agreement-identity-nested-profession')
   assert(nested_text==capture('agreement-identity-nested-profession-warm'),'Repeated nested identity description differs')
   form.event=event.id
  end
  local rejected={}
  if variant=='profession'or variant=='unnamed-profession'then
   local race=identity.race
   for _,invalid in ipairs{-2,65534,131070}do
    identity.race=invalid
    for _,root in ipairs{event.id,lost.id}do
    form.event=root
    local guards={}
    for _,value in ipairs{identity,unit,df.global.game.main_interface.view_sheets,df.global.plotinfo}do
     local size,address=df.sizeof(value);local bytes=df.new('uint8_t',size)
     dfhack.internal.memmove(bytes,address,size);guards[#guards+1]={bytes=bytes,address=address,size=size}
    end
    local output,status=dfhack.run_command_silent('df3d','dance-detail-probe',tostring(form.id))
    local unchanged=true
    for _,guard in ipairs(guards)do
     if dfhack.internal.memcmp(guard.bytes,guard.address,guard.size)~=0 then unchanged=false end
     df.delete(guard.bytes)
    end
    assert(status~=0,'UI-dependent identity race was accepted: '..invalid..' '..output)
    assert(unchanged,'Rejected identity probe changed source/UI state')
    rejected[#rejected+1]={race=invalid,nested=root==lost.id}
    end
   end
   form.event=event.id
   identity.race=race
  end
  results[#results+1]={case=variant,text=text,nested_text=nested_text,reason=data.reason,race=identity.race,caste=identity.caste,profession=identity.profession,rejected_ui_races=rejected}
 end,debug.traceback)
 form.event=original
 while #events>counts[1]do events:erase(#events-1)end
 while #identities>counts[2]do identities:erase(#identities-1)end
 while #agreements>counts[3]do agreements:erase(#agreements-1)end
 agreement.parties:resize(0);agreement.details:resize(0);detail.data.JoinParty=nil
 df.delete(lost);df.delete(event);df.delete(agreement);df.delete(detail);df.delete(data);df.delete(member);df.delete(party);df.delete(identity)
 assert(ok,err)
end
local f=assert(io.open(out..'/knowledge-agreement-identity-native.json','w'));f:write(json.encode(results));f:close()
return true
