extends RefCounted
## External recorder handshake and lean frame telemetry. No image readback/audit.
func write_json(path: String, value: Dictionary):
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func run(test, setup: Dictionary, fps_label: Label, survivor_label: Label) -> bool:
	var prefix: String = test.output
	# Match the preceding SFX-only review mix without saving user audio settings.
	test.scene._audio.persist_settings = false
	for bus in ["Master", "SFX"]:
		AudioServer.set_bus_mute(AudioServer.get_bus_index(bus), false)
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus), 0.0)
	for bus in ["Music", "UI", "Ambience"]:
		AudioServer.set_bus_mute(AudioServer.get_bus_index(bus), true)
	write_json(prefix + "-obs-ready.json", {"ready":true})
	var deadline := Time.get_ticks_msec() + 60000
	while not FileAccess.file_exists(prefix + "-obs-go.json"):
		if Time.get_ticks_msec() > deadline:
			push_error("OBS did not start recording"); return false
		await test.create_timer(0.1).timeout
	if not await test.set_paused(false): return false
	var start_unix := Time.get_unix_time_from_system()
	var start := Time.get_ticks_usec()
	var previous := start
	var duration: float = setup.get("capture_seconds", 50)
	var samples: Array = []
	var frame_ms: Array = []
	var next_sample := 0.0
	var dead := {}
	var cursor := 0
	while true:
		await test.process_frame
		var now := Time.get_ticks_usec()
		var elapsed := float(now - start) / 1000000.0
		frame_ms.append(float(now - previous) / 1000.0)
		previous = now
		if elapsed >= duration: break
		var distance := lerpf(float(setup.camera_distance), float(setup.orbit_close_distance), smoothstep(4.0, 12.0, elapsed))
		test.scene.camera_rig.set_orbit_pose(PI / 4.0 + TAU * elapsed / float(setup.orbit_seconds), float(setup.camera_pitch), distance)
		if elapsed >= next_sample:
			next_sample = elapsed + 0.5
			var native_fps = null
			if FileAccess.file_exists(setup.fps_path):
				var telemetry = JSON.parse_string(FileAccess.get_file_as_string(setup.fps_path))
				if telemetry is Dictionary: native_fps = telemetry.get("fps")
			var fps := Engine.get_frames_per_second()
			fps_label.text = "DF3D: %d FPS\nDF: %s FPS" % [fps, str(int(native_fps)) if native_fps != null else "unavailable"]
			samples.append({"seconds":elapsed,"render_fps":fps,"native_fps":native_fps,"bridge_tick":test.scene.world.bridge_tick()})
			for event in test.scene.world.unit_combat_events(cursor):
				cursor = maxi(cursor, int(event.id))
				if int(event.kind) == 2: dead[int(event.victim_id)] = true
			var counts := {}
			for fighter in setup.combatants:
				var team: String = fighter.team
				counts[team] = int(counts.get(team, 0)) + (0 if dead.has(int(fighter.id)) else 1)
			var labels: Array[String] = []
			for team in counts: labels.append("%s: %d" % [setup.team_labels.get(team, team), counts[team]])
			survivor_label.text = "    ".join(labels)
	if not await test.set_paused(true): return false
	write_json(prefix + ".json", {"setup":setup,"duration":duration,"start_unix":start_unix,"fps_samples":samples,"frame_ms":frame_ms,"recorder":"OBS"})
	write_json(prefix + "-obs-done.json", {"done":true})
	deadline = Time.get_ticks_msec() + 30000
	while not FileAccess.file_exists(prefix + "-obs-finished.json"):
		if Time.get_ticks_msec() > deadline:
			push_error("OBS did not finalize recording"); return false
		await test.create_timer(0.1).timeout
	print("TARGETED_ATTACK_LIVE_PASS OBS frames=", frame_ms.size())
	return true
