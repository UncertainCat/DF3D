extends RefCounted
# Local geometry only. DF validates occupancy and owns the resulting footprint.
var area: Dictionary = {}
var cells: Dictionary = {}
var original: Dictionary = {}
var z := -1
var map_size := Vector2i.ZERO
var stopped := false
var problem := ""
var geometry_generation := 0

func clear() -> void:
	geometry_generation += 1
	area = {}; cells = {}; original = {}; z = -1; stopped = false; problem = ""

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
	if stopped or first.z != z or last.z != z: return false
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

func stroke(_first: Vector3i, last: Vector3i, erase := false) -> bool:
	# Native stockpile and zone brush input samples the current pointer tile.
	return rectangle(last,last,erase)

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

func stop(reason: String) -> void:
	stopped = true
	problem = reason
