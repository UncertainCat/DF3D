-- Retained unit-log values, independently owned from ordinary tabs and popups.
-- Refresh is explicit: existing rows never change; only newer identities append.
return function(map_row)
 assert(type(map_row)=='function')
 local snapshot;local revision=0
 local MAX_BYTES=32*1024*1024
 local function fail(message)return {ok=false,message=message}end
 local function copy(value)
  if type(value)~='table' then
   assert(type(value)=='number' or type(value)=='boolean' or type(value)=='string' or value==nil,'Snapshot contains non-value data')
   return value
  end
  local out={};for k,v in pairs(value)do out[copy(k)]=copy(v)end;return out
 end
 local function cut(text,cursor)
  local stop=math.min(cursor+16384,#text)
  while stop>cursor and text:byte(stop+1) and text:byte(stop+1)>=128 and text:byte(stop+1)<192 do stop=stop-1 end
  return text:sub(cursor+1,stop),stop
 end
 local function capture(id,category,old)
  local unit=df.unit.find(id);if not unit then return nil,'Unit no longer exists'end
  local source=unit.reports.log[category]
  if #source>65536 then return nil,'Unit log exceeds 65536 entries'end
  if old and old.source_count==#source then return old end
  local result={id=id,category=category,source_count=#source,rows={},by_id={},bytes=0,trimmed=#source>0 and source[0]-1 or -1}
  if old then
   result.bytes=old.bytes;result.trimmed=old.trimmed
   for _,row in ipairs(old.rows)do result.rows[#result.rows+1]=row;result.by_id[row.id]=row end
  end
  local tail=#result.rows>0 and result.rows[#result.rows].id or -1
  local previous=-1;local seen=false
  for _,ref in ipairs(source)do
   if ref<0 or ref<=previous then return nil,'Native unit log identities are not ordered'end
   previous=ref
   if ref>tail then
    local native=df.report.find(ref)
    if native then
     local raw=native.text
     if #raw>MAX_BYTES then return nil,'Unit log snapshot exceeds 32 MiB'end
     local text=dfhack.df2utf(raw)
     if #text>MAX_BYTES then return nil,'Unit log snapshot exceeds 32 MiB'end
     if not utf8.len(text) then return nil,'Report text is not valid UTF-8'end
     local row=copy(map_row(native));row.text=text;row.text_complete=true
     if row.id~=ref then return nil,'Report identity changed'end
     result.bytes=result.bytes+#text+512
     if result.bytes>MAX_BYTES then return nil,'Unit log snapshot exceeds 32 MiB'end
     if #result.rows>=65536 then return nil,'Retained unit log exceeds 65536 entries'end
     result.rows[#result.rows+1]=row;result.by_id[ref]=row;seen=true
    elseif not old and not seen then result.trimmed=ref end
   end
  end
  return result
 end
 local function selector(a)
  local id=a.unit_id or -1;local category=a.unit_category or -1
  if math.type(id)~='integer' or id<0 then return nil,nil,'Unit log needs a unit'end
  if math.type(category)~='integer' or category<0 or category>2 then return nil,nil,'Unit category must be combat, sparring or hunting'end
  return id,category
 end
 local function read(a)
  local id,category,error=selector(a);if error then return fail(error)end
  local expected=a.expected_list_revision or 0
  local after=a.after_id or -1;local before=a.before_id or -1
  if math.type(expected)~='integer' or expected<0 then return fail('Invalid unit log revision')end
  if math.type(after)~='integer' or after< -1 or math.type(before)~='integer' or before< -1 or
   (after>=0 and 1 or 0)+(before>=0 and 1 or 0)+(a.from_end and 1 or 0)>1 then return fail('Invalid unit log cursor')end
  if a.refresh~=nil and type(a.refresh)~='boolean' then return fail('Invalid unit log refresh')end
  if a.refresh and (expected==0 or before>=0 or a.from_end) then return fail('Refresh requires a retained forward log')end
  if expected==0 then
   local fresh,err=capture(id,category);if not fresh then return fail(err)end
   if revision==math.maxinteger then return fail('Unit log revision exhausted')end
   revision=revision+1;snapshot=fresh
  elseif not snapshot or expected~=revision or id~=snapshot.id or category~=snapshot.category then
   return fail('Unit log snapshot expired')
  elseif a.refresh then
   local fresh,err=capture(id,category,snapshot);if not fresh then return fail(err)end
   snapshot=fresh
  end
  local selected=snapshot.rows
  local function boundary(value)
   local lo,hi=1,#selected+1
   while lo<hi do local mid=(lo+hi)//2;if selected[mid].id<value then lo=mid+1 else hi=mid end end
   return lo
  end
  local backwards=a.from_end or before>=0
  local index=backwards and (before>=0 and boundary(before)-1 or #selected) or (after>=0 and boundary(after+1) or 1)
  local rows={};local bytes=0;local first,last
  while index>=1 and index<=#selected and #rows<64 do
   local value=copy(selected[index]);local text,stop=cut(value.text,0)
   value.text_complete=stop==#value.text;value.text=text
   if bytes+#text>131072 then break end
   rows[#rows+1]=value;bytes=bytes+#text
   first=first and math.min(first,index) or index;last=last and math.max(last,index) or index
   index=index+(backwards and -1 or 1)
  end
  if backwards then for i=1,#rows//2 do rows[i],rows[#rows-i+1]=rows[#rows-i+1],rows[i]end end
  local trimmed=snapshot.trimmed
  return {ok=true,message='',view=3,unit_id=id,unit_category=category,list_revision=revision,
   after_id=after,from_end=a.from_end or false,reports=rows,total=#selected,announcements_only=false,trimmed_through=trimmed,
   next_before_id=first and first>1 and selected[first].id or -1,
   next_after_id=last and last<#selected and selected[last].id or -1,
   gap=(after>=0 and after<trimmed) or (before>=0 and trimmed>=0 and (not first or first==1))}
 end
 local function read_text(a)
  local id,category,error=selector(a);if error then return fail(error)end
  local expected=a.expected_list_revision or 0;local cursor=a.cursor or 0;local report=a.id
  if math.type(expected)~='integer' or expected<=0 or not snapshot or expected~=revision or id~=snapshot.id or category~=snapshot.category then return fail('Unit log snapshot expired')end
  if math.type(report)~='integer' or report<0 then return fail('Invalid report identity')end
  local row=snapshot.by_id[report];if not row then return fail('Report is not in retained unit log')end
  if math.type(cursor)~='integer' or cursor<0 then return fail('Invalid report text cursor')end
  local text=row.text
  if cursor>=#text and cursor>0 then return fail('Invalid report text cursor')end
  local byte=text:byte(cursor+1)
  if byte and byte>=128 and byte<192 then return fail('Invalid report text cursor')end
  local chunk,stop=cut(text,cursor);local value=copy(row);value.text=chunk;value.text_complete=cursor==0 and stop==#text
  return {ok=true,message='',view=5,unit_id=id,unit_category=category,reports={value},cursor=cursor,
   next_cursor=stop<#text and stop or 0,total=#text,list_revision=revision}
 end
 return read,read_text,function()snapshot=nil end
end
