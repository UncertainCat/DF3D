extends RefCounted
signal changed
signal applied
const C=preload("res://scripts/management_contract.gd")
enum Phase { Closed, Reading, Ready, Applying, Rejected, Unknown, Unavailable }
var service
var phase:=Phase.Closed
var building_id: int=-1
var snapshot: Dictionary={}
var ticket:=0
var generation:=0
var pending_value: int=-1

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
	building_id=-1;snapshot={};pending_value=-1;phase=Phase.Closed;changed.emit()
func _session_changed() -> void:
	close();phase=Phase.Unavailable;changed.emit()
func open(id: int) -> void:
	close()
	if id<0 or id>2147483647:return
	building_id=id;refresh()
func refresh() -> void:
	if building_id<0 or ticket!=0:return
	snapshot={};phase=Phase.Reading
	_send({"action":C.ManagementAction.ProductionInspect,"workshop_orders":true,"building_id":building_id})
func step(delta: int) -> void:
	if phase!=Phase.Ready or ticket!=0 or delta not in [-1,1]:return
	phase=Phase.Applying
	_send({"action":C.ManagementAction.FarmEdit,"workshop_orders":true,"building_id":building_id,"expected_revision":snapshot.revision,"general_order_delta":delta})
func set_limit(value: int) -> void:
	if value<0 or value>99:return
	if phase==Phase.Applying:pending_value=value;return
	if phase!=Phase.Ready or ticket!=0:return
	pending_value=-1;phase=Phase.Applying
	_send({"action":C.ManagementAction.FarmEdit,"workshop_orders":true,"building_id":building_id,"expected_revision":snapshot.revision,"general_order_value":value})
func _send(intent: Dictionary) -> void:
	if service==null:_fail(Phase.Unavailable);return
	var owner:=generation
	ticket=service.submit("production",intent,func(received,result,sent):
		if owner==generation and received==ticket:_receive(result,sent))
	if ticket==0:_fail(Phase.Unavailable);return
	changed.emit()
func _fail(next: Phase) -> void:
	snapshot={};pending_value=-1;phase=next;changed.emit()
func _receive(result: Dictionary,sent: Dictionary) -> void:
	ticket=0
	var editing: bool=sent.action==C.ManagementAction.FarmEdit
	var value: Dictionary=result.get("production",{}).get("workshop_orders",{})
	if result.get("outcome","")=="unknown" or value.get("outcome",0)==C.FarmEditOutcome.Unknown:_fail(Phase.Unknown);return
	if result.get("status",-1)!=C.ManagementStatus.Ok:_fail(Phase.Rejected);return
	if result.get("action",-1)!=sent.action or value.get("building_id",-1)!=building_id or value.get("revision",0)<=0 or not value.get("order_ids") is Array:
		_fail(Phase.Unknown if editing else Phase.Rejected);return
	if editing:
		var absolute: int=sent.get("general_order_value",-1)
		var delta: int=sent.get("general_order_delta",0)
		var expected: int=absolute if absolute>=0 else clampi(int(snapshot.general_order_limit)+delta,0,99)
		if value.get("outcome",0)!=C.FarmEditOutcome.Completed or value.get("delta",0)!=delta or value.get("value",-1)!=absolute or value.get("general_order_limit",-1)!=expected:
			_fail(Phase.Unknown);return
	elif value.get("outcome",-1)!=C.FarmEditOutcome.None:_fail(Phase.Rejected);return
	snapshot=value.duplicate(true);phase=Phase.Ready;changed.emit()
	if editing:applied.emit()
	# A later local draft is a new intent, sent only after a confirmed receipt.
	# Failure clears it above; never retry a rejected or uncertain write.
	if pending_value>=0:
		var next:=pending_value;pending_value=-1;set_limit(next)
