extends RefCounted
# Presentation inference only. Never changes DF passage/pathfinding semantics.
# Axis names describe the panel span, perpendicular to travel through the door.
static func classify(world, tile: Vector3i) -> int:
	var info: Dictionary = world.tile_hover_info(tile)
	var shape: String = info.get("shape", "Unknown")
	if shape in ["Wall", "Fortification", "TreeTrunk"]: return 1
	if shape in ["Floor", "Ramp", "StairUp", "StairDown", "StairUpDown", "Boulder", "Pebbles", "Shrub", "Sapling"]: return -1
	return 0 # Hidden, unobserved and open space provide no orientation evidence.

static func resolve(world, tile: Vector3i) -> Dictionary:
	if world == null: return {"axis": "ew", "ambiguous": true}
	if world.has_method("door_orientation"): return world.door_orientation(tile)
	var neighbors: Array[int] = []
	var offsets := [Vector3i(1,0,0), Vector3i(-1,0,0), Vector3i(0,1,0), Vector3i(0,-1,0)]
	for offset in offsets: neighbors.append(classify(world, tile + offset))
	# Jambs outweigh distant evidence. A complete passage pair helps endcaps;
	# corners can remain ambiguous, rather than inventing a diagonal doorway.
	var ew := 0
	var ns := 0
	for i in 2:
		if neighbors[i] == 1: ew += 8
		if neighbors[i+2] == 1: ns += 8
	if neighbors[2] == -1 and neighbors[3] == -1: ew += 4
	if neighbors[0] == -1 and neighbors[1] == -1: ns += 4
	# A bounded second ring resolves some broad openings / missing jambs.
	for i in 4:
		if classify(world, tile + offsets[i] * 2) == 1:
			if i < 2: ew += 1
			else: ns += 1
	# Fixed tie break: independent of camera, entity iteration and client history.
	return {"axis": "ew" if ew >= ns else "ns", "ambiguous": ew == ns}

static func transform(axis: String, pivot: Vector3) -> Transform3D:
	var right := Vector3.RIGHT if axis == "ew" else Vector3.BACK
	var axes := Basis(right, right.cross(Vector3.UP) * (0.035 / 0.12), Vector3.DOWN)
	# Center thickness on the door tile; original image north becomes upright.
	return Transform3D(axes, pivot + Vector3.UP * 0.5 - axes.y * 0.06)
