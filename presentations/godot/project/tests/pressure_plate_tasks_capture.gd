extends "res://tests/farm_body_capture.gd"
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(77);return
	root.size=Vector2i(1200,800)
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):fail("Pressure plate assets unavailable");return
	var background:=ColorRect.new();root.add_child(background)
	background.color=world.ui_texture("HOVER_RECTANGLE").get_image().get_pixel(8,12);background.size=Vector2(1200,800)
	var state=preload("res://scripts/workshop_tasks_state.gd").new()
	state.building_id=61;state.phase=state.Phase.Ready
	var view=preload("res://scripts/pressure_plate_tasks_view.gd").new();root.add_child(view)
	view.configure(world,state);view.position=Vector2(432,106)
	var calls: Array=[]
	view.link_requested.connect(func():calls.append("link"))
	view.pull_requested.connect(func():calls.append("pull"))
	var directory:=OS.get_environment("DF3D_PLATE_REFERENCE")
	for label in ["initial","link","linked-job"]:
		state.snapshot={"jobs":[],"recipes":[]}
		view.need_mechanisms=label=="link"
		if label=="linked-job":state.snapshot.jobs.append({"id":0,"name":"Link a building to trigger","repeat":false,"priority":false,"suspended":false,"editable":true,"can_move_up":false})
		state.changed.emit()
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
		var native:=Image.load_from_file(directory+"/pressure-plate-"+label+".png");native.convert(Image.FORMAT_RGB8)
		var rect:=Rect2i(432,130,456,114)
		image.get_region(rect).save_png(directory+"/pressure-plate-tasks-"+label+"-viewer.png")
		if image.get_region(rect).get_data()!=native.get_region(rect).get_data():fail("Pressure plate task pixels differ: "+label);return
	click(view.position+view.lever_button(0).get_center())
	click(view.position+view.lever_button(1).get_center())
	if calls!=["link"]:fail("Pressure plate exposed Pull or failed Link");return
	view.queue_free();world.queue_free();await process_frame
	print("PRESSURE_PLATE_TASKS_CAPTURE_PASS");quit(0)
