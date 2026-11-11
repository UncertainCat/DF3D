extends "res://tests/chest_scene_live.gd"
func expected_filename() -> String:return "nobles-native.json"
func result_filename() -> String:return "job-settings-wire-result.json"
func run() -> void:
	Engine.max_fps=30;await super.run()
func exercise(expected: Dictionary) -> void:
	owner=scene._ui.controller("nobles");owner.open_panel()
	if not await settle(owner.state):return
	check(owner.state.rows.size()==expected.rows.size(),"Composed Nobles rows differ")
	check(scene._interaction.construction_active,"Nobles does not own world input")
	for dimensions in [Vector2i(912,552),Vector2i(1600,900)]:
		root.size=dimensions;await process_frame;await process_frame
		await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(136,24));await drain()
		var tasks=scene._ui.controller("tasks")
		check(scene._ui.host.active==tasks and not owner.panel.visible,"Nobles header failed to reach Tasks")
		await pointer(tasks.panel.get_global_transform_with_canvas()*Vector2(24 if dimensions.x<1240 else 456,24))
		if not await settle(owner.state):return
		check(scene._ui.host.active==owner and not tasks.panel.visible,"Tasks failed to return to Nobles")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/nobles-main-"+str(dimensions.x)+".png")
	scene._fortress_hud.toggle_game_menu();await process_frame
	check(scene._ui.host.overlay_blocked,"Nobles overlay gate missing")
	await pointer(owner.panel.get_global_transform_with_canvas()*Vector2(136,24))
	check(scene._ui.host.active==owner,"Overlay allowed Nobles header navigation")
	scene._fortress_hud.close_menus();await process_frame
	key(KEY_F10);await process_frame
	check(scene._ui.host.active==null and not owner.panel.visible and not scene._interaction.construction_active,"Nobles reset did not release map input")
	await drain();exercised=true
