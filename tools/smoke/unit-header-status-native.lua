-- Native-only status-row oracle. Temporary facts never advance simulation.
local unit,view=...
local json=require('json')
local p=assert(unit.status.current_soul).personality
local saved={mood=unit.mood,soldier=unit.counters.soldier_mood,sex=unit.sex,
 flags1=unit.flags1.whole,flags3=unit.flags3.whole,flags4=unit.flags4.whole,
 owner=unit.relationship_ids[0],emotions={}}
local artifact=df.language_name:new();artifact:assign(unit.status.artifact_name)
for _,emotion in ipairs(p.emotions)do saved.emotions[#saved.emotions+1]=emotion end
local first,second=df.personality_moodst:new(),df.personality_moodst:new()
local cases={}
local function clear()while #p.emotions>0 do p.emotions:erase(#p.emotions-1)end end
local function reset()
 clear();unit.mood=df.mood_type.None;unit.counters.soldier_mood=-1;unit.sex=saved.sex
 unit.flags1.whole=saved.flags1;unit.flags1.on_ground=false
 unit.flags3.whole=saved.flags3;unit.flags3.emotionally_overloaded=false
 unit.flags4.whole=saved.flags4;unit.flags4.mood_succeeded=false
 unit.relationship_ids[0]=-1;first.flags.whole=1;second.flags.whole=1
end
local function observe(name)
 view:render(0)
 local rows={}
 for y=8,9 do
  local chars,colors={},{}
  for x=66,98 do
   local pen=dfhack.screen.readTile(x,y)
   chars[#chars+1]=pen.ch>=32 and string.char(pen.ch) or ' '
   colors[#colors+1]=pen.fg+(pen.bold and 8 or 0)
  end
  local text=table.concat(chars):gsub('%s+$','')
  while #colors>#text do table.remove(colors)end
  rows[#rows+1]={y=y,text=dfhack.df2utf(text),colors=colors}
 end
 local objects={unit,unit.status.current_soul,p,first,second,df.global.game.main_interface.view_sheets,df.global.plotinfo}
 local owner=df.unit.find(unit.relationship_ids[0]);if owner then objects[#objects+1]=owner end
 for _,emotion in ipairs(p.emotions)do objects[#objects+1]=emotion end
 local index=unit.enemy.histfig_vector_idx;unit.enemy.histfig_vector_idx=-1
 local copies={}
 for _,object in ipairs(objects)do
  local size,address=df.sizeof(object);local bytes=df.new('uint8_t',size)
  dfhack.internal.memmove(bytes,address,size);copies[#copies+1]={bytes=bytes,address=address,size=size}
 end
 local text,status=dfhack.run_command_silent('df3d','unit-header-status-probe',tostring(unit.id))
 local unchanged=true
 for _,copy in ipairs(copies)do
  if dfhack.internal.memcmp(copy.bytes,copy.address,copy.size)~=0 then unchanged=false end
  df.delete(copy.bytes)
 end
 unit.enemy.histfig_vector_idx=index
 assert(status==0,text);assert(unchanged,'header status reader changed guarded state: '..name)
 local result=json.decode(text)
 assert(dfhack.df2utf(dfhack.utf2df(result.text):sub(1,33))==rows[1].text,'header status text differs from native: '..name)
 for _,color in ipairs(rows[1].colors)do assert(color==result.color,'header status color differs from native: '..name)end
 cases[#cases+1]={name=name,rows=rows,probe=result,reader_unchanged=unchanged,cold_histfig_index=true}
end
local ok,err=xpcall(function()
 reset();observe('baseline')
 for value=0,4 do reset();unit.counters.soldier_mood=value;observe('soldier='..value)end
 for value=0,9 do reset();unit.mood=value;observe('mood='..value)end
 reset();unit.mood=df.mood_type.Raving;unit.flags1.on_ground=true;observe('raving-on-ground')
 for _,value in ipairs{5,12,13,39,44,46,64,68,78,88,111,112,135,141,143,152,0}do
  reset();unit.flags3.emotionally_overloaded=true;first.type=value;p.emotions:insert('#',first);observe('overloaded-emotion='..value)
 end
 for _,sex in ipairs{-1,0,1}do
  reset();unit.sex=sex;unit.flags3.emotionally_overloaded=true;first.type=78;p.emotions:insert('#',first);observe('overloaded-sex='..sex)
 end
 reset();unit.flags3.emotionally_overloaded=true;observe('overloaded-empty')
 reset();unit.flags3.emotionally_overloaded=true;first.type=152;first.flags.whole=0;p.emotions:insert('#',first);observe('overloaded-unflagged')
 reset();unit.flags3.emotionally_overloaded=true;first.type=0;second.type=152;p.emotions:insert('#',first);p.emotions:insert('#',second);observe('overloaded-skips-unmapped')
 first.type=5;observe('overloaded-first-mapped')
 unit.mood=df.mood_type.Fey;observe('mood-before-overload')
 unit.counters.soldier_mood=0;observe('soldier-before-mood')
 reset();unit.relationship_ids[0]=2147483000;observe('pet-missing-owner')
 local owner
 for _,candidate in ipairs(df.global.world.units.active)do if candidate.id~=unit.id then owner=candidate;break end end
 assert(owner,'header fixture requires another unit')
 unit.relationship_ids[0]=owner.id;observe('pet-owner')
 reset();unit.status.artifact_name:assign(owner.name);unit.flags4.mood_succeeded=true;observe('creator')
 unit.relationship_ids[0]=owner.id;observe('pet-before-creator')
 unit.flags3.emotionally_overloaded=true;observe('overload-before-pet')
end,debug.traceback)
clear();for _,emotion in ipairs(saved.emotions)do p.emotions:insert('#',emotion)end
unit.mood=saved.mood;unit.counters.soldier_mood=saved.soldier;unit.sex=saved.sex
unit.flags1.whole=saved.flags1;unit.flags3.whole=saved.flags3;unit.flags4.whole=saved.flags4
unit.relationship_ids[0]=saved.owner;unit.status.artifact_name:assign(artifact)
df.delete(artifact);df.delete(first);df.delete(second)
view:render(dfhack.getTickCount());assert(ok,err)
return cases
