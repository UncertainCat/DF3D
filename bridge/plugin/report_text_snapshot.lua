-- A retained, pointer-free full-text value. Independent of tab/list snapshots.
-- Byte cursors refer to UTF-8, never the native encoding. Helper lifetime is the
-- fortress/bridge epoch; reset invalidates handles without reusing revisions.
return function(map_row)
 assert(type(map_row)=='function')
 local snapshot;local revision=0
 local MAX_BYTES=32*1024*1024
 local PAGE_BYTES=16384
 local function copy(value)
  if type(value)~='table' then
   assert(type(value)=='number' or type(value)=='boolean' or type(value)=='string' or value==nil,'Snapshot contains non-value data')
   return value
  end
  local out={};for k,v in pairs(value)do out[copy(k)]=copy(v)end;return out
 end
 local function fail(message)return {ok=false,message=message}end
 local function continuation(byte)return byte and byte>=128 and byte<192 end
 local function read(a)
  local id=a.id;local cursor=a.cursor or 0;local expected=a.expected_list_revision or 0
  if math.type(id)~='integer' or id<0 then return fail('Invalid report identity')end
  if math.type(cursor)~='integer' or cursor<0 or cursor>MAX_BYTES then return fail('Invalid report text cursor')end
  if math.type(expected)~='integer' or expected<0 then return fail('Invalid report text revision')end
  if expected==0 then
   if cursor~=0 then return fail('Report text capture requires cursor zero')end
   local source=df.report.find(id)
   if not source then return fail('Report no longer exists')end
   local raw=source.text
   if #raw>MAX_BYTES then return fail('Report text exceeds 32 MiB')end
   local text=dfhack.df2utf(raw)
   if #text>MAX_BYTES then return fail('Report text exceeds 32 MiB')end
   if not utf8.len(text) then return fail('Report text is not valid UTF-8')end
   local value=copy(map_row(source));value.text=text
   if value.id~=id then return fail('Report identity changed')end
   if revision==math.maxinteger then return fail('Report text revision exhausted')end
   revision=revision+1;snapshot=value
  elseif not snapshot or expected~=revision or id~=snapshot.id then
   return fail('Report text snapshot expired')
  end
  local text=snapshot.text
  if (cursor>=#text and cursor>0) or continuation(text:byte(cursor+1)) then return fail('Invalid report text cursor')end
  local stop=math.min(cursor+PAGE_BYTES,#text)
  while stop>cursor and continuation(text:byte(stop+1))do stop=stop-1 end
  local value=copy(snapshot);value.text=text:sub(cursor+1,stop)
  -- A suffix is never a complete report, including the terminal page.
  value.text_complete=cursor==0 and stop==#text
  return {ok=true,message='',view=5,reports={value},cursor=cursor,
   next_cursor=stop<#text and stop or 0,total=#text,list_revision=revision}
 end
 return read,function()snapshot=nil end
end
