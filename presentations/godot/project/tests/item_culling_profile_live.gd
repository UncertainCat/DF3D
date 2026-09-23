extends "res://tests/render_attribution_live.gd"
# Fixed save/tick/camera; actor partitions and material policy never change.
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
	if OS.get_environment("DF3D_CELL_SWEEP_NEAR") == "1":
		scene.camera_rig.focus_on(Vector3(72,129,72),20)
	for cell in [Vector2i(16,1),Vector2i(32,1),Vector2i(32,4),Vector2i(16,4),Vector2i(0,1),Vector2i(16,1)]:
		scene.configure_item_batches(cell.x>0,maxi(16,cell.x),cell.y)
		await settle()
		await measure("items_"+str(cell.x)+"x"+str(cell.y)+( "_repeat" if results.size()==5 else ""))
		results[-1]["sprite_stats"] = scene.sprite_batch_stats()
		for layer in scene._item_layers.values():
			if layer.multimesh.visible_instance_count == 0 and layer.visible:
				push_error("Inactive item layer remains visible"); quit(1); return
	if results[0].draw_calls.p50 != results[-1].draw_calls.p50:
		push_error("Repeated partition must restore draw count"); quit(1); return
	var file := FileAccess.open(output+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"census":{},"phases":results},"  "))
	file.close()
	print("FLOOR_PROFILE_PASS")
	quit()
