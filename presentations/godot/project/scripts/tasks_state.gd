extends RefCounted
# Native rows and capabilities are authority. Paging, scroll and ownership are local.
signal changed
signal inspect_ready(tile: Vector3i,unit_id: int)
const C=preload("res://scripts/management_contract.gd")
enum Phase {Closed,Reading,Ready,Applying,Rejected,Unknown,Unavailable,Navigating}
var service
var phase:=Phase.Closed
var rows: Array=[]
var first:=0
var ticket:=0
var generation:=0
var last_result: Dictionary={}
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
	_retire();_clear();first=0;last_result={};phase=Phase.Closed;changed.emit()
func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()
func open() -> void:close();refresh()
func refresh() -> void:
	if phase in [Phase.Reading,Phase.Applying,Phase.Navigating]:return
	_retire();_clear();_restarts=0;phase=Phase.Reading;_page()
func seek(value: int,capacity: int) -> void:
	if phase!=Phase.Ready:return
	first=clampi(value,0,maxi(0,rows.size()-maxi(1,capacity)));changed.emit()
func inspect_worker(job_id: int) -> void:
	if phase!=Phase.Ready or service==null:return
	for row in rows:
		if row.job_id!=job_id or row.worker_id<0:continue
		var id: int=row.worker_id;var owner:=generation
		_clear();phase=Phase.Navigating
		ticket=service.submit("creature_sheet_location",{"action":C.ManagementAction.CreatureSheetLocate,"unit_id":id},func(received,result,_sent):
			if owner!=generation or received!=ticket:return
			ticket=0
			var value: Variant=result.get("creature_position",{})
			if typeof(value)!=TYPE_DICTIONARY or result.get("outcome","")=="unknown" or result.get("status")!=C.ManagementStatus.Ok or result.get("action")!=C.ManagementAction.CreatureSheetLocate or value.get("unit_id")!=id or typeof(value.get("position"))!=TYPE_VECTOR3I:_reject(result);return
			var tile: Vector3i=value.position
			if tile.x<0 or tile.y<0 or tile.z<0 or tile.x>32767 or tile.y>32767 or tile.z>32767:_reject(result);return
			inspect_ready.emit(tile,id))
		if ticket==0:phase=Phase.Unavailable
		changed.emit();return
func apply(job_id: int,operation: int) -> void:
	if phase!=Phase.Ready or operation<0 or operation>3:return
	for row in rows:
		if row.job_id!=job_id:continue
		if not row[["can_repeat","can_suspend","can_remove_worker","can_cancel"][operation]]:return
		var expected: int=int(row.repeating) if operation==0 else (int(row.suspended) if operation==1 else -1)
		var intent: Dictionary={"action":C.ManagementAction.TasksApply,"job_id":row.job_id,"worker_id":row.worker_id,"building_id":row.building_id,"expected_revision":row.revision,"operation":operation,"expected_state":expected}
		_clear();phase=Phase.Applying;_submit(intent);return
func _page() -> void:
	_submit({"action":C.ManagementAction.TasksRead,"offset":_pending_rows.size(),"limit":32,"expected_list_revision":_revision})
func _integer(value: Variant,low: int,high: int) -> bool:return typeof(value)==TYPE_INT and value>=low and value<=high
func _valid_page(value: Dictionary,intent: Dictionary) -> bool:
	if not _integer(value.get("list_revision"),1,9223372036854775807) or not _integer(value.get("total"),0,1048576) or value.get("offset")!=intent.offset or value.get("job_id")!=-1 or typeof(value.get("rows"))!=TYPE_ARRAY:return false
	if value.rows.size()>intent.limit or intent.offset+value.rows.size()>value.total or (intent.offset<value.total and value.rows.is_empty()):return false
	if _revision!=0 and (value.list_revision!=_revision or value.total!=_total):return false
	for row in value.rows:
		if typeof(row)!=TYPE_DICTIONARY or not _integer(row.get("job_id"),0,2147483647) or _seen.has(row.job_id) or not _integer(row.get("worker_id"),-1,2147483647) or not _integer(row.get("building_id"),-1,2147483647) or not _integer(row.get("revision"),1,9223372036854775807):return false
		_seen[row.job_id]=true
		for key in ["caption","worker_name","building_caption"]:
			if typeof(row.get(key))!=TYPE_STRING or row[key].to_utf8_buffer().size()>16384:return false
		for key in ["can_view_job","can_repeat","can_remove_worker","can_suspend","can_cancel","repeating","suspended"]:
			if typeof(row.get(key))!=TYPE_BOOL:return false
		if row.worker_id<0 and (not row.worker_name.is_empty() or row.can_remove_worker or row.has("worker_color") or row.has("worker_position") or row.has("worker_appearance")):return false
		if row.building_id<0 and (not row.building_caption.is_empty() or row.can_repeat or row.can_suspend or row.can_cancel or row.can_remove_worker or row.has("building_position") or row.has("building_appearance")):return false
		if row.worker_id>=0:
			var color: Variant=row.get("worker_color")
			if typeof(color)!=TYPE_DICTIONARY or not _integer(color.get("effect"),0,3):return false
			for key in ["color","alternate"]:
				if typeof(color.get(key))!=TYPE_ARRAY or color[key].size()!=3:return false
				for i in 3:
					if not _integer(color[key][i],0,1 if i==2 else 7):return false
		for key in ["worker_appearance","building_appearance"]:
			if row.has(key) and not preload("res://scripts/item_sheet_state.gd")._valid_recipe(row[key]):return false
		for key in ["worker_position","building_position"]:
			if row.has(key) and (typeof(row[key])!=TYPE_VECTOR3I or row[key].x<0 or row[key].y<0 or row[key].z<0 or row[key].x>32767 or row[key].y>32767 or row[key].z>32767):return false
	return true
func _reject(result: Dictionary) -> void:
	_clear();last_result=result.duplicate(true)
	var value: Variant=result.get("tasks",{})
	phase=Phase.Unknown if result.get("outcome","")=="unknown" or (typeof(value)==TYPE_DICTIONARY and value.get("outcome")==C.TasksOutcome.Unknown) else Phase.Rejected
	changed.emit()
func _submit(intent: Dictionary) -> void:
	if service==null:_clear();phase=Phase.Unavailable;changed.emit();return
	var owner:=generation
	ticket=service.submit("tasks",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		var value: Variant=result.get("tasks",{})
		var editing: bool=intent.action==C.ManagementAction.TasksApply
		if typeof(value)!=TYPE_DICTIONARY or result.get("action")!=intent.action or result.get("outcome","")=="unknown":_reject(result);return
		if not editing and result.get("status")==C.ManagementStatus.Rejected and value.get("outcome")==C.TasksOutcome.Stale and _restarts==0:
			_clear();_restarts+=1;_page();return
		if result.get("status")!=C.ManagementStatus.Ok or value.get("outcome")!=(C.TasksOutcome.Applied if editing else C.TasksOutcome.None):_reject(result);return
		if editing:
			if value.get("job_id")!=intent.job_id or value.get("list_revision")!=0 or value.get("total")!=0 or value.get("offset")!=0 or typeof(value.get("rows"))!=TYPE_ARRAY or not value.rows.is_empty():_reject(result);return
			phase=Phase.Rejected;refresh();return
		if not _valid_page(value,intent):_reject(result);return
		_revision=value.list_revision;_total=value.total;_pending_rows.append_array(value.rows.duplicate(true))
		if _pending_rows.size()<_total:_page();return
		rows=_pending_rows;_pending_rows=[];_seen={};last_result={};phase=Phase.Ready
		first=mini(first,maxi(0,rows.size()-1));changed.emit())
	if ticket==0:_clear();phase=Phase.Unavailable
	changed.emit()
