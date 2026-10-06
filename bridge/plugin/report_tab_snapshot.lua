-- Pointer-free ordinary-tab snapshot owned by the Reports management helper.
-- The helper releases retained values on epoch/bridge reset.
-- A zero revision captures once at a bridge safe point; continuations never read
-- mutable native vectors. One retained snapshot per management owner.
return function(classify, map_row)
 assert(type(classify)=='function' and type(map_row)=='function')
 local snapshot;local revision=0
 local MAX_BYTES=32*1024*1024
 local function copy(value)
  if type(value)~='table' then
   assert(type(value)=='number' or type(value)=='boolean' or type(value)=='string' or value==nil,'Snapshot contains non-value data')
   return value
  end
  local out={};for k,v in pairs(value)do out[copy(k)]=copy(v)end;return out
 end
 local function capture()
  local status=df.global.world.status;local source=status.reports
  if #source>65536 then return nil,'Report list exceeds 65536 entries'end
  local result={tabs={},counts={},by_id={},trimmed=#source>0 and source[0].id-1 or status.next_report_id-1}
  for i=1,25 do result.counts[i]=0 end
  for i=1,22 do result.tabs[i]={}end
  local previous=-1;local bytes=0
  for _,r in ipairs(source)do
   if r.id<=previous then return nil,'Native report identities are not ordered'end
   previous=r.id
   local category=classify(df.announcement_type[r.type])
   if category==nil then return nil,'Unverified native report type: '..tostring(r.type)end
   if category>0 then
    local value=map_row(r)
    local raw=r.text
    if #raw>MAX_BYTES then return nil,'Report snapshot exceeds 32 MiB'end
    local text=dfhack.df2utf(raw)
    if #text>MAX_BYTES then return nil,'Report snapshot exceeds 32 MiB'end
    if not utf8.len(text) then return nil,'Report text is not valid UTF-8'end
    value.text=text;value.text_complete=true
    -- Accounted payload budget: fixed charge plus text, not a Lua heap measurement.
    bytes=bytes+#value.text+512
    if bytes>MAX_BYTES then return nil,'Report snapshot exceeds 32 MiB'end
    value=copy(value)
    result.by_id[r.id]={row=value,category=category}
    result.tabs[1][#result.tabs[1]+1]=value
    result.tabs[category][#result.tabs[category]+1]=value
    result.counts[1]=result.counts[1]+1;result.counts[category]=result.counts[category]+1
   end
  end
  for _,u in ipairs(df.global.world.units.all)do
   for category=0,2 do if #u.reports.log[category]>0 then result.counts[23+category]=result.counts[23+category]+1 end end
  end
  return result
 end
 local function read(a)
  local tab=a.tab or 0;local expected=a.expected_list_revision or 0
  local after=a.after_id or -1;local before=a.before_id or -1
  if math.type(tab)~='integer' or tab<1 or tab>22 then return {ok=false,message='Unsupported report tab'}end
  if math.type(expected)~='integer' or expected<0 then return {ok=false,message='Invalid report snapshot revision'}end
  if math.type(after)~='integer' or math.type(before)~='integer' or after< -1 or before< -1 or
   (after>=0 and 1 or 0)+(before>=0 and 1 or 0)+(a.from_end and 1 or 0)>1 then return {ok=false,message='Invalid report snapshot cursor'}end
  if expected==0 then
   local fresh,err=capture();if not fresh then return {ok=false,message=err}end
   if revision==math.maxinteger then return {ok=false,message='Report snapshot revision exhausted'}end
   revision=revision+1;snapshot=fresh
  elseif not snapshot or expected~=revision then return {ok=false,message='Report snapshot expired'}end
  local selected=snapshot.tabs[tab]
  local function boundary(id)
   local lo,hi=1,#selected+1
   while lo<hi do local mid=(lo+hi)//2;if selected[mid].id<id then lo=mid+1 else hi=mid end end
   return lo
  end
  local backwards=a.from_end or before>=0
  local index=backwards and (before>=0 and boundary(before)-1 or #selected) or (after>=0 and boundary(after+1) or 1)
  local rows={};local bytes=0;local first,last
  while index>=1 and index<=#selected and #rows<64 do
   local value=copy(selected[index])
   if #value.text>16384 then
    local stop=16384
    while value.text:byte(stop+1)>=128 and value.text:byte(stop+1)<192 do stop=stop-1 end
    value.text=value.text:sub(1,stop);value.text_complete=false
   end
   if bytes+#value.text>131072 then break end
   rows[#rows+1]=value;bytes=bytes+#value.text
   first=first and math.min(first,index) or index;last=last and math.max(last,index) or index
   index=index+(backwards and -1 or 1)
  end
  if backwards then for i=1,#rows//2 do rows[i],rows[#rows-i+1]=rows[#rows-i+1],rows[i]end end
  local trimmed=snapshot.trimmed
  return {ok=true,message="",view=1,tab=tab,reports=rows,total=#selected,tab_counts=copy(snapshot.counts),list_revision=revision,
   after_id=after,from_end=a.from_end or false,announcements_only=false,trimmed_through=trimmed,
   next_before_id=first and first>1 and selected[first].id or -1,
   next_after_id=last and last<#selected and selected[last].id or -1,
   gap=(after>=0 and after<trimmed) or (before>=0 and trimmed>=0 and (not first or first==1))}
 end
 -- Reset invalidates old handles even if another snapshot is later opened.
 local function reset()snapshot=nil end
 local function read_text(a)
  local tab=a.tab or 0;local expected=a.expected_list_revision or 0
  local cursor=a.cursor or 0;local id=a.id
  if math.type(tab)~='integer' or tab<1 or tab>22 then return {ok=false,message='Unsupported report tab'}end
  if math.type(expected)~='integer' or expected<=0 or not snapshot or expected~=revision then return {ok=false,message='Report snapshot expired'}end
  if math.type(id)~='integer' or id<0 then return {ok=false,message='Invalid report identity'}end
  local retained=snapshot.by_id[id]
  if not retained or (tab~=1 and tab~=retained.category) then return {ok=false,message='Report is not in retained tab'}end
  local text=retained.row.text
  local function continuation(byte)return byte and byte>=128 and byte<192 end
  if math.type(cursor)~='integer' or cursor<0 or (cursor>=#text and cursor>0) or continuation(text:byte(cursor+1)) then return {ok=false,message='Invalid report text cursor'}end
  local stop=math.min(cursor+16384,#text)
  while stop>cursor and continuation(text:byte(stop+1))do stop=stop-1 end
  local value=copy(retained.row);value.text=text:sub(cursor+1,stop)
  value.text_complete=cursor==0 and stop==#text
  return {ok=true,message='',view=5,tab=tab,reports={value},cursor=cursor,
   next_cursor=stop<#text and stop or 0,total=#text,list_revision=revision}
 end
 return read,reset,read_text
end
