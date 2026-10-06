extends RefCounted
# Local geometry only. DF validates occupancy and owns the resulting footprint.
const Contract = preload("res://scripts/management_contract.gd")
var area: Dictionary = {}
var cells: Dictionary = {}
var original: Dictionary = {}
var z := -1
var map_size := Vector2i.ZERO
var prepared := false
var pending: Dictionary = {}
var stopped := false
var problem := ""
var geometry_generation := 0

func clear() -> void:
	geometry_generation += 1
	area = {}; cells = {}; original = {}; z = -1; prepared = false; pending = {}; stopped = false; problem = ""

static func footprint(observed: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var width := int(observed.get("width",0))
	var height := int(observed.get("height",0))
	var extents: PackedByteArray = observed.get("extents",PackedByteArray())
	if width <= 0 or height <= 0 or extents.size() != width * height: return result
	var origin: Vector3i = observed.origin
	for y in height:
		for x in width:
			if extents[y * width + x] != 0: result[Vector2i(origin.x+x,origin.y+y)] = true
	return result

func open(observed: Dictionary, bounds: Vector2i, level: int) -> void:
	clear(); area = observed.duplicate(true); map_size = bounds
	z = int(observed.origin.z) if not observed.is_empty() else level
	original = footprint(observed); cells = original.duplicate()

func rectangle(first: Vector3i, last: Vector3i, erase := false) -> bool:
	if stopped or not pending.is_empty() or prepared or first.z != z or last.z != z: return false
	var low := Vector2i(mini(first.x,last.x),mini(first.y,last.y))
	var high := Vector2i(maxi(first.x,last.x),maxi(first.y,last.y))
	if low.x < 0 or low.y < 0 or high.x >= map_size.x or high.y >= map_size.y: return false
	if high.x-low.x >= 256 or high.y-low.y >= 256: return false
	var next := cells.duplicate()
	for y in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			if erase: next.erase(Vector2i(x,y))
			else: next[Vector2i(x,y)] = true
	if not valid_size(next): return false
	if cells != next: geometry_generation += 1
	cells = next; problem = ""; return true

func stroke(first: Vector3i, last: Vector3i, erase := false) -> bool:
	if stopped or not pending.is_empty() or prepared or first.z != z or last.z != z: return false
	for point in [first,last]:
		if point.x < 0 or point.y < 0 or point.x >= map_size.x or point.y >= map_size.y: return false
	var next := cells.duplicate()
	var point := Vector2i(first.x,first.y)
	var end := Vector2i(last.x,last.y)
	var dx := absi(end.x-point.x); var dy := -absi(end.y-point.y)
	var sx := signi(end.x-point.x); var sy := signi(end.y-point.y)
	var error := dx+dy
	while true:
		if erase: next.erase(point)
		else: next[point] = true
		if point == end: break
		var twice := 2*error
		if twice >= dy: error += dy; point.x += sx
		if twice <= dx: error += dx; point.y += sy
	if not valid_size(next): return false
	if cells != next: geometry_generation += 1
	cells = next; problem = ""; return true

static func valid_size(value: Dictionary) -> bool:
	if value.size() > 32768: return false
	if value.is_empty(): return true
	var low: Vector2i = value.keys()[0]
	var high := low
	for point: Vector2i in value:
		low.x = mini(low.x,point.x); low.y = mini(low.y,point.y)
		high.x = maxi(high.x,point.x); high.y = maxi(high.y,point.y)
	return high.x-low.x < 256 and high.y-low.y < 256 and (high.x-low.x+1)*(high.y-low.y+1) <= 32768

static func spans_for(value: Dictionary) -> Array:
	var points := value.keys()
	points.sort_custom(func(a: Vector2i,b: Vector2i): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var spans: Array = []
	for point: Vector2i in points:
		if not spans.is_empty() and int(spans[-1].y) == point.y and int(spans[-1].x)+int(spans[-1].length) == point.x:
			spans[-1].length += 1
		else: spans.append({"x":point.x,"y":point.y,"length":1})
	return spans

func prepare() -> bool:
	if stopped or not pending.is_empty() or prepared: return false
	if cells.is_empty(): problem = "Erase would remove the whole area; use Remove"; return false
	if not area.is_empty() and int(area.get("revision",0)) <= 0:
		problem = "Inspect this area before changing it"; return false
	if cells == original: return false
	prepared = true; problem = ""
	return true

func next_request(kind := 0, zone_type := -1) -> Dictionary:
	if stopped or not pending.is_empty() or not prepared: return {}
	var request := {"spans":spans_for(cells),"paint_mode":1 if area.is_empty() else 3,
		"operation":Contract.AreaOperation.Paint,"paint_z":z}
	request.action = Contract.ManagementAction.AreaCreate if area.is_empty() else Contract.ManagementAction.AreaUpdate
	request.kind = kind if area.is_empty() else int(area.kind)
	if area.is_empty():
		if kind == 1: request.zone_type = zone_type
	else:
		request.id = int(area.id); request.expected_revision = int(area.revision)
	pending = request.duplicate(true)
	return request

func accept(observed: Dictionary) -> bool:
	if pending.is_empty() or stopped: return false
	if int(observed.get("revision",0)) <= 0 or int(observed.get("id",-1)) < 0 or int(observed.get("kind",-1)) != int(pending.kind):
		stop("Missing authoritative paint result"); return false
	if not area.is_empty() and int(observed.id) != int(area.id):
		stop("Paint result changed area identity"); return false
	area = observed.duplicate(true); pending = {}; prepared = false
	original = footprint(observed); cells = original.duplicate()
	geometry_generation += 1
	return true

func stop(reason: String) -> void:
	stopped = true; pending = {}
	problem = reason

func rebase(observed: Dictionary) -> void:
	geometry_generation += 1
	# Explicit recovery after inspection; regenerate differences, never replay.
	area = observed.duplicate(true); original = footprint(observed)
	prepared = false; pending = {}; stopped = false; problem = ""
