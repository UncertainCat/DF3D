-- Diagnostic-only broker/skill fixture in a paused disposable save.
local out,view,b,capture,click,compare_selection=...
local gui=require('gui');local json=require('json');local g=df.global.gps
local menu=df.global.game.main_interface.assign_trade
local assignments=df.global.plotinfo.main.fortress_entity.assignments_by_type[df.entity_position_responsibility.TRADE]
assert(#assignments==0 and menu.open and #b.jobs==0)
local frame=df.global.world.frame_counter;local unit
for _,u in ipairs(df.global.world.units.active)do if dfhack.units.isCitizen(u) and u.status.current_soul and u.hist_figure_id>=0 then unit=u;break end end
assert(unit)
local skills=unit.status.current_soul.skills;local skill;local created=false
for _,v in ipairs(skills)do if v.id==df.job_skill.APPRAISAL then skill=v;break end end
if not skill then skill=df.unit_skill:new();skill.id=df.job_skill.APPRAISAL;require('utils').insert_sorted(skills,skill,'id');created=true end
local rating,rusty=skill.rating,skill.rusty
local assignment=df.entity_position_assignment:new();assignment.histfig=unit.hist_figure_id
local inserted=false;local result={unit_id=unit.id,cases={}}
local function select_type(kind)
 local index
 for i,v in ipairs(menu.filtered_type_list)do if v==kind then index=i;break end end
 assert(index)
 -- Oracle setup only: expose the target category, then use its actual button.
 menu.scroll_position_type=math.max(0,index-3);view:render(dfhack.getTickCount())
 click(150,4+(7+3*(index-menu.scroll_position_type))*12+12)
 assert(menu.current_type==kind)
end
local function sample(label,known)
 view:render(dfhack.getTickCount())
 local text,code=dfhack.run_command_silent('df3d','depot-selection-probe',tostring(b.id),tostring(menu.current_type),menu.sort_by_distance and '1' or '0','1','0','')
 assert(code==0,text);local facts=json.decode(text)
 local expected=known and math.max(0,dfhack.units.getEffectiveSkill(unit,df.job_skill.APPRAISAL))+1 or 0
 assert(facts.appraisal==expected,'Native appraisal lookup differs')
 assert(#facts.ids==#menu.current_type_tgi)
 for i,row in ipairs(menu.current_type_tgi)do assert(facts.ids[i+1]==row.it.id,'Native sorting differs')end
 local captions={};for i,id in ipairs(facts.ids)do
  local chars={};for _,ch in ipairs(facts.value_captions[i])do chars[#chars+1]=string.char(ch)end
  captions[id]=table.concat(chars)
  assert((#captions[id]>0)==known,'Unexpected value disclosure')
 end
 local cell=9;local visible=0
 for _,group in ipairs(facts.groups)do if group.matches then
  cell=cell+3
  if group.expanded then for _,id in ipairs(group.ids)do
   if cell+2<g.dimy-5 then
    local chars={};for x=45,g.dimx-30 do local ch=dfhack.screen.readTile(x,cell+2).ch;chars[#chars+1]=ch>=0 and ch<=255 and string.char(ch)or' 'end
    local line=table.concat(chars)
    if known then assert(line:find('Value: '..captions[id],1,true),'Native value text differs: '..label..' '..id);visible=visible+1 end
   end
   cell=cell+3
  end end
 end end
 if known then assert(visible>0,'No value rows observed')end
 assert(menu.open and #b.jobs==0 and df.global.world.frame_counter==frame)
 capture('depot-valuation-'..label)
 if os.getenv('DF3D_DEPOT_GOODS_WIRE')=='1' then compare_selection('valuation-'..label,facts)end
 result.cases[#result.cases+1]={label=label,category=menu.current_type,appraisal=facts.appraisal,sort_by_distance=menu.sort_by_distance,ids=facts.ids,value_captions=facts.value_captions,visible_values=visible,groups=facts.groups}
end
local ok,err=xpcall(function()
 sample('unassigned',false);click(888,94);assert(menu.sort_by_distance,'Hidden value-sort button accepted click')
 assignments:insert('#',assignment);inserted=true
 local best=menu.master_i_list.tgi[0]
 for _,row in ipairs(menu.master_i_list.tgi)do if row.value>best.value then best=row end end
 result.high_value_item=best.it.id;result.high_value=best.value
 select_type(best.it:getType())
 local shift=menu.i_height>(math.floor((g.dimy-11)/3)-1)*3 and 16 or 0
 for _,level in ipairs{0,5,15}do
  skill.rating=level;skill.rusty=0
  click(856-shift,94);assert(menu.sort_by_distance,'Distance sort hitbox missed');sample('distance-'..level,true)
  click(888-shift,94);assert(not menu.sort_by_distance,'Value sort hitbox missed');sample('value-'..level,true)
 end
 click(856-shift,94);assert(menu.sort_by_distance)
 assignment.histfig=-1;sample('missing-figure',false)
 assignment.histfig=unit.hist_figure_id;select_type(df.item_type.ANVIL)
end,debug.traceback)
if inserted then assignments:erase(#assignments-1)end
assignment:delete();skill.rating=rating;skill.rusty=rusty
if created then for i,v in ipairs(skills)do if v==skill then skills:erase(i);break end end;skill:delete()end
if not ok then error(err)end
menu.scroll_position_type=0;view:render(dfhack.getTickCount());sample('restored',false)
result.success=true
return result
