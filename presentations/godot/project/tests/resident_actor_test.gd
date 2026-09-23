extends SceneTree
# Semantic intervals and paged residency have independent clocks and ownership.
var failures: Array[String] = []
func check(ok: bool, label: String):
	if not ok: failures.append(label); push_error(label)
func _initialize(): call_deferred("run")
func run():
	var pool = load("res://scripts/actor_motion_pool.gd").new()
	pool.reset(1)
	for id in 65:
		pool.write(id, Color(id,0,0,10), Color(id,1,0,11), Vector2.ZERO, Vector3(id,0,0),0)
	pool.flush()
	check(pool.pages.size() == 3 and pool.uploads == 3, "three bounded pages uploaded")
	var bytes: int = pool.upload_bytes
	for id in 65:
		pool.write(id, Color(id,0,0,10), Color(id,1,0,11), Vector2.ZERO, Vector3(id,0,0),0)
	pool.flush()
	check(pool.upload_bytes == bytes, "unchanged observations upload nothing")
	pool.write(40, Color(40,0,0,10), Color(40,2,0,11), Vector2.ZERO, Vector3(40,0,0),0)
	pool.flush()
	check(pool.upload_bytes - bytes == 2048, "one changed actor updates only its page")
	var survivors := PackedInt64Array()
	for id in 65:
		if id != 40: survivors.append(id)
	var address: int = pool.slots[40]
	pool.retain(survivors)
	check(pool.slot_for(100) == address and pool.slots[41] == 41, "departed slot reused without moving live actors")
	var demand = load("res://scripts/unit_demand.gd").new()
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0,0,10)
	camera.current = true
	demand.update_view(camera)
	check(demand.visible(AABB(Vector3(-1,-1,-1),Vector3(2,2,2))), "frustum includes forward box")
	check(not demand.visible(AABB(Vector3(0,0,20),Vector3.ONE)), "frustum excludes box behind camera")
	demand.changed("actor", AABB(Vector3(0,0,20),Vector3.ONE))
	check(demand.stale("actor"), "hidden changes retain stale state")
	camera.rotation.y = PI
	check(demand.update_view(camera), "reveal requests latest hidden data")
	var layer := MultiMeshInstance3D.new()
	root.add_child(layer)
	demand.prepared("actor",layer)
	camera.rotation.y = 0
	demand.update_view(camera)
	camera.rotation.y = PI
	check(not demand.update_view(camera) and layer.visible, "valid resident reveal performs no preparation")
	var world := Df3dWorld.new()
	root.add_child(world)
	world.set_fixed_render_tick(10.25)
	check(world.load_fixture(ProjectSettings.globalize_path("res://../../../build/vertical-motion.df3dfix")), "motion fixture opens")
	world.set_top_z(4); world.set_window_depth(5); world.poll()
	var revision: int = world.unit_render_revision()
	var original: PackedVector3Array = world.unit_positions()
	for tick in [10.25,10.5,10.75]:
		world.set_fixed_render_tick(tick); world.poll()
		var first: PackedColorArray = world.unit_motion_from()
		var last: PackedColorArray = world.unit_motion_to()
		var epochs: PackedVector2Array = world.unit_motion_epochs()
		var positions: PackedVector3Array = world.unit_positions()
		check(world.unit_render_revision() == revision, "fractional clock does not invalidate actor payloads")
		check(world.unit_render_delta(revision).indices.is_empty(), "clock-only delta is empty")
		for i in positions.size():
			var start := epochs[i].x * 4096.0 + first[i].a
			var end := epochs[i].y * 4096.0 + last[i].a
			var alpha: float = clampf((tick-start)/(end-start),0,1) if end>start else 0.0
			var position := Vector3(first[i].r,first[i].g,first[i].b).lerp(Vector3(last[i].r,last[i].g,last[i].b),alpha)
			# Legacy unit_positions exposes marker centers: floor .1 + half cube .4.
			check((position + Vector3(0,.5,0)).is_equal_approx(positions[i]), "GPU interval reconstruction matches CPU interaction position")
	check(world.unit_positions() != original, "semantic interaction positions still advance")
	check(world.unit_render_delta(-1).full, "lost delta baseline requests full data")
	world.free(); camera.free(); layer.free()
	print("RESIDENT_ACTOR_TEST_PASS" if failures.is_empty() else "RESIDENT_ACTOR_TEST_FAIL")
	quit(0 if failures.is_empty() else 1)
