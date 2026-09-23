extends SceneTree
# Exercise the real scene consumer with the generated appearance-churn fixture.
# Runs with headless or GPU rendering; no renderer/threading overrides.
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize(): call_deferred("run")
func run():
	var fixture := ProjectSettings.globalize_path("res://../../../build/resource-lifetime.df3dfix")
	OS.set_environment("DF3D_FIXTURE", fixture)
	OS.set_environment("DF3D_FIXTURE_TICK", "")
	OS.set_environment("DF3D_FIXTURE_SPEED", "0")
	OS.set_environment("DF3D_TOP_Z", "1")
	OS.set_environment("DF3D_WINDOW", "3")
	OS.set_environment("DF3D_COMPOSITE_BUDGET", "0")
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene._unit_demand.enabled = false
	var world: Df3dWorld = scene.world
	check(world.assets_loaded(), "scene assets load")
	var previous_material: WeakRef
	var previous_slot := -1
	for session in 3:
		if session > 0: check(world.load_fixture(fixture), "scene source replacement succeeds")
		for frame in 80:
			world.set_replay_elapsed(float(frame) + 0.5)
			scene._process(0.0)
			await process_frame
			check(scene._sprite_layers.size() == 1, "scene keeps one resident sprite layer")
			check(scene._cutout_resources.size() == 1, "scene material and contour cache plateaus")
			if scene._sprite_layers.is_empty(): continue
			var node: MultiMeshInstance3D = scene._sprite_layers.values()[0]
			var slot: int = node.get_meta("sprite_slot")
			check(world.sprite_slot_valid(slot), "scene never keeps a retired slot")
			check(node.material_override.get_shader_parameter("sprite_tex") == world.sprite_texture(slot), "scene material uses current native texture")
			check(node.multimesh.mesh != null and node.multimesh.instance_count == 1, "scene retains current contour and instance payload")
			if previous_material != null and previous_slot != slot:
				check(previous_material.get_ref() == null, "old scene material releases after appearance or session replacement")
			previous_material = weakref(node.material_override)
			previous_slot = slot
			check(scene._instance_uploads._layers.size() <= 2 and scene._instance_uploads._region_keys.size() <= 1, "scene auxiliary caches plateau")
		var old_slot := previous_slot
		check(world.load_assets(OS.get_environment("DF3D_DF_PATH")), "scene asset replacement succeeds")
		scene._process(0.0)
		await process_frame
		check(not world.sprite_slot_valid(old_slot), "asset replacement cannot alias a prior scene handle")
		check(previous_material.get_ref() == null, "asset replacement releases old scene material")
		previous_material = null
		previous_slot = -1
	scene.queue_free()
	await process_frame
	await process_frame
	print("RESOURCE_LIFETIME_SCENE_PASS" if failures == 0 else "RESOURCE_LIFETIME_SCENE_FAIL")
	quit(failures)
