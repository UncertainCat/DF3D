extends "res://tests/workshop_order_wire_live.gd"

func run() -> void:
	directory=OS.get_environment("DF3D_CARRIER_DIRECTORY")
	Engine.max_fps=30;OS.set_environment("DF3D_FIXTURE","")
	var preferences=preload("res://scripts/presentation_settings.gd")
	preferences.loaded=true;preferences.ui_scale=1.0;preferences.camera_mode="df"
	root.size=Vector2i(1200,800)
	var scene=load("res://scenes/main.tscn").instantiate();root.add_child(scene);world=scene.world
	var deadline:=Time.get_ticks_msec()+60000
	while not scene._loader.entered and Time.get_ticks_msec()<deadline:await create_timer(0.05).timeout
	if not check(scene._loader.entered,"Labor main scene did not enter fortress"):quit(1);return
	var service=scene._ui.actions;service.set_process(false)
	var owner=scene._ui.controller("work_details");var host=scene._ui.host
	click(scene._fortress_hud.launcher_rect("Labor").get_center())
	if not check(await settle(service,func():return owner.state.phase==owner.state.Phase.Ready),"Labor HUD did not load"):quit(1);return
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory+"/work-details-native.json"))
	check(owner.state.details.size()==expected.details.size(),"Public Work Details count differs from native")
	for frame in 3:await process_frame
	var selections: Array=[]
	for column in [0,0,3]:
		if not check(owner.state.ids.size()>1,"Work Details selection fixture needs two workers"):quit(1);return
		click(owner.panel.position+Vector2(280,owner.panel.list_top()+54));await process_frame
		check(owner.panel.worker_selected==owner.state.ids[1],"Second portrait did not select its worker")
		var header_x: float=owner.panel.DETAIL_SORT_X[column]*8+4
		click(owner.panel.position+Vector2(header_x,owner.panel.list_top()-18))
		if not check(await settle(service,func():return owner.state.phase==owner.state.Phase.Ready),"Worker sort did not settle"):quit(1);return
		check(owner.panel.worker_selected==owner.state.ids[0],"Sort did not reset highlight to the first native-ordered worker")
		selections.append({"column":column,"selected":owner.panel.worker_selected,"ids":Array(owner.state.ids)})
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory+"/labor-sorted-selection-"+str(selections.size())+".png")
	var selection_file:=FileAccess.open(directory+"/labor-sorted-selection.json",FileAccess.WRITE)
	selection_file.store_string(JSON.stringify(selections));selection_file.close()
	var original_mode: int=owner.state.selected.mode
	var changed_mode: int=3 if original_mode!=3 else 2
	click(owner.panel.position+owner.panel.mode_rect([1,3,2].find(changed_mode)).get_center())
	if not check(await settle(service,func():return owner.state.phase==owner.state.Phase.Ready),"Labor mode edit failed"):quit(1);return
	check(owner.state.selected.mode==changed_mode,"Mode edit not reflected")
	click(owner.panel.position+owner.panel.mode_rect([1,3,2].find(original_mode)).get_center())
	if not check(await settle(service,func():return owner.state.phase==owner.state.Phase.Ready),"Labor mode restoration failed"):quit(1);return
	check(owner.state.selected.mode==original_mode,"Mode not restored")
	for settings in [false,true]:
		if settings:
			click(owner.panel.position+Vector2(648,owner.panel.header_top()+18))
			if not check(await settle(service,func():return owner.state.phase==owner.state.Phase.Ready and owner.state.editing_settings),"Work Details settings did not open"):quit(1);return
		for tab in ["standing","kitchen","stone"]:
			var rect: Rect2=owner.panel.standing_orders_rect() if tab=="standing" else owner.panel.kitchen_rect() if tab=="kitchen" else owner.panel.stone_use_rect()
			click(owner.panel.position+rect.get_center())
			var sibling=scene._ui.controller("standing_orders")
			var state=sibling.state if tab=="standing" else sibling.kitchen_state if tab=="kitchen" else sibling.stone_state
			var panel=sibling.panel if tab=="standing" else sibling.kitchen_panel if tab=="kitchen" else sibling.stone_panel
			if not check(await settle(service,func():return state.phase==state.Phase.Ready and panel.visible),"Labor tab failed: "+tab):quit(1);return
			check(host.active==sibling and not owner.panel.visible,"Labor sibling did not take ownership")
			click(panel.position+panel.work_details_rect().get_center())
			if not check(await settle(service,func():return owner.state.phase==owner.state.Phase.Ready and owner.panel.visible),"Work Details return failed: "+tab):quit(1);return
			check(host.active==owner and owner.state.editing_settings==settings,"Labor return lost settings or owner")
	for dimensions in [Vector2i(1600,900),Vector2i(912,552),Vector2i(1200,800)]:
		root.size=dimensions
		for frame in 3:await process_frame
		if not check(await settle(service,func():return owner.state.phase==owner.state.Phase.Ready),"Labor resize failed"):quit(1);return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/labor-public-settings.png")
	number_key(KEY_ESCAPE);await process_frame
	check(host.active==null and not owner.panel.visible,"Labor Escape retained input")
	click(scene._fortress_hud.launcher_rect("Labor").get_center())
	if not check(await settle(service,func():return owner.state.phase==owner.state.Phase.Ready),"Labor HUD reopen failed"):quit(1);return
	check(not owner.state.editing_settings,"Labor reopen retained old settings view")
	host.close_active();await process_frame
	var file:=FileAccess.open(directory+"/job-settings-wire-result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":not failed}));file.close()
	scene.queue_free();await process_frame
	quit(1 if failed else 0)
