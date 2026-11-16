-- Disposable paused native oracle. Call with source isolation enabled and an
-- open populated trade interface whose appraisal phase has not run yet.
local view,unit,trade,caravan=...
local json=require('json')
assert(trade.open and #trade.good[0]>0 and #trade.good[0]<=5 and #caravan.goods==0)
local soul=assert(unit.status.current_soul)
local skill
for _,s in ipairs(soul.skills)do if s.id==df.job_skill.APPRAISAL then skill=s;break end end
local created=not skill
local skill_fields={'rating','experience','unused_counter','rusty','rust_counter','demotion_counter','natural_skill_lvl'}
local attr_fields={'value','max_value','improve_counter','unused_counter','soft_demotion','rust_counter','demotion_counter'}
local function fields(object,names)
 local result={};for _,name in ipairs(names)do result[name]=object[name]end;return result
end
local original_skill=skill and fields(skill,skill_fields)
local original_attrs={}
for i=0,12 do original_attrs[i+1]=fields(soul.mental_attrs[i],attr_fields)end
if not skill then skill=df.unit_skill:new();skill.id=df.job_skill.APPRAISAL;require('utils').insert_sorted(soul.skills,skill,'id')end
-- Keep this case below the first level boundary so profession/thought side
-- effects cannot be mistaken for restored state. Those need separate coverage.
for _,name in ipairs(skill_fields)do skill[name]=0 end
local function snapshot()
 local row={skill=fields(skill,skill_fields),attributes={},goods={}}
 for i=0,12 do row.attributes[i+1]=fields(soul.mental_attrs[i],attr_fields)end
 for _,id in ipairs(caravan.goods)do row.goods[#row.goods+1]=id end
 return row
end
local result={before=snapshot(),merchant_items={},fortress_items={}}
for side=0,1 do for _,item in ipairs(trade.good[side])do
 table.insert(side==0 and result.merchant_items or result.fortress_items,item.id)
end end
local ok,err=xpcall(function()
 trade.handle_appraisal=1;view:render(dfhack.getTickCount())
 result.after=snapshot()
 assert(skill.rating==0 and skill.experience>0 and skill.experience<=250,'Unexpected appraisal gain')
 assert(trade.handle_appraisal==0)
 local seen={};for _,id in ipairs(caravan.goods)do assert(not seen[id]);seen[id]=true end
 for side=0,1 do for _,item in ipairs(trade.good[side])do assert(seen[item.id])end end
 for iteration=1,2 do
  -- Re-arm the native phase, as rebuilding/reopening does, to verify history
  -- deduplication rather than merely testing its one-shot UI flag.
  trade.handle_appraisal=1;view:render(dfhack.getTickCount())
  assert(json.encode(snapshot())==json.encode(result.after),'Appraisal repeated for known goods')
 end
 result.rearmed_deduplicated=true
end,debug.traceback)
for i=0,12 do for _,name in ipairs(attr_fields)do soul.mental_attrs[i][name]=original_attrs[i+1][name]end end
if created then
 for i,s in ipairs(soul.skills)do if s==skill then soul.skills:erase(i);break end end
 skill:delete()
else for _,name in ipairs(skill_fields)do skill[name]=original_skill[name]end end
if not ok then error(err)end
return result
