extends Node
# Parent this to the action service, not the sheet. Explicit typing survives
# closing the sheet; only confirmed receipts authorize a continuation.
signal changed(snapshot: Dictionary)
signal finished
signal failed(result: Dictionary)
const C=preload("res://scripts/management_contract.gd")
var validator=preload("res://scripts/farm_state.gd").new()
var service
var snapshot: Dictionary={}
var desired: String=""
var ticket:=0
var ending:=false
var stopped:=false
var receiving:=false

func configure(owner_service,observed: Dictionary) -> void:
	service=owner_service
	if service==null or typeof(observed.get("building_id"))!=TYPE_INT or typeof(observed.get("selected_season"))!=TYPE_INT:
		_fail({});return
	validator.building_id=observed.building_id;validator.season=observed.selected_season
	if validator.building_id<0 or validator.season<0 or validator.season>3 or not validator._valid(observed) or observed.removing:
		_fail({});return
	snapshot=observed.duplicate(true);desired=snapshot.custom_name
	service.session_changed.connect(_invalidated)

func edit(value: String) -> bool:
	var bytes:=value.to_utf8_buffer()
	if stopped or ending or bytes.size()>90 or bytes.has(0):return false
	desired=value;_drain();return true

func finish() -> void:
	if stopped:return
	ending=true;_drain()

func _drain(previous:=0) -> void:
	if stopped or receiving or ticket!=0:return
	if desired==snapshot.custom_name:
		if ending:_stop();finished.emit();queue_free()
		return
	var request: Dictionary={"action":C.ManagementAction.FarmEdit,"building_id":snapshot.building_id,
		"season":snapshot.selected_season,"expected_revision":snapshot.revision,
		"farm_operation":C.FarmOperation.Rename,"farm_name":desired}
	ticket=service.submit_continuation(previous,"production",request,_received) if previous>0 else service.submit("production",request,_received)
	if ticket==0:_fail({})

func _received(receipt: int,result: Dictionary,request: Dictionary) -> void:
	if stopped or receipt!=ticket:return
	ticket=0
	var production: Dictionary=result.get("production",{})
	var observed: Dictionary=production.get("farm",{})
	if result.get("status",C.ManagementStatus.Rejected)!=C.ManagementStatus.Ok or result.get("outcome","")=="unknown" or production.get("farm_edit_outcome")!=C.FarmEditOutcome.Completed:
		_fail(result);return
	if result.get("action")!=C.ManagementAction.FarmEdit or not validator._valid(observed) or observed.removing or observed.custom_name!=request.farm_name:
		var uncertain:=result.duplicate(true);uncertain.outcome="unknown";_fail(uncertain);return
	snapshot=observed.duplicate(true)
	# Observers may finish or type again synchronously. Preserve continuation
	# priority until their changes are incorporated, without submitting twice.
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

func _exit_tree() -> void:
	_stop()
