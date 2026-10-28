extends "res://tests/farm_body_capture.gd"
func wheel(point: Vector2) -> void:
	var event:=InputEventMouseButton.new();event.position=point;event.global_position=point
	event.button_index=MOUSE_BUTTON_WHEEL_DOWN;event.pressed=true;root.push_input(event,true)
	event.pressed=false;root.push_input(event,true)
func drag(point: Vector2, destination: Vector2) -> void:
	var start:=InputEventMouseMotion.new();start.position=point;start.global_position=point;root.push_input(start,true)
	var event:=InputEventMouseButton.new();event.position=point;event.global_position=point
	event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;root.push_input(event,true)
	var motion:=InputEventMouseMotion.new();motion.position=destination;motion.global_position=destination
	motion.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(motion,true)
	event.position=destination;event.global_position=destination;event.pressed=false;root.push_input(event,true)
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	root.size=Vector2i(480,320)
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):fail("Farm assets unavailable");return
	var background:=ColorRect.new();root.add_child(background)
	background.color=world.ui_texture("HOVER_RECTANGLE").get_image().get_pixel(8,12);background.size=Vector2(480,320)
	var model:=Model.new()
	var view=preload("res://scripts/farm_body_view.gd").new();root.add_child(view);view.configure(world,model)
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/building_management/native_farm.json"))
	var reference: Dictionary=fixture.scroll_reference
	model.snapshot=reference.snapshot.duplicate(true);model.changed.emit()
	for sample in reference.cases:
		view.scrollbar.move_to(int(sample.first));view.scrollbar.hover_cell=-1
		await process_frame;await RenderingServer.frame_post_draw
		var crop:=root.get_texture().get_image().get_region(Rect2i(0,0,456,300));crop.convert(Image.FORMAT_RGB8)
		crop.save_png(ProjectSettings.globalize_path("res://../../../build/"+str(sample.name)+"-viewer.png"))
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(crop.get_data())
		if hash.finish().hex_encode()!=sample.rgb_sha256:fail("Farm scroll pixels differ: "+str(sample.name));return
	view.scrollbar.move_to(0)
	for probe in [[Vector2(448,246),1],[Vector2(448,6),0],[Vector2(448,204),7],[Vector2(448,30),0]]:
		click(probe[0])
		if view.first!=probe[1]:fail("Farm scrollbar pointer step differs");return
	wheel(Vector2(200,24));wheel(Vector2(448,54))
	if view.first!=0:fail("Farm unexpectedly accepts wheel");return
	for probe in [[184,0],[208,0],[220,2],[280,12],[400,32],[436,38],[460,38]]:
		view.scrollbar.move_to(0);drag(Vector2(448,30),Vector2(448,probe[0]-196))
		if view.first!=probe[1] or view.scrollbar.dragging:fail("Farm drag differs at "+str(probe[0]));return
	await process_frame
	click(Vector2(424,18))
	if model.calls!=[["crop",int(view.rows[38].id)]]:fail("Scrolled checkbox used wrong crop identity: "+str(model.calls)+" expected "+str(view.rows[38].id));return
	model.phase=Model.Phase.Applying;model.changed.emit();click(Vector2(448,6))
	if view.first!=38:fail("Pending farm accepted scroll input");return
	model.phase=Model.Phase.Ready;model.season=0;model.changed.emit()
	if view.first!=0:fail("Season change retained farm scroll");return
	view.input_allowed=func():return false;click(Vector2(448,246))
	if view.first!=0:fail("Farm scroll bypassed owner gate");return
	view.queue_free();world.queue_free();background.queue_free();await process_frame
	print("FARM_SCROLL_CAPTURE_PASS");quit(0)
