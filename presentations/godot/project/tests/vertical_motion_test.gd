extends SceneTree
# Asset-free fixture regression: animation elevation survives physical stack
# allocation and subsequent cached animation frames. The independent worker
# depth manifest must agree at fractional render timestamps too.
var failures: Array[String] = []

func check(value: bool, message: String):
	if not value: failures.append(message)

func _initialize(): call_deferred("run")

func sample(world) -> Dictionary:
	var result := {}
	var ids: PackedInt64Array = world.unit_ids()
	var positions: PackedVector3Array = world.unit_positions()
	var cutouts: PackedVector3Array = world.unit_cutout_positions()
	var thickness: PackedFloat32Array = world.unit_thicknesses()
	check(ids.size() == 5 and cutouts.size() == 5, "all five motion cases remain visible")
	for i in ids.size():
		result[ids[i]] = {"position": positions[i], "cutout": cutouts[i], "thickness": thickness[i]}
	return result

func run():
	var world := Df3dWorld.new()
	root.add_child(world)
	world.set_fixed_render_tick(10)
	check(world.load_fixture(ProjectSettings.globalize_path("res://../../../build/vertical-motion.df3dfix")), "vertical motion fixture loads")
	world.poll()
	world.set_top_z(4)
	world.set_window_depth(5)
	world.poll()
	var initial := sample(world)
	var owner_tiles := {201:Vector3i(2,2,2),202:Vector3i(4,2,1),203:Vector3i(6,2,1),204:Vector3i(14,4,4),205:Vector3i(9,2,1)}
	var vertical_distances := {201: 1.0, 202: -1.0, 203: -3.0, 204: 3.0, 205: 0.0}
	for progress in [0.0, 0.25, 0.5, 0.75, 1.0]:
		world.set_fixed_render_tick(10.0 + progress)
		world.poll()
		var current := sample(world)
		for id in vertical_distances:
			if not initial.has(id) or not current.has(id): continue
			check(world.unit_tile(id)==owner_tiles[id],"unit %d picking retains authoritative tile at %.2f" % [id,progress])
			var before: Dictionary = initial[id]
			var now: Dictionary = current[id]
			var fraction: float = progress if id != 204 else (1.0 if progress == 1.0 else 0.0)
			var delta: float = vertical_distances[id] * fraction
			check(is_equal_approx(now.position.y - before.position.y, delta), "unit %d has expected evaluated elevation at %.2f" % [id, progress])
			check(is_equal_approx(now.cutout.y - before.cutout.y, delta), "unit %d cutout follows vertical motion at %.2f" % [id, progress])
			check(is_equal_approx(now.cutout.y - now.position.y, before.cutout.y - before.position.y), "unit %d retains authoritative stack offset" % id)
			check(now.thickness == before.thickness, "unit %d retains stack thickness" % id)
			check(now.cutout.x == now.position.x and now.cutout.z == now.position.z, "unit %d retains horizontal animation" % id)
		check(world.layout_matches_reference(), "independent layout oracle matches animated scene at %.2f" % progress)
		# Force synchronous depth reallocation at the same fractional timestamp.
		world.clear_layout_cache()
		world.poll()
		check(sample(world) == current, "fresh allocation preserves cached animation at %.2f" % progress)
		world.clear_layout_cache()
		world.poll()
		check(sample(world) == current, "restored cache preserves animated height at %.2f" % progress)
	var final := sample(world)
	var items: PackedVector3Array = world.item_physical_layout().positions
	var item_thickness: PackedFloat32Array = world.item_physical_layout().thicknesses
	check(items.size() == 2, "quantity stack contains two supporting item pieces")
	if final.has(201):
		for i in items.size():
			check(final[201].cutout.y >= items[i].y + item_thickness[i], "arriving unit stands above supporting item pieces")
	# Range changes must refresh arrays at the same fixed timestamp, before art
	# preparation, including units at the bottom boundary and restored IDs.
	world.set_sprite_depth(1)
	world.poll()
	check(world.unit_ids() == PackedInt64Array([204]), "one-level sprite range retains selected-level unit")
	world.set_sprite_depth(3)
	world.poll()
	check(world.unit_ids().size() == 2 and 201 in world.unit_ids() and 204 in world.unit_ids(), "sprite range includes bottom level and excludes next level")
	check(world.layout_matches_reference(), "limited sprite layout matches full semantic reference")
	world.set_top_z(2)
	world.set_sprite_depth(1)
	world.poll()
	check(world.unit_ids() == PackedInt64Array([201]), "sprite range follows selected level while paused")
	world.set_top_z(4)
	world.set_sprite_depth(0)
	world.poll()
	check(sample(world) == final, "disabling range restores exact unit presentation")
	world.set_window_depth(1)
	world.poll()
	check(world.unit_ids() == PackedInt64Array([204]), "terrain depth also refreshes paused unit membership")
	world.set_window_depth(0)
	world.poll()
	check(world.get_window_depth() == 5 and sample(world) == final, "automatic depth restores full current map")
	world.free()
	for failure in failures: push_error(failure)
	print("VERTICAL_MOTION_TEST_PASS" if failures.is_empty() else "VERTICAL_MOTION_TEST_FAIL")
	quit(0 if failures.is_empty() else 1)
