extends Node
# Service-owned explicit typing survives panel closure. Only confirmed receipts
# authorize buffered edits; uncertainty discards them without replay.
signal changed(snapshot: Dictionary)
signal finished
signal failed(result: Dictionary)
const C=preload("res://scripts/management_contract.gd")
var service
var snapshot: Dictionary={}
var desired: String=""
var ticket:=0
var ending:=false
var stopped:=false
var receiving:=false
var detail_index: int=-1
func configure(source,observed: Dictionary) -> void:
	service=source
	if service==null or typeof(observed.get("index"))!=TYPE_INT:_fail({});return
	detail_index=observed.index
	if not _valid(observed):_fail({});return
	snapshot=observed.duplicate(true);desired=snapshot.name
	service.session_changed.connect(_invalidated)
func _valid(value: Dictionary) -> bool:
	return typeof(value.get("index"))==TYPE_INT and value.index==detail_index and detail_index>=0 and detail_index<128 and typeof(value.get("revision"))==TYPE_INT and value.revision>0 and typeof(value.get("name"))==TYPE_STRING and value.name.to_utf8_buffer().size()<=160
func edit(value: String) -> bool:
	if stopped or ending or value.length()>40 or value.to_utf8_buffer().has(0):return false
	desired=value;_drain();return true
func finish() -> void:
	if stopped:return
	ending=true;_drain()
func _drain(previous:=0) -> void:
	if stopped or receiving or ticket!=0:return
	if desired==snapshot.name:
		if ending:_stop();finished.emit();queue_free()
		return
	var request: Dictionary={"action":C.ManagementAction.WorkDetailEdit,"detail_index":detail_index,"expected_revision":snapshot.revision,"edit":1,"name":desired}
	ticket=service.submit_continuation(previous,"citizens",request,_received) if previous>0 else service.submit("citizens",request,_received)
	if ticket==0:_fail({})
func _received(receipt: int,result: Dictionary,request: Dictionary) -> void:
	if stopped or receipt!=ticket:return
	ticket=0
	if result.get("status")!=C.ManagementStatus.Ok or result.get("outcome","")=="unknown":_fail(result);return
	var rows: Array=result.get("citizen",{}).get("details",[])
	if result.get("action")!=C.ManagementAction.WorkDetailEdit or rows.size()!=1 or not _valid(rows[0]) or rows[0].name!=request.name:
		var uncertain:=result.duplicate(true);uncertain.outcome="unknown";_fail(uncertain);return
	snapshot=rows[0].duplicate(true)
	receiving=true;changed.emit(snapshot.duplicate(true));receiving=false
	_drain(receipt)
func _invalidated() -> void:_fail({"outcome":"unknown"})
func _stop() -> void:
	stopped=true
	if service!=null:
		if service.session_changed.is_connected(_invalidated):service.session_changed.disconnect(_invalidated)
		if ticket!=0:service.detach(ticket)
	ticket=0
func _fail(result: Dictionary) -> void:
	if stopped:return
	_stop();desired="";snapshot={};failed.emit(result.duplicate(true));queue_free()
func _exit_tree() -> void:_stop()
