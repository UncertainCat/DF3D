extends "res://tests/mesh_batch_motion_live.gd"
## Real DF AI in an owned no-save development session. Setup is deliberately
## staged; action observations and renderer reactions must come from the bridge.
var native_arena := false
var detailed_trace: Array[String] = []
var observed_corpses := {} # Capture-only audit of exact corpse handoffs.
func set_paused(value: bool) -> bool:
	var accepted: bool = await super.set_paused(value)
	if accepted and native_arena: scene._session_state["paused"] = value
	return accepted

func run():
	Engine.max_fps = 60
	var setup = JSON.parse_string(FileAccess.get_file_as_string("res://../../../build/targeted-attack-setup.json"))
	root.size = Vector2i(int(setup.get("capture_width", 1280)), int(setup.get("capture_height", 720)))
	var ui_scale := float(root.size.y) / 720.0
	var capture_pitch := float(setup.get("camera_pitch", -0.75))
	native_arena = bool(setup.get("native_arena", false))
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 120000
	if native_arena:
		# Development capture only. Product fortress loading remains unchanged.
		scene._loader.hide()
		scene._loader.queue_free()
		scene._loader = null
		scene._session_state = {"paused":true}
		scene._set_play_enabled(true, true)
		scene.world.attach()
		while not scene._fort_ready() and Time.get_ticks_msec() < deadline: await create_timer(.1).timeout
	else:
		while not scene._loader.entered and Time.get_ticks_msec() < deadline: await create_timer(.1).timeout
	if (native_arena and not scene._fort_ready()) or (not native_arena and not scene._loader.entered):
		push_error("Battle capture load failed"); quit(1); return
	if not await set_paused(true):
		push_error("Cannot pause battle capture"); quit(1); return
	var focus := Vector3(setup.focus.x, setup.focus.z + float(setup.get("camera_focus_height", 1.0)), setup.focus.y)
	var arena: bool = setup.get("arena", false)
	var arena_ids := {}
	for value in setup.units: arena_ids[int(value)] = true
	var duration := float(setup.get("capture_seconds", 30.0)) if arena else 12.0
	var orbit_seconds := float(setup.get("orbit_seconds", 0.0))
	scene.camera_rig.set_mode("free" if orbit_seconds > 0 else "isometric")
	if orbit_seconds > 0: scene.camera_rig.set_orbit_pose(PI / 4.0, capture_pitch)
	scene._sprite_presentation.set_style("billboard")
	preload("res://scripts/presentation_settings.gd").animation_strength = 1.0
	RenderingServer.global_shader_parameter_set("actor_animation_strength", 1.0)
	var headroom := int(OS.get_environment("DF3D_CAPTURE_HEADROOM")) if OS.has_environment("DF3D_CAPTURE_HEADROOM") else 4
	setup.requested_headroom = headroom
	headroom = mini(headroom, int(setup.get("open_headroom", headroom)))
	await go_level(int(setup.focus.z) + (headroom if arena else 0))
	if arena:
		scene.world.set_window_depth(maxi(1, scene.world.get_top_z() - int(setup.focus.z) + 1))
		scene.camera_rig.level_focus_offset = float(setup.focus.z) - scene.world.get_top_z()
		setup.recording_top_z = scene.world.get_top_z()
		setup.recording_window = scene.world.get_window_depth()
		setup.recording_headroom = headroom
	scene.camera_rig.focus_on(focus, float(setup.get("camera_distance", 12.0)) if arena else 14)
	await settle()
	var survivor_label: Label
	var fps_label: Label
	var fps_samples: Array = []
	var listener_samples: Array = []
	var next_fps_sample := 0.0
	var team_names: Dictionary = setup.get("team_labels", {})
	var initial_teams := {}
	for fighter in setup.get("combatants", []):
		var team: String = fighter.get("team", fighter.get("race", ""))
		initial_teams[team] = int(initial_teams.get(team, 0)) + 1
	if arena:
		for child in scene.get_children():
			if child is CanvasLayer: child.hide()
		scene._fortress_hud.root_control.hide()
		var overlay := CanvasLayer.new()
		root.add_child(overlay)
		var title := Label.new()
		title.position = Vector2(28, 18) * ui_scale
		title.text = setup.get("title", "DF3D / DWARVES vs GOBLINS")
		title.add_theme_font_size_override("font_size", int(26 * ui_scale))
		overlay.add_child(title)
		var detail := Label.new()
		detail.position = Vector2(28, 57) * ui_scale
		detail.size = Vector2(1224, 50) * ui_scale
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.text = setup.get("equipment_note", "Matched equipment and skills")
		detail.add_theme_font_size_override("font_size", int(17 * ui_scale))
		overlay.add_child(detail)
		survivor_label = Label.new()
		survivor_label.position = Vector2(28, 682) * ui_scale
		survivor_label.add_theme_font_size_override("font_size", int(18 * ui_scale))
		overlay.add_child(survivor_label)
		if setup.get("show_fps", false):
			fps_label = Label.new()
			fps_label.position = Vector2(992, 20) * ui_scale
			fps_label.size = Vector2(260, 65) * ui_scale
			fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			fps_label.add_theme_font_size_override("font_size", int(20 * ui_scale))
			fps_label.text = "DF3D: measuring\nDF: measuring"
			overlay.add_child(fps_label)
	if OS.get_environment("DF3D_OBS_CAPTURE") == "1":
		var capture = preload("res://tests/encounter_obs_capture.gd").new()
		var succeeded: bool = await capture.run(self, setup, fps_label, survivor_label)
		quit(0 if succeeded else 1)
		return
	if not await set_paused(false):
		push_error("Cannot resume battle capture"); quit(1); return
	var sound_events: Array = []
	var sound_clock := {"start": Time.get_ticks_usec()}
	scene._audio.sfx.cue_started.connect(func(event):
		if sound_clock.start == 0: return
		var row: Dictionary = event.duplicate(true)
		row.seconds = float(Time.get_ticks_usec() - sound_clock.start) / 1000000.0
		row.kind = "sound"
		row.tick = event.metadata.get("tick", 0)
		row.position = [event.position.x, event.position.y, event.position.z]
		sound_events.append(row))
	var seen := {}
	var observations: Array = []
	var native_observations: Array = []
	var native_seen := {}
	var combat_events: Array = []
	var combat_cursor := 0
	var contact_cursor := 0
	var attack_cursor := 0
	var resolved_attacks: Array = []
	var projectile_combat: Array = []
	var projectile_combat_cursor := 0
	var item_contacts: Array = []
	var release_cursor := 0
	var projectile_releases: Array = []
	var projectiles_seen := {}
	var shot_reactions: Array = []
	var shots_seen := {}
	var projectile_peak := 0
	var reactions: Array = []
	var reaction_seen := {}
	var dead := {}
	var finish_at := -1.0
	var images: Array[Image] = []
	var times: Array = []
	var start_tick: int = scene.world.bridge_tick()
	var spatter_start: int = scene.world.spatter_revision()
	var frame_ticks: Array = []
	var start := Time.get_ticks_usec() if arena else 0
	sound_clock.start = start
	deadline = Time.get_ticks_msec() + (int(duration * 1000) + 500 if arena else 45000)
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if orbit_seconds > 0 and start > 0:
			var orbit_elapsed := float(Time.get_ticks_usec() - start) / 1000000.0
			var approach := smoothstep(4.0, 12.0, orbit_elapsed)
			var wide: float = setup.get("camera_distance", 43.0)
			var close: float = setup.get("orbit_close_distance", wide)
			scene.camera_rig.set_orbit_pose(PI / 4.0 + TAU * orbit_elapsed / orbit_seconds, capture_pitch, lerpf(wide, close, approach))
		await RenderingServer.frame_post_draw
		if scene.world.item_ground_flags().size() != scene.world.item_ids().size():
			push_error("Item ground flags lost alignment"); quit(1); return
		for event in scene.world.unit_combat_events(combat_cursor):
			combat_cursor = maxi(combat_cursor, int(event.id))
			if arena_ids.has(int(event.victim_id)):
				combat_events.append(event)
				if int(event.kind) == 2: dead[int(event.victim_id)] = true
		for event in scene.world.projectile_combat_events(projectile_combat_cursor):
			projectile_combat_cursor = maxi(projectile_combat_cursor, int(event.id))
			projectile_combat.append(event)
		for event in scene.world.resolved_attack_events(attack_cursor):
			attack_cursor = maxi(attack_cursor, int(event.id))
			resolved_attacks.append(event)
		for event in scene.world.item_contact_events(contact_cursor):
			contact_cursor = maxi(contact_cursor, int(event.id))
			item_contacts.append(event)
		for release in scene.world.projectile_release_events(release_cursor):
			release_cursor = maxi(release_cursor, int(release.id))
			if arena_ids.has(int(release.firer_id)): projectile_releases.append(release)
		var flying_ids = scene.world.projectile_ids()
		var flying_positions = scene.world.projectile_positions()
		var visible_bolts := 0
		for i in flying_ids.size():
			if flying_positions[i].y < scene.world.get_top_z() + 1 and flying_positions[i].y >= scene.world.get_top_z() - scene.world.get_window_depth() + 1 and scene.get_node("CameraRig/Camera3D").is_position_in_frustum(flying_positions[i]):
				projectiles_seen[flying_ids[i]] = true
				visible_bolts += 1
		projectile_peak = maxi(projectile_peak, visible_bolts)
		if arena:
			var ids = scene.world.unit_ids()
			var attacks = scene.world.unit_attack_ids()
			var targets = scene.world.unit_attack_targets()
			var positions = scene.world.unit_positions()
			for i in ids.size():
				if not arena_ids.has(ids[i]) or attacks[i] < 0: continue
				var key := str(ids[i]) + ":" + str(attacks[i])
				if native_seen.has(key): continue
				native_seen[key] = true
				var target_index: int = ids.find(targets[i])
				var position: Vector3 = positions[i]
				var target: Vector3 = positions[target_index] if target_index >= 0 else Vector3.INF
				native_observations.append({"unit":ids[i],"action":attacks[i],"target":targets[i],"distance":position.distance_to(target) if target.is_finite() else -1.0,"record":scene._actor_animation.records.get(ids[i],{}).duplicate()})
		for id in scene._actor_animation.records:
			if arena and not arena_ids.has(id): continue
			var record: Dictionary = scene._actor_animation.records[id]
			if record.animation == "shoot":
				var shot_key := str(id) + ":" + str(record.start)
				if not shots_seen.has(shot_key):
					shots_seen[shot_key] = true
					shot_reactions.append({"unit":id,"start":record.start})
			if record.animation == "flinch":
				var reaction_key := str(id) + ":" + str(record.start)
				if not reaction_seen.has(reaction_key):
					reaction_seen[reaction_key] = true
					reactions.append({"unit":id,"start":record.start})
			if record.animation != "attack": continue
			var key := str(id) + ":" + str(record.start)
			if not seen.has(key):
				seen[key] = true
				observations.append({"unit":id,"action":record.attack_id,"start":record.start,"angle":record.parameter,"bridge_tick":scene.world.bridge_tick()})
				if start == 0:
					start = Time.get_ticks_usec()
					sound_clock.start = start
					sound_events.clear()
					deadline = Time.get_ticks_msec() + 12500
		if start > 0:
			var elapsed := (Time.get_ticks_usec() - start) / 1000000.0
			if orbit_seconds > 0:
				var sound_focus: Vector3 = scene._audio.sfx._focus
				var sound_right: Vector3 = scene._audio.sfx._camera_basis.x
				listener_samples.append({"seconds":elapsed,"focus":[sound_focus.x,sound_focus.y,sound_focus.z],"right":[sound_right.x,sound_right.y,sound_right.z]})
			if is_instance_valid(fps_label) and elapsed >= next_fps_sample:
				next_fps_sample = elapsed + 0.5
				var native_fps = null
				var fps_path: String = setup.get("fps_path", "")
				if not fps_path.is_empty() and FileAccess.file_exists(fps_path):
					var telemetry = JSON.parse_string(FileAccess.get_file_as_string(fps_path))
					if telemetry is Dictionary: native_fps = telemetry.get("fps")
				var render_fps := Engine.get_frames_per_second()
				fps_label.text = "DF3D: %d FPS\nDF: %s FPS" % [render_fps,str(int(native_fps)) if native_fps != null else "unavailable"]
				fps_samples.append({"seconds":elapsed,"render_fps":render_fps,"native_fps":native_fps,"bridge_tick":scene.world.bridge_tick()})
			if arena and finish_at < 0.0 and not dead.is_empty():
				var alive_by_team := initial_teams.duplicate()
				for team in alive_by_team: alive_by_team[team] = 0
				for fighter in setup.get("combatants", []):
					if not dead.has(int(fighter.id)):
						var team: String = fighter.get("team", "")
						if alive_by_team.has(team): alive_by_team[team] += 1
				if alive_by_team.size() >= 2 and 0 in alive_by_team.values():
					finish_at = maxf(8.0, elapsed + 2.0)
			if finish_at > 0.0 and elapsed >= finish_at:
				duration = elapsed
				break
			if elapsed >= duration: break
			if is_instance_valid(survivor_label):
				var remaining := initial_teams.duplicate()
				for fighter in setup.get("combatants", []):
					if dead.has(int(fighter.id)):
						var team: String = fighter.get("team", fighter.get("race", ""))
						remaining[team] -= 1
				var labels: Array[String] = []
				for team in remaining: labels.append("%s: %d" % [team_names.get(team, team.capitalize()), remaining[team]])
				survivor_label.text = "    ".join(labels)
			if OS.get_environment("DF3D_ARENA_DIAGNOSTICS") == "1":
				var trace_ids = scene.world.unit_ids()
				var trace_positions = scene.world.unit_positions()
				for item_id in scene._actor_deaths.corpses:
					observed_corpses[item_id] = scene._actor_deaths.corpses[item_id].unit
				var rendered_items = scene.world.item_ids() if not observed_corpses.is_empty() else PackedInt64Array()
				for actor_id in arena_ids:
					var trace_index: int = trace_ids.find(actor_id)
					var row := {"schema":1,"kind":"render_unit","frame":images.size(),"seconds":elapsed,"tick":scene.world.bridge_tick(),"unit_id":actor_id,"listed":trace_index >= 0,"animation_clock":scene._actor_animation.clock,"top_z":scene.world.get_top_z(),"window":scene.world.get_window_depth()}
					row.death_pose = scene._actor_deaths.active.has(actor_id)
					row.corpses = []
					for item_id in observed_corpses:
						if observed_corpses[item_id] == actor_id:
							row.corpses.append({"item_id":item_id,"held":scene._actor_deaths.corpses.has(item_id),"rendered":rendered_items.has(item_id)})
					if trace_index >= 0:
						var point: Vector3 = trace_positions[trace_index]
						row.position = [point.x, point.y, point.z]
						row.in_frustum = scene.get_node("CameraRig/Camera3D").is_position_in_frustum(point)
						var pose: Dictionary = scene._actor_animation.records.get(actor_id,{})
						row.animation = pose.get("animation", "")
						row.animation_start = pose.get("start", -1.0)
					detailed_trace.append(JSON.stringify(row))
			images.append(root.get_texture().get_image())
			times.append(elapsed)
			frame_ticks.append(scene.world.bridge_tick())
	sound_clock.start = 0
	sound_events = sound_events.filter(func(event): return event.seconds >= 0 and event.seconds < duration)
	if not await set_paused(true):
		push_error("Cannot restore pause"); quit(1); return
	if OS.get_environment("DF3D_ARENA_DIAGNOSTICS") == "1":
		var trace_file := FileAccess.open(output + "-render-trace.jsonl", FileAccess.WRITE)
		for line in detailed_trace: trace_file.store_line(line)
		trace_file.close()
	var sound_trace := FileAccess.open(output + "-sound-trace.jsonl", FileAccess.WRITE)
	for event in sound_events: sound_trace.store_line(JSON.stringify(event))
	sound_trace.close()
	var directory := output + "-frames"
	var write_error: String = preload("res://tests/capture_frame_writer.gd").write(images, directory)
	if not write_error.is_empty():
		push_error(write_error); quit(1); return
	FileAccess.open(output + ".json", FileAccess.WRITE).store_string(JSON.stringify({"kind":"live_staged_combat", "arena":arena,"setup":setup,"duration":duration,"frame_times":times,"fps_samples":fps_samples,"audio_listener_samples":listener_samples,"observations":observations,"native_observations":native_observations,"combat_events":combat_events,"resolved_attacks":resolved_attacks,"projectile_combat_events":projectile_combat,"projectile_combat_stats":scene.world.projectile_combat_stats(),"resolved_attack_stats":scene.world.resolved_attack_stats(),"item_contacts":item_contacts,"item_contact_stats":scene.world.item_contact_stats(),"sound_events":sound_events,"spatter_revision_start":spatter_start,"spatter_revision_end":scene.world.spatter_revision(),"feedback_stats":scene._gameplay_feedback.counters,"source_effect_stats":scene.world.effect_event_stats() if scene.world.has_method("effect_event_stats") else {},"effect_stats":scene._combat_effects.counters,"sfx_stats":scene._audio.sfx.counters,"flinches":reactions,"rendered_deaths":scene._actor_deaths.rendered_deaths,"ground_items":scene.world.item_ground_flags().count(1),"projectile_releases":projectile_releases,"projectiles_seen":projectiles_seen.keys(),"projectile_peak":projectile_peak,"shot_reactions":shot_reactions,"frame_ticks":frame_ticks,"tick_start":start_tick,"tick_end":scene.world.bridge_tick()}, "  "))
	if observations.is_empty() and combat_events.is_empty() and projectile_releases.is_empty():
		push_error("No real targeted attack reached the renderer"); quit(1); return
	print("FLOOR_PROFILE_PASS targeted_attacks=", observations.size(), " flinches=", reactions.size(), " deaths=", scene._actor_deaths.rendered_deaths, " releases=", projectile_releases.size(), " flying_peak=", projectile_peak, " frames=", images.size())
	quit()
