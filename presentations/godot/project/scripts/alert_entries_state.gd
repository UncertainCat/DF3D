extends RefCounted
# Native source order/duplicate/expiry evidence: fixtures/reports/alert_entries.json.
# Internal loading state has no product copy. Partial session references and text
# requiring paging stay unpublished until the complete retained value is assembled.
signal changed
signal dismissed
signal request_cancelled
signal request_requested(data:Dictionary,token:int)
var opened:=false
var epoch:=0
var generation:=0
var rows:Array=[]
var pending:Dictionary={}
var loaded:=false
var complete:=false
var failed:=false
var read_retry_needed:=false
var _retry_text:Dictionary={}
var unit_id:=-1
var unit_category:=-1
var _group_rows:Array=[]
var _group_selector:Dictionary={}
var _group_revision:=0
var _group_cursor:=0
var _group_total:=-1
var _group_more:=false
var _group_seen_units:=false
var _log_cursor:=-1
var _log_more:=false
var _log_revision:=0
var _unit_text
var _reports:Array=[]
var _units:Array=[]
var _report_cursor:=0
var _unit_cursor:=0
var _staged:Array=[]
var _resolve:Array=[]
var _resolved:Dictionary={}
var _source_complete:=false
var _text:Dictionary={}
var _text_bytes:=PackedByteArray()

func set_epoch(value:int) -> void:
 if value==epoch:return
 close();epoch=value

func open(group:Dictionary) -> void:
 _reset()
 opened=true;loaded=false;complete=false;failed=false
 if group.has("category") or bool(group.get("alert_button",false)):
  _group_selector={"notification_category":int(group.get("category",-1)),"alert_button":bool(group.get("alert_button",false))}
  _group_more=true;_source_complete=true;_next();return
 # Explicit reference reads remain available independently of native group opens.
 _reports=group.get("report_ids",[]).duplicate(true)
 _units=group.get("unit_reports",[]).duplicate(true)
 _source_complete=bool(group.get("complete",false)) and int(group.get("report_count",_reports.size()))==_reports.size() and int(group.get("unit_report_count",_units.size()))==_units.size()
 _next()

func close() -> void:
 _reset();changed.emit();dismissed.emit()

func back() -> void:
 if unit_id<0:close();return
 read_retry_needed=false;_retry_text={}
 generation+=1;pending={};_clear_text();request_cancelled.emit()
 unit_id=-1;unit_category=-1;_log_revision=0;_log_more=false;_resolve=[];_resolved={}
 rows=_group_rows.duplicate();_staged=rows.duplicate();loaded=true;complete=true;failed=false
 changed.emit()

func open_unit(id:int,category:int) -> bool:
 if not opened or not complete or unit_id>=0:return false
 var found:=false
 for entry in rows:
  if entry.kind=="unit" and int(entry.data.unit_id)==id and int(entry.data.category)==category:found=true;break
 if not found:return false
 _group_rows=rows.duplicate();unit_id=id;unit_category=category
 rows=[];_staged=[];_resolve=[];_resolved={};loaded=false;complete=false;failed=false
 _log_revision=0;_log_cursor=-1;_log_more=true;_source_complete=true;_next();return true

func _reset() -> void:
 read_retry_needed=false;_retry_text={}
 _clear_text()
 _group_selector={};_group_revision=0;_group_cursor=0;_group_total=-1;_group_more=false;_group_seen_units=false
 generation+=1;pending={};opened=false;rows=[];loaded=false;complete=false;failed=false
 _reports=[];_units=[];_report_cursor=0;_unit_cursor=0;_staged=[];_resolve=[];_resolved={};_source_complete=false
 unit_id=-1;unit_category=-1;_group_rows=[];_log_cursor=-1;_log_more=false;_log_revision=0
 request_cancelled.emit()

func _send(request:Dictionary,mode:String) -> void:
 read_retry_needed=false;_retry_text={}
 generation+=1;pending={"request":request.duplicate(true),"mode":mode}
 request_requested.emit(request,generation);changed.emit()

func _next() -> void:
 if not opened:return
 if unit_id>=0 and _log_more:
  _send({"action":34,"view":3,"unit_id":unit_id,"unit_category":unit_category,"after_id":_log_cursor,"expected_list_revision":_log_revision},"log");return
 if unit_id<0 and _group_more:
  var request:Dictionary=_group_selector.duplicate()
  request.merge({"action":34,"view":6,"cursor":_group_cursor,"expected_list_revision":_group_revision})
  _send(request,"group");return
 if _report_cursor<_reports.size():
  var ids:Array=_reports.slice(_report_cursor,mini(_report_cursor+64,_reports.size()))
  _send({"action":35,"view":4,"ids":ids},"reports");return
 if _unit_cursor<_units.size():
  var units:Array=_units.slice(_unit_cursor,mini(_unit_cursor+64,_units.size()))
  _send({"action":35,"view":4,"units":units},"units");return
 if not _text.is_empty():
  _send({"action":35,"view":5,"id":_text.id,"cursor":_text_bytes.size(),"expected_list_revision":_text.revision},"text");return
 if not _resolve.is_empty():
  if unit_id>=0 or not _group_selector.is_empty():
   for entry in _staged:
    if entry.kind=="report" and int(entry.data.id)==int(_resolve[0]):
     var in_log:bool=unit_id>=0
     _unit_text=preload("res://scripts/report_text_assembly.gd").new(entry.data,0,_log_revision if in_log else _group_revision,unit_id,unit_category,int(_group_selector.get("notification_category",-1)) if not in_log else -1,bool(_group_selector.get("alert_button",false)) if not in_log else false)
     _send(_unit_text.request(),"unit_text");return
   failed=true;changed.emit();return
  _send({"action":35,"view":4,"ids":[_resolve[0]]},"resolve");return
 # Published rows are immutable; preserve shared resolved values across duplicates.
 rows=_staged.duplicate();loaded=true;complete=_source_complete
 for row in rows:
  if row.kind=="report" and not bool(row.data.get("text_complete",false)):complete=false
 changed.emit()

func accept(token:int,session:int,reply:Dictionary) -> bool:
 if not opened or pending.is_empty() or token!=generation or session!=epoch:return false
 if pending.mode=="unit_text":return _accept_unit_text(reply)
 if pending.mode=="group":return _accept_group(reply)
 if pending.mode=="log":return _accept_log(reply)
 if pending.mode=="text":return _accept_text(reply)
 if int(reply.get("view",-1))!=4:return false
 var reports:Array=reply.get("reports",[])
 var units:Array=reply.get("units",[])
 var mode:String=pending.mode
 # Receipt identities must be an ordered subsequence of the exact requested
 # references. Omitted expired identities are permitted; extras/reordering aren't.
 var requested:Array=pending.request.get("units",[]) if mode=="units" else pending.request.get("ids",[])
 var incoming:Array=units if mode=="units" else reports
 if (mode=="units" and not reports.is_empty()) or (mode!="units" and not units.is_empty()):return false
 var index:=0
 for row in incoming:
  var found:=false
  while index<requested.size():
   var target=requested[index];index+=1
   if mode=="units":found=int(row.get("unit_id",-1))==int(target.unit_id) and int(row.get("category",-1))==int(target.category)
   else:found=int(row.get("id",-1))==int(target)
   if found:break
  if not found:return false
 if mode=="resolve":
  var id:int=int(_resolve.pop_front());_resolved[id]=true
  if not reports.is_empty() and not bool(reports[0].get("text_complete",false)):
   _text={"id":id,"revision":0,"total":0,"metadata":{}};_text_bytes=PackedByteArray()
   pending={};_next();return true
  # A missing report during resolution is omitted just like an initially stale
  # reference. Replace every duplicate with the same resolved value.
  for i in range(_staged.size()-1,-1,-1):
   if _staged[i].kind=="report" and int(_staged[i].data.id)==id:
    if reports.is_empty():_staged.remove_at(i)
    else:_staged[i].data=reports[0].duplicate(true)
 elif mode=="reports":
  for row in reports:
   _staged.append({"kind":"report","data":row.duplicate(true)})
   var id:int=int(row.id)
   if not bool(row.get("text_complete",false)) and not _resolve.has(id) and not _resolved.has(id):_resolve.append(id)
  _report_cursor+=requested.size()
 else:
  for row in units:_staged.append({"kind":"unit","data":row.duplicate(true)})
  _unit_cursor+=requested.size()
 pending={};_next();return true

func reject(token:int) -> void:
 if token!=generation or pending.is_empty():return
 _retry_text=_text.duplicate(true);read_retry_needed=true
 pending={};_clear_text();failed=true;complete=false;loaded=false;changed.emit()

func retry_read() -> bool:
 if not opened or not pending.is_empty() or not read_retry_needed:return false
 _text=_retry_text;failed=false
 # Group/log cursors and incomplete IDs advance only after accepted receipts.
 # Retained Text restarts at byte zero on the same owner; explicit Text keeps
 # its acquired independent revision while discarding incomplete bytes.
 _next();return true

func _accept_log(reply:Dictionary) -> bool:
 if int(reply.get("view",-1))!=3 or int(reply.get("unit_id",-1))!=unit_id or int(reply.get("unit_category",-1))!=unit_category:return false
 var revision:int=int(reply.get("list_revision",0))
 if revision<=0 or (_log_revision>0 and revision!=_log_revision):return false
 var incoming:Array=reply.get("reports",[])
 var previous:=_log_cursor
 for row in incoming:
  if int(row.get("id",-1))<=previous:return false
  previous=int(row.id)
 var next:int=int(reply.get("next_after_id",-1))
 if next>=0 and (incoming.is_empty() or next!=previous or next<=_log_cursor):return false
 for row in incoming:
  _staged.append({"kind":"report","data":row.duplicate(true)})
  if not bool(row.get("text_complete",false)) and not _resolve.has(int(row.id)):_resolve.append(int(row.id))
 _log_revision=revision;_log_cursor=next;_log_more=next>=0;pending={};_next();return true

func _clear_text() -> void:
 _text={};_text_bytes=PackedByteArray();_unit_text=null

func _accept_text(reply:Dictionary) -> bool:
 if int(reply.get("view",-1))!=5 or _text.is_empty():return false
 var incoming:Array=reply.get("reports",[])
 if incoming.size()!=1 or not reply.get("units",[]).is_empty() or not reply.get("missing_ids",[]).is_empty():return false
 var row:Dictionary=incoming[0]
 if int(row.get("id",-1))!=int(_text.id):return false
 var cursor:int=int(reply.get("cursor",-1));var total:int=int(reply.get("total",-1))
 var revision:int=int(reply.get("list_revision",0));var next:int=int(reply.get("next_cursor",-1))
 var chunk:PackedByteArray=str(row.get("text","")).to_utf8_buffer()
 if cursor!=_text_bytes.size() or total<0 or total>33554432 or revision<=0 or chunk.size()>16384:return false
 var end:int=cursor+chunk.size()
 if end>total or (total>0 and chunk.is_empty()) or next!=(end if end<total else 0):return false
 if bool(row.get("text_complete",false))!=(cursor==0 and end==total):return false
 var metadata:Dictionary=row.duplicate(true);metadata.erase("text");metadata.erase("text_complete")
 if int(_text.revision)!=0 and (revision!=int(_text.revision) or total!=int(_text.total) or metadata!=_text.metadata):return false
 _text.revision=revision;_text.total=total;_text.metadata=metadata
 _text_bytes.append_array(chunk)
 if next==0:
  var resolved:Dictionary=metadata.duplicate(true)
  resolved.text=_text_bytes.get_string_from_utf8();resolved.text_complete=true
  for entry in _staged:
   if entry.kind=="report" and int(entry.data.id)==int(_text.id):entry.data=resolved
  _clear_text()
 pending={};_next();return true

func _accept_unit_text(reply:Dictionary) -> bool:
 if _unit_text==null or not _unit_text.accept(reply):return false
 if not _unit_text.complete:
  _send(_unit_text.request(),"unit_text");return true
 var id:int=int(_resolve.pop_front());_resolved[id]=true
 var value:Dictionary=_unit_text.result()
 for entry in _staged:
  if entry.kind=="report" and int(entry.data.id)==id:entry.data=value
 _unit_text=null;pending={};_next();return true

func _accept_group(reply:Dictionary) -> bool:
 if int(reply.get("view",-1))!=6 or int(reply.get("notification_category",-1))!=int(_group_selector.notification_category) or bool(reply.get("alert_button",false))!=bool(_group_selector.alert_button):return false
 if int(reply.get("unit_id",-1))!=-1 or int(reply.get("unit_category",-1))!=-1 or int(reply.get("tab",0))!=0 or not reply.get("missing_ids",[]).is_empty():return false
 var revision:int=int(reply.get("list_revision",0));var cursor:int=int(reply.get("cursor",-1))
 var total:int=int(reply.get("total",-1));var next:int=int(reply.get("next_cursor",-1))
 var reports:Array=reply.get("reports",[]);var units:Array=reply.get("units",[])
 var count:int=reports.size()+units.size();var end:int=cursor+count
 if revision<=0 or (_group_revision>0 and revision!=_group_revision) or cursor!=_group_cursor or total<0 or total>65536 or (_group_total>=0 and total!=_group_total):return false
 if count>64 or end>total or (total>0 and count==0) or next!=(end if end<total else 0) or (_group_seen_units and not reports.is_empty()):return false
 for row in reports:
  if int(row.get("id",-1))<0:return false
 for row in units:
  if int(row.get("unit_id",-1))<0 or int(row.get("category",-1))<0 or int(row.get("category",-1))>2:return false
 for row in reports:
  _staged.append({"kind":"report","data":row.duplicate(true)})
  if not bool(row.get("text_complete",false)) and not _resolve.has(int(row.id)):_resolve.append(int(row.id))
 for row in units:_staged.append({"kind":"unit","data":row.duplicate(true)})
 _group_revision=revision;_group_total=total;_group_cursor=next;_group_more=next>0;_group_seen_units=_group_seen_units or not units.is_empty()
 pending={};_next();return true
