extends RefCounted
# Staged candidate picker ownership. DF supplies order, search and mutation effects.
signal changed
signal convicted(crime_id: int,unit_id: int)
const C=preload("res://scripts/management_contract.gd")
enum Phase {Closed,Reading,Ready,Applying,Rejected,Unknown,Unavailable}
var service
var phase:=Phase.Closed
var tab:=0
var crime_id:=-1
var list_revision:=0
var case_revision:=0
var candidate_revision:=0
var interrogate:=false
var cursor_id:=-1
var _retained_ids: Array=[]
var _retained_first:=0
var query:=""
var priorities: Array[int]=[C.JusticeCandidateColumn.Crime,C.JusticeCandidateColumn.Name]
var directions: Array[bool]=[false,false,false,false]
var rows: Array=[]
var first:=0
var ticket:=0
var generation:=0
var last_result: Dictionary={}
var _pending: Array=[]
var _seen: Dictionary={}
var _total:=0
func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(_session_changed)
func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
	service=null
func _retire() -> void:
	generation+=1;var old:=ticket;ticket=0
	if service!=null and old!=0:service.detach(old)
func close() -> void:
	_retire();phase=Phase.Closed;crime_id=-1;rows=[];_pending=[];_seen={};_total=0
	list_revision=0;case_revision=0;candidate_revision=0;query="";first=0;last_result={}
	interrogate=false;cursor_id=-1;_retained_ids=[];_retained_first=0
	priorities=[C.JusticeCandidateColumn.Crime,C.JusticeCandidateColumn.Name];directions=[false,false,false,false];changed.emit()
func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()
func open(selected_tab: int,id: int,list_rev: int,case_rev: int,interview:=false) -> void:
	if phase in [Phase.Applying,Phase.Unknown] or selected_tab not in [0,2] or id<0 or list_rev<=0 or case_rev<=0:return
	close();interrogate=interview;tab=selected_tab;crime_id=id;list_revision=list_rev;case_revision=case_rev;search("")
func search(value: String) -> void:
	_read(value,false)
func _read(value: String,retain: bool) -> void:
	var bytes:=value.to_utf8_buffer()
	if crime_id<0 or phase in [Phase.Applying,Phase.Unknown,Phase.Unavailable] or bytes.size()>512 or bytes.has(0):return
	_retained_ids=rows.map(func(row):return row.unit_id) if retain else []
	_retained_first=first if retain else 0
	if not retain:cursor_id=-1
	_retire();query=value;rows=[];_pending=[];_seen={};candidate_revision=0;_total=0;first=0
	last_result={};phase=Phase.Reading;_page()
func seek(value: int,capacity: int) -> void:
	if phase!=Phase.Ready:return
	first=clampi(value,0,maxi(0,rows.size()-maxi(1,capacity)));changed.emit()
func select_sort(column: int,retain:=false,remove:=false) -> void:
	if crime_id<0 or column<0 or column>3 or phase in [Phase.Closed,Phase.Applying,Phase.Unknown,Phase.Unavailable]:return
	if remove:
		while priorities.has(column):priorities.erase(column)
		if priorities.is_empty():priorities.append(C.JusticeCandidateColumn.Category)
	else:
		if retain and priorities.size()>=65536:return
		if priorities.has(column):directions[column]=not directions[column]
		if not retain:priorities.clear()
		priorities.append(column)
	search(query)
func _intent(action: int) -> Dictionary:
	var sorts: Array=[]
	for column in priorities:sorts.append({"column":column,"reverse":directions[column]})
	return {"action":action,"tab":tab,"crime_id":crime_id,"expected_list_revision":list_revision,
		"expected_case_revision":case_revision,"expected_candidate_revision":candidate_revision,"query":query,"sorts":sorts,"offset":0,"limit":32,"interrogate":interrogate}
func _fail(result: Dictionary,unknown:=false) -> void:
	_pending=[];_seen={};last_result=result.duplicate(true);phase=Phase.Unknown if unknown else Phase.Rejected;changed.emit()
func _valid(page: Dictionary,intent: Dictionary) -> bool:
	if page.get("interrogate",false)!=interrogate:return false
	if page.get("crime_id")!=crime_id or typeof(page.get("revision"))!=TYPE_INT or page.revision<=0 or typeof(page.get("total"))!=TYPE_INT or page.total<0 or page.total>1048576:return false
	if page.get("offset")!=intent.offset or typeof(page.get("rows"))!=TYPE_ARRAY:return false
	if page.rows.size()>intent.limit or intent.offset+page.rows.size()>page.total or (intent.offset<page.total and page.rows.is_empty()):return false
	if candidate_revision!=0 and (page.revision!=candidate_revision or page.total!=_total):return false
	for row in page.rows:
		if typeof(row)!=TYPE_DICTIONARY or typeof(row.get("unit_id"))!=TYPE_INT or row.unit_id<0 or row.unit_id>2147483647 or _seen.has(row.unit_id):return false
		if typeof(row.get("rank"))!=TYPE_INT or row.rank< -2147483648 or row.rank>2147483647 or typeof(row.get("interrogation_pending"))!=TYPE_BOOL or typeof(row.get("counterintelligence"))!=TYPE_BOOL:return false
		if not _valid_display(row.get("display")):return false
		_seen[row.unit_id]=true
	return true
func _valid_display(value: Variant) -> bool:
	if typeof(value)!=TYPE_DICTIONARY:return false
	for key in ["name","witness_label","deceased"]:
		if typeof(value.get(key))!=TYPE_STRING or value[key].to_utf8_buffer().size()>16384:return false
	for bounds in [["columns",3,2048],["witness_count",0,1048576],["witness_color",0,15]]:
		if typeof(value.get(bounds[0]))!=TYPE_INT or value[bounds[0]]<bounds[1] or value[bounds[0]]>bounds[2]:return false
	var color: Variant=value.get("name_color")
	if typeof(color)!=TYPE_DICTIONARY or typeof(color.get("effect"))!=TYPE_INT or color.effect<0 or color.effect>3:return false
	for key in ["color","alternate"]:
		if typeof(color.get(key))!=TYPE_ARRAY or color[key].size()!=3:return false
		for i in 3:
			if typeof(color[key][i])!=TYPE_INT or color[key][i]<0 or color[key][i]>(1 if i==2 else 7):return false
	return true
func _page() -> void:
	if service==null:phase=Phase.Unavailable;changed.emit();return
	var intent:=_intent(C.ManagementAction.JusticeCandidatesRead);intent.offset=_pending.size()
	var owner:=generation
	ticket=service.submit("justice",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0;var value: Variant=result.get("justice",{})
		if result.get("action")!=intent.action or result.get("status")!=C.ManagementStatus.Ok or result.get("outcome","")=="unknown" or typeof(value)!=TYPE_DICTIONARY:_fail(result);return
		if value.get("outcome")!=C.JusticeOutcome.None or value.get("tab")!=tab or value.get("list_revision")!=list_revision or typeof(value.get("candidates"))!=TYPE_DICTIONARY:_fail(result);return
		var page: Dictionary=value.candidates
		if not _valid(page,intent):_fail(result);return
		candidate_revision=page.revision;_total=page.total;_pending.append_array(page.rows.duplicate(true))
		if _pending.size()<_total:_page();return
		if not _retained_ids.is_empty():
			var by_id: Dictionary={}
			for row in _pending:by_id[row.unit_id]=row
			var retained: Array=[]
			for id in _retained_ids:
				if by_id.has(id):retained.append(by_id[id]);by_id.erase(id)
			for row in _pending:
				if by_id.has(row.unit_id):retained.append(row)
			_pending=retained
		rows=_pending;_pending=[];_seen={};first=mini(_retained_first,maxi(0,rows.size()-1));_retained_ids=[]
		if cursor_id<0 and not rows.is_empty():cursor_id=rows[0].unit_id
		phase=Phase.Ready;changed.emit())
	if ticket==0:phase=Phase.Unavailable
	changed.emit()
func convict(id: int) -> void:
	if interrogate:return
	_apply(id)
func toggle_interrogation(id: int) -> void:
	if not interrogate:return
	_apply(id)
func _apply(id: int) -> void:
	if phase!=Phase.Ready or not rows.any(func(row):return row.unit_id==id):return
	var intent:=_intent(C.ManagementAction.JusticeInterrogate if interrogate else C.ManagementAction.JusticeConvict);intent.unit_id=id
	if interrogate:
		intent.expected_selected=rows.filter(func(row):return row.unit_id==id)[0].interrogation_pending
		cursor_id=id
	var owner:=generation;phase=Phase.Applying;last_result={}
	ticket=service.submit("justice",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0;var value: Variant=result.get("justice",{})
		if result.get("outcome","")=="unknown" or typeof(value)!=TYPE_DICTIONARY or result.get("action")!=intent.action:_fail(result,true);return
		if value.get("outcome")==C.JusticeOutcome.Unknown:_fail(result,true);return
		if result.get("status")==C.ManagementStatus.Ok and value.get("outcome")==C.JusticeOutcome.Applied:
			if interrogate:
				phase=Phase.Ready;_read(query,true);return
			var completed:=crime_id;close();convicted.emit(completed,id);return
		if result.get("status")==C.ManagementStatus.Rejected and value.get("outcome") in [C.JusticeOutcome.Rejected,C.JusticeOutcome.Stale]:_fail(result);return
		_fail(result,true))
	if ticket==0:_fail({"outcome":"not_sent"})
	changed.emit()
