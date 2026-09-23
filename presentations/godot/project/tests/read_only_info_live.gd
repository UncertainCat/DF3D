extends "res://tests/mesh_batch_motion_live.gd"
func run():
	root.size = Vector2i(1920,1080)
	scene = load("res://scenes/main.tscn").instantiate(); root.add_child(scene)
	var deadline := Time.get_ticks_msec()+120000
	while not scene._loader.entered and Time.get_ticks_msec()<deadline: await create_timer(.1).timeout
	if not scene._loader.entered: push_error("UI load failed"); quit(1); return
	if not await set_paused(true): quit(1); return
	await go_level(128); await settle()
	var view = scene._ui.controller("readouts")
	var evidence := {}
	for page in view.PAGES:
		scene._ui.open_destination(page)
		await process_frame
		deadline = Time.get_ticks_msec()+30000
		while (not view.complete or view.loading) and Time.get_ticks_msec()<deadline: await create_timer(.1).timeout
		assert(view.panel.visible and view.complete and not view.loading and view.message.text.is_empty(), "Read completed: "+page+" "+view.message.text)
		evidence[page] = {"residents":view.people.size(),"details":view.details.size(),"orders":view.orders.size(),"epoch":view.epoch}
		for size in [Vector2i(1920,1080),Vector2i(960,640)]:
			root.size=size
			for i in 10: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output+"-"+page.to_snake_case()+"-"+str(size.x)+".png")
		view.close_panel()
		assert(not scene._interaction.construction_active)
	# Returning to a completed domain uses its cache immediately, before any new poll.
	view.set_info_page("Residents")
	view.open_panel()
	assert(view.complete and view.people.size()==int(evidence["Residents"].residents), "Cached domain is immediate")
	view.set_info_page("Work orders")
	assert(view.complete and view.orders.size()==int(evidence["Work orders"].orders), "Switch never consumes another domain's rows")
	view.close_panel()
	var file := FileAccess.open(output+"-data.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence,"  "))
	print("READ_ONLY_INFO_LIVE_PASS"); quit()
