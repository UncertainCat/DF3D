extends "res://tests/cage_picker_capture.gd"
func run() -> void:
	Engine.max_fps=30;root.size=Vector2i(1200,800)
	var directory:=OS.get_environment("DF3D_CAGE_CAPTURE")
	if directory.is_empty():quit(77);return
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var data: Dictionary=integers(JSON.parse_string(FileAccess.get_file_as_string(directory+"/cage-glass-wire-result.json")))
	var state=preload("res://scripts/building_header_state.gd").new()
	state.snapshot=data.receipts[0];state.building_id=state.snapshot.id;state.phase=state.Phase.Ready
	var view=preload("res://scripts/cage_sheet_view.gd").new();root.add_child(view);view.configure(world,state);view.layout(Vector2(1200,800))
	var error:=0
	for snapshot in data.receipts:
		state.snapshot=snapshot;view.refresh()
		for i in 6:await process_frame;await RenderingServer.frame_post_draw
		var label: String="aquarium" if snapshot.cage.aquarium else "terrarium"
		var actual:=root.get_texture().get_image();actual.save_png(directory+"/cage-glass-view-"+label+".png")
		var expected:=Image.load_from_file(directory+"/cage-glass-"+label+".png")
		var bounds:=Rect2i(432,388,472,36)
		actual=actual.get_region(bounds);actual.convert(Image.FORMAT_RGB8)
		expected=expected.get_region(bounds);expected.convert(Image.FORMAT_RGB8)
		if actual.get_data()!=expected.get_data():push_error("Cage glass controls differ: "+label);error=1
	print("CAGE_GLASS_CAPTURE ",error)
	view.queue_free();world.queue_free();await process_frame;quit(error)
