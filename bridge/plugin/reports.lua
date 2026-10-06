local classify, make_tab_page, profession, make_unit_page, make_unit_log, make_entries, make_tab_snapshot, make_text_snapshot, make_group_snapshot = ...
assert(type(classify)=='function' and type(make_tab_page)=='function')
-- Bounded, read-only native reports. Never retain native report pointers across updates.
local scan
local function cut(text,limit)
 if #text<=limit then return text,true end
 local stop=limit
 while stop>0 and text:byte(stop+1)>=128 and text:byte(stop+1)<192 do stop=stop-1 end
 return text:sub(1,stop),false
end
local function row(r)
 local raw=r.text
 local text,complete=cut(dfhack.df2utf(raw:sub(1,16384)),16384)
 complete=complete and #raw<=16384
 local v={id=r.id,category=df.announcement_type[r.type] or 'Unknown',text=text,text_complete=complete,
 year=r.year,year_tick=r.time,repeat_count=r.repeat_count,continuation=r.flags.continuation,
 x=-1,y=-1,z=-1,x2=-1,y2=-1,z2=-1,position_visible=false,position2_visible=false}
 -- Native recenter uses stored coordinates, including NONE zooms and hidden/off-map targets.
 -- position_visible means a recenter target is present, not that terrain is revealed.
 -- Evidence: fixtures/reports/recenter.json; native coord absence uses x=-30000.
 local function zoom(kind)
  return kind and kind>=-1 and kind<=2 and kind+2 or 0
 end
 v.tab=classify(df.announcement_type[r.type]) or 0
 v.color=r.color and r.color>=0 and r.color<=15 and r.color or -1
 v.bright=r.bright or false;v.zoom_type=zoom(r.zoom_type);v.zoom_type2=zoom(r.zoom_type2)
 v.speaker_id=r.speaker_id or -1;v.position_hidden=false;v.position2_hidden=false
 local function position(p,suffix)
  if not p or p.x==-30000 then return end
  v['x'..suffix]=p.x;v['y'..suffix]=p.y;v['z'..suffix]=p.z
  v[suffix=='' and 'position_visible' or 'position2_visible']=true
  local flags=dfhack.maps.isValidTilePos(p) and dfhack.maps.getTileFlags(p)
  v[suffix=='' and 'position_hidden' or 'position2_hidden']=not flags or flags.hidden or false
 end
 position(r.pos,'');position(r.pos2,'2')
 return v
end
-- Fresh metadata reads are independent of the retained ordinary-tab snapshot.
local tab_page=make_tab_page(classify,row)
local tab_snapshot,_,tab_text=make_tab_snapshot(classify,row)
local unit_page,unit_row=make_unit_page(profession)
local unit_log,unit_text=make_unit_log(row)
local entries=make_entries(row,unit_row)
local text_snapshot=make_text_snapshot(row)
local group_snapshot,group_text=make_group_snapshot(row,unit_row)
return function(request)
 local a=request.report
 if a.view==1 then return tab_snapshot(a)end
 if a.view==6 then return group_snapshot(a)end
 if a.view==5 and ((a.notification_category or -1)>=0 or a.alert_button)then return group_text(a)end
 if a.view==4 then return entries(a)end
 if a.view==5 then return (a.unit_id and a.unit_id>=0 and unit_text or a.tab and a.tab>0 and tab_text or text_snapshot)(a)end
 if a.view==2 or a.view==3 then
  local result=a.view==2 and unit_page(a) or unit_log(a)
  if not result.ok then return result end
  local counts=tab_page{tab=1}
  if not counts.ok then return counts end
  result.tab_counts=counts.tab_counts;result.unit_counts=nil;result.message=""
  return result
 end
 if request.action==35 then
  local r=df.report.find(a.id)
  if not r then return {ok=false,message='Report no longer exists'}end
  return {ok=true,message='Native report',reports={row(r)},next_before_id=-1,announcements_only=a.announcements_only}
 end
 local source=a.announcements_only and df.global.world.status.announcements or df.global.world.status.reports
 -- Native vectors are chronological by monotonically assigned report ID.
 -- Find the exclusive ID cursor with a binary search, preserving native ID zero.
 if not scan or scan.seq~=request.seq then
  local lo,hi=0,#source
  if a.before_id>=0 then
   while lo<hi do local mid=(lo+hi)//2;if source[mid].id<a.before_id then lo=mid+1 else hi=mid end end
  else lo=#source end
  scan={seq=request.seq,before=a.before_id,index=lo-1,rows={},bytes=0,query=a.query:lower()}
 end
 if scan.before>=0 then
  local lo,hi=0,#source
  while lo<hi do local mid=(lo+hi)//2;if source[mid].id<scan.before then lo=mid+1 else hi=mid end end
  scan.index=lo-1
 end
 local inspected=0
 while scan.index>=0 and inspected<512 do
  -- Reports may expire between updates. Re-establish the last scanned ID boundary.
  if scan.index>=#source then scan.index=#source-1 end
  if scan.index<0 then break end
  local r=source[scan.index]
  if scan.before<0 or r.id<scan.before then
   local value=row(r)
   if scan.query=='' or tostring(r.id)==scan.query or value.text:lower():find(scan.query,1,true)then
    if #scan.rows>=16 or scan.bytes+#value.text>131072 then
     local result={ok=true,message='Native reports',reports=scan.rows,next_before_id=scan.before,announcements_only=a.announcements_only}
     scan=nil;return result
    end
    scan.rows[#scan.rows+1]=value;scan.bytes=scan.bytes+#value.text
   end
   scan.before=r.id
  end
  scan.index=scan.index-1;inspected=inspected+1
 end
 if scan.index>=0 then return {ok=true,pending=true,message='Searching native reports'}end
 local result={ok=true,message='Native reports',reports=scan.rows,next_before_id=-1,announcements_only=a.announcements_only}
 scan=nil;return result
end
