extends "res://tests/mesh_batch_motion_live.gd"
# Diagnostic-only ablations. Main results never read render-server timers in
# the sampled loop, preserving overlap with the separate rendering thread.
var gpu_results: Array = []

func measure(label: String, mode: String, moving := false, frames := 600):
	var uploads: Dictionary = scene._instance_uploads.stats()
	await sample(label, mode == "df", moving, frames, 90)
	var after: Dictionary = scene._instance_uploads.stats()
	for key in after: after[key] -= uploads.get(key, 0)
	results.back()["instance_activity_including_warmup"] = after
	results.back()["units"] = scene.world.unit_count()
	results.back()["items"] = scene.world.item_drawn_count()
	results.back()["batches"] = scene.world.mesh_batch_stats()
	# Read exact submission counts only after the timed interval has ended.
	results.back()["viewport_draw_calls"] = RenderingServer.viewport_get_render_info(root.get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var file = FileAccess.open(output + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"phases": results, "gpu_calibration": gpu_results}, "  "))

func gpu_calibration(mode: String):
	# Synchronized diagnostics are separate from frame-budget measurements.
	# Render work is frozen, so readback overhead cannot trigger extra updates.
	var gpu: Array = []
	var cpu: Array = []
	for frame in 120:
		await process_frame
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	gpu_results.append({"mode": mode, "gpu_ms": distribution(gpu), "render_cpu_ms": distribution(cpu)})

func run():
	root.size = Vector2i(1920,1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var deadline = Time.get_ticks_msec() + 120000
	while not scene._loader.entered and Time.get_ticks_msec() < deadline: await create_timer(0.1).timeout
	if not scene._loader.entered: push_error("Breakdown load failed"); quit(1); return
	for mode in ["free", "df", "billboard"]:
		if not await set_paused(true): push_error("Cannot pause"); quit(1); return
		scene.camera_rig.set_df_mode(mode == "df")
		scene._sprite_presentation.set_style("billboard" if mode =="billboard" else "classic")
		await go_level(128)
		await measure(mode + "_paused", mode)
		if OS.get_environment("DF3D_BREAKDOWN_FROZEN_ONLY") != "1":
			if not await set_paused(false): push_error("Cannot resume"); quit(1); return
			await measure(mode + "_running_fixed", mode)
			await measure(mode + "_running_pan", mode, true)
		if not await set_paused(true): push_error("Cannot restore pause"); quit(1); return
		# Producer pause precedes consumption of delayed publications. Drain them
		# before requiring an empty geometry queue and freezing scene processing.
		await create_timer(0.5).timeout
		await settle()
		if scene.world.pending_block_count() != 0 or scene.world.building_pending_count() != 0:
			push_error("Cannot freeze pending geometry"); quit(1); return
		scene.process_mode = Node.PROCESS_MODE_DISABLED
		await measure(mode + "_render_only", mode)
		await gpu_calibration(mode)
		# Freeze all scene logic before visibility ablations so update callbacks
		# cannot recreate visible nodes. Restore each factor before the next.
		var units: Array = scene._sprite_layers.values() + [scene.units]
		var items: Array = scene._item_layers.values() + [scene.item_markers]
		for entry in [["units", units], ["items", items], ["terrain", [scene.get_node("Terrain")]], ["buildings", [scene.get_node("Buildings")]]]:
			var shown: Array = []
			for node in entry[1]:
				if node.visible: shown.append(node); node.hide()
			await measure(mode + "_no_" + entry[0], mode, false, 360)
			for node in shown: node.show()
		root.scaling_3d_scale = 0.5
		await measure(mode + "_half_render_resolution", mode, false, 360)
		root.scaling_3d_scale = 1.0
		await measure(mode + "_render_only_repeat", mode, false, 360)
		scene.process_mode = Node.PROCESS_MODE_INHERIT
	print("FLOOR_PROFILE_PASS")
	quit()
