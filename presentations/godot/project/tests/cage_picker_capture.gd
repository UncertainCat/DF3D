extends SceneTree
const Owner=preload("res://scripts/furniture_panel.gd")
func integers(value):
	if value is float:return int(value)
	if value is Dictionary:
		for key in value:value[key]=integers(value[key])
	elif value is Array:
		for index in value.size():value[index]=integers(value[index])
	return value
func _initialize() -> void:call_deferred("run")
func run() -> void:
	Engine.max_fps=30
	root.size=Vector2i(1200,800)
	var directory:=OS.get_environment("DF3D_CAGE_CAPTURE")
	if directory.is_empty():quit(77);return
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var data: Dictionary=integers(JSON.parse_string(FileAccess.get_file_as_string(directory+"/cage-wire-result.json")))
	var state=preload("res://scripts/cage_picker_state.gd").new()
	state.building_id=int(data.initial.building_id);state.area={"id":state.building_id}
	state.snapshot=data.initial;state.rows=data.initial.rows;state.phase=state.Phase.Ready
	var view=preload("res://scripts/area_candidates_view.gd").new();view.cage_layout=true
	root.add_child(view);view.configure(world,state);view.layout(Vector2(1200,800))
	view.add_theme_stylebox_override("panel",view.panel_style())
	for slot in view.portrait_slots:
		slot.view.texture=world.candidate_icon(slot.recipe);slot.loaded=true
	for i in 6:
		view.layout(Vector2(1200,800));await process_frame;await RenderingServer.frame_post_draw
	var rendered:=root.get_texture().get_image()
	var error:=rendered.save_png(directory+"/cage-picker-view.png")
	var native:=Image.load_from_file(directory+"/cage-assignment-open.png")
	var bounds:=Rect2i(32,52,384,708)
	var actual:=rendered.get_region(bounds);actual.convert(Image.FORMAT_RGB8)
	var expected:=native.get_region(bounds);expected.convert(Image.FORMAT_RGB8)
	if actual.get_data()!=expected.get_data():push_error("Native cage picker pixels differ");error=1
	print("CAGE_PICKER_CAPTURE ",error)
	view.queue_free();world.queue_free();await process_frame;quit(error)
