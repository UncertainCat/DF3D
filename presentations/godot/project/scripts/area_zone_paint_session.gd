extends Node
# The action service owns this node, not the panel. Completed gestures survive
# view closure; unknown outcomes stay with the service and are never replayed.
signal changed
signal finished(destination: String, observed: Dictionary)
signal failed(result: Dictionary)
const Contract = preload("res://scripts/management_contract.gd")
const Geometry = preload("res://scripts/area_paint_state.gd")
var geometry = Geometry.new()
var service
var area: Dictionary = {}
var created_here := false
var zone_type := -1
var ticket := 0
var ending := ""
var stopped := false
var _queue: Array[Dictionary] = []
var _deleting := false

func configure(owner_service, observed: Dictionary, type: int, bounds: Vector2i, level: int) -> void:
	service = owner_service
	area = observed.duplicate(true)
	created_here = observed.is_empty()
	zone_type = type
	geometry.open(observed,bounds,level)
	service.session_changed.connect(_session_changed)

func rectangle(first: Vector3i, last: Vector3i, erase := false) -> bool:
	if stopped or not ending.is_empty(): return false
	var before: Dictionary = geometry.cells.duplicate()
	if not geometry.rectangle(first,last,erase): return false
	_enqueue_difference(before,erase)
	return true

func can_follow_elevation() -> bool:
	return not stopped and ending.is_empty() and area.is_empty() and geometry.cells.is_empty() and ticket == 0 and _queue.is_empty()

func stroke(_first: Vector3i, last: Vector3i, erase := false) -> bool:
	if stopped or not ending.is_empty(): return false
	var before: Dictionary = geometry.cells.duplicate()
	# Native082230 samples the current held-pointer tile; it does not fill an
	# interpolated line between sparse motion events.
	if not geometry.stroke(last,last,erase): return false
	_enqueue_difference(before,erase)
	return true

func _enqueue_difference(before: Dictionary, erase: bool) -> void:
	var delta: Dictionary = {}
	var source: Dictionary = before if erase else geometry.cells
	var other: Dictionary = geometry.cells if erase else before
	for point in source:
		if not other.has(point): delta[point] = true
	if not delta.is_empty():
		_queue.append({"mode":2 if erase else 1,"spans":Geometry.spans_for(delta)})
	_drain()
	changed.emit()

func finish(destination: String) -> bool:
	if stopped or not ending.is_empty(): return false
	if destination not in ["accept","exit","cancel","remove","multi"]: return false
	if destination == "accept" and geometry.cells.is_empty(): return false
	if destination in ["cancel","multi"] and not created_here: return false
	ending = destination
	# Native Cancel rolls back the new zone. No later queued geometry needs to
	# run, but an in-flight creation must resolve before its identity is removed.
	if destination in ["cancel","remove","multi"]: _queue.clear()
	_drain()
	changed.emit()
	return true

func _drain(previous := 0) -> void:
	if stopped or ticket != 0: return
	var request: Dictionary = {}
	if not _queue.is_empty():
		var gesture: Dictionary = _queue.pop_front()
		# Erasing an empty, never-created interaction is a local no-op.
		if area.is_empty() and int(gesture.mode) == 2:
			_drain(previous); return
		request = {"action":Contract.ManagementAction.AreaCreate if area.is_empty() else Contract.ManagementAction.AreaUpdate,
			"kind":1,"operation":Contract.AreaOperation.Paint,"paint_mode":gesture.mode,
			"paint_z":geometry.z,"spans":gesture.spans}
		if area.is_empty(): request.zone_type = zone_type
		else:
			request.id = int(area.id); request.expected_revision = int(area.revision)
	elif not ending.is_empty():
		if not area.is_empty() and (ending in ["cancel","remove","multi"] or (ending == "exit" and Geometry.footprint(area).is_empty())):
			_deleting = true
			request = {"action":Contract.ManagementAction.AreaDelete,"kind":1,"id":int(area.id),"expected_revision":int(area.revision)}
		else:
			_complete(); return
	else: return
	ticket = service.submit_continuation(previous,"areas",request,_received) if previous > 0 else service.submit("areas",request,_received)
	if ticket == 0: _fail({})

func _received(receipt: int, result: Dictionary, _request: Dictionary) -> void:
	if stopped or receipt != ticket: return
	ticket = 0
	if int(result.get("status",Contract.ManagementStatus.Rejected)) != Contract.ManagementStatus.Ok or str(result.get("outcome","")) == "unknown":
		_fail(result); return
	if _deleting:
		area = {}; _complete(); return
	var rows: Array = result.get("areas",result.get("area",{}).get("areas",[]))
	if rows.size() != 1:
		_fail(result); return
	var observed: Dictionary = rows[0]
	if int(observed.get("kind",-1)) != 1 or int(observed.get("id",-1)) < 0 or int(observed.get("revision",0)) <= 0 or (not area.is_empty() and int(observed.id) != int(area.id)):
		_fail(result); return
	area = observed.duplicate(true)
	geometry.area = area.duplicate(true)
	geometry.original = Geometry.footprint(area)
	if _queue.is_empty():
		geometry.cells = geometry.original.duplicate()
		geometry.geometry_generation += 1
	changed.emit()
	_drain(receipt)

func _session_changed() -> void:
	# No work crosses epochs. The service separately retains sent receipts.
	_fail({})

func _fail(result: Dictionary) -> void:
	if stopped: return
	stopped = true; geometry.stopped = true; _queue.clear()
	_disconnect()
	failed.emit(result.duplicate(true))
	queue_free()

func _complete() -> void:
	stopped = true
	_disconnect()
	finished.emit(ending,area.duplicate(true))
	queue_free()

func _disconnect() -> void:
	if service != null and service.session_changed.is_connected(_session_changed):
		service.session_changed.disconnect(_session_changed)
