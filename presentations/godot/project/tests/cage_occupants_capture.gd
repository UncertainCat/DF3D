extends "res://tests/cage_picker_capture.gd"
func run() -> void:
	Engine.max_fps=30;root.size=Vector2i(1200,800)
	var directory:=OS.get_environment("DF3D_CAGE_CAPTURE")
	if directory.is_empty():quit(77);return
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var data: Dictionary=integers(JSON.parse_string(FileAccess.get_file_as_string(directory+"/cage-wire-result.json")))
	var state=preload("res://scripts/building_header_state.gd").new()
	state.snapshot=data.parent;state.building_id=state.snapshot.id;state.phase=state.Phase.Ready
	var occupants=preload("res://scripts/cage_picker_state.gd").new();occupants.parent_body=true
	occupants.snapshot=data.assigned_occupants;occupants.rows=occupants.snapshot.occupants
	occupants.building_id=state.building_id;occupants.phase=occupants.Phase.Ready
	var view=preload("res://scripts/cage_sheet_view.gd").new();root.add_child(view)
	view.configure(world,state);view.configure_occupants(occupants);view.layout(Vector2(1200,800))
	for i in 6:await process_frame;await RenderingServer.frame_post_draw
	var actual:=root.get_texture().get_image();actual.save_png(directory+"/cage-occupants-view.png")
	var expected:=Image.load_from_file(directory+"/cage-body-assigned-unit.png")
	var bounds:=Rect2i(432,136,456,252)
	actual=actual.get_region(bounds);actual.convert(Image.FORMAT_RGB8)
	expected=expected.get_region(bounds);expected.convert(Image.FORMAT_RGB8)
	var error:=0
	if actual.get_data()!=expected.get_data():push_error("Cage occupant pixels differ");error=1
	print("CAGE_OCCUPANTS_CAPTURE ",error)
	view.queue_free();world.queue_free();await process_frame;quit(error)
