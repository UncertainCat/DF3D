-- Unit logs are read afresh at the bridge safe point. No native pointer survives
-- the request. Expired report references are omitted, but do not remove unit rows.
return function(row)
 assert(type(row)=='function')
 return function(a)
  local id=a.unit_id or -1;local category=a.unit_category or -1
  local after=a.after_id or -1;local before=a.before_id or -1
  if math.type(id)~='integer' or id<0 then return {ok=false,message='Unit log needs a unit'}end
  if math.type(category)~='integer' or category<0 or category>2 then return {ok=false,message='Unit category must be combat, sparring or hunting'}end
  if math.type(after)~='integer' or after< -1 or math.type(before)~='integer' or before< -1 then return {ok=false,message='Invalid unit log cursor'}end
  if (after>=0 and 1 or 0)+(before>=0 and 1 or 0)+(a.from_end and 1 or 0)>1 then return {ok=false,message='Only one report cursor may be set'}end
  local u=df.unit.find(id)
  if not u then return {ok=false,message='Unit no longer exists'}end
  local source=u.reports.log[category]
  if #source>65536 then return {ok=false,message='Unit log exceeds 65536 entries'}end
  local selected={};local previous=-1;local trimmed=-1;local seen=false
  if #source>0 then trimmed=source[0]-1 end
  for _,ref in ipairs(source)do
   if ref<0 or ref<=previous then return {ok=false,message='Native unit log identities are not ordered'}end
   previous=ref
   local r=df.report.find(ref)
   if r then selected[#selected+1]=r;seen=true
   elseif not seen then trimmed=ref end
  end
  local function boundary(value)
   local lo,hi=1,#selected+1
   while lo<hi do local mid=(lo+hi)//2;if selected[mid].id<value then lo=mid+1 else hi=mid end end
   return lo
  end
  local backwards=a.from_end or before>=0
  local index=backwards and (before>=0 and boundary(before)-1 or #selected) or (after>=0 and boundary(after+1) or 1)
  local result={};local bytes=0;local first,last
  while index>=1 and index<=#selected and #result<64 do
   local value=row(selected[index])
   if #value.text>16384 then return {ok=false,message='Report row exceeds text limit'}end
   if bytes+#value.text>131072 then break end
   result[#result+1]=value;bytes=bytes+#value.text
   first=first and math.min(first,index) or index;last=last and math.max(last,index) or index
   index=index+(backwards and -1 or 1)
  end
  if backwards then for i=1,#result//2 do result[i],result[#result-i+1]=result[#result-i+1],result[i]end end
  return {ok=true,view=3,unit_id=id,unit_category=category,after_id=after,from_end=a.from_end or false,
   reports=result,total=#selected,announcements_only=false,trimmed_through=trimmed,
   next_before_id=first and first>1 and selected[first].id or -1,
   next_after_id=last and last<#selected and selected[last].id or -1,
   gap=(after>=0 and after<trimmed) or (before>=0 and trimmed>=0 and (not first or first==1))}
 end
end
