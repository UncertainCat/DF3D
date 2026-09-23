extends SceneTree
var failures := 0
func check(ok: bool, reason: String) -> void:
	if not ok:
		failures += 1
		push_error(reason)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world := Df3dWorld.new()
	root.add_child(world)
	check(world.load_assets(OS.get_environment("DF3D_DF_PATH")), "licensed original assets load")
	var rock := world.ui_texture("HIDDEN_ROCK_1").get_image()
	var counts := {}
	for y in rock.get_height():
		for x in rock.get_width():
			var pixel := rock.get_pixel(x,y)
			if pixel.a > 0.999:
				var packed := pixel.to_rgba32()
				counts[packed] = counts.get(packed, 0) + 1
	var dominant: int = -1
	var frequency := 0
	for packed in counts:
		if counts[packed] > frequency:
			dominant = packed
			frequency = counts[packed]
	check(dominant >= 0, "source hidden rock has opaque backing")
	var expected := Color.hex(dominant)
	check(world.rock_backing_color().is_equal_approx(expected), "shared backing matches original art")
	world.set_fixed_render_tick(1000)
	check(world.load_fixture(ProjectSettings.globalize_path("res://../../../fixtures/synthetic/demo_fort.df3dfix")), "semantic fixture loads")
	world.set_top_z(3)
	world.set_window_depth(3)
	for i in 20: world.poll()
	check(world.pending_block_count() == 0, "all fixture terrain built")
	check(world.hidden_face_count() > 0, "fixture contains undisclosed geometry")
	var hidden_surfaces := 0
	var merged_quads := 0
	var backdrop := false
	for child in world.get_terrain_root().get_children():
		if not child is MeshInstance3D: continue
		var mesh: Mesh = child.mesh
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface)
			if not material is ShaderMaterial or not material.get_shader_parameter("rock_backing"): continue
			var arrays := mesh.surface_get_arrays(surface)
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			if colors.is_empty(): continue
			# A source_color uniform avoids UNorm8 quantization of dark linear
			# vertex values and applies the same conversion as sampled textures.
			var vertices_white := true
			for color in colors: vertices_white = vertices_white and color.is_equal_approx(Color.WHITE)
			check(vertices_white, "hidden color bypasses vertex quantization")
			check(material.get_shader_parameter("rock_backing_color").is_equal_approx(expected), "hidden uniform matches original backing")
			check("rock_backing_color : source_color" in material.shader.code, "hidden uniform uses the same color space as source textures")
			check("cull_disabled" in material.shader.code and "depth_draw_opaque" in material.shader.code, "hidden body stays opaque and two-sided")
			check("FRONT_FACING ? c.rgb : vec3(0.0)" in material.shader.code, "inside/back faces retain information-hiding black")
			if child.name == "backdrop": backdrop = true
			else:
				hidden_surfaces += 1
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for i in range(0, vertices.size(), 4):
					if i+3 < vertices.size() and (vertices[i].distance_to(vertices[i+1]) > 1.01 or vertices[i].distance_to(vertices[i+3]) > 1.01): merged_quads += 1
	check(backdrop, "bottom backdrop uses shared rock backing")
	check(hidden_surfaces > 0 and merged_quads > 0, "ordinary block path includes merged hidden caps")
	world.free()
	print("HIDDEN_ROCK_TEST failures=", failures, " surfaces=", hidden_surfaces, " merged=", merged_quads)
	quit(1 if failures else 0)
