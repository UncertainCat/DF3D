-- Semantic Reports tab paging, evaluated at one bridge safe point.
-- No native widgets, viewscreens or retained DF pointers. Factory inputs are the
-- captured type classifier and the report-to-pointer-free-row mapper.
return function(classify, row)
assert(type(classify)=='function' and type(row)=='function')
return function(a)
 local tab=a.tab or 0
 local after=a.after_id or -1;local before=a.before_id or -1
 if tab<1 or tab>22 or math.type(tab)~='integer' then return {ok=false,message='Unsupported report tab'}end
 if (after>=0 and 1 or 0)+(before>=0 and 1 or 0)+(a.from_end and 1 or 0)>1 then
  return {ok=false,message='Only one report cursor may be set'}
 end
 local status=df.global.world.status
 local source=status.reports
 if #source>65536 then return {ok=false,message='Report list exceeds 65536 entries'}end
 local counts={};for i=1,25 do counts[i]=0 end
 local selected={};local previous=-1
 for _,r in ipairs(source) do
  if r.id<=previous then return {ok=false,message='Native report identities are not ordered'}end
  previous=r.id
  local category=classify(df.announcement_type[r.type])
  if category==nil then return {ok=false,message='Unverified native report type: '..tostring(r.type)}end
  if category>0 then
   counts[1]=counts[1]+1;counts[category]=counts[category]+1
   if tab==1 or tab==category then selected[#selected+1]=r end
  end
 end
 -- Native unit tabs retain rows even when their report IDs have expired.
 for _,u in ipairs(df.global.world.units.all)do
  for category=0,2 do
   if #u.reports.log[category]>0 then counts[23+category]=counts[23+category]+1 end
  end
 end
 local function boundary(id)
  local lo,hi=1,#selected+1
  while lo<hi do local mid=(lo+hi)//2;if selected[mid].id<id then lo=mid+1 else hi=mid end end
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
 if backwards then
  for i=1,#result//2 do result[i],result[#result-i+1]=result[#result-i+1],result[i]end
 end
 local trimmed=#source>0 and source[0].id-1 or status.next_report_id-1
 return {ok=true,message='Native reports',view=1,tab=tab,after_id=after,from_end=a.from_end or false,
  reports=result,tab_counts=counts,total=#selected,announcements_only=false,
  next_before_id=first and first>1 and selected[first].id or -1,
  next_after_id=last and last<#selected and selected[last].id or -1,
  trimmed_through=trimmed,
  gap=(after>=0 and after<trimmed) or (before>=0 and trimmed>=0 and (not first or first==1))}
end
end
