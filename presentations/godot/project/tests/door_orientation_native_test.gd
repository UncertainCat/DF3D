extends SceneTree
const Doors = preload("res://tests/door_orientation.gd")
class ReferenceSource:
	extends RefCounted
	var world
	func tile_hover_info(tile): return world.tile_hover_info(tile)
class Terrain:
	extends RefCounted
	var tiles := {}
	func tile_hover_info(tile): return {"shape": tiles.get(tile, "Floor")}

func run_pure_rules():
	var world := Terrain.new()
	var origin := Vector3i.ZERO
	world.tiles = {Vector3i.LEFT:"Wall", Vector3i.RIGHT:"Wall"}
	assert(Doors.resolve(world, origin).axis == "ew")
	world.tiles = {Vector3i.UP:"Wall", Vector3i.DOWN:"Wall"}
	assert(Doors.resolve(world, origin).axis == "ns")
	# A single jamb still anchors an endcap; no opposite jamb required.
	world.tiles = {Vector3i.UP:"Wall"}
	assert(Doors.resolve(world, origin).axis == "ns")
	world.tiles = {Vector3i.LEFT:"Wall"}
	assert(Doors.resolve(world, origin).axis == "ew")
	# Symmetric corners and freestanding doors have an explicit fixed fallback.
	world.tiles = {Vector3i.LEFT:"Wall", Vector3i.UP:"Wall"}
	assert(Doors.resolve(world, origin) == {"axis":"ew", "ambiguous":true})
	world.tiles = {}
	assert(Doors.resolve(world, origin).ambiguous)
	world.tiles = {Vector3i(0,2,0):"Wall", Vector3i(0,-2,0):"Wall"}
	assert(Doors.resolve(world, origin).axis == "ns")
	world.tiles = {Vector3i.LEFT:"Unknown", Vector3i.UP:"Empty"}
	assert(Doors.resolve(world, origin).ambiguous)
	for axis in ["ew", "ns"]:
		var transform := Doors.transform(axis, Vector3(0.5,0.1,0.5))
		assert(is_equal_approx((transform * Vector3(0,0,0.5)).y, 0.1))
		assert(is_equal_approx((transform * Vector3(0,0,-0.5)).y, 1.1))
		assert(transform.basis.x.is_equal_approx(Vector3.RIGHT if axis == "ew" else Vector3.BACK))

func _initialize(): call_deferred("run")

func run():
	run_pure_rules()
	var world := Df3dWorld.new()
	root.add_child(world)
	world.set_fixed_render_tick(1000)
	if not world.load_fixture(ProjectSettings.globalize_path("res://../../../fixtures/recorded/mature_fort_pause_53.16.df3dfix")):
		push_error("Door orientation fixture failed"); quit(1); return
	world.poll()
	var source := ReferenceSource.new()
	source.world = world
	var checked := 0
	# Include every orientation around map edges, hidden/unobserved elevations,
	# underground rooms, outdoor vegetation, and map-outside centers.
	for z in [-1, 0, 110, 127, 150, int(world.map_size().y)]:
		for x in range(-2, int(world.map_size().x) + 3, 7):
			for y in range(-2, int(world.map_size().z) + 3, 11):
				var tile := Vector3i(x, y, z)
				var expected: Dictionary = Doors.resolve(source, tile)
				if world.door_orientation(tile) != expected or Doors.resolve(world, tile) != expected:
					push_error("Native door orientation differs at " + str(tile)); quit(1); return
				checked += 1
	# Debug reveal must not turn hidden neighbors into orientation evidence.
	world.set_reveal_hidden(true)
	for x in range(0, int(world.map_size().x), 13):
		var tile := Vector3i(x, x % int(world.map_size().z), 110)
		if Doors.resolve(world, tile) != Doors.resolve(source, tile):
			push_error("Native door orientation exposes hidden evidence"); quit(1); return
		checked += 1
	world.free()
	print("DOOR_ORIENTATION_NATIVE_PASS comparisons=", checked)
	quit()
