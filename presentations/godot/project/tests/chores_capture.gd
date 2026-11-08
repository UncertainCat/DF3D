extends SceneTree
func _initialize() -> void:call_deferred("run")
func integers(value):
	if value is float:return int(value)
	if value is Array:
		for index in value.size():value[index]=integers(value[index])
	elif value is Dictionary:
		for key in value:value[key]=integers(value[key])
	return value
func run() -> void:
	Engine.max_fps=30
	if DisplayServer.get_name()=="headless":quit(77);return
	var reference: Dictionary=integers(JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/production/native_standing_orders.json"))).chores_reference
	var directory:=ProjectSettings.globalize_path("res://../../../"+str(reference.appearance_reference.capture))
	if directory.is_empty() or not FileAccess.file_exists(directory+"/chores-rows.json"):push_error("Native Chores row capture required");quit(1);return
	root.size=Vector2i(1200,800)
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var state=preload("res://scripts/chores_state.gd").new();state.phase=state.Phase.Ready
	var native: Dictionary=integers(JSON.parse_string(FileAccess.get_file_as_string(directory+"/standing-orders-native.json"))).chores
	state.snapshot={"enabled":native.enabled,"children":PackedInt32Array(native.children),"exempted":PackedInt32Array(native.exempted),"labors":native.labors}
	state.children=reference.captions_reference.captions.children
	state.labors=reference.captions_reference.captions.labors
	var view=preload("res://scripts/chores_view.gd").new();root.add_child(view)
	view.configure_chores(world,state);view.layout(Vector2(1200,800));view.ticks_override=0
	view.display_rows(integers(JSON.parse_string(FileAccess.get_file_as_string(directory+"/chores-rows.json"))))
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/chores.png"))
	view.queue_free();world.queue_free();await process_frame
	print("CHORES_CAPTURE_PASS");quit(0)

