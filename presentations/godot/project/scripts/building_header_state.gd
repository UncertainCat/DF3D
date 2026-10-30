extends RefCounted
# One building's independently revisioned header authority; DF owns all effects.
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
	building_id=id;_read()

func refresh() -> void:
	if building_id<0 or ticket!=0 or phase in [Phase.Closed,Phase.Unavailable]:return
	_read()

func _read() -> void:
	snapshot={};phase=Phase.Reading
	_send({"action":C.ManagementAction.ProductionInspect,"building_header":true,"building_id":building_id})

func rename(value: String) -> void:
	var bytes:=value.to_utf8_buffer()
	if bytes.size()>90 or bytes.has(0):return
	_edit(C.FarmOperation.Rename,{"farm_name":value})

func request_removal() -> void:_edit(C.FarmOperation.Remove,{})
func cancel_removal() -> void:_edit(C.FarmOperation.CancelRemoval,{})

func _edit(operation: int,fields: Dictionary) -> void:
	if phase!=Phase.Ready or ticket!=0 or snapshot.is_empty() or snapshot.stage!=snapshot.max_stage:return
	if snapshot.removing!=(operation==C.FarmOperation.CancelRemoval):return
	var intent={"action":C.ManagementAction.FarmEdit,"building_header":true,"building_id":building_id,
		"expected_revision":snapshot.revision,"farm_operation":operation}
	intent.merge(fields);phase=Phase.Applying;_send(intent)

func _send(intent: Dictionary) -> void:
	var owner:=generation
	ticket=service.submit("production",intent,func(received,result,sent):
		if owner==generation and received==ticket:_receive(result,sent))
	if ticket==0:_fail(Phase.Unavailable);return
	changed.emit()

func _fail(next: Phase) -> void:
	phase=next;snapshot={};changed.emit()

static func valid_snapshot(value: Dictionary,id: int) -> bool:
	for field in ["id","type","revision","stage","max_stage"]:
		if typeof(value.get(field))!=TYPE_INT:return false
	if value.id!=id or id<0 or id>2147483647 or value.type!=10 or value.revision<=0 or value.stage<0 or value.max_stage<value.stage or value.max_stage>2147483647:return false
	for field in ["custom_name","native_name","header_name"]:
		if typeof(value.get(field))!=TYPE_STRING:return false
		var bytes: PackedByteArray=value[field].to_utf8_buffer()
		if bytes.size()>1536 or bytes.has(0) or (field!="custom_name" and bytes.is_empty()):return false
	for field in ["removing","suspended","has_worker"]:
		if typeof(value.get(field))!=TYPE_BOOL:return false
	return value.removing or (not value.suspended and not value.has_worker)

func _receive(result: Dictionary,sent: Dictionary) -> void:
	ticket=0
	var editing: bool=sent.action==C.ManagementAction.FarmEdit
	var state: Dictionary=result.get("production",{}).get("building_header",{})
	var outcome: int=state.get("outcome",C.FarmEditOutcome.None)
	if result.get("outcome","")=="unknown" or outcome==C.FarmEditOutcome.Unknown:_fail(Phase.Unknown);return
	if result.get("status",C.ManagementStatus.Rejected)!=C.ManagementStatus.Ok:
		_fail(Phase.Stale if editing and outcome==C.FarmEditOutcome.Stale else Phase.Rejected);return
	var observed: Dictionary=state.get("snapshot",{})
	var operation: int=state.get("operation",-1)
	if result.get("action",-1)!=sent.action or not valid_snapshot(observed,building_id) or \
		outcome!=(C.FarmEditOutcome.Completed if editing else C.FarmEditOutcome.None) or \
		operation!=(sent.farm_operation if editing else C.FarmOperation.Crop):
		_fail(Phase.Unknown if editing else Phase.Rejected);return
	if editing:
		if observed.stage!=observed.max_stage or observed.removing!=(operation==C.FarmOperation.Remove) or \
			(operation==C.FarmOperation.Rename and observed.custom_name!=sent.farm_name):
			_fail(Phase.Unknown);return
	snapshot=observed.duplicate(true);phase=Phase.Ready;changed.emit()
	if editing:applied.emit()
