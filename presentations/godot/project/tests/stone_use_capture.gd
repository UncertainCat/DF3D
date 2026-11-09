extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	Engine.max_fps=30
	if DisplayServer.get_name()=="headless":quit(77);return
	root.size=Vector2i(1200,800)
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../../../fixtures/production/native_stone_use.json"))
	var state=preload("res://scripts/stone_use_state.gd").new();state.phase=state.Phase.Ready
	for row in fixture.display_rows:
		row.category=int(row.category);row.index=int(row.index);state.rows.append(row)
	var world:=Df3dWorld.new();root.add_child(world)
	if not world.load_assets(OS.get_environment("DF3D_DF_PATH")):quit(1);return
	var view=preload("res://scripts/stone_use_view.gd").new();root.add_child(view)
	view.configure_stone_use(world,state);view.layout(Vector2(1200,800))
	for category in 2:
		state.select_category(category)
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../../../build/stone-use-category-%d.png"%category))
	view.queue_free();world.queue_free();await process_frame
	print("STONE_USE_CAPTURE_PASS");quit(0)
