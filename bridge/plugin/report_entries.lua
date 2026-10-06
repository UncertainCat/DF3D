-- Explicit alert references. Preserve each source sequence; reports precede units
-- in the presentation, including duplicate references. Missing reports are returned separately, never invented.
return function(report_row,unit_row)
 assert(type(report_row)=='function' and type(unit_row)=='function')
 return function(a)
  local ids=a.ids or {};local refs=a.units or {}
  if #ids>64 or #refs>64 then return {ok=false,message='Too many report entries'}end
  if #ids+#refs==0 then return {ok=false,message='No report entries requested'}end
  for _,id in ipairs(ids)do
   if math.type(id)~='integer' or id<0 then return {ok=false,message='Invalid report identity'}end
  end
  for _,ref in ipairs(refs)do
   if math.type(ref.unit_id)~='integer' or ref.unit_id<0 or math.type(ref.category)~='integer' or ref.category<0 or ref.category>2 then return {ok=false,message='Invalid unit report reference'}end
  end
  local result={ok=true,message='',view=4,reports={},units={},missing_ids={}}
  -- Native popup text is not limited to 2048 bytes. Share the existing 128 KiB
  -- reply budget across requested references; singleton reads can retrieve the
  -- full mapped row (up to the common 16 KiB row limit). Preserve duplicates.
  local text_limit=math.min(16384,131072//math.max(1,#ids))
  for _,id in ipairs(ids)do
   local r=df.report.find(id)
   if r then
    local value=report_row(r)
    if #value.text>text_limit then
     local stop=text_limit
     while stop>0 and value.text:byte(stop+1)>=128 and value.text:byte(stop+1)<192 do stop=stop-1 end
     value.text=value.text:sub(1,stop);value.text_complete=false
    end
    result.reports[#result.reports+1]=value
   else result.missing_ids[#result.missing_ids+1]=id end
  end
  for _,ref in ipairs(refs)do
   local u=df.unit.find(ref.unit_id)
   if u then result.units[#result.units+1]=unit_row(u,ref.category)end
  end
  return result
 end
end
