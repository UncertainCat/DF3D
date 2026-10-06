extends RefCounted
# Native labels: fixtures/reports/tab_membership.json.named_tab_capture.
# Row swaps/dim no-op/reopen: e7 r01,r05,r09 and findings items1,3.
signal changed
signal request_requested(data: Dictionary, token: int)
signal request_cancelled
signal pause_requested
signal recenter_requested(tile: Vector3i)
signal speaker_requested(unit_id:int)
signal dismissed
const LABELS = ["All", "General", "World", "Environment", "Arrivals", "Attacks", "Trade", "Nobles", "Animal", "Life changes", "Strange moods", "Profession changes", "Military", "Mental state", "Masterpieces", "Job failures", "Death", "Ghosts", "Wildlife", "Labor", "Crime", "Curses", "Combat", "Sparring", "Hunting"]
const INITIAL_ROWS = [[18,19,20,21,22,23,24,25],[11,12,13,14,15,16,17],[1,2,3,4,5,6,7,8,9,10]]
var tab_rows: Array = INITIAL_ROWS.duplicate(true)
var selected_tab := 1
var counts: Array = []
var opened := false
# Release initialization defect: native captures contain noncanonical bool bytes.
# Keep an owned explicit value; see pause_on_new.json.release_initialization_policy.
var pause_on_new:=false
var unit_log_length:=-1
var log_refresh_needed:=false
var unit_id := -1
var unit_category := -1
var rows: Array = []
var total:=0
var log_start:=0
var log_requested:=0
var log_first:=0
var first_row:=0
var requested_row:=0
const PAGE_ROWS=15
var next_before := -1
var next_after := -1
var next_cursor := 0
var list_revision := 0
# Separate from UnitList revisions; retained for the whole Reports open lifetime.
var tab_revision := 0
var log_revision:=0
var log_initial_needed:=false
var epoch := 0
var generation := 0
var pending: Dictionary = {}
var read_retry:Dictionary={}
var tab_cache:Dictionary={}
var _text_reply:Dictionary={}
var _text_pending:Dictionary={}
var _text_index:=0
var _text_assembly


func set_epoch(value: int) -> void:
 if value==epoch:return
 _clear_text()
 read_retry={};tab_cache.clear();tab_revision=0;log_revision=0;log_initial_needed=false
 epoch=value;pause_on_new=false;unit_log_length=-1;log_refresh_needed=false;generation+=1;pending={};rows=[];log_start=0;log_requested=0;log_first=0;total=0;first_row=0;requested_row=0;counts=[]
 unit_id=-1;unit_category=-1;list_revision=0
 next_before=-1;next_after=-1;next_cursor=0
 changed.emit()

func open() -> void:
 _clear_text()
 read_retry={};tab_cache.clear();tab_revision=0;log_revision=0;log_initial_needed=false
 log_refresh_needed=false
 opened=true;unit_id=-1;unit_category=-1;rows=[];log_start=0;log_requested=0;log_first=0;total=0;first_row=0;requested_row=0
 _request_selection()

func close() -> void:
 _clear_text()
 read_retry={};tab_cache.clear();tab_revision=0;log_revision=0;log_initial_needed=false
 log_refresh_needed=false
 opened=false;generation+=1;pending={};rows=[];log_start=0;log_requested=0;log_first=0;total=0;first_row=0;requested_row=0
 # Native remembers tab selection and its row arrangement across reopening.
 changed.emit();dismissed.emit()

func choose_tab(tab: int) -> bool:
 if not opened or unit_id>=0 or tab<1 or tab>25 or counts.size()!=25 or int(counts[tab-1])==0:return false
 if tab==selected_tab:return false
 # Native074957 preserves each ordinary tab's rows and scroll until close.
 if selected_tab<=22 and pending.is_empty() and read_retry.get("mode","") not in ["replace","snapshot"]:
  tab_cache[selected_tab]={"rows":rows.duplicate(true),"total":total,"first":first_row,"requested":requested_row,"before":next_before,"after":next_after}
 _clear_text();read_retry={}
 selected_tab=tab
 for i in tab_rows.size():
  if tab in tab_rows[i]:
   var bottom: Array=tab_rows[2];tab_rows[2]=tab_rows[i];tab_rows[i]=bottom;break
 rows=[];log_start=0;log_requested=0;log_first=0;total=0;first_row=0;requested_row=0;list_revision=0
 if tab_cache.has(tab):
  generation+=1;pending={};request_cancelled.emit()
  var cached:Dictionary=tab_cache[tab]
  rows=cached.rows.duplicate(true);total=cached.total;first_row=cached.first;requested_row=cached.requested
  next_before=cached.before;next_after=cached.after;next_cursor=0
  changed.emit();return true
 _request_selection();return true

func open_unit(id: int, category: int) -> bool:
 if not opened or id<0 or category<0 or category>2:return false
 var found:=false
 for row in rows:
  if int(row.get("unit_id",-1))==id and int(row.get("category",-1))==category:found=true;unit_log_length=int(row.get("log_count",-1));break
 if not found:return false
 log_refresh_needed=false
 log_revision=0;log_initial_needed=true
 unit_id=id;unit_category=category;rows=[];log_start=0;log_requested=0;log_first=0;total=0;first_row=0;requested_row=0
 _send({"action":34,"view":3,"unit_id":id,"unit_category":category,"from_end":true},"replace")
 return true

func _request_selection() -> void:
 if selected_tab<=22:_send({"action":34,"view":1,"tab":selected_tab,"expected_list_revision":tab_revision},"replace")
 elif tab_revision==0:_send({"action":34,"view":1,"tab":1},"snapshot")
 else:_send({"action":34,"view":2,"unit_category":selected_tab-23},"replace")

func next_page() -> bool:
 if not opened or not pending.is_empty():return false
 if unit_id>=0:
  if next_after<0:return false
  _send({"action":34,"view":3,"unit_id":unit_id,"unit_category":unit_category,"after_id":next_after,"expected_list_revision":log_revision},"append")
 elif selected_tab<=22:
  if next_after<0:return false
  _send({"action":34,"view":1,"tab":selected_tab,"after_id":next_after,"expected_list_revision":tab_revision},"append")
 else:
  if next_cursor==0:return false
  _send({"action":34,"view":2,"unit_category":selected_tab-23,"cursor":next_cursor,"expected_list_revision":list_revision},"append")
 return true

func previous_page() -> bool:
 if not opened or not pending.is_empty() or unit_id<0 or next_before<0:return false
 _send({"action":34,"view":3,"unit_id":unit_id,"unit_category":unit_category,"before_id":next_before,"expected_list_revision":log_revision},"prepend")
 return true

func _send(data: Dictionary, mode: String) -> void:
 read_retry={}
 if mode!="text":_clear_text()
 generation+=1;pending={"request":data.duplicate(true),"mode":mode,"epoch":epoch}
 request_requested.emit(data,generation);changed.emit()

func retry_initial_log() -> void:
 if not opened or unit_id<0 or not log_initial_needed or not pending.is_empty():return
 # If capture succeeded but text retrieval failed, retry against that same
 # retained value. A still-unpublished initial read may otherwise capture anew.
 _send({"action":34,"view":3,"unit_id":unit_id,"unit_category":unit_category,"from_end":true,"expected_list_revision":log_revision},"replace")

func refresh_new_reports() -> void:
 if not opened or unit_id<0:return
 log_refresh_needed=true
 if not pending.is_empty() or log_revision<=0:return
 # Native retains already displayed rows on removal and appends newer identities.
 # Read forward from our cached tail, rather than replacing it with a fresh log.
 _send({"action":34,"view":3,"unit_id":unit_id,"unit_category":unit_category,"after_id":int(rows.back().id) if not rows.is_empty() else -1,"expected_list_revision":log_revision,"refresh":true},"live_append")

func accept(token: int, world_epoch: int, reply: Dictionary) -> bool:
 if not opened or pending.is_empty() or token!=generation or world_epoch!=epoch:return false
 if pending.mode=="text":return _accept_text(reply)
 var request: Dictionary=pending.request
 if int(reply.get("view",-1))!=int(request.view):return false
 for key in ["tab","unit_id","unit_category"]:
  if request.has(key) and int(reply.get(key,-1))!=int(request[key]):return false
 if int(request.view)==1:
  var revision:int=int(reply.get("list_revision",0))
  if revision<=0 or (tab_revision>0 and revision!=tab_revision):return false
  tab_revision=revision
  if pending.mode=="snapshot":
   if reply.get("tab_counts",[]).size()==25:counts=reply.tab_counts.duplicate()
   pending={};_request_selection();return true
 if int(request.view)==2:
  var revision:int=int(reply.get("list_revision",0))
  var expected:int=int(request.get("expected_list_revision",0))
  if revision<=0 or (expected>0 and revision!=expected):return false
 if int(request.view)==3:
  var revision:int=int(reply.get("list_revision",0))
  if revision<=0 or (log_revision>0 and revision!=log_revision):return false
  log_revision=revision
 var incoming: Array=reply.get("units",[]) if int(request.view)==2 else reply.get("reports",[])
 if int(request.view) in [1,3]:
  for row in incoming:
   if not bool(row.get("text_complete",true)):
    _text_reply=reply.duplicate(true);_text_pending=pending.duplicate(true);_text_index=0
    _next_text();return true
 if int(request.view)==3 and pending.mode=="replace":log_initial_needed=false
 var live_append:bool=pending.mode=="live_append"
 var history_page:bool=unit_id>=0 and pending.mode in ["prepend","append"]
 if pending.mode=="prepend":rows=incoming.duplicate(true)+rows;log_first+=incoming.size();log_start-=incoming.size()
 elif pending.mode=="append" or live_append:rows.append_array(incoming.duplicate(true))
 else:
  rows=incoming.duplicate(true)
  if unit_id>=0:
   log_start=maxi(0,int(reply.get("total",rows.size()))-rows.size()) if request.get("from_end",false) else 0
   log_first=maxi(0,rows.size()-17) if request.get("from_end",false) else 0
   log_requested=log_start+log_first
 if int(request.view)==1 and reply.get("tab_counts",[]).size()==25:counts=reply.tab_counts.duplicate()
 # Preserve the other end when extending a loaded range.
 if pending.mode!="append" and not live_append:next_before=int(reply.get("next_before_id",-1))
 if pending.mode!="prepend":next_after=int(reply.get("next_after_id",-1))
 next_cursor=int(reply.get("next_cursor",0));list_revision=int(reply.get("list_revision",0))
 if live_append:total+=incoming.size()
 elif not history_page:total=maxi(int(reply.get("total",rows.size())),rows.size())
 # History extends the cached snapshot. A newer source total must not count an
 # append here and again when the tail refresh arrives, or discard cached removals.
 if live_append:log_requested=maxi(0,total-17)
 if live_append and next_after>=0 and not incoming.is_empty():
  pending={};refresh_new_reports();changed.emit();return true
 if live_append:log_refresh_needed=false
 pending={};_advance_window();changed.emit();return true

func reject(token: int) -> void:
 if token!=generation or pending.is_empty():return
 var original:Dictionary=_text_pending if pending.mode=="text" else pending
 read_retry=original.duplicate(true)
 read_retry.requested_row=requested_row;read_retry.log_requested=log_requested
 # An initial page may already own a snapshot when its text failed. Keep it.
 if int(read_retry.request.view)==1:read_retry.request.expected_list_revision=tab_revision
 if int(read_retry.request.view)==3:read_retry.request.expected_list_revision=log_revision
 _clear_text()
 pending={};requested_row=first_row;log_requested=log_start+log_first;changed.emit()

func retry_read() -> bool:
 if not opened or not pending.is_empty() or read_retry.is_empty():return false
 var retry:Dictionary=read_retry
 requested_row=int(retry.requested_row);log_requested=int(retry.log_requested)
 _send(retry.request,retry.mode);return true

func recenter(report_id:int,secondary:bool=false) -> bool:
 if not opened:return false
 for row in rows:
  if int(row.get("id",-1))!=report_id:continue
  var key:="position2" if secondary else "position"
  if not bool(row.get(key+"_visible",false)) or not row.get(key) is Vector3i:return false
  var tile:Vector3i=row[key]
  # Stored position wins over zoom category, hidden flag and current unit position.
  close();recenter_requested.emit(tile);return true
 return false

func inspect_speaker(report_id:int) -> bool:
 if not opened or unit_id<0:return false
 for row in rows:
  if int(row.get("id",-1))!=report_id:continue
  var speaker:int=int(row.get("speaker_id",-1))
  if speaker<0:return false
  # The navigation owner resolves the current creature before closing. Native
  # leaves Reports open when this historical speaker no longer exists.
  speaker_requested.emit(speaker);return true
 return false

func list_count() -> int:return maxi(total,rows.size())

func scroll_to(first:int) -> void:
 if not opened:return
 # Initial content is still required even if scrolling arrives after rejection.
 # Only a failed history navigation can be superseded by a new scroll target.
 if read_retry.get("mode","") in ["replace","snapshot"]:return
 read_retry={}
 if unit_id>=0:
  log_requested=clampi(first,0,maxi(0,list_count()-17))
  _advance_window();changed.emit();return
 requested_row=clampi(first,0,maxi(0,list_count()-PAGE_ROWS))
 _advance_window();changed.emit()

func _advance_window() -> void:
 if unit_id>=0:
  log_first=clampi(log_requested-log_start,0,maxi(0,rows.size()-17))
  if pending.is_empty():
   if log_requested<log_start:previous_page()
   elif log_requested+17>log_start+rows.size():next_page()
  return
 requested_row=clampi(requested_row,0,maxi(0,list_count()-PAGE_ROWS))
 # Keep displaying retained rows until the requested range has arrived.
 first_row=mini(requested_row,maxi(0,rows.size()-PAGE_ROWS))
 if requested_row+PAGE_ROWS>rows.size() and pending.is_empty():next_page()

func toggle_pause_on_new() -> void:
 if not opened or unit_id<0:return
 pause_on_new=not pause_on_new;changed.emit()

func observe_log_length(id:int,category:int,length:int,session:int) -> bool:
 if not opened or id!=unit_id or category!=unit_category or session!=epoch or length<0:return false
 var previous:=unit_log_length
 unit_log_length=length
 if previous<0 or previous==length:return false
 log_refresh_needed=true
 # Native popup compares raw source log length, including decreases, not retained
 # report count or newest ID. This local option persists across closing/reopening.
 if pause_on_new:pause_requested.emit()
 return true

func _clear_text() -> void:
 _text_reply={};_text_pending={};_text_index=0;_text_assembly=null

func _next_text() -> void:
 var incoming:Array=_text_reply.reports
 while _text_index<incoming.size():
  if not bool(incoming[_text_index].get("text_complete",true)):
   var log_view:bool=int(_text_pending.request.view)==3
   _text_assembly=preload("res://scripts/report_text_assembly.gd").new(incoming[_text_index],0 if log_view else int(_text_pending.request.tab),log_revision if log_view else tab_revision,unit_id if log_view else -1,unit_category if log_view else -1)
   _send(_text_assembly.request(),"text");return
  _text_index+=1
 var resolved:Dictionary=_text_reply
 var original:Dictionary=_text_pending
 _clear_text();pending=original
 accept(generation,epoch,resolved)

func _accept_text(reply:Dictionary) -> bool:
 if _text_assembly==null or not _text_assembly.accept(reply):return false
 if not _text_assembly.complete:
  _send(_text_assembly.request(),"text");return true
 _text_reply.reports[_text_index]=_text_assembly.result()
 _text_index+=1;_text_assembly=null;_next_text();return true
