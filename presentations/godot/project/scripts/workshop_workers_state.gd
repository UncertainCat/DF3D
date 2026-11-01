extends RefCounted
# Workshop profile and candidate-list authority are independent receipts.
signal changed
signal applied
const C=preload("res://scripts/management_contract.gd")
enum Phase { Closed, Reading, Ready, Applying, Rejected, Unknown, Unavailable }
var service
var phase:=Phase.Closed
var building_id: int=-1
var rows: Array=[]
var permitted_workers: Array=[]
var profile_revision:=0
var revision:=0
var ticket:=0
var generation:=0
var _pending: Array=[]
var _total:=0

func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(_session_changed)
func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
	service=null
func close() -> void:
	generation+=1
	var previous:=ticket;ticket=0
	if service!=null and previous!=0:service.detach(previous)
	building_id=-1;_clear();phase=Phase.Closed;changed.emit()
func _clear() -> void:
	rows=[];permitted_workers=[];profile_revision=0;revision=0;_pending=[];_total=0
func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()
func open(id: int) -> void:
	close()
	if id<0 or id>2147483647:_fail(Phase.Rejected);return
	building_id=id;refresh()
func refresh() -> void:
	if building_id<0 or ticket!=0:return
	_clear();phase=Phase.Reading;_read(0)
func _read(cursor: int) -> void:
	_send({"action":C.ManagementAction.ProductionInspect,"workshop_workers":true,"building_id":building_id,"cursor":cursor,"worker_list_revision":revision})
func select_worker(id: int) -> void:
	if phase!=Phase.Ready or ticket!=0:return
	var found:=false
	for row in rows:
		if row.unit_id==id:found=true;break
	if not found:return
	phase=Phase.Applying
	_send({"action":C.ManagementAction.FarmEdit,"workshop_workers":true,"building_id":building_id,"farm_operation":C.FarmOperation.WorkerSelect,
		"worker_id":id,"expected_revision":profile_revision,"worker_list_revision":revision})
func _send(intent: Dictionary) -> void:
	if service==null:_fail(Phase.Unavailable);return
	var owner:=generation
	ticket=service.submit("production",intent,func(received,result,sent):
		if owner==generation and received==ticket:_receive(result,sent))
	if ticket==0:_fail(Phase.Unavailable);return
	changed.emit()
func _fail(next: Phase) -> void:
	_clear();phase=next;changed.emit()
func _receive(result: Dictionary,sent: Dictionary) -> void:
	ticket=0
	var editing: bool=sent.action==C.ManagementAction.FarmEdit
	var value: Dictionary=result.get("production",{}).get("workshop_workers",{})
	if result.get("outcome","")=="unknown" or value.get("outcome",0)==C.FarmEditOutcome.Unknown:_fail(Phase.Unknown);return
	if result.get("status",-1)!=C.ManagementStatus.Ok:_fail(Phase.Rejected);return
	if result.get("action",-1)!=sent.action or value.get("building_id",-1)!=building_id or value.get("profile_revision",0)<=0 or not value.get("permitted_workers") is Array:
		_fail(Phase.Unknown if editing else Phase.Rejected);return
	if editing:
		var expected:=permitted_workers.duplicate()
		var index:=expected.rfind(sent.worker_id)
		if index>=0:expected.remove_at(index)
		else:expected=[sent.worker_id]
		if value.get("outcome",0)!=C.FarmEditOutcome.Completed or value.get("unit_id",-1)!=sent.worker_id or value.permitted_workers!=expected:
			_fail(Phase.Unknown);return
		# Retire the old list after a confirmed change; never replay a selection.
		applied.emit();refresh();return
	if value.get("outcome",-1)!=C.FarmEditOutcome.None or value.get("revision",0)<=0 or value.get("cursor",-1)!=sent.cursor or not value.get("rows") is Array:
		_fail(Phase.Rejected);return
	if sent.cursor==0:
		revision=value.revision;profile_revision=value.profile_revision;permitted_workers=value.permitted_workers.duplicate();_total=value.total
	elif value.revision!=revision or value.profile_revision!=profile_revision or value.permitted_workers!=permitted_workers or value.total!=_total:
		_fail(Phase.Rejected);return
	if sent.cursor!=_pending.size() or value.rows.size()!=mini(128,_total-sent.cursor):_fail(Phase.Rejected);return
	_pending.append_array(value.rows.duplicate(true))
	if value.next_cursor!=0:
		if value.next_cursor!=_pending.size():_fail(Phase.Rejected);return
		_read(value.next_cursor);return
	if _pending.size()!=_total:_fail(Phase.Rejected);return
	rows=_pending;_pending=[];phase=Phase.Ready;changed.emit()
