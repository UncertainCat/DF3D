extends SceneTree
# Offline fixed-tick camera-only upload regression. No DF process required.
var scene
var failures: Array[String] = []
func _initialize(): call_deferred("run")
func check(value: bool, message: String):
	if not value: failures.append(message); push_error(message)
func delta(before: Dictionary, after: Dictionary) -> Dictionary:
	var result := {}
	for key in after:
		if after[key] is int or after[key] is float:
			result[key] = after[key] - before.get(key, 0)
	return result
func sample(label: String) -> Dictionary:
	var before: Dictionary = scene._instance_uploads.stats()
	var submissions: Dictionary = scene.engine_submission_stats()
	var native: Dictionary = scene.world.engine_submission_stats()
	var frames: Array[float] = []
	var previous := Time.get_ticks_usec()
	var original: Vector3 = scene.camera_rig.position
	for frame in 120:
		if label == "rotate": scene.camera_rig._yaw += TAU / 120.0
		if label == "pan": scene.camera_rig.position = original + Vector3(sin(frame * TAU / 120.0) * 4.0, 0, 0)
		scene.camera_rig._update_transform()
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append(float(now - previous) / 1000.0)
		previous = now
	if OS.get_environment("DF3D_MOTION_SCREENSHOTS") == "1":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("DF3D_BILLBOARD_OUT").get_basename() + "-" + label + ".png")
	frames.sort()
	var writes := delta(before, scene._instance_uploads.stats())
	for key in ["transforms_written", "custom_written", "colors_written", "ceiling_evaluations", "cache_invalidations"]:
		check(writes[key] == 0, label + " camera-only " + key + " must be zero (got " + str(writes[key]) + ")")
	return {"phase": label, "frames": frames.size(), "median_ms": frames[60], "p95_ms": frames[114], "max_ms": frames.back(), "instance_cache": writes, "instance_submissions": delta(submissions, scene.engine_submission_stats()), "native_submissions": delta(native, scene.world.engine_submission_stats())}
func run():
	preload("res://tests/recorded_fixture.gd").configure_scene()
	root.size = Vector2i(1280, 900)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	# Populate offscreen payloads once to isolate camera invalidation from the
	# separate, permitted cost of first-demand preparation.
	scene._unit_demand.enabled = false
	var deadline := Time.get_ticks_msec() + 90000
	while not scene.world.terrain_loaded() and Time.get_ticks_msec() < deadline: await process_frame
	check(scene.world.terrain_loaded() and not scene.world.is_live(), "Offline fixture loads")
	if not failures.is_empty(): quit(1); return
	scene.world.set_replay_speed(0)
	scene.world.set_fixed_render_tick(preload("res://tests/recorded_fixture.gd").tick())
	scene.world.set_top_z(preload("res://tests/recorded_fixture.gd").top_z())
	scene.camera_rig.set_mode("free")
	scene.camera_rig.focus_on(preload("res://tests/recorded_fixture.gd").focus(), 30)
	scene._sprite_presentation.set_style(OS.get_environment("DF3D_MOTION_STYLE") if OS.has_environment("DF3D_MOTION_STYLE") else "billboard")
	for frame in 240: await process_frame
	scene._unit_demand.enabled = true
	check(not scene._sprite_layers.is_empty() and not scene._item_layers.is_empty(), "Fixture exercises item and unit sprites")
	var result := {"fixture": OS.get_environment("DF3D_FIXTURE").get_file(), "tick":preload("res://tests/recorded_fixture.gd").tick(), "style":OS.get_environment("DF3D_MOTION_STYLE"), "phases": []}
	for phase in ["idle", "rotate", "pan"]: result.phases.append(await sample(phase))
	result.failures = failures
	var path := OS.get_environment("DF3D_BILLBOARD_OUT")
	if not path.is_empty():
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(result, "  "))
	for phase in result.phases:
		print("BILLBOARD_MOTION ", phase.phase, " median_ms=", phase.median_ms, " transforms=", phase.instance_cache.transforms_written, " custom=", phase.instance_cache.custom_written, " ceilings=", phase.instance_cache.ceiling_evaluations)
	scene.queue_free()
	for frame in 8: await process_frame
	print("BILLBOARD_MOTION_TEST_PASS" if failures.is_empty() else "BILLBOARD_MOTION_TEST_FAIL")
	quit(0 if failures.is_empty() else 1)
