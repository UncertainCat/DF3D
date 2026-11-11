extends RefCounted
# Native membership and row data are authority; tabs, paging and scroll are local.
signal changed
signal located(destination: Dictionary)
const C=preload("res://scripts/management_contract.gd")
enum Phase {Closed,Reading,Ready,Rejected,Unavailable,Locating,Unknown}
var service
var phase:=Phase.Closed
var tab:=0
var rows: Array=[]
var first:=0
var ticket:=0
var generation:=0
var last_result: Dictionary={}
var _scroll: Array[int]=[0,0,0,0]
var _pending_rows: Array=[]
var _seen: Dictionary={}
var _revision:=0
var _total:=0
var _restarts:=0
func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(_session_changed)
func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
	service=null
func _clear() -> void:
	rows=[];_pending_rows=[];_seen={};_revision=0;_total=0
func _retire() -> void:
	generation+=1;var previous:=ticket;ticket=0
	if service!=null and previous!=0:service.detach(previous)
func close() -> void:
	_retire();_clear();tab=0;first=0;_scroll=[0,0,0,0];last_result={};phase=Phase.Closed;changed.emit()
func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()
func open(selected_tab:=0) -> void:
	if selected_tab<0 or selected_tab>3:return
	close();tab=selected_tab;refresh()
func select_tab(value: int) -> void:
	if phase in [Phase.Closed,Phase.Unavailable] or value<0 or value>3 or value==tab:return
	_scroll[tab]=first;_retire();_clear();tab=value;first=_scroll[tab]
	phase=Phase.Rejected;refresh()
func refresh() -> void:
	if phase in [Phase.Reading,Phase.Locating]:return
	_retire();_clear();_restarts=0;last_result={};phase=Phase.Reading;_page()
func seek(value: int,capacity: int) -> void:
	if phase!=Phase.Ready:return
	first=clampi(value,0,maxi(0,rows.size()-maxi(1,capacity)));_scroll[tab]=first;changed.emit()
func locate(artifact_id: int) -> void:
	if phase!=Phase.Ready or not rows.any(func(row):return row.artifact_id==artifact_id and row.has("position")):return
	phase=Phase.Locating
	_submit({"action":C.ManagementAction.ObjectsLocate,"tab":tab,"artifact_id":artifact_id,"expected_list_revision":_revision})
func _page() -> void:
	_submit({"action":C.ManagementAction.ObjectsRead,"tab":tab,"offset":_pending_rows.size(),"limit":32,"expected_list_revision":_revision})
func _integer(value: Variant,low: int,high: int) -> bool:return typeof(value)==TYPE_INT and value>=low and value<=high
func _valid_page(value: Dictionary,intent: Dictionary) -> bool:
	if value.get("tab")!=intent.tab or not _integer(value.get("list_revision"),1,9223372036854775807) or not _integer(value.get("total"),0,1048576) or value.get("offset")!=intent.offset or typeof(value.get("rows"))!=TYPE_ARRAY:return false
	if value.rows.size()>intent.limit or intent.offset+value.rows.size()>value.total or (intent.offset<value.total and value.rows.is_empty()):return false
	if _revision!=0 and (value.list_revision!=_revision or value.total!=_total):return false
	for row in value.rows:
		if typeof(row)!=TYPE_DICTIONARY or not _integer(row.get("artifact_id"),0,2147483647) or _seen.has(row.artifact_id):return false
		_seen[row.artifact_id]=true
		for key in ["native_name","translated_name","ownership"]:
			if typeof(row.get(key))!=TYPE_STRING or row[key].to_utf8_buffer().size()>16384:return false
		if not _integer(row.get("item_id"),0,2147483647) or not _integer(row.get("item_type"),-1,92):return false
		if row.has("position"):
			var p: Variant=row.position
			if typeof(p)!=TYPE_VECTOR3I or p.x<0 or p.y<0 or p.z<0 or p.x>32767 or p.y>32767 or p.z>32767:return false
		if row.has("appearance") and not preload("res://scripts/item_sheet_state.gd")._valid_appearance(row.appearance,row.item_type):return false
	return true
func _reject(result: Dictionary) -> void:
	_clear();last_result=result.duplicate(true)
	phase=Phase.Unknown if result.get("outcome","")=="unknown" else Phase.Rejected
	changed.emit()
func _submit(intent: Dictionary) -> void:
	if service==null:_clear();phase=Phase.Unavailable;changed.emit();return
	var owner:=generation
	ticket=service.submit("objects",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0;var value: Variant=result.get("objects",{})
		if typeof(value)!=TYPE_DICTIONARY or result.get("action")!=intent.action or result.get("outcome","")=="unknown":_reject(result);return
		if value.get("tab")!=intent.tab:_reject(result);return
		if intent.action==C.ManagementAction.ObjectsLocate:
			var target: Variant=value.get("destination")
			if result.get("status")!=C.ManagementStatus.Ok or value.get("outcome")!=C.ObjectsOutcome.None or value.get("list_revision")!=_revision or typeof(target)!=TYPE_DICTIONARY or target.get("artifact_id")!=intent.artifact_id or not _integer(target.get("item_id"),0,2147483647):_reject(result);return
			if target.has("position") and (typeof(target.position)!=TYPE_VECTOR3I or target.position.x<0 or target.position.y<0 or target.position.z<0 or target.position.x>32767 or target.position.y>32767 or target.position.z>32767):_reject(result);return
			phase=Phase.Ready;changed.emit();located.emit(target.duplicate(true));return
		if result.get("status")==C.ManagementStatus.Rejected and value.get("outcome")==C.ObjectsOutcome.Stale and _restarts==0:
			_clear();_restarts+=1;_page();return
		if result.get("status")!=C.ManagementStatus.Ok or value.get("outcome")!=C.ObjectsOutcome.None or not _valid_page(value,intent):_reject(result);return
		_revision=value.list_revision;_total=value.total;_pending_rows.append_array(value.rows.duplicate(true))
		if _pending_rows.size()<_total:_page();return
		rows=_pending_rows;_pending_rows=[];_seen={};phase=Phase.Ready;last_result={}
		first=mini(first,maxi(0,rows.size()-1));_scroll[tab]=first;changed.emit())
	if ticket==0:_clear();phase=Phase.Unavailable
	changed.emit()
