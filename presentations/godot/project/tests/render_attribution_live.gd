extends "res://tests/deep_profile_live.gd"
# Owned diagnostic lane only. Census/readbacks happen outside timing windows.
# Ablations measure removal of work, not production-ready visual changes.
var categories: Dictionary = {}

func collect_nodes(node: Node, category := "other") -> void:
	if node == scene.world.get_terrain_root(): category = "terrain"
	if node == scene.world.get_building_root(): category = "buildings"
	if node is MultiMeshInstance3D and node.get_parent() == scene:
		category = "units" if scene._sprite_layers.values().has(node) else "items" if scene._item_layers.values().has(node) else "other"
	if node is GeometryInstance3D:
		if not categories.has(category): categories[category] = []
		categories[category].append(node)
	for child in node.get_children(): collect_nodes(child, category)

func census() -> Dictionary:
	var result := {}
	for category in categories:
		var row := {"nodes":0,"enabled_nodes":0,"instances":0,"surfaces":0,"triangles_times_instances":0,"materials":{}}
		for node in categories[category]:
			row.nodes += 1
			if not node.is_visible_in_tree() or node.layers == 0: continue
			var mesh: Mesh
			var instances := 1
			if node is MeshInstance3D: mesh = node.mesh
			elif node is MultiMeshInstance3D and node.multimesh != null:
				mesh = node.multimesh.mesh
				instances = node.multimesh.instance_count if node.multimesh.visible_instance_count < 0 else node.multimesh.visible_instance_count
			if mesh == null or instances == 0: continue
			row.enabled_nodes += 1
			row.instances += instances
			for surface in mesh.get_surface_count():
				row.surfaces += 1
				var material: Material = node.material_override
				if material == null and node is MeshInstance3D: material = node.get_surface_override_material(surface)
				if material == null: material = mesh.surface_get_material(surface)
				var label := "standard_or_none"
				if material is ShaderMaterial and material.shader != null: label = material.shader.resource_path.get_file()
				row.materials[label] = row.materials.get(label,0) + 1
				if mesh is ArrayMesh:
					var indices: int = mesh.surface_get_array_index_len(surface)
					var vertices: int = mesh.surface_get_array_len(surface)
					row.triangles_times_instances += (indices if indices > 0 else vertices) / 3 * instances
		result[category] = row
	return result

func shader_variant(backface := false) -> Array:
	var restored := []
	var seen := {}
	var shaders := {}
	for nodes in categories.values():
		for node in nodes:
			var mesh: Mesh = node.mesh if node is MeshInstance3D else node.multimesh.mesh if node is MultiMeshInstance3D and node.multimesh != null else null
			if mesh == null: continue
			for i in mesh.get_surface_count():
				var material: Material = node.material_override
				if material == null and node is MeshInstance3D: material = node.get_surface_override_material(i)
				if material == null: material = mesh.surface_get_material(i)
				if not material is ShaderMaterial or material.shader == null or seen.has(material.get_instance_id()): continue
				seen[material.get_instance_id()] = true
				if material.shader.resource_path.get_file() not in ["unit_sprite.gdshader","billboard_sprite.gdshader"]: continue
				var shader_id: int = material.shader.get_instance_id()
				if not shaders.has(shader_id):
					var code: String = material.shader.code
					code = code.replace('#include "standee.gdshaderinc"',FileAccess.get_file_as_string("res://shaders/standee.gdshaderinc"))
					code = code.replace(", depth_prepass_alpha", "").replace("ALPHA = COLOR.a;", "")
					if backface: code = code.replace("cull_disabled", "cull_back")
					var variant := Shader.new()
					variant.code = code
					shaders[shader_id] = variant
				restored.append([material,material.shader])
				material.shader = shaders[shader_id]
	return restored

func measure(label: String) -> void:
	for i in 90: await process_frame
	EngineDebugger.send_message("df3d:render_phase", [label,"start",Engine.get_frames_drawn()])
	var rows := []
	var before: Dictionary = scene.world.mesh_batch_stats()
	var previous_batches := before
	var previous_submissions := submission_counters()
	var tick_start: int = scene.world.bridge_tick()
	var previous := Time.get_ticks_usec()
	for i in 300:
		await process_frame
		var now := Time.get_ticks_usec()
		var started := now
		var batches: Dictionary = scene.world.mesh_batch_stats()
		var submissions := submission_counters()
		rows.append({"frame":Engine.get_frames_drawn(),"interval_ms":(now-previous)/1000.0,
			"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			"batch_delta":counter_delta(previous_batches,batches),"submission_delta":counter_delta(previous_submissions,submissions)})
		previous_batches = batches
		previous_submissions = submissions
		rows[-1]["diagnostic_us"] = Time.get_ticks_usec()-started
		previous = now
	EngineDebugger.send_message("df3d:render_phase", [label,"end",Engine.get_frames_drawn()])
	var intervals := []
	var draws := []
	for row in rows:
		intervals.append(row.interval_ms)
		draws.append(row.draw_calls)
	results.append({"phase":label,"frame_ms":distribution(intervals),"draw_calls":distribution(draws),
		"tick_start":tick_start,"tick_end":scene.world.bridge_tick(),
		"batch_delta":counter_delta(before,scene.world.mesh_batch_stats()),"rows":rows})
	print("ATTRIBUTION ",label," median_ms=",results[-1].frame_ms.p50," draws=",results[-1].draw_calls.p50)

func run():
	if not EngineDebugger.is_active(): push_error("Requires RenderProbe"); quit(1); return
	root.size = Vector2i(1920,1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec()+120000
	while not scene._loader.entered and Time.get_ticks_msec()<deadline: await create_timer(.1).timeout
	if not scene._loader.entered: push_error("Load failed"); quit(1); return
	if not await set_paused(true): push_error("Pause failed"); quit(1); return
	scene.camera_rig.set_df_mode(false)
	scene._sprite_presentation.set_style("billboard")
	await go_level(128)
	await settle()
	collect_nodes(scene)
	var inventory := census()
	await measure("baseline")
	for category in ["terrain","buildings","units","items"]:
		var restore := []
		for node in categories.get(category,[]):
			restore.append([node,node.layers])
			node.layers = 0
		await measure("without_"+category)
		for entry in restore: entry[0].layers = entry[1]
	await measure("baseline_before_shader")
	var materials := shader_variant()
	await measure("solid_sprite_shader")
	for entry in materials: entry[0].shader = entry[1]
	materials = shader_variant(true)
	await measure("solid_backface_shader")
	for entry in materials: entry[0].shader = entry[1]
	await measure("baseline_repeat")
	if not await set_paused(false): push_error("Resume failed"); quit(1); return
	await measure("running")
	if not await set_paused(true): push_error("Restore pause failed"); quit(1); return
	var file := FileAccess.open(output+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"census":inventory,"phases":results,"variant_materials":materials.size(),
		"semantics":"Census is enabled application geometry before engine frustum/occlusion/pass expansion. Monitor frame IDs are observation IDs, not guaranteed GPU completion IDs. Census getters outside measured windows. Paused fixed camera except running phase; shader variant diagnostic only."},"  "))
	file.close()
	print("FLOOR_PROFILE_PASS")
	quit()
