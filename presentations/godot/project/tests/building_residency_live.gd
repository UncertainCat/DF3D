extends "res://tests/mesh_batch_motion_live.gd"
# Owned live visual/residency check; never saves the fortress.
func run():
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec() + 120000
	while not scene._loader.entered and Time.get_ticks_msec() < deadline:
		await create_timer(0.1).timeout
	if not scene._loader.entered:
		push_error("Building residency load failed"); quit(1); return
	if not await set_paused(true): quit(1); return
	await go_level(128)
	var visual_probe = preload("res://tests/building_cutout_probe.gd").new()
	var visual_result: Dictionary = await visual_probe.run(scene, scene.world, output)
	if visual_result.failures != 0:
		push_error("Building cutout invariants failed"); quit(1); return
	var focus := Vector3.ZERO
	for node in scene.world.get_building_root().get_children():
		if node.get_meta("df3d_building_kind", "") not in ["Workshop", "TradeDepot"]: continue
		var fragments: Array = node.get_meta("df3d_draw_fragments", [])
		if fragments.is_empty(): continue
		var f: Dictionary = fragments[0]
		focus = Vector3(f.x + 1.5, f.z + 1.0, f.y + 1.5)
		if str(node.name) == "building_203": break
	if focus == Vector3.ZERO:
		push_error("No workshop available for visual check"); quit(1); return
	var checks := []
	for mode in ["df", "free", "billboard"]:
		scene.camera_rig.set_df_mode(mode == "df")
		scene._sprite_presentation.set_style("billboard" if mode =="billboard" else "classic")
		scene.camera_rig.focus_on(focus, 14.0)
		for i in 90: await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		if image.save_png(output + "-" + mode + ".png") != OK:
			push_error("Could not save building visual capture"); quit(1); return
		var before: Dictionary = building_mesh_ids()
		var native_before: Dictionary = scene.world.presentation_perf_stats()
		if not await set_paused(false): quit(1); return
		var tick_before: int = scene.world.bridge_tick()
		for i in 360: await process_frame
		if not await set_paused(true): quit(1); return
		var after: Dictionary = building_mesh_ids()
		var changed := []
		for id in before:
			if after.get(id, -1) != before[id]: changed.append(id)
		var native_after: Dictionary = scene.world.presentation_perf_stats()
		var batches: Dictionary = scene.world.mesh_batch_stats()
		if batches.buildings.max_surfaces_per_mesh > RenderingServer.MAX_MESH_SURFACES or batches.terrain.max_surfaces_per_mesh > RenderingServer.MAX_MESH_SURFACES:
			push_error("Published batch exceeds engine surface limit"); quit(1); return
		checks.append({"mode":mode,"tracked":before.size(),"changed_ids":changed,
			"tick_start":tick_before,"tick_end":scene.world.bridge_tick(),
			"batch_stats":batches,
			"building_builds":native_after.building_geometry_builds - native_before.building_geometry_builds})
		if scene.world.bridge_tick() <= tick_before:
			push_error("Residency test simulation did not advance"); quit(1); return
		# These are long-lived furniture/workshop sources, excluding animated doors.
		if not changed.is_empty():
			push_error("Furniture meshes changed during moving-unit residency check: " + str(changed)); quit(1); return
	var file := FileAccess.open(output + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(checks, "  "))
	print("FLOOR_PROFILE_PASS")
	quit()

func building_mesh_ids() -> Dictionary:
	var ids := {}
	for node in scene.world.get_building_root().get_children():
		if node is MeshInstance3D and node.mesh != null and node.get_meta("df3d_building_kind", "") in ["Workshop", "Furnace", "TradeDepot", "Table", "Chair", "Bed"]:
			ids[str(node.name)] = node.mesh.get_instance_id()
	return ids
