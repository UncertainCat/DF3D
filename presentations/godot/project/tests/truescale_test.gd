extends SceneTree
const Preferences = preload("res://scripts/presentation_settings.gd")
var failures: Array[String]=[]
func _initialize(): call_deferred("run")
func check(ok: bool, message: String):
	if not ok:failures.append(message);push_error(message)
func run():
	var capture_dir := ProjectSettings.globalize_path("res://../../../build/truescale-review")
	check(DirAccess.make_dir_recursive_absolute(capture_dir)==OK,"capture directory available")
	OS.set_environment("DF3D_FIXTURE",ProjectSettings.globalize_path("res://../../../build/truescale-test.df3dfix"))
	OS.set_environment("DF3D_FIXTURE_TICK","1000")
	OS.set_environment("DF3D_UI_SETTINGS_PATH",ProjectSettings.globalize_path("res://../../../build/truescale-test.cfg"))
	OS.set_environment("DF3D_AUDIO_SILENT","1")
	Preferences.truescale=true
	check(Preferences.save_preferences()==OK,"preferences save")
	Preferences.loaded=false;Preferences.truescale=false;Preferences.load_preferences()
	check(Preferences.truescale,"Truescale survives preference reload")
	root.size=Vector2i(1280,900)
	var scene=load("res://scenes/main.tscn").instantiate();root.add_child(scene)
	var deadline:=Time.get_ticks_msec()+60000
	while not scene.world.terrain_loaded() and Time.get_ticks_msec()<deadline:await process_frame
	check(scene.world.terrain_loaded(),"fixture loaded")
	if not failures.is_empty():quit(1);return
	scene.world.set_replay_speed(0);scene.world.set_fixed_render_tick(1000);scene.world.set_top_z(0)
	scene.camera_rig.set_mode("free");scene.camera_rig.focus_on(Vector3(12,1,7),22)
	for frame in 100:await process_frame
	var params:PackedColorArray=scene.world.unit_scale_params()
	check(params.size()==6,"all volumes have scale payloads")
	if params.size()==6:
		check(absf(params[1].r/params[0].r-pow(20.0,1.0/3.0))<.001,"same art gets cube-root volume ratio")
		check(params[3].r == 1.0 and params[4].r == 1.0 and params[3].g == 0.0 and params[4].g == 0.0, "Dwarves keep original size and anchoring regardless of volume")
		check(params[5].r < 1.0, "Explicit dwarf baby still scales down")
		check(params[2].r>1.0,"large actor grows beyond original tile")
		# Check absolute calibration, not just relative ratios: 60,000 cm3
		# must occupy the original reference dwarf's 493/1024 cell area.
		var slots: PackedInt32Array = scene.world.unit_sprite_slots()
		var regions: PackedColorArray = scene.world.unit_sprite_regions()
		var sizes: PackedVector2Array = scene.world.unit_sprite_sizes()
		var image: Image = scene.world.sprite_texture(slots[1]).get_image()
		var region: Color = regions[1]
		var rect := Rect2i(roundi(region.r*image.get_width()),roundi(region.g*image.get_height()),roundi(region.b*image.get_width()),roundi(region.a*image.get_height()))
		var opaque := 0
		for y in range(rect.position.y,rect.end.y):
			for x in range(rect.position.x,rect.end.x):
				if image.get_pixel(x,y).a >= 128.0/255.0: opaque += 1
		var original_area := float(opaque)/rect.get_area()*sizes[1].x*sizes[1].y
		check(absf(original_area*params[1].r*params[1].r-493.0/1024.0)<.0001,"adult dwarf baseline retains original opaque area")

	print("TRUESCALE_SOURCE_PARAMS ",params)
	for style in ["classic","billboard"]:
		scene._sprite_presentation.set_style(style)
		for frame in 30:await process_frame
		var before:Dictionary=scene._instance_uploads.stats()
		for enabled in [false,true]:
			Preferences.truescale=enabled;RenderingServer.global_shader_parameter_set("actor_truescale",enabled)
			for frame in 30:
				scene.camera_rig._yaw+=.003;scene.camera_rig._update_transform();await process_frame
		var after:Dictionary=scene._instance_uploads.stats()
		for counter in ["transforms_written","custom_written","colors_written","ceiling_evaluations"]:
			check(before[counter]==after[counter],style+" toggle/camera must not write "+counter)
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(capture_dir.path_join("fixture-"+style+".png"))==OK,"capture saved for "+style)
	scene.queue_free()
	for frame in 5:await process_frame
	print("TRUESCALE_RUNTIME_PASS" if failures.is_empty() else "TRUESCALE_RUNTIME_FAIL")
	quit(0 if failures.is_empty() else 1)
