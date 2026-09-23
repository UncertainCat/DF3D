extends "res://tests/mesh_batch_motion_live.gd"
# Capture running intervals before pausing: exit-only rolling traces otherwise
# mostly show the settled teardown rather than the slow live frames of interest.
func counter_delta(before: Dictionary, after: Dictionary) -> Dictionary:
	var result := {}
	for key in before:
		if typeof(before[key]) in [TYPE_INT, TYPE_FLOAT]:
			result[key] = after[key] - before[key]
		elif before[key] is Dictionary:
			result[key] = counter_delta(before[key], after[key])
	return result

func run():
	var render_probe := OS.get_environment("DF3D_RENDER_PROBE") == "1"
	var submission_detail := OS.get_environment("DF3D_SUBMISSION_DETAIL") == "1"
	if render_probe and not EngineDebugger.is_active():
		push_error("Render probe requires its owned debugger collector")
		quit(1)
		return
	root.size = Vector2i(1920,1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var deadline = Time.get_ticks_msec() + 120000
	while not scene._loader.entered and Time.get_ticks_msec() < deadline: await create_timer(0.1).timeout
	if not scene._loader.entered: push_error("Deep capture load failed"); quit(1); return
	for mode in ["free", "billboard", "df"]:
		if not await set_paused(true): push_error("Cannot pause"); quit(1); return
		scene.camera_rig.set_df_mode(mode == "df")
		scene._sprite_presentation.set_style("billboard" if mode =="billboard" else "classic")
		await go_level(128)
		if not await set_paused(false): push_error("Cannot resume"); quit(1); return
		for i in 120: await process_frame
		scene._hitch_phase_override = mode
		scene._hitches.start_window(mode)
		if render_probe: EngineDebugger.send_message("df3d:render_phase", [mode, "start", Engine.get_frames_drawn()])
		scene._item_probe.reset()
		scene._unit_probe.rows.clear()
		var native_before: Dictionary = scene.world.presentation_perf_stats()
		var batches_before: Dictionary = scene.world.mesh_batch_stats()
		var sprites_before: Dictionary = scene.sprite_batch_stats()
		var lifecycle_before: Dictionary = scene._frame_costs._lifecycle.stats() if is_instance_valid(scene._frame_costs._lifecycle) else {}
		var tick_before: int = scene.world.bridge_tick()
		var times: Array = []
		var previous := Time.get_ticks_usec()
		var cursor: Dictionary = scene._frame_costs.cursor()
		var submission_probe = preload("res://tests/engine_submission_probe.gd").new()
		submission_probe.begin(submission_counters())
		if submission_detail: scene.world.engine_submission_details() # Discard warmup events.
		for i in 360:
			await process_frame
			var now := Time.get_ticks_usec()
			scene._frame_costs.record("frame.interval", previous, now - previous)
			times.append((now - previous) / 1000.0)
			previous = now
			var submission_start := Time.get_ticks_usec()
			var details: Dictionary = scene.world.engine_submission_details() if submission_detail else {}
			submission_probe.record(submission_counters(), Engine.get_frames_drawn(), details, times[-1])
			scene._frame_costs.record("diagnostics.engine_submissions", submission_start, Time.get_ticks_usec() - submission_start)
		if render_probe: EngineDebugger.send_message("df3d:render_phase", [mode, "end", Engine.get_frames_drawn()])
		var worst: Dictionary = scene._hitches.finish_window()
		worst.erase("intervals_us")
		var worst_file := FileAccess.open(output + "-" + mode + "-worst.json", FileAccess.WRITE)
		worst_file.store_string(JSON.stringify(worst)); worst_file.close()
		scene._hitch_phase_override = "between_samples"
		var stages := {}
		var samples: Dictionary = scene._frame_costs.since(cursor)
		for name in samples:
			stages[name] = distribution(samples[name])
		var native_after: Dictionary = scene.world.presentation_perf_stats()
		results.append({"mode": mode, "frames": times.size(), "frame_ms": distribution(times), "stages": stages,
			"tick_start": tick_before, "tick_end": scene.world.bridge_tick(),
			"native_delta": counter_delta(native_before, native_after),
			"sprite_delta": counter_delta(sprites_before, scene.sprite_batch_stats()),
			"lifecycle_delta": counter_delta(lifecycle_before, scene._frame_costs._lifecycle.stats()) if not lifecycle_before.is_empty() else {},
			"item_probe": scene._item_probe.summary(),
			"unit_probe": scene._unit_probe.rows.duplicate(true),
			"engine_submissions": submission_probe.summary(),
			"render_totals_endpoint": {"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)},
			"render_memory_endpoint": render_memory_endpoint() if submission_detail else {},
			"batch_delta": counter_delta(batches_before, scene.world.mesh_batch_stats())})
		if native_after.get("building_duplicate_builds", 0) != native_before.get("building_duplicate_builds", 0):
			push_error("A building was rebuilt multiple times in one poll")
			quit(1)
			return
		scene._frame_costs.write_capture(scene.world, output + "-" + mode)
		var file = FileAccess.open(output + ".json", FileAccess.WRITE)
		file.store_string(JSON.stringify(results, "  "))
	if not await set_paused(true): push_error("Cannot restore pause"); quit(1); return
	print("DEEP_PROFILE_LIVE_PASS")
	quit()

func submission_counters() -> Dictionary:
	var counters: Dictionary = scene.world.engine_submission_stats()
	counters.merge(scene.engine_submission_stats())
	return counters

func render_memory_endpoint() -> Dictionary:
	# Outside the sampled interval: these getters may synchronize with rendering.
	# Godot allocation accounting is not a measurement of physical VRAM residency.
	return {"video_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		"texture_bytes": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),
		"buffer_bytes": Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),
		"semantics": "Godot-reported allocation bytes, not physical residency or whole-GPU usage. Video is total; do not add subcategories."}
