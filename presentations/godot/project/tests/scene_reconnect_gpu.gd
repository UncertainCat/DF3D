extends SceneTree
# Recorded full-scene replacement while the loader conceals the world.
var scene
var failed := false
func check(ok: bool, message: String) -> bool:
	if not ok: failed = true; push_error(message)
	return ok
func _initialize() -> void: call_deferred("run")
func ready_scene() -> bool:
	var deadline := Time.get_ticks_msec()+60000
	while Time.get_ticks_msec()<deadline:
		# Recorded sources have no live transport synchronization flag.
		if scene.world.terrain_loaded() and scene.world.pending_block_count()==0 and scene.world.composite_pending_count()==0 and scene.world.building_pending_count()==0 and scene.world.item_composite_pending_count()==0 and scene._focused and scene._sprite_layers.size()>0: return true
		await process_frame
	return check(false,"Recorded scene did not finish preparation")
func run() -> void:
	preload("res://tests/recorded_fixture.gd").configure_scene()
	if DisplayServer.get_name()=="headless": quit(77); return
	var fixture := ProjectSettings.globalize_path("res://../../../fixtures/recorded/mature_fort_pause_53.16.df3dfix")
	OS.set_environment("DF3D_FIXTURE",fixture)
	OS.set_environment("DF3D_FIXTURE_SPEED","0")
	OS.set_environment("DF3D_FIXTURE_TICK",str(preload("res://tests/recorded_fixture.gd").tick()))
	scene = load("res://scenes/main.tscn").instantiate(); root.add_child(scene)
	if await ready_scene():
		var mask: int = scene._camera.cull_mask
		var epoch: int = scene.world.session_generation()
		scene._set_play_enabled(false); scene._set_play_enabled(false)
		check(scene.visible and scene._camera.cull_mask==0,"Loading must conceal the map without hiding render owners")
		check(not scene._ui.host.play_enabled,"Loading retained management input")
		check(scene.world.load_fixture(ProjectSettings.globalize_path("res://../../../build/effect-events.df3dfix")),"Empty interval fixture failed")
		for frame in 30: await process_frame
		check(not scene.world.terrain_loaded() and scene.world.unit_count()==0 and scene._sprite_layers.is_empty(),"Old source or sprite layers survived empty interval")
		check(scene.world.load_fixture(fixture),"Replacement fixture failed")
		if await ready_scene():
			check(scene.world.session_generation()!=epoch,"Replacement retained old session generation")
			check(scene._camera.cull_mask==0,"World was revealed before loading ended")
			scene._set_play_enabled(true)
			check(scene._camera.cull_mask==mask and scene._ui.host.play_enabled,"Play did not restore camera layers and input")
			for frame in 30: await process_frame
			for node in scene._sprite_layers.values():
				check(scene.world.sprite_slot_valid(int(node.get_meta("sprite_slot"))),"Reopened scene retained retired artwork")
			await RenderingServer.frame_post_draw
			var directory := ProjectSettings.globalize_path("res://../../../build/qa/04-U")
			DirAccess.make_dir_recursive_absolute(directory)
			check(root.get_texture().get_image().save_png(directory+"/scene_reconnect.png")==OK,"Reopened scene capture failed")
	scene.queue_free(); await process_frame; await process_frame
	print("SCENE_RECONNECT_PASS" if not failed else "SCENE_RECONNECT_FAIL")
	quit(1 if failed else 0)
