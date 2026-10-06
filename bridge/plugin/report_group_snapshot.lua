-- Whole-open alert contents. Staged helper: protocol/client wiring is separate.
-- Native vectors are read only during capture; retained pages own plain values.
return function(report_row,unit_row)
 assert(type(report_row)=='function' and type(unit_row)=='function')
 local snapshot;local revision=0
 local MAX_BYTES=32*1024*1024;local MAX_REFS=65536
 local function fail(message)return {ok=false,message=message}end
 local function copy(value)
  if type(value)~='table' then
   assert(type(value)=='number' or type(value)=='boolean' or type(value)=='string' or value==nil,'Snapshot contains non-value data')
   return value
  end
  local out={};for k,v in pairs(value)do out[copy(k)]=copy(v)end;return out
 end
 local function selector(a)
  local category=a.notification_category;if category==nil then category=-1 end
  local button=a.alert_button;if button==nil then button=false end
  if type(button)~='boolean' or math.type(category)~='integer' or
   (button and category~=-1) or (not button and (category<0 or category>36)) then return nil,nil,'Invalid alert group selector'end
  return category,button
 end
 local function capture(category,button)
  local status=df.global.world.status
  local ids,units,categories
  if button then ids=status.alert_button_announcement_id
  else
   for _,group in ipairs(status.announcement_alert)do
    if group.type==category then
     if ids then return nil,'Ambiguous alert group'end
     ids=group.announcement_id;units=group.report_unid;categories=group.report_unit_announcement_category
    end
   end
   if not ids then return nil,'Alert group no longer exists'end
  end
  if units and #units~=#categories then return nil,'Invalid native unit report references'end
  if #ids+(units and #units or 0)>MAX_REFS then return nil,'Alert group exceeds 65536 references'end
  local result={category=category,button=button,rows={},reports={},units={},bytes=0}
  local function charge(n)result.bytes=result.bytes+n;return result.bytes<=MAX_BYTES end
  for _,id in ipairs(ids)do
   if math.type(id)~='integer' or id<0 then return nil,'Invalid native report reference'end
   local value=result.reports[id]
   if value==nil then
    local native=df.report.find(id)
    if native then
     local raw=native.text
     if #raw>MAX_BYTES then return nil,'Alert snapshot exceeds 32 MiB'end
     local text=dfhack.df2utf(raw)
     if #text>MAX_BYTES or not charge(#text+512) then return nil,'Alert snapshot exceeds 32 MiB'end
     if not utf8.len(text)then return nil,'Report text is not valid UTF-8'end
     value=copy(report_row(native));value.text=text;value.text_complete=true
     if value.id~=id then return nil,'Report identity changed'end
    else value=false end
    result.reports[id]=value
   end
   if value then
    if not charge(16)then return nil,'Alert snapshot exceeds 32 MiB'end
    result.rows[#result.rows+1]={kind='report',value=value}
   end
  end
  if units then for i,id in ipairs(units)do
   local cat=categories[i]
   if math.type(id)~='integer' or id<0 or math.type(cat)~='integer' or cat<0 or cat>2 then return nil,'Invalid native unit report reference'end
   local key=id..':'..cat;local value=result.units[key]
   if value==nil then
    local native=df.unit.find(id)
    value=native and copy(unit_row(native,cat)) or false
    if value then
     if value.unit_id~=id or value.category~=cat then return nil,'Unit report identity changed'end
     if not charge(512+#(value.profession or '')+#(value.name or '')+#(value.error or ''))then return nil,'Alert snapshot exceeds 32 MiB'end
    end
    result.units[key]=value
   end
   if value then
    if not charge(16)then return nil,'Alert snapshot exceeds 32 MiB'end
    result.rows[#result.rows+1]={kind='unit',value=value}
   end
  end end
  return result
 end
 local function cut(text,cursor,limit)
  local stop=math.min(cursor+limit,#text)
  while stop>cursor and text:byte(stop+1) and text:byte(stop+1)>=128 and text:byte(stop+1)<192 do stop=stop-1 end
  return text:sub(cursor+1,stop),stop
 end
 local function matches(category,button,expected)
  return snapshot and expected==revision and snapshot.category==category and snapshot.button==button
 end
 local function read(a)
  local category,button,error=selector(a);if error then return fail(error)end
  local expected=a.expected_list_revision or 0;local cursor=a.cursor or 0
  if math.type(expected)~='integer' or expected<0 or math.type(cursor)~='integer' or cursor<0 or (expected==0 and cursor~=0)then return fail('Invalid alert snapshot cursor')end
  if expected==0 then
   local value,err=capture(category,button);if not value then return fail(err)end
   if revision==math.maxinteger then return fail('Alert snapshot revision exhausted')end
   snapshot=value;revision=revision+1
  elseif not matches(category,button,expected)then return fail('Alert snapshot expired')end
  if cursor>=#snapshot.rows and cursor>0 then return fail('Invalid alert snapshot cursor')end
  local result={ok=true,message='',view=6,notification_category=category,alert_button=button,cursor=cursor,total=#snapshot.rows,list_revision=revision,reports={},units={}}
  local bytes=0;local index=cursor+1
  while index<=#snapshot.rows and index<=cursor+64 do
   local entry=snapshot.rows[index];local value=copy(entry.value)
   if entry.kind=='report' then
    local text,stop=cut(value.text,0,16384)
    if bytes+#text>131072 then break end
    value.text_complete=stop==#value.text;value.text=text;bytes=bytes+#text
    result.reports[#result.reports+1]=value
   else result.units[#result.units+1]=value end
   index=index+1
  end
  result.next_cursor=index<=#snapshot.rows and index-1 or 0
  return result
 end
 local function text(a)
  local category,button,error=selector(a);if error then return fail(error)end
  local expected=a.expected_list_revision or 0
  if math.type(expected)~='integer' or expected<=0 or not matches(category,button,expected)then return fail('Alert snapshot expired')end
  if math.type(a.id)~='integer' or a.id<0 then return fail('Invalid report identity')end
  local value=snapshot.reports[a.id];if not value then return fail('Report is not in retained alert group')end
  local cursor=a.cursor or 0
  if math.type(cursor)~='integer' or cursor<0 or (cursor>0 and cursor>=#value.text)then return fail('Invalid report text cursor')end
  local byte=value.text:byte(cursor+1)
  if byte and byte>=128 and byte<192 then return fail('Invalid report text cursor')end
  local chunk,stop=cut(value.text,cursor,16384);local row=copy(value);row.text=chunk;row.text_complete=cursor==0 and stop==#value.text
  return {ok=true,message='',view=5,notification_category=category,alert_button=button,cursor=cursor,total=#value.text,next_cursor=stop<#value.text and stop or 0,list_revision=revision,reports={row}}
 end
 return read,text,function()snapshot=nil end
end
