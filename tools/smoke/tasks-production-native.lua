-- Protected execution oracle only; do not manufacture inputs, workers or products.
local out,view,records,job=...
local script=require('gui.script');local gui=require('gui');local json=require('json');local utils=require('utils')
assert(job and df.global.pause_state and not job.flags['repeat'] and not job.flags.suspend)
local id=job.id;local material={job.mat_type,job.mat_index};local figure=job.art_spec.id
assert(job.job_type==df.job_type.ConstructStatue and job.art_spec.type==0 and figure>=0)
local before={};for _,item in ipairs(df.global.world.items.other.STATUE)do before[item.id]=true end
local function current()for _,candidate in utils.listpairs(df.global.world.jobs.list)do if candidate.id==id then return candidate end end end
local function snapshot(target)
 local worker=-1;local items={}
 for _,ref in ipairs(target.general_refs)do if ref:getType()==df.general_ref_type.UNIT_WORKER then worker=ref:getUnit().id end end
 for _,ref in ipairs(target.items)do items[#items+1]={id=ref.item and ref.item.id or -1,role=ref.role,job_item_idx=ref.job_item_idx}end
 return {flags=target.flags.whole,worker=worker,timer=target.completion_timer,items=items}
end
local reports=df.global.world.status.reports;local last_report=#reports>0 and reports[#reports-1].id or -1
local start=df.global.world.frame_counter
local result={job_id=id,material=material,figure=figure,start_tick=start,samples={},products={}}
local function save()local f=assert(io.open(out..'/tasks-production-native.json','w'));f:write(json.encode(result));f:close()end
local ok,err=xpcall(function()
 if df.global.game.main_interface.info.open then gui.simulateInput(view,'LEAVESCREEN')end
 assert(not df.global.game.main_interface.info.open,'Execution must leave native information menu')
 local deadline=dfhack.getTickCount()+180000;local next_sample=0
 df.global.pause_state=false
 while current() and df.global.world.frame_counter-start<12000 and dfhack.getTickCount()<deadline do
  script.sleep(1,'frames')
  local elapsed=df.global.world.frame_counter-start;local target=current()
  if target and elapsed>=next_sample then result.samples[#result.samples+1]={tick=elapsed,state=snapshot(target)};next_sample=elapsed+100;save()end
  if df.global.pause_state then result.native_paused=true;break end
 end
 df.global.pause_state=true
 result.end_tick=df.global.world.frame_counter;result.job_removed=current()==nil
 for _,item in ipairs(df.global.world.items.other.STATUE)do if not before[item.id] then
  local chunk=df.art_image_chunk.find(item.image.id)
  local art=chunk and chunk.images[item.image.subid].art_image;local subjects={}
  if art then for _,element in ipairs(art.elements)do if df.art_image_element_creaturest:is_instance(element)then subjects[#subjects+1]=element.histfig end end end
  result.products[#result.products+1]={id=item.id,material={item:getMaterial(),item:getMaterialIndex()},subjects=subjects}
 end end
 local matching=0
 for _,item in ipairs(result.products)do
  local subject=false;for _,hf in ipairs(item.subjects)do if hf==figure then subject=true end end
  if item.material[1]==material[1] and item.material[2]==material[2] and subject then matching=matching+1 end
 end
 result.matching_products=matching;result.reports={}
 for _,report in ipairs(reports)do if report.id>last_report then result.reports[#result.reports+1]={id=report.id,text=dfhack.df2utf(report.text)}end end
 save()
 assert(result.job_removed and matching==1,'Edited production job did not produce one matching statue within the bounded interval')
 records[#records+1]={name='tasks-production-simulation',start_tick=start,end_tick=result.end_tick,job_id=id,matching_products=matching}
end,debug.traceback)
df.global.pause_state=true
result.end_tick=df.global.world.frame_counter;result.success=ok;result.error=ok and nil or err;save()
assert(ok,err)
