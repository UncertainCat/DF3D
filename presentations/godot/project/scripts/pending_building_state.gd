extends RefCounted
signal changed
signal applied
signal retired(id: int,removing: bool)
const C=preload("res://scripts/management_contract.gd")
enum Phase { Closed, Reading, Ready, Applying, Rejected, Stale, Unknown, Unavailable }
enum Operation { Resume, Suspend, Cancel, CancelRemoval }
var service
var phase:=Phase.Closed
var building_id: int=-1
var snapshot: Dictionary={}
var ticket:=0
var generation:=0

func configure(source) -> void:
	dispose();service=source
	if service!=null:service.session_changed.connect(_session_changed)
func dispose() -> void:
	close()
	if service!=null and service.session_changed.is_connected(_session_changed):service.session_changed.disconnect(_session_changed)
	service=null
func close() -> void:
	generation+=1
	var previous:=ticket;ticket=0;building_id=-1;snapshot={};phase=Phase.Closed
	if service!=null and previous!=0:service.detach(previous)
	changed.emit()
func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()
func open(id: int) -> void:
	close()
	if id<0 or id>2147483647:_fail(Phase.Rejected);return
	if service==null:_fail(Phase.Unavailable);return
	building_id=id;phase=Phase.Reading
	_send({"action":C.ManagementAction.ProductionInspect,"pending_building":true,"building_id":id})
func edit(operation: Operation) -> void:
	if phase!=Phase.Ready or ticket!=0 or snapshot.is_empty() or operation not in [Operation.Resume,Operation.Suspend,Operation.Cancel,Operation.CancelRemoval]:return
	if snapshot.removing!=(operation==Operation.CancelRemoval):return
	if operation in [Operation.Resume,Operation.Suspend] and snapshot.job_id<0:return
	phase=Phase.Applying
	_send({"action":C.ManagementAction.FarmEdit,"pending_building":true,"building_id":building_id,"expected_revision":snapshot.revision,"pending_operation":operation})
func refresh() -> void:
	if building_id>=0 and ticket==0:open(building_id)
func _send(intent: Dictionary) -> void:
	var owner:=generation
	ticket=service.submit("production",intent,func(received,result,sent):
		if owner==generation and received==ticket:_receive(result,sent))
	if ticket==0:_fail(Phase.Unavailable);return
	changed.emit()
func _fail(next: Phase) -> void:
	phase=next;snapshot={};changed.emit()
static func valid_snapshot(value: Dictionary,id: int) -> bool:
	for field in ["id","type","revision","stage","max_stage","job_id","progress"]:
		if typeof(value.get(field))!=TYPE_INT:return false
	for field in ["suspended","has_worker","removing","forbidden"]:
		if typeof(value.get(field))!=TYPE_BOOL:return false
	if value.progress<0 or value.progress>4:return false
	if value.job_id== -1 and (value.removing or value.suspended or value.has_worker):return false
	return value.id==id and value.type>=0 and value.type<=54 and value.type not in [29,30] and value.revision>0 and value.stage>=0 and value.stage<value.max_stage and value.job_id>=-1 and typeof(value.get("header_name"))==TYPE_STRING and not value.header_name.is_empty()
func _receive(result: Dictionary,sent: Dictionary) -> void:
	ticket=0
	var editing: bool=sent.action==C.ManagementAction.FarmEdit
	var state: Dictionary=result.get("production",{}).get("pending_building",{})
	var outcome: int=state.get("outcome",C.FarmEditOutcome.None)
	if result.get("outcome","")=="unknown" or outcome==C.FarmEditOutcome.Unknown:_fail(Phase.Unknown);return
	if result.get("status",C.ManagementStatus.Rejected)!=C.ManagementStatus.Ok:
		_fail(Phase.Stale if editing and outcome==C.FarmEditOutcome.Stale else Phase.Rejected);return
	if result.get("action",-1)!=sent.action or outcome!=(C.FarmEditOutcome.Completed if editing else C.FarmEditOutcome.None) or typeof(state.get("removed"))!=TYPE_BOOL or typeof(state.get("removing"))!=TYPE_BOOL:
		_fail(Phase.Unknown if editing else Phase.Rejected);return
	if editing and sent.pending_operation==Operation.Cancel:
		if state.has("snapshot") or state.removed!=bool(snapshot.stage==0) or state.removing!=bool(snapshot.stage>0):_fail(Phase.Unknown);return
		var removing: bool=state.removing
		var id:=building_id
		close();retired.emit(id,removing);return
	var observed: Dictionary=state.get("snapshot",{})
	if state.removed or state.removing or not valid_snapshot(observed,building_id):_fail(Phase.Unknown if editing else Phase.Rejected);return
	if editing:
		if observed.stage!=snapshot.stage or observed.max_stage!=snapshot.max_stage or observed.removing:_fail(Phase.Unknown);return
		if sent.pending_operation==Operation.CancelRemoval:
			if observed.job_id!=-1:_fail(Phase.Unknown);return
		elif observed.job_id!=snapshot.job_id or observed.suspended!=bool(sent.pending_operation==Operation.Suspend):_fail(Phase.Unknown);return
	snapshot=observed.duplicate(true);phase=Phase.Ready;changed.emit()
	if editing:applied.emit()
