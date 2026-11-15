extends "res://tests/chest_scene_live.gd"
func expected_filename() -> String:return "lever-native.json"
func result_filename() -> String:return "lever-warning-wire-result.json"
func lever_ready() -> bool:
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		world.poll();actions.poll(0.01);await process_frame
		if owner.state.phase==owner.state.Phase.Ready and owner.contents.phase==owner.contents.Phase.Ready and owner.tasks.phase==owner.tasks.Phase.Ready and owner.lever.state.phase==owner.lever.state.Phase.Ready:return true
	return check(false,"No-stock lever did not become ready")
func exercise(_expected: Dictionary) -> void:
	owner=scene._ui.controller("lever");owner.open_target(55)
	if not await lever_ready():return
	check(owner.lever.state.snapshot.target_mechanism==-1,"Warning fixture unexpectedly has two mechanisms")
	for attempt in 2:
		await pointer(Vector2(744,154))
		if not await lever_ready():return
		check(owner.panel.tasks.need_mechanisms and owner.panel.visible and not owner.lever.view.visible and not owner.modal_input,"Missing mechanisms did not leave usable warning panel")
		check(owner.tasks.jobs().is_empty(),"Unavailable Link created a job")
		var motion:=InputEventMouseMotion.new();motion.position=Vector2(300,400);root.push_input(motion,true)
		await process_frame;await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
		var native:=Image.load_from_file(directory+"/lever-link-open.png");native.convert(Image.FORMAT_RGB8)
		var rect:=Rect2i(416,52,488,708);var crop:=image.get_region(rect)
		crop.save_png(directory+"/lever-warning-"+str(attempt)+"-viewer.png")
		check(crop.get_data()==native.get_region(rect).get_data(),"Native warning panel pixels differ")
	key(KEY_ESCAPE);await drain();await process_frame
	check(scene._ui.host.active==null and not owner.panel.visible,"Warning Escape retained owner")
	owner.open_target(55)
	if not await lever_ready():return
	check(not owner.panel.tasks.need_mechanisms,"Reopen retained old warning")
	await pointer(Vector2(744,154));owner.close_panel();await drain();await process_frame
	check(scene._ui.host.active==null and not owner.panel.visible and owner.lever.state.building_id==-1,"Late no-stock reply revived owner")
	exercised=true
