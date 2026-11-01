-- Valid identity graphs on the disposable paused world; restore every insertion.
local unit,form_id,capture,out=...
local json=require('json');local form=assert(df.dance_form.find(form_id))
local world=df.global.world;local events=world.history.events;local identities=world.identities.all
local original=form.event;local event_count,identity_count=#events,#identities
local missing_hf=world.history.figures[#world.history.figures-1].id+1
local results={}
for _,variant in ipairs{'named','unnamed','profession','entity','impersonated','missing-impersonated','missing-identity','missing-trickster'}do
 local identity=df.identity:new();local event=df.history_event_assume_identityst:new()
 local ok,err=xpcall(function()
  identity.id=#identities>0 and identities[#identities-1].id+1 or 0
  identity.name:assign(unit.name);identity.race=unit.race;identity.caste=unit.caste
  identity.impersonated_hf=-1;identity.histfig_id=-1;identity.type=df.identity_type.FalseIdentity
  identity.profession=-1;identity.entity_id=-1
  assert(identity.race>=0 and identity.race<32767)
  if variant=='unnamed'then identity.name.has_name=false end
  if variant=='profession'then identity.profession=df.profession.MINER end
  if variant=='entity'then identity.entity_id=unit.civ_id end
  if variant=='impersonated'then identity.impersonated_hf=unit.hist_figure_id end
  if variant=='missing-impersonated'then identity.impersonated_hf=missing_hf end
  identities:insert('#',identity)
  event.id=events[#events-1].id+1;event.year=df.global.cur_year;event.seconds=df.global.cur_year_tick
  event.trickster=variant=='missing-trickster'and missing_hf or unit.hist_figure_id
  event.identity=variant=='missing-identity'and identity.id+1 or identity.id;event.target=unit.civ_id
  events:insert('#',event);form.event=event.id
  local text=capture('identity-'..variant);local repeated=capture('identity-'..variant..'-warm')
  assert(text==repeated,'Repeated identity description differs')
  results[#results+1]={case=variant,text=text,race=identity.race,caste=identity.caste,profession=identity.profession}
 end,debug.traceback)
 form.event=original
 while #events>event_count do events:erase(#events-1)end
 while #identities>identity_count do identities:erase(#identities-1)end
 df.delete(event);df.delete(identity);assert(ok,err)
end
local f=assert(io.open(out..'/knowledge-identity-native.json','w'));f:write(json.encode(results));f:close()
return true
