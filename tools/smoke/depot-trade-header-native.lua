-- Disposable paused reference for semantic header text and native colors.
local view,trade,building,exercise_moods=...
local json=require('json');local result={cases={}}
local function row(y)
 local chars={}
 for x=17,118 do local t=dfhack.screen.readTile(x,y);chars[#chars+1]=t.ch>=32 and t.ch<=255 and string.char(t.ch)or' 'end
 return dfhack.df2utf(table.concat(chars)):gsub('%s+$','')
end
local function color(x,y)
 local t=dfhack.screen.readTile(x,y);return t.fg+((t.bold==1 or t.bold==true)and 8 or 0)
end
local function check(label)
 view:render(dfhack.getTickCount())
 local output,code=dfhack.run_command_silent('df3d','trade-header-probe',tostring(building.id),'0',tostring(math.max(0,trade.talkline)))
 assert(code==0,output);local h=json.decode(output);assert(h.available,output)
 if h.speaker>=0 then
  assert(h.name==row(5),'Header name differs: '..h.name..' != '..row(5))
  assert(h.name_effect==0,'Fixture unexpectedly needs animated name color')
  assert(h.name_color[1]+8*h.name_color[3]==color(17,5),'Name color differs')
 end
 for i,text in ipairs(h.status)do assert(text==row(6+i),'Status differs');assert(h.status_color==color(17,6+i),'Status color differs')end
 if trade.havetalker~=0 and trade.stillunloading==0 and trade.merchant_trader then
  assert(h.mood==row(10),'Mood differs: '..h.mood..' != '..row(10))
  if h.mood~='' then assert(h.mood_color==color(17,10),'Mood color differs')end
 end
 result.cases[#result.cases+1]={label=label,header=h};return h
end
check('initial')
if exercise_moods then
 local soul=assert(trade.fortress_trader.status.current_soul);local skill
 for _,s in ipairs(soul.skills)do if s.id==df.job_skill.JUDGING_INTENT then skill=s;break end end
 local created=not skill;local old=skill and skill.rating;local mood=trade.mer.mood
 if not skill then skill=df.unit_skill:new();skill.id=df.job_skill.JUDGING_INTENT;require('utils').insert_sorted(soul.skills,skill,'id')end
 local ok,err=xpcall(function()
  skill.rating=15
  for _,value in ipairs{-1,0,1,19,20,39,40,59,60,79,80,99,100}do
   trade.mer.mood=value;local h=check('mood-'..value);assert(h.mood~='','Fixture lacks effective Judging Intent')
  end
 end,debug.traceback)
 trade.mer.mood=mood
 if created then for i,s in ipairs(soul.skills)do if s==skill then soul.skills:erase(i);break end end;skill:delete()else skill.rating=old end
 view:render(dfhack.getTickCount());assert(ok,err)
end
return result
