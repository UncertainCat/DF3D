extends RefCounted
# Native membership and row data are authority; tabs, paging and scroll are local.
signal changed
const C=preload("res://scripts/management_contract.gd")
enum Phase {Closed,Reading,Ready,Rejected,Unavailable}
var service
var phase:=Phase.Closed
var tab:=0
var rows: Array=[]
var first:=0
var ticket:=0
var generation:=0
var last_result: Dictionary={}
var _scroll: Array[int]=[0,0,0,0,0,0]
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
	_retire();_clear();tab=0;first=0;_scroll=[0,0,0,0,0,0];last_result={};phase=Phase.Closed;changed.emit()
func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()
func open(selected_tab:=0) -> void:
	if selected_tab<0 or selected_tab>5:return
	close();tab=selected_tab;refresh()
func select_tab(value: int) -> void:
	if phase in [Phase.Closed,Phase.Unavailable] or value<0 or value>5 or value==tab:return
	_scroll[tab]=first;_retire();_clear();tab=value;first=_scroll[tab]
	phase=Phase.Rejected;refresh()
func refresh() -> void:
	if phase==Phase.Reading:return
	_retire();_clear();_restarts=0;last_result={};phase=Phase.Reading;_page()
func seek(value: int,capacity: int) -> void:
	if phase!=Phase.Ready:return
	first=clampi(value,0,maxi(0,rows.size()-maxi(1,capacity)));_scroll[tab]=first;changed.emit()
func _page() -> void:
	_submit({"action":C.ManagementAction.PlacesRead,"tab":tab,"offset":_pending_rows.size(),"limit":32,"expected_list_revision":_revision})
func _integer(value: Variant,low: int,high: int) -> bool:return typeof(value)==TYPE_INT and value>=low and value<=high
func _valid_page(value: Dictionary,intent: Dictionary) -> bool:
	if value.get("tab")!=intent.tab or not _integer(value.get("list_revision"),1,9223372036854775807) or not _integer(value.get("total"),0,1048576) or value.get("offset")!=intent.offset or typeof(value.get("rows"))!=TYPE_ARRAY:return false
	if value.rows.size()>intent.limit or intent.offset+value.rows.size()>value.total or (intent.offset<value.total and value.rows.is_empty()):return false
	if _revision!=0 and (value.list_revision!=_revision or value.total!=_total):return false
	for row in value.rows:
		if typeof(row)!=TYPE_DICTIONARY or not _integer(row.get("building_id"),0,2147483647) or _seen.has(row.building_id):return false
		_seen[row.building_id]=true
		for key in ["name","subtitle","job_caption","status_caption","secondary_status","status_overlay","operator_caption"]:
			if typeof(row.get(key))!=TYPE_STRING or row[key].to_utf8_buffer().size()>16384:return false
		if not _integer(row.get("additional_jobs"),0,1048576) or not _integer(row.get("siege_action"),0 if tab==5 else -1,4 if tab==5 else -1):return false
		if row.has("position"):
			var p: Variant=row.position
			if typeof(p)!=TYPE_VECTOR3I or p.x<0 or p.y<0 or p.z<0 or p.x>32767 or p.y>32767 or p.z>32767:return false
		if row.has("appearance") and not preload("res://scripts/item_sheet_state.gd")._valid_recipe(row.appearance):return false
	return true
func _reject(result: Dictionary) -> void:
	_clear();last_result=result.duplicate(true);phase=Phase.Rejected;changed.emit()
func _submit(intent: Dictionary) -> void:
	if service==null:_clear();phase=Phase.Unavailable;changed.emit();return
	var owner:=generation
	ticket=service.submit("places",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0;var value: Variant=result.get("places",{})
		if typeof(value)!=TYPE_DICTIONARY or result.get("action")!=intent.action or result.get("outcome","")=="unknown":_reject(result);return
		if value.get("tab")!=intent.tab:_reject(result);return
		if result.get("status")==C.ManagementStatus.Rejected and value.get("outcome")==C.PlacesOutcome.Stale and _restarts==0:
			_clear();_restarts+=1;_page();return
		if result.get("status")!=C.ManagementStatus.Ok or value.get("outcome")!=C.PlacesOutcome.None or not _valid_page(value,intent):_reject(result);return
		_revision=value.list_revision;_total=value.total;_pending_rows.append_array(value.rows.duplicate(true))
		if _pending_rows.size()<_total:_page();return
		rows=_pending_rows;_pending_rows=[];_seen={};phase=Phase.Ready;last_result={}
		first=mini(first,maxi(0,rows.size()-1));_scroll[tab]=first;changed.emit())
	if ticket==0:_clear();phase=Phase.Unavailable
	changed.emit()
