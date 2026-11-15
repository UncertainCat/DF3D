extends "res://tests/lever_wire_live.gd"
func inspect_prompt(snapshot: Dictionary,_expected: Dictionary) -> void:
	if not check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Lever prompt assets unavailable"):return
	root.size=Vector2i(1200,800)
	var service=preload("res://scripts/semantic_action_service.gd").new();root.add_child(service);service.configure(world,true)
	var claim_deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<claim_deadline:
		world.poll();await process_frame
		if not service._needs_claim and service._active==0 and service._epoch>0:break
	var owner=preload("res://scripts/lever_link_owner.gd").new();root.add_child(owner);owner.configure(world,service,root)
	owner.layout(Vector2(32,52));owner.open(55,"Main Water Control")
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline and owner.state.phase==owner.state.Phase.Reading:
		world.poll();await process_frame
	if not check(owner.state.phase==owner.state.Phase.Ready,"Lever owner initial read failed"):
		owner.queue_free();service.queue_free();await process_frame;return
	owner.begin_link()
	var view=owner.view
	deadline=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		world.poll();view.refresh()
		if view.visible and view.ready_art():break
		await create_timer(0.02).timeout
	check(view.ready_art(),"Lever mechanism textures did not arrive")
	check(owner.state.snapshot.get("source_mechanism")==snapshot.source_mechanism and owner.state.snapshot.get("target_mechanism")==snapshot.target_mechanism,"Owner changed native mechanism selection")
	await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
	var crop:=Rect2i(32,52,456,156);var actual:=image.get_region(crop)
	actual.save_png(directory+"/lever-prompt-viewer.png")
	var native:=Image.load_from_file(directory+"/lever-link-reopened.png");native.convert(Image.FORMAT_RGB8)
	check(actual.get_data()==native.get_region(crop).get_data(),"Native lever prompt pixels differ")
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=Vector2(200,142);root.push_input(event,true)
	await process_frame
	check(owner.state.phase==owner.state.Phase.Ready and not view.visible,"Mechanism row click did not cancel Link")
	owner.queue_free();service.queue_free();await process_frame
