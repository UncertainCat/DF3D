extends "res://tests/cage_picker_capture.gd"
func run() -> void:
	Engine.max_fps=30
	root.size=Vector2i(1200,800)
	var directory:=OS.get_environment("DF3D_CHAIN_CAPTURE")
	if directory.is_empty():quit(77);return
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var data: Dictionary=integers(JSON.parse_string(FileAccess.get_file_as_string(directory+"/chain-wire-result.json")))
	var state=preload("res://scripts/cage_picker_state.gd").new()
	state.building_id=int(data.initial.building_id);state.area={"id":state.building_id}
	state.snapshot=data.initial;state.rows=data.initial.rows;state.phase=state.Phase.Ready
	var view=preload("res://scripts/area_candidates_view.gd").new();view.cage_layout=true;view.chain_layout=true
	root.add_child(view);view.configure(world,state);view.layout(Vector2(1200,800))
	view.add_theme_stylebox_override("panel",view.panel_style())
	for slot in view.portrait_slots:
		slot.view.texture=world.candidate_icon(slot.recipe);slot.loaded=true
	for i in 6:
		view.layout(Vector2(1200,800));await process_frame;await RenderingServer.frame_post_draw
	var rendered:=root.get_texture().get_image()
	var error:=rendered.save_png(directory+"/chain-picker-view.png")
	var native:=Image.load_from_file(directory+"/chain-assignment-open.png")
	var bounds:=Rect2i(32,52,384,708)
	var actual:=rendered.get_region(bounds);actual.convert(Image.FORMAT_RGB8)
	var expected:=native.get_region(bounds);expected.convert(Image.FORMAT_RGB8)
	if actual.get_data()!=expected.get_data():push_error("Native chain picker pixels differ");error=1
	print("CHAIN_PICKER_CAPTURE ",error)
	var header=preload("res://scripts/building_header_state.gd").new()
	header.snapshot=data.header;header.building_id=header.snapshot.id;header.phase=header.Phase.Ready
	var occupants=preload("res://scripts/cage_picker_state.gd").new();occupants.parent_body=true
	occupants.snapshot=data.body;occupants.rows=data.body.occupants
	occupants.building_id=header.building_id;occupants.phase=occupants.Phase.Ready
	var panel=preload("res://scripts/cage_sheet_view.gd").new();root.add_child(panel)
	panel.configure(world,header);panel.configure_occupants(occupants);panel.layout(Vector2(1200,800))
	for i in 6:await process_frame;await RenderingServer.frame_post_draw
	rendered=root.get_texture().get_image();rendered.save_png(directory+"/chain-body-view.png")
	native=Image.load_from_file(directory+"/chain-assignment-selected.png")
	bounds=Rect2i(432,136,456,364)
	actual=rendered.get_region(bounds);actual.convert(Image.FORMAT_RGB8)
	expected=native.get_region(bounds);expected.convert(Image.FORMAT_RGB8)
	if actual.get_data()!=expected.get_data():push_error("Native chain body pixels differ");error=1
	print("CHAIN_BODY_CAPTURE ",error)
	panel.queue_free()
	view.queue_free();world.queue_free();await process_frame;quit(error)
