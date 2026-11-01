-- Synthetic corpse data copied from a valid living body; no creature is killed.
local unit,form_id,capture,out=...
local json=require('json');local form=assert(df.dance_form.find(form_id))
local world=df.global.world;local events=world.history.events;local artifacts=world.artifacts.all;local items=world.items.all
local original=form.event;local counts={#events,#artifacts,#items};local cached=unit.enemy.histfig_vector_idx
local has_name=unit.name.has_name
local item=df.item_corpsest:new();local artifact=df.artifact_record:new();local event=df.history_event_artifact_createdst:new();local results={}
local ok,err=xpcall(function()
 item.id=items[#items-1].id+1;item.world_data_id=-1;item.world_data_subid=-1
 item.race=unit.race;item.caste=unit.caste;item.normal_race=unit.race;item.normal_caste=unit.caste;item.sex=unit.sex
 item.unit_id=unit.id;item.unit_id2=-1;item.undead_unit_id=-1;item.hist_figure_id=-1;item.hist_figure_id2=-1;item.from_custom_body=0
 item.corpse_flags.whole=0;item.corpse_flags.rottable=true
 for _,field in ipairs{'body_part_status','numbered_masks','nonsolid_remaining','layer_status','layer_wound_area','layer_cut_fraction','layer_dent_fraction','layer_effect_fraction'}do
  local source=unit.body.components[field];local target=item.body.components[field];target:resize(#source)
  for i,value in ipairs(source)do
   if type(value)=='number'then target[i]=value else target[i]:assign(value)end
  end
 end
 assert(#item.body.components.body_part_status==#unit.body.body_plan.body_parts)
 for _,part in ipairs(unit.body.body_plan.body_parts)do assert(part.con_part_id==-1 or(part.con_part_id>=0 and part.con_part_id<#item.body.components.body_part_status))end
 artifact.id=artifacts[#artifacts-1].id+1;artifact.item=item;artifact.name.has_name=false
 event.id=events[#events-1].id+1;event.year=df.global.cur_year;event.seconds=df.global.cur_year_tick
 event.artifact_id=artifact.id;event.creator_unit_id=-1;event.creator_hfid=-1;event.entity=-1;event.site=-1
 items:insert('#',item);artifacts:insert('#',artifact);events:insert('#',event);form.event=event.id
 for _,variant in ipairs{'named','unnamed','unresolved-unit'}do
 unit.name.has_name=variant~='unnamed'and has_name or false
 item.unit_id=variant=='unresolved-unit'and 2147483647 or unit.id
 for _,mode in ipairs{'native-first','probe-first'}do
  unit.enemy.histfig_vector_idx=-1
  local cold,cold_index
  if mode=='probe-first'then
   local text,status=dfhack.run_command_silent('df3d','dance-detail-probe',tostring(form.id));assert(status==0,text);cold=json.decode(text).text
   cold_index=unit.enemy.histfig_vector_idx
   if variant=='unnamed'then assert(cold_index>=0,'Unnamed corpse did not reach history-cache refresh')
   else assert(cold_index==-1,'Named/unresolved corpse unexpectedly refreshed history cache')end
  end
  local text=capture('corpse-'..variant..'-'..mode)
  if cold then assert(cold==text,'Cold corpse caption differs from native')end
  assert(text==capture('corpse-'..variant..'-'..mode..'-warm'),'Repeated corpse description differs')
  results[#results+1]={case=variant..'-'..mode,variant=variant,mode=mode,text=text,cold_probe_index=cold_index,histfig_index=unit.enemy.histfig_vector_idx,body_parts=#item.body.components.body_part_status}
 end
 assert(results[#results-1].text==results[#results].text,'Corpse ordering changed text')
 end
end,debug.traceback)
form.event=original;unit.enemy.histfig_vector_idx=cached;unit.name.has_name=has_name
while #events>counts[1]do events:erase(#events-1)end
while #artifacts>counts[2]do artifacts:erase(#artifacts-1)end
while #items>counts[3]do items:erase(#items-1)end
artifact.item=nil;df.delete(event);df.delete(artifact);df.delete(item);assert(ok,err)
local f=assert(io.open(out..'/knowledge-corpse-native.json','w'));f:write(json.encode(results));f:close()
return true
