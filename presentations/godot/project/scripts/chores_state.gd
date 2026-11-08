extends RefCounted
# Local ownership only. Eligibility, ordering, captions and labor effects belong to DF.
signal changed
const C=preload("res://scripts/management_contract.gd")
const LABORS=[23,37,1,2,6,3,4,5,7,8,74,77,9,75]
enum Phase { Closed, Reading, Ready, Applying, Rejected, Unknown, Unavailable }
var service
var phase:=Phase.Closed
var snapshot: Dictionary={}
var children: Array=[]
var labors: Array=[]
var child_first:=0
var labor_first:=0
var ticket:=0
var generation:=0
var last_result: Dictionary={}
func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(_session_changed)
func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
	service=null
func _clear() -> void:
	snapshot={};children=[];labors=[]
func close() -> void:
	generation+=1
	var previous:=ticket;ticket=0
	if service!=null and previous!=0:service.detach(previous)
	_clear();last_result={};child_first=0;labor_first=0;phase=Phase.Closed;changed.emit()
func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()
func open() -> void:
	close();_read()
func _read() -> void:
	_clear();phase=Phase.Reading
	_submit({"action":C.ManagementAction.ChoresRead})
func set_enabled(value: bool) -> void:_apply(C.ChoresOperation.Enabled,-1,value)
func set_labor(id: int,value: bool) -> void:
	if id not in LABORS:return
	_apply(C.ChoresOperation.Labor,id,value)
func set_exempt(id: int,value: bool) -> void:
	if id not in snapshot.get("children",PackedInt32Array()):return
	_apply(C.ChoresOperation.Exempt,id,value)
func _apply(operation: int,id: int,value: bool) -> void:
	if phase!=Phase.Ready:return
	phase=Phase.Applying
	_submit({"action":C.ManagementAction.ChoresApply,"operation":operation,"id":id,"value":value,"expected":snapshot.duplicate(true)})
func _valid_snapshot(value: Dictionary) -> bool:
	if typeof(value.get("enabled"))!=TYPE_BOOL or typeof(value.get("children"))!=TYPE_PACKED_INT32_ARRAY or typeof(value.get("exempted"))!=TYPE_PACKED_INT32_ARRAY or typeof(value.get("labors"))!=TYPE_ARRAY:return false
	if value.children.size()>65536 or value.exempted.size()>65536 or value.labors.size()!=LABORS.size():return false
	var seen: Dictionary={}
	for id: int in value.children:
		if id<0 or seen.has(id):return false
		seen[id]=true
	var prior: int=-1
	for id: int in value.exempted:
		if id<=prior:return false
		prior=id
	for index in LABORS.size():
		if typeof(value.labors[index])!=TYPE_DICTIONARY:return false
		var row: Dictionary=value.labors[index]
		if typeof(row.get("id"))!=TYPE_INT or row.id!=LABORS[index] or typeof(row.get("enabled"))!=TYPE_BOOL:return false
	return true
func _valid_captions(rows: Array,ids: PackedInt32Array) -> bool:
	if rows.size()!=ids.size():return false
	for index in ids.size():
		if typeof(rows[index])!=TYPE_DICTIONARY:return false
		var row: Dictionary=rows[index]
		if typeof(row.get("id"))!=TYPE_INT or row.id!=ids[index] or typeof(row.get("caption"))!=TYPE_STRING or row.caption.is_empty():return false
	return true
func _reject(result: Dictionary) -> void:
	_clear();last_result=result.duplicate(true)
	phase=Phase.Unknown if result.get("outcome","")=="unknown" or result.get("chores",{}).get("outcome",-1)==C.ChoresOutcome.Unknown else Phase.Rejected
	changed.emit()
func _submit(intent: Dictionary) -> void:
	if service==null:_clear();phase=Phase.Unavailable;changed.emit();return
	var owner:=generation
	ticket=service.submit("chores",intent,func(received,result,_sent):
		if owner!=generation or received!=ticket:return
		ticket=0
		var value: Dictionary=result.get("chores",{})
		var apply: bool=intent.action==C.ManagementAction.ChoresApply
		if result.get("outcome","")=="unknown" or result.get("status",-1)!=C.ManagementStatus.Ok or result.get("action",-1)!=intent.action or value.get("outcome",-1)!=(C.ChoresOutcome.Applied if apply else C.ChoresOutcome.None):
			_reject(result);return
		if typeof(value.get("snapshot"))!=TYPE_DICTIONARY or not _valid_snapshot(value.snapshot):_reject(result);return
		if apply:
			# Refresh metadata from a new native read; this never replays the edit.
			_read();return
		if typeof(value.get("children"))!=TYPE_ARRAY or typeof(value.get("labors"))!=TYPE_ARRAY or not _valid_captions(value.children,value.snapshot.children) or not _valid_captions(value.labors,PackedInt32Array(LABORS)):
			_reject(result);return
		snapshot=value.snapshot.duplicate(true);children=value.children.duplicate(true);labors=value.labors.duplicate(true)
		last_result={};phase=Phase.Ready;changed.emit())
	if ticket==0:_clear();phase=Phase.Unavailable
	changed.emit()
