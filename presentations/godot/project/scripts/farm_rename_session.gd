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
var building_header:=false
var target_id: int=-1

func configure(owner_service,observed: Dictionary,independent_header:=false) -> void:
	service=owner_service;building_header=independent_header
	if service==null:_fail({});return
	if building_header:
		if typeof(observed.get("id"))!=TYPE_INT:_fail({});return
		target_id=observed.id
	else:
		if typeof(observed.get("building_id"))!=TYPE_INT or typeof(observed.get("selected_season"))!=TYPE_INT:_fail({});return
		validator.building_id=observed.building_id;validator.season=observed.selected_season;target_id=observed.building_id
	if not _valid(observed) or observed.removing:_fail({});return
	snapshot=observed.duplicate(true);desired=snapshot.custom_name
	service.session_changed.connect(_invalidated)

func _valid(observed: Dictionary) -> bool:
	if building_header:
		return preload("res://scripts/building_header_state.gd").valid_snapshot(observed,target_id) and observed.stage==observed.max_stage
	return validator.building_id>=0 and validator.season>=0 and validator.season<=3 and validator._valid(observed)

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
	var request: Dictionary={"action":C.ManagementAction.FarmEdit,"building_id":target_id,
		"expected_revision":snapshot.revision,"farm_operation":C.FarmOperation.Rename,"farm_name":desired}
	if building_header:request.building_header=true
	else:request.season=snapshot.selected_season
	ticket=service.submit_continuation(previous,"production",request,_received) if previous>0 else service.submit("production",request,_received)
	if ticket==0:_fail({})

func _received(receipt: int,result: Dictionary,request: Dictionary) -> void:
	if stopped or receipt!=ticket:return
	ticket=0
	var production: Dictionary=result.get("production",{})
	var header: Dictionary=production.get("building_header",{})
	var observed: Dictionary=header.get("snapshot",{}) if building_header else production.get("farm",{})
	var outcome=header.get("outcome") if building_header else production.get("farm_edit_outcome")
	if result.get("status",C.ManagementStatus.Rejected)!=C.ManagementStatus.Ok or result.get("outcome","")=="unknown" or outcome!=C.FarmEditOutcome.Completed:
		_fail(result);return
	if result.get("action")!=C.ManagementAction.FarmEdit or not _valid(observed) or observed.removing or observed.custom_name!=request.farm_name or (building_header and header.get("operation")!=C.FarmOperation.Rename):
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
