extends Node
# Explicit text edits belong to the service, so closing the palette does not
# discard characters typed while a preceding write is in flight.
signal changed(area: Dictionary)
signal finished
signal failed(result: Dictionary)
const Contract = preload("res://scripts/management_contract.gd")
var service
var area: Dictionary = {}
var desired := ""
var ticket := 0
var ending := false
var stopped := false

func configure(owner_service, observed: Dictionary) -> void:
	service = owner_service; area = observed.duplicate(true)
	desired = str(area.custom_name)
	service.session_changed.connect(_invalidated)

func edit(value: String) -> void:
	if stopped or ending: return
	desired = value; _drain()

func finish() -> void:
	if stopped: return
	ending = true; _drain()

func _drain(previous := 0) -> void:
	if stopped or ticket != 0: return
	if desired == str(area.custom_name):
		if ending:
			_stop(); finished.emit(); queue_free()
		return
	var request := {"action":Contract.ManagementAction.AreaUpdate,"operation":Contract.AreaOperation.Rename,
		"kind":int(area.kind),"id":int(area.id),"expected_revision":int(area.revision),"name":desired}
	ticket = service.submit_continuation(previous,"areas",request,_received) if previous > 0 else service.submit("areas",request,_received)
	if ticket == 0: _fail({})

func _received(receipt: int, result: Dictionary, request: Dictionary) -> void:
	if stopped or receipt != ticket: return
	ticket = 0
	if int(result.get("status",0)) != Contract.ManagementStatus.Ok or str(result.get("outcome","")) == "unknown":
		_fail(result); return
	var rows: Array = result.get("areas",result.get("area",{}).get("areas",[]))
	if rows.size() != 1 or int(rows[0].get("id",-1)) != int(area.id) or int(rows[0].get("kind",-1)) != int(area.kind) or int(rows[0].get("revision",0)) <= 0 or rows[0].get("custom_name",null) != request.name:
		_fail(result); return
	area = rows[0].duplicate(true)
	_drain(receipt)
	changed.emit(area)

func _invalidated() -> void: _fail({})

func _stop() -> void:
	stopped = true
	if service.session_changed.is_connected(_invalidated): service.session_changed.disconnect(_invalidated)

func _fail(result: Dictionary) -> void:
	if stopped: return
	_stop(); desired = ""
	failed.emit(result); queue_free()
