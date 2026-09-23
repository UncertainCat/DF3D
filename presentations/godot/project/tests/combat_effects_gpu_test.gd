extends SceneTree
func _initialize(): call_deferred("run")
func run():
	root.size = Vector2i(800, 400)
	var scene := Node3D.new()
	root.add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.07, 0.08, 0.1)
	scene.add_child(environment)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(3, 6, 5)
	camera.look_at(Vector3(3, 0, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8
	var effects := preload("res://scripts/combat_effects.gd").new()
	scene.add_child(effects)
	effects.configure(OS.get_environment("DF3D_DF_PATH"))
	for upright in [false, true]:
		effects.reset_session()
		effects.set_style(upright)
		for i in 4:
			effects.emit_effect(["HIT", "MISS", "BLOCK", "PARRY"][i], Vector3(i*2,0,0), Vector3.RIGHT, 1.0)
		RenderingServer.global_shader_parameter_set("actor_animation_time", 1.1)
		for frame in 5: await process_frame
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		var visible_pixels := 0
		for y in picture.get_height():
			for x in picture.get_width():
				if picture.get_pixel(x,y).r > 0.75: visible_pixels += 1
		if visible_pixels < 100:
			push_error("Native combat effects not visible"); quit(1); return
		if upright:
			var silhouettes := {}
			for i in 4:
				var center := Vector2i(camera.unproject_position(Vector3(i*2,0,0)))
				var crop := picture.get_region(Rect2i(center - Vector2i(60,60), Vector2i(120,120)))
				silhouettes[hash(crop.get_data())] = true
			if silhouettes.size() < 3:
				push_error("Outcome rows aliased on GPU"); quit(1); return
		picture.save_png(ProjectSettings.globalize_path("res://../../../build/combat-effects-" + ("upright" if upright else "flat") + ".png"))
		print("COMBAT_EFFECT_PIXELS ", upright, " ", visible_pixels)
	scene.queue_free()
	for frame in 3: await process_frame
	print("COMBAT_EFFECTS_GPU_PASS")
	quit()
