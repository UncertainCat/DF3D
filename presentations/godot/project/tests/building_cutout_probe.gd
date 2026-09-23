extends RefCounted
# Invoked by a protected full-scene native lane after readiness; does not mutate
# game state. Original artwork stays in the local screenshot/asset cache only.
var failures := 0
func check(ok: bool, reason: String) -> void:
	if not ok:
		failures += 1
		push_error(reason)

func run(scene, world, outprefix: String) -> Dictionary:
	var tree: SceneTree = scene.get_tree()
	var deadline := Time.get_ticks_msec() + 30000
	while world.building_pending_count() > 0 and Time.get_ticks_msec() < deadline:
		await tree.create_timer(0.05).timeout
	check(world.building_pending_count() == 0, "building cutout queue drained")
	var records: Array = []
	var workshops := 0
	var overhangs := 0
	var foregrounds := 0
	var focus := Vector3.ZERO
	for node in world.get_building_root().get_children():
		if not node is MeshInstance3D: continue
		var kind: String = node.get_meta("df3d_building_kind", "")
		if kind not in ["Workshop", "Furnace", "TradeDepot"]: continue
		workshops += 1
		var fragments: Array = node.get_meta("df3d_draw_fragments", [])
		for f in fragments:
			check(f.thickness > 0.0, "equipment source has silhouette thickness")
			check(f.bottom >= 0.0 and f.bottom + f.thickness < 0.9, "fragment remains below next floor")
			if f.north_spill:
				overhangs += 1
				if focus == Vector3.ZERO: focus = Vector3(f.x + 0.5, f.z + 1.0, f.y + 1.5)
			if f.foreground: foregrounds += 1
			check(not f.foreground, "own artwork composites without a physical foreground stack")
		# Exact duplicate triangles within a building are a cheap detector for
		# coincident per-cell contour faces; pure tests cover partial intervals.
		var triangles := {}
		var duplicates := 0
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for i in range(0, indices.size(), 3):
				var points: Array[String] = []
				for j in 3:
					var v := vertices[indices[i+j]]
					points.append("%.6f,%.6f,%.6f" % [v.x,v.y,v.z])
				points.sort()
				var key := "|".join(points)
				if triangles.has(key): duplicates += 1
				triangles[key] = true
		check(duplicates == 0, "no coincident triangles within " + str(node.name))
		records.append({"node":str(node.name), "kind":kind, "fragments":fragments, "duplicate_triangles":duplicates})
	check(workshops > 0, "licensed fortress includes workshops")
	check(overhangs > 0, "original north-spilling equipment artwork reached mesh")
	if focus != Vector3.ZERO:
		scene.camera_rig.focus_on(focus, scene.camera_rig.current_distance())
	for df_mode in [true, false]:
		scene.camera_rig.set_df_mode(df_mode)
		if not df_mode and focus != Vector3.ZERO:
			scene.camera_rig.focus_on(focus,16.0)
		await tree.create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		var suffix := "-workshops-df.png" if df_mode else "-workshops-free.png"
		tree.root.get_texture().get_image().save_png(outprefix + suffix)
	scene.camera_rig.set_df_mode(true)
	var result := {"failures":failures, "workshops":workshops, "overhangs":overhangs, "foregrounds":foregrounds, "records":records}
	var output := FileAccess.open(outprefix + ".building-cutouts.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result)); output.close()
	print("BUILDING_CUTOUT_PROBE failures=", failures, " workshops=", workshops, " overhangs=", overhangs, " foregrounds=", foregrounds)
	return result
