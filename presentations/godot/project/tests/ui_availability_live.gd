extends "res://tests/mesh_batch_motion_live.gd"
# Product exposure test on an owned paused fort. No gameplay edits.
func run():
	root.size = Vector2i(1920,1080)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var deadline := Time.get_ticks_msec()+120000
	while not scene._loader.entered and Time.get_ticks_msec()<deadline: await create_timer(.1).timeout
	if not scene._loader.entered: push_error("UI load failed"); quit(1); return
	if not await set_paused(true): push_error("UI pause failed"); quit(1); return
	await go_level(128)
	await settle()
	var hud = scene._fortress_hud
	for id in ["citizens","work_orders","trade","agreements","notifications","stocks","appointments","kitchen","rough_panels"]:
		assert(scene._ui.controller(id)==null, "Retired controller has no product factory")
	assert(not scene._interaction.construction_active, "Rejected routes leave input free")
	for title in ["Stocks","Petitions","Trade","Tasks","Places","Objects","Justice"]:
		assert(not hud.navigation[title].visible, "Hidden entry: "+title)
	for title in ["Citizens","Labor","Work orders"]:
		assert(hud.navigation[title].visible, "Accepted entry: "+title)
	for title in ["Stockpiles / zones"]:
		assert(not hud.navigation.has(title) or not hud.navigation[title].visible, "Unpromoted controller remains hidden from HUD")
	assert(hud.navigation.Reports.visible and hud.navigation["Build / construction"].visible )
	# A session refresh must not allow a retired placeholder to steal ownership.
	scene._ui.controller("construction").open_panel()
	await process_frame
	assert(scene._ui.controller("construction").panel.visible and scene._interaction.construction_active)
	scene._set_play_enabled(true,true)
	assert(scene._ui.controller("construction").panel.visible and scene._interaction.construction_active)
	scene._ui.controller("construction").close_panel()
	assert(not scene._interaction.construction_active)
	for view in [Vector2i(1920,1080),Vector2i(960,640)]:
		root.size = view
		for i in 10: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+"-"+str(view.x)+".png")
	print("UI_AVAILABILITY_LIVE_PASS")
	quit()
