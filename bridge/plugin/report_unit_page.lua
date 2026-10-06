-- Fresh semantic unit-list snapshot at one safe point; no retained native pointers.
-- Unit membership follows nonempty logs even when every referenced report expired.
return function(profession)
 assert(type(profession)=='function')
 local function row(u,category)
  local name=dfhack.df2utf(dfhack.translation.translateName(u.name,false))
  local label=dfhack.df2utf(profession(u));local error=''
  if #name>512 then name='';error='Unit name exceeds 512 bytes'end
  if #label>512 then label='';error='Unit profession exceeds 512 bytes'end
  return {unit_id=u.id,category=category,name=name,profession=label,dead=dfhack.units.isDead(u),
   log_count=#u.reports.log[category],error=error}
 end
 local function integer(h,n)
  for _=1,4 do h=(h ~ (n & 255))*0x100000001b3;n=n>>8 end
  return h
 end
 return function(a)
  local category=a.unit_category or -1;local unit=a.unit_id or -1
  local cursor=a.cursor or 0;local expected=a.expected_list_revision or 0
  if math.type(category)~='integer' or category<0 or category>2 then return {ok=false,message='Unit category must be combat, sparring or hunting'}end
  if math.type(cursor)~='integer' or cursor<0 or math.type(unit)~='integer' or unit< -1 or
   math.type(expected)~='integer' or expected<0 then return {ok=false,message='Invalid unit list cursor'}end
  local source=df.global.world.units.all
  if #source>32768 then return {ok=false,message='Unit list exceeds 32768 units'}end
  local selected={};local counts={0,0,0};local total_rows=0;local hash=0xcbf29ce484222325
  for _,u in ipairs(source)do
   for cat=0,2 do
    if #u.reports.log[cat]>0 then
     total_rows=total_rows+1
     if total_rows>16384 then return {ok=false,message='Unit list exceeds 16384 rows'}end
     counts[cat+1]=counts[cat+1]+1
     hash=integer(integer(hash,u.id),cat)
     if cat==category and (unit<0 or unit==u.id)then selected[#selected+1]=u end
    end
   end
  end
  local revision=hash & 0x7fffffffffffffff;if revision==0 then revision=1 end
  if expected~=0 and expected~=revision then return {ok=false,message='List changed; refresh'}end
  if cursor>#selected then return {ok=false,message='Unit list cursor exceeds row count'}end
  local rows={};local stop=math.min(cursor+64,#selected)
  for i=cursor+1,stop do rows[#rows+1]=row(selected[i],category)end
  return {ok=true,view=2,unit_id=unit,unit_category=category,cursor=cursor,units=rows,total=#selected,
   next_cursor=stop<#selected and stop or 0,list_revision=revision,unit_counts=counts}
 end,row
end
