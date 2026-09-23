extends "res://tests/frame_profile.gd"
var failures: Array[String] = []
func check(ok: bool, label: String):
	if not ok: failures.append(label); push_error(label)
func _initialize():
	OS.set_environment("DF3D_FIXTURE",ProjectSettings.globalize_path("res://../../../build/ramp-support.df3dfix"))
	OS.set_environment("DF3D_FIXTURE_TICK","")
	OS.set_environment("DF3D_AUDIO_SILENT","1")
	OS.set_environment("DF3D_UI_SETTINGS_PATH",ProjectSettings.globalize_path("res://../../../build/ramp-support-prefs.cfg"))
	call_deferred("run")
func settle():
	for frame in 60: await process_frame
func capture(label: String):
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/ramp-"+label+".png"))
func run():
	root.size=Vector2i(1280,800)
	scene=load("res://scenes/main.tscn").instantiate();root.add_child(scene)
	var world=scene.world
	world.set_replay_speed(0);world.set_replay_elapsed(0)
	world.poll();world.set_top_z(0);world.set_window_depth(1)
	scene._unit_demand.enabled=false
	scene.camera_rig.set_mode("free");scene.camera_rig.focus_on(Vector3(15.5,.6,5.5),6)
	await settle()
	check(ready_scene(),"fixture completely prepared")
	check(world.unit_ids().size()==5 and world.item_ids().size()==5,"five populated ramp cases")
	var ids: PackedInt64Array=world.unit_ids()
	for i in ids.size():
		var expected := .4 if ids[i]==5 else .45
		check(is_equal_approx(world.unit_ground_support(i).y,expected),"creature on matching ramp surface")
		check(world.unit_cutout_positions()[i].y>.5,"creature lifted above slope and shared stack")
	var item_ids: PackedInt64Array=world.item_ids()
	for i in item_ids.size():
		check(world.item_physical_layout().positions[i].y>.5,"item lifted above slope and furniture")
	check(world.layout_matches_reference(),"ramp support preserves category ordering oracle")
	check(is_equal_approx(world.ground_support(Vector3(15.25,0,5.5)).y,.225),"continuous low-quarter support")
	check(is_equal_approx(world.ground_support(Vector3(15.75,0,5.5)).y,.675),"continuous high-quarter support")
	for style in ["classic","billboard"]:
		scene._sprite_presentation.set_style(style)
		for mode in ["df","isometric","free"]:
			scene.camera_rig.set_mode(mode)
			scene.camera_rig.focus_on(Vector3(15.5,.6,5.5),6)
			await settle()
			var before: Dictionary=world.presentation_perf_stats()
			var writes: Dictionary=scene._instance_uploads.stats()
			for frame in 30:
				scene.camera_rig._yaw+=.002;scene.camera_rig._update_transform();await process_frame
			var after: Dictionary=world.presentation_perf_stats()
			for key in ["ramp_support_tiles_evaluated","stack_atlas_page_uploads","building_geometry_builds"]:
				check(after[key]==before[key],style+"/"+mode+" camera/clock causes zero "+key)
			for key in ["transforms_written","custom_written","colors_written"]:
				check(scene._instance_uploads.stats()[key]==writes[key],style+"/"+mode+" no resident "+key)
			await capture(style+"-"+mode)
	world.set_window_depth(3)
	scene.camera_rig.focus_on(Vector3(15.5,.1,7.5),6)
	scene.camera_rig.set_mode("walk")
	scene.camera_rig._yaw=0.0;scene.camera_rig._pitch=-.1;scene.camera_rig._update_transform()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	await settle()
	check(scene.camera_rig.is_walk_mode(),"FPS uses the same support data")
	await capture("walk")
	scene.camera_rig.set_mode("free")
	world.set_top_z(0);world.set_window_depth(1)
	await settle()
	var before: Dictionary=world.presentation_perf_stats()
	var resident: PackedVector3Array=world.item_positions().duplicate()
	world.set_replay_elapsed(10)
	await settle()
	check(world.bridge_tick()==101,"water edit ingested")
	var after: Dictionary=world.presentation_perf_stats()
	for key in ["ramp_support_tiles_evaluated","stack_atlas_page_uploads","building_geometry_builds"]:
		check(after[key]==before[key],"water-only update causes zero "+key)
	check(after.ramp_support_blocks_skipped>before.ramp_support_blocks_skipped,"shape-only gate skips liquid update")
	before=after
	world.set_replay_elapsed(20)
	await settle()
	after=world.presentation_perf_stats()
	check(world.bridge_tick()==102,"cross-block wall removal ingested")
	check(world.ground_support(Vector3(15.5,0,5.5)).is_equal_approx(Vector3(0,.4,0)),"adjacent block change updates isolated ramp")
	check(after.ramp_support_tiles_evaluated-before.ramp_support_tiles_evaluated==5,"one changed wall evaluates only itself and four neighbors")
	check(after.ramp_support_tiles_changed-before.ramp_support_tiles_changed==1,"one ramp record changed")
	check(after.stack_atlas_page_uploads-before.stack_atlas_page_uploads==1,"one bounded atlas page uploaded")
	check(after.building_geometry_builds-before.building_geometry_builds==1,"only building on changed ramp rebuilt")
	check(world.item_positions()==resident,"terrain support never rewrites item transforms")
	print("RAMP_SUPPORT_WORK ",{"evaluated":after.ramp_support_tiles_evaluated-before.ramp_support_tiles_evaluated,"changed":after.ramp_support_tiles_changed-before.ramp_support_tiles_changed,"pages":after.stack_atlas_page_uploads-before.stack_atlas_page_uploads,"buildings":after.building_geometry_builds-before.building_geometry_builds})
	scene.queue_free();await process_frame
	print("RAMP_SUPPORT_PASS" if failures.is_empty() else "RAMP_SUPPORT_FAIL")
	quit(0 if failures.is_empty() else 1)
