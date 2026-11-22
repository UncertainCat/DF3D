extends "res://tests/trade_goods_art_wire_live.gd"
func run() -> void:
	Engine.max_fps=30;directory=OS.get_environment("DF3D_DISPLAY_CAPTURE_DIRECTORY")
	if directory.is_empty():quit(77);return
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Display assets missing"):quit(1);return
	root.size=Vector2i(1200,800)
	var recorded: Dictionary=integers(JSON.parse_string(FileAccess.get_file_as_string(directory+"/display-wire-result.json"))).parent_capture
	var model=preload("res://scripts/display_state.gd").new()
	model.building_id=recorded.display.building_id;model.body=recorded.display.body;model.phase=model.Phase.Ready
	for row in recorded.display.items:model.items[row.id]=row
	var header=preload("res://scripts/building_header_state.gd").new();header.building_id=model.building_id;header.snapshot=recorded.header;header.phase=header.Phase.Ready
	var contents_model=preload("res://scripts/building_contents_state.gd").new();contents_model.building_id=model.building_id;contents_model.snapshot=recorded.contents;contents_model.phase=contents_model.Phase.Ready
	var view=preload("res://scripts/display_sheet_view.gd").new();root.add_child(view)
	view.configure(world,header,null,contents_model);view.configure_display(model);view.layout(Vector2(1200,800))
	for frame in 8:world.poll();await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		var rendered:=root.get_texture().get_image();rendered.convert(Image.FORMAT_RGB8);rendered.save_png(directory+"/display-parent-view.png")
		var native:=Image.load_from_file(directory+"/display-selected-parent.png");native.convert(Image.FORMAT_RGB8)
		# The selection owner's side tabs overlay the final eight pixels of the
		# sheet frame. This isolated view does not own that navigation component.
		var rect:=Rect2i(416,52,480,708)
		check(rendered.get_region(rect).get_data()==native.get_region(rect).get_data(),"Native Display parent pixels differ")
	var calls: Array=[];view.display_requested.connect(func():calls.append(true))
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;event.position=view.assign_rect().get_center();view._gui_input(event)
	check(calls==[true],"Display parent assignment button failed")
	view.queue_free();await process_frame;model.dispose();header.dispose();contents_model.dispose();world.queue_free();await process_frame
	if not failed:print("DISPLAY_PARENT_VIEW_PASS")
	quit(1 if failed else 0)
