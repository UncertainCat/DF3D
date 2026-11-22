extends "res://tests/trade_goods_art_wire_live.gd"
func run() -> void:
	Engine.max_fps=30;directory=OS.get_environment("DF3D_DISPLAY_CAPTURE_DIRECTORY")
	if directory.is_empty():quit(77);return
	world=Df3dWorld.new();root.add_child(world)
	if not check(world.load_assets(OS.get_environment("DF3D_DF_PATH")),"Display assets missing"):quit(1);return
	root.size=Vector2i(1200,800)
	var recorded: Dictionary=integers(JSON.parse_string(FileAccess.get_file_as_string(directory+"/display-wire-result.json"))).full_page
	var model=preload("res://scripts/display_state.gd").new()
	model.building_id=recorded.building_id;model.category=recorded.category;model.categories=recorded.categories;model.groups=recorded.groups;model.phase=model.Phase.Ready
	for row in recorded.items:model.items[row.id]=row
	var view=preload("res://scripts/display_picker_view.gd").new();root.add_child(view);view.configure_display(world,model);view.layout(Vector2(1200,800))
	for frame in 8:world.poll();view.refresh();await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		var rendered:=root.get_texture().get_image();rendered.convert(Image.FORMAT_RGB8);rendered.save_png(directory+"/display-picker-view.png")
		var native:=Image.load_from_file(directory+"/display-amulets.png");native.convert(Image.FORMAT_RGB8)
		var rect:=Rect2i(32,52,944,708)
		check(rendered.get_region(rect).get_data()==native.get_region(rect).get_data(),"Native Display picker pixels differ")
	# Native search/clear leaves filter typing active while selecting an item.
	view.search.ticks_override=0;view.search.grab_focus()
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;event.position=view.item_canvas.position+view.checkbox_rect(1).get_center()
	view._gui_input(event)
	check(model.selected.has(recorded.groups[0].item_ids[0]),"Display checkbox did not toggle local draft")
	if DisplayServer.get_name()!="headless":
		await process_frame;await RenderingServer.frame_post_draw
		var rendered:=root.get_texture().get_image();rendered.convert(Image.FORMAT_RGB8);rendered.save_png(directory+"/display-picker-selected-view.png")
		var native:=Image.load_from_file(directory+"/display-selected-draft.png");native.convert(Image.FORMAT_RGB8)
		var rect:=Rect2i(32,52,944,708)
		check(rendered.get_region(rect).get_data()==native.get_region(rect).get_data(),"Native selected Display picker pixels differ")
	view._gui_input(event);check(model.selected.is_empty(),"Display checkbox failed to clear draft")
	var before_height: int=view.total_rows
	for point in [Vector2(140,18),Vector2(140,54)]:
		event.position=view.item_canvas.position+point;view._gui_input(event)
	check(model.selected.is_empty() and view.total_rows==before_height,"Display captions changed selection or expansion")
	view.queue_free();await process_frame;model.dispose();world.queue_free();await process_frame
	if not failed:print("DISPLAY_PICKER_VIEW_PASS")
	quit(1 if failed else 0)

