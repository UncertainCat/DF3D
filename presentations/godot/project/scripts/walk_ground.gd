extends RefCounted
# Local visitor movement over WorldModel queries. Never sends simulation commands.
const FLOOR := 0.1
const RADIUS := 0.18
var world
var _tiles: Dictionary = {}

func begin_step() -> void:
	_tiles.clear()

func info(tile: Vector3i) -> Dictionary:
	if not _tiles.has(tile): _tiles[tile] = world.tile_hover_info(tile)
	return _tiles[tile]

func shape(tile: Vector3i) -> String:
	return str(info(tile).get("shape", "Unknown"))

func surface(point: Vector3, level: int) -> float:
	var tile := Vector3i(floori(point.x), floori(point.z), level)
	var kind := shape(tile)
	if int(info(tile).get("liquid_level", 0)) >= 4: return NAN
	if kind in ["Floor", "StairUp", "StairDown", "StairUpDown", "Shrub", "Sapling", "Boulder", "Pebbles"]:
		return level + FLOOR
	if kind == "Ramp":
		# Same N/E/S/W wall preference as the terrain mesher.
		var local := Vector2(point.x - floorf(point.x), point.z - floorf(point.z))
		var dirs := [Vector3i(0,-1,0), Vector3i(1,0,0), Vector3i(0,1,0), Vector3i(-1,0,0)]
		var heights := [1.0-local.y, local.x, local.y, 1.0-local.x]
		for i in range(4):
			if shape(tile + dirs[i]) in ["Wall", "Fortification", "TreeTrunk"]: return level + lerpf(FLOOR, 1.0, heights[i])
		return level + 0.5
	return NAN

func support(point: Vector3) -> float:
	var best := NAN
	for level in range(floori(point.y)-1, floori(point.y)+2):
		var height := surface(point, level)
		if not is_nan(height) and absf(height-point.y) <= 0.30:
			if is_nan(best) or absf(height-point.y) < absf(best-point.y): best = height
	return best

func can_stand(point: Vector3) -> bool:
	for offset in [Vector2(-RADIUS,-RADIUS), Vector2(RADIUS,-RADIUS), Vector2(-RADIUS,RADIUS), Vector2(RADIUS,RADIUS)]:
		var probe := point + Vector3(offset.x,0,offset.y)
		if is_nan(support(probe)): return false
		var tile := Vector3i(floori(probe.x), floori(probe.z), floori(point.y + preload("res://scripts/actor_view_scale.gd").WALK_EYE))
		if shape(tile) in ["Unknown", "Wall", "Fortification", "TreeTrunk"]: return false
	return true

func spawn_near(point: Vector3, level: int) -> Vector3:
	begin_step()
	for radius in range(25):
		for x in range(-radius, radius+1):
			for y in range(-radius, radius+1):
				if maxi(absi(x), absi(y)) != radius: continue
				var next := Vector3(floorf(point.x)+x+0.5, 0, floorf(point.z)+y+0.5)
				next.y = surface(next, level)
				if is_nan(next.y) or not can_stand(next): continue
				# Starting inside a dwarf or door fills the whole first-person view.
				var occupied := false
				if world.has_method("inspect_tile"):
					for entity in world.inspect_tile(Vector3i(floori(next.x),floori(next.z),level)):
						if int(entity.get("kind",0)) in [1,3]: occupied = true
				if not occupied: return next
	return Vector3(NAN,NAN,NAN)
