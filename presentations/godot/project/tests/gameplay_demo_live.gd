extends "res://tests/mesh_batch_motion_live.gd"
## Actual simulation activity, captured only through the exclusive owned lane.
## Frame timestamps are exported so packaging preserves wall-clock pacing.
func run():
	root.size = Vector2i(1280, 720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 60
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 120000
	while not scene._loader.entered and Time.get_ticks_msec() < deadline:
		await create_timer(.1).timeout
	if not scene._loader.entered:
		push_error("Gameplay capture load failed"); quit(1); return
	if not await set_paused(true):
		push_error("Cannot pause for framing"); quit(1); return
	scene.camera_rig.set_mode("isometric")
	scene._sprite_presentation.set_style("billboard")
	RenderingServer.global_shader_parameter_set("actor_animation_strength", 1.0)
	await go_level(128)
	# Pick the densest 8-tile cell on this level from semantic unit positions.
	var cells := {}
	for position in scene.world.unit_positions():
		if absf(position.y - 128.5) > 1.0: continue
		var key := Vector2i(floori(position.x / 8.0), floori(position.z / 8.0))
		cells[key] = int(cells.get(key, 0)) + 1
	var focus := Vector3(72, 129, 72)
	var highest := 0
	for key in cells:
		if cells[key] > highest:
			highest = cells[key]
			focus = Vector3(key.x * 8 + 4, 129, key.y * 8 + 4)
	scene.camera_rig.focus_on(focus, 22)
	await settle()
	if not await set_paused(false):
		push_error("Cannot resume capture"); quit(1); return
	await create_timer(1.0).timeout
	var directory := output + "-frames"
	DirAccess.make_dir_recursive_absolute(directory)
	var start_tick: int = scene.world.bridge_tick()
	var start := Time.get_ticks_usec()
	var times: Array = []
	var images: Array[Image] = []
	while Time.get_ticks_usec() - start < 12000000:
		await RenderingServer.frame_post_draw
		var timestamp := (Time.get_ticks_usec() - start) / 1000000.0
		images.append(root.get_texture().get_image())
		times.append(timestamp)
		await create_timer(maxf(.001, timestamp + 1.0 / 24.0 - (Time.get_ticks_usec() - start) / 1000000.0)).timeout
	var end_tick: int = scene.world.bridge_tick()
	if not await set_paused(true):
		push_error("Cannot restore pause"); quit(1); return
	# PNG compression is intentionally outside the simulation recording interval.
	for i in images.size():
		if images[i].save_png(directory.path_join("%04d.png" % i)) != OK:
			push_error("Cannot save capture frame"); quit(1); return
	FileAccess.open(output + ".json", FileAccess.WRITE).store_string(JSON.stringify({"kind":"live_fortress_activity", "tick_start":start_tick, "tick_end":end_tick, "frame_times":times, "duration":12.0, "focus":str(focus), "cell_units":highest, "combat_staged":false}, "  "))
	if end_tick <= start_tick:
		push_error("Simulation did not advance"); quit(1); return
	print("FLOOR_PROFILE_PASS live_frames=", times.size(), " ticks=", end_tick - start_tick)
	quit()
