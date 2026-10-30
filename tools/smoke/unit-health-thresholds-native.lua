-- Protected paused native oracle. Controlled fields are restored before returning.
local unit,view=...
local json=require('json')
local saved,baseline,cases={},{},{}
local wound,part,job,target_ref,bed
local extra_signature
local function remember(object,key,value)
 saved[#saved+1]={object=object,key=key,value=object[key]}
 object[key]=value;baseline[#baseline+1]={object=object,key=key,value=value}
end
local function reset()for _,v in ipairs(baseline)do v.object[v.key]=v.value end end
local function cleanup()
 for i=#saved,1,-1 do local v=saved[i];v.object[v.key]=v.value end
 if bed then
  while #bed.users.unit>0 do bed.users.unit:erase(#bed.users.unit-1)end
  while #bed.users.mode>0 do bed.users.mode:erase(#bed.users.mode-1)end
 end
 if job then
  while #job.general_refs>0 do job.general_refs:erase(#job.general_refs-1)end
  if target_ref then df.delete(target_ref)end
  df.delete(job)
 end
 if wound then
  for i=#unit.body.wounds-1,0,-1 do if unit.body.wounds[i]==wound then unit.body.wounds:erase(i);break end end
  if part then wound.parts:erase(0);df.delete(part)end
  df.delete(wound)
 end
end
local ok,err=xpcall(function()
 local c,c2,p=unit.counters,unit.counters2,unit.status.current_soul.personality
 remember(unit,'mood',df.mood_type.None);remember(p,'longterm_stress',0)
 for _,key in ipairs{'winded','stunned','unconscious','webbed','pain','nausea','dizziness'}do remember(c,key,0)end
 for _,key in ipairs{'paralysis','numbness','fever','exhaustion','hunger_timer','thirst_timer','sleepiness_timer'}do remember(c2,key,0)end
 remember(unit.body,'blood_count',unit.body.blood_max);remember(unit.flags1,'drowning',false)
 remember(assert(unit.health).flags,'whole',0);remember(unit.job,'current_job',nil)
 for _,existing in ipairs(unit.body.wounds)do for _,layer in ipairs(existing.parts)do remember(layer,'bleeding',0)end end
 wound=df.unit_wound:new();part=df.unit_wound_layerst:new()
 wound.id=2147483000;wound.attacker_unit_id=-1;wound.attacker_hist_figure_id=-1;wound.syndrome_id=-1
 part.body_part_id=0;part.layer_idx=0;part.global_layer_idx=0
 wound.parts:insert('#',part);unit.body.wounds:insert('#',wound)
 remember(part,'bleeding',0)
 local protected={unit,unit.health,p,df.global.game.main_interface.view_sheets,df.global.plotinfo}
 for _,w in ipairs(unit.body.wounds)do protected[#protected+1]=w;for _,layer in ipairs(w.parts)do protected[#protected+1]=layer end end
 local function observe(name,tick)
  view:render(tick or 0)
  local native={}
  for y=24,29 do
   local chars={};for x=53,81 do local ch=dfhack.screen.readTile(x,y).ch;chars[#chars+1]=ch>=32 and string.char(ch) or ' ' end
   local text=table.concat(chars):gsub('%s+$','');local pen=dfhack.screen.readTile(53,y)
   if #text>0 then native[#native+1]={text=text,color=pen.fg+(pen.bold and 8 or 0)}end
  end
  local copies={}
  for _,object in ipairs(protected)do local size,address=df.sizeof(object);local bytes=df.new('uint8_t',size);dfhack.internal.memmove(bytes,address,size);copies[#copies+1]={bytes=bytes,address=address,size=size}end
  local extra_before=extra_signature and extra_signature()
  local text,status=dfhack.run_command_silent('df3d','unit-health-probe',tostring(unit.id))
  local unchanged=true
  for _,copy in ipairs(copies)do if dfhack.internal.memcmp(copy.bytes,copy.address,copy.size)~=0 then unchanged=false end;df.delete(copy.bytes)end
  if extra_signature then unchanged=unchanged and extra_before==extra_signature()end
  assert(status==0,text);assert(unchanged,'health threshold reader mutated guarded state: '..name)
  local rows=json.decode(text);assert(#rows==#native,'health threshold count mismatch: '..name)
  for i,row in ipairs(rows)do
   local color=row.color
   if row.flash==1 then color=color+((tick or 0)%1000>=500 and 8 or 0)
   elseif row.flash==2 then color=({1,9,11,9})[((tick or 0)%500)//125+1]end
   assert(row.text==native[i].text and color==native[i].color,'health threshold native mismatch: '..name..' row '..i)
  end
  cases[#cases+1]={name=name,tick=tick or 0,rows=rows,native=native,guarded_state_unchanged=unchanged}
 end
 local function sweep(object,key,values)
  for _,value in ipairs(values)do reset();object[key]=value;observe(key..'='..value)end
 end
 observe('baseline')
 sweep(p,'longterm_stress',{19999,20000,49999,50000,99999,100000})
 for mood=-1,9 do reset();p.longterm_stress=100000;unit.mood=mood;observe('stress-mood='..mood)end
 sweep(c2,'hunger_timer',{49999,50000,74999,75000})
 sweep(c2,'thirst_timer',{24999,25000,49999,50000})
 sweep(c2,'sleepiness_timer',{57599,57600,149999,150000})
 sweep(c,'unconscious',{0,1});sweep(c2,'paralysis',{0,1,49,50,99,100})
 sweep(c,'stunned',{0,1});sweep(c,'dizziness',{0,1})
 sweep(c2,'exhaustion',{1999,2000,3999,4000,5999,6000})
 sweep(c,'winded',{0,1});sweep(c,'nausea',{0,1});sweep(c,'pain',{49,50,99,100})
 sweep(c2,'numbness',{0,1});sweep(c2,'fever',{0,1})
 local max=unit.body.blood_max;sweep(unit.body,'blood_count',{max//4-1,max//4,max//2-1,max//2})
 sweep(part,'bleeding',{0,1,9,10});reset();part.bleeding=10;observe('heavy-bleeding-bright',500)
 sweep(c,'webbed',{0,1,9,10})
 sweep(unit.health.flags,'whole',{0,1,2,4,8,16,32,64,128,256,512,1024,6})
 reset();c.unconscious=1;c2.paralysis=100;observe('unconscious-before-paralysis')
 reset();c.stunned=1;c.dizziness=1;c2.exhaustion=6000;observe('stunned-before-dizzy-exhausted')
 reset();c.dizziness=1;c2.exhaustion=6000;observe('dizzy-before-exhausted')
 reset()
 for _,candidate in ipairs(df.global.world.buildings.all)do
  if df.building_bedst:is_instance(candidate) and #candidate.users.unit==0 and #candidate.users.mode==0 then bed=candidate;break end
 end
 assert(bed,'traction reader fixture needs an unused bed')
 job=df.job:new();job.job_type=df.job_type.Rest;job.id=-1;job.pos:assign(unit.pos)
 target_ref=df.general_ref_building_use_target_1st:new();target_ref.building_id=bed.id
 protected[#protected+1]=job;protected[#protected+1]=target_ref;protected[#protected+1]=bed
 extra_signature=function()
  local users,modes,refs={},{},{}
  for _,value in ipairs(bed.users.unit)do users[#users+1]=value end
  for _,value in ipairs(bed.users.mode)do modes[#modes+1]=value end
  for _,value in ipairs(job.general_refs)do refs[#refs+1]={type=value:getType(),id=value:getID()}end
  return json.encode{users=users,modes=modes,refs=refs}
 end
 unit.job.current_job=job;observe('rest-no-target')
 job.general_refs:insert('#',target_ref);target_ref.building_id=-1;observe('rest-missing-building')
 target_ref.building_id=bed.id;observe('rest-unused-bed')
 bed.users.unit:insert('#',-1);bed.users.mode:insert('#',df.building_use_type.RestInTraction);observe('traction-other-unit')
 bed.users.unit[0]=unit.id;bed.users.mode[0]=df.building_use_type.Rest;observe('ordinary-rest')
 bed.users.mode[0]=df.building_use_type.RestInTraction;observe('rest-in-traction')
 bed.users.unit:insert('#',unit.id);bed.users.mode:insert('#',df.building_use_type.Rest);observe('traction-before-last-matching-user')
 unit.health.flags.whole=2;observe('traction-seriously-injured')
 unit.health.flags.whole=4;observe('traction-injured')
end,debug.traceback)
cleanup();view:render(dfhack.getTickCount());assert(ok,err)
return cases
