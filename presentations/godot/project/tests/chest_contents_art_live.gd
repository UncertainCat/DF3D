extends "res://tests/chest_contents_live.gd"
func inspect_render(page: Dictionary) -> void:
	if not check(DisplayServer.get_name()!="headless","Chest contents requires renderer"):return
	if not check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Chest contents assets unavailable"):return
	root.size=Vector2i(472,216)
	var background:=ColorRect.new();root.add_child(background);background.size=Vector2(472,216)
	background.color=world.ui_texture("HOVER_RECTANGLE").get_image().get_pixel(8,12)
	var model=Contents.new();model.snapshot=page.duplicate(true);model.phase=Contents.Phase.Ready
	var view=preload("res://scripts/farm_contents_view.gd").new();root.add_child(view);view.configure(world,model)
	await process_frame;await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8);image.save_png(directory+"/chest-contents-viewer.png")
	var native:=Image.load_from_file(directory+"/farm-item-carrier-container-building.png");native.convert(Image.FORMAT_RGB8)
	check(native.get_region(Rect2i(424,508,472,216)).get_data()==image.get_data(),"Native chest contents pixels differ")
	var calls: Array=[];view.view_requested.connect(func(id):calls.append(id))
	for index in page.rows.size():
		for pressed in [true,false]:
			var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=view.control_rect(index,1).get_center();root.push_input(event,true)
	check(calls==page.rows.map(func(row):return row.id),"Contents View identities differ")
	view.queue_free();background.queue_free();await process_frame;model.dispose()
