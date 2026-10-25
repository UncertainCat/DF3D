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
var area_kind := 1
var ticket := 0
var ending := ""
var stopped := false
var _queue: Array[Dictionary] = []
var _deleting := false
var _initial_hit_started := false
var _initial_hit := Vector3i()

func resolve_initial_hit(tile: Vector3i) -> void:
	if stopped or _initial_hit_started or area_kind != 0 or not area.is_empty(): return
	_initial_hit_started = true; _initial_hit = tile
	_read_initial_hit(0)

func _read_initial_hit(cursor: int) -> void:
	ticket = service.submit("areas",{"action":Contract.ManagementAction.AreaInspectAtTile,"origin":_initial_hit,"cursor":cursor},_initial_hit_received)
	if ticket == 0: _fail({})

func _initial_hit_received(receipt: int, result: Dictionary, request: Dictionary) -> void:
	if stopped or receipt != ticket: return
	ticket = 0
	if int(result.get("status",Contract.ManagementStatus.Rejected)) != Contract.ManagementStatus.Ok or str(result.get("outcome","")) == "unknown":
		_fail(result); return
	for observed in result.get("areas",[]):
		if int(observed.get("kind",-1)) == 0:
			# Selecting an existing pile never applies the queued creation strokes.
			_queue.clear(); area = observed.duplicate(true)
			if ending.is_empty() or ending == "accept": ending = "inspect"
			_complete(); return
	var cursor := int(result.get("area_next_cursor",0))
	if cursor != 0:
		if cursor <= int(request.cursor): _fail({}); return
		_read_initial_hit(cursor); return
	_drain()
	changed.emit()

func configure(owner_service, observed: Dictionary, type: int, bounds: Vector2i, level: int, kind := 1) -> void:
	service = owner_service
	area = observed.duplicate(true)
	created_here = observed.is_empty()
	zone_type = type
	area_kind = int(observed.get("kind",kind))
	geometry.open(observed,bounds,level)
	service.session_changed.connect(_session_changed)

func rectangle(first: Vector3i, last: Vector3i, erase := false) -> bool:
	if stopped or not ending.is_empty(): return false
	if not geometry.rectangle(first,last,erase): return false
	var spans: Array = []
	for y in range(mini(first.y,last.y),maxi(first.y,last.y)+1):
		spans.append({"x":mini(first.x,last.x),"y":y,"length":absi(first.x-last.x)+1})
	_enqueue_gesture(spans,erase)
	return true

func can_follow_elevation() -> bool:
	return not stopped and ending.is_empty() and area.is_empty() and geometry.cells.is_empty() and ticket == 0 and _queue.is_empty()

func stroke(_first: Vector3i, last: Vector3i, erase := false) -> bool:
	if stopped or not ending.is_empty(): return false
	# Native082230 samples the current held-pointer tile; it does not fill an
	# interpolated line between sparse motion events.
	if not geometry.stroke(last,last,erase): return false
	_enqueue_gesture([{"x":last.x,"y":last.y,"length":1}],erase)
	return true

func _enqueue_gesture(spans: Array, erase: bool) -> void:
	# Retain explicit intent, not differences against speculative cells: DF may
	# trim an earlier gesture before a later overlapping one reaches it.
	var gesture := {"mode":2 if erase else 1,"spans":spans}
	# Repeated held-pointer samples can share the latest unsent intent.
	if _queue.is_empty() or _queue[-1] != gesture: _queue.append(gesture)
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
			"kind":area_kind,"operation":Contract.AreaOperation.Paint,"paint_mode":gesture.mode,
			"paint_z":geometry.z,"spans":gesture.spans}
		if area.is_empty():
			if area_kind == 1: request.zone_type = zone_type
		else:
			request.id = int(area.id); request.expected_revision = int(area.revision)
	elif not ending.is_empty():
		if ending == "accept" and Geometry.footprint(area).is_empty():
			# Speculative additions can be trimmed by DF. Empty native Paint has
			# no Accept action; keep the interaction available for another gesture.
			ending = ""; changed.emit(); return
		if not area.is_empty() and (ending in ["cancel","remove","multi"] or (ending == "exit" and Geometry.footprint(area).is_empty())):
			_deleting = true
			request = {"action":Contract.ManagementAction.AreaDelete,"kind":area_kind,"id":int(area.id),"expected_revision":int(area.revision)}
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
	if rows.is_empty() and area.is_empty() and area_kind == 0 and int(_request.get("action",-1)) == Contract.ManagementAction.AreaCreate and result.get("building_id") == -1:
		# Successful all-clipped creation publishes no identity. It is not a
		# rejection or unknown outcome, and must not replay the consumed gesture.
		if _queue.is_empty(): _initial_hit_started = false
		_reconcile(); _drain(receipt); return
	if rows.size() != 1:
		_fail(result); return
	var observed: Dictionary = rows[0]
	if int(observed.get("kind",-1)) != area_kind or int(observed.get("id",-1)) < 0 or int(observed.get("revision",0)) <= 0 or (not area.is_empty() and int(observed.id) != int(area.id)):
		_fail(result); return
	area = observed.duplicate(true)
	_reconcile()
	_drain(receipt)

func _reconcile() -> void:
	geometry.area = area.duplicate(true)
	geometry.original = Geometry.footprint(area)
	geometry.cells = geometry.original.duplicate()
	for gesture in _queue:
		for span in gesture.spans:
			for x in range(int(span.x),int(span.x)+int(span.length)):
				var point := Vector2i(x,int(span.y))
				if int(gesture.mode) == 2: geometry.cells.erase(point)
				else: geometry.cells[point] = true
	geometry.geometry_generation += 1
	changed.emit()

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
