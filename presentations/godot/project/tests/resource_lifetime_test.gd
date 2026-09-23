extends SceneTree
var failures := 0
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)
func _initialize(): call_deferred("run")
func run():
	var world := Df3dWorld.new()
	root.add_child(world)
	check(world.load_assets(OS.get_environment("DF3D_DF_PATH")), "installed assets load")
	var fixture := ProjectSettings.globalize_path("res://../../../build/resource-lifetime.df3dfix")
	var previous := -1
	var maximum_slots := 0
	for session in 3:
		var old_generation: int = world.session_generation()
		check(world.load_fixture(fixture), "synthetic appearance churn fixture loads")
		check(world.session_generation() != old_generation, "replacing fixture is a new source session")
		world.set_composite_budget_ms(0)
		world.set_replay_elapsed(0.5)
		world.poll()
		world.set_top_z(1)
		world.set_window_depth(3)
		for frame in 80:
			world.set_replay_elapsed(float(frame) + 0.5)
			world.poll()
			var slots: PackedInt32Array = world.unit_sprite_slots()
			check(slots.size() == 1 and slots[0] >= 0, "one composited resident remains rendered")
			if slots.is_empty(): continue
			var slot := slots[0]
			check(world.sprite_texture(slot) != null, "current resource handle resolves")
			if previous >= 0 and previous != slot:
				check(not world.sprite_slot_valid(previous), "historical appearance handle retires without alias")
			previous = slot
			world.sprite_cutout_mesh(slot, Color(0,0,1,1))
			var stats: Dictionary = world.sprite_resource_stats()
			maximum_slots = maxi(maximum_slots, stats.slots)
			check(stats.appearances <= 1 and stats.meshes <= 1, "native appearance resources plateau during churn")
		var revision: int = world.sprite_resource_revision()
		var collections: int = world.sprite_resource_stats().collections
		for unused in 20: world.poll()
		check(world.sprite_resource_stats().collections == collections, "unchanged paused frames perform no resource collection scans")
		check(world.load_assets(OS.get_environment("DF3D_DF_PATH")), "asset replacement succeeds")
		check(world.sprite_resource_revision() > revision and not world.sprite_slot_valid(previous), "asset replacement retires old handles")
		previous = -1
	check(maximum_slots < 12, "texture residency is bounded by current scene, not history")
	world.queue_free()
	await process_frame
	print("RESOURCE_LIFETIME_PASS" if failures == 0 else "RESOURCE_LIFETIME_FAIL")
	quit(failures)
