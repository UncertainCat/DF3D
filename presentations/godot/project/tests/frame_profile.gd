extends SceneTree
var scene
var results: Array = []
func ready_scene() -> bool:
	var world = scene.world
	return world.terrain_loaded() and scene._focused and world.pending_block_count() == 0 and world.composite_pending_count() == 0 and world.building_pending_count() == 0 and world.item_composite_pending_count() == 0
func _initialize(): call_deferred("run")
func distribution(values: Array) -> Dictionary:
	if values.is_empty(): return {}
	values.sort()
	var sum := 0.0
	var slow := 0
	for value in values:
		sum += value
		if value > 16.667: slow += 1
	return {"mean":sum/values.size(),"p50":values[int(values.size()*0.5)],"p95":values[int(values.size()*0.95)],"p99":values[int(values.size()*0.99)],"max":values.back(),"over_16_67_ms":slow}
func sample(name: String, df: bool, moving: bool, frames: int = 600, warmup: int = 60):
	scene.camera_rig.set_df_mode(df)
	var origin: Vector3 = scene.camera_rig.position
	for frame in warmup: await process_frame
	var stage_cursor: Dictionary = scene._frame_costs.cursor()
	var before_stats: Dictionary = scene.world.presentation_perf_stats() if scene.world.has_method("presentation_perf_stats") else {}
	var before_uploads := Vector3i(scene._unit_upload_count,scene._item_upload_count,scene._instance_resize_count)
	var tick_start: int = scene.world.bridge_tick()
	var paused_frames := 0
	var buffer_ages: Array = []
	var elapsed: Array = []
	var process: Array = []
	var gpu: Array = []
	var render_cpu: Array = []
	var last := Time.get_ticks_usec()
	for frame in frames:
		if moving:
			var offset := Vector3(sin(frame*0.012)*8,0,cos(frame*0.012)*8)
			scene.camera_rig.focus_on(origin+offset,scene.camera_rig.current_distance())
		await process_frame
		if scene._session_state.get("paused",false): paused_frames += 1
		elif scene.world.has_method("buffered_state") and scene.world.is_live():
			buffer_ages.append(scene.world.buffered_state().display_age_ms)
		var now := Time.get_ticks_usec()
		elapsed.append((now-last)/1000.0)
		last = now
		process.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		if OS.get_environment("DF3D_PERF_NO_RENDER_READBACK") != "1":
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
			render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
	scene.camera_rig.focus_on(origin,scene.camera_rig.current_distance())
	var stats: Dictionary = scene.world.presentation_perf_stats() if scene.world.has_method("presentation_perf_stats") else {}
	for key in stats:
		if typeof(stats[key]) == TYPE_INT or typeof(stats[key]) == TYPE_FLOAT:
			stats[key] -= before_stats.get(key,0)
	var uploads := Vector3i(scene._unit_upload_count,scene._item_upload_count,scene._instance_resize_count)-before_uploads
	results.append({"phase":name,"frame_ms":distribution(elapsed),"process_ms":distribution(process),"render_cpu_ms":distribution(render_cpu),"gpu_ms":distribution(gpu),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"presentation_totals":stats,"unit_uploads":uploads.x,"item_uploads":uploads.y,"instance_resizes":uploads.z})
	var stage_samples: Dictionary = scene._frame_costs.since(stage_cursor)
	var stage_costs: Dictionary = {}
	for stage in stage_samples:
		if not stage_samples[stage].is_empty(): stage_costs[stage] = distribution(stage_samples[stage])
	results.back()["cpu_stages"] = stage_costs
	if scene.world.has_method("wall_top_cache_stats"): results.back()["wall_top_cache"] = scene.world.wall_top_cache_stats()
	results.back()["tick_start"] = tick_start
	results.back()["tick_end"] = scene.world.bridge_tick()
	results.back()["paused_frames"] = paused_frames
	if not buffer_ages.is_empty(): results.back()["buffer_age_ms"] = distribution(buffer_ages)
	print("FRAME_PROFILE_PHASE ",JSON.stringify(results.back()))
func run():
	root.size = Vector2i(1920,1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec()+90000
	while not ready_scene() and Time.get_ticks_msec()<deadline: await create_timer(0.05).timeout
	if not ready_scene():
		push_error("Profiling scene did not become ready")
		quit(1)
		return
	await sample("df_static",true,false)
	await sample("df_pan",true,true)
	await sample("free_pan",false,true)
	var timings := {}
	for method in ["_update_units","_update_items"]:
		var times: Array = []
		for index in 100:
			var start := Time.get_ticks_usec()
			scene.call(method)
			times.append((Time.get_ticks_usec()-start)/1000.0)
		timings[method] = distribution(times)
	var prefix := OS.get_environment("DF3D_PERF_OUT")
	var file = FileAccess.open(prefix+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"phases":results,"micro_ms":timings,"vsync":false,"resolution":[1920,1080],"source":scene.world.source_name(),"units":scene.world.unit_count(),"items":scene.world.item_drawn_count(),"window":scene.world.get_window_depth()},"  "))
	file.close()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(prefix+".png")
	print("FRAME_PROFILE_PASS")
	quit()
