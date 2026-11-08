extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	Engine.max_fps=30
	if DisplayServer.get_name()=="headless":quit(77);return
	root.size=Vector2i(1200,800)
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/production/native_standing_orders.json")).hunter_ammunition_reference
	var state=preload("res://scripts/hunter_ammunition_state.gd").new();state.phase=state.Phase.Ready
	state.specs=reference.before.specs.duplicate(true)
	for row: Dictionary in reference.caption_provider.specs:state.rules.append({"caption":row.caption,"quantity":int(row.assigned_quantity),"items":row.items.duplicate(true)})
	for caption: String in reference.caption_provider.types:state.types.append({"caption":caption})
	var view=preload("res://scripts/hunter_ammunition_view.gd").new();root.add_child(view)
	view.configure_ammunition(world,state);view.layout(Vector2(1200,800))
	for mode in [state.Mode.Main,state.Mode.Types]:
		state.mode=mode;state.changed.emit();await process_frame;await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/hunter-ammunition-"+str(mode)+".png"))
	view.queue_free();world.queue_free();await process_frame
	print("HUNTER_AMMUNITION_CAPTURE_PASS");quit(0)
