extends RefCounted
signal changed
signal applied
const C=preload("res://scripts/management_contract.gd")
enum Phase { Closed, Reading, Ready, Applying, Rejected, Stale, Unknown, Unavailable }
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
	_send({"action":C.ManagementAction.ProductionInspect,"door_controls":true,"building_id":id})

func set_forbidden(value: bool) -> void:
	if phase!=Phase.Ready or ticket!=0 or snapshot.is_empty() or snapshot.controlled:return
	if value and not snapshot.forbidden and not snapshot.closed:return
	phase=Phase.Applying
	_send({"action":C.ManagementAction.FarmEdit,"door_controls":true,"building_id":building_id,
		"expected_revision":snapshot.revision,"door_forbidden":1 if value else 0})

func _send(intent: Dictionary) -> void:
	var owner:=generation
	ticket=service.submit("production",intent,func(received,result,sent):
		if owner==generation and received==ticket:_receive(result,sent))
	if ticket==0:_fail(Phase.Unavailable);return
	changed.emit()

func _fail(next: Phase) -> void:
	phase=next;snapshot={};changed.emit()

static func valid_snapshot(value: Dictionary,id: int) -> bool:
	if typeof(value.get("id"))!=TYPE_INT or value.id!=id or typeof(value.get("revision"))!=TYPE_INT or value.revision<=0:return false
	for field in ["forbidden","closed","controlled","taken_by_invaders","used_by_intruder","operated_by_mechanisms"]:
		if typeof(value.get(field))!=TYPE_BOOL:return false
	return value.controlled==(value.taken_by_invaders or value.used_by_intruder or value.operated_by_mechanisms)

func _receive(result: Dictionary,sent: Dictionary) -> void:
	ticket=0
	var editing: bool=sent.action==C.ManagementAction.FarmEdit
	var state: Dictionary=result.get("production",{}).get("door_controls",{})
	var outcome: int=state.get("outcome",C.FarmEditOutcome.None)
	if result.get("outcome","")=="unknown" or outcome==C.FarmEditOutcome.Unknown:_fail(Phase.Unknown);return
	if result.get("status",C.ManagementStatus.Rejected)!=C.ManagementStatus.Ok:
		_fail(Phase.Stale if editing and outcome==C.FarmEditOutcome.Stale else Phase.Rejected);return
	var observed: Dictionary=state.get("snapshot",{})
	if result.get("action",-1)!=sent.action or not valid_snapshot(observed,building_id) or outcome!=(C.FarmEditOutcome.Completed if editing else C.FarmEditOutcome.None):
		_fail(Phase.Unknown if editing else Phase.Rejected);return
	if editing and observed.forbidden!=(sent.door_forbidden==1):_fail(Phase.Unknown);return
	snapshot=observed.duplicate(true);phase=Phase.Ready;changed.emit()
	if editing:applied.emit()
