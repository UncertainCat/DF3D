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
