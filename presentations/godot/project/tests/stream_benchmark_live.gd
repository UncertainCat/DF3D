extends SceneTree
# Companion collector for stream_benchmark.ps1. No video/readback during samples.
var scene
var output := OS.get_environment("DF3D_STREAM_BENCH_OUT")
var render_style := OS.get_environment("DF3D_STREAM_BENCH_STYLE")
var frame_cap := int(OS.get_environment("DF3D_STREAM_FRAME_CAP")) if OS.has_environment("DF3D_STREAM_FRAME_CAP") else 60
var control := ""
var active := ""
var samples: Array[float]=[]
var ages: Array[float]=[]
var before := {}
var before_submission := {}
var before_status_uploads := 0
var started := 0
var last := 0
var base_yaw := 0.0
func _initialize():call_deferred("run")
func write_json(path: String,data):
	var f=FileAccess.open(path,FileAccess.WRITE);f.store_string(JSON.stringify(data));f.close()
func export_profile(suffix: String):
	if not scene._frame_costs.enabled: return
	var begin := Time.get_ticks_usec()
	scene._frame_costs.write_capture(scene.world, output+"-"+suffix)
	scene._hitches.record("diagnostics.profile_export",begin,Time.get_ticks_usec()-begin)
func distribution(values: Array[float]) -> Dictionary:
	if values.is_empty():return {}
	var sorted:=values.duplicate();sorted.sort()
	return {"p50":sorted[int(sorted.size()*.5)],"p95":sorted[mini(int(sorted.size()*.95),sorted.size()-1)],"p99":sorted[mini(int(sorted.size()*.99),sorted.size()-1)],"max":sorted.back()}
func budget_counts() -> Dictionary:
	var result := {"over_20ms":0,"over_25ms":0,"over_33ms":0,"over_50ms":0}
	for value in samples:
		if value > 20: result.over_20ms += 1
		if value > 25: result.over_25ms += 1
		if value > 33: result.over_33ms += 1
		if value > 50: result.over_50ms += 1
	return result
func finish():
	if active.is_empty():return
	var worst: Dictionary = scene._hitches.finish_window()
	samples.clear()
	for interval in worst.intervals_us: samples.append(float(interval)/1000.0)
	worst.erase("intervals_us")
	var complete: bool = int(worst.sample_overflow) == 0
	var durations := distribution(samples) if complete else {"max":float(worst.peak_frame_us)/1000.0,"p50":null,"p95":null,"p99":null}
	write_json(output+"-"+active+"-worst.json", worst)
	var after:Dictionary=scene.world.buffered_state()
	var counters:Dictionary={}
	for key in ["source_publications_accepted","source_publications_missed","source_gap_events","source_read_failures","source_rejected_reads","presentation_coalesced","published","capture_publications_accepted","capture_publications_missed","capture_read_failures","capture_rejected_reads","capture_queue_drops"]:
		counters[key]=int(after.get(key,0))-int(before.get(key,0))
	write_json(output+"-"+active+"-godot.json",{"phase":active,"render_style":render_style,"billboard_enabled":scene._sprite_presentation.billboard,"render_thread_model":ProjectSettings.get_setting("rendering/driver/threads/thread_model",1),"resolution":[root.size.x,root.size.y],"frame_cap":Engine.max_fps,"frames":worst.observed_frames,"duration_samples":samples.size(),"duration_statistics_complete":complete,"sample_overflow":worst.sample_overflow,"frame_ms":durations,"frame_budget":budget_counts() if complete else {},"display_age_ms":distribution(ages),"before":before,"after":after,"delta":counters,"units":scene.world.unit_count(),"items":scene.world.item_drawn_count()})
	var end := Time.get_ticks_usec()
	write_json(output+"-"+active+"-indicators.json", {"status_batch_uploads":scene._unit_status.uploads-before_status_uploads,"status_records":scene._unit_status.records.size(),"status_batches":scene._unit_status.batches.size()})
	var submissions: Dictionary = scene.engine_submission_stats()
	for key in submissions: submissions[key] -= before_submission.get(key,0)
	write_json(output+"-"+active+"-diagnostics.json", {"phase":active,"start_us":started,"end_us":end,"hitches":scene._hitches.stats(),"item_probe":scene._item_probe.summary(),"instance_cache":scene._instance_uploads.counters,"submission_delta":submissions})
	if scene._unit_probe.enabled: write_json(output+"-"+active+"-units.json", {"start_us":started,"end_us":end,"rows":scene._unit_probe.rows})
	var completed := active
	active=""
	scene._hitch_phase_override = "between_samples"
	export_profile(completed)
func run():
	root.size=Vector2i(1920,1080);DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=frame_cap
	control=output+"-control.json"
	scene=load("res://scenes/main.tscn").instantiate();root.add_child(scene)
	# Benchmark misses of the 60 fps budget, not only severe gameplay hitches.
	# Production keeps the recorder's coarser threshold and lower report rate.
	scene._hitches.threshold_us = 20000
	scene._hitches.cooldown_us = 500000
	scene._hitch_phase_override = "warmup"
	var deadline:=Time.get_ticks_msec()+180000
	while not scene._loader.entered and Time.get_ticks_msec()<deadline:await create_timer(.1).timeout
	if not scene._loader.entered:push_error("stream benchmark load timeout");quit(1);return
	if render_style.is_empty():render_style="billboard"
	scene.camera_rig.set_mode("free");scene._sprite_presentation.set_style(render_style);scene.world.set_top_z(128)
	scene.camera_rig.focus_on(Vector3(72,129,72),60)
	deadline=Time.get_ticks_msec()+120000
	while Time.get_ticks_msec()<deadline:
		await create_timer(.25).timeout
		if scene.world.pending_block_count()==0 and scene.world.composite_pending_count()==0 and scene.world.item_composite_pending_count()==0 and scene.world.building_pending_count()==0:break
	await create_timer(3).timeout
	export_profile("warmup")
	write_json(output+"-ready.json",{"ready":true,"buffer":scene.world.buffered_state()})
	base_yaw=scene.camera_rig._yaw
	var poll_at:=0
	while true:
		await process_frame
		var now:=Time.get_ticks_usec()
		if not active.is_empty():
			if last>0:
				if scene._frame_costs.mode == "deep": scene._frame_costs.record("frame.interval",last,now-last)
			if "orbit" in active:
				scene.camera_rig._yaw=base_yaw+(now-started)/1000000.0*.12;scene.camera_rig._update_transform()
		last=now
		if now>=poll_at:
			poll_at=now+500000
			if not active.is_empty():ages.append(float(scene.world.buffered_state().get("display_age_ms",0)))
			if FileAccess.file_exists(control):
				var command=JSON.parse_string(FileAccess.get_file_as_string(control))
				if command is Dictionary:
					var name:String=command.get("phase","")
					if name!=active:
						finish()
						if name=="quit":
							write_json(output+"-ack.json",{"phase":name});quit();return
						if not name.is_empty():
							active=name;samples.clear();ages.clear();before=scene.world.buffered_state();started=now;last=0
							before_submission=scene.engine_submission_stats()
							before_status_uploads=scene._unit_status.uploads
							if scene._unit_probe.enabled: scene._unit_probe.rows.clear()
							scene._hitch_phase_override = name
							scene._hitches.start_window(name)
						write_json(output+"-ack.json",{"phase":name})
